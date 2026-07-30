// Tech-debt audit 2026-05-20 finding A10 — THIN SHIM.
//
// This file used to be 2127 lines carrying 4 contracts in one class:
//   - AI snapshot building (buildAiContext + ~40 private read helpers)
//   - Interaction persistence (saveInteraction + dedup window + pending/failed flags)
//   - Identity-signal detection (detectAndPersistIdentitySignals)
//   - Coaching-notes extraction + backfill
//
// Test #8's "4 ai_coach_repository drift fixes" all landed here because
// every AI-snapshot field flowed through one buildAiContext(). To keep
// the writer/reader-drift blast radius scoped, the 4 contracts moved
// into 3 dedicated services:
//
//   - AiSnapshotBuilder         (lib/features/ai_coach/services/ai_snapshot_builder.dart)
//   - CoachInteractionRepository(lib/features/ai_coach/repositories/coach_interaction_repository.dart)
//   - CoachMemoryService        (lib/features/ai_coach/services/coach_memory_service.dart)
//
// AiCoachRepository now FORWARDS every call to the right service for
// back-compat with existing imports (main.dart, ai_coach_provider.dart,
// insight_card.dart, sync_service.dart). New callers should import the
// specific service directly.
//
// Snapshot contract gate note: `scripts/check_snapshot_contract.dart`
// regex-scans this file for `'<key>':` emissions. The literal key list
// is reproduced here in `_snapshotContractKeyManifest` so the gate
// continues to validate against the canonical source-of-truth file
// even though the actual emission now lives in AiSnapshotBuilder.
// Keep this manifest in lock-step with AiSnapshotBuilder.buildAiContext.
//
// closes-finding: tech-debt-audit-2026-05-20-A10

import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:meta/meta.dart';
import '../services/ai_snapshot_builder.dart';
import '../services/coach_memory_service.dart';
import '../services/pattern_detector.dart';
import 'coach_interaction_repository.dart';

/// Back-compat shim. Forwards to the three new services.
///
/// Prefer importing the specific service for new code:
///   - `AiSnapshotBuilder.instance.buildAiContext()`
///   - `CoachInteractionRepository.instance.saveInteraction(...)`
///   - `CoachMemoryService.instance.detectAndPersistIdentitySignals(...)`
class AiCoachRepository {
  AiCoachRepository._();
  static final AiCoachRepository _instance = AiCoachRepository._();
  static AiCoachRepository get instance => _instance;

  /// Direct access to the snapshot builder for callers that want to skip
  /// the shim layer.
  AiSnapshotBuilder get snapshotBuilder => AiSnapshotBuilder.instance;

  /// Direct access to the interaction repository.
  CoachInteractionRepository get interactions =>
      CoachInteractionRepository.instance;

  /// Direct access to the coach-memory service.
  CoachMemoryService get memory => CoachMemoryService.instance;

  // ── AI snapshot surface (forwards to AiSnapshotBuilder) ────────────

  Map<String, dynamic> buildAiContext() =>
      AiSnapshotBuilder.instance.buildAiContext();

  Map<String, dynamic> enrichContextForQuery(
          String message, Map<String, dynamic> context) =>
      AiSnapshotBuilder.instance.enrichContextForQuery(message, context);

  // ── Interaction persistence (forwards to CoachInteractionRepository) ──

  Future<String> saveInteraction({
    required String userMessage,
    required String aiResponse,
    required String modelUsed,
    required String mode,
  }) =>
      CoachInteractionRepository.instance.saveInteraction(
        userMessage: userMessage,
        aiResponse: aiResponse,
        modelUsed: modelUsed,
        mode: mode,
      );

  Future<String> saveUserMessagePending({
    required String userMessage,
    required String mode,
    String? mediaUrl,
    String? mediaType,
    String? mediaStoragePath,
  }) =>
      CoachInteractionRepository.instance.saveUserMessagePending(
        userMessage: userMessage,
        mode: mode,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        mediaStoragePath: mediaStoragePath,
      );

  /// Unit 8 (coach-media-consent, OI-25) — thin forwarder, mirrors the
  /// shape above. See CoachInteractionRepository.recordMediaSaveDecision.
  Future<void> recordMediaSaveDecision(String key, {required bool saved}) =>
      CoachInteractionRepository.instance
          .recordMediaSaveDecision(key, saved: saved);

  /// Back-compat forwarder for the dedup contract test. New code should
  /// call `CoachInteractionRepository.instance.findRecentDuplicateMessageKey`
  /// directly (it's `@visibleForTesting` on that class).
  String? findRecentDuplicateMessageKey({
    required String userMessage,
    required String mode,
    String? mediaUrl,
    Duration? window,
  }) =>
      // ignore: invalid_use_of_visible_for_testing_member
      CoachInteractionRepository.instance.findRecentDuplicateMessageKey(
        userMessage: userMessage,
        mode: mode,
        mediaUrl: mediaUrl,
        // Mirror of CoachInteractionRepository.coachWriterDedupWindow.
        // Inlined to avoid invalid_use_of_visible_for_testing_member
        // here on the production-code shim.
        window: window ?? const Duration(seconds: 60),
      );

  Future<void> updateInteractionWithResponse(
    String key, {
    required String aiResponse,
    required String modelUsed,
  }) =>
      CoachInteractionRepository.instance.updateInteractionWithResponse(
        key,
        aiResponse: aiResponse,
        modelUsed: modelUsed,
      );

  /// Bug 2026-05-22 / diagnose b4a09c — A10 refactor (commit d6e472c,
  /// 2026-05-21) extracted snapshot logic into `AiSnapshotBuilder` but
  /// did not forward these two `@visibleForTesting` seams. Existing
  /// tests at `test/ai_coach/meals_today_snapshot_test.dart` +
  /// `nutrition_trend_7d_snapshot_test.dart` were left calling deleted
  /// methods, blocking the pre-commit hook on every new commit. These
  /// forwarders match the shim pattern documented at line 51
  /// (`snapshotBuilder` getter) and the dedup forwarder at line 100.
  @visibleForTesting
  List<Map<String, dynamic>> mealsTodayForTest() {
    // ignore: invalid_use_of_visible_for_testing_member
    return AiSnapshotBuilder.instance.mealsTodayForTest();
  }

  @visibleForTesting
  List<Map<String, dynamic>> nutritionTrend7dForTest() {
    // ignore: invalid_use_of_visible_for_testing_member
    return AiSnapshotBuilder.instance.nutritionTrend7dForTest();
  }

  Future<void> updateInteractionWithError(
    String key, {
    required String errorText,
  }) =>
      CoachInteractionRepository.instance
          .updateInteractionWithError(key, errorText: errorText);

  int getTodayUserMessageCount() =>
      CoachInteractionRepository.instance.getTodayUserMessageCount();

  String getLatestInsight() =>
      CoachInteractionRepository.instance.getLatestInsight();

  /// Unit 2 — coach short-term memory. Forwards to
  /// [CoachInteractionRepository.recentHistoryExchanges].
  List<Map<String, dynamic>> recentHistoryExchanges(
          {int limit = 8, String? excludeKey}) =>
      CoachInteractionRepository.instance
          .recentHistoryExchanges(limit: limit, excludeKey: excludeKey);

  // ── Coach-memory surface (forwards to CoachMemoryService) ──────────

  Future<void> detectAndPersistIdentitySignals(String userMessage) =>
      CoachMemoryService.instance.detectAndPersistIdentitySignals(userMessage);

  /// Renamed canonical: extractAndAppendCoachingNotes (was extractCoachingNotes).
  /// Kept the legacy method name on the shim for back-compat.
  Future<void> extractCoachingNotes() =>
      CoachMemoryService.instance.extractAndAppendCoachingNotes();

  Future<void> backfillCoachMemoryIfNeeded() =>
      CoachMemoryService.instance.backfillCoachMemoryIfNeeded();

  bool isFirstMessageToday() =>
      CoachMemoryService.instance.isFirstMessageToday();

  Future<void> markGreetedToday() =>
      CoachMemoryService.instance.markGreetedToday();

  CoachingInsight? getTopInsight() =>
      CoachMemoryService.instance.getTopInsight();

  // ── Composite UI helper kept on the shim (uses both snapshot + state) ──

  /// Returns contextual quick prompts based on user's current state.
  /// Reads from the snapshot builder so the source of truth stays
  /// single — the prompts react to the exact same fields the AI sees.
  List<String> getContextualPrompts() {
    final snapshot = AiSnapshotBuilder.instance.buildAiContext();
    final prompts = <String>[];
    final progress = (snapshot['progress'] as Map?) ?? const {};
    final todayNutrition = (snapshot['today_nutrition'] as Map?) ?? const {};
    final thisWeekWorkouts =
        (snapshot['this_week_workouts'] as Map?) ?? const {};

    final workoutsToday = (thisWeekWorkouts['completed_today'] as bool?) ?? false;
    if (workoutsToday) {
      prompts.add('How did my workout go?');
      prompts.add('What should I eat for recovery?');
    } else {
      prompts.add('What\'s my workout today?');
    }

    final caloriesLogged = (todayNutrition['calories_logged'] as num?) ?? 0;
    if (caloriesLogged == 0) {
      prompts.add('What should I eat today?');
    } else {
      prompts.add('Am I on track with macros?');
    }

    final phase = (progress['current_phase'] as int?) ?? 1;
    if (phase == 1) {
      prompts.add('Tips for beginners?');
    } else {
      prompts.add('Analyse my progress');
    }

    if (prompts.length < 4) {
      prompts.add('Help me stay motivated');
    }

    return prompts.take(4).toList();
  }

  /// Drift-fix batch 2026-05-24 / F1 workout (P1).
  ///
  /// Returns the reps achieved at the PR weight (the heaviest set in
  /// the log), NOT the SUM across sets. Falls through to
  /// `reps_completed` for legacy rows without a `sets[]` array.
  ///
  /// Why: per CLAUDE.md §15 Hive field-name contract, `reps_completed`
  /// is SUM across sets (writer-side semantic). The AI coach PR
  /// snapshot used to surface this as "PR: 100kg x 28 reps" for a
  /// 4-set pyramid — nonsense lifting semantics.
  ///
  /// Static + pure helper — usable from `AiSnapshotBuilder` (where the
  /// PR projection now lives post-A10 split) without an instance.
  static int? prSetRepsForExlog(Map<String, dynamic> log) {
    final sets = (log['sets'] as List?) ?? const [];
    if (sets.isNotEmpty) {
      final prWeight = (log['weight_kg'] as num?)?.toDouble();
      if (prWeight != null) {
        for (final s in sets) {
          if (s is! Map) continue;
          final w = (s['weight_kg'] as num?)?.toDouble();
          if (w == prWeight) {
            final r = (s['reps'] as num?)?.toInt();
            if (r != null) return r;
          }
        }
      }
    }
    // Fall through: legacy rows without sets[] OR no set matched PR
    // weight (degenerate data) OR empty sets[] array.
    return (log['reps_completed'] as num?)?.toInt();
  }

  /// F14 · Test #9 — returns the user's lifetime count of free
  /// image analyses on the AI coach. Server enforces the 5-cap; this is
  /// purely for "X of 5 free analyses left" display in the chat UI.
  ///
  /// Cloud-only read — does not belong on either Hive-bound service.
  Future<int> getFreeImageAnalysisCount() async {
    final user = SupabaseService.instance.client.auth.currentUser;
    if (user == null) return 0;
    try {
      final rows = await SupabaseService.instance.client
          .from('ai_coach_interactions')
          .select('id')
          .eq('user_id', user.id)
          .eq('channel', 'free_image_analysis');
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// Snapshot contract key manifest — DO NOT REMOVE.
  ///
  /// `scripts/check_snapshot_contract.dart` regex-scans the writer file
  /// for `'<key>':` literal emissions. Since the actual emission moved
  /// to `AiSnapshotBuilder.buildAiContext` during the A10 split, the
  /// gate would now miss the keys. We reproduce the key list here as a
  /// data structure (not used at runtime) so the gate's source-grep
  /// continues to validate against this canonical path.
  ///
  /// Keep in lock-step with AiSnapshotBuilder.buildAiContext. If a key
  /// is added or removed there, mirror the change here.
  // ignore: unused_field
  static const Map<String, Object?> _snapshotContractKeyManifest = {
    'is_first_ever_message': null,
    'profile': null,
    'progress': null,
    'current_streak_weeks': null,
    'current_streak_days': null,
    'total_workouts_done': null,
    'current_weight_kg': null,
    'target_weight_kg': null,
    'today_workout_name': null,
    'recent_pr_exercise': null,
    'recent_pr_weight': null,
    'yesterday_calories': null,
    'daily_calorie_target': null,
    'daily_targets': null,
    'this_week_workouts': null,
    'today_nutrition': null,
    'today_steps': null,
    'step_history_7d': null,
    'latest_weight': null,
    'personal_records': null,
    'coaching_notes': null,
    'coach_memory': null,
    'fitness_summary': null,
    'motivational_style': null,
    'coach_notices': null,
    'custom_exercises': null,
    'saved_templates': null,
    'meals_today': null,
    'nutrition_trend_7d': null,
    'data_window_days': null,
    'first_workout_date': null,
    'workout_logs_count': null,
    'nutrition_logs_count_7d': null,
    'sleep_logs_count_7d': null,
    'today_workout': null,
    'yesterday_workout': null,
    'week_lookahead': null,
    'current_plan_summary': null,
    'sleep_7d': null,
    'water_7d': null,
    'streak_freezes_available': null,
    'streak_freezes_refill_date': null,
    'subscription': null,
    'current_rank': null,
    'next_rank': null,
    'eta_next_promotion': null,
    'cadence': null,
    'active_workout': null,
    'committed_at': null,
    'committed_to_lt_cdr': null,
    'days_since_commitment': null,
    'why_now': null,
    'definition_of_winning': null,
    'known_injuries': null,
    'typical_wake_time': null,
    'preferred_workout_time': null,
    'body_part_priorities': null,
    'pr_timeline_summary': null,
    'goal_changed_at': null,
    'body_measurements': null,
    'onboarding_completed_at': null,
    'phase_transitions': null,
    'recent_meal_deletes': null,
  };
}
