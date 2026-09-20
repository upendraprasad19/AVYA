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
  (5) Because (1) makes onboarding_completed_at a durable Hive value, the streak
  walk-back anchor (_earliestUserAnchor, workout_repository.dart) now reads it —
  its consider() read was dormant while the Hive profile lacked the column.
  Normalize that anchor to istMidnight(dt): the walk-back stop is date-granular
  and a raw mid-day instant would exclude the onboarding-day workout when
  onboarding's time-of-day exceeds the walk's wall clock. istMidnight only moves
  the anchor earlier, so it can include the onboarding day but never drops a
  completed day. The plan-proposed bootstrapper reconcile (GoHome if
  users.onboarding_completed OR onboarding_completed_at) is NOT needed: it would
  require a cross-table read of users.onboarding_completed (a different table
  from the user_profile row classifyDestination fetches — the 42703 footgun at
  auth_session_bootstrapper.dart:106-112), and (2)+(4) fix the cause so the
  column is reliably non-null for completed users; keying GoHome on
  onboarding_completed_at != null stays correct.
regression_test_planned: >
  test/contracts/onboarding_completed_at_durable_writer_test.dart — comment-stripped
  source contract: asserts sync_profile.dart _syncUserProfile payload INCLUDES
  onboarding_completed_at (guarded), completeOnboarding stamps it into the Hive
  profile map, and the last_active_at / onboarding_completed_at writes use
  .toUtc(). Fails on the pre-fix tree (omitted field / naive .toIso8601String()).
  Behavioral: test/contracts/onboarding_streak_anchor_ist_midnight_test.dart —
  real Hive + the _calculateStreak walk; a completed workout on the onboarding
  day (late-in-IST-day onboarding instant) is counted (streak 2, not 1) and the
  anchor still floors the walk before the onboarding date. Fails on the raw-
  instant anchor (B-pass Finding 1).
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — 6 edits: onboarding_provider.dart (Hive stamp + 2x .toUtc()), sync_profile.dart (_syncUserProfile payload += onboarding_completed_at), sync_service.dart (.toUtc()), workout_repository.dart _earliestUserAnchor (istMidnight normalization — the durable Hive value activated this dormant streak-anchor reader; B-pass Finding 1)."
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

## Streak-anchor interaction (B-pass Finding 1)
The Hive stamp is load-bearing: `_syncUserProfile` reads
`profile['onboarding_completed_at']` from Hive, so without the stamp the durable
writer would be inert on the normal path (only the restoring-screen self-heal
ever populated the Hive value). Keeping the stamp activated a previously-dormant
reader — `WorkoutRepository._earliestUserAnchor`'s
`consider(profile['onboarding_completed_at'])` — which had silently fallen back
to the first-workout date because the Hive profile never carried the column.
The walk-back stop (`date.isBefore(anchor)`) is date-granular while `date`
carries the wall-clock time-of-day, so a raw mid-day instant excluded the
onboarding-day workout when onboarding's time-of-day exceeded the walk's.
`istMidnight(dt)` normalizes the anchor to the onboarding IST calendar-date
midnight; because `istMidnight(dt) <= dt`, the anchor can only move earlier — it
includes the onboarding day but never drops a completed day. (It may now consume
a streak freeze for a missed *scheduled* day in the onboarding→first-workout
window — the SoT-intended behavior: those are real missed days the user had the
app for.)

## Scope note — bootstrapper reconcile NOT taken
The original plan also proposed a second mechanism: have
`classifyDestination` return `GoHome` when `users.onboarding_completed = true`
OR `onboarding_completed_at != null`. That is NOT taken and is NOT required.
`classifyDestination` fetches only a `user_profile` row; `users.onboarding_completed`
lives on the `users` table, so the OR would need a cross-table read in the hot
auth path — the exact 42703 silent-degrade-everyone footgun documented at
`auth_session_bootstrapper.dart:106-112`. The durable `_syncUserProfile` writer
(2) plus heal migration 098 (4) repair the cause, so `onboarding_completed_at`
is reliably non-null for completed users and the existing presence check stays
correct.
