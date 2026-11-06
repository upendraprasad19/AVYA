import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// What a prediction refresh came to. [dailyLimitReached] is the server's
/// 3/day cap (HTTP 429 + `code: RATE_LIMITED`, `_shared/prediction_handler.ts`):
/// a retry cannot succeed before the next IST day, so a caller must not say
/// "try again later" for it (B-pass c5d659f52986 Finding 1). [skipped] is an
/// automatic refresh that made no request because today's automatic attempt
/// was already spent (see [PredictionAttemptGate]).
enum PredictionRefreshOutcome { success, dailyLimitReached, failed, skipped }

/// One refresh at a time, and at most one AUTOMATIC attempt per IST day.
///
/// The server's 3/day cap counts attempts, not results, and never refunds.
/// The PRO 30-day auto-refresh fires on every rebuild of the prediction
/// provider while the text is 30+ days old, and the PRO goal-change
/// regenerate fires on every goal save — so with Gemini failing, automatic
/// calls alone could spend all three units before the user ever tapped
/// UPDATE (Hermes 2026-09-26, L1-F3 / L29-F4). Automatic callers now share
/// one attempt a day, recorded BEFORE the request so an app killed mid-call
/// still counts, which leaves at least two units for the user's own taps.
/// A request made while another is running joins it instead of spending a
/// second unit. A manual tap is never limited here — the server cap is its
/// only limit.
class PredictionAttemptGate {
  PredictionAttemptGate({
    required String? Function() readLastAutomaticDay,
    required Future<void> Function(String day) writeLastAutomaticDay,
    required String Function() today,
  })  : _readLastAutomaticDay = readLastAutomaticDay,
        _writeLastAutomaticDay = writeLastAutomaticDay,
        _today = today;

  final String? Function() _readLastAutomaticDay;
  final Future<void> Function(String day) _writeLastAutomaticDay;
  final String Function() _today;
  Future<PredictionRefreshOutcome>? _inFlight;

  /// B-pass finding, 2026-09-26: without this, a same-device account
  /// switch while a request is in flight lets the NEW account's own tap
  /// join the OLD account's stale future via [run]'s `if (running != null)
  /// return running;` line, handing the new user an outcome (e.g. success)
  /// for a request that was never made on their behalf. Called from
  /// [PredictionService]'s [SingletonLifecycleRegistry] hook — the
  /// `_regenerate` closure already in flight for the old account is not
  /// cancelled (Dart Futures can't be), only DEREFERENCED here so nothing
  /// new joins it; its own write is separately guarded by
  /// [PredictionService.safeToWriteForTest].
  void clearInFlightForAccountChange() {
    _inFlight = null;
  }

  Future<PredictionRefreshOutcome> run(
    Future<PredictionRefreshOutcome> Function() attempt, {
    required bool automatic,
  }) {
    final running = _inFlight;
    if (running != null) return running;
    String? automaticDay;
    if (automatic) {
      automaticDay = _today();
      if (_readLastAutomaticDay() == automaticDay) {
        return Future.value(PredictionRefreshOutcome.skipped);
      }
    }
    // Assigned before the first await, so a second call in the same tick
    // already sees it.
    final future = () async {
      if (automaticDay != null) await _writeLastAutomaticDay(automaticDay);
      return attempt();
    }();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }
}

/// Shared utility for AI prediction generation.
///
/// Extracted from profile_screen._refreshPrediction so that both
/// profile_screen (manual refresh) and edit_profile_screen (auto-refresh
/// on goal change) can reuse the same logic.
class PredictionService {
  PredictionService._() {
    // B-pass finding, 2026-09-26 — PredictionService was the one service
    // in this family (AiService, SubscriptionService, SyncService, …, all
    // 10+) never registered with SingletonLifecycleRegistry, so an
    // account switch never cleared its in-flight gate. See
    // PredictionAttemptGate.clearInFlightForAccountChange's doc comment.
    SingletonLifecycleRegistry.register('PredictionService', _onUserChanged);
  }
  static final instance = PredictionService._();

  final PredictionAttemptGate _gate = PredictionAttemptGate(
    readLastAutomaticDay: () =>
        MigratedKey.read<String>('prediction_auto_attempt_day'),
    writeLastAutomaticDay: (day) =>
        MigratedKey.write('prediction_auto_attempt_day', day),
    today: istTodayStr,
  );

  void _onUserChanged() {
    _gate.clearInFlightForAccountChange();
  }

  /// Generate a fresh AI prediction using CURRENT profile data and save to
  /// configBox. [automatic] is for refreshes the user did not ask for (the
  /// PRO 30-day refresh, the PRO goal-change regenerate): they get one
  /// attempt per IST day between them and otherwise return
  /// [PredictionRefreshOutcome.skipped] without a request.
  Future<PredictionRefreshOutcome> regeneratePrediction(
          {bool automatic = false}) =>
      _gate.run(_regenerate, automatic: automatic);

  Future<PredictionRefreshOutcome> _regenerate() async {
    // B-pass finding, 2026-09-26: MigratedKey.write resolves the CURRENT
    // userBox at write time (migrated_key.dart), not the box open when
    // this method started. Capture the owner now so the write below can
    // refuse if the signed-in account changed while `predict()` was
    // in flight — otherwise a prediction generated for THIS profile would
    // land in a DIFFERENT, later-signed-in account's box (the
    // auth_hive_owner_agreement class).
    final ownerAtStart = HiveUserSession.currentOwnerFullId;
    final profile = UserRepository.instance.getProfile();
    final progress = UserRepository.instance.getProgress();
    if (profile == null) return PredictionRefreshOutcome.failed;

    try {
      final name = profile['full_name'] ?? 'User';
      final weight = profile['current_weight_kg'] ?? '?';
      final target = profile['target_weight_kg'] ?? '?';
      final goal = profile['primary_goal'] ?? 'general_fitness';
      final workoutsDone = progress?['total_workouts_done'] ?? 0;
      final streakDays = progress?['current_streak_days'] ?? 0;

      const rulesBlock = '''
CRITICAL OUTPUT RULES:
- Reply in plain English sentences or bullet points only.
- DO NOT use any structured format.
- DO NOT prefix lines with labels like "outcome:", "weight_kg:", "summary:", "prediction:", or any colon-separated keys.
- DO NOT return JSON. DO NOT wrap in code fences.
- Just write 2-4 bullet points of prose. Direct address ("you").
- 80 words maximum.''';

      final prompt = '''Predict realistic 12-week fitness outcomes.

Data: $name, ${weight}kg → ${target}kg, goal=$goal, $workoutsDone workouts done, $streakDays day streak.
$rulesBlock

Format (use • not JSON):
• Weight: current → 4wk → 8wk → 12wk
• Body fat estimate change
• Key lift projections
• One motivational line''';

      final response = await AiService.instance.predict(prompt);
      if (!safeToWriteForTest(ownerAtStart, HiveUserSession.currentOwnerFullId)) {
        unawaited(ErrorTelemetry.recordNonFatal(
            StateError(
                'prediction resolved after the signed-in account changed'),
            StackTrace.current,
            reason: 'prediction_service_regenerate_account_switched'));
        return PredictionRefreshOutcome.failed;
      }
      if (response.reply.isNotEmpty) {
        await MigratedKey.write('prediction_text', response.reply);
        await MigratedKey.write(
            'prediction_date', DateTime.now().toIso8601String());
        await MigratedKey.write(
            'prediction_generated_at', DateTime.now().toIso8601String());
        await MigratedKey.delete('prediction_stale');
        debugPrint('[PredictionService] Prediction regenerated successfully');
        return PredictionRefreshOutcome.success;
      }
      return PredictionRefreshOutcome.failed;
    } catch (e, st) {
      debugPrint('[PredictionService] Prediction regeneration failed: $e');
      final outcome = outcomeForError(e);
      // The daily cap is the server working as designed, not a fault — only
      // real failures go to telemetry. audit-2026-05-11 H-42 — telemetry pair.
      if (outcome == PredictionRefreshOutcome.failed) {
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'prediction_service_regenerate_prediction'));
      }
      return outcome;
    }
  }

  /// Whether it is still safe to write a regeneration's result: the
  /// signed-in account must be the SAME one that was active when the
  /// request started. Pure two-argument form so it is testable without
  /// touching [HiveUserSession] (see the doc comment on the call site in
  /// [_regenerate]).
  @visibleForTesting
  static bool safeToWriteForTest(String? ownerAtStart, String? ownerNow) =>
      ownerAtStart == ownerNow;

  /// A caught error as an outcome. Pure, so the 429 rule is testable without
  /// Hive or the network; [AiService.predictionFailure] supplies the status
  /// and the body's `code`. Only the prediction cap's own refusal — 429 WITH
  /// `RATE_LIMITED` — reads as the daily limit: a 429 from anything else
  /// (a gateway or platform limit) is a fault, and must neither tell the user
  /// "try again tomorrow" nor skip telemetry (Hermes 2026-09-26, L37-F3).
  @visibleForTesting
  static PredictionRefreshOutcome outcomeForError(Object error) =>
      error is AiServiceException &&
              error.statusCode == 429 &&
              error.code == 'RATE_LIMITED'
          ? PredictionRefreshOutcome.dailyLimitReached
          : PredictionRefreshOutcome.failed;

  /// Whether a PRO user's UPDATE button is live: monthly, and also whenever
  /// the text is stale — the goal changed and the automatic regenerate failed
  /// or was skipped. Without the stale arm the card told a PRO user to
  /// "Refresh prediction" while the button stayed disabled for up to 30 days
  /// (Hermes 2026-09-26, L1-F1). Free users refresh through the paywall path,
  /// never this button.
  static bool refreshEnabled({
    required bool isPro,
    required DateTime? generatedAt,
    required bool isStale,
    required DateTime now,
  }) {
    if (!isPro) return false;
    if (isStale) return true;
    return generatedAt != null && now.difference(generatedAt).inDays >= 30;
  }

  /// Mark the current cached prediction as stale (goal changed: a free user,
  /// or a PRO user whose automatic regenerate did not succeed).
  void markStale() {
    MigratedKey.write('prediction_stale', true);
  }

  /// Clear the stale flag (after successful regeneration).
  void clearStale() {
    MigratedKey.delete('prediction_stale');
  }
}
