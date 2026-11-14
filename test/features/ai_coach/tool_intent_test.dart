import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';

void main() {
  group('ToolIntent', () {
    test('fromJson parses server response', () {
      final json = {
        'id': 'intent-1',
        'type': 'swap_exercise',
        'payload': {'exerciseId': 'ex1', 'newExerciseId': 'ex2'},
        'confirmationClass': 'reviewable',
        'previewSummary': 'Squat → Goblet Squat',
        'createdAt': DateTime.now().toIso8601String(),
      };
      final intent = ToolIntent.fromJson(json);
      expect(intent.id, 'intent-1');
      expect(intent.type, 'swap_exercise');
      expect(intent.payload['exerciseId'], 'ex1');
      expect(intent.confirmationClass, ConfirmationClass.reviewable);
      expect(intent.status, ToolIntentStatus.pending);
    });

    test('fromJson defaults confirmationClass to reviewable on unknown', () {
      final json = {
        'id': 'intent-1',
        'type': 'x',
        'payload': {},
        'confirmationClass': 'mystery',
        'previewSummary': '',
        'createdAt': DateTime.now().toIso8601String(),
      };
      final intent = ToolIntent.fromJson(json);
      expect(intent.confirmationClass, ConfirmationClass.reviewable);
    });

    test('isExpired returns true after 1h', () {
      final intent = ToolIntent(
        id: 'i1',
        type: 't',
        payload: {},
        confirmationClass: ConfirmationClass.trivial,
        previewSummary: '',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(intent.isExpired, true);
    });

    test('isExpired returns false within 1h', () {
      final intent = ToolIntent(
        id: 'i1',
        type: 't',
        payload: {},
        confirmationClass: ConfirmationClass.trivial,
        previewSummary: '',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      expect(intent.isExpired, false);
    });

    test('isActionable: pending + not expired => true', () {
      final intent = ToolIntent(
        id: 'i1',
        type: 't',
        payload: {},
        confirmationClass: ConfirmationClass.trivial,
        previewSummary: '',
        createdAt: DateTime.now(),
      );
      expect(intent.isActionable, true);
    });

    test('isActionable: failed + not expired => true (retry path)', () {
      final intent = ToolIntent(
        id: 'i1',
        type: 't',
        payload: {},
        confirmationClass: ConfirmationClass.trivial,
        previewSummary: '',
        createdAt: DateTime.now(),
        status: ToolIntentStatus.failed,
      );
      expect(intent.isActionable, true);
    });

    test('isActionable: executed => false', () {
      final intent = ToolIntent(
        id: 'i1',
        type: 't',
        payload: {},
        confirmationClass: ConfirmationClass.trivial,
        previewSummary: '',
        createdAt: DateTime.now(),
        status: ToolIntentStatus.executed,
      );
      expect(intent.isActionable, false);
    });

    test('isActionable: expired => false', () {
      final intent = ToolIntent(
        id: 'i1',
        type: 't',
        payload: {},
        confirmationClass: ConfirmationClass.trivial,
        previewSummary: '',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(intent.isActionable, false);
    });

    test('copyWith updates only specified fields', () {
      final original = ToolIntent(
        id: 'i1',
        type: 't',
        payload: {'a': 1},
        confirmationClass: ConfirmationClass.trivial,
        previewSummary: 'orig',
        createdAt: DateTime.now(),
      );
      final updated = original.copyWith(
        status: ToolIntentStatus.executed,
      );
      expect(updated.id, original.id);
      expect(updated.type, original.type);
      expect(updated.previewSummary, 'orig');
      expect(updated.status, ToolIntentStatus.executed);
    });
  });
}
