// OI-483: a Dart script that spawns dart contains the native-assets race the same way the shell
// side does (`_dart_run_retrying`, `run_dart_cli` in scripts/_dart_bin.sh; test/helpers/spawn.dart
// for the test suite). `dart run` rewrites <package>/.dart_tool/native_assets.yaml in place and every
// dart child reads the nearest one WALKING UP from its script, so a child that reads it empty exits
// 254 with "File not formatted as yaml: ." BEFORE `main`: re-running it repeats no side effect.
// Measured in docs/diagnoses/2026-11-06-spawn-status-native-assets-race-b7e2d9.md; plan
// docs/plans/2026-11-07-oi483-harness-dart-race.md.
//
// DEPENDENCY-FREE ON PURPOSE: `dart:io` only, pinned by test/scripts/dart_race_retry_lib_test.dart.
// git_safety_hook.dart deliberately does NOT import this file: a compile error in the guard's closure
// is 254, which the harness reads as "allow". Its one spawn is an advisory precheck.
//
// Same budget, same backoff and the same `[dart-run-retry]` note as the shell function; here the
// status AND the signature are visible, so both are required. Kill switch: AVYA_DART_RUN_RETRY=0,
// exactly `0`.

import 'dart:io';

/// Equal to the literal in scripts/_dart_bin.sh and to `nativeAssetsRaceSignature` in
/// test/helpers/spawn.dart (pinned). A Flutter bump that changes the text turns the canary red.
const String kNativeAssetsRaceSignature = 'File not formatted as yaml';
const int kNativeAssetsRaceStatus = 254;
const int kNativeAssetsRaceMaxRetries = 2;
const Duration kNativeAssetsRaceBackoff = Duration(seconds: 1);

bool isNativeAssetsRace(int status, String stderrText) =>
    status == kNativeAssetsRaceStatus && stderrText.contains(kNativeAssetsRaceSignature);

bool dartRaceRetryOff(Map<String, String> environment) => environment['AVYA_DART_RUN_RETRY'] == '0';

/// The shell function's note: one line after a leading newline, stderr flattened and cut at 300.
String dartRaceNote(int retry, String label, String stderrText) {
  final flat = stderrText.replaceAll('\n', ' ');
  final cut = flat.length > 300 ? flat.substring(0, 300) : flat;
  return '\n[dart-run-retry] native-assets race: retry $retry of $kNativeAssetsRaceMaxRetries | '
      '$label | exit=$kNativeAssetsRaceStatus | stderr=$cut';
}

/// Runs [attempt], and again (at most [kNativeAssetsRaceMaxRetries] more times) while its result is
/// the race. The last result is returned either way, so a caller's failure handling is unchanged.
/// [stop] ends the retry early (land_pr: an interrupt). [onNote] defaults to stderr: never stdout, a
/// hook's stdout is the JSON the harness parses. [backoff] and [environment] are test seams.
Future<T> retryDartRace<T>(
  Future<T> Function() attempt, {
  required int Function(T) statusOf,
  required String Function(T) stderrOf,
  required String label,
  void Function(String note)? onNote,
  Future<void> Function(Duration)? backoff,
  bool Function()? stop,
  Map<String, String>? environment,
}) async {
  final off = dartRaceRetryOff(environment ?? Platform.environment);
  bool stopped() => stop != null && stop();
  for (var n = 0;; n++) {
    final result = await attempt();
    final text = stderrOf(result);
    if (off || n >= kNativeAssetsRaceMaxRetries || !isNativeAssetsRace(statusOf(result), text) || stopped()) {
      return result;
    }
    final note = dartRaceNote(n + 1, label, text);
    if (onNote != null) {
      onNote(note);
    } else {
      stderr.writeln(note);
    }
    await (backoff ?? _delay)(kNativeAssetsRaceBackoff);
    if (stopped()) return result;
  }
}

/// [retryDartRace] for the common `Process.run` shape.
Future<ProcessResult> retryDartProcess(
  Future<ProcessResult> Function() attempt, {
  required String label,
  void Function(String note)? onNote,
  Future<void> Function(Duration)? backoff,
  Map<String, String>? environment,
}) =>
    retryDartRace<ProcessResult>(
      attempt,
      statusOf: (r) => r.exitCode,
      stderrOf: (r) => '${r.stderr}',
      label: label,
      onNote: onNote,
      backoff: backoff,
      environment: environment,
    );

Future<void> _delay(Duration d) => Future<void>.delayed(d);
