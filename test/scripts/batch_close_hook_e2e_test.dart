// E2E for scripts/batch_close_hook.dart — runs the REAL Stop hook against a real
// git repo.
//
// The pure test covers the decision. This covers the contract with the harness,
// which the predicate cannot see:
//   - it ALWAYS exits 0 (a non-zero Stop hook is a wedged session);
//   - it emits `{"decision":"block"}` only when it should;
//   - the once-per-HEAD state file actually silences the second run;
//   - `stop_hook_active` short-circuits before anything else.
//
// It also pins the bug that live-testing found and no unit test could: the hook
// derives the harness memory directory from `--git-common-dir`, NOT
// `--show-toplevel`, because every session works in a linked worktree per §4.13
// and the worktree path never matches the harness's mangled directory name.

// ⚠ FILE-LEVEL TIMEOUT — omitted when this file was written, and the full suite
// caught it. Every sibling e2e here carries one (`gate_index_e2e` 3 min,
// `retire_worktree_e2e` 4 min) for the same reason: these tests spawn REAL `dart
// run` subprocesses, and each pays the flutter/bin/dart wrapper cost CLAUDE.md
// measures at 3.4-10.5s for a NO-OP. Two sequential spawns plus git work fits
// comfortably in the default 30s when run alone — and does NOT when the full
// suite runs many files in parallel. It passed in isolation and timed out in the
// suite, which is exactly the shape a targeted run cannot show you.
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_');
  });
  return env;
}

late final String _hook;
late final String _lib;
late final String _telemetryCli;
late final String _telemetryLib;

ProcessResult _git(String cwd, List<String> args) => Process.runSync(
      'git',
      args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );

/// Runs the real hook with [stdinJson] on stdin.
///
/// Uses Process.start rather than runSync because the hook reads stdin, and
/// runSync cannot supply it. Cross-platform: no shell, no `cmd /c` pipe.
Future<({int exitCode, String stdout})> _runHook(String cwd,
    {String stdinJson = '{}'}) async {
  final p = await Process.start(
    'dart',
    ['run', 'scripts/batch_close_hook.dart'],
    workingDirectory: cwd,
    environment: _cleanEnv(),
    includeParentEnvironment: false,
    runInShell: true,
  );
  p.stdin.write(stdinJson);
  await p.stdin.close();
  final out = await p.stdout.transform(utf8.decoder).join();
  await p.stderr.transform(utf8.decoder).join();
  final code = await p.exitCode;
  return (exitCode: code, stdout: out);
}

/// A repo with an `origin/main` that HEAD is ahead of.
Directory _repoWithUnpushed({int commits = 2}) {
  final dir = Directory.systemTemp.createTempSync('batchclose_e2e_');
  final root = dir.path;
  Directory('$root/scripts').createSync(recursive: true);
  File('$root/scripts/batch_close_hook.dart')
      .writeAsStringSync(File(_hook).readAsStringSync());
  File('$root/scripts/batch_close_lib.dart')
      .writeAsStringSync(File(_lib).readAsStringSync());

  _git(root, ['init', '-q']);
  _git(root, ['config', 'user.email', 't@t.t']);
  _git(root, ['config', 'user.name', 't']);
  File('$root/seed.txt').writeAsStringSync('seed\n');
  _git(root, ['add', '.']);
  _git(root, ['commit', '-q', '-m', 'seed']);
  // Fabricate origin/main at the seed so HEAD is ahead by `commits`.
  _git(root, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
  for (var i = 0; i < commits; i++) {
    File('$root/f$i.txt').writeAsStringSync('$i\n');
    _git(root, ['add', '.']);
    _git(root, ['commit', '-q', '-m', 'fix(x): commit $i']);
  }
  return dir;
}

Map<String, dynamic>? _decision(({int exitCode, String stdout}) r) {
  for (final line in r.stdout.split(String.fromCharCode(10))) {
    final t = line.trim();
    if (t.startsWith('{')) {
      try {
        return jsonDecode(t) as Map<String, dynamic>;
      } catch (_) {}
    }
  }
  return null;
}

/// Fixture with the telemetry CLI + its lib copied in and a plan-review record
/// for the CURRENT branch (whatever `git init` named it — never hardcoded).
/// Built on [_repoWithUnpushed] so the existing fixture stays untouched.
Directory _repoWithTelemetry({String? recordContent}) {
  final d = _repoWithUnpushed();
  File('${d.path}/scripts/batch_process_telemetry.dart')
      .writeAsStringSync(File(_telemetryCli).readAsStringSync());
  File('${d.path}/scripts/batch_process_telemetry_lib.dart')
      .writeAsStringSync(File(_telemetryLib).readAsStringSync());
  Directory('${d.path}/docs/plan-reviews').createSync(recursive: true);
  if (recordContent != null) {
    final branch =
        _git(d.path, ['branch', '--show-current']).stdout.toString().trim();
    File('${d.path}/docs/plan-reviews/${branch.replaceAll('/', '-')}.md')
        .writeAsStringSync(recordContent);
  }
  return d;
}


/// Remove a fixture directory without ever failing the test.
///
/// On Windows a child process that has just exited can still hold a handle into
/// the directory, and `deleteSync` then throws PathAccessException — which the
/// full suite reported as a SECOND failure stacked on top of the real one (a
/// timeout), obscuring it. Cleanup is hygiene, not an assertion: the OS reaps
/// %TEMP% regardless, so a failure here must never redden a test.
void _cleanup(Directory d) {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      if (d.existsSync()) d.deleteSync(recursive: true);
      return;
    } catch (_) {
      sleep(const Duration(milliseconds: 200));
    }
  }
}

void main() {
  setUpAll(() {
    _hook = '${Directory.current.path}/scripts/batch_close_hook.dart';
    _lib = '${Directory.current.path}/scripts/batch_close_lib.dart';
    _telemetryCli =
        '${Directory.current.path}/scripts/batch_process_telemetry.dart';
    _telemetryLib =
        '${Directory.current.path}/scripts/batch_process_telemetry_lib.dart';
  });

  test('BLOCKS once when a batch has landed unpushed', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => _cleanup(d));

    final r = await _runHook(d.path);
    expect(r.exitCode, 0, reason: 'a Stop hook must NEVER exit non-zero');
    final dec = _decision(r);
    expect(dec, isNotNull);
    expect(dec!['decision'], 'block');
    expect(dec['reason'], contains('§5'));
    expect(dec['reason'], contains('2 unpushed'));
  });

  test('SILENT on the second run at the same HEAD', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => _cleanup(d));

    await _runHook(d.path); // first run records the sha
    final second = await _runHook(d.path);
    expect(second.exitCode, 0);
    expect(_decision(second), isNull,
        reason: 'bounded to one interruption per HEAD — otherwise every '
            'conversational turn after a commit is interrupted');
  });

  test('stop_hook_active NEVER blocks (infinite-loop guard)', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => _cleanup(d));
    final r = await _runHook(d.path, stdinJson: '{"stop_hook_active":true}');
    expect(r.exitCode, 0);
    expect(_decision(r), isNull);
  });

  test('SILENT when nothing is unpushed', () async {
    final d = _repoWithUnpushed(commits: 0);
    addTearDown(() => _cleanup(d));
    final r = await _runHook(d.path);
    expect(r.exitCode, 0);
    expect(_decision(r), isNull);
  });

  test('kill switch silences it', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => _cleanup(d));
    Directory('${d.path}/.claude').createSync(recursive: true);
    File('${d.path}/.claude/.batch_close.disabled').writeAsStringSync('');
    final r = await _runHook(d.path);
    expect(r.exitCode, 0);
    expect(_decision(r), isNull);
  });

  test('garbage on stdin does not wedge or crash it', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => _cleanup(d));
    final r = await _runHook(d.path, stdinJson: 'not json at all');
    expect(r.exitCode, 0, reason: 'every error path exits 0');
  });

  test('DOES NOT HANG when stdin is never closed', () async {
    // THE BLOCKING FINDING from round 1, reproduced then pinned. The first
    // version used the SYNCHRONOUS, BLOCKING `stdin.readLineSync`: a caller that
    // does not write-then-close blocked forever. A hang is not an exception, so
    // the surrounding try/catch could not rescue it — and Stop fires at the END
    // OF EVERY TURN, so it would wedge every session.
    //
    // Reproduced during review with a delayed writer: still blocked after 8s,
    // exit 124. The fix mirrors the two sibling hooks the repo had ALREADY
    // fixed for this exact class (git_safety_hook.dart:85-95,
    // discipline_hook.dart:82,221) — hasTerminal guard + a 3s timeout.
    final d = _repoWithUnpushed();
    addTearDown(() => _cleanup(d));

    final p = await Process.start(
      'dart',
      ['run', 'scripts/batch_close_hook.dart'],
      workingDirectory: d.path,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );
    // ⚠ DRAIN BOTH PIPES. Not optional, and getting it wrong cost a wrong
    // diagnosis: the first version of this test awaited exitCode without
    // consuming stdout, the hook's JSON block filled the pipe buffer, and the
    // child blocked on WRITE. It looked exactly like the read-hang being tested
    // for — a test-harness deadlock masquerading as the defect under test.
    final outFuture = p.stdout.transform(utf8.decoder).join();
    final errFuture = p.stderr.transform(utf8.decoder).join();

    // Write a payload but DELIBERATELY never close stdin.
    p.stdin.write('{}');
    await p.stdin.flush();

    // ⚠ 25s here was NOT enough under full-suite contention, and this is the
    // FIFTH recurrence of the documented class in CLAUDE.md §4.9 — in the very
    // file that `0a99a0b7` ("the two new e2e files had no file-level timeout,
    // and the full suite caught it") already fixed once.
    //
    // What that fix missed: it added `@Timeout(Duration(minutes: 6))` at the
    // FILE level, and this test's own `timeout:` override (60s, below) silently
    // took precedence over it — so the file-level budget never applied here.
    // Inside that, 25s bounded the child. Solo the child costs ~5s (3s stdin
    // self-release + dart startup) and 25s looks generous; in the full suite
    // ~40 files compete and every `dart` child pays the wrapper cost §0
    // measures at 3.4-10.5s FOR A NO-OP. Measured 2026-09-04: green targeted
    // (7/7) and green across all of test/scripts/ (555/555), RED only in the
    // ~5300-test suite — exactly "a targeted run is a different input set, not
    // a subset".
    //
    // 90s keeps the failure meaningful: the hook self-releases in 3s, so 30x
    // that is still unambiguously "released" rather than "hung", and it sits
    // far enough inside the file's 6-minute budget that a genuine hang fails
    // HERE with the message below rather than as an opaque file timeout.
    final code = await p.exitCode.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    try {
      await p.stdin.close();
    } catch (_) {}
    await outFuture;
    await errFuture;

    expect(code, isNot(-1),
        reason: 'the hook must self-release on its stdin timeout rather than '
            'block forever waiting for a close that never comes');
    expect(code, 0, reason: 'and it must still exit 0');
    // NO per-test `timeout:` override here, deliberately. One used to sit on
    // this line (60s) and it DEFEATED the file-level `@Timeout(minutes: 6)`
    // added by 0a99a0b7 for exactly this contention problem — a per-test
    // `timeout:` takes precedence over the file annotation, so the file got the
    // fix and this test kept the old ceiling. Inheriting the file budget is the
    // point; do not re-add a tighter one without re-reading §4.9.
  });

  test('telemetry appears on the hook stdout channel when a record exists',
      () async {
    final d = _repoWithTelemetry(recordContent: '''
---
branch: test
review_rounds: 2
mechanical_only: false
---
body
''');
    addTearDown(() => _cleanup(d));

    final r = await _runHook(d.path);
    expect(r.exitCode, 0);
    final dec = _decision(r);
    expect(dec, isNotNull);
    expect(dec!['decision'], 'block');
    // Same channel as the checklist: the JSON `reason` field on stdout.
    expect(dec['reason'], contains('process-telemetry:'));
    expect(dec['reason'], contains('review_rounds=2'));
    expect(dec['reason'], contains('mechanical_only=false'));
  });

  test('corrupted record still exits 0 and the checklist still emits',
      () async {
    final d = _repoWithTelemetry(recordContent: '@@@ not a record at all @@@');
    addTearDown(() => _cleanup(d));

    final r = await _runHook(d.path);
    expect(r.exitCode, 0, reason: 'every error path exits 0');
    final dec = _decision(r);
    expect(dec, isNotNull, reason: 'checklist must still emit');
    expect(dec!['decision'], 'block');
    expect(dec['reason'], contains('§5'));
    // Telemetry degrades to the defaults (parse fell back, rounds read 0)
    // rather than crashing the hook or vanishing from the payload.
    expect(dec['reason'], contains('process-telemetry:'));
    expect(dec['reason'], contains('review_rounds=0'));
  });

  test('sweep counts 7-day mtime window, s_fix tier, absent ledger is unknown',
      () async {
    final d = _repoWithTelemetry();
    addTearDown(() => _cleanup(d));

    final diag = Directory('${d.path}/docs/diagnoses')
      ..createSync(recursive: true);
    final now = DateTime.now();
    // OLD (8 days back) but s_fix — must be excluded by the mtime window
    // even though its content matches the tier pattern.
    final old = File('${diag.path}/old_sfix.md');
    old.writeAsStringSync('tier: s_fix\n');
    old.setLastModifiedSync(now.subtract(const Duration(days: 8)));
    File('${diag.path}/recent_sfix.md').writeAsStringSync('tier: s_fix\n');
    File('${diag.path}/recent_plain.md').writeAsStringSync('tier: a_fix\n');
    Directory('${d.path}/docs/reviews').createSync(recursive: true);
    File('${d.path}/docs/reviews/one-bpass.md').writeAsStringSync('review\n');
    // NO docs/audit/s_tier_escapes.yaml — ledger absent must render unknown.

    final r = await _runHook(d.path);
    expect(r.exitCode, 0);
    final dec = _decision(r);
    expect(dec, isNotNull);
    expect(dec!['decision'], 'block');
    expect(dec['reason'], contains('s_tier_fixes=1/2'),
        reason: 'only the 2 recent diagnose docs count, and only 1 is s_fix '
            '— the 8-day-old s_fix file is outside the mtime window');
    expect(dec['reason'], contains('review_files_7d=1'));
    expect(dec['reason'], contains('open_s_escapes=unknown'),
        reason: 'ledger ABSENT renders unknown, never 0 (bad-news-vs-no-news) '
            '— pinned at the wiring level, not just in the pure lib');
    expect(dec['reason'], contains('gate_failures_7d=unknown'),
        reason: 'gate-failures log ABSENT renders unknown, never 0 — '
            'the sweep fixture writes no .claude/.gate_failures.log');
  });

  test('gate-failures log: 7-day window, top gate, unparseable is unknown',
      () async {
    final d = _repoWithTelemetry();
    addTearDown(() => _cleanup(d));
    Directory('${d.path}/.claude').createSync(recursive: true);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    File('${d.path}/.claude/.gate_failures.log').writeAsStringSync(
      '${nowSec - 100} check_alpha\n'
      '${nowSec - 200} check_alpha\n'
      '${nowSec - 691200} check_beta\n',
    );

    final r = await _runHook(d.path);
    expect(r.exitCode, 0);
    final dec = _decision(r);
    expect(dec, isNotNull);
    expect(dec!['decision'], 'block');
    expect(dec['reason'], contains('gate_failures_7d=2'),
        reason: 'only the 2 recent lines count — the 8-day-old check_beta '
            'line is outside the window');
    expect(dec['reason'], contains('top_gate=check_alpha'));

    // Unparseable content degrades to unknown, never 0.
    final d2 = _repoWithTelemetry();
    addTearDown(() => _cleanup(d2));
    Directory('${d2.path}/.claude').createSync(recursive: true);
    File('${d2.path}/.claude/.gate_failures.log')
        .writeAsStringSync('not a gate-failures log\n');
    final r2 = await _runHook(d2.path);
    expect(r2.exitCode, 0);
    final dec2 = _decision(r2);
    expect(dec2, isNotNull);
    expect(dec2!['reason'], contains('gate_failures_7d=unknown'));
    expect(dec2['reason'], isNot(contains('gate_failures_7d=0')));
    // No-news must not hide beside unknown: top_gate renders unknown too.
    expect(dec2['reason'], contains('top_gate=unknown'));
  });
}
