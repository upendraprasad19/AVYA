// scripts/check_oi_numbering_unique.dart
//
// Closes the MINT-TIME half of OI-112. The LANDING half (a corrupt board that
// cannot render) is `build_oi_index.dart:120-136`, which reads ONE working copy
// of ONE file and therefore cannot see another branch at all.
//
// WHAT IT CATCHES: this branch minted an OI number that origin/main also
// minted, for a different issue. Six live instances by 2026-08-16; the fifth
// (0e4d97cd -> 0cb4120a) went 3 days 0h 34m before a human noticed, and the
// pushed commit message still cites the superseded numbers because a pushed
// message is not rewritten. A seventh was in flight when this gate was written:
// main's OI-128 is the retire_worktree regenerable gap, branch
// oi-session-coordination's OI-128 is cross-session visibility.
//
// It also catches one number appearing on BOTH boards at once, which nothing
// in the repo checked before.
//
// WHERE IT RUNS, and why the two placements have different authority --
// OI-112's stated open decision ("pre-commit reads a possibly-stale
// origin/main; CI is authoritative but only after the push") is resolved by
// doing both rather than choosing:
//   - pre-commit (via the scripts/check_*.dart loop): ADVISORY-fast. It reads
//     whatever origin/main ref is already local and deliberately does NOT
//     fetch -- a network round trip on every commit would be slow, and would
//     hang a commit made offline. It catches the mint AT THE MOMENT IT
//     HAPPENS, which is the entire point; a stale origin/main only makes it
//     miss, never misfire.
//   - CI on merge-to-main: AUTHORITATIVE. actions/checkout gives a current
//     origin/main, so the comparison is against the real tip.
//   - pre-merge-commit: the merge is where both boards first coexist, and
//     until that hook was installed a CLEAN auto-merge ran no hook at all.
//
// FAILS OPEN on anything it cannot determine (no origin/main ref, no
// merge-base, git unavailable). A commit must never be wedged because the
// machine is offline or the remote ref was never fetched -- same convention as
// check_worktree_config_integrity.dart. An UNDETERMINED result is reported to
// stderr as a warning and exits 0.
//
// No `// Gate: N` line, per CLAUDE.md rule 24: a new gate takes NO number; the
// filename is the identity that pre-commit.sh, test.yml and Gate 33 key on.

import 'dart:convert';
import 'dart:io';

import 'oi_numbering_lib.dart';

const _openBoard = 'docs/audit/open_issues.md';
const _closedBoard = 'docs/audit/closed_issues.md';

/// Runs [exe] and returns stdout, or null when the command could not answer.
/// Null is a THIRD state, distinct from an empty result: an empty board is an
/// answer, a failed `git show` is not (feedback_bad_news_vs_no_news).
///
/// `stdoutEncoding: utf8` is LOAD-BEARING, not tidiness. Process.runSync
/// defaults to `systemEncoding`; on this Windows machine that decodes the
/// board's em-dash separator (U+2014, UTF-8 `E2 80 94`) as three cp1252
/// characters, so `oiSectionRe` matched 0 of 77 headings and this gate reported
/// PASS against an EMPTY mainline board -- on a branch carrying a real, live
/// collision. Caught only because the first end-to-end run was against a branch
/// already known to be colliding. See `_parseStrict` for the structural half of
/// the fix: pinning the encoding fixes the instance, refusing to treat an
/// unparseable board as a clean one fixes the class.
String? _run(String exe, List<String> args) {
  try {
    final r = Process.runSync(exe, args, stdoutEncoding: utf8);
    if (r.exitCode != 0) return null;
    return r.stdout as String;
  } on ProcessException {
    return null;
  }
}

/// Board content at [rev], or null when unreadable. A board file that does not
/// exist at that rev is legitimately empty -- the closed board postdates the
/// open one -- so an absent path yields '' via the caller, not null.
String? _showAtRev(String rev, String path) => _run('git', ['show', '$rev:$path']);

/// Parses a board and distinguishes "genuinely no entries" from "could not read
/// this at all", which look identical to every caller that returns a bare map.
///
/// Returns null -- meaning UNDETERMINED -- when [source] is null (git could not
/// answer), or when the file plainly CONTAINS headings that the full pattern
/// failed to parse.
///
/// The discriminator is [countHeadingPrefixes], which matches only the
/// ASCII `## OI-<digits>` prefix. That count survives any mis-decoding; the
/// em-dash separator in `oiSectionRe` does not. So:
///   prefixes > 0, parsed == 0  -> broken input. UNDETERMINED.
///   prefixes == 0              -> genuinely no entries. A real, clean answer.
///
/// The second case is not hypothetical and an earlier, cruder rule ("any
/// non-blank content with zero parsed entries is undetermined") got it wrong:
/// a closed board holding only its `# Closed issues` title is 17 bytes of real
/// content and zero entries, which is exactly correct for an early revision.
/// That rule made every scenario in the e2e suite undetermined and was caught
/// by those tests rather than in review.
Map<int, String>? _parseStrict(String? source, String label) {
  if (source == null) return null;
  final parsed = parseBoard(source);
  if (parsed.isNotEmpty) return parsed;
  final prefixes = countHeadingPrefixes(source);
  if (prefixes > 0) {
    stderr.writeln('[check_oi_numbering_unique] $label: '
        '$prefixes `## OI-N` heading(s) present but ZERO parsed with the '
        'full `## OI-N — title` pattern. The separator is an em-dash (U+2014); '
        'a mis-decoded or hand-edited board looks exactly like this. '
        'Treating as UNDETERMINED, never as clean.');
    return null;
  }
  return <int, String>{};
}

void _warnPass(String why) {
  stderr.writeln('[check_oi_numbering_unique] UNDETERMINED (passing): $why');
  stderr.writeln('  This gate fails OPEN by design -- an offline commit or an '
      'unfetched origin/main must never wedge a commit. CI re-runs it against '
      'a current origin/main.');
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');

  final root = _run('git', ['rev-parse', '--show-toplevel'])?.trim();
  if (root == null || root.isEmpty) {
    _warnPass('not a git repository (or git unavailable).');
    exit(0);
  }
  Directory.current = root;

  // ---- The two boards as they stand right now -------------------------------
  // Working tree, not the index. At pre-commit the working tree is what is
  // about to be committed; at CI it IS the checkout; and build_oi_index.dart
  // (the sibling gate) reads the working tree too, so the two agree on input.
  final openFile = File(_openBoard);
  if (!openFile.existsSync()) {
    _warnPass('$_openBoard not found.');
    exit(0);
  }
  final headOpen = parseBoard(openFile.readAsStringSync());
  final closedFile = File(_closedBoard);
  final headClosed =
      closedFile.existsSync() ? parseBoard(closedFile.readAsStringSync()) : <int, String>{};

  final failures = <String>[];
  // Set when any input could not be determined. A gate that warns UNDETERMINED
  // and then prints "PASS: no collisions" has told the reader two different
  // things and the reassuring one is the lie -- it did not check. Tracked so
  // the final verdict can say SKIPPED instead.
  var undetermined = false;

  // ---- Check A: one number on BOTH boards ----------------------------------
  final dupes = crossFileDuplicates(headOpen, headClosed);
  for (final d in dupes) {
    failures.add('${d.id} appears on BOTH boards at once.\n'
        '    $_openBoard   : ${d.openTitle}\n'
        '    $_closedBoard : ${d.closedTitle}\n'
        '    An issue is open or closed, never both. One of these is a stray '
        'copy -- delete it, do not renumber it.');
  }

  // ---- Check B: cross-branch collision --------------------------------------
  // Resolve the mainline ref. origin/main is the contract; a repo without it
  // (fresh clone mid-fetch, a detached CI checkout) is UNDETERMINED, not clean.
  final mainlineRev =
      _run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/main'])
          ?.trim();

  if (mainlineRev == null || mainlineRev.isEmpty) {
    if (failures.isEmpty) {
      _warnPass('no refs/remotes/origin/main -- cannot compare against '
          'mainline. Check A (both-boards) still ran and found nothing.');
      exit(0);
    }
  } else {
    final baseRev = _run('git', ['merge-base', 'HEAD', 'origin/main'])?.trim();
    if (baseRev == null || baseRev.isEmpty) {
      undetermined = true;
      _warnPass('no merge-base between HEAD and origin/main (unrelated '
          'histories, or a shallow clone). Collision check skipped.');
    } else {
      final mainOpen =
          _parseStrict(_showAtRev('origin/main', _openBoard), 'origin/main open board');
      final mainClosed = _parseStrict(
          _showAtRev('origin/main', _closedBoard) ?? '', 'origin/main closed board');
      final baseOpen =
          _parseStrict(_showAtRev(baseRev, _openBoard) ?? '', 'merge-base open board');
      final baseClosed =
          _parseStrict(_showAtRev(baseRev, _closedBoard) ?? '', 'merge-base closed board');

      if (mainOpen == null || mainClosed == null || baseOpen == null || baseClosed == null) {
        undetermined = true;
        // At least one input could not be read or could not be parsed. Compare
        // nothing rather than compare against a board we know is wrong -- an
        // empty mainline makes EVERY number look uncontested.
        _warnPass('one or more boards at origin/main / merge-base were '
            'unreadable or unparseable (detail above). Collision check skipped.');
      } else {
        final collisions = findCollisions(
          base: mergeBoards(baseOpen, baseClosed),
          head: mergeBoards(headOpen, headClosed),
          mainline: mergeBoards(mainOpen, mainClosed),
        );

        if (collisions.isNotEmpty) {
          final next = nextFreeNumber([
            mergeBoards(headOpen, headClosed),
            mergeBoards(mainOpen, mainClosed),
          ]);
          for (final c in collisions) {
            failures.add('${c.id} names two different issues.\n$c\n'
                '    This branch minted ${c.id} against a base that did not '
                'have it, and origin/main minted it independently.\n'
                '    FIX: renumber THIS branch\'s entry (origin/main is '
                'published; its number is fixed). Next free is OI-$next.\n'
                '    Add a provenance bullet to the renumbered entry -- any '
                'already-pushed commit message still cites the old number and '
                'is not rewritten. Precedent: commit 0cb4120a.');
          }
        }
      }
    }
  }

  if (failures.isEmpty) {
    if (undetermined) {
      // Deliberately NOT the word PASS. The collision check did not run, and
      // saying "no collisions" about a comparison that never happened is the
      // exact shape of the bug this gate exists to catch.
      stdout.writeln('[check_oi_numbering_unique] SKIPPED: '
          '${headOpen.length} entries in open_issues.md + '
          '${headClosed.length} in closed_issues.md; '
          'no cross-board duplicates. Cross-branch collision check did NOT '
          'run (see UNDETERMINED above) -- CI re-runs it against a current '
          'origin/main.');
      exit(0);
    }
    // Says "entries in <file>", never "open" / "closed". These are SECTION
    // counts in each board FILE, not status tallies: open_issues.md holds 77
    // sections of which only 59 carry Status OPEN/IN_PROGRESS, so "77 open"
    // would contradict build_oi_index.dart's own "58 open issues indexed" and
    // send someone hunting a phantom discrepancy. The number space this gate
    // guards is the union of BOTH files regardless of status, which is exactly
    // why it counts sections.
    stdout.writeln('[check_oi_numbering_unique] PASS: '
        '${headOpen.length} entries in open_issues.md + '
        '${headClosed.length} in closed_issues.md (section counts, not status '
        'tallies — one number space), no cross-board duplicates, no '
        'cross-branch collisions.');
    exit(0);
  }

  stderr.writeln('[check_oi_numbering_unique] FAIL: '
      '${failures.length} numbering problem(s).');
  stderr.writeln('');
  for (final f in failures) {
    stderr.writeln('  - $f');
    stderr.writeln('');
  }
  stderr.writeln('Why this matters: an OI number is a permanent identifier '
      'cited from diagnose-docs and commit messages '
      '(docs/audit/open_issues.md:8-10). Two issues under one number breaks '
      'every citation in both directions.');
  exit(warnOnly ? 0 : 1);
}
