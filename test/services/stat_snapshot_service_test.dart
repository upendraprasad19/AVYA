import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/stat_snapshot_service.dart';

void main() {
  group('UserStatSnapshot.fromRow', () {
    test('parses a complete row', () {
      final row = {
        'id': 'uuid-1',
        'user_id': 'user-1',
        'snapshot_at': '2026-05-01T12:00:00Z',
        'source': 'onboarding',
        'rank_at_snapshot': null,
        'weight_kg': 76.9,
        'body_fat_pct': 18.0,
        'height_cm': 178.0,
        'age_years': 32,
        'measurements': {'chest': 100.0, 'waist': 84.0},
        'photos': null,
        'avg_calories_7d': 2400,
        'avg_protein_7d': 145,
        'avg_steps_7d': 8200,
        'avg_sleep_hours_7d': 7.2,
        'plan_phase': 1,
        'plan_week': 1,
        'primary_goal': 'build_muscle',
      };
      final s = UserStatSnapshot.fromRow(row);
      expect(s.id, 'uuid-1');
      expect(s.weightKg, 76.9);
      expect(s.measurements['chest'], 100.0);
      expect(s.avgCalories7d, 2400);
    });

    test('handles null/missing optional fields', () {
      final row = {
        'id': 'uuid-2',
        'user_id': 'user-1',
        'snapshot_at': '2026-05-01T12:00:00Z',
        'source': 'manual',
      };
      final s = UserStatSnapshot.fromRow(row);
      expect(s.weightKg, isNull);
      expect(s.measurements, isEmpty);
      expect(s.photos, isEmpty);
    });
  });

  group('StatSnapshotService.diff', () {
    test('computes weight + body fat + elapsed deltas', () {
      final base = UserStatSnapshot(
        id: 'a',
        userId: 'u',
        snapshotAt: DateTime(2026, 1, 1),
        source: 'onboarding',
        weightKg: 80.0,
        bodyFatPct: 22.0,
        avgCalories7d: 2200,
        avgProtein7d: 120,
      );
      final later = UserStatSnapshot(
        id: 'b',
        userId: 'u',
        snapshotAt: DateTime(2026, 4, 1),
        source: 'promotion',
        weightKg: 75.0,
        bodyFatPct: 17.5,
        avgCalories7d: 2400,
        avgProtein7d: 145,
      );
      final d = StatSnapshotService.instance.diff(base, later);
      expect(d.weightDeltaKg, -5.0);
      expect(d.bodyFatDelta, -4.5);
      expect(d.caloriesDelta, 200);
      expect(d.proteinDelta, 25);
      expect(d.elapsed!.inDays, 90);
    });

    test('null fields produce null deltas (not zero)', () {
      final base = UserStatSnapshot(
        id: 'a',
        userId: 'u',
        snapshotAt: DateTime(2026, 1, 1),
        source: 'onboarding',
        weightKg: 80.0,
      );
      final later = UserStatSnapshot(
        id: 'b',
        userId: 'u',
        snapshotAt: DateTime(2026, 4, 1),
        source: 'manual',
        weightKg: null,
      );
      final d = StatSnapshotService.instance.diff(base, later);
      expect(d.weightDeltaKg, isNull);
      expect(d.bodyFatDelta, isNull);
    });
  });

  group('StatSnapshotDiff.shortDescription', () {
    test('renders weight then→now and weeks elapsed', () {
      final base = UserStatSnapshot(
        id: 'a',
        userId: 'u',
        snapshotAt: DateTime(2026, 1, 1),
        source: 'onboarding',
        weightKg: 76.9,
      );
      final later = UserStatSnapshot(
        id: 'b',
        userId: 'u',
        snapshotAt: DateTime(2026, 3, 26), // 12 weeks
        source: 'manual',
        weightKg: 73.5,
      );
      final d = StatSnapshotService.instance.diff(base, later);
      expect(d.shortDescription(), '76.9 kg → 73.5 kg · 12 weeks');
    });

    test('falls back when weights are missing', () {
      final base = UserStatSnapshot(
        id: 'a',
        userId: 'u',
        snapshotAt: DateTime(2026, 1, 1),
        source: 'onboarding',
      );
      final later = UserStatSnapshot(
        id: 'b',
        userId: 'u',
        snapshotAt: DateTime(2026, 1, 8),
        source: 'manual',
      );
      final d = StatSnapshotService.instance.diff(base, later);
      expect(d.shortDescription(), '1 weeks');
    });
  });
}
