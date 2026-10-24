---
bug_id: b9f4d2
date: 2026-05-31
batch: rank-deployment-sequential-2026-05-31
status: fixed
symptom: >
  Surfaced while wiring the deployment-driven rank ladder: the server cron
  `evaluate-rank-promotions` SELECTs four columns from `user_progress`
  (current_streak_days, deployments_complete, longest_gap_days, last_workout_date)
  that DO NOT EXIST on the live table. PostgREST returns a 400, the cron's
  `const { data: progressRow }` is null, every gate input defaults to 0, and
  `highestQualified()` can only ever return SD2 — so the server-side rank
  evaluation has been silently inert for the entire sailor + officer ladder.
  Compounding it: `deployments_complete` was never written client-side (F18
  deferral), so PO (>=2) / CPO (>=3) were unreachable even on the client; and
  both engines "leap-frogged" (highest independently-qualifying rung) rather
  than advancing sequentially as the rank metaphor intends.
concept: rank_monotonic_current_code
sot_registry_entry: rank_monotonic_current_code
blast_radius: platform
writers:
  - { file: supabase/functions/evaluate-rank-promotions/index.ts, method: cron upserts rank_promotions + user_profile.current_rank_code from highestQualified(state), line: 144 }
  - { file: lib/shared/repositories/user_repository.dart, method: saveProgress stamps deployments_complete = current_phase-1 (monotonic), line: 78 }
  - { file: lib/core/services/sync/sync_profile.dart, method: _syncUserProgress upserts the 4 rank-eval columns to user_progress, line: 160 }
readers:
  - { file: supabase/functions/_shared/rank_engine.ts, method: highestQualified — now a sequential (no-skip) contiguous walk, line: 93 }
  - { file: supabase/functions/evaluate-rank-promotions/index.ts, method: SELECT current_streak_days/deployments_complete/longest_gap_days/last_workout_date, line: 107 }
  - { file: lib/core/services/rank_service.dart, method: _qualifiedRankCode — sequential client mirror; _readEvaluationState reads progress['deployments_complete'], line: 460 }
hive_key_prefix: "userBox['progress'] (deployments_complete / current_streak_days / last_workout_date)"
hive_key_formula: "n/a — top-level 'progress' map keys"
sync_methods: [_syncUserProgress]
restore_methods: [_restoreUserProgress]
cloud_table: user_progress
cloud_columns: [deployments_complete, current_streak_days, last_workout_date, longest_gap_days]
contract_test_path: test/contracts/deployments_complete_writer_to_reader_test.dart
ist_handling:
  - { site: last_workout_date stamped by train_provider on completion, helper: istDateStr, status: ok }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [sync_user_progress]
cross_account_guard: >
  n/a — user_progress is per-user (UNIQUE(user_id)); the cron iterates per user_id
  and the client write goes through the user-scoped progress map. No cross-account
  exposure.
forbidden_patterns_checked:
  - { pattern: "Edge Function SELECTs a column absent from live information_schema", absent: true }
  - { pattern: "rank engine leap-frogs a locked rung (highest independently-qualifying)", absent: true }
proposed_fix: >
  (1) Migration 081 adds the four columns to user_progress and backfills
  deployments_complete = GREATEST(0, current_phase-1) forward-only, so the cron's
  SELECT resolves and existing users get a correct deployment count immediately.
  (2) The client now WRITES deployments_complete (monotonic, in
  UserRepository.saveProgress — the single progress writer every phase-advance
  path funnels through) and SYNCS it + current_streak_days + last_workout_date +
  longest_gap_days via sync_profile._syncUserProgress. current_streak_days and
  last_workout_date were already stamped into the progress map by train_provider
  on workout completion — they just never made it into the upsert payload.
  (3) Both engines (client rank_service._qualifiedRankCode AND server
  rank_engine.highestQualified) switched from "highest independently-qualifying
  rung" to a SEQUENTIAL contiguous walk that stops at the first failed gate — so
  the deployment-gated PO/CPO rungs can no longer be leap-frogged; reaching
  SubLt/Lt requires earning PO+CPO first. Monotonic no-demotion (shouldPromote)
  preserved. EF redeployed byte-identical via host-shell deploy.
regression_test_planned:
  - test/contracts/deployments_complete_writer_to_reader_test.dart
  - test/contracts/rank_sequential_no_skip_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "rank_service._qualifiedRankCode sequential walk; saveProgress stamps deployments_complete monotonically; flutter analyze clean" }
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migration 081 adds deployments_complete/current_streak_days/last_workout_date/longest_gap_days; live information_schema query confirms all four present post-apply" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "backfill UPDATE set amar (0f35f3dd) deployments_complete=11 (current_phase 12-1); confirmed via SELECT" }
  - { tier: 5, layer: migrations_applied, status: fixed_in_this_batch, evidence: "081 applied via Management API; backups/applied_migrations.json + backups/live_schema_columns.json paired" }
  - { tier: 6, layer: edge_function_deploy, status: fixed_in_this_batch, evidence: "evaluate-rank-promotions redeployed with sequential rank_engine.ts; smoke verified cron promotes a seeded test user through the contiguous ladder" }
impact_analysis: >
  Platform-tier rank correctness. The server cron — the backstop that promotes
  users who aren't actively opening the app — could only ever grant SD2 because
  it read four columns that did not exist. In practice the CLIENT
  evaluateAndPromote (post-workout / splash) carried promotions, so users still
  saw SD2->SD1->LS; but PO/CPO and the entire officer track were unreachable
  because deployments_complete was hard-zero client-side AND the cron was inert.
  This is the root of "completing phases didn't advance my rank / didn't complete
  deployments." With the fix, completing a phase earns a deployment, the cron and
  client agree on a sequential ladder, and a sustained user can progress through
  PO -> CPO -> MCPO -> SubLt -> Lt over the designed ~2.5-year tenure.
---

# b9f4d2 — server rank cron reads four nonexistent user_progress columns (silently inert) + deployment wiring + sequential ladder

## What happened
`evaluate-rank-promotions/index.ts:107` does:

```ts
.select("current_streak_days, deployments_complete, longest_gap_days, last_workout_date")
```

None of those columns existed on `public.user_progress` (live `information_schema`
confirmed: only `current_phase, current_week, total_workouts_done,
current_streak_weeks, phase_started_at, streak_freezes_*, …`). PostgREST 400s, the
cron ignores the error, `progressRow` is null, and the `EvalState` is built with
`streak=0, deploymentsComplete=0, gap=0`. `highestQualified()` therefore returns
SD2 for everyone — the server rank evaluation never promoted anyone past
induction.

Two adjacent defects made the ladder incoherent:
- **`deployments_complete` had no client writer** (explicit F18 deferral in
  `rank_service.dart`), so PO(>=2)/CPO(>=3) were dead rungs.
- **Both engines leap-frogged** — `_qualifiedRankCode` / `highestQualified`
  picked the highest *independently*-qualifying rung, so an officer-track
  completion-rate qualifier could skip the locked sailor rungs.

## Why it mattered
The whole "complete phases → earn deployments → climb rank to Lieutenant" loop
was broken end-to-end: deployments never counted, PO/CPO were unreachable, the
server backstop was inert, and the ladder allowed skipping. A user finishing the
12-phase program plateaued at LS forever.

## Fix
1. **Migration 081** adds the four columns + forward-only backfill
   `deployments_complete = GREATEST(0, current_phase-1)`.
2. **Client writes + syncs** the real values: `UserRepository.saveProgress`
   stamps `deployments_complete` monotonically (single source — every
   phase-advance path funnels through it); `sync_profile._syncUserProgress`
   pushes all four columns.
3. **Sequential engines** (client + server lockstep): walk the ladder from the
   bottom, advance only while each successive gate passes, stop at the first
   failure. Deployment-gated PO/CPO can no longer be skipped. Monotonic
   no-demotion preserved.
4. **EF redeployed** byte-identical (host-shell) to ship the sequential
   `rank_engine.ts`.

## Verification
- Live `information_schema` shows all four columns post-081; amar backfilled to
  `deployments_complete = 11`.
- `flutter analyze` clean.
- Contract tests: `deployments_complete_writer_to_reader_test.dart` (monotonic
  writer→reader) + `rank_sequential_no_skip_test.dart` (officer ranks unreachable
  until PO+CPO earned; no leap-frog; no demotion).
- EF smoke: a seeded test user with deployments+streak satisfying PO/CPO is
  promoted through the contiguous ladder by the cron.
