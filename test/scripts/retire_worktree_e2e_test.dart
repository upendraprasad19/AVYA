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

@Timeout(Duration(minutes: 8))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

ProcessResult _run(String exe, List<String> args, String cwd) => runSpawn(
      exe,
      args,
      why: 'retire_worktree e2e: $exe ${args.join(' ')} (in $cwd)',
      workingDirectory: cwd,
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
    final r = retire(['--execute', '--all']);
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

  // ── Branch deletion after retirement (OI-138) ──────────────────────────────
  //
  // EVERY test below builds its OWN throwaway repo. The shared `setUpAll` repo
  // above is mutated by its last test (`--execute`), so tests that depended on
  // it would depend on file order. Each case needs at most two `dart run`
  // spawns: CLAUDE.md §4.9 measures the Dart wrapper at 3.4-10.5 s per spawn on
  // the Windows dev machine, and this file runs under suite-wide contention.
  group('branch deletion after retirement (OI-138)', () {
    final made = <Directory>[];

    tearDownAll(() {
      for (final d in made) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {/* hygiene, not an assertion */}
      }
    });

    /// A fresh primary repo (branch `main`, one seed commit) with the two
    /// scripts copied in and isolation proven before anything can delete.
    String freshRepo() {
      final t = Directory.systemTemp.createTempSync('retire_br_e2e_');
      made.add(t);
      final r = '${t.path}/main';
      Directory(r).createSync(recursive: true);
      _run('git', ['init', '-q', '-b', 'main', '.'], r);
      _run('git', ['config', 'user.email', 'test@example.invalid'], r);
      _run('git', ['config', 'user.name', 'Test'], r);
      final top = _run('git', ['rev-parse', '--show-toplevel'], r);
      if (!(top.stdout as String).toLowerCase().contains('retire_br_e2e_')) {
        throw StateError('ENV LEAK: git resolved to "${top.stdout}". Aborting — '
            'this test runs a command that DELETES worktrees and branches.');
      }
      Directory('$r/scripts').createSync(recursive: true);
      for (final f in const ['retire_worktree.dart', 'retire_worktree_lib.dart']) {
        File('$srcRoot/scripts/$f').copySync('$r/scripts/$f');
      }
      File('$r/.gitignore').writeAsStringSync('.claude/\n.env\n');
      File('$r/seed.txt').writeAsStringSync('seed\n');
      _run('git', ['add', '-A'], r);
      _run('git', ['commit', '-q', '-m', 'seed'], r);
      Directory('$r/.claude/worktrees').createSync(recursive: true);
      return r;
    }

    String w(String r, String slug) => '$r/.claude/worktrees/$slug';

    /// The REAL workflow's shape: a session branch cut from main, committed to,
    /// then merged with a merge commit (as a GitHub PR merge does here). The
    /// worktree is left CLEAN so the only reason to keep it would be the branch.
    void addMerged(String r, String slug, {String? branch}) {
      final b = branch ?? slug;
      _run('git', ['worktree', 'add', '-q', w(r, slug), '-b', b], r);
      File('${w(r, slug)}/${slug.replaceAll('/', '_')}.txt')
          .writeAsStringSync('work for $b\n');
      _run('git', ['add', '-A'], w(r, slug));
      _run('git', ['commit', '-q', '-m', 'work on $b'], w(r, slug));
      _run('git', ['merge', '-q', '--no-ff', '-m', 'merge $b', 'refs/heads/$b'], r);
    }

    ProcessResult retireIn(String r, List<String> extra) =>
        _run('dart', ['run', 'scripts/retire_worktree.dart', ...extra], r);

    Set<String> branches(String r) => (_run('git',
                ['for-each-ref', '--format=%(refname:short)', 'refs/heads'], r)
            .stdout as String)
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    test('dry-run deletes nothing; --execute deletes the branch and frees the slug',
        () {
      final r = freshRepo();
      addMerged(r, 'alpha');

      final dry = retireIn(r, ['alpha']);
      expect(dry.exitCode, 0, reason: '${dry.stdout}${dry.stderr}');
      expect(dry.stdout as String, contains('RETIRE  alpha'));
      expect(dry.stdout as String, contains('branch alpha would be deleted'));
      expect(branches(r), contains('alpha'),
          reason: 'dry-run must not delete the branch');
      expect(Directory(w(r, 'alpha')).existsSync(), isTrue,
          reason: 'dry-run must not remove the worktree');

      final run = retireIn(r, ['--execute', 'alpha']);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      expect(run.stdout as String, contains('RETIRED alpha'));
      expect(run.stdout as String, contains('BRANCH-DELETED alpha'));
      expect(branches(r), isNot(contains('alpha')));

      // The point of OI-138: the slug is immediately reusable.
      final again = _run(
          'git', ['worktree', 'add', '-q', '-b', 'alpha', w(r, 'alpha2')], r);
      expect(again.exitCode, 0,
          reason: 'a freed slug must be reusable: ${again.stderr}');
    });

    test('keys on the BRANCH git reports, never on the folder slug', () {
      // OI-138's trap: the folder name is not the branch name. An unrelated
      // branch that happens to be named like the folder must survive.
      final r = freshRepo();
      _run('git', ['branch', 'x'], r);
      addMerged(r, 'x', branch: 'feature/x');
      expect(branches(r), containsAll(['x', 'feature/x']));

      final run = retireIn(r, ['--execute', 'x']);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      expect(run.stdout as String, contains('BRANCH-DELETED feature/x'));
      expect(branches(r), isNot(contains('feature/x')));
      expect(branches(r), contains('x'),
          reason: 'the unrelated branch named like the folder slug must survive');
    });

    test('a `git branch -d` refusal is KEPT-BRANCH: worktree retired, exit 0, '
        'and no force-delete command in the output', () {
      // The refusal must be REACHABLE for the -d -> -D mutation to redden. With
      // the primary on main it never is: `-d` accepts anything merged into HEAD.
      // Leave the primary detached at the seed commit, so a genuinely merged
      // branch is not merged into HEAD and `-d` refuses it.
      final r = freshRepo();
      final seed = (_run('git', ['rev-parse', 'HEAD'], r).stdout as String).trim();
      addMerged(r, 'beta');
      final co = _run('git', ['checkout', '-q', '--detach', seed], r);
      expect(co.exitCode, 0, reason: co.stderr as String);

      final run = retireIn(r, ['--execute', 'beta']);
      _run('git', ['checkout', '-q', 'main'], r); // restore for teardown clarity

      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      final out = run.stdout as String;
      expect(out, contains('RETIRED beta'),
          reason: 'the worktree WAS retired; only the branch is kept');
      expect(out, contains('KEPT-BRANCH beta'));
      expect(out, contains('resolve by hand'));
      expect(out, isNot(contains('-D')),
          reason: 'must not echo git\'s force-delete advice');
      expect(branches(r), contains('beta'),
          reason: 'a refused delete must leave the branch');
    });

    test('protected prefixes are retired-but-kept, in any case', () {
      final r = freshRepo();
      addMerged(r, 'rx', branch: 'rescue/x');
      addMerged(r, 'oy', branch: 'OI/y');
      addMerged(r, 'dz', branch: 'Dependabot/z');

      final run = retireIn(r, ['--execute', '--all']);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      final out = run.stdout as String;
      for (final b in ['rescue/x', 'OI/y', 'Dependabot/z']) {
        expect(out, contains('KEPT-BRANCH $b [protected prefix'), reason: b);
        expect(branches(r), contains(b), reason: '$b must survive');
      }
      for (final s in ['rx', 'oy', 'dz']) {
        expect(Directory(w(r, s)).existsSync(), isFalse,
            reason: 'the worktree $s is still retired');
      }
    });

    test('a worktree on `main` or `develop` is retired but neither branch is '
        'ever deleted', () {
      // Git refuses a second checkout of `main` while the primary is on it, so
      // first move the primary onto another branch. Reproduced 2026-09-29: with
      // that shape `git branch -d -- main` DELETES main, and the tool's own
      // predicate calls the worktree retirable. Without this fixture the
      // "drop the main skip" mutation reddens nothing.
      final r = freshRepo();
      _run('git', ['checkout', '-q', '-b', 'holder'], r);
      _run('git', ['branch', 'develop'], r);
      expect(_run('git', ['worktree', 'add', '-q', w(r, 'wm'), 'main'], r).exitCode,
          0, reason: 'fixture: a linked worktree on main must be creatable');
      expect(
          _run('git', ['worktree', 'add', '-q', w(r, 'wd'), 'develop'], r).exitCode,
          0);

      final run = retireIn(r, ['--execute', '--all']);
      _run('git', ['checkout', '-q', 'main'], r);

      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      final out = run.stdout as String;
      expect(out, contains('KEPT-BRANCH main [protected branch name]'));
      expect(out, contains('KEPT-BRANCH develop [protected branch name]'));
      expect(branches(r), containsAll(['main', 'develop']),
          reason: 'main and develop must never be deleted by the retire tool');
    });

    test('a branch and a TAG of the same name: the worktree still retires, the '
        'branch goes, the tag stays', () {
      // `%(refname:short)` prints `heads/tg` when a tag `tg` exists, so the
      // merged set missed it and the worktree was silently KEPT forever.
      final r = freshRepo();
      addMerged(r, 'tg');
      _run('git', ['tag', 'tg', 'refs/heads/tg'], r);

      final run = retireIn(r, ['--execute', 'tg']);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      expect(run.stdout as String, contains('RETIRED tg'));
      expect(run.stdout as String, contains('BRANCH-DELETED tg'));
      expect(branches(r), isNot(contains('tg')));
      expect((_run('git', ['tag', '-l', 'tg'], r).stdout as String).trim(), 'tg',
          reason: 'the same-named tag must survive');
    });

    test('an upstream deleted on the remote — three shapes — still retires and '
        'deletes the branch', () {
      // (i)   `git push origin --delete B`      tracking ref removed
      // (ii)  B deleted inside the bare origin, NO fetch in the clone — the shape
      //       GitHub's auto-delete produces; the tracking ref is STALE but
      //       present, so `@{u}` still resolves
      // (iii) (ii) then `git fetch --prune`     tracking ref removed
      // Order matters: `fetch --prune` prunes EVERY stale ref, so (ii) is deleted
      // last and never fetched.
      final r = freshRepo();
      final bare = '${Directory(r).parent.path}/origin.git';
      _run('git', ['init', '-q', '--bare', '-b', 'main', bare], r);
      _run('git', ['remote', 'add', 'origin', bare], r);
      _run('git', ['push', '-q', 'origin', 'main'], r);
      for (final n in ['g1', 'g2', 'g3']) {
        addMerged(r, n);
        final push =
            _run('git', ['push', '-q', '-u', 'origin', n], w(r, n));
        expect(push.exitCode, 0, reason: 'fixture push of $n: ${push.stderr}');
      }
      _run('git', ['push', '-q', 'origin', '--delete', 'g1'], r); // (i)
      _run('git', ['-C', bare, 'branch', '-D', 'g3'], r); // (iii) setup
      _run('git', ['fetch', '-q', '--prune', 'origin'], r);
      _run('git', ['-C', bare, 'branch', '-D', 'g2'], r); // (ii), never fetched

      final dry = retireIn(r, []);
      expect(dry.exitCode, 0, reason: '${dry.stdout}${dry.stderr}');
      final dout = dry.stdout as String;
      for (final n in ['g1', 'g2', 'g3']) {
        expect(dout, contains('RETIRE  $n'),
            reason: 'a remote-deleted upstream must not make $n unretirable');
      }
      expect(dout, contains('deleted on the remote'),
          reason: 'states (i) and (iii) read as no-upstream');

      final run = retireIn(r, ['--execute', '--all']);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      for (final n in ['g1', 'g2', 'g3']) {
        expect(run.stdout as String, contains('BRANCH-DELETED $n'), reason: n);
        expect(branches(r), isNot(contains(n)), reason: n);
      }
    });

    test('the ancestry re-check is what keeps an UNMERGED branch: a commit that '
        'lands on a later candidate after the merged set was computed', () {
      // `git branch -d` tests "merged into HEAD or upstream", so a candidate whose
      // upstream tracks its (new) tip is deletable by `-d` ALONE. The only thing
      // that stops that is the ancestor-of-main re-check. The window is made
      // deterministic with a reference-transaction hook: when a1's branch ref is
      // deleted, it commits on b1 and advances b1's tracking ref, exactly as
      // another session pushing in the middle of a long loop would.
      final r = freshRepo();
      final bare = '${Directory(r).parent.path}/origin.git';
      _run('git', ['init', '-q', '--bare', '-b', 'main', bare], r);
      _run('git', ['remote', 'add', 'origin', bare], r);
      _run('git', ['push', '-q', 'origin', 'main'], r);
      for (final n in ['a1', 'b1']) {
        addMerged(r, n);
        final push = _run('git', ['push', '-q', '-u', 'origin', n], w(r, n));
        expect(push.exitCode, 0, reason: 'fixture push of $n: ${push.stderr}');
      }
      final mark = '${Directory(r).parent.path}/race.fired';
      final hook = File('$r/.git/hooks/reference-transaction');
      hook.parent.createSync(recursive: true);
      hook.writeAsStringSync('#!/bin/sh\n'
          '[ "\$1" = committed ] || exit 0\n'
          'while read old new ref; do\n'
          '  if [ "\$ref" = refs/heads/a1 ] && [ ! -e "$mark" ]; then\n'
          '    : > "$mark"\n'
          '    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE\n'
          '    git -C "${w(r, 'b1')}" commit -q --allow-empty -m race\n'
          '    git -C "$r" update-ref refs/remotes/origin/b1 refs/heads/b1\n'
          '  fi\n'
          'done\n');
      if (!Platform.isWindows) _run('chmod', ['+x', hook.path], r);

      final run = retireIn(r, ['--execute', '--all']);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      expect(File(mark).existsSync(), isTrue,
          reason: 'the hook never fired, so this test proved nothing');
      final out = run.stdout as String;
      expect(out, contains('BRANCH-DELETED a1'));
      expect(out, contains('KEPT-BRANCH b1 [not an ancestor of main at delete time]'),
          reason: out);
      expect(out, isNot(contains('BRANCH-DELETED b1')), reason: out);
      expect(branches(r), contains('b1'),
          reason: 'b1 carries a commit main does not have');
    });

    test('a FAILED worktree removal never touches the branch (no branch line at '
        'all)', () {
      // `git branch -d` would refuse a branch still checked out anywhere, so a
      // moved-up branch deletion is absorbed at the DATA level — but it still
      // prints a KEPT-BRANCH line, which is what this asserts against.
      final r = freshRepo();
      if (Platform.isWindows ||
          (_run('id', ['-u'], r).stdout as String).trim() == '0') {
        markTestSkipped('needs a non-root POSIX user to make removal fail');
        return;
      }
      File('$r/.git/info/exclude')
          .writeAsStringSync('build/\n', mode: FileMode.append);
      addMerged(r, 'f1');
      final sub = Directory('${w(r, 'f1')}/build/sub')..createSync(recursive: true);
      File('${sub.path}/x.txt').writeAsStringSync('x');
      _run('chmod', ['000', sub.path], r);
      try {
        final run = retireIn(r, ['--execute', '--all']);
        final out = run.stdout as String;
        expect(out, contains('FAILED  f1'), reason: '${run.stdout}${run.stderr}');
        expect(out, isNot(contains('BRANCH-DELETED')), reason: out);
        expect(out, isNot(contains('KEPT-BRANCH')), reason: out);
        expect(branches(r), contains('f1'));
      } finally {
        _run('chmod', ['755', sub.path], r);
      }
    });

    test('a BARE --execute is refused: nothing removed, no branch touched, and '
        '--all plus a slug is rejected too', () {
      // The sweep also deletes every retirable worktree's branch, so it must be
      // asked for by name (--all). A session that just finished ONE worktree
      // passes its own slug; this is what stops it sweeping by accident.
      final r = freshRepo();
      addMerged(r, 'k1');
      addMerged(r, 'k2');

      final bare = retireIn(r, ['--execute']);
      expect(bare.exitCode, isNot(0), reason: '${bare.stdout}${bare.stderr}');
      expect(bare.stderr as String, contains('refusing a bare --execute'),
          reason: 'the refusal must say WHY, not just fail');
      expect(Directory(w(r, 'k1')).existsSync(), isTrue);
      expect(Directory(w(r, 'k2')).existsSync(), isTrue);
      expect(branches(r), containsAll(['k1', 'k2']));

      final both = retireIn(r, ['--execute', '--all', 'k1']);
      expect(both.exitCode, isNot(0), reason: '${both.stdout}${both.stderr}');
      expect(both.stderr as String, contains('mutually exclusive'));
      expect(Directory(w(r, 'k1')).existsSync(), isTrue);

      // The scoped form still works and touches ONLY the named worktree.
      final one = retireIn(r, ['--execute', 'k1']);
      expect(one.exitCode, 0, reason: '${one.stdout}${one.stderr}');
      expect(Directory(w(r, 'k1')).existsSync(), isFalse);
      expect(branches(r), isNot(contains('k1')));
      expect(Directory(w(r, 'k2')).existsSync(), isTrue,
          reason: 'a slug must never sweep a sibling');
      expect(branches(r), contains('k2'));

      // A DRY-RUN with no slug stays allowed: it removes nothing.
      final dry = retireIn(r, []);
      expect(dry.exitCode, 0, reason: '${dry.stdout}${dry.stderr}');
      // ...and its footer must not tell the reader to run the refused form.
      expect(dry.stdout as String, contains('--execute <slug>'));
      expect(dry.stdout as String, contains('--execute --all'));
    });
  });
}
