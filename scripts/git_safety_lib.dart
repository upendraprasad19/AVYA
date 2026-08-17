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

/// Statements that a shell would REALLY execute: separators inside quotes or a
/// heredoc body are not separators at all.
///
/// WHY THIS EXISTS SEPARATELY FROM [splitStatements].
/// [splitStatements] splits on every `\n`, which is right for the DENY
/// detectors -- over-splitting there can only ever produce an extra BLOCK, and
/// a spurious block is loud and recoverable. It is catastrophically wrong for
/// the ALLOW path: review round 2 (2026-08-17) showed that a line INSIDE a
/// multi-line commit message or a heredoc body was treated as its own
/// statement, so a message merely DESCRIBING the escape hatch granted it.
/// Verified against the real hook -- these were BLOCKED before this batch and
/// ALLOWED after the round-1 fix:
///
///     git commit --no-verify -F - <<'EOF'
///     FOUNDER_APPROVED_NO_VERIFY=1 git commit was discussed
///     EOF
///
///     git commit -m "fix: thing
///
///     ALLOW_RAW_GIT=1 git commit is the hatch"
///
/// The first disarms the hook entirely. And multi-line messages are this repo's
/// ONLY commit convention, so this is not an exotic shape -- writing a commit
/// message that explains the hatch policy would have unlocked it.
///
/// Round 1 fixed WHERE in a statement the assignment may sit; it did not
/// question whether the "statement" was executable text at all. Both are needed.
///
/// Deliberately NOT a general shell parser. It tracks single quotes, double
/// quotes, backslash escapes and heredoc bodies -- the constructs that actually
/// carry prose in this repo's commands. Anything it cannot classify stays a
/// separator, so an unparseable command yields MORE statements, never fewer:
/// the failure direction is toward the deny path.
List<String> splitExecutableStatements(String command) {
  final out = <String>[];
  final buf = StringBuffer();

  var inSingle = false;
  var inDouble = false;
  String? heredocDelim;
  var inHeredocBody = false;

  var i = 0;
  while (i < command.length) {
    final c = command[i];

    // Inside a heredoc body nothing is a separator until the delimiter line.
    if (inHeredocBody) {
      final lineEnd = command.indexOf('\n', i);
      final line = (lineEnd == -1 ? command.substring(i) : command.substring(i, lineEnd));
      if (line.trim() == heredocDelim) {
        inHeredocBody = false;
        heredocDelim = null;
      }
      if (lineEnd == -1) break;
      i = lineEnd + 1;
      continue;
    }

    if (c == r'\' && !inSingle && i + 1 < command.length) {
      buf.write(c);
      buf.write(command[i + 1]);
      i += 2;
      continue;
    }
    if (c == "'" && !inDouble) {
      inSingle = !inSingle;
      buf.write(c);
      i++;
      continue;
    }
    if (c == '"' && !inSingle) {
      inDouble = !inDouble;
      buf.write(c);
      i++;
      continue;
    }

    if (!inSingle && !inDouble) {
      // Heredoc introducer: << or <<- , optional quote, then the delimiter word.
      final hd = RegExp(r'^<<-?\s*(["\x27]?)([A-Za-z_][A-Za-z0-9_]*)\1')
          .firstMatch(command.substring(i));
      if (hd != null) {
        heredocDelim = hd.group(2);
        buf.write(command.substring(i, i + hd.end));
        i += hd.end;
        // The body starts after the current line ends.
        final lineEnd = command.indexOf('\n', i);
        if (lineEnd == -1) break;
        buf.write(command.substring(i, lineEnd));
        out.add(buf.toString());
        buf.clear();
        inHeredocBody = true;
        i = lineEnd + 1;
        continue;
      }

      final sep = RegExp(r'^(\r?\n|;|&&|\|\|?)').firstMatch(command.substring(i));
      if (sep != null) {
        out.add(buf.toString());
        buf.clear();
        i += sep.end;
        continue;
      }
    }

    buf.write(c);
    i++;
  }
  out.add(buf.toString());
  return out;
}

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
///
/// POSITION IS LOAD-BEARING, and this return value is an ALLOW.
/// The first version of this function matched `(?:^|\s)NAME=...` ANYWHERE in a
/// statement. Review round 1 (2026-08-17) demonstrated, against the real hook,
/// that this disarmed the guard outright -- merely NAMING the variable was
/// enough, and the worst shape put it in a shell COMMENT:
///
///     git push --no-verify origin main # FOUNDER_APPROVED_NO_VERIFY=1 pending
///     git commit -m "noted ALLOW_RAW_GIT=1 in docs"
///     echo "try ALLOW_RAW_GIT=1 next time"; git commit -m x
///
/// All three were BLOCKED before this batch and ALLOWED after it -- a security
/// control turned off by a change that claimed to strengthen it. The first is
/// the whole hook disarmed: `--no-verify` matches, the hatch reads "approved",
/// and the raw-push check below never runs.
///
/// This is EXACTLY the class [commandUsesWrapper] documents twenty lines down
/// ("merely NAMING the wrapper anywhere disarmed the guard") and had already
/// fixed. The lesson was applied to one detector and not to its neighbour in
/// the same commit -- `feedback_mistake_guard_without_its_mirror`, the repo's
/// most-recurrent class. Both detectors now require an INVOCATION, not a
/// mention, and both carry a mention-does-not-count test.
///
/// So the assignment must (a) sit in the LEADING prefix chain of a statement --
/// the only position where a real shell would apply it to the command's
/// environment -- and (b) that same statement must actually invoke `git`. A
/// prefix on some OTHER statement (`ALLOW_RAW_GIT=1 echo hi; git commit`) does
/// not reach git in a real shell either, so honouring it would be wrong on the
/// shell's own terms, not merely unsafe.
String? inlineEnvAssignment(String command, String name) {
  // splitExecutableStatements, NOT splitStatements: the ALLOW path must only
  // consider text a shell would actually run. See that function's header for
  // the multi-line-message and heredoc bypasses this closes.
  for (final raw in splitExecutableStatements(command)) {
    final v = _leadingAssignmentIfGitStatement(raw, name);
    if (v != null) return v;
  }
  return null;
}

/// Walks the leading prefix chain of one statement exactly as
/// [stripCommandPrefixes] does, returning [name]'s value if it is assigned
/// there AND the statement's real command word is `git`.
///
/// Kept as its own function so the chain-walk stays byte-identical in shape to
/// [stripCommandPrefixes]; if the two ever drift on what counts as a prefix,
/// the hatch would apply in positions the strip does not recognise (or vice
/// versa), which is how the original hole opened.
String? _leadingAssignmentIfGitStatement(String statement, String name) {
  var s = statement.trim();
  String? found;

  // Same alternation as stripCommandPrefixes, but with the assignment arm
  // captured so its NAME and VALUE can be read as the chain is consumed.
  final prefix = RegExp(
    r'^(?:(\\)'
    r'|(?:command|builtin)\s+'
    r'|env(?:\s+-i)?\s+'
    r'|([A-Za-z_][A-Za-z0-9_]*)=("[^"]*"|' "'[^']*'" r'|\S*)\s+'
    r')',
  );

  for (var i = 0; i < 16; i++) {
    final m = prefix.firstMatch(s);
    if (m == null) break;
    final varName = m.group(2);
    if (varName == name) {
      var v = m.group(3) ?? '';
      if (v.length >= 2 &&
          ((v.startsWith('"') && v.endsWith('"')) ||
              (v.startsWith("'") && v.endsWith("'")))) {
        v = v.substring(1, v.length - 1);
      }
      found = v;
    }
    s = s.substring(m.end).trimLeft();
  }

  if (found == null) return null;
  // (b) the statement carrying the hatch must be the git invocation itself.
  if (!RegExp(r'^git(\s|$)').hasMatch(s)) return null;
  return found;
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
