import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';

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
///
/// onboarding-fuse-commit (2026-11-14): the pledge moved from the retired
/// Induction screen to the Plan screen's pledge card (`WardroomCopy
/// .onboardingPledge*`), cut to one card by the founder. These checks now
/// read the copy constants themselves, so whole phrases are matched. The
/// "Eighty percent" sentence was cut with the rest of the long speech; the
/// consistency mechanism is now carried by "if you stay on it".
void main() {
  const src = '${WardroomCopy.onboardingPledgeGreetingTemplate} '
      '${WardroomCopy.onboardingPledgeBody} '
      '${WardroomCopy.onboardingPledgeContract} '
      '${WardroomCopy.onboardingPledgeSeal}';

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

  test('pledge anchors on the nearer ranks + Lieutenant as the destination (B)', () {
    expect(src.contains('Petty Officer by month three'), isTrue,
        reason: 'framing B anchors the commit on the fast nearer ranks');
    expect(src.contains('Lieutenant if you stay on it'), isTrue,
        reason: 'Lieutenant is the destination, earned by consistency');
  });

  test('pledge keeps the Navy contract voice', () {
    expect(src.contains("That's the contract."), isTrue);
    expect(src.contains('Tap below to seal it.'), isTrue);
  });
}
