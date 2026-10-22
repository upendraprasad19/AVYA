@Timeout(Duration(minutes: 6))
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

/// The 2.1 template. `check_alerts.dart` has always run without flags.
String hookTemplate(String script) {
  final flags = script == 'check_alerts.dart' ? '' : '--verbosity=error ';
  return r'r=$(git rev-parse --show-toplevel 2>/dev/null); '
      '[ -n "\$r" ] && [ -f "\$r/scripts/$script" ] || '
      r'r="${CLAUDE_PROJECT_DIR:-.}"; cd "$r" || exit 1; '
      'dart run ${flags}scripts/$script';
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
    RegExp(r'dart run (?:--verbosity=error )?scripts/([a-z_]+\.dart)')
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
/// a real program.
List<String> safetyViolations(String command) {
  final out = <String>[];
  final text = command.replaceAll(_gitSubst, '__GITREV__');
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
  StubRun(this.exitCode, this.stderr, this.ran, this.cwd, this.lastArg,
      this.found, this.stdin);
  final int exitCode;
  final String stderr;
  final bool ran;
  final String? cwd;
  final String? lastArg;
  final bool? found;
  final String? stdin;
}

/// Fixtures shared by every check (built in setUpAll).
class Fx {
  Fx(this.base, this.a, this.d, this.w, this.x, this.nested, this.ceiling);
  final Directory base;
  final String a; // checkout A (resolved), holds every hook script
  final String d; // decoy checkout, used as CLAUDE_PROJECT_DIR
  final String w; // linked worktree of A
  final String x; // a non-repo directory
  final String nested; // a nested `git init` inside A, no scripts/
  final String ceiling; // GIT_CEILING_DIRECTORIES
}

late Fx fx;
var _fxReady = false;
const _payload = '{"probe":"8f3e35","tool_name":"Bash"}';
const shells = ['/bin/sh', '/bin/bash'];

bool get shIsDash {
  try {
    return File('/bin/sh').resolveSymbolicLinksSync().endsWith('dash');
  } catch (_) {
    return false;
  }
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
}) async {
  final stub = Directory.systemTemp.createTempSync('hook_stub_');
  try {
    final bin = Directory('${stub.path}/bin')..createSync();
    final rec = Directory('${stub.path}/rec')..createSync();
    final dart = File('${bin.path}/dart')
      ..writeAsStringSync('#!/bin/sh\n'
          "rec='${rec.path}'\n"
          r'pwd -P > "$rec/cwd"' '\n'
          r'last=""; for a in "$@"; do last=$a; done' '\n'
          r'printf %s "$last" > "$rec/last"' '\n'
          r'if [ -f "$last" ]; then echo FOUND > "$rec/found"; '
          r'else echo MISSING > "$rec/found"; fi' '\n'
          r'cat > "$rec/stdin"' '\n'
          'exit $stubExit\n');
    final chmod = runSpawn('chmod', ['+x', dart.path], why: 'chmod the stub dart');
    expect(chmod.exitCode, 0, reason: 'chmod of the stub dart failed');

    final r = await runSpawnWithInput(
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
      },
      allowControl: const {'GIT_CEILING_DIRECTORIES'},
      report: (_) {},
    ).timeout(const Duration(seconds: 60));

    String? read(String name) {
      final f = File('${rec.path}/$name');
      return f.existsSync() ? f.readAsStringSync() : null;
    }

    final cwdRec = read('cwd')?.trim();
    final found = read('found')?.trim();
    return StubRun(r.exitCode, r.stderr, cwdRec != null, cwdRec, read('last'),
        found == null ? null : found == 'FOUND', read('stdin'));
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
    final b = base.resolveSymbolicLinksSync();
    ProcessResult git(List<String> args, String cwd) {
      final r = runSpawn('git', args,
          why: 'fixture: git ${args.join(' ')}', workingDirectory: cwd);
      expect(r.exitCode, 0, reason: 'fixture git ${args.join(' ')}: ${r.stderr}');
      return r;
    }

    void seedScripts(String dir) {
      for (final s in scripts) {
        File('$dir/scripts/$s').createSync(recursive: true);
      }
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

    fx = Fx(base, a.path, d.path, w, x.path, nested.path, b);
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
      test('[$shell] C3 C4 C4b C5 C6 C7 C8 C9 hold for every command', () async {
        expect(File(shell).existsSync(), isTrue,
            reason: '$shell is required on Linux/macOS CI');
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
    };

    test('every mutant differs from the template and passes the SAFETY rule '
        '(so it reaches the behaviour checks)', () {
      for (final e in mutants.entries) {
        expect(e.value, isNot(good), reason: '${e.key} did not apply');
        expect(safetyViolations(e.value), isEmpty, reason: e.key);
      }
      expect(safetyViolations(good), isEmpty);
    });

    test('the SAFETY rule refuses real programs', () {
      expect(safetyViolations('sh scripts/x.sh'), isNotEmpty);
      expect(safetyViolations('[ -f "\$(sh x)" ]; $tail'), isNotEmpty);
      expect(safetyViolations('$tail | tee /tmp/x'), isNotEmpty);
      expect(safetyViolations('curl -s http://x; $tail'), isNotEmpty);
      expect(safetyViolations('cd "\$r" & sh x.sh; $tail'), isNotEmpty);
      expect(safetyViolations('cd "\$r" || exit 1\nsh x.sh; $tail'), isNotEmpty);
      expect(safetyViolations('cd "\$r" || exit 1\rsh x.sh; $tail'), isNotEmpty);
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
      });
    }

    test('M4b (`cd && dart`) is killed by C6 under dash, where a failed cd '
        'exits 2 (bash exits 1 there, so only the dash arm can see it)', () async {
      final v = await checkMissingRoot(mutants['M4b && instead of || exit 1']!,
          shell: '/bin/sh');
      expect(v, isNotEmpty);
    }, skip: shIsDash ? false : '/bin/sh is not dash on this machine');
  }, skip: Platform.isWindows ? 'POSIX shells and a stub dart' : false);
}
