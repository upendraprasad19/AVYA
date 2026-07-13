---
branch: workout-progression-resolver
review_type: b-pass
blast_radius: platform
verdict: accepted
---

# B-Pass Review — workout-progression-resolver (Batch 3b-i: ⑦(a) detraining WEIGHT decay)

Context-blind adversarial B-pass on the implemented diff (self-initiated before the `--no-ff` merge,
§4.3; platform-tier). Every claim verified against the actual code + the IST helpers + the production
writer + the test harness wiring + the SoT registry.

## Verified CORRECT (no defect)

1. **F3 reduce-only invariant** — `est1rm` uses the original `top.weight` (`:97`); ALL FOUR reps-rule
   references use the decayed `base` (progress `:111`, hold `:114`, back-off `:118`, and the
   `<=0` floor `:119` resets to `base`, not `top.weight`). The F3 test is load-bearing: Squat 5kg/4reps/40d
   → base 2.5 → back-off 0.0 → floor FIRES → resets to base 2.5; asserts `2.5` AND `< 5.0` (the
   floor→`top.weight` mutation would yield 5.0 and fail both).
2. **F5 IST gap** — `_detrainingFactor` diffs two date-only parses (`istTodayStr()` + raw `dateStr`),
   never re-zones `top.date` (no `istDateStr`/`istDateOf` double-shift). `dateStr` is the raw `log['date']`
   carried into `_SessionTop.dateStr`. Confirmed the prod writer stores `date` as date-only IST
   (`workout_write_service.dart:83,168`) — the premise holds in prod, not just the test seed. Gap is
   CI-timezone-invariant.
3. **Epley clamp** — from pre-decay `top.weight`; `base ≤ top.weight` so decayed `suggested ≤` un-decayed
   pointwise, preserved through the `min(x, est1rm)` clamp. Negative gaps (clock skew) → `≤7 → 1.0`, no
   decay/crash.
4. **Band boundaries** — `≤7/≤21/≤35/else` → 1.0/0.925/0.825/0.5, contiguous integer bands, pinned
   7/8/21/22/35/36 by the test (`toStringAsFixed(1)` normalizes float noise).
5. **Kill-switch** — byte-for-byte the sibling `cardioGoalDefaultEnabled` pattern (safe-default ON);
   OFF → verbatim `top.weight`.
6. **Test determinism / non-vacuity** — `setTestClockTo`/`resetTestClock`; seed shape matches `_topSet`;
   box wiring correct (`testBypassOwnership` + owner set by `openForUser`); F7 asserts in the HOLD band
   (Epley never binds) so the clamp can't mask decay; F7+F4 fail on decay-off (100 ≠ 82.5/92.5/50).

SoT `detraining_decay` writers/readers match the code (reader contract unchanged — name→weight Map);
CLAUDE.md Stage-0 + flag docstrings accurate; two added imports both used.

## Findings

**P0/P1: none.**

**P3 (non-blocking, no code change):**
1. F3 also passes on decay-OFF (5−2.5=2.5) — it is a floor-reset *mutation guard*, not a decay
   discriminator (that non-vacuity is carried by F7/F4). By design.
2. No PROGRESS-band binding-Epley-clamp test — low value (code correct at `:97`; such a change would
   only be MORE conservative, no safety regression).
3. **Product nuance (matches the plan, not a bug) — for founder awareness:** in the PROGRESS band
   (reps≥10) at very light loads + a long gap, the additive `+5/+2.5` increment can EXCEED the
   multiplicative decay, netting a weight slightly ABOVE the last logged weight (e.g. 8kg×12/40d →
   base 4 +5 = 9). This is consistent with the plan's explicit "reduce-only = decayed ≤ un-decayed"
   (NOT "≤ original") and stays ≤ the pre-decay Epley cap. Only affects very light loads in the
   progress band. If the founder prefers a hard "never above last weight" rule, that's a one-line
   `min(suggested, top.weight)` follow-up — flagged, not changed (it would alter the progress semantics).

VERDICT: accepted
