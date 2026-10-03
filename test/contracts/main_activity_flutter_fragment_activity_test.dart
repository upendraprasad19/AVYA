// test/contracts/main_activity_flutter_fragment_activity_test.dart
//
// Pins MainActivity's SUPERCLASS, because the health plugin's Android side
// casts the host Activity to a FragmentActivity and a plain FlutterActivity is
// not one.
//
// This is a REAL regression that already shipped once. QA on 2026-03-30 caught
// it on a device, logged at 13:55:10:
//
//   java.lang.ClassCastException:
//     com.icanbefitter.icanbefitter.MainActivity cannot be cast to b.l
//
// (`b.l` is the R8-minified name of androidx.fragment.app.FragmentActivity in a
// release build — which is why the message names no recognisable type and why
// this is easy to misread as unrelated.) Stated impact at the time: "Google Fit
// / Health Connect integration will NOT work" — step counter, sleep, heart
// rate, and device weight all fail. Commit 6421178e (2026-03-23) had
// FlutterActivity; 8a5df734 (2026-03-30) changed it to FlutterFragmentActivity
// and fixed it.
//
// WHY A TEST AND NOT A COMMENT: nothing detected this the first time and
// nothing would detect it again. The failure mode is uniquely bad —
//
//   * it CANNOT be caught by `flutter analyze`, `flutter test`, or any Dart
//     test: MainActivity.kt is Kotlin, and the cast happens inside the plugin's
//     Android code at runtime;
//   * it needs a REAL DEVICE plus a granted Health permission to reproduce, so
//     no emulator smoke test on CI reaches it;
//   * it is SILENT to the user — health sync fails and the step counter simply
//     reads 0, which looks like "no data today", not like a crash.
//
// So a one-line edit reverting the superclass could ship to production and be
// invisible until a user reported flat step counts. Reading the file is the
// only check available that runs anywhere, and it costs microseconds.
//
// This asserts SOURCE TEXT, which per CLAUDE.md rule 21 is presence-only and
// weaker than a behavioral test. That limit is accepted here rather than papered
// over: the behavioral counterpart is a device test (Health permission granted,
// read steps, assert no ClassCastException) and belongs with the Patrol flows in
// docs/operations/DEVICE_TESTING.md. What this file DOES buy is that the exact
// edit which caused the 2026-03-30 incident cannot land again unnoticed.
//
// Ref: OI-129 (where the QA report was re-read and this gap was found).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Repo root, resolved from the test's own location so this works from the
/// primary worktree and from any linked worktree under .claude/worktrees/.
String _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/android').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}

void main() {
  group('MainActivity must extend FlutterFragmentActivity', () {
    final file = File(
      '${_repoRoot()}/android/app/src/main/kotlin/com/icanbefitter/'
      'icanbefitter/MainActivity.kt',
    );

    test('the source file exists where the health plugin contract needs it',
        () {
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'MainActivity.kt not found at ${file.path}. If the Android package '
            'was renamed, update this test WITH the rename — do not delete it; '
            'the ClassCastException it guards is silent at runtime.',
      );
    });

    test('declares FlutterFragmentActivity as its superclass', () {
      final src = file.readAsStringSync();

      // Match by REGEX, not a literal line: whitespace, a body block, or an
      // added interface must not make the guard silently stop matching. A
      // literal-string check is the failure mode feedback_mistake_guard_without
      // _its_mirror names — it passes for the wrong reason after any reformat.
      final declaration = RegExp(
        r'class\s+MainActivity\s*:\s*FlutterFragmentActivity\s*\(',
      );

      expect(
        declaration.hasMatch(src),
        isTrue,
        reason:
            'MainActivity must extend FlutterFragmentActivity. The health '
            'plugin casts the host Activity to androidx FragmentActivity; a '
            'plain FlutterActivity throws ClassCastException at runtime and '
            'Google Fit / Health Connect sync fails SILENTLY (steps read 0). '
            'This shipped once already — QA 2026-03-30, fixed in 8a5df734. '
            'Found:\n$src',
      );
    });

    test('does not extend a bare FlutterActivity', () {
      final src = file.readAsStringSync();

      // The mirror of the assertion above. Kept separate and phrased in the
      // negative on purpose: `FlutterFragmentActivity` CONTAINS the substring
      // `FlutterActivity`, so a naive `contains('FlutterActivity')` check reads
      // TRUE on the correct file. The word boundary is what makes this test
      // able to fail for the right reason.
      final bareActivity = RegExp(
        r'class\s+MainActivity\s*:\s*FlutterActivity\b',
      );

      expect(
        bareActivity.hasMatch(src),
        isFalse,
        reason:
            'MainActivity extends a bare FlutterActivity — this is the exact '
            '2026-03-30 regression (ClassCastException, health sync dead). '
            'Change it to FlutterFragmentActivity.',
      );
    });

    test('imports the FlutterFragmentActivity it extends', () {
      final src = file.readAsStringSync();

      expect(
        src.contains(
          'import io.flutter.embedding.android.FlutterFragmentActivity',
        ),
        isTrue,
        reason:
            'MainActivity.kt must import '
            'io.flutter.embedding.android.FlutterFragmentActivity. Without it '
            'the file does not compile, but a stale import of FlutterActivity '
            'alongside a correct declaration is the confusing half-state this '
            'catches.',
      );
    });
  });
}
