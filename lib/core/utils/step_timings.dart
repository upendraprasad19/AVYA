// Step timings for one multi-step operation (OI-348 Landing 3a, B6).
//
// The sign-in / email-confirm account load took ~10 s on a phone (walk A1,
// 2026-11-22) and nothing said which cloud call was slow. One `StepTimings`
// rides through `_ensureLocalUser` and `hydrateFromCloud`; each `lap` records
// the milliseconds since the previous lap, and the summary becomes ONE
// `auth_ensure_timing` telemetry line per sign-in.
//
// Never throws in release: the name check is an `assert` (debug only), and
// nothing here touches I/O. Test: test/core/step_timings_test.dart.

class StepTimings {
  /// [elapsedMs] is a test seam (a fake clock); production uses a
  /// [Stopwatch] started here.
  StepTimings({int Function()? elapsedMs})
      : _elapsedMs = elapsedMs ?? _startedStopwatch();

  static int Function() _startedStopwatch() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMilliseconds;
  }

  // Reads the started Stopwatch, or the test's clock.
  final int Function() _elapsedMs;
  final Map<String, int> _laps = <String, int>{};
  int _lastMs = 0;

  /// Records the milliseconds since the previous lap (or since creation)
  /// under [name]. A name used twice adds up. Names are `[a-z_]+`.
  void lap(String name) {
    assert(RegExp(r'^[a-z_]+$').hasMatch(name), 'bad lap name: $name');
    final now = _elapsedMs();
    _laps[name] = (_laps[name] ?? 0) + (now - _lastMs);
    _lastMs = now;
  }

  /// Milliseconds since creation.
  int get totalMs => _elapsedMs();

  /// The laps in the order they were first recorded.
  Map<String, int> get laps => Map<String, int>.unmodifiable(_laps);

  /// `total=<ms> <name>=<ms> ...`: the total FIRST, so a length cap on the
  /// telemetry message cuts laps, never the total.
  String summary() {
    final out = StringBuffer('total=$totalMs');
    _laps.forEach((name, ms) => out.write(' $name=$ms'));
    return out.toString();
  }
}

/// Runs [body] and, whatever happens, reports [timings] exactly once through
/// [log] as `outcome=<ok|threw> total=<ms> <laps>`. The body's result is
/// returned and its error rethrown unchanged; a throwing [log] is swallowed,
/// so reporting can never change what the caller sees.
Future<T> runTimed<T>(
  StepTimings timings,
  Future<T> Function() body,
  void Function(String line) log,
) async {
  var outcome = 'threw';
  try {
    final result = await body();
    outcome = 'ok';
    return result;
  } finally {
    try {
      log('outcome=$outcome ${timings.summary()}');
    } catch (_) {
      // Reporting must never mask the body's own result or error.
    }
  }
}
