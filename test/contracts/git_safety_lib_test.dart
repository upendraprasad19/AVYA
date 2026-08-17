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
    test('finds it on any statement, not just the first', () {
      expect(
        inlineEnvAssignment('echo hi && ALLOW_RAW_GIT=1 git push',
            'ALLOW_RAW_GIT'),
        '1',
      );
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
