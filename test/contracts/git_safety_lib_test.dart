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
}
