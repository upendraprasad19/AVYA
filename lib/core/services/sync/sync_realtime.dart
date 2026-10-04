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
  ///
  /// e4a7c9 — THE ENTITLEMENT CHECK LIVES HERE, ON THE SINK, and must stay
  /// here. It used to live on the callers, and `sync_service.dart:789` had it
  /// while `day_rollover_service.dart:65` did not — under a comment claiming
  /// it did. Since resume fires on every foreground, every user (free or PRO)
  /// attached a WAL poller: `realtime.list_changes()` was 35.4% of all
  /// database CPU over the project's first 143 days, serving a PRO feature
  /// with a PRO population of ~zero. Guarding one entry while another bypasses
  /// it is bug-class 2.25; a sink guard cannot be bypassed by a call site
  /// nobody has written yet.
  ///
  /// `proStateSnapshot()` NOT `isPro()`: isPro() is the DECISION path and can
  /// reach `_downgradeLocally()` — five Hive writes plus an `onStateChanged`
  /// → `ref.invalidate` cascade. Deciding whether to open a socket must not
  /// mutate entitlement state (OI-44 Unit 6, diagnose a9c4e1).
  ///
  /// The gate is only half the contract: the re-entrancy return below means an
  /// ALREADY-ATTACHED channel never re-enters it, so the downgrade teardown in
  /// `SubscriptionService._downgradeLocally` is the other half. Without it a
  /// lapsed PRO user keeps a live PRO channel until background or dispose.
  Future<void> subscribeToRealtimeSync() async {
    if (_realtimeSubscription != null) return; // Already subscribed

    // e4a7c9 — entitlement gate; rationale in the doc comment above.
    //
    // Deliberately BEFORE the currentUser read: entitlement is a purely local
    // Hive decision, so a free user is turned away without touching Supabase
    // at all. That is both cheaper and what makes this branch reachable from a
    // pure-VM behavioral test (Supabase cannot be initialised there, so a gate
    // placed after the session read could only ever be source-grepped).
    if (!_realtimeProGateDisabled &&
        !SubscriptionService.instance.proStateSnapshot()) {
      if (!_realtimeSkipLogged) {
        _realtimeSkipLogged = true;
        unawaited(
            ErrorTelemetry.logEvent('realtime_subscribe_skipped_free_tier'));
      }
      return;
    }

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
            } else if (isTokenExpired || isChannelError) {
              // Obs#8 (a3d7e2): reconnect budget exhausted — a PERSISTENT
              // failure (most often a backgrounded web tab whose WS can't
              // re-authorize; cloud publication + RLS are live-verified correct).
              // Tear the channel DOWN so the Supabase realtime client stops
              // auto-reconnecting the WS and spamming channelError into the
              // console + client_errors. Pre-fix the dead channel stayed
              // attached and the error RECURRED (the founder's report); the 24h
              // batch pull is the fallback.
              debugPrint('[realtime] weight_logs reconnect budget exhausted — '
                  'tearing down channel; batch pull is the fallback.');
              unsubscribeRealtime();
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

  /// Cancels realtime subscriptions (call on app background, logout, account
  /// swap, or entitlement downgrade).
  ///
  /// e4a7c9 — the SINGLE teardown site. `_onUserChanged` used to inline an
  /// equivalent cancel, so anything added here silently skipped that path.
  /// The try/catch came from that inlined copy and is kept: a subscription
  /// already cancelled by the reconnect-budget path can throw, and teardown
  /// must never be the thing that fails a sign-out or a downgrade.
  ///
  /// Does NOT reset `_realtimeSkipLogged`. The first version of this fix did,
  /// and the B-pass caught it as a P0: `day_rollover_service.dart` calls this
  /// on EVERY `AppLifecycleState.paused`, so re-arming the latch here meant a
  /// free user re-fired the skip event — an Edge Function call plus a
  /// `client_errors` row — on every single background/foreground cycle. That is
  /// bug-class 2.13, the exact flood the latch exists to prevent, reintroduced
  /// by the anti-flood mechanism itself.
  ///
  /// The latch means "I have already reported that THIS user is unentitled", so
  /// the only thing that should clear it is the user CHANGING — which is
  /// `_onUserChanged`, and nowhere else. A downgrade needs no reset either: a
  /// PRO user's latch is false already (the gate never blocked them), so their
  /// first post-lapse attempt logs once on its own.
  void unsubscribeRealtime() {
    try {
      _realtimeSubscription?.cancel();
    } catch (_) {
      // Subscription may already be cancelled; ignore.
    }
    _realtimeSubscription = null;
  }
}
