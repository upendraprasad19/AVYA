// scripts/gate_scripts_wired_lib.dart
//
// Pure parsing logic extracted from check_gate_scripts_wired.dart (Gate 33)
// so it can be imported by both the gate itself and its regression test —
// a single definition instead of two independently-maintained copies that
// can silently drift, which is the exact root-cause shape d7a3f9 fixed one
// level up (test.yml's case-skip list vs pre-commit.sh's). Round-1 review of
// that fix flagged the new test for repeating the pattern it was written to
// guard against.
//
// Deliberately NOT named check_gate_scripts_wired_lib.dart: Gate 33 itself
// scans every scripts/check_*.dart file as a gate script the dynamic
// pre-commit.sh / test.yml loops must invoke. A check_*-prefixed library
// file with no main() would match that glob, get bare-invoked by both
// loops, and crash with "Invoked Dart programs must have a 'main' function
// defined" — the same failure mode this file exists to prevent, one file
// over. Confirmed live: naming it with the check_ prefix during this fix's
// own development pushed Gate 33's count from 91 to 92 and reproduced the
// crash on `dart run`. Matches the existing convention of every OTHER pure
// script library in this repo (bug_index_lib.dart, worktree_guard_lib.dart,
// git_safety_lib.dart, plan_review_record_lib.dart) — none carry a
// gate-triggering prefix.

/// Matches a `check_<name>.dart` script filename inside a shell case block.
final caseSkipRegex = RegExp(r'check_[a-z0-9_]+\.dart');

/// Return script filenames that appear inside the PATTERN-LIST portion of a
/// shell `case "$NAME" in ... esac` block's arms (the `name|\` lines up to
/// and including the one closing with `)`) — these are intentionally skipped
/// by the dynamic `for GATE in scripts/check_*.dart` loop (present in both
/// scripts/pre-commit.sh and .github/workflows/test.yml).
///
/// Deliberately does NOT scan a matched arm's COMMAND BODY (the lines
/// between its closing `)` and its `;;`) — B-pass review of d7a3f9 found
/// that scanning the whole arm let an explanatory comment restating a script
/// name (e.g. "# check_closes_oi_cited.dart: a commit-msg gate...") register
/// as a case-skip even with no real pattern for it. That is silent, not
/// fail-closed: `check_gate_scripts_wired.dart`'s wiring check for THAT
/// script never used the false positive on its own (a separate, real mention
/// elsewhere in the same file happened to also satisfy it), but this
/// function's own regression test uses the false positive directly — a
/// future edit removing a real case pattern while leaving its explanatory
/// comment behind would make the test wrongly keep passing.
Set<String> extractCaseSkips(String content, RegExp pattern) {
  final skips = <String>{};
  final lines = content.split('\n');
  var inCase = false;
  var inPatternList = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('case ') && trimmed.contains(' in')) {
      inCase = true;
      inPatternList = true;
      continue;
    }
    if (inCase && trimmed == 'esac') {
      inCase = false;
      inPatternList = false;
      continue;
    }
    if (!inCase) continue;
    if (inPatternList) {
      for (final m in pattern.allMatches(line)) {
        skips.add(m.group(0)!);
      }
      if (line.contains(')')) {
        inPatternList = false; // the closing paren ends this arm's pattern list
      }
      continue;
    }
    // Inside an arm's command body — do not scan for names here. `;;` ends
    // the arm and opens the next one's pattern list (or is immediately
    // followed by `esac` when there is only one arm, as in every case block
    // in this repo today).
    if (trimmed == ';;') {
      inPatternList = true;
    }
  }
  return skips;
}
