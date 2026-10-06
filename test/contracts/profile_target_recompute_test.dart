// OI-150 Unit 2a — the profile's DERIVED half is recomputed after a restore
// rather than merged field-by-field.
//
// `_restoreUserProfile` merges cloud over local per key with no guard, so it
// can take cloud's weight and keep the phone's calorie target — a target
// computed from a weight that is no longer in the map. Profile has no
// client-written version stamp to arbitrate with (`updated_at` is server-set
// and absent from the client payload), so instead of versioning it we merge
// the inputs and regenerate the outputs.
//
// ⚠ Goal tokens here are the CANONICAL ones from `fitness_goals.dart`
// (`build_muscle`, not `muscle_gain`). `FitnessGoals.of` ASSERTS on an unknown
// token, so a wrong one makes these tests ERROR rather than fail — a false
// gate. Plan-review round 1 caught exactly that in the first draft.
//
// Run: flutter test test/contracts/profile_target_recompute_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';

void main() {
  final now = DateTime.utc(2026, 8, 30);

  Map<String, dynamic> completeProfile() => <String, dynamic>{
        'current_weight_kg': 80.0,
        'height_cm': 175.0,
        'date_of_birth': '1995-01-01',
        'gender': 'male',
        'primary_goal': 'build_muscle',
        'lifestyle_activity': 'desk_job',
        'days_per_week': 4,
        'pace_preference': 'balanced',
      };

  group('recomputeDerivedTargets (pure)', () {
    test('returns the full derived overlay for a complete profile', () {
      final out = recomputeDerivedTargets(completeProfile(), now: now);
      expect(out, isNotNull);
      expect(
          out!.keys,
          containsAll(<String>[
            'bmr',
            'tdee',
            'daily_calories',
            'protein_grams',
            'carbs_grams',
            'fat_grams',
            'activity_level',
          ]));
      expect(out['daily_calories'], isA<int>());
    });

    test('returns null when any required input is missing', () {
      for (final missing in <String>[
        'current_weight_kg',
        'height_cm',
        'date_of_birth',
        'gender',
        'primary_goal',
      ]) {
        final p = completeProfile()..remove(missing);
        expect(recomputeDerivedTargets(p, now: now), isNull,
            reason: 'missing $missing must abort the recompute rather than '
                'write a partial or invented set');
      }
    });

    test('returns null on an unparseable date_of_birth', () {
      final p = completeProfile()..['date_of_birth'] = 'not-a-date';
      expect(recomputeDerivedTargets(p, now: now), isNull);
    });

    test('c3f2d8: a null body_fat_percent is NOT defaulted', () {
      // If null were being coerced to 18.0 these two would be identical.
      final withNull = completeProfile()..['body_fat_percent'] = null;
      final withValue = completeProfile()..['body_fat_percent'] = 18.0;
      final a = recomputeDerivedTargets(withNull, now: now)!;
      final b = recomputeDerivedTargets(withValue, now: now)!;
      expect(a['daily_calories'], isNot(equals(b['daily_calories'])),
          reason: 'Mifflin (no body fat) and Katch-McArdle (18%) must differ — '
              'equality here means a fabricated default is back');
    });

    test('activity_level is RESOLVED from lifestyle + days, not copied', () {
      final p = completeProfile()
        ..['lifestyle_activity'] = 'desk_job'
        ..['days_per_week'] = 2
        ..['activity_level'] = 'very_active'; // stale stored value
      expect(recomputeDerivedTargets(p, now: now)!['activity_level'], 'light',
          reason: 'desk_job with <=3 days resolves to light; the stale stored '
              'string must not win');
    });

    test('falls back to the stored activity_level when lifestyle is absent',
        () {
      final p = completeProfile()
        ..remove('lifestyle_activity')
        ..['activity_level'] = 'active';
      expect(recomputeDerivedTargets(p, now: now)!['activity_level'], 'active');
    });
  });

  group('restore merge recomputes rather than splitting', () {
    test('cloud weight + local targets → targets follow cloud weight', () {
      final local = completeProfile()..['daily_calories'] = 3000;
      final cloud = <String, dynamic>{'current_weight_kg': 60.0};

      // Exactly what _restoreUserProfile's merge does: cloud wins per key.
      final merged = <String, dynamic>{
        ...local,
        for (final e in cloud.entries)
          if (e.value != null) e.key: e.value,
      };
      final overlay = recomputeDerivedTargets(merged, now: now);
      expect(overlay, isNotNull);
      merged.addAll(overlay!);

      expect(merged['daily_calories'], isNot(3000),
          reason: 'the stale target must not survive alongside cloud weight');
      final fresh = recomputeDerivedTargets(
          completeProfile()..['current_weight_kg'] = 60.0,
          now: now)!;
      expect(merged['daily_calories'], fresh['daily_calories'],
          reason: 'the recomputed set must match a clean computation from the '
              'winning inputs');
    });

    test('incomplete inputs leave the merged map untouched', () {
      final merged = <String, dynamic>{'daily_calories': 2500};
      expect(recomputeDerivedTargets(merged, now: now), isNull);
      expect(merged['daily_calories'], 2500);
    });

    test('the gate fires ONLY when a derivation input changed (B5c)', () {
      // This gate is what honours the founder-locked decision recorded at
      // body_fat_default_healer.dart:28 — "NO daily_calories recompute
      // (founder-locked: no silent backfill)". The healer clears the CLOUD
      // column first and then the local one, so by the next restore both are
      // null, the merge changes nothing, and no recompute fires. The lock is
      // honoured structurally, not by a special case for body fat.
      final before = completeProfile();

      // A restore that changed nothing must NOT recompute.
      expect(derivedTargetInputsChanged(before, {...before}), isFalse);

      // The healer's shape: body fat already null on both sides.
      final healed = completeProfile()..['body_fat_percent'] = null;
      expect(derivedTargetInputsChanged(healed, {...healed}), isFalse,
          reason: 'a healed profile must not have its calorie target rewritten '
              'on the next sign-in');

      // The actual defect: cloud hands over a different weight.
      expect(
          derivedTargetInputsChanged(
              before, {...before, 'current_weight_kg': 60.0}),
          isTrue);

      // Every declared input must move the gate — otherwise the derived set
      // silently stops tracking it.
      for (final k in derivedTargetInputKeys) {
        expect(derivedTargetInputsChanged(before, {...before, k: '__CHANGED__'}),
            isTrue,
            reason: '$k is a declared input but does not move the gate');
      }
    });

    test('a non-input key changing does NOT trigger a recompute', () {
      final before = completeProfile();
      expect(
          derivedTargetInputsChanged(
              before, {...before, 'full_name': 'Someone Else'}),
          isFalse,
          reason: 'full_name/avatar_url/city are not derivation inputs; '
              'recomputing on them would widen the blast for no benefit');
    });

    test('c3f2d8: the disable_bodyfat_calc switch reaches this path (B5a)', () {
      final withBf = completeProfile()..['body_fat_percent'] = 18.0;
      final enabled = recomputeDerivedTargets(withBf, now: now)!;
      final disabled = recomputeDerivedTargets(withBf,
          now: now, bodyFatCalcDisabled: true)!;
      expect(disabled['daily_calories'], isNot(enabled['daily_calories']),
          reason: 'with the switch on, body fat must be excluded (Mifflin) — '
              'otherwise the switch is half-effective: Mifflin at onboarding '
              'and Katch-McArdle here, on the same device');
      final noBf = completeProfile()..['body_fat_percent'] = null;
      expect(disabled['daily_calories'],
          recomputeDerivedTargets(noBf, now: now)!['daily_calories'],
          reason: 'switch on must equal having no body fat at all');
    });

    test('age is CALENDAR age, matching onboarding (B5b)', () {
      // Onboarding uses calendar age (onboarding_provider.dart:384-392); the
      // `inDays ~/ 365` form this replaced disagreed for ~2.1% of birthdays.
      final dayBeforeBirthday = completeProfile()
        ..['date_of_birth'] = '1995-08-31';
      final dayOfBirthday = completeProfile()
        ..['date_of_birth'] = '1995-08-30';
      final a = recomputeDerivedTargets(dayBeforeBirthday,
          now: DateTime.utc(2026, 8, 30))!;
      final b = recomputeDerivedTargets(dayOfBirthday,
          now: DateTime.utc(2026, 8, 30))!;
      expect(a['bmr'], isNot(b['bmr']),
          reason: 'turning 31 today vs tomorrow must differ by one year of '
              'age — a day-granularity formula rounds them together');
    });

    test('_restoreUserProfile wires the recompute correctly (N6)', () {
      // A bare `contains('recomputeDerivedTargets(')` was the original
      // assertion and it is the §2.41 absorbed shape: turning
      // `merged.addAll(overlay)` into a no-op, deleting the kill-switch guard,
      // or moving the call above the usersRow layering all leave the string
      // present and the test green. Pin the WIRING, not the mention.
      final src = File('lib/core/services/sync/sync_profile.dart')
          .readAsStringSync();
      final i = src.indexOf('Future<void> _restoreUserProfile(');
      expect(i, isNot(-1));
      final next = src.indexOf('Future<Map<String, dynamic>?> _fetchUsersRowForRestore(', i);
      final body = src.substring(i, next == -1 ? src.length : next);

      final mergedAt = body.indexOf('final merged = <String, dynamic>{');
      final callAt = body.indexOf('recomputeDerivedTargets(');
      final gateAt = body.indexOf('derivedTargetInputsChanged(');
      final applyAt = body.indexOf('merged.addAll(overlay)');
      final writeAt = body.indexOf('updateProfile(merged, skipSync: true)');

      expect(callAt, isNot(-1), reason: 'the restore must regenerate the '
          'derived half — otherwise the per-key merge can split it');
      expect(gateAt, isNot(-1), reason: 'the input-changed gate is what keeps '
          'the founder-locked no-silent-backfill decision intact');
      expect(applyAt, isNot(-1),
          reason: 'computing an overlay and never applying it is a no-op that '
              'a mention-only assertion cannot see');
      expect(callAt, greaterThan(mergedAt),
          reason: 'it must run AFTER the merge, on the winning inputs');
      expect(applyAt, greaterThan(callAt));
      expect(writeAt, greaterThan(applyAt),
          reason: 'the overlay must land BEFORE the Hive write, or the '
              'recomputed values are computed and thrown away');
      expect(body.contains('kDisableProfileTargetRecomputeKey'), isTrue,
          reason: '§4.6 — the behaviour change needs a reachable kill-switch');
    });
  });
}
