---
branch: oi172-push-result-file
date: 2026-09-10
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/08e601e60f35-review.md
---

# Plan-review record — OI-172 push-result record + the §4.9 verification-width row (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Platform-tier both halves, computed not estimated:
`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
→ `platform` (with the build-hooks banner sharing the result line — the exact trap
this batch's own §4.9 row documents). Not catastrophic → no Hermes.

⚠ **This file's absence was a P1 in the B-pass.** `docs/audit/open_issues.md` cited
it before it existed, and the merge would have failed CI's keystone gate. The three
review rounds it records genuinely happened and are documented in full at
`docs/audit/oi172-push-result-plan.md` §10–§12 — but a plan doc under `docs/audit/`
is invisible to the gate, which reads exactly this branch-keyed path. Producing
review artifacts is not the same as producing THE artifact the gate reads.

## Scope

Two items, batched at founder direction because both are platform, both are
discipline infrastructure, and both trace to the same session.

**A.** `safe_push.sh` distinguishes three outcomes (0 LANDED / 1 FAILED /
2 UNVERIFIED) and nothing recorded which one happened. The only in-flight evidence
was the lock's `holder` file, and `_git_lock.sh:174-189` `rm -rf`s the lock on a
`trap … EXIT HUP INT TERM`, so on any normal exit it is gone. The lock answers
"is a push running right now" and structurally cannot answer "what happened".
Fixed by a record at `$(git rev-parse --absolute-git-dir)/.safe_push_result` plus
`scripts/push_result_lib.dart` as the reader. Closes OI-172.

**B.** One row in root `CLAUDE.md` §4.9 for the class where a filter added for
readability narrows a verification's input set and zero reads as proof.

## Rounds

| round | findings | outcome |
|---|---|---|
| 1 | 7 (0 P0, 3 P1, 2 P2, 2 P3) | 6 accepted, **1 REJECTED with measurement** |
| 2 | 7 (0 P0, 3 P1, 3 P2, 1 P3) | all 7 accepted |
| 3 | 6 (0 P0, 1 P1, 3 P2, 2 P3) | all 6 accepted |
| B-pass | 7 (0 P0, 1 P1, 4 P2, 2 P3) | all 7 accepted, 0 false alarms |

**27 findings, 0 false alarms across four independent context-blind passes.**

### Why three rounds and not the mandated two

Two of round 2's three P1s were defects in round 1's own **corrections**. Shipping
corrections that had never themselves been reviewed was the one thing both rounds
argued against, so round 3 ran scoped narrowly to the v2→v3 delta — and found more
of the same, including the batch's most substantive finding.

### The rejection worth recording

Round 1 claimed the §4.9 row was factually wrong about analyzer output, citing a
committed report showing `warning` lines indented. **That file is not analyzer
output** — it uses `—` separators where the analyzer uses ` - `, and prints the
issue count *above* the issues rather than last. It is a hand-typed markdown
summary. Characterising a tool's stdout from a prose report is the very
input-set-width error the row documents, committed while disputing it.

Measured instead, with a positive control: the analyzer right-aligns the severity
column to a **fixed** width of 7 (`len("warning")`), so `warning` gets **0**
leading spaces, `error` **2**, `info` **3** — fixed rather than longest-present,
because info-only output still gets 3. The published regex returns **0** against 2
real warnings. Round 2 reproduced this independently from scratch and confirmed the
rejection sound.

### The most substantive finding (round 3)

The reader contract lived as **prose**, and its test had to invent its own reader —
so the assertion could only prove that a stand-in agreed with a paragraph by the
same author, and there were no real callers to be wrong. Fixed by shipping the
contract as code (`push_result_lib.dart`), which made the "relax to `local_sha`
only" mutation a real code mutation instead of a fixture edit. Same pure-lib /
own-test split as `ci_reconcile_state_lib.dart`.

## Ground truth verified

Not inferred — each of these was run:

- **All three outcomes end-to-end** against a real bare remote: LANDED (exit 0,
  `local_sha == remote_sha`), FAILED (exit 1, non-empty reason), UNVERIFIED
  (exit 2, EMPTY `remote_sha`), plus a mid-flight `STARTED` sampled while a
  sleeping `pre-receive` hook held the push open, with `kill -0` confirming the pid.
- **`mv -T` semantics on this stack**, both directions: onto an existing
  DIRECTORY it refuses (exit 1) where plain `mv` exits **0** and moves the file
  inside; onto an existing FILE it replaces unconditionally (4 consecutive writes).
  The second half was checked separately because a `-T` that refused to overwrite
  would have broken every push after the first.
- **`--git-dir` vs `--git-common-dir`** measured in both worktree kinds; `--git-dir`
  is RELATIVE in the primary, which is why the record resolves through
  `--absolute-git-dir`.
- **Retirement invisibility**, by planting a file and running the exact command
  `retire_worktree_lib.dart` uses. Independently reproduced by the B-pass.
- **The analyzer column measurement**, three ways, reproduced by two reviewers.
- **15 mutation legs against the full 51-assertion suite** (13 red, 2 predicted
  green and explained). ⚠ The first measurement ran each leg against ONE file and
  undercounted three of them; the B-pass caught it and every leg was re-run.

## Residues, stated rather than closed

1. **`kill -9` leaves no record** — the same limit `_git_lock.sh`'s trap has, and
   exactly why an absent record must read UNVERIFIED and never FAILED.
2. **A tag passed where a branch is expected still gets a wrong `FAILED`**, because
   `probe_remote_sha()` hardcodes `refs/heads/$BRANCH`. Pre-existing; zero call
   sites pass `--tags`. The record now carries `verified_ref` so a reader can SEE
   the probe used the wrong namespace, but the verdict itself is still wrong.
   Fixing it means changing the script's verification semantics — a different
   change with its own blast radius.
3. **The `reason` sanitizer is defensive-only** and NOT mutation-proven: every
   reason the script passes today is a script-authored single-line string, so
   making it a passthrough reddens zero. Stated rather than counted as a proof.
4. **No gate reads the record.** Deliberate — a gate on a diagnostic artifact would
   be a ship-stop for a hygiene feature, the reasoning §4.13 point 6 already applies
   to retirement.

## Found and fixed in-batch, not planned

`safe_push.sh:75`'s own resolve guard was **inert**. Plain
`git rev-parse <unresolvable>` prints the NAME to stdout and exits 128, so
`LOCAL_SHA` captured the literal branch string, the `-z` guard never fired, and the
script pushed a bogus refspec instead of printing "could not resolve local ref" —
making that exit effectively unreachable for the case it was written for. Now
`--verify --quiet`. Surfaced by a new test, not by reading.
