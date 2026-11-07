@Timeout(Duration(minutes: 12))
library;

// Diagnose 8f3e35 (OI-384). Claude Code runs a project hook in the session's
// CURRENT directory, which follows the Bash tool's persistent `cd`. The hooks
// in .claude/settings.json were registered as `dart run scripts/<name>.dart`,
// so from a subdirectory dart printed "Could not find file" and exited 255 —
// a NON-blocking error — and every hook, the git-safety guard included, was
// silently skipped. Each command now resolves the checkout that holds its
// script first (plan docs/plans/hook-cwd-fail-open.md, 2.1).
//
// Structure (plan 3.1): every behaviour check is a function of a COMMAND
// STRING that returns its violations. The real tests apply the checks to the
// commands in .claude/settings.json; the META tests apply the same checks to
// synthetic mutants of the template and require each mutant to fail its NAMED
// check, so the kills are part of the suite. `setUpAll` checks SAFETY only (no
// command may run a real program here), never shape, so a mutated settings
// file still reaches the behaviour assertions.
//
// A stub `dart` is first on PATH: it records its cwd, its last argument,
// whether that file exists, and its stdin, then exits with a baked-in code.
// No real hook runs, except C11, which runs the real git-safety hook once on
// purpose. That hook DOES run git against the payload `cwd`: it waives a raw
// commit while MERGE_HEAD / CHERRY_PICK_HEAD / REVERT_HEAD exists there
// (git_safety_hook.dart, mergeInProgress). So C11's payload `cwd` is the
// non-repo fixture, never the live repo, or C11 would go red during every
// merge commit, when pre-commit's regression-catalog walk runs this file
// (same trap as b7e4c2, `neutralCwd` in git_safety_hook_integration_test).
//
// OI-483: each command now runs dart through `_dart_run_retrying` when the checkout's helper can
// be sourced, and through today's call otherwise. Exit 2 BLOCKS a tool call and any other status
// lets it through, so a helper must not be able to change the outcome in either direction: the
// source happens in a PROBE subshell first (C14 is the table of what a helper can do; ground truth
// 10 of docs/plans/2026-11-07-oi483-harness-dart-race.md).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

/// The nine (event, matcher, script) registrations, exactly (plan F1).
const _expectedHooks = <(String, String?, String)>[
  ('SessionStart', null, 'check_alerts.dart'),
  ('SessionStart', null, 'discipline_hook.dart'),
  ('SessionStart', null, 'reconcile_ci.dart'),
  ('UserPromptSubmit', null, 'discipline_hook.dart'),
  ('PreToolUse', 'Skill', 'discipline_hook.dart'),
  ('PreToolUse', 'Bash', 'git_safety_hook.dart'),
  ('PreToolUse', 'Write|Edit', 'memory_write_guard_hook.dart'),
  ('Stop', null, 'batch_close_hook.dart'),
  ('SessionEnd', null, 'session_release.dart'),
];

/// OI-483: the retry fragment. Accepted by the SAFETY rule ONLY as this exact string.
/// The probe says yes only by printing `ok`, so no exit status of the helper reads as success. The `;` after the `.` and
/// the plain assignment keep the source out of an `&&` list and an `if` condition, where `set -e` is ignored.
const retryHead = 'DART_BIN=dart; p=\$( (. scripts/_dart_bin.sh; use_dart_race_retry && echo ok) 2>/dev/null); '
    'if [ "\$p" = ok ]; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; ';

/// The 2.1 template plus [retryHead]. `check_alerts.dart` has always run without flags.
String hookTemplate(String script) {
  final flags = script == 'check_alerts.dart' ? '' : '--verbosity=error ';
  return r'r=$(git rev-parse --show-toplevel 2>/dev/null); '
      '[ -n "\$r" ] && [ -f "\$r/scripts/$script" ] || '
      r'r="${CLAUDE_PROJECT_DIR:-.}"; cd "$r" || exit 1; '
      '$retryHead"\$DART_BIN" run ${flags}scripts/$script';
}

typedef HookEntry = ({String event, String? matcher, String command});

List<HookEntry> loadHooks(String root) {
  final parsed = jsonDecode(File('$root/.claude/settings.json').readAsStringSync())
      as Map<String, dynamic>;
  final hooks = parsed['hooks'] as Map<String, dynamic>;
  return [
    for (final event in hooks.entries)
      for (final group in event.value as List<dynamic>)
        for (final hook in ((group as Map<String, dynamic>)['hooks'] as List<dynamic>))
          (
            event: event.key,
            matcher: group['matcher'] as String?,
            command: (hook as Map<String, dynamic>)['command'] as String,
          ),
  ];
}

/// The script a hook command runs (`scripts/<name>.dart` after `dart run`).
String? scriptOf(String command) =>
    RegExp(r'(?:dart|"\$DART_BIN") run (?:--verbosity=error )?scripts/([a-z_]+\.dart)')
        .firstMatch(command)
        ?.group(1);

// ── Safety (setUpAll): may this command be executed here at all? ──────────

final _gitSubst = RegExp(r'\$\(git rev-parse --[a-z-]+ 2>/dev/null\)');
final _assignOk = RegExp(
    r'^r=(?:__GITREV__|"\$\{CLAUDE_PROJECT_DIR(?::-\.)?\}"|"\$\{r%[^}"`$]*\}"|"?\.?"?)$');
final _dartRun = RegExp(r'^dart run (?:--verbosity=error )?scripts/[a-z_]+\.dart(?: </dev/null)?$');

/// Violations of the plan 3.1 safety rule. Empty means the command only uses
/// git rev-parse, `[`, `cd`, `exit`, `true`, an `r=` assignment and
/// `dart run scripts/<name>.dart` (the stub), so executing it here cannot run
/// a real program. [retryHead] is removed first, as one exact string, and `"$DART_BIN" run` reads
/// as `dart run`, so every other segment still goes through this rule and an altered head does not
/// pass. [alsoAllow] admits one more literal, for a META mutant of the fragment and nothing else.
List<String> safetyViolations(String command, {String? alsoAllow}) {
  final out = <String>[];
  var text = command.replaceAll(_gitSubst, '__GITREV__');
  if (alsoAllow != null) text = text.replaceAll(alsoAllow, '');
  text = text.replaceAll(retryHead, '').replaceAll('"\$DART_BIN" run', 'dart run');
  if (text.contains(r'$(') || text.contains('`')) {
    out.add('a command substitution other than `git rev-parse --<flag>`');
  }
  // A newline, carriage return or lone `&` starts a command the `;`/`&&`/`||`
  // split below would never classify (B-pass 2026-10-21).
  if (text.contains('\n') || text.contains('\r')) {
    out.add('a newline or carriage return');
  }
  if (RegExp(r'(?<!&)&(?!&)').hasMatch(text)) out.add('a lone `&`');
  for (final m in RegExp(r'\d*[<>]+\S*').allMatches(text)) {
    if (m.group(0) != '</dev/null') out.add('redirection ${m.group(0)}');
  }
  var sawDart = false;
  for (final raw in text.split(RegExp(r';|&&|\|\|'))) {
    final seg = raw.trim();
    if (seg.isEmpty) continue;
    if (seg.contains('|')) {
      out.add('a pipe in `$seg`');
      continue;
    }
    final first = seg.split(RegExp(r'\s+')).first;
    if (first.startsWith('r=')) {
      if (!_assignOk.hasMatch(seg)) out.add('assignment `$seg`');
    } else if (first == 'dart') {
      if (_dartRun.hasMatch(seg)) {
        sawDart = true;
      } else {
        out.add('dart invocation `$seg`');
      }
    } else if (!const {'[', 'cd', 'exit', 'true'}.contains(first)) {
      out.add('program `$first`');
    }
  }
  if (!sawDart) out.add('no `dart run scripts/<name>.dart` segment');
  return out;
}

// ── The stub-dart runner ─────────────────────────────────────────────────

class StubRun {
  StubRun(this.exitCode, this.stdout, this.stderr, this.ran, this.cwd, this.lastArg,
      this.found, this.stdin, this.calls, this.backoffs);
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool ran;
  final String? cwd;
  final String? lastArg;
  final bool? found;
  final String? stdin;
  final int calls; // how many times the stub dart started
  final int backoffs; // how many times the `sleep` stub ran
}

/// Fixtures shared by every check (built in setUpAll).
class Fx {
  Fx(this.base, this.a, this.d, this.w, this.x, this.nested, this.ceiling, this.hostile);
  final Directory base;
  final String a; // checkout A (resolved), holds every hook script
  final String d; // decoy checkout, used as CLAUDE_PROJECT_DIR
  final String w; // linked worktree of A
  final String x; // a non-repo directory
  final String nested; // a nested `git init` inside A, no scripts/
  final String ceiling; // GIT_CEILING_DIRECTORIES
  final String hostile; // a repo whose helper each check writes itself
}

/// The fixture the checks use: [fxHelper] (the real helper in every checkout, the retry path) or
/// [fxBare] (no helper anywhere, today's call).
late Fx fx;
late Fx fxHelper;
late Fx fxBare;
var _fxReady = false;
const raceStderr = 'File not formatted as yaml: .';
const _payload = '{"probe":"8f3e35","tool_name":"Bash"}';
const shells = ['/bin/sh', '/bin/bash'];

bool get shIsDash {
  try {
    return File('/bin/sh').resolveSymbolicLinksSync().endsWith('dash');
  } catch (_) {
    return false;
  }
}

/// `runSpawnWithInput` for a child that may exit WITHOUT reading its stdin. Mutant M9
/// redirects the stub's stdin from /dev/null, so the shell can be gone before the harness
/// writes the payload; the write then fails with a broken pipe, which on a loaded machine
/// reddened a different, innocent test (the helper deliberately has no try/catch around the
/// stdin write, its doc sends such a site to `startSpawn`). A closed pipe is the EXPECTED
/// outcome here: the checks read what the stub recorded, never whether the write landed.
Future<({int exitCode, String stdout, String stderr})> _runSpawnClosedStdinOk(
  String exe,
  List<String> args, {
  required String why,
  required String stdin,
  String? workingDirectory,
  Set<String> remove = const <String>{},
  Map<String, String> extraEnv = const <String, String>{},
  Set<String> allowControl = const <String>{},
}) async {
  final process = await startSpawn(
    exe,
    args,
    workingDirectory: workingDirectory,
    remove: remove,
    extraEnv: extraEnv,
    allowControl: allowControl,
  );
  Future<List<int>> collect(Stream<List<int>> s) => s.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
  final outF = collect(process.stdout);
  final errF = collect(process.stderr);
  // The sink reports a broken pipe on `done` as well as on `close()`: absorb both.
  unawaited(process.stdin.done.then<void>((_) {}, onError: (Object _) {}));
  try {
    process.stdin.write(stdin);
    await process.stdin.close();
  } on SocketException {
    // The child exited first.
  }
  final out = utf8.decode(await outF, allowMalformed: true);
  final err = utf8.decode(await errF, allowMalformed: true);
  final code = await process.exitCode;
  reportSpawn(code, out, err, why, report: (_) {});
  return (exitCode: code, stdout: out, stderr: err);
}

/// Runs [command] under [shell] from [cwd] with a FRESH stub `dart` first on
/// PATH (one stub and record directory per spawn).
Future<StubRun> runWithStub(
  String command, {
  required String shell,
  required String cwd,
  String? projectDir,
  int stubExit = 0,
  String stdin = _payload,
  int loseRaces = 0, // the first N calls exit 254 + the signature WITHOUT reading stdin, as real dart does
  String stubStderr = '',
  Map<String, String> env = const {},
}) async {
  final stub = Directory.systemTemp.createTempSync('hook_stub_');
  try {
    final bin = Directory('${stub.path}/bin')..createSync();
    final rec = Directory('${stub.path}/rec')..createSync();
    final dart = File('${bin.path}/dart')
      ..writeAsStringSync('#!/bin/sh\n'
          "rec='${rec.path}'\n"
          r'n=$(cat "$rec/calls" 2>/dev/null || echo 0); echo $((n + 1)) > "$rec/calls"' '\n'
          'if [ "\$n" -lt $loseRaces ]; then echo \'$raceStderr\' >&2; exit 254; fi\n'
          r'pwd -P > "$rec/cwd"' '\n'
          r'last=""; for a in "$@"; do last=$a; done' '\n'
          r'printf %s "$last" > "$rec/last"' '\n'
          r'if [ -f "$last" ]; then echo FOUND > "$rec/found"; '
          r'else echo MISSING > "$rec/found"; fi' '\n'
          r'cat > "$rec/stdin"' '\n'
          'echo STUB-OUT\n'
          '${stubStderr.isEmpty ? '' : "echo '$stubStderr' >&2\n"}'
          'exit $stubExit\n');
    // The retry's 1 s backoff, logged and skipped.
    final sleep = File('${bin.path}/sleep')
      ..writeAsStringSync('#!/bin/sh\necho "\$1" >> \'${rec.path}/backoffs\'\n');
    final chmod = runSpawn('chmod', ['+x', dart.path, sleep.path], why: 'chmod the stub dart');
    expect(chmod.exitCode, 0, reason: 'chmod of the stub dart failed');

    final r = await _runSpawnClosedStdinOk(
      shell,
      ['-c', command],
      why: 'hook command under $shell from $cwd',
      stdin: stdin,
      workingDirectory: cwd,
      remove: projectDir == null ? const {'CLAUDE_PROJECT_DIR'} : const {},
      extraEnv: {
        'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
        'GIT_CEILING_DIRECTORIES': fx.ceiling,
        'CLAUDE_PROJECT_DIR': ?projectDir,
        ...env,
      },
      allowControl: const {'GIT_CEILING_DIRECTORIES', 'AVYA_DART_RUN_RETRY'},
    ).timeout(const Duration(seconds: 60));

    String? read(String name) {
      final f = File('${rec.path}/$name');
      return f.existsSync() ? f.readAsStringSync() : null;
    }

    final cwdRec = read('cwd')?.trim();
    final found = read('found')?.trim();
    final calls = int.tryParse(read('calls')?.trim() ?? '') ?? 0;
    final backoffs = '\n'.allMatches(read('backoffs') ?? '').length;
    return StubRun(r.exitCode, r.stdout, r.stderr, cwdRec != null, cwdRec, read('last'),
        found == null ? null : found == 'FOUND', read('stdin'), calls, backoffs);
  } finally {
    stub.deleteSync(recursive: true);
  }
}

// ── Behaviour checks: each returns its violations ───────────────────────

/// C3: from a subdirectory (and from the checkout itself) the hook runs from
/// the checkout root, with the right script, the payload on stdin, exit 0.
Future<List<String>> checkSubdir(String command, String script,
    {required String shell, required String checkout}) async {
  final out = <String>[];
  for (final from in ['$checkout/sub dir', checkout]) {
    final r = await runWithStub(command, shell: shell, cwd: from);
    if (!r.ran) {
      out.add('[$from] the stub never ran (exit ${r.exitCode}, ${r.stderr.trim()})');
      continue;
    }
    if (r.found != true) out.add('[$from] script MISSING from cwd ${r.cwd}');
    if (r.lastArg != 'scripts/$script') out.add('[$from] ran ${r.lastArg}');
    if (r.cwd != checkout) out.add('[$from] cwd ${r.cwd}, want $checkout');
    if (r.stdin != _payload) out.add('[$from] stdin "${r.stdin}"');
    if (r.exitCode != 0) out.add('[$from] exit ${r.exitCode}');
  }
  return out;
}

/// C4: outside any repository, `CLAUDE_PROJECT_DIR` is the fallback.
Future<List<String>> checkFallback(String command, {required String shell}) async {
  final r = await runWithStub(command, shell: shell, cwd: fx.x, projectDir: fx.d);
  return [
    if (!r.ran) 'the stub never ran',
    if (r.ran && r.found != true) 'MISSING (cwd ${r.cwd})',
    if (r.ran && r.cwd != fx.d) 'cwd ${r.cwd}, want the fallback ${fx.d}',
  ];
}

/// C4b: no repository and no `CLAUDE_PROJECT_DIR`: today's behaviour (the
/// stub runs in the current directory, finds nothing, its exit is the hook's).
Future<List<String>> checkNoFallback(String command, {required String shell}) async {
  final r = await runWithStub(command, shell: shell, cwd: fx.x, stubExit: 0);
  return [
    if (!r.ran) 'the stub never ran',
    if (r.ran && r.cwd != fx.x) 'cwd ${r.cwd}, want ${fx.x}',
    if (r.ran && r.found != false) 'expected MISSING',
    if (r.exitCode != 0) 'exit ${r.exitCode}',
  ];
}

/// C5: the hook's exit code is dart's: 2 still blocks.
Future<List<String>> checkExitCode(String command, {required String shell}) async {
  final out = <String>[];
  for (final code in [2, 0, 1]) {
    final r = await runWithStub(command,
        shell: shell, cwd: '${fx.a}/sub dir', stubExit: code);
    if (r.exitCode != code) out.add('stub exited $code, hook exited ${r.exitCode}');
  }
  return out;
}

/// C6: a root that cannot be entered is a NON-blocking error (exactly 1),
/// never dash's 2, and dart is not run against the wrong directory.
Future<List<String>> checkMissingRoot(String command, {required String shell}) async {
  final r = await runWithStub(command,
      shell: shell, cwd: fx.x, projectDir: '${fx.x}/missing dir', stdin: '');
  return [
    if (r.exitCode != 1) 'exit ${r.exitCode}, want exactly 1',
    if (r.ran) 'the stub ran (from ${r.cwd})',
  ];
}

/// C7: the checkout of the current directory beats `CLAUDE_PROJECT_DIR`.
Future<List<String>> checkCheckoutBeatsFallback(String command,
    {required String shell}) async {
  final r = await runWithStub(command,
      shell: shell, cwd: '${fx.a}/sub dir', projectDir: fx.d);
  return [
    if (!r.ran) 'the stub never ran',
    if (r.ran && r.cwd != fx.a) 'cwd ${r.cwd}, want the checkout ${fx.a}',
  ];
}

/// C8: a linked worktree runs ITS OWN copy (not the primary's, not the
/// fallback's).
Future<List<String>> checkWorktree(String command, {required String shell}) async {
  final r = await runWithStub(command,
      shell: shell, cwd: '${fx.w}/sub dir', projectDir: fx.d);
  return [
    if (!r.ran) 'the stub never ran',
    if (r.ran && r.cwd != fx.w) 'cwd ${r.cwd}, want the worktree ${fx.w}',
  ];
}

/// C9: a nested repository without the script falls back.
Future<List<String>> checkNested(String command, {required String shell}) async {
  final r = await runWithStub(command,
      shell: shell, cwd: fx.nested, projectDir: fx.d);
  return [
    if (!r.ran) 'the stub never ran',
    if (r.ran && r.found != true) 'MISSING (cwd ${r.cwd})',
    if (r.ran && r.cwd != fx.d) 'cwd ${r.cwd}, want the fallback ${fx.d}',
  ];
}

// ── OI-483: the retry and what a helper can do to the hook ──────────────

/// C12: a lost race is retried, then the hook behaves as if it never happened: dart's own exit 2
/// still blocks, the payload reaches it, stdout passes through, and one note says what happened.
Future<List<String>> checkLostRace(String command, {required String shell}) async {
  final r = await runWithStub(command,
      shell: shell, cwd: fx.a, loseRaces: 1, stubExit: 2, stubStderr: 'BLOCK-MESSAGE');
  return [
    if (r.calls != 2) '${r.calls} calls, want 2 (stderr ${r.stderr.trim()})',
    if (r.exitCode != 2) 'exit ${r.exitCode}, want 2',
    if (r.stdin != _payload) 'stdin "${r.stdin}"',
    if (!r.stdout.contains('STUB-OUT')) 'stdout "${r.stdout}"',
    if (!r.stderr.contains('[dart-run-retry]')) 'no retry note',
    if (!r.stderr.contains('BLOCK-MESSAGE')) 'the exit 2 message was lost',
    if (r.backoffs != 1) '${r.backoffs} backoffs, want 1',
  ];
}

/// C12b: the budget. Three lost races end in 254, the status of today's call, after 2 backoffs.
Future<List<String>> checkRaceBudget(String command, {required String shell}) async {
  final r = await runWithStub(command, shell: shell, cwd: fx.a, loseRaces: 3);
  return [
    if (r.calls != 3) '${r.calls} calls, want 3',
    if (r.exitCode != 254) 'exit ${r.exitCode}, want 254',
    if (r.backoffs != 2) '${r.backoffs} backoffs, want 2',
    if (!r.stderr.contains(raceStderr)) 'the child stderr was lost',
  ];
}

/// C13: no helper at all is today's call: one attempt, no note, the race's status back.
Future<List<String>> checkHelperAbsent(String command, {required String shell}) async {
  final helper = File('${fx.hostile}/scripts/_dart_bin.sh');
  if (helper.existsSync()) helper.deleteSync();
  final r = await runWithStub(command, shell: shell, cwd: fx.hostile, loseRaces: 1);
  return [
    if (r.calls != 1) '${r.calls} calls, want 1',
    if (r.exitCode != 254) 'exit ${r.exitCode}, want 254',
    if (r.stderr.contains('[dart-run-retry]')) 'a retry ran with no helper',
  ];
}

/// C14: a helper that is valid syntax or not, and fails while it is sourced: exit 2 must come ONLY
/// from dart, and dart must run. Each row was measured to escape a weaker guard (plan, truth 10).
const hostileHelpers = <String, String>{
  'syntax error': 'if then fi (',
  'exit 3 (passes sh -n)': 'exit 3',
  'a failing `.` (kills dash with 2)': '. /nonexistent/x',
  'an invalid set -o': 'set -o nosuchopt',
  'a top-level return 1': 'return 1',
  'a readonly DART_BIN (kills the setter)': 'readonly DART_BIN=zzz',
  'a setter that returns 1': 'use_dart_race_retry() { return 1; }',
  'a top-level exit 0 (a clean death, the probe needs its own status)': 'exit 0',
  'a top-level exit 7 (the status a status sentinel would use)': 'exit 7',
};

/// The same contract for text at the TOP of the helper: `set -e` with a failing command only ends a bash shell there,
/// and only when the source is not in an `&&` list (B-pass, seat A, measured against dash, bash and bash --posix).
const hostileHelperHeads = <String, String>{
  'exit 0 on the first line': 'exit 0',
  'exit 7 on the first line': 'exit 7',
  'set -e then a failing command': 'set -e\nfalse',
};

Future<List<String>> checkHostileHelpers(String command, {required String shell}) async {
  final real = File('scripts/_dart_bin.sh').readAsStringSync();
  final out = <String>[];
  final rows = <String, String>{
    for (final row in hostileHelpers.entries) row.key: '$real\n${row.value}\n',
    for (final row in hostileHelperHeads.entries) row.key: '${row.value}\n$real',
  };
  for (final row in rows.entries) {
    File('${fx.hostile}/scripts/_dart_bin.sh').writeAsStringSync(row.value);
    final r = await runWithStub(command, shell: shell, cwd: fx.hostile, stubExit: 2, stubStderr: 'BLOCK-MESSAGE');
    if (r.calls != 1) out.add('[${row.key}] ${r.calls} calls, want 1 (exit ${r.exitCode})');
    if (r.exitCode != 2) out.add('[${row.key}] exit ${r.exitCode}, want dart\'s 2');
    if (r.stdin != _payload) out.add('[${row.key}] the payload did not reach dart');
    if (!r.stderr.contains('BLOCK-MESSAGE')) out.add('[${row.key}] dart\'s message was lost');
  }
  return out;
}

/// C15: exit 2 through the function: the status, the message and stdout are all intact.
Future<List<String>> checkBlockThroughFunction(String command, {required String shell}) async {
  final r = await runWithStub(command, shell: shell, cwd: fx.a, stubExit: 2, stubStderr: 'BLOCK-MESSAGE');
  return [
    if (r.calls != 1) '${r.calls} calls, want 1',
    if (r.exitCode != 2) 'exit ${r.exitCode}, want 2',
    if (!r.stderr.contains('BLOCK-MESSAGE')) 'stderr "${r.stderr}"',
    if (!r.stdout.contains('STUB-OUT')) 'stdout "${r.stdout}"',
    if (r.stdin != _payload) 'stdin "${r.stdin}"',
  ];
}

/// C16: the kill switch, exactly `0`, is today's call. `false` keeps the retry on.
Future<List<String>> checkKillSwitch(String command, {required String shell}) async {
  final off = await runWithStub(command,
      shell: shell, cwd: fx.a, loseRaces: 1, env: const {'AVYA_DART_RUN_RETRY': '0'});
  final on = await runWithStub(command,
      shell: shell, cwd: fx.a, loseRaces: 1, env: const {'AVYA_DART_RUN_RETRY': 'false'});
  return [
    if (off.calls != 1) 'switch 0: ${off.calls} calls, want 1',
    if (off.exitCode != 254) 'switch 0: exit ${off.exitCode}, want 254',
    if (off.stderr.contains('[dart-run-retry]')) 'switch 0: a retry note',
    if (on.calls != 2) 'switch false: ${on.calls} calls, want 2',
  ];
}

/// C17: a tree whose helper predates OI-482 (a worktree on an old branch) is today's call, silently.
Future<List<String>> checkOldHelper(String command, {required String shell}) async {
  File('test/scripts/fixtures/pre_oi482_hooks/_dart_bin.sh.txt').copySync('${fx.hostile}/scripts/_dart_bin.sh');
  final r = await runWithStub(command, shell: shell, cwd: fx.hostile, loseRaces: 1);
  return [
    if (r.calls != 1) '${r.calls} calls, want 1',
    if (r.exitCode != 254) 'exit ${r.exitCode}, want 254',
    if (r.stderr.contains('not found')) 'a `not found` line on stderr: ${r.stderr.trim()}',
  ];
}

void main() {
  final root = Directory.current.path;
  final scripts = {for (final h in _expectedHooks) h.$3};

  setUpAll(() {
    // SAFETY ONLY (plan 3.1): never shape, so a mutated settings file still
    // reaches the behaviour assertions below.
    for (final h in loadHooks(root)) {
      final v = safetyViolations(h.command);
      if (v.isNotEmpty) {
        fail('refusing to execute hook command `${h.command}` in a test: $v');
      }
    }
    if (Platform.isWindows) return;

    final base = Directory.systemTemp.createTempSync('hook cwd ');
    ProcessResult git(List<String> args, String cwd) {
      final r = runSpawn('git', args,
          why: 'fixture: git ${args.join(' ')}', workingDirectory: cwd);
      expect(r.exitCode, 0, reason: 'fixture git ${args.join(' ')}: ${r.stderr}');
      return r;
    }

    Fx build(String name, {required bool helper}) {
      final b = (Directory('${base.path}/$name')..createSync()).resolveSymbolicLinksSync();
      void seedScripts(String dir) {
        for (final s in scripts) {
          File('$dir/scripts/$s').createSync(recursive: true);
        }
        if (helper) File('$root/scripts/_dart_bin.sh').copySync('$dir/scripts/_dart_bin.sh');
      }

      final a = Directory('$b/repo a')..createSync();
      git(['init', '-q'], a.path);
      seedScripts(a.path);
      git(['add', 'scripts'], a.path);
      git(['-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false',
          'commit', '-q', '-m', 'seed'], a.path);
      Directory('${a.path}/sub dir').createSync();

      final d = Directory('$b/decoy d')..createSync();
      git(['init', '-q'], d.path);
      seedScripts(d.path);

      final w = '$b/wt w';
      git(['worktree', 'add', '-q', '--detach', w], a.path);
      Directory('$w/sub dir').createSync();
      for (final s in scripts) {
        expect(File('$w/scripts/$s').existsSync(), isTrue,
            reason: 'worktree W lacks scripts/$s, so C8 would silently fall back');
      }

      final x = Directory('$b/outside x')..createSync();
      final nested = Directory('${a.path}/nested n')..createSync();
      git(['init', '-q'], nested.path);

      final hostile = Directory('$b/hostile h')..createSync();
      git(['init', '-q'], hostile.path);
      for (final s in scripts) {
        File('${hostile.path}/scripts/$s').createSync(recursive: true);
      }

      return Fx(base, a.path, d.path, w, x.path, nested.path, b, hostile.path);
    }

    fxHelper = build('with helper', helper: true);
    fxBare = build('no helper', helper: false);
    fx = fxHelper;
    _fxReady = true;
  });

  tearDownAll(() {
    if (_fxReady && fx.base.existsSync()) {
      fx.base.deleteSync(recursive: true);
    }
  });

  group('wiring and shape (no spawn)', () {
    test('C1: exactly the nine (event, matcher, script) registrations', () {
      final got = [
        for (final h in loadHooks(root)) (h.event, h.matcher, scriptOf(h.command)),
      ];
      expect(got, _expectedHooks,
          reason: 'a hook was added, removed, or moved to another event');
    });

    test('C2: every command is exactly the cwd-independent template', () {
      for (final h in loadHooks(root)) {
        final s = scriptOf(h.command);
        expect(s, isNotNull, reason: 'no script in `${h.command}`');
        expect(h.command, hookTemplate(s!), reason: '${h.event}/${h.matcher}');
      }
    });
  });

  group('real hook commands from .claude/settings.json', () {
    final commands = <String>{};
    setUpAll(() => commands.addAll(loadHooks(root).map((h) => h.command)));

    for (final shell in shells) {
      for (final bare in [false, true]) {
        test('[$shell] C3 C4 C4b C5 C6 C7 C8 C9 hold for every command, ${bare ? 'with no helper (today\'s call)' : 'through the helper'}', () async {
          expect(File(shell).existsSync(), isTrue,
              reason: '$shell is required on Linux/macOS CI');
          fx = bare ? fxBare : fxHelper;
          addTearDown(() => fx = fxHelper);
          for (final c in commands) {
            final s = scriptOf(c)!;
            final v = <String>[
              ...await checkSubdir(c, s, shell: shell, checkout: fx.a),
              ...await checkFallback(c, shell: shell),
              ...await checkNoFallback(c, shell: shell),
              ...await checkExitCode(c, shell: shell),
              ...await checkMissingRoot(c, shell: shell),
              ...await checkCheckoutBeatsFallback(c, shell: shell),
              ...await checkWorktree(c, shell: shell),
              ...await checkNested(c, shell: shell),
            ];
            expect(v, isEmpty, reason: '`$c` under $shell');
          }
        });
      }

      test('[$shell] C12 C12b C13 C14 C15 C16 C17 hold for every command (OI-483)', () async {
        for (final c in commands) {
          final v = <String>[
            ...await checkLostRace(c, shell: shell),
            ...await checkRaceBudget(c, shell: shell),
            ...await checkHelperAbsent(c, shell: shell),
            ...await checkHostileHelpers(c, shell: shell),
            ...await checkBlockThroughFunction(c, shell: shell),
            ...await checkKillSwitch(c, shell: shell),
            ...await checkOldHelper(c, shell: shell),
          ];
          expect(v, isEmpty, reason: '`$c` under $shell');
        }
      });

      test('[$shell] a hook shell with errexit on and a sound helper still reaches the real hook, retry included', () async {
        final c = loadHooks(root).firstWhere((h) => h.matcher == 'Bash').command;
        expect(await checkBlockThroughFunction('set -e; $c', shell: shell), isEmpty);
        expect(await checkLostRace('set -e; $c', shell: shell), isEmpty);
      });

      test('[$shell] a REAL lost race: the real SDK exits 254 on an empty yaml, the retry reaches the real hook, whose exit 2 and stdin survive', () async {
        final c = loadHooks(root).firstWhere((h) => h.matcher == 'Bash').command;
        final pkg = Directory('${fx.hostile}/../real sdk ${shell.split('/').last}')..createSync(recursive: true);
        final dir = pkg.resolveSymbolicLinksSync();
        final git = runSpawn('git', ['init', '-q'], why: 'real SDK fixture', workingDirectory: dir);
        expect(git.exitCode, 0);
        File('$dir/pubspec.yaml').writeAsStringSync('name: p\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n');
        File('$dir/.dart_tool/package_config.json')
          ..createSync(recursive: true)
          ..writeAsStringSync('{"configVersion":2,"packages":[{"name":"p","rootUri":"../","packageUri":"lib/","languageVersion":"3.0"}]}\n');
        final yaml = File('$dir/.dart_tool/native_assets.yaml')..writeAsStringSync('');
        File('$dir/scripts/git_safety_hook.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync("import 'dart:convert';\nimport 'dart:io';\n"
              'Future<void> main() async {\n'
              '  final s = await stdin.transform(utf8.decoder).join();\n'
              '  stderr.writeln("REAL HOOK GOT \$s");\n'
              '  exit(2);\n}\n');
        File('$root/scripts/_dart_bin.sh').copySync('$dir/scripts/_dart_bin.sh');
        // A shim on PATH named `dart`: the real SDK, deleting the yaml after its 254 (the writer finishing).
        final bin = Directory('$dir/.shim')..createSync();
        final shim = File('${bin.path}/dart')
          ..writeAsStringSync('#!/bin/sh\n"${dartBin()}" "\$@"\nrc=\$?\n'
              '[ "\$rc" = 254 ] && echo 254 >> "$dir/.shim/lost" && rm -f "${yaml.path}"\nexit "\$rc"\n');
        expect(runSpawn('chmod', ['+x', shim.path], why: 'chmod the shim').exitCode, 0);
        final r = await runSpawnWithInput(shell, ['-c', c],
            why: 'the git-safety command against the real SDK',
            stdin: _payload,
            workingDirectory: dir,
            extraEnv: {'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}'},
            report: (_) {}).timeout(const Duration(seconds: 120));
        expect(File('$dir/.shim/lost').readAsStringSync().trim(), '254', reason: 'attempt 1 must be a REAL 254: ${r.stderr}');
        expect(r.stderr, contains('[dart-run-retry]'));
        expect(r.stderr, contains('REAL HOOK GOT $_payload'));
        expect(r.exitCode, 2, reason: r.stderr);
      });

      test('[$shell] C3 against the REAL repo from supabase/functions', () async {
        final top = runSpawn('git', ['rev-parse', '--show-toplevel'],
            why: 'the real repo root', workingDirectory: root);
        expect(top.exitCode, 0,
            reason: 'git cannot see the repo root, so this check cannot run: '
                '${top.stderr}');
        final realRoot = Directory((top.stdout as String).trim())
            .resolveSymbolicLinksSync();
        for (final c in commands) {
          final r = await runWithStub(c,
              shell: shell, cwd: '$realRoot/supabase/functions');
          expect(r.ran, isTrue, reason: '`$c`: ${r.stderr}');
          expect(r.found, isTrue, reason: '`$c` from supabase/functions');
          expect(r.cwd, realRoot, reason: '`$c`');
        }
      });
    }

    test('C11: the REAL git-safety hook blocks a raw commit from a '
        'subdirectory; the old relative form could not even start', () async {
      final guard = loadHooks(root)
          .firstWhere((h) => h.event == 'PreToolUse' && h.matcher == 'Bash')
          .command;
      final payload = jsonEncode({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        // Neutral: the hook's merge-in-progress waiver reads THIS directory.
        // The shell still starts in supabase/functions (workingDirectory).
        'cwd': fx.x,
        'tool_input': {'command': 'git commit -m probe'},
      });
      final r = await runSpawnWithInput('/bin/sh', ['-c', guard],
          why: 'real git-safety hook from supabase/functions',
          stdin: payload,
          workingDirectory: '$root/supabase/functions',
          remove: const {'CLAUDE_PROJECT_DIR'}).timeout(
          const Duration(seconds: 120));
      expect(r.exitCode, 2, reason: 'the guard must BLOCK: ${r.stderr}');
      expect(r.stderr, contains('[git-safety] BLOCKED'));

      // Control, from a non-repo directory (so no stray cache lands in the
      // repo): the old relative form exits 255, a NON-blocking error.
      final old = await runSpawnWithInput('/bin/sh',
          ['-c', 'dart run --verbosity=error scripts/git_safety_hook.dart'],
          why: 'the old relative hook form from a directory without scripts/',
          stdin: payload,
          workingDirectory: fx.x,
          remove: const {'CLAUDE_PROJECT_DIR'},
          report: (_) {}).timeout(const Duration(seconds: 120));
      expect(old.exitCode, 255,
          reason: 'the bug this file guards: the hook never started');
    });
  }, skip: Platform.isWindows ? 'POSIX shells and a stub dart' : false);

  group('META: each mutant fails its NAMED check', () {
    const s = 'git_safety_hook.dart';
    final good = hookTemplate(s);
    const tail = 'dart run --verbosity=error scripts/$s';
    final mutants = <String, String>{
      'M1 relative form': tail,
      'M2 fallback arm is "."': good.replaceFirst(r'r="${CLAUDE_PROJECT_DIR:-.}"', 'r="."'),
      'M3 || true': '$good || true',
      'M4 ; instead of || exit 1': good.replaceFirst('cd "\$r" || exit 1;', 'cd "\$r";'),
      'M4b && instead of || exit 1':
          good.replaceFirst('cd "\$r" || exit 1; ', 'cd "\$r" && '),
      'M5 fallback only': 'r="\${CLAUDE_PROJECT_DIR:-.}"; cd "\$r" || exit 1; $tail',
      'M5b git-common-dir': good.replaceFirst(
          r'r=$(git rev-parse --show-toplevel 2>/dev/null);',
          r'r=$(git rev-parse --git-common-dir 2>/dev/null); r="${r%/.git}";'),
      'M8 no [ -f ] check':
          good.replaceFirst(' && [ -f "\$r/scripts/$s" ]', ''),
      'M9 stdin from /dev/null': '$good </dev/null',
      'M12 unquoted \$r': good
          .replaceFirst('[ -f "\$r/scripts/$s" ]', '[ -f \$r/scripts/$s ]')
          .replaceFirst('cd "\$r"', 'cd \$r'),
      'M18 dart run past the function': good.replaceFirst('"\$DART_BIN" run', 'dart run'),
    };

    // OI-483, mutants of the fragment: each is a fixed literal the SAFETY rule admits one at a time.
    String withHead(String head) => good.replaceFirst(retryHead, head);
    const probe = 'p=\$( (. scripts/_dart_bin.sh; use_dart_race_retry && echo ok) 2>/dev/null); if [ "\$p" = ok ]; ';
    final m13 = withHead('DART_BIN=dart; . scripts/_dart_bin.sh; use_dart_race_retry; ');
    final m14 = withHead('DART_BIN=dart; if sh -n scripts/_dart_bin.sh 2>/dev/null; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; ');
    final m15 = withHead('DART_BIN=dart; p=\$( (. scripts/_dart_bin.sh; echo ok) 2>/dev/null); if [ "\$p" = ok ]; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; ');
    final m16 = withHead('DART_BIN=dart; p=\$( (. scripts/_dart_bin.sh; use_dart_race_retry && echo ok)); if [ "\$p" = ok ]; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; ');
    final m17 = withHead('${probe}then . scripts/_dart_bin.sh; use_dart_race_retry; fi; ');
    final m19 = withHead('DART_BIN=dart; ${probe}then . scripts/_dart_bin.sh; fi; ');
    final m20 = withHead('DART_BIN=dart; ${probe}then use_dart_race_retry; fi; ');
    final m21 = good.replaceFirst('"\$DART_BIN" run', 'exec "\$DART_BIN" run');
    final m22 = withHead('DART_BIN=dart; if (. scripts/_dart_bin.sh && use_dart_race_retry) >/dev/null 2>&1; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; ');
    final m23 = withHead('DART_BIN=dart; p=\$( (. scripts/_dart_bin.sh && use_dart_race_retry && echo ok) 2>/dev/null); if [ "\$p" = ok ]; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; ');
    final m24 = withHead('DART_BIN=dart; (. scripts/_dart_bin.sh; use_dart_race_retry && exit 7) >/dev/null 2>&1; if [ \$? = 7 ]; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; ');
    final m25 = withHead('DART_BIN=dart; p=\$( (. scripts/_dart_bin.sh; use_dart_race_retry && echo ok) 2>/dev/null) || :; if [ "\$p" = ok ]; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; ');
    String headOf(String mutant) => mutant.substring(mutant.indexOf('exit 1; ') + 8, mutant.indexOf('"\$DART_BIN" run'));

    test('every mutant differs from the template and passes the SAFETY rule '
        '(so it reaches the behaviour checks)', () {
      for (final e in mutants.entries) {
        expect(e.value, isNot(good), reason: '${e.key} did not apply');
        expect(safetyViolations(e.value), isEmpty, reason: e.key);
      }
      expect(safetyViolations(good), isEmpty);
      for (final m in [m13, m14, m15, m16, m17, m19, m20, m22, m23, m24, m25]) {
        expect(m, isNot(good));
        expect(safetyViolations(m), isNotEmpty, reason: 'only the exact fragment passes on its own: $m');
        expect(safetyViolations(m, alsoAllow: headOf(m)), isEmpty, reason: m);
      }
      expect(m21, isNot(good));
      expect(safetyViolations(m21), isNotEmpty);
      expect(safetyViolations(m21, alsoAllow: 'exec '), isEmpty);
    });

    test('a hook that never reads stdin is a mutant kill, not a harness error (broken pipe, 8f3e35 flake)', () async {
      // 4 MiB cannot fit a pipe buffer, so the write is still pending when the shell exits:
      // deterministic, where the 41-byte payload only lost the race on a loaded machine.
      final r = await runWithStub(mutants['M9 stdin from /dev/null']!,
          shell: '/bin/sh', cwd: fx.a, stdin: 'x' * (4 << 20));
      expect(r.ran, isTrue, reason: 'the stub ran; the closed pipe must not abort the run');
      expect(r.stdin, isEmpty, reason: 'the stub read /dev/null, so M9 still fails its payload check');
    });

    test('the SAFETY rule refuses real programs', () {
      expect(safetyViolations('sh scripts/x.sh'), isNotEmpty);
      expect(safetyViolations('[ -f "\$(sh x)" ]; $tail'), isNotEmpty);
      expect(safetyViolations('$tail | tee /tmp/x'), isNotEmpty);
      expect(safetyViolations('curl -s http://x; $tail'), isNotEmpty);
      expect(safetyViolations('cd "\$r" & sh x.sh; $tail'), isNotEmpty);
      expect(safetyViolations('cd "\$r" || exit 1\nsh x.sh; $tail'), isNotEmpty);
      expect(safetyViolations('cd "\$r" || exit 1\rsh x.sh; $tail'), isNotEmpty);
      // The fragment is one exact string: an altered head does not pass, whatever it sources.
      expect(safetyViolations(good.replaceFirst('then . scripts/_dart_bin.sh', 'then . /anything')), isNotEmpty);
      expect(safetyViolations(good.replaceFirst('(. scripts/_dart_bin.sh', '(. /anything')), isNotEmpty);
      expect(safetyViolations(good.replaceFirst('fi; ', 'fi; sh x.sh; ')), isNotEmpty);
    });

    for (final shell in shells) {
      test('[$shell] the template passes every check', () async {
        expect(await checkSubdir(good, s, shell: shell, checkout: fx.a), isEmpty);
        expect(await checkFallback(good, shell: shell), isEmpty);
        expect(await checkNoFallback(good, shell: shell), isEmpty);
        expect(await checkExitCode(good, shell: shell), isEmpty);
        expect(await checkMissingRoot(good, shell: shell), isEmpty);
        expect(await checkCheckoutBeatsFallback(good, shell: shell), isEmpty);
        expect(await checkWorktree(good, shell: shell), isEmpty);
        expect(await checkNested(good, shell: shell), isEmpty);
        expect(await checkLostRace(good, shell: shell), isEmpty);
        expect(await checkRaceBudget(good, shell: shell), isEmpty);
        expect(await checkHelperAbsent(good, shell: shell), isEmpty);
        expect(await checkHostileHelpers(good, shell: shell), isEmpty);
        expect(await checkBlockThroughFunction(good, shell: shell), isEmpty);
        expect(await checkKillSwitch(good, shell: shell), isEmpty);
        expect(await checkOldHelper(good, shell: shell), isEmpty);
      });

      test('[$shell] each mutant is killed by its named check', () async {
        Future<void> killed(String name, Future<List<String>> v) async =>
            expect(await v, isNotEmpty, reason: '$name survived its check');
        await killed('M1', checkSubdir(mutants['M1 relative form']!, s,
            shell: shell, checkout: fx.a));
        await killed('M2', checkFallback(mutants['M2 fallback arm is "."']!, shell: shell));
        await killed('M3', checkExitCode(mutants['M3 || true']!, shell: shell));
        await killed('M4', checkMissingRoot(mutants['M4 ; instead of || exit 1']!,
            shell: shell));
        await killed('M5', checkCheckoutBeatsFallback(mutants['M5 fallback only']!,
            shell: shell));
        await killed('M5b', checkWorktree(mutants['M5b git-common-dir']!, shell: shell));
        await killed('M8', checkNested(mutants['M8 no [ -f ] check']!, shell: shell));
        await killed('M9', checkSubdir(mutants['M9 stdin from /dev/null']!, s,
            shell: shell, checkout: fx.a));
        await killed('M12', checkSubdir(mutants['M12 unquoted \$r']!, s,
            shell: shell, checkout: fx.a));
        await killed('M13', checkHostileHelpers(m13, shell: shell));
        await killed('M14', checkHostileHelpers(m14, shell: shell));
        await killed('M15', checkHostileHelpers(m15, shell: shell));
        await killed('M16', checkOldHelper(m16, shell: shell));
        await killed('M17', checkSubdir(m17, s, shell: shell, checkout: fx.a));
        await killed('M18', checkLostRace(mutants['M18 dart run past the function']!, shell: shell));
        await killed('M19', checkLostRace(m19, shell: shell));
        await killed('M20', checkLostRace(m20, shell: shell));
        await killed('M21', checkLostRace(m21, shell: shell));
        await killed('M22', checkHostileHelpers(m22, shell: shell));
        await killed('M24', checkHostileHelpers(m24, shell: shell));
      });
    }

    test('M23 (`&&` after the `.`) and M25 (`|| :` on the assignment) turn `set -e` off for the probe: C14 kills both under bash; dash survives that helper either way', () async {
      final bash = shells.firstWhere((s) => s.endsWith('bash'));
      expect((await checkHostileHelpers(m23, shell: bash)).join('; '), contains('set -e then a failing command'));
      expect((await checkHostileHelpers(m25, shell: bash)).join('; '), contains('set -e then a failing command'));
    });

    test('M4b (`cd && dart`) is killed by C6 under dash, where a failed cd '
        'exits 2 (bash exits 1 there, so only the dash arm can see it)', () async {
      final v = await checkMissingRoot(mutants['M4b && instead of || exit 1']!,
          shell: '/bin/sh');
      expect(v, isNotEmpty);
    }, skip: shIsDash ? false : '/bin/sh is not dash on this machine');
  }, skip: Platform.isWindows ? 'POSIX shells and a stub dart' : false);
}
