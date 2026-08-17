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

/// Splits a shell command into statements on every separator Claude commonly
/// emits. Shared so the git-subcommand and wrapper detectors cannot drift apart
/// on what a "statement" is.
List<String> splitStatements(String command) =>
    command.split(RegExp(r'\r?\n|;|&&|\|\|?'));

/// Strips shell noise that sits BEFORE the real command word: leading
/// `VAR=value` assignments, `env [-i] [VAR=val ...]`, `command` / `builtin`,
/// and a leading backslash (the standard alias-suppression form).
///
/// WHY THIS EXISTS -- it closes a bypass that made the whole hook optional.
/// `commandInvokesGitSubcommand` anchored its pattern at `^git`, so ANY prefix
/// defeated it: `FOO=1 git commit -m x` did not match, no deny fired, and the
/// raw commit ran. The documented escape hatch `ALLOW_RAW_GIT=1 git commit`
/// therefore never worked the way it reads either -- it "worked" because the
/// hook could not SEE the command, not because it checked the variable. That
/// made the hatch indistinguishable from an accidental bypass, and any
/// env-prefixed raw git command silently skipped the guard.
///
/// Deliberately NOT stripped: `sudo`, `nohup`, `xargs`, `time`. Those change
/// what is really being run, and over-stripping risks a false BLOCK on
/// legitimate work — the one failure mode this hook must never have.
String stripCommandPrefixes(String statement) {
  var s = statement.trim();
  final prefix = RegExp(
    r'^(\\'
    r'|(?:command|builtin)\s+'
    r'|env(?:\s+-i)?\s+'
    r'|[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|' "'[^']*'" r'|\S*)\s+'
    r')',
  );
  // Loop: several prefixes can stack (`env FOO=1 BAR=2 command git ...`).
  // Bounded so a pathological input cannot spin.
  for (var i = 0; i < 16; i++) {
    final m = prefix.firstMatch(s);
    if (m == null) break;
    s = s.substring(m.end).trimLeft();
  }
  return s;
}

/// True if [command] contains, as its own statement (split on newline, `;`,
/// `&&`, `||`, `|`), an invocation of `git [flags...] <subcommand>` --
/// tolerating a few common global flags between `git` and the subcommand
/// (`-C <dir>`, `--no-pager`, `-c key=val`) and any leading env/prefix noise
/// (see [stripCommandPrefixes]).
bool commandInvokesGitSubcommand(String command, String subcommand) {
  final pattern = RegExp(
    r'^git(\s+(-C\s*\S+|--no-pager|-c\s*\S+))*\s+' + subcommand + r'\b',
  );
  for (final raw in splitStatements(command)) {
    if (pattern.hasMatch(stripCommandPrefixes(raw))) return true;
  }
  return false;
}

/// True if [command] contains a literal `--no-verify` flag anywhere.
/// Deliberately broad (over-matching just requires an explicit founder-
/// approved override; it never silently allows a bypass).
bool commandHasNoVerifyFlag(String command) =>
    RegExp(r'--no-verify\b').hasMatch(command);

/// Value of an inline `NAME=value` assignment prefixed to any statement in
/// [command], or null when absent.
///
/// WHY THE HOOK MUST READ THIS AND NOT ONLY `Platform.environment`.
/// Both documented hatches are written as inline prefixes --
/// `ALLOW_RAW_GIT=1 git push`, `FOUNDER_APPROVED_NO_VERIFY=1 git commit
/// --no-verify` (CLAUDE.md §4.3, and the hook's own deny messages). An inline
/// prefix applies to the PENDING command's environment; it is not in the
/// environment of the hook process that inspects it. So the hook's
/// `env['...'] == '1'` checks could never see either one.
///
/// That left the two hatches in opposite broken states, and neither behaved as
/// written: ALLOW_RAW_GIT appeared to work, but only because `^git` anchoring
/// meant the prefixed command was never detected at all -- fixing that anchor
/// (see [stripCommandPrefixes]) would have turned a hatch that "worked" into
/// one that could not be used. FOUNDER_APPROVED_NO_VERIFY was already
/// unusable: `--no-verify` matching is unanchored, so the deny fired regardless
/// of the prefix.
///
/// Reading the assignment off the command makes the documented incantation the
/// real mechanism. The actual control on `--no-verify` is unchanged and is not
/// mechanical: CLAUDE.md §4.3 requires founder approval in chat FIRST. This is
/// the same trust model as `ALLOW_MAIN_COMMIT=1` and rule 21's `presence_only:`
/// -- self-attested, and read by review.
String? inlineEnvAssignment(String command, String name) {
  final n = RegExp.escape(name);
  final re = RegExp('(?:^|\\s)$n=("[^"]*"|\'[^\']*\'|\\S*)');
  for (final raw in splitStatements(command)) {
    final m = re.firstMatch(raw.trim());
    if (m == null) continue;
    var v = m.group(1) ?? '';
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }
  return null;
}

/// True if [command] actually INVOKES the given wrapper script as one of its
/// statements, i.e. routes through the sanctioned safe_commit.sh /
/// safe_push.sh path.
///
/// This return value is an ALLOW: it is what tells the hook "the raw git in
/// this command is fine, it went through the wrapper". So a false positive here
/// is a silent bypass, and a false negative is a ship-stop. It used to be a
/// bare `command.contains(basename)`, which meant merely NAMING the wrapper
/// anywhere disarmed the guard:
///     echo "remember to use safe_commit.sh" && git commit -m x
/// passed cleanly. Now the wrapper must appear as the command word of a
/// statement, so a mention inside an `echo`, a comment, or a commit message no
/// longer counts.
///
/// Accepts every real invocation form in the repo and its docs:
///   sh scripts/safe_commit.sh "msg"      bash scripts/safe_push.sh
///   sh "$REPO_ROOT/scripts/safe_commit.sh"   ./scripts/safe_push.sh
///   scripts/safe_commit.sh "msg"         FOO=1 sh scripts/safe_push.sh
bool commandUsesWrapper(String command, String wrapperBasename) {
  final escaped = RegExp.escape(wrapperBasename);
  // Optional interpreter, then an optionally-quoted path ending in the wrapper.
  final pattern = RegExp('^(?:(?:sh|bash|zsh|source|\\.)\\s+)?'
      '["\']?[^"\'\\s;&|]*$escaped\\b');
  for (final raw in splitStatements(command)) {
    if (pattern.hasMatch(stripCommandPrefixes(raw))) return true;
  }
  return false;
}

/// True if [command], considered as a whole, looks push-shaped -- either a
/// raw `git push` statement or an invocation of the safe_push.sh wrapper.
/// Used to decide whether the local plan-review-record precheck should run.
bool commandIsPushShaped(String command) =>
    commandInvokesGitSubcommand(command, 'push') ||
    commandUsesWrapper(command, 'safe_push.sh');
