---
bug_id: c4d8a2
date: 2026-06-28
batch: ist-onboarding-durability
status: fixed
blast_radius: account
symptom: >
  Live data (test7@gmail.com): a fully-onboarded user — users.onboarding_completed
  = true, a complete user_profile (date_of_birth, primary_goal, fitness_experience,
  days_per_week, current_weight) and a generated plan — yet
  user_profile.onboarding_completed_at IS NULL. Two columns that both mean
  "finished onboarding" disagree. The post-login router (AuthSessionBootstrapper.
  classifyDestination) returns GoHome only when onboarding_completed_at != null, so
  on a NEW device / fresh web (empty Hive) this user is routed BACK through
  onboarding despite having completed it (the e2a4f7 forced-re-onboarding class).
  Secondary: users.last_active_at and user_profile.onboarding_completed_at were
  written with a naive-local DateTime.now().toIso8601String() (no offset) into
  timestamptz columns, so on an IST device they landed ~5.5h ahead (IST-as-UTC),
  skewing the re-engagement / founder-metrics cron windows that filter on
  last_active_at.
concept: onboarding_completed_at
sot_registry_entry: >
  onboarding_completed_at — adds two writers: the Hive userBox['profile'] stamp in
  OnboardingNotifier.completeOnboarding AND the recurring _syncUserProfile cloud
  upsert (previously the column had no durable writer; only the one-shot onboarding
  cloud write + the restoring-screen self-heal touched it).
writers: >
  CLOUD onboarding_completed_at: (1) onboarding_provider.dart completeOnboarding
  profileData write (one-shot at onboarding); (2) NEW — sync/sync_profile.dart
  _syncUserProfile payload (recurring, durable, guarded never-null); (3)
  restoring_screen.dart Plan-A self-heal (stamps Hive then syncProfileNow → now
  reaches cloud because (2) carries the column). HIVE onboarding_completed_at: NEW
  — completeOnboarding now stamps userBox['profile']['onboarding_completed_at']
  (UTC) so local readers and (2) have a value. last_active_at: onboarding_provider
  completeOnboarding userData + sync_service.dart _syncOnboardingToSupabase userData
  (both now .toUtc()).
readers: >
  user_profile.onboarding_completed_at — auth_session_bootstrapper.dart
  classifyDestination (GoHome vs ResumeOnboarding, presence check); Hive
  profile['onboarding_completed_at'] — profile prediction_card.dart (presence),
  workout_repository.dart _earliestUserAnchor (date anchor), ai_snapshot_builder.dart.
  users.last_active_at — server crons (re-engagement, founder_metrics) windowed
  filters.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: ["_syncUserProfile", "_syncOnboardingToSupabase", "syncProfileNow"]
restore_methods: []
cloud_table: user_profile
cloud_columns: ["onboarding_completed_at", "last_active_at"]
contract_test_path: test/contracts/onboarding_completed_at_durable_writer_test.dart
ist_handling: >
  last_active_at (onboarding_provider + sync_service) and onboarding_completed_at
  (onboarding_provider profileData + the new Hive stamp) now use
  DateTime.now().toUtc().toIso8601String() so the timestamptz columns store the
  true UTC instant instead of a naive IST wall-clock ~5.5h ahead. Lower-impact
  Hive-stored-and-synced timestamps (plan_generated_at, phase_started_at,
  updated_at) are left naive in this batch — their skew is weeks-granularity /
  cosmetic and the safe fix is sync-boundary conversion (a separate careful item),
  not a blind .toUtc() that could shift a naive-substring local reader.
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["upsert_user_profile"]
cross_account_guard: false
forbidden_patterns_checked:
  - "A cloud column whose ONLY writers are a one-shot path + a self-heal that itself routes through a sync method that OMITS the column — i.e. no durable/recurring writer. _syncUserProfile (the canonical recurring profile->cloud sync) omitted onboarding_completed_at, so a missed one-shot write was never repaired and the self-heal (syncProfileNow -> _syncUserProfile) was a silent no-op. FIXED: the column is now in the _syncUserProfile payload + stamped into the Hive profile."
  - "A timestamptz cloud column written with a naive DateTime.now().toIso8601String() (no .toUtc()) — stored ~5.5h ahead on an IST device. FIXED for last_active_at + onboarding_completed_at."
proposed_fix: >
  (1) completeOnboarding stamps userBox['profile']['onboarding_completed_at'] (UTC)
  so the Hive profile carries it and local readers stop seeing null. (2) Add
  onboarding_completed_at to the _syncUserProfile upsert payload (guarded
  SyncService._hasValue so it never clobbers with null) — the column now has a
  durable recurring writer AND the restoring-screen self-heal (which pushes via
  syncProfileNow → _syncUserProfile) actually reaches cloud. (3) .toUtc() the
  last_active_at + onboarding_completed_at cloud writes. (4) Heal migration 098
  backfills user_profile.onboarding_completed_at = COALESCE(onboarding_completed_at,
  users.created_at) where users.onboarding_completed = true AND
  onboarding_completed_at IS NULL (fixes test7 + any existing rows).
regression_test_planned: >
  test/contracts/onboarding_completed_at_durable_writer_test.dart — comment-stripped
  source contract: asserts sync_profile.dart _syncUserProfile payload INCLUDES
  onboarding_completed_at (guarded), completeOnboarding stamps it into the Hive
  profile map, and the last_active_at / onboarding_completed_at writes use
  .toUtc(). Fails on the pre-fix tree (omitted field / naive .toIso8601String()).
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — 5 edits: onboarding_provider.dart (Hive stamp + 2x .toUtc()), sync_profile.dart (_syncUserProfile payload += onboarding_completed_at), sync_service.dart (.toUtc())."
  - "postgres_data — status: fixed_in_this_batch — migration 098 backfills onboarding_completed_at for onboarded users whose column is NULL (test7)."
  - "postgres_schema — status: verified — user_profile.onboarding_completed_at (timestamptz, nullable) + users.onboarding_completed (bool) confirmed present via live information_schema 2026-06-25."
  - "client_to_server_contract — status: fixed_in_this_batch — _syncUserProfile now syncs onboarding_completed_at; the documented onboarding SoT contract (Hive stamp) is now met."
impact_analysis: >
  Affects every user whose one-shot onboarding cloud write of onboarding_completed_at
  missed (network/timing) — they showed onboarded locally but null in cloud, and
  the broken self-heal never repaired it. On a new device they were forced to
  re-onboard. Fix makes the column durable (recurring writer + working self-heal +
  Hive stamp) and heals existing nulls. last_active_at UTC fix corrects cron-window
  filtering. No data loss; guarded writes never clobber existing values.
---

# c4d8a2 — `onboarding_completed_at` has no durable writer (forced re-onboarding) + IST-as-UTC timestamps

See YAML frontmatter for the full diagnosis. Surfaced during the 2026-06-28
consistency batch when the founder questioned why test7's
`onboarding_completed_at` was NULL despite a complete profile + plan.

## Root cause (one line)
`_syncUserProfile` — the canonical recurring profile→cloud sync — **omitted**
`onboarding_completed_at`, so the column had no durable writer; the
restoring-screen Plan-A self-heal pushed through that same method and therefore
**silently dropped** the field (a cloud no-op). A missed one-shot onboarding write
then stayed NULL forever → forced re-onboard on a new device.

## Fix
Hive stamp at onboarding + `_syncUserProfile` carries the column (guarded) + the
two cloud-`now()` writes use `.toUtc()` + heal migration 098 backfills existing
nulls.
