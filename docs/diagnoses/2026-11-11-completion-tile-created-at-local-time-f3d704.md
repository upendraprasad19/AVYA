---
bug_id: f3d704
date: 2026-11-11
batch: coach-workout-parity-tile (S3, commit A)
status: fixed
blast_radius: account
symptom: >-
  The coach chat's "X of Y - Complete workout" tile (the coachBox completion_prompt_<date> row) sorted in the wrong
  place in the chat thread. CompletionPromptStore.write stamped created_at with DateTime.now().toIso8601String(), a
  device-local time with no offset, while every chat row is stamped in UTC with Z. ChatHistoryNotifier.build sorts all
  rows by the created_at STRING. In IST the tile's string reads 5.5 h ahead of the UTC strings, so the tile sat under
  every reply the user sent for the next 5.5 hours instead of under the reply that produced it. West of UTC it would sort
  above earlier replies. Live in 1b since PR #240; found at S3 plan review round 1 (T1A-4), not by a user report.
concept: coach_derived_completion
sot_registry_entry: coach_derived_completion (reader ChatHistoryNotifier.build fields_read + created_at note) and coach_day_completion_rule (writer CompletionPromptStore note)
writers:
  - file: lib/core/services/completion_prompt_store.dart
    method: CompletionPromptStore.write (created_at for a new row, a reshow and the keep path)
    line: 50
  - file: lib/features/ai_coach/repositories/coach_interaction_repository.dart
    method: chat row writers (created_at DateTime.now().toUtc().toIso8601String(), unchanged)
    line: 53
readers:
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method_or_widget: ChatHistoryNotifier.build (reads created_at at 205, sorts the strings at 213)
    line: 213
hive_key_prefix: completion_prompt_
hive_key_formula: "coachBox['completion_prompt_<yyyy-MM-dd IST>'] = {kind: 'completion_prompt', date, planned_count, logged_count, created_at (UTC with Z), resolved_at}"
sync_methods:
  - none (the row is local-only; _syncCoachInteractions skips kind != null)
restore_methods:
  - none (never restored)
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/coach_completion_prompt_test.dart
ist_handling:
  - the row KEY stays the IST date (istTodayStr); only the created_at INSTANT changes representation (UTC with Z), so it orders against the UTC chat rows on any host zone
  - the ordering test runs under TZ=Asia/Kolkata and TZ=Etc/GMT+12; each zone reddens a different half of it against the pre-fix stamp
provider_invalidations:
  - none (the existing write callers keep their invalidation of chatHistoryProvider)
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a (coachBox is user-scoped; the callers keep their owner guards)
forbidden_patterns_checked:
  - { pattern: "'created_at'.*DateTime\\.now\\(\\)\\.toIso8601String\\(\\)", absent: true }
proposed_fix: >-
  A new row stamps DateTime.now().toUtc().toIso8601String(). The keep path (a default write over an existing row keeps
  its created_at so the tile keeps its place) normalises the stored stamp with CompletionPromptStore.utcStamp:
  DateTime.tryParse(v)?.toUtc().toIso8601String() ?? v. That is the same instant, so a row written by an older build
  sorts right after the update and never jumps. write gains {bool reshow = false} for S3's "I'm done" tile: a reshow
  stamps a fresh UTC created_at (the tile sorts under the reply that asked for it) and writes resolved_at: null.
  resolve keeps its local resolved_at: it is only null-checked, never ordered.
regression_test_planned:
  - test/contracts/coach_completion_prompt_test.dart
related_bugs:
  - c2b7e4  # progress photos taken_at: local toIso8601String() with no offset compared against UTC (docs/diagnoses/2026-10-08-progress-photos-lapsed-user-and-taken-at-c2b7e4.md)
  - 280c4d  # Unit 1, the tap-card that introduced the row
  - 24e630  # 1b, CompletionPromptStore became the row's one owner (body moved unchanged)
recurrence: |
  Recurrence of c2b7e4's class: a DateTime.now().toIso8601String() (local, no offset) compared against UTC values. In
  c2b7e4 the comparison was in Postgres; here it is a Dart string sort. The known-good fix applied: stamp UTC with Z at
  the writer. Sweep done at planning (plan 7.6): of the coach-side DateTime.now().toIso8601String() writers
  (completion_prompt_store.dart resolve, tool_dispatcher.dart:249,742,765,804,1263,1726, induction_service.dart:58,133,
  tool_confirm_card.dart:64, media_picker.dart:275, hotel_workout_planner.dart:221, regenerate_plan_planner.dart:382,461)
  only the prompt row's created_at is ORDERED against UTC strings; the others are standalone stamps or null-checked, so
  they stay as they are.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "completion_prompt_store.dart write (UTC new row, utcStamp keep path, reshow); 5 new tests in coach_completion_prompt_test.dart (16 green under TZ=Asia/Kolkata and TZ=Etc/GMT+12); mutation table below." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "Tests write real coachBox rows (a pre-fix local stamp, a Z stamp, a resolved row, UTC chat rows) and read them back through the store and through ChatHistoryNotifier.build's sorted output." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "The row is local-only; no schema involved." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "The row is never pushed (kind != null skip in _syncCoachInteractions)." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function in commit A." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "Local-only row; no request or response shape." }
impact_analysis: >-
  The tile now sorts by its real instant against the chat rows on any device zone. Rows written by an older build are
  normalised on their next write to the same instant. Until that next write, an old row's stamp still sorts as before,
  because build is a pure read and does not rewrite it. The row is today-only and swept the next day, so an old stamp
  lasts at most until the next coach log or the next day. No count, streak or cloud value changes.
---

# The completion tile's created_at was local time, sorted against UTC chat rows (f3d704)

## Root cause
`CompletionPromptStore.write` (`completion_prompt_store.dart`, before this fix line 42) stamped
`DateTime.now().toIso8601String()`: local time, no `Z`. `CoachInteractionRepository` stamps chat rows with
`DateTime.now().toUtc().toIso8601String()` (lines 53, 121). `ChatHistoryNotifier.build` reads `created_at` at
`ai_coach_provider.dart:205` and sorts the raw strings at `:213`. A string sort of mixed representations is wrong by
the zone offset: +5:30 in IST puts the tile 5.5 h late.

## Fix
- New row: `DateTime.now().toUtc().toIso8601String()`.
- Keep path: `CompletionPromptStore.utcStamp(existing)`, the same instant in UTC (an unparseable value is kept).
- `reshow: true` (S3): fresh UTC stamp, `resolved_at: null`.
- `resolve` unchanged (local `resolved_at`, only null-checked).

## Tests
`test/contracts/coach_completion_prompt_test.dart`, group "f3d704":
- a new row ends with `Z` and is within one second of now;
- a pre-fix local stamp is normalised to the same instant (`isAtSameMomentAs`);
- a `Z` stamp round-trips unchanged;
- ordering: a UTC chat row one second older renders above the tile, one second newer renders below it, through
  `ChatHistoryNotifier.build`;
- reshow: a fresh UTC stamp, `resolved_at` null, and a following default write keeps that stamp.

Existing test (e) (supersede keeps `created_at`) still passes. The file passes in full (16 tests) under
`TZ=Asia/Kolkata` and `TZ=Etc/GMT+12`.

## Mutation evidence (rule 21)
Each mutant was applied by exact-string replacement, with a count assertion that the edit landed once. The file was
run under both zones, then restored, and the restore was checked by sha256. Script:
`m59.py` in the session scratchpad.

| id | edit | Asia/Kolkata | Etc/GMT+12 |
|---|---|---|---|
| M59a | reshow path stamps `DateTime.now().toIso8601String()` (local) | RED, 1 (reshow test) | RED, 1 (reshow test) |
| M59b | new-row path (not reshow) stamps local | RED, 3 (new-row UTC, ordering, existing (e): its kept stamp is now normalised and no longer equals the local first stamp) | RED, 3 (same) |
| M59c | keep path returns the stored stamp without `utcStamp` | RED, 1 (keep-path normalisation) | RED, 1 (same) |

Survivors: none. The ordering test reddens under M59b in both zones, for opposite reasons: in IST the tile sorts after
the newer row, west of UTC it sorts before the older row.
