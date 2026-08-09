// test/scripts/retire_worktree_e2e_test.dart
//
// END-TO-END: builds a throwaway repo with THREE real linked worktrees
// (clean+merged / dirty / unmerged) and runs the real
// scripts/retire_worktree.dart against them, asserting what survives.
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
    // .gitignore must exist BEFORE any worktree is created so the ignored-file
    // scenario below is genuinely ignored rather than merely untracked.
    // `.envrc` and `.envs/` are here specifically to exercise round-2's P0:
    // `.env` prefix-matching swept them up and destroyed them.
    File('$repo/.gitignore')
        .writeAsStringSync('secrets/\n.env\n.envrc\n.envs/\n');

    // Prove isolation BEFORE anything destructive can run.
    final top = _run('git', ['rev-parse', '--show-toplevel'], repo);
    if (!(top.stdout as String).toLowerCase().contains('retire_wt_e2e_')) {
      throw StateError('ENV LEAK: git resolved to "${top.stdout}". Aborting — '
          'this test runs a command that DELETES worktrees.');
    }

    Directory('$repo/scripts').createSync(recursive: true);
    for (final f in const [
      'retire_worktree.dart',
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

    // 4. merged + clean by `git status` BUT holding a non-regenerable IGNORED
    //    file. Round-1 P0: status --porcelain hides these and `worktree remove`
    //    does not refuse, so the file was destroyed silently.
    _run('git', ['worktree', 'add', '-q', wt('ignored'), '-b', 'ignored'], repo);
    _run('git', ['merge', '-q', '--no-ff', '-m', 'merge ignored', 'ignored'], repo);
    Directory('${wt("ignored")}/secrets').createSync(recursive: true);
    File('${wt("ignored")}/secrets/creds.txt')
        .writeAsStringSync('irreplaceable\n');

    // 5. merged + clean + holding ONLY regenerable ignored files (.env). Must
    //    still RETIRE — every worktree in this repo has one (§4.13 copies it
    //    in), so if these blocked, nothing would ever be retirable.
    _run('git', ['worktree', 'add', '-q', wt('envonly'), '-b', 'envonly'], repo);
    _run('git', ['merge', '-q', '--no-ff', '-m', 'merge envonly', 'envonly'], repo);
    File('${wt("envonly")}/.env').writeAsStringSync('SUPABASE_URL=x\n');

    // 6. ROUND-2 P0 at e2e level: merged + clean, holding an ignored `.envrc`
    //    (direnv secrets) and an ignored `.envs/` tree. Prefix-matching `.env`
    //    classified BOTH as regenerable and deleted them. Must survive.
    _run('git', ['worktree', 'add', '-q', wt('envrc'), '-b', 'envrc'], repo);
    _run('git', ['merge', '-q', '--no-ff', '-m', 'merge envrc', 'envrc'], repo);
    File('${wt("envrc")}/.envrc').writeAsStringSync('export SECRET=real\n');
    Directory('${wt("envrc")}/.envs').createSync(recursive: true);
    File('${wt("envrc")}/.envs/prod.key').writeAsStringSync('irreplaceable\n');

    // 7. ROUND-3 P0: the `.env` ignore rule is UNANCHORED, so git emits a
    //    NESTED `.env` as its own `!!` entry. Basename-at-any-depth matching
    //    classified it regenerable and DESTROYED it. This repo really carries
    //    `supabase/.env` (518 bytes, .gitignore:69); only the ROOT `.env` is
    //    reconstructible (new-worktree.sh copies exactly that one).
    _run('git', ['worktree', 'add', '-q', wt('nestedenv'), '-b', 'nestedenv'],
        repo);
    _run('git',
        ['merge', '-q', '--no-ff', '-m', 'merge nestedenv', 'nestedenv'], repo);
    Directory('${wt("nestedenv")}/supabase').createSync(recursive: true);
    File('${wt("nestedenv")}/supabase/.env')
        .writeAsStringSync('SERVICE_ROLE_KEY=irreplaceable\n');

    // 8. merged + clean but LOCKED. A lock is an explicit do-not-touch. Without
    //    honouring it the tool attempts removal, git refuses, and a routine
    //    sweep exits 1. `locked` is emitted AFTER `branch` in the porcelain, so
    //    a parser that flushed on `branch` never saw it (it shipped inert).
    _run('git', ['worktree', 'add', '-q', wt('lockedwt'), '-b', 'lockedwt'], repo);
    _run('git',
        ['merge', '-q', '--no-ff', '-m', 'merge lockedwt', 'lockedwt'], repo);
    _run('git', ['worktree', 'lock', wt('lockedwt'), '--reason', 'do not touch'],
        repo);

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
      _run('dart', ['run', 'scripts/retire_worktree.dart', ...extra], repo);

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
        ['run', '$repo/scripts/retire_worktree.dart'], wt('done-dirty'));
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

  test('a worktree with an IGNORED file is kept, not silently destroyed', () {
    final out = retire([]).stdout as String;
    expect(out, contains('KEEP    ignored'));
    expect(out, contains('non-regenerable ignored'));
  });

  test('a worktree holding ONLY regenerable ignored files still retires', () {
    // Otherwise the .env that §4.13 puts in every worktree would make the tool
    // permanently inert.
    expect(retire([]).stdout as String, contains('RETIRE  envonly'));
  });

  test('a slug matching nothing FAILS instead of silently sweeping orphans',
      () {
    // Round-1 F4: `--execute <unmatched-slug>` previously deleted an orphan the
    // operator never named, and reported success.
    final r = retire(['--execute', 'no-such-worktree-xyz']);
    expect(r.exitCode, 1);
    expect(r.stderr as String, contains('no registered worktree named'));
  });

  test('a LOCKED worktree is kept, and the sweep does not fail', () {
    // Pre-fix this printed RETIRE, then `--execute` produced
    // `FAILED lockedwt [fatal: cannot remove a locked working tree]` + exit 1 —
    // verbatim the outcome the code claimed to prevent.
    final out = retire([]).stdout as String;
    expect(out, contains('KEEP    lockedwt'));
    expect(out, contains('protected'));
  });

  test('--execute removes ONLY the retirable worktrees', () {
    final r = retire(['--execute']);
    expect(r.exitCode, 0,
        reason: 'a locked worktree must not redden a routine sweep: '
            '${r.stdout}${r.stderr}');

    expect(Directory(wt('done-clean')).existsSync(), isFalse,
        reason: 'clean+merged should be retired');
    expect(Directory(wt('envonly')).existsSync(), isFalse,
        reason: 'only-regenerable-ignored should be retired');

    expect(Directory(wt('done-dirty')).existsSync(), isTrue,
        reason: 'THE KILLER CASE: merged but dirty must survive --execute');
    expect(Directory(wt('wip')).existsSync(), isTrue,
        reason: 'unmerged must survive --execute');
    expect(Directory(wt('ignored')).existsSync(), isTrue,
        reason: 'THE ROUND-1 P0: an ignored file must survive --execute');
    expect(Directory(wt('envrc')).existsSync(), isTrue,
        reason: 'THE ROUND-2 P0: .envrc/.envs must not be swept up by `.env` '
            'prefix matching');
    expect(Directory(wt('nestedenv')).existsSync(), isTrue,
        reason: 'THE ROUND-3 P0: a NESTED .env is not the root .env and is not '
            'regenerable');
    expect(Directory(wt('lockedwt')).existsSync(), isTrue,
        reason: 'a locked worktree is an explicit do-not-touch');

    // Surviving work is byte-intact, not merely present.
    expect(File('${wt('done-dirty')}/uncommitted.txt').readAsStringSync(),
        'work nobody has committed\n');
    expect(File('${wt('ignored')}/secrets/creds.txt').readAsStringSync(),
        'irreplaceable\n');
    expect(File('${wt('envrc')}/.envs/prod.key').readAsStringSync(),
        'irreplaceable\n');
  });
}
