// Regression contract for bug a7c3f8 (Obs#3, 2026-06-13; recurrence of §2.21 /
// dc52a4): the coach_memory backfill ran in main() BEFORE
// HiveUserSession.openForUser → "HiveUserSession not opened — cannot wrap
// user-scoped box coachBox" every boot (silent fail). Relocated to
// restoring_screen, after openForUser, in BOTH the foreground + background-restore
// paths. Source-grep, comment-stripped.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  test('a7c3f8 — main() no longer runs the coach_memory backfill (pre-openForUser)',
      () {
    final src = _strip(File('lib/main.dart').readAsStringSync());
    expect(src.contains('backfillCoachMemoryIfNeeded'), isFalse,
        reason:
            'main() runs BEFORE HiveUserSession.openForUser — a user-scoped-box '
            'backfill here throws "HiveUserSession not opened" every boot');
  });

  test('a7c3f8 — restoring_screen runs the backfill after openForUser (both paths)',
      () {
    final src = _strip(
        File('lib/features/auth/screens/restoring_screen.dart').readAsStringSync());
    expect(src.contains('openForUser'), isTrue,
        reason: 'restoring_screen opens the user session before the backfill');
    final count =
        'backfillCoachMemoryIfNeeded'.allMatches(src).length;
    expect(count, greaterThanOrEqualTo(2),
        reason:
            'both the foreground (_ensureOwnershipBeforeHome) and background '
            '(_healAfterRestoreInBackground) post-openForUser paths must run it');
  });
}
