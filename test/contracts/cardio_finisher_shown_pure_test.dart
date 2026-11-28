// Unit 3C (OI-396, docs/plans/2026-11-16-generator-step3c-cardio-finisher.md): the pure pieces of the shown, injury-safe
// and timed cardio finisher. No Hive: the plan is built through the public `CardioFinisher.plan`.
//
// - `FinisherSafety.isInjured` is the engine's own `normalizedInjuries` test over the PROFILE only (d78).
// - `FinisherSafety.shownFinisherMaps` is the reader rule every screen and `shortenDay` use (§2.3).
// - The reservation and the display price a finisher with the same rule (round 2 B-F4 parity).
// - `CardioFinisher.plan` shapes (OI-396, d74, d76) and `FinisherPlan.secondsByDay`.
// - The coach mapping (d77 / d78) and the confirm card's executed lines (d77, d79).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/swap_service.dart' show ShortenDayResult;
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/coach_injury_profile.dart';
import 'package:icanbefitter/features/ai_coach/widgets/tool_confirm_card.dart' show executedMessageFor;
import 'package:icanbefitter/shared/repositories/plan_engine/cardio_finisher.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/finisher_safety.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';

FinisherPlan _plan({
  String goal = 'lose_fat',
  String? pref,
  bool gym = true,
  List<String> injuries = const [],
  int? minutes,
  int days = 4,
}) =>
    CardioFinisher.plan(
      goal: goal,
      cardioPreference: pref,
      equipmentList: const [],
      hasGymEquipmentOverride: gym,
      capability: null,
      injuries: injuries,
      dayCount: days,
      minutes: minutes,
    );

List<String> _names(List<PlannedExercise> items) => [for (final e in items) e.exerciseName];

ToolIntent _intent(String type) => ToolIntent(
      id: 'x',
      type: type,
      payload: const {},
      confirmationClass: ConfirmationClass.reviewable,
      previewSummary: 'x',
      createdAt: DateTime(2026, 11, 16),
    );

void main() {
  group('isInjured: the profile only, the engine normalisation (d78, round 3 A-F1)', () {
    for (final (value, expected) in <(Object?, bool)>[
      (null, false),
      (<String>[], false),
      (['none'], false),
      ('none', false),
      (['xyz free text'], false),
      (['knee'], true),
      (['back'], true), // legacy alias -> lower_back
      ('shoulder', true), // a legacy bare String
      (['none', 'wrist'], true),
    ]) {
      test('$value -> $expected', () => expect(FinisherSafety.isInjured(value), expected));
    }
  });

  group('shownFinisherMaps: the reader rule (§2.3)', () {
    final hiit = [
      {'exercise_name': 'Burpees', 'sets': 3, 'reps': '10', 'duration_seconds': 120, 'rest_seconds': 0},
      {'exercise_name': 'Jump Squats', 'sets': 3, 'reps': '10', 'duration_seconds': 120, 'rest_seconds': 60},
    ];
    final bike = [
      {'exercise_name': 'Stationary Bike Sprints', 'sets': 8, 'reps': '30s fast / 30s slow', 'duration_seconds': 480},
    ];
    test('uninjured: every map entry, a non-map entry dropped', () {
      expect(FinisherSafety.shownFinisherMaps(hiit, injured: false), hiit);
      expect(FinisherSafety.shownFinisherMaps([...hiit, 'junk'], injured: false), hiit);
    });
    test('injured: a jumping finisher is hidden, the bike is shown', () {
      expect(FinisherSafety.shownFinisherMaps(hiit, injured: true), isEmpty);
      expect(FinisherSafety.shownFinisherMaps(bike, injured: true), bike);
    });
    test('injured: the bike matched by `name` too, case and spaces ignored', () {
      final odd = [
        {'name': '  stationary BIKE sprints '},
      ];
      expect(FinisherSafety.shownFinisherMaps(odd, injured: true), hasLength(1));
    });
    test('injured: a bike mixed with anything else, a nameless item, a non-map entry, or empty -> hidden', () {
      expect(FinisherSafety.shownFinisherMaps([...bike, ...hiit], injured: true), isEmpty);
      expect(
          FinisherSafety.shownFinisherMaps([
            ...bike,
            {'sets': 1},
          ], injured: true),
          isEmpty);
      expect(FinisherSafety.shownFinisherMaps([...bike, 'junk'], injured: true), isEmpty);
      expect(FinisherSafety.shownFinisherMaps(const [], injured: true), isEmpty);
    });
    test('a non-list stored value is nothing', () {
      expect(FinisherSafety.shownFinisherMaps('burpees', injured: false), isEmpty);
      expect(FinisherSafety.shownFinisherMaps(null, injured: false), isEmpty);
    });
  });

  group('row text and label (round 2 B-F1, round 5 B-F5)', () {
    test('detail: rounds and the reps text, never the digits of the reps', () {
      expect(FinisherSafety.detail(8, '30s fast / 30s slow'), '8 rounds · 30s fast / 30s slow');
      expect(FinisherSafety.detail(3, '10'), '3 rounds · 10');
      expect(FinisherSafety.detail(2, '30s'), '2 rounds · 30s');
      expect(FinisherSafety.detail(1, '60s'), '1 round · 60s');
      expect(FinisherSafety.detail('5', '60s on / 30s rest'), '5 rounds · 60s on / 30s rest');
      expect(FinisherSafety.detail(null, '10'), '10');
    });
    test('minutes label rounds like budgetMinutes', () {
      expect(FinisherSafety.minutesLabel(240), '4 MIN');
      expect(FinisherSafety.minutesLabel(450), '8 MIN');
      expect(FinisherSafety.minutesLabel(480), '8 MIN');
      expect(FinisherSafety.minutesLabel(540), '9 MIN');
    });
  });

  group('the plan (OI-396, d74, d76)', () {
    test('uninjured Cut at 60+: the HIIT circuit with its 60 s round rest stored (540 s)', () {
      final p = _plan(minutes: 60);
      expect(_names(p.exercises), ['Burpees', 'Mountain Climbers', 'Jump Squats']);
      expect(p.exercises.last.restSeconds, 60);
      expect(p.seconds, 540);
      expect(p.reserved, isTrue);
      expect(p.days, {0, 2});
      expect(p.secondsByDay, {0: 540, 2: 540});
    });
    test('under 60 minutes (d76): the mini HIIT, 240 s', () {
      for (final m in [30, 45, 59]) {
        final p = _plan(minutes: m);
        expect(_names(p.exercises), ['High Knees', 'Burpees', 'Mountain Climbers'], reason: '$m');
        expect(p.seconds, CardioFinisher.shortFinisherSeconds, reason: '$m');
      }
    });
    test('any injury (d74): the bike in a gym (8 rounds; 4 under 60), nothing at home', () {
      for (final token in InjuryVocab.canonicalTokens) {
        final gym = _plan(injuries: [token], minutes: 60);
        expect(_names(gym.exercises), [CardioFinisher.injuredGymFinisherName], reason: token);
        expect(gym.seconds, 480, reason: token);
        expect(_plan(injuries: [token], minutes: 45).seconds, 240, reason: token);
        expect(_plan(injuries: [token], gym: false, minutes: 60), same(FinisherPlan.none), reason: token);
      }
    });
    test('the finisher days per day count (B-pass seat A F2): the reserved days are the attached days', () {
      for (final (days, want) in const [(2, {0, 1}), (3, {0, 2}), (4, {0, 2}), (5, {0, 3}), (6, {0, 3})]) {
        final p = _plan(days: days, minutes: 60);
        expect(p.days, want, reason: '$days days');
        expect(p.secondsByDay.keys.toSet(), want, reason: '$days days');
      }
    });
    test('no cardio goal or fewer than 2 days: none', () {
      expect(_plan(goal: 'build_muscle'), same(FinisherPlan.none));
      expect(_plan(days: 1), same(FinisherPlan.none));
    });
    test('debugReserve false: the same finisher, nothing reserved', () {
      CardioFinisher.debugReserve = false;
      try {
        final p = _plan(minutes: 60);
        expect(p.seconds, 540);
        expect(p.secondsByDay, isEmpty);
      } finally {
        CardioFinisher.debugReserve = true;
      }
    });
  });

  test('pricing parity (round 2 B-F4): secondsOf == finisherSecondsOfPlanDay for every shape', () {
    final shapes = <String, List<PlannedExercise>>{
      for (final pref in ['running', 'cycling', 'hiit', 'jump_rope', 'hate_cardio'])
        for (final gym in [true, false])
          for (final m in [45, 60]) '$pref gym=$gym $m': _plan(pref: pref, gym: gym, minutes: m).exercises,
      'bike 8': _plan(injuries: const ['knee'], minutes: 60).exercises,
      'bike 4': _plan(injuries: const ['knee'], minutes: 30).exercises,
    };
    final seen = <int>{};
    shapes.forEach((label, items) {
      expect(items, isNotEmpty, reason: label);
      final stored = [for (final e in items) e.toMap()];
      expect(SessionBudget.finisherSecondsOfPlanDay(stored), CardioFinisher.secondsOf(items), reason: label);
      seen.add(CardioFinisher.secondsOf(items));
    });
    // The shapes really differ (a pricing that ignored the rest term would still pass on equal shapes). The OFF HIIT's
    // 360 s (no round rest) went with the kill switch (generator-killswitch-3a3c).
    expect(seen, containsAll(<int>[240, 450, 480, 540]));
  });

  test('finisherSecondsOfPlanDay is total over odd stored rows', () {
    expect(SessionBudget.finisherSecondsOfPlanDay(const []), 0);
    expect(
        SessionBudget.finisherSecondsOfPlanDay([
          'junk',
          null,
          {'duration_seconds': '120', 'sets': '3', 'rest_seconds': '60'},
          {'sets': 2},
          {'duration_seconds': 'x', 'rest_seconds': 30},
          {'duration_seconds': 90},
        ]),
        (120 + 3 * 60) + 0 + (0 + 1 * 30) + 90);
  });

  group('the coach writer (d77 / d78)', () {
    test('every coach body part maps to a profile token', () {
      const parts = {
        'shoulder': 'shoulder',
        'elbow': 'elbow',
        'wrist': 'wrist',
        'lower_back': 'lower_back',
        'upper_back': 'shoulder',
        'knee': 'knee',
        'ankle': 'ankle',
        'hip': 'hip',
        'neck': 'neck',
        'chest': 'shoulder',
        'hamstring': 'hamstring',
        'quad': 'knee',
        'calf': 'ankle',
      };
      parts.forEach((part, token) => expect(InjuryVocab.coachPartToken(part), token, reason: part));
      expect(InjuryVocab.coachPartToken('toe'), isNull);
      expect(InjuryVocab.coachPartToken(null), isNull);
    });
    test('the profile patch adds the token, drops none, keeps the rest, never twice', () {
      expect(coachInjuryProfilePatch({'injuries': ['none']}, 'knee'), {
        'injuries': ['knee'],
      });
      expect(coachInjuryProfilePatch({'injuries': ['wrist']}, 'knee'), {
        'injuries': ['wrist', 'knee'],
      });
      expect(coachInjuryProfilePatch({'injuries': 'none'}, 'knee'), {
        'injuries': ['knee'],
      });
      expect(coachInjuryProfilePatch({'injuries': ['knee']}, 'knee'), isNull);
      expect(coachInjuryProfilePatch({'injuries': ['back']}, 'lower_back'), isNull); // legacy alias
      expect(coachInjuryProfilePatch(const {}, 'knee'), isNull); // no profile
    });
    test('the preview line names the token by its chip label', () {
      expect(coachInjuryAddsLine('knee'), 'Adds Knee to your injuries (change it in Edit Profile)');
      expect(coachInjuryAddsLine('lower_back'), 'Adds Lower Back to your injuries (change it in Edit Profile)');
    });
  });

  group('the confirm card executed line (d77, d79)', () {
    test('a shortened day that lost its finisher says so', () {
      const dropped = ShortenDayResult(
        date: '2026-11-16',
        originalExerciseCount: 5,
        trimmedExerciseCount: 5,
        estimatedOriginalMinutes: 52,
        estimatedTrimmedMinutes: 43,
        droppedExerciseNames: [],
        finisherDropped: true,
      );
      const kept = ShortenDayResult(
        date: '2026-11-16',
        originalExerciseCount: 5,
        trimmedExerciseCount: 4,
        estimatedOriginalMinutes: 52,
        estimatedTrimmedMinutes: 43,
        droppedExerciseNames: ['Curl'],
      );
      expect(executedMessageFor(_intent('shorten_workout'), dropped), 'Workout shortened · finisher removed');
      expect(executedMessageFor(_intent('shorten_workout'), kept), 'Workout shortened');
      expect(executedMessageFor(_intent('shorten_workout'), null), 'Workout shortened');
    });
    test('a coach injury saved to the profile says so', () {
      expect(executedMessageFor(_intent('modify_workout_for_injury'), {'swaps': [], 'profile_injury_added': 'knee'}),
          'No workouts changed · Knee added to your injuries');
      expect(executedMessageFor(_intent('modify_workout_for_injury'), {'swaps': []}), 'No workouts changed');
      expect(
          executedMessageFor(_intent('modify_workout_for_injury'), {
            'swaps': [
              {'date': '2026-11-28', 'from': 'A', 'to': 'B'}
            ]
          }),
          'Workouts updated');
      expect(executedMessageFor(_intent('modify_workout_for_injury'), null), 'Workouts updated');
    });
  });
}
