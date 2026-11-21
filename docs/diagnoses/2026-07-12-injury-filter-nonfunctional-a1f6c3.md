---
bug_id: a1f6c3
date: 2026-07-12
batch: injuries-safety
status: fixed
blast_radius: platform
symptom: >
  Injuries were collected everywhere (onboarding default, Edit-Profile chips,
  AI-coach muster) but the plan engine's contraindication filter excluded
  ESSENTIALLY ZERO exercises for most users — a safety feature shipping as
  theater. Three independent mechanisms, all writer/reader-drift class:
  (1) VOCAB DRIFT — the Edit-Profile injury chip stored `back`, but the library
  tags `lower_back`; the exact-lowercase-equality match (exercise_repository
  queryV4) never matched, so a back-injured user's plan excluded 0 of the 24
  lower_back-contraindicated exercises. elbow/neck/hamstring were library tokens
  with no chip to select them at all. AI-coach muster wrote free-text
  ("lower back", "bad knee") verbatim into profile.injuries — never matched.
  (2) THREADING DROPS — 7 of ~10 plan-generation entry points called the
  generator WITHOUT passing profile.injuries at all (onboarding, train auto-gen,
  login-restore regen, graduation next-phase, Edit-Profile reschedule-on-save,
  AND both AI-coach paths: regenerate-plan + hotel-workout). So even a
  correctly-vocabularied injury never reached the filter on those paths.
  (3) UNIVERSAL-POOL BYPASS — the exercise selector's attempt-5 bodyweight
  fallback pool bypassed queryV4 entirely, so it handed out contraindicated
  moves (e.g. Pike Push Up to a shoulder-injured user) even when injuries DID
  reach the cascade. Batch-0 scorecard measured 2 unsafe plans from this alone.
concept: injury_contraindication_filter
sot_registry_entry: >
  Adds a new SoT concept `injury_vocabulary_contract` to docs/sot_registry.yaml:
  the canonical injury token set (lib/core/utils/injury_vocab.dart
  InjuryVocab.canonicalTokens) MUST equal the exercise library's distinct
  `injury_contraindications` tokens, and every writer of profile.injuries (the
  Edit-Profile chips + the muster/induction bridge) normalizes through
  InjuryVocab. Behavioral pin: injury_vocab_library_contract_test.dart (the set
  == the live library) + injury_filter_behavioral_test.dart (the end-to-end
  exclusion). Reader of the contract is PlanGenerator.generateV4, which
  normalizes centrally before ExerciseSelector.pickV4.
writers: >
  NEW canonical vocabulary: lib/core/utils/injury_vocab.dart (InjuryVocab.normalize
  + canonicalTokens). Injury WRITERS to userBox['profile']['injuries'] now emit
  canonical tokens: edit_profile_screen.dart _buildInjuriesChips (chip token
  `back`→`lower_back`, added elbow/neck/hamstring, ~:1205) + its profile reader
  (~:171, normalizes legacy stored values on load); induction_service.dart
  _bridgeToProfile `known_injuries` case (~:92, normalizes muster free-text).
  GENERATION callers now THREAD profile.injuries (were dropping it): onboarding_
  provider.dart (~:453), train_provider.dart _autoGeneratePlan (~:466), auth_
  session_bootstrapper.dart login-restore regen (~:379), graduation_screen.dart
  (~:588), edit_profile_screen.dart reschedule-on-save (~:1795), regenerate_plan_
  planner.dart (~:184), hotel_workout_planner.dart (~:111). CENTRAL normalization:
  plan_generator.dart generateV4 (~:77) canonicalizes injuries once for all paths.
  U2 filter writer: exercise_selector.dart _cascadeFill attempt-5 (~:828) now
  skips contraindicated pool picks (kill-switch plan_engine_flags.dart
  injuryUniversalFilterEnabled).
readers: >
  exercise_repository.dart queryV4 injury match (exact lowercase equality on
  `injury_contraindications`, ~:290 — attempts 1-4, unchanged, already correct);
  exercise_selector.dart _cascadeFill attempt-5 universal-pool (NEW injury check
  via _isContraindicated). The Batch-0 measurement harness mirrors both:
  test/plan_generator/v4_diagnostic/cascade_tracer.dart attempt-5 + query_v4_mirror,
  scored by plan_scorecard.dart safety dimension.
hive_key_prefix: profile
hive_key_formula: "userBox['profile']['injuries'] — a List<String> field on the single profile map (not a per-row key). Written by the profile writers above; read by every generation entry point + Edit-Profile chip render."
sync_methods: >
  injuries ride inside the profile map: SyncService.syncProfileNow /
  syncOnboarding push userBox['profile'] to the cloud user_profile row
  (user_profile.injuries text[]). No new sync surface — this fix changes the
  VALUES stored (canonical tokens) + who reads them, not the sync path.
restore_methods: >
  _restoreUserProfile applies the cloud user_profile row back into
  userBox['profile'] (including injuries). No new restore path. The read-side
  alias (InjuryVocab.normalize at the Edit-Profile reader + the central
  generateV4 seam) canonicalizes even a restored legacy value, so no boot
  normalizer / migration is required (restore-safe by construction).
cloud_table: user_profile
cloud_columns: >
  user_profile.injuries (text[]) — unchanged shape. Verified present in
  backups/live_schema_columns.json. No migration: the fix normalizes at read/
  write seams, it does not add or rename a column.
contract_test_path: test/contracts/injury_filter_behavioral_test.dart
ist_handling: >
  n/a — no date key introduced; injuries are a static profile field, not a
  date-scoped counter.
provider_invalidations: >
  n/a to this fix — plan (re)generation invalidations (currentPlanProvider /
  calendarWeekProvider) already fire on the downstream write paths, unchanged.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  n/a to change — all injury reads/writes go through userBox['profile'] via
  HiveService.instance (user-scoped, wrapUserScopedBox-guarded). No new box, no
  new raw Hive access. InjuryVocab + PlanEngineFlags are pure/config-only.
forbidden_patterns_checked: []
proposed_fix: >
  (U1) Introduce InjuryVocab (canonical 9 tokens + normalize read-side alias);
  rename the Edit-Profile chip `back`→`lower_back`, add elbow/neck/hamstring,
  normalize legacy values at the chip reader, and normalize muster/induction
  free-text at the profile-write bridge. (U4) Thread profile.injuries into all 7
  generation entry points that dropped it, and normalize CENTRALLY in
  generateV4 so every path (including any direct generateV4 caller) is covered
  by one seam rather than 7 fragile per-caller normalizations. (U2) Injury-filter
  the exercise selector's attempt-5 universal pool: skip a contraindicated pool
  pick, prefer the next injury-safe pool member (the pool already contains safe
  options for the one at-risk pattern, shoulder_isolation → Arm Circles); when
  the WHOLE pool is contraindicated, safely omit the slot (return null — fewer-
  but-safe) rather than injure the user. Kill-switch
  configBox['disable_injury_universal_filter'] (default filter ON).
regression_test_planned: >
  injury_vocab_library_contract_test.dart pins InjuryVocab.canonicalTokens ==
  the live library tokens + normalize() units. injury_filter_behavioral_test.dart
  (Hive + real library): a LEGACY `back` injury excludes lower_back-contra
  exercises (proves vocab + central normalize); a shoulder injury excludes Pike
  Push Up (proves U2); the kill-switch reverts and Pike Push Up REAPPEARS
  (non-vacuity); the AI-coach regenerate path excludes a knee user's knee-contra
  exercises (proves the U4 coach threading drop is fixed). injury_safe_omission_
  test.dart proves an all-contraindicated pool → safelyOmitted, not (none).
  scorecard_gate_test.dart (597-persona matrix) drives unsafe plans 2→0 with 0
  missing picks — the measured improvement; baseline re-frozen (unsafe floor 0).
touched_layers_checked:
  - "tier: 1_client_code, status: fixed_in_this_batch — InjuryVocab + PlanEngineFlags added; 7 entry points threaded; chips renamed; muster bridge + central generateV4 normalize; flutter analyze clean (0 new issues)."
  - "tier: 2_hive_local_state, status: fixed_in_this_batch — injury_filter_behavioral_test.dart seeds the real library + reads userBox['profile']['injuries'] end-to-end; all 4 behavioral cases green."
  - "tier: 12_client_server_contract, status: verified — user_profile.injuries (text[]) unchanged (backups/live_schema_columns.json); no migration; canonical values round-trip via the existing profile sync/restore."
impact_analysis: >
  Blast radius platform (lib/shared/repositories/plan_engine/**). Behavior change:
  injured users' generated plans now actually exclude contraindicated exercises
  across every generation path (onboarding, train, login-restore, graduation,
  profile-edit reschedule, AI-coach regenerate + hotel). Measured via the Batch-0
  scorecard: unsafe plans 2→0, safety 99.7→100.0, mean overall 86.5→86.8, with 0
  missing/(none) picks and equipment/fallback counts unchanged (the fix only
  affects injured personas' picks). The one at-risk universal-pool pattern
  (shoulder_isolation) has injury-safe members, so no slot is dropped for any
  matrix persona; the safe-omission path (drop a slot when the whole pool is
  contraindicated) is reachable only for contrived multi-injury combos and is
  proven safe by injury_safe_omission_test.dart. Everything ships behind the
  disable_injury_universal_filter kill-switch (default ON) — reverting restores
  the verbatim pre-fix universal-pool behavior. Downstream: this is Ship 1 of the
  workout-generator overhaul's injury batch; Ship 2 (U3 warmup/cooldown injury
  filter) and Ship 3 (U5 onboarding injury chip) build on this canonical
  vocabulary.
---

# Injury contraindication filter non-functional — vocab drift + threading drops + universal-pool bypass (a1f6c3)

## What happened
The app collected injuries in three places (onboarding default, Edit-Profile
chips, AI-coach muster) but the plan engine's contraindication filter excluded
essentially zero exercises for most users. Three independent writer/reader-drift
mechanisms conspired (see `symptom` + `proposed_fix` above): vocabulary drift
(`back` ≠ library `lower_back`; elbow/neck/hamstring unreachable; muster
free-text unnormalized), threading drops (7 of ~10 generation entry points never
passed `profile.injuries`, including BOTH AI-coach paths), and the attempt-5
universal-pool bypass (contraindicated bodyweight picks handed out unfiltered).

## Root cause
The recurring writer/reader-drift class (lib/CLAUDE.md): the injury WRITERS
(UI chips, muster) and the injury READER (queryV4's exact-match) used different
vocabularies, and the intermediate THREADING (entry point → generator) silently
dropped the field on most paths. The universal pool was a fourth reader that
skipped the filter entirely.

## Fix
U1 canonical vocabulary + read-side alias; U4 central normalization in
generateV4 + threading all 7 drop sites; U2 injury-filtering the universal pool
with a safe-omission floor + kill-switch. See `proposed_fix` + the Ship-1 plan
`docs/plans/injuries-safety-batch.md`.

## Related
Surfaced by the workout-generator overhaul's injuries-safety ×2 plan review
(ground-truth + design reviewers). Prerequisite for Ship 2 (U3 warmup injury
filter) and Ship 3 (U5 onboarding injury chip). Measured against the Batch-0
validation harness (unsafe 2→0).
closes-diagnose: a1f6c3
