part of '../sync_service.dart';

/// Sync + restore for AI coach surfaces: coach_memory (induction state +
/// coach_notes) and ai_coach_interactions (chat history). See CLAUDE.md
/// §11 for the AI architecture context.
extension SyncServiceCoach on SyncService {
  /// Upserts coach_memory induction columns to Supabase.
  /// Only non-null Hive fields are included — preserves partial induction
  /// state without overwriting cloud columns with null when the user hasn't
  /// yet completed the muster. Uses migration 042 columns.
  /// Fire-and-forget per CLAUDE.md §15.
  Future<void> syncCoachMemoryNow(String userId) async {
    try {
      final coach = _hive.coachBox;
      final payload = <String, dynamic>{
        'user_id': userId,
      };
      // Helper: only include when non-null — preserves partial induction state.
      void putIfPresent(String key) {
        final v = coach.get(key);
        if (v != null) payload[key] = v;
      }
      putIfPresent('committed_at');
      final ltcdr = coach.get('committed_to_lt_cdr');
      if (ltcdr is bool) payload['committed_to_lt_cdr'] = ltcdr;
      putIfPresent('induction_completed_at');
      putIfPresent('why_now');
      putIfPresent('definition_of_winning');
      putIfPresent('known_injuries');
      putIfPresent('typical_wake_time');
      putIfPresent('preferred_workout_time');
      putIfPresent('body_part_priorities');

      await _supabase.client
          .from('coach_memory')
          .upsert(payload, onConflict: 'user_id')
          .select()
          .single();
    } catch (e, st) {
      debugPrint('[SyncService.syncCoachMemoryNow] coach_memory upsert failed: $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_put_if_present'));
      unawaited(_reportSyncFailure(
        opType: 'upsert_coach_memory_induction',
        error: e,
      ));
    }
  }

  /// Pushes AI coach interactions to Supabase for analytics + history.
  ///
  /// Audit 2026-05-12 P2-B — pre-fix this was a hot double-write path. The
  /// `ai-proxy` Edge Function ALREADY writes an authoritative
  /// `ai_coach_interactions` row server-side at every chat turn (channel =
  /// 'app'). Then this method walked the Hive coachBox and re-upserted each
  /// entry with `channel: 'in_app'`, producing 81 phantom-duplicate rows
  /// vs. 22 legitimate 'app' rows in the live table (79% noise).
  /// Interaction-volume analytics were inflated 4× by this double-write.
  ///
  /// New behaviour: skip the upsert by default. The 'app' rows from
  /// ai-proxy ARE the source of truth. If `entry['id']` is non-null AND
  /// shaped like a UUID, the server already received this turn, so we have
  /// nothing to add. The pre-fix path only existed to catch "edge-case
  /// local-only entries" — those were always rare and the cost (4× row
  /// inflation) wasn't worth the catch.
  Future<void> _syncCoachInteractions(String userId) async {
    final coachBox = _hive.coachBox;
    for (final key in coachBox.keys) {
      if (key is! String || !key.startsWith('coach_')) continue;
      final raw = coachBox.get(key);
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);

      try {
        final rawId = entry['id'];
        // Audit 2026-05-12 P2-B — server already wrote the authoritative
        // row when id is a real UUID (ai-proxy emits one on every turn).
        // Skip the duplicate 'in_app' write.
        if (rawId is String && SyncService._looksLikeUuid(rawId)) {
          continue;
        }
        // Edge case: pre-server entry with no UUID. Persist with a
        // deterministic v5 UUID under a clearer channel so server-side
        // analytics can isolate this fallback path if it becomes
        // surprisingly hot.
        final cloudId = SyncService._deterministicId('coach|$userId|$key');
        await _supabase.client.from('ai_coach_interactions').upsert({
          'id': cloudId,
          'user_id': userId,
          'channel': 'in_app_orphan',
          'user_message': entry['user_message'] ?? '',
          'ai_response': entry['ai_response'] ?? '',
          'model_used': entry['model_used'] ?? 'unknown',
          'created_at': entry['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e, st) {
        debugPrint('[SyncService._syncCoachInteractions] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_27'));
        try {
          await _reportSyncFailure(opType: 'upsert_coach_interaction', error: e);
        } catch (_) {}
      }
    }
  }

  /// Restores AI coach interactions from Supabase (for chat history on new device).
  Future<void> _restoreCoachInteractions(String userId, String since) async {
    try {
      final rows = await _supabase.client
          .from('ai_coach_interactions')
          .select()
          .eq('user_id', userId)
          .gte('created_at', since)
          .order('created_at')
          .limit(1000);

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String? ?? '';
        if (id.isEmpty) continue;
        // APK Test #12.8 / Bug #1 — derive deterministic Hive key from
        // (user_id, created_at). Pre-fix `'coach_${id.hashCode}'` keyed
        // by the cloud UUID's hash, which never matches the local-write
        // key `coach_<created_at_ms>` produced by `ai_coach_repository`
        // — every cold restore appended a sibling row. The cloud
        // `created_at` ISO string is stable and globally unique per
        // user-message turn so it collapses cloud→local on round-trip.
        final createdAt = map['created_at'] as String? ?? '';
        final ts =
            DateTime.tryParse(createdAt)?.millisecondsSinceEpoch ?? 0;
        final hiveKey = ts > 0
            ? 'coach_$ts'
            : 'coach_${id.hashCode.toUnsigned(32).toRadixString(16)}';

        await _hive.coachBox.put(hiveKey, {
          'id': hiveKey,
          'user_message': map['user_message'] ?? '',
          'ai_response': map['ai_response'] ?? '',
          'model_used': map['model_used'] ?? 'unknown',
          'mode': 'quick',
          'is_user_message': true,
          'created_at': map['created_at'],
          'source': 'cloud_restore',
        });
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreCoachInteractions] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_28'));
      try {
        await _reportSyncFailure(opType: 'restore_coach_interactions', error: e);
      } catch (_) {}
    }
  }

  /// Pulls coach_memory induction state from Supabase into local coachBox.
  ///
  /// Run on restoreFromCloud so returning users (new device or post-logout)
  /// skip the InductionScreen — the cloud row already has [induction_completed_at]
  /// and all muster answers. If the user has no coach_memory row yet (un-inducted),
  /// maybeSingle() returns null and we skip silently.
  Future<void> _restoreCoachMemory(String userId) async {
    try {
      final row = await _supabase.client
          .from('coach_memory')
          .select(
            'committed_at, committed_to_lt_cdr, induction_completed_at, '
            'why_now, definition_of_winning, known_injuries, '
            'typical_wake_time, preferred_workout_time, body_part_priorities, '
            'coach_notes',
          )
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return;

      final coach = _hive.coachBox;
      const keys = [
        'committed_at',
        'committed_to_lt_cdr',
        'induction_completed_at',
        'why_now',
        'definition_of_winning',
        'known_injuries',
        'typical_wake_time',
        'preferred_workout_time',
        'body_part_priorities',
      ];
      for (final key in keys) {
        final v = row[key];
        if (v != null) await coach.put(key, v);
      }

      // A6 — coach_notes: restore AI coach memory so it's available
      // between reinstall and the next 11 PM IST extraction run.
      // Cloud column is `coach_notes` (singular table, see migration set);
      // Hive field-name contract preserves `coaching_notes` so consumers
      // (`coachBox.get('coaching_notes')`) keep working unchanged.
      final notes = row['coach_notes'];
      if (notes != null) {
        await coach.put('coaching_notes', notes);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreCoachMemory] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_22'));
      unawaited(_reportSyncFailure(
        opType: 'restore_coach_memory',
        error: e,
      ));
    }
  }
}
