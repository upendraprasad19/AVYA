// Train screen compaction (founder call 2026-11-01): the top of the screen is the
// week's schedule. Removed: the "TODAY'S WORKOUT" eyebrow, the "DEPLOYMENT NN ..."
// eyebrow, the "THIS WEEK" label. The roadmap pill (and the hold-week strip that
// travels with it) now sits right AFTER the PRs block (`StatsGrid`).
//
// Source-grep pins (presence/order only — the screen is a 600-line private-state
// extension tree that needs the full provider graph to pump). Each pin is
// mutation-checked in the batch's diagnose notes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock.split('\n').map((l) {
    final at = l.indexOf('//');
    return at < 0 ? l : l.substring(0, at);
  }).join('\n');
}

void main() {
  final screen = _stripComments(
      File('lib/features/train/screens/train/screen.dart').readAsStringSync());
  final hero = _stripComments(
      File('lib/features/train/screens/train/hero_cards.dart')
          .readAsStringSync());

  group('removed labels', () {
    test("no TODAY'S WORKOUT / TODAY · HOLD WEEK eyebrow in the hero card", () {
      expect(hero.contains("TODAY'S WORKOUT"), isFalse);
      expect(hero.contains('TODAY · HOLD WEEK'), isFalse);
    });
    test('no THIS WEEK section label and no DEPLOYMENT eyebrow on the screen', () {
      expect(screen.contains("'THIS WEEK'"), isFalse);
      expect(screen.contains('DEPLOYMENT'), isFalse);
      expect(screen.contains('deploymentEyebrowLabel'), isFalse);
    });
  });

  group('roadmap pill placement', () {
    int at(String needle) => screen.indexOf(needle);

    test('pill comes AFTER the PRs block (StatsGrid) and is not above the week rows',
        () {
      final stats = at('const StatsGrid()');
      final pill = at('VIEW THE 12-WEEK ROADMAP');
      final weeks = at('WeekSelector(');
      expect(stats, greaterThan(-1));
      expect(pill, greaterThan(-1));
      expect(weeks, greaterThan(-1));
      expect(pill, greaterThan(stats),
          reason: 'the roadmap pill must sit after the PRs block');
      expect(weeks, lessThan(stats),
          reason: 'the week schedule stays above the PRs block');
      // Exactly one pill (a move, not a copy).
      expect('VIEW THE 12-WEEK ROADMAP'.allMatches(screen).length, 1);
    });

    test('the hold-week roadmap strip travels with the pill', () {
      final pill = at('VIEW THE 12-WEEK ROADMAP');
      final strip = at('HoldRoadmapStrip(');
      expect(strip, greaterThan(pill),
          reason: 'HoldRoadmapStrip belongs directly under the pill');
      expect(strip - pill, lessThan(1500),
          reason: 'and must not drift away from it');
    });

    test('the hold state reaches the hero card call', () {
      expect(
        RegExp(r'_buildTodayHeroCard\([^;]*?isHolding:\s*holdStatus\.isHolding',
                dotAll: true)
            .hasMatch(screen),
        isTrue,
      );
    });
  });

  group('compact hero (all four states)', () {
    test('every state takes isHolding and renders the HOLD WEEK lead-in', () {
      for (final b in const [
        '_buildWorkoutHeroCard(BuildContext context, WorkoutDayData workout,\n      {bool isHolding = false})',
        '_buildRestHeroCard({bool isHolding = false})',
        '_buildEmptyWorkoutHeroCard({bool isHolding = false})',
        '_buildDoneHeroCard(WorkoutDayData workout, {bool isHolding = false})',
      ]) {
        expect(hero.contains(b), isTrue, reason: 'missing signature: $b');
      }
      expect('_holdLead(isHolding)'.allMatches(hero).length, greaterThanOrEqualTo(8),
          reason: 'each of the four states checks + uses the HOLD WEEK lead');
      expect(hero.contains('HOLD WEEK'), isTrue);
      // The lead-in itself must be driven by isHolding (a `=> false` stub would
      // satisfy every call-site pin above while never showing the tag).
      expect(
        RegExp(r"_holdLead\(bool isHolding\)\s*=>\s*isHolding\s*\?\s*TextSpan\(\s*text:\s*'HOLD WEEK")
            .hasMatch(hero),
        isTrue,
        reason: '_holdLead must return the accent HOLD WEEK span when isHolding',
      );
    });

    test('START is still gated on a non-empty plan; the rest day is one tappable row',
        () {
      expect(hero.contains('todayWorkout.exercises.isNotEmpty'), isTrue);
      expect(hero.contains('_buildEmptyWorkoutHeroCard('), isTrue);
      expect(hero.contains("'START'"), isTrue);
      expect(hero.contains("'RESUME'"), isTrue);
      expect(hero.contains('_showRestDaySheet(context)'), isTrue);
      // One line: the rest card no longer carries the old two-row copy.
      expect(hero.contains('tap for recovery tips'), isFalse);
    });

    test('the full-width START WORKOUT button is gone from the hero', () {
      expect(hero.contains('START WORKOUT'), isFalse);
      expect(hero.contains('fullWidth: false'), isTrue);
    });
  });
}
