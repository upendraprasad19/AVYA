---
bug_id: 321062
date: 2026-08-30
batch: OI-150 — progress + profile write durability and restore authority
status: fixed
blast_radius: platform
symptom: |
  A phase advance writes four fields to Hive as one atomic delta, then pushes
  fire-and-forget. If the push has not landed before the next launch — the app
  closed after a workout, a network blip, ordinary offline-first usage — the
  next restore merges a STALE cloud row over it. `current_phase` is guarded
  (OI-83) and stays advanced; `current_week`, `phase_started_at` and
  `plan_generated_at` are not, and revert. The merged map is written straight
  back to Hive, so local and cloud then agree on a shape neither ever wrote and
  nothing flags it again.

  Second-order and worse: the login restore regenerates the plan for the
  ADVANCED phase anchored at the STALE phase's start date, producing a plan
  window in the past — the `c9e4b7` / `b7f1c8` "expired / wrong week / missing
  Phase I" family.

  Third: the push itself can vanish. `unawaited(syncProgressNow())` lives only
  in RAM, so process death destroys it with NOTHING recording the debt. Live
  telemetry shows the version-conflict drop path firing 8 times across 3 users.

  Fourth, same class on a sibling surface: `_restoreUserProfile` merges cloud
  over local per key with NO guard at all, so it can take cloud's weight while
  keeping the phone's calorie target — a target computed from a weight that is
  no longer in the map.
concept: phase_progress_current_phase
sot_registry_entry: phase_progress_current_phase
writers:
  - { file: lib/shared/services/pro_phase_advance.dart, line: 343, method: "commitPhaseAdvance — the atomic 4-field delta this batch exists to keep whole" }
  - { file: lib/shared/repositories/user_repository.dart, line: 385, method: "mergeCloudProgress — the post-pass couples the 3 companions to the phase decision" }
  - { file: lib/shared/repositories/user_repository.dart, line: 300, method: "phaseDeltaCompanionFields — the coupled set (NOT monotonic; they are dates and a reset counter)" }
  - { file: lib/core/services/sync/sync_profile.dart, line: 679, method: "_restoreUserProfile — recomputes the derived half after the merge" }
  - { file: lib/core/services/sync/sync_profile.dart, line: 376, method: "_syncUserProgress — gains fromQueue; enqueues a marker on failure and on the version-conflict drop" }
  - { file: lib/features/profile/services/profile_target_recompute.dart, line: 88, method: "recomputeDerivedTargets — the single derivation for the edit and restore paths" }
readers:
  - { file: lib/core/services/auth_session_bootstrapper.dart, line: 130, method: "resolvePlanRegenStart — anchors the login plan regen on the GUARDED value" }
  - { file: lib/core/services/sync/sync_profile.dart, line: 889, method: "_restoreUserProgress — routes through the shared merge" }
  - { file: lib/core/services/sync_service.dart, line: 712, method: "_executeUserProgressSync — drain-time executor, re-reads current Hive" }
  - { file: lib/core/services/sync_service.dart, line: 691, method: "_executeUserProfileMarker — same, for profile" }
  - { file: lib/shared/repositories/user_repository.dart, line: 89, method: "reportProgressDemotionsDeclined — now also emits progress_restore_phase_delta_refused" }
hive_key_prefix: "userBox['progress'] and userBox['profile'] — single map keys, not prefixed row families"
hive_key_formula: "userBox.get('progress') → Map; coupled sub-keys current_week | phase_started_at | plan_generated_at, keyed on current_phase"
sync_methods: [_syncUserProgress, _syncUserProfile, syncProgressNow, syncProfileNow, pushOnboardingProgressSnapshot]
restore_methods: [_restoreUserProgress, _restoreUserProfile, restoreLightweightAlways]
cloud_table: user_progress
cloud_columns: [current_phase, current_week, phase_started_at, plan_generated_at, streak_progress_version]
contract_test_path: test/contracts/progress_restore_monotonic_behavioral_test.dart
ist_handling: |
  not_applicable for the coupling itself — `phase_started_at` / `plan_generated_at`
  are ISO instants stamped by `commitPhaseAdvance` from ONE `DateTime.now()`, not
  IST date-keys, and this batch does not change how they are produced. The
  profile recompute takes `now` as a parameter so it is testable and carries no
  implicit clock.
provider_invalidations: [userProfileProvider]
telemetry_op_types:
  success: [restore_op_done]
  failure:
    - progress_restore_demotion_declined
    - progress_restore_field_malformed
    - progress_restore_phase_delta_refused
    - sync_user_progress_retry_dropped
    - sync_service_sync_user_profile_enqueued
    - sync_service_restore_profile_recompute
cross_account_guard: |
  STRENGTHENED. `syncBox` is SHARED, not user-scoped, so a queued marker can
  outlive an account switch whose `clearAllData` partially failed. Both drain
  executors compare `payload['user_id']` against `_supabase.currentUser?.id` and
  refuse with a NON-TRANSIENT ValidationError so the op dead-letters immediately
  rather than retrying for hours against a stranger's account. Migration 115
  also raises `cross-account progress write blocked` server-side, so such an op
  could never have succeeded.
forbidden_patterns_checked: |
  - No `?? 18.0` on body fat: the recompute passes the raw nullable value through
    `BmrCalculator.bodyFatForCalc` (c3f2d8). Pinned by a test that fails if the
    null and 18.0 cases produce equal calories.
  - No `SyncError(...)` direct construction — the class is `sealed` with an
    abstract `code`; refusals use `ValidationError`, failures `SyncError.classify`.
  - No `import` added to a `part of` file (`sync/sync_profile.dart`); the import
    went in the parent `sync_service.dart`.
  - No raw `Hive.box(` introduced; all reads go through existing box handles.
  - No unawaited without an error sink — the only unawaited calls wrap
    ErrorTelemetry, which is itself the sink.
  - No `| head` on any completeness grep; every enumeration in the review rounds
    was run unpiped.
proposed_fix: |
  1. Couple the phase delta as a POST-PASS over the merged map, keyed on whether
     the merge kept local's `current_phase`. The loop is untouched, so OI-83's
     demotion/malformed telemetry keeps working and the seven-branch cascade is
     not duplicated. Per-key carve-out: refuse only a companion local actually
     HOLDS, or a phase-ahead map with no dates would be refused into absence.
     Kill-switch `disable_progress_phase_delta_coupling`, independent of the
     OI-83 switch.
  2. Anchor the login plan regen on the guarded Hive value via the pure
     `resolvePlanRegenStart`. Kill-switch `disable_guarded_plan_regen_anchor`.
  3. Recompute the profile's DERIVED half after the restore merge, ONLY when the
     merge changed a derivation input. That gate is what honours the
     founder-locked "NO daily_calories recompute (no silent backfill)" decision
     at `body_fat_default_healer.dart:28`: the healer clears cloud then local,
     so by the next restore both are null, the merge sees no change, and nothing
     recomputes. Kill-switch `disable_profile_target_recompute`.
  4. Route progress and profile writes through the existing `SyncQueue` outbox
     as MARKERS (never payloads — the RPC is optimistic-locked and a replayed
     payload carries a stale version). Flip `sync_reliability_v1` on.
regression_test_planned: |
  test/contracts/progress_restore_monotonic_behavioral_test.dart — the coupling
  group (17 new cases): all-four-survive, reinstall, cloud-ahead, the absent-
  companion carve-out, identical-values, both kill-switches, cloud-phase-absent,
  cloud-phase-null, non-numeric with and without local, current_phase-LAST, and
  the telemetry EMISSION (not merely the recorded list — see the mutation note).
  test/contracts/profile_target_recompute_test.dart — 13 cases including the
  input-changed gate over every declared input, the c3f2d8 null-body-fat
  discrimination, the disable_bodyfat_calc switch, calendar age, and the restore
  wiring pinned by ORDER rather than mention.
  test/contracts/sync_queue_progress_marker_test.dart — 15 cases: executor
  registration, marker-not-payload, non-transient refusals, the fromQueue
  rethrow-before-enqueue ordering, the drop-path enqueue, dedup, and that a
  failed profile push still reports.
  test/contracts/restore_progress_uses_shared_merge_test.dart — the Part A pins.
mutation_evidence: |
  Rule 21's mutate-it-and-run-it clause. Every mutation was CONFIRMED APPLIED by
  grepping the removed token before running, and every arm was EXECUTED.

  - emptied `phaseDeltaCompanionFields`            → 5 red
  - removed the per-key `localValue == null` carve-out → 1 red
  - removed the differ-check before recording       → 1 red
  - removed the `localRaw != null` guard            → 0 red FIRST TIME (absorbed
    by the carve-out), then 1 red after adding a case where local holds a
    companion but no phase, so the guard is the only thing deciding
  - coupling forced always-on                       → 3 red
  - removed the N1 key-absent seed                  → 1 red
  - deleted the reporter's refusal loop             → 0 red FIRST TIME (the test
    asserted the merge's recorded list, which is populated regardless), then
    1 red after rewriting it to capture the EMISSION via
    `ErrorTelemetry.debugOnLogEventForTests`
  - removed the profile input-changed gate          → 1 red
  - made the overlay application a no-op            → 1 red
  - defaulted `bodyFatPercent` to 18.0              → 1 red
  - reverted the regen anchor to the raw cloud row  → 1 red

  ⚠ TWO mutations were absorbed on first run. Both are recorded above rather
  than quietly re-run, because the absorbed result WAS the finding: in each case
  the test asserted an intermediate value instead of the observable effect, and
  would have shipped as coverage it did not have (§2.41).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze repo-wide: 0 warnings, 0 errors (268 pre-existing infos). 8 lib/ files changed." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "the coupling group writes a locally-advanced progress map, merges a stale cloud row, puts, and reads back through UserRepository.getProgress() — all four delta fields survive" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "no schema change. backups/live_schema_columns.json confirms user_progress carries all four delta columns and user_profile all 34 synced ones" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "all 17 user_progress rows queried live 2026-08-30. Only 2 have current_phase >= 2 and BOTH are QA accounts (amar@gmail.com with 0 workout_logs at phase 2; the founder's own). No heal — scheduled_workouts.week_number only holds 1..4, so no phase discriminator exists and any heal value would be invented. Terminal state verified_clean." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this batch" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched; the new telemetry op-types ride the existing log-client-error LOW lane" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron path touched" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change; the restore reads are unchanged" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no Storage object touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret referenced" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no third-party integration touched" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "the cloud reads are byte-identical (bare .select()); only the client-side merge of the payload changed. The profile push payload is unchanged at 34 fields; what changed is that a FAILED push now persists a marker instead of evaporating." }
impact_analysis: |
  WHO IS AFFECTED. Any user with more than one device, or whose local state ran
  ahead of the last successful push — a network blip between a phase advance and
  its sync is enough. A genuine reinstall is NOT affected: local is empty, so the
  coupling never fires and the merge is byte-identical to before.

  MEASURED, NOT ASSUMED. Zero real users are affected today: all 17 accounts are
  ours and the only two at phase >= 2 are QA. The lost-write half is NOT
  theoretical — `sync_user_progress_retry_dropped` fired 8 times across 3 users
  in the 30-day client_errors window.

  WHY THE OUTBOX IS NARROW. `weeklyFullSync` is misnamed: `_fullSyncInterval` is
  ONE DAY, so a lost write already self-heals within a day across 20 surfaces.
  The outbox is therefore not about permanent loss — it closes the window in
  which a stale cloud row is MERGED BACK over good local, which corrupts the
  phone rather than merely lagging the backup. Only two surfaces merge back that
  way, and both are covered.

  VOLUME IS NOT A REASON TO ACT. Measured live: ~5-10 user-generated writes per
  user per active day; all real user data across all accounts and ~4 months is
  ~1,147 rows, against 1,905 telemetry rows. This batch is justified by
  correctness alone. The telemetry ratio and the doubled sync+snapshot round
  trips are filed as OI-151 and OI-152 rather than folded in.

  REVIEW HISTORY. Three context-blind rounds on a WITHDRAWN merge-only design
  (its own root-cause analysis was compensating for a lost write instead of
  preventing one), one round on the plan (9 blocking — four API errors, a
  non-existent goal token, and an uncommittable task order), and one round on
  the implementation (5 blocking, 13 non-blocking, all fixed here). The core
  merge post-pass was attacked hardest and verified sound; every defect the last
  round found was in what had been built around it.
related_bugs: [d1f6b3, c8f3d1, c9e4b7, b7f1c8, c9f4a2, c3f2d8, a1d4f9, 3a7b9f]
recurrence: |
  DIRECT RECURRENCE of d1f6b3 (OI-83), which guarded `current_phase` on this
  exact merge and left its three atomic companions unguarded. Instance #16 of
  `feedback_mistake_guard_without_its_mirror`: d1f6b3's own B-pass finding F1
  wrote an eleven-line comment explaining why the login regen must not read the
  raw cloud row, applied it to the `phase` argument, and left the `startDate`
  argument eight lines below still reading it — both feeding the same
  `generateAndSchedule` call.

---
