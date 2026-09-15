// test/scripts/safe_merge_test.dart
//
// END-TO-END coverage for scripts/safe_merge.sh (Unit 3c, discipline-tooling
// hardening batch, 2026-08-03). Builds a real bare "remote" + a real
// "primary" clone in throwaway directories and runs the actual script
// against them, asserting exit codes and HEAD movement -- not a mocked git.
//
// WHY THIS EXISTS: before this unit, the merge-into-main step had no wrapper
// at all -- just a raw `git merge --no-ff <branch>`, exempted by
// git_safety_hook.dart as an integration op. That is exactly the moment
// "is local main caught up with origin/main" matters most. This test proves
// the new wrapper actually refuses onto a stale base rather than merging
// silently, mirroring the seeded-stale-origin scenario the plan called for.
//
// ENV SCRUBBING IS LOAD-BEARING -- see plan_review_record_gate_e2e_test.dart's
// header for why (feedback_mistake_git_hook_env_leak): a surrounding git hook
// exports GIT_DIR/GIT_WORK_TREE, which override BOTH `workingDirectory:` and
// `-C <path>`, so an unscrubbed child git would operate on the REAL repo.

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd,
    {Map<String, String>? extra}) {
  final env = _cleanEnv();
  if (extra != null) env.addAll(extra);
  return Process.runSync(exe, args,
      workingDirectory: cwd,
      environment: env,
      includeParentEnvironment: false,
      runInShell: true);
}

String _fileUri(String path) => 'file:///${path.replaceAll('\\', '/')}';

void main() {
  final srcRoot = Directory.current.path;
  late Directory tmp;
  late String remote; // bare "origin"
  late String primary; // clone acting as the primary worktree

  void copyScripts(String repoPath) {
    Directory('$repoPath/scripts').createSync(recursive: true);
    for (final f in const ['safe_merge.sh', '_git_lock.sh']) {
      File('$srcRoot/scripts/$f').copySync('$repoPath/scripts/$f');
    }
  }

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('safe_merge_e2e_');
    remote = '${tmp.path}/remote.git';
    primary = '${tmp.path}/primary';

    Directory(remote).createSync(recursive: true);
    expect(_run('git', ['init', '-q', '--bare', '-b', 'main', '.'], remote)
        .exitCode, 0);

    Directory(primary).createSync(recursive: true);
    expect(
        _run('git', ['clone', '-q', _fileUri(remote), '.'], primary).exitCode,
        0,
        reason: 'setup: cloning the empty bare remote must succeed');
    _run('git', ['config', 'user.email', 'test@example.invalid'], primary);
    _run('git', ['config', 'user.name', 'Test'], primary);

    // Verify isolation actually took before trusting any assertion below.
    final top = _run('git', ['rev-parse', '--show-toplevel'], primary);
    final resolved = (top.stdout as String).trim();
    if (!resolved.toLowerCase().contains('safe_merge_e2e_')) {
      throw StateError(
          'ENV LEAK: throwaway primary resolved to "$resolved", not the temp '
          'dir. GIT_* scrubbing failed -- aborting rather than running '
          'assertions against the real repository.');
    }

    copyScripts(primary);
    File('$primary/seed.txt').writeAsStringSync('seed\n');
    _run('git', ['add', '-A'], primary);
    _run('git', ['commit', '-qm', 'seed'], primary);
    expect(_run('git', ['push', '-q', '-u', 'origin', 'main'], primary)
        .exitCode, 0,
        reason: 'setup: seeding the bare remote must succeed');
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* best effort on Windows file locks */}
  });

  /// Creates a feature branch in [repo] off its current `main`, with one
  /// commit, then returns to `main`. Returns the branch name.
  String makeFeatureBranch(String repo, String name) {
    _run('git', ['checkout', '-q', '-B', name, 'main'], repo);
    File('$repo/$name.txt').writeAsStringSync('$name\n');
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-qm', 'work on $name'], repo);
    _run('git', ['checkout', '-q', 'main'], repo);
    return name;
  }

  test('refuses to merge when local main is BEHIND origin/main', () {
    // Simulate someone else pushing directly to the shared remote: a THIRD
    // clone, independent of `primary`, commits and pushes -- advancing the
    // bare repo without primary's local main or its cached
    // refs/remotes/origin/main moving at all.
    final otherDir = '${tmp.path}/other_pusher';
    Directory(otherDir).createSync(recursive: true);
    expect(_run('git', ['clone', '-q', _fileUri(remote), '.'], otherDir)
        .exitCode, 0);
    _run('git', ['config', 'user.email', 'other@example.invalid'], otherDir);
    _run('git', ['config', 'user.name', 'Other'], otherDir);
    File('$otherDir/other.txt').writeAsStringSync('other push\n');
    _run('git', ['add', '-A'], otherDir);
    _run('git', ['commit', '-qm', 'a push primary has not seen'], otherDir);
    expect(_run('git', ['push', '-q', 'origin', 'main'], otherDir).exitCode,
        0,
        reason: 'setup: the "other pusher" must land on the shared remote');

    final branch = makeFeatureBranch(primary, 'stale-base-feature');
    final beforeHead = (_run('git', ['rev-parse', 'HEAD'], primary).stdout
            as String)
        .trim();

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);

    expect(r.exitCode, 1,
        reason: 'local main is behind origin/main -- this must refuse, not '
            'merge onto a stale base.\n${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('behind origin/main'));

    final afterHead = (_run('git', ['rev-parse', 'HEAD'], primary).stdout
            as String)
        .trim();
    expect(afterHead, beforeHead,
        reason: 'a refused merge must not move HEAD at all');
  });

  test('merges cleanly once local main is caught up with origin/main', () {
    // Catch primary up for real (the previous test's failure left it
    // deliberately behind).
    expect(_run('git', ['fetch', '-q', 'origin', 'main'], primary).exitCode,
        0);
    expect(
        _run('git', ['merge', '-q', '--ff-only', 'origin/main'], primary)
            .exitCode,
        0,
        reason: 'setup: primary must genuinely catch up before this test');

    final branch = makeFeatureBranch(primary, 'caught-up-feature');
    final beforeHead = (_run('git', ['rev-parse', 'HEAD'], primary).stdout
            as String)
        .trim();

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);

    expect(r.exitCode, 0,
        reason: 'local main matches origin/main -- this must succeed.\n'
            '${r.stdout}${r.stderr}');
    final afterHead = (_run('git', ['rev-parse', 'HEAD'], primary).stdout
            as String)
        .trim();
    expect(afterHead, isNot(beforeHead),
        reason: 'a successful merge must advance HEAD');

    final log = _run('git', ['log', '-1', '--format=%P'], primary).stdout
        as String;
    expect(log.trim().split(RegExp(r'\s+')).length, 2,
        reason: 'must be a real merge commit (two parents), i.e. --no-ff');
  });

  test(
      'passes a multi-word -m message through as ONE argument, not '
      'word-split (round-2 review blocking #2)', () {
    // Re-sync defensively rather than assume prior test ordering left
    // primary caught up.
    expect(
        _run('git', ['fetch', '-q', 'origin', 'main'], primary).exitCode, 0);
    _run('git', ['merge', '-q', '--ff-only', 'origin/main'], primary);

    final branch = makeFeatureBranch(primary, 'extra-args-feature');
    // ASCII-only deliberately: Dart's Process API on Windows does not
    // reliably preserve a non-ASCII argument (e.g. an em-dash, this repo's
    // actual merge-message convention) through to the child process's
    // command line -- confirmed separately by invoking safe_merge.sh
    // directly from a real shell, where the SAME em-dash round-trips as
    // correct UTF-8 bytes. That is a Dart/Windows test-harness limitation
    // unconnected to safe_merge.sh itself (which is only ever invoked from
    // a real shell in actual use, never via Dart's Process API), so it is
    // avoided here rather than "fixed" -- this test's job is to pin the
    // word-splitting bug (round-2 blocking #2), not Windows Unicode
    // argv handling.
    final subject = "Merge branch 'extra-args-feature' "
        '- regression test for the round-2 word-splitting bug';

    final r =
        _run('sh', ['scripts/safe_merge.sh', branch, '-m', subject], primary);

    expect(r.exitCode, 0,
        reason: 'a multi-word -m message must be accepted, not shredded '
            'into unresolvable extra merge-target arguments. The FIRST '
            'shipped version of this passthrough failed here with '
            '"branch - not something we can merge".\n${r.stdout}${r.stderr}');

    final actualSubject =
        (_run('git', ['log', '-1', '--format=%s'], primary).stdout as String)
            .trim();
    expect(actualSubject, subject,
        reason: 'the commit subject must be the EXACT string passed to -m, '
            'proving it survived as one argument rather than being '
            'word-split and partially consumed by git as separate '
            'extra merge-target arguments.');
  });

  test('refuses when the current branch is not main', () {
    final branch = makeFeatureBranch(primary, 'off-main-feature');
    _run('git', ['checkout', '-q', branch], primary);
    addTearDown(() => _run('git', ['checkout', '-q', 'main'], primary));

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);
    expect(r.exitCode, 1);
    expect('${r.stdout}${r.stderr}', contains('not \'main\''));
  });

  test('refuses when run from a LINKED worktree, not primary', () {
    final worktreeDir = '${tmp.path}/linked_wt';
    final wtBranch = 'linked-wt-probe';
    _run('git', ['branch', wtBranch, 'main'], primary);
    final add = _run(
        'git', ['worktree', 'add', '-q', worktreeDir, wtBranch], primary);
    expect(add.exitCode, 0, reason: 'setup: worktree add must succeed');
    copyScripts(worktreeDir);
    addTearDown(() {
      _run('git', ['worktree', 'remove', '--force', worktreeDir], primary);
    });

    final r = _run('sh', ['scripts/safe_merge.sh', 'main'], worktreeDir);
    expect(r.exitCode, 1);
    expect('${r.stdout}${r.stderr}', contains('LINKED worktree'));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PRE-MERGE bpass-verdict PRECHECK (2026-08-30).
  //
  // check_plan_review_record_exists.dart reads the record's bpass_review file
  // AT THE MERGE COMMIT, so a `verdict: pending` there is unfixable by any
  // later commit — the repair is a full merge unwind, which is what it cost on
  // 2026-08-30. This precheck asks the same question one step earlier.
  //
  // It is ADVISORY: it must WARN and still merge. A blocking version would
  // wedge the only path that lands work on main, which is exactly the hazard
  // git_safety_hook.dart's own round-2 review closed for the push-side twin.
  /// Commits a plan-review record for [branch] claiming `bpass: accepted`,
  /// pointing at a review file carrying [verdict] — **onto [branch] itself**,
  /// then returns to `main` leaving main's working tree WITHOUT either file.
  ///
  /// ⚠ The branch-side placement is the whole point, and the first version of
  /// this helper got it wrong (B-pass finding 1). It committed both files onto
  /// `main`, which made all three tests pass against a precheck that was a
  /// no-op in production: the real workflow authors the record on the feature
  /// branch (verified against real history — `docs/plan-reviews/
  /// profile-phase-fixes.md` is absent from `a7a254b8^1`, reachable only via
  /// the branch parent), so a working-tree read on main finds nothing.
  /// A fixture that manufactures a state the workflow never produces asserts
  /// nothing about the workflow. This one reproduces the real shape, which is
  /// what makes the precheck's `git show "$BRANCH:..."` read load-bearing:
  /// revert that read to a working-tree read and these tests go red.
  void writeReviewPairOnBranch(String repo, String branch, String verdict) {
    _run('git', ['checkout', '-q', branch], repo);
    Directory('$repo/docs/plan-reviews').createSync(recursive: true);
    Directory('$repo/docs/reviews').createSync(recursive: true);
    final slug = branch.replaceFirst(RegExp(r'^origin/'), '').replaceAll('/', '-');
    File('$repo/docs/reviews/$slug-review.md')
        .writeAsStringSync('---\nverdict: $verdict\n---\n# review\n');
    File('$repo/docs/plan-reviews/$slug.md').writeAsStringSync(
        '---\nbranch: $branch\nblast_radius: platform\nreview_rounds: 2\n'
        'ground_truth_verified: true\nverdict: converged\nbpass: accepted\n'
        'bpass_review: docs/reviews/$slug-review.md\n---\n# record\n');
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-qm', 'review artifacts for $branch'], repo);
    _run('git', ['checkout', '-q', 'main'], repo);

    // The load-bearing precondition: main must NOT have these files, or the
    // test cannot distinguish a branch-tree read from a working-tree read.
    expect(File('$repo/docs/plan-reviews/$slug.md').existsSync(), isFalse,
        reason: 'setup: the record must live ONLY on the branch — if it is on '
            'main too, a working-tree read would pass and prove nothing');
  }

  test('WARNS before merging when the bpass_review verdict is still pending',
      () {
    final branch = makeFeatureBranch(primary, 'pending-verdict-feature');
    writeReviewPairOnBranch(primary, branch, 'pending');

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);

    expect(r.exitCode, 0,
        reason: 'ADVISORY — it must warn, never block the merge.\n'
            '${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('verdict: accepted'),
        reason: 'the warning must name what is missing');
    expect('${r.stdout}${r.stderr}', contains('unwinding this merge'),
        reason: 'and must say WHY it matters now rather than later — that is '
            'the whole point of moving the check earlier');
  });

  test('stays SILENT when the bpass_review verdict is accepted', () {
    // The mirror. A precheck that warns on the healthy path is noise, and
    // noise is how a real warning gets skimmed past.
    final branch = makeFeatureBranch(primary, 'accepted-verdict-feature');
    writeReviewPairOnBranch(primary, branch, 'accepted');

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);

    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', isNot(contains('unwinding this merge')),
        reason: 'an accepted verdict must produce no warning at all');
  });

  // Round-1 review finding 1: the precheck originally warned on ONE of the
  // three shapes the CI gate rejects, and stayed silent on the two likelier
  // operator errors. These two tests pin the missing shapes. Both were
  // confirmed to merge with zero output before the fix.
  test('WARNS when bpass: accepted names NO bpass_review file', () {
    final branch = makeFeatureBranch(primary, 'no-bpass-field-feature');
    _run('git', ['checkout', '-q', branch], primary);
    Directory('$primary/docs/plan-reviews').createSync(recursive: true);
    File('$primary/docs/plan-reviews/$branch.md').writeAsStringSync(
        '---\nbranch: $branch\nblast_radius: platform\nreview_rounds: 2\n'
        'ground_truth_verified: true\nverdict: converged\nbpass: accepted\n'
        '---\n# record with no bpass_review: line\n');
    _run('git', ['add', '-A'], primary);
    _run('git', ['commit', '-qm', 'record without bpass_review'], primary);
    _run('git', ['checkout', '-q', 'main'], primary);

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);
    expect(r.exitCode, 0, reason: 'advisory: ${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('names no'),
        reason: 'the CI gate rejects this shape outright — the precheck that '
            'previews it must not be silent here');
  });

  test('WARNS when bpass_review names a file absent from the branch', () {
    final branch = makeFeatureBranch(primary, 'dangling-bpass-feature');
    _run('git', ['checkout', '-q', branch], primary);
    Directory('$primary/docs/plan-reviews').createSync(recursive: true);
    File('$primary/docs/plan-reviews/$branch.md').writeAsStringSync(
        '---\nbranch: $branch\nblast_radius: platform\nreview_rounds: 2\n'
        'ground_truth_verified: true\nverdict: converged\nbpass: accepted\n'
        'bpass_review: docs/reviews/never-committed-review.md\n---\n# record\n');
    _run('git', ['add', '-A'], primary);
    _run('git', ['commit', '-qm', 'record with dangling bpass_review'], primary);
    _run('git', ['checkout', '-q', 'main'], primary);

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);
    expect(r.exitCode, 0, reason: 'advisory: ${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('does not exist on'),
        reason: 'a typo or an uncommitted review file is the likeliest '
            'operator error of the three, and was the most silent');
  });

  // Round-1 review finding 3: the verdict grep is correctly line-anchored, but
  // the only non-accepted fixture was the literal `pending`, which contains no
  // `accepted` substring — so removing BOTH anchors left all 8 tests green.
  // This pins the anchoring itself, mirroring the CI gate's own
  // `^verdict:\s*accepted\s*$` and its "fabricated acceptance" rationale.
  test('WARNS on a HEDGED verdict that merely contains "accepted"', () {
    final branch = makeFeatureBranch(primary, 'hedged-verdict-feature');
    writeReviewPairOnBranch(primary, branch, 'accepted_pending_signoff');

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);
    expect(r.exitCode, 0, reason: 'advisory: ${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('line-anchored'),
        reason: 'an unanchored match would read `accepted_pending_signoff` as '
            'clean acceptance — exactly the fabricated-acceptance shape the '
            'CI gate anchors against.');
  });

  // Round-2 review P2. `refs/heads/` was added for round-1 finding 4 (a TAG
  // sharing a branch's name silently wins git's ref precedence), and nothing
  // tested it: removing the prefix from both `git show` calls left all 11
  // tests green. This fixture builds the collision.
  test('reads the BRANCH, not a same-named TAG (refs/heads/ disambiguation)',
      () {
    final branch = makeFeatureBranch(primary, 'tag-collision-feature');
    // The BRANCH carries a pending verdict — the precheck must warn about it.
    writeReviewPairOnBranch(primary, branch, 'pending');
    // A TAG of the same name points at a commit whose record says `accepted`.
    // Bare `git show "$BRANCH:..."` resolves the TAG, so a precheck without
    // `refs/heads/` reads the clean record and stays silent about a branch
    // that is in fact about to fail CI.
    _run('git', ['checkout', '-q', '-B', 'tag-src', 'main'], primary);
    Directory('$primary/docs/plan-reviews').createSync(recursive: true);
    Directory('$primary/docs/reviews').createSync(recursive: true);
    File('$primary/docs/reviews/$branch-review.md')
        .writeAsStringSync('---\nverdict: accepted\n---\n# clean\n');
    File('$primary/docs/plan-reviews/$branch.md').writeAsStringSync(
        '---\nbranch: $branch\nbpass: accepted\n'
        'bpass_review: docs/reviews/$branch-review.md\n---\n# record\n');
    _run('git', ['add', '-A'], primary);
    _run('git', ['commit', '-qm', 'decoy accepted record'], primary);
    final tagged = _run('git', ['tag', branch, 'HEAD'], primary);
    expect(tagged.exitCode, 0, reason: 'setup: creating the colliding tag');
    _run('git', ['checkout', '-q', 'main'], primary);
    addTearDown(() => _run('git', ['tag', '-d', branch], primary));

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);

    expect(r.exitCode, 0, reason: 'advisory: ${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('line-anchored'),
        reason: 'the precheck must read the BRANCH (verdict: pending) and warn '
            '— resolving the same-named TAG instead finds `accepted` and goes '
            'silent about a branch that will fail CI at the merge commit.');
  });

  test('stays SILENT when the branch has no plan-review record', () {
    // Feature-tier branches legitimately have no record. The precheck must
    // not invent a requirement the merge gate itself does not impose.
    final branch = makeFeatureBranch(primary, 'no-record-feature');

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);

    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', isNot(contains('unwinding this merge')));
  });
}
