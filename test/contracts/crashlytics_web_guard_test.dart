// Regression contract for bug b2e9d3 (Obs#2, 2026-06-13 live web E2E): main()
// ran Firebase + Crashlytics init with NO kIsWeb guard → a null-check inside the
// (web-unsupported) Crashlytics plugin crashed boot on web. Pins the init behind
// `if (!kIsWeb)`. Source-grep, comment-stripped (per feedback_source_grep_strip_comments_first).

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
  test('b2e9d3 — Firebase/Crashlytics init is gated behind if (!kIsWeb)', () {
    final src = _strip(File('lib/main.dart').readAsStringSync());

    final initIdx = src.indexOf('Firebase.initializeApp(');
    expect(initIdx, isNot(-1), reason: 'main() must init Firebase');

    // A `!kIsWeb` guard must appear within the 300 chars preceding the init.
    final before = src.substring(initIdx < 300 ? 0 : initIdx - 300, initIdx);
    expect(before.contains('if (!kIsWeb)'), isTrue,
        reason:
            'Firebase.initializeApp + FirebaseCrashlytics init must be INSIDE an '
            'if (!kIsWeb) guard — Crashlytics has no web binding and null-check-'
            'crashes web boot otherwise (b2e9d3).');

    // And there must be no Crashlytics call before that guard (unguarded use).
    final guardIdx = src.indexOf('if (!kIsWeb)');
    final firstCrashlytics = src.indexOf('FirebaseCrashlytics.instance');
    expect(firstCrashlytics, isNot(-1));
    expect(guardIdx, lessThan(firstCrashlytics),
        reason: 'no FirebaseCrashlytics.instance use may precede the !kIsWeb guard');
  });
}
