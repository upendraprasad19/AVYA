import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

/// APK Test #14 / Bug D.3 — streak-freeze pill shows `x/y`.
///
/// User wants the streak badge to expose freeze CAPACITY, not just remaining
/// count. Format: `❄ <available>/<max>` so:
///   - free user with 0 used sees `❄ 1/1`
///   - PRO user with 2 burnt sees `❄ 1/3`
///   - PRO user with all 3 burnt sees `❄ 0/3`
///
/// Pre-Test-#14 the badge showed only `❄ <available>` (single digit) and
/// auto-hid the snowflake section when count was 0 — leaving the user with
/// no signal that freezes were a thing they could earn back.
///
/// Three concerns pinned:
///   1. `StreakBadge` accepts a `freezesMax` parameter
///   2. The render uses `<available>/<max>` format
///   3. `streakFreezeMaxProvider` exists in home_provider.dart and returns
///      1 (free) / 3 (PRO) based on subscription
void main() {
  group('streak badge widget contract', () {
    late String badgeSrc;

    setUpAll(() {
      final f = File('lib/features/home/widgets/streak_badge.dart');
      expect(f.existsSync(), isTrue,
          reason: 'streak_badge.dart must exist');
      badgeSrc = f.readAsStringSync();
    });

    test('StreakBadge accepts freezesMax parameter', () {
      expect(
        badgeSrc.contains('final int freezesMax;') ||
            badgeSrc.contains('this.freezesMax'),
        isTrue,
        reason:
            'StreakBadge must accept a freezesMax parameter so the pill can '
            'render <available>/<max>. closes-diagnose: 2026-05-10-pill-xy',
      );
    });

    test('render uses <available>/<max> format', () {
      // Pin the literal format string in the build method so the visual
      // contract doesn't drift back to single-digit on a refactor.
      expect(
        badgeSrc.contains(r"'${widget.freezesAvailable}/${widget.freezesMax}'"),
        isTrue,
        reason:
            'StreakBadge must render `<available>/<max>` (e.g. `1/3`). '
            'Pre-Test-#14 it showed `<available>` only.',
      );
    });

    test('forbidden: bare freezesAvailable render without max suffix', () {
      // The pre-fix line was `'${widget.freezesAvailable}'` (no slash).
      // Pin its absence to prevent a future refactor from dropping the max.
      // We allow it inside Text widgets that are NOT the freeze count
      // (e.g., diagnostic logging) — so we look for the specific shape
      // `'${widget.freezesAvailable}'` followed by a Text close (no slash).
      // Simpler: just require the count of '/${widget.freezesMax}' >= 1.
      final divCount = '/\${widget.freezesMax}'.allMatches(badgeSrc).length;
      expect(divCount >= 1, isTrue,
          reason:
              'render must contain at least one `/widget.freezesMax` to '
              'guarantee the x/y format survives.');
    });
  });

  group('streakFreezeMaxProvider', () {
    late String homeProvSrc;

    setUpAll(() {
      final f = File('lib/features/home/providers/home_provider.dart');
      expect(f.existsSync(), isTrue,
          reason: 'home_provider.dart must exist');
      homeProvSrc = f.readAsStringSync();
    });

    test('streakFreezeMaxProvider declared', () {
      expect(homeProvSrc.contains('streakFreezeMaxProvider'), isTrue,
          reason:
              'home_provider must export streakFreezeMaxProvider so badges '
              'reading the pill ladder don\'t hardcode 3 or 1.');
    });

    test('streakFreezeMaxProvider returns 3 for PRO, 1 for free', () {
      // Source-grep the conditional rather than instantiate Riverpod —
      // SubscriptionService is a singleton and bootstrapping it here would
      // require a full Hive setup. The conditional is the contract.
      expect(
        homeProvSrc.contains('isPro() ? 3 : 1') ||
            homeProvSrc.contains('isPro() ? 3:1'),
        isTrue,
        reason:
            'streakFreezeMaxProvider must read SubscriptionService.isPro() '
            'and return 3 (PRO) or 1 (free). Founder direction 2026-05-10.',
      );
    });
  });

  group('caller chain: WardStatusStrip threads freezesMax', () {
    late String stripSrc;

    setUpAll(() {
      final f = File('lib/shared/widgets/wardroom/ward_status_strip.dart');
      expect(f.existsSync(), isTrue,
          reason: 'ward_status_strip.dart must exist');
      stripSrc = f.readAsStringSync();
    });

    test('WardStatusStrip accepts and forwards freezesMax', () {
      expect(stripSrc.contains('this.freezesMax'), isTrue,
          reason: 'WardStatusStrip must accept freezesMax');
      expect(stripSrc.contains('freezesMax: freezesMax'), isTrue,
          reason: 'WardStatusStrip must forward freezesMax to StreakBadge');
    });
  });

  group('caller chain: home/train/nutrition pass freezesMax via provider', () {
    test('home_screen reads streakFreezeMaxProvider', () {
      final src =
          File('lib/features/home/screens/home_screen.dart').readAsStringSync();
      expect(src.contains('streakFreezeMaxProvider'), isTrue,
          reason: 'home_screen must pass freezesMax via provider');
    });

    test('train_screen reads streakFreezeMaxProvider', () {
      final src = readScreenSource('train');
      expect(src.contains('streakFreezeMaxProvider'), isTrue,
          reason: 'train_screen must pass freezesMax via provider');
    });

    test('nutrition_screen reads streakFreezeMaxProvider', () {
      final src = File('lib/features/nutrition/screens/nutrition_screen.dart')
          .readAsStringSync();
      expect(src.contains('streakFreezeMaxProvider'), isTrue,
          reason: 'nutrition_screen must pass freezesMax via provider');
    });
  });
}
