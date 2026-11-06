// scripts/worktree_config_integrity_lib.dart
//
// Pure decision logic for the shared-config `core.worktree` integrity gate
// (scripts/check_worktree_config_integrity.dart). Kept separate + git-free so
// every branch is testable deterministically without a git fixture. Named
// WITHOUT the `check_` prefix so the pre-commit `check_*.dart` gate loop (and
// Gate 33) treat only the gate itself as a gate, not this lib — same convention
// as worktree_guard_lib.dart.
//
// WHY THIS EXISTS (live incident 2026-08-09):
// `.git/config` — the config SHARED by every linked worktree — carried
//     [core] worktree = .../.claude/worktrees/post38-auth-fixes
// so `git rev-parse --show-toplevel` returned post38-auth-fixes' path from
// EVERY worktree and from the shared main folder. Every git command in the repo
// (102 worktrees) resolved against one branch's files. A `git add` from any
// other worktree would have staged post38's content into its own index.
//
// This is the §4.13 cross-session mixing incident one level BELOW where
// check_commit_from_worktree.dart watches: that gate compares `--git-dir` vs
// `--git-common-dir` to classify primary-vs-linked, and passes cleanly while
// the substrate its guarantee depends on is corrupt. §4.13's claim that "a
// worktree has its OWN index, so mixing is structurally impossible" holds only
// while no `core.worktree` overrides the per-worktree resolution.
//
// ROOT CAUSE is NOT closed. scripts/new-worktree.sh is a bare
// `git worktree add` and sets no config; repo-wide the only scripts writing git
// config are setup-hooks.sh (core.sshCommand) and a comment in
// prepare-commit-msg.sh. So no IN-REPO script sets it. External tooling (IDE
// git plugins, harness worktree tooling) is NOT ruled out. The most likely
// mechanism is a `git config core.worktree <path>` run without `--worktree`
// scope, which writes the SHARED config instead of a per-worktree one.
//
// SCOPE OF THE RULE — deliberately narrow, see check header:
// "any core.worktree is a bug" is NOT true of git in general (`clone/init
// --separate-git-dir` and submodule git-dirs legitimately carry it in the
// shared config). It IS true of THIS repo's verified layout: `.git` is a real
// directory, core.bare=false, no .gitmodules, and zero `config.worktree` files
// exist across all worktrees. So: any origin at all → FAIL.

/// One parsed line of `git config --show-origin --get-all core.worktree`.
class WorktreeConfigEntry {
  /// Origin file as git reported it, normalised (forward slashes, lowercased).
  final String origin;

  /// The configured worktree path, verbatim (NOT normalised — echoed to the
  /// user so they can see exactly what is in their config).
  final String value;

  const WorktreeConfigEntry(this.origin, this.value);
}

class WorktreeConfigResult {
  /// True → the gate must FAIL (exit 1).
  final bool violation;

  /// True → something went wrong reading git itself; the caller must fail
  /// LOUDLY rather than treat it as "clean" (see exit-code note below).
  final bool indeterminate;

  final String reason;
  final List<WorktreeConfigEntry> entries;

  const WorktreeConfigResult({
    required this.violation,
    required this.indeterminate,
    required this.reason,
    this.entries = const [],
  });
}

/// Normalise a path for comparison: backslashes → forward slashes, trailing
/// slashes dropped, lowercased. Mirrors `_norm()` in
/// check_commit_from_worktree.dart:36-37.
String normPath(String p) =>
    p.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

/// Parse the raw stdout of `git config --show-origin --get-all core.worktree`.
///
/// FORMAT (verified live, 2026-08-09): each line is
///     `file:<path>` + a literal TAB + `<value>`
/// The path is RELATIVE from some working directories (`file:.git/config`)
/// and ABSOLUTE from others (`file:C:/Upendra/.../.git/config`), and shifts
/// again under the `GIT_DIR` that a git hook exports. So callers must never
/// match it with `contains()` — split on the FIRST tab only, then normalise.
///
/// A value may itself contain tabs in principle, hence `indexOf` rather than
/// `split('\t')`.
List<WorktreeConfigEntry> parseShowOrigin(String stdout) {
  final out = <WorktreeConfigEntry>[];
  for (final rawLine in stdout.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    final tab = line.indexOf('\t');
    if (tab < 0) {
      // No tab: git gave us a bare value with no origin (e.g. --get-all
      // without --show-origin). Still a configured value — record it with an
      // empty origin rather than dropping it silently.
      out.add(WorktreeConfigEntry('', line.trim()));
      continue;
    }
    var origin = line.substring(0, tab);
    final value = line.substring(tab + 1).trim();
    if (origin.startsWith('file:')) origin = origin.substring(5);
    out.add(WorktreeConfigEntry(normPath(origin), value));
  }
  return out;
}

/// Decide the gate verdict from git's exit code + stdout.
///
/// EXIT-CODE CONTRACT (verified live, 2026-08-09) — easy to get backwards:
///   0 → key present   → entries parsed → VIOLATION
///   1 → key ABSENT    → clean → PASS        (this is the healthy case!)
///   other → git could not answer → INDETERMINATE
///
/// `128` is NOT "not a repo" — B-pass corrected this. Verified: OUTSIDE any
/// repository `git config --show-origin --get-all core.worktree` still exits
/// **1**, identical to the healthy in-repo case. So exit 1 alone cannot
/// distinguish "clean repo" from "never looked at a repo", and this function
/// requires the caller to supply [inRepo] as independent evidence. A real 128
/// comes from e.g. a malformed config file (`fatal: bad config line N`).
///
/// Do NOT reuse check_commit_from_worktree.dart:29-32's `_git()` helper here:
/// it returns '' on ANY non-zero exit, which conflates "clean" (1) with "git
/// is broken". That conflation would make this gate silently pass in exactly
/// the environments where it is least able to see the truth.
WorktreeConfigResult evaluateWorktreeConfig({
  required int exitCode,
  required String stdout,
  bool inRepo = true,
}) {
  if (!inRepo) {
    // Never report health for a directory we never established is a repo.
    return const WorktreeConfigResult(
      violation: false,
      indeterminate: true,
      reason: 'not inside a git repository — no health claim can be made '
          '(git config exits 1 here exactly as it does when clean).',
    );
  }
  if (exitCode == 1) {
    return const WorktreeConfigResult(
      violation: false,
      indeterminate: false,
      reason: 'no core.worktree configured in any scope (healthy).',
    );
  }
  if (exitCode != 0) {
    return WorktreeConfigResult(
      violation: false,
      indeterminate: true,
      reason: 'git exited $exitCode — could not determine config state.',
    );
  }
  final entries = parseShowOrigin(stdout);
  if (entries.isEmpty) {
    // Exit 0 but nothing parseable: treat as indeterminate, never as clean.
    return const WorktreeConfigResult(
      violation: false,
      indeterminate: true,
      reason: 'git exited 0 but produced no parseable core.worktree entry.',
    );
  }
  return WorktreeConfigResult(
    violation: true,
    indeterminate: false,
    reason: 'core.worktree is set (${entries.length} entr'
        '${entries.length == 1 ? 'y' : 'ies'}) — every worktree in this repo '
        'will resolve against that path instead of its own.',
    entries: entries,
  );
}
