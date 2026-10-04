// Contract test for the git-safety PreToolUse hook's pure detection logic
// (scripts/git_safety_hook.dart via scripts/git_safety_lib.dart).
//
// Regression coverage for review round 1 (discipline-overhead batch,
// 2026-07-19, finding F2): the original single-anchored regex silently
// failed to match a `git commit`/`git push` on any line after the first in
// a multi-line Bash command — the dominant shape Claude actually emits,
// since `^` without MULTILINE only anchors the whole string. The
// 'multi-line command' group below pins that exact failure mode.

import 'package:flutter_test/flutter_test.dart';
import '../../scripts/git_safety_lib.dart';

void main() {
  group('commandInvokesGitSubcommand — single-line', () {
    test('plain raw commit is detected', () {
      expect(commandInvokesGitSubcommand('git commit -m "x"', 'commit'), isTrue);
    });
    test('plain raw push is detected', () {
      expect(commandInvokesGitSubcommand('git push origin main', 'push'), isTrue);
    });
    test('leading whitespace still detected', () {
      expect(commandInvokesGitSubcommand('  git commit -m "x"', 'commit'), isTrue);
    });
    test('git -C <dir> commit is detected', () {
      expect(
        commandInvokesGitSubcommand('git -C /repo commit -m "x"', 'commit'),
        isTrue,
      );
    });
    test('git --no-pager push is detected', () {
      expect(
        commandInvokesGitSubcommand('git --no-pager push origin main', 'push'),
        isTrue,
      );
    });
    test('unrelated command is not detected', () {
      expect(commandInvokesGitSubcommand('git status', 'commit'), isFalse);
    });
    test('a wrapper script name alone is not mistaken for the raw form', () {
      expect(
        commandInvokesGitSubcommand('sh scripts/safe_commit.sh "msg"', 'commit'),
        isFalse,
      );
    });
  });

  group('commandInvokesGitSubcommand — multi-line command (F2 regression)', () {
    test('commit on the SECOND line of a multi-line command is detected', () {
      const command = 'git add -A\ngit commit -m "x"';
      expect(commandInvokesGitSubcommand(command, 'commit'), isTrue);
    });
    test('push on the second line is detected', () {
      const command = 'git merge --no-ff feature\ngit push origin main';
      expect(commandInvokesGitSubcommand(command, 'push'), isTrue);
    });
    test('commit after a semicolon-separated statement is detected', () {
      expect(
        commandInvokesGitSubcommand('git add -A; git commit -m "x"', 'commit'),
        isTrue,
      );
    });
    test('commit after && is detected', () {
      expect(
        commandInvokesGitSubcommand('git add -A && git commit -m "x"', 'commit'),
        isTrue,
      );
    });
    test('push after a pipe-separated statement is detected', () {
      expect(
        commandInvokesGitSubcommand('echo x | git push origin main', 'push'),
        isTrue,
      );
    });
    test('three-line command with commit buried on the last line', () {
      const command = 'cd worktree\ngit add file.dart\ngit commit -m "x"';
      expect(commandInvokesGitSubcommand(command, 'commit'), isTrue);
    });
  });

  group('commandHasNoVerifyFlag', () {
    test('detects --no-verify', () {
      expect(commandHasNoVerifyFlag('git commit -m "x" --no-verify'), isTrue);
    });
    test('absent when not present', () {
      expect(commandHasNoVerifyFlag('git commit -m "x"'), isFalse);
    });
  });

  group('commandUsesWrapper', () {
    test('detects safe_commit.sh', () {
      expect(
        commandUsesWrapper('sh scripts/safe_commit.sh "x"', 'safe_commit.sh'),
        isTrue,
      );
    });
    test('detects safe_push.sh', () {
      expect(
        commandUsesWrapper('sh scripts/safe_push.sh origin main', 'safe_push.sh'),
        isTrue,
      );
    });
    test('absent for a raw command', () {
      expect(commandUsesWrapper('git commit -m "x"', 'safe_commit.sh'), isFalse);
    });
  });

  group('commandIsPushShaped', () {
    test('raw git push is push-shaped', () {
      expect(commandIsPushShaped('git push origin main'), isTrue);
    });
    test('safe_push.sh invocation is push-shaped', () {
      expect(commandIsPushShaped('sh scripts/safe_push.sh origin main'), isTrue);
    });
    test('a commit is NOT push-shaped', () {
      expect(commandIsPushShaped('git commit -m "x"'), isFalse);
    });
    test('multi-line command with push on the second line is push-shaped', () {
      expect(
        commandIsPushShaped('git merge --no-ff feature\ngit push origin main'),
        isTrue,
      );
    });
  });

  // ==========================================================================
  // 2026-08-17: the env-prefix bypass.
  //
  // `commandInvokesGitSubcommand` anchored at `^git`, so ANY prefix defeated
  // detection entirely — `FOO=1 git commit -m x` produced no match, no deny,
  // and the raw commit ran. The documented hatch `ALLOW_RAW_GIT=1 git commit`
  // appeared to work for the SAME reason, i.e. by detection miss rather than by
  // the env check the deny message advertises, so an accidental bypass and an
  // authorised one were indistinguishable.
  // ==========================================================================
  group('env-prefix bypass (2026-08-17 regression)', () {
    for (final prefixed in <String>[
      'FOO=1 git commit -m x',
      'ALLOW_RAW_GIT=1 git commit -m x',
      'GIT_AUTHOR_NAME="a b" git commit -m x',
      r"FOO='q' git commit -m x",
      'env FOO=1 git commit -m x',
      'env -i PATH=/bin git commit -m x',
      'command git commit -m x',
      'builtin git commit -m x',
      r'\git commit -m x',
      'echo start && FOO=1 git commit -m x',
      'FOO=1 BAR=2 command git commit -m x',
    ]) {
      test('detects a prefixed commit: $prefixed', () {
        expect(commandInvokesGitSubcommand(prefixed, 'commit'), isTrue);
      });
    }

    test('detects a prefixed push', () {
      expect(commandInvokesGitSubcommand('FOO=1 git push origin main', 'push'),
          isTrue);
    });

    test('does NOT strip sudo/nohup — those change what actually runs', () {
      // Over-stripping risks a false BLOCK on legitimate work, the one failure
      // mode this hook must not have. These stay undetected by design.
      expect(commandInvokesGitSubcommand('sudo git commit -m x', 'commit'),
          isFalse);
    });

    test('a bare word ending in = does not swallow the command', () {
      expect(commandInvokesGitSubcommand('git commit -m a=b', 'commit'), isTrue);
    });
  });

  group('commandUsesWrapper must require an INVOCATION, not a mention', () {
    // It used to be `command.contains(basename)`, so merely naming the wrapper
    // disarmed the guard for the whole command. This return value is an ALLOW,
    // so a false positive here is a silent bypass.
    test('a mention inside echo does not count as using the wrapper', () {
      expect(
        commandUsesWrapper(
            'echo "remember to use safe_commit.sh" && git commit -m x',
            'safe_commit.sh'),
        isFalse,
      );
    });

    test('a mention inside a commit message does not count', () {
      expect(
        commandUsesWrapper(
            'git commit -m "route through safe_commit.sh next time"',
            'safe_commit.sh'),
        isFalse,
      );
    });

    // Every real invocation form used in the repo and its docs must still pass,
    // or this becomes a ship-stop rather than a guard.
    for (final real in <String>[
      'sh scripts/safe_commit.sh "msg"',
      'bash scripts/safe_commit.sh "msg"',
      r'sh "$REPO_ROOT/scripts/safe_commit.sh" "msg"',
      './scripts/safe_commit.sh',
      'scripts/safe_commit.sh "msg"',
      'FOO=1 sh scripts/safe_commit.sh',
      'cd /repo && sh scripts/safe_commit.sh "msg"',
    ]) {
      test('still recognises a real invocation: $real', () {
        expect(commandUsesWrapper(real, 'safe_commit.sh'), isTrue);
      });
    }
  });

  group('inlineEnvAssignment', () {
    // The hatches are DOCUMENTED as inline prefixes, which never reach the hook
    // process's own environment — so reading only Platform.environment made
    // FOUNDER_APPROVED_NO_VERIFY unusable outright.
    test('reads a plain inline assignment', () {
      expect(inlineEnvAssignment('ALLOW_RAW_GIT=1 git push', 'ALLOW_RAW_GIT'),
          '1');
    });
    test('reads a quoted value', () {
      expect(inlineEnvAssignment('X="1" git push', 'X'), '1');
      expect(inlineEnvAssignment("X='1' git push", 'X'), '1');
    });
    test('finds it on a later statement, when it prefixes THAT git call', () {
      expect(
        inlineEnvAssignment('echo hi && ALLOW_RAW_GIT=1 git push',
            'ALLOW_RAW_GIT'),
        '1',
      );
    });

    // ---- MENTION IS NOT AN INVOCATION -------------------------------------
    //
    // This block is the mirror of the one commandUsesWrapper carries above,
    // and it exists because the first version of inlineEnvAssignment matched
    // `(?:^|\s)NAME=` ANYWHERE in a statement. Review round 1 (2026-08-17)
    // proved against the REAL hook that this disarmed it: each command below
    // was BLOCKED (exit 2) before the change that introduced the helper and
    // ALLOWED (exit 0) after it.
    //
    // Every case is a real shape, not a contrived one — a commit message
    // quoting the hatch, a note-to-self echo, and (worst) a shell comment on a
    // raw force-skip push. In that last one the whole hook stands down: the
    // skip-hooks flag matches, the hatch reads "approved", and the raw-push
    // check never runs at all.
    //
    // These assert the LIBRARY predicate; the end-to-end exit codes are pinned
    // by the hook's own e2e coverage. Do not relax either one — a false
    // positive here is a silent bypass of the only mechanical guard on the
    // sanctioned write path.
    test('a mention inside a commit message does NOT grant the hatch', () {
      expect(
        inlineEnvAssignment(
            'git commit -m "noted ALLOW_RAW_GIT=1 in docs"', 'ALLOW_RAW_GIT'),
        isNull,
      );
    });
    test('a mention in a preceding echo does NOT grant the hatch', () {
      expect(
        inlineEnvAssignment(
            'echo "try ALLOW_RAW_GIT=1 next time"; git commit -m x',
            'ALLOW_RAW_GIT'),
        isNull,
      );
    });
    test('a mention in a trailing shell COMMENT does NOT grant the hatch', () {
      expect(
        inlineEnvAssignment(
            'git push origin main # FOUNDER_APPROVED_NO_VERIFY=1 pending',
            'FOUNDER_APPROVED_NO_VERIFY'),
        isNull,
      );
    });
    test('a prefix on a NON-git statement does not carry to the git one', () {
      // In a real shell this assignment applies to `echo`, not to `git`, so
      // honouring it would be wrong on the shell's own terms — not merely
      // unsafe. The guard and the shell agree here.
      expect(
        inlineEnvAssignment(
            'ALLOW_RAW_GIT=1 echo hi; git commit -m x', 'ALLOW_RAW_GIT'),
        isNull,
      );
    });
    // ---- MULTI-LINE: a mention on its OWN LINE is still only a mention -----
    //
    // Round 1 fixed WHERE in a statement the assignment may sit. It did not ask
    // whether the "statement" was executable text at all, and every test it
    // added used a SINGLE-LINE message — so these shapes reddened nothing and
    // shipped. Review round 2 (2026-08-17) found them against the real hook.
    //
    // splitStatements splits on every `\n`, so a line inside a heredoc body or
    // a multi-line `-m` message became its own "statement"; if it happened to
    // START with the incantation, the leading-prefix walk accepted it.
    //
    // This is not exotic. Multi-line commit messages are this repo's only
    // commit convention (the Co-Authored-By trailer alone guarantees one), so a
    // commit message that EXPLAINS the hatch policy would have unlocked it.
    // The heredoc case is worse: it disarms the whole hook, because the
    // skip-hooks handler exits 0 as soon as it believes it is approved.
    test('a heredoc BODY line starting with the incantation does not grant it',
        () {
      const cmd = 'git commit -F - <<\'EOF\'\n'
          'FOUNDER_APPROVED_NO_VERIFY=1 git commit was discussed\n'
          'EOF';
      expect(
        inlineEnvAssignment(cmd, 'FOUNDER_APPROVED_NO_VERIFY'),
        isNull,
        reason: 'a heredoc body is DATA. Nothing in it is ever executed, so '
            'nothing in it can grant an execution hatch.',
      );
    });

    test('a multi-line commit MESSAGE body line does not grant it', () {
      const cmd = 'git commit -m "fix: thing\n'
          '\n'
          'ALLOW_RAW_GIT=1 git commit is the documented hatch"';
      expect(
        inlineEnvAssignment(cmd, 'ALLOW_RAW_GIT'),
        isNull,
        reason: 'the text is inside quotes — a shell never executes it',
      );
    });

    test('a REAL prefix on a later line of a multi-line command still works',
        () {
      // The mirror, and the reason the fix is quote-aware rather than
      // "first line only": a genuine multi-line Bash command whose second line
      // carries the hatch is legitimate and must keep working.
      const cmd = 'cd /tmp\n'
          'ALLOW_RAW_GIT=1 git commit -m x';
      expect(inlineEnvAssignment(cmd, 'ALLOW_RAW_GIT'), '1',
          reason: 'this line IS executable text at top level');
    });

    test('splitExecutableStatements keeps quoted separators out of the split',
        () {
      // Directly pins the primitive, so a future refactor of the splitter has
      // its own failing test rather than only the indirect ones above.
      final s = splitExecutableStatements('git commit -m "a; b && c"');
      expect(s.length, 1,
          reason: 'separators inside quotes are not separators: got $s');

      final h = splitExecutableStatements(
          'git commit -F - <<\'EOF\'\nbody; still body\nEOF\ngit push');
      expect(h.any((x) => x.contains('still body')), isFalse,
          reason: 'heredoc body must not surface as an executable statement: $h');
      expect(h.any((x) => x.trim() == 'git push'), isTrue,
          reason: 'the statement AFTER the heredoc must still be seen: $h');
    });

    test('an unbalanced quote yields MORE statements, never fewer', () {
      // The failure direction matters. This splitter feeds an ALLOW decision,
      // so when it cannot parse something it must not silently swallow a
      // separator and merge a hatch onto a git call that never had one.
      final s = splitExecutableStatements('echo "unterminated\nALLOW_RAW_GIT=1 git commit');
      expect(inlineEnvAssignment('echo "unterminated\nALLOW_RAW_GIT=1 git commit',
          'ALLOW_RAW_GIT'), isNull,
          reason: 'inside an unterminated quote it is still data: $s');
    });

    // ---- THE HATCH BINDS TO A STATEMENT, NOT TO THE COMMAND ---------------
    //
    // Generation 3 of this bug, found by the B-pass (2026-08-17) after rounds 1
    // and 2 had each fixed a different half of it. Rounds 1 and 2 bound the
    // assignment correctly to a statement — and then the CALLER collapsed that
    // into one command-wide boolean and applied it to every deny. So a harmless
    // hatched statement exempted an unrelated dangerous one.
    //
    // Reproduced against the real hook with controls blocking:
    //     ALLOW_RAW_GIT=1 git status; git push origin main --force   -> ALLOWED
    //     ALLOW_RAW_GIT=1 git status && git commit -m sneaky         -> ALLOWED
    //     FOUNDER_APPROVED_NO_VERIFY=1 git status; git commit --no-verify -m x
    //                                                                -> ALLOWED
    // None of these is even shell-accurate: an inline assignment prefixes ONE
    // command and is never carried to the next statement.
    //
    // These test the LIBRARY predicate. The hook's end-to-end behaviour is
    // covered by the case matrices driven through its stdin contract.
    group('unhatchedGitStatements — pairing danger with its own hatch', () {
      test('a hatch on one statement does NOT exempt another', () {
        expect(
          unhatchedGitStatements(
              'ALLOW_RAW_GIT=1 git status; git push origin main --force',
              'push',
              'ALLOW_RAW_GIT'),
          isNotEmpty,
          reason: 'the push carries no hatch of its own and must be reported',
        );
      });

      test('a hatch on the dangerous statement itself DOES exempt it', () {
        // The mirror. Without it, a predicate that reported every git statement
        // unconditionally would satisfy the test above and break every
        // documented use of the hatch.
        expect(
          unhatchedGitStatements(
              'ALLOW_RAW_GIT=1 git push origin main', 'push', 'ALLOW_RAW_GIT'),
          isEmpty,
        );
      });

      test('each statement is judged on its own hatch, independently', () {
        expect(
          unhatchedGitStatements(
              'ALLOW_RAW_GIT=1 git commit -m a; ALLOW_RAW_GIT=1 git push',
              'push',
              'ALLOW_RAW_GIT'),
          isEmpty,
          reason: 'both hatched individually — the documented multi-step form',
        );
        expect(
          unhatchedGitStatements(
              'ALLOW_RAW_GIT=1 git commit -m a; git push', 'push', 'ALLOW_RAW_GIT'),
          isNotEmpty,
          reason: 'only the commit was hatched; the push was not',
        );
      });

      test('returns the offending statement text, not just a flag', () {
        // A bool is what let generation 3 happen: the binding existed and the
        // caller threw it away. Returning the statements keeps the pairing
        // visible at the call site and lets the deny quote what it objects to.
        final out = unhatchedGitStatements(
            'ALLOW_RAW_GIT=1 git status; git push origin main',
            'push',
            'ALLOW_RAW_GIT');
        expect(out.single, contains('git push origin main'));
        expect(out.single, isNot(contains('git status')));
      });

      test('no git statement of that subcommand yields empty', () {
        expect(
          unhatchedGitStatements('ls -la; echo hi', 'push', 'ALLOW_RAW_GIT'),
          isEmpty,
        );
      });
    });

    group('unhatchedNoVerifyStatements — same pairing for the skip-hooks flag',
        () {
      test('a hatch on an unrelated statement does NOT exempt the flag', () {
        expect(
          unhatchedNoVerifyStatements(
              'FOUNDER_APPROVED_NO_VERIFY=1 git status; '
              'git commit --no-verify -m x',
              'FOUNDER_APPROVED_NO_VERIFY'),
          isNotEmpty,
          reason: 'this shape exits the hook at the top, before the commit and '
              'push checks run — it disarms everything',
        );
      });

      test('a hatch on the flagged statement itself DOES exempt it', () {
        expect(
          unhatchedNoVerifyStatements(
              'FOUNDER_APPROVED_NO_VERIFY=1 git commit --no-verify -m x',
              'FOUNDER_APPROVED_NO_VERIFY'),
          isEmpty,
        );
      });
    });

    test('the prefix chain is still honoured through env(1) and stacking', () {
      // The strictness above must not cost the documented forms. These are the
      // shapes stripCommandPrefixes already accepts, so the two must agree —
      // if they drift, the hatch applies in positions the strip does not
      // recognise, which is how the original hole opened.
      expect(inlineEnvAssignment('env ALLOW_RAW_GIT=1 git commit -m x',
          'ALLOW_RAW_GIT'), '1');
      expect(inlineEnvAssignment('FOO=1 ALLOW_RAW_GIT=1 git push',
          'ALLOW_RAW_GIT'), '1');
      expect(inlineEnvAssignment('cd /tmp && ALLOW_RAW_GIT=1 git commit -m x',
          'ALLOW_RAW_GIT'), '1');
    });
    test('returns null when absent — never a default that grants the hatch', () {
      expect(inlineEnvAssignment('git push', 'ALLOW_RAW_GIT'), isNull);
    });
    test('does not match a different variable with the same suffix', () {
      expect(inlineEnvAssignment('NOT_ALLOW_RAW_GIT=1 git push', 'ALLOW_RAW_GIT'),
          isNull);
    });
    test('a value other than 1 is returned verbatim, not coerced', () {
      // The hook compares to '1' itself; the helper must not decide for it.
      expect(inlineEnvAssignment('ALLOW_RAW_GIT=0 git push', 'ALLOW_RAW_GIT'),
          '0');
    });
  });
}
