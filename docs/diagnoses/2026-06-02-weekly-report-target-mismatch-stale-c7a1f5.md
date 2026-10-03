---
bug_id: c7a1f5
date: 2026-06-02
batch: apk-obs-2026-06-02
status: fixed
blast_radius: platform
symptom: >
  The Weekly Report showed a calorie/protein target (3141 kcal / 155 g) that
  disagreed with every other surface (Nutrition / Profile / Diet Plan all show
  3069 kcal / 140 g), and "0 workouts / 0% nutrition" despite recent activity. Two
  causes: (1) the weekly-report Edge Function RECOMPUTED its own target
  (tdee×1.1 = 3141, weight×2 = 155) instead of reading the canonical stored target;
  (2) the report screen treated a cached EF result as valid for SEVEN DAYS and never
  auto-refreshed, so the founder saw a multi-day-stale report (the 0s + a protein
  target computed at an old weight).
concept: weekly_report_target_and_freshness
sot_registry_entry: weekly_report_target_and_freshness
writers: >
  Canonical target: lib/features/nutrition/providers/nutrition_provider.dart
  _resolveNutritionTargets → persisted to user_profile(daily_calories, protein_grams,
  carbs_grams, fat_grams). Report cache: reports_screen.dart _generateReport →
  configBox[weekly_report_cache].
readers: >
  supabase/functions/weekly-report/index.ts (FIX: reads user_profile.daily_calories /
  protein_grams as the target, falling back to a tdee/weight estimate only when null);
  lib/features/profile/screens/reports_screen.dart (FIX: refreshes the report on
  open via _generateReport(silent:true) instead of trusting a 7-day cache).
hive_key_prefix: not_applicable (report cache key is configBox['weekly_report_cache'], not a domain prefix)
hive_key_formula: not_applicable
sync_methods: not_applicable (the EF reads cloud user_profile directly; targets reach cloud via the onboarding/profile sync)
restore_methods: not_applicable
cloud_table: user_profile (read for the target) + nutrition_logs / workout_log_exercises (read for the aggregates)
cloud_columns: user_profile(daily_calories int, protein_grams int, carbs_grams int, fat_grams int, tdee, current_weight_kg, primary_goal) — all verified live present.
contract_test_path: test/contracts/weekly_report_canonical_target_test.dart
ist_handling: not_applicable (no date math changed; the EF's IST 7-day window is unchanged)
provider_invalidations: not_applicable (the report is fetched on screen open; no provider mutated)
telemetry_op_types: not_applicable (no new telemetry; the silent refresh swallows transient failures and keeps the cached report)
cross_account_guard: >
  preserved. The EF reads user_profile by the authed target user_id; the silent
  refresh uses SupabaseService.currentUser.id — both single-user scoped.
forbidden_patterns_checked:
  - "Weekly-report EF recomputing its own calorie/protein target (tdee×multiplier, weight×g/kg) instead of reading the canonical user_profile.daily_calories/protein_grams — eliminated; pinned by test/contracts/weekly_report_canonical_target_test.dart."
  - "reports_screen showing a cached report up to 7 days old with no refresh-on-open — eliminated; initState now fires _generateReport(silent:true)."
proposed_fix: >
  (3a) In weekly-report/index.ts add daily_calories, protein_grams, carbs_grams,
  fat_grams to the user_profile select and use storedCalories/storedProtein as the
  target; fall back to the old tdee/weight estimate only when they are null/0 (legacy
  profiles). Redeploy the EF (host-shell, byte-identical) + smoke.
  (3b) In reports_screen.dart add a `silent` param to _generateReport (skip the
  full-screen loader + swallow errors so the cached report stays visible) and call
  _generateReport(silent: true) from initState — the report now reflects current
  cloud data on every open instead of a 7-day-stale cache.
regression_test_planned: >
  test/contracts/weekly_report_canonical_target_test.dart (comment-stripped
  source-grep): the EF selects daily_calories + protein_grams and uses storedCalories
  / storedProtein for calorieTarget / proteinTarget; reports_screen initState calls
  _generateReport(silent: true). Behavioral proof: post-EF-deploy invoke for upendra
  returns target 3069/140 (matching the app), verified live in the deploy step.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "reports_screen.dart refreshes on open (silent _generateReport); flutter analyze clean" }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "live: user_profile has daily_calories/protein_grams/carbs_grams/fat_grams (int) — the canonical target the EF now reads" }
  - { tier: 6, layer: edge_function_vs_deploy, status: fixed_in_this_batch, evidence: "weekly-report/index.ts edited to read the canonical target; deploy + smoke (target==3069/140 for upendra) pending in the deploy phase" }
impact_analysis: >
  Platform blast radius — affects every PRO user's Weekly Report. The dual-SoT
  (EF recomputing vs the app's stored target) meant the report's headline numbers
  never matched the rest of the app; reading the canonical stored target makes them
  identical by construction. The 7-day cache compounded it (a stale report showed
  old numbers + 0s); refresh-on-open makes the report reflect current cloud data
  (now correct after the sync-ID fixes d4b8e2 land the workout/nutrition rows). The
  EF fall-back path is conservative (only fires when daily_calories is null — legacy
  profiles that predate target persistence). Found via the founder's APK observation
  (images 3/4/5) + live user_profile inspection.
---

# Weekly report — recomputed target (dual-SoT) + a 7-day-stale cache

## What happened
The report showed 3141 kcal / 155 g (vs the app's 3069 / 140) and 0 workouts.

## Root cause
1. `weekly-report/index.ts` recomputed its own target (`tdee×1.1`, `weight×2`)
   instead of reading `user_profile.daily_calories` / `protein_grams`.
2. `reports_screen.dart` treated the cached EF report as valid for 7 days and
   never refreshed — the founder saw a multi-day-old report.

## Fix
- EF reads the canonical stored target (fall back to the estimate only when null).
- `reports_screen` refreshes on open via `_generateReport(silent: true)` (cached
  report stays visible until the fresh one lands; transient failures keep the cache).

## Verification
- Live: `user_profile` has the canonical macro columns; post-deploy invoke returns
  3069/140 for upendra.
- `weekly_report_canonical_target_test.dart` source-grep.

## See also
- `supabase/functions/weekly-report/index.ts`, `lib/features/profile/screens/reports_screen.dart`
- Related: the report's "0 workouts" deeper cause is the sync-ID collision `d4b8e2`.
