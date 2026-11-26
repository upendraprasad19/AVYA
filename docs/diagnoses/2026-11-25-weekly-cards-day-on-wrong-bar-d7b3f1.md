---
bug_id: d7b3f1
date: 2026-11-25
batch: nutrition-history
status: fixed
tier: full
blast_radius: account
symptom: |
  Found by plan review (round 2) of Nutrition History and confirmed by a behavioral test on the unchanged code, NOT observed on a device: the two weekly cards under INSIGHTS & TRENDS on the Nutrition tab ("This Week - Calories", "This Week - Protein") put a day's meals on the wrong bar at any time of day other than exactly midnight. Tuesday's meals are added to Monday's bar, every later day shows one bar early, and Sunday's bar stays empty. Run on a Wednesday with meals of 100 / 200 / 300 kcal on Mon / Tue / Wed the old code returned [300, 300, 0, 0, 0, 0, 0] where [100, 200, 300, 0, 0, 0, 0] is right.
concept: nutrition_total_calories
sot_registry_entry: nutrition_total_calories
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: "logMeal: writes nlog_* rows whose date field is the IST day", line: 69 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "WeeklyNutritionNotifier.build: buckets each row of the current week into one of seven bars", line: 1669 }
  - { file: lib/features/nutrition/services/nutrition_history.dart, method_or_widget: "weekIndexOfDateKey: the bar index, from two IST date keys", line: 34 }
hive_key_prefix: "nlog_ (read only)"
hive_key_formula: "n/a (no key change)"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/weekly_nutrition_day_bucket_behavioral_test.dart
ist_handling: ["today is istDateStr(DateTime.now()) (nutrition_provider.dart:1685); the week's Monday and the day index are calendar-day differences between date KEYS parsed as UTC calendar dates (nutrition_history.dart:34), never a device-local DateTime with a time of day"]
provider_invalidations: ["none changed by this fix"]
telemetry_op_types:
  success: ["none"]
  failure: ["none"]
cross_account_guard: "Unchanged: the '<anon>' early return still precedes every box read."
forbidden_patterns_checked:
  - { pattern: "date.difference(weekStart).inDays with a weekStart that keeps a time of day", absent: true }
  - { pattern: "now.subtract(Duration(days: now.weekday - 1)) used as a week start", absent: true }
proposed_fix: |
  The notifier took Monday as now minus (weekday - 1) days, which keeps the current time of day t, then indexed a row (parsed at midnight) with date.difference(weekStart).inDays, which truncates. Monday is -t hours (index 0), Tuesday is 24 - t hours (also index 0 for any t > 0), Wednesday index 1, and so on. The index is now weekIndexOfDateKey(dateStr, todayKey): both keys parsed as UTC calendar dates, Monday derived from today's key, a whole-day difference.
regression_test_planned: |
  test/contracts/weekly_nutrition_day_bucket_behavioral_test.dart (real Hive, the real provider): one meal per day from Monday to today with distinct calories plus one on last Sunday, expects each day on its own bar and last Sunday on none. Written FIRST and red on the old code on a Wednesday. Pure cases for the helper in test/contracts/nutrition_history_writer_to_reader_test.dart ("calendar helpers").
mutation_proof: |
  Two mutants, each applied (one site counted) and reverted by scratch script nh_mutate.py: M17 (the helper takes today as the week's Monday) and M25 (the notifier shifts every index after Monday one early, the old behaviour). Results are recorded in docs/audit/nutrition-history.closure.yaml. Clock note: the provider test is green on the OLD code only when it runs on a Monday (one bar); on every other weekday the old code fails it.
impact_analysis: |
  Display only: the two weekly bar charts and their averages (the average is over bars with data, so merging two days into one bar also raised the average). No write, no sync, no schema. The History screen uses the same date-key maths from the start.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "nutrition_provider.dart:1685-1698 and nutrition_history.dart:34; whole-project flutter analyze --no-fatal-infos has no warning." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The regression test writes real nutritionBox rows and reads them through weeklyNutritionProvider." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
recurrence: "Recurrence of the class 'a week or day window anchored on a device-local DateTime instead of an IST date key': e7a2c4 (getWeeklyWorkoutCounts anchored its window off IST) and the IST-throughout rule (CLAUDE.md 4.5). bae4dd touched the same notifier and added a missing rebuild trigger, and noted that weekStart was recomputed fresh each build; the bucket arithmetic itself was not checked then. Same known-good fix applied: compute from IST date keys."
related_bugs: [e7a2c4, bae4dd]
---

# d7b3f1 - weekly Insights cards put a day on the wrong bar

## What happened
`weekStart` kept the time of day and the bar index truncated a difference in hours, so every day after Monday landed one bar early.

## The fix
One pure helper, `weekIndexOfDateKey`, working on IST date keys.

## Not established
- Not observed on a device. How long it has been wrong is not established (the arithmetic has no dependency on recent changes).
- The server weekly report is a different code path and was not examined for this class.
