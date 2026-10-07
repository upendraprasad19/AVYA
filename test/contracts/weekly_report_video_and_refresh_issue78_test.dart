import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/features/profile/services/weekly_report_refresh_policy.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

/// Issue #78 / diagnose d7b2e5. Weekly Report screen:
///  * the Share-as-Video row is gone (its backend, `video-status`, is a 410 stub),
///  * Regenerate is replaced by a back button,
///  * the open-time refresh is PRO-only and at most once per IST day,
///  * the card speaks in the coach voice.
void main() {
  group('shouldSilentRefreshWeeklyReport (BEHAVIORAL)', () {
    // 2026-10-08 00:10 IST == 2026-10-07 18:40 UTC. UTC inputs keep the test
    // independent of the machine's time zone (CI pins IST, the VPS is UTC).
    final now = DateTime.utc(2026, 10, 7, 18, 40);

    test('no cache at all -> refresh', () {
      expect(
          shouldSilentRefreshWeeklyReport(
              cachedJson: null, cachedDateIso: null, now: now),
          isTrue);
    });

    test('cache body present but stamp missing / unparseable -> refresh', () {
      expect(
          shouldSilentRefreshWeeklyReport(
              cachedJson: '{}', cachedDateIso: null, now: now),
          isTrue);
      expect(
          shouldSilentRefreshWeeklyReport(
              cachedJson: '{}', cachedDateIso: 'not-a-date', now: now),
          isTrue);
    });

    test('stamp present but body missing -> refresh', () {
      expect(
          shouldSilentRefreshWeeklyReport(
              cachedJson: null,
              cachedDateIso: '2026-10-07T18:35:00Z',
              now: now),
          isTrue);
    });

    test('cached earlier the same IST day -> skip (the cap)', () {
      // 00:05 IST on the 8th, same IST day as `now`.
      expect(
          shouldSilentRefreshWeeklyReport(
              cachedJson: '{}',
              cachedDateIso: '2026-10-07T18:35:00Z',
              now: now),
          isFalse);
    });

    test('cached 20 minutes earlier but across IST midnight -> refresh', () {
      // 23:50 IST on the 7th vs now = 00:10 IST on the 8th. A UTC-date compare
      // would call these the same day; the IST compare must not.
      expect(
          shouldSilentRefreshWeeklyReport(
              cachedJson: '{}',
              cachedDateIso: '2026-10-07T18:20:00Z',
              now: now),
          isTrue);
    });

    test('cached yesterday -> refresh', () {
      expect(
          shouldSilentRefreshWeeklyReport(
              cachedJson: '{}',
              cachedDateIso: '2026-10-06T10:00:00Z',
              now: now),
          isTrue);
    });
  });

  group('reports_screen wiring (PRESENCE-ONLY source pins)', () {
    final screen = _strip(
        File('lib/features/profile/screens/reports_screen.dart')
            .readAsStringSync());

    test('no video row, no video provider, no regenerate button', () {
      for (final dead in [
        'triggerWorkoutVideo',
        'videoRenderNotifierProvider',
        'VideoShareButton',
        '_buildWeeklyVideoShareRow',
        'Share as Video',
        'Regenerate Report',
        'Regenerating',
      ]) {
        expect(screen.contains(dead), isFalse,
            reason: 'reports_screen must not reference "$dead" (issue #78)');
      }
    });

    test('back button routes to /profile', () {
      expect(screen.contains('WardroomCopy.reportBackToProfileCta'), isTrue);
      expect(RegExp(r"context\.go\('/profile'\)").allMatches(screen).length,
          greaterThanOrEqualTo(2),
          reason: 'header BACK + the new bottom back button');
    });

    test('open-time refresh goes through the PRO gate; free does nothing', () {
      final m = RegExp(r'void _refreshOnOpen\(\) \{(.*?)\n  \}\n', dotAll: true)
          .firstMatch(screen);
      expect(m, isNotNull, reason: '_refreshOnOpen must exist');
      final body = m!.group(1)!;
      expect(
          RegExp(r'gateAndVerify\(\s*AppConstants\.featureWeeklyAiReport')
              .hasMatch(body),
          isTrue);
      expect(body.contains('shouldSilentRefreshWeeklyReport('), isTrue);
      expect(body.contains('_generateReport(silent: true)'), isTrue);
      expect(RegExp(r'onFree:\s*\(\)\s*\{\s*\}').hasMatch(body), isTrue,
          reason: 'a free user must NOT silently spend the lifetime report');
      // initState must call the gated wrapper, never the raw silent refresh.
      final init = RegExp(r'void initState\(\) \{(.*?)\n  \}\n', dotAll: true)
          .firstMatch(screen)!
          .group(1)!;
      expect(init.contains('_refreshOnOpen()'), isTrue);
      expect(init.contains('_generateReport('), isFalse);
    });

    test('card title, blurb and free-user line come from WardroomCopy', () {
      expect(screen.contains('AI Weekly Report'), isFalse);
      expect(screen.contains('WardroomCopy.reportCardTitle'), isTrue);
      expect(screen.contains('WardroomCopy.reportCardBlurb'), isTrue);
      expect(screen.contains('WardroomCopy.reportFirstFreeLine'), isTrue);
    });
  });

  group('WardroomCopy (coach voice)', () {
    test('exact strings', () {
      expect(WardroomCopy.reportCardTitle, "Coach's Weekly Dispatch");
      expect(WardroomCopy.reportFirstFreeLine, 'Your first dispatch is on us.');
      expect(
          WardroomCopy.reportCardBlurb,
          'Your coach reads your week — sessions, meals, weight — and '
          'tells you what held, what slipped, and what to fix next.');
    });
  });
}
