import 'dart:async';

import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Thin analytics helper — fire-and-forget inserts into
/// `ai_coach_interactions` with `channel='app_event'`.
///
/// Reusing the existing interactions table (vs. adding a new
/// `app_events` table) because:
///   - No schema migration required.
///   - Existing indexes on (user_id, channel, created_at) work.
///   - The same log-client-error + retry infrastructure applies.
///   - Post-beta, if volume grows we can split out into its own table.
///
/// Usage:
///   AppEventsService.instance.log('phase_1_day_29_upgrade_tapped');
///   AppEventsService.instance.log('phase_1_day_29_redo_week_4_tapped',
///     metadata: {'week': 4});
///
/// Never blocks the caller. Never throws. A failed insert is dropped.
class AppEventsService {
  AppEventsService._();
  static final AppEventsService instance = AppEventsService._();

  static const String _channel = 'app_event';

  /// Fire-and-forget event log. Safe from any screen / any state.
  void log(String event, {Map<String, dynamic>? metadata}) {
    unawaited(_logAsync(event, metadata));
  }

  Future<void> _logAsync(String event, Map<String, dynamic>? metadata) async {
    try {
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return; // not logged in — no event emitted
      final payload = <String, dynamic>{
        'event': event,
        if (metadata != null) ...metadata,
      };
      await SupabaseService.instance.client
          .from('ai_coach_interactions')
          .insert({
        'user_id': userId,
        'channel': _channel,
        // user_message carries the serialized event + metadata. Keep
        // short to avoid blowing up the column (~500 chars is plenty).
        'user_message': payload.toString().substring(
              0,
              payload.toString().length > 500 ? 500 : payload.toString().length,
            ),
        'ai_response': '',
        'model_used': 'n/a',
        'tokens_used': 0,
      });
    } catch (e) {
      // Silent — analytics must not impact UX.
      debugPrint('[AppEventsService.log] $event: $e');
    }
  }
}
