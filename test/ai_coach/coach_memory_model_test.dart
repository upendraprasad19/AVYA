import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';

void main() {
  group('CoachMemory', () {
    test('round-trips through JSON', () {
      final original = CoachMemory(
        userId: 'u1',
        preferredName: 'Upen',
        communicationStyle: 'hinglish',
        depthPreference: 'action_taker',
        motivationStyle: 'data_driven',
        injuries: [{'part': 'shoulder', 'severity': 'mild'}],
        dropoutRiskScore: 0.42,
        privateMode: false,
      );
      final decoded = CoachMemory.fromJson(original.toJson());
      expect(decoded.preferredName, 'Upen');
      expect(decoded.communicationStyle, 'hinglish');
      expect(decoded.dropoutRiskScore, closeTo(0.42, 0.001));
      expect(decoded.injuries, hasLength(1));
    });

    test('fromJson handles null and missing fields', () {
      final mem = CoachMemory.fromJson({'user_id': 'u1'});
      expect(mem.userId, 'u1');
      expect(mem.preferredName, isNull);
      expect(mem.privateMode, isFalse);
      expect(mem.injuries, isEmpty);
    });

    test('merge() overwrites only non-null fields', () {
      final base = CoachMemory(userId: 'u1', preferredName: 'Upen');
      final patch = CoachMemory(userId: 'u1', communicationStyle: 'hinglish');
      final merged = base.merge(patch);
      expect(merged.preferredName, 'Upen');
      expect(merged.communicationStyle, 'hinglish');
    });
  });
}
