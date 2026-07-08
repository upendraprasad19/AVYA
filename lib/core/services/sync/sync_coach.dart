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

      // audit-2026-05-16 F3-1.1 — Hive `coaching_notes` <-> cloud `coach_notes`
      // name mismatch caused this column to be 100% NULL across all users (4/4).
      // Upward sync never projected it; AI memory was lost on every reinstall.
      // Hive key preserved as `coaching_notes` for back-compat with consumers
      // (`coachBox.get('coaching_notes')`); the cloud column is `coach_notes`.
      final notes = coach.get('coaching_notes');
      if (notes != null) payload['coach_notes'] = notes;

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
      // Unit 1 (coach-completion-tap-card) — kind-tagged LOCAL-ONLY action
      // rows (the 'completion_prompt' card) are NOT ai_coach_interactions and
      // must NEVER be pushed to the cloud table — they carry no
      // user_message / ai_response and would corrupt interaction analytics.
      // (They're already keyed `completion_prompt_<date>`, not `coach_*`, so
      // the prefix guard above skips them; this is the belt-and-braces
      // semantic guard in case a future writer changes the key shape.)
      if (entry['kind'] != null) continue;

      try {
        final rawId = entry['id'];
        // Audit 2026-05-12 P2-B — server already wrote the authoritative
        // row when id is a real UUID (ai-proxy emits one on every turn).
        // Skip the duplicate 'in_app' write.
        if (rawId is String && SyncService._looksLikeUuid(rawId)) {
          continue;
        }

        // audit-2026-05-16 F6-4 — cross-channel dedup. Pre-fix the orphan
        // path silently produced paired duplicate rows whenever a user
        // pasted the same meal text into both the AI Coach chat (Hive
        // `coach_<ms>` entry → orphan upsert) and the Nutrition AI Text
        // tab (server-side `food_text_analysis` placeholder insert from
        // ai-proxy) within 60-90 seconds of each other. The server-side
        // 60s dedup gate at ai-proxy/index.ts:222-254 only catches
        // intra-channel duplicates — it can't see the client orphan path.
        //
        // Live audit found 8 such cross-channel pairs spanning
        // 2026-05-11 → 2026-05-15 (every one was a meal-log text the
        // founder typed twice during testing). Class fix: before the
        // orphan upsert, SELECT for ANY existing row from this user with
        // the same user_message within the last 5 minutes. If hit, skip
        // the orphan write — the server-side row IS the source of truth
        // for that turn regardless of channel.
        final userMsg = (entry['user_message'] as String? ?? '').trim();
        if (userMsg.isNotEmpty) {
          final cutoff =
              DateTime.now().toUtc().subtract(const Duration(minutes: 5));
          final existing = await _supabase.client
              .from('ai_coach_interactions')
              .select('id, channel, created_at')
              .eq('user_id', userId)
              .eq('user_message', userMsg.substring(
                  0, userMsg.length > 500 ? 500 : userMsg.length))
              .gte('created_at', cutoff.toIso8601String())
              .limit(1)
              .maybeSingle();
          if (existing != null) {
            // Server already has a row for this turn (any channel) — drop
            // the orphan write. Stamp the Hive entry with the cloud id
            // so future cold restores collapse cleanly on the
            // `coach_<ts>` derivation path in _restoreCoachInteractions.
            final cloudId = existing['id'] as String?;
            if (cloudId != null && cloudId.isNotEmpty) {
              final updated = Map<String, dynamic>.from(entry);
              updated['id'] = cloudId;
              await coachBox.put(key, updated);
            }
            continue;
          }
        }

        // True local-only entry (no server-side match within 5 min).
        // Persist with a deterministic v5 UUID under the orphan channel
        // so server-side analytics can isolate this fallback path if it
        // becomes surprisingly hot.
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
  /// [preFetched] (C3 single-call): injected `ai_coach_interactions` rows;
  /// legacy callers omit it → network read. Plan §4.
  Future<void> _restoreCoachInteractions(String userId, String since,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('ai_coach_interactions')
              .select()
              .eq('user_id', userId)
              .gte('created_at', since)
              .order('created_at')
              .limit(1000)
          : (preFetched as List? ?? const []);

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
          // Preserve the cloud channel so recentHistoryExchanges can exclude
          // restored NON-CHAT interactions (food_text_analysis / scan_meal /
          // cart_auditor / …) from the replayed coach history (Hermes P2).
          'channel': map['channel'],
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
  /// [preFetched] (C3 single-call): injected `coach_memory` object|null;
  /// legacy callers omit it → network `maybeSingle` read. An injected `null`
  /// (un-inducted user — a legitimately-empty row) is honored exactly like the
  /// network null. Plan §4.
  Future<void> _restoreCoachMemory(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final Object? rawRow = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('coach_memory')
              .select(
                'committed_at, committed_to_lt_cdr, induction_completed_at, '
                'why_now, definition_of_winning, known_injuries, '
                'typical_wake_time, preferred_workout_time, body_part_priorities, '
                'coach_notes',
              )
              .eq('user_id', userId)
              .maybeSingle()
          : preFetched;
      if (rawRow == null) return;
      // Both the maybeSingle result and an injected bundle value are JSON
      // objects; normalize to a typed map so the apply loop below is unchanged.
      final Map row = rawRow as Map;

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

  // ── SyncDomain public forwarders for coach helpers (A6 migration) ──

  static const String _kSyncDomainRestoreSinceCoach = '2020-01-01T00:00:00Z';

  Future<void> pushCoachInteractionsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncCoachInteractions(userId);
  }

  Future<void> restoreCoachInteractionsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreCoachInteractions(userId, since ?? _kSyncDomainRestoreSinceCoach);
  }

  Future<void> pushCoachMemoryForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await syncCoachMemoryNow(userId);
  }

  Future<void> restoreCoachMemoryForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreCoachMemory(userId);
  }
}
