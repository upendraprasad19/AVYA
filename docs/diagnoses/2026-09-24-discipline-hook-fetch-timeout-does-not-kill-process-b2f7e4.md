---
bug_id: b2f7e4
date: 2026-09-24
batch: main-sync-warning (B-pass remediation, same branch as the fix it corrects)
status: fixed
blast_radius: platform
symptom: |
  A B-pass adversarial review of commit `1db54e4f` (the SessionStart
  main-vs-origin/main sync warning added to `scripts/discipline_hook.dart`
  this same batch) found that `_mainSyncWarning()`'s bounded fetch used
  `Process.run('git', [...]).timeout(const Duration(seconds: 4))`.
  `Future.timeout()` is a pure race against a Timer with no process
  cancellation API — when the timer fires it abandons the original Future
  and throws `TimeoutException`, but never signals the underlying OS
  process. A `git fetch` that genuinely hangs (most plausibly: blocked on
  an interactive SSH/credential prompt reading from a stdin pipe that will
  never receive input, since `Process.run` attaches no real tty) is
  ORPHANED and keeps running indefinitely after the timeout fires.

  Reproducing this live (a fake `git` on PATH whose `fetch` subcommand
  `exec`s into `sleep 300`, everything else delegated to the real git)
  showed the defect was WORSE than "an orphaned background process": the
  Dart runtime does not exit the discipline_hook.dart process itself while
  a stream listener on an open child-process pipe is still pending, so the
  ENTIRE hook hung for the full 300s duration of the fake hang — not the
  advertised ~4s bound. `refs/remotes/origin/main` and `.git/FETCH_HEAD`
  are shared mutable state across every §4.13 linked-worktree session
  (they all share one `.git` directory), and `SessionStart` fires on every
  session start, so a genuinely hung fetch would have blocked the harness
  from returning control to the user for minutes, and could hold a lock a
  concurrent `safe_commit.sh`/`safe_push.sh`/`git fetch` in another
  worktree session needs.
concept: discipline_hook_main_sync_bounded_fetch
sot_registry_entry: not_applicable — a harness SessionStart hook mechanism,
  not a Hive/Postgres writer/reader contract.
writers:
  - { file: scripts/discipline_hook.dart, method_or_widget: "_boundedFetch — spawns via Process.start and kills the process directly on timeout instead of racing a Future", line: 334 }
readers:
  - { file: scripts/discipline_hook.dart, method_or_widget: "_mainSyncWarning — calls _boundedFetch(); also gained the DISCIPLINE_HOOK_SYNC_SKIP=1 kill switch this same fix added", line: 370 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/scripts/discipline_hook_main_sync_e2e_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — a local git-state check with no auth/session involvement.
forbidden_patterns_checked:
  - "tightening the timeout duration instead of fixing the cancellation mechanism — a shorter Future.timeout() would still never kill the child process; the defect is the absence of a kill, not the duration chosen"
  - "leaving the fix unguarded — added DISCIPLINE_HOOK_SYNC_SKIP=1 (same B-pass review, separate P2 finding) so an operator can disable this SessionStart mechanism surgically if it misbehaves in a way this fix doesn't anticipate, consistent with every other risky mechanism in this file (DISCIPLINE_HOOK_MEMORY_PATH, .claude/.batch_close.disabled, CONTRACT_SWEEP_SKIP=1, .claude/.reconcile_ci.disabled)"
proposed_fix: |
  Replace `Process.run(...).timeout(...)` with `Process.start(...)`,
  explicitly `.timeout()` on `process.exitCode` (not the whole run), and
  call `process.kill(ProcessSignal.sigkill)` in the `onTimeout` callback so
  the child is actually killed rather than merely abandoned by the
  awaiting Future. Also set `GIT_TERMINAL_PROMPT=0` in the fetch's
  environment so a credential prompt fails fast instead of hanging in the
  first place (belt-and-suspenders — the timeout+kill still covers any
  OTHER cause of a hang, e.g. a slow/dead network). Drain
  `process.stdout`/`process.stderr` explicitly (not just ignore them) since
  an unread pipe can fill its OS buffer and deadlock the child before exit,
  even with `--quiet`.
regression_test_planned:
  - test/scripts/discipline_hook_main_sync_e2e_test.dart — new test "a hanging `git fetch` is actually KILLED on timeout, not orphaned": stubs a `git` on PATH whose `fetch` subcommand execs into `sleep 300` (writing its own pid to a file first) and everything else delegates to the real git; asserts the hook process exits in well under 20s (not 300s) AND that the recorded pid is no longer alive ~1s after the hook exits — the second assertion is what distinguishes "the Future gave up waiting" (pre-fix: process lives on) from "the process was actually killed" (fix). POSIX-only fixture (exec/kill -0/sh script), skipped on Windows; the underlying fix itself is platform-independent.
  - test/scripts/discipline_hook_main_sync_e2e_test.dart — new test "kill switch DISCIPLINE_HOOK_SYNC_SKIP=1 disables the check entirely": sets the env var against a fixture that would otherwise report MAIN BEHIND, asserts no MAIN BEHIND/AHEAD/DIVERGED line appears.
impact_analysis: |
  Fixes a defect in code that had not yet been pushed/merged (introduced
  and corrected within the same unmerged branch, discovered by this
  batch's own self-triggered B-pass per CLAUDE.md §4.3 before merge to
  main) — zero live/production exposure. Scope is limited to
  `_mainSyncWarning`'s own fetch call; no other function in
  discipline_hook.dart uses the `Process.run(...).timeout(...)` pattern
  (confirmed by grep), so this is not a recurrence-class fix elsewhere in
  the file.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "dart analyze scripts/discipline_hook.dart -- No issues found, both before and after the fix." }
mutation_proven:
  mutated: "scripts/discipline_hook.dart:_boundedFetch reverted to the pre-fix Process.run(...).timeout(...) pattern (no Process.start, no kill), per the mutate-it-and-run-it requirement (CLAUDE.md §4.4 rule 21)."
  result: "The new 'actually KILLED on timeout, not orphaned' test reddened as expected -- but the failure shape itself was the sharper confirmation: rather than a fast (~4-5s) wall-clock assertion failure, the mutated hook process did not exit at all until the fake fetch's full 300s sleep completed (Expected: a value less than 0:00:20.000000, Actual: 0:05:00.470355), directly reproducing the 'entire hook hangs, not just an orphaned background process' severity noted above. All 7 other tests in the same file were unaffected by the mutation (not re-run individually here since the mutation was isolated to _boundedFetch, which only the two new tests exercise directly enough to distinguish the timing)."
  confirmed_applied: "Ran the target test before the mutation (green, ~5-6s), applied the mutation via a file copy-swap, dart analyze confirmed it still compiled, ran the target test again (red, 5:00 wall time, correct failure message), restored the fix via the same copy-swap, dart analyze confirmed clean, re-ran the full discipline_hook_main_sync_e2e_test.dart + discipline_hook_main_sync_format_test.dart + discipline_hook_oi_line_e2e_test.dart + discipline_hook_memory_path_test.dart suite (22/22 green)."
residual: |
  None. The B-pass's remaining two findings (P3: fetch failure reasons
  [timeout/missing-git/offline/no-remote] are conflated into one
  "offline/fetch failed" message; P4: this function doesn't resolve an
  absolute repo root the way its sibling `_oiBoardLine()` does) were both
  explicitly assessed by the reviewer as not requiring a fix — P3 is an
  accepted simplification consistent with this file's fail-silent
  philosophy (no reader distinguishes the cases), and P4 is a stylistic
  divergence with no functional risk (all git subcommands used operate on
  repo state, not filesystem paths, so cwd-independence holds regardless).
  Not fixed, not silently dropped — recorded here per §4.2.
---

## Summary

A self-triggered B-pass review of this batch's own new SessionStart
main-sync warning (CLAUDE.md §4.3, mandatory for platform-tier changes
before merge) found that its bounded `git fetch` used
`Process.run(...).timeout(...)`, which does not kill the underlying OS
process on timeout — a well-documented Dart `dart:io`/`dart:async` gotcha
(no `Future.cancel()` API). Live reproduction showed the defect was worse
than an orphaned background process: because the Dart runtime keeps a
process alive while a stream listener on an open child pipe is pending, a
genuinely hung fetch would hang the ENTIRE hook for the fetch's full
duration, not the advertised ~4s bound — directly undermining the feature's
purpose (a fast, bounded check at session start) and risking lock
contention on the shared `.git` directory every §4.13 worktree session
reads/writes.

## Root cause

`Future.timeout()` races a Timer against a Future; when the timer wins it
abandons the original Future's continuation but has no mechanism to signal
or kill whatever OS-level work that Future represents. `Process.run()`
internally spawns via `Process.start()` and only completes once the child
exits AND its stdout/stderr streams are fully drained — none of which the
timeout can interrupt.

## Fix

`scripts/discipline_hook.dart`: new `_boundedFetch()` helper (line 334)
spawns via `Process.start()`, times out `process.exitCode` specifically
(not the whole run), and calls `process.kill(ProcessSignal.sigkill)` on
timeout so the child is actually terminated. Sets `GIT_TERMINAL_PROMPT=0`
so a credential prompt fails fast rather than hanging in the first place.
`_mainSyncWarning()` (line 377) also gained a `DISCIPLINE_HOOK_SYNC_SKIP=1`
kill switch, a separate P2 finding from the same review, fixed in the same
commit.

## Regression tests

- `test/scripts/discipline_hook_main_sync_e2e_test.dart` — "a hanging `git
  fetch` is actually KILLED on timeout, not orphaned" (new)
- `test/scripts/discipline_hook_main_sync_e2e_test.dart` — "kill switch
  DISCIPLINE_HOOK_SYNC_SKIP=1 disables the check entirely" (new)

Both mutation-proven — see `mutation_proven` in the frontmatter.
