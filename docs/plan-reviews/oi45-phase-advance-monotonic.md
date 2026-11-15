---
branch: oi45-phase-advance-monotonic
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/6584fc31ad5b-review.md
hermes_report: not_required
---

# Plan review — `oi45-phase-advance-monotonic`

Unit 3c + task #41 of the OI-25/44/45/46/48/50 batch. **Closes OI-45.**
Diagnose-doc `c8f3d1`. B-pass record: `docs/reviews/0119a592b81f-review.md`.

## Tier

Measured on the actual staged set, not a remembered list:

```
git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -
→ platform
```

**The trailing `-` is load-bearing** — without it the script reads
`git diff --cached` itself, which is empty at the wrong moment, prints nothing,
and reads as a broken tool.

`platform` comes entirely from this batch editing `docs/blast_radius.yaml`, which
the registry makes platform-tier by its own self-referential rule. Every `lib/`
file here is individually `account`. An earlier measurement in this batch said
`account` because I classified a **hand-typed list of four `lib/` paths** rather
than the staged set — recorded because it is the second time in two batches that
this classifier has been fed the wrong input and produced a confidently wrong
tier.

Platform `requires:` is
`[regression_test, behavioral_test_path, code_review_b_pass, feature_flag]`.
All four satisfied — see below for how `feature_flag` was resolved without
shipping the fix dark.

## Ground truth verified

Every load-bearing claim was checked against the artifact, not against prose:

- `user_progress.current_phase` is `integer`/`int4` — **live
  `information_schema` query run by me**, not taken from either reviewer (one
  asserted it, the other explicitly could not verify it).
- `current_phase` has no monotonic guard: read `user_repository.dart:128-135`.
- `PlanEngineFlags.adherenceGateEnabled` is ship-dark default OFF:
  `plan_engine_flags.dart:212-218`.
- `PhaseProgressReconciler`'s only callers are `restoring_screen.dart:384,696` —
  grepped; the "boot heal" shorthand in an earlier draft was wrong.
- `lib/shared/services/` holds exactly one file — `ls`.
- Both behavioral tests proven to discriminate by **negative control**, run
  twice: by me while writing them, and independently by the B-pass reviewer.

## Round 1 — 9 findings (0 P0, 4 P2, 5 P3)

Full table in the diagnose-doc's "Round-1 review" section. The consequential
ones: the SoT registry's *gated* `behavioral_test_path` pointed at a pure test
that could not fail if the writer broke; `PhaseProgressReconciler` was the one
phase writer left outside the new lock; `advanced == false` fired
`phase_unlock_completed` for a write that never happened; and my "hoisted so it
guards every unlock" claim was provably unreachable on the default path.

It also **refuted a change I had made mid-review** — a `num?)?.toInt()` hardening
against a double `current_phase`. Testing the hypothesis showed `saveProgress`
throws on a double at `user_repository.dart:129`, and the column is `integer`
anyway. Reverted, and recorded as refuted rather than dropped.

## Round 2 — 4 findings (0 P0, 1 P2, 3 P3), ALL round-1 regressions

Run on the hardened diff, with the reviewer told explicitly that its primary job
was to attack round 1's corrections. That was the right instruction: **every one
of the four was caused by a round-1 remediation.**

The P2 is the reason §4.12.1 exists. Round 1's fix — wrapping the reconciler in
`withPhaseAdvanceLock` — introduced a **starvation bug**, because that primitive
is a try-lock that returns immediately rather than queueing. A contended boot
would silently drop the two-Phase-1 heal, with nothing to retrigger it, and the
heal's only callers are on the restore path. My safety argument ("idempotent,
runs on every restore") was wrong in a specific way: idempotence makes
*re-running* safe, not *skipping* safe. Fixed with a bounded retry.

## Convergence, and why this is not a "split it" signal

§4.12.1 says successive rounds surfacing *new material issues* means the unit is
too large. That is not this shape:

| | P0/P1 | P2 | P3 | new defects in the ORIGINAL work |
|---|---|---|---|---|
| Round 1 | 0 | 4 | 5 | 9 |
| Round 2 | 0 | 1 | 3 | **0** — all 4 traced to round-1 fixes |
| B-pass | 0 | 2 | 1 | 1 (F1, a consequence neither round named) |

Severity is strictly decreasing, and round 2 found nothing new in the original
work. B-pass F1 is the one genuinely new finding, and it was actionable in two
lines plus an OI note. **Verdict: converged.**

## B-pass — accepted

3 findings (2 P2, 1 P3), all fixed before the merge:

1. **Stale `schedule_*` rows when the commit declines.** Narrowed in code (an
   in-lock live-phase re-check before the expensive generate, with its own
   telemetry event), and the window that remains — a bump landing *during*
   generation — written into OI-83 as a named second-order effect.
2. **Frontmatter tier + the missing `feature_flag`.** Frontmatter corrected to
   `platform`. Added `configBox['disable_phase_advance_lock']`, gating **the lock
   only**, default-OFF-means-active, matching `disable_phase_reconciler` /
   `disable_bg_restore`. The monotonic guard deliberately has **no** switch: it
   is pure, cannot wedge anything, and a switch whose only effect is to
   re-enable the demotion bug is not a safety valve. Covered by a test that
   fails if the switch stops working.
3. **Reconciler retry latency on the foreground restore path.** Gap 1.5 s → 1 s,
   worst case 2 s (the reviewer's ~4.5 s figure double-counted the gaps — 3
   attempts have 2, not 3), bounded by the restore screen's 15 s escape hatch.

## Hermes

`not_required` — Hermes is catastrophic-tier only. This is `platform`.

## Filed, not folded in

**OI-83** — the cloud→Hive `progress` restore merges (`sync_profile.dart:613-622`,
`auth_session_bootstrapper.dart:323-328`, `sync_restore_completeness.dart:242,411`)
copy PostgREST values verbatim, cloud-wins, bypassing `saveProgress`, the lock
and the monotonic guard. `current_phase` is monotonic **on the advance
operation**, not as a field.

Deliberately out of scope, and the scope line is not a convenience: a restore
that refuses to lower `current_phase` is right for a stale second device and
**wrong** for a genuine account restore where the cloud row is the only truth
left. That is a product decision, not a mechanical fix, and guessing it is
exactly the unverified-premise failure this board exists to catch.
