// scripts/check_skill_tuning_history.dart
//
// Gate: a commit that ADDS a `docs/reviews/<x>-review.md` must also append a
// same-dated entry to `.claude/skills/code-review/SKILL.md`'s Tuning history.
//
// CLAUDE.md §5.1 (skill self-evolution) and the skill's own §5 both require it.
// Neither was enforced. On 2026-08-25 a B-pass produced a 4-finding review and
// the entry was never written; it surfaced only when founder asked whether
// discipline had been followed. Pure predicate: scripts/skill_tuning_lib.dart.
//
// SCOPE, stated so the pass is not read as wider than it is: this gates the
// code-review (B-pass) skill only. `/hermes-pass` writes to the same directory
// but keeps its own tuning section, and wiring that needs its own decision about
// which file a hermes report must update — not assumed here.
//
// FAILS OPEN on anything it cannot answer (unreadable skill file, unparseable
// `reviewed_at:`, git unavailable). A gate that wedges a commit because it could
// not read its own input is worse than the omission it prevents.

import 'dart:io';

import 'skill_tuning_lib.dart';

const _skillPath = '.claude/skills/code-review/SKILL.md';
const _tag = '[check_skill_tuning_history]';

ProcessResult? _git(List<String> args) {
  try {
    return Process.runSync('git', args, stdoutEncoding: systemEncoding);
  } catch (_) {
    return null;
  }
}

/// Staged paths ADDED by this commit (status A), forward-slashed.
List<String>? _stagedAdded() {
  final r = _git(['diff', '--cached', '--name-status', '--diff-filter=A']);
  if (r == null || r.exitCode != 0) return null;
  final out = <String>[];
  for (final line in (r.stdout as String).split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    out.add(parts.sublist(1).join(' ').replaceAll(r'\', '/'));
  }
  return out;
}

/// Read a path at [rev] — `:` for the STAGED blob, `HEAD:` for the last commit.
///
/// Load-bearing, and the repo has paid for this once already: OI-72 found a
/// review file could satisfy the catastrophic gate while never entering history,
/// because the gate read the working tree. What is committed is what must be
/// checked.
///
/// ⚠ The `exitCode != 0` check is the whole safety of the fallback below, and
/// the e2e caught its absence: `git show HEAD:<missing>` exits non-zero but
/// still yields an EMPTY stdout, so returning it unchecked hands the predicate
/// `''` instead of `null`. An empty string is not "unreadable" — it is a file
/// with no tuning entry, so the gate would BLOCK on a repo that simply has no
/// skill file. Fail-open became fail-closed through a missing exit-code check.
String? _showOrNull(String rev, String path) {
  final r = _git(['show', '$rev$path']);
  if (r == null || r.exitCode != 0) return null;
  return r.stdout as String;
}

String? _stagedContent(String path) => _showOrNull(':', path);

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');

  final added = _stagedAdded();
  if (added == null) {
    stdout.writeln('$_tag SKIPPED: git unavailable — failing OPEN.');
    exit(0);
  }

  // ANY .md added under docs/reviews/, not a suffix allow-list.
  //
  // ⚠ The first version matched only `-review.md`. Measured during round 1 of
  // this batch's own review: of 164 files in docs/reviews/, **81 use `-bpass.md`
  // and 79 use `-review.md`** — so the gate was blind to the MAJORITY
  // convention, and the skill's own Tuning history cites `-bpass.md` for most of
  // its recent entries. A review named the usual way would have passed silently,
  // which is the exact omission this gate exists to catch.
  //
  // Enumerating both suffixes would fix today and rot on the next spelling. The
  // artifact is identified by WHAT IT IS — a file in the reviews directory —
  // with only the two generated index files excluded by name.
  const notAReview = {'INDEX.md', 'README.md'};
  final reviews = added
      .where((p) =>
          p.startsWith('docs/reviews/') &&
          p.endsWith('.md') &&
          !notAReview.contains(p.split('/').last))
      .toList();
  if (reviews.isEmpty) {
    stdout.writeln('$_tag PASS: no review file added by this commit '
        '(${added.length} added path(s) scanned).');
    exit(0);
  }

  final claims = <ReviewClaim>[];
  for (final p in reviews) {
    final body = _stagedContent(p);
    claims.add(ReviewClaim(p, body == null ? null : reviewedOnFrom(body)));
  }

  // The skill file may be staged (edited this commit) or unchanged (edited
  // earlier). Prefer the staged blob; fall back to HEAD so an unmodified but
  // already-correct skill file still satisfies the gate.
  final skill = _stagedContent(_skillPath) ?? _showOrNull('HEAD:', _skillPath);

  final result = evaluateTuning(addedReviews: claims, skillMarkdown: skill);

  switch (result.verdict) {
    case TuningVerdict.notApplicable:
      stdout.writeln('$_tag PASS: ${result.reason}.');
      exit(0);
    case TuningVerdict.satisfied:
      stdout.writeln(
          '$_tag PASS: ${result.reason} (${claims.length} review(s) checked).');
      exit(0);
    case TuningVerdict.undetermined:
      stdout.writeln('$_tag SKIPPED: ${result.reason}.');
      for (final p in result.offendingPaths) {
        stdout.writeln('  - $p');
      }
      exit(0);
    case TuningVerdict.missingEntry:
      final sink = warnOnly ? stdout : stderr;
      sink.writeln('$_tag ${warnOnly ? "WARN" : "FAIL"}: ${result.reason}.');
      for (final p in result.offendingPaths) {
        sink.writeln('  - $p');
      }
      sink.writeln('');
      sink.writeln('  CLAUDE.md §5.1 and $_skillPath\'s own §5 require an entry');
      sink.writeln('  per invocation: date, blast-radius, findings count,');
      sink.writeln('  false-alarm count, and what was tuned (or that nothing was).');
      sink.writeln('  Append a `- **YYYY-MM-DD** — blast-radius …` bullet under');
      sink.writeln('  "## 7. Tuning history", matching the review\'s reviewed_at.');
      exit(warnOnly ? 0 : 1);
  }
}
