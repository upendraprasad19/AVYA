---
reviewed_at: 2026-07-19T08:15:00+05:30
staged_against: discipline-overhead vs main (branch diff, main...HEAD)
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 6
verdict: accepted
---

# Code Review — discipline-overhead vs main

Fresh-agent B-pass on the full branch diff (10 files → grew to 13 after fixes below),
after 2 independent ×2 plan-review rounds already found and fixed 10 issues (F1-F9, N1).

## Finding 1 — P1 — process (uncommitted fix)
- **file:line:** scripts/git_safety_hook.dart:135-153 (as of commit `d442e577`)
- **claim:** the N1 advisory-precheck fix existed only in the working tree (staged,
  uncommitted) at review time; HEAD still had the hard-blocking version.
- **verification:** `git diff main...HEAD -- scripts/git_safety_hook.dart` (hard block)
  vs `git diff --cached -- scripts/git_safety_hook.dart` (fix)
- **suggested-fix:** commit the staged fix before merge.
- **status:** accepted — committed `2eb55dcc` (with a `build(discipline):` prefix, not
  `fix:`, since this is pre-merge hardening of unshipped code per this repo's own
  precedent, not a diagnose-doc-requiring production bug fix).

## Finding 2 — P1 — blast_radius_mismatch
- **file:line:** docs/blast_radius.yaml (scripts/** and .claude/** both feature-tier)
- **claim:** `scripts/git_safety_hook.dart`, `scripts/git_safety_lib.dart`, and
  `.claude/settings.json` had no explicit tier override — a future commit touching
  ONLY those files (not CLAUDE.md) would clear zero review gate despite having sole
  power to block every git commit/push platform-wide in every future session.
- **verification:** `grep -n "git_safety\|settings.json" docs/blast_radius.yaml`
  (was: no match)
- **suggested-fix:** add explicit platform-tier overrides.
- **status:** accepted — added overrides for git_safety_hook.dart, git_safety_lib.dart,
  .claude/settings.json, and (for consistency — same safety-critical property,
  reviewer's own reasoning applies equally) the pre-existing
  check_commit_from_worktree.dart + worktree_guard_lib.dart, which had the identical
  pre-existing gap.

## Finding 3 — P2 — writer_reader_drift (channel mismatch)
- **file:line:** scripts/git_safety_hook.dart (advisory warning path)
- **claim:** the advisory warning used `stderr.writeln` on a non-blocking (exit 0)
  PreToolUse return; scripts/discipline_hook.dart's own header states plain output on
  a non-blocking return is debug-log-only and `hookSpecificOutput.additionalContext`
  is "the sole channel" — so the warning likely wasn't visible at all, not just seen
  later than CI.
- **verification:** `grep -n "additionalContext\|stderr.writeln" scripts/discipline_hook.dart scripts/git_safety_hook.dart`
- **suggested-fix:** emit via the same JSON additionalContext channel.
- **status:** accepted — added `_allowWithContext()` mirroring discipline_hook.dart's
  `_emit()` exactly; the precheck's advisory path now uses it instead of stderr.

## Finding 4 — P2 — unawaited_no_error_sink (hang risk)
- **file:line:** scripts/git_safety_hook.dart stdin read (no timeout/hasTerminal guard,
  unlike its sibling discipline_hook.dart:82,221)
- **claim:** this hook runs on every Bash call in every session; an unresolved stdin
  read (manual invocation, a harness edge case) hangs forever with no fail-open.
- **verification:** `grep -n "stdin.hasTerminal\|\.timeout(" scripts/*.dart`
- **suggested-fix:** mirror discipline_hook.dart's 3s timeout + hasTerminal guard.
- **status:** accepted — added `_readStdin()` with the identical guard + timeout.

## Finding 5 — P2 — test-coverage gap
- **file:line:** test/contracts/git_safety_lib_test.dart (only unit-tests pure
  functions; nothing exercises the hook's actual stdin JSON → exit-code contract)
- **claim:** the field-name assumptions (hook_event_name, tool_name,
  tool_input.command, cwd) had zero regression coverage at the wire level.
- **verification:** repo-wide `grep -rn tool_input` outside this branch → empty
- **suggested-fix:** add an integration test spawning the real subprocess.
- **status:** accepted — added test/contracts/git_safety_hook_integration_test.dart,
  8 cases, spawns the actual `dart run scripts/git_safety_hook.dart` subprocess with
  real JSON on stdin (found + fixed an unrelated Windows `Process.start` PATHEXT
  issue — needed `runInShell: true` — while making this test pass for real).

## Finding 6 — P3 — unawaited_no_error_sink (shell)
- **file:line:** safe_commit.sh:28-29 / safe_push.sh:28-29
- **claim:** `REPO_ROOT="$(git rev-parse --show-toplevel)"` then `cd "$REPO_ROOT"` was
  unchecked; an empty substitution makes `cd` fail silently (no `set -e`).
- **verification:** `sh -c 'R=""; cd "$R"; echo exit=$?'`
- **suggested-fix:** guard both.
- **status:** accepted — both scripts now check for empty REPO_ROOT and check `cd`'s
  own exit code before proceeding.

## Checked clean (per the reviewer, re-verified)
- `check_plan_review_record_exists.dart` isolation: the bpass/hermes/anti-fabrication
  blocks are byte-identical to main; only the `rounds` check changed.
- secrets_in_tree: zero credential-shaped literals in any new file; DENY/WARN messages
  never echo the raw untrusted `command` string verbatim.
- No fire-and-forget async in the new Dart code; all subprocess calls are synchronous
  by design or explicitly awaited.

## Founder triage notes
All 6 findings fixed in-batch (no deferrals). Verified via: `flutter test
test/contracts/git_safety_lib_test.dart test/contracts/git_safety_hook_integration_test.dart`
(30/30 green) + a fresh synthetic PreToolUse payload confirming the advisory path.
