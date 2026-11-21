---
reviewed_at: 2026-09-24T00:00:00+05:30
staged_against: 1db54e4f4634b74f5fc1326d1db3733a21836468
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
---

# Code Review — commit `1db54e4f` (branch `main-sync-warning`)

Reviewed post-commit (the diff was already committed; the review targeted
`git diff HEAD~1 HEAD` rather than the staged index, since nothing remained
staged — same pattern as the 2026-09-23 `claude/oi-242-flaky-test-filing`
entry in this skill's tuning history). Dispatched as a fresh, context-blind
`general-purpose` subagent with no prior conversation context.

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** `scripts/discipline_hook.dart:322-333` (pre-fix)
- **claim:** `Process.run(...).timeout(const Duration(seconds: 4))` does not
  kill the underlying OS process on timeout — `Future.timeout()` races a
  Timer against the Future with no cancellation API, so a stalled `git
  fetch` (e.g. blocked on an interactive credential prompt) is orphaned and
  keeps running after the function returns, potentially holding a lock on
  the SHARED `.git` dir every §4.13 worktree session reads/writes.
- **verification:** reasoned from `dart:io`/`dart:async` semantics (no
  `Future.cancel()` API); reproduced live post-review with a fake `git` on
  PATH whose `fetch` subcommand execs into `sleep 300` — the pre-fix hook
  did not exit until the full 300s elapsed, confirming the defect is worse
  than "an orphaned background process": the ENTIRE hook hangs, not just a
  4s-bounded check with a lingering side effect.
- **suggested-fix:** spawn via `Process.start()`, time out `exitCode`
  specifically, and call `process.kill(ProcessSignal.sigkill)` on timeout.
- **status:** accepted, fixed — `_boundedFetch()`
  (`scripts/discipline_hook.dart:334`), also sets `GIT_TERMINAL_PROMPT=0` so
  a credential prompt fails fast rather than hanging in the first place.
  Mutation-proven: reverting to the pre-fix pattern reddens the new
  regression test with exactly the predicted failure mode (300s wall time
  vs. an expected <20s bound). Diagnose-doc:
  `docs/diagnoses/2026-09-24-discipline-hook-fetch-timeout-does-not-kill-process-b2f7e4.md`.

## Finding 2 — P2 — blast_radius_mismatch
- **file:line:** `scripts/discipline_hook.dart:314-373` (pre-fix, whole
  `_mainSyncWarning`); `docs/blast_radius.yaml:225` pins
  `scripts/discipline_hook.dart` at `platform` tier.
- **claim:** every other consequential mechanism in this file carries an
  explicit kill switch (`DISCIPLINE_HOOK_MEMORY_PATH` override,
  `.claude/.batch_close.disabled`, `CONTRACT_SWEEP_SKIP=1`,
  `.claude/.reconcile_ci.disabled`); `_mainSyncWarning()` introduced the
  file's first network call with no equivalent way to disable it
  surgically.
- **verification:** grep of the file for existing kill-switch env vars/flag
  files, confirmed none covered the new fetch.
- **suggested-fix:** add an env-var kill switch checked at the top of the
  function.
- **status:** accepted, fixed — `DISCIPLINE_HOOK_SYNC_SKIP=1`
  (`scripts/discipline_hook.dart:371`), regression-tested.

## Finding 3 — P2 — guard_without_its_mirror (lock contention)
- **file:line:** `scripts/discipline_hook.dart:322-327` (pre-fix)
- **claim:** CLAUDE.md §4.13 encourages multiple simultaneous linked-worktree
  sessions sharing one `.git`; every session's `SessionStart` now spawns a
  `git fetch` against that shared state concurrently, increasing the odds of
  hitting Finding 1's failure mode under real lock contention.
- **verification:** reasoning from §4.13's documented multi-worktree usage
  pattern; not independently executed.
- **suggested-fix:** covered by Finding 1's fix (the process is now
  genuinely bounded, so even a lock-wait-induced stall is capped at ~4s
  before being killed).
- **status:** accepted, resolved by Finding 1's fix — no separate change
  needed.

## Finding 4 — P3 — asserted_fixture_value (informational, no fix required)
- **file:line:** `scripts/discipline_hook.dart:273-282` (`formatMainSyncWarning`)
- **claim:** the fetch-failure `catch (_)` treats `TimeoutException`,
  `ProcessException` (git missing), and a normal non-zero exit (auth/DNS
  failure, no remote) identically — the user-facing message always says
  "offline/fetch failed" regardless of cause, which could mislead someone
  debugging an unrelated problem (e.g. a broken git install).
- **verification:** read `formatMainSyncWarning`'s staleness-suffix branch.
- **suggested-fix:** none required — reviewer's own assessment: acceptable
  given the file's stated fail-silent design philosophy (no reader
  distinguishes the cases at this granularity).
- **status:** accepted, no fix — recorded in the diagnose-doc's `residual`
  field per §4.2 (not silently dropped, deliberately left as-is).

## Finding 5 — P4 — missing_input (informational, no fix required)
- **file:line:** `scripts/discipline_hook.dart:373-417` vs. `_oiBoardLine()`
  and `_worktreeWarning()`
- **claim:** `_mainSyncWarning()` never resolves an absolute repo root via
  `git rev-parse --show-toplevel` the way `_oiBoardLine()` does, and doesn't
  pass `workingDirectory` to its `Process.run` calls — a stylistic
  divergence from its two sibling functions.
- **verification:** compared all three functions' repo-root resolution.
- **suggested-fix:** none required — all git subcommands used
  (`rev-parse --verify`, `fetch`, `rev-list`) operate on repo state, not
  filesystem paths, and git auto-discovers the enclosing `.git` by walking
  up from cwd, so this is not a functional defect.
- **status:** accepted, no fix — recorded in the diagnose-doc's `residual`
  field.

## Lenses that came back clean
- **writer_reader_drift:** grepped the whole tree for the new function
  names/output strings outside the implementation and its own tests — zero
  external dependents.
- **function_exception_swallow:** every try/catch reviewed; Finding 1 is the
  one place this mattered (see above).
- **secrets_in_tree:** nothing credential-shaped in the diff.
- **unawaited_no_error_sink:** the new e2e test's `unawaited(p.stderr.drain())`
  matches the pre-existing, working idiom in the sibling
  `discipline_hook_oi_line_e2e_test.dart`.
- **asserted_fixture_value (test literals):** independently re-derived
  `git rev-list --left-right --count` semantics against all 4 e2e scenarios
  and the pure-formatter boundary test — all literals match. The
  `file:///`-based offline-fallback fixture resolves as a local path check
  (rejected near-instantly, no DNS/network round-trip), so the reviewer's
  specific worry about that test flaking on a slow DNS timeout does not
  apply.

## Founder triage notes
All 5 findings triaged and closed in this same commit batch: Findings 1–2
fixed with regression tests (mutation-proven for Finding 1); Finding 3
resolved as a side effect of Finding 1's fix; Findings 4–5 accepted as
informational with no code change, recorded in the diagnose-doc's
`residual` field per CLAUDE.md §4.2 (explicitly stated, not silently
dropped).
