---
bug_id: 7ad0cd
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 3 surfaces (`userStatsProvider`, `train_screen` WeekSelector.onSelect, `swap_sheet`) snapshot `SubscriptionService.instance.isPro()` at build/init time and never reactively rebuild when the user upgrades to PRO mid-session. Same stale-PRO class APK Test #12 / C-2 already closed for the home screen + roadmap surfaces. Result — user pays for PRO, the stats card still says "free", week selector still routes to the read-only preview screen, swap sheet still enforces free-tier restrictions until the page is reopened.
concept: reactive_subscription_three_sites
sot_registry_entry: subscription_info_provider
writers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: SubscriptionInfoNotifier (subscriptionInfoProvider), line: 379 }
readers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: UserStatsNotifier.build, line: 268 }
  - { file: lib/features/train/screens/train_screen.dart, method_or_widget: WeekSelector.onSelect, line: 227 }
  - { file: lib/features/home/widgets/swap_sheet.dart, method_or_widget: _SwapSheetState._onConfirm, line: 113 }
hive_key_prefix: "n/a — reactivity fix; no Hive write involved"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [user_id, plan, status, end_date]
contract_test_path: test/contracts/reactive_subscription_three_sites_test.dart
ist_handling: []
provider_invalidations: [subscriptionInfoProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["userstats_direct_isPro_snapshot", "train_screen_onSelect_direct_isPro", "swap_sheet_isPro_cached_at_initState"]
proposed_fix: (a) `UserStatsNotifier.build` reads `ref.watch(subscriptionInfoProvider).isPro` instead of `SubscriptionService.instance.isPro()`. (b) `train_screen` `WeekSelector.onSelect` callback reads `ref.read(subscriptionInfoProvider).isPro`; the sibling `StreakExplainerSheet.show` site fixed too. (c) `swap_sheet` upgraded from `StatefulWidget` to `ConsumerStatefulWidget`; `late final bool _isPro` field removed; `_onConfirm` reads `ref.read(subscriptionInfoProvider).isPro` at confirm time.
regression_test_planned:
  - test/contracts/reactive_subscription_three_sites_test.dart
---
# Audit H-1 / H-2 / H-2b: stale subscription state on 3 surfaces

## Bug

`SubscriptionService.instance.isPro()` returns a snapshot from Hive
configBox. Three surfaces called it directly at build / init time and
captured the return value into a field or a closure:

- **H-1** `UserStatsNotifier.build` (profile_provider.dart:292) — set
  `isPro: SubscriptionService.instance.isPro()` into the
  `UserStatsData` returned from `build()`. Consumers (`profile_screen`,
  `reports_screen`) treat that bool as authoritative.
- **H-2** `train_screen` WeekSelector `onSelect` callback
  (train_screen.dart:227-238) — read `SubscriptionService.instance.isPro()`
  at tap-time. Same stale-snapshot class.
- **H-2b** `swap_sheet` `_SwapSheetState.initState` — captured
  `_isPro = _subscriptionService.isPro()` into a `late final` field.

All three would stay on "free" UI after a fresh PRO upgrade until the
specific surface rebuilt (page navigation, re-open).

## Cause

The bug class APK Test #12 / C-2 closed the same issue on the home
screen by switching to `ref.watch(subscriptionInfoProvider)`. Three
surfaces missed the sweep — train screen + swap sheet + profile stats
card were all built around direct service calls before
`subscriptionInfoProvider` existed.

## Fix

- `UserStatsNotifier.build`:
  ```dart
  final isPro = ref.watch(subscriptionInfoProvider).isPro;
  return UserStatsData(... isPro: isPro);
  ```
- `train_screen` WeekSelector callback:
  ```dart
  final isProUser = ref.read(subscriptionInfoProvider).isPro;
  ```
  Plus the sibling `StreakExplainerSheet.show` site (line 374-377)
  fixed in the same edit.
- `swap_sheet`:
  - `extends StatefulWidget` → `extends ConsumerStatefulWidget`
  - `late final bool _isPro` field removed
  - `_isPro = _subscriptionService.isPro()` line removed
  - `_onConfirm` reads `final isPro = ref.read(subscriptionInfoProvider).isPro;`

## Regression test

`test/contracts/reactive_subscription_three_sites_test.dart` — 4
source-grep cases:

1. UserStatsNotifier body contains `ref.watch(subscriptionInfoProvider)`.
2. WeekSelector callback contains `ref.read(subscriptionInfoProvider)`.
3. swap_sheet does NOT carry `late final bool _isPro` field or
   `_isPro = _subscriptionService.isPro()` line; DOES carry
   `ref.read(subscriptionInfoProvider)`.
4. swap_sheet class extends ConsumerStatefulWidget + state extends
   ConsumerState.

Suite: 1557 pass / 0 fail / 2 skip.

## Related

- APK Test #12 / C-2 (closed the home screen + roadmap surfaces)
- CLAUDE.md Bug class "PRO upgrade pills don't unlock after payment"
