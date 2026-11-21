---
branch: phase-arc-flip
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/phase-arc-flip-bpass.md
blast_radius: platform
reviewed_at: 2026-09-05
---

# Plan review — phase-arc-flip (OI-53 flag 3 of 12)

Flip `enable_phase_arc` live so the periodization wave strip renders on the Train
tab. §4.12.4: a FLIP takes the full ×2, never the lighter `ship_dark_build` tier,
plus `bpass: accepted` at ≥platform.

## Rounds

**Round 1 — context-blind, on the v1 plan. 13 findings, `needs-revision`.**
Two P1. It found that the plan's rollback section described a kill-switch no
release build can set — every flag toggle lives in the `kDebugMode` dev panel and
there is no RemoteConfig — and that the flip would light a SECOND surface, the
week-4 deload-reason line, which could contradict the wave node above it. It also
caught that the plan cited a third writer of the plan blob it had never named
(`sync_workout.dart:1108`, the cloud restore), and that the task list omitted
`bpass_review:`, whose absence fails CI **at the merge commit**.

**Round 2 — context-blind, on the HARDENED plan. 20 findings, `needs-revision`.**
Five P1, and the headline was that ROUND 1's own correction was defective. The
hardened plan proposed changing `DeloadEvaluator` to report whether the blob write
happened. Round 2 showed that fix targeted a contradiction the plan's other two
fixes already made unreachable, while introducing a reachable one — emitting
"Recovery week logged — you're recovered" over rows stamped
`week_character: 'working'` — in code shipped to every user since 2026-09-01. It
was dropped entirely. Round 2 also found the genuinely reachable version of the
bug (`deload_reason_phase_<P>` is never deleted anywhere in `lib/` while a regen
re-stamps week 4 as `deload`), and that adding the B-pass file would itself trip
`check_skill_tuning_history.dart`.

**Split.** §4.12.1: successive rounds surfacing new material issues means the unit
is too large — split and ship the smallest converged piece. Founder chose to split
on 2026-09-05, reversing the earlier "ship both surfaces in one flip". The strip
ships; the reason line stays dark behind a new `enable_deload_reason_line` and is
Unit B, with its own ×2.

**Scoped split-verification.** A narrow fourth pass tested only the claim the split
rests on: with the reason line dark, does anything leak? Verdict `split-is-clean`
on that question, with two real problems elsewhere — a `recordNonFatal` that would
have fired for every pre-onboarding user, and a SoT entry at `:8077` that names
`enable_phase_arc` for the render and that no earlier round had found.

**B-pass.** 5 findings, `verdict: rejected` on its own pass, all resolved. Its P0
was that the closure ledger attested to artifacts — including this file — that did
not yet exist. See `docs/reviews/phase-arc-flip-bpass.md`.

## Ground truth verified

Every citation re-derived from source rather than carried between rounds. Two of
v1's were wrong (`phase_arc_strip.dart:36-37` is a blank line and `return
Container(`; `_labels` is `:19-24`, not `:20-25`); v2 corrected them; the B-pass
then found one more in the diagnose-doc (`train_provider.dart:903` → `906`). The
`>= 4` guard, the five-token vocabulary, the clamp at `:1214`, the Campaign Gold
value, and the blast-radius tier were each confirmed against the file.

## Corrections to my own claims, recorded so they are not re-inherited

- **F1's evidence was false** (round 2, R8). A `configBox.put` grep found one flag
  writer; three more exist in the same file via a local `cfg` binding. The
  conclusion — no release-build kill-switch — survived; the evidence did not.
- **The parity gate's mechanism was stated backwards** (R9). It does range-check
  the block form, but only for `line_range:` immediately after `file:`.
- **"No node is ever `isCurrent`" was unconditional** (R17). It holds only when
  `currentWeek > waves.length`.
- **The blast-radius checks earlier in this session used the wrong invocation** —
  a piped file list without the required `-`, so the script read `git diff --cached`
  instead. The verdicts happened to be right; the method was not.
- **The closure ledger was written in the past tense about work not yet done**
  (B-pass P0). A ledger is a cache of artifacts; I wrote the cache first.

## Residuals, all tracked, none deferred

- **Unit B** — the reason line plus R5's stale-reason bug. On
  `ship_dark_pending_review.yaml`'s `enable_deload_reason_line` entry.
- **FOB-8** — the strip is a seventh "you are in week 4" surface, because it reads
  `getCurrentWeekNumber()` directly rather than `weekIdentityProvider`. Filed
  against `enable_hold_weeks` (default OFF, so unreachable today).
- **OI-95** — no release-build kill-switch for any OI-53 flag. Pre-existing,
  accepted risk, cited rather than re-litigated.
