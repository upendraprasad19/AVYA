// test/contracts/phase_unlock_card_thursday_gate_test.dart
//
// Contract — Theme E (closes-diagnose 0e7714).
//
// Pre-fix gate at lib/features/train/screens/train/phase_unlock_card.dart:9
//   if (plan.currentWeek < 4) return const SizedBox.shrink();
//
// Surfaces from MONDAY of Week 4. Founder's stated expectation 2026-
// 05-21: "should open up on thursday of the last week". Post-fix gate
// is Week 4 AND local weekday >= Thursday — 4-day runway (Thu-Sun).
// LOCAL weekday on purpose (not IST) — UI presence is perceptual.
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  late String src;

  setUpAll(() {
    src = _stripComments(
        File('lib/features/train/screens/train/phase_unlock_card.dart')
            .readAsStringSync());
  });

  test('gate uses DateTime.thursday (or weekday >= 4)', () {
    final hasThursdayConst = RegExp(
            r'DateTime\.now\(\)\.weekday\s*<\s*DateTime\.thursday')
        .hasMatch(src);
    final hasWeekdayLiteral = RegExp(
            r'DateTime\.now\(\)\.weekday\s*<\s*4\b')
        .hasMatch(src);
    expect(
      hasThursdayConst || hasWeekdayLiteral,
      isTrue,
      reason: 'phase_unlock_card must gate on weekday >= Thursday. Use '
          'either DateTime.thursday constant (preferred) or weekday < 4. '
          'Pre-fix surfaced from Monday of Week 4 — founder explicitly '
          'asked for Thursday surface.',
    );
  });

  test('bare currentWeek < 4 gate is GONE (replaced by combined condition)',
      () {
    // The pre-fix predicate. Must be gone — leaving it would make the
    // card surface for every week < 4 (i.e. never on weeks 5+ which is
    // fine but also would never gate by weekday).
    expect(
      RegExp(r'plan\.currentWeek\s*<\s*4\s*\)\s*return').hasMatch(src),
      isFalse,
      reason: 'pre-fix `if (plan.currentWeek < 4) return …` is replaced '
          'by the combined Week-4-AND-weekday-Thursday condition.',
    );
  });

  test('gate scopes to currentWeek == 4 (not >= 4)', () {
    // Subtle but important — the card MUST disappear when the user
    // transitions to Week 5+ (post-unlock). The pre-fix `< 4` would
    // continue showing it for weeks 5-12 because those are NOT less
    // than 4. Post-fix uses `!= 4` so weeks 1-3 + weeks 5+ all hide
    // the card. Only the 4-day window Thu-Sun of Week 4 surfaces it.
    expect(
      RegExp(r'plan\.currentWeek\s*!=\s*4').hasMatch(src),
      isTrue,
      reason: 'gate must be `plan.currentWeek != 4` so the card is '
          'hidden during weeks 1-3 (too early) AND weeks 5+ (already '
          'past the unlock window).',
    );
  });

  test('uses LOCAL weekday, NOT istNow().weekday', () {
    // UI presence is perceptual ("Thursday begins at local midnight").
    // istDateStr / istNow are for date-key math per CLAUDE.md §4.5
    // (Hive keys + cloud date columns + counter resets). UI surface
    // timing is local.
    expect(
      src.contains('istNow().weekday') ||
          src.contains('istDateStr(DateTime.now()).weekday'),
      isFalse,
      reason: 'phase unlock card must use LOCAL DateTime.now().weekday, '
          'NOT istNow().weekday. UI presence is a perceptual concern; '
          'IST shift would surface the card at 05:30 local for Indian '
          'users (the canonical date-key rule from CLAUDE.md §4.5 '
          'does not apply to UI presence gates).',
    );
  });
}
