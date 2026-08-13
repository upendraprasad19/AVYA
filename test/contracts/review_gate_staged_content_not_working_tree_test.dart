@Timeout(Duration(minutes: 3))
library;

// TIMEOUT RAISED FROM THE 30s DEFAULT (2026-08-13, diagnose 4f2a9e).
//
// Every test in this file spawns `dart run <script>` as a real subprocess, and a
// cold `dart run` costs seconds on its own (VM start + kernel compile). Measured
// standalone with ZERO contention: this file takes ~33s wall for its handful of
// tests — already brushing the 30s PER-TEST default.
//
// The merge-commit regression-catalog walk then runs ~700 tests concurrently, so
// the same subprocesses take far longer and these tests time out. That produced
// false failures that blocked a merge twice while the file passed standalone
// every time. The default is simply wrong for a test whose body starts a Dart VM;
// this matches what test/scripts/*_e2e_test.dart already declare for the same
// reason.
//
// This is a TIMEOUT, not a retry: a genuine hang still fails, just later.

// scripts/check_code_review_pass_exists.dart is the one gate in the
// content-aware blast-radius batch that actually BLOCKS a local commit
// (unlike blast_radius_from_diff.dart, which is advisory, or
// check_plan_review_record_exists.dart, which runs in a clean CI checkout
// where working-tree == HEAD). It runs post-staging/pre-commit, so it must
// judge the STAGED blob that's about to be committed — not the working-tree
// file on disk.
//
// Round-2 plan-review found: `contentForcesCatastrophic` (the shared
// library's default I/O) reads `File(path).readAsStringSync()` — the
// working-tree copy. If a migration with SECURITY DEFINER content is
// staged, then the working copy is further edited (without re-staging) to
// strip that content before `git commit`, the STAGED blob that actually
// lands in the commit still carries SECURITY DEFINER, but a working-tree
// read would see the edited-clean version and miss it — reopening exactly
// the "innocuous filename hides SECURITY DEFINER" gap this feature exists
// to close. Fixed by reading the staged (index) blob via `git show :<path>`
// / `git cat-file -e :<path>` instead (`_stagedFileExists`/
// `_stagedFileContent` in check_code_review_pass_exists.dart).
//
// This test isolates the underlying git-plumbing mechanism (same technique
// as test/contracts/review_gate_hash_raw_bytes_test.dart — an isolated temp
// git repo, not the real worktree's index) and proves: (a) a working-tree
// read of a staged-then-further-edited file misses the staged content, (b)
// a `git show :<path>` read of the same scenario correctly sees the STAGED
// content that would actually be committed.
//
// INCIDENT (2026-07-18): the first version of this test passed
// `workingDirectory: tmp.path` to `Process.run('git', [...])` to scope every
// git call to the temp repo. That failed to isolate it — the `git init`/
// `git config` calls ran against the SHARED repo config instead
// (`.git/config` at the project root), flipping `core.bare = true`
// (breaking `git status`/commit in EVERY worktree project-wide, including
// other concurrent sessions) and injecting a spurious
// `[user] name=Test email=test@example.com` that would have misattributed
// every future commit in the repo. No commits/objects were corrupted —
// only those two config values.
//
// ROOT CAUSE, fully diagnosed (not just worked around): this test's own
// regression coverage runs inside the `pre-commit` git hook (`flutter test
// test/contracts/` is exactly what `scripts/pre-commit.sh` invokes). Git
// sets `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/`GIT_PREFIX`/
// `GIT_COMMON_DIR` in a HOOK's own environment so any git command the hook
// script runs stays pinned to the commit in progress, regardless of that
// command's cwd. `Process.run` inherits the parent environment by default,
// so those variables leaked into every git subprocess this test spawned —
// and `GIT_DIR`/`GIT_WORK_TREE`, when set, take precedence over BOTH
// `workingDirectory:` AND an explicit `-C <path>` flag for repository
// identity. This is why an initial follow-up fix using `-C <path>` alone
// (without also scrubbing the environment) still intermittently failed
// under the real `test/contracts/` hook run (a `_freshIsolatedGitTargetDir`
// pre-flight check occasionally found the "fresh" temp dir already
// resolving as a git toplevel — it was actually resolving to the leaked
// `GIT_DIR`, not a naming collision). Confirmed by deliberately injecting
// `GIT_DIR`/`GIT_WORK_TREE` into a standalone run: it broke the `-C`-only
// version and passed once environment-scrubbing was added.
//
// Fully fixed via `_git`: every call uses BOTH the explicit `-C <path>`
// flag AND `environment:`/`includeParentEnvironment: false` to strip
// `GIT_DIR` et al. before spawning — belt and suspenders, since either one
// alone is insufficient once this runs inside a git hook.
//
// Run: flutter test test/contracts/review_gate_staged_content_not_working_tree_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `GIT_*` environment variables to strip before every git call this test
/// spawns. When `flutter test` runs as a child of `git commit` (i.e. from
/// inside the `pre-commit` hook, which this test's own regression coverage
/// runs under), git sets `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/
/// `GIT_PREFIX`/`GIT_COMMON_DIR` in the HOOK's environment so any git
/// command the hook script itself runs stays pinned to the commit in
/// progress, regardless of that command's cwd or `-C` flag. Dart's
/// `Process.run` inherits the parent environment by default, so those
/// variables leak into every subprocess this test spawns — silently
/// overriding `-C <tmp.path>` and making git treat the temp repo as if it
/// were the SHARED real repo. This is the actual mechanism behind BOTH
/// incidents in this file's history (the original workingDirectory bug
/// AND the "temp dir already inside a repo" retry-exhaustion failure —
/// both were really the same root cause, `GIT_DIR` et al. leaking in from
/// the hook, not a `workingDirectory` bug or a naming collision).
const _gitEnvKeysToStrip = [
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_PREFIX',
  'GIT_COMMON_DIR',
];

/// Runs `git -C <repoPath> <args>` with a git-env-scrubbed environment. The
/// `-C` flag tells git which directory to operate in as an explicit
/// argument, independent of the process's actual working directory —
/// necessary but NOT sufficient on its own, since `GIT_DIR`/`GIT_WORK_TREE`
/// (if inherited) take precedence over `-C` for repository identity. See
/// `_gitEnvKeysToStrip`'s doc comment for why both are needed together.
Future<ProcessResult> _git(String repoPath, List<String> args) {
  final cleanEnv = Map<String, String>.from(Platform.environment)
    ..removeWhere((key, _) => _gitEnvKeysToStrip.contains(key.toUpperCase()));
  return Process.run('git', ['-C', repoPath, ...args],
      environment: cleanEnv, includeParentEnvironment: false);
}

/// Creates a fresh temp directory and verifies it is NOT already inside a
/// git repository (via `git -C <dir> rev-parse --show-toplevel`) before
/// handing it back. Retries with a brand-new directory (bounded) rather than
/// failing outright on the first collision: under this repo's full
/// `test/contracts/` run (1500+ tests, often with other Claude Code sessions
/// running their own test suites concurrently on the same machine — see the
/// INCIDENT note below), `Directory.systemTemp.createTemp()` has been
/// observed to occasionally hand back a path basename that collides with
/// something else's git repo. Retrying is safe (each attempt independently
/// re-verifies) and turns a rare naming collision into a non-issue instead
/// of test flakiness — the hard guarantee (never run `git init` on a
/// directory that's already a repo) is preserved either way.
Future<Directory> _freshIsolatedGitTargetDir(String prefix) async {
  const maxAttempts = 5;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final tmp = await Directory.systemTemp.createTemp(prefix);
    final check = await _git(tmp.path, ['rev-parse', '--show-toplevel']);
    if (check.exitCode != 0) {
      return tmp; // genuinely fresh — not inside any repo
    }
    // Collision (or transient concurrent-process interference) — this
    // specific directory isn't safe to `git init` in. Clean it up and try
    // a new one rather than touching it further.
    await tmp.delete(recursive: true);
  }
  fail('SAFETY ABORT: could not obtain a temp directory NOT already inside '
      'a git repository after $maxAttempts attempts (prefix "$prefix"). '
      'Refusing to run `git init` anywhere — this is the exact precondition '
      'that caused the 2026-07-18 shared-config-corruption incident.');
}

void main() {
  test('staged-then-further-edited file: git show :<path> sees the STAGED '
      'content; a plain working-tree read sees the (wrong) edited content',
      () async {
    final tmp = await _freshIsolatedGitTargetDir('staged_content_f_test');
    addTearDown(() => tmp.delete(recursive: true));

    final initGit = await _git(tmp.path, ['init', '-q']);
    expect(initGit.exitCode, 0, reason: 'git init must succeed in the temp repo');
    await _git(tmp.path, ['config', 'user.email', 'test@example.com']);
    await _git(tmp.path, ['config', 'user.name', 'Test']);

    const relPath = 'supabase/migrations/999_scratch.sql';
    final scratchFile = File('${tmp.path}/$relPath');
    await scratchFile.parent.create(recursive: true);

    const stagedContent =
        'create function f() returns void security definer as \$\$ \$\$;';
    const workingTreeContentAfterFurtherEdit =
        'create function f() returns void as \$\$ \$\$; -- cleaned up, no marker';

    // Stage version A (with SECURITY DEFINER) ...
    await scratchFile.writeAsString(stagedContent);
    final add = await _git(tmp.path, ['add', relPath]);
    expect(add.exitCode, 0, reason: 'git add must succeed');

    // ... then further-edit the WORKING COPY without re-staging.
    await scratchFile.writeAsString(workingTreeContentAfterFurtherEdit);

    // A plain working-tree read (the OLD, buggy behavior) sees the
    // edited-clean content — it would have MISSED the staged SECURITY
    // DEFINER, which is exactly the bug this fix closes.
    final workingTreeRead = scratchFile.readAsStringSync();
    expect(workingTreeRead, workingTreeContentAfterFurtherEdit);
    expect(workingTreeRead.toLowerCase(), isNot(contains('security definer')),
        reason: 'demonstrates the bug: a working-tree read misses the '
            'staged content entirely');

    // `git show :<path>` (the FIXED behavior) reads the STAGED blob — the
    // one that actually lands in the commit — and correctly still sees
    // SECURITY DEFINER.
    final show = await _git(tmp.path, ['show', ':$relPath']);
    expect(show.exitCode, 0, reason: 'git show :<path> must succeed for a staged path');
    final stagedRead = show.stdout as String;
    expect(stagedRead, stagedContent);
    expect(stagedRead.toLowerCase(), contains('security definer'),
        reason: 'the fix: reading the STAGED blob correctly still sees the '
            'dangerous content that is about to be committed');

    // `git cat-file -e :<path>` (the existence-check half of the fix)
    // confirms the staged blob exists.
    final catFile = await _git(tmp.path, ['cat-file', '-e', ':$relPath']);
    expect(catFile.exitCode, 0,
        reason: 'git cat-file -e :<path> must confirm the staged blob exists');
  });

  // ── OI-72 ────────────────────────────────────────────────────────────────
  // The SAME staged-vs-working-tree asymmetry, one level up: the gate applied
  // the fix above to `contentForcesCatastrophic` but NOT to the review file it
  // is gating on. `stagedDiffHash()` hashed the INDEX while the review file was
  // checked with `File(...).existsSync()` — the WORKING TREE. So an untracked
  // docs/reviews/<hash>-review.md satisfied the catastrophic gate without ever
  // entering history, and because it was untracked it contributed nothing to
  // the staged diff, so the hash it was named after never moved. Three untracked
  // `docs/reviews/*-review.md` files were sitting in the working tree when this
  // was found.
  //
  // Staging the review is what makes the fix meaningful, and that is only
  // possible because the hash now EXCLUDES docs/reviews/ — otherwise staging it
  // would rename the very file it satisfies.
  group('OI-72 — the review artifact must be staged, not merely on disk', () {
    /// Builds an isolated repo carrying the real gate + registry, stages a
    /// catastrophic change, and returns (repo, expected review filename).
    Future<({Directory tmp, String hash})> setUpCatastrophicRepo(
        String prefix) async {
      final srcRoot = Directory.current.path;
      final tmp = await _freshIsolatedGitTargetDir(prefix);
      await _git(tmp.path, ['init', '-q']);
      await _git(tmp.path, ['config', 'user.email', 'test@example.com']);
      await _git(tmp.path, ['config', 'user.name', 'Test']);

      await Directory('${tmp.path}/scripts').create(recursive: true);
      for (final f in const [
        'check_code_review_pass_exists.dart',
        'blast_radius_content_rules_lib.dart',
      ]) {
        File('$srcRoot/scripts/$f').copySync('${tmp.path}/scripts/$f');
      }
      await Directory('${tmp.path}/docs/reviews').create(recursive: true);
      File('$srcRoot/docs/blast_radius.yaml')
          .copySync('${tmp.path}/docs/blast_radius.yaml');

      // SECURITY DEFINER content forces catastrophic regardless of path tier.
      const mig = 'supabase/migrations/999_probe.sql';
      final migFile = File('${tmp.path}/$mig');
      await migFile.parent.create(recursive: true);
      await migFile.writeAsString(
          'create function f() returns void security definer as \$\$ \$\$;');
      await _git(tmp.path, ['add', mig]);

      // The hash the gate will demand — computed the same way it does, over the
      // staged diff EXCLUDING docs/reviews.
      final diff = await Process.run(
          // MUST be byte-identical to the gate's own argv in
          // check_code_review_pass_exists.dart, or this computes a different
          // oracle and the test passes by coincidence (round-2 review P2-C
          // caught exactly that: the pre-P3-2 form here happened to agree at
          // the repo root and diverged from a subdirectory).
          'git', ['-C', tmp.path, 'diff', '--cached', '--', ':(top)',
              ':(top,exclude)docs/reviews'],
          stdoutEncoding: null,
          environment: Map<String, String>.from(Platform.environment)
            ..removeWhere((k, _) => _gitEnvKeysToStrip.contains(k.toUpperCase())),
          includeParentEnvironment: false);
      final hasher = await Process.start('git', ['hash-object', '--stdin']);
      hasher.stdin.add(diff.stdout as List<int>);
      await hasher.stdin.close();
      final hash = (await hasher.stdout
              .transform(const SystemEncoding().decoder)
              .join())
          .trim()
          .substring(0, 12);
      await hasher.exitCode;
      return (tmp: tmp, hash: hash);
    }

    Future<ProcessResult> runGate(Directory tmp) => Process.run(
          'dart',
          ['scripts/check_code_review_pass_exists.dart'],
          workingDirectory: tmp.path,
          environment: Map<String, String>.from(Platform.environment)
            ..removeWhere((k, _) => _gitEnvKeysToStrip.contains(k.toUpperCase())),
          includeParentEnvironment: false,
          runInShell: true,
        );

    test('an UNTRACKED accepted review no longer satisfies the gate', () async {
      final s = await setUpCatastrophicRepo('oi72_untracked_test');
      addTearDown(() => s.tmp.delete(recursive: true));

      // Present on disk, accepted, correctly named — but never `git add`ed.
      await File('${s.tmp.path}/docs/reviews/${s.hash}-review.md')
          .writeAsString('---\nverdict: accepted\n---\n');

      final r = await runGate(s.tmp);
      expect(r.exitCode, 1,
          reason: 'the pre-fix gate passed here: existsSync() saw the working-'
              'tree file while the hash came from the index. An unstaged review '
              'never enters history, so nothing records that this commit was '
              'reviewed.');
      expect('${r.stdout}${r.stderr}', contains('not staged'),
          reason: 'the failure must name the actual problem — the author is '
              'one `git add` away, and a generic "run /review" message would '
              'send them to regenerate a file they already have');
    });

    test('a STAGED accepted review satisfies it, and staging does not rename it',
        () async {
      final s = await setUpCatastrophicRepo('oi72_staged_test');
      addTearDown(() => s.tmp.delete(recursive: true));

      final rel = 'docs/reviews/${s.hash}-review.md';
      await File('${s.tmp.path}/$rel').writeAsString('---\nverdict: accepted\n---\n');
      await _git(s.tmp.path, ['add', rel]);

      final r = await runGate(s.tmp);
      expect(r.exitCode, 0,
          reason: 'staging the review must SATISFY the gate — if the hash still '
              'covered docs/reviews/, adding the file would move the hash and '
              'the gate would now demand a differently-named file, making the '
              'requirement unsatisfiable');
      expect('${r.stdout}${r.stderr}', contains(rel));
    });

    test('a staged review whose verdict is not accepted still FAILS', () async {
      final s = await setUpCatastrophicRepo('oi72_rejected_test');
      addTearDown(() => s.tmp.delete(recursive: true));

      final rel = 'docs/reviews/${s.hash}-review.md';
      await File('${s.tmp.path}/$rel').writeAsString('---\nverdict: rejected\n---\n');
      await _git(s.tmp.path, ['add', rel]);

      final r = await runGate(s.tmp);
      expect(r.exitCode, 1,
          reason: 'reading from the index must not weaken the verdict check');
      // Assert the REASON, not just the exit code (round-1B review P3-1): the
      // pre-fix gate also exits 1 here, but for the wrong reason — staging the
      // review moved the hash, so it failed with file-not-found rather than
      // verdict-rejected. Exit code alone cannot tell those apart.
      expect('${r.stdout}${r.stderr}', contains('verdict is not "accepted"'));
    });
  });
}
