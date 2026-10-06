// test/helpers/spawn.dart
//
// The ONE way a test spawns a child process (class 2.56 + class 2.90).
//
// WHY. Two recurring defects lived in the ~50 hand-built `Process.run*(…)` call
// sites under test/:
//   1. ENVIRONMENT. `environment:` alone MERGES with the parent, and each test kept
//      its own hand-copied list of variables to strip, so the lists drifted: the
//      sweep test (contract_sweep_e2e_test.dart) filtered three families and
//      inherited CONTRACT_SWEEP_NESTED=1 from the very sweep that ran it, so 5 of
//      its 7 tests failed. Earlier instances: 4f2a9e, c3f8e1, d81f3c, d9e4b1.
//   2. FAILURE REPORT. A spawn test that asserts only an exit code prints
//      "Expected: <0> Actual: <1>" and hides the child's stderr (class 2.90).
//
// WHAT. Every spawn here (a) gets `scrubbedChildEnvironment` (scripts/
// regression_catalog_lib.dart, the ONE canonical list) plus the helper's own
// default removals, with `includeParentEnvironment: false`, and (b) reports the
// child's exit code, stdout and stderr through ONE choke point
// ([defaultSpawnReport]), so a failing assertion elsewhere in the test always has the
// child's output under it, whatever the next author remembers to write in `reason:`.
//
// WHAT THIS DOES NOT CLAIM. The child is not hermetic: variables an EXTERNAL tool
// reads (git's HOME / ~/.gitconfig, XDG_*) still flow unless a scenario removes or
// pins them. The completeness of the control-variable list is checked, two-way,
// by test/contracts/spawn_env_manifest_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show printOnFailure;

import '../../scripts/regression_catalog_lib.dart';

/// Removed from EVERY test-spawned child by default, on top of the canonical scrub.
///
/// `DART_BIN_OVERRIDE` is a LOCATOR, not a control switch: `scripts/_dart_bin.sh:85`
/// returns it before any PATH walk. The canonical scrub KEEPS it (the merge walk's
/// `flutter test` child contains tests that read it from their own process
/// environment to find dart), but a spawned SCRIPT under test must not inherit it:
/// a hook e2e that puts a stub `dart` first on PATH would otherwise be sent to the
/// REAL dart and silently run the whole gate loop in the real tree. A scenario whose
/// child legitimately needs the override re-supplies it through `extraEnv`, so a
/// scenario that forgets fails loudly on a machine that needs it, where a leaked
/// override fails silently on a machine that has one.
const Set<String> spawnDefaultRemovals = <String>{'DART_BIN_OVERRIDE'};

/// The child environment for a spawn: the parent, minus the canonical control
/// variables, minus the helper's default removals, minus [remove], plus [extra].
///
/// ORDER IS FIXED AND PINNED (spawn_helper_test.dart): scrub, helper defaults,
/// [remove], then [extra] last, so a scenario declares exactly what the child may
/// see (a scenario that sets `GIT_CONFIG_GLOBAL` after the strip works).
///
/// [remove] is case-insensitive and is how a scenario drops a variable the scrub
/// KEEPS (HOME, USERPROFILE). [parent] is a test seam: Dart cannot mutate its own
/// environment, so a poisoned parent can only be injected.
///
/// GUARD: a control variable in [extra] throws [ArgumentError] unless it is listed in
/// [allowControl]. Without it a whole-parent map passed as `extra`
/// (`{...Platform.environment, 'GIT_DIR': x}`) would silently put every control
/// variable back. Scenarios that set one deliberately (GIT_DIR,
/// GIT_CONFIG_GLOBAL, PRE_PUSH_FULL, CONTRACT_SWEEP_SKIP) name it. Honest limit: in a
/// CLEAN shell a whole-parent spread holds no control keys and passes.
Map<String, String> hermeticEnvironment({
  Map<String, String>? parent,
  Set<String> remove = const <String>{},
  Map<String, String> extra = const <String, String>{},
  Set<String> allowControl = const <String>{},
}) {
  final allowed = allowControl.map((k) => k.toUpperCase()).toSet();
  final undeclared = <String>[
    for (final k in extra.keys)
      if (isChildControlVariable(k) && !allowed.contains(k.toUpperCase())) k,
  ];
  if (undeclared.isNotEmpty) {
    throw ArgumentError(
        'hermeticEnvironment: `extra` carries control variable(s) $undeclared. '
        'Pass them in `allowControl` if the scenario sets them deliberately '
        '(otherwise a whole-parent map has put the leak back).');
  }
  final env = scrubbedChildEnvironment(parent ?? Platform.environment);
  final drop = <String>{
    ...spawnDefaultRemovals.map((k) => k.toUpperCase()),
    ...remove.map((k) => k.toUpperCase()),
  };
  env.removeWhere((k, _) => drop.contains(k.toUpperCase()));
  env.addAll(extra);
  return env;
}

/// `"$why\nexit=…\nstdout=…\nstderr=…"` (the PR #79 format): whole, no truncation.
/// A `List<int>` stream (a spawn with `stdoutEncoding: null`) is rendered as `N bytes`
/// plus its UTF-8 decode with malformed bytes allowed, so a raw-bytes site cannot crash
/// the reporter.
String spawnDiag(int exitCode, Object? stdout, Object? stderr, String why) =>
    '$why\nexit=$exitCode\nstdout=${_render(stdout)}\nstderr=${_render(stderr)}';

String _render(Object? v) {
  if (v is List<int>) {
    return '${v.length} bytes ${utf8.decode(v, allowMalformed: true)}';
  }
  return '$v';
}

/// The default failure report, the choke point.
///
/// Inside a test zone: `printOnFailure` (prints only if THAT test fails, buffers
/// silently otherwise). With NO current invoker (a spawn from `main()` at load time,
/// which nine test files do for `which dart`): `printOnFailure` throws
/// `StateError('There is no current invoker …')`, so print instead, and only when the
/// child failed, so a successful probe stays silent and a failed one is visible.
void defaultSpawnReport(String diag, int exitCode) {
  try {
    printOnFailure(diag);
  } on StateError {
    if (exitCode != 0) {
      // ignore: avoid_print
      print(diag);
    }
  }
}

/// Runs [exe] with a control-variable-clean environment, reports its output, returns
/// the result. ALWAYS `includeParentEnvironment: false`. [why] is required so a call
/// cannot be wired without a label. [report] receives the diagnostic text (a test seam,
/// so a test can SEE what would be printed); the default is [defaultSpawnReport].
///
/// The encodings are declared as defaulted parameters, not `?? systemEncoding`, so an
/// explicit `null` (raw bytes) survives.
ProcessResult runSpawn(
  String exe,
  List<String> args, {
  required String why,
  String? workingDirectory,
  Set<String> remove = const <String>{},
  Map<String, String> extraEnv = const <String, String>{},
  Set<String> allowControl = const <String>{},
  bool runInShell = false,
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
  Map<String, String>? parentEnvironment,
  void Function(String diag)? report,
}) {
  final result = Process.runSync(
    exe,
    args,
    workingDirectory: workingDirectory,
    environment: hermeticEnvironment(
        parent: parentEnvironment, remove: remove, extra: extraEnv, allowControl: allowControl),
    includeParentEnvironment: false,
    runInShell: runInShell,
    stdoutEncoding: stdoutEncoding,
    stderrEncoding: stderrEncoding,
  );
  reportSpawn(result.exitCode, result.stdout, result.stderr, why, report: report);
  return result;
}

/// [runSpawn]'s asynchronous twin (`Process.run`); keeps the raw-bytes `null` too.
Future<ProcessResult> runSpawnAsync(
  String exe,
  List<String> args, {
  required String why,
  String? workingDirectory,
  Set<String> remove = const <String>{},
  Map<String, String> extraEnv = const <String, String>{},
  Set<String> allowControl = const <String>{},
  bool runInShell = false,
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
  Map<String, String>? parentEnvironment,
  void Function(String diag)? report,
}) async {
  final result = await Process.run(
    exe,
    args,
    workingDirectory: workingDirectory,
    environment: hermeticEnvironment(
        parent: parentEnvironment, remove: remove, extra: extraEnv, allowControl: allowControl),
    includeParentEnvironment: false,
    runInShell: runInShell,
    stdoutEncoding: stdoutEncoding,
    stderrEncoding: stderrEncoding,
  );
  reportSpawn(result.exitCode, result.stdout, result.stderr, why, report: report);
  return result;
}

/// For the `Process.start` sites: a control-variable-clean child, and the caller
/// collects its output and then calls [reportSpawn]. The environment is the only thing
/// forced here; a start site that never collects stderr cannot be made to report by the
/// helper (the PR that migrates those sites lists each one).
Future<Process> startSpawn(
  String exe,
  List<String> args, {
  String? workingDirectory,
  Set<String> remove = const <String>{},
  Map<String, String> extraEnv = const <String, String>{},
  Set<String> allowControl = const <String>{},
  bool runInShell = false,
  ProcessStartMode mode = ProcessStartMode.normal,
  Map<String, String>? parentEnvironment,
}) {
  return Process.start(
    exe,
    args,
    workingDirectory: workingDirectory,
    environment: hermeticEnvironment(
        parent: parentEnvironment, remove: remove, extra: extraEnv, allowControl: allowControl),
    includeParentEnvironment: false,
    runInShell: runInShell,
    mode: mode,
  );
}

/// Reports one finished child through [report] (default: [defaultSpawnReport]). Called
/// by [runSpawn] / [runSpawnAsync] after the process ends, and by a `startSpawn` caller
/// after it has collected the child's output.
void reportSpawn(
  int exitCode,
  Object? stdout,
  Object? stderr,
  String why, {
  void Function(String diag)? report,
}) {
  final diag = spawnDiag(exitCode, stdout, stderr, why);
  if (report != null) {
    report(diag);
  } else {
    defaultSpawnReport(diag, exitCode);
  }
}

/// The Dart binary to spawn a runner with (the one shared copy of the `dartBinOf()`
/// that 13 test files carried).
///
/// NOT `Platform.resolvedExecutable`: under `flutter test` that resolves to the
/// flutter_tester binary, not dart, so the spawn never returns and the suite HANGS
/// rather than failing (test/scripts/oi_numbering_lib_test.dart:284 documents the
/// >10-minute hang). Honours `DART_BIN_OVERRIDE` read from the TEST process's own
/// environment (the test, unlike a spawned child, is allowed to read it); otherwise
/// prefers the SDK exe beside the Flutter wrapper (the wrapper takes the SDK update
/// lock and shells out to git on EVERY call) and falls back to `dart`.
String dartBin() {
  final override = Platform.environment['DART_BIN_OVERRIDE'];
  if (override != null && File(override).existsSync()) return override;
  final which = runSpawn(
    Platform.isWindows ? 'where' : 'which',
    ['dart'],
    why: 'dartBin: locate dart',
    stdoutEncoding: utf8,
  );
  if (which.exitCode == 0) {
    final first = (which.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) {
      final dir = File(first).parent.path.replaceAll(r'\', '/');
      for (final c in ['$dir/cache/dart-sdk/bin/dart.exe', '$dir/cache/dart-sdk/bin/dart']) {
        if (File(c).existsSync()) return c;
      }
    }
  }
  return 'dart';
}
