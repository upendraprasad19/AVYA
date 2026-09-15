// Wiring contract — U5 (Ship 3): onboarding COLLECTS injuries and threads the
// selection into plan generation. Comment-stripped source-grep (the established
// pattern for onboarding-flow wiring, cf plan_screen_targets_match_*). Catches
// exactly the ×2-review P1-C regressions: a future RE-HARDCODE of
// plan_screen's injuries answer back to ['none'], a missing details→plan extras
// key, or a lost initState seed (the ADJUST-PLAN round-trip drop).
//
// The RUNTIME injury filter this feeds is behaviorally proven downstream
// (injury_filter_behavioral_test — generate(injuries) excludes contra-exercises)
// and the chip toggle by injury_chip_vocab_contract_test; completeOnboarding's
// full runtime (auth/sync/weight-seed) is an integration_test concern, not a
// contract unit test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strip block + line comments (never trust comment text — feedback_source_grep_
/// strip_comments_first).
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
  final planSrc = _strip(
      File('lib/features/onboarding/screens/plan_screen.dart').readAsStringSync());
  final detailsSrc = _strip(
      File('lib/features/onboarding/screens/details_screen.dart')
          .readAsStringSync());

  test('plan_screen READS injuries from the extras — no re-hardcode to [none]',
      () {
    // The old bug: setAnswer('injuries', ['none']) — a hardcoded literal that
    // ignored the chip. A re-hardcode is the P1-C regression.
    expect(
      RegExp(r"setAnswer\(\s*'injuries'\s*,\s*<String>\['none'\]\s*\)")
          .hasMatch(planSrc),
      isFalse,
      reason: 'plan_screen must NOT hardcode injuries to [none] — read the chip',
    );
    expect(planSrc.contains("widget.data['injuries']"), isTrue,
        reason: 'plan_screen must read the collected injuries from route extras');
    // The injuries answer is written from the extras value.
    expect(RegExp(r"setAnswer\(\s*'injuries'").hasMatch(planSrc), isTrue);

    // POSITIVE guard (B-pass P3-1): the injuries setAnswer must be FED from the
    // extras-derived variable, not any literal. This closes the gap where an
    // exotically-reformatted re-hardcode (e.g. a plain ['none'] without the
    // <String> prefix) leaves the widget.data read as dead code and slips past
    // the negative literal check above.
    expect(
      RegExp(r"selectedInjuries\s*=\s*widget\.data\['injuries'\]")
          .hasMatch(planSrc),
      isTrue,
      reason: 'the injuries answer must derive from widget.data[injuries]',
    );
    final injuriesSetAnswer =
        RegExp(r"setAnswer\(\s*'injuries'\s*,").firstMatch(planSrc);
    expect(injuriesSetAnswer, isNotNull);
    final window = planSrc.substring(
      injuriesSetAnswer!.end,
      (injuriesSetAnswer.end + 160).clamp(0, planSrc.length),
    );
    expect(window.contains('selectedInjuries'), isTrue,
        reason: 'setAnswer(injuries) must reference the extras-derived '
            'selectedInjuries, not a hard-coded list');
  });

  test('details_screen WRITES the selected injuries into the plan extras', () {
    expect(detailsSrc.contains("'injuries':"), isTrue,
        reason: 'details_screen must add injuries to the enriched route extras');
    expect(detailsSrc.contains('_injuries'), isTrue);
    // Passed onward to the plan screen.
    expect(detailsSrc.contains("context.go('/onboarding/plan'"), isTrue);
  });

  test('details_screen SEEDS _injuries from extras in initState (round-trip safe)',
      () {
    // Without seeding, the plan→details "ADJUST PLAN" round-trip resets a real
    // selection to ['none'] before generation (×2 review P1-A).
    expect(detailsSrc.contains("widget.data['injuries']"), isTrue,
        reason: 'initState must seed _injuries from the incoming extras so the '
            'ADJUST-PLAN round-trip preserves the selection');
  });

  test('the chip uses the SHARED InjuryVocab source (no duplicated vocab)', () {
    expect(detailsSrc.contains('InjuryVocab.chipTokens'), isTrue,
        reason: 'details chip must use the shared InjuryVocab.chipTokens');
    expect(detailsSrc.contains('InjuryVocab.toggleChip'), isTrue,
        reason: 'details chip must use the shared none-toggle');
  });
}
