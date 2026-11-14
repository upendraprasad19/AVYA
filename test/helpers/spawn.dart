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
// RETRIES (OI-468, OI-311; docs/plans/2026-11-06-oi468-spawn-status.md). The three
// result-returning helpers ([runSpawn], [runSpawnAsync], [runSpawnWithInput]) run a
// child again, and say so, in exactly two cases where the HARNESS lost the child's
// answer:
//   1. NATIVE-ASSETS RACE (cause measured 2026-11-06). `dart run` rewrites
//      `<cwd package>/.dart_tool/native_assets.yaml` in place (truncate, then write) and
//      every `dart` child READS `<script's package>/.dart_tool/native_assets.yaml`
//      while it starts. A reader that opens the file inside another `dart run`'s
//      empty-file window exits 254 with `File not formatted as yaml: .`, BEFORE `main`
//      runs. Retried (at most twice) only when the child IS the dart executable
//      ([isDartExecutable]) AND the status is 254 AND stderr carries that text: a bare
//      254 is a compile error, and a `sh -c "work; dart run ..."` wrapper that forwards
//      a nested 254 could repeat the work it did first, so wrappers are not retried.
//   2. IMPOSSIBLE STATUS. A POSIX exit code above 255 or below -255 is not a process
//      status (two CI sightings, both from a quiet `git`; cause NOT established).
//      Retried once, for any child, never on Windows (codes above 255 are legitimate
//      there). For an idempotent child (git push, config, add) that cures it; for a
//      non-idempotent child whose first attempt really ran (git worktree add, git
//      commit) the second attempt fails with the child's own message or duplicates its
//      effect: a diagnostic, not an explanation.
// Every attempt is reported whole (attempt n>1 carries ` [attempt n]` on its label) and
// ONE `[spawn-retry]` line is printed with plain `print` before each retry runs, so the
// failed attempt's output survives a passing test (printOnFailure would drop it). The
// decision, the budgets and the note are pure ([spawnRetryDecision], [spawnRetryNote]).
// NOT covered: [startSpawn] callers (they drive the streams), children that are not the
// dart executable, nested spawns. TWO LIMITS of the covered path, stated so nobody has to
// find them: (a) "the child is dart" means "died before main" only for the dart process this
// helper started; a Dart SCRIPT that itself spawns a nested `dart run` and forwards its
// status and stderr is indistinguishable from the race and would be run again (no test
// spawns such a script today); (b) a stdin payload larger than the pipe buffer written to a
// child that already died on the race throws out of the stdin write, before any status is
// read, so that attempt is not retried (the same as before the retry existed; the payloads
// of the callers are small).
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

/// Why a finished child's result is the HARNESS's failure and not the child's answer
/// (see the RETRIES block in the header).
enum SpawnRetryReason { nativeAssetsRace, lostStatus }

/// The native-assets race is retried at most this many times, the impossible status at
/// most this many times; the two budgets are independent (worst case 4 attempts).
const int spawnRaceRetryCap = 2;
const int spawnLostStatusRetryCap = 1;

/// The front end's own text when it reads an empty `.dart_tool/native_assets.yaml`.
const String nativeAssetsRaceSignature = 'File not formatted as yaml';

const int _noteExcerptLength = 300;

/// True when [exe] is the Dart binary itself: its basename (split on `/` and `\`),
/// lower-cased, minus ONE trailing `.exe` / `.bat` / `.cmd`, is `dart`. `sh`, `git`,
/// `mydart`, `dart-wrapper`, `dart.exe.exe`, an empty string and a path that ends in a
/// separator are not. The native-assets retry is scoped to this: only the dart process
/// is known to die before `main` runs.
bool isDartExecutable(String exe) {
  var base = exe.split(RegExp(r'[\\/]')).last.toLowerCase();
  for (final ext in const <String>['.exe', '.bat', '.cmd']) {
    if (base.endsWith(ext)) {
      base = base.substring(0, base.length - ext.length);
      break;
    }
  }
  return base == 'dart';
}

String _decoded(Object? v) => v is List<int> ? utf8.decode(v, allowMalformed: true) : '$v';

/// The whole retry decision, pure. [raceRetriesUsed] / [lostStatusRetriesUsed] are how many
/// retries of each reason already ran for THIS spawn. An impossible status (outside
/// -255..255, never on Windows) is checked first and may be any child; the race needs the
/// dart executable, exit code exactly 254 AND the signature in the decoded stderr (the
/// stderr is only decoded when the first two hold).
SpawnRetryReason? spawnRetryDecision({
  required String exe,
  required int exitCode,
  required Object? stderr,
  required int raceRetriesUsed,
  required int lostStatusRetriesUsed,
  required bool isWindows,
}) {
  if (!isWindows && (exitCode > 255 || exitCode < -255)) {
    return lostStatusRetriesUsed < spawnLostStatusRetryCap ? SpawnRetryReason.lostStatus : null;
  }
  if (exitCode == 254 && isDartExecutable(exe) && _decoded(stderr).contains(nativeAssetsRaceSignature)) {
    return raceRetriesUsed < spawnRaceRetryCap ? SpawnRetryReason.nativeAssetsRace : null;
  }
  return null;
}

/// The ONE `[spawn-retry]` line, pure. [k] is the retry about to run for [reason] and [cap]
/// that reason's budget; [why] is the spawn's own label (no attempt suffix); [ms] the failed
/// attempt's own time. `<len>` is the UTF-16 code-unit count of a String and the byte count
/// of a `List<int>`; the excerpt is the decoded text with `\r` and `\n` escaped FIRST and the
/// first 300 code units taken after that, so the line stays one line for CR and LF.
/// LIMITS (cosmetic, a diagnostic line): a literal backslash is not escaped, so the two
/// characters `\n` in a child's text read like an escaped newline; U+2028 and U+0085 are not
/// escaped; the cut can land on a lone `\` or inside a surrogate pair.
String spawnRetryNote({
  required SpawnRetryReason reason,
  required int k,
  required int cap,
  required String why,
  required int exitCode,
  required Object? stdout,
  required Object? stderr,
  required int ms,
}) {
  String oneLine(String s) => s.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
  String slot(Object? v) {
    final text = _decoded(v);
    final len = v is List<int> ? v.length : text.length;
    final escaped = oneLine(text);
    final cut = escaped.length > _noteExcerptLength ? escaped.substring(0, _noteExcerptLength) : escaped;
    return '($len)=$cut';
  }

  final label = reason == SpawnRetryReason.nativeAssetsRace ? 'native-assets-race' : 'lost-status';
  return '[spawn-retry] $label retry $k of $cap ${oneLine(why)} '
      '| exit=$exitCode (0x${exitCode.toUnsigned(32).toRadixString(16)}) '
      '| $ms ms | stdout${slot(stdout)} | stderr${slot(stderr)}';
}

void _defaultNote(String line) {
  // ignore: avoid_print
  print(line);
}

/// The retry loop of [runSpawn]: [once] performs ONE attempt (the raw spawn lives in the
/// caller's closure). Each attempt is timed with [clock], reported whole through
/// [reportSpawn] (attempt n>1 gets ` [attempt n]` on its label), then judged by
/// [spawnRetryDecision]; a retry prints [note] BEFORE it runs. Returns the LAST result.
/// [isWindows] and [clock] are test seams the public entry points never set; [note] is
/// forwarded from their own `note:` parameter.
ProcessResult retryingSpawn(
  ProcessResult Function() once, {
  required String exe,
  required String why,
  void Function(String diag)? report,
  void Function(String line)? note,
  bool? isWindows,
  DateTime Function()? clock,
}) {
  final now = clock ?? DateTime.now;
  final windows = isWindows ?? Platform.isWindows;
  final emit = note ?? _defaultNote;
  var race = 0;
  var lost = 0;
  var attempt = 1;
  while (true) {
    final started = now();
    final result = once();
    final ms = now().difference(started).inMilliseconds;
    reportSpawn(result.exitCode, result.stdout, result.stderr, attempt == 1 ? why : '$why [attempt $attempt]',
        report: report);
    final reason = spawnRetryDecision(
        exe: exe,
        exitCode: result.exitCode,
        stderr: result.stderr,
        raceRetriesUsed: race,
        lostStatusRetriesUsed: lost,
        isWindows: windows);
    if (reason == null) return result;
    final int k;
    final int cap;
    if (reason == SpawnRetryReason.nativeAssetsRace) {
      race++;
      k = race;
      cap = spawnRaceRetryCap;
    } else {
      lost++;
      k = lost;
      cap = spawnLostStatusRetryCap;
    }
    emit(spawnRetryNote(
        reason: reason,
        k: k,
        cap: cap,
        why: why,
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        ms: ms));
    attempt++;
  }
}

/// [retryingSpawn]'s asynchronous twin, generic over the result type (a `ProcessResult` for
/// [runSpawnAsync], a record for [runSpawnWithInput]); the accessors read the three fields.
Future<T> retryingSpawnAsync<T>(
  Future<T> Function() once, {
  required int Function(T result) exitCodeOf,
  required Object? Function(T result) stdoutOf,
  required Object? Function(T result) stderrOf,
  required String exe,
  required String why,
  void Function(String diag)? report,
  void Function(String line)? note,
  bool? isWindows,
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  final windows = isWindows ?? Platform.isWindows;
  final emit = note ?? _defaultNote;
  var race = 0;
  var lost = 0;
  var attempt = 1;
  while (true) {
    final started = now();
    final result = await once();
    final ms = now().difference(started).inMilliseconds;
    final code = exitCodeOf(result);
    final out = stdoutOf(result);
    final err = stderrOf(result);
    reportSpawn(code, out, err, attempt == 1 ? why : '$why [attempt $attempt]', report: report);
    final reason = spawnRetryDecision(
        exe: exe,
        exitCode: code,
        stderr: err,
        raceRetriesUsed: race,
        lostStatusRetriesUsed: lost,
        isWindows: windows);
    if (reason == null) return result;
    final int k;
    final int cap;
    if (reason == SpawnRetryReason.nativeAssetsRace) {
      race++;
      k = race;
      cap = spawnRaceRetryCap;
    } else {
      lost++;
      k = lost;
      cap = spawnLostStatusRetryCap;
    }
    emit(spawnRetryNote(
        reason: reason, k: k, cap: cap, why: why, exitCode: code, stdout: out, stderr: err, ms: ms));
    attempt++;
  }
}

/// Runs [exe] with a control-variable-clean environment, reports its output, returns
/// the result. ALWAYS `includeParentEnvironment: false`. [why] is required so a call
/// cannot be wired without a label. [report] receives the diagnostic text (a test seam,
/// so a test can SEE what would be printed); the default is [defaultSpawnReport]. A child
/// that lost its answer to the harness is run again, see the RETRIES block in the header;
/// [note] receives each `[spawn-retry]` line (default: `print`).
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
  void Function(String line)? note,
}) {
  return retryingSpawn(
    () => Process.runSync(
      exe,
      args,
      workingDirectory: workingDirectory,
      environment: hermeticEnvironment(
          parent: parentEnvironment, remove: remove, extra: extraEnv, allowControl: allowControl),
      includeParentEnvironment: false,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    ),
    exe: exe,
    why: why,
    report: report,
    note: note,
  );
}

/// [runSpawn]'s asynchronous twin (`Process.run`); keeps the raw-bytes `null` too, and the
/// same retries and [note] seam.
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
  void Function(String line)? note,
}) {
  return retryingSpawnAsync<ProcessResult>(
    () => Process.run(
      exe,
      args,
      workingDirectory: workingDirectory,
      environment: hermeticEnvironment(
          parent: parentEnvironment, remove: remove, extra: extraEnv, allowControl: allowControl),
      includeParentEnvironment: false,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    ),
    exitCodeOf: (r) => r.exitCode,
    stdoutOf: (r) => r.stdout,
    stderrOf: (r) => r.stderr,
    exe: exe,
    why: why,
    report: report,
    note: note,
  );
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

/// The "write stdin, close, drain both streams, wait, report" idiom (PR 2 of batch
/// spawn-tests-env-and-stderr; 14 `Process.start` sites repeated it by hand).
///
/// [stdin] is a `String` (written) or a `List<int>` (ADDED as raw bytes: two review-gate
/// tests feed `git hash-object --stdin` bytes that are not valid text); anything else
/// throws [ArgumentError]. stdout and stderr are drained CONCURRENTLY, so a child that
/// fills one pipe before reading its stdin cannot deadlock the test; the output is
/// decoded with [stdoutEncoding] / [stderrEncoding] (`null` means UTF-8 with malformed
/// bytes allowed). No `try/catch` around the stdin write: a site that tests a broken
/// pipe or a kill keeps [startSpawn]. The same retries and [note] seam as [runSpawn]; the
/// stdin is written again on every attempt.
Future<({int exitCode, String stdout, String stderr})> runSpawnWithInput(
  String exe,
  List<String> args, {
  required String why,
  required Object stdin,
  String? workingDirectory,
  Set<String> remove = const <String>{},
  Map<String, String> extraEnv = const <String, String>{},
  Set<String> allowControl = const <String>{},
  bool runInShell = false,
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
  Map<String, String>? parentEnvironment,
  void Function(String diag)? report,
  void Function(String line)? note,
}) async {
  if (stdin is! String && stdin is! List<int>) {
    throw ArgumentError.value(stdin, 'stdin', 'runSpawnWithInput: stdin must be a String or a List<int>');
  }
  // One attempt: spawn, feed stdin, drain both pipes, wait, decode. The stdin is written
  // again on every attempt (a child that died in the front end never read it). Reporting
  // and the retry decision live in retryingSpawnAsync.
  Future<({int exitCode, String stdout, String stderr})> once() async {
    final process = await startSpawn(
      exe,
      args,
      workingDirectory: workingDirectory,
      remove: remove,
      extraEnv: extraEnv,
      allowControl: allowControl,
      runInShell: runInShell,
      parentEnvironment: parentEnvironment,
    );
    Future<List<int>> collect(Stream<List<int>> s) => s.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    final outF = collect(process.stdout);
    final errF = collect(process.stderr);
    if (stdin is String) {
      process.stdin.write(stdin);
    } else {
      process.stdin.add(stdin as List<int>);
    }
    await process.stdin.close();
    final outBytes = await outF;
    final errBytes = await errF;
    final code = await process.exitCode;
    String decode(Encoding? enc, List<int> bytes) =>
        enc == null ? utf8.decode(bytes, allowMalformed: true) : enc.decode(bytes);
    return (exitCode: code, stdout: decode(stdoutEncoding, outBytes), stderr: decode(stderrEncoding, errBytes));
  }

  return retryingSpawnAsync<({int exitCode, String stdout, String stderr})>(
    once,
    exitCodeOf: (r) => r.exitCode,
    stdoutOf: (r) => r.stdout,
    stderrOf: (r) => r.stderr,
    exe: exe,
    why: why,
    report: report,
    note: note,
  );
}

/// Reports one finished child through [report] (default: [defaultSpawnReport]). Called
/// by the retry loops ([retryingSpawn], [retryingSpawnAsync]) after each attempt, and by a
/// `startSpawn` caller after it has collected the child's output.
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
  final which = runSpawn(
    Platform.isWindows ? 'where' : 'which',
    ['dart'],
    why: 'dartBin: locate dart',
    stdoutEncoding: utf8,
  );
  return dartBinFrom(
    override: override,
    whichStdout: which.exitCode == 0 ? which.stdout as String : '',
    fileExists: (path) => File(path).existsSync(),
  );
}

/// The decision inside [dartBin], pure so a test can feed it the layouts that differ between
/// machines. [whichStdout] is what `which dart` / `where dart` printed ('' when it failed).
///
/// Order: an existing [override]; the real SDK exe beside the Flutter wrapper `which` found;
/// the ABSOLUTE path `which` found; a bare `dart`. The third step is the CI fix (PR 1 of batch
/// spawn-tests-env-and-stderr, run 37431225458): where the SDK cache is not beside the wrapper
/// the old code returned a bare `dart`, which a child spawned with a minimal environment (no
/// PATH) cannot resolve ("ProcessException: No such file or directory"), while on the
/// developer's machine `dart` happened to sit on the default path and hid it.
String dartBinFrom({
  required String? override,
  required String whichStdout,
  required bool Function(String path) fileExists,
}) {
  if (override != null && fileExists(override)) return override;
  final first = whichStdout.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (first.isEmpty) return 'dart';
  final dir = first.replaceAll(r'\', '/');
  final bin = dir.contains('/') ? dir.substring(0, dir.lastIndexOf('/')) : '.';
  for (final c in ['$bin/cache/dart-sdk/bin/dart.exe', '$bin/cache/dart-sdk/bin/dart']) {
    if (fileExists(c)) return c;
  }
  return first;
}
