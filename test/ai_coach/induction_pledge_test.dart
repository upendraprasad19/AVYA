import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// OBS-1 / diagnose f1a9d3 — the "I COMMIT" pledge must describe the ACTUAL
/// rank engine (time + consistency), never a false workout-count threshold.
///
/// PRE-FIX the pledge promised "Make Sub Lieutenant rank — 104 workouts" and
/// "104 workouts is roughly six months". The engine gates Sub Lieutenant on
/// 104 WEEKS (2 years) + 80% completion and ignores workout count entirely, so
/// the promise was a broken-promise churn landmine at ~month 6. The PRE-FIX
/// version of THIS test actively pinned the false copy in place (it asserted
/// "104 workouts" MUST be present) — a test enforcing the bug.
///
/// Founder picked framing B: anchor the commit on the nearer fast ranks with
/// Lieutenant named as the destination. Engine unchanged — copy only.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/screens/induction_screen.dart')
        .readAsStringSync();
  });

  test('pledge must NOT claim a false workout-count gate (OBS-1 regression)', () {
    expect(src.contains('104 workouts'), isFalse,
        reason: 'engine gates Sub Lieutenant on 104 WEEKS, not 104 workouts');
    expect(src.contains('200 workouts'), isFalse);
    expect(src.contains('Sub Lieutenant rank'), isFalse,
        reason: 'the pledge no longer promises Sub Lieutenant on a workout count');
  });

  test('pledge must NOT claim the false "six months" Sub Lieutenant timeline', () {
    expect(src.contains('six months'), isFalse,
        reason: 'the false "104 workouts ≈ six months" promise (real gate 2 yrs)');
  });

  // NOTE: these assert single-line-safe substrings — the copy is split across
  // concatenated Dart string literals (line-wrap), so a multi-word phrase like
  // 'Petty Officer' is NOT a contiguous substring of the SOURCE.
  test('pledge anchors on the nearer ranks + Lieutenant as the destination (B)', () {
    expect(src.contains('Petty'), isTrue,
        reason: 'framing B anchors the commit on the fast nearer ranks (Petty Officer)');
    expect(src.contains('month three'), isTrue,
        reason: 'the nearer-rank timeline (Petty Officer by month three)');
    expect(src.contains('Lieutenant'), isTrue,
        reason: 'Lieutenant is named as the destination (Become a Lt)');
  });

  test('pledge describes the real mechanism — consistency, not a count', () {
    expect(src.contains('Eighty percent'), isTrue,
        reason: 'officer ranks gate on 80% completion (the real engine)');
    expect(src.contains('contract'), isTrue,
        reason: 'Navy voice — the commitment is "the contract"');
  });
}
