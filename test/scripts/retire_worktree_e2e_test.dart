// test/scripts/retire_worktree_e2e_test.dart
//
// END-TO-END: builds a throwaway repo with THREE real linked worktrees
// (clean+merged / dirty / unmerged) and runs the real
// scripts/retire-worktree.dart against them, asserting what survives.
//
// WHY in addition to retire_worktree_lib_test.dart: the pure tests certify the
// predicate. They cannot prove the COMMAND gathers the right facts — that it
// counts `status --porcelain` lines correctly, that it reads merge state from
// the right branch, that `--execute` actually removes and `--dry-run` actually
// does not. Only running the binary against real worktrees shows that. Same
// lesson as plan_review_record_gate_e2e_test.dart's header.
//
// ENV SCRUBBING IS LOAD-BEARING. Inside `pre-commit`, a test that spawns its
// own git repo inherits GIT_DIR / GIT_WORK_TREE, which override BOTH
// `workingDirectory:` and `-C <path>` (feedback_mistake_git_hook_env_leak).
// For THIS test a leak would be actively destructive rather than merely
// meaningless: the command under test DELETES WORKTREES, and a leaked GIT_DIR
// would point it at the real repository. Hence the hard abort below if the
// isolation did not take.

@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd) => Process.runSync(
      exe,
      args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );

void main() {
  late Directory tmp;
  late String repo;

  final srcRoot = Directory.current.path;

  String wt(String name) => '$repo/.claude/worktrees/$name';

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('retire_wt_e2e_');
    repo = '${tmp.path}/main';
    Directory(repo).createSync(recursive: true);

    _run('git', ['init', '-q', '-b', 'main', '.'], repo);
    _run('git', ['config', 'user.email', 'test@example.invalid'], repo);
    _run('git', ['config', 'user.name', 'Test'], repo);

    // Prove isolation BEFORE anything destructive can run.
    final top = _run('git', ['rev-parse', '--show-toplevel'], repo);
    if (!(top.stdout as String).toLowerCase().contains('retire_wt_e2e_')) {
      throw StateError('ENV LEAK: git resolved to "${top.stdout}". Aborting — '
          'this test runs a command that DELETES worktrees.');
    }

    Directory('$repo/scripts').createSync(recursive: true);
    for (final f in const [
      'retire-worktree.dart',
      'retire_worktree_lib.dart',
    ]) {
      File('$srcRoot/scripts/$f').copySync('$repo/scripts/$f');
    }

    File('$repo/seed.txt').writeAsStringSync('seed\n');
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-q', '-m', 'seed'], repo);

    Directory('$repo/.claude/worktrees').createSync(recursive: true);

    // 1. clean + merged  -> the ONLY one that should be retired.
    //    Branch off main and merge it back so it is genuinely --merged.
    _run('git', ['worktree', 'add', '-q', wt('done-clean'), '-b', 'done-clean'],
        repo);
    _run('git', ['merge', '-q', '--no-ff', '-m', 'merge done-clean', 'done-clean'],
        repo);

    // 2. merged BUT dirty -> must survive (the killer case).
    _run('git', ['worktree', 'add', '-q', wt('done-dirty'), '-b', 'done-dirty'],
        repo);
    _run('git', ['merge', '-q', '--no-ff', '-m', 'merge done-dirty', 'done-dirty'],
        repo);
    File('${wt('done-dirty')}/uncommitted.txt')
        .writeAsStringSync('work nobody has committed\n');

    // 3. unmerged, clean -> must survive.
    _run('git', ['worktree', 'add', '-q', wt('wip'), '-b', 'wip'], repo);
    File('${wt('wip')}/f.txt').writeAsStringSync('x\n');
    _run('git', ['add', '-A'], wt('wip'));
    _run('git', ['commit', '-q', '-m', 'wip commit'], wt('wip'));

    // Verify the fixture is actually the shape the tests assume, rather than
    // trusting six setup commands to have all succeeded.
    for (final n in ['done-clean', 'done-dirty', 'wip']) {
      if (!Directory(wt(n)).existsSync()) {
        throw StateError('SETUP FAILED: worktree $n missing — assertions would '
            'pass vacuously.');
      }
    }
    final merged = _run(
        'git', ['branch', '--merged', 'main', '--format=%(refname:short)'], repo);
    final m = merged.stdout as String;
    if (!m.contains('done-clean') || !m.contains('done-dirty')) {
      throw StateError('SETUP FAILED: expected done-clean and done-dirty to be '
          'merged; got: $m');
    }
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* Windows file locks — a leaked temp dir is not worth a red suite */}
  });

  ProcessResult retire(List<String> extra) =>
      _run('dart', ['run', 'scripts/retire-worktree.dart', ...extra], repo);

  test('DRY-RUN (the default) removes nothing at all', () {
    final r = retire([]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout as String, contains('DRY-RUN'));
    for (final n in ['done-clean', 'done-dirty', 'wip']) {
      expect(Directory(wt(n)).existsSync(), isTrue,
          reason: 'dry-run must not delete $n');
    }
  });

  test('dry-run classifies each worktree correctly', () {
    final out = retire([]).stdout as String;
    expect(out, contains('RETIRE  done-clean'));
    expect(out, contains('KEEP    done-dirty'));
    expect(out, contains('uncommitted'));
    expect(out, contains('KEEP    wip'));
    expect(out, contains('not merged'));
  });

  test('refuses to run from a LINKED worktree', () {
    // Removing the tree you stand in is undefined.
    final r = _run('dart',
        ['run', '$repo/scripts/retire-worktree.dart'], wt('done-dirty'));
    expect(r.exitCode, 1);
    expect(r.stderr as String, contains('PRIMARY worktree'));
  });

  test('ABORTS while core.worktree is set — dirty checks would be garbage', () {
    _run('git', ['config', 'core.worktree', wt('wip')], repo);
    final r = retire([]);
    expect(r.exitCode, 1);
    expect(r.stderr as String, contains('core.worktree is set'));
    _run('git', ['config', '--unset-all', 'core.worktree'], repo);
    // Confirm the guard released, so later tests are not silently aborting.
    expect(retire([]).exitCode, 0);
  });

  test('--execute removes ONLY the clean+merged worktree', () {
    final r = retire(['--execute']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');

    expect(Directory(wt('done-clean')).existsSync(), isFalse,
        reason: 'clean+merged should be retired');
    expect(Directory(wt('done-dirty')).existsSync(), isTrue,
        reason: 'THE KILLER CASE: merged but dirty must survive --execute');
    expect(Directory(wt('wip')).existsSync(), isTrue,
        reason: 'unmerged must survive --execute');

    // And the surviving work is byte-intact, not merely present.
    expect(File('${wt('done-dirty')}/uncommitted.txt').readAsStringSync(),
        'work nobody has committed\n');
  });
}
