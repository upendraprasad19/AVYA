// scripts/git_safety_hook.dart
//
// PreToolUse(Bash) BLOCKING hook -- discipline-overhead batch 2026-07-19.
// Converts the git-landing-verification lesson
// (memory/feedback_git_landing_verification.md: 6 documented incidents
// 2026-06-05 -> the workout-generator batch -- masked exit codes from
// pipes/backgrounding, SIGPIPE on a long-idle SSH channel) from a memory rule
// I have to remember and re-apply every time into a real block. Unlike
// scripts/discipline_hook.dart (reminder-only: injects additionalContext,
// fails open on ANY error by design, never blocks anything), THIS hook can
// DENY the tool call outright via exit code 2 + stderr -- Claude Code's
// PreToolUse blocking contract.
//
// Kept as a SEPARATE script from discipline_hook.dart on purpose: that
// script's contract is "never break the session, fail open on any error"
// (right for a reminder). This hook's job is the opposite -- actively deny
// specific unsafe git invocations -- so mixing the two contracts in one file
// risked diluting discipline_hook.dart's tested fail-open guarantee.
//
// Denies (exit 2):
//   1. a literal `--no-verify` flag on any git command. No general escape
//      hatch -- CLAUDE.md §4.3 already requires explicit founder approval in
//      chat before using it; bypass here needs FOUNDER_APPROVED_NO_VERIFY=1,
//      a deliberately separate/louder env var from the one below, set ONLY
//      after that approval was actually given for this specific invocation.
//   2. a raw `git commit` not going through scripts/safe_commit.sh, unless a
//      merge/cherry-pick/revert is in progress (mirrors
//      check_commit_from_worktree.dart's exact MERGE_HEAD/CHERRY_PICK_HEAD/
//      REVERT_HEAD exemption -- those are the legitimate ways `git commit`
//      gets invoked directly, e.g. completing a conflicted merge).
//   3. a raw `git push` not going through scripts/safe_push.sh.
//   Escape hatch for 2+3 (mirrors check_commit_from_worktree.dart's
//   ALLOW_MAIN_COMMIT=1 pattern): ALLOW_RAW_GIT=1, for a legitimate case this
//   hook mis-detects. Never bypasses 1.
//
// Separately (not a deny path, a local re-run of an existing gate): any
// push-shaped command (raw `git push` OR via safe_push.sh) that would land a
// merge on main gets scripts/check_plan_review_record_exists.dart run
// LOCALLY first, synchronously, unmodified -- so a missing/invalid plan-
// review record is caught before the push+CI round-trip instead of after.
// That script already no-ops correctly for anything that isn't a >=account
// merge-to-main commit, so invoking it unconditionally on any push-shaped
// command is safe.
//
// Fails OPEN on any internal error (malformed stdin, non-Bash tool, git dirs
// unresolvable) -- a bug in THIS script must never wedge an unrelated tool
// call. Threads the hook's own `cwd` (from the PreToolUse JSON) through every
// git/dart subprocess call -- this repo has multiple worktrees, each with its
// own per-worktree HEAD/MERGE_HEAD, so resolving the WRONG cwd could silently
// check the wrong worktree's state.

import 'dart:convert';
import 'dart:io';

import 'git_safety_lib.dart';

bool _gitOk(String cwd, List<String> args) {
  try {
    return Process.runSync('git', args, workingDirectory: cwd).exitCode == 0;
  } catch (_) {
    return false;
  }
}

void _deny(String message) {
  stderr.writeln(message);
  exit(2);
}

// Non-blocking advisory: uses the SAME hookSpecificOutput.additionalContext
// JSON channel as scripts/discipline_hook.dart (B-pass finding #3: a plain
// stderr.writeln on a non-blocking exit-0 PreToolUse return is debug-log
// only per that script's own documented channel contract -- it would not
// actually have been seen).
void _allowWithContext(String context) {
  stdout.writeln(jsonEncode({
    'hookSpecificOutput': {
      'hookEventName': 'PreToolUse',
      'additionalContext': context,
    }
  }));
  exit(0);
}

Future<String> _readStdin() async {
  // B-pass finding #4: mirror discipline_hook.dart's hasTerminal guard + 3s
  // timeout. This hook now runs on every Bash call in every session -- an
  // unresolved read (manual invocation, a harness edge case) must never hang
  // the whole session; fail open instead.
  if (stdin.hasTerminal) return '';
  return utf8.decoder.bind(stdin).join().timeout(
        const Duration(seconds: 3),
        onTimeout: () => '',
      );
}

void main() async {
  try {
    final input = await _readStdin();
    if (input.trim().isEmpty) exit(0);
    final data = jsonDecode(input) as Map<String, dynamic>;

    if (data['hook_event_name'] != 'PreToolUse') exit(0);
    if (data['tool_name'] != 'Bash') exit(0);

    final toolInput = data['tool_input'] as Map<String, dynamic>?;
    final command = (toolInput?['command'] as String?) ?? '';
    if (command.trim().isEmpty) exit(0);

    final cwd = (data['cwd'] as String?) ?? Directory.current.path;
    final env = Platform.environment;

    // 1. --no-verify: no general escape hatch.
    if (commandHasNoVerifyFlag(command)) {
      // Both the process env AND an inline `NAME=1 git ...` prefix count. The
      // inline form is what CLAUDE.md §4.3 and the deny message below actually
      // tell you to type, and it never reaches this process's environment --
      // see inlineEnvAssignment's doc comment for why that left this hatch
      // unusable and the ALLOW_RAW_GIT one working only by detection miss.
      if (env['FOUNDER_APPROVED_NO_VERIFY'] == '1' ||
          inlineEnvAssignment(command, 'FOUNDER_APPROVED_NO_VERIFY') == '1') {
        exit(0);
      }
      _deny(
        '[git-safety] BLOCKED: --no-verify requires explicit founder approval '
        'in chat FIRST (CLAUDE.md §4.3 -- never a unilateral bypass of a '
        'failing hook). If the founder has already approved this exact '
        'invocation, set FOUNDER_APPROVED_NO_VERIFY=1 for it and retry.',
      );
    }

    // Statement-split detection (review round 1, F2): a single string-wide
    // anchored regex silently missed a `git commit`/`git push` on any line
    // after the first in a multi-line command -- the dominant shape Claude
    // actually emits. git_safety_lib splits on \n/;/&&/||/| and checks each
    // statement, and also tolerates `git -C <dir> commit` / `--no-pager`.
    // Honoured from either source, for the same reason as the hatch above.
    final allowRawGit = env['ALLOW_RAW_GIT'] == '1' ||
        inlineEnvAssignment(command, 'ALLOW_RAW_GIT') == '1';

    final hasRawCommit = commandInvokesGitSubcommand(command, 'commit');
    final hasRawPush = commandInvokesGitSubcommand(command, 'push');
    final usesSafeCommit = commandUsesWrapper(command, 'safe_commit.sh');
    final usesSafePush = commandUsesWrapper(command, 'safe_push.sh');

    // 2. raw `git commit`.
    if (hasRawCommit && !usesSafeCommit) {
      final mergeInProgress =
          _gitOk(cwd, ['rev-parse', '-q', '--verify', 'MERGE_HEAD']) ||
              _gitOk(cwd, ['rev-parse', '-q', '--verify', 'CHERRY_PICK_HEAD']) ||
              _gitOk(cwd, ['rev-parse', '-q', '--verify', 'REVERT_HEAD']);
      if (!mergeInProgress && !allowRawGit) {
        _deny(
          '[git-safety] BLOCKED: raw `git commit` -- 6 documented incidents '
          '(memory/feedback_git_landing_verification.md) where a backgrounded '
          'or piped commit reported success while the actual commit failed. '
          'Use:\n    sh scripts/safe_commit.sh "<message>"\n'
          'Escape hatch for a case this hook mis-detects: ALLOW_RAW_GIT=1 git commit ...',
        );
      }
    }

    // 3. raw `git push`.
    if (hasRawPush && !usesSafePush && !allowRawGit) {
      _deny(
        '[git-safety] BLOCKED: raw `git push` -- a long pre-push suite can '
        'idle the SSH channel and SIGPIPE silently with no git error '
        '(memory/feedback_git_landing_verification.md, 2026-07-03). Use:\n'
        '    sh scripts/safe_push.sh [remote] [branch]\n'
        'Escape hatch for a case this hook mis-detects: ALLOW_RAW_GIT=1 git push ...',
      );
    }

    // Local re-run of the plan-review-record gate, for ANY push-shaped
    // command (raw or via the safe wrapper) -- ADVISORY ONLY (review round 2,
    // N1): this precheck is a pure local optimization -- CI re-runs the exact
    // same gate as the real, authoritative backstop -- so it must never be
    // able to hard-block a push with no escape hatch. An earlier version
    // denied on any non-zero exit, which could wedge the ONE path that lands
    // work on main (the integration push from the shared main folder) with
    // no override if the precheck itself ever misbehaves (toolchain hiccup,
    // an edge case in its own branch-recovery logic). Warning-only here loses
    // no real enforcement -- only visibility timing (before vs. after the
    // push+CI round-trip) -- and CI still hard-fails a genuinely missing
    // review regardless of what happens on this local pass.
    if (commandIsPushShaped(command)) {
      final scriptPath = 'scripts/check_plan_review_record_exists.dart';
      if (File('$cwd/$scriptPath').existsSync()) {
        try {
          final result = Process.runSync(
            'dart',
            ['run', scriptPath],
            workingDirectory: cwd,
          );
          if (result.exitCode != 0) {
            // additionalContext, not stderr -- see _allowWithContext's
            // doc comment (B-pass finding #3: stderr on a non-blocking
            // return is debug-log only, effectively invisible).
            _allowWithContext(
              '[git-safety] NOTE: local plan-review-record precheck failed '
              '(advisory only -- CI will enforce this for real before merge):\n'
              '${result.stdout}${result.stderr}',
            );
          }
        } catch (_) {
          // A precheck toolchain hiccup must never block the push itself --
          // CI is the authoritative backstop regardless.
        }
      }
    }

    exit(0);
  } catch (_) {
    // Fail OPEN -- a bug in this hook must never wedge an unrelated tool call.
    exit(0);
  }
}
