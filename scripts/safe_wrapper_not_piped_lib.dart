// scripts/safe_wrapper_not_piped_lib.dart
//
// Pure logic for check_safe_wrapper_not_piped.dart.
//
// Bug class: CLAUDE.md §4.9 pitfalls table (already a documented RULE with
// zero enforcement until this gate): `safe_push.sh`/`safe_commit.sh` print a
// temp log to stdout then DELETE it. Piping either through `head`/`tail`
// truncates the only copy of the diagnostic. Confirmed: this repo's own
// memory records a real 5-minute push cycle lost to exactly this.

/// True iff [addedLine] mentions `safe_push.sh` or `safe_commit.sh` and is
/// LATER on the same line piped into `head` or `tail` (whole-word match, so
/// `tailwind.config.js` or `header.dart` don't false-positive).
bool isPipedThroughHeadOrTail(String addedLine) {
  final wrapperMatch =
      RegExp(r'safe_(?:push|commit)\.sh\b').firstMatch(addedLine);
  if (wrapperMatch == null) return false;

  final afterWrapper = addedLine.substring(wrapperMatch.end);
  return RegExp(r'\|\s*(head|tail)\b').hasMatch(afterWrapper);
}
