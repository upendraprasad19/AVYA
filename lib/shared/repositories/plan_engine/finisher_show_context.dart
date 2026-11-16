import 'dart:async';

import 'package:icanbefitter/core/services/error_telemetry.dart';

import '../user_repository.dart';
import 'finisher_safety.dart';
import 'plan_engine_flags.dart';

/// Unit 3C (OI-396, d78): the ONE I/O reader of the finisher display rule's inputs. Every screen and service that
/// shows or prices a stored finisher (both Train constructors, Home, the locked-week preview, `shortenDay`) calls
/// [read] ONCE per build and passes the result to `FinisherSafety.shownOfRow`; none reads the profile or the switch
/// for this itself. Kept apart from the pure `finisher_safety.dart` so the predicate tests need no Hive.
class FinisherShowContextReader {
  const FinisherShowContextReader._();

  /// The switch and the profile's injuries. Total: a read failure (no user session, a corrupt box) or NO profile (a
  /// device before its restore lands; B-pass seat A F1) gives `injured: true`, the safe side (only the bike finisher
  /// can show). Generation does not use this.
  static FinisherShowContext read() {
    try {
      final enabled = PlanEngineFlags.cardioFinisherShownEnabled;
      final profile = UserRepository.instance.getProfile();
      return FinisherShowContext(
        enabled: enabled,
        injured: profile == null || FinisherSafety.isInjured(profile['injuries']),
      );
    } catch (e, st) {
      // Once per process: this runs on every build, and a persistent failure must not flood telemetry.
      if (!_failureReported) {
        _failureReported = true;
        unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'finisher_show_context_read_failed'));
      }
      return const FinisherShowContext(enabled: true, injured: true);
    }
  }

  static bool _failureReported = false;
}
