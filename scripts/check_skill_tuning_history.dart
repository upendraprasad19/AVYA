// scripts/check_skill_tuning_history.dart
//
// Gate: a commit that ADDS a `docs/reviews/<x>.md` must carry that review's tuning
// entry INSIDE the review file, as a `## Tuning entry` section (dated bullet first),
// and must NOT add new entries to the legacy archive
// `.claude/skills/code-review/tuning-history.md` (frozen).
//
// WHY INSIDE THE REVIEW (merge-conflict-treadmill A1, 2026-10-24). The archive was
// an append-at-EOF file that every parallel review PR edited at the same spot: it
// conflicted on 35 of 52 main-sync merges, and each conflict meant a hand-merge plus
// a CI rerun. A review file is unique per PR, so its own section cannot conflict.
//
// CLAUDE.md §5.1 (skill self-evolution) and .claude/skills/code-review/SKILL.md §5
// require the entry.
// Before the original gate, neither was enforced: on 2026-08-25 a B-pass produced a
// 4-finding review and the entry was never written; it surfaced only when founder
// asked whether discipline had been followed. Pure predicate:
// scripts/skill_tuning_lib.dart.
//
// TWO CHECKS, exit codes combined:
//   1. IN-REVIEW ROUTE (or a legacy archive entry that names the review): every
//      added review needs one.
//   2. FREEZE: a non-merge commit that makes the staged archive hold MORE dated
//      headers than its HEAD blob fails. Exempt: a merge in progress (MERGE_HEAD
//      path exists, via `git rev-parse --git-path` so a linked worktree works), an
//      archive with no HEAD blob. LOCAL-ONLY and TRANSITIONAL: CI's audit-gates job
//      runs every scripts/check_*.dart (this one is not on its skip list) but with
//      nothing staged, so it passes vacuously there, and a pre-A1 branch merged on
//      GitHub can still grow the archive. KNOWN LIMIT: the freeze compares COUNTS, so
//      a commit that un-dates one old header and adds a new dated one is not seen; that
//      takes deliberate effort and blocks nothing a mistake would produce.
//   The pre-commit loop hides this gate's output (pre-commit.sh), so on a block
//   re-run `dart run scripts/check_skill_tuning_history.dart` on the staged state
//   to read the message.
//
// SCOPE, stated so the pass is not read as wider than it is: this gates the
// code-review (B-pass) skill only. `/hermes-pass` writes to the same directory
// but keeps its own tuning section, and wiring that needs its own decision about
// which file a hermes report must update — not assumed here. Known limit: a later
// edit that DELETES a review's section is unchecked (the gate judges additions).
//
// FAILS OPEN on anything it cannot answer (unparseable `reviewed_at:`, git
// unavailable). An unreadable or absent ARCHIVE no longer silences the gate: it only
// means "no legacy entries", and the in-review route is still judged. A gate that
// wedges a commit because it could not read its own input is worse than the omission
// it prevents.

import 'dart:io';

import 'skill_tuning_lib.dart';

const _skillPath = '.claude/skills/code-review/tuning-history.md';
const _tag = '[check_skill_tuning_history]';

ProcessResult? _git(List<String> args) {
  try {
    return Process.runSync('git', args, stdoutEncoding: systemEncoding);
  } catch (_) {
    return null;
  }
}

/// True when a merge is in progress: the path `git rev-parse --git-path MERGE_HEAD`
/// names EXISTS (a file, a directory or an empty file all count, so a present-but-
/// unresolvable MERGE_HEAD is mid-merge, the `check_oi_numbering_unique.dart`
/// precedent). `--git-path` and not a hardcoded `.git/MERGE_HEAD`: in a linked
/// worktree `.git` is a FILE and the state lives under the common dir.
bool _mergeInProgress() {
  final r = _git(['rev-parse', '--git-path', 'MERGE_HEAD']);
  if (r == null || r.exitCode != 0) return false;
  final path = (r.stdout as String).trim();
  if (path.isEmpty) return false;
  return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
}

/// Staged paths ADDED by this commit (status A), forward-slashed.
///
/// `--no-renames` only OUTSIDE a merge: a review renamed on this branch then shows
/// as D + A and needs its own section (git's default rename detection would hide the
/// add). Inside a merge, renames from main keep default detection, so a bulk move
/// on main cannot block every sync.
List<String>? _stagedAdded({required bool noRenames}) {
  final r = _git([
    'diff',
    '--cached',
    '--name-status',
    '--diff-filter=A',
    if (noRenames) '--no-renames',
  ]);
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

/// The freeze check. Prints and returns the exit code it contributes.
int _freeze({
  required bool midMerge,
  required List<ReviewClaim> claims,
  required bool warnOnly,
}) {
  if (midMerge) return 0;
  final staged = _stagedContent(_skillPath);
  final head = _showOrNull('HEAD:', _skillPath);
  // HEAD blob absent (the archive is new in this repo) = nothing to compare.
  if (staged == null || head == null) return 0;
  if (countDatedHeaders(staged) <= countDatedHeaders(head)) return 0;

  final headLines = datedHeaderLines(head);
  final added = <String>[];
  final remaining = [...headLines];
  for (final l in datedHeaderLines(staged)) {
    if (!remaining.remove(l)) added.add(l);
  }
  final sink = warnOnly ? stdout : stderr;
  sink.writeln('$_tag ${warnOnly ? "WARN" : "FAIL"}: $_skillPath is FROZEN, but this commit adds '
      '${added.length} dated entr${added.length == 1 ? "y" : "ies"} to it:');
  for (final l in added.take(5)) {
    sink.writeln('  + $l');
  }
  sink.writeln('');
  sink.writeln('  Every parallel review PR appended at the end of that file, so it conflicted on');
  sink.writeln('  most main syncs. Put the entry INSIDE the review file instead, and restore the');
  sink.writeln('  archive:');
  sink.writeln('    git restore --source=HEAD --staged --worktree -- $_skillPath');
  sink.writeln('  (A dated SUB-bullet counts as an entry too.)');
  _printSectionTemplate(sink, claims);
  sink.writeln('  Re-run `dart run scripts/check_skill_tuning_history.dart` on the staged state to');
  sink.writeln('  read this message; the pre-commit loop hides it. Exempt: a merge in progress.');
  return warnOnly ? 0 : 1;
}

/// The exact section text for each added review that has a parseable date.
void _printSectionTemplate(StringSink sink, List<ReviewClaim> claims) {
  final dated = claims.where((c) => c.reviewedOn != null).toList();
  if (dated.isEmpty) {
    sink.writeln('  Section to put in the review file (docs/reviews/<x>.md):');
    sink.writeln('    ## Tuning entry');
    sink.writeln('    - **YYYY-MM-DD** - blast-radius <tier> - N findings; M false_alarm; tuning: <what changed, or none>');
    return;
  }
  for (final c in dated) {
    final tier = c.body == null ? null : frontmatterBlastRadius(c.body!);
    sink.writeln('  Section to put in ${c.path}:');
    sink.writeln('    ## Tuning entry');
    sink.writeln('    - **${c.reviewedOn}** - blast-radius ${tier ?? "<tier>"} - N findings; M false_alarm; tuning: <what changed, or none>');
  }
}

/// The review check. Prints and returns the exit code it contributes.
int _judgeReviews({
  required List<ReviewClaim> claims,
  required int addedCount,
  required bool warnOnly,
  required bool freezeFailed,
}) {
  if (claims.isEmpty) {
    // When the freeze already failed, a PASS line here would sit next to its FAIL and
    // read as a contradiction.
    if (!freezeFailed) {
      stdout.writeln('$_tag PASS: no review file added by this commit '
          '($addedCount added path(s) scanned).');
    }
    return 0;
  }

  // The legacy archive may be staged (edited this commit) or unchanged. Prefer the
  // staged blob; fall back to HEAD. Null = absent or unreadable = "no legacy
  // entries" (the in-review route is judged regardless).
  final archive = _stagedContent(_skillPath) ?? _showOrNull('HEAD:', _skillPath);

  final result = evaluateTuning(addedReviews: claims, skillMarkdown: archive);

  switch (result.verdict) {
    case TuningVerdict.notApplicable:
      stdout.writeln('$_tag PASS: ${result.reason}.');
      return 0;
    case TuningVerdict.satisfied:
      stdout.writeln(
          '$_tag PASS: ${result.reason} (${claims.length} review(s) checked).');
      return 0;
    case TuningVerdict.undetermined:
      stdout.writeln('$_tag SKIPPED: ${result.reason}.');
      for (final p in result.offendingPaths) {
        stdout.writeln('  - $p');
      }
      return 0;
    case TuningVerdict.missingEntry:
      final sink = warnOnly ? stdout : stderr;
      sink.writeln('$_tag ${warnOnly ? "WARN" : "FAIL"}: ${result.reason}.');
      for (final p in result.offendingPaths) {
        sink.writeln('  - $p');
      }
      sink.writeln('');
      sink.writeln('  CLAUDE.md §5.1 and .claude/skills/code-review/SKILL.md §5 require an entry');
      sink.writeln('  per invocation: date, blast-radius, findings count,');
      sink.writeln('  false-alarm count, and what was tuned (or that nothing was).');
      sink.writeln('  Put it INSIDE the review file, as a `## Tuning entry` heading at column 0');
      sink.writeln('  whose FIRST non-blank line is the dated bullet (date = the review\'s');
      sink.writeln('  reviewed_at; the blast-radius word must match the frontmatter tier):');
      _printSectionTemplate(sink, claims);
      sink.writeln('  Do NOT append to $_skillPath: it is frozen.');
      return warnOnly ? 0 : 1;
  }
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');

  final midMerge = _mergeInProgress();
  final added = _stagedAdded(noRenames: !midMerge);
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

  final claims = <ReviewClaim>[];
  for (final p in reviews) {
    final body = _stagedContent(p);
    claims.add(ReviewClaim(p, body == null ? null : reviewedOnFrom(body), body: body));
  }

  // Both checks always run and their exit codes combine, so a freeze violation can
  // never be hidden by a clean review (or the reverse).
  final freezeCode = _freeze(midMerge: midMerge, claims: claims, warnOnly: warnOnly);
  final reviewCode = _judgeReviews(
      claims: claims, addedCount: added.length, warnOnly: warnOnly, freezeFailed: freezeCode != 0);
  exit(freezeCode != 0 || reviewCode != 0 ? 1 : 0);
}
