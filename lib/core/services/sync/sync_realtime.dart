part of '../sync_service.dart';

/// PRO Realtime cross-channel sync. Manages the Supabase realtime
/// subscription lifecycle for the active user — used by the Telegram
/// bot relay path so logs land in the app instantly instead of
/// waiting for the 24h batch pull.
extension SyncServiceRealtime on SyncService {
  // ── PRO Realtime Sync ──────────────────────────────────────

  /// Subscribes to Supabase realtime channels for instant cross-device
  /// sync. PRO only — enables Telegram-logged data to appear in the
  /// app immediately without waiting for the 24h batch pull.
  Future<void> subscribeToRealtimeSync() async {
    if (_realtimeSubscription != null) return; // Already subscribed

    final userId = _supabase.currentUser?.id;
    if (userId == null) return;

    // Test #12.6 — refresh JWT before opening the realtime channel.
    // Realtime subscribes carry the access token in the WebSocket
    // upgrade; if the token expired while the app was backgrounded
    // we get `RealtimeSubscribeException: Token has expired N seconds
    // ago` on the first message and the stream errors permanently.
    // refreshSession is idempotent and cheap when token is fresh.
    try {
      await _supabase.client.auth.refreshSession();
    } catch (e, st) {
      debugPrint('[realtime] refreshSession failed before subscribe: $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_subscribe_to_realtime_sync'));
      // Non-fatal — subscription may still succeed if token is valid.
    }

    _attachRealtimeStream(userId, attempt: 1);
  }

  /// Internal: opens the weight_logs stream. On token-expired errors
  /// from the channel, refreshes JWT and re-subscribes once.
  void _attachRealtimeStream(String userId, {required int attempt}) {
    _realtimeSubscription = _supabase.client
        .from('weight_logs')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen(
          (rows) async {
            try {
              for (final row in rows) {
                final date = row['date'] as String? ?? '';
                final key = 'weight_$date';
                if (_hive.healthBox.get(key) == null) {
                  await _hive.healthBox.put(key, {
                    'type': 'weight_log',
                    'date': date,
                    'weight_kg': row['weight_kg'],
                    'created_at': row['created_at'],
                    'source': 'realtime',
                  });
                }
              }
            } catch (e, st) {
              debugPrint('[realtime] weight_logs handler failed: $e\n$st');
              try {
                await _reportSyncFailure(
                  opType: 'realtime_handler_weight_logs',
                  error: e,
                );
              } catch (_) {
                // ignore: avoid_catches_without_on_clauses
              }
              // do NOT rethrow — keep stream alive
            }
          },
          onError: (e, st) {
            debugPrint('[realtime] weight_logs stream error: $e\n$st');
            // ignore: discarded_futures
            _reportSyncFailure(opType: 'realtime_stream_weight_logs', error: e)
                .catchError((_) {});

            // Test #12.6 — Token-expired reconnect (one-shot). If the
            // channel errored with "Token has expired", refresh the JWT
            // and re-subscribe once. Subsequent failures fall through
            // (no infinite retry loop).
            final msg = e.toString().toLowerCase();
            final isTokenExpired = msg.contains('token has expired') ||
                msg.contains('jwt expired') ||
                msg.contains('expired_token');
            // BUG-H (a7f2e9): also recover from a transient channelError
            // (RealtimeSubscribeException channelError / WS close 1002).
            // Pre-fix only token-expired reconnected, so a channelError left
            // the weight_logs stream permanently dead — it recurred 113x in
            // client_errors and PRO Telegram->app instant-sync silently never
            // delivered. Bounded (attempt < 2) so a persistent failure (RLS /
            // missing publication) still falls back to the batch pull, no loop.
            final isChannelError =
                msg.contains('channelerror') || msg.contains('channel_error');
            if ((isTokenExpired || isChannelError) && attempt < 2) {
              // ignore: discarded_futures
              _reconnectRealtimeWithRefreshedJwt(userId, attempt + 1);
            }
          },
        );
  }

  Future<void> _reconnectRealtimeWithRefreshedJwt(
    String userId,
    int attempt,
  ) async {
    try {
      await _realtimeSubscription?.cancel();
    } catch (_) {}
    _realtimeSubscription = null;
    try {
      await _supabase.client.auth.refreshSession();
    } catch (e, st) {
      debugPrint('[realtime] refreshSession on reconnect failed: $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_catch_4'));
      return; // can't recover without a fresh token
    }
    _attachRealtimeStream(userId, attempt: attempt);
  }

  /// Cancels realtime subscriptions (call on app background or logout).
  void unsubscribeRealtime() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
  }
}
