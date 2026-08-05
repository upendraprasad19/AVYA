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

void main() {
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
    for (final f in const ['safe_push.sh', '_git_lock.sh']) {
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
