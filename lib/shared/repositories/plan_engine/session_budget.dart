/// Batch B2 (docs/plans/2026-10-22-session-set-budget.md): the session set
/// budget. Behind `PlanEngineFlags.sessionSetBudgetEnabled` (ship-dark, default
/// OFF) a generated session's size follows the user's minutes and evidence-based
/// caps instead of a fixed exercise count.
///
/// Pure Dart: no Hive, no repository, no flag read. Callers pass everything in,
/// so the engine stays deterministic and every rule is testable on its own.
/// This file grows task by task; Task 0 is the minutes resolution only.
class SessionBudget {
  SessionBudget._();

  /// The minutes a session is budgeted at when nothing says otherwise (founder
  /// decision F2: an empty `session_duration_minutes` means 60, no new
  /// onboarding question).
  static const int defaultMinutes = 60;

  /// The range of minutes a caller or a saved profile may ask for. The Edit
  /// Profile screen offers 30 / 45 / 60 / 90; the wider range tolerates a value
  /// restored from an older client without ever feeding the model nonsense.
  static const int minMinutes = 15;
  static const int maxMinutes = 180;

  /// The session length to use, in minutes.
  ///
  /// 1. [param] if it is in [minMinutes]..[maxMinutes];
  /// 2. else [profileValue], if it is a finite number that rounds into that
  ///    range (a JSON double such as `90.0` is a number, a string is not);
  /// 3. else [defaultMinutes].
  ///
  /// Never throws: every input class lands on a usable number.
  static int resolveMinutes({int? param, Object? profileValue}) {
    if (param != null && param >= minMinutes && param <= maxMinutes) {
      return param;
    }
    if (profileValue is num) {
      final v = profileValue.toDouble();
      // Range-check BEFORE rounding: a huge finite double must not reach
      // `round()`, and `x.5` rounds up so the bounds are 14.5 and 180.5.
      if (v.isFinite && v >= minMinutes - 0.5 && v < maxMinutes + 0.5) {
        return v.round();
      }
    }
    return defaultMinutes;
  }

  /// The Edit Profile screen's initial session length for a stored [profile]
  /// map (Ruling 7: 60, no longer 90, when the field is missing). Reads the same
  /// field the generator reads, through the same resolution, so the screen and
  /// the plan can never disagree about what an empty value means.
  static int initialSessionDuration(Map<dynamic, dynamic> profile) =>
      resolveMinutes(profileValue: profile['session_duration_minutes']);
}
