import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

void main() {
  group('loggedCountsAsPhaseTrainingDayEnabled', () {
    test('defaults to false with no Hive', () {
      expect(PlanEngineFlags.loggedCountsAsPhaseTrainingDayEnabled, isFalse);
    });
  });

  group('isRestDayConsideringLogged (flag OFF, no Hive → default OFF)', () {
    test('workout and custom_template are training (not rest)', () {
      expect(PlanEngineFlags.isRestDayConsideringLogged('workout'), isFalse);
      expect(
          PlanEngineFlags.isRestDayConsideringLogged('custom_template'), isFalse);
    });

    test('logged reads as REST when the flag is off — the pre-fix shape', () {
      expect(PlanEngineFlags.isRestDayConsideringLogged('logged'), isTrue);
    });

    test('rest, off, and null are rest', () {
      expect(PlanEngineFlags.isRestDayConsideringLogged('rest'), isTrue);
      expect(PlanEngineFlags.isRestDayConsideringLogged('off'), isTrue);
      expect(PlanEngineFlags.isRestDayConsideringLogged(null), isTrue);
    });
  });
}
