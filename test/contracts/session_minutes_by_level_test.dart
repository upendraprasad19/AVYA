// OI-488 (Unit 3B, founder d70, 2026-11-16): 90-minute sessions are for advanced users only, keyed on the PROFILE
// level (`fitness_experience`), not the generator's effective level. A stored value above 60 below advanced plans as
// 60; Edit Profile offers 90 only to an advanced profile and moves a 90 selection to 60 when the level drops.
//
// SoT concept `session_duration_minutes`. Plan `docs/plans/2026-11-16-generator-step3b-goal-list.md` §2.3 / §2.4.
//
// Behavioural: the pure rule's table; every reader of the stored value (`sessionMinutesFromProfile` on real Hive,
// `profileParamMinutes` for the two param passers, `initialSessionDuration`); the Edit Profile chip rules.
// PRESENCE (stated): the two param passers (`pro_phase_advance.dart`, `simulation_service.dart`) call
// `SessionBudget.profileParamMinutes` and no raw `session_duration_minutes` cast is left in either.
//
// Mutations (diagnose table): keyed `== 'beginner'`; the 90-chip condition inverted; the pro_phase_advance bypass
// restored; the experience-change reset removed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/profile/screens/edit_profile_screen.dart'
    show sessionDurationOptions, sessionDurationForExperience;
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

import '../helpers/hive_test_setup.dart';

String _noComments(String s) => s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('SessionBudget.minutesForLevel (pure)', () {
    test('above 60 below advanced -> 60; advanced keeps it', () {
      for (final level in <Object?>['beginner', 'intermediate', null, 'Advanced', 'ADVANCED', '', 7, 'expert']) {
        expect(SessionBudget.minutesForLevel(90, level), 60, reason: '$level');
        expect(SessionBudget.minutesForLevel(90.0, level), 60, reason: '$level (double)');
        expect(SessionBudget.minutesForLevel(120, level), 60, reason: '$level 120');
        expect(SessionBudget.minutesForLevel(61, level), 60, reason: '$level 61');
      }
      expect(SessionBudget.minutesForLevel(90, 'advanced'), 90);
      expect(SessionBudget.minutesForLevel(120, 'advanced'), 120);
    });

    test('60 or less, null and garbage are returned unchanged for every level', () {
      for (final level in <Object?>['beginner', 'intermediate', 'advanced', null]) {
        for (final v in <Object?>[60, 45, 30, 60.0, null, 'abc', '90', double.nan, -5]) {
          final out = SessionBudget.minutesForLevel(v, level);
          if (v is double && v.isNaN) {
            expect(out is double && out.isNaN, isTrue, reason: '$level NaN');
          } else {
            expect(out, v, reason: '$level $v');
          }
        }
      }
    });

    test('profileParamMinutes caps, then converts like the old (as num?)?.toInt()', () {
      expect(SessionBudget.profileParamMinutes({'session_duration_minutes': 90, 'fitness_experience': 'beginner'}), 60);
      expect(SessionBudget.profileParamMinutes({'session_duration_minutes': 90}), 60);
      expect(SessionBudget.profileParamMinutes({'session_duration_minutes': 90.0, 'fitness_experience': 'advanced'}), 90);
      expect(SessionBudget.profileParamMinutes({'session_duration_minutes': 45, 'fitness_experience': 'intermediate'}), 45);
      expect(SessionBudget.profileParamMinutes({'session_duration_minutes': '90'}), isNull);
      expect(SessionBudget.profileParamMinutes(const {}), isNull);
    });
  });

  group('sessionMinutesFromProfile (real Hive): the generator, swap and schedule readers', () {
    late Directory tempDir;
    setUp(() async => tempDir = await setUpHiveForTests());
    tearDown(() => tearDownHiveForTests(tempDir));

    Future<Object?> read(Map<String, dynamic> p) async {
      await HiveService.instance.userBox.put('profile', p);
      return TrainingHistoryAnalyzer.sessionMinutesFromProfile();
    }

    test('a stored 90 resolves to 60 below advanced and 90 for advanced', () async {
      for (final level in ['beginner', 'intermediate']) {
        final v = await read({'session_duration_minutes': 90, 'fitness_experience': level});
        expect(SessionBudget.resolveMinutes(profileValue: v), 60, reason: level);
      }
      final adv = await read({'session_duration_minutes': 90, 'fitness_experience': 'advanced'});
      expect(SessionBudget.resolveMinutes(profileValue: adv), 90);
      final none = await read({'session_duration_minutes': 90});
      expect(SessionBudget.resolveMinutes(profileValue: none), 60, reason: 'no level is not advanced (d70)');
    });
  });

  group('Edit Profile chips', () {
    test('90 is offered to an advanced profile only', () {
      expect(sessionDurationOptions('advanced'), [30, 45, 60, 90]);
      for (final level in ['beginner', 'intermediate', '']) {
        expect(sessionDurationOptions(level), [30, 45, 60], reason: level);
      }
    });

    test('dropping the level below advanced moves a 90 selection to 60; other selections are kept', () {
      expect(sessionDurationForExperience(90, 'intermediate'), 60);
      expect(sessionDurationForExperience(90, 'beginner'), 60);
      expect(sessionDurationForExperience(90, 'advanced'), 90);
      for (final level in ['beginner', 'intermediate', 'advanced']) {
        for (final v in [30, 45, 60, null]) {
          expect(sessionDurationForExperience(v, level), v, reason: '$level $v');
        }
      }
    });

    test('the reset only caps down: back to Advanced keeps 60 until the user taps 90 again (B-pass, by design)', () {
      // An advanced user with 90 picks Intermediate (90 -> 60), then Advanced again: the form keeps 60; the 90 chip
      // is offered again and the user can tap it. Nothing restores the stored value behind their back.
      var selected = sessionDurationForExperience(90, 'intermediate');
      selected = sessionDurationForExperience(selected, 'advanced');
      expect(selected, 60);
      expect(sessionDurationOptions('advanced'), contains(90));
    });
  });

  test('PRESENCE: the two param passers cap through profileParamMinutes', () {
    for (final path in ['lib/shared/services/pro_phase_advance.dart', 'lib/features/dev/simulation_service.dart']) {
      final src = _noComments(File(path).readAsStringSync());
      expect(src.contains('SessionBudget.profileParamMinutes(profile)'), isTrue, reason: path);
      expect(RegExp(r"\(profile\['session_duration_minutes'\] as num\?\)").hasMatch(src), isFalse,
          reason: '$path: a raw cast bypasses the cap (the param wins over the profile value)');
      // B-pass: ANY other read of the key in these files (as int?, .toInt(), a helper of their own) bypasses it too.
      expect(RegExp("'session_duration_minutes'").allMatches(src).length, 0,
          reason: '$path: the stored minutes are read only through SessionBudget.profileParamMinutes');
    }
    final screen = _noComments(File('lib/features/profile/screens/edit_profile_screen.dart').readAsStringSync());
    expect(screen.contains('final options = sessionDurationOptions(_fitnessExperience);'), isTrue);
    expect(screen.contains('_sessionDuration = sessionDurationForExperience(_sessionDuration, opt.\$1);'), isTrue);
  });
}
