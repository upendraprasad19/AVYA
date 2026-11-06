---
bug_id: d3f1a7
date: 2026-08-17
batch: cycle-time-and-board-gaps
status: fixed
blast_radius: platform
symptom: >
  Two symptoms with one shape, both surfaced by the founder asking why the
  pipeline is slow and why the OI board number mismatch survived it.
  (1) SPEED: every commit paid ~182 s of discipline gates, of which the majority
  was not gate work at all — `flutter/bin/dart` is a wrapper that takes the SDK
  update lock and shells out to `git rev-parse` on the Flutter checkout on EVERY
  invocation, and the hooks call it 17 times. The lock SERIALIZES concurrent
  callers, so the wrapper's cost scaled with the gate loop's job count instead of
  dividing by it — which is also why raising PRE_COMMIT_GATE_JOBS had only ever
  bought ~20%.
  (2) CORRECTNESS: an OI number minted on two branches for two different issues
  reached `main` and was found by a human three days later. Everything had
  passed. `build_oi_index.dart:120-136` has a duplicate detector and two places
  in the repo asserted it made such corruption unable to LAND — but git invokes
  `pre-merge-commit` for an automatically created merge commit, and that hook was
  never installed. On a clean auto-merge NO hook ran at all.
concept: hook_coverage_and_dart_invocation_cost
sot_registry_entry: not_applicable — process/tooling; no Hive or cloud writer/reader contract
writers: >
  scripts/setup-hooks.sh:64-68 — installed FOUR hooks (pre-commit, pre-push,
  commit-msg, prepare-commit-msg) and had no notion of pre-merge-commit, so the
  merge path was uncovered by construction. Any session appending a `## OI-NN`
  section to docs/audit/open_issues.md is the writer of the colliding data;
  scripts/build_oi_index.dart:114-115 states there is no allocator and the number
  is chosen by eyeballing a tail split across two files.
  For the cost half: scripts/pre-commit.sh (13 sites), scripts/commit-msg.sh (3),
  scripts/pre-push.sh (1), scripts/prepare-commit-msg.sh (1) each wrote a bare
  `dart run`, resolving to the Flutter wrapper on PATH.
readers: >
  scripts/build_oi_index.dart:120-136 duplicateIds() — the LANDING detector that
  could not fire, because nothing ran it at a clean merge;
  scripts/check_closes_oi_cited.dart — resolves `closes-oi: OI-NN` at commit-msg
  time; and every diagnose-doc, closure YAML and commit message citing an OI
  number as a stable target. docs/audit/open_issues.md:2426-2428 and
  docs/diagnoses/2026-08-13-oi-id-collision-renders-silently-b7e3d1.md:56-58 both
  READ as authoritative claims that landing was gated; both were false.
hive_key_prefix: not_applicable — no Hive state involved
hive_key_formula: not_applicable — no Hive state involved
sync_methods: not_applicable — no sync path involved
restore_methods: not_applicable — no restore path involved
cloud_table: not_applicable — no cloud table involved
cloud_columns: not_applicable — no cloud columns involved
contract_test_path: >
  test/scripts/oi_numbering_lib_test.dart (20 tests: pure predicate + e2e against
  real throwaway git repos) and test/scripts/dart_bin_resolver_test.dart (9 tests,
  including the MIRROR test that fails if any hook reverts to a bare `dart run`
  or drops the `. _dart_bin.sh` source line). Plus 30 new assertions in
  test/contracts/git_safety_lib_test.dart for the env-prefix bypass found en route.
ist_handling: not_applicable — no date keys or counter resets involved
provider_invalidations: not_applicable — no Riverpod providers involved
telemetry_op_types: not_applicable — hook/gate tooling emits no client telemetry
cross_account_guard: not_applicable — no per-user data involved
forbidden_patterns_checked: >
  Full gate loop re-run green after every change (75 in-loop + 2 explicit + Gate
  40). check_gate_scripts_wired PASS at 99 scripts; check_gate_test_ledger PASS at
  89 gates; check_no_deferral_euphemism PASS after being widened from
  staged-diff-only to a full sweep of CLAUDE.md + all SKILL.md files.
proposed_fix: >
  (1) scripts/_dart_bin.sh — resolve the SDK exe once per hook run, falling back
  to PATH `dart` on any unexpected layout so a hook can never be wedged by a path
  guess. All five hooks source it.
  (2) scripts/pre-merge-commit.sh — installed as the FIFTH hook, running the two
  board gates only (~2 s), not the 75-gate loop.
  (3) scripts/check_oi_numbering_unique.dart + scripts/oi_numbering_lib.dart — a
  THREE-point predicate (minted-on-this-branch AND present on mainline AND titles
  differ) closing the MINT-TIME half of OI-112.
regression_test_planned: >
  Shipped, not planned. Mutation-proven on both halves. Dart resolver: reverting
  the gate-loop line to bare `dart run` reddens the pre-commit case; deleting the
  source line reddens the commit-msg case. OI gate: 4 mutations, each VERIFIED as
  actually applied before its run (a mutation that silently fails to apply
  reports green and proves nothing) — dropping stdoutEncoding utf8 reddens 3,
  dropping the unparseable-board guard reddens 1, dropping LEG 1 reddens 2,
  dropping LEG 3 reddens 2, against a 20/20 green baseline.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "no lib/ code changed — this batch is hooks, gates, tests and docs only" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "no Hive box read or written" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no DDL, no schema reference added or changed" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "no data surface touched" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration; backups/applied_migrations.json unchanged" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function changed or deployed" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron job added or changed" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy touched" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no bucket or object touched" }
  - { tier: 10, name: secrets, status: verified, evidence: "check_razorpay_key_flavor.dart wired into build-apk.md — it reads the gitignored .env.prod, which is exactly why it cannot run in pre-commit or CI. Confirmed no secret is read, written or committed by this batch: the gate is referenced, never executed here." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no Razorpay / OneSignal / Firebase interaction" }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "the analogous contract here is which hooks run at which git operation, and it was incomplete: pre-merge-commit was absent, so a clean auto-merge ran nothing. Verified end to end by running the REAL scripts/pre-commit.sh (exit 0, 98447 ms, all gates passing) and by running the new gate against the live colliding branch oi-session-coordination, where it correctly exits 1 naming both OI-128 titles and the next free number (OI-130)." }
impact_analysis: >
  SPEED: ~84 s saved per commit on a quiet machine (182149 -> 98447 ms, same
  gates, both exit 0); ~236 s under load (399370 -> 163744). At the observed
  cadence of 2-4 merges/day with several commits each, that is minutes per day
  of blocking wait, and it compounds with every gate added later — the previous
  cost model made each new gate cost a wrapper invocation rather than ~1 s of
  actual work.
  CORRECTNESS: six OI collisions had shipped by 2026-08-16 (five renumber
  commits, three on 2026-08-13 alone). The fifth went 3 days 0 h 34 m undetected
  and its pushed commit message still cites the superseded numbers, because a
  pushed message is not rewritten — so those citations are permanently wrong in
  both directions. A SEVENTH was live and unmerged while this was being written
  (main's OI-128 vs oi-session-coordination's OI-128), and the new gate detects
  it. The residual risk is unchanged for anything the founder must decide:
  OI-101 (Gate 41 re-arm-or-retire) and OI-129 (salvage the orphan's uncommitted
  April work) both stay OPEN and blocked on a human, by design.
related_bugs: >
  b7e3d1 (2026-08-13, oi_board_id_uniqueness) — the same class, one generation
  earlier. It correctly recorded that detection "does not stop it being CREATED"
  and left OI-112 open for the cross-branch half; this doc closes that half. It
  ALSO asserted that landing was gated, which this doc corrects.
recurrence: >
  YES for the OI-numbering class — 6th and 7th instances. And the batch itself
  reproduced two documented recurring classes IN ITS OWN new code, which is the
  more useful finding: (a) feedback_green_check_input_set_width — the new gate's
  first live run reported PASS against an EMPTY mainline board, because
  Process.runSync defaults to systemEncoding and mangled the em-dash separator so
  0 of 77 headings parsed; an empty input set reported nothing in the same colour
  as nothing-wrong. Caught ONLY because the first end-to-end run was aimed at a
  branch already known to be colliding. (b) feedback_mistake_guard_without_its_mirror
  — fixing the encoding alone would have fixed the instance and left the class,
  so _parseStrict now refuses to treat an unparseable board as a clean one and
  the verdict says SKIPPED rather than PASS whenever an input was undetermined.
---

# The merge hook that was never installed, and the Dart wrapper tax

## What the founder actually asked

Two questions in one message: *why do the tests and gates take so long*, and
*when everything passed, why was the board mismatch still there*. The first plan
for this work answered only the second — and answered it by **adding two more
gates**. The founder's reply was one line: *"how will time come down with this?"*
That correction is the reason this batch has a (T) half at all, and it is
recorded as its own memory (`feedback_answer_the_cost_question_asked.md`),
because the failure mode is specific to this repo: its whole history is adding
discipline machinery, and the founder is the only counterweight.

## Root cause 1 — the wrapper, not the gates

`flutter/bin/dart` is not the Dart binary. On Windows/MSYS it `exec`s
`flutter/bin/dart.bat`; on POSIX it sources `internal/shared.sh`. Either path,
on **every invocation**, acquires `flutter/bin/cache/.upgrade_lock`, runs
`git rev-parse HEAD` on the Flutter checkout, and re-verifies the SDK stamp.

That is correct for interactive use and pure waste for a hook that invokes dart
17 times, where the SDK cannot change between the first call and the last.

Measured, alternating order, quiet machine:

| | wrapper | SDK exe |
|---|---|---|
| `dart --version` (does nothing) | 3357 / 3665 / 8048 ms | 216 / 151 / 220 / 206 / 103 ms |
| real `pre-commit.sh`, same gates, both exit 0 | **182149 ms** | **98447 ms** |
| same pair, machine under load | 399370 ms | 163744 ms |

**The lock is the mechanism.** N concurrent wrappers serialize on one
`.upgrade_lock`, so the wrapper's cost scales with `PRE_COMMIT_GATE_JOBS`
instead of dividing by it. That explains a previously unexplained observation:
raising the job count from 4 to 12 bought only ~20%, and buys nothing measurable
now the wrapper is out of the path. **Do not "fix" gate latency by raising the
job count** — that lever was measuring lock contention, not parallelism headroom.

Two hypotheses were tested and **refuted**, and are recorded in
`scripts/_dart_bin.sh` so nobody re-runs them:

- **Windows Defender.** Real-time protection is ON, but the SDK exe is scanned
  identically and costs 280 ms. The cost is the wrapper's own work.
- **The hook's `GIT_DIR` leak reaching `dart.bat`'s git call.** Wrapper costs
  3916–4113 ms without the leak and 4029–4201 ms with it. No effect.

## Root cause 2 — a detector wired to a moment that never occurs

`build_oi_index.dart:120-136` fails closed on duplicate `## OI-N` headings. It
runs in exactly one place: `pre-commit.sh:159-166`, and only when
`docs/audit/open_issues.md` is staged.

A merge is where two boards first coexist. Git invokes **`pre-merge-commit`** —
not `pre-commit` — for an automatically created merge commit. Only four hooks
were installed. So on a **clean auto-merge**, which is precisely the documented
failure shape (the two sessions' additions sat in different regions and git
combined them silently), **no hook ran at all**. A *conflicted* merge was
covered only incidentally, because the human then runs `git commit`.

Two places asserted the opposite, and both are corrected in this batch:

> "a corrupt board can no longer render and cannot LAND — the merge commit
> regenerates the index and the gate fires"
> — `open_issues.md:2426-2428` (OI-112) and `b7e3d1.md:56-58`

Neither was supported by the installed hook set.

## The gate shipped with its own instance of a documented bug class

`check_oi_numbering_unique.dart`'s first end-to-end run was aimed at
`oi-session-coordination`, a branch **known** to carry a live OI-128 collision.
It reported **PASS**.

`Process.runSync` defaults to `systemEncoding`. On this machine that decodes the
board's em-dash separator (U+2014, UTF-8 `E2 80 94`) as three cp1252 characters,
so the section regex matched **0 of 77** headings and the gate compared against
an empty mainline board — in which every number looks uncontested.

Every unit test passed throughout; the predicate was correct the whole time. Only
running it against real git data exposed it. The fix is deliberately two-layered:

- **instance** — pin `stdoutEncoding: utf8`.
- **class** — `_parseStrict` distinguishes "no entries" from "could not read
  this" using `countHeadingPrefixes`, which matches only the ASCII `## OI-<digits>`
  prefix and therefore survives any mis-decode. A board with headings present and
  zero parsed is UNDETERMINED, never clean. And the final verdict prints
  **SKIPPED**, not PASS, whenever any input was undetermined — saying "no
  collisions" about a comparison that never happened is the same defect one level
  up.

An earlier, cruder version of that rule ("any non-blank content with zero parsed
entries is undetermined") was itself wrong — a closed board holding only its
title is 17 bytes of real content and legitimately zero entries — and was caught
by the e2e suite rather than in review.

## Found en route: the git-safety hook was optional

`commandInvokesGitSubcommand` anchored its pattern at `^git`, so **any**
environment prefix defeated detection: `FOO=1 git commit -m x` produced no match,
no deny, and the raw commit ran. The documented hatch `ALLOW_RAW_GIT=1 git commit`
had therefore been "working" by **detection miss**, not by the env check its own
deny message advertises — which made an accidental bypass indistinguishable from
an authorised one. Meanwhile `FOUNDER_APPROVED_NO_VERIFY=1 git commit --no-verify`
genuinely did not work at all: the `--no-verify` match is unanchored so the deny
still fired, while the env read inspected the hook process's own environment,
which an inline prefix never sets.

Separately, `commandUsesWrapper` was `command.contains(basename)` — and its return
value is an ALLOW, so merely naming the wrapper disarmed the guard:
`echo "use safe_commit.sh" && git commit -m x` passed cleanly.

Both closed. `sudo` and `nohup` are deliberately **not** stripped: over-stripping
risks a false BLOCK, the one failure mode this hook must not have.

## Verification

- Real `pre-commit.sh` A/B in the same worktree, both exit 0, all gates passing.
- New gate run against the live colliding branch: exit 1, both titles printed,
  next free number computed (OI-130).
- 20 + 9 + 30 tests; mutation-proven on 4 legs (gate) and 2 legs (resolver), each
  mutation verified as actually applied before its run.
- `.claude/worktrees`: 15 dirs / 4 orphans → 11 dirs / 1 orphan, and the survivor
  is OI-129, which holds genuinely unrecoverable work and was deliberately left.

## What is still open, and why

- **OI-101** — Gate 41 re-arm-or-retire. Two legitimate options; a founder scope
  call, not a defect.
- **OI-129** — the surviving orphan. Widened here: beyond the 2 reports and 25
  screenshots already recorded, **20 further source paths** differ from every
  commit in history (checked exhaustively for two of them, not sampled), with
  mtime 2026-04-20 against main's 2026-05/06 commits to the same paths. Salvage
  scope is bigger than the entry said; the decision is still the founder's.
- **OI-106** — the 3.9× local-vs-CI per-file gap is *not* explained by the wrapper
  finding, since CI's gate loop does not pay it. Still unmeasured.
