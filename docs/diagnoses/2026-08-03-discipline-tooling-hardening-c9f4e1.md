---
bug_id: c9f4e1
date: 2026-08-03
batch: discipline-tooling-hardening (Unit 3 of the 4-unit batch that succeeded terms-accepted-fix, 2026-08-03)
status: fixed
blast_radius: platform
symptom: >
  Two independent, real (not hypothetical) gaps in the git-safety tooling
  that CLAUDE.md §4.3 already relies on. (1) A 2026-08-03 near-miss during
  the terms-accepted-fix backfill follow-up: a foreground safe_commit.sh
  attempt timed out; the liveness check used to decide "safe to retry" was a
  `ps aux | grep` for a process NAME, which sampled a real gap between two
  short-lived subprocess spawns inside the pre-commit hook's bounded-parallel
  gate loop, concluded attempt 1 was dead, and started attempt 2 while
  attempt 1 was still running. Both committed concurrently; benign only
  because both had staged byte-identical content — a process-name sample is
  not proof of death, and neither safe_commit.sh nor safe_push.sh had any
  actual mutual-exclusion mechanism. (2) Reading
  scripts/check_plan_review_record_exists.dart in full (not trusting a
  subagent summary) surfaced its own header already documents a live,
  numbered gap: OI-58b's "one-record-one-landing" design (a branch re-landing
  at >=account must show its review record was actually re-touched, not
  reused verbatim from the first landing) was independently reviewed and
  bpass-accepted in docs/plan-reviews/gate-input-family.md, then split into
  its own unit alongside OI-58a and never implemented — the CURRENT gate code
  explicitly comments "is NOT enforced here." Separately, the merge-into-main
  step itself had no wrapper at all: git_safety_hook.dart actively denies a
  raw `git commit`/`git push` that bypasses safe_commit.sh/safe_push.sh, but
  verified by reading the file directly that it has NO clause for `git merge`
  whatsoever — not a recognized exemption, an absence of any check — so
  nothing ever verified local main was caught up with origin/main before a
  `git merge --no-ff` in primary.
concept: git_safety_tooling
sot_registry_entry: not_applicable — this batch adds process/tooling safety
  infrastructure (a lock helper, a gate NOTE, a new wrapper script), not a
  Hive/cloud data concept the SoT registry tracks.
writers: >
  New file scripts/_git_lock.sh (git_lock_acquire / git_lock_release) —
  sourced, not a writer of application data. Modified
  scripts/safe_commit.sh and scripts/safe_push.sh to acquire the lock around
  their git-mutating sections. New file scripts/safe_merge.sh — the first
  wrapper for the merge-into-main step, fetches origin/main and refuses to
  merge when local main is behind it. Modified
  scripts/check_plan_review_record_exists.dart to add
  _checkOneRecordOneLanding, called from the merge-processing loop.
readers: >
  Not applicable in the Hive/cloud sense — these are process-safety scripts
  invoked by the agent (and, for check_plan_review_record_exists.dart, by
  CI) directly, not application data with UI/service consumers.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable — no Hive or cloud sync touched.
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: >
  test/contracts/git_lock_concurrency_test.dart (3a — real concurrent
  processes, not mocked timing; 5 tests after round-2's fix round, see
  below),
  test/scripts/plan_review_record_gate_e2e_test.dart (3b — 3 new tests
  appended to the existing E2E suite for this gate),
  test/scripts/safe_merge_test.dart (3c — real bare-remote + clone E2E,
  including the seeded-stale-origin scenario and, after round-2, the
  multi-word -m passthrough),
  test/scripts/safe_push_test.dart (NEW in round-2's fix round — safe_push.sh
  had zero prior coverage; this pins only the EXTRA_ARGS fix that batch
  actually changed there, not the pre-existing SSH-keepalive/retry logic).
ist_handling: not_applicable — no date-key or timestamp business logic
  touched. (_git_lock.sh's holder timestamp is UTC diagnostic metadata for a
  human to sanity-check a suspiciously old lock, not a date key.)
provider_invalidations: not_applicable — no Riverpod provider touched.
telemetry_op_types: >
  None added. This is local/CI tooling, not an in-app code path with
  ErrorTelemetry instrumentation.
cross_account_guard: not_applicable — no Hive user-scoped box touched.
forbidden_patterns_checked: >
  - Container(color:+decoration:) — n/a, no widget touched.
  - unawaited() without an error sink — n/a, no Dart async fire-and-forget
    introduced; the shell lock is synchronous mkdir/trap.
  - .functions.invoke without FunctionException handling — n/a.
  - Source-grep without stripping comments — n/a, no new source-grep test;
    3a/3c tests drive real subprocesses and assert exit codes + stdout
    content, 3b's tests drive the real gate against real merge commits.
  - BuildContext across an async gap — n/a, no Flutter widget code touched.
proposed_fix: >
  3a: scripts/_git_lock.sh — a lock keyed on
  `$(git rev-parse --git-dir)/.safe_git_op.lock` (deliberately --git-dir, not
  --show-toplevel + /.git — a worktree's .git is a plaintext file, a claim
  attempt inside it fails outright). Records holder PID + op + UTC
  timestamp; on contention, checks the recorded PID's liveness via `kill -0`
  (empirically verified correct in this repo's actual Git-Bash-on-Windows
  environment before relying on it) and refuses rather than races if alive,
  or refuses if dead. Released automatically via an EXIT/HUP/INT/TERM trap.
  Wired into safe_commit.sh and safe_push.sh around their git-mutating
  sections. **Claim mechanism rewritten in round-2's fix round** (see the
  Round-2 review section below): the original design claimed the lock via
  `mkdir`, then wrote holder metadata in a SEPARATE later step. Round-2
  review reproduced live that a holder delayed between those two steps
  could have its lock reclaimed as stale by a second process, and the
  delayed holder's own later write — targeting a path, not the specific
  directory instance its own mkdir created — would then silently clobber
  the reclaimer's holder file. Replaced with a private-candidate-then-
  atomic-`mv -T`-publish design: full holder content is prepared in a
  uniquely-named (PID-suffixed) private directory first, then published to
  the canonical lock path in ONE atomic `rename()` (GNU coreutils
  `mv -T`/--no-target-directory, confirmed present in this repo's
  Git-for-Windows toolchain) — which either fully succeeds (content already
  complete, no visible partial state) or fully fails with both sides
  untouched. Verified empirically under genuine concurrent contention (not
  assumed) before relying on it: 5 parallel processes racing `mv -T` against
  an already-populated target, and separately against a fresh (no target)
  path, each produced exactly 1 winner and clean, content-intact losers. The
  exact round-2 cascade (a slow holder racing an on-time one) was then
  reproduced live against the OLD code and confirmed NOT to reproduce
  against the new code, using the same injected-delay technique the
  reviewer used. **Round-3 review found the reclaim branch had the SAME
  check-then-act shape, one step over**, and its two-layer fix (an age gate
  plus steal-verify-restore) then failed ROUND 4 on the same shape again --
  `mv -T`'s restore FAILS into a non-empty destination while the following
  `rm -rf` ran unconditionally, so a third process claiming the
  momentarily-emptied path caused a stolen LIVE lock to be destroyed and two
  processes to hold the mutex. **The automatic reclaim was therefore REMOVED
  ENTIRELY, not patched a fourth time** (OI-92, founder-ratified 2026-08-05):
  a lock whose holder PID is dead is REFUSED, printing the manual `rm -rf`
  the script already emitted. No correct auto-reclaim exists with the
  primitives on this stack -- `flock` is absent, and `mv -T` is
  fail-if-present for directories but replace-unconditionally for files, so
  "remove THEIR lock and install MINE" cannot be expressed atomically. The
  full round-4 finding, the reproduction, and why round 3's explicit
  acceptance of this residual was wrong are in the Round-4 section below.
  The trap gained HUP at the same time, so a closed terminal no longer leaks
  a lock -- which matters more now that a stale lock is a manual clear.
  3b: _checkOneRecordOneLanding in check_plan_review_record_exists.dart —
  walks main's first-parent history strictly before the current merge for
  the most recent EARLIER merge of the same raw branch name (restricted to
  MergeSubjectKind.branchMerge/pullRequestMerge — conservative on purpose,
  a missed NOTE costs less than a wrong one). If found, compares the review
  record's blob byte-for-byte between the two landings; byte-identical means
  nothing shows the new diff was reviewed. Ships as an unconditional
  stdout NOTE (never routed through fail()) so real-world behavior can be
  observed before anything here can block a merge — promoting it to a hard
  failure is an explicit follow-up once that baseline exists (CLAUDE.md
  §4.11), not bundled into this landing.
  3c: scripts/safe_merge.sh <branch> — confirms it is running from PRIMARY
  using the SAME two git invocations as check_commit_from_worktree.dart
  (--git-dir vs --git-common-dir, both --path-format=absolute) AND the SAME
  normalization before comparing (lowercase + backslash-to-slash + strip
  trailing slash — a shell port of that file's _norm(), not a raw string
  compare). Correction after round-1 review (finding #12): an earlier draft
  claimed this "mirrors exactly" while actually doing an un-normalized
  string compare, true only by coincidence on this machine's paths — fixed
  in the script itself, not just this doc. One deliberate divergence,
  stated rather than silently copied: on an unresolvable git-dir the Dart
  gate fails OPEN (never wedge a routine commit on a git hiccup) but this
  script fails CLOSED (refuses to merge) — landing on main is high-stakes
  enough to warrant the stricter default. Acquires the 3a lock,
  confirms the current branch is main, unconditionally `git fetch origin
  main`, refuses loudly if local main is behind the freshly-fetched
  origin/main, only then `git merge --no-ff`, and verifies HEAD actually
  advanced before reporting success (same masked-exit-code discipline as
  safe_commit.sh/safe_push.sh). Also accepts extra `git merge` args (e.g.
  `-m "<subject>"`, needed for this repo's dominant merge-subject
  convention). **Round-2 review blocking #2**: the FIRST version of this
  passthrough collapsed extra args into one string (`EXTRA_ARGS="$*"`) and
  re-expanded it UNQUOTED at the call site, which word-splits a multi-word
  `-m` message into separate argv tokens — reproduced live by the reviewer,
  git failed outright ("branch - not something we can merge"), and none of
  this script's own tests exercised the path. Fixed by keeping extra args
  as real, separate positional parameters (`shift` then `"$@"`) instead of
  flattening and re-splitting them. `safe_push.sh` had the identical latent
  pattern (same `EXTRA_ARGS="$*"`) for its own extra-args passthrough —
  fixed the same way, same commit, even though its typical single-token
  extra args (`-u`, `--force-with-lease`, `--tags`) never triggered it in
  practice.
regression_test_planned: >
  All sub-units are covered by tests that exercise REAL subprocesses against
  REAL throwaway git repos, not mocked timing or pure-function
  approximations of concurrency:
  git_lock_concurrency_test.dart (7 tests after round-3's fix round) spawns
  a real holder process, polls a readiness marker (not a fixed sleep),
  asserts a contended second attempt refuses while the holder is alive,
  asserts the lock is reusable once released, and separately asserts a lock
  left by a genuinely-dead PID (spawned, awaited to exit, never a guessed
  magic number) is REFUSED, never auto-reclaimed, and prints the manual clear
  command (INVERTED by OI-92 -- it previously asserted the lock was reclaimed;
  it now also asserts `isNot(contains('Reclaiming stale lock'))`, so re-adding
  the takeover path fails a test rather than passing silently); asserts release
  does not remove a lock it no
  longer owns (round-1 finding #1); directly tests the underlying `mv -T`
  primitive's exactly-one-winner property under 5-way concurrent contention
  against a pre-existing empty target; reproduces the round-2 reviewer's
  EXACT cascade attack (a delayed-publish variant of the real script racing
  a normal instance, built via a targeted string-replace on the actual
  production file so the test tracks real code rather than a copy that
  could drift) and asserts it no longer succeeds. TWO TESTS WERE DELETED BY
  OI-92 -- the round-3 steal-verify-restore cascade repro and the age-floor
  test -- because the reclaim they exercised no longer exists on any path;
  both asserted a string the script no longer emits, so keeping them green
  would have meant re-adding the removed machinery. Their real guarantee
  (nobody silently re-adds a takeover path) is carried by the inverted test
  above, negative-controlled by execution: a naive re-added reclaim makes ONLY
  that test fail, the other four still pass. (The round-1 fix-round's
  original TOCTOU-pause test, which asserted a timing floor before a
  stale-reclaim verdict, was retired rather than patched: the round-2
  redesign eliminates the read-then-decide step that test was pinning, so
  asserting a "pause" no longer describes real code — its replacement tests
  the actual current safety property instead.)
  plan_review_record_gate_e2e_test.dart's 3 new tests land the SAME branch
  name twice in a scratch repo: an unchanged-record re-landing prints the
  advisory NOTE without blocking (exit 0), an updated-record re-landing does
  not print it, and a brand-new branch's first landing never does either.
  safe_merge_test.dart builds a real bare "remote" + primary clone, has a
  THIRD independent clone push directly to the remote (simulating another
  session), and asserts safe_merge.sh refuses with HEAD unmoved when local
  main is behind; a follow-up test catches primary up for real and asserts a
  genuine --no-ff merge (two parents) succeeds; further tests assert refusal
  from a non-main branch and from a linked worktree; and (added in round-2's
  fix round) a multi-word -m message survives as one argument and lands as
  the exact commit subject, not shredded into unresolvable extra merge
  targets.
  safe_push_test.dart (NEW, round-2's fix round) builds the same kind of
  bare-remote + clone harness and proves a multi-word `-o` push option
  survives as ONE opaque value by capturing what the remote's pre-receive
  hook actually received (GIT_PUSH_OPTION_0/_COUNT env vars) — a
  server-side, not just exit-code, verification.
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "No lib/ file touched — this batch is entirely scripts/ tooling." }
  - { tier: 2_hive, status: not_applicable, evidence: "No Hive box touched." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "No data touched." }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "No supabase/functions/ file touched." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9_storage, status: not_applicable, evidence: "No bucket touched." }
  - { tier: 10_secrets, status: not_applicable, evidence: "No secret touched." }
  - { tier: 11_external_services, status: not_applicable, evidence: "No external service touched." }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "The client-server contract here is agent<->git/CI, not app<->Supabase: safe_commit.sh/safe_push.sh/safe_merge.sh now share one lock so two overlapping git-mutating invocations cannot race; check_plan_review_record_exists.dart's merge-loop now also surfaces (informationally) when a branch's review record was reused unmodified across two landings. Verified by running each new/changed script's own E2E test suite against real subprocesses (see regression_test_planned), not by reading the code alone." }
impact_analysis: >
  Zero behavior change on the paths already in normal use today — the lock
  is uncontended in the overwhelmingly common single-attempt case (adds one
  mkdir + one rmdir), and the one-record-one-landing check is a pure NOTE
  that cannot fail a build. What it closes: the EXACT race class that
  produced a real (if benign) near-miss on 2026-08-03, so a future retry
  after a genuine timeout can no longer double-commit even if both attempts
  stage DIFFERENT content; and a real blind spot where a branch name could
  be reused across two landings with the second silently riding the first
  review's record, which this batch's own review process could not have
  caught before this fix existed (the gate's own header already flagged it
  as a known, unimplemented design). safe_merge.sh additionally closes the
  one integration step (merge-into-main) that had no freshness check at all,
  unlike commit/push which safe_commit.sh/safe_push.sh already covered.
---

# c9f4e1 — Git-safety tooling hardening: concurrent-commit lock, one-record-one-landing advisory, safe_merge.sh

Unit 3 of the 4-unit batch that succeeded diagnose b3f9e7 (terms-accepted-fix, 2026-08-03).

## What was actually wrong

Three sub-gaps, all in the tooling this project's own §4.3/§4.12 process
invariants depend on to be trustworthy:

### 3a — safe_commit.sh / safe_push.sh had no mutual exclusion

A real 2026-08-03 incident (not hypothetical): a foreground `safe_commit.sh`
attempt timed out mid-run. The liveness check used to decide "is it safe to
retry" was a `ps aux | grep` for a process NAME — this sampled a genuine gap
between two short-lived subprocess spawns inside the pre-commit hook's own
bounded-parallel `check_*.dart` gate loop, concluded attempt 1 was dead, and
a second attempt started. Both ran concurrently. Attempt 1 won the race and
committed; attempt 2 correctly found nothing left to commit. Benign only
because both attempts had staged byte-identical content — a coincidence, not
a property the tooling guaranteed.

### 3b — check_plan_review_record_exists.dart's own documented gap

Reading [`scripts/check_plan_review_record_exists.dart`](scripts/check_plan_review_record_exists.dart)
in full (not trusting a subagent's summary of it) surfaced that its own
header comments already track this as OI-58b's deferred half:
[`check_plan_review_record_exists.dart:49-53`](scripts/check_plan_review_record_exists.dart:49)
says "Branch identity still comes from the merge SUBJECT... the residual
first-time spoof are NOT addressed here," and the merge-loop's own comment at
the call site (pre-fix) read "One-record-one-landing (OI-58b) is NOT enforced
here." Cross-referencing
[`docs/plan-reviews/gate-input-family.md:151-160`](docs/plan-reviews/gate-input-family.md:151)
found the design had ALREADY been independently reviewed and bpass-accepted
once (as part of a larger batch that was later split, per that same file's
own scope note at lines 14-20) — it was simply never implemented. This
batch's own Unit 3b plan had independently proposed a cruder trigger ("this
branch was reused at all"); finding the already-vetted, more precise design
("the record must have been *modified in this range*") sitting unimplemented
in the same file motivated shipping something closer to it than the original
cruder trigger. **Correction after round-1 review:** the FIRST draft of this
doc claimed the vetted design itself had shipped. It had not — the
implementation compares the record's blob at two point-in-time landings,
not whether the path was touched anywhere in the range, and does not check
the prior landing's own tier. Both the code's doc comment and this doc were
corrected in the same round rather than left overclaiming; see
`_checkOneRecordOneLanding`'s doc comment in
`scripts/check_plan_review_record_exists.dart` for the precise, honest
statement of what ships and its two known divergences from the vetted
design.

### 3c — the merge-into-main step had no wrapper at all

`safe_commit.sh` and `safe_push.sh` already guard commit/push, and
[`scripts/git_safety_hook.dart`](scripts/git_safety_hook.dart) actively
DENIES a raw `git commit`/`git push` that bypasses them. Verified by reading
that file directly: it has NO clause for `git merge` at all — not a
recognized-and-exempted integration op (the plan's own first framing), just
an absence of any check. A raw `git merge --no-ff <branch>` in primary has
always been unguarded, which is exactly the moment "is local main caught up
with origin/main" matters most.

## Related bugs

- The 2026-08-03 commit-race near-miss itself has no separate diagnose-doc —
  it was caught and handled correctly in the moment (no blind retry), and is
  the motivating incident this fix closes rather than a shipped bug.
- OI-58a (2026-07-28, same gate file) — the sibling half of the same
  originally-split unit; already implemented (the direct-commit
  version-bump-exemption logic in `check_plan_review_record_exists.dart`).
  This batch closes the other half.

## The fix

See `proposed_fix` above for the three sub-fixes. All three ship together as
one platform-tier unit because they share one theme (closing gaps in the
tooling that enforces §4.3/§4.12) and 3a's lock is a direct dependency of
3c (`safe_merge.sh` sources and uses the same `scripts/_git_lock.sh`).

## Verification

- `test/contracts/git_lock_concurrency_test.dart` — 7/7 passing. 2
  pre-existing; round-1 added release-ownership-on-impersonated-holder
  (finding #1); round-2 REPLACED round-1's TOCTOU-timing test with a direct
  test of the `mv -T` primitive's exactly-one-winner property (the original
  test's premise — a "pause before deciding" — no longer describes real
  code after the round-2 redesign, see below) and ADDED a live reproduction
  of the round-2 cascade attack against the current code, asserting it no
  longer succeeds; round-3 ADDED a live reproduction of the round-3 cascade
  attack (same technique, targeting the reclaim/steal line instead of the
  publish line) and a standalone test of the age-gate layer.
- `test/scripts/plan_review_record_gate_e2e_test.dart` — 8/8 passing
  (5 pre-existing + 3 new for Unit 3b).
- `test/scripts/safe_merge_test.dart` — 5/5 passing (4 pre-existing/round-1
  + 1 new in round-2: a multi-word `-m` message lands as the exact commit
  subject, not word-split).
- `test/scripts/safe_push_test.dart` — 1/1 passing. NEW in round-2:
  `safe_push.sh` had zero prior coverage; pins only the EXTRA_ARGS fix this
  batch actually made there (a multi-word `-o` push option survives intact,
  verified server-side via a pre-receive hook capturing what the remote
  actually received), not the file's pre-existing, unrelated SSH-keepalive/
  retry logic.
- `dart analyze` on every touched/new script — 0 issues (re-run after the
  round-3 fixes).

## Round-1 independent review (context-blind, per CLAUDE.md §4.12)

Verdict: NOT CONVERGED. 3 blocking findings, all fixed in this same round:

1. `git_lock_release` removed the lock directory unconditionally, with no
   check that it still belonged to the releasing process. Demonstrated
   cascade: a false-positive stale-reclaim by process B, followed by
   process A's (the original, still-legitimate holder) EXIT trap firing and
   deleting B's now-legitimate lock, let a third process acquire
   concurrently with B — the exact class of race this file exists to
   prevent, reintroduced one layer down. Fixed: release now compares the
   holder file's recorded `pid=` to `$$` before removing anything.
2. The lock's documented manual recovery (`rmdir "$LOCK_DIR"`) never works —
   `rmdir` only removes empty directories, and the lock dir always contains
   a `holder` file. Fixed: the message now prints `rm -rf`, the form that
   actually succeeds.
3. `scripts/_git_lock.sh` and `scripts/safe_merge.sh` graded `feature` tier
   in `docs/blast_radius.yaml`, three tiers below the `safe_commit.sh` /
   `safe_push.sh` wrappers that depend on the lock and are pinned
   `platform` — a future change gutting the lock alone would have cleared
   no review gate. Fixed: both added at `platform` tier alongside their
   siblings.

Should-fix findings also resolved in this round: a TOCTOU gap between
`mkdir` succeeding and the holder file being written (closed with a brief
re-read before declaring a lock stale); the one-record-one-landing
overclaim documented above; `safe_merge.sh`'s primary-detection comparison
now genuinely normalizes the same way `check_commit_from_worktree.dart`
does (it previously did a raw string compare while claiming equivalence);
`safe_merge.sh` gained `-m`/extra-args passthrough so it can actually
produce this repo's dominant merge-subject convention; CLAUDE.md §4.13 and
`check_commit_from_worktree.dart`'s own hint text now mention
`safe_merge.sh` (without hard-wiring `git_safety_hook.dart` to block a raw
merge — that remains a separate, explicitly-deferred founder decision, not
assumed here); two new lock tests cover release-ownership-checking and the
TOCTOU window; this doc's test-count and design-fidelity claims were
corrected. Full findings: round-1 review transcript (not committed
separately — summarized here per finding).

## Round-2 independent review (context-blind, per CLAUDE.md §4.12 — runs on the round-1-hardened diff)

Verdict: NOT CONVERGED. 2 blocking findings, both fixed by a genuine redesign
(not another narrow patch) in this same round:

1. **The round-1 TOCTOU fix narrowed but did not close the race; the round-1
   finding #1 cascade was still reachable, reproduced live end-to-end.** The
   round-1 fix added a brief re-read/sleep before the mkdir-then-separate-
   write design declared a holder-less lock stale. The reviewer calibrated
   the real mkdir-to-write gap on this machine at 61-89ms (just the `date`
   subprocess spawn) — already consuming up to nearly half of the 200ms
   budget with zero contention — then built a copy of `_git_lock.sh` with an
   injected 1.5s delay between mkdir and the write, ran it as process A
   concurrently with the real, unmodified script as process B, and captured
   the full cascade: B reclaimed A's (merely slow) lock as stale and
   acquired; ~1.2s later A's delayed write landed and silently overwrote B's
   holder file with A's identity; B's own release then read the (clobbered)
   file, saw a pid mismatch, and correctly-per-its-own-bookkeeping but
   incorrectly-per-reality refused to release the lock it had legitimately
   created — an orphaned, wrongly-attributed lock, both processes believing
   from their own local state that they exclusively held the mutex.
   **Fixed via a genuine redesign, not a narrower patch**: replaced the
   mkdir-then-separate-write claim mechanism with a private-candidate-then-
   atomic-`mv -T`-publish design (full detail in `proposed_fix` above and
   `scripts/_git_lock.sh`'s header). Before writing this fix, empirically
   verified the `mv -T` primitive itself under genuine concurrent contention
   — 5-way races against both a fresh path and an already-populated one,
   each producing exactly 1 winner and clean, content-intact losers — then
   reproduced the reviewer's EXACT attack (same injected-delay technique)
   against the new code and confirmed the cascade no longer occurs: the
   on-time process publishes first, the delayed process's later publish
   attempt fails cleanly (target now non-empty) and falls through to a
   correct "holder alive, refuse" verdict, never touching the on-time
   holder's state. This live repro is now a permanent regression test (see
   `regression_test_planned`).
2. **The `-m`/extra-args passthrough (round-1's claimed fix for finding
   #13) was completely non-functional for its one stated purpose.** The
   first version collapsed extra args into one string (`EXTRA_ARGS="$*"`)
   and re-expanded it UNQUOTED, which word-splits on whitespace. The
   reviewer ran `sh scripts/safe_merge.sh feature-x -m "Merge branch
   'feature-x' — never cancel a main run; cache gradle"` and showed git
   received 15 separate word-split tokens instead of one, failing outright
   ("branch - not something we can merge") — i.e. broken for every
   realistic multi-word message, exactly this repo's own dominant
   convention. It failed safely (HEAD unmoved), but none of
   `safe_merge_test.dart`'s 4 tests ever passed a 3rd argument, so this
   shipped "4/4 passing" while the headline round-1 capability didn't work.
   **Fixed**: real, separate positional parameters (`shift` then `"$@"`,
   properly quoted) instead of flatten-then-re-split. Applied the identical
   fix to `safe_push.sh` in the same commit — same latent pattern, never
   triggered there only because its typical extra args happen to be single
   tokens, but the underlying defect was the same and is now closed in both
   places rather than left to bite `safe_push.sh` later.

Should-fix findings from round-2, also resolved: the acquire retry loop
bound raised 2→3 (a bound of 2 could exhaust immediately after a reclaim,
with no attempt left to actually claim the now-clear lock); no test had
exercised the `-m`/`-o` extra-args path at all in either wrapper (closed —
see `safe_merge_test.dart`'s new test and the new `safe_push_test.dart`).
Reviewed and found ALREADY CORRECT, no change needed: the 3b advisory-NOTE
mechanism (confirmed structurally advisory-only — its one call site never
reaches `fail()` — and its byte-comparison logic correct for what it
claims); `safe_merge.sh`'s `_norm()` port (verified character-by-character
against the Dart original); `git_safety_hook.dart` confirmed to genuinely
have zero `git merge` handling (the round-1 claim), so the deliberate
non-wiring is a real, intentional scope boundary and not an oversight
sneaking through unannounced.

A note on why round-2 changed a test's assertion rather than just adding
fixes: the round-1 TOCTOU test asserted a timing floor proving a "pause
before declaring a holder-less lock stale" — with the mkdir-then-write
design replaced entirely, there is no more read-then-decide step for that
scenario to pause before; a bare directory at the canonical lock path can
no longer arise as a legitimate in-flight state of this file's own code at
all. Re-running the OLD assertion against the NEW code failed immediately
(the new code's `mv -T` absorbs a pre-existing empty directory directly,
which is safe — verified under 5-way concurrent contention — but does not
print the old "Reclaiming stale lock" pause-then-log sequence the old test
looked for). Rather than force the new design to imitate the old one's
observable log lines just to keep an old assertion green, the test was
rewritten to pin what is actually true and actually safe about the current
code, with the historical context kept in a comment so a future reader
does not wonder why the assertion changed.

## Round-3 independent review (context-blind, per CLAUDE.md §4.12 — runs on the round-2-hardened diff)

Verdict: NOT CONVERGED. 1 blocking finding, fixed in this same round:

1. **The reclaim branch had the same check-then-act shape round-2's fix
   closed on the publish side — a sibling gap neither prior round
   scrutinized on its own.** Round-2's redesign made the PUBLISH path
   provably atomic (prepare privately, publish in one `mv -T`), but the
   RECLAIM path (read the current holder, decide it is dead, then
   unconditionally `rm -rf` it) is itself a separate check-then-act
   sequence. The reviewer proved it live: process A reads a stale entry,
   decides it is dead, and is merely slow before acting; process B reads
   the identical entry, reclaims it (via the pre-fix unconditional
   `rm -rf`), and legitimately republishes its own fresh, live lock; A then
   wakes and its own unconditional `rm -rf` destroys B's now-live lock with
   no check that anything changed; A's retry then acquires too — genuine
   double-acquire, reproduced 3/3 with a timestamped trace showing the
   exact mechanism. The reviewer's own suggested direction (swap `rm -rf`
   for an atomic `mv -T` steal) was verified NOT sufficient on its own
   before implementing anything further: empirically confirmed `mv -T` is
   keyed purely on the DESTINATION's existence, not the SOURCE's content —
   it will happily steal a live source into a fresh destination name just
   as readily as a dead one. **Fixed with two layers, neither alone
   sufficient:** (a) an age gate refusing to even attempt a reclaim until
   the lock is ≥3s old by its own `started=` timestamp — verified this
   directly defeats the reproduction technique (an injected short delay)
   under realistic conditions, since nothing in the real decide-then-act
   sequence has a natural multi-second gap (unlike round-2's bug, which had
   a real ~60-90ms natural gap from a subprocess spawn); (b)
   steal-verify-restore — atomically move whatever is at the lock path into
   a private graveyard, then verify the stolen content is still the exact
   same stale entity before discarding it, restoring it instead if a live
   claim raced in first. Reproduced the reviewer's exact attack against the
   fixed code (same injected-delay technique, targeting the steal line) and
   confirmed the cascade no longer occurs: the slower reclaimer's steal
   grabs the faster one's live content as expected (mv -T still doesn't
   discriminate), but the verify step catches the mismatch and restores it,
   and the slower reclaimer then correctly refuses on its retry. The
   faster reclaimer's holder content survives completely unclobbered
   (checked 2.5s after acquiring). This live repro is now a permanent
   regression test, alongside a standalone test of the age-gate layer.

**Honesty note on the residual gap, stated rather than hidden:** unlike the
round-2 publish-side fix (which is provably airtight — verified under
genuine 5-way concurrent contention with zero exceptions), the reclaim-side
fix does not achieve the same mathematical guarantee. A narrower race
remains in principle: a THIRD process claiming the momentarily-emptied lock
path in the exact window between the steal and the restore. That process's
own eventual `git_lock_release` would correctly detect (via the existing,
already-tested ownership check) that it no longer owns what it thinks it
owns and refuse to touch it — the same accepted-risk shape as this file's
already-documented PID-reuse limitation — but it is not a proof of
impossibility, only a proof that the failure direction stays "refuse/wait,"
never "silently corrupt," under every scenario tried. Achieving true
compare-and-swap semantics using only `mkdir`/`rename` primitives (no
`flock`, ruled out earlier for Windows portability) appears to require
either a fencing-token/generation scheme or accepting this class of
residual — reconsidered at length before choosing the latter, given the
combination of the age gate (removing the realistic trigger window) and the
existing ownership check (bounding the blast radius of the theoretical one)
already matches this file's own established bar for "safe under realistic
conditions, fails toward refuse-not-corrupt" rather than "provably immune
to an adversarially-constructed 3-way race."

## Round-4 independent review (2026-08-05) — NOT CONVERGED, and the reclaim was removed rather than patched

**Verdict: the reclaim does not ship.** Round 4 found a FOURTH defect of the
same check-then-act shape, one layer above round 3's. Verified by execution on
this toolchain, not by argument.

### The defect

`scripts/_git_lock.sh` (round-3 revision), in the steal-verify-restore block:

```sh
mv -T "$graveyard" "$lock_path" 2>/dev/null   # FAILS if destination non-empty
rm -rf "$graveyard" 2>/dev/null               # ran UNCONDITIONALLY
```

`mv -T` fails into a non-empty destination — that is the exact semantic the
CLAIM path depends on and which this document establishes empirically further
up. The `rm -rf` after it had no guard. Reproduced directly: with a populated
destination, `mv -T` exits 1, the source survives, and the following `rm -rf`
deletes it.

Sequence, needing no injected delay:

1. Lock holds dead holder `D`, old enough to clear the age gate.
2. Process **A** reads it, decides stale.
3. Process **B** reads the same, reclaims, publishes its own lock — B now
   legitimately holds it.
4. **A** steals. Per this file's own note, `mv -T` is "a blind move keyed on the
   DESTINATION's existence, not the SOURCE's content", so A steals **B's live
   lock**.
5. The path is momentarily empty; **C** publishes there.
6. A's verify correctly detects it stole the wrong thing (`stolen_pid=B` ≠
   `holder_pid=D`) and enters the restore branch.
7. The restore `mv -T` **fails** — C occupies the path.
8. The unconditional `rm -rf` destroys **B's live lock**.
9. B still believes it holds the mutex. C believes it holds the mutex. **Both
   proceed.**

### Why the round-3 acceptance was wrong

The section immediately above this one names the window ("a THIRD process
claiming the momentarily-emptied path…") and **explicitly weighs and accepts
it**, concluding the design "already matches this file's own established bar for
'safe under realistic conditions, fails toward refuse-not-corrupt'."

That conclusion was the error. The residual does **not** fail toward
refuse-not-corrupt — it produces a genuine double-acquire, the precise failure
this file exists to prevent. The round-3 reasoning defended the wrong process:
it argued the third process's own `git_lock_release` would refuse to touch a
lock it no longer owned (true, and irrelevant), and never addressed the original
holder still running.

The window is also wider than round 3 assumed. The age gate is justified there
by "there is no natural multi-second gap anywhere in this file's own logic … no
subprocess-spawn-class delay". But the steal→restore window contains a `sed`
subprocess plus two `echo`s, and this document's own measurement puts a
subprocess spawn at **61–89 ms** on this stack — the same class it calls
realistically reproducible.

### Resolution — removal, not a fifth layer (OI-92, founder-ratified 2026-08-05)

CLAUDE.md §4.12 names four consecutive rounds finding the same shape as the
signal to reconsider the design. Filed as **OI-92**; the founder ratified
removal.

**The automatic reclaim is deleted** — `_RECLAIM_MIN_AGE_SECONDS`, the age gate,
and the steal-verify-restore block, ~50 lines. A lock whose holder is dead is now
REFUSED, printing the manual `rm -rf` the script already emitted.

There is no correct auto-reclaim available here, which is why this is a removal:

- `flock` is **not available** on this Git-Bash/MSYS2 stack (checked directly).
- With only `mkdir` / `mv -T` / `kill -0` there is no atomic "remove THEIR lock
  AND install MINE". A **directory** destination makes `mv -T` fail-if-present
  (correct for claiming, useless for replacing); a **file** destination makes it
  replace unconditionally (exactly backwards). The operation the reclaim needs
  cannot be expressed by these primitives.

The fencing-token/generation scheme the round-3 section floated remains the only
design that would work — and it means more state machinery in a file that has now
failed four review rounds. Removal is strictly simpler and strictly safer.

**What it costs, stated rather than minimised:** a holder killed without its trap
running (`kill -9`, power loss) leaves a lock needing one manual `rm -rf`, with
the command already on screen and a `started=` timestamp to sanity-check. That
set also got smaller — the trap now catches **HUP**, so closing a terminal no
longer leaks a lock. It notably does **not** include the incident that motivated
this whole file: a timed-out `safe_commit.sh` is not killed, so its trap runs
normally. That incident needed the CLAIM path, which is verified sound under
5-way contention — never the reclaim.

### Test changes

- **INVERTED** — "a stale lock … is reclaimed" became "a stale lock … is
  **REFUSED**, never auto-reclaimed, and prints the manual clear command". It
  asserts `isNot(contains('Reclaiming stale lock'))`, so re-adding the takeover
  path now fails a test instead of passing silently. Inverted rather than deleted
  deliberately: dropping it would leave nothing pinning which behaviour is
  intended, and a future "the lock wedges forever, let's auto-clear it" patch
  would sail through.
- **DELETED (2)** — the round-3 slow-reclaim cascade repro and the age-floor
  test. Both asserted a string the script no longer emits on any path; keeping
  them green would have required re-adding the machinery this change removes.
- **UNTOUCHED (4)** — alive-holder refusal + reuse, release-ownership,
  N-way `mv -T` single-winner, and the round-2 slow-publish cascade. These cover
  the CLAIM path, which was never the defective part.

**Negative-controlled by execution:** re-adding a naive auto-reclaim (`rm -rf
"$lock_path"` + `continue`, exactly the shape a well-meaning future patch would
take) makes **only** the inverted test fail; the other four still pass. The
script was restored from a byte-copy afterwards and re-verified by md5
(`f6144bd9…`), with a grep confirming no residue.
