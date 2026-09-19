---
bug_id: 3a7b9f
date: 2026-05-27
batch: 2026-05-27 rank-permanence batch (single-bug focused fix + c2 audit fast-follow)
status: shipped
symptom: |
  Founder-as-user "upendra" (auth.users d7a67a37-0b05-4f0a-b13c-388bff3cb59b)
  earned SD1 (ordinal 1) on 2026-05-21 14:35 UTC at streak=7, week=2,
  15 workouts. Approximately 7 hours later (2026-05-21 21:24 UTC),
  `user_profile.current_rank_code` reverted to SD2 (ordinal 0, the floor
  rank) while the historical `rank_promotions` row for SD1 remained
  intact (UNIQUE (user_id, rank_code) makes it insert-only).

  Cloud diff at investigation time (2026-05-27):
    rank_promotions: [SD2 @ 2026-05-01, SD1 @ 2026-05-21 14:35]
    user_profile.current_rank_code: 'SD2'  -- DEMOTED
    user_profile.current_rank_achieved_at: 2026-05-21 21:24 UTC  -- bogus

  Root cause: client `RankService.evaluateAndPromote`
  (lib/core/services/rank_service.dart:138) checked
  `if (currentCode != qualified.code)` and unconditionally overwrote the
  user_profile denormalization with `qualified.code` — the currently-
  qualifying ceiling. `_qualifiedRankCode(state)` recomputes the ceiling
  from live state (streak, total workouts, weeks since signup). When the
  user's streak dropped below 7 (SD1's `streakAtLeast: 7` gate in
  kRankGates at lib/core/services/rank_ladder_data.dart:200),
  `qualified` recomputed to SD2 and the writer demoted them. OI-37's
  local-Hive sync (rank_service.dart:147-150) propagated the demotion
  into userBox['profile'] → Profile/Home rank readers (getCurrentRank()
  at line 215) served the demoted rank.

  Server cron `evaluate-rank-promotions/index.ts:228-231` had the same
  unconditional overwrite — would have re-demoted nightly even if the
  client had been correct.

  New bug class: monotonic-field-recompute demotion. The
  rank_promotions table is the append-only event log (max-ever);
  user_profile.current_rank_code is its denormalization and must
  monotonically increase. Two writers disagreeing on semantic.
concept: rank_monotonic_current_code
sot_registry_entry: rank_monotonic_current_code
writers:
  - { file: lib/core/services/rank_service.dart, method_or_widget: RankService.evaluateAndPromote — wraps user_profile update + Hive mirror + onStateChanged + pending promotion stamp inside `if (shouldPromote(currentCode, qualified))`, line: 157 }
  - { file: lib/core/services/rank_service.dart, method_or_widget: RankService.shouldPromote — pure helper exercised by behavioral test, line: 61 }
  - { file: supabase/functions/evaluate-rank-promotions/index.ts, method_or_widget: evaluate-rank-promotions cron sync block — mirrors client guard server-side, deployed as v7, line: 244 }
readers:
  - { file: lib/core/services/rank_service.dart, method_or_widget: RankService.getCurrentRank — reads userBox['profile']['current_rank_code'], line: 215 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: _maybeShowPendingPromotion — surface pending promotion celebration, line: 138 }
  - { file: lib/features/profile/widgets/rank_chip_full_width.dart, method_or_widget: RankChipFullWidth — calls RankService.instance.getCurrentRank() and renders the displayed rank, line: 30 }
hive_key_prefix: null
hive_key_formula: "n/a — denormalization stored at userBox['profile']['current_rank_code'] (single value per user, not a key-prefixed collection)"
sync_methods: []
restore_methods:
  - _restoreUserProfile
cloud_table: user_profile
cloud_columns: [current_rank_code, current_rank_achieved_at]
contract_test_path: test/contracts/rank_no_demotion_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/rank_service.dart, line: 153, source: "current_rank_achieved_at stamped with DateTime.now().toIso8601String() at the moment of legitimate promotion — historical timestamps preserved via migration 075 heal" }
provider_invalidations:
  - userProfileProvider
  - currentRankProvider
telemetry_op_types:
  success: []
  failure:
    - rank_service_evaluate_and_promote
    - rank_service_local_profile_update
    - rank_service_pending_promotion_stamp
cross_account_guard: |
  evaluateAndPromote calls HiveUserSession.ensureOpenedForCurrentSession()
  before reading state (rank_service.dart:79) so cross-account session swap
  cannot corrupt the comparison. The cloud read at line 138-145 scopes by
  user.id from SupabaseService.currentUser — same identity check that
  governs every other writer in this service.
forbidden_patterns_checked:
  - "unconditional user_profile.update({current_rank_code: <recomputed>})"
  - "comparing rank codes by string inequality instead of ladder ordinal"
  - "demoting current_rank_code in a recompute path (now banned class — see debugging skill §2.19)"
proposed_fix: |
  Three-part fix:

  1. Migration 075 (data heal) — for every user, recompute
     user_profile.current_rank_code + current_rank_achieved_at from the
     max-ordinal row in rank_promotions (using historical achieved_at,
     not now()). Applied 2026-05-27 19:00 IST. Only Upendra was
     affected; verified before/after by SELECT.

  2. Client guard (rank_service.dart:157) — replace
     `if (currentCode != qualified.code)` with
     `if (shouldPromote(currentCode, qualified))`. The new pure helper
     compares by ladder ordinal and returns true only when
     `qualified.ordinal > currentOrdinal`.

  3. Server guard (evaluate-rank-promotions/index.ts:227-251) — same
     ordinal-compare gate. Reads existing user_profile.current_rank_code,
     looks up its ordinal via LADDER, only issues `.update()` when
     `winner.ordinal > currentOrdinal`. Deployed as v7 2026-05-27.

  Fast-follow (c2 audit finding, same batch): apply identical defense
  to `weekly-recalc/index.ts:266-298` where the cron was overwriting
  `user_progress.total_workouts_done` with the count of distinct
  workout dates from the LAST 4 WEEKS only — a silent decrease every
  Sunday for any user training longer than 4 weeks. Fix uses
  Math.max(recomputed, existing) per chunk pre-fetch. Deployed as v16.
regression_test_planned:
  - test/contracts/rank_no_demotion_behavioral_test.dart — 9 behavioral assertions covering (a) null→SD2 promotes, (b) SD2→SD2 no-op, (c) SD1→SD2 NO demote (the real incident), (d) Lt→SubLt NO demote (officer track), (e) Capt→every lower NO demote, (f) SD2→SD1 promotes, (g) SD2→Lt multi-rung promotion, (h) unknown code → SD2 promotes (fail-open for legacy data), (i) exhaustive 11×11 ladder pair coverage. Verified passing.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "rank_service.dart:157 — guard now if (shouldPromote(currentCode, qualified)); helper at :61" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "UserRepository.updateProfileFields at rank_service.dart:158-162 only fires inside the promote branch; demotion cannot reach Hive" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "user_profile.current_rank_code column exists (information_schema.columns query 2026-05-27); no DDL change needed" }
  - { tier: 4, name: postgres_data, status: fixed_in_this_batch, evidence: "migration 075 healed user_profile.current_rank_code for Upendra back to SD1 with historical achieved_at 2026-05-21 14:35 UTC; verified via SELECT post-apply" }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "backups/applied_migrations.json updated with migration 075 sha256:7c7f1016... applier=claude-via-mcp diagnose=3a7b9f" }
  - { tier: 6, name: edge_function_deploy, status: fixed_in_this_batch, evidence: "evaluate-rank-promotions deployed v7 (HTTP 201) + smoke OK; weekly-recalc deployed v16 (HTTP 201) + smoke OK; both archived under backups/edge_function_payloads/" }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "Cron `evaluate_rank_promotions` continues at 00:00 IST; new v7 will no-op for already-correct users. weekly-recalc cron remains Sunday." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "No RLS change — user_profile.current_rank_code already writable by service_role via Edge Function path." }
  - { tier: 10, name: secrets, status: verified, evidence: "No new Vault entries; existing service_role_key reused by evaluate-rank-promotions." }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/rank_no_demotion_behavioral_test.dart 9/9 passing; cloud verification of Upendra's user_profile post-migration shows SD1 + 2026-05-21 14:35 UTC restored." }
impact_analysis:
  callers_audited:
    - lib/core/services/rank_service.dart (RankService.evaluateAndPromote, getCurrentRank)
    - supabase/functions/evaluate-rank-promotions/index.ts (cron sync block)
    - supabase/functions/weekly-recalc/index.ts (c2 finding — total_workouts_done overwrite)
    - lib/features/home/screens/home_screen.dart:138 (_maybeShowPendingPromotion — reads pending promotion stamp; now only set when shouldPromote returns true)
    - lib/features/profile/repositories/rank_promotion_repository.dart:20-45 (rank_promotions reader — already monotonic per UNIQUE constraint)
    - lib/features/train/providers/train_provider.dart:1420 (client writer for total_workouts_done — increments +1 monotonically; unaffected)
  callers_updated_in_this_batch:
    - lib/core/services/rank_service.dart (extracted shouldPromote + replaced guard)
    - supabase/functions/evaluate-rank-promotions/index.ts (ordinal-compare guard around .update())
    - supabase/functions/weekly-recalc/index.ts (Math.max guard around total_workouts_done upsert)
    - docs/sot_registry.yaml (new concept rank_monotonic_current_code)
    - backups/applied_migrations.json (migration 075 entry)
  callers_unchanged:
    - lib/features/profile/repositories/rank_promotion_repository.dart — read-only on append-only table; no demotion possible
    - lib/core/services/stat_snapshot_service.dart — insert-only snapshot rows on promotion (no demotion path exists)
    - lib/core/services/badge_service.dart:32 — `tryUnlock` already guards with `!unlocked.containsKey(id.name)`; correctly monotonic by design (verified clean by c2 audit subagent)
---
# Body

## Why this was misdiagnosed pre-investigation

The natural first guess for "rank shows first rank after streak loss" would be
writer/reader drift in the field-name sense (the well-known recurring class
per `feedback_writer_reader_field_drift_recurring.md`). But field names
matched perfectly — `current_rank_code` is consistent across writer + reader.
The bug was a SEMANTIC mismatch between two cloud columns:

- `rank_promotions.rank_code` rows (event log, max-ever)
- `user_profile.current_rank_code` (denormalization, recomputed each eval)

Two columns disagreed on what "current rank" means. The reader picks the
denorm (because it's a single value, not a query-the-log). The writer
recomputes from current state. The two get out of sync the moment current
state drops below a previously-passed gate.

## Why this is a new bug class (debugging skill §2.19)

Existing catalog entries don't cover it:
- §2.1 (writer/reader field drift) — fields match here; semantic differs.
- §2.4 (partial unique arbiter) — unrelated.
- §2.10 (provider invalidation gaps) — provider IS invalidated; the value
  being written is just wrong.

The class is "monotonic-field-recompute demotion": a field that semantically
should only-increase (rank, lifetime workout count, longest streak, badge
unlock state, peak achievements) is unconditionally overwritten by a recompute
that returns a current-state ceiling. Defense pattern: any writer to a
monotonic field must guard `if (new > existing)` (or use SQL `GREATEST` /
`Math.max`).

Apply broadly to: rank, total_workouts_done, longest_streak, badge unlock
state, PR records, deployment counts. The c2 audit subagent found one
additional instance (weekly-recalc total_workouts_done) which is also fixed
in this batch. badge_service was verified clean by the audit.

## Why migration 075 uses historical achieved_at

Option b1 (chosen) — `current_rank_achieved_at` for the heal is read from
the matching `rank_promotions.achieved_at`, NOT `now()`. The profile rank
card UI renders "Promoted to SD1 · N days ago" using this timestamp;
stamping `now()` would have lied to the user (e.g. shown "Promoted to SD1
just now" when they actually earned it 6 days ago). The rank_promotions
event log is the truthful source; the heal restores truth, not a
re-stamping artifact.

## Why this affects only Upendra in production (sample size of one)

Production user count is small (founder + early invites). Only one user
crossed a sailor-track gate AND broke the streak below it AND got hit by
the recompute. Other users either:
- Never crossed SD2 → no demotion possible (already at floor)
- Are on officer track which uses completionRateMinimum, not streak gates
  (would still demote on completion rate drop, but no current officer-
  track users tested this path)

The bug was latent for every future user who breaks a streak gate post-
promotion. Migration 075 + the only-promote guards close it before
broader rollout.

## c2 audit follow-on shipped: weekly-recalc

`supabase/functions/weekly-recalc/index.ts` was overwriting
`user_progress.total_workouts_done` (a lifetime counter incremented by
client at train_provider.dart:1420) with the count of distinct workout
dates from `workout_log_exercises` over the LAST 4 WEEKS only. For any
user training longer than 4 weeks, this silently DECREASED the lifetime
counter every Sunday. Same class as rank demotion; same fix pattern
(monotonic guard via Math.max(recomputed, existing) per pre-fetched
chunk). Deployed as v16 with smoke OK.

`total_workouts_done` is currently read by `rank_service.dart:398` for
gate evaluation input (although no current kRankGates entry uses
`totalWorkoutsAtLeast`), AI snapshot building (`ai_snapshot_builder`),
and Mission Brief copy. None of those readers would have visibly broken
from a decrease today, but the class fix prevents the latent regression
once a totalWorkoutsAtLeast gate ships.

## Open question / next batch follow-up

The c2 audit flagged `user_progress.deployments_complete` (driver for
PO/CPO rank gates) as a P1 future risk — no writer exists today, but
when one ships (Plan A's W12 path per rank_service.dart:415-417 comment),
it MUST be only-increment. Adding to the deferred-class-watchlist; not
gated this batch because there's no writer to guard yet.
