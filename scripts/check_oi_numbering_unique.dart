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
    // ---- Choose the THREE points from what we are actually standing on ------
    //
    // WHY THIS IS NOT SIMPLY (merge-base(HEAD, origin/main), HEAD, origin/main).
    // That triple DEGENERATES INTO A NO-OP whenever HEAD is at or ahead of
    // origin/main, because then the merge-base IS origin/main and `base` ==
    // `mainline`. Leg 1 skips every number the base has; leg 2 skips every
    // number the mainline lacks; with the two maps equal those are exhaustive,
    // so leg 3 is unreachable FOR EVERY POSSIBLE INPUT and findCollisions can
    // only ever return []. That is not a bug that shows up on odd inputs -- it
    // is structural, provable by construction.
    //
    // And "HEAD at or ahead of origin/main" is exactly the state at TWO of this
    // gate's three documented placements: the pre-merge-commit hook, and CI on
    // a push to main. So the naive triple works ONLY from a feature branch --
    // the one placement where a collision has not landed yet. Found by review
    // round 1 (2026-08-17); the gate had been shipped, ledgered and called
    // authoritative in all three positions.
    //
    // The fix is to compare THE TWO SIDES OF THE MERGE against their own
    // merge-base, which is the question actually being asked -- "did these two
    // branches each mint this number independently?" -- rather than a triple
    // that happens to be right in one context.
    String thisSideRev;   // plays "mainline": the side already published
    String otherSideRev;  // plays "head": the side that may have minted
    String? baseRev;
    String shapeNote;

    // A SHALLOW repository cannot answer this question, and must say so.
    //
    // `actions/checkout` defaults to depth 1. In a shallow clone git reports a
    // merge commit as PARENTLESS, so the merge-shape arms below never fire, the
    // branch arm compares HEAD against an origin/main that IS HEAD, and the
    // comparison degenerates — then gets reported as "PASS (vacuous) ... a
    // checked answer, not a skipped one". Review round 2 (2026-08-17)
    // reproduced it end-to-end: a merged board carrying TWO `## OI-2` headings
    // read as PASS in a `--depth 1` clone and FAIL in a full one.
    //
    // The environment fix is `fetch-depth: 0` on the audit-gates job. This is
    // the other half: even with that in place, any future shallow context must
    // degrade to UNDETERMINED rather than quietly re-acquiring the old no-op.
    // A truncated history is a statement about the INPUT; vacuity is a
    // statement about the BOARD. They must never share a word.
    // ⚠ SHALLOW IS NOT A BLANKET DISQUALIFIER, and treating it as one was the
    // first version of this fix — it disabled the check in the REAL repository.
    // This working clone reports `--is-shallow-repository: true` while still
    // resolving both parents of its merge commits perfectly well, because a
    // shallow clone is truncated at some depth, not stripped of recent history.
    // Blanket-skipping there would have traded a false PASS for a permanent
    // SKIPPED, which is the same loss of coverage wearing an honest label.
    //
    // The genuinely ambiguous combination is narrower: shallow AND we fell
    // through to the branch arm AND the comparison came out vacuous. Only then
    // is "nothing was minted on that side" indistinguishable from "the history
    // that would show the mint was truncated away". That exact combination is
    // what a `--depth 1` CI checkout produces at a merge commit, and it is
    // handled where the vacuous verdict is printed, below.
    final isShallow =
        _run('git', ['rev-parse', '--is-shallow-repository'])?.trim() == 'true';

    final mergeHead =
        _run('git', ['rev-parse', '--verify', '--quiet', 'MERGE_HEAD'])?.trim();
    final parentLine =
        _run('git', ['rev-list', '--parents', '-n', '1', 'HEAD'])?.trim();
    final parents = (parentLine == null || parentLine.isEmpty)
        ? const <String>[]
        : parentLine.split(RegExp(r'\s+'));

    // OCTOPUS MERGES: this gate compares exactly TWO sides, and says so.
    //
    // Both merge arms below are structurally blind to a 3+-parent merge, for
    // two unrelated mechanisms (B-pass 2026-08-17, P1, both reproduced):
    //   - post-merge: `parents[1]` vs `parents[2]` only; a third parent's mint
    //     is never examined;
    //   - mid-merge: `.git/MERGE_HEAD` holds ONE SHA PER LINE for an octopus,
    //     and `git rev-parse --verify --quiet MERGE_HEAD` silently resolves to
    //     the first line with exit 0 — no error to notice.
    // Verified: three branches, two of them minting OI-31 with different
    // titles in non-conflicting regions, merge cleanly and the gate printed
    // PASS while its own diagnostic line reported 32 raw headings vs 31
    // distinct.
    //
    // Reported as UNDETERMINED rather than fixed by looping the parents,
    // because a correct N-way comparison is a different predicate (every pair,
    // or mainline vs the union) and would need its own e2e coverage — whereas
    // this repo produces octopus merges NOWHERE: safe_merge.sh takes a single
    // branch. Refusing to answer is honest, matches this file's convention
    // everywhere else, and cannot be mistaken for a clean bill.
    final mergeHeadFile = File('.git/MERGE_HEAD');
    final mergeHeadLines = mergeHeadFile.existsSync()
        ? mergeHeadFile
            .readAsLinesSync()
            .where((l) => l.trim().isNotEmpty)
            .length
        : 0;
    final isOctopus = parents.length > 3 || mergeHeadLines > 1;
    if (isOctopus) {
      undetermined = true;
      _warnPass('this is an OCTOPUS merge '
          '(${parents.length > 3 ? '${parents.length - 1} parents' : '$mergeHeadLines merge heads'}). '
          'This gate compares exactly two sides, so a number minted on a third '
          'branch would not be seen. NOT reported as clean. Merge the branches '
          'one at a time (scripts/safe_merge.sh takes one branch) and the check '
          'runs normally on each.');
      // Fall through to the branch triple only so the locals are definitely
      // assigned; the comparison itself is skipped below on `isOctopus`.
      thisSideRev = 'origin/main';
      otherSideRev = 'HEAD';
      baseRev = null;
      shapeNote = 'octopus (not compared)';
    } else if (mergeHead != null && mergeHead.isNotEmpty) {
      // Mid-merge: the pre-merge-commit hook. The merge commit does not exist
      // yet, but both sides do -- HEAD is the branch being merged INTO and
      // MERGE_HEAD the branch being merged IN.
      thisSideRev = 'HEAD';
      otherSideRev = mergeHead;
      baseRev = _run('git', ['merge-base', 'HEAD', mergeHead])?.trim();
      shapeNote = 'mid-merge (HEAD vs MERGE_HEAD)';
    } else if (parents.length >= 3) {
      // HEAD is a merge commit (>=2 parents after the commit's own sha): CI on
      // a push to main, after the merge landed. Compare its parents.
      thisSideRev = parents[1];
      otherSideRev = parents[2];
      baseRev = _run('git', ['merge-base', parents[1], parents[2]])?.trim();
      shapeNote = 'merge commit (HEAD^1 vs HEAD^2)';
    } else {
      // Ordinary commit on a branch: the original triple, which is correct here
      // precisely because HEAD has diverged from origin/main.
      thisSideRev = 'origin/main';
      otherSideRev = 'HEAD';
      baseRev = _run('git', ['merge-base', 'HEAD', 'origin/main'])?.trim();
      shapeNote = 'branch (HEAD vs origin/main)';
    }

    if (isOctopus) {
      // Already reported above as UNDETERMINED. Deliberately no comparison:
      // running the two-side predicate here would produce a real-looking
      // verdict about two of the three-or-more sides.
    } else if (baseRev == null || baseRev.isEmpty) {
      undetermined = true;
      _warnPass('no merge-base for the $shapeNote comparison (unrelated '
          'histories, or a shallow clone). Collision check skipped.');
    } else {
      final mainOpen =
          _parseStrict(_showAtRev(thisSideRev, _openBoard), '$thisSideRev open board');
      final mainClosed = _parseStrict(
          _showAtRev(thisSideRev, _closedBoard) ?? '', '$thisSideRev closed board');
      final baseOpen =
          _parseStrict(_showAtRev(baseRev, _openBoard) ?? '', 'merge-base open board');
      final baseClosed =
          _parseStrict(_showAtRev(baseRev, _closedBoard) ?? '', 'merge-base closed board');

      // In the two merge shapes the "head" side is a REF, not the working tree.
      // Reading the working tree there would compare the already-merged board
      // (which holds BOTH entries) against one side, and every number would look
      // contested. Only the branch shape wants the working tree, so the mint is
      // caught before it is even committed.
      final bool useWorkingTree = otherSideRev == 'HEAD';
      final otherOpen = useWorkingTree
          ? headOpen
          : _parseStrict(_showAtRev(otherSideRev, _openBoard) ?? '',
              '$otherSideRev open board');
      final otherClosed = useWorkingTree
          ? headClosed
          : _parseStrict(_showAtRev(otherSideRev, _closedBoard) ?? '',
              '$otherSideRev closed board');

      if (mainOpen == null ||
          mainClosed == null ||
          baseOpen == null ||
          baseClosed == null ||
          otherOpen == null ||
          otherClosed == null) {
        undetermined = true;
        // At least one input could not be read or could not be parsed. Compare
        // nothing rather than compare against a board we know is wrong -- an
        // empty mainline makes EVERY number look uncontested.
        _warnPass('one or more boards for the $shapeNote comparison were '
            'unreadable or unparseable (detail above). Collision check skipped.');
      } else {
        // Guard the degeneracy explicitly rather than trusting the shape
        // selection above to have avoided it. If base and mainline hold the
        // same numbers, findCollisions is mathematically incapable of returning
        // anything, and printing PASS would assert a check that cannot fail --
        // the precise false assurance this gate exists to prevent elsewhere.
        final baseMerged = mergeBoards(baseOpen, baseClosed);
        final mainMerged = mergeBoards(mainOpen, mainClosed);
        final otherMerged = mergeBoards(otherOpen, otherClosed);

        // VACUOUS vs UNDETERMINED -- these look identical in the output of a
        // careless gate and mean opposite things.
        //
        // If the mainline side minted no number the merge-base lacked, then
        // every n in `mainline` is also in `base`, leg 1 skips it, and no
        // collision is expressible. With the shape selection above that is a
        // genuine ANSWER ("nothing was minted on that side, so nothing can
        // clash"), not a failure to look -- so it is a PASS, and calling it
        // UNDETERMINED would put the word on an ordinary merge and teach the
        // reader to skip it.
        //
        // What is NOT benign is reaching this state because the three points
        // were chosen wrongly -- which is exactly the bug review round 1 found,
        // where base was merge-base(HEAD, origin/main) while HEAD was already
        // ahead of origin/main, so base == mainline in EVERY case and the gate
        // could never fail. The shape selection above is what prevents that;
        // this branch just names the vacuous case out loud so the two can never
        // again be confused in the output.
        final mainlineMintedNothing =
            mainMerged.keys.every(baseMerged.containsKey);
        if (mainlineMintedNothing) {
          // THE ONE COMBINATION WHERE VACUOUS CANNOT BE TRUSTED.
          //
          // Shallow + the branch arm + vacuous is exactly what a `--depth 1`
          // checkout produces AT A MERGE COMMIT: git reports the merge as
          // parentless, so the merge arms never fire, HEAD and origin/main
          // resolve to the same commit, and "nothing was minted" is
          // indistinguishable from "the parents that carried the mint were
          // truncated away". Verified end-to-end: a merged board holding TWO
          // `## OI-2` headings read as PASS in a --depth 1 clone and FAIL in a
          // full one.
          //
          // Shallow ALONE is fine — this working repo is shallow and resolves
          // its merge parents correctly, taking the merge arm, where a vacuous
          // result is a real answer.
          // The condition is the CI signature, not "shallow" on its own.
          //
          // First attempt was `isShallow && branch-arm && parents.length < 3`,
          // which fires for ANY branch in a shallow clone that has merged main
          // in — i.e. the normal local state — and made the gate permanently
          // SKIPPED on this machine. That trades a false PASS for a permanent
          // blind spot: the same loss of coverage, wearing an honest label.
          //
          // What actually distinguishes the broken case is that HEAD and the
          // mainline ref are THE SAME COMMIT. That is what a `--depth 1`
          // checkout of main produces (and why the comparison degenerates), and
          // it is never true on a feature branch, however shallow the clone.
          final headRev = _run('git', ['rev-parse', 'HEAD'])?.trim();
          final untrustworthy = isShallow &&
              headRev != null &&
              headRev == mainlineRev &&
              parents.length < 3;
          if (untrustworthy) {
            undetermined = true;
            _warnPass('the $shapeNote comparison came out vacuous in a SHALLOW '
                'repository, and those two facts cannot be separated: git '
                'reports a merge commit as parentless when the history is '
                'truncated, so "nothing was minted" may simply be "the mint is '
                'not in this clone". NOT reported as clean. Fix for CI: set '
                '`fetch-depth: 0` on the checkout step.');
          } else {
            stdout.writeln('[check_oi_numbering_unique] PASS (vacuous): $shapeNote -- the '
                '$thisSideRev side minted no OI number that the merge-base '
                'lacked, so no cross-branch collision is expressible. '
                '${otherMerged.length} entries on the $otherSideRev side were '
                'read and compared; this is a checked answer, not a skipped one.');
          }
        } else {
          final collisions = findCollisions(
            base: baseMerged,
            head: otherMerged,
            mainline: mainMerged,
          );

          if (collisions.isNotEmpty) {
            final next = nextFreeNumber([otherMerged, mainMerged]);
            for (final c in collisions) {
              failures.add('${c.id} names two different issues.\n$c\n'
                  '    Comparison: $shapeNote. The $otherSideRev side minted '
                  '${c.id} against a base that did not have it, and '
                  '$thisSideRev minted it independently.\n'
                  '    FIX: renumber the $otherSideRev side\'s entry '
                  '($thisSideRev is published; its number is fixed). Next free '
                  'is OI-$next.\n'
                  '    Add a provenance bullet to the renumbered entry -- any '
                  'already-pushed commit message still cites the old number and '
                  'is not rewritten. Precedent: commit 0cb4120a.');
            }
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
    // Report DISTINCT NUMBERS and say so, plus the raw heading count when the
    // two disagree.
    //
    // This line used to claim its figures were "section counts, not status
    // tallies". They are neither: parseBoard writes `out[n] = title`, so two
    // `## OI-7` headings collapse into one entry and the count silently drops.
    // The de-duplication is invisible EXACTLY in the corrupt state this gate
    // exists to report — a board with a duplicated number reads as one entry
    // shorter, and the verdict line reassures at the same time. (On the real
    // board today the two agree, so nothing was visibly wrong; the claim was
    // still false.) Naming both numbers makes any divergence self-evident.
    final openHeadings = countHeadingPrefixes(openFile.readAsStringSync());
    final closedHeadings = closedFile.existsSync()
        ? countHeadingPrefixes(closedFile.readAsStringSync())
        : 0;
    final dedupNote =
        (openHeadings != headOpen.length || closedHeadings != headClosed.length)
            ? ' [raw `## OI-N` headings: $openHeadings open / $closedHeadings '
                'closed — higher than the distinct count means a number appears '
                'twice in one file]'
            : '';
    stdout.writeln('[check_oi_numbering_unique] PASS: '
        '${headOpen.length} distinct numbers in open_issues.md + '
        '${headClosed.length} in closed_issues.md (one number space across both '
        'files, regardless of status)$dedupNote, no cross-board duplicates, no '
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
