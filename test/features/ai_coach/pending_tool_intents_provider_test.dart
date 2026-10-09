import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/pending_tool_intents_provider.dart';

ToolIntent _intent({
  String id = 'i1',
  ToolIntentStatus status = ToolIntentStatus.pending,
  Duration age = Duration.zero,
}) {
  return ToolIntent(
    id: id,
    type: 't',
    payload: {},
    confirmationClass: ConfirmationClass.trivial,
    previewSummary: '',
    createdAt: DateTime.now().subtract(age),
    status: status,
  );
}

void main() {
  group('PendingToolIntentsNotifier', () {
    test('addIntents adds and dedupes by id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingToolIntentsProvider.notifier);

      notifier.addIntents([_intent(id: 'a'), _intent(id: 'b')]);
      expect(container.read(pendingToolIntentsProvider).length, 2);

      // Re-add 'a' — should dedupe
      notifier.addIntents([_intent(id: 'a'), _intent(id: 'c')]);
      expect(container.read(pendingToolIntentsProvider).length, 3);
      expect(
        container.read(pendingToolIntentsProvider).map((i) => i.id).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('reject sets status to rejected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingToolIntentsProvider.notifier);

      notifier.addIntents([_intent(id: 'a')]);
      notifier.reject('a');
      expect(
        container.read(pendingToolIntentsProvider).first.status,
        ToolIntentStatus.rejected,
      );
    });

    test('addIntents sweeps stale (>1h) intents to expired', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingToolIntentsProvider.notifier);

      // Add a stale pending intent
      notifier.addIntents([_intent(id: 'old', age: const Duration(hours: 2))]);
      // Add a fresh one — triggers sweep
      notifier.addIntents([_intent(id: 'new')]);

      final state = container.read(pendingToolIntentsProvider);
      final old = state.firstWhere((i) => i.id == 'old');
      final fresh = state.firstWhere((i) => i.id == 'new');
      expect(old.status, ToolIntentStatus.expired);
      expect(fresh.status, ToolIntentStatus.pending);
    });

    test('prune removes settled intents older than 5 min', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingToolIntentsProvider.notifier);

      notifier.addIntents([
        _intent(id: 'recent_executed', status: ToolIntentStatus.executed),
        _intent(
          id: 'old_executed',
          status: ToolIntentStatus.executed,
          age: const Duration(minutes: 10),
        ),
        _intent(id: 'pending', status: ToolIntentStatus.pending),
        _intent(
          id: 'failed_old',
          status: ToolIntentStatus.failed,
          age: const Duration(minutes: 10),
        ),
      ]);

      notifier.prune();

      final ids =
          container.read(pendingToolIntentsProvider).map((i) => i.id).toList();
      // recent_executed: kept (settled but recent)
      // old_executed: removed (settled + old)
      // pending: kept (still active)
      // failed_old: kept (failed = active state, not settled)
      expect(ids.contains('recent_executed'), true);
      expect(ids.contains('old_executed'), false);
      expect(ids.contains('pending'), true);
      expect(ids.contains('failed_old'), true);
    });

    test('confirm on missing intent returns failure', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingToolIntentsProvider.notifier);

      final result = await notifier.confirm('nonexistent');
      expect(result.success, false);
      expect(result.errorMessage, contains('not found'));
    });

    test('confirm on expired intent returns failure', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingToolIntentsProvider.notifier);

      notifier.addIntents([_intent(id: 'old', age: const Duration(hours: 2))]);
      // The addIntents sweep should have marked it expired.
      final result = await notifier.confirm('old');
      expect(result.success, false);
    });
  });
}
