// goal-change-targets B2b (pure): the first-sign-in merge recomputes the derived targets when the
// merge changed a derivation input, on a NON-EMPTY local profile only, and fails open.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/services/profile_cloud_merge.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';

Map<String, dynamic> _inputs(double kg) => {
      'current_weight_kg': kg,
      'height_cm': 178.0,
      'date_of_birth': '1995-06-15',
      'gender': 'male',
      'primary_goal': 'lose_fat',
      'lifestyle_activity': 'moderately_active',
      'days_per_week': 4,
      'pace_preference': 'balanced',
      'target_weight_kg': 70.0,
    };

final _now = DateTime(2026, 11, 18);

Map<String, dynamic> _merge(
  Map<String, dynamic>? existing,
  Map<String, dynamic> cloud, {
  bool recomputeDisabled = false,
  bool bodyFatOff = false,
}) =>
    mergeCloudProfileWithTargets(
      existing: existing,
      cloud: cloud,
      now: _now,
      bodyFatCalcDisabled: bodyFatOff,
      recomputeDisabled: recomputeDisabled,
    );

void main() {
  final local = {..._inputs(80), 'daily_calories': 2111, 'protein_grams': 150};
  final cloud = {..._inputs(74), 'daily_calories': 2111, 'protein_grams': 150};

  test('local data plus a cloud weight recomputes the targets and writes the basis', () {
    final m = _merge(local, cloud);
    expect(m['current_weight_kg'], 74);
    expect(m[kTargetsBasisWeightKey], 74.0);
    expect(m['daily_calories'], isNot(2111));
  });

  test('a null or empty local profile keeps the cloud targets verbatim', () {
    for (final existing in <Map<String, dynamic>?>[null, <String, dynamic>{}]) {
      final m = _merge(existing, cloud);
      expect(m['daily_calories'], 2111, reason: 'existing=$existing');
      expect(m.containsKey(kTargetsBasisWeightKey), isFalse);
    }
  });

  test('no input change -> no recompute (the body-fat healer lock)', () {
    final m = _merge(local, {...local});
    expect(m['daily_calories'], 2111);
    expect(m.containsKey(kTargetsBasisWeightKey), isFalse);
  });

  test('either kill switch: recompute disabled leaves the plain merge', () {
    final m = _merge(local, cloud, recomputeDisabled: true);
    expect(m['daily_calories'], 2111);
    expect(m['current_weight_kg'], 74);
  });

  test('a local map of stray keys only (id, email, a view setting) is a fresh device', () {
    final m = _merge({'id': 'u', 'email': 'a@b.c', 'diet_serving_view': 'grams'}, cloud);
    expect(m['daily_calories'], 2111);
    expect(m.containsKey(kTargetsBasisWeightKey), isFalse);
  });

  test('an ISO-timestamp date of birth against the cloud YYYY-MM-DD is no change', () {
    final isoLocal = {...local, 'date_of_birth': '1995-06-15T00:00:00.000'};
    final m = _merge(isoLocal, {...local});
    expect(m['daily_calories'], 2111);
    expect(m.containsKey(kTargetsBasisWeightKey), isFalse);
  });

  test('the body-fat switch reaches the merge recompute', () {
    final withFat = {...local, 'body_fat_percent': 24.0};
    final cloudFat = {...cloud, 'body_fat_percent': 24.0};
    final on = _merge(withFat, cloudFat);
    final off = _merge(withFat, cloudFat, bodyFatOff: true);
    expect(on['daily_calories'], isNot(off['daily_calories']));
  });

  test('cloud nulls never erase a local value', () {
    final m = _merge(local, {..._inputs(80), 'height_cm': null});
    expect(m['height_cm'], 178.0);
  });

  test('a null overlay (incomplete profile) leaves the map as merged', () {
    final m = _merge({'current_weight_kg': 80.0, 'primary_goal': 'lose_fat'},
        {'current_weight_kg': 74.0});
    expect(m['current_weight_kg'], 74.0);
    expect(m.containsKey('daily_calories'), isFalse);
  });

  test('a String height_cm still produces the plain merge (fail-open)', () {
    final broken = {...local, 'height_cm': '178'};
    final m = _merge(broken, {..._inputs(74), 'height_cm': '178'});
    expect(m['current_weight_kg'], 74);
    expect(m['daily_calories'], 2111);
  });
}
