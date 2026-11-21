---
branch: oi84-graduation-hoist
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi84-graduation-hoist-bpass.md
hermes_report: not_required
---

# Plan review — `oi84-graduation-hoist`

Unit B of the post-batch residuals. **Closes OI-84.** Diagnose `b4e9c7`.

## Tier

Measured on the actual staged set, after the last edit:

```
git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -
→ platform
```

**The plan predicted `account`, and it WAS `account` — until the B-pass fix.**
Fixing the B-pass P1 meant editing `docs/blast_radius.yaml`, which carries its
own `platform` rule (`:171`), and that promoted the whole batch. Per-file
classification confirms it is the SOLE platform contributor:

| tier | files |
|---|---|
| `platform` | `docs/blast_radius.yaml` (1) |
| `account` | `graduation_screen.dart`, `pro_phase_advance.dart` (2) |
| `feature` | the other 16 |

Two consequences, and I measured the tier BEFORE that last edit and had to
correct this record — the same measure-too-early error the plan file itself
warns about ("measure at diff time"):

- `bpass: accepted` is now **REQUIRED**, not advisory. It is present, and it was
  run before the tier moved, so nothing was retrofitted to satisfy a gate.
- `hermes` is still not required (catastrophic only).

The trailing `-` is load-bearing: a path passed positionally classifies THAT
path; piping on stdin classifies the staged diff. Both forms are used above and
they answer different questions.

## Ground truth verified

- **909 → 552 lines**, confirmed three ways (`wc -l`, `git show :<path>|wc -l`,
  `readAsLinesSync().length`). The gate comment initially said 555 — written
  before three dead imports were removed; both round-1 reviewers caught it
  independently.
- Gate 43 green **with the allow-list entry deleted**, and `graduation_screen.dart`
  absent from the `ALLOW` output. `_maxLines` still 800 — verified not raised.
- `withPhaseAdvanceLock` take-point unchanged: still after the choice sheet
  closes, never across it. That ordering is now the caller's, enforced by where
  the call sits in `_onPro`.
- All four outcome arms mapped 1:1 against the old `bool?`: `busy`←`null`,
  `committed`←`true`, and BOTH `preemptedBeforeGenerate` and
  `generatedButDeclined`←`false`, sharing the same copy, the same
  `phase_unlock_counter_already_advanced` event and the same navigation — as
  they did before. The two were never distinguishable screen-side and still
  aren't; the enum makes a future divergence expressible, nothing diverges yet.
- `scheduleSvc` is re-derived rather than captured, but
  `workoutScheduleReadServiceProvider` returns the `.instance` singleton and the
  `ref.read` runs before any `await` — same object, no new gap.
- `phaseRepeatNudgeProvider` confirmed at `home_provider.dart:957` (a feature
  file), which is what forced `repeatNudgeFlagged` into the return type.

## Round 1 — 6 findings, all real, all fixed

Two context-blind reviewers, distinct lenses. Every claim re-verified against
the files before action (`feedback_audit_verifier_cannot_trust_own_subagent`);
none was refuted. **Two were in tests written specifically to catch that class:**

1. The `'current_phase': nextPhase` negative guard went **trivially true** when
   re-pointed — that literal cannot reach a file where `nextPhase` is a
   parameter. The replacement ban-list named only helper functions, so a
   regrown raw `updateProgress({'current_phase': …})` in the screen — the exact
   Unit 3c / OI-45-finding-5 defect — would have passed everything in this
   batch. The write is now banned where it could reappear, with a companion
   assertion that the READ stays legal.
2. The blast-radius test covered one of two extraction targets while claiming to
   cover "the hoist". `phase2_preview_card.dart` is `feature`, which is correct
   (read-only UI), but nothing asserted it.
3. The layering justification cited `lib/CLAUDE.md` rule 7, which is about
   import STYLE, not direction. Design kept on its merits; citation removed.
4. "Behaviour-preserving" was an overclaim — the preview went eager→lazy.
5. Three stale `graduation_screen._onPro` refs in `pro_phase_advance.dart`'s own
   doc comments.
6. The gate comment's stale 555.

## Round 2 — 5 findings, all real, all fixed, **all inside round-1 corrections**

This is the §4.12 signature and it fired exactly as documented — every round-2
finding was in something round 1 had just changed:

1. Round 1 softened the layering claim in two files but left it asserted as a
   hard rule in `sot_registry.yaml` and `advance_choice_test.dart` — an internal
   contradiction inside one diff.
2. "three breaches" is **four**: `ward_status_strip.dart:3` uses the relative
   `../../../features/` spelling, invisible to a `package:`-only grep.
3. The eager→lazy consequence was stated **backwards** and contradicted its own
   adjacent bullet.
4. The `{0,6000}` regex "bound" bounds nothing — signature→EOF is 3593 chars.
   Replaced with a structural check that asserts the function is the file's last
   top-level declaration.
5. The new tier assertion's comment promised write-detection `tierFor()` cannot
   do (it resolves globs, never reads content). Made TRUE with real read-only
   content assertions rather than by weakening the comment.

## B-pass — accepted

5 lenses clean with evidence; 3 findings. Record:
`docs/reviews/oi84-graduation-hoist-bpass.md`.

The P1 is the one worth remembering: **three documents in this diff claimed, in
the past tense, that the stale `docs/blast_radius.yaml` justification "was
restated" — and `blast_radius.yaml` was not in the diff at all.** The tier was
never wrong, so no gate weakened; what was wrong is that the change asserted its
own fix had landed, inside a unit whose prose names that failure mode twice.
Fixed by actually editing the yaml, not by downgrading the claim.

## Convergence

| | P0 | P1 | P2 | P3 | new defects in the ORIGINAL move |
|---|---|---|---|---|---|
| Round 1 | 0 | 0 | 4 | 2 | 4 (2 in the move, 2 in its docs) |
| Round 2 | 0 | 0 | 2 | 3 | **0** — all five are round-1 regressions |
| B-pass | 0 | 1 | 0 | 2 | **0** — the P1 is a false claim about a fix, not a code defect |

**Verdict: converged.** Round 2 found nothing new in the move itself, and the
B-pass found no code defect — its P1 is a documentation-truth failure. The
relocated code has now been read line-by-line against `HEAD` by three
independent reviewers and the mechanical diff shows only the enum and the
relocated `ref.invalidate`.

Zero P0s across all three passes, which is the honest distinguishing feature of
this unit versus its siblings: it moves code rather than changing behaviour, and
every real finding was in the SCAFFOLDING — the tests, the tier justifications,
the doc claims — not in the moved logic.

## Self-caught defect worth recording

My own round-1 fix for the missing `repeatNudgeFlagged` coverage was **vacuous**,
and a mutation test is what proved it. It asserted an equivalence
(`flag == nudgeWritten`) that reads like a real end-to-end check but cannot fail:
one variable drives BOTH the Hive write and the returned flag, so mutating it
moves both sides together. Substituting `= repeat` left the test green.

The shipped version asserts absolute values at an input where the correct and
wrong expressions genuinely disagree (`repeat: true` with no repeatable content,
so `pins == null`). Verified both directions — clean passes, mutated fails —
with the source restored from a file copy and `md5sum -c`'d, never
`git checkout` (the Unit 7 incident). Generalised into
`memory/feedback_green_check_input_set_width.md`.

## Feature flag — none, and the reasoning is not a waiver

`platform` lists `feature_flag` in its `requires:` set. **No script enforces it**
(`grep -rln feature_flag scripts/` → nothing), so this is a judgement I am
making explicitly rather than one a gate made for me.

None ships, because there is nothing for one to gate. The platform tier here
comes from ONE file — `docs/blast_radius.yaml` — and the edit to it is a
COMMENT: the stale justification for a rule whose tier is unchanged. There is no
runtime path in that file to switch off. The requirement exists so a risky
runtime change can be reverted without a redeploy; a kill-switch on a yaml
comment would be ceremony, and worse, it would put a fake flag in the ledger.

The runtime delta in this batch is `account`-tier and is a pure relocation: the
old path is not preserved because it is not a different path, only a different
location. A switch could only choose between two spellings of identical
behaviour — and `phaseAdvanceTarget`'s own doc already states the principle a
switch whose only effect is to restore a defect is not a safety valve.

Contrast with Unit A, which DID ship a kill-switch at platform tier: there the
platform classification came from `sync_profile.dart`, a genuine runtime
multi-user sync path, and the change altered restore semantics. The tier looked
the same; the risk did not. **The tier is a prompt to think, not a checklist to
satisfy.** Nothing is owed to `docs/ship_dark_pending_review.yaml` — that ledger
tracks flags shipped under the lighter §4.12.4 build-tier review, and this unit
had the full ×2 + B-pass.

## Nothing owed to a later batch

No migration, no Edge Function deploy, no live-prod action. Every finding from
all three passes is closed in this commit.

## Process findings

- **Verify the fix landed, not just that you decided to make it.** The B-pass P1
  existed because I read `blast_radius.yaml`, decided to correct it, wrote three
  documents saying I had, and never edited the file. `git diff --cached
  --name-only` would have caught it in one command.
- **Name review artifacts by something stable, not by a hash that later edits
  move.** The hash excludes `docs/reviews/` but not `docs/plan-reviews/`, so
  staging this very record shifts it. That circularity is what left `ca4ef2c3`
  pointing at a non-existent review and turned `main` red today.
- **Reviewers were told, in the brief, not to write to the tree**, with the Unit
  7 incident quoted. All three complied. The full diff was staged before each
  dispatch.
