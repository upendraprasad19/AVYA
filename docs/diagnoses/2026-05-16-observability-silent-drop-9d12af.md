---
bug_id: 9d12af
date: 2026-05-16
batch: APK Test #16.1 / Theme D
status: in_progress
symptom: |
  Hidden observability bug — silent for an unknown number of days.

  `supabase/functions/log-client-error/index.ts` enforced a per-user
  rate limit of 100 events/24h. Past the threshold, the function
  returned 200 `{ok: true, rate_limited: true}` but DID NOT INSERT.
  The Flutter client (`lib/core/services/error_telemetry.dart`)
  ignored the `rate_limited` flag entirely and kept POSTing for every
  subsequent event.

  On 2026-05-15, the founder's count hit 100 by 04:10 UTC from a 42P10
  storm (closes-diagnose 76c8f4). For the rest of that day, hundreds
  of `log-client-error` 200 responses were logged BUT `client_errors`
  received ZERO new rows. We were blind to all +25 production failures
  in the same window — including any that would have surfaced new
  bug classes from Test #15.5.

  No user-visible symptom (telemetry is fire-and-forget) — but every
  observation-driven batch (Test #11.1 onward) depends on
  `client_errors` row counts to find production bugs. A silent
  observability sink is a meta-bug that hides every other bug.
concept: client_errors_telemetry_pipeline
sot_registry_entry: telemetry_op_types
writers:
  - { file: supabase/functions/log-client-error/index.ts, method_or_widget: rate-limit branch, line: 142 }
  - { file: lib/core/services/error_telemetry.dart, method_or_widget: logEvent + recordNonFatal, line: 84 }
readers:
  - { file: docs/audit/2026-05-12, method_or_widget: 24h client_errors scan, line: 1 }
  - { file: scripts/check_generic_error_telemetry.dart, method_or_widget: pre-commit gate, line: 24 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: client_errors
cloud_columns:
  - user_id
  - error_code
  - error_message
  - op_type
  - retry_count
  - client_version
  - platform
  - created_at
contract_test_path: test/safety/error_telemetry_rate_limit_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success:
    - guarded_box_disagreement
    - hive_session_owner_mismatch
  failure:
    - sync_skipped_null_natural_key
    - edge_function_cold_start_retry
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "return ok({ ok: true, rate_limited: true })", absent: false }
  - { pattern: "rateLimitedUntil", absent: false }
proposed_fix: |
  1. Bump server `DAILY_RATE_LIMIT` from 100 → 2000. Founder's worst
     pre-storm day was 47 unique events; 2000 leaves ~40× safety.
  2. Add server-side `HIGH_PRIORITY_OP_TYPES` allowlist — crash classes,
     auth failures, SQL state codes (42P10, 23502, 23505, 23503,
     permission_denied), discipline-gate violations, and bug-class
     triggers. HIGH op_types ALWAYS insert, bypassing the budget.
  3. When the LOW-priority budget is hit, return a distinguishable
     response body `{ok: true, rate_limited: true, next_window_at: <iso>,
     priority_lane: "low"}`. `next_window_at` is computed as 24h after
     the OLDEST event currently in the user's window (tighter bound
     than `now + 24h`).
  4. Client `ErrorTelemetry.logEvent` + `recordNonFatal` honor the
     reply: parse `next_window_at` into `rateLimitedUntil` (UTC).
     Subsequent LOW-priority calls within the cooldown window
     short-circuit before the network round-trip. HIGH-priority calls
     ignore the cooldown and ALWAYS POST (server lane handles them).
  5. Client `highPriorityOpTypes` list mirrors the server set 1:1.
     Drift is pinned by twin tests (Deno + Dart).

  Risk: false-positive HIGH classification spams the table from a
  runaway client. Mitigated by (a) keeping the list curated + small
  (sanity-capped at 30 entries by a Deno test), (b) the Deno test
  suite asserts the LOW classification of the known chatty op_types
  (`sync_skipped_null_natural_key`, `edge_function_cold_start_retry`,
  `restore_*`, `subscription_refresh_success`).

  Deploy: source changes only — main thread will deploy
  `log-client-error` after Theme D review per Agent D's brief.
regression_test_planned:
  - test/safety/error_telemetry_rate_limit_test.dart
  - supabase/functions/log-client-error/index_test.ts
---

# Bug 9d12af — observability silent-drop past per-user rate limit

## Symptom

Telemetry pipeline silently dropped every `log-client-error` call past
100 events/user/24h. On 2026-05-15 the founder hit the limit by
04:10 UTC from a 42P10 storm, then produced +25 production failures
the rest of the day. ZERO new rows in `client_errors` for those +25
events.

We've been blind to an unknown number of similar windows on prior days
— the function has had this drop path since some unrecorded commit.
Every observation-driven batch since Test #11.1 has implicitly assumed
`client_errors` is a complete record; on any "noisy day" that
assumption was wrong.

## User-visible impact

None directly. The meta-impact is severe: every bug class we found
through `client_errors` audits (42P10, 9f4ab2, 7c4e1a, c01d57, etc.)
could have a silent counterpart that surfaced AFTER the 100-event
threshold and was thrown away.

## Root cause

`supabase/functions/log-client-error/index.ts:142-147` (pre-fix):

```ts
if ((count ?? 0) >= DAILY_RATE_LIMIT) {
  return ok({ ok: true, rate_limited: true });
}
```

`DAILY_RATE_LIMIT = 100` was set when client error telemetry was new
and we were worried about a runaway sync loop. The number was never
calibrated against real per-user noise. Compounding:

- The client (`lib/core/services/error_telemetry.dart`) didn't inspect
  the response body — `await callFunction(...)` succeeded with status
  200, so the inner try block completed cleanly. There was no
  cooldown, no log, no metric — the dropped rows simply vanished.
- No HIGH-priority bypass: a P0 crash event hit the same 100-event
  budget as `sync_skipped_null_natural_key` heartbeats. The budget
  did not distinguish signal from noise.
- The "quietly succeed" comment in the original code (lines 143-145)
  is technically defensible for noise containment but operationally
  catastrophic for a young product with daily observation cycles.

## Reproducer

Pre-fix:
1. From a single authenticated user, POST 100 `log-client-error`
   events within 24h.
2. POST one more event with any op_type.
3. Observe: response 200 `{ok: true, rate_limited: true}` AND no new
   row in `client_errors`.

Post-fix:
1. POST 2000 LOW-priority events. Observe count = 2000 in
   `client_errors`.
2. POST one LOW event past 2000. Observe 200 `{ok: true,
   rate_limited: true, next_window_at: <iso>, priority_lane: "low"}`
   AND no row inserted.
3. From the same user, POST an event with `op_type: "42P10"`.
   Observe: row IS inserted (HIGH-priority lane bypasses budget).
4. From the Flutter client, observe `ErrorTelemetry.rateLimitedUntil`
   is set to `next_window_at`, and subsequent LOW-priority
   `logEvent` calls short-circuit before the network round-trip.

## Fix applied

Server (`supabase/functions/log-client-error/index.ts`):

- `DAILY_RATE_LIMIT` 100 → 2000.
- New `HIGH_PRIORITY_OP_TYPES` allowlist (~20 entries, sanity-capped
  at 30 by `index_test.ts`). Markers ending in `_` are prefix; bare
  values are exact equality.
- New `isHighPriority(opType)` helper.
- Rate-limit branch only runs for LOW op_types. HIGH op_types skip
  the count query AND the budget gate — always insert.
- New `nextWindowAt` helper computes 24h after the oldest in-window
  event (returns null if no rows).
- Rate-limited response: `{ok: true, rate_limited: true,
  next_window_at: <iso>, priority_lane: "low"}`.
- Success response: `{ok: true, priority_lane: "high" | "low"}` —
  ops + tests can sanity-check classification without table scans.
- `DAILY_RATE_LIMIT`, `HIGH_PRIORITY_OP_TYPES`, `isHighPriority`,
  `MAX_OP_TYPE_CHARS` exported for Deno tests.

Client (`lib/core/services/error_telemetry.dart`):

- New static `rateLimitedUntil` (UTC DateTime?) — null when no
  cooldown active.
- New `highPriorityOpTypes` list mirroring the server allowlist 1:1.
  Pinned by `test/safety/error_telemetry_rate_limit_test.dart`.
- New `isHighPriorityOpType(opType)` helper.
- `_isCooldownActive()` + `_maybeHonorRateLimit(data)` private
  helpers manage the cooldown state machine.
- Both `logEvent` and `recordNonFatal`:
  - Short-circuit before the network call when cooldown active AND
    op_type is LOW.
  - Parse `next_window_at` from the response body and set
    `rateLimitedUntil` when `rate_limited: true`.
  - HIGH op_types always attempt the POST (server lane inserts them).
- Crashlytics leg in `recordNonFatal` always runs — separate sink,
  separate budget.
- `@visibleForTesting` seams: `rateLimitedUntil`,
  `forceTreatAllAsLowPriorityForTest`, `highPriorityOpTypes`,
  `isHighPriorityOpType`.

Tests:

- `test/safety/error_telemetry_rate_limit_test.dart` — 24 Dart cases
  covering HIGH classification (10), LOW classification (5), cooldown
  state machine (4), drift guards (5).
- `supabase/functions/log-client-error/index_test.ts` — 10 Deno cases
  covering DAILY_RATE_LIMIT, classifier semantics, drift guards.

## Codex agent stanza

- agent_id: claude-opus-4-7-test-16-1-agent-d
- preamble_version: docs/agent_brief_preamble.md@v3
- writer_file_line: supabase/functions/log-client-error/index.ts:108-205 (rate-limit branch + priority lane), lib/core/services/error_telemetry.dart:48-119 (cooldown state machine + classifier)
- reader_file_line: docs/audit/* (all post-Test-#11 audits assumed full client_errors fidelity), `/build-apk` Gate 16 violation surfacing
- evidence: founder's 2026-05-15 day hit 100 events by 04:10 UTC (closes-diagnose 76c8f4); subsequent hundreds of 200 `{rate_limited: true}` responses with ZERO `client_errors` inserts; +25 production failures invisible
- fix_locality: cross-tier (Edge Function + Dart client) — both sides need to agree on the priority allowlist; drift caught by twin Deno + Dart tests
- risk: low — bumping the limit + adding bypass is strictly additive; cooldown gating is client-side opt-in; HIGH op_types still POST through cooldown so the highest-signal events never drop

## Notes for main-thread reviewer

- Deploy: source-only patch per Agent D's brief. Main thread will
  deploy `log-client-error` after review via `.claude/deploy_via_api.js`
  per CLAUDE.md §11 deploy flow.
- Client side ships in the next APK — `ErrorTelemetry` changes are
  backward-compatible (cooldown defaults null → behaviour identical to
  pre-fix for any users on stale builds).
- Followup (NOT in this batch): add a `client_errors` health dashboard
  panel showing per-user 24h count distribution + `rate_limited`
  count, so we can spot a recurrence proactively.
