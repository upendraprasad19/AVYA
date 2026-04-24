import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Shared utility for AI prediction generation.
///
/// Extracted from profile_screen._refreshPrediction so that both
/// profile_screen (manual refresh) and edit_profile_screen (auto-refresh
/// on goal change) can reuse the same logic.
class PredictionService {
  PredictionService._();
  static final instance = PredictionService._();

  /// Generate a fresh AI prediction using CURRENT profile data and save to
  /// configBox. Returns `true` on success.
  Future<bool> regeneratePrediction() async {
    final profile = UserRepository.instance.getProfile();
    final progress = UserRepository.instance.getProgress();
    if (profile == null) return false;

    try {
      final name = profile['full_name'] ?? 'User';
      final weight = profile['current_weight_kg'] ?? '?';
      final target = profile['target_weight_kg'] ?? '?';
      final goal = profile['primary_goal'] ?? 'general_fitness';
      final workoutsDone = progress?['total_workouts_done'] ?? 0;
      final streakDays = progress?['current_streak_days'] ?? 0;

      final prompt = '''Predict realistic 12-week fitness outcomes.

Data: $name, ${weight}kg → ${target}kg, goal=$goal, $workoutsDone workouts done, $streakDays day streak.

Reply as plain text bullet points ONLY. Max 80 words.
DO NOT return JSON. DO NOT wrap in code fences. DO NOT include keys like "predictions", "timeframe", or "summary". Plain bullets only.

Format (use • not JSON):
• Weight: current → 4wk → 8wk → 12wk
• Body fat estimate change
• Key lift projections
• One motivational line''';

      final aiContext = {
        'system_prompt':
            'You are a sports science expert making evidence-based fitness predictions. Be specific with numbers but realistic.',
      };

      final response = await AiService.instance.predict(prompt, aiContext);
      if (response.reply.isNotEmpty) {
        final configBox = HiveService.instance.configBox;
        await configBox.put('prediction_text', response.reply);
        await configBox.put('prediction_date', DateTime.now().toIso8601String());
        await configBox.put(
            'prediction_generated_at', DateTime.now().toIso8601String());
        await configBox.delete('prediction_stale');
        debugPrint('[PredictionService] Prediction regenerated successfully');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[PredictionService] Prediction regeneration failed: $e');
      return false;
    }
  }

  /// Mark the current cached prediction as stale (goal changed, free user).
  void markStale() {
    HiveService.instance.configBox.put('prediction_stale', true);
  }

  /// Clear the stale flag (after successful regeneration).
  void clearStale() {
    HiveService.instance.configBox.delete('prediction_stale');
  }
}
