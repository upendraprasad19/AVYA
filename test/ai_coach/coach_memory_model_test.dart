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

    test('merge() preserves privateMode when patch defaults it to false', () {
      final base = CoachMemory(userId: 'u1', privateMode: true);
      final patch = CoachMemory(userId: 'u1', preferredName: 'Upen');
      final merged = base.merge(patch);
      expect(merged.privateMode, isTrue,
          reason: 'merge must never silently disable private_mode');
      expect(merged.preferredName, 'Upen');
    });

    test('merge() collection patch with empty list does not clear base', () {
      final base = CoachMemory(
        userId: 'u1',
        injuries: [{'part': 'shoulder'}],
      );
      final patch = CoachMemory(userId: 'u1');
      final merged = base.merge(patch);
      expect(merged.injuries, hasLength(1));
    });

    // a2b-2 (single-owner batch, 2026-09-27): lockedFieldConflicts is the
    // vessel _getCoachMemoryForContext() (ai_snapshot_builder.dart) passes
    // wholesale into the AI's prompt context via toJson() — these pin the
    // round-trip so a drift here silently breaks a reader that never opens
    // this file.
    test('lockedFieldConflicts round-trips through JSON', () {
      final original = CoachMemory(
        userId: 'u1',
        lockedFieldConflicts: {
          'diet_preference': {'attempted_value': 'non_veg', 'at': '2026-09-27T00:00:00.000Z'},
        },
      );
      final decoded = CoachMemory.fromJson(original.toJson());
      expect(decoded.lockedFieldConflicts['diet_preference'], isA<Map>());
      expect(
        (decoded.lockedFieldConflicts['diet_preference'] as Map)['attempted_value'],
        'non_veg',
      );
    });

    test('lockedFieldConflicts is omitted from toJson when empty (matches every other optional field here)', () {
      final mem = CoachMemory(userId: 'u1');
      expect(mem.toJson().containsKey('locked_field_conflicts'), isFalse);
    });

    test('fromJson defaults lockedFieldConflicts to empty when absent', () {
      final mem = CoachMemory.fromJson({'user_id': 'u1'});
      expect(mem.lockedFieldConflicts, isEmpty);
    });

    test('merge() overlays lockedFieldConflicts only when the patch is non-empty', () {
      final base = CoachMemory(
        userId: 'u1',
        lockedFieldConflicts: {'injuries': {'attempted_value': [], 'at': 'x'}},
      );
      final emptyPatch = CoachMemory(userId: 'u1');
      expect(base.merge(emptyPatch).lockedFieldConflicts, hasLength(1));

      final realPatch = CoachMemory(
        userId: 'u1',
        lockedFieldConflicts: {'diet_preference': {'attempted_value': 'veg', 'at': 'y'}},
      );
      final merged = base.merge(realPatch);
      expect(merged.lockedFieldConflicts.containsKey('diet_preference'), isTrue);
    });
  });
}
