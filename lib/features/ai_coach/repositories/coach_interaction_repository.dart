// Tech-debt audit 2026-05-20 finding A10 — CoachInteractionRepository
// extracted from AiCoachRepository.
//
// Owns the durable chat-interaction surface in coachBox: persistence of
// pending user messages, in-place update on AI reply success, in-place
// update on failure, 60-second client-side dedup window, day-bounded
// counters, and the "latest insight" projection used by the home insight
// card.
//
// Why split out: this is the canonical write path for coach_<ms> rows
// (per docs/sot_registry.yaml `coach_interactions`). Mixing it with the
// AI snapshot read surface in one 2127-line class made every writer
// change a bigger blast radius than it needed to be.
//
// Hive contract: every read/write routes through HiveService.instance
// (rule #4 — Hive-first). Identity-signal detection is delegated to
// CoachMemoryService so this file only owns interaction persistence.

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import '../services/coach_memory_service.dart';

/// Canonical persistence layer for AI Coach chat interactions.
///
/// Hive keys: `coach_<DateTime.now().millisecondsSinceEpoch>` in coachBox.
/// Singleton sibling keys (`coaching_notes`, `coach_memory`, `fitness_summary`,
/// etc.) live in coachBox too but are owned by CoachMemoryService /
/// AiSnapshotBuilder.
class CoachInteractionRepository {
  CoachInteractionRepository._();
  static final CoachInteractionRepository _instance =
      CoachInteractionRepository._();
  static CoachInteractionRepository get instance => _instance;

  final HiveService _hive = HiveService.instance;

  /// Saves an AI interaction to coachBox.
  Future<String> saveInteraction({
    required String userMessage,
    required String aiResponse,
    required String modelUsed,
    required String mode,
  }) async {
    final id = mintCoachKey();
    await _hive.coachBox.put(id, {
      'id': id,
      'user_message': userMessage,
      'ai_response': aiResponse,
      'model_used': modelUsed,
      'mode': mode,
      'is_user_message': true,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  /// 60-second client-side dedup window for [saveUserMessagePending].
  /// APK Test #16.1 / Agent B (closes-diagnose: a17bc3).
  /// Exposed for tests so the window can be exercised deterministically.
  @visibleForTesting
  static const Duration coachWriterDedupWindow = Duration(seconds: 60);

  // Monotonic coach-key minter. Two interactions saved within the same
  // millisecond otherwise both mint `coach_<ms>` and the second Hive.put
  // overwrites the first (silent data loss). Surfaced as a same-ms key
  // collision in coach_writer_dedup_test (CI flake) and a real rapid-write
  // loss path. Bumping to last+1 keeps the key numeric, ordered, and unique.
  // closes-diagnose: c3f9a1.
  static int _lastMintedKeyMs = 0;
  @visibleForTesting
  static String mintCoachKey() {
    var ms = DateTime.now().millisecondsSinceEpoch;
    if (ms <= _lastMintedKeyMs) ms = _lastMintedKeyMs + 1;
    _lastMintedKeyMs = ms;
    return 'coach_$ms';
  }

  /// Bug #19 — Persists the user message immediately, BEFORE the AI call.
  /// Marks the entry as `pending: true` so [ChatHistoryNotifier] can render
  /// it as a loading bubble even if the app is killed mid-call. Returns the
  /// Hive key so the caller can update it on success/failure.
  ///
  /// APK Test #16.1 / Agent B (closes-diagnose: a17bc3) — added a 60s
  /// dedup window. If a recent NON-FAILED `coach_*` entry exists with the
  /// same `user_message` AND `mode` AND `media_url` within the last 60
  /// seconds, returns the existing key instead of minting a new one.
  Future<String> saveUserMessagePending({
    required String userMessage,
    required String mode,
    String? mediaUrl,
    String? mediaType,
  }) async {
    // Run cheap on-device identity heuristics on every outbound user message.
    // Patches Hive coach_memory in place; no-op if no signals detected.
    await CoachMemoryService.instance
        .detectAndPersistIdentitySignals(userMessage);

    // Layer 1 dedup — scan coachBox for a recent non-failed match.
    final existing = _findRecentDuplicateMessageKey(
      userMessage: userMessage,
      mode: mode,
      mediaUrl: mediaUrl,
      window: coachWriterDedupWindow,
    );
    if (existing != null) {
      return existing;
    }

    final id = mintCoachKey();
    await _hive.coachBox.put(id, {
      'id': id,
      'user_message': userMessage,
      'ai_response': '',
      'model_used': '',
      'mode': mode,
      'is_user_message': true,
      'pending': true,
      'failed': false,
      'created_at': DateTime.now().toIso8601String(),
      'media_url': ?mediaUrl,
      'media_type': ?mediaType,
    });
    return id;
  }

  /// Returns the Hive key of an existing `coach_*` entry that is a
  /// duplicate of the proposed write under the dedup window, or null
  /// if no recent duplicate exists.
  @visibleForTesting
  String? findRecentDuplicateMessageKey({
    required String userMessage,
    required String mode,
    String? mediaUrl,
    Duration window = coachWriterDedupWindow,
  }) =>
      _findRecentDuplicateMessageKey(
        userMessage: userMessage,
        mode: mode,
        mediaUrl: mediaUrl,
        window: window,
      );

  String? _findRecentDuplicateMessageKey({
    required String userMessage,
    required String mode,
    String? mediaUrl,
    required Duration window,
  }) {
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    String? bestKey;
    DateTime bestCreated = DateTime.fromMillisecondsSinceEpoch(0);
    for (final entry in _hive.coachBox.toMap().entries) {
      final key = entry.key;
      final raw = entry.value;
      if (key is! String || !key.startsWith('coach_')) continue;
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      // Skip failed entries — explicit retry should mint a new row.
      if (map['failed'] == true) continue;
      if (map['user_message'] != userMessage) continue;
      if ((map['mode'] as String?) != mode) continue;
      if ((map['media_url'] as String?) != mediaUrl) continue;
      final createdStr = map['created_at'] as String?;
      if (createdStr == null) continue;
      final created = DateTime.tryParse(createdStr);
      if (created == null) continue;
      if (created.isBefore(cutoff)) continue;
      if (created.isAfter(bestCreated)) {
        bestCreated = created;
        bestKey = key;
      }
    }
    return bestKey;
  }

  /// Bug #19 — Updates a pending interaction with the AI's reply on success.
  /// Clears the `pending` flag and writes the model used.
  Future<void> updateInteractionWithResponse(
    String key, {
    required String aiResponse,
    required String modelUsed,
  }) async {
    // gate16-exempt: in-place mutation + write-back. Map is not surfaced
    // to a List consumer; the key is held by the caller.
    final raw = _hive.coachBox.get(key);
    if (raw is! Map) return;
    final entry = Map<String, dynamic>.from(raw);
    entry['ai_response'] = aiResponse;
    entry['model_used'] = modelUsed;
    entry['pending'] = false;
    entry['failed'] = false;
    entry.remove('error_text');
    await _hive.coachBox.put(key, entry);
  }

  /// Bug #19 — Marks a pending interaction as failed with the error text.
  /// The user message stays in coachBox so it survives an app restart, and
  /// [ChatHistoryNotifier] surfaces it as an error bubble with a Retry button.
  Future<void> updateInteractionWithError(
    String key, {
    required String errorText,
  }) async {
    // gate16-exempt: in-place mutation + write-back. Map is not surfaced
    // to a List consumer; the key is held by the caller.
    final raw = _hive.coachBox.get(key);
    if (raw is! Map) return;
    final entry = Map<String, dynamic>.from(raw);
    entry['ai_response'] = '';
    entry['pending'] = false;
    entry['failed'] = true;
    entry['error_text'] = errorText;
    await _hive.coachBox.put(key, entry);
  }

  /// Counts only user messages sent today (not AI responses).
  int getTodayUserMessageCount() {
    final todayStr = istDateStr(DateTime.now());

    int count = 0;
    for (final raw in _hive.coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final createdAt = interaction['created_at'] as String? ?? '';
      final hasUserMsg = interaction['user_message'] as String?;
      if (createdAt.startsWith(todayStr) &&
          hasUserMsg != null &&
          hasUserMsg.isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  /// Unit 2 — coach short-term memory. Returns the last [limit] COMPLETE coach
  /// exchanges (a user turn + its AI reply), oldest→newest, as a flat alternating
  /// list of `{role: 'user'|'model', text: ...}` maps for the ai-proxy `history`
  /// field. [limit] counts EXCHANGES (coachBox rows), so the result holds up to
  /// `2 * limit` entries — NOT 8 flat entries.
  ///
  /// Excludes rows that cannot be safely replayed:
  ///  - `kind`-tagged action rows (e.g. `completion_prompt` tap-cards),
  ///  - `pending`/`failed` rows (incl. the CURRENT turn's just-written pending
  ///    row — so a message never leaks into its own history),
  ///  - media rows (`mode == 'media'` — their `user_message` is a `[Photo] …`
  ///    placeholder, not usable text),
  ///  - any row missing a non-empty `user_message` OR `ai_response`.
  ///
  /// Hive iteration is INSERTION order, not chronological, so rows are SORTED
  /// ascending by `created_at` (ISO8601, lexicographically == chronologically)
  /// before the last-[limit] slice — mirrors the render path's sort in
  /// `ChatHistoryNotifier.build`. SoT concept `coach_chat_history_replay`.
  List<Map<String, dynamic>> recentHistoryExchanges({int limit = 8}) {
    final rows = <Map<String, dynamic>>[];
    for (final entry in _hive.coachBox.toMap().entries) {
      final key = entry.key;
      final raw = entry.value;
      // Interaction rows are keyed `coach_<ms>`; singleton siblings like
      // `coach_memory` also match the prefix but carry no `user_message`, so
      // the empty-text guard below drops them.
      if (key is! String || !key.startsWith('coach_')) continue;
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (map['kind'] != null) continue; // action rows (completion_prompt etc.)
      if (map['pending'] == true) continue;
      if (map['failed'] == true) continue;
      if (map['mode'] == 'media') continue; // '[Photo] …' placeholder text
      final user = (map['user_message'] as String?)?.trim() ?? '';
      final ai = (map['ai_response'] as String?)?.trim() ?? '';
      if (user.isEmpty || ai.isEmpty) continue;
      if ((map['created_at'] as String?) == null) continue;
      rows.add(map);
    }

    rows.sort((a, b) =>
        (a['created_at'] as String).compareTo(b['created_at'] as String));

    final recent =
        rows.length > limit ? rows.sublist(rows.length - limit) : rows;

    final out = <Map<String, dynamic>>[];
    for (final row in recent) {
      out.add({'role': 'user', 'text': (row['user_message'] as String).trim()});
      out.add({'role': 'model', 'text': (row['ai_response'] as String).trim()});
    }
    return out;
  }

  /// Gets the latest coaching insight from coaching_notes or last AI response.
  String getLatestInsight() {
    final notes = _hive.coachBox.get('coaching_notes');
    if (notes is Map) {
      final notesList = notes['notes'] as List?;
      if (notesList != null && notesList.isNotEmpty) {
        return notesList.last.toString();
      }
    }

    // Fallback: get the last AI response
    String? lastResponse;
    String lastTime = '';
    for (final raw in _hive.coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final aiResponse = interaction['ai_response'] as String?;
      final createdAt = interaction['created_at'] as String? ?? '';
      if (aiResponse != null &&
          aiResponse.isNotEmpty &&
          createdAt.compareTo(lastTime) > 0) {
        lastResponse = aiResponse;
        lastTime = createdAt;
      }
    }

    if (lastResponse != null && lastResponse.length > 120) {
      return '${lastResponse.substring(0, 120)}...';
    }
    return lastResponse ?? '';
  }
}
