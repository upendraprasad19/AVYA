// supabase/functions/_shared/workout_statuses.ts
//
// `scheduled_workouts.status` values that are NOT a planned workout, for the
// coach tools' adherence maths (L1b plan B7). A null status is also excluded
// by the caller (`status !== null`).
//
// Parity (pinned by workout_statuses_test.ts):
//   this set  ⊇  rank_engine.ts `completionRateOverWindow` skip set (rest, paused, moved, dropped)
//             ⊇  client `invisibleScheduleStatuses`
//                (lib/core/services/workout_schedule_read_service.dart:889 = paused, moved, dropped).
// `skipped` and null are deliberate tool-only additions.

export const NON_WORKOUT_STATUSES: ReadonlySet<string> = new Set([
  "paused",
  "skipped",
  "rest",
  "moved",
  "dropped",
]);
