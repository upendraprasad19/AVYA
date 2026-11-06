// Regression contract for bug f1b6d4 (Obs#6, 2026-06-13 live web E2E): the
// onboarding plan PREVIEW showed 2867 kcal but the SAVED daily_calories was 3200
// — the preview (plan_screen._computeTargets) and the commit
// (OnboardingNotifier.completeOnboarding) passed DIFFERENT inputs to
// BmrCalculator.calculateTargets:
//   - activity: preview read widget.data['activity_level'] directly; commit
//     DERIVED it via resolveActivityLevel(lifestyle_activity, days).
//   - body fat: preview passed bodyFatPercent (Katch-McArdle); commit omitted it.
// onboarding/CLAUDE.md claimed THIS test pinned the parity, but the file never
// existed — so the drift shipped. This is that test (now real): the two
// calculateTargets calls must pass the IDENTICAL named-arg set, and both must
// derive activity via the lifestyle-activity system. Source-grep, comment-stripped.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';

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

/// Named-argument labels passed to the first `calculateTargets(...)` call.
Set<String> _argNames(String src) {
  final m = RegExp(r'calculateTargets\(([\s\S]*?)\);').firstMatch(src);
  if (m == null) return <String>{};
  return RegExp(r'(\w+):')
      .allMatches(m.group(1)!)
      .map((x) => x.group(1)!)
      .toSet();
}

void main() {
  final planSrc = _strip(
      File('lib/features/onboarding/screens/plan_screen.dart').readAsStringSync());
  final commitSrc = _strip(
      File('lib/features/onboarding/providers/onboarding_provider.dart')
          .readAsStringSync());

  test('f1b6d4 — preview + completeOnboarding pass the IDENTICAL args to calculateTargets',
      () {
    final planArgs = _argNames(planSrc);
    final commitArgs = _argNames(commitSrc);
    expect(planArgs, isNotEmpty, reason: 'plan_screen must call calculateTargets');
    expect(commitArgs, isNotEmpty,
        reason: 'completeOnboarding must call calculateTargets');
    expect(planArgs, equals(commitArgs),
        reason:
            'the preview must pass the SAME named-arg set to '
            'BmrCalculator.calculateTargets as completeOnboarding, or the preview '
            'calories drift from the saved daily_calories (was 2867 vs 3200). '
            'plan=$planArgs commit=$commitArgs');
  });

  test('f1b6d4 — preview derives activityLevel via the lifestyle-activity system (like the commit)',
      () {
    expect(planSrc.contains('resolveActivityLevel'), isTrue,
        reason:
            'preview must derive activityLevel the same way the commit does '
            '(resolveActivityLevel), not read activity_level directly');
    expect(commitSrc.contains('resolveActivityLevel'), isTrue,
        reason: 'commit derives activityLevel via resolveActivityLevel');
  });

  test('f1b6d4 — preview DERIVES lifestyle_activity (does not read the never-written key)',
      () {
    // The Hermes E-pass caught the residual drift: the preview read
    // widget.data['lifestyle_activity'] (which NO stepped screen writes → always
    // 'desk_job') while the commit DERIVES it from activity_level. Both must
    // derive via the shared BmrCalculator.lifestyleFromActivityLevel.
    // Both _computeTargets (preview) and _onReportForDuty (commit-prep, which
    // sets the answer completeOnboarding reads) live in plan_screen and must
    // derive via the shared mapping → helper appears >=2x.
    expect('lifestyleFromActivityLevel'.allMatches(planSrc).length,
        greaterThanOrEqualTo(2),
        reason:
            'preview + commit-prep must both derive lifestyle_activity via the '
            'shared BmrCalculator.lifestyleFromActivityLevel');
    expect(commitSrc.contains("a['lifestyle_activity']"), isTrue,
        reason:
            'completeOnboarding reads the lifestyle_activity that _onReportForDuty derived');
    expect(planSrc.contains("widget.data['lifestyle_activity']"), isFalse,
        reason:
            'the preview must NOT read a lifestyle_activity key — no stepped '
            'screen writes it, so it always fell back to desk_job and drifted');
  });

  test('f1b6d4 — shared activity mapping + chain produce the COMMIT value (behavioral)',
      () {
    // Value-level (not arg-name): the chain both paths now use —
    // resolveActivityLevel(lifestyleFromActivityLevel(activity_level), days) —
    // produces the SAVED activity bucket. A 'moderate', 4-day user (the Hermes
    // worked example) must resolve to 'active' (x1.725), NOT the pre-fix
    // preview's 'moderate' (x1.55) — this is what closes the 2867-vs-3200 drift.
    expect(BmrCalculator.lifestyleFromActivityLevel('sedentary'), 'desk_job');
    expect(BmrCalculator.lifestyleFromActivityLevel('light'), 'desk_job');
    expect(
        BmrCalculator.lifestyleFromActivityLevel('moderate'), 'lightly_active');
    expect(
        BmrCalculator.lifestyleFromActivityLevel('heavy'), 'very_active_job');
    expect(
        BmrCalculator.resolveActivityLevel(
            BmrCalculator.lifestyleFromActivityLevel('moderate'), 4),
        'active',
        reason:
            'a moderate/4-day user resolves to the active bucket (the saved value)');
  });
}
