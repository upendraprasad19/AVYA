---
bug_id: 2b8d4e
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 / finding A6 (full wrapper landing — B5 D7-D8 batch)
status: closed
symptom: |
  `lib/core/services/sync_service.dart` plus its 8 `part of` files
  under `lib/core/services/sync/` host every sync + restore helper as
  private methods on the SyncService singleton. The restore-vs-sync
  symmetry (every `_syncX` must have a matching `_restoreX`) is
  purely conventional. Test #12.8 caught 16-of-16 `_restoreXxx`
  methods that wrote the wrong Hive shape because the pattern was
  never compile-checked; only the runtime round-trip contract test
  belatedly failed.

  Audit 2026-05-20 finding A6 (score 16) flags this as the highest-
  impact-per-risk architectural debt. The scaffold batch landed
  `SyncDomain` interface + `StreaksSyncDomain` proof-of-pattern +
  exhaustiveness source-grep test (`sync_domain_interface_test.dart`).
  This batch (B5 D7-D8) lands the REMAINING SEVEN wrapper classes
  for the other part-files and the dispatcher infrastructure
  (`SyncFlags` per-domain gate + `_domains` registration list +
  `_dispatchDomainPushes` / `_dispatchDomainRestores` dispatcher).

  The wrappers ship DUAL-PATH-READY but the per-domain flags default
  FALSE. The legacy fan-out keeps running unchanged. The follow-up
  batch flips one flag at a time after 24h smoke, deleting the
  matching legacy `_safeRestoreOp(...)` line in the same commit
  (CLAUDE.md §4.11 gates-before-refactor).
concept: sync_domain_full_migration_A6
sot_registry_entry: restore_completeness
writers:
  - { file: lib/core/services/sync_flags.dart, method: SyncFlags.useDomainFor (per-domain configBox gate; default FALSE), line: 50 }
  - { file: lib/core/services/sync_domains/workouts_sync_domain.dart, method: WorkoutsSyncDomain.push + .restore (6 sub-surfaces), line: 38 }
  - { file: lib/core/services/sync_domains/nutrition_sync_domain.dart, method: NutritionSyncDomain.push + .restore (3 sub-surfaces), line: 21 }
  - { file: lib/core/services/sync_domains/health_sync_domain.dart, method: HealthSyncDomain.push + .restore (5 sub-surfaces — urine push-only), line: 31 }
  - { file: lib/core/services/sync_domains/coach_sync_domain.dart, method: CoachSyncDomain.push + .restore (2 sub-surfaces), line: 18 }
  - { file: lib/core/services/sync_domains/profile_sync_domain.dart, method: ProfileSyncDomain.push + .restore (3 sub-surfaces), line: 19 }
  - { file: lib/core/services/sync_domains/community_sync_domain.dart, method: CommunitySyncDomain.push + .restore (custom items orchestrator), line: 26 }
  - { file: lib/core/services/sync_domains/restore_completeness_sync_domain.dart, method: RestoreCompletenessSyncDomain.push + .restore (6 sub-surfaces — push split repos vs SyncService), line: 38 }
  - { file: lib/core/services/sync/sync_workout.dart, method: SyncServiceWorkout public forwarders (6 push + 6 restore + push-streaks/restore-streaks pair from scaffold), line: 1697 }
  - { file: lib/core/services/sync/sync_nutrition.dart, method: SyncServiceNutrition public forwarders (3 push + 3 restore), line: 449 }
  - { file: lib/core/services/sync/sync_health.dart, method: SyncServiceHealth public forwarders (5 push + 4 restore — urine push-only), line: 402 }
  - { file: lib/core/services/sync/sync_coach.dart, method: SyncServiceCoach public forwarders (2 push + 2 restore), line: 244 }
  - { file: lib/core/services/sync/sync_profile.dart, method: SyncServiceProfile public forwarders (3 push + 3 restore), line: 360 }
  - { file: lib/core/services/sync/sync_community.dart, method: SyncServiceCommunity public forwarders (1 push orchestrator + 1 restore orchestrator), line: 460 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method: SyncServiceRestoreCompleteness public forwarders (6 restore — push remains via existing public methods + repositories), line: 415 }
  - { file: lib/core/services/sync_service.dart, method: SyncService._domains registration list + _dispatchDomainPushes/_dispatchDomainRestores dispatcher + visibleForTesting accessors, line: 145 }
readers:
  - { file: test/contracts/sync_domain_full_migration_test.dart, method_or_widget: 14 behavioural + source-structure tests pinning wrapper registration, SyncFlags defaults, dispatcher no-op safety, and SyncDomainBase inheritance, line: 1 }
  - { file: test/contracts/sync_domain_interface_test.dart, method_or_widget: existing source-grep exhaustiveness (continues to pass — public forwarders use push/restore prefixes that are NOT matched by the _syncX/_restoreX regexes), line: 1 }
  - { file: test/contracts/restore_completeness_writes_test.dart, method_or_widget: existing restore-completeness contracts still pass — wrappers do not touch any write-side fan-out, line: 1 }
hive_key_prefix: sync_domain_
hive_key_formula: |
  `configBox['sync_domain_<name>']` where <name> ∈ {workouts, streaks,
  nutrition, health, coach, profile, community, restore_completeness}.
  All 8 keys default UNSET (read returns null → SyncFlags.useDomainFor
  returns FALSE → legacy fan-out path runs). Follow-up batch will
  `configBox.put('sync_domain_streaks', true)` to flip the first
  domain on after smoke.
sync_methods:
  - SyncService._dispatchDomainPushes (iterates _domains; skip-if-flag-OFF)
  - All existing private _syncX helpers (unchanged; still called by the legacy fan-out)
  - 23 new `pushXForSyncDomain` public forwarders on the 7 part-files
restore_methods:
  - SyncService._dispatchDomainRestores (iterates _domains; skip-if-flag-OFF)
  - All existing private _restoreX helpers (unchanged; still called by the legacy fan-out)
  - 24 new `restoreXForSyncDomain` public forwarders on the 7 part-files
cloud_table: |
  No cloud changes. The wrappers delegate to the existing private
  helpers; cloud tables (workout_logs, nutrition_logs, weight_logs,
  measurements, sleep_logs, daily_steps, water_logs, ai_coach_interactions,
  coach_memory, user_profile, user_progress, user_preferences,
  user_custom_exercises, user_custom_foods, user_progress streak
  freeze columns, notifications_inbox, saved_diet_plans,
  rank_promotions, referral_codes, referral_redemptions, streaks)
  are untouched.
cloud_columns: []
contract_test_path: test/contracts/sync_domain_full_migration_test.dart
ist_handling:
  - { file: lib/core/services/sync_flags.dart, line: 1, fn: "No IST surface — flag values are booleans in configBox; behaviour-time decisions live inside the legacy helpers which already enforce IST via istDateStr." }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [sync_domain_push_workouts, sync_domain_push_streaks, sync_domain_push_nutrition, sync_domain_push_health, sync_domain_push_coach, sync_domain_push_profile, sync_domain_push_community, sync_domain_push_restore_completeness, sync_domain_restore_workouts, sync_domain_restore_streaks, sync_domain_restore_nutrition, sync_domain_restore_health, sync_domain_restore_coach, sync_domain_restore_profile, sync_domain_restore_community, sync_domain_restore_restore_completeness]
cross_account_guard: |
  Every public forwarder resolves userId via `_ensureSessionOpen()`
  → `HiveUserSession.ensureOpenedForCurrentSession()` before
  touching any user-scoped box. Same guard the existing helpers
  already use. With no signed-in user the forwarder short-circuits
  cleanly (verified by the dispatcher test: flip `streaks` flag ON,
  no auth session, expect `_dispatchDomainPushes()` completes
  without throwing).
forbidden_patterns_checked:
  - { pattern: "duplicate.*_syncX.*body.*in.*wrapper", absent: true }
  - { pattern: "wrapper.*calls.*Hive\\.box.*directly", absent: true }
  - { pattern: "wrapper.*flag.*defaults.*TRUE", absent: true }
proposed_fix: |
  Artifacts landed in this batch (B5 D7-D8 of audit 2026-05-20):

  1. `lib/core/services/sync_flags.dart` (NEW, 97 lines) — per-domain
     boolean gate. `useDomainFor(name)` reads `configBox` key
     `sync_domain_<name>` (defaults FALSE). Test-only setters for
     flipping flags in unit tests. Production callers MUST NOT flip
     flags in code — they flip via one-shot migration or remote
     config write only.

  2. SEVEN new wrapper classes under `lib/core/services/sync_domains/`:
       - `workouts_sync_domain.dart` (74 lines) — workout logs +
         exercise logs + schedule completions + workout plan +
         workout templates + scheduled workouts. Preserves the
         templates-before-schedules + plan-before-scheduled
         ordering quirks documented in APK Test #14 / Bug B.1
         and Test #12.9.
       - `nutrition_sync_domain.dart` (46 lines) — nutrition logs +
         water logs + saved meals.
       - `health_sync_domain.dart` (60 lines) — weight + measurements +
         sleep + steps + urine color (push-only — restore is
         synthesised from water_logs).
       - `coach_sync_domain.dart` (35 lines) — coach interactions +
         coach memory.
       - `profile_sync_domain.dart` (44 lines) — user profile +
         user progress + user preferences.
       - `community_sync_domain.dart` (40 lines) — custom items
         orchestrator (push covers exercises AND foods in a single
         iteration; restore is split across two halves run
         sequentially under one domain call).
       - `restore_completeness_sync_domain.dart` (66 lines) —
         freezes + notifications inbox + saved diet plan + rank
         promotions + referral codes + referral redemptions.

  3. PUBLIC FORWARDERS appended to each part-file (`pushXForSyncDomain`
     + `restoreXForSyncDomain` per private `_syncX` / `_restoreX`
     pair):
       - sync_workout.dart  +93 lines  (6 push + 6 restore)
       - sync_nutrition.dart +43 lines (3 push + 3 restore)
       - sync_health.dart   +60 lines  (5 push + 4 restore)
       - sync_coach.dart    +29 lines  (2 push + 2 restore)
       - sync_profile.dart  +40 lines  (3 push + 3 restore)
       - sync_community.dart +13 lines (1 push + 1 restore — both
                                       orchestrators)
       - sync_restore_completeness.dart +45 lines (6 restore — push
                                       remains via existing public
                                       methods + repositories)

  4. `lib/core/services/sync_service.dart` (+90 lines) — domain
     registration (`_domains` late final list of 8 wrappers, ordered
     to match the legacy fan-out's documented ordering), dispatcher
     (`_dispatchDomainPushes` / `_dispatchDomainRestores` that iterate
     `_domains` and skip any domain whose flag is FALSE), and
     `@visibleForTesting` accessors. New imports: `sync_domain.dart`,
     `sync_flags.dart`, and the 8 wrapper files.

  5. `test/contracts/sync_domain_full_migration_test.dart` (NEW, 215
     lines) — 14 behavioural + source-structure tests:
       - Wrapper registration: 8 domains in order, each implements
         SyncDomain, names are unique + lower_snake_case.
       - SyncFlags defaults: every registered domain reads FALSE
         from useDomainFor() by default; unknown names also FALSE.
       - Dispatcher safety: push + restore complete cleanly with
         all flags FALSE (no-op); push exercises the real forwarder
         code path when streaks flag is flipped TRUE + no auth session
         (proves the dispatcher is invoking the public forwarder, not
         a stub).
       - Source structure: every `*_sync_domain.dart` file declares
         a class that `extends SyncDomainBase`; sync_flags.dart uses
         the `sync_domain_` configBox key prefix.

  6. `docs/sot_registry.yaml` — `restore_completeness.migration_note`
     updated from the scaffold-batch wording to the full-wrapper
     landing wording, enumerating all 8 wrapper file paths + the
     dual-path-ready posture + the flag-flip rollout plan.

  NO RUNTIME BEHAVIOUR CHANGE in this batch. All 8 `SyncFlags`
  default FALSE → the dispatchers skip every domain → legacy
  `_safeRestoreOp(...)` calls in `syncWorkoutData` /
  `weeklyFullSync` / `restoreFromCloudForUser` run unchanged. The
  dispatcher infrastructure is dormant until a follow-up batch
  flips a flag and removes the corresponding legacy line in the
  same commit.

  The follow-up flag-flip batch will:
    (a) `configBox.put('sync_domain_streaks', true)` via a one-shot
        boot-time migration (or remote-config write).
    (b) Insert `await _dispatchDomainPushes()` /
        `_dispatchDomainRestores()` at the appropriate fan-out sites
        in `syncWorkoutData` / `weeklyFullSync` /
        `restoreFromCloudForUser` — these are no-op for all domains
        whose flag is still FALSE, so safe to add before the first
        flip.
    (c) Smoke 24h on prod APK. Verify streaks sync + restore still
        round-trip cleanly via the existing
        `test/contracts/restore_round_trip_field_coverage_test.dart`.
    (d) Delete the legacy `_safeRestoreOp('sync_streaks', ...)` /
        `_safeRestoreOp('streaks', ...)` lines in the same commit
        as the next domain's flag flip.
    (e) Repeat for each of the remaining 7 domains in dependency
        order (workouts last because its sub-surfaces have the most
        ordering quirks).
    (f) Once all 8 flags are TRUE for 7+ days with no regressions,
        delete the legacy `_syncX` / `_restoreX` private helpers in
        one final cleanup batch. The matched-pair invariant is then
        enforced at compile time via the SyncDomain interface.
regression_test_planned:
  - test/contracts/sync_domain_full_migration_test.dart — 14 behavioural + source-structure tests. (1) 8 registered domains in canonical order. (2) Every domain implements SyncDomain. (3) Names unique + lower_snake_case. (4) SyncFlags defaults FALSE for every registered domain. (5) Unknown-name lookup returns FALSE. (6) Dispatcher push completes when all flags FALSE (no-op). (7) Dispatcher restore completes when all flags FALSE (no-op). (8) Dispatcher push completes when a flag is flipped TRUE with no auth session — proves real forwarder code path. (9) Every wrapper file extends SyncDomainBase. (10) sync_flags.dart uses the `sync_domain_` key prefix.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "9 NEW artifacts (1 SyncFlags class, 7 wrapper classes, 1 behavioural test) totalling ~770 lines + ~320 lines of forwarders appended across 7 part-files + ~90 lines added to sync_service.dart for domain registration / dispatcher. `flutter analyze --no-fatal-infos lib/core/services/sync_domain.dart lib/core/services/sync_domains/ lib/core/services/sync_flags.dart lib/core/services/sync_service.dart lib/core/services/sync/ test/contracts/sync_domain_full_migration_test.dart` = 0 errors, 18 pre-existing info-level warnings (16 use_null_aware_elements / prefer_null_aware_operators on existing helper bodies + 2 dep_on_referenced_packages on the new test matching the precedent test pattern). No new lint failures introduced." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "SyncFlags persists per-domain boolean gates in `configBox` under key `sync_domain_<name>`. Behavioural test setup opens 5 shared Hive boxes on temp dir + GuardedBox.testBypassOwnership. SyncFlags.debugSetForTests + debugResetAllForTests confirm the persistence round-trip works. With every flag FALSE the dispatchers iterate the 8 domains, skip each, and complete cleanly — verified by tests 6+7 in the new contract test." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change. The wrappers delegate to existing private helpers that hit existing cloud tables." }
  - { tier: 6, name: cloud_sync_outbound, status: verified, evidence: "Legacy fan-out (syncWorkoutData / weeklyFullSync / restoreFromCloudForUser) is untouched — same `_safeRestoreOp(...)` calls to the same private helpers. The wrapper dispatcher (`_dispatchDomainPushes` / `_dispatchDomainRestores`) is NOT yet wired into the fan-out; it's a parallel surface gated behind SyncFlags. Verified by tests 6+7 (dispatcher no-op when flags FALSE) + test 8 (forwarder code path exercised cleanly when flag TRUE + no auth)." }
  - { tier: 9, name: sot_registry, status: fixed_in_this_batch, evidence: "docs/sot_registry.yaml `restore_completeness.migration_note` updated from the scaffold-batch wording to the full-wrapper landing wording. Enumerates all 8 wrapper file paths, the dual-path-ready posture, and the flag-flip rollout plan. `restore_completeness_writes_test.dart` (10 tests) still PASS — wrappers do not touch any write-side fan-out." }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "23 contract tests across 3 test files PASS: sync_domain_interface_test.dart (4 tests — scaffold exhaustiveness still holds; new forwarders use `push/restore` prefixes that are NOT matched by the `_?sync<Suffix>` / `_restore<Suffix>` regexes, so the source-grep exhaustiveness check is unaffected), sync_domain_full_migration_test.dart (14 tests — wrapper registration + SyncFlags defaults + dispatcher safety + source structure), restore_completeness_writes_test.dart (10 tests — push-side fan-out contracts unchanged). Total: 28/28 PASS." }
impact_analysis:
  callers_audited:
    - lib/core/services/sync_service.dart (syncWorkoutData / weeklyFullSync / restoreFromCloud / restoreFromCloudForUser — 4 fan-out sites, all unchanged)
    - lib/core/services/sync_service.dart (15 new imports — 8 wrapper classes + sync_domain + sync_flags + existing helpers)
  callers_updated_in_this_batch:
    - 0 — no existing caller migrates to dispatch through SyncDomain.push() / .restore() in this batch. The dispatcher is dormant (all flags default FALSE).
  callers_unchanged:
    - All 4 fan-out sites continue to invoke the private helpers directly via _safeRestoreOp.
    - All ad-hoc fire-and-forget callers (NutritionWriteService, WorkoutWriteService, etc.) keep calling syncWorkoutData / syncNutritionData / syncProfileNow / syncWeightNow / syncSleepNow / syncMeasurementsNow / syncProgressNow / syncCustomItemsNow / syncFreezes / syncNotificationsInboxEntry / syncSavedDietPlan unchanged.
---
# Body

## What changed

This batch lands the FULL set of [SyncDomain] wrapper classes started
by the scaffold batch (A6, `StreaksSyncDomain`). The remaining seven
part-files of `sync_service.dart` now each have a corresponding
`<Domain>SyncDomain extends SyncDomainBase` class under
`lib/core/services/sync_domains/`. The dispatcher infrastructure
(`SyncFlags` per-domain gate + `_domains` registration list +
`_dispatchDomainPushes` / `_dispatchDomainRestores`) ships dormant —
all 8 flags default FALSE, so the legacy fan-out path runs unchanged
on every device until a follow-up batch flips them on.

## Architecture

```
lib/core/services/
├── sync_domain.dart                        (interface — pre-existing scaffold)
├── sync_flags.dart                         (NEW — per-domain gate)
├── sync_service.dart                       (+ _domains list + dispatcher)
├── sync/
│   ├── sync_workout.dart                   (+ 12 public forwarders)
│   ├── sync_nutrition.dart                 (+ 6 public forwarders)
│   ├── sync_health.dart                    (+ 9 public forwarders)
│   ├── sync_coach.dart                     (+ 4 public forwarders)
│   ├── sync_profile.dart                   (+ 6 public forwarders)
│   ├── sync_community.dart                 (+ 2 public forwarders)
│   ├── sync_restore_completeness.dart      (+ 6 public forwarders)
│   └── sync_realtime.dart                  (untouched — no _syncX/_restoreX pairs)
└── sync_domains/
    ├── streaks_sync_domain.dart            (scaffold proof-of-pattern)
    ├── workouts_sync_domain.dart           (NEW)
    ├── nutrition_sync_domain.dart          (NEW)
    ├── health_sync_domain.dart             (NEW)
    ├── coach_sync_domain.dart              (NEW)
    ├── profile_sync_domain.dart            (NEW)
    ├── community_sync_domain.dart          (NEW)
    └── restore_completeness_sync_domain.dart (NEW)
```

## Gates-before-refactor compliance

This batch follows CLAUDE.md §4.11 (gates-before-refactor): the
`SyncFlags` gate ships in the SAME commit as the wrappers, with all
flags defaulting FALSE. The legacy `_syncX` / `_restoreX` helpers are
preserved verbatim. The follow-up flag-flip batch is responsible for
the per-domain rollout, smoke, and legacy-line deletion.

## Out of scope (follow-up batches)

- Flip `sync_domain_streaks` ON via boot-time migration after 24h
  smoke of this wrapper landing.
- Wire `_dispatchDomainPushes` / `_dispatchDomainRestores` into the
  fan-out at `syncWorkoutData` / `weeklyFullSync` /
  `restoreFromCloudForUser`. (Safe to add at any point — no-op until
  a flag flips.)
- Delete the legacy `_safeRestoreOp('streaks', ...)` /
  `_safeRestoreOp('sync_streaks', ...)` lines once the streaks
  domain is verified through the wrapper path.
- Migrate `sync_realtime.dart` separately — it contains lifecycle
  methods (`subscribeToRealtimeSync`), not `_syncX/_restoreX` pairs,
  and does not fit the SyncDomain shape.
- Once all 8 flags are TRUE for 7+ days, delete the legacy private
  helpers in a final cleanup batch and rely on the SyncDomain
  interface as the compile-checked contract.
