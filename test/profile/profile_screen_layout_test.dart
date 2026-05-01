// test/profile/profile_screen_layout_test.dart
//
// Layout invariants for ProfileScreen after Plan D restructure
// (Test #6 D-11).
//
// Pumping the full ProfileScreen requires deep Hive bootstrap +
// many provider overrides; following the convention in
// `test/safety/null_guard_test.dart` we instead assert source
// structure: order of section headers + presence/absence rules.
//
// Invariants:
//   C13a — WardRankPill renders near top of Profile.
//   C13b — No StreakBadge / FreezeBadge / WardStatusStrip on Profile.
//   C14  — Edit Profile row appears INSIDE the SETTINGS card and
//          does NOT appear above the SETTINGS section header.
//   C15a — Predictions row appears under REPORTS.
//   C15b — No standalone YOUR PREDICTION section header anywhere.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _profilePath = 'lib/features/profile/screens/profile_screen.dart';
const _profileIdentityPath = 'lib/features/profile/widgets/profile_identity.dart';

String _src(String relative) => File(relative).readAsStringSync();

void main() {
  group('Profile layout — Plan D Test #6 D-11 invariants', () {
    final src = _src(_profilePath);

    test('C13a — WardRankPill renders inside ProfileScreen', () {
      expect(src, contains('WardRankPill('),
          reason: 'WardRankPill should be invoked inside the Profile body');
    });

    test('C13b — No StreakBadge / FreezeBadge / WardStatusStrip on Profile',
        () {
      // None of the Plan D-removed primitives should be invoked anywhere
      // inside profile_screen.dart or profile_identity.dart.
      final identitySrc = _src(_profileIdentityPath);
      for (final forbidden in ['StreakBadge(', 'FreezeBadge(', 'WardStatusStrip(']) {
        expect(src, isNot(contains(forbidden)),
            reason:
                '$forbidden must not appear in profile_screen.dart (Plan D D-8 removed it)');
        expect(identitySrc, isNot(contains(forbidden)),
            reason:
                '$forbidden must not appear in profile_identity.dart');
      }
    });

    test('C14 — Edit Profile lives in SETTINGS card, NOT above SETTINGS header',
        () {
      // The SETTINGS section header anchor and the Edit Profile row
      // must both exist.
      final settingsHeaderIndex = src.indexOf("SectionHeader('SETTINGS')");
      expect(settingsHeaderIndex, greaterThan(-1),
          reason: 'SETTINGS section header must exist');

      final editProfileIndex = src.indexOf("title: 'Edit Profile'");
      expect(editProfileIndex, greaterThan(-1),
          reason: 'Edit Profile ProfileRow must exist somewhere');

      expect(editProfileIndex, greaterThan(settingsHeaderIndex),
          reason:
              'Edit Profile row must appear AFTER the SETTINGS header — '
              'it is no longer at the top of Profile (Plan D D-7 + D-9)');
    });

    test('C14b — ProfileIdentity is invoked with onTapEdit: null', () {
      // Plan D D-7 hides the top EDIT PROFILE button by passing
      // onTapEdit: null to ProfileIdentity.
      expect(src, contains('onTapEdit: null'),
          reason:
              'ProfileIdentity must be invoked with onTapEdit: null so the '
              'top EDIT PROFILE button hides (Plan D D-7).');
    });

    test('C15a — Predictions row appears AFTER REPORTS section header', () {
      final reportsHeaderIndex = src.indexOf("SectionHeader('REPORTS')");
      expect(reportsHeaderIndex, greaterThan(-1),
          reason: 'REPORTS section header must exist');

      final predictionsRowIndex = src.indexOf("title: 'Predictions'");
      expect(predictionsRowIndex, greaterThan(-1),
          reason: 'Predictions ProfileRow must exist (Plan D D-10)');

      expect(predictionsRowIndex, greaterThan(reportsHeaderIndex),
          reason:
              'Predictions row must appear AFTER the REPORTS header (D-10)');
    });

    test('C15b — Standalone YOUR PREDICTION section header is gone', () {
      expect(src, isNot(contains("SectionHeader('YOUR PREDICTION')")),
          reason:
              'YOUR PREDICTION section header was removed in Plan D D-10');
      expect(src, isNot(contains("'YOUR PREDICTION'")),
          reason: 'YOUR PREDICTION literal should not exist anywhere');
    });

    test('Service Record section is no longer rendered as a top-level widget',
        () {
      expect(src, isNot(contains('ServiceRecordSection()')),
          reason:
              'ServiceRecordSection was removed from the Profile body in '
              'Plan D D-7; its content lives inside WardRankPill expansion');
      expect(src, isNot(contains("../widgets/service_record_section.dart")),
          reason: 'service_record_section.dart import should be removed');
    });

    test('WeeklyReportCard precedes Predictions row (REPORTS ordering)', () {
      final weeklyReportIndex = src.indexOf('WeeklyReportCard(');
      final predictionsRowIndex = src.indexOf("title: 'Predictions'");
      expect(weeklyReportIndex, greaterThan(-1));
      expect(predictionsRowIndex, greaterThan(-1));
      expect(weeklyReportIndex, lessThan(predictionsRowIndex),
          reason:
              'WeeklyReportCard must appear BEFORE Predictions row inside REPORTS '
              '(APK Test #7 ordering: Weekly Report card → 3-row card [Predictions / '
              'Progress Comparison / Progress Photos])');
    });
  });
}
