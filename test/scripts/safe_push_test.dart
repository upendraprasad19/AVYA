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

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
