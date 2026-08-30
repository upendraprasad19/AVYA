// scripts/check_closes_oi_performed.dart
//
// Merge-commit gate: every `closes-oi: OI-NN` in the commits a merge brings in
// must be matched by OI-NN actually reading CLOSED on the board at that merge.
//
// THE MIRROR OF check_closes_oi_cited.dart. That gate enforces
// `status-change => citation`; this one enforces `citation => status-change`.
// The full rationale, and the two real shipped failures that motivated it,
// live in scripts/oi_closure_lib.dart's header — read that first.
//
// WHERE IT RUNS. Picked up automatically by the `scripts/check_*.dart` glob in
// BOTH scripts/pre-commit.sh and the `audit-gates` CI job. It needs no
// allowlist entry and no workflow edit: the CI job already checks out with
// `fetch-depth: 0` (load-bearing for check_oi_numbering_unique.dart), so
// `HEAD^1..HEAD^2` is reachable there.
//
// It SKIPS unless HEAD is a merge commit, which makes the pre-commit case a
// no-op in normal work (you are committing on a branch; HEAD has one parent)
// and makes CI-on-push-to-main the enforcing run, where HEAD *is* the merge.
// That asymmetry is the same one check_plan_review_record_exists.dart records:
// a `--no-ff` merge skips the local pre-commit hook entirely, so the merge
// commit is only ever judged in CI.
//
// FAILS OPEN, AND SAYS SKIPPED RATHER THAN PASS. Every path where git cannot
// answer exits 0 with an explicit SKIPPED line naming what it could not
// determine. check_oi_numbering_unique.dart's first live run reported PASS
// against an EMPTY board because Process.runSync defaults to systemEncoding
// and mangled the em-dash in every `## OI-NN — title` heading (0 of 77 parsed).
// Every git read here therefore pins `stdoutEncoding: utf8` explicitly, and a
// board that parses to zero entries is treated as unreadable, not as empty.
//
// Usage: dart run scripts/check_closes_oi_performed.dart [--warn-only]
// Exit codes: 0 = pass / skipped / --warn-only, 1 = a cited close never happened.

import 'dart:convert';
import 'dart:io';

import 'oi_closure_lib.dart';

const _openBoard = 'docs/audit/open_issues.md';
const _closedBoard = 'docs/audit/closed_issues.md';

/// Runs git with UTF-8 pinned on BOTH streams. See the header: the default
/// systemEncoding silently corrupts every em-dash heading on this machine, and
/// a corrupted board parses to zero entries, which reads as "nothing to check".
String? _gitOrNull(List<String> args) {
  try {
    final r = Process.runSync('git', args,
        stdoutEncoding: utf8, stderrEncoding: utf8);
    return r.exitCode == 0 ? r.stdout as String : null;
  } on ProcessException {
    return null;
  }
}

void _skip(String why) {
  stdout.writeln('[closes-oi-performed] SKIPPED: $why');
  exit(0);
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');

  // %P is the parent list. Two or more parents == a merge commit.
  final parentsRaw = _gitOrNull(['log', '-1', '--format=%P', 'HEAD']);
  if (parentsRaw == null) {
    _skip('git could not report HEAD\'s parents (not a repo, or no commits).');
  }
  final parents =
      parentsRaw!.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
  if (parents.length < 2) {
    // The overwhelmingly common case at pre-commit. Silent-ish by design: a
    // line on every ordinary commit would be noise, and noise is what makes
    // people stop reading gate output.
    exit(0);
  }

  // The commits the merge BRINGS IN — reachable from the merged branch and not
  // from the target. NUL-separated so a message body containing anything at all
  // cannot be mistaken for a record boundary.
  final logRaw = _gitOrNull(['log', '--format=%B%x00', 'HEAD^1..HEAD^2']);
  if (logRaw == null) {
    _skip('could not read HEAD^1..HEAD^2 — a shallow clone cannot see the '
        'merged range. The audit-gates CI job checks out fetch-depth: 0.');
  }
  final messages =
      logRaw!.split('\x00').map((m) => m.trim()).where((m) => m.isNotEmpty);

  final cited = citationsAcross(messages);
  if (cited.isEmpty) exit(0);

  final openRaw = _gitOrNull(['show', 'HEAD:$_openBoard']);
  if (openRaw == null) {
    _skip('could not read $_openBoard at HEAD.');
  }
  // closed_issues.md is allowed to be absent (it did not always exist); an
  // absent file is a determined answer of "no closed entries", unlike an
  // unreadable open board above.
  final closedRaw = _gitOrNull(['show', 'HEAD:$_closedBoard']) ?? '';

  final statuses =
      mergedBoardStatuses(openContent: openRaw!, closedContent: closedRaw);
  if (statuses.isEmpty) {
    // Not "no issues" — far more likely a parse that produced nothing, which is
    // exactly the failure this gate's header warns about. Refusing to render a
    // verdict is the honest move.
    _skip('parsed ZERO OI sections from the board at HEAD. Treating as '
        'unreadable rather than empty — a board that parses to nothing is the '
        'encoding-corruption shape, not a real state.');
  }

  final verdict = unsatisfiedCitations(cited, statuses);

  // A dangling citation WARNS, it does not block. OI numbers have been
  // renumbered on a branch six times in this repo's history, so a message can
  // legitimately name a number that no longer exists by the time it merges.
  // Blocking on that would create exactly the false-positive class that trains
  // people to bypass a gate. The measured, shipped bug is `unperformed`, and
  // that is what blocks.
  if (verdict.unknown.isNotEmpty) {
    stdout.writeln('[closes-oi-performed] WARN: ${verdict.unknown.join(', ')} '
        'cited as closed but present on NEITHER board. Likely a typo or a '
        'number renumbered after the message was written. Not blocking.');
  }

  if (verdict.unperformed.isEmpty) {
    stdout.writeln('[closes-oi-performed] OK: '
        '${cited.length} citation(s) checked against ${statuses.length} board '
        'entries; every OI a merged commit claims to close reads CLOSED.');
    exit(0);
  }

  final label = warnOnly ? 'WARN (--warn-only)' : 'FAIL';
  final sink = warnOnly ? stdout : stderr;
  sink.writeln('[closes-oi-performed] $label: this merge brings in commits '
      'that claim to close ${verdict.unperformed.join(', ')}, but the board at '
      'this commit does not agree:');
  for (final oi in verdict.unperformed) {
    sink.writeln('  - $oi is "${statuses[oi]}" in $_openBoard');
  }
  sink.writeln('             Either finish the close — move the entry to '
      '$_closedBoard with `- **Status**: CLOSED` and regenerate the index with '
      '`dart run scripts/build_oi_index.dart` — or drop the `closes-oi:` line '
      'from the commit that does not actually close it.');
  sink.writeln('             Both halves of this have shipped: OI-150 was '
      'cited and never performed (the board sat stale while an agent reported '
      'it closed); OI-58 was cited for work that failed review twice and was '
      'split out. A citation nobody checks is a claim, not a record.');
  exit(warnOnly ? 0 : 1);
}
