---
adr_id: 0018
title: Move flutter analyze + flutter test off pre-commit; analyze becomes unconditional at pre-push
status: accepted
date: 2026-08-11
deciders: Upendra
---

# ADR-0018: Commit-time gate cost split

## Context

Every commit blocked for **~14 minutes**, independent of diff size. Measured per-phase by timing
each stage of `scripts/pre-commit.sh` separately:

| Phase | Time | Share |
|---|---|---|
| `flutter analyze --no-fatal-infos` | 212s (cold) | 25% |
| `flutter test test/contracts/` | 521s | 62% |
| Gate 40 + 3 explicit `dart run` gates | 7s | <1% |
| 71-gate `check_*.dart` loop (j=4) | 105s | 12% |
| **total** | **845s** | |

⚠ **These seconds are contested and this ADR does not settle them.** Two caveats, both raised by
the round-1 review:

- A **warm** `flutter analyze` measures ~18s; the 212s is a cold first run (pub get + analyzer
  startup included), not steady state.
- **OI-102** — OPEN, board-`Verified` the same day — measured `flutter test test/contracts/` at
  **1114.6s over 477 files** via a full JSON-reporter run, 2.1× the 521s above. OI-102 is itself
  open *because* no contamination-free measurement exists, and it explicitly warns that
  in-session timings are artifact-prone. The 845s run was in-session.

Treat 845s as a **floor**. The decision does not turn on which figure is right: under both, the
two flutter steps dominate. (If OI-102 is right the case is stronger, not weaker.)

**On the file counts quoted around this batch** — 477, 478, 479 and 480 all appear and all are
correct for different moments: 477 and 478 are OI-102's own two reporter counts, 479 was the
count at authoring time, and 480 is the count after this batch adds
`hook_gate_placement_test.dart` to `test/contracts/`. Authority is
`find test/contracts -name '*.dart' | wc -l`; the numbers are snapshots, not disagreements.

Three compounding causes: almost nothing is scoped to the staged diff (only the 6 index regens
and the blast-radius calls read it); every `_test.dart` compiles separately, so the suite has a
large fixed cost that does not divide; and the gate loop pays 71 cold Dart VM starts.

The two Flutter steps were 87% of the cost **and** the most duplicated work in the pipeline:
`test/contracts/` is a strict subdirectory of `test/`, so an ≥account batch ran those same 479
files three times — at commit, at push, and in CI.

A second finding reframed the safety question. `.github/workflows/test.yml` is the only workflow
and triggers on `push: [main, develop]` **plus `pull_request` targeting them**. Counted live:
`git ls-remote --heads origin` returns 29 refs (28 non-main); **8 have an open PR and therefore
do get CI on every push; the remaining ~20 — including most `claude/*` working branches — get
none.** Both `pre-push.sh`'s header ("CI runs it ~2 min after push — the backstop") and
CLAUDE.md §0 ("on every push, regardless of the local tier") asserted a remote backstop that
does not exist for that PR-less majority.

(An earlier draft of this ADR said "42 branches, none of them run CI". Both halves were wrong:
42 counts remote-*tracking* refs from `git branch -r` — including `origin/main` and refs already
deleted upstream — and it missed the `pull_request` trigger entirely. Corrected by the round-1
review; recorded here rather than silently patched, because the alternative rejected below was
argued partly on that number.)

## Decision

1. `scripts/pre-commit.sh` runs the discipline gates only — no `flutter analyze`, no
   `flutter test` — on its default path. What remains is ~112s.
2. `scripts/pre-push.sh` runs `flutter analyze --no-fatal-infos` **unconditionally**, placed
   above every early exit (`PRE_PUSH_FULL`, the `origin/main` and empty-range fail-safes, and
   the `feature`-tier skip — all of which `exit 0`).
3. The tiered full-suite rule at pre-push is **unchanged**: ≥account runs it, `feature` skips it,
   any uncertainty runs it.
4. The prior behaviour stays reachable verbatim behind `PRE_COMMIT_LEGACY=1`; `PRE_COMMIT_FULL=1`
   keeps its existing meaning (analyze + full suite at commit time).

Decision 2 is the load-bearing half. Analyze is cheap, catches the whole class of error a
`scripts/`-heavy repo actually produces, and is the only check a feature-tier branch push
receives anywhere. Making it tiered would have left that push with nothing.

Net effect on a 6-commit batch: ~84 min of blocking wait → ~16 min.

## Alternatives considered

**Delete both steps and add nothing back** (~12 min/batch, the cheapest option). Rejected: it
leaves `docs/`, `scripts/`, `test/`, `.claude/` and `lib/features/*` work — the bulk of this
repo — with no analyze and no tests anywhere until after the merge to `main`, at which point a
failure is a red `main`, a P0 under coding rule 20. The extra ~4 min/batch it saves over the
chosen option is the worst-value time in the set.

**Widen the CI trigger to `push: ['**']`** so branch pushes get a real remote backstop.
Strictly safer and would make `pre-push.sh`'s own comment true for the first time. Declined by
the founder on cost: it spends GitHub runner minutes on every branch to protect against
something the unconditional local analyze already blocks before the push completes. Re-checked
against the corrected numbers above — the exposed set is the ~20 PR-less branches, not 42, which
makes this alternative cheaper than first argued but does not change the decision, since local
analyze covers those 20 already and does so *before* the push rather than after. Recorded here
so the next reader need not re-derive it.

**Ship dark** (§4.12.4): lean path behind a default-OFF flag, flipped in a later commit. This
would have bought the lighter 1-round build review, but the saving is the entire point of the
change and would not have landed until the flip commit — which needs the full ×2 review anyway.
Rejected as two batches for one outcome.

## On platform tier's `feature_flag` requirement

`docs/blast_radius.yaml` lists `requires: [regression_test, behavioral_test_path,
code_review_b_pass, feature_flag]` for platform. The first three are satisfied (two new test
files incl. two runtime e2e tests; this ADR's B-pass). **`feature_flag` is deliberately NOT
satisfied, and this section is the record of that rather than a claim of compliance** — the
B-pass flagged its absence and it should stay visible.

Reasoning: the flag mechanism for a change like this is §4.12.4 ship-dark (new path default-OFF,
flipped in a later commit). That was considered and rejected above — the saving *is* the change,
so shipping it dark buys nothing until the flip, which then needs the full ×2 review anyway.
Founder chose default-ON with a reversion hatch.

What stands in for it: `PRE_COMMIT_LEGACY=1` restores the prior behaviour verbatim for any single
run, and reverting the batch is a one-file change plus re-running `setup-hooks.sh`. That is a
rollback switch, not a §4.6 feature flag — §4.6 wants the NEW path behind the gate, and here the
new path is the default. Naming the difference matters: an earlier draft of `pre-commit.sh`
asserted §4.6 compliance on the strength of the hatch, which was backwards, and the round-1
review caught it.

Blast-radius note: the failure mode of this change is *slower or weaker gating*, not corrupted
user data — no runtime code path in `lib/` is touched. That is why a rollback switch was judged
adequate where a payment or sync change would not be.

## Consequences

- A broken commit can now exist locally. **A compile error** is caught at push (analyze is
  unconditional there). Cost: one amend.
- **A failing TEST is not necessarily caught at push.** At `feature` tier the suite is skipped,
  and a PR-less branch push runs no CI, so the first test run anywhere is CI on the
  merge-to-`main` push. That is a genuine coverage narrowing versus the old
  `test/contracts/`-on-every-commit behaviour, and `test/contracts/` is exactly where the
  script/tooling tests live. Stated plainly rather than left implicit: on feature-tier work you
  are trading a per-commit test gate for a per-merge one. `PRE_PUSH_FULL=1` closes it for a
  given push; `PRE_COMMIT_FULL=1` closes it for a given commit.
- Feedback on a compile error arrives once per batch rather than once per commit, so several
  broken commits can stack before the push reports it.
- `main` is as protected as before: nothing reaches `origin` without analyze, and nothing but a
  `feature`-tier range reaches it without the full suite.
- Coding rule 20's enforcement point moved from commit to push. The policy did not change; the
  rule text was corrected to say where it is enforced.
- Two stale claims about CI coverage were corrected in `CLAUDE.md` §0, `scripts/pre-push.sh` and
  `docs/handbook/process/tiered-gating-by-blast-radius.md` rather than left to mislead.
- The hooks are installed as **verbatim copies** (`setup-hooks.sh` does a plain `cp` into the
  worktree-shared `git-common-dir/hooks`), so this change has no effect until that script is
  re-run — and re-running it from an unmerged branch would change hooks for every concurrent
  session at once. Reinstall belongs after the merge to `main`. This interacts with **OI-104**
  (`check_hooks_installed.dart` checks hook PRESENCE, not freshness; the installed hooks were
  found 12 days stale on 2026-08-11): between this merge and the reinstall, every gate reports
  green while the hook on disk is the old one. OI-104's hash-vs-presence fix is out of scope
  here and remains open.
- **Gate 32's anchor was repaired in passing.** `check_hooks_installed.dart:40` accepts a hook
  containing either `scripts/pre-commit.sh` or `flutter analyze`. The script contained **zero**
  occurrences of the former *before* this batch too, so the gate was already resting solely on
  `flutter analyze` — a string this batch demotes to hatch-only. The literal path is now in the
  header and asserted by a test, which closes a latent breakage this change would otherwise have
  made load-bearing.
- **OI-102 is closed by this change** (its "What's wrong" — `pre-commit.sh:66` runs
  `flutter test test/contracts/` on every commit — is no longer true). The *measurement* question
  it was blocked on is NOT answered: why local runs ~3.9× slower per file than CI is still
  unexplained, and is restated on the board rather than dropped.

## Pinning

- `test/contracts/hook_gate_placement_test.dart` — asserts the pre-commit **else** (default)
  branch invokes no flutter command, that no flutter call escapes the hatch chain, that Gate 32
  can still identify the hook, and the by-character-index proof that pre-push analyze precedes
  every early exit.
- `test/scripts/pre_push_analyze_always_e2e_test.dart` — executes the real hook with a stub
  `flutter` on PATH: once under `PRE_PUSH_FULL=1`, and once against a scratch repo whose pushed
  range is **forced** feature-tier (stubbed `dart`, synthetic `origin/main`), so the skip path is
  genuinely exercised.

**Mutation-proven, both halves** (round-1 review found the first version of the pre-commit half
was not):

- Restoring `flutter analyze` + `flutter test test/contracts/` into the pre-commit **else**
  branch — the most natural way this regression returns — reddens the else-body test. The first
  version of that test asserted only containment within the whole `if/elif/else`, a range that
  *includes* the else body, so this mutation passed green.
- Relocating pre-push analyze below the `feature`-tier skip reddens 3 tests (1 ordering +
  2 behavioural), the feature-tier one reporting `Got: []` — i.e. analyze never ran at all.
  (An earlier claim of "3 tests" here was true only for one mutation placement; the review
  showed a different placement reddened 2, because the old third test inherited whatever tier
  the real branch happened to be. The forced-tier scratch repo removes that dependence.)

## Status

Accepted. Shipped 2026-08-11 on `claude/commit-merge-push-process-aae061`. Blast radius
**platform** (`scripts/pre-commit.sh`, `scripts/pre-push.sh` and `CLAUDE.md` are all platform in
`docs/blast_radius.yaml`), so it carries a ×2 context-blind plan review and a B-pass.

Refines ADR-0013 rather than superseding it: the blast-radius tiering 0013 established is intact
and unchanged. What this ADR revises is (a) which hook the expensive steps run in, and (b) 0013's
factual premise that "CI runs the full suite on every push regardless", which is true only for
`main`/`develop` pushes and PR branches — corrected in place at ADR-0013's Context.

**Not in effect until `sh scripts/setup-hooks.sh` is re-run from `main` after the merge** — the
hooks are `cp` copies into the worktree-shared hooks dir.

## Companion

- ADR-0013 (the original tiered-gating decision this refines).
- `docs/handbook/process/tiered-gating-by-blast-radius.md`.
- CLAUDE.md §0 (hook semantics) + §4.4 rule 20 (where test failures are gated).
