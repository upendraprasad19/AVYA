import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

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
  List<ToolIntent> build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    return const [];
  }

  /// Add intents received from a new ai-proxy response.
  /// Filters out duplicates by id (idempotent if response is replayed).
  ///
  /// Coach workout parity S3: an auto-run intent ([kAutoRunIntentTypes], the
  /// "I'm done" tile) never enters `state`; it is dispatched once, at once.
  /// The partition lives here so it covers every caller. A replay of the same
  /// intent id is a no-op in the dispatcher (its Hive marker).
  void addIntents(List<ToolIntent> intents) {
    if (intents.isEmpty) return;
    final queued =
        intents.where((i) => !kAutoRunIntentTypes.contains(i.type)).toList();
    if (queued.isNotEmpty) {
      _expireStale(); // sweep before adding
      final existingIds = state.map((i) => i.id).toSet();
      final fresh =
          queued.where((i) => !existingIds.contains(i.id)).toList();
      if (fresh.isNotEmpty) state = [...state, ...fresh];
    }
    // After the queued cards are in state, so the dispatcher sees the whole
    // list (a log_set APPLY that is running blocks the tile; a card waiting
    // for APPLY does not). The dispatcher gets this state directly: this
    // notifier's ref cannot read its own provider.
    for (final intent in intents) {
      if (!kAutoRunIntentTypes.contains(intent.type)) continue;
      unawaited(
        ToolDispatcher.instance
            .execute(ref, intent, pendingIntents: state)
            .catchError(
          (Object e, StackTrace st) {
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'auto_run_intent_dispatch'));
            return ToolExecutionResult.failure(e.toString());
          },
        ),
      );
    }
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
