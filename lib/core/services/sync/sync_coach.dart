part of '../sync_service.dart';

/// Mirrors the two hardcoded, non-model apology strings exported from
/// `supabase/functions/_shared/tool-loop.ts`
/// (`HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED` /
/// `HARD_FAILURE_APOLOGY_ROUNDS_EXHAUSTED`). `ai-proxy`'s reservation-resolve
/// UPDATE persists `ai_response` to the cloud `ai_coach_interactions` row
/// UNCONDITIONALLY — there is no cloud column carrying `hadHardFailure` — so
/// a cold restore of this exact row on another device has no flag to read
/// (plan-review round 1 finding, APK +43 obs 2, diagnose a1c6b9).
/// `_restoreCoachInteractions` below recognizes a restored hard-failure turn
/// by its exact text instead. Parity with the server strings is pinned by
/// test/contracts/hard_failure_apology_texts_parity_test.dart.
const Set<String> kKnownHardFailureApologyTexts = {
  'I had trouble reaching the model. Try again in a moment.',
  "Recruit — I had trouble pinning that down. Try asking again with a bit "
      "more specificity. If you want today's workout or your current plan, "
      "ask plainly: \"what's my workout today\" or \"what's my plan\" — I'll "
      "read the manifest directly.",
};

/// True when [aiResponse] is (trimmed) byte-identical to one of the known
/// hard-failure apology texts above. Pure — no Hive/network reads — so it is
/// directly mutation-testable; the only I/O-touching call site
/// (`_restoreCoachInteractions`) is pinned structurally instead, mirroring
/// the existing `restore_keys_deterministic_test.dart` source-grep pattern.
bool isKnownHardFailureApologyText(String? aiResponse) {
  return kKnownHardFailureApologyTexts.contains((aiResponse ?? '').trim());
}

/// Mirrors `supabase/functions/ai-proxy/index.ts`'s
/// `MODEL_USED_LOOP_THREW_SENTINEL` — set when `runToolLoop` itself THROWS
/// (a genuine crash calling the tool loop), a THIRD, structurally distinct
/// failure-text case from the two apology texts above: that catch block
/// never runs the normal reservation-resolve path at all, so `ai_response`
/// is a different literal ("[failed] runToolLoop threw") not in
/// [kKnownHardFailureApologyTexts]. Plan-review round 2 finding, same
/// diagnose (a1c6b9) — the original restore-path defense covered only the
/// known-apology-TEXT case and missed this one.
const String kModelUsedLoopThrewSentinel = 'failed';

/// True when a restored row (identified by [aiResponse] and [modelUsed])
/// should be excluded from history replay: either it matches a known
/// apology text, OR its `model_used` carries the loop-threw sentinel. Both
/// signals are pure/text-based because the cloud table carries no
/// `hadHardFailure` column for either failure shape.
bool isRestoredHardFailureRow({
  required String? aiResponse,
  required String? modelUsed,
}) {
  return isKnownHardFailureApologyText(aiResponse) ||
      modelUsed == kModelUsedLoopThrewSentinel;
}

/// True when a cloud `ai_coach_interactions.user_message` is a media/photo
/// turn's placeholder text — `ai-media-proxy/index.ts` writes
/// `'[Photo: ${media_type}] ...'` for every image/video-analysis insert
/// (paywall-exhausted, video-paywall, AND the successful PRO analysis, whose
/// `channel` is `'app'` — indistinguishable by channel from a normal chat
/// turn). The client's own local write is `'[Photo] ...'`
/// (`ai_coach_provider.dart:654`, never itself pushed — the server row above
/// is always the sync source of truth). OI-245: the cloud table carries NO
/// `mode` column (same gap [isRestoredHardFailureRow] documents for the
/// hard-failure case), so `_restoreCoachInteractions` used to hardcode every
/// restored row's `mode` to `'quick'` — a restored photo turn then passed
/// `CoachInteractionRepository.recentHistoryExchanges`'s `mode == 'media'`
/// exclusion and was replayed into Gemini context as plain text. This text
/// match lets restore recover the real mode. Pure — mutation-testable.
bool isRestoredMediaRow(String? userMessage) {
  final m = userMessage ?? '';
  return m.startsWith('[Photo') || m.startsWith('[Video');
}

/// Derives an ISO-8601 UTC timestamp from a `coach_<ms>` Hive key (spec
/// §5.12 fallback order: recorded value -> derive from a *_ms sibling or the
/// Hive key -> omit). `coach_interaction_repository.dart:70-77` mints every
/// key as `coach_<millisecondsSinceEpoch>`, so the key itself IS the
/// creation timestamp for a locally-written row. Returns null when the key
/// carries no parseable millisecond suffix, so the caller OMITS the field
/// rather than sending "now" — matching the existing "absence beats null on
/// the wire" convention (sync_workout.dart:613-614).
String? _coachCreatedAtFromKey(String key) {
  if (!key.startsWith('coach_')) return null;
  final ms = int.tryParse(key.substring('coach_'.length));
  if (ms == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
      .toIso8601String();
}

// ── OI-503: one coach turn = one local row (the shared turn key) ─────────
//
// Plan docs/plans/2026-11-13-coach-chat-time-dup.md section 4 (C4, C5),
// migration 178, diagnose d4a7c9. The phone sends its Hive key of a turn
// (`coach_<ms>`) as `client_key`; ai-proxy / ai-media-proxy store it on the
// cloud row. The restore writes that row back AT the key, so the sending
// phone's row and the cloud row are one row, and another device gets the same
// key. Pure rules here; the I/O is in [SyncServiceCoach].

/// configBox kill switch: `true` restores coach rows with the pre-OI-503 loop
/// (kept verbatim). It gates the RESTORE only; key emission and the push's key
/// lookup stay on (both harmless: a key nobody reads changes nothing, and the
/// lookup falls back on a throw).
const String kDisableCoachClientKeyRestore = 'disable_coach_client_key_restore';

/// A coach chat row key. Only keys of this shape are ever targeted, deleted or
/// compared by the restore: `coach_memory` and other singletons share the box.
final RegExp kCoachRowKeyPattern = RegExp(r'^coach_[0-9]+$');

/// The key shape the server's CHECK (`ai_coach_interactions_client_key_format`)
/// and `_shared/client_key.ts` accept. A `coach_<hex>` key (a restored row with
/// an unparseable `created_at`) is never sent: the CHECK would refuse the upsert
/// on every pass.
final RegExp kCoachClientKeyPattern = RegExp(r'^coach_[0-9]{10,16}$');

final RegExp _coachMediaTag = RegExp(r'^\[(?:Photo(?::[^\]]*)?|Video)\]\s*');

/// The turn's text with the media tag removed, so the phone's `[Photo] cap`
/// and the server's `[Photo: image] cap` / `[Video] cap` compare equal.
String coachTurnText(String? userMessage) =>
    (userMessage ?? '').trim().replaceFirst(_coachMediaTag, '').trim();

/// A cloud row that carries a real reply: non-empty, not the `pending`
/// reservation, not a hard failure (an apology text or the loop-threw marker).
bool isCompleteCloudCoachRow(Map row) {
  final reply = (row['ai_response'] as String? ?? '').trim();
  final model = row['model_used'] as String?;
  return reply.isNotEmpty &&
      model != 'pending' &&
      !isRestoredHardFailureRow(
        aiResponse: row['ai_response'] as String?,
        modelUsed: model,
      );
}

/// A local row still waiting for (or missing) its reply.
bool isIncompleteLocalCoachRow(Map local) =>
    local['failed'] == true ||
    local['pending'] == true ||
    (local['ai_response'] as String? ?? '').trim().isEmpty;

DateTime? _coachRowInstant(Map row, [String? key]) {
  final parsed = DateTime.tryParse(row['created_at'] as String? ?? '');
  if (parsed != null) return parsed;
  if (key == null) return null;
  final ms = int.tryParse(key.startsWith('coach_') ? key.substring(6) : '');
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// One cloud row per key: a complete row over an incomplete one, then the
/// latest `created_at`; on a tie the later row in [rows] (the fetch order).
Map<String, dynamic> pickKeyedCloudCoachRow(List<Map<String, dynamic>> rows) {
  var best = rows.first;
  for (final r in rows.skip(1)) {
    final rc = isCompleteCloudCoachRow(r), bc = isCompleteCloudCoachRow(best);
    if (rc != bc) {
      if (rc) best = r;
      continue;
    }
    final ri = _coachRowInstant(r), bi = _coachRowInstant(best);
    if (bi == null || (ri != null && !ri.isBefore(bi))) best = r;
  }
  return best;
}

/// Round 4 F1: a `failed` local row the user has already re-sent: a newer local
/// row with the same turn text, not failed, within 60 s after it. Filling the
/// failed row from the cloud would show that exchange twice.
bool isResentFailedCoachRow(Map<dynamic, dynamic> box, String key, Map local) {
  if (local['failed'] != true) return false;
  final at = _coachRowInstant(local, key);
  if (at == null) return false;
  final text = coachTurnText(local['user_message'] as String?);
  for (final k in box.keys) {
    if (k is! String || k == key || !kCoachRowKeyPattern.hasMatch(k)) continue;
    final other = box[k];
    if (other is! Map || other['failed'] == true) continue;
    if (coachTurnText(other['user_message'] as String?) != text) continue;
    final oat = _coachRowInstant(other, k);
    if (oat == null) continue;
    final d = oat.difference(at);
    if (d > Duration.zero && d <= const Duration(seconds: 60)) return true;
  }
  return false;
}

/// The local row a cloud row restores to (the same fields the pre-OI-503
/// loop writes), with `id` = the cloud uuid.
Map<String, dynamic> coachRowFromCloud(Map<String, dynamic> map) => {
      'id': map['id'],
      'user_message': map['user_message'] ?? '',
      'ai_response': map['ai_response'] ?? '',
      'model_used': map['model_used'] ?? 'unknown',
      'mode': isRestoredMediaRow(map['user_message'] as String?)
          ? 'media'
          : 'quick',
      'is_user_message': true,
      'created_at': map['created_at'],
      'channel': map['channel'],
      'source': 'cloud_restore',
      'had_hard_failure': isRestoredHardFailureRow(
        aiResponse: map['ai_response'] as String?,
        modelUsed: map['model_used'] as String?,
      ),
    };

/// The unkeyed restore key of a cloud row (the pre-OI-503 derivation).
String coachUnkeyedRestoreKey(Map<String, dynamic> map) {
  final ts = DateTime.tryParse(map['created_at'] as String? ?? '')
          ?.millisecondsSinceEpoch ??
      0;
  final id = map['id'] as String? ?? '';
  return ts > 0
      ? 'coach_$ts'
      : 'coach_${id.hashCode.toUnsigned(32).toRadixString(16)}';
}

/// Sync + restore for AI coach surfaces: coach_memory (induction state +
/// coach_notes) and ai_coach_interactions (chat history). See CLAUDE.md
/// §11 for the AI architecture context.
extension SyncServiceCoach on SyncService {
  /// Upserts coach_memory induction columns to Supabase.
  /// Only non-null Hive fields are included — preserves partial induction
  /// state without overwriting cloud columns with null when the user hasn't
  /// yet completed the muster. Uses migration 042 columns.
  /// Fire-and-forget per docs/architecture/sync.md.
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
          reason: 'sync_service_put_if_present', skipServerPost: true));
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
      // OI-503 (round 5 P2-a): a row restored from the cloud is already there.
      // Pushing it once it is older than the 5-minute text window created the
      // `in_app_orphan` echoes; with a key it would create KEYED echoes.
      if (entry['source'] == 'cloud_restore') continue;
      // OI-503 (round 3 F8): a live send's server row may not exist yet.
      if (CoachInteractionRepository.isInFlight(key)) continue;

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
        // OI-503 (C4): the server row of this turn carries the phone's key.
        // Look it up FIRST; no hit falls through to the text lookup below
        // (older rows carry no key). A throw (a database without the column)
        // also falls through, and the orphan then goes up without the key.
        final sendKey = kCoachClientKeyPattern.hasMatch(key);
        var keyLookupFailed = false;
        if (sendKey) {
          try {
            final keyed = await _supabase.client
                .from('ai_coach_interactions')
                .select('id')
                .eq('user_id', userId)
                .eq('client_key', key)
                .limit(1)
                .maybeSingle();
            final keyedId = keyed?['id'] as String?;
            if (keyedId != null && keyedId.isNotEmpty) {
              await _stampCoachCloudId(key, keyedId);
              continue;
            }
          } catch (e, st) {
            keyLookupFailed = true;
            debugPrint('[SyncService._syncCoachInteractions] key lookup: $e');
            // Local telemetry only: a database without the column would fail
            // this lookup for every row on every pass.
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'coach_client_key_lookup_failed', skipServerPost: true));
          }
        }

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
              await _stampCoachCloudId(key, cloudId);
            }
            continue;
          }
        }

        // True local-only entry (no server-side match within 5 min).
        // Persist with a deterministic v5 UUID under the orphan channel
        // so server-side analytics can isolate this fallback path if it
        // becomes surprisingly hot.
        final cloudId = SyncService._deterministicId('coach|$userId|$key');
        final createdAt =
            entry['created_at'] as String? ?? _coachCreatedAtFromKey(key);
        final payload = <String, dynamic>{
          'id': cloudId,
          'user_id': userId,
          'channel': 'in_app_orphan',
          'user_message': entry['user_message'] ?? '',
          'ai_response': entry['ai_response'] ?? '',
          'model_used': entry['model_used'] ?? 'unknown',
          // Merge note (origin/main a2b, 2026-09-28): main changed the old
          // `now()` fallback here to UTC; this branch removed the `now()`
          // fallback entirely (G2 gate) and derives the time from the Hive key
          // as UTC (`_coachCreatedAtFromKey`), which already covers it.
          if (createdAt != null) 'created_at': createdAt,
          // OI-503: keyed, so a later restore writes it back at this key.
          if (sendKey && !keyLookupFailed) 'client_key': key,
        };
        await _supabase.client
            .from('ai_coach_interactions')
            .upsert(payload, onConflict: 'id');
        // OI-204 write-amplification fix (day-swapper + sync-load Task 19):
        // stamp the cloud id back into the Hive row, exactly like the
        // dedup-hit branch above (:186-191). Without this, `entry['id']`
        // never becomes a real UUID, so the rawId guard at :148-150 never
        // catches the row and it re-upserts on every single sync pass.
        await _stampCoachCloudId(key, cloudId);
      } catch (e, st) {
        debugPrint('[SyncService._syncCoachInteractions] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_27', skipServerPost: true));
        try {
          await _reportSyncFailure(opType: 'upsert_coach_interaction', error: e);
        } catch (_) {}
      }
    }
  }

  /// OI-503 (round 3 F8): writes ONLY `id` onto a FRESH read of the row, with
  /// no await between the read and the put. The push used to write back the
  /// copy it took before its network awaits, which could undo a restore's
  /// fill or re-create a row deleted meanwhile (a null fresh read: no put).
  Future<void> _stampCoachCloudId(String key, String cloudId) async {
    final fresh = _hive.coachBox.get(key);
    if (fresh is! Map || fresh['id'] == cloudId) return;
    await _hive.coachBox.put(key, Map<String, dynamic>.from(fresh)..['id'] = cloudId);
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

      // OI-503: the keyed restore, unless the kill switch is set (then the
      // pre-OI-503 loop below runs unchanged).
      if (_hive.configBox.get(kDisableCoachClientKeyRestore) != true) {
        await _applyKeyedCoachRows(userId, rows);
        return;
      }

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
          // OI-245 — was hardcoded 'quick', which made a restored photo turn
          // replay into Gemini context as plain text (see
          // [isRestoredMediaRow] doc above).
          'mode': isRestoredMediaRow(map['user_message'] as String?)
              ? 'media'
              : 'quick',
          'is_user_message': true,
          'created_at': map['created_at'],
          // Preserve the cloud channel so recentHistoryExchanges can exclude
          // restored NON-CHAT interactions (food_text_analysis / scan_meal /
          // cart_auditor / …) from the replayed coach history (Hermes P2).
          'channel': map['channel'],
          'source': 'cloud_restore',
          // Plan-review round 1 finding (APK +43 obs 2, diagnose a1c6b9):
          // the cloud row carries no `hadHardFailure` column, so a restored
          // hard-failure turn is recognized by its exact text/sentinel
          // instead (round 2 widened this to a THIRD failure shape — the
          // runToolLoop-threw case, recognized via model_used rather than
          // apology text). Deliberately a SEPARATE field from `failed` —
          // `failed` also drives ChatHistoryNotifier.build's
          // error-bubble+Retry UI, which a hard-failure turn must NOT
          // trigger on restore any more than it does on the live path.
          // recentHistoryExchanges excludes on EITHER field.
          'had_hard_failure': isRestoredHardFailureRow(
            aiResponse: map['ai_response'] as String?,
            modelUsed: map['model_used'] as String?,
          ),
        });
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreCoachInteractions] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_28', skipServerPost: true));
      try {
        await _reportSyncFailure(opType: 'restore_coach_interactions', error: e);
      } catch (_) {}
    }
  }

  /// OI-503 (plan section 4, C5): one turn, one local row.
  ///
  /// Cloud rows WITH a valid `client_key` are grouped by it and each group
  /// restores to that key; rows without one keep the pre-OI-503 derivation
  /// (`coach_<server ms>`). Every write re-checks the account first, and each
  /// decision (in-flight check, read, decide, put) is one synchronous slice:
  /// no await between the read of the local row and the `put(` call.
  Future<void> _applyKeyedCoachRows(String userId, List rows) async {
    final box = _hive.coachBox;
    final keyed = <String, List<Map<String, dynamic>>>{};
    final unkeyed = <Map<String, dynamic>>[];
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      if ((map['id'] as String? ?? '').isEmpty) continue;
      final ck = map['client_key'];
      if (ck is String && kCoachClientKeyPattern.hasMatch(ck)) {
        (keyed[ck] ??= []).add(map);
      } else {
        unkeyed.add(map);
      }
    }
    // Round 3 F3: an unkeyed row with the same turn text and the same instant
    // as a keyed row is a legacy echo of that turn (a pre-OI-503 orphan push
    // of a restored copy); writing it would re-create the stale copy.
    final keyedFingerprints = <String>{
      for (final g in keyed.values)
        for (final m in g)
          '${coachTurnText(m['user_message'] as String?)}|'
              '${_coachRowInstant(m)?.millisecondsSinceEpoch}',
    };

    final occupiedKeys = <String>{};
    for (final entry in keyed.entries) {
      if (ownerChangedSince(userId)) return;
      final key = entry.key;
      final group = entry.value;
      final cloud = pickKeyedCloudCoachRow(group);
      final cloudId = cloud['id'] as String;
      // ── one synchronous slice: in-flight check, read, decide, put( ──
      final inFlight = CoachInteractionRepository.isInFlight(key);
      final local = box.get(key);
      Map<String, dynamic>? next;
      var occupied = false;
      if (local is! Map) {
        if (!inFlight) next = coachRowFromCloud(cloud);
      } else if (coachTurnText(local['user_message'] as String?) !=
          coachTurnText(cloud['user_message'] as String?)) {
        occupied = true; // round 3 F2: another turn holds this key
      } else {
        final updated = Map<String, dynamic>.from(local);
        var changed = false;
        final localId = local['id'];
        if (!(localId is String && SyncService._looksLikeUuid(localId))) {
          updated['id'] = cloudId;
          changed = true;
        }
        if (!inFlight &&
            isIncompleteLocalCoachRow(local) &&
            isCompleteCloudCoachRow(cloud) &&
            !isResentFailedCoachRow(box.toMap(), key, local)) {
          updated['ai_response'] = cloud['ai_response'] ?? '';
          updated['model_used'] = cloud['model_used'] ?? 'unknown';
          updated['had_hard_failure'] = isRestoredHardFailureRow(
            aiResponse: cloud['ai_response'] as String?,
            modelUsed: cloud['model_used'] as String?,
          );
          updated['pending'] = false;
          updated['failed'] = false;
          updated.remove('error_text');
          changed = true;
        }
        if (changed) next = updated;
      }
      if (next != null) await box.put(key, next);
      // ── end of the slice ──

      if (occupied) {
        occupiedKeys.add(key);
        // The cloud row goes down the unkeyed path at its own server key.
        for (final m in group) {
          unkeyed.add(m);
        }
        continue;
      }
      // A stale copy an earlier, pre-key build made of THESE cloud rows:
      // `source: cloud_restore` at `coach_<that row's ms>`, same text.
      for (final m in group) {
        final copyKey = coachUnkeyedRestoreKey(m);
        if (copyKey == key || !kCoachRowKeyPattern.hasMatch(copyKey)) continue;
        if (ownerChangedSince(userId)) return;
        final copy = box.get(copyKey);
        if (copy is Map &&
            copy['source'] == 'cloud_restore' &&
            copy['user_message'] == m['user_message'] &&
            !CoachInteractionRepository.isInFlight(copyKey)) {
          await box.delete(copyKey);
        }
      }
    }

    for (final map in unkeyed) {
      if (ownerChangedSince(userId)) return;
      if (map['client_key'] == null &&
          keyedFingerprints.contains('${coachTurnText(map['user_message'] as String?)}|'
              '${_coachRowInstant(map)?.millisecondsSinceEpoch}')) {
        continue;
      }
      final hiveKey = coachUnkeyedRestoreKey(map);
      // Never over the row that occupies a key, nor into a live send.
      if (occupiedKeys.contains(hiveKey)) continue;
      if (CoachInteractionRepository.isInFlight(hiveKey)) continue;
      await box.put(hiveKey, coachRowFromCloud(map));
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
          reason: 'sync_service_if_22', skipServerPost: true));
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

  /// OI-479 test seam — drives [_restoreCoachInteractions] with INJECTED
  /// `ai_coach_interactions` rows ([preFetched] is required, so this never
  /// reaches the network).
  @visibleForTesting
  Future<void> restoreCoachInteractionsForTest(String userId,
          {required Object? preFetched}) =>
      _restoreCoachInteractions(userId, '2020-01-01T00:00:00Z',
          preFetched: preFetched);
}
