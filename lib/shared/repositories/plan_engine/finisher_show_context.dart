import '../user_repository.dart';
import 'finisher_safety.dart';
import 'plan_engine_flags.dart';

/// Unit 3C (OI-396, d78): the ONE I/O reader of the finisher display rule's inputs. Every screen and service that
/// shows or prices a stored finisher (both Train constructors, Home, the locked-week preview, `shortenDay`) calls
/// [read] ONCE per build and passes the result to `FinisherSafety.shownOfRow`; none reads the profile or the switch
/// for this itself. Kept apart from the pure `finisher_safety.dart` so the predicate tests need no Hive.
class FinisherShowContextReader {
  const FinisherShowContextReader._();

  /// The switch and the profile's injuries. Total: a read failure (no user session, a corrupt box) gives
  /// `enabled: true, injured: true`, the safe side (only the bike finisher can show). Generation does not use this.
  static FinisherShowContext read() {
    try {
      final enabled = PlanEngineFlags.cardioFinisherShownEnabled;
      final profile = UserRepository.instance.getProfile();
      return FinisherShowContext(
        enabled: enabled,
        injured: FinisherSafety.isInjured(profile?['injuries']),
      );
    } catch (_) {
      return const FinisherShowContext(enabled: true, injured: true);
    }
  }
}
