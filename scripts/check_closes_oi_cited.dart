// scripts/check_closes_oi_cited.dart
//
// Commit-msg gate: a commit that flips an OI from OPEN to CLOSED in
// docs/audit/open_issues.md must cite `closes-oi: OI-NN` in its body.
//
// WHY THIS EXISTS. `docs/audit/open_issues.md:17` documents the convention
// ("every commit that closes one cites `closes-oi: OI-NN`"). It was followed in
// 5 citation lines across 3 of the last 400 commits and enforced by nothing —
// a board that claims a practice nobody performs. Either enforce it or delete
// it; this enforces it, narrowly.
//
// WHY commit-msg AND NOT pre-commit. pre-commit runs BEFORE git writes the
// message, so `-m` / `-F` / `--amend` commits have nothing to check. That is
// the same reason scripts/commit-msg.sh already exists for `closes-diagnose:`.
//
// WHY IT COMPARES BLOBS, NOT DIFF TEXT. The OI-58a version-bump exemption went
// through three rejected designs that all parsed diff text the commit author
// writes, and each was bypassed by feeding the parser something it mis-read
// (a content line starting `++ `, a file git renders with no +/- lines, an
// unanchored regex used as a containment test). So this reads the BEFORE blob
// (HEAD) and the AFTER blob (the staged index), parses each into
// {OI-NN -> status}, and diffs the two maps. There is no attacker-shaped text
// in the decision path.
//
// Usage: dart run scripts/check_closes_oi_cited.dart <commit-msg-file>
// Exit codes: 0 = pass (or not applicable), 1 = missing citation, 2 = usage.

import 'dart:io';

const _boardPath = 'docs/audit/open_issues.md';

/// `## OI-47 — L30 prompt injection vectors: …`
final _sectionRe = RegExp(r'^##\s+(OI-\d+)\b', multiLine: true);

/// `- **Status**: CLOSED · 2026-07-28 · …` / `- **Status**: OPEN — …`
final _statusRe = RegExp(r'^-\s+\*\*Status\*\*:\s*\**\s*([A-Z_]+)', multiLine: true);

String? _gitOrNull(List<String> args) {
  final r = Process.runSync('git', args);
  return r.exitCode == 0 ? (r.stdout as String) : null;
}

bool _refExists(String ref) =>
    Process.runSync('git', ['rev-parse', '-q', '--verify', ref]).exitCode == 0;

/// `## OI-NN` sections in [content] whose status line this parser cannot read.
///
/// An unreadable status is NOT a silent omission. `parseBoardStatuses` drops
/// such a section from its map, so `newlyClosed` never visits it and no citation
/// is ever demanded — a formatting slip like `- **Status:** CLOSED` (colon
/// inside the bold) or a missing `- ` bullet would disable this gate for that
/// issue, with no output at all. Same family as the OI-68 scar recorded in
/// `open_issues.md`: a parser that silently skips what it does not understand
/// reports success while doing nothing.
List<String> unreadableStatuses(String content) {
  final bad = <String>[];
  final matches = _sectionRe.allMatches(content).toList();
  for (var i = 0; i < matches.length; i++) {
    final end = i + 1 < matches.length ? matches[i + 1].start : content.length;
    if (_statusRe.firstMatch(content.substring(matches[i].end, end)) == null) {
      bad.add(matches[i].group(1)!);
    }
  }
  return bad;
}

/// Maps every `## OI-NN` section to the status on its first `**Status**:` line.
/// A section with no status line is omitted here and reported by
/// [unreadableStatuses] — never silently accepted.
Map<String, String> parseBoardStatuses(String content) {
  final out = <String, String>{};
  final matches = _sectionRe.allMatches(content).toList();
  for (var i = 0; i < matches.length; i++) {
    final oi = matches[i].group(1)!;
    final start = matches[i].end;
    final end = i + 1 < matches.length ? matches[i + 1].start : content.length;
    final status = _statusRe.firstMatch(content.substring(start, end));
    if (status != null) out[oi] = status.group(1)!.toUpperCase();
  }
  return out;
}

/// OIs whose status moved OPEN (or IN_PROGRESS) -> CLOSED between two boards.
List<String> newlyClosed(Map<String, String> before, Map<String, String> after) {
  final closed = <String>[];
  after.forEach((oi, now) {
    if (now != 'CLOSED') return;
    final was = before[oi];
    // A section that did not exist before is NOT a transition — a batch may add
    // an OI already-closed (an issue found and fixed in the same breath), and
    // demanding a citation for that is noise, not discipline.
    if (was == null || was == 'CLOSED') return;
    closed.add(oi);
  });
  closed.sort();
  return closed;
}

/// Which of [required] are cited as `closes-oi: OI-NN` in the message body.
Set<String> citedOis(String body) {
  final re = RegExp(r'closes-oi:\s*(OI-\d+)', caseSensitive: false);
  return re.allMatches(body).map((m) => m.group(1)!.toUpperCase()).toSet();
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
        'Usage: dart run scripts/check_closes_oi_cited.dart <commit-msg-file>');
    exit(2);
  }
  final msgFile = File(args[0]);
  if (!msgFile.existsSync()) {
    stderr.writeln('[closes-oi] commit message file not found: ${args[0]}');
    exit(2);
  }

  // A merge/cherry-pick/revert commit re-presents the branch's whole change as
  // its own staged diff, so an OI closed on the branch would demand the citation
  // a SECOND time — in an auto-generated merge subject that has no body. The
  // citation belongs on the commit that does the closing. Same detection the
  // worktree gate uses (check_commit_from_worktree.dart:78-80).
  //
  // Residual, stated rather than hidden: an OI closed ONLY inside a merge — by
  // a conflict resolution that flips the status line — never requires a
  // citation. Narrow, and far cheaper than citing twice on every merge.
  if (_refExists('MERGE_HEAD') ||
      _refExists('CHERRY_PICK_HEAD') ||
      _refExists('REVERT_HEAD')) {
    exit(0);
  }

  // Nothing staged for the board -> nothing to check.
  final staged = _gitOrNull(['diff', '--cached', '--name-only', '--', _boardPath]);
  if (staged == null || staged.trim().isEmpty) exit(0);

  final beforeRaw = _gitOrNull(['show', 'HEAD:$_boardPath']);
  final afterRaw = _gitOrNull(['show', ':$_boardPath']);
  if (afterRaw == null) exit(0); // deleted, or unreadable — not our call to make
  // No HEAD version (initial commit / board newly added) means no transition.
  // Fail LOUD on a status line we cannot read, rather than quietly requiring no
  // citation for it. Checked on the staged (after) blob only — a pre-existing
  // malformed line in HEAD is not this commit's to fix, but shipping one is.
  final unreadable = unreadableStatuses(afterRaw);
  if (unreadable.isNotEmpty) {
    stderr.writeln('[closes-oi] FAIL: ${unreadable.length} section(s) in '
        '$_boardPath have a `**Status**:` line this gate cannot read, so they '
        'would silently escape the citation requirement:');
    for (final oi in unreadable) {
      stderr.writeln('  - $oi');
    }
    stderr.writeln('             Expected exactly: `- **Status**: OPEN` / '
        '`- **Status**: CLOSED · …` (leading `- `, colon OUTSIDE the bold).');
    exit(1);
  }

  final before = parseBoardStatuses(beforeRaw ?? '');
  final after = parseBoardStatuses(afterRaw);

  final closed = newlyClosed(before, after);
  if (closed.isEmpty) exit(0);

  final body = msgFile.readAsStringSync();
  final cited = citedOis(body);
  final missing = closed.where((oi) => !cited.contains(oi)).toList();
  if (missing.isEmpty) {
    stdout.writeln(
        '[closes-oi] OK: ${closed.join(', ')} closed and cited.');
    exit(0);
  }

  stderr.writeln(
      '[closes-oi] FAIL: this commit closes ${missing.join(', ')} in $_boardPath '
      'but the message does not cite them.');
  stderr.writeln('             Add to the commit body:');
  for (final oi in missing) {
    stderr.writeln('               closes-oi: $oi');
  }
  stderr.writeln(
      '             $_boardPath documents this convention; it is now enforced '
      'so the board stops claiming a practice nobody performs.');
  exit(1);
}
