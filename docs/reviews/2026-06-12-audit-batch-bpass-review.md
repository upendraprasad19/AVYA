---
reviewed_at: 2026-06-12T00:00:00Z
staged_against: fa96bda..HEAD
blast_radius: account
reviewer: claude-sonnet-bpass
findings_count: 1 P0 (→false_alarm, live-verified), 0 P1, 2 P2 (→accepted, comments added)
verdict: accepted
triaged_by: claude-opus (live-verified the P0; addressed both P2 comments)
---

## TRIAGE (Opus, live-verified)
- **P0 `enforce_food_text_daily_limit` → FALSE_ALARM.** Live query (pg_proc): the
  function is `prosecdef=false` (SECURITY **INVOKER**, not DEFINER), `rettype=trigger`,
  1 attached trigger, no args. anon's EXECUTE grant is harmless — no RLS bypass (not
  DEFINER) and a trigger-returning function isn't PostgREST-RPC-callable. 090 hardened
  its search_path as hygiene (the advisor flags `function_search_path_mutable` for ALL
  functions, not just DEFINER) — that does NOT imply DEFINER. **Completeness check:**
  `SELECT ... WHERE prosecdef=true AND has_function_privilege('anon',oid,'EXECUTE')`
  returns `[]` → ZERO SECURITY DEFINER public functions remain anon-executable → 091 is
  COMPLETE. The reviewer reasoned from a wrong premise (assumed DEFINER); verified live
  per feedback_audit_verifier_cannot_trust_own_subagent.
- **P2-1 (mergeFreezeProgress both-null) → accepted:** clarifying comment added at
  streak_progress_service.dart:212. Behavior was already correct (reviewer agreed).
- **P2-2 (getWeeklyWorkoutCounts daysAgo==7 boundary) → accepted:** clarifying comment
  added at workout_repository.dart:780. Pre-existing intentional sliding-window semantics.

# B-pass: audit-2026-06-10 batch

## Lens 1 — writer_reader_drift

### wlog_ double-count (orphan synthesize vs _restoreWorkoutLogs)

**Checked:** The orphan-completion path (`sync_workout.dart:867`) synthesizes a `wlog_<date>` row only when `_hive.workoutBox.get(wlogKey) == null` — additive/local-wins guard is present. `_restoreWorkoutLogs` (line 605) does the same: `if (_hive.workoutBox.get(logId) != null) continue;`. The two writers are both additive and key on the same `wlog_<date>` string. Only one will win on first-write; re-run is a no-op. Double-count **not possible** with this guard in place.

**Checked:** `getWeeklyWorkoutCounts` iterates `workoutBox.values` and counts rows where `type == 'workout_log'`. There is only ever one `wlog_<date>` key per date. A live `markCompleted` call and a restore for the same date both resolve to the same key — the first writer wins, the second is skipped. No double-count.

**Checked:** `WlogTypeBackfillMigrator.repairRow` mutates the existing map in place; it does not create a new key. Cannot produce a second row.

Result: **clean**.

---

### P2 — mergeFreezeProgress: both-null last_refill lands in cloud-wins branch but result has `lastRefill: null`

- **Severity:** P2
- **File:line:** `lib/core/services/streak_progress_service.dart:212`
- **Claim:** When both `localLastRefill` AND `cloudLastRefill` are null (brand-new user, never refilled on either side), `localLastRefill == null` makes `cloudWins = true`. The function returns `cloudAvailable`, `cloudUsed`, and `lastRefill: cloudLastRefill ?? localLastRefill` which resolves to `null ?? null = null`. The caller at `sync_restore_completeness.dart:174` then skips the `lastRefill` write due to the `if (merged.lastRefill != null)` guard — so `streak_freezes_last_refill` is never set in `existingMap`. This is actually the correct outcome (brand new user has no last_refill; the first refill sets it). However, the function's `scheduleSyncUp: false` on this path means if the local device had a later refill that was `null` (impossible in practice — a refill always sets a non-null Monday string), no sync would be triggered. In isolation the behavior is safe. The concern is documentation: the "cloud-wins when both null" path is not commented, making it easy to misread `cloudWins` as defaulting to cloud-available=1, when really it means "use cloud state as baseline for a user with no freeze history on either side". No change needed but could produce confusion.
- **verification:** `grep -n "cloudWins\|localLastRefill == null" lib/core/services/streak_progress_service.dart`
- **suggested-fix:** Add a comment above line 212: `// Both null → brand-new user; cloud (available=1 default) is the canonical baseline.`
- **status:** pending

---

### P2 — `getWeeklyWorkoutCounts` week boundary: "today" day is counted in week 0 (`daysAgo == 0 < 7`), correct; but a workout logged exactly 7 days ago (daysAgo==7) falls into `< 14` i.e. week 1, not week 0 — pre-existing behaviour, unchanged by this diff

- **Severity:** P2 (existing semantics preserved — this is not a regression introduced by the diff, but it is a latent incorrect edge)
- **File:line:** `lib/features/train/repositories/workout_repository.dart:780`
- **Claim:** The bucket boundaries are `daysAgo < 7` → week 0, `daysAgo < 14` → week 1, etc. A workout done exactly 7 days ago has `daysAgo == 7`, which does NOT satisfy `< 7`, so it lands in week 1 ("last week"). This is consistent with "this week = the last 7 days not including today+7" semantics but the IST fix did not change this. The comment says "Index 0 = this week" — correct. The boundary is unchanged from before the fix and matches the existing tests (checked `weekly_workout_counts_ist_test.dart` implicitly via the diff). **Not a regression**, but worth noting for anyone reading the review.
- **verification:** `grep -n "daysAgo < 7\|daysAgo < 14" lib/features/train/repositories/workout_repository.dart`
- **suggested-fix:** No code change needed; consider adding a comment: `// daysAgo == 7 → last week (not this week) — intentional sliding-window semantics.`
- **status:** pending

---

## Lens 2 — function_exception_swallow

**Checked:**
- `WlogTypeBackfillMigrator.runIfNeeded` — outer `try/catch` catches and records via `ErrorTelemetry.recordNonFatal`; deliberately does NOT set the flag on failure so the next launch retries. `unawaited(ErrorTelemetry...)` calls are both present. Clean.
- `syncFreezes()` (called via `unawaited` from `_restoreFreezes`) — has its own try/catch with telemetry pair. Clean.
- `_restoreFreezes` outer catch — records with `reason: 'sync_service_if_23'` + `_reportSyncFailure`. Clean.
- Auth provider call site wraps `WlogTypeBackfillMigrator.runIfNeeded()` in try/catch with `debugPrint`. Clean.

Result: **clean** — every new Supabase/Hive call in the diff has a catch block; no swallowed exceptions.

---

## Lens 3 — blast_radius_mismatch

### P0 — migration 091: `enforce_food_text_daily_limit` is a SECURITY DEFINER function not in either 090 or 091

- **Severity:** P0
- **File:line:** `supabase/migrations/090_revoke_anon_security_definer_execute.sql:116` (`ALTER FUNCTION public.enforce_food_text_daily_limit() SET search_path = ...`)
- **Claim:** `enforce_food_text_daily_limit` appears in 090 as a `search_path` hardening target (line 116), confirming it is a `SECURITY DEFINER` function in `public`. However, **it is absent from migration 091's REVOKE/GRANT block**. If it holds `SECURITY DEFINER` privileges, the `anon` role still has EXECUTE on it via the PUBLIC default grant after 091 applies. The diagnose doc (c9b3e2) + migration 090 comment enumerate the functions that needed revoking — `enforce_food_text_daily_limit` is not in that enumeration. Either (a) it was intentionally left callable by anon (it's a trigger or a cron, not an RPC), or (b) it is an oversight.

  Checking: the function name `enforce_food_text_daily_limit` sounds like a row-level enforcement trigger (fired from a `BEFORE INSERT` trigger on a nutrition table) rather than a direct RPC. If so, callers cannot invoke it via `/rest/v1/rpc/` — the danger surface is closed — and revoking EXECUTE would have no effect on trigger firing (Postgres triggers fire regardless of EXECUTE grant, as correctly noted in 091's comment for the other trigger functions). In that case this is NOT a gap.

  **But the review cannot confirm** without reading the trigger definition. The `search_path` hardening in 090 being applied to it confirms it exists and is SECURITY DEFINER; whether it has a PostgREST-accessible RPC signature is unknown from the diff alone.
- **verification:** `SELECT p.proname, p.prosecdef, t.tgname FROM pg_proc p LEFT JOIN pg_trigger t ON t.tgfoid = p.oid WHERE p.proname = 'enforce_food_text_daily_limit';` — if `tgname IS NOT NULL`, it is a trigger function; EXECUTE grant doesn't matter. If `tgname IS NULL` and `prosecdef = true`, it is a callable RPC and 091 has a gap.
- **suggested-fix:** If the query confirms it is a trigger function, add a comment in 091 explaining why it is excluded (mirrors the pattern used for the other trigger functions). If it is NOT a trigger function, add `REVOKE EXECUTE ON FUNCTION public.enforce_food_text_daily_limit() FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.enforce_food_text_daily_limit() TO service_role;` to a follow-up migration.
- **status:** pending

---

**Checked (positive):** `update_streak_progress` in 091 — `REVOKE ... FROM PUBLIC; GRANT ... TO authenticated, service_role`. The `authenticated` EXECUTE is preserved for the client optimistic-lock write path. The `auth.uid()` body guard in 090 blocks cross-account writes. The EF callers (`verify-payment`, `razorpay-webhook`, `redeem-referral`) all use `SUPABASE_SERVICE_ROLE_KEY` and retain EXECUTE via `service_role`. No over-revocation.

**Checked:** trigger functions (`auto_approve_community_item`, `update_user_subscription_status`, `handle_new_auth_user`, `rls_auto_enable`) — 091 revokes PUBLIC EXECUTE only, no re-grant. 090's comment and 091's comment both correctly note triggers fire regardless of EXECUTE grant. Clean.

**Checked:** `cron_call_log_cleanup_7d` — REVOKE PUBLIC + GRANT service_role. Cron runs as service_role. Clean.

---

## Lens 4 — secrets_in_tree

Scanned all files in the diff for `rzp_`, `sk_`, `pk_`, `AIza`, `eyJ` (JWT), `AAAA` (Firebase), and generic `password/token/api_key` literals. Only hit is the comment in 090 mentioning `auth leaked-password protection` as a dashboard toggle (not a credential). **Clean.**

---

## Lens 5 — unawaited_no_error_sink

All `unawaited(...)` calls in the diff:
- `unawaited(ErrorTelemetry.recordNonFatal(...))` (×2 in wlog_type_backfill_migrator.dart) — `recordNonFatal` is itself a fire-and-forget telemetry helper with its own internal error suppression. Acceptable pattern per existing codebase convention.
- `unawaited(SyncService.instance.syncFreezes())` (sync_restore_completeness.dart:179) — `syncFreezes()` has a try/catch with telemetry pair. Clean.

**Clean.**

---

## Extra focus — WlogTypeBackfillMigrator idempotency

Flag is `migrationBox['wlog_type_backfill_v1_done']`. The flag is set AFTER the repair loop completes. On crash mid-loop, the migrator retries on next launch — rows already repaired will have `type == 'workout_log'` (the check `if (row['type'] != 'workout_log')` is a no-op for those); only un-repaired rows will be mutated. **Idempotent per row; re-entrant safe.**

The migrator is wired into `auth_provider.dart:_ensureLocalUser` (line 472 in diff), which runs on every post-auth boot. Flag gating confirmed. **Clean.**

---

## Extra focus — getWeeklyWorkoutCounts off-by-one at week boundaries

`_dayUtc(istTodayStr())` returns UTC-midnight for today's IST date. `_dayUtc(dateStr)` returns UTC-midnight for the logged date string. `today.difference(date).inDays` is thus a pure integer day count with no time-of-day component. A workout logged today: daysAgo=0, lands in `< 7`. A workout logged yesterday: daysAgo=1, lands in `< 7`. Boundary is correct. The `daysAgo == 7` edge noted in P2 above is the only anomaly and was present before this diff.

---

## Summary

| Severity | Count |
|---|---|
| P0 | 1 |
| P1 | 0 |
| P2 | 2 |
| false_alarm | 0 |

**Single most important finding (P0):** `enforce_food_text_daily_limit` is a SECURITY DEFINER function in `public` that received `search_path` hardening in migration 090 but was not included in migration 091's REVOKE/GRANT block. If it is a direct RPC (not exclusively a trigger), `anon` retains EXECUTE. Verify with the query above; if it is trigger-only, close with a clarifying comment.
