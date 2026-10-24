---
bug_id: a9c3e2
date: 2026-06-01
batch: derive-only-ai-coach-tool-surface
status: fixed
blast_radius: platform
symptom: >
  Driving the AI coach live as amar (a year-sim power user), EVERY message failed
  with "Your coaching context is unusually large. Please try a shorter question."
  The server-side snapshot guard (`ai-proxy`, snapshot ≤ 10000 chars per CLAUDE.md
  §4.4 rule 18) rejected the request because `AiSnapshotBuilder.buildAiContext`
  produced a snapshot over the cap. The coach was 100% unusable for a heavy user —
  no message could get through, regardless of how short the message itself was.
concept: ai_snapshot_building
sot_registry_entry: ai_snapshot_building
writers:
  - lib/features/ai_coach/services/ai_snapshot_builder.dart buildAiContext (assembles the ~50-field user_daily_snapshot)
  - lib/features/ai_coach/services/ai_snapshot_builder.dart trimSnapshotToBudget (NEW — caps the serialized snapshot under the server limit)
readers:
  - supabase/functions/ai-proxy/index.ts (enforces snapshot ≤ 10000 chars; rejects with "snapshot too large")
  - lib/features/ai_coach/providers/ai_coach_provider.dart (maps the rejection to "coaching context unusually large")
hive_key_prefix: not_applicable (the snapshot is an assembled request payload, not a Hive row)
hive_key_formula: not_applicable
sync_methods: not_applicable (snapshot is sent with each AI request; not synced)
restore_methods: not_applicable
cloud_table: not_applicable (request payload to the ai-proxy Edge Function, not a table)
cloud_columns: not_applicable
contract_test_path: test/contracts/ai_snapshot_budget_trim_test.dart
ist_handling: not_applicable (no date math changed)
provider_invalidations: not_applicable (read-only snapshot assembly; no mutation)
telemetry_op_types: >
  not_applicable for new telemetry — the trim logs via debugPrint when it fires;
  the server rejection already surfaces as the mapped user error. (A future
  enhancement could emit an `ai_snapshot_trimmed` event for observability.)
cross_account_guard: >
  not_applicable — the snapshot is built from the already user-scoped Hive boxes
  (HiveService.instance, wrapUserScopedBox); the trim only shrinks values.
forbidden_patterns_checked:
  - "Unbounded snapshot field with no size cap (e.g. personal_records over a year of unique exercises) — now bounded by trimSnapshotToBudget regardless of which field is large."
  - "Snapshot exceeding the 10000-char server limit — pinned under budget by test/contracts/ai_snapshot_budget_trim_test.dart."
  - "enrichContextForQuery re-inflating the trimmed base past the 10000 cap via unbounded 90-day weight/adherence/nutrition trends (the base trim left only ~1500 chars headroom) — closed by RE-TRIMMING the enriched output to budget 9500 before returning; pinned by ai_snapshot_budget_trim_test.dart (enriched-shape case + a source-grep that enrichContextForQuery routes its return through trimSnapshotToBudget). Surfaced by the Hermes L37 pass the same day."
proposed_fix: >
  Add `AiSnapshotBuilder.trimSnapshotToBudget(snapshot, {budget = 8500})`, called at
  the end of buildAiContext. It iteratively finds the LARGEST non-critical field and
  shrinks it (halve a List, halve a Map's entries, or drop a scalar blob) until the
  serialized snapshot fits the budget (8500 leaves headroom under the 10000 server
  cap for `enrichContextForQuery` additions). A `keep` allowlist of high-signal
  fields (profile, progress, today_workout, today_nutrition, current_plan_summary,
  subscription, current_rank, daily_targets, ...) is never trimmed, so the coach
  always retains the fields it reasons from. Generic by design — fixes the overflow
  regardless of WHICH field is pathologically large for a given user.
regression_test_planned: >
  test/contracts/ai_snapshot_budget_trim_test.dart — (1) an oversized snapshot
  (huge personal_records Map + coaching_notes List, > 8500 chars) trims under budget
  while keeping profile/today_workout/subscription/progress intact; (2) a small
  snapshot is left byte-identical; (3) default budget always yields ≤ 10000 chars
  even with 5000 PR entries. 3/3 pass (observed trims 58266→7116 and 167828→4852).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "ai_snapshot_builder.dart trimSnapshotToBudget added + wired into buildAiContext; flutter analyze on the file = No issues found; 3/3 behavioral tests pass" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "server enforces snapshot <=10000 (rule 18); budget 8500 leaves headroom; snapshot-contract gate (check_snapshot_contract.dart) still PASS (52 keys) — no contract key removed at source" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "trim operates on the assembled in-memory map only; no Hive write; reads still route through HiveService user-scoped boxes" }
impact_analysis: >
  Platform blast radius — touches the shared AI snapshot builder every user's coach
  uses. The BUG manifested per-account based on data volume (power users with long
  histories), but it would hit ANY user as they accumulate enough data (PRs, custom
  exercises, a long log history). The fix is conservative: snapshots under 8500 chars
  are untouched (byte-identical), so normal users see no change; only oversized
  snapshots are trimmed, and only their largest non-critical fields. Worst case of a
  wrong trim is the coach getting slightly less historical detail for an overloaded
  user — strictly better than the current "coach cannot respond at all." Found live
  via the Claude-in-Chrome E2E on amar; verified by re-sending a coach message after
  the fix (coach responds instead of erroring).
---

# AI coach unusable for power users — snapshot exceeded the 10K server limit

## What happened

Driving the AI coach as amar (year-simulation power user, 13+ phases of history) in
the live web E2E, every message — even a 2-word "hi" — came back with:

> "Your coaching context is unusually large. Please try a shorter question…"

That string is the client mapping of the server's *snapshot too large* rejection
(`ai-proxy` enforces the user_daily_snapshot ≤ 10000 chars, CLAUDE.md §4.4 rule 18).
The message length was irrelevant — the **snapshot** was over the cap, so the coach
rejected 100% of messages.

## Root cause

`AiSnapshotBuilder.buildAiContext` assembles a ~50-field snapshot. Several fields are
**unbounded** and scale with history — most notably `personal_records` (a Map keyed by
every distinct exercise the user has ever logged; a year of varied training yields a
large map). For amar the serialized snapshot exceeded 10000 chars. `coach_notes` was
verified *empty* (0 chars) for amar, ruling that field out — confirming the bloat was
the history-scaling fields, not free-text notes.

## Fix

`trimSnapshotToBudget(snapshot, {budget = 8500})` — iteratively shrinks the largest
NON-critical field (halve a List, halve a Map, drop a scalar) until the serialized
snapshot fits, preserving a `keep` allowlist of high-signal fields. Generic so it
fixes the overflow no matter which field is large for a given user. Called at the end
of `buildAiContext`.

## Follow-up — enrich-after-trim re-breach (Hermes L37, same day)

The Hermes E-pass (L37 null-shape/empty-state lens) caught that the original fix was
**incomplete for the exact power-user case it targeted**. `buildAiContext` trims the
BASE snapshot to 8500, but the send path (`ai_coach_provider.dart:633-634`, and the
retry at `:698-699`) calls `enrichContextForQuery(message, baseContext)` **after** the
trim, and that method appends **unbounded** historical data — `weight_trend`
(`getWeightHistory(days: 90)`), `workout_adherence` (90 days), `nutrition_trend`
(12 weeks) — then `return`ed without re-trimming. A single 90-entry `weight_trend`
(~3600 chars) blows the ~1500-char headroom, so a power user's **historical** query
("how has my weight changed") re-breached the server's hard `> 10000` reject
(`ai-proxy/index.ts:547`) and re-bricked the coach — the very symptom a9c3e2 set out to
cure, just gated behind a historical keyword instead of every message.

**Fix:** `enrichContextForQuery` now ends with `return trimSnapshotToBudget(context,
budget: 9500)` — the enriched payload is re-capped (9500 keeps a 500-char margin under
the 10000 server cap). The `keep` allowlist protects the base high-signal fields, so the
trim shrinks the (non-critical) historical adds first. Non-historical queries (enrich
adds nothing) are unaffected — the trim is a no-op when already under budget.
Regression: `ai_snapshot_budget_trim_test.dart` gained (1) an enriched-shape behavioral
case (base + 250-entry trends → ≤ 9500, core intact, trends shrunk, proving the trend
keys are NON-keep) and (2) a source-grep pinning that `enrichContextForQuery` routes its
return through `trimSnapshotToBudget`.

## Lesson / class

Any payload assembled from user data and bounded by a server limit MUST be
defensively capped on the client — an unbounded field will eventually breach the
limit for *some* user, and a hard server rejection with no client-side trimming makes
the whole feature silently unusable for exactly the most engaged users. Cap the
total, not just individual fields (you can't predict which field grows). **And cap it
at the LAST mutation before send** — a trim applied mid-pipeline (here, before the
`enrichContextForQuery` step) is defeated by any later append. The Hermes L37 pass found
exactly this: the right cap at the wrong point in the pipeline.

## See also

- `lib/features/ai_coach/services/ai_snapshot_builder.dart` (`buildAiContext`, `trimSnapshotToBudget`)
- `supabase/functions/ai-proxy/index.ts` (snapshot ≤ 10K enforcement)
- `lib/features/ai_coach/providers/ai_coach_provider.dart` (error mapping)
- `test/contracts/ai_snapshot_budget_trim_test.dart`
- ADR-0012 (the derive-only batch this surfaced in)
