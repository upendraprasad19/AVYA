---
branch: readiness-flip
date: 2026-09-02
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/9e4c5681-review.md
hermes: not_required
---

# Plan review record — readiness-flip (OI-53 flags 1 & 2)

## ⚠ ONE review covering TWO flags — stated openly, not presented as a single flip

`docs/ship_dark_pending_review.yaml` warns that batching flag flips is *"one review
pretending to be thirteen."* This pairing is deliberate and the justification is mechanical,
not convenience:

`plan_generator.dart` gates `stashWorkingBase` on `triggeredDeloadEnabled` **at generation
time**. A plan generated while that flag was OFF carries no stash, and `deload_evaluator`
guards on stash presence — so flipping deload later would help no existing plan and would
need a second APK plus a second wait. The eval additionally early-returns without readiness,
so the two flags are untestable apart.

Reviewers should judge this record as covering both.

## Review rounds

**Rounds 1-3 — on the PLAN for a pure flag flip (design later superseded).** Context-blind,
all `not_converged` (2, 2, 2 blocking). Round 1 found the Reports paywall the flip would
light up and a kill-switch with no writer anywhere in the app (a §4.6 violation — a gate
nothing can close). Round 2 found a defect round 1's own hardening created. Round 3 found a
defect round 2's hardening created, and correctly identified that the batch's remaining
findings were all citation errors a gate catches for free.

**The design then changed on founder direction** — readiness moved to data-collection, then
back to pre-workout with sleep measured from Health Connect instead of asked. Spec:
`docs/superpowers/specs/2026-09-01-readiness-sensor-and-deload-engine-design.md`.

**Rounds 4-5 — on the IMPLEMENTATION PLAN.** Both `not_converged`.
- Round 4 (2 BLOCKING, 7 MAJOR, 12 MINOR): `SLEEP_ASLEEP` is the wrong data type — the plugin
  returns a whole session only for `SLEEP_SESSION`. And a 7th breaking test the plan had
  mis-filed as a harmless line to delete.
- Round 5 (6 BLOCKING, 4 MAJOR, 7 MINOR), **four of them defects round 4's fixes created**:
  `READ_SLEEP` declared in no manifest; a self-contradictory insertion point; a permission
  request function with no caller; a test that never touched its own subject; an invented
  enum member; two missing imports.

A split was recommended after round 5 and **retracted** — its premise was that the sleep half
could not be verified without a device. `adb` was already installed and the founder has the
device, so the premise was false when the recommendation was made.

## Ground truth verified

Every blocking finding was independently re-verified against source before acceptance, not
taken on the reviewer's word: the plugin's `HealthDataReader.handleSleepData` +
`HealthConstants.mapSleepStageToType` (for the data-type defect), `AndroidManifest.xml` (for
the permission), `write_result.dart` (for the invented enum member), and the actual
`_syncToHiveLocked` line numbers (for the placement contradiction).

## B-pass

`docs/reviews/9e4c5681-review.md` — 5 findings, 0 false alarms, all fixed in-batch. The P1 was
a permission-scope defect: the sheet's sleep nudge reached the steps/weight consent dialog.

## Mutation evidence (rule 21)

- Mutation B — flip kill-switch polarity — applied (grep=1): **22 tests reddened**.
- Mutation C — catch-block default — applied (grep=2): **2 tests reddened**.
- Mutation D — sever the sheet's `resolveSleepAxis` delegation — applied (grep=0): **1 reddened**.
- Restored from file backups (never `git checkout`); all green after.
- **NOT claimed:** the Health Connect read itself is unprovable in this suite — no
  `flutter test` reaches the plugin. That is what the on-device logcat check is for.

## Accepted residues, recorded not hidden

- Killing `disable_triggered_deload` does NOT revert a lift already applied; the week stays
  `working` and only the reason strip disappears.
- Killing `disable_readiness` stops new collection but does not hide readiness history already
  rendered by the Reports card. The CODE path reverts verbatim (§4.6's actual requirement);
  the DATA persists.
- A plan generated before this commit has no stash, so the deload is unobservable until a
  fresh plan is generated. **The device test must account for this or nothing will happen.**
- OI-95 (kill-switches reachable only in debug builds) is unchanged and out of scope.
