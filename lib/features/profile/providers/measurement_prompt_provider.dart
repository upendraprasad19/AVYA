import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';

String? _storedDate(String key) {
  final v = MigratedKey.read<dynamic>(key);
  return v is String ? v : null;
}

/// Which body-measurements prompt the Home banner and the Weight-sheet link
/// show (L2b Landing B, B2/B3).
///
/// `build()` is TOTAL: it must yield a value, never throw into a widget build.
/// Order: (1) the anonymous token returns `none` silently, before the flag, the
/// history or the profile is touched (the profile throws in that window, and
/// an event there would be a wasted call); (2) the flag; (3) the history and the
/// profile, inside a try/catch that logs `measurement_prompt_build_failed`.
/// The token watch is redundant only for a real-to-real token change and
/// load-bearing in the anonymous window, where it is the prompt's only
/// dependency (the prompt is never invalidated from outside).
class MeasurementPromptNotifier extends Notifier<MeasurementPrompt> {
  @override
  MeasurementPrompt build() {
    final token = ref.watch(authUserIdTokenProvider); // c4055a
    if (token == '<anon>') return MeasurementPrompt.none;
    final flagOn = ref.watch(measurementsEnabledProvider);
    if (!flagOn) return MeasurementPrompt.none;
    try {
      // An explicit watch, so a write or a restore tick that invalidates the
      // history refreshes the prompt.
      final history = ref.watch(bodyMeasurementsProvider);
      final profile = ref.watch(userProfileProvider);
      // The stamp is a UTC ISO string: never its first ten characters (wrong
      // for 18:30-24:00 UTC) and never a cast (1 of 33 cloud rows has none).
      final raw = profile['onboarding_completed_at'];
      final parsed = raw is String ? DateTime.tryParse(raw) : null;
      return measurementPromptFor(
        flagOn: flagOn,
        historyKnown: history.loaded,
        todayIst: istTodayStr(),
        onboardedIst: parsed == null ? null : istDateStr(parsed),
        lastEntryIst: history.lastEntryDate,
        dismissedIst: _storedDate('body_measurement_prompt_dismissed_at'),
        baselineSkippedIst:
            _storedDate('body_measurement_prompt_baseline_skipped_at'),
      );
    } catch (_) {
      unawaited(ErrorTelemetry.logEvent('measurement_prompt_build_failed',
          message: 'stage=prompt'));
      return MeasurementPrompt.none;
    }
  }

  /// The X on a `due` banner: silences every surface of this landing for
  /// [kMeasurementDismissSnoozeDays] days. Writes nothing without a session
  /// owner (the key would land in the shared `configBox`).
  Future<void> dismiss() async {
    if (HiveUserSession.currentOwnerFullId == null) return;
    await MigratedKey.write(
        'body_measurement_prompt_dismissed_at', istTodayStr());
    ref.invalidateSelf();
  }

  /// The X on a `baseline` banner: silences the baseline prompt for
  /// [kMeasurementBaselineSnoozeDays] days.
  Future<void> skipBaseline() async {
    if (HiveUserSession.currentOwnerFullId == null) return;
    await MigratedKey.write(
        'body_measurement_prompt_baseline_skipped_at', istTodayStr());
    ref.invalidateSelf();
  }
}

final measurementPromptProvider =
    NotifierProvider<MeasurementPromptNotifier, MeasurementPrompt>(
        MeasurementPromptNotifier.new);
