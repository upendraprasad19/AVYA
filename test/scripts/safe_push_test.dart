// test/scripts/safe_push_test.dart
//
// Minimal, deliberately NARROW coverage for scripts/safe_push.sh -- this
// file had ZERO automated coverage before this batch (a pre-existing gap,
// not introduced here; its SSH-keep-alive and ls-remote-retry logic are
// untouched by this batch and are NOT tested here -- that is a separate,
// larger undertaking out of scope for this fix). This test exists ONLY to
// pin the one thing this batch actually changed in safe_push.sh: the
// round-2 review's blocking #2 (safe_merge.sh's identical EXTRA_ARGS="$*"
// word-splitting bug) applied here too. safe_push.sh's own typical extra
// args (-u, --force-with-lease, --tags) are single tokens so the bug never
// bit in practice, but the underlying defect was the same, and it was
// fixed the same way (shift + "$@") in the same commit.
//
// ENV SCRUBBING IS LOAD-BEARING -- see plan_review_record_gate_e2e_test.dart's
// header for why (feedback_mistake_git_hook_env_leak): a surrounding git hook
// exports GIT_DIR/GIT_WORK_TREE, which override BOTH `workingDirectory:` and
// `-C <path>`, so an unscrubbed child git would operate on the REAL repo.

@Timeout(Duration(minutes: 14))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The REAL reader, so the writer->reader test below cannot pass by agreeing
// with a local helper that shares none of its code.
import '../../scripts/push_result_lib.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd) {
  return Process.runSync(exe, args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true);
}

String _fileUri(String path) => 'file:///${path.replaceAll('\\', '/')}';

/// Builds a throwaway bare remote + a primary clone with safe_push.sh copied
/// in, and returns their paths. Aborts loudly if GIT_* scrubbing failed and the
/// "throwaway" repo actually resolved to the real one -- see the header.
({String remote, String primary}) _setupRepo(Directory tmp, String srcRoot) {
  final remote = '${tmp.path}/remote.git';
  final primary = '${tmp.path}/primary';

  Directory(remote).createSync(recursive: true);
  expect(_run('git', ['init', '-q', '--bare', '-b', 'main', '.'], remote).exitCode, 0);

  Directory(primary).createSync(recursive: true);
  expect(_run('git', ['clone', '-q', _fileUri(remote), '.'], primary).exitCode, 0,
      reason: 'setup: cloning the empty bare remote must succeed');
  _run('git', ['config', 'user.email', 'test@example.invalid'], primary);
  _run('git', ['config', 'user.name', 'Test'], primary);

  final resolved =
      (_run('git', ['rev-parse', '--show-toplevel'], primary).stdout as String).trim();
  if (!resolved.toLowerCase().contains('safe_push_e2e_')) {
    throw StateError(
        'ENV LEAK: throwaway primary resolved to "$resolved", not the temp dir. '
        'GIT_* scrubbing failed -- aborting rather than running assertions '
        'against the real repository.');
  }

  Directory('$primary/scripts').createSync(recursive: true);
  for (final f in const [
    'safe_push.sh',
    '_git_lock.sh',
    // safe_push.sh's LANDED path arms a CI-reconcile entry through this. It is
    // `|| true`-wrapped, so omitting it here would not redden anything -- the
    // append would just fail silently and the arm assertion below would be
    // testing nothing.
    'arm_ci_reconcile.sh',
  ]) {
    File('$srcRoot/scripts/$f').copySync('$primary/scripts/$f');
  }
  File('$primary/seed.txt').writeAsStringSync('seed\n');
  _run('git', ['add', '-A'], primary);
  _run('git', ['commit', '-qm', 'seed'], primary);

  return (remote: remote, primary: primary);
}

Directory _tmp() {
  final tmp = Directory.systemTemp.createTempSync('safe_push_e2e_');
  addTearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* best effort on Windows file locks */}
  });
  return tmp;
}

void main() {
  // ---------------------------------------------------------------------
  // The landing-verification contract. Three outcomes, not two.
  //
  // Both tests below FAIL against the pre-2026-08-11 script, which exited 0
  // in both scenarios -- it could not tell "the ref is absent" from "I could
  // not reach the remote", because `ls-remote ... | cut -f1` yields an empty
  // string for both AND makes `$?` the exit status of `cut`.
  // ---------------------------------------------------------------------

  test(
      'a push that does NOT move the ref exits 1 FAILED -- not 0. Before the '
      'fix, an absent ref was indistinguishable from a failed probe and the '
      'script exited 0 with only a stderr WARNING.', () {
    final srcRoot = Directory.current.path;
    final repo = _setupRepo(_tmp(), srcRoot);

    // --dry-run makes git push exit 0 while provably NOT moving the remote
    // ref -- the exact shape the wrapper exists to catch (git says success,
    // the remote never moved), reproduced with real git rather than a stub.
    final r = _run('sh',
        ['scripts/safe_push.sh', 'origin', 'main', '--dry-run'], repo.primary);

    expect(r.exitCode, 1,
        reason: 'git push exited 0 but refs/heads/main was never created on '
            'the remote, so this MUST be reported as a failure.\n'
            'stdout:\n${r.stdout}\nstderr:\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('did NOT move'),
        reason: 'the failure must name the actual problem.\n'
            'stdout:\n${r.stdout}\nstderr:\n${r.stderr}');

    // Ground truth: the ref really is absent, so exit 1 is correct and this
    // test is not passing for an unrelated reason.
    final ls = _run('git', ['ls-remote', 'origin', 'refs/heads/main'], repo.primary);
    expect(ls.exitCode, 0, reason: 'the probe itself must have succeeded');
    expect((ls.stdout as String).trim(), isEmpty,
        reason: 'refs/heads/main must genuinely not exist on the remote');
  });

  test(
      'an unreachable remote after a successful push exits 2 UNVERIFIED -- '
      'neither 0 (the old behaviour: claiming a landing it never observed) '
      'nor 1 (which would cry wolf on a push that may well have landed).', () {
    final srcRoot = Directory.current.path;
    final tmp = _tmp();
    final repo = _setupRepo(tmp, srcRoot);

    // Split the push URL from the fetch URL: `git push` uses the pushurl (a
    // real bare repo, so it succeeds and the ref genuinely moves), while
    // `git ls-remote` uses the fetch url (a path that does not exist, so the
    // probe fails non-zero). That isolates "probe failed" from "ref absent"
    // using nothing but real git behaviour.
    _run('git', ['remote', 'set-url', '--push', 'origin', _fileUri(repo.remote)],
        repo.primary);
    _run('git', ['remote', 'set-url', 'origin', _fileUri('${tmp.path}/no-such.git')],
        repo.primary);

    final r = _run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary);

    expect(r.exitCode, 2,
        reason: 'the push succeeded but could not be confirmed; that is its '
            'own outcome and must never be reported as success.\n'
            'stdout:\n${r.stdout}\nstderr:\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('UNVERIFIED'),
        reason: 'the operator must be told the landing was not observed.\n'
            'stdout:\n${r.stdout}\nstderr:\n${r.stderr}');

    // Ground truth: the push DID land (via the pushurl), which is precisely
    // why exit 1 "FAILED" would be wrong here and exit 2 is the honest answer.
    final ls = _run('git', ['ls-remote', _fileUri(repo.remote), 'refs/heads/main'],
        repo.primary);
    expect((ls.stdout as String).trim(), isNotEmpty,
        reason: 'the push really did land on the push URL, so reporting a '
            'flat FAILURE would be the F6 false positive');
  });

  test('a genuinely landed push still exits 0 and reports the observed sha',
      () {
    final srcRoot = Directory.current.path;
    final repo = _setupRepo(_tmp(), srcRoot);

    final r = _run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary);

    expect(r.exitCode, 0,
        reason: 'the happy path must be unaffected by the verifier rework.\n'
            'stdout:\n${r.stdout}\nstderr:\n${r.stderr}');
    final localSha =
        (_run('git', ['rev-parse', 'main'], repo.primary).stdout as String).trim();
    expect('${r.stdout}', contains(localSha),
        reason: 'success must report the sha it actually OBSERVED on the '
            'remote, not merely announce success.\n${r.stdout}');

    // A landed push must ARM a CI-reconcile entry. safe_push.sh can only prove
    // the ref moved; the arm is what lets reconcile_ci.dart later report what
    // CI concluded. The call is `|| true`-wrapped, so if it silently stopped
    // working nothing else in this suite would notice -- which is exactly why
    // it is asserted here rather than assumed.
    final state = File('${repo.primary}/.claude/.ci_reconcile_pending.jsonl');
    expect(state.existsSync(), isTrue,
        reason: 'safe_push.sh LANDED path must have armed a reconcile entry.\n'
            'stdout:\n${r.stdout}');
    final armed = state.readAsStringSync();
    expect(armed, contains(localSha),
        reason: 'the armed entry must name the sha that actually landed');
    expect(armed, contains('"branch":"main"'),
        reason: 'the armed entry must name the branch that was pushed');
  });

  test(
      'a push that git reports as FAILED still exits 0 when the remote ref is '
      'OBSERVED at our tip -- the SIGPIPE-after-landing case this wrapper was '
      'written for (B-pass finding 1: the retry is deliberately not gated on '
      'GIT_EXIT, and nothing tested that)', () {
    final srcRoot = Directory.current.path;
    final repo = _setupRepo(_tmp(), srcRoot);

    // Land the ref for real first.
    expect(_run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary)
        .exitCode,
        0,
        reason: 'setup: the first push must genuinely land');

    // Now force `git push` itself to fail while the remote ref is ALREADY at
    // our local tip -- an unknown flag makes git exit non-zero without moving
    // anything. That is the shape of the founding incident: git reports
    // failure, yet the work is provably on the remote.
    final r = _run(
        'sh',
        ['scripts/safe_push.sh', 'origin', 'main', '--no-such-flag-xyz'],
        repo.primary);

    expect(r.exitCode, 0,
        reason: 'an OBSERVED remote at our tip is stronger evidence than '
            "git's own exit code -- that is this wrapper's founding premise. "
            'Reporting FAILED here would be the F6 false positive.\n'
            'stdout:\n${r.stdout}\nstderr:\n${r.stderr}');

    // Ground truth: git push really did fail, so this is not passing because
    // the push quietly succeeded.
    final direct = _run('git', ['push', 'origin', 'main', '--no-such-flag-xyz'],
        repo.primary);
    expect(direct.exitCode, isNot(0),
        reason: 'the flag must genuinely make git push fail, or this test '
            'proves nothing');
  });

  test(
      'the unreachable duplicate success block is gone (source assertion -- '
      'presence only, since unreachable code cannot be exercised at runtime)',
      () {
    final src = File('${Directory.current.path}/scripts/safe_push.sh')
        .readAsStringSync();
    // Structural, not message-based: the removed block was a SECOND, identical
    // `[ "$REMOTE_SHA" = "$LOCAL_SHA" ]` success test, unreachable-true on every
    // route. Exactly one such test must remain. Keyed on the condition rather
    // than the "confirmed on retry" wording because that wording is now carried
    // by a genuinely REACHABLE path (the retry-succeeded message).
    final matches =
        RegExp(r'"\$REMOTE_SHA" = "\$LOCAL_SHA"').allMatches(src).length;
    expect(matches, 1,
        reason: r'pre-fix there were TWO identical `$REMOTE_SHA = $LOCAL_SHA` '
            'success tests (old :80 and :110); the second was unreachable-true '
            'on every route while reading as a live success path, in the one '
            'file whose job is to be trusted about whether a push landed. '
            'Found $matches.');
  });

  test(
      'a multi-word push-option (-o "...") survives as ONE argument, not '
      'word-split into extra bogus refspecs (round-2 review blocking #2, '
      'same defect as safe_merge.sh, fixed the same way)', () {
    final srcRoot = Directory.current.path;
    final tmp = Directory.systemTemp.createTempSync('safe_push_e2e_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best effort on Windows file locks */}
    });

    final remote = '${tmp.path}/remote.git';
    final primary = '${tmp.path}/primary';

    Directory(remote).createSync(recursive: true);
    expect(
        _run('git', ['init', '-q', '--bare', '-b', 'main', '.'], remote)
            .exitCode,
        0);

    Directory(primary).createSync(recursive: true);
    expect(
        _run('git', ['clone', '-q', _fileUri(remote), '.'], primary)
            .exitCode,
        0,
        reason: 'setup: cloning the empty bare remote must succeed');
    _run('git', ['config', 'user.email', 'test@example.invalid'], primary);
    _run('git', ['config', 'user.name', 'Test'], primary);

    final top = _run('git', ['rev-parse', '--show-toplevel'], primary);
    final resolved = (top.stdout as String).trim();
    if (!resolved.toLowerCase().contains('safe_push_e2e_')) {
      throw StateError(
          'ENV LEAK: throwaway primary resolved to "$resolved", not the '
          'temp dir. GIT_* scrubbing failed -- aborting rather than '
          'running assertions against the real repository.');
    }

    Directory('$primary/scripts').createSync(recursive: true);
    for (final f in const [
    'safe_push.sh',
    '_git_lock.sh',
    // safe_push.sh's LANDED path arms a CI-reconcile entry through this. It is
    // `|| true`-wrapped, so omitting it here would not redden anything -- the
    // append would just fail silently and the arm assertion below would be
    // testing nothing.
    'arm_ci_reconcile.sh',
  ]) {
      File('$srcRoot/scripts/$f').copySync('$primary/scripts/$f');
    }
    File('$primary/seed.txt').writeAsStringSync('seed\n');
    _run('git', ['add', '-A'], primary);
    _run('git', ['commit', '-qm', 'seed'], primary);

    // Enable the receiving remote to accept arbitrary push options, and
    // capture whatever it actually receives via a pre-receive hook -- the
    // most direct way to observe what git-push actually transmitted,
    // rather than inferring it from safe_push.sh's own exit code alone.
    _run('git', ['config', 'receive.advertisePushOptions', 'true'], remote);
    final hookDir = Directory('$remote/hooks')..createSync(recursive: true);
    final hookPath = '${hookDir.path}/pre-receive';
    File(hookPath).writeAsStringSync('''
#!/usr/bin/env sh
env | grep '^GIT_PUSH_OPTION_' > "\$(dirname "\$0")/../../captured_push_options.txt" 2>/dev/null
exit 0
''');
    // Hooks must be executable; Git for Windows' Bash respects the file
    // mode bit even though NTFS itself has no exec permission concept.
    Process.runSync('chmod', ['+x', hookPath], runInShell: true);

    const multiWordOption = 'ci message with several distinct words';
    final r = _run('sh',
        ['scripts/safe_push.sh', 'origin', 'main', '-o', multiWordOption],
        primary);

    expect(r.exitCode, 0,
        reason: 'a multi-word -o push-option must be accepted, not '
            'shredded into extra unresolvable refspec arguments.\n'
            '${r.stdout}${r.stderr}');

    final capturedFile = File('${tmp.path}/captured_push_options.txt');
    expect(capturedFile.existsSync(), isTrue,
        reason: 'the remote pre-receive hook must have fired and captured '
            'something.\n${r.stdout}${r.stderr}');
    final captured = capturedFile.readAsStringSync();
    expect(captured, contains('GIT_PUSH_OPTION_0=$multiWordOption'),
        reason: 'the remote must receive the push option as ONE opaque '
            'string, proving it was never word-split by safe_push.sh. '
            'Captured:\n$captured');
    // If the bug were present, git would either fail outright (a stray
    // trailing word interpreted as an invalid extra refspec) or, at best,
    // split the option into multiple GIT_PUSH_OPTION_<N> entries -- assert
    // there is exactly one. (Deliberately excludes GIT_PUSH_OPTION_COUNT,
    // which is itself always present and would otherwise inflate this
    // count by one regardless of splitting.)
    expect(RegExp(r'GIT_PUSH_OPTION_\d+=').allMatches(captured).length, 1,
        reason: 'exactly one numbered push option must have been received, '
            'not several fragments from word-splitting.\nCaptured:\n'
            '$captured');
    expect(captured, contains('GIT_PUSH_OPTION_COUNT=1'),
        reason: 'git itself must also report receiving exactly one push '
            'option.\nCaptured:\n$captured');
  });

  // =====================================================================
  // OI-172 -- the terminal push-result record.
  //
  // safe_push.sh distinguishes THREE outcomes, and before this batch nothing
  // recorded WHICH one happened: the only in-flight evidence was the lock's
  // `holder` file, which _git_lock.sh deletes via a trap on EXIT/HUP/INT/TERM.
  // So a push that was reaped, interrupted, or run in a now-closed terminal
  // left nothing to read afterwards.
  //
  // These tests pin the WRITER. The READER contract is pinned separately, and
  // purely, in test/scripts/push_result_lib_test.dart -- including the
  // two-refs-at-one-sha case, which is where the contract is easiest to get
  // wrong.
  // =====================================================================

  /// The record path, resolved the way the script resolves it.
  ///
  /// `--absolute-git-dir`, NOT `--git-dir`: the latter returns a RELATIVE
  /// `.git` in a primary worktree, which a reader elsewhere would resolve
  /// against its own cwd.
  String recordPath(String repo) =>
      (_run('git', ['rev-parse', '--absolute-git-dir'], repo).stdout as String)
              .trim() +
          '/.safe_push_result';

  Map<String, String> readRecord(String repo) {
    final f = File(recordPath(repo));
    if (!f.existsSync()) return <String, String>{};
    final out = <String, String>{};
    for (final line in f.readAsStringSync().split('\n')) {
      final t = line.trim();
      final eq = t.indexOf('=');
      if (eq > 0) out.putIfAbsent(t.substring(0, eq), () => t.substring(eq + 1));
    }
    return out;
  }

  test('a LANDED push records result=LANDED with local_sha == remote_sha', () {
    final repo = _setupRepo(_tmp(), Directory.current.path);
    final r = _run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');

    final rec = readRecord(repo.primary);
    expect(rec['result'], 'LANDED');
    expect(rec['exit'], '0');
    expect(rec['ref'], 'refs/heads/main');
    expect(rec['local_sha'], isNotEmpty);
    expect(rec['remote_sha'], rec['local_sha'],
        reason: 'LANDED means the remote was OBSERVED at our tip');
    expect(rec['verified_ref'], 'refs/heads/main');
    expect(rec['pid'], isNotEmpty);
    expect(rec['ended'], isNotEmpty, reason: 'a terminal record is timestamped');
  });

  test(
      'the record lands in the git dir, NOT the worktree -- nothing named '
      'safe_push_result appears in `git status --ignored`. This is the '
      'anti-regression for the class that has already made a worktree '
      'permanently unretirable three times.', () {
    final repo = _setupRepo(_tmp(), Directory.current.path);

    expect(_run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary)
        .exitCode, 0);

    expect(File(recordPath(repo.primary)).existsSync(), isTrue,
        reason: 'the record must exist, or this test passes vacuously');
    expect(recordPath(repo.primary), contains('.git'),
        reason: 'the record must live inside the git admin dir');
    expect(File('${repo.primary}/.safe_push_result').existsSync(), isFalse);
    expect(
        File('${repo.primary}/.claude/.last_push_result').existsSync(), isFalse);

    final after = (_run('git', ['status', '--porcelain', '--ignored'],
            repo.primary)
        .stdout as String);
    // arm_ci_reconcile.sh legitimately adds `.claude/` here, so assert only
    // that no reported path is OURS rather than requiring byte-identity.
    expect(after, isNot(contains('safe_push_result')),
        reason: 'the record must be invisible to git status.\n$after');
  });

  test('a rejected push records result=FAILED with a non-empty reason', () {
    final tmp = _tmp();
    final repo = _setupRepo(tmp, Directory.current.path);
    expect(_run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary)
        .exitCode, 0);

    // Move the remote ahead from a second clone so our next push is rejected.
    final other = '${tmp.path}/other';
    Directory(other).createSync(recursive: true);
    expect(_run('git', ['clone', '-q', _fileUri(repo.remote), '.'], other).exitCode, 0);
    _run('git', ['config', 'user.email', 'test@example.invalid'], other);
    _run('git', ['config', 'user.name', 'Test'], other);
    File('$other/theirs.txt').writeAsStringSync('theirs\n');
    _run('git', ['add', '-A'], other);
    _run('git', ['commit', '-qm', 'theirs'], other);
    expect(_run('git', ['push', '-q', 'origin', 'main'], other).exitCode, 0);

    File('${repo.primary}/mine.txt').writeAsStringSync('mine\n');
    _run('git', ['add', '-A'], repo.primary);
    _run('git', ['commit', '-qm', 'mine'], repo.primary);

    final r = _run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary);
    expect(r.exitCode, isNot(0));
    final rec = readRecord(repo.primary);
    expect(rec['result'], 'FAILED');
    expect(rec['reason'], isNotEmpty,
        reason: 'a FAILED record must say why, or it adds nothing to the exit code');
  });

  test(
      'an unreachable PROBE after a SUCCESSFUL push records UNVERIFIED with an '
      'EMPTY remote_sha -- never FAILED. Collapsing the two re-creates '
      'diagnose d4f9b2, which is the bug exit code 2 exists to prevent.', () {
    final tmp = _tmp();
    final repo = _setupRepo(tmp, Directory.current.path);

    // FIXTURE NOTE, learned by getting it wrong first: pointing `origin` at a
    // nonexistent path does NOT reach this branch. `git push` itself then fails
    // (exit 128) and the script takes the FAILED path instead. UNVERIFIED
    // requires the push to SUCCEED and only the PROBE to fail, so `git` has to
    // be stubbed on PATH to fail `ls-remote` alone.
    final stubDir = Directory('${tmp.path}/stub')..createSync(recursive: true);
    final realGit = (Process.runSync('sh', ['-c', 'command -v git'],
            runInShell: true)
        .stdout as String)
        .trim();
    expect(realGit, isNotEmpty, reason: 'could not locate the real git');
    final stub = File('${stubDir.path}/git');
    stub.writeAsStringSync('#!/bin/sh\n'
        'if [ "\$1" = "ls-remote" ]; then exit 128; fi\n'
        'exec "$realGit" "\$@"\n');
    Process.runSync('chmod', ['+x', stub.path], runInShell: true);

    // The PATH entry MUST be POSIX-form. A Windows `C:/...` entry is not
    // searched by this MSYS shell, so the stub would be silently ignored, the
    // real ls-remote would succeed, and this test would assert LANDED while
    // claiming to test UNVERIFIED -- green for the wrong reason.
    final posixStub = (Process.runSync('cygpath', ['-u', stubDir.path],
            runInShell: true)
        .stdout as String)
        .trim();
    expect(posixStub, startsWith('/'),
        reason: 'cygpath must yield a POSIX path or the stub is never found');

    final env = _cleanEnv();
    env['PATH'] = '$posixStub:${env['PATH']}';
    final r = Process.runSync('sh', ['scripts/safe_push.sh', 'origin', 'main'],
        workingDirectory: repo.primary,
        environment: env,
        includeParentEnvironment: false,
        runInShell: true);

    expect(r.exitCode, 2,
        reason: 'UNVERIFIED is exit 2, distinct from both 0 and 1.\n'
            '${r.stdout}${r.stderr}');
    final rec = readRecord(repo.primary);
    expect(rec['result'], 'UNVERIFIED');
    expect(rec['exit'], '2');
    expect(rec['remote_sha'], isEmpty,
        reason: 'nothing was observed on the remote, so this must be empty '
            'rather than carry a stale or invented sha');
    expect(rec['result'], isNot('FAILED'));
  });

  test('a second push OVERWRITES the record rather than appending to it', () {
    final repo = _setupRepo(_tmp(), Directory.current.path);
    expect(_run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary)
        .exitCode, 0);
    final firstSha = readRecord(repo.primary)['local_sha'];

    File('${repo.primary}/second.txt').writeAsStringSync('second\n');
    _run('git', ['add', '-A'], repo.primary);
    _run('git', ['commit', '-qm', 'second'], repo.primary);
    expect(_run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary)
        .exitCode, 0);

    final text = File(recordPath(repo.primary)).readAsStringSync();
    expect(RegExp(r'^result=', multiLine: true).allMatches(text).length, 1,
        reason: 'exactly ONE record, not an accumulating log:\n$text');
    expect(readRecord(repo.primary)['local_sha'], isNot(firstSha));
  });

  test(
      'a pre-push ABORT leaves the prior record untouched, and its local_sha '
      'therefore stops matching HEAD -- which is what makes the four silent '
      'abort paths harmless rather than misleading', () {
    final repo = _setupRepo(_tmp(), Directory.current.path);
    expect(_run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary)
        .exitCode, 0);
    final landedSha = readRecord(repo.primary)['local_sha'];
    expect(landedSha, isNotEmpty);

    // Abort before any push is attempted: an unresolvable branch name.
    final r = _run(
        'sh', ['scripts/safe_push.sh', 'origin', 'no-such-branch-xyz'], repo.primary);
    expect(r.exitCode, isNot(0));

    final rec = readRecord(repo.primary);
    expect(rec['result'], 'LANDED',
        reason: 'the abort must NOT have written a FAILED record -- no push was '
            'attempted, so claiming failure would be a lie');
    expect(rec['local_sha'], landedSha);

    // Advance HEAD. The stale record's sha now cannot match, so a reader
    // following the contract gets UNVERIFIED instead of a stale verdict.
    File('${repo.primary}/third.txt').writeAsStringSync('third\n');
    _run('git', ['add', '-A'], repo.primary);
    _run('git', ['commit', '-qm', 'third'], repo.primary);
    final head =
        (_run('git', ['rev-parse', 'HEAD'], repo.primary).stdout as String).trim();
    expect(readRecord(repo.primary)['local_sha'], isNot(head));
  });

  test(
      'a record write that FAILS does not fail the push -- the record is '
      'advisory, the push verdict is not', () {
    final repo = _setupRepo(_tmp(), Directory.current.path);
    // Squat the record path with a DIRECTORY. `mv -T` refuses that outright;
    // plain `mv` would exit 0 and move the file INSIDE it, so the record would
    // land where no reader looks while the push reported success. That is why
    // the script mandates -T, and why this fixture only works because it does.
    Directory(recordPath(repo.primary)).createSync(recursive: true);

    final r = _run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary);
    expect(r.exitCode, 0,
        reason: 'an unwritable record must never turn a landed push into a '
            'reported failure.\n${r.stdout}${r.stderr}');
    expect(r.stdout as String, contains('OK --'));
    expect(Directory(recordPath(repo.primary)).existsSync(), isTrue);
    expect(Directory(recordPath(repo.primary)).listSync(), isEmpty,
        reason: 'mv -T must have REFUSED, not moved the file inside the '
            'directory the way plain mv does');
    expect(File('${recordPath(repo.primary)}.tmp').existsSync(), isFalse,
        reason: 'the refused candidate must be cleaned up, not left as litter '
            'inside .git for every later push to add to');
  });

  test(
      'a tag passed where a branch is expected records the namespace actually '
      'probed, so the wrong verdict is self-diagnosing', () {
    final repo = _setupRepo(_tmp(), Directory.current.path);
    expect(_run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary)
        .exitCode, 0);
    _run('git', ['tag', 'v9.9.9'], repo.primary);

    // probe_remote_sha() hardcodes refs/heads/$BRANCH, so the tag pushes but
    // the probe looks in the wrong namespace and the script reports FAILED for
    // a push that landed. PRE-EXISTING behaviour, not introduced by this batch;
    // the record makes it visible instead of silently wrong.
    final r = _run('sh', ['scripts/safe_push.sh', 'origin', 'v9.9.9'], repo.primary);
    expect(r.exitCode, isNot(0), reason: 'documenting current behaviour');

    final rec = readRecord(repo.primary);
    expect(rec['ref'], 'refs/tags/v9.9.9');
    expect(rec['verified_ref'], 'refs/heads/v9.9.9');
    expect(rec['ref'], isNot(rec['verified_ref']),
        reason: 'the mismatch is the signal push_result_lib.dart reads as '
            'probedTheWrongNamespace');
  });

  test('reason is sanitized to ONE line, so git stderr cannot inject a field',
      () {
    final tmp = _tmp();
    final repo = _setupRepo(tmp, Directory.current.path);
    expect(_run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary)
        .exitCode, 0);

    // A rejected push produces multi-line stderr; whatever lands in `reason`
    // must not add keys. Assert on the KEY SET, which is what a parser sees.
    final other = '${tmp.path}/other2';
    Directory(other).createSync(recursive: true);
    expect(_run('git', ['clone', '-q', _fileUri(repo.remote), '.'], other).exitCode, 0);
    _run('git', ['config', 'user.email', 'test@example.invalid'], other);
    _run('git', ['config', 'user.name', 'Test'], other);
    File('$other/x.txt').writeAsStringSync('x\n');
    _run('git', ['add', '-A'], other);
    _run('git', ['commit', '-qm', 'x'], other);
    _run('git', ['push', '-q', 'origin', 'main'], other);

    File('${repo.primary}/y.txt').writeAsStringSync('y\n');
    _run('git', ['add', '-A'], repo.primary);
    _run('git', ['commit', '-qm', 'y'], repo.primary);
    _run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary);

    final text = File(recordPath(repo.primary)).readAsStringSync();
    final keys = RegExp(r'^([a-z_]+)=', multiLine: true)
        .allMatches(text)
        .map((m) => m.group(1))
        .toList();
    expect(keys.length, keys.toSet().length,
        reason: 'no duplicated keys -- an injected line would duplicate one:\n$text');
    expect(keys, contains('reason'));
    final reasonLine =
        text.split('\n').firstWhere((l) => l.startsWith('reason='), orElse: () => '');
    expect(reasonLine, isNot(contains('\n')));
    expect(reasonLine.length, lessThanOrEqualTo(300));
  });


  test(
      'a push IN FLIGHT leaves result=STARTED carrying a LIVE pid -- the case '
      'that motivated OI-172, where the push was still running and no terminal '
      'verdict existed yet, so a terminal-only record would have been absent at '
      'exactly the moment it was wanted', () async {
    final tmp = _tmp();
    final repo = _setupRepo(tmp, Directory.current.path);

    // The mid-flight window is created DELIBERATELY, not sampled by luck: a
    // sleeping pre-receive hook on the receiving end holds the push open. An
    // implicit race here would be the 6th recurrence of the
    // green-targeted/red-in-the-suite class this repo has already paid for 5
    // times, because suite contention changes the timing.
    final hookDir = Directory('${repo.remote}/hooks')..createSync(recursive: true);
    final hookPath = '${hookDir.path}/pre-receive';
    File(hookPath).writeAsStringSync('#!/usr/bin/env sh\nsleep 6\nexit 0\n');
    Process.runSync('chmod', ['+x', hookPath], runInShell: true);

    final proc = await Process.start(
        'sh', ['scripts/safe_push.sh', 'origin', 'main'],
        workingDirectory: repo.primary,
        environment: _cleanEnv(),
        includeParentEnvironment: false,
        runInShell: true);
    // Drain, or a full pipe buffer could block the child on Windows.
    proc.stdout.drain<void>();
    proc.stderr.drain<void>();

    Map<String, String> seen = <String, String>{};
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final rec = readRecord(repo.primary);
      if (rec['result'] == 'STARTED') {
        seen = rec;
        break;
      }
      if (rec['result'] == 'LANDED') break; // finished before we sampled
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    expect(seen['result'], 'STARTED',
        reason: 'the record must exist and read STARTED while the push is still '
            'running -- a terminal-only record cannot answer "is a push in '
            'flight", which is the question the motivating incident asked');
    expect(seen['pid'], isNotEmpty);
    expect(seen['ended'], isEmpty,
        reason: 'an in-flight record has no end time; a non-empty `ended` here '
            'would let a reader mistake it for a verdict');
    expect(seen['exit'], '-',
        reason: 'no exit code exists yet, and writing 0 would read as success');
    expect(seen['local_sha'], isNotEmpty);

    // The pid must be a live process: that pairing is the whole point, since
    // STARTED alone cannot distinguish "running" from "interrupted".
    final alive = Process.runSync('sh', ['-c', 'kill -0 ${seen['pid']}'],
        runInShell: true);
    expect(alive.exitCode, 0,
        reason: 'pid ${seen['pid']} should still be alive while the remote hook '
            'sleeps');

    final code = await proc.exitCode;
    expect(code, 0, reason: 'the push itself must still succeed');
    final finalRec = readRecord(repo.primary);
    expect(finalRec['result'], 'LANDED',
        reason: 'the STARTED record must be REPLACED by the terminal verdict, '
            'not left behind for a later reader to misread');
    expect(finalRec['ended'], isNotEmpty);
  });


  test(
      'WRITER -> READER: a record produced by the real safe_push.sh is parsed '
      'and classified LANDED by push_result_lib.dart. This is the drift seam -- '
      'the writer is shell and the reader is Dart, so a renamed field would make '
      'the reader silently read empty and answer UNVERIFIED forever, which is '
      'fail-SAFE and therefore invisible.', () {
    final repo = _setupRepo(_tmp(), Directory.current.path);
    final r = _run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');

    // Parse with the REAL reader, not this file's local helper -- the local
    // helper shares no code with push_result_lib.dart, so it cannot detect a
    // field name the reader does not know about.
    final record = parsePushResult(File(recordPath(repo.primary)).readAsStringSync());
    expect(record, isNotNull,
        reason: 'the real reader must parse the real writer output');

    final head =
        (_run('git', ['rev-parse', 'HEAD'], repo.primary).stdout as String).trim();
    expect(
      classifyPushResult(record, wantRef: 'refs/heads/main', wantSha: head),
      PushVerdict.landed,
      reason: 'end-to-end: the shell wrote it, the Dart reader classified it, and '
          'the answer is the one the push actually achieved',
    );

    // And the mirror: the same real record must NOT be readable as a verdict
    // about a different ref, even though the sha matches exactly.
    expect(
      classifyPushResult(record, wantRef: 'refs/heads/other', wantSha: head),
      PushVerdict.unverified,
    );

    // Field-level drift guard: assert the reader actually POPULATED the fields it
    // classifies on, rather than defaulting them to '' and reaching `landed` by
    // some other route. A rename would leave these empty.
    expect(record!.ref, 'refs/heads/main');
    expect(record.localSha, head);
    expect(record.remoteSha, head);
    expect(record.verifiedRef, 'refs/heads/main');
    expect(record.pid, isNotEmpty);
    expect(record.isInFlight, isFalse);
    expect(record.probedTheWrongNamespace, isFalse);
  });


  test(
      'the KILL SWITCH suppresses the record without touching the push — and '
      'lives beside the record in the git dir, NOT in .claude/, because neither '
      'existing kill switch is in regenerableIgnoredPaths and a worktree holding '
      'one would be unretirable', () {
    final repo = _setupRepo(_tmp(), Directory.current.path);
    final marker = File('${recordPath(repo.primary)}.disabled')
      ..writeAsStringSync('');

    final r = _run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary);
    expect(r.exitCode, 0,
        reason: 'disabling the record must not affect the push at all.\n'
            '${r.stdout}${r.stderr}');
    expect(r.stdout as String, contains('OK --'));
    expect(File(recordPath(repo.primary)).existsSync(), isFalse,
        reason: 'no record may be written while the switch is present');

    // The mirror: remove it and the record comes back. Without this leg the test
    // would pass against a writer that is simply broken.
    marker.deleteSync();
    File('${repo.primary}/after.txt').writeAsStringSync('after\n');
    _run('git', ['add', '-A'], repo.primary);
    _run('git', ['commit', '-qm', 'after'], repo.primary);
    expect(_run('sh', ['scripts/safe_push.sh', 'origin', 'main'], repo.primary)
        .exitCode, 0);
    expect(File(recordPath(repo.primary)).existsSync(), isTrue,
        reason: 'with the switch gone the record must be written again');
    expect(readRecord(repo.primary)['result'], 'LANDED');

    // And the switch itself must not be visible to worktree retirement either.
    final status = (_run('git', ['status', '--porcelain', '--ignored'],
            repo.primary)
        .stdout as String);
    expect(status, isNot(contains('safe_push_result')));
  });

}
