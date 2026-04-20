import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tool_intent.dart';
import '../services/tool_dispatcher.dart';

/// Holds the list of queued AI coach tool intents awaiting user confirmation
/// or in-flight / completed.
///
/// Lifecycle:
///   pending → confirming → executing → executed | failed
///   pending → rejected (user explicitly dismissed)
///   pending → expired (1h TTL)
///   failed → confirming (retry)
class PendingToolIntentsNotifier extends Notifier<List<ToolIntent>> {
  @override
  List<ToolIntent> build() => const [];

  /// Add intents received from a new ai-proxy response.
  /// Filters out duplicates by id (idempotent if response is replayed).
  void addIntents(List<ToolIntent> intents) {
    if (intents.isEmpty) return;
    _expireStale(); // sweep before adding
    final existingIds = state.map((i) => i.id).toSet();
    final fresh =
        intents.where((i) => !existingIds.contains(i.id)).toList();
    if (fresh.isEmpty) return;
    state = [...state, ...fresh];
  }

  /// User confirmed an intent. Sets status=executing, dispatches, then
  /// updates to executed | failed.
  Future<ToolExecutionResult> confirm(String intentId) async {
    final intent = _findById(intentId);
    if (intent == null) {
      return const ToolExecutionResult.failure('Intent not found.');
    }
    if (!intent.isActionable) {
      return ToolExecutionResult.failure(
        intent.isExpired
            ? 'This suggestion has expired.'
            : 'Already handled.',
      );
    }

    _updateStatus(intentId, ToolIntentStatus.executing);

    final result = await ToolDispatcher.instance.execute(ref, intent);

    if (result.success) {
      _updateStatus(intentId, ToolIntentStatus.executed);
    } else {
      _updateStatusWithError(
        intentId,
        ToolIntentStatus.failed,
        result.errorMessage ?? 'Failed.',
      );
    }
    return result;
  }

  /// User explicitly rejected an intent.
  void reject(String intentId) {
    _updateStatus(intentId, ToolIntentStatus.rejected);
  }

  /// Retry a failed intent.
  Future<ToolExecutionResult> retry(String intentId) {
    return confirm(intentId);
  }

  /// Remove fully settled intents (executed, rejected, expired) older than 5 min
  /// to keep state lean. Call on app resume or before adding new intents.
  void prune() {
    final now = DateTime.now();
    state = state.where((i) {
      if (i.status == ToolIntentStatus.pending ||
          i.status == ToolIntentStatus.executing ||
          i.status == ToolIntentStatus.failed) {
        return true; // keep active
      }
      // settled — keep if recent
      return now.difference(i.createdAt) < const Duration(minutes: 5);
    }).toList();
  }

  /// Internal: sweep intents past 1h TTL into expired status.
  void _expireStale() {
    bool changed = false;
    final updated = state.map((i) {
      if (i.isExpired && i.status == ToolIntentStatus.pending) {
        changed = true;
        return i.copyWith(status: ToolIntentStatus.expired);
      }
      return i;
    }).toList();
    if (changed) state = updated;
  }

  ToolIntent? _findById(String id) {
    for (final i in state) {
      if (i.id == id) return i;
    }
    return null;
  }

  void _updateStatus(String id, ToolIntentStatus status) {
    state =
        state.map((i) => i.id == id ? i.copyWith(status: status) : i).toList();
  }

  void _updateStatusWithError(
      String id, ToolIntentStatus status, String error) {
    state = state
        .map((i) => i.id == id
            ? i.copyWith(status: status, errorMessage: error)
            : i)
        .toList();
  }
}

final pendingToolIntentsProvider =
    NotifierProvider<PendingToolIntentsNotifier, List<ToolIntent>>(
  PendingToolIntentsNotifier.new,
);
