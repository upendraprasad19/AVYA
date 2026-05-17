---
bug_id: 41507e
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase C (P2 process)
status: shipped
symptom: |
  Home + Rank widgets called `WorkoutRepository.currentStreak()`
  (live walk-back through `schedule_*` keys). Profile + Reports read
  cached `current_streak_weeks` from `user_progress`. The cached field
  could lag the live calc by hours or days. Users saw different streak
  numbers in different screens.
concept: current_streak_single_reader
sot_registry_entry: workout_read_service
writers:
  - { file: lib/features/train/repositories/workout_repository.dart, method: calculateCurrentStreak (canonical), line: 157 }
  - { file: lib/features/profile/providers/profile_provider.dart, method: currentStreak now delegates, line: 299 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: StreakNotifier.build, line: 245 }
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: UserStatsNotifier.build (NEW reader), line: 299 }
  - { file: test/contracts/phase_c_oi_closures_test.dart, method_or_widget: OI-41 group (2 cases), line: 196 }
hive_key_prefix: "schedule_"
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods: [syncWorkoutData]
restore_methods: [_restoreScheduleCompletions]
cloud_table: workout_schedule_completions
cloud_columns: [status, completed_at]
contract_test_path: test/contracts/phase_c_oi_closures_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations: [streakProvider, userStatsProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "workoutBox is user-scoped via HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "profile_provider reads cached current_streak_weeks for currentStreak field", absent: true }
proposed_fix: |
  Profile's UserStatsData.currentStreak now reads from
  WorkoutRepository.instance.currentStreak() — the same canonical
  source Home + Rank use. Pre-fix reading `current_streak_weeks` from
  user_progress was always going to lag because that field is only
  written by SyncService restore + weekly recalc, not by every
  workout completion.

  The historical `current_streak_weeks` field still exists and may
  be read by weekly reports / aggregates separately (different
  semantic — cumulative weekly milestone count, not active day
  streak). Renaming was considered but the field is also written by
  weekly-recalc Edge Function — a rename without server-side sweep
  would break that consumer.

  Lens L1 (writer/reader drift). SoT registry's workout_read_service
  entry should be extended to pin the streak reader contract too.
regression_test_planned:
  - test/contracts/phase_c_oi_closures_test.dart
---

# Bug 41507e — Profile vs Home streak source drift

closes-oi: OI-41

Profile now reads streak from the same canonical live walk-back as Home + Rank. The cached `current_streak_weeks` field remains for weekly aggregate reports (different semantic).
