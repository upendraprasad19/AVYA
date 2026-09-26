// scripts/oi_closure_lib.dart
//
// Pure decision logic for check_closes_oi_performed.dart — the MIRROR of
// check_closes_oi_cited.dart. Split out so the predicate is unit-testable
// without a real repo, matching every other gate's `_lib.dart` companion.
// Named WITHOUT the `check_` prefix deliberately: pre-commit.sh and test.yml
// both glob `scripts/check_*.dart` and `dart run` each match with no
// arguments, so a `check_`-prefixed file with no `main()` would be swept into
// that loop and fail as a bogus gate.
//
// WHY A MIRROR EXISTS AT ALL.
//
// check_closes_oi_cited.dart enforces ONE direction:
//
//     status moved OPEN -> CLOSED  ==>  the message must cite `closes-oi:`
//
// and it opens with `if (nothing staged for the board) exit(0)`. That guard is
// correct for what it does and it is also the whole hole: a commit that CITES
// a close it never performed touches no board file, so the gate never looks.
// Declaring a close and not doing it was structurally invisible.
//
// Measured on real history 2026-08-30, not hypothesised. Of 65 OIs some commit
// declared closed via `closes-oi:`, TWO were still OPEN on the board, and they
// are the two opposite failures of the same unverified citation:
//
//   * OI-150 — cited by c2534257 and NOT PERFORMED. The fix shipped, merged,
//     went green on all 7 CI jobs; the board write was simply never done, and
//     an agent then asserted "OI-150 closed" in a compaction summary on the
//     strength of the merge. Founder caught it, 0 automation did.
//   * OI-58  — cited by bd91c6eb and NOT WARRANTED. Here the BOARD is right:
//     that enforcement was built twice, failed review twice, and was split out
//     (`Verified: never`). The commit's claim was the wrong half. It has been
//     wrong for 33 days.
//
// This gate closes both, because both reduce to the same assertion: **if a
// commit says it closed OI-NN, the board must agree.** For OI-150 that forces
// the board write; for OI-58 it forces the author to either finish the work or
// drop the claim. Both are correct outcomes.
//
// WHY NOT AT commit-msg, WHERE ITS SIBLING LIVES. A batch legitimately fixes in
// one commit and closes the board in the next — the fix commit carries the
// citation while the board still reads OPEN, and a commit-msg check would
// reject a workflow this repo actively recommends (§4.3: batch commits, push
// once). Only the merge sees the branch whole. That is the same reasoning
// check_plan_review_record_exists.dart records for its own placement, and
// CLAUDE.md §4.12.3 calls the merge "the only structurally-gateable point".

import 'check_closes_oi_cited.dart' show citedOis, parseBoardStatuses;

/// Every `closes-oi: OI-NN` across the commit messages in [messages].
///
/// Takes a LIST rather than one blob so a caller cannot accidentally join
/// messages in a way that splices two lines into a false citation. Reuses the
/// sibling gate's parser rather than restating the regex: two copies of a
/// citation pattern that must agree is the drift class this repo tracks, and
/// the sibling's copy is the one with the tests behind it.
Set<String> citationsAcross(Iterable<String> messages) {
  final out = <String>{};
  for (final m in messages) {
    out.addAll(citedOis(m));
  }
  return out;
}

/// Both board files parsed into one `{OI-NN -> STATUS}` map.
///
/// OPEN WINS ON CONFLICT, and that is deliberate. An OI present in both files
/// is a corrupt board — `check_oi_numbering_unique.dart` already owns detecting
/// that, so this gate does not need to re-report it. What this gate must not do
/// is let a stale `closed_issues.md` entry vouch for a ticket that is still
/// sitting on the open board: taking OPEN as authoritative errs toward
/// flagging, which is the safe direction for a discipline gate.
Map<String, String> mergedBoardStatuses({
  required String openContent,
  required String closedContent,
}) {
  final out = <String, String>{}
    ..addAll(parseBoardStatuses(closedContent))
    ..addAll(parseBoardStatuses(openContent));
  return out;
}

/// The verdict for one merge.
///
/// Two DISTINCT failure lists, never collapsed into one. `unperformed` means
/// the board knows this OI and does not agree it is closed — the OI-150 shape,
/// and the fix is a board write. `unknown` means neither board mentions it at
/// all — a dangling citation, usually a typo or a number that was renumbered
/// out from under the message, and the fix is different. Reporting them
/// together would send the reader looking for the wrong thing.
typedef ClosureVerdict = ({List<String> unperformed, List<String> unknown});

/// Which of [cited] the board does not agree are closed.
///
/// Returns sorted lists so the failure message is stable across runs — an
/// unordered gate message diffs noisily and trains readers to skim it.
ClosureVerdict unsatisfiedCitations(
  Set<String> cited,
  Map<String, String> statuses,
) {
  final unperformed = <String>[];
  final unknown = <String>[];
  for (final oi in cited) {
    final status = statuses[oi];
    if (status == null) {
      unknown.add(oi);
    } else if (status != 'CLOSED') {
      unperformed.add(oi);
    }
  }
  unperformed.sort();
  unknown.sort();
  return (unperformed: unperformed, unknown: unknown);
}
