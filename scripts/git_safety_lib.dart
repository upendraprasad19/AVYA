// scripts/git_safety_lib.dart
//
// Pure, git-free detection logic for scripts/git_safety_hook.dart, split out
// so it's unit-testable (mirrors scripts/worktree_guard_lib.dart's split from
// check_commit_from_worktree.dart). Review round 1 (discipline-overhead
// batch, 2026-07-19) caught a regression here: the original single-anchored
// regex silently failed to match a `git commit`/`git push` on any line after
// the first in a multi-line Bash command -- the DOMINANT shape Claude
// actually emits -- because `^` without MULTILINE only anchors the whole
// string, not each line. Fixed by splitting the command into statements on
// every separator Claude commonly emits (newline, `;`, `&&`, `||`, `|`) and
// testing each statement independently.

/// True if [command] contains, as its own statement (split on newline, `;`,
/// `&&`, `||`, `|`), an invocation of `git [flags...] <subcommand>` --
/// tolerating a few common global flags between `git` and the subcommand
/// (`-C <dir>`, `--no-pager`, `-c key=val`).
bool commandInvokesGitSubcommand(String command, String subcommand) {
  final statements = command.split(RegExp(r'\r?\n|;|&&|\|\|?'));
  final pattern = RegExp(
    r'^git(\s+(-C\s*\S+|--no-pager|-c\s*\S+))*\s+' + subcommand + r'\b',
  );
  for (final raw in statements) {
    if (pattern.hasMatch(raw.trim())) return true;
  }
  return false;
}

/// True if [command] contains a literal `--no-verify` flag anywhere.
/// Deliberately broad (over-matching just requires an explicit founder-
/// approved override; it never silently allows a bypass).
bool commandHasNoVerifyFlag(String command) =>
    RegExp(r'--no-verify\b').hasMatch(command);

/// True if [command] mentions the given wrapper script's basename, i.e. the
/// command routes through the sanctioned safe_commit.sh / safe_push.sh path.
bool commandUsesWrapper(String command, String wrapperBasename) =>
    command.contains(wrapperBasename);

/// True if [command], considered as a whole, looks push-shaped -- either a
/// raw `git push` statement or an invocation of the safe_push.sh wrapper.
/// Used to decide whether the local plan-review-record precheck should run.
bool commandIsPushShaped(String command) =>
    commandInvokesGitSubcommand(command, 'push') ||
    commandUsesWrapper(command, 'safe_push.sh');
