# OI-237 IO measurements (day-swapper + sync-load batch)

Spec §10. `pg_stat_user_tables` counters are cumulative since the last stats
reset, so every comparison is a DIFFERENCE between two snapshots.

| Snapshot | When | Purpose |
|---|---|---|
| 1 | Task 1 (this commit) | start of the "before" window |
| 2 | Task 34, right before the migration apply | end of the "before" window |
| 3 | Task 34, 3 days after the new build reaches the founder's devices | end of the "after" window |

## Snapshot 1

| table | n_tup_ins | n_tup_upd | n_tup_hot_upd | n_live_tup | captured_at |
|---|---|---|---|---|---|
| ai_coach_interactions | 181 | 128 | 116 | 238 | 2026-09-27 01:23:25.118865+00 |
| body_measurements | 0 | 0 | 0 | 0 | 2026-09-27 01:23:25.118865+00 |
| daily_steps | 0 | 16 | 16 | 0 | 2026-09-27 01:23:25.118865+00 |
| nutrition_log_items | 68 | 489 | 489 | 183 | 2026-09-27 01:23:25.118865+00 |
| nutrition_logs | 33 | 151 | 151 | 59 | 2026-09-27 01:23:25.118865+00 |
| readiness_daily | 7 | 41 | 41 | 7 | 2026-09-27 01:23:25.118865+00 |
| scheduled_workouts | 112 | 1443 | 1422 | 999 | 2026-09-27 01:23:25.118865+00 |
| sleep_logs | 0 | 0 | 0 | 0 | 2026-09-27 01:23:25.118865+00 |
| streaks | 0 | 296 | 296 | 12 | 2026-09-27 01:23:25.118865+00 |
| template_exercises | 3 | 806 | 806 | 23 | 2026-09-27 01:23:25.118865+00 |
| user_custom_exercises | 0 | 32 | 32 | 0 | 2026-09-27 01:23:25.118865+00 |
| user_custom_foods | 0 | 0 | 0 | 0 | 2026-09-27 01:23:25.118865+00 |
| user_progress | 23 | 44 | 44 | 26 | 2026-09-27 01:23:25.118865+00 |
| user_saved_meals | 0 | 0 | 0 | 0 | 2026-09-27 01:23:25.118865+00 |
| water_logs | 4 | 1660 | 1660 | 40 | 2026-09-27 01:23:25.118865+00 |
| weight_logs | 28 | 178 | 178 | 56 | 2026-09-27 01:23:25.118865+00 |
| workout_log_exercises | 16 | 526 | 525 | 200 | 2026-09-27 01:23:25.118865+00 |
| workout_log_sets | 46 | 1580 | 1557 | 488 | 2026-09-27 01:23:25.118865+00 |
| workout_logs | 25 | 1132 | 1132 | 53 | 2026-09-27 01:23:25.118865+00 |
| workout_schedule_completions | 5 | 1132 | 1132 | 39 | 2026-09-27 01:23:25.118865+00 |
| workout_templates | 1 | 187 | 187 | 6 | 2026-09-27 01:23:25.118865+00 |

## Snapshot 2

Taken right before the migration apply (it became migration 149 at apply time: the live database
already held a `148_` from another branch). The window from snapshot 1 is ~31 hours.

| table | n_tup_ins | n_tup_upd | n_tup_hot_upd | n_live_tup | captured_at |
|---|---|---|---|---|---|
| ai_coach_interactions | 252 | 152 | 137 | 293 | 2026-09-28 08:26:42.698543+00 |
| body_measurements | 0 | 0 | 0 | 0 | 2026-09-28 08:26:42.698543+00 |
| daily_steps | 3 | 24 | 24 | 3 | 2026-09-28 08:26:42.698543+00 |
| nutrition_log_items | 82 | 489 | 489 | 189 | 2026-09-28 08:26:42.698543+00 |
| nutrition_logs | 44 | 151 | 151 | 62 | 2026-09-28 08:26:42.698543+00 |
| readiness_daily | 10 | 63 | 63 | 19 | 2026-09-28 08:26:42.698543+00 |
| scheduled_workouts | 154 | 1560 | 1538 | 1041 | 2026-09-28 08:26:42.698543+00 |
| sleep_logs | 0 | 0 | 0 | 0 | 2026-09-28 08:26:42.698543+00 |
| streaks | 1 | 319 | 319 | 13 | 2026-09-28 08:26:42.698543+00 |
| template_exercises | 3 | 869 | 869 | 23 | 2026-09-28 08:26:42.698543+00 |
| user_custom_exercises | 0 | 40 | 40 | 0 | 2026-09-28 08:26:42.698543+00 |
| user_custom_foods | 0 | 0 | 0 | 0 | 2026-09-28 08:26:42.698543+00 |
| user_progress | 32 | 60 | 60 | 27 | 2026-09-28 08:26:42.698543+00 |
| user_saved_meals | 0 | 0 | 0 | 0 | 2026-09-28 08:26:42.698543+00 |
| water_logs | 5 | 1765 | 1765 | 41 | 2026-09-28 08:26:42.698543+00 |
| weight_logs | 38 | 237 | 237 | 58 | 2026-09-28 08:26:42.698543+00 |
| workout_log_exercises | 24 | 533 | 532 | 207 | 2026-09-28 08:26:42.698543+00 |
| workout_log_sets | 65 | 1599 | 1576 | 507 | 2026-09-28 08:26:42.698543+00 |
| workout_logs | 34 | 1221 | 1221 | 54 | 2026-09-28 08:26:42.698543+00 |
| workout_schedule_completions | 5 | 1219 | 1219 | 39 | 2026-09-28 08:26:42.698543+00 |
| workout_templates | 3 | 202 | 202 | 6 | 2026-09-28 08:26:42.698543+00 |

Before-window update deltas (snapshot 2 − 1), the tables the batch targets: water_logs +105,
workout_logs +89, workout_schedule_completions +87, scheduled_workouts +117, template_exercises
+63, streaks +23, weight_logs +59. The low-traffic tables barely moved; the "after" window is
compared per day once snapshot 3 exists.
