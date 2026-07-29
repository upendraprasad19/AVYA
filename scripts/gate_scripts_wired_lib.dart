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

/// Return script filenames that appear inside a shell `case "$NAME" in` block
/// — these are intentionally skipped by the dynamic `for GATE in
/// scripts/check_*.dart` loop (present in both scripts/pre-commit.sh and
/// .github/workflows/test.yml).
Set<String> extractCaseSkips(String content, RegExp pattern) {
  final skips = <String>{};
  final lines = content.split('\n');
  var inCase = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('case ') && trimmed.contains(' in')) {
      inCase = true;
      continue;
    }
    if (inCase && trimmed == 'esac') {
      inCase = false;
      continue;
    }
    if (!inCase) continue;
    for (final m in pattern.allMatches(line)) {
      skips.add(m.group(0)!);
    }
  }
  return skips;
}
