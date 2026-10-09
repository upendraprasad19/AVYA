---
branch: safe-push-verifier
date: 2026-08-11
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/safe-push-verifier-bpass.md
---

# Plan-review record — safe_push landing-verifier fixes (platform)

Keystone record for the §4.12 merge gate. Two context-blind review rounds ran on a
plan **four times this size**; they cut it to this. What shipped is the piece that
survived all of it.

## What the reviews removed, and why that is the headline

The batch began as four founder-ranked remedies for a slow session. Ground-truthing
plus ×2 review found:

| Proposed | Outcome |
|---|---|
| Blast-radius-tier the pre-commit hook | **CUT** — duplicated `check_test_runtime_budget.dart` (Gate 41), shipped 2026-05-21 and skip-listed at `pre-commit.sh:222` / `test.yml:224` for being too slow; the tiering itself was proposed by name at `docs/audit/2026-05-28-test-pyramid.md:72,74` 75 days ago; diff-conditional selection was explicitly rejected in `docs/adr/0013-blast-radius-tiered-gating.md:52-67` alt #3 |
| Raise test concurrency instead | **CUT — unproven.** Looked like 2.1× (j8-cold 191s → j16-warm 91s); the control refuted it (j8-**warm** 90s, j16-**warm** 170s). Runs alternate with no relationship to the flag |
| safe_push keepalive | **PREMISE FALSE** — already present twice (`safe_push.sh:72`; `core.sshCommand` via `setup-hooks.sh:63-64`, commit `e7f11f6f`) |
| Fewer, larger commits | **NO CODE** — already `CLAUDE.md:257-265`; a gate here would be the ship-stop error class |
| A "P0 git recovery" STEP 0 | **CUT — it was DESTRUCTIVE.** See below |

**The STEP 0 near-miss.** The plan's first draft opened with `git reset --hard 4df6ef23`
on `main`, framed as a clean repair that "loses nothing". Ground truth: `main` and
`origin/main` are both `549bc5fe`, `0 0` ahead/behind, **CI green**, and `fc4552bb`
is the commit that *added* `docs/plan-reviews/unshard.md` (`git log --diff-filter=A`
confirms) and is already an ancestor. The causality was backwards; executing it would
have destroyed 5 pushed commits including a shipped auth-P0 batch. Round 1 caught it.

**§4.12.1 was applied literally.** Round 2 still surfaced 2 P0s and 7 P1s on the
*hardened* plan — the documented signal that the unit is too large. Rather than
review a fourth version, the batch was split to the smallest converged piece:
`scripts/safe_push.sh` only.

## Ground truth — every claim re-verified directly, not taken from reviewer prose

| Claim | Verified how |
|---|---|
| `:110-115` unreachable | Traced independently 3× (author + both rounds); `:80` exits on equality, `:92` on the retry's, `:107` assigns a value `:92` proved unequal |
| Old had 2 `$REMOTE_SHA = $LOCAL_SHA` tests, new has 1 | `git show HEAD:scripts/safe_push.sh \| grep -c` → 2; working tree → 1 |
| `:98-105` exits 0 having verified nothing | Read directly; literal comment "Trusting git's exit code" at `:102` |
| Keepalive already present | `safe_push.sh:72`; `git config --show-origin --get-all core.sshCommand` non-empty |
| Nothing branches on safe_push's exit code | `grep -rn "safe_push"` over `scripts/`, `.github/`, `.claude/` — hook only string-matches command text |
| `scripts/safe_push.sh` is platform tier | `docs/blast_radius.yaml:158` |
| 42 of 110 plan-review records carry `date:` | Counted — this killed a proposed date-conditional gate field |

## Round 1 — two context-blind reviewers (factual + design lenses)

Beyond STEP 0: killed the budget gate and partition as duplicated prior art; showed
the proposed `prior_art_checked:` field was **not** "additive and forward-only"
(0 of 110 records carry it, and the gate validates each merge against its own tree);
and corrected an over-broad claim that `scripts/**` is uniformly feature-tier (most
governed scripts are individually escalated to platform).

## Round 2 — on the hardened plan

Found defects **introduced by round 1's own corrections**, which is exactly what
review #2 exists for:

- The date-conditional fix for `prior_art_checked:` was **worse** than the hole it
  patched — 68 of 110 records carry no `date:`, so the rule needs "no date ⇒ exempt"
  and any future record opts out by omitting the field. Sound design instead reuses
  the existing `refs` mechanism at `check_plan_review_record_exists.dart:842-854`.
- `trap '' PIPE` would be **inherited across `exec`** by `git push` and its `ssh`
  child, plausibly converting a fast, loud exit-141 into a hang — i.e. causing the
  symptom it was meant to mitigate. Dropped.
- Flipping the soft-exit to non-zero would **re-create the F6 false positive**; the
  correct fix is one line up, capturing the probe's exit status. This is what shipped.
- "Re-arm or retire Gate 41" is ~10 files, 4 platform-tier, hard-fails the rule-24
  ledger (`gate_test_ledger_lib.dart:274`) and silently reopens audit finding T9.
  Two named options = not converged. Cut.

## What shipped

Capture `ls-remote`'s exit status separately, so "ref absent" (exits 0, empty) and
"probe failed" (non-zero) stop collapsing to the same empty string — which makes a
third honest outcome expressible: **0 LANDED / 1 FAILED / 2 UNVERIFIED**. Delete the
unreachable duplicate success block. Diagnose-doc `d4f9b2`.

B-pass (self-triggered per §4.3, before the merge) returned 2 findings, both from
lens 6 `guard_without_its_mirror`, both fixed in-batch: an undocumented+untested
widening of the retry gate, and a lost retry signal in the success message.

**Verification:** 6/6 green; mutation proof reddens 3 with the actuals being the bug
itself (`Expected: <1> Actual: <0>`, `Expected: <2> Actual: <0>`, `Expected: <1>
Actual: <2>`); `flutter analyze` clean.

## The process finding, recorded because it is the most expensive thing here

**This batch committed CI-10 instance #2 — inside the very batch whose own unit
existed to prevent CI-10.** The §4.1.5 prior-art subagent was stopped and never
reported; the plan proceeded anyway and then asserted the lookup "paid for itself".
It had not been run. Three separate premises died to measurement or review in one
session, all the same shape: **a number read off an input set that had not been
controlled.** Logged to `feedback_green_check_input_set_width` as instances 12–14.
The durable fix — making `prior_art_checked:` a *verified artifact reference* rather
than free text — is specified in the OI filed from this batch, not hand-waved.
