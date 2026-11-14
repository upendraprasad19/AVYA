---
bug_id: e1c6a9
date: 2026-06-02
batch: apk-obs-2026-06-02
status: fixed
blast_radius: feature
symptom: >
  On the Home weight view, logging a weight after a 7+ day gap rendered a single
  isolated dot — misleading (reads as a stray entry, not a trend). The old
  WardSpark sparkline only plotted points inside the selected range (default 7d),
  so a lone recent weigh-in with no other in-window point drew one dot; it also
  spaced points evenly by index, ignoring real date gaps. The founder wanted the
  richer trend chart (range chips + goal line) on Home with a connecting line
  across non-logged days.
concept: weight_trend_home_chart
sot_registry_entry: weight_logs
writers: lib/core/services/health_write_service.dart logWeight (Hive healthBox key weight_${istDateStr}, fields type:'weight_log', date, weight_kg).
readers: >
  lib/features/home/providers/home_provider.dart weightHistoryProvider
  (List<WeightEntryData>, all entries) → lib/features/home/screens/home_screen.dart
  _buildWeightSparkline → NEW lib/shared/widgets/weight_trend_chart.dart
  WeightTrendChart (replaced the deleted weight_sparkline.dart).
hive_key_prefix: weight_
hive_key_formula: weight_${istDateStr(date)} (HealthWriteService.logWeight)
sync_methods: _syncWeightLogs (weight_logs) — unchanged by this fix (the id/onConflict fix lives in d4b8e2)
restore_methods: health restore path (cloud weight_logs → weight_* Hive)
cloud_table: weight_logs (read indirectly via Hive)
cloud_columns: weight_logs(user_id, date, weight_kg, notes, created_at) — read for the chart via Hive after restore.
contract_test_path: test/contracts/weight_trend_chart_gap_connect_test.dart
ist_handling: >
  the chart parses each point's istDateStr 'date' and plots x = days-since-first,
  so the date axis is IST-consistent with the stored keys; no UTC date math.
provider_invalidations: >
  weightHistoryProvider is invalidated on weight log + day rollover (home_screen);
  the chart rebuilds from it. No new invalidation needed.
telemetry_op_types: not_applicable (display widget; no telemetry)
cross_account_guard: >
  preserved — weightHistoryProvider watches authUserIdTokenProvider + reads the
  user-scoped healthBox; the chart is a pure render of that.
forbidden_patterns_checked:
  - "Home weight chart that drops a lone in-window point to a single dot / spaces points by index ignoring date gaps — eliminated; WeightTrendChart uses a date-proportional x-axis and carries the last pre-window point into the series so a post-gap weigh-in always draws a connecting line. Pinned by test/contracts/weight_trend_chart_gap_connect_test.dart."
proposed_fix: >
  New shared lib/shared/widgets/weight_trend_chart.dart (fl_chart) with range chips
  (All/1Y/6M/3M/1M/1W), a dashed goal line from target_weight_kg, and a
  DATE-PROPORTIONAL x-axis (days since the first shown point). Crucially it CARRIES
  the last logged point strictly BEFORE the selected window into the series, so a
  recent weigh-in after a gap always connects to prior history with a line — never
  a lone dot. A genuine single-ever weigh-in (no prior point to connect to) shows
  one point + a "log again to see your trend" hint. Wired into Home
  (_buildWeightSparkline) replacing the deleted weight_sparkline.dart; targetWeight
  read from the profile; onViewFullHistory → /profile/reports.
regression_test_planned: >
  test/contracts/weight_trend_chart_gap_connect_test.dart: a sparse fixture
  (one weigh-in ~12 days ago + one today) within a 7d window yields ≥2 plotted
  points (the carry-forward anchor + today) → a connecting line, not a lone dot;
  the x of the two points differs by ~12 (date-proportional, not index-1-apart).
  (Tests the pure windowing/carry-forward helper.)
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "WeightTrendChart added (date-proportional x + carry-forward); home_screen wired to it; old weight_sparkline.dart deleted; flutter analyze clean after adding the spacing import" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "reads weightHistoryProvider (healthBox weight_* rows); upendra live data shows the gap (last weigh-in 05-21, then today) that produced the lone dot" }
impact_analysis: >
  Feature blast radius — Home weight visualisation only; no data write path. Affects
  any user who logs weight intermittently (the common case): the old sparkline drew
  a lone dot when only one point fell in the range. The new chart's carry-forward +
  date-proportional x always show a continuous trend line and the gap at its true
  width, matching the founder's requested design (range chips + goal line). Reuses
  the proven fl_chart config from the Reports screen. Found via the founder's APK
  observation (the weight-graph screenshot + "logged after 7+ days, saw a dot").
---

# Home weight chart — lone dot after a logging gap

## What happened
Logging weight after a 7+ day gap showed a single isolated dot on Home, not a
trend line. The founder asked for the richer trend chart (range chips + goal
line) with a connecting line across non-logged days.

## Root cause
The old `weight_sparkline.dart` (WardSpark) only plotted in-window points and
spaced them by index. A lone recent weigh-in with no other in-window point → one
dot; gaps weren't proportional.

## Fix
New `WeightTrendChart` (fl_chart): range chips, dashed goal line, **date-
proportional x-axis**, and it **carries the last pre-window point into the
series** so a post-gap weigh-in always draws a connecting line — never a lone
dot. Wired into Home; old sparkline deleted.

## Verification
`flutter analyze` clean; `weight_trend_chart_gap_connect_test.dart` (sparse
fixture → ≥2 points + proportional x).

## See also
- `lib/shared/widgets/weight_trend_chart.dart`, `lib/features/home/screens/home_screen.dart`
- Reuses the Reports-screen fl_chart pattern; `weight_logs` SoT.
