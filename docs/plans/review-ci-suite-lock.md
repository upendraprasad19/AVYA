# Plan — review CI + one local full suite at a time (A + B)

Branch / worktree `review-ci-suite-lock`. Founder decision 2026-11-11 (chat): adopt **A** (CI provides the
full-suite leg of the §4.12.8 review gate loop) **+ B** (a machine-wide lock: one local full suite at a time),
and a **standing permission to push feature branches for review CI**.

Blast radius **platform** (CLAUDE.md, git hooks, `land_pr`). Execution mode (§4.12.7): **inline**, one worktree,
single writer. Type: `feat(process)`, not a bug fix, so no diagnose-doc.

## 1. Problem, measured (2026-11-11)

- The 4-core ARM VPS (Neoverse-N1, 1 thread per core, 24 GB) was at 0 % idle with load 9.6. `vmstat`: run queue
  3–7, `wa` 0, `si`/`so` 0 → **CPU-bound only**; RAM (15 GB available) is not a factor.
- The load was two concurrent `flutter test` runs from two sessions (each runs ~2 `flutter_tester` at ~90 % CPU
  plus a `frontend_server`).
- Local full suite wall time, from the sessions' own logs: **76:52 → 116:28 min** over 11 runs (2026-11-09..11),
  growing with the suite (13,667 → 14,121 tests). CI's 4 whole-file shards: **~16 min** (run of 2026-11-11 16:32–16:48).
- Five full local runs finished on 2026-11-11 alone (~9 h of the box), plus a sixth running.
- Cause in our process: CLAUDE.md §4.12.8 requires `flutter test` (the whole suite) before EVERY review dispatch,
  while §4.3 says "don't manually re-run the full suite, CI is the source of truth". §4.12.8 wins in practice, and
  nothing serialises two sessions' suites.
- Side finding (already handled in chat, not code): 49 orphaned `land_pr.dart 191` test-fixture processes from
  ~9 days earlier held 1.2 GB RSS + 2 GB swap; `SIGTERM` did not end them, `SIGKILL` did. This is why B must not let
  a suite's CHILD processes hold the lock (§3.2).

## 2. Scope

| Unit | What |
|---|---|
| A1 | `land_pr --ci-only`: the existing landing command stops after CI is green on the pushed head and never merges |
| A2 | Rule text: §4.12.8 (root + detail), §4.3 (root + detail), §0 test commands; the standing push permission |
| B1 | `scripts/_suite_lock.sh` (sourced helper) + `scripts/run_full_suite.sh` (the local full suite, locked) |
| B2 | The hooks' suite paths take the lock: `pre-push.sh` `run_full_suite()`, `pre-commit.sh` `PRE_COMMIT_FULL` / `PRE_COMMIT_LEGACY` |
| D  | hooks.md rows, memory `reference_vps_quirks` pointer, §5 checklist |

**Out of scope (decided, with reason):**
- A PreToolUse block on a raw `flutter test` full-suite command. `git_safety_hook.dart` is a command-string parser
  with three generations of parser bugs on record (its own header); a new detector re-opens that class for a
  convenience gate. A removes the main source of local full runs; the rules, the memory pointer and the hooks route
  the remaining ones through the lock. A session that types a bare full `flutter test` is not serialised: stated limit.
- Draft PRs. `land_pr` refuses a draft today; `--ci-only` keeps that precondition (open a normal PR). No change to
  `prRefusal`.
- Auto-creating the PR. The session opens it (`gh pr create`); `land_pr` already refuses a missing PR with a message.
- Targeted-but-heavy runs (e.g. 8 generator contract files) are not locked: only full-suite paths are.

## 3. Design

### 3.1 A1 — `sh scripts/land_pr.sh <pr> --ci-only`

`land_pr` already does, in order: preconditions (PR open, not draft, from this branch, base main, no fork, remote
tip an ancestor of HEAD, `.github/` edits need the flag), then per round: `sync_with_main.sh --commit`, push via
`safe_push.sh` when HEAD is not the remote tip, `_waitCi(head)` (the merge judge `classifyCheckRuns` +
`CiWatch`), fetch main / round again, PR-head check, record replay, `safe_pr_merge.sh`.

`--ci-only` changes exactly one thing: in `rounds()`, right after `_waitCi(head)` returns (green), it prints
`land_pr: CI is green on <sha>; --ci-only: stopping before the merge` and returns a new result
**`ci-green`, exit 0**. Everything before that point is unchanged (sync, push, CI wait, refusals, red/timeout
results). Nothing after it runs: no main-moved round, no PR-head check, no record replay, no merge.

- Why keep the sync: the review hash should be taken on a synced branch (merge-train lesson "sync BEFORE the
  review hash"); the PR's CI already tests the merge ref, so the sync changes no verdict, only makes the branch
  match what was tested.
- Files: `scripts/land_pr.dart` (`_Opts.ciOnly`, `_parse`, `rounds()`, header), `scripts/land_pr_lib.dart`
  (`resCiGreen`, `exitCodeByWord` gains `'ci-green': 0`), `scripts/land_pr.sh` (argument grammar:
  `<pr> [--allow-workflow-change] [--ci-only]`, each flag at most once, any order after the PR number; still
  forwards `"$@"` and no seam), `docs/plans/merge-train.md` §3.1 table (one appended row, dated, so the existing
  table pin keeps one row per word).
- `maxCliStatus` stays 7; the wrapper's `-gt 7` mapping is unchanged. **`ci-green` exits 0 like `merged`**: a
  caller MUST read the `result:` word, never chain on the status (stated in both headers, hooks.md and the CLAUDE.md
  row). Chaining is harmless in the one place it could matter: `retire_worktree.dart` refuses an unmerged branch.
- `_parse` refuses a repeated `--ci-only` / `--allow-workflow-change` ("given twice"); every usage text names both
  flags. The CLI still accepts a flag before the PR number (as today); the WRAPPER owns the strict grammar.
- Every "invoking it pushes AND merges" sentence gains the qualifier "(with `--ci-only`: pushes, never merges)":
  `land_pr.sh` / `land_pr.dart` headers, hooks.md "Landing a PR" row, CLAUDE.md §4.3 land_pr bullet,
  `docs/naming_conventions.md` result-word list (§4.7).
- Ordering inside a review round: commit the draft → `land_pr --ci-only` (which may add a sync merge commit) →
  dispatch the review on the HEAD that went green. The reviewer therefore sees the synced diff; nothing lands
  under a review in progress.
- **What `ci-green` means (round 2, P3-F):** CI ran on the PR merge ref GitHub computed when the run started;
  `--ci-only` returns before the main-moved check, so `ci-green` is a review gate, not merge-readiness (the landing
  run re-checks everything). The sync just before the push narrows the gap to the CI duration. Said in both headers
  and hooks.md.

### 3.2 B1 — `scripts/_suite_lock.sh` + `scripts/run_full_suite.sh`

`_suite_lock.sh` (sourced only; the `case "$0"` execution guard, exit 64, like `_git_lock.sh` / `_dart_bin.sh`)
defines:

- `suite_lock_acquire`: lock file `$(git rev-parse --path-format=absolute --git-common-dir)/avya_full_suite.lock`,
  shared by every worktree of the clone (the VPS has one clone). Steps: resolve the dir; if not in a git repo, or
  `flock` is not on PATH, or the lock file cannot be opened for append (`( : >>"$f" ) 2>/dev/null` pre-check), print
  `[suite-lock] WARNING: … running WITHOUT the lock` to stderr and return 0 (**fail open**: the lock is an
  efficiency measure; a missing tool must never block a push or commit). Otherwise `command exec 9>>"$f"`
  (`command` keeps a redirection failure from ending a POSIX shell), then `flock -n 9`; when held, print once
  `[suite-lock] another full suite holds the lock (<holder line>); waiting — one local full suite at a time` and
  block in `flock 9`; a non-zero `flock` = warn + run unlocked. On acquire, write `pid=<$$> since=<date> dir=<PWD>`
  to `<lock>.holder` (informational only; never read for a decision; never cleared, so the wait message calls it
  "last recorded holder" — a waiter can lose the race before the new holder writes it, round 2 P3-G).
- **Two modes.** `suite_lock_acquire` (no argument) WAITS — for `run_full_suite.sh`, which is meant to run in the
  background (a 77–116 min job never fits a 10-min foreground call). `suite_lock_acquire --no-wait` (the hooks) never
  waits: when the lock is held it prints the holder and `another local full suite is running; retry when it ends`
  and returns 1, and the hook exits 1. Reason (round 1, P1-2): the hooks run inside `safe_commit`/`safe_push`'s
  git lock (`safe_push.sh:62-63`, `safe_commit.sh:40-41`), which other callers do not wait for, so a hook that
  waited ~100 min would refuse every other primary-folder commit/push meanwhile (and an idle push risks the SIGPIPE
  class in `feedback_git_landing_verification.md`).
- **Nesting marker** (round 1, P1-1). `run_full_suite.sh` exports `AVYA_SUITE_LOCK_HELD=1` to its suite;
  `suite_lock_acquire` returns 0 at once, silently, when it is `1`. Two existing tests run the REAL hooks in the
  REAL repo on the locked paths with a stub `flutter`
  (`pre_commit_lean_path_e2e_test.dart:133-155` with `PRE_COMMIT_FULL=1`/`PRE_COMMIT_LEGACY=1`;
  `pre_push_analyze_always_e2e_test.dart:116-143` with `PRE_PUSH_FULL=1`): inside a suite started by
  `run_full_suite.sh` they would otherwise block on the lock their own suite holds. Both tests ALSO set the marker
  in their spawn env, so they never touch the real lock however the outer suite was started (CI shards, a bare
  `flutter test`). Also the hatch for a case the lock mis-handles: `AVYA_SUITE_LOCK_HELD=1 <command>`.
- **Marker classification (round 2, P1-A): STRIPPED.** Add the exact name to `childEnvStrippedNames`
  (`scripts/regression_catalog_lib.dart:88`, precedent `AVYA_DART_RUN_RETRY`) and to `_stripped` in
  `test/contracts/spawn_env_manifest_test.dart:47` (the "lib lists equal manifest" pin), plus (optional hardening) the literal lists in
  `test/contracts/spawn_helper_test.dart:30` / `regression_catalog_lib_test.dart:243` where they enumerate stripped names. Reason:
  a suite started by `run_full_suite.sh` carries the marker; the NEW lock tests spawn `run_full_suite.sh` /
  `suite_lock_acquire` and must not inherit it, or they would skip `flock` and go red on exactly the intended path.
  The two real-hook e2e tests pass it on purpose through `allowControl` (`_setOnPurpose` at
  `pre_push_analyze_always_e2e_test.dart:66`; the `allowControl` const at `pre_commit_lean_path_e2e_test.dart:122`),
  since `hermeticEnvironment` throws for a stripped name in `extra` without it — set UNCONDITIONALLY in both tests'
  `runHook` env, not only on the `*_FULL` cases (round 3: a non-full pre-push case in the real repo can still reach
  `run_full_suite` through the tier or a fail-safe). The NEW lock tests that pass the marker (B-T8) declare
  `allowControl` too. The shell scan's builtin set must stay exactly `{PWD}` (`spawn_env_manifest_test.dart:91`):
  the new scripts read no `$HOME`/`$USER`/`$PATH`/`$IFS`. Every shell local in the two new
  scripts is assigned before it is read (the shell scan flags an unassigned `$name`).
- `suite_lock_release`: `exec 9>&-` (a no-op when nothing was opened).
- **The fd must not reach the suite's children.** Callers append `9>&-` to the test command, so `flutter`,
  `frontend_server` and `flutter_tester` never inherit fd 9. The lock is then held only by the calling shell and is
  released by the kernel when that shell exits or is killed (flock semantics) — an orphaned test child cannot
  hold it (the §1 side finding is exactly that shape). Proven by test B-T4.
- Why `flock` and not the `mkdir` scheme of `_git_lock.sh`: `flock` has no stale-lock reclaim problem (released on
  process death), which is what made `_git_lock.sh` 331 lines and OI-92 ("a lock file has no safe reclaim").
  Windows Git Bash / macOS without `flock`: fail open with the warning (stated limit; the contention problem is
  the VPS).
- **Stated limit — SIGKILL of the holder** (round 1, P2-7): if the holding SHELL is SIGKILLed, the kernel releases
  the lock while its `flutter` tree may keep running, so the next suite can overlap it. A plain TERM/INT/HUP to the
  shell's process group stops `flutter` too. Letting the children hold fd 9 would instead let ANY orphan (the §1
  `land_pr` fixtures were descendants of a test run) hold the lock for days — the worse failure, so `9>&-` stays.

`run_full_suite.sh` (executable script, no arguments; any argument → usage, exit 2): resolves the repo top from its
own location, `cd`s there, sources `_suite_lock.sh`, `suite_lock_acquire || exit 1` (waiting; every fail-open path
returns 0, so the check costs nothing and makes a wrong non-zero visible — round 2 P2-C), then runs exactly
`AVYA_SUITE_LOCK_HELD=1 TZ=Asia/Kolkata flutter test test/ --exclude-tags golden 9>&-` and exits with its status.
Prints the start and the end with wall time. Both new scripts get `docs/blast_radius.yaml` entries (platform,
like the other hook helpers).

### 3.3 B2 — the hooks

- `pre-push.sh`: source `_suite_lock.sh` with the same guard shape it uses for `_dart_bin.sh` (readable + `sh -n`,
  else define no-op `suite_lock_acquire() { :; }` / `suite_lock_release() { :; }` and print nothing — an old tree
  without the helper keeps today's behaviour). `run_full_suite()` runs `suite_lock_acquire --no-wait || exit 1`
  before its unchanged invocation line, which gains only the trailing `9>&-`:
  `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden 9>&-`. The `flutter()` env-stripping function is still
  the thing called (no `env` prefix).
- `pre-commit.sh`: same guarded source; `PRE_COMMIT_FULL=1` → `suite_lock_acquire --no-wait || exit 1`,
  `flutter test 9>&-`, `suite_lock_release`; `PRE_COMMIT_LEGACY=1` → same around `flutter test test/contracts/ 9>&-`. Analyze stays
  outside the lock (it is ~3 min and not the problem).
- No deadlock: the hooks never wait (`--no-wait`); `run_full_suite.sh` waits but holds nothing else; a hook
  running inside a `run_full_suite.sh` suite sees the marker and skips; the two real-hook e2e tests set the marker;
  every NEW test uses a throwaway git repo, so its lock file is in that repo's git dir.
- `check_hooks_installed.dart` compares installed hook content, so every checkout reports stale hooks until
  `setup-hooks.sh` is re-run from the primary after the merge (planned in §5).
- After the merge: `sh scripts/setup-hooks.sh` from the primary (hooks are read-only copies; memory
  `reference_git_hooks_and_stop_hook_traps_class`).

### 3.4 A2 — rule text (root CLAUDE.md stays within its budget: replace, do not append)

- **§4.12.8 (root):** the loop is `flutter analyze --no-fatal-infos` (whole project) + the pre-commit gate loop
  LOCALLY, and the full `flutter test` from **CI**: commit the draft, open the branch's PR (not a draft),
  `sh scripts/land_pr.sh <pr> --ci-only`, dispatch only on `result: ci-green`. A local full suite only via
  `sh scripts/run_full_suite.sh`. Keep "never a hand-picked subset".
- **§4.3 (root):** "Never commit or push unless explicitly asked" gains: *except, for review CI (§4.12.8), committing
  on the session's feature branch, opening its PR and pushing it: standing founder permission 2026-11-11 (the
  founder granted "push feature branches for review CI"; CI runs only for a PR, so the commit and the PR are the
  same act); never `main`/`develop`, never a merge*. "Batch commits; push once per logical batch" gains: *review-CI
  pushes are exempt (each new push supersedes the PR's previous run: `test.yml:17-19`)*. The "Don't manually re-run the full
  `flutter test`" bullet becomes consistent with §4.12.8 (CI is the full-suite source; a local run only through
  `run_full_suite.sh`).
- **§0:** the `flutter test` line notes `sh scripts/run_full_suite.sh` for a local full suite.
- **§4.12.6 M tier:** "flutter analyze lib/ before every reviewer dispatch" → "the §4.12.8 loop before every
  reviewer dispatch" (the two already disagreed on analyze scope; round 1, item 9).
- **Catastrophic tier exception:** `check_code_review_pass_exists.dart` (header :5-9) blocks the COMMIT of a
  catastrophic diff until a review of the STAGED diff exists, so CI cannot run before that review. A catastrophic
  batch takes its pre-review full suite locally via `run_full_suite.sh`. Stated in §4.12.8 and in
  `.claude/skills/code-review/SKILL.md` §3 step 0 (which assumes a staged diff).
- **detail doc** `process-invariants-detail.md` §4.3 + §4.12.8: the same change with the §1 measurements and the
  history line ("the full suite ran locally before every review dispatch until 2026-11-11 …").
- **hooks.md:** a row for the suite lock (what, why, fail-open, fd rule, tests) and the `--ci-only` mode in the
  "Landing a PR" row (flow, result word, exit table).
- **memory:** `reference_vps_quirks` → "full suite: `sh scripts/run_full_suite.sh`; review rounds: `land_pr --ci-only`".
- Re-read for contradictions and edit where they instruct a local full suite before review:
  `process-invariants-detail.md` :89, :116 and the §4.12.8 block (:300-308); hooks.md :118 and the pre-push row.

**Stated limits (round 1, item 10; round 2, P2-B):** not serialised — a bare `flutter test` typed by a session (only
the rules and the memory pointer stand against it), `flutter analyze` (~3 min), the pre-push `contract_sweep`
targeted run, and `/build-apk` Gate 5 (`.claude/commands/build-apk.md:192-196`, a bare `flutter test`). Gate 5 stays
as is on purpose: it is a release gate that today also runs the goldens (no tag filter) on the founder's machine,
routing it through `run_full_suite.sh` would silently drop them, and the normal path `--from-green` skips Gate 5.
The bare `flutter test` lines in CLAUDE.md §0 (:29) and hooks.md (:435, verbatim history) are re-read: §0 gets the
`run_full_suite.sh` note; the history block stays verbatim.
Goal 1 for hand-typed runs is met by compliance, not by a mechanism (see §2 out-of-scope for why no PreToolUse block).

## 4. Tests (each mutated once, §4.4 rule 21)

| # | Test | Mutation that must redden it |
|---|---|---|
| A-T1 | `land_pr_e2e_test`: `--ci-only`, CI green → `result: ci-green`, exit 0; calls end at `gh check-runs` (no `pr-head`, `gate`, `merge`, `pr-state`) | delete the `ciOnly` return → it merges |
| A-T2 | `--ci-only` with a red required job → `ci-failed`, exit 3 (the flag changes nothing before green) | return `ci-green` before `_waitCi` |
| A-T3 | `--ci-only` with an unpushed commit → pushed, CI read for the PUSHED head, then `ci-green` | — (behaviour reuse; covered by the mutation of A-T1) |
| A-T4 | `land_pr_wrapper_e2e_test`: accepts `<pr> --ci-only`, `<pr> --ci-only --allow-workflow-change` and the reverse order, forwards them; refuses a repeated flag, an unknown one, a flag first, four args | drop `--ci-only` from the wrapper grammar |
| A-T5 | `land_pr_lib_test`: `resCiGreen` agrees with `exitCodeByWord` (now 10 words) | — (table consistency) |
| B-T1 | new `test/scripts/suite_lock_e2e_test.dart` (throwaway git repo, stub `flutter` on PATH, `run_full_suite.sh` + `_suite_lock.sh` copied into it): two concurrent runs do NOT overlap (stub writes start/end stamps; second prints the waiting line) | remove the `flock` call |
| B-T2 | the stub sees argv `test test/ --exclude-tags golden` and `TZ=Asia/Kolkata`; the stub's exit status 3 is the script's exit status | change the status passthrough |
| B-T3 | no `flock` on PATH (a PATH of symlinks without it) → the warning, the suite still runs, exit = stub status | make the missing-flock branch `return 1` |
| B-T4 | kill -9 the holder SHELL while its stub child keeps running → a second run acquires within seconds (fd 9 not inherited, released on death) | drop the `9>&-` in `run_full_suite.sh` → the second run waits on the orphan |
| B-T5 | executing `_suite_lock.sh` directly exits 64 with the "must be SOURCED" text | delete the guard |
| B-T6 | `pre_push_matches_ci_invocation_test`: still matches CI; plus `run_full_suite.sh`'s invocation also matches CI (TZ + tag filter); plus in pre-push `run_full_suite()` the `suite_lock_acquire` call precedes the invocation | move the acquire below the invocation |
| B-T7 | pre-commit: `PRE_COMMIT_FULL` and `PRE_COMMIT_LEGACY` branches call `suite_lock_acquire --no-wait` before their `flutter test … 9>&-` (source pin, plus the existing `pre_commit_lean_path_e2e_test` keeps passing with the marker set) | delete one acquire |
| B-T8 | `--no-wait` with the lock held (the test holds it via `flock` in a throwaway repo) → returns 1 within a second and prints the holder; the waiting mode with the marker `AVYA_SUITE_LOCK_HELD=1` → returns 0 at once without touching the lock | make `--no-wait` block / drop the marker check |
| B-T9 | `run_full_suite.sh` exports the marker to the suite (stub sees `AVYA_SUITE_LOCK_HELD=1`); the two real-hook e2e tests pass it in their spawn env (source pin) | remove the export |
| B-T10 | a hook (pre-push via `PRE_PUSH_FULL=1` in a throwaway repo) with a syntactically BROKEN `_suite_lock.sh` still runs the suite with the no-op functions (`pre-push.sh:66-80` records a corrupt helper once wedging commit/push/merge) | remove the `sh -n` guard |
| A-T6 | `_parse` refuses `--ci-only` given twice (`refused`, exit 2, names the flag) | drop the once-check |

Dash and bash: B-T1..B-T4 run the script under `sh` (dash on the VPS, the hooks' shell); B-T1 also under `bash`.
File-level `@Timeout` + `library;`, per-call `.timeout()` (pitfall: subprocess tests in the full suite); spawns via
`test/helpers/spawn.dart` `runSpawn(why:)` / `startSpawn` (spawn_sites_guard_test).
Robustness (round 2, P3-E): B-T1 launches the second run only after the first run's start stamp exists and asserts
stamp ORDER (end₁ ≤ start₂), not wall time. B-T4 uses `startSpawn` + a stub pid file, a short stub sleep, kills the
stub in `tearDown` (never leave the §1 orphan class behind), and in its mutated form the second run would wait for
ever, so the call carries a `.timeout()`. B-T8 holds the lock with `flock <file> sleep N` in the throwaway repo.

Known pins to update (round 1, item 5): `land_pr_lib_test.dart:120,124` (constant list, length 9→10);
`land_pr_source_pins_test.dart:35` (wrapper grammar literal), `:39-40` (exactly two `echo "result: ` in the
wrapper — the new grammar refuses only through `refuse()`), `:153-165` (merge-train.md row `| 0 | \`ci-green\` |`),
`:183-190` (hooks.md section carries `` `ci-green` ``); `land_pr_wrapper_e2e_test.dart:41-77` (arg table,
`wrapperOwned`, a forwarding case); the usage literals at `land_pr.dart:138,143,146` and the refusal case at
`land_pr_e2e_test.dart:552` (they assert no flag list, so updating the literals is enough). The CI invocation the
pre-push pin compares against is now the shard line (`test.yml:182`), not `:112`.

## 5. Gate loop and review (this batch)

- Before each review dispatch with a diff: `flutter analyze --no-fatal-infos`, the pre-commit gate loop, targeted
  tests (`land_pr_*`, `suite_lock_e2e`, `pre_push_*`, `hook_gate_placement`), and the full suite **from CI via the
  new `land_pr --ci-only`** once A1 exists on the branch (the founder's decision covers this batch; running a
  100-min local suite here would be the very load this batch removes).
- Plan review ×2 (context-blind Sonnet, sequential: #2 on the post-#1 plan), B-pass (`/code-review`) before merge,
  record `docs/plan-reviews/review-ci-suite-lock.md`, land with `sh scripts/land_pr.sh <pr>`.
- After the merge: `setup-hooks.sh` from the primary, retire the worktree.

## 6. Review round 1 (context-blind, Sonnet) — verdict `harden`, all items resolved above

P1-1 nested deadlock → marker + both e2e tests set it (§3.2). P1-2 hook wait inside the git lock → hooks `--no-wait`
(§3.2/3.3). P2-3 unbounded wait → waiting mode is for background use only, hooks never wait. P2-4 `ci-green` = exit
0, headers that say "merges", repeated flags, usage text, sync-commit ordering → §3.1. P2-5 pins → §4 list. P2-6
blast_radius.yaml entries, `runSpawn(why:)`, env manifest → §3.2/§4. P2-7 SIGKILL orphan → stated limit with the
reason the alternative is worse. P3-8 commit + PR + push all needed; batch-push bullet → §3.4. P3-9 other texts,
M tier, catastrophic exception, code-review skill step 0 → §3.4. P3-10 unserialised work → stated limits.
Verified by the reviewer: `flock` at `/usr/bin/flock`; `command exec 9>>f` failing leaves dash and bash running;
`fn 9>&-` closes fd 9 for the function's external child; no other `9>` in `scripts/*.sh`; CI runs on
`pull_request` into main (`test.yml:6`).

## 7. Review round 2 (context-blind, Sonnet, on the post-round-1 plan) — verdict `harden`, all items resolved above

Verified correct by the reviewer (dash + bash experiments): `--no-wait || exit 1` under `set -e` inside a function
with `flutter()` shadowed; the second hook gets rc 1 while the first holds the lock; the stub child sees no fd 9;
only two tests run a real hook in the real repo with a helper present (the rest fall back to the no-op in temp
repos); hook exit 1 maps to safe_push FAILED, and safe_commit / sync / land_pr never reach a suite path; the
catastrophic exception (`check_code_review_pass_exists.dart:5-9`, record job main-push only `test.yml:421-423`);
the pin regex accepts both new invocation lines; the prefix-assigned marker reaches only the `flutter` child.
New and resolved: P1-A marker classification (stripped + allowControl) → §3.2; P2-B `/build-apk` Gate 5 → stated
limit with reason; P2-C runner checks the acquire status → §3.2; P2-D corrupt-helper fallback → B-T10; P3-E test
robustness → §4; P3-F `ci-green` meaning → §3.1; P3-G holder file wording → §3.2; extra pins → §4.

## 8. Review round 3 (context-blind, Sonnet, on the post-round-2 plan) — verdict `converged`

No P0-P2. Verified: P1-A shape (stripped + allowControl) and the four manifest requirements (in `_stripped`, equal to
`childEnvStrippedNames`' un-prefixed exact names, found by the `scripts/*.sh` scan, builtins exactly `{PWD}`); the
runtime path run_full_suite → flutter test → real hook has no deadlock (only the two e2e tests run a real hook in the
real repo, both set the marker; every spawn strips it); the `/build-apk` Gate 5 limit is accurate (`build-apk.md:192-196`
bare, `:38`/`:458` `--from-green` skips it). Three P3s folded into §3.2 (file paths, allowControl in new tests, the
marker unconditional in both e2e `runHook`s).

## 9. Rollback

`git revert` of the merge. The hooks fall back to no-op locking when the helper is absent; `--ci-only` is opt-in.
