// test/contracts/profile_provider_single_source_test.dart
//
// Regression contract for diagnose b3c9d4 — "Profile tab serves a pre-restore
// profile map for the whole session".
//
// The bug: Home and Profile read the SAME Hive key through DIFFERENT providers.
// `userFirstNameProvider` did its own `UserRepository.instance.getProfile()`;
// `userProfileProvider` did another. A returning user reaches /home while the
// cloud restore is still in flight (`restoring_screen.dart:307` background
// branch), so both cached a map with no `full_name`. When the restore landed,
// `home_screen.invalidateOnRetry` refreshed the name providers but NOT
// `userProfileProvider` — so Home healed and Profile / Edit Profile served the
// pre-restore snapshot for the rest of the session. Founder saw Home render
// "UPENDRA" while Profile rendered "User" and Edit Profile rendered blank.
//
// The protection is the BEHAVIORAL group: invalidating ONLY the source provider
// must reach every derived reader. Pre-fix that is impossible — the name
// providers held their own snapshot — so these tests fail on the pre-fix code.
//
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_completeness_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/mixins/hive_tab_scaffold.dart';

import '../helpers/hive_test_setup.dart';

/// The pre-restore shape: the profile map EXISTS (so the probe reports
/// `hasProfile=true`, exactly as the live rows did) but `full_name` has not
/// merged yet — it lives on `users`, not `user_profile`.
const _preRestore = <String, dynamic>{
  'primary_goal': 'build_muscle',
  'gender': 'male',
  'date_of_birth': '1988-06-30',
};

/// The same map after the background restore merges the `users` row.
///
/// "Bruce Wayne" rather than the founder's own name on purpose: its first name
/// ("BRUCE") differs from the `'User'` fallback AND its initial ("B") differs
/// from the `'U'` fallback. With a name starting in U, the initial assertion
/// would pass even if the feature did nothing at all.
const _postRestore = <String, dynamic>{
  'primary_goal': 'build_muscle',
  'gender': 'male',
  'date_of_birth': '1988-06-30',
  'full_name': 'Bruce Wayne',
};

void main() {
  late Directory tempDir;
  late List<String> events;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    events = <String>[];
    ErrorTelemetry.debugOnLogEventForTests = (op, {String? message}) {
      events.add('$op ${message ?? ''}');
    };
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    await tearDownHiveForTests(tempDir);
  });

  // ── The bug, reproduced ────────────────────────────────────────────────

  group('single source: invalidating userProfileProvider reaches every reader',
      () {
    test(
        'a restore landing AFTER first paint updates the name providers when '
        'ONLY userProfileProvider is invalidated', () async {
      await HiveService.instance.userBox.put('profile', _preRestore);

      final c = ProviderContainer();
      addTearDown(c.dispose);

      // First paint, mid-restore — this is what the founder's Home rendered at
      // 19:23:27 IST and what Profile kept rendering afterwards.
      expect(c.read(userFirstNameProvider), 'USER');
      expect(c.read(userInitialProvider), 'U');
      expect(c.read(userProfileProvider)['full_name'], isNull);

      // The background restore completes and merges the users row into Hive.
      await HiveService.instance.userBox.put('profile', _postRestore);

      // Exactly what the restore tick now does — and ONLY the source provider.
      // That is the whole point: pre-fix each name provider held its own Hive
      // snapshot, so invalidating the source could not reach them and they
      // stayed on 'USER' forever.
      c.invalidate(userProfileProvider);

      expect(c.read(userFirstNameProvider), 'BRUCE',
          reason: 'Derived from userProfileProvider — invalidating the source '
              'must rebuild it. Pre-fix this stayed USER, which is the '
              'Home-vs-Profile divergence the founder reported.');
      expect(c.read(userInitialProvider), 'B',
          reason: 'B (not the U fallback) proves a real value was read.');
      expect(c.read(userGreetingProvider), contains('Bruce'));
    });

    test('all four providers agree — Home and Profile cannot diverge', () async {
      await HiveService.instance.userBox.put('profile', _postRestore);

      final c = ProviderContainer();
      addTearDown(c.dispose);

      // Profile tab's reader and Home's readers resolve to the same map.
      final viaProfileTab = c.read(userProfileProvider)['full_name'] as String?;
      expect(viaProfileTab, 'Bruce Wayne');
      expect(c.read(userFirstNameProvider), 'BRUCE');
      expect(c.read(userInitialProvider), 'B');
      expect(c.read(userGreetingProvider), contains('Bruce'));
    });

    test('the empty-map case still reports hasProfile faithfully', () async {
      // getProfile() returned null for an absent map; userProfileProvider maps
      // that to {}. The probe's hasProfile field must follow the same meaning.
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(c.read(userFirstNameProvider), 'USER');
      expect(
          events.where((e) =>
              e.startsWith('profile_full_name_empty_at_read') &&
              e.contains('hasProfile=false')),
          isNotEmpty,
          reason: 'No profile map at all must read hasProfile=false.');

      events.clear();
      await HiveService.instance.userBox.put('profile', _preRestore);
      c.invalidate(userProfileProvider);

      expect(c.read(userFirstNameProvider), 'USER');
      expect(
          events.where((e) =>
              e.startsWith('profile_full_name_empty_at_read') &&
              e.contains('hasProfile=true')),
          isNotEmpty,
          reason: 'A map that exists but lacks full_name must read '
              'hasProfile=true — the exact live signature of this bug.');
    });

    test('profile completeness follows the source too — the 94% in the '
        "founder's screenshot (round-1 review finding 1)", () async {
      await HiveService.instance.userBox.put('profile', _preRestore);

      final c = ProviderContainer();
      addTearDown(c.dispose);

      final before = c.read(profileCompletenessProvider).percentage;

      await HiveService.instance.userBox.put('profile', _postRestore);
      c.invalidate(userProfileProvider);

      final after = c.read(profileCompletenessProvider).percentage;

      // full_name is 1 of 10 kTier1Fields and tier 1 is weighted 60%, so
      // exactly 6 points. Derived from the data, not read off the impl.
      expect(after - before, 6,
          reason: 'profileCompletenessProvider was a FOURTH independent Hive '
              'read sitting in NO invalidateOnRetry list, so it cached the '
              'pre-restore map for the session and rendered a permanently '
              'wrong percentage on the same screen as the wrong name. '
              'Reverting it to UserRepository.instance.getProfile() makes '
              'after == before and this fails.');
    });
  });

  // ── The mixin: every tab, not just Home ────────────────────────────────

  group('HiveTabScaffoldMixin listens for the background restore', () {
    testWidgets('a completed restore refreshes a tab that is not Home',
        (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _ProbeTab(onRefresh: () => refreshes++),
        ),
      ));

      expect(refreshes, 0, reason: 'Nothing has happened yet.');

      // What heal_after_restore.dart:74 does when the restore lands.
      SyncService.instance.bumpRestoreCompleted();
      await tester.pump();

      expect(refreshes, 1,
          reason: 'Before this fix the tick was wired ONLY in home_screen, so '
              'Nutrition, Train and Profile never refreshed after a background '
              'restore. A screen that merely mixes in HiveTabScaffoldMixin '
              'must now get it with nothing to remember.');
    });

    testWidgets(
        'the tick routes through invalidateOnBackgroundRestore, NOT '
        'invalidateOnRetry directly (B-pass finding 1)', (tester) async {
      var background = 0, retry = 0;
      await tester.pumpWidget(ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _SplitProbeTab(
            onBackground: () => background++,
            onRetry: () => retry++,
          ),
        ),
      ));

      SyncService.instance.bumpRestoreCompleted();
      await tester.pump();

      expect(background, 1,
          reason: 'a completed background restore must use the background '
              'hook so a screen can exclude providers that are unsafe to '
              'invalidate without a user action behind it');
      expect(retry, 0,
          reason: 'a screen that OVERRIDES invalidateOnBackgroundRestore must '
              'not also get invalidateOnRetry — otherwise the exclusion it '
              'just declared is silently ignored. Reverting the mixin to call '
              'invalidateOnRetry(ref) makes this fail.');
    });

    test('Nutrition excludes aiBreakdownProvider from the background path',
        () {
      final src = File('lib/features/nutrition/screens/nutrition_screen.dart')
          .readAsStringSync();
      final bg = src.substring(src.indexOf('void invalidateOnBackgroundRestore'));
      expect(bg.contains('aiBreakdownProvider'), isFalse,
          reason: 'ai_mode_body.dart:41 pops the Log Food sheet on that '
              "provider's non-null -> null transition. Invalidating it from "
              'the restore tick discards a just-generated AI analysis.');
      expect(bg.contains('dailyNutritionProvider'), isTrue,
          reason: 'the rest of the set must still refresh — this exclusion is '
              'surgical, not a disabling of the background refresh.');
    });

    testWidgets('the listener is removed on dispose', (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _ProbeTab(onRefresh: () => refreshes++),
        ),
      ));
      SyncService.instance.bumpRestoreCompleted();
      await tester.pump();
      expect(refreshes, 1);

      // Unmount the tab, then fire again.
      await tester.pumpWidget(ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: const SizedBox.shrink(),
        ),
      ));
      SyncService.instance.bumpRestoreCompleted();
      await tester.pump();

      expect(refreshes, 1,
          reason: 'A disposed tab must not keep refreshing — an un-removed '
              'listener leaks the State and fires ref on a dead element.');
    });
  });
}

/// A tab that OVERRIDES the background hook — proves the seam is real and
/// that the mixin does not also fire invalidateOnRetry behind its back.
class _SplitProbeTab extends ConsumerStatefulWidget {
  const _SplitProbeTab({required this.onBackground, required this.onRetry});
  final VoidCallback onBackground;
  final VoidCallback onRetry;

  @override
  ConsumerState<_SplitProbeTab> createState() => _SplitProbeTabState();
}

class _SplitProbeTabState extends ConsumerState<_SplitProbeTab>
    with HiveTabScaffoldMixin<_SplitProbeTab> {
  @override
  void invalidateOnRetry(WidgetRef ref) => widget.onRetry();

  @override
  void invalidateOnBackgroundRestore(WidgetRef ref) => widget.onBackground();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Minimal stand-in for a tab screen: mixes in the real
/// [HiveTabScaffoldMixin] and records each `invalidateOnRetry` call. Renders
/// nothing styled on purpose — a widget test that renders an AppTypography
/// style walks GoogleFonts into its fetch-and-save path (CLAUDE.md pitfall).
class _ProbeTab extends ConsumerStatefulWidget {
  const _ProbeTab({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  ConsumerState<_ProbeTab> createState() => _ProbeTabState();
}

class _ProbeTabState extends ConsumerState<_ProbeTab>
    with HiveTabScaffoldMixin<_ProbeTab> {
  @override
  void invalidateOnRetry(WidgetRef ref) => widget.onRefresh();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
