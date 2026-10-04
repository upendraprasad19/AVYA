import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/water_target_service.dart';

void main() {
  group('WaterTargetService.computeFromProfile', () {
    test('floors at 2500 ml for small sedentary user', () {
      final ml = WaterTargetService.computeFromProfile({
        'current_weight_kg': 50,
        'lifestyle_activity': 'sedentary',
        'days_per_week': 0,
      });
      expect(ml, 2500); // 50*35=1750 → floor
    });

    test('caps at 4000 ml for very heavy very active 6-day lifter', () {
      final ml = WaterTargetService.computeFromProfile({
        'current_weight_kg': 130,
        'lifestyle_activity': 'very_active',
        'days_per_week': 6,
      });
      expect(ml, 4000); // 130*35+500+300=5350 → ceiling
    });

    test('75 kg moderate 4-day lifter → 3125 ml clamped pass-through', () {
      final ml = WaterTargetService.computeFromProfile({
        'current_weight_kg': 75,
        'lifestyle_activity': 'moderate',
        'days_per_week': 4,
      });
      expect(ml, 3125); // 75*35+500=3125
    });

    test('60 kg very_active 4-day lifter → 2900 ml', () {
      final ml = WaterTargetService.computeFromProfile({
        'current_weight_kg': 60,
        'lifestyle_activity': 'very_active',
        'days_per_week': 4,
      });
      expect(ml, 2900); // 60*35+500+300=2900
    });

    test('null/missing fields fall back to defaults (70kg moderate 0-day → floor)', () {
      final ml = WaterTargetService.computeFromProfile({});
      expect(ml, 2500); // 70*35=2450 → floor
    });

    test('active lifestyle but under 4 days still adds 300 ml boost', () {
      final ml = WaterTargetService.computeFromProfile({
        'current_weight_kg': 70,
        'lifestyle_activity': 'active',
        'days_per_week': 3,
      });
      // 70*35=2450, no days bonus (3<4), +300 active = 2750
      expect(ml, 2750);
    });
  });
}
