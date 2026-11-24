---
bug_id: 8b1f3d
date: 2026-11-23
batch: oi348-walk-fixes Landing 2 (B8)
status: fixed
tier: full
blast_radius: platform
symptom: |
  OI-348 walk (AAB 1.0.0+50, 2026-11-22): a brand-new account, 0 sessions, got a coach "Promotion Day" chat message, a push and the full-screen celebration for Seaman 2 (SD2), the floor rung every account is given at sign-up. Live 2026-11-23: rank_promotions 48 SD2 rows (29 signup, 19 combined); ai_coach_interactions 27 tool_calls.kind='proactive_promotion' rows, ALL for SD2.
concept: rank_floor_never_announced
sot_registry_entry: rank_floor_never_announced
writers:
  - { file: lib/core/services/rank_service.dart, method_or_widget: "evaluateAndPromote: inserts every rung up to the qualified one, floor included (history); stamps the pending celebration inside the shouldPromote block, now behind shouldStampPromotionCelebration", line: 197 }
  - { file: supabase/functions/evaluate-rank-promotions/index.ts, method_or_widget: "cron: ranksUpTo(winner) minus existing -> upsert (floor included); one promotion_ceremony row per NEW code, now floor excluded", line: 336 }
  - { file: supabase/migrations/184_rank_floor_trigger_when.sql, method_or_widget: "trg_dispatch_proactive_coach_promotion AFTER INSERT FOR EACH ROW, now WHEN (NEW.rank_code <> 'SD2')", line: 42 }
readers:
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "_maybeShowPendingPromotion: reads + clears the stamp; pendingPromotionAction clearOnly for a floor stamp, else push PromotionCelebrationScreen", line: 222 }
  - { file: supabase/functions/proactive-coach-promotion/index.ts, method_or_widget: "handler: floor payload -> 200 {skipped: floor} before any client, prefs read, chat insert or push", line: 104 }
  - { file: lib/core/services/rank_ladder_data.dart, method_or_widget: "isFloorRank / shouldStampPromotionCelebration / pendingPromotionAction (the one floor rule, Dart)", line: 265 }
  - { file: supabase/functions/_shared/rank_engine.ts, method_or_widget: "isFloorRank (the one floor rule, TS)", line: 117 }
hive_key_prefix: "userBox pending_promotion_rank_code (unchanged key; a floor value is no longer written, and a stored one is cleared unshown)"
hive_key_formula: "n/a (single key)"
sync_methods: []
restore_methods: [_restoreRankPromotions]
cloud_table: rank_promotions
cloud_columns: [user_id, rank_code, trigger_type, achieved_at]
contract_test_path: test/contracts/rank_floor_never_announced_test.dart
ist_handling: ["none: no date logic changes"]
provider_invalidations: ["unchanged: RankService.onStateChanged still fires for null -> SD2 (app.dart invalidates userProfileProvider)"]
telemetry_op_types:
  success: [rank_promotion_pending_stamped, rank_promotion_celebration_shown]
  failure: [rank_service_pending_promotion_stamp]
cross_account_guard: "unchanged: the stamp lives in the per-user userBox; the EF and cron act per payload user_id."
forbidden_patterns_checked:
  - { pattern: "CREATE OR REPLACE FUNCTION private.dispatch_proactive_coach_promotion (would make the change catastrophic)", absent: true }
  - { pattern: "the definer phrase anywhere in migration 184's text (blast_radius_content_rules_lib.dart:37 escalates on text)", absent: true }
  - { pattern: "a floor check around the current_rank_code / Hive / onStateChanged writes (null -> SD2 must still move)", absent: true }
  - { pattern: "deps.isAuthorized in proactive-coach-promotion (auth must stay the literal isAuthorizedCronCall(req), cron_auth_adoption_test.dart:132-143)", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-walk-fixes-landing2.md (v4 CONVERGED, Unit B8; founder 2026-11-23: the starting rank is never announced, rows stay as history). One floor predicate per language (Dart isFloorRank in rank_ladder_data.dart, TS isFloorRank in _shared/rank_engine.ts); the SQL literal in migration 184 is pinned equal to both.
  1. Client: the pending-celebration stamp is skipped for the floor (shouldStampPromotionCelebration); current_rank_code, the Hive profile and onStateChanged still move null -> SD2.
  2. Home mirror: a floor stamp left by an older build is read, cleared, and never shown (no route, no "shown" event).
  3. Cron: no promotion_ceremony row for the floor; the previous-rank fallback is LADDER[0].code (was the literal "SD2"); a first run inserting SD2 + SD1 gives one ceremony, SD2 -> SD1.
  4. EF sink guard: proactive-coach-promotion returns 200 {ok, skipped: "floor"} after the payload check and before any client, read, write or push. New handler(req, deps) seam (deps = createAdmin, fetchPrefs, sendPush; auth stays direct; env read inside realDeps / the push; serve under import.meta.main).
  5. Trigger: migration 184 recreates the trigger with WHEN (NEW.rank_code <> 'SD2'), one transaction; the dispatch function is untouched.
  Existing rows and the 27 chat messages are left (history; testing accounts only, CLAUDE.md section 1).
regression_test_planned: |
  test/contracts/rank_floor_never_announced_test.dart (5 tests): pure seams (floor false, every higher rung true; none / clearOnly / clearAndCelebrate) and call-site pins (the stamp sits behind the gate inside the shouldPromote block while the rank writes sit before it; Home order read -> action -> clear -> clearOnly return -> shown event -> push).
  test/contracts/rank_floor_trigger_migration_test.dart (4, presence_only: the SQL runs only live): WHEN floor literal = Dart = TS first rung; drop before create inside BEGIN/COMMIT; no function created or altered; the file text never matches containsSecurityDefiner.
  Deno: evaluate-rank-promotions/index_test.ts (+3: floor-only user -> SD2 row and no ceremony; new SD1 user -> SD2 + SD1 rows and one ceremony opening "Recruit, " with "Promotion: Seaman 1st Class."; SD2 holder -> SD1 row and one ceremony); proactive-coach-promotion/index_test.ts (+3, the 8 existing kept: floor -> 200 skipped with no client, prefs read, chat row or push; SD1 -> one chat row + one push; unauthenticated floor -> 401).
  Live: test/sql/rank_floor_trigger_live_verify.sql (BEGIN ... ROLLBACK, borrows a floor-only account, deletes and re-inserts its SD2 row, inserts SD1, counts net.http_request_queue deltas).
mutation_proof: |
  Rule 21. scratchpad/mut_b8/run.sh: sed on the live file, grep -c of the mutated text, the test run, restore by cp and cmp (never git checkout). 13 of 13 red after one test tightening:
  Dart (rank_floor_never_announced_test): M1 shouldStamp... returns true; M2 returns false (the SD1 mirror case); M3 Home clearOnly return deleted; M7 the floor check widened over the whole shouldPromote block; M8 the stamp gate replaced by `if (true)` - all red.
  Deno: M4 cron floor filter deleted (red, 3 lines); M4b previous-rank fallback set to "SD1" SURVIVED the first test (it checked only the new rank) -> the test now asserts the ceremony opens "Recruit, " -> red; M4c fallback LADDER[2] red; M5 EF guard `if (false)` red; M5b TS isFloorRank pointed at the second rung red.
  Migration pins: M6 WHEN line deleted red; M6b WHEN literal 'SD1' red; M6c the definer phrase added to a comment red.
  Live (2026-11-23, BEGIN ... ROLLBACK, both runs verified rolled back: queue 0, 50 rows, 47 floor-only accounts after each): against the CURRENT binding floor_queued=1, sd1_queued=1 (the bug reproduced); with migration 184's DDL applied inside the transaction floor_queued=0, sd1_queued=1.
impact_analysis: |
  New accounts stop receiving a congratulation, a push and a celebration for the rank they are given; every real promotion (SD1 and above) is unchanged on all three channels. rank_promotions history, deployments counts, restore of the last 20 rows, migration 075's heal and current_rank_code are unchanged. A first weekly report no longer takes the CEREMONIAL tone from a floor ceremony row (weekly-report/index.ts:~443, intended). Old builds (AAB +50) still stamp the floor locally; the new Home reader clears such a stamp unshown, and once migration 184 is live no build's floor insert dispatches the coach EF.
announcer_sweep: |
  Swept 2026-11-23 by grep (promot / ceremon / celebrat / push / onesignal / insert / SnackBar / showDialog) with every hit read in context; each "reads rank state or history only, announces nothing" unless noted (the Profile record sheet and rank ladder list the floor row as HISTORY, intended): weekly-report/index.ts (CEREMONIAL tone keyed on a promotion_ceremony row: intended change above), daily-snapshot/index.ts, future-prediction/index.ts, _shared/captain_manual.ts, _shared/tools/progress/getPromotionStatus.ts, _shared/ceremony_text.ts (formatter only), restore-user-snapshot/index.ts (reads rows), ai_snapshot_builder.dart (eta_next_promotion), rank_ladder_screen.dart, progress_comparison_screen.dart, rank_service_record_sheet.dart, stat_snapshot_service.dart snapshotOnPromotion (a baseline row, not shown as news), simulation_service.dart (dev-only), coach_interaction_repository.dart (channel filter), sync_restore_completeness.dart (_restoreRankPromotions), promotion_history_provider.dart, rank_promotion_repository.dart, notification_settings_screen.dart (the toggle). The only stamp consumer is user_repository.dart (storage); only Home opens PromotionCelebrationScreen; RankService.onStateChanged is wired only in lib/app.dart.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "rank_ladder_data.dart (isFloorRank, shouldStampPromotionCelebration, pendingPromotionAction), rank_service.dart (stamp gate), home_screen.dart (clearOnly); 85 + 92 targeted tests green." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "pending_promotion_rank_code: no floor value written; a stored one is cleared unshown (pin)." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "Trigger binding only (migration 184); no table, column or function change." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "48 SD2 rows, 27 proactive_promotion chat rows all SD2 (read-only). Existing rows left as history." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "184 dry-run in BEGIN...ROLLBACK passed; applied 2026-11-24 after the founder go, cloud version 20261124012738; live trigger definition read back with the WHEN clause; backups/applied_migrations.json entry in the same commit." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "proactive-coach-promotion and evaluate-rank-promotions changed; deno check clean, Deno suites green; deploy of each pending a founder go, then the floor/SD1 smoke." }
  - { tier: 7, name: "Cron jobs", status: verified, evidence: "evaluate-rank-promotions schedule unchanged; only its ceremony loop changes." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "Env names unchanged; now read inside realDeps / the push instead of at module scope." }
  - { tier: 11, name: "External services", status: verified, evidence: "OneSignal call unchanged for SD1+; no push for the floor." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Live BEGIN...ROLLBACK: floor insert queues 0 dispatches with the new trigger, SD1 queues 1." }
recurrence: "Not a recurrence. Related: 9aa2c1 (celebration wiring, which made every stamped code celebrate), 8b1f33 (the proactive coach EF), 3a7b9f (monotonic rank; shouldPromote's null-as-minus-1 is why null -> SD2 counts as a promotion). New class: a rung the user is GIVEN treated as one they EARNED."
related_bugs: [9aa2c1, 8b1f33, 3a7b9f, f4b2c9]
---

# 8b1f3d - rank-floor-never-announced

## What happened
Every account holds the floor rung SD2 from sign-up. `shouldPromote(null, SD2)` is true (null is ordinal -1, diagnose 3a7b9f), so the client treated sign-up as a promotion and stamped a celebration; the cron inserted the floor with the rest of the ladder and wrote a ceremony for it; and the AFTER INSERT trigger posted every `rank_promotions` row, floor included, to `proactive-coach-promotion`, which wrote a "Promotion Day" chat message and sent a push.

## The fix
The floor stays in the history and is never news: no stamp, no Home celebration, no ceremony, no trigger dispatch, and a sink-side guard in the EF. See the frontmatter.

## Residual, stated
- The 27 existing SD2 chat messages and the 18 floor ceremony rows stay in the users' chat history (testing accounts only).
- AAB +50 keeps stamping the floor locally until the next build ships; the Home mirror in the new build clears it, the old build would still show it once.
- The floor literal exists in three places (Dart, TS, SQL); the contract test pins them equal. A change of the floor rung needs a new trigger migration.
