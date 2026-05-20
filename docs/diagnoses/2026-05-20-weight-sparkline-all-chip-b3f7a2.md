---
bug_id: b3f7a2
date: 2026-05-20
batch: APK Test #16.2 observations (2026-05-20 — obs 4)
status: shipped
symptom: |
  Founder asked on 2026-05-20: "in the weight graph in dashboard screen,
  what if user wants to see more than 90 days data?" The dashboard
  Weight Trend card (lib/features/home/widgets/weight_sparkline.dart)
  exposed only 7D / 30D / 90D chips per the original daily.jsx handoff
  spec. Comment at lines 26-28 documented the deliberate removal of
  legacy 1y / All chips. Founder revised the product call after
  realizing long-range data was already available but unreachable
  from the dashboard without navigating to Reports — and that the
  Reports destination wasn't obvious from this card.
concept: weight_trend_range
sot_registry_entry: weight
writers:
  - { file: lib/features/home/widgets/weight_sparkline.dart, method_or_widget: WeightSparkline._ranges constant extended to include 'all' + footer link added, line: 31 }
readers:
  - { file: lib/features/home/widgets/weight_sparkline.dart, method_or_widget: WeightSparkline._filteredEntries reads _selectedRange + filters widget.entries, line: 38 }
  - { file: lib/features/profile/screens/reports_screen.dart, method_or_widget: ReportsScreen renders the full-history chart users land on via the new link, line: 489 }
hive_key_prefix: "weight_"
hive_key_formula: "weight_<istDateStr> with type='weight_log' (per CLAUDE.md weight contract)"
sync_methods: [_syncWeightLogs, syncWeightNow]
restore_methods: [_restoreWeightLogs]
cloud_table: weight_logs
cloud_columns: [user_id, date, weight_kg]
contract_test_path: test/contracts/weight_sparkline_all_chip_and_footer_link_test.dart
ist_handling:
  - { file: lib/features/home/widgets/weight_sparkline.dart, line: 48, source: "cutoff converted to IST before lexical compareTo on YYYY-MM-DD strings; mirrors HealthWriteService.istDateStr semantics" }
provider_invalidations: [weightHistoryProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Widget reads from `widget.entries` (passed in by ConsumerWidget parent at home_screen.dart); upstream weightHistoryProvider already watches authUserIdTokenProvider for cross-account rebuilds.
forbidden_patterns_checked:
  - "Re-introducing the 90D hardcap on the dashboard chip set without also revising the comment at lines 26-30 — would mask the founder's intentional decision."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "_ranges extended, _filteredEntries switch extended, footer link added, comment block updated to reflect the new intent" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "no Hive contract change; weight_<istDateStr> keys and the type='weight_log' filter unchanged" }
  - { tier: 5, name: cloud_sync_outbound, status: verified, evidence: "no sync path change; _syncWeightLogs / syncWeightNow unchanged" }
  - { tier: 6, name: cloud_sync_restore, status: verified, evidence: "_restoreWeightLogs already pulls since='2020-01-01T00:00:00Z' (full lifetime); ALL chip exposes data that was always there" }
  - { tier: 9, name: provider_invalidation, status: verified, evidence: "weightHistoryProvider invalidation set unchanged" }
  - { tier: 11, name: ist_correctness, status: verified, evidence: "IST cutoff conversion at line 48 preserved; ALL branch uses DateTime(1970) sentinel which is well outside any IST boundary edge case" }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "test/contracts/weight_sparkline_all_chip_and_footer_link_test.dart pins ALL chip + go_router import + /profile/reports navigation + 'View full history' copy" }
impact_analysis:
  callers_audited:
    - lib/features/home/screens/home_screen.dart (renders WeightSparkline in the dashboard)
    - lib/features/profile/screens/reports_screen.dart (destination of the new footer link — already exists with All/1Y/6M/3M/1M/1W chips + projection callout)
  callers_updated_in_this_batch:
    - lib/features/home/widgets/weight_sparkline.dart (chip set + footer link + comment revision)
  callers_unchanged:
    - lib/features/profile/screens/reports_screen.dart (destination unchanged, just newly linked from dashboard)
    - lib/features/home/providers/home_provider.dart (weightHistoryProvider already exposed full series)
proposed_fix: |
  Three coordinated changes inside weight_sparkline.dart:

  1. Extend the _ranges constant from `['7d', '30d', '90d']` to
     `['7d', '30d', '90d', 'all']`. The chip label rendering at line 174
     already does `range.toUpperCase()` so the new chip surfaces as
     `ALL` automatically — no label-mapping fork.

  2. Extend the _filteredEntries switch with an explicit
     `'all' => DateTime(1970)` case. The DateTime sentinel is far
     before any plausible weigh-in so the IST cutoff compareTo at
     line 51 trivially passes for every entry. We do NOT short-circuit
     and return widget.entries directly because keeping the same
     compareTo path means any future range additions slot in without
     revisiting an early-return.

  3. Add a `Center(GestureDetector(...))` wrapping a Text widget
     reading "View full history →" below the existing LOW / HIGH /
     N ENTRIES summary row. onTap calls
     `context.go('/profile/reports')`. Styled with the existing
     wardroom accent gold + monoXs typography to stay visually
     consistent with the surrounding eyebrow / chip text.

  Also: update the comment block at lines 26-30 from the legacy
  "1y / All chips removed to match the spec" wording to a brief
  reference to this diagnose-doc explaining the founder's intentional
  re-addition. Future readers shouldn't think the `ALL` chip is a
  regression.

  Founder's locked decision was Option C (hybrid) after considering:
  - Option A (extend chips only): would let the user stay on the
    dashboard but Reports' projection + finer chips would stay hidden.
  - Option B (link only): would honor the original 90D cap but require
    navigation for the simple "show me everything" use case.
  - Option C (hybrid): both. Quick-glance ALL on the card + the rich
    Reports view a tap away.
regression_test_planned:
  - test/contracts/weight_sparkline_all_chip_and_footer_link_test.dart — pins (a) go_router import, (b) `'all'` in _ranges, (c) explicit `'all' =>` switch arm, (d) `context.go('/profile/reports')` navigation, (e) "View full history" copy.
---
# Body

## What changed and why this is a `feat` not a `fix`

The 90D cap on the dashboard was not a bug. It was a deliberate product
decision baked into the `daily.jsx` Wardroom handoff spec and faithfully
implemented at lines 26-28 of `weight_sparkline.dart`. Long-range data
lives at `/profile/reports` (with `All / 1Y / 6M / 3M / 1M / 1W` chips +
a 180-day projection callout). Three things made this batch worthwhile:

1. **Discoverability.** The Reports destination wasn't surfaced from the
   dashboard. Even with obs 3's fix to `usageWeeks` now letting the
   Weekly Report card become tappable, the founder hadn't connected
   "I want to see weight beyond 90 days" with "I should go to the
   Weekly Report screen." The footer link makes the path explicit.

2. **Friction for the quick-glance case.** Adding a single `ALL` chip
   to the dashboard lets a user answer "is my weight trending down
   over my full history" without leaving Home. Reports is for the
   forensic case (specific window, projection math); Home should
   serve the at-a-glance.

3. **Cost is near zero.** No new data, no new providers, no new schema.
   The widget already received the full series via `weightHistoryProvider`
   (verified — no upstream cap exists). The filter logic just needed
   one new switch arm.

## The IST sentinel choice

`DateTime(1970)` is used for the `ALL` cutoff rather than e.g.
`DateTime(0)` or returning `widget.entries` directly. Reasons:

- `DateTime(1970)` is well outside any plausible weight log (the app
  was founded 2026) so the lexical YYYY-MM-DD compareTo at line 51
  always passes.
- Going through the IST conversion path (line 48) keeps the code
  consistent — if a future range addition needs to interact with the
  IST cutoff math, there's no special-case to remember.
- The line-52 fallback `filtered.isEmpty ? widget.entries : filtered`
  is preserved as a safety net for the "user has no weight entries"
  case, same as before.

## What this enables for the founder right now

Founder has ~4 weeks of weight history. With option C shipped:

- The `ALL` chip on the dashboard surfaces all ~4 weeks in one tap
  (today same as 90D for them; meaningfully different for a multi-year
  user).
- The `View full history →` link opens Reports where the projection
  callout uses the same 4-week data to estimate target arrival date
  per the existing logic at reports_screen.dart:543.

## What stays the same

- The `daily.jsx` handoff spec for the dashboard card visual treatment
  (icon, eyebrow, header row layout, Y-axis labels, X-axis labels,
  LOW/HIGH/ENTRIES footer) is unchanged.
- The 90D filter math is the same; we just added a fourth range that
  passes more data through.
- Reports screen is untouched.
