// scripts/gate_existssync_file_vs_dir_lib.dart
//
// Pure decision logic for scripts/check_gate_existssync_file_vs_dir.dart.
// Named WITHOUT the `check_` prefix so the pre-commit `check_*.dart` loop (and
// Gate 33) treat only the gate itself as a gate, not this lib — same
// convention as worktree_config_integrity_lib.dart / worktree_guard_lib.dart.
//
// WHY THIS EXISTS (feedback_mistake_guard_without_its_mirror.md instance #32,
// 2026-09-19): while drafting the OI-195 remediation spec (Gate 42's
// `behavioral_test_path:` existence check — live board status: still OPEN,
// zero live violations as of 2026-09-13), the spec itself required a bare
// `File(...).existsSync()` to check whether a cited path existed. Caught in
// review BEFORE it shipped: `File.existsSync()` answers FALSE for a
// DIRECTORY, so had that spec landed as written, a legitimate `test/sql/`-
// style directory citation would have read as "missing" even though it
// existed on disk. This gate exists so the same mistake can't recur silently
// in any future gate/validator-authoring commit.
//
// SCOPE — deliberately narrow, calibrated live against this repo
// (2026-09-19, point-in-time — re-run the grep rather than trusting this
// number, since it is self-referential: every new gate/validator file this
// class of check adds grows the count it describes):
// `grep -rn "\.existsSync(" scripts/*.dart | wc -l` returned
// **220** occurrences that day. The overwhelming majority are legitimate,
// unambiguous file checks (config files, output files, known non-directory
// paths) where directory-ambiguity cannot occur. Flagging all of them would
// be almost pure noise and would never be viable as a hard blocker. This gate
// therefore only evaluates newly-STAGED-ADDED lines, and only within
// gate/validator-AUTHORING files — the exact class where OI-195 happened:
// `scripts/check_*.dart`, `scripts/*_lib.dart`, `scripts/validate_*.dart`.
// The 220 pre-existing calls are invisible to it (not staged, not re-added)
// unless a future commit re-adds an identical line in one of those files.
//
// DEFENSE IN DEPTH: the caller (check_gate_existssync_file_vs_dir.dart) scopes
// the `git diff --cached` pathspec to the three globs above, but this pure
// function ALSO re-checks the `+++ b/<path>` header against the same pattern
// before evaluating any line under it — so a caller that forgets or loosens
// the pathspec cannot silently widen this gate's blast radius. Tested
// explicitly below (see "ignores files outside the gate-authoring pathset").
//
// ESCAPE HATCH: a trailing `// file-only:` comment on the same line documents
// a deliberate, justified file-only check — same trust model as rule 21's
// `presence_only: true` and rule 24's ledger: self-attested, read at review
// time, not mechanically verified.

// Non-greedy `.*?` — stops at the FIRST literal `).existsSync(`, so an
// argument with nested parens (e.g. `File(p.join(root, entry.path))`) still
// matches instead of failing at the argument's own inner `)`.
final _existsSyncCall = RegExp(r'\bFile\(.*?\)\.existsSync\(');
final _gateAuthoringFile =
    RegExp(r'^scripts/(check_[^/]+\.dart|[^/]+_lib\.dart|validate_[^/]+\.dart)$');

/// Scan a unified diff (from `git diff --cached --unified=0 --no-color`) for
/// newly-added lines inside gate-authoring files that call
/// `File(...).existsSync()` without a `// file-only:` justification.
///
/// Returns one human-readable `"<file>:<content>"` entry per violation.
List<String> findDirBlindExistsSyncCalls(String diffText) {
  final violations = <String>[];
  var currentFile = '';
  var inScope = false;

  for (final rawLine in diffText.split('\n')) {
    final line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;

    if (line.startsWith('+++ b/')) {
      currentFile = line.substring('+++ b/'.length).trim();
      inScope = _gateAuthoringFile.hasMatch(currentFile);
      continue;
    }
    if (!inScope) continue;
    // Added content lines start with a single '+'; skip the '+++' header.
    if (!line.startsWith('+') || line.startsWith('+++')) continue;

    final added = line.substring(1);
    if (!_existsSyncCall.hasMatch(added)) continue;
    if (added.contains('// file-only:')) continue;

    violations.add('$currentFile:  ${added.trim()}');
  }

  return violations;
}
