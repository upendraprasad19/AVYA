// test/scripts/plan_review_record_gate_e2e_test.dart
//
// END-TO-END gate test: builds real merge commits in a throwaway repo and runs
// `check_plan_review_record_exists.dart` against them, asserting exit codes.
//
// WHY this exists in addition to plan_review_record_lib_test.dart:
// the pure-helper tests are what MISSED round-2 review's P0-1. The first draft
// end-anchored the branch regex, which rejected this repo's dominant merge
// convention (`Merge branch 'X' — <description>`, 49 of 174 merges on main) and
// would have reddened main on the very next merge. Every pure test passed,
// because they only ever exercised the ` into Y` suffix. Only executing the
// real gate against a real merge commit surfaced it. See
// feedback_source_grep_false_confidence.md — the same class, one level up:
// unit-testing a helper certifies the helper, not the gate.
//
// ENV SCRUBBING IS LOAD-BEARING. Run inside `pre-commit`, a test that spawns
// its own git repo inherits GIT_DIR / GIT_WORK_TREE, which override BOTH
// `workingDirectory:` and `-C <path>` — the child git would operate on the REAL
// repo and every assertion here would be meaningless (or destructive).
// feedback_mistake_git_hook_env_leak. We pass a filtered environment with
// includeParentEnvironment: false so no GIT_* can leak in.

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Parent environment minus anything git-related, so a surrounding hook cannot
/// redirect the child git at the real repository.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  // GIT_*  — a surrounding git hook exports GIT_DIR / GIT_WORK_TREE, which
  //          override BOTH `workingDirectory:` and `-C <path>`, so the child
  //          git would operate on the REAL repo (feedback_mistake_git_hook_env_leak).
  //
  // GITHUB_* — added 2026-07-28 after this file went RED in CI while green
  //          locally. The gate's range-base resolution falls back to parsing
  //          `GITHUB_EVENT_PATH`, and in CI that payload is real: its `before`
  //          names a commit on the ACTUAL repo, which does not exist in this
  //          throwaway one. The gate then correctly reported
  //          "supplied but unresolvable" and hard-failed — the right behaviour
  //          on a bogus base, triggered by an input the test never meant to
  //          give it. Each test re-supplies the GITHUB_* keys it actually wants
  //          via `extra:`, so the spawned gate sees only what the scenario
  //          declares. Hermetic by construction rather than by luck.
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
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

void main() {
  late Directory tmp;
  late String repo;

  /// Repo root of the code under test (the test's own working directory).
  final srcRoot = Directory.current.path;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('keystone_gate_e2e_');
    repo = tmp.path;

    // Isolated repo. `-c` flags keep it independent of global git config.
    _run('git', ['init', '-q', '-b', 'main', '.'], repo);
    _run('git', ['config', 'user.email', 'test@example.invalid'], repo);
    _run('git', ['config', 'user.name', 'Test'], repo);
    _run('git', ['remote', 'add', 'origin',
        'git@github.com:upendraprasad19/AVYA.git'], repo);

    // Verify the isolation actually took, rather than assuming it.
    final top = _run('git', ['rev-parse', '--show-toplevel'], repo);
    final resolved = (top.stdout as String).trim();
    if (!resolved.toLowerCase().contains('keystone_gate_e2e_')) {
      throw StateError(
          'ENV LEAK: throwaway git resolved to "$resolved", not the temp repo. '
          'GIT_DIR/GIT_WORK_TREE scrubbing failed — aborting rather than '
          'running assertions against the real repository.');
    }

    // The gate + its two relative imports.
    Directory('$repo/scripts').createSync(recursive: true);
    for (final f in const [
      'check_plan_review_record_exists.dart',
      'plan_review_record_lib.dart',
      'blast_radius_content_rules_lib.dart',
    ]) {
      File('$srcRoot/scripts/$f').copySync('$repo/scripts/$f');
    }

    // Real tier registry, so blast-radius resolution matches production.
    Directory('$repo/docs/plan-reviews').createSync(recursive: true);
    File('$srcRoot/docs/blast_radius.yaml')
        .copySync('$repo/docs/blast_radius.yaml');

    // Baseline commit on main.
    File('$repo/seed.txt').writeAsStringSync('seed\n');
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-qm', 'seed'], repo);
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* best effort on Windows file locks */}
  });

  /// Builds `branchName` off main touching a PLATFORM-tier path, merges it back
  /// with `subject`, and returns the gate's exit code.
  int mergeAndRunGate(String branchName, String subject,
      {bool withRecord = true, String? recordBranchField}) {
    _run('git', ['checkout', '-q', '-B', branchName, 'main'], repo);
    // pubspec.yaml is platform tier (docs/blast_radius.yaml).
    File('$repo/pubspec.yaml').writeAsStringSync('name: probe\n# $branchName\n');
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-qm', 'change on $branchName'], repo);

    _run('git', ['checkout', '-q', 'main'], repo);

    final slug = branchName.replaceAll('/', '-');
    final recFile = File('$repo/docs/plan-reviews/$slug.md');
    if (withRecord) {
      recFile.writeAsStringSync('''
---
branch: ${recordBranchField ?? branchName}
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/probe.md
---
''');
      Directory('$repo/docs/reviews').createSync(recursive: true);
      File('$repo/docs/reviews/probe.md')
          .writeAsStringSync('verdict: accepted\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'record'], repo);
    } else if (recFile.existsSync()) {
      recFile.deleteSync();
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'drop record'], repo);
    }

    _run('git', ['merge', '--no-ff', '-q', branchName, '-m', subject], repo);

    final r = _run('dart', ['scripts/check_plan_review_record_exists.dart'], repo,
        extra: {
          'GITHUB_REF': 'refs/heads/main',
          'GITHUB_REPOSITORY_OWNER': 'upendraprasad19',
        });
    return r.exitCode;
  }

  test('REGRESSION P0-1: the repo\'s em-dash merge convention PASSES', () {
    // Verbatim shape of 904e6961, the merge immediately before this batch.
    final code = mergeAndRunGate('emdash-branch',
        "Merge branch 'emdash-branch' — never cancel a main run; cache gradle");
    expect(code, 0,
        reason: 'an end-anchored branch regex rejects every descriptive merge '
            'subject this repo writes, reddening main on the next merge');
  });

  test('a platform change with NO record still FAILS (gate not defanged)', () {
    final code = mergeAndRunGate('no-record-branch',
        "Merge branch 'no-record-branch' — description here",
        withRecord: false);
    expect(code, 1,
        reason: 'relaxing the subject regex must not weaken the requirement');
  });

  test('REGRESSION P1-2: a crafted "\' of x\'" suffix cannot bypass the gate',
      () {
    // Unconditionally passing this shape let ANY subject ending `' of x'` exit 0
    // before blast-radius was computed.
    final code = mergeAndRunGate('craft-branch',
        "Merge branch 'craft-branch' of x", withRecord: false);
    expect(code, 1,
        reason: 'only a same-branch sync of main may pass as a remote sync');
  });

  test('a genuine `git pull` sync of main PASSES', () {
    final code = mergeAndRunGate('sync-probe',
        "Merge branch 'main' of git@github.com:upendraprasad19/AVYA.git",
        withRecord: false);
    expect(code, 0,
        reason: 'syncing main with its own remote is not a feature landing');
  });

  test('REGRESSION: a record naming a DIFFERENT branch is rejected', () {
    final code = mergeAndRunGate('slug-collision', "Merge branch 'slug-collision'",
        recordBranchField: 'some-other-branch');
    expect(code, 1,
        reason: 'the record must vouch for the branch actually being merged');
  });
}
