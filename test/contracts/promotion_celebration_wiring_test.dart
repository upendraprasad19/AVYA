// test/contracts/promotion_celebration_wiring_test.dart
//
// Contract — Theme B (closes-diagnose 9aa2c1).
//
// Pins the wiring that surfaces the pre-existing PromotionCelebrationScreen
// on a real rank promotion. Pre-fix: the widget existed at
// lib/features/profile/screens/promotion_celebration_screen.dart with a
// full implementation (animated insignia paint-on, ceremony text,
// baseline→today stats, share button, 30s auto-dismiss) but ZERO call
// sites in the codebase. Founder never saw the celebration after
// promoting from SD2 to LT.
//
// Fix wires it via a one-shot Hive flag pattern:
//   - RankService.evaluateAndPromote stamps userBox[
//     'pending_promotion_rank_code'] when a real rank change is detected.
//   - UserRepository owns getPendingPromotionRankCode /
//     setPendingPromotionRankCode / clearPendingPromotionRankCode helpers.
//   - HomeScreen reads + clears + pushes the modal on initTab() AND on
//     AppLifecycleState.resumed.
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('UserRepository — pending promotion helpers', () {
    final src = File('lib/shared/repositories/user_repository.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('declares the pending_promotion_rank_code constant', () {
      expect(
        stripped.contains("_pendingPromotionKey = 'pending_promotion_rank_code'"),
        isTrue,
        reason:
            'UserRepository must declare a private _pendingPromotionKey '
            'constant so both setter+getter+clearer point at the same '
            'Hive slot.',
      );
    });

    test('exposes getPendingPromotionRankCode + setter + clearer', () {
      expect(
        stripped.contains('String? getPendingPromotionRankCode()'),
        isTrue,
        reason: 'must expose getter returning nullable String.',
      );
      expect(
        RegExp(r'Future<void>\s+setPendingPromotionRankCode\s*\(\s*String')
            .hasMatch(stripped),
        isTrue,
        reason: 'must expose setter accepting rankCode String.',
      );
      expect(
        stripped.contains('Future<void> clearPendingPromotionRankCode()'),
        isTrue,
        reason: 'must expose clearer for idempotent one-shot consumption.',
      );
    });

    test('helpers are top-level userBox keys, not inside the progress map',
        () {
      // Implementation detail BUT this is what keeps the field from
      // syncing to cloud (no user_progress column). If someone moves
      // it inside progress, the F-NEW syncProgressNow fix would attempt
      // to sync it and we'd need a cloud column.
      final idx = stripped.indexOf('_pendingPromotionKey');
      expect(idx, greaterThan(-1));
      // The setter must call _hive.userBox.put — not saveProgress / merge
      // into the progress map.
      final setterIdx = stripped.indexOf('setPendingPromotionRankCode');
      final setterTail = stripped.substring(setterIdx, setterIdx + 300);
      expect(
        setterTail.contains('_hive.userBox.put(_pendingPromotionKey'),
        isTrue,
        reason: 'setter must write to a top-level userBox key, not inside '
            'the progress map (avoids accidental cloud sync via the F-NEW '
            'syncProgressNow fan-out).',
      );
    });
  });

  group('RankService stamps pending promotion on real rank change', () {
    final src =
        File('lib/core/services/rank_service.dart').readAsStringSync();
    final stripped = _stripComments(src);

    test('calls setPendingPromotionRankCode inside the rank-changed branch',
        () {
      // Match the call across whitespace/newlines — the call site uses a
      // multi-line `await UserRepository.instance\n    .setPending...`
      // shape which a literal `contains` would miss.
      expect(
        RegExp(r'UserRepository\.instance\s*\.\s*setPendingPromotionRankCode')
            .hasMatch(stripped),
        isTrue,
        reason: 'RankService.evaluateAndPromote must stamp the pending '
            'promotion only when the rank actually changed. Calling it on '
            'every evaluateAndPromote would re-fire the celebration on '
            'every workout completion.',
      );
    });

    test('stamp is guarded by currentCode != qualified.code branch', () {
      // The stamp must be physically inside the changed-branch. Match
      // the call (multi-line-tolerant) then walk backwards.
      final stampMatch =
          RegExp(r'UserRepository\.instance\s*\.\s*setPendingPromotionRankCode')
              .firstMatch(stripped);
      expect(stampMatch, isNotNull);
      final stampIdx = stampMatch!.start;
      final pre = stripped.substring(0, stampIdx);
      expect(
        pre.contains('currentCode != qualified.code'),
        isTrue,
        reason:
            'the stamp must live INSIDE the `if (currentCode != qualified.code)` '
            'branch — outside, it would fire on every evaluation, '
            'producing duplicate celebrations.',
      );
    });

    test('emits rank_promotion_pending_stamped telemetry', () {
      expect(
        stripped.contains("'rank_promotion_pending_stamped'"),
        isTrue,
        reason: 'must emit telemetry on every successful stamp so we can '
            'query client_errors for "did the celebration fire?" without '
            'instrumenting the device.',
      );
    });
  });

  group('HomeScreen reads + clears + pushes modal', () {
    final src = File('lib/features/home/screens/home_screen.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('mixes in WidgetsBindingObserver', () {
      expect(
        RegExp(r'with\s+HiveTabScaffoldMixin<HomeScreen>\s*,\s*WidgetsBindingObserver')
            .hasMatch(stripped),
        isTrue,
        reason: 'HomeScreen must register WidgetsBindingObserver to catch '
            'AppLifecycleState.resumed — pending promotion may be stamped '
            'while the app is paused (background sync running RankService).',
      );
    });

    test('initState adds + dispose removes the observer', () {
      expect(
        stripped.contains('WidgetsBinding.instance.addObserver(this)'),
        isTrue,
        reason: 'initState must add observer.',
      );
      expect(
        stripped.contains('WidgetsBinding.instance.removeObserver(this)'),
        isTrue,
        reason: 'dispose must remove observer to avoid leak warnings.',
      );
    });

    test('didChangeAppLifecycleState resumes → _maybeShowPendingPromotion',
        () {
      expect(
        RegExp(r'AppLifecycleState\.resumed[\s\S]{0,200}?'
                r'_maybeShowPendingPromotion\(\)')
            .hasMatch(stripped),
        isTrue,
        reason: 'resume handler must call _maybeShowPendingPromotion so '
            'celebration fires after app backgrounds.',
      );
    });

    test('initTab also fires _maybeShowPendingPromotion', () {
      expect(
        stripped.contains('_maybeShowPendingPromotion()'),
        isTrue,
        reason: 'first-mount path (initTab) must also check the slot.',
      );
    });

    test('_maybeShowPendingPromotion clears slot BEFORE pushing modal', () {
      // Idempotency guard — clear-then-push means re-firing resume won't
      // double-render the modal.
      final idx = stripped.indexOf('void _maybeShowPendingPromotion()');
      expect(idx, greaterThan(-1));
      final body = stripped.substring(idx, idx + 1500);
      final clearIdx = body.indexOf('clearPendingPromotionRankCode');
      final pushIdx = body.indexOf('Navigator.of(context).push');
      expect(clearIdx, greaterThan(-1));
      expect(pushIdx, greaterThan(-1));
      expect(clearIdx < pushIdx, isTrue,
          reason: 'must clear the slot BEFORE pushing — otherwise a '
              'resume during the celebration re-fires the modal.');
    });

    test('pushes PromotionCelebrationScreen with newRankCode', () {
      expect(
        RegExp(r'PromotionCelebrationScreen\s*\(\s*newRankCode:\s*rankCode')
            .hasMatch(stripped),
        isTrue,
        reason: 'must instantiate PromotionCelebrationScreen with '
            'newRankCode argument set to the stamped rank code.',
      );
    });

    test('telemetry emitted when celebration is shown', () {
      expect(
        stripped.contains("'rank_promotion_celebration_shown'"),
        isTrue,
        reason: 'must emit rank_promotion_celebration_shown so we can '
            'verify the wiring actually fires for real users without '
            'instrumenting their device.',
      );
    });
  });
}
