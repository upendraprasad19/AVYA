// test/contracts/ci_workflow_concurrency_test.dart
//
// CI-speed batch (2026-07-26). Pins the three properties of
// `.github/workflows/test.yml` that this batch established, the first of which
// is a real defect in enforcement machinery rather than a speed tweak:
//
//   1. CONCURRENCY (the defect). `cancel-in-progress: true` applied to EVERY
//      ref. All main pushes share the group `<workflow>-refs/heads/main`, so a
//      second merge cancelled the first merge's run — and that run is the only
//      place `plan-review-record` (the §4.12 keystone gate) executes. The gate
//      therefore skipped itself, silently, for a commit that DID land on main,
//      under exactly the condition it exists to catch: rapid back-to-back
//      merges. This test asserts the SEMANTICS both ways (main => never cancel,
//      PR => still cancel), not the literal expression text, so an equivalent
//      rewrite passes and an inverted one fails.
//
//   2. build-check has NO `needs:`. It is an independent compile check; the old
//      `needs: [analyze-and-unit-test, contract-tests]` made total wall-clock
//      the SUM of the two longest jobs (6m58s + 7m41s = 14m46s on run
//      30168462713) instead of their MAX.
//
//   3. setup-java caches gradle. Content-keyed, so a stale cache degrades to
//      the uncached behaviour rather than breaking.
//
// Comment-stripped before every assertion (per
// feedback_source_grep_strip_comments_first.md) — REQUIRED here, not cosmetic:
// the explanatory comments this batch added to test.yml themselves contain the
// literal strings `needs:` and `cancel-in-progress`, so an unstripped grep
// would false-pass assertion 2 against a comment.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    final f = File('.github/workflows/test.yml');
    expect(f.existsSync(), isTrue,
        reason: '.github/workflows/test.yml must exist');
    src = _stripYamlComments(f.readAsStringSync());
  });

  group('concurrency — the keystone gate must never be cancelled on main', () {
    test('cancel-in-progress is not an unconditional literal true', () {
      final raw = _cancelInProgressValue(src);
      expect(raw, isNotNull,
          reason: 'concurrency.cancel-in-progress must be declared');
      expect(raw, isNot('true'),
          reason: 'a blanket `true` cancels a main run mid-flight, which is how '
              'plan-review-record silently skips a merge commit that landed');
    });

    test('a push to main is NEVER cancelled', () {
      final raw = _cancelInProgressValue(src)!;
      expect(_evalGithubRefExpr(raw, 'refs/heads/main'), isFalse,
          reason: 'a second merge to main must not kill the first merge run — '
              'that run is the only place the §4.12 keystone gate executes');
    });

    test('a PR push is still cancelled (no wasted runners)', () {
      final raw = _cancelInProgressValue(src)!;
      expect(_evalGithubRefExpr(raw, 'refs/pull/14/merge'), isTrue,
          reason: 'refs/pull/N/merge is unique per PR, so superseding a stale '
              'PR run is safe and should be preserved');
      expect(_evalGithubRefExpr(raw, 'refs/heads/some-feature'), isTrue,
          reason: 'non-main branch pushes should still supersede');
    });
  });

  group('wall-clock', () {
    test('build-check declares no needs: (runs from t=0)', () {
      final job = _jobBlock(src, 'build-check');
      expect(job, isNotNull, reason: 'build-check job must exist');
      expect(RegExp(r'^\s+needs:', multiLine: true).hasMatch(job!), isFalse,
          reason: 'a needs: on build-check serializes the two longest jobs and '
              'roughly doubles total wall-clock; it gates nothing, since every '
              'job already fails the workflow independently');
    });

    test('setup-java caches gradle', () {
      final job = _jobBlock(src, 'build-check')!;
      expect(job.contains('actions/setup-java'), isTrue,
          reason: 'the APK job must still set up Java');
      expect(RegExp(r"cache:\s*'gradle'").hasMatch(job), isTrue,
          reason: 'without cache: gradle the APK job re-downloads the whole '
              'Gradle dependency graph on every run');
    });
  });
}

/// Strips FULL-LINE YAML comments only (first non-whitespace char is `#`).
///
/// Deliberately does not touch trailing `#` on a value line — a `#` inside a
/// quoted string or a `run:` shell body must survive untouched.
String _stripYamlComments(String s) => s
    .split('\n')
    .where((l) => !RegExp(r'^\s*#').hasMatch(l))
    .join('\n');

/// The raw scalar assigned to the top-level `concurrency.cancel-in-progress`.
String? _cancelInProgressValue(String src) =>
    RegExp(r'^\s*cancel-in-progress:\s*(.+?)\s*$', multiLine: true)
        .firstMatch(src)
        ?.group(1);

/// Extracts a job's YAML block: from `  <id>:` to the next sibling job.
///
/// Jobs are indented two spaces under `jobs:`, so the block ends at the next
/// line matching exactly that indent depth.
String? _jobBlock(String src, String jobId) {
  final lines = src.split('\n');
  final start = lines.indexWhere((l) => RegExp('^  $jobId:').hasMatch(l));
  if (start < 0) return null;
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (RegExp(r'^  [A-Za-z0-9_-]+:').hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n');
}

/// Evaluates the small subset of GitHub expression syntax used by
/// `cancel-in-progress`, for a given `github.ref`.
///
/// Handles a bare boolean literal and `${{ github.ref <op> '<literal>' }}` for
/// `==` / `!=`. Anything else throws rather than silently returning a default —
/// a test that quietly "passes" on an expression form it cannot read would be
/// exactly the false confidence this file exists to prevent.
bool _evalGithubRefExpr(String raw, String ref) {
  final v = raw.trim();
  if (v == 'true') return true;
  if (v == 'false') return false;

  final m = RegExp(
    r"^\$\{\{\s*github\.ref\s*(==|!=)\s*'([^']*)'\s*\}\}$",
  ).firstMatch(v);
  if (m == null) {
    throw StateError(
      'cancel-in-progress uses an expression this test cannot evaluate: "$v". '
      'Extend _evalGithubRefExpr so the main-vs-PR semantics stay asserted.',
    );
  }
  final negate = m.group(1) == '!=';
  final matches = ref == m.group(2);
  return negate ? !matches : matches;
}
