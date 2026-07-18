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
}
