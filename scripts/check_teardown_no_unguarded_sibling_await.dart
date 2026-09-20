// scripts/check_teardown_no_unguarded_sibling_await.dart
//
// Blocks a STAGED test file whose tearDown/tearDownAll block mixes a
// try/catch-guarded await with an unguarded SIBLING await in the same block.
//
// WHY (feedback_mistake_guard_without_its_mirror.md, instance #27,
// 2026-09-10): `ai_proxy_test.dart`/`pgvector_test.dart` wrapped one cleanup
// call (`await x.delete()`) in try/catch and left a sibling cleanup call
// (`await y.signOut()`) bare, two lines below, in the SAME tearDown block. The
// guard protected one call and left its neighbour able to throw -- and a
// throwing teardown can mask the real test failure underneath it (see
// CLAUDE.md's `@Timeout`/full-suite pitfalls row: "a failing teardown can mask
// the failure it follows... make it never throw").
//
// SCOPE: only STAGED test files (`git diff --cached --name-only`), never a
// full-repo sweep -- this repo has 267 files with tearDown blocks today; most
// pre-date this gate and are out of scope until a commit touches them (same
// bounding convention as check_no_deferral_euphemism.dart's staged-diff scan,
// and CLAUDE.md's own "conversion-on-touch" precedent for stale citations).
// Only flags the INCONSISTENT-guarding shape -- a block with zero guards at
// all is a different, wider problem this gate does not claim to cover.
//
// Decision logic lives in scripts/teardown_sibling_await_lib.dart (pure,
// string-in/findings-out, unit-tested against literal Dart source snippets).
//
// Exit 0 = pass. Exit 1 = fail. --warn-only never fails.

import 'dart:io';
import 'teardown_sibling_await_lib.dart';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[teardown-sibling-await WARN]' : '[teardown-sibling-await]';

  ProcessResult? diffResult;
  try {
    diffResult = Process.runSync('git', ['diff', '--cached', '--name-only']);
  } on ProcessException {
    diffResult = null;
  }

  if (diffResult == null || diffResult.exitCode != 0) {
    // Fail OPEN, loudly -- never wedge a commit on a git/environment problem.
    // Matches check_worktree_config_integrity.dart's convention.
    stderr.writeln('$tag WARNING (passing): could not read staged files '
        '(git diff --cached --name-only unavailable). Scan skipped.');
    exit(0);
  }

  // Self-exclusion: this gate's own test file necessarily embeds the exact
  // BAD tearDown shape as string-literal fixture data feeding the pure
  // detector under test -- reading its whole-file content the same way as
  // any other staged test file makes the fixtures read as real tearDown
  // blocks in THIS file. Same self-referential class as every sibling gate
  // in this batch (feedback_mistake_guard_without_its_mirror.md's "sibling
  // shape" note).
  const selfTestFile = 'test/scripts/teardown_sibling_await_lib_test.dart';
  final stagedTestFiles = (diffResult.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) =>
          s.startsWith('test/') && s.endsWith('.dart') && s != selfTestFile)
      .toList();

  final allFindings = <TeardownFinding>[];
  for (final path in stagedTestFiles) {
    final f = File(path);
    if (!f.existsSync()) continue; // deleted/renamed in this diff
    final content = f.readAsStringSync();
    allFindings.addAll(findUnguardedSiblingAwaits(content, fileLabel: path));
  }

  if (allFindings.isEmpty) {
    stdout.writeln('$tag PASS: no tearDown/tearDownAll block in ${stagedTestFiles.length} '
        'staged test file(s) mixes a guarded await with an unguarded sibling.');
    exit(0);
  }

  stderr.writeln('$tag FAIL: ${allFindings.length} tearDown/tearDownAll block(s) mix a '
      'try/catch-guarded await with an unguarded sibling await in the SAME block.');
  for (final f in allFindings) {
    stderr.writeln('  ${f.describe()}');
  }
  stderr.writeln(
    '\n  Fix: wrap the unguarded await in the same try { await ...; } catch (_) {}\n'
    '  shape as its guarded sibling -- or wrap the whole tearDown body in one\n'
    '  try/catch if every cleanup call in it should tolerate failure.',
  );
  exit(warnOnly ? 0 : 1);
}
