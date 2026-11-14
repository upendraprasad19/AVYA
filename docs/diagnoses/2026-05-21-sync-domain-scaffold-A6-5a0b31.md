---
bug_id: 5a0b31
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 / finding A6 (scaffold step — PARTIAL CLOSE)
status: partial
symptom: |
  `lib/core/services/sync_service.dart` (1395 lines) plus 8 `part of`
  files under `lib/core/services/sync/` (5577 lines total) host every
  sync + restore helper as private methods on a single `SyncService`
  singleton. The restore-vs-sync symmetry — every `_syncXxx` must
  have a matching `_restoreXxx` — was only enforced by the bolted-on
  `sync/sync_restore_completeness.dart` part-file plus a runtime
  contract test (`test/contracts/restore_round_trip_field_coverage_test.dart`).

  Test #12.8 caught 16-of-16 `_restoreXxx` methods that wrote the
  wrong Hive shape because the pattern was purely conventional:
  "write a `_syncX` and remember to also write `_restoreX`." There
  was no compile-checked contract; the part-files share intricate
  state via private members on the SyncService class, so a missing
  restore counterpart compiled cleanly until the round-trip test
  belatedly failed.

  Audit 2026-05-20 finding A6 (score 16) flags this as the highest-
  impact-per-risk architectural debt in the SyncService surface.
  A full part-file → independent-class migration is too risky in
  one batch (5577 lines, 8 part-files, intricate cross-domain state
  sharing). This batch lands the SCAFFOLD that proves the
  destination pattern works without disturbing the live call graph.
concept: sync_domain_interface_scaffold_A6
sot_registry_entry: restore_completeness
writers:
  - { file: lib/core/services/sync_domain.dart, method: SyncDomain interface declaration + SyncDomainBase mixin, line: 65 }
  - { file: lib/core/services/sync_domains/streaks_sync_domain.dart, method: StreaksSyncDomain.push + .restore (delegators), line: 44 }
  - { file: lib/core/services/sync/sync_workout.dart, method: SyncServiceWorkout.pushStreaksForSyncDomain + restoreStreaksForSyncDomain (public forwarders for the private _syncStreaks + _restoreStreaks helpers), line: 833 }
readers:
  - { file: test/contracts/sync_domain_interface_test.dart, method_or_widget: StreaksSyncDomain behavioural verification + _syncX/_restoreX exhaustiveness source-grep, line: 81 }
hive_key_prefix: streaks
hive_key_formula: "healthBox['streaks'] is a List<Map> keyed off cloud table `streaks` via (user_id, week_start). The scaffold does not change the key shape — it wraps the existing _syncStreaks/_restoreStreaks logic."
sync_methods: [SyncService._syncStreaks, SyncService.pushStreaksForSyncDomain, StreaksSyncDomain.push]
restore_methods: [SyncService._restoreStreaks, SyncService.restoreStreaksForSyncDomain, StreaksSyncDomain.restore]
cloud_table: streaks
cloud_columns: [id, user_id, week_start, workouts_planned, workouts_completed, is_streak_maintained, created_at]
contract_test_path: test/contracts/sync_domain_interface_test.dart
ist_handling:
  - { file: lib/core/services/sync/sync_workout.dart, line: 463, fn: "_syncStreaks keys streaks rows on `week_start` (string ISO date). IST handling is inherited from the existing helper; the scaffold does not move the IST surface." }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [sync_streaks, restore_streaks]
cross_account_guard: |
  StreaksSyncDomain delegates to SyncService.pushStreaksForSyncDomain
  / restoreStreaksForSyncDomain, which call _ensureSessionOpen() →
  HiveUserSession.ensureOpenedForCurrentSession() before touching
  the user-scoped healthBox. Cross-account writes blocked at the
  GuardedBox layer (HiveUserSession + GuardedBox.testBypassOwnership
  reset between tests).
forbidden_patterns_checked:
  - { pattern: "_syncStreaks.*public", absent: true }
  - { pattern: "duplicate.*streaks.*logic", absent: true }
proposed_fix: |
  Three artifacts land in this scaffold batch:

  1. `lib/core/services/sync_domain.dart` (NEW, 100 lines) — the
     `SyncDomain` interface (`name`, `push()`, `restore()`,
     `pushSnapshot()`) plus a `SyncDomainBase` abstract class that
     supplies a no-op `pushSnapshot()` default. The interface
     declaration captures the symmetric push/restore contract that
     SyncService has historically enforced by convention only.

  2. `lib/core/services/sync_domains/streaks_sync_domain.dart`
     (NEW, 67 lines) — `StreaksSyncDomain extends SyncDomainBase`
     wrapping the existing `_syncStreaks` + `_restoreStreaks`
     private methods via two new public forwarders on the
     `SyncServiceWorkout` extension. The wrapper is a thin facade —
     the part-file remains the source of truth, the wrapper just
     exposes the symmetric public surface SyncDomain demands.

  3. `lib/core/services/sync/sync_workout.dart` (+30 lines, no
     behavioural change to existing methods) — two new public
     methods on the SyncServiceWorkout extension:
       * `pushStreaksForSyncDomain()` resolves userId via
         `_ensureSessionOpen()` and delegates to `_syncStreaks(userId)`.
       * `restoreStreaksForSyncDomain()` resolves userId via
         `_ensureSessionOpen()` and delegates to `_restoreStreaks(userId)`.
     The forwarders preserve the zero-arg `Future<void>` shape the
     SyncDomain interface demands while keeping `_ensureSessionOpen`
     as the single auth gate.

  Streaks was chosen as the first proof-of-pattern because the pair
  is the smallest contained `_syncX` / `_restoreX` duo in the
  codebase (45 + 53 lines respectively), uses one Hive list +
  one cloud table + one onConflict key, and has no cross-domain
  transactional dependency.

  SoT registry: `restore_completeness` concept gains a top-level
  `migration_note:` block documenting the SyncDomain interface as
  the destination shape and pointing at the first wrapper.

  Why this scaffold and not a full split: 5577 lines × 8 part-files
  × intricate shared private state means a one-batch full migration
  is the textbook recipe for a `part_of` → top-level conversion
  drift bug. The scaffold pattern lets each follow-up batch migrate
  ONE part-file at a time, with the SyncDomain interface as the
  invariant the migration converges on.

  PARTIAL CLOSE — A6 stays open. The audit closure YAML entry
  records "scaffold landed; 8 part-files still pending migration in
  follow-up batches" so the score-16 finding doesn't drop off the
  audit ledger.
regression_test_planned:
  - test/contracts/sync_domain_interface_test.dart — BEHAVIOURAL on real Hive temp dir. (1) StreaksSyncDomain implements SyncDomain (isA + name field). (2) push() returns Future<void> and completes without throwing when no auth session is open — exercises the real public-forwarder code path through `_ensureSessionOpen()` short-circuit. (3) Same for restore(). (4) Source-grep exhaustiveness — every `_syncX` private declaration in `sync_service.dart` + part-files has a matching `_restoreX` declaration (or appears on a documented push-only allowlist with the rationale captured inline). The exhaustiveness check is the structural guard that catches the Test #12.8 drift class — "added a _syncBar without _restoreBar" now fails CI instead of waiting for the next reinstall to round-trip into the bug.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "3 new artifacts: lib/core/services/sync_domain.dart (100 lines, SyncDomain interface + SyncDomainBase mixin); lib/core/services/sync_domains/streaks_sync_domain.dart (67 lines, first proof-of-pattern wrapping _syncStreaks + _restoreStreaks); test/contracts/sync_domain_interface_test.dart (293 lines, 4 BEHAVIOURAL tests). 1 surgical addition to lib/core/services/sync/sync_workout.dart (30 lines: two public forwarders for the existing private streak helpers; zero edits to the helpers themselves). flutter analyze --no-fatal-infos on all 3 touched files: only pre-existing info-level dependency-allowlist warnings (identical to the precedent test sync_fanout_workout_domain_behavioral_test.dart), no errors." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Behavioural test setup opens 5 shared Hive boxes on temp dir + GuardedBox.testBypassOwnership. With no signed-in user, `_ensureSessionOpen()` returns null and the public forwarders short-circuit — exercises the real call path, not a stub. Test asserts Future<void> completes cleanly through both push() and restore()." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change. The cloud `streaks` table (id, user_id, week_start, workouts_planned, workouts_completed, is_streak_maintained, created_at) is touched by the EXISTING _syncStreaks/_restoreStreaks helpers; the wrapper does not alter the payload." }
  - { tier: 6, name: cloud_sync_outbound, status: verified, evidence: "SyncService.syncWorkoutData (sync_service.dart:545) and SyncService.restoreFromCloudForUser (sync_service.dart:761,885) keep calling _syncStreaks / _restoreStreaks directly via the existing _safeRestoreOp wrappers. The new StreaksSyncDomain class is an ADDITIONAL surface — not yet wired into the fan-out — proving the wrapper compiles and works in isolation before migration begins." }
  - { tier: 9, name: sot_registry, status: fixed_in_this_batch, evidence: "docs/sot_registry.yaml — added `migration_note:` block under the `restore_completeness` concept documenting the SyncDomain destination pattern and pointing at the streaks proof-of-pattern. scripts/check_reader_manifest_complete.dart PASS (phase-1 30 forbidden patterns + phase-2 25 manifest-complete concepts)." }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "All 4 behavioural tests in test/contracts/sync_domain_interface_test.dart PASS. The exhaustiveness test source-greps both the root sync_service.dart and every part-file under lib/core/services/sync/ via the existing _sync_service_source.dart facade (anchored 2026-05-13). The current source has 31 `_syncX` declarations and 28 `_restoreX` declarations; 22 match by exact suffix, 6 fall on the documented push-only allowlist (WorkoutData/NutritionData orchestrators, HealthDataSnapshot, UrineColorLogs deferred, FitnessSummary misnamed-pull, CustomItems multi-domain orchestrator), and 11 fall on the documented restore-only allowlist (orchestrator guards plus public-push-named counterparts like syncCoachMemoryNow ↔ _restoreCoachMemory)." }
impact_analysis:
  callers_audited:
    - lib/core/services/sync_service.dart:545 (syncWorkoutData fan-out site for _syncStreaks — unchanged)
    - lib/core/services/sync_service.dart:761 (restoreFromCloudForUser site for _restoreStreaks — unchanged)
    - lib/core/services/sync_service.dart:885 (restoreFromCloudForUser second site — unchanged)
  callers_updated_in_this_batch:
    - 0 — the scaffold is additive. No existing caller migrates from `_syncStreaks(userId)` to `StreaksSyncDomain().push()` in this batch; that switch lands in a follow-up batch alongside the second part-file migration (so the dispatcher can be tested with at least two real domains).
  callers_unchanged:
    - All 3 fan-out sites continue to invoke the private helpers directly. The new wrapper exists alongside the legacy call graph; once 2+ domains are wrapped, SyncService can adopt a `List<SyncDomain>` dispatcher and the legacy sites delete in one go.
---
# Body

## What changed

Scaffold artifact for the multi-batch SyncService extraction. The
`SyncDomain` interface is the destination shape every part-file
migrates to; this batch lands the interface + one proof-of-pattern
wrapper + the source-grep exhaustiveness gate. No existing call
site moves.

| Artifact | Lines | Role |
|---|---|---|
| `lib/core/services/sync_domain.dart` | 100 | `SyncDomain` interface (`name`, `push`, `restore`, `pushSnapshot`) + `SyncDomainBase` mixin with no-op `pushSnapshot` default. |
| `lib/core/services/sync_domains/streaks_sync_domain.dart` | 67 | `StreaksSyncDomain extends SyncDomainBase` — first proof-of-pattern. Wraps `_syncStreaks` + `_restoreStreaks` via public forwarders. |
| `lib/core/services/sync/sync_workout.dart` (+30 lines) | — | Two new public methods on the existing `SyncServiceWorkout` extension: `pushStreaksForSyncDomain` + `restoreStreaksForSyncDomain`. Both resolve userId via `_ensureSessionOpen()` then delegate to the private helpers. |
| `test/contracts/sync_domain_interface_test.dart` | 293 | 4 behavioural + source-grep tests. The exhaustiveness check is the structural guard that catches the Test #12.8 drift class. |
| `docs/sot_registry.yaml` (+22 lines) | — | `migration_note:` block under `restore_completeness` documenting the destination pattern. |

## Why streaks first

The streaks pair is the smallest contained `_syncX` / `_restoreX`
duo in the codebase (45 + 53 lines respectively), uses one Hive
list + one cloud table + one onConflict key, has no cross-domain
transactional dependency, no template ordering quirk, no rate-limit
interplay. Ideal scaffold target — proves the wrapper pattern works
without surface-area noise.

## Why this is a PARTIAL CLOSE for A6

A6 (score 16) flags 8 part-files of asymmetric restore/sync. This
batch lands the interface + 1 of 9 domains. The remaining 8 part
files (`sync_workout.dart` minus streaks, `sync_nutrition.dart`,
`sync_health.dart`, `sync_coach.dart`, `sync_profile.dart`,
`sync_community.dart`, `sync_realtime.dart`,
`sync_restore_completeness.dart`) still need migration in follow-up
batches. The audit closure YAML keeps A6 open with a note pointing
here.

## What the exhaustiveness test catches

The source-grep test in `sync_domain_interface_test.dart` reads the
aggregated SyncService source (root + every part-file via the
existing `_sync_service_source.dart` facade), strips comments, and
asserts that every `_syncX` private declaration has a matching
`_restoreX` declaration (or sits on an explicitly-documented
allowlist). The Test #12.8 drift class — "added a `_syncBar`
without `_restoreBar`" — now fails CI instead of waiting for the
next reinstall round-trip to surface the regression.

Two allowlists capture the legitimate asymmetries:
- **PUSH-ONLY** (6 entries): orchestrators (`WorkoutData`,
  `NutritionData`, `CustomItems`), one-way push surfaces
  (`HealthDataSnapshot`), misnamed pulls (`FitnessSummary`), and
  deferred items (`UrineColorLogs`).
- **RESTORE-ONLY** (11 entries): orchestrator guards (`IfNeeded`,
  `FromCloudForUser`) and domains where the push counterpart uses a
  different naming convention — public methods like `syncFreezes`,
  `syncSavedDietPlan`, `syncCoachMemoryNow`, or per-entry pushes
  like `syncNotificationsInboxEntry`.

Each entry carries an inline comment naming why it's exempt. New
entries require the same justification; otherwise the test fails.

## Gate status

| Gate | Status |
|---|---|
| `flutter analyze --no-fatal-infos` on 3 touched files | clean (2 pre-existing info-level dep_on_referenced_packages on the test, identical to precedent test) |
| `scripts/check_reader_manifest_complete.dart` | PASS (phase-1 30 forbidden patterns + phase-2 25 manifest-complete concepts) |
| 4 behavioural tests | 4 / 4 PASS |

## Out of scope (follow-up batches)

- Migrate the second domain (suggested next: nutrition saved meals
  — small, contained, similar shape to streaks). Once 2 domains
  exist, the SyncService fan-out can adopt a `List<SyncDomain>`
  dispatcher and the streaks call sites switch over.
- Migrate the remaining 7 part-files to their own SyncDomain
  implementations.
- Resolve the `UrineColorLogs` missing-restore-counterpart deferral
  (it's on the push-only allowlist as a TODO; not part of A6
  scaffold).
- Wire SyncDomain into the cron telemetry helper
  (`_shared/cron_telemetry.ts`) so domain `name` becomes the
  canonical `op_type` tag everywhere.
