// goal-change-targets B2 (pure): the weigh-in rule. A weigh-in recomputes the targets only when
// the 7-day mean has drifted MORE than 2.0 kg from the weight the targets were built from.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';
import 'package:icanbefitter/features/profile/services/weigh_in_target_refresh.dart';

Map<String, dynamic> _profile({
  double weight = 80,
  double? basis,
  String goal = 'lose_fat',
}) {
  final p = <String, dynamic>{
    'current_weight_kg': weight,
    'height_cm': 178.0,
    'date_of_birth': '1995-06-15',
    'gender': 'male',
    'primary_goal': goal,
    'lifestyle_activity': 'moderately_active',
    'days_per_week': 4,
    'pace_preference': 'balanced',
    'target_weight_kg': 70.0,
  };
  final built = recomputeDerivedTargets(p, now: DateTime(2026, 11, 18))!;
  p.addAll(built);
  if (basis != null) {
    p[kTargetsBasisWeightKey] = basis;
  } else {
    p.remove(kTargetsBasisWeightKey);
  }
  return p;
}

MapEntry<dynamic, dynamic> _w(String day, num kg, {String type = 'weight_log'}) =>
    MapEntry('weight_$day', {'type': type, 'date': day, 'weight_kg': kg});

void main() {
  final now = DateTime(2026, 11, 18);

  group('band in integer tenths', () {
    test('exactly 2.0 kg does not recompute, 2.1 does', () {
      expect(weighInDriftExceedsBand(82.0, 80.0), isFalse);
      expect(weighInDriftExceedsBand(82.1, 80.0), isTrue);
      expect(weighInDriftExceedsBand(78.0, 80.0), isFalse);
      expect(weighInDriftExceedsBand(77.9, 80.0), isTrue);
    });

    test('the float trap: 64.4 against 62.4 is exactly 2.0 and does not recompute', () {
      expect(64.4 - 62.4 > 2.0, isTrue, reason: 'the raw double compare would fire');
      expect(weighInDriftExceedsBand(64.4, 62.4), isFalse);
    });
  });

  group('decision', () {
    test('no basis anywhere -> nothing', () {
      final r = weighInTargetRefresh(<String, dynamic>{},
          smoothedKg: 90, now: now, bodyFatCalcDisabled: false);
      expect(r.patch, isNull);
      expect(r.targetsMoved, isFalse);
    });

    test('inside the band with no stored basis seeds ONLY the basis (the stored weight)', () {
      final r = weighInTargetRefresh(_profile(weight: 80),
          smoothedKg: 81.5, now: now, bodyFatCalcDisabled: false);
      expect(r.patch, <String, dynamic>{kTargetsBasisWeightKey: 80.0});
      expect(r.targetsMoved, isFalse);
    });

    test('inside the band with a stored basis does nothing', () {
      final r = weighInTargetRefresh(_profile(weight: 81, basis: 80),
          smoothedKg: 81.5, now: now, bodyFatCalcDisabled: false);
      expect(r.patch, isNull);
    });

    test('over the band recomputes from the mean and moves the basis with it', () {
      final p = _profile(weight: 80, basis: 80);
      final r = weighInTargetRefresh(p,
          smoothedKg: 77.0, now: now, bodyFatCalcDisabled: false);
      expect(r.patch, isNotNull);
      expect(r.patch![kTargetsBasisWeightKey], 77.0);
      expect(r.targetsMoved, isTrue);
      expect(r.caloriesFrom, p['daily_calories']);
      expect(r.caloriesTo, r.patch!['daily_calories']);
      expect(r.caloriesTo, isNot(r.caloriesFrom));
    });

    test('an incomplete profile over the band -> nothing', () {
      final p = _profile(weight: 80, basis: 80)..remove('height_cm');
      final r = weighInTargetRefresh(p,
          smoothedKg: 70, now: now, bodyFatCalcDisabled: false);
      expect(r.patch, isNull);
    });

    test('a 12-week loss of 0.4 kg a week recomputes at week 6 and again at week 12', () {
      var p = _profile(weight: 80, basis: 80);
      final fired = <int>[];
      for (var week = 1; week <= 12; week++) {
        final kg = 80 - 0.4 * week;
        final r = weighInTargetRefresh(p,
            smoothedKg: kg, now: now, bodyFatCalcDisabled: false);
        if (r.patch != null && r.targetsMoved) {
          fired.add(week);
          p = {...p, ...r.patch!};
        }
        p['current_weight_kg'] = kg;
      }
      expect(fired, [6, 12]);
    });
  });

  group('recentWeighInKgs', () {
    test('mean over a 7-day window with gaps; today and today-6 count, today-7 does not', () {
      final kgs = recentWeighInKgs([
        _w('2026-11-18', 80),
        _w('2026-11-15', 81),
        _w('2026-11-12', 82),
        _w('2026-11-11', 99),
      ], '2026-11-18');
      expect(kgs..sort(), [80, 81, 82]);
      expect(smoothedWeightKg(kgs, 0), 81);
    });

    test('rejects a future row, a weight_log_ key, another type, 0, 501 and a non-number', () {
      final kgs = recentWeighInKgs([
        _w('2026-11-19', 90),
        MapEntry('weight_log_2026-11-18', {'type': 'weight_log', 'weight_kg': 90}),
        _w('2026-11-17', 90, type: 'step_log'),
        _w('2026-11-16', 0),
        _w('2026-11-15', 501),
        MapEntry('weight_2026-11-14', {'type': 'weight_log', 'weight_kg': '90'}),
        MapEntry('weight_garbage', {'type': 'weight_log', 'weight_kg': 90}),
        const MapEntry('other_2026-11-13', {'type': 'weight_log', 'weight_kg': 90}),
        _w('2026-11-13', 79.5),
      ], '2026-11-18');
      expect(kgs, [79.5]);
    });

    test('zero qualifying entries -> the raw weigh-in', () {
      expect(smoothedWeightKg(const <double>[], 83.2), 83.2);
    });

    test('a mean that is not exactly representable still feeds the band in tenths', () {
      final kgs = recentWeighInKgs([
        _w('2026-11-18', 80.1),
        _w('2026-11-17', 80.2),
        _w('2026-11-16', 80.4),
      ], '2026-11-18');
      final mean = smoothedWeightKg(kgs, 0);
      expect(weighInDriftExceedsBand(mean, 78.2), isFalse); // 802 - 782 = 20 tenths
      expect(weighInDriftExceedsBand(mean, 78.1), isTrue);
    });
  });

  test('the overlay carries the basis key', () {
    final o = recomputeDerivedTargets(_profile(weight: 77), now: now)!;
    expect(o.containsKey(kTargetsBasisWeightKey), isTrue);
    expect(o[kTargetsBasisWeightKey], 77.0);
  });
}
