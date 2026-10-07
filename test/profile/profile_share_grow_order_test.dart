// Profile tab layout, as the founder asked for it (2026-10-03):
//   * "move share and grow block to below avya block"
//   * one "Photos" row instead of "Progress Photos" + "Saved Photos"
//
// Source pins over the concatenated, COMMENT-STRIPPED Profile screen source
// (`readScreenSourceStripped('profile')`): presence / order / count only. A plain
// read cannot tell a row that is live from one that was commented out instead of
// deleted. The Photos hub's own behavior is in `user_photos_hub_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';

/// Every spelling under which Profile code could route to either photo
/// destination (path, route name, class). Only the hub may.
final _destination = RegExp(
  r'''profile/progress-photos|profile/saved-coach-photos|['"]progressPhotos['"]|['"]savedCoachPhotos['"]|ProgressPhotosScreen|SavedCoachPhotosScreen''',
);

void main() {
  late String src;

  setUpAll(() {
    src = readScreenSourceStripped('profile');
  });

  int at(String needle) {
    final i = src.indexOf(needle);
    expect(i, greaterThan(-1), reason: 'missing from the Profile source: $needle');
    return i;
  }

  test('section order: REPORTS, SETTINGS, AVYA, SHARE & GROW, SUBSCRIPTION, '
      'each header exactly once', () {
    // First-occurrence indexes cannot see a SECOND block (what a bad merge of
    // two branches that each moved SHARE & GROW would leave), so count too.
    for (final h in [
      'REPORTS',
      'SETTINGS',
      'AVYA',
      'SHARE & GROW',
      'SUBSCRIPTION',
    ]) {
      expect("SectionHeader('$h')".allMatches(src).length, 1,
          reason: "the '$h' section must render exactly once");
    }
    final reports = at("SectionHeader('REPORTS')");
    final settings = at("SectionHeader('SETTINGS')");
    final avya = at("SectionHeader('AVYA')");
    final shareGrow = at("SectionHeader('SHARE & GROW')");
    final subscription = at("SectionHeader('SUBSCRIPTION')");
    expect(reports, lessThan(settings));
    expect(settings, lessThan(avya));
    expect(avya, lessThan(shareGrow),
        reason: 'SHARE & GROW goes BELOW the AVYA block');
    expect(shareGrow, lessThan(subscription),
        reason: 'and above the closing SUBSCRIPTION pitch');
  });

  test('SHARE & GROW kept every row through the move', () {
    final start = at("SectionHeader('SHARE & GROW')");
    final end = at("SectionHeader('SUBSCRIPTION')");
    final block = src.substring(start, end);
    for (final row in [
      "title: 'Apply Referral Code'",
      "title: 'Invite Friends'",
      "title: 'Submissions'",
      "title: 'Rate App'",
    ]) {
      expect(block.contains(row), isTrue,
          reason: '$row must still be inside the SHARE & GROW block');
    }
    expect(block.contains('ApplyReferralSheet.show'), isTrue);
    expect(block.contains('InviteFriendsSheet.show'), isTrue);
    expect(block.contains("context.go('/profile/submissions')"), isTrue);
    // The block was moved verbatim; this is its one guard that matters: the
    // "7 days of PRO unlocked!" snackbar and the eligibility refresh happen only
    // after a SUCCESSFUL redeem (`ok == true`) on a live context. `||` would show
    // them when the sheet is merely dismissed.
    expect(block.contains('if (ok == true && context.mounted) {'), isTrue,
        reason: 'the Apply Referral success branch must still be '
            '`ok == true && context.mounted`');
  });

  test('the Profile tab has ONE Photos row, to the hub; nothing else routes to '
      'a destination', () {
    expect(RegExp("title: 'Photos'").allMatches(src).length, 1,
        reason: 'exactly one Photos row');
    expect(src.contains("context.go('/profile/photos')"), isTrue,
        reason: 'the Photos row opens the hub');
    expect(src.contains("title: 'Progress Photos'"), isFalse);
    expect(src.contains("title: 'Saved Photos'"), isFalse);
    // Not one literal but every spelling: a `goNamed('progressPhotos')` row
    // would hand a FREE user the Progress screen's locked card instead of the
    // hub's paywall (the screen gates itself since 2026-10-05, but the hub is
    // where the paywall belongs).
    expect(_destination.hasMatch(src), isFalse,
        reason: 'only the hub routes to the destinations now');
  });
}
