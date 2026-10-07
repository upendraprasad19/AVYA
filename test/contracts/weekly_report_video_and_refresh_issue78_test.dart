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

    test('the REAL stamp format (local ISO, no Z) is parsed by IST date', () {
      // _generateReport writes nowWall().toIso8601String(): a LOCAL DateTime,
      // so no trailing Z. Same instants as the Z-suffixed cases above.
      final sameDay = DateTime.utc(2026, 10, 7, 18, 35).toLocal();
      final prevDay = DateTime.utc(2026, 10, 7, 18, 20).toLocal();
      expect(sameDay.toIso8601String().endsWith('Z'), isFalse,
          reason: 'fixture must model the production stamp (local, no Z)');
      expect(
          shouldSilentRefreshWeeklyReport(
              cachedJson: '{}',
              cachedDateIso: sameDay.toIso8601String(),
              now: now),
          isFalse);
      expect(
          shouldSilentRefreshWeeklyReport(
              cachedJson: '{}',
              cachedDateIso: prevDay.toIso8601String(),
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

  group('isLifetimeFreeReportSpent (BEHAVIORAL)', () {
    test('403 with a NOT_PRO body (decoded map or JSON string) -> true', () {
      expect(
          isLifetimeFreeReportSpent(status: 403, details: {'code': 'NOT_PRO'}),
          isTrue);
      expect(
          isLifetimeFreeReportSpent(
              status: 403, details: '{"error":"x","code":"NOT_PRO"}'),
          isTrue);
    });

    test('a 403 that is NOT the free-quota answer -> false', () {
      expect(isLifetimeFreeReportSpent(status: 403, details: null), isFalse);
      expect(
          isLifetimeFreeReportSpent(
              status: 403, details: {'error': 'Forbidden: user_id mismatch'}),
          isFalse);
      expect(isLifetimeFreeReportSpent(status: 403, details: 'Forbidden'),
          isFalse);
    });

    test('NOT_PRO code on a non-403 status -> false', () {
      expect(
          isLifetimeFreeReportSpent(status: 500, details: {'code': 'NOT_PRO'}),
          isFalse);
      expect(
          isLifetimeFreeReportSpent(status: null, details: {'code': 'NOT_PRO'}),
          isFalse);
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

    String between(String start, String end) {
      final i = screen.indexOf(start);
      expect(i, greaterThanOrEqualTo(0), reason: '"$start" must exist');
      final j = screen.indexOf(end, i);
      expect(j, greaterThan(i), reason: '"$end" must follow "$start"');
      return screen.substring(i, j);
    }

    test('open-time refresh goes through the PRO gate; free does nothing', () {
      final body = between('void _refreshOnOpen()', 'Future<void> _generateReport');
      expect(
          RegExp(r'gateAndVerify\(\s*AppConstants\.featureWeeklyAiReport')
              .hasMatch(body),
          isTrue);
      expect(RegExp(r'final due = shouldSilentRefreshWeeklyReport\(')
              .hasMatch(body),
          isTrue);
      expect(
          RegExp(r'if\s*\(due\)\s*_generateReport\(\s*silent:\s*true\s*\)')
              .hasMatch(body),
          isTrue,
          reason: 'the refresh must be conditional on the policy result');
      expect(RegExp(r'onFree:\s*\(\)\s*\{\s*\}').hasMatch(body), isTrue,
          reason: 'a free user must NOT silently spend the lifetime report');
      final init = between('void initState()', 'void _refreshOnOpen()');
      expect(init.contains('_refreshOnOpen()'), isTrue);
      expect(init.contains('_generateReport('), isFalse);
      expect(init.contains('ref.listen'), isFalse,
          reason: 'ref.listen is only legal inside build');
    });

    test('_generateReport: one call at a time, across screen re-opens', () {
      expect(screen.contains('static bool _inFlight = false;'), isTrue);
      final g = between('Future<void> _generateReport', 'void _retry()');
      final guard = g.indexOf('if (_inFlight) return;');
      final set = g.indexOf('_inFlight = true;');
      expect(guard, greaterThanOrEqualTo(0));
      expect(set, greaterThan(guard), reason: 'check BEFORE set');
      expect(RegExp(r'finally\s*\{\s*_inFlight = false;').hasMatch(g), isTrue,
          reason: 'cleared in finally, or one failure wedges refresh forever');
      expect(
          RegExp(r'onPressed:\s*\(_isGeneratingReport \|\| _inFlight\)')
              .hasMatch(screen),
          isTrue,
          reason: 'the Generate card is disabled while a silent call runs');
    });

    test('a spent-free-report 403 sets the flag and opens the paywall, '
        'after the silent early-return', () {
      final g = between('Future<void> _generateReport', 'void _retry()');
      final silent = g.indexOf('if (silent) {');
      final spent = g.indexOf('isLifetimeFreeReportSpent(');
      expect(silent, greaterThanOrEqualTo(0));
      expect(spent, greaterThan(silent),
          reason: 'else the paywall opens on every screen open');
      final branch = g.substring(spent);
      expect(branch.contains("put('first_report_generated', true)"), isTrue,
          reason: 'else the free-user line keeps promising a spent report');
      expect(branch.contains('showPaywallSheet('), isTrue);
    });

    test('a free -> PRO transition while open re-runs the refresh', () {
      final b = between('Widget build(BuildContext context)', 'return Scaffold(');
      expect(
          RegExp(r'ref\.listen\(\s*subscriptionInfoProvider')
              .hasMatch(b),
          isTrue);
      expect(b.contains('prev != null && !prev.isPro && next.isPro'), isTrue);
      expect(b.contains('_refreshOnOpen()'), isTrue);
    });

    test('the cache stamp uses the test-clock seam, same clock as the policy',
        () {
      final g = between('Future<void> _generateReport', 'void _retry()');
      expect(
          RegExp(r'_reportCacheDateKey,\s*nowWall\(\)\.toIso8601String\(\)')
              .hasMatch(g),
          isTrue);
      expect(g.contains('DateTime.now('), isFalse,
          reason: 'any wall-clock read here diverges from the policy under '
              'the dev-panel time seam');
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
