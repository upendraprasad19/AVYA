import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// What the measurements sheet and the prompt know about the stored history
/// (L2b Landing B, B2).
///
/// [loaded] is true when the read succeeded (an empty history is `loaded` with
/// no entries); false on a failed read or in the anonymous-token window, so
/// that "could not read" never looks like "never measured". [latest] is the
/// newest valid value per site with its IST day; [lastEntryDate] is the newest
/// entry's day. [entries] is the valid history NEWEST FIRST, the list
/// `HealthReadService.measurementHistory()` returned (L2b Landing C: the
/// Progress comparison card derives the first and latest value of each site
/// from it; the sheet and the prompt keep reading [latest] and
/// [lastEntryDate]). It stays empty on a failed read and in the anonymous-token
/// window, like the rest of the state.
///
/// Deliberately NO value equality: Riverpod 3 filters notifications with `==`,
/// so an `==` over [latest] would stop a rollover refresh reaching the prompt.
/// The name follows the `ExpiryBannerState` precedent (the naming doc's
/// `<Concept>Data` rule is departed from, recorded in `naming_conventions.md`).
class BodyMeasurementsState {
  const BodyMeasurementsState({
    this.loaded = false,
    this.latest = const {},
    this.lastEntryDate,
    this.entries = const [],
  });

  final bool loaded;
  final Map<String, ({double cm, String date})> latest;
  final String? lastEntryDate;
  final List<MeasurementEntry> entries;
}

class BodyMeasurementsNotifier extends Notifier<BodyMeasurementsState> {
  @override
  BodyMeasurementsState build() {
    final token = ref.watch(authUserIdTokenProvider); // c4055a
    // The window of every account swap (live auth uid and Hive owner disagree):
    // healthBox throws there. Silent: not a defect, and no read is attempted.
    if (token == '<anon>') return const BodyMeasurementsState();
    try {
      final history = HealthReadService.instance.measurementHistory();
      return BodyMeasurementsState(
        loaded: true,
        latest: HealthReadService.latestBySiteOf(history),
        lastEntryDate: history.isEmpty ? null : history.first.date,
        entries: history,
      );
    } catch (_) {
      unawaited(ErrorTelemetry.logEvent('measurement_history_read_failed',
          message: 'stage=history'));
      return const BodyMeasurementsState();
    }
  }
}

final bodyMeasurementsProvider =
    NotifierProvider<BodyMeasurementsNotifier, BodyMeasurementsState>(
        BodyMeasurementsNotifier.new);

/// PURE rule for remembering the sheet's last-used unit after a save: the save
/// succeeded AND the auth token was a real user's before the write AND is the
/// same token after it.
///
/// Why the token and not the Hive owner: `authUserIdTokenProvider` is
/// `'<anon>'` exactly when the live auth uid and the Hive owner disagree (or
/// either is null), and otherwise carries the auth uid, so it changes in both
/// account-swap windows. In the window in which the auth uid already names the
/// next user while the Hive owner is still the old one, `userBox` serves an
/// empty stub and `MigratedKey.write` falls back to the shared `configBox`: a
/// guard that compared the Hive owner with itself would pass there and let the
/// first user's cm/in preference reach the next account.
@visibleForTesting
bool shouldRememberUnit({
  required bool saved,
  required String tokenBefore,
  required String tokenNow,
}) =>
    saved && tokenBefore != '<anon>' && tokenNow == tokenBefore;

/// Writes from the measurements sheet and refreshes [bodyMeasurementsProvider].
///
/// A [Notifier] so its [Ref] outlives any widget (a `WidgetRef` used after an
/// await on a disposed sheet throws a `StateError`). It holds no per-user state.
class MeasurementWriteNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Saves [sites] (centimetres) as one day record dated now.
  ///
  /// Order matters and is pinned: the token is read before the write and again
  /// after it ([shouldRememberUnit]); the unit is remembered only on a success
  /// in the same session; and the provider is invalidated AFTER the await (an
  /// invalidation placed before it is observable under a held day lock: the
  /// zero-delay refresh would build the provider from a box that holds the
  /// first writer's site and not yet this one, and nothing would refresh it
  /// again).
  Future<WriteResult> save({
    required Map<String, double> sites,
    required WriteSource source,
    required bool inchesUsed,
  }) async {
    final tokenBefore = ref.read(authUserIdTokenProvider);
    final result = await HealthWriteService.instance.logMeasurements(
      date: nowWall(),
      sites: sites,
      source: source,
    );
    final tokenNow = ref.read(authUserIdTokenProvider);
    if (shouldRememberUnit(
      saved: result.success,
      tokenBefore: tokenBefore,
      tokenNow: tokenNow,
    )) {
      await MigratedKey.write(
          'body_measurement_sheet_unit', inchesUsed ? 'in' : 'cm');
    }
    ref.invalidate(bodyMeasurementsProvider);
    return result;
  }

  /// Refreshes the history after a write made elsewhere (the chat path, B7).
  /// Invalidating a provider that was never built is a no-op.
  void noteWritten() {
    ref.invalidate(bodyMeasurementsProvider);
  }

  /// The unit of the last successful save: `true` inches, `false` centimetres,
  /// `null` when none was ever remembered (the sheet then follows the device's
  /// `units_metric` setting).
  bool? lastUnitInches() {
    final v = MigratedKey.read<dynamic>('body_measurement_sheet_unit');
    if (v == 'in') return true;
    if (v == 'cm') return false;
    return null;
  }

  /// Whether the sheet and the Progress comparison card show inches: the unit of
  /// the last successful save, else the device's `units_metric` setting (L2b
  /// Landing C: the ONE expression both surfaces use, so they cannot disagree).
  ///
  /// TOTAL: a throwing read (a corrupt stored value, an account-swap window)
  /// answers centimetres and logs `measurement_unit_read_failed`, so a widget
  /// build or a sheet `initState` that calls it cannot throw.
  bool preferredInches() {
    try {
      return lastUnitInches() ?? !UserRepository.instance.getUnitsMetric();
    } catch (_) {
      unawaited(ErrorTelemetry.logEvent('measurement_unit_read_failed',
          message: 'stage=unit'));
      return false;
    }
  }
}

final measurementWriteProvider =
    NotifierProvider<MeasurementWriteNotifier, void>(
        MeasurementWriteNotifier.new);
