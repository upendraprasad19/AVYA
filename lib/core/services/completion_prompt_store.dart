import 'hive_service.dart';

/// Coach workout parity 1b (OI-490; plan `docs/plans/coach-workout-parity-1b.md`
/// D1): the ONE owner of the coach completion-prompt row,
/// `coachBox['completion_prompt_<yyyy-MM-dd>']` — the "X of Y · [Log more]
/// [Complete]" chat tile.
///
/// The row is a LOCAL-ONLY action row (`kind: 'completion_prompt'`): it is not
/// an `ai_coach_interaction`, `sync_coach.dart` excludes it from push and
/// restore, and `ChatHistoryNotifier.build` renders it. `resolved_at: null`
/// on write; a tap, a later all-logged completion or a move/drop of the day
/// stamps `resolved_at`.
///
/// Moved here from `ToolDispatcher._writeCompletionPrompt` /
/// `_resolveCompletionPromptIfPresent` (bodies unchanged) so the chat card,
/// the typed backstop, the tile and Train's Complete button share one writer,
/// and Train never imports the coach feature. Prompts are written for IST
/// TODAY only (decision F: a past partial day stays not done); the callers
/// decide that, and [write] sweeps older unresolved rows.
class CompletionPromptStore {
  CompletionPromptStore._();
  static final CompletionPromptStore instance = CompletionPromptStore._();

  static const String keyPrefix = 'completion_prompt_';
  static String keyFor(String dateStr) => '$keyPrefix$dateStr';

  /// Writes (or updates — supersede on the next log) the prompt row for
  /// [dateStr], keeping the original `created_at` so the tile keeps its place
  /// in the chat scroll; only the counts refresh. Any OLDER unresolved prompt
  /// row is resolved in the same call (the sweep lives in a write path, never
  /// in a provider build).
  Future<void> write({
    required String dateStr,
    required int plannedCount,
    required int loggedCount,
  }) async {
    final box = HiveService.instance.coachBox;
    final key = keyFor(dateStr);
    final existing = box.get(key);
    final createdAt = (existing is Map && existing['created_at'] is String)
        ? existing['created_at'] as String
        : DateTime.now().toIso8601String();
    await box.put(key, {
      'kind': 'completion_prompt',
      'date': dateStr,
      'planned_count': plannedCount,
      'logged_count': loggedCount,
      'created_at': createdAt,
      'resolved_at': null,
    });
    await _resolveOlderThan(dateStr);
  }

  /// Stamps `resolved_at` on the prompt row for [dateStr] if one exists and is
  /// still open (idempotent no-op otherwise).
  Future<void> resolve(String dateStr) async {
    final box = HiveService.instance.coachBox;
    final key = keyFor(dateStr);
    final raw = box.get(key);
    if (raw is! Map || raw['resolved_at'] != null) return;
    final entry = Map<String, dynamic>.from(raw);
    entry['resolved_at'] = DateTime.now().toIso8601String();
    await box.put(key, entry);
  }

  Future<void> _resolveOlderThan(String dateStr) async {
    final box = HiveService.instance.coachBox;
    final older = <String>[
      for (final k in box.keys)
        if (k is String &&
            k.startsWith(keyPrefix) &&
            k.substring(keyPrefix.length).compareTo(dateStr) < 0)
          k.substring(keyPrefix.length),
    ];
    for (final d in older) {
      await resolve(d);
    }
  }
}
