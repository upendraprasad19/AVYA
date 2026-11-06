---
reviewed_at: 2026-09-05T12:40:00+05:30
staged_against: phase-arc-flip@branch
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, guard_without_its_mirror, unawaited_no_error_sink, asserted_fixture_value, missing_input, blast_radius_mismatch, flag_inversion_correctness]
findings_count: 5
verdict: accepted
---

# Code Review (B-pass) — phase-arc-flip

Flip of `enable_phase_arc` to live (OI-53 flag 3 of 12), plus a new ship-dark
`enable_deload_reason_line` keeping the week-4 reason line dark, plus three
latent-defect fixes in `PhaseArcStrip`.

The reviewer returned `verdict: rejected` on its own pass. All five findings are
resolved below; this file records the accepted state after remediation.

## Finding 1 — P0 — self-attesting tracking docs

- **file:line:** `docs/audit/phase-arc-flip.closure.yaml:12-13`, and its entry `R3`
- **claim:** The closure ledger named `docs/plan-reviews/phase-arc-flip.md` and
  `docs/reviews/phase-arc-flip-bpass.md` as existing artifacts, and `R3` asserted
  in the past tense that a tuning entry "was appended to
  `.claude/skills/code-review/SKILL.md` in this commit". None of the three existed
  or were staged. A platform-tier merge without the plan-review record fails
  `check_plan_review_record_exists.dart` in CI at the merge commit.
- **verification:** `ls docs/plan-reviews/phase-arc-flip.md docs/reviews/phase-arc-flip-bpass.md`
  → both absent; `git diff --cached --name-only | grep -c "plan-reviews\|reviews/phase-arc"` → 0
- **status:** accepted — fixed
- **resolution:** All three authored and staged in this commit. The ledger's
  past-tense claims were rewritten to describe what the commit actually contains.
  **This is worth naming as a class, not just a slip:** a ledger is a CACHE of
  artifacts, and I wrote the cache before the artifacts. The repo already records
  this shape for `flip_reviewed:` in `ship_dark_pending_review.yaml`, where a
  stale status field nearly caused a false P0 report on 2026-09-02. Same error,
  different file, three days later.

## Finding 2 — P2 — stale line citation in the diagnose-doc

- **file:line:** `docs/diagnoses/2026-09-05-...-e3b7d1.md:49`
- **claim:** Cites `train_provider.dart:903` for `phaseArcProvider`; line 903 is
  `PhaseArcData`'s const constructor. The provider begins at 906.
- **verification:** `grep -n "final phaseArcProvider" lib/features/train/providers/train_provider.dart` → 906
- **status:** accepted — fixed (903 → 906)

## Finding 3 — P2 — unfilled placeholder in the ship-dark ledger

- **file:line:** `docs/ship_dark_pending_review.yaml` resolved entry, `flip_commit:`
- **claim:** Carried the literal `PENDING_COMMIT_SHA`, which is neither a sha nor
  an established convention anywhere in that file.
- **verification:** `grep -n PENDING_COMMIT_SHA docs/ship_dark_pending_review.yaml`
- **status:** accepted — fixed. The sha cannot be known while writing the commit
  that contains the ledger, so the flip lands in two commits on this branch: the
  batch, then a one-line commit filling `flip_commit:` with the real sha. Both
  reach `main` in the same merge. That is honest about the ordering instead of
  encoding a placeholder that reads like a value.

## Finding 4 — P3 — the dev-panel kill-switch would have looked inert

- **file:line:** `lib/features/dev/dev_panel_screen.dart` `_togglePhaseArc`
- **claim:** `setState` rebuilds the dev screen, not the Train tab, and
  `phaseArcProvider` reads the flag non-reactively. Nothing would re-run the gate,
  so toggling the switch would appear to do nothing until an unrelated rebuild.
- **verification:** every sibling toggle (`:245,:256,:283,:303`) calls
  `DayRolloverObserver.instance.runRolloverNow(ref)`, which is what invalidates
  for them; `_togglePhaseArc` called neither.
- **status:** accepted — fixed. Added `ref.invalidate(currentPlanProvider)`, which
  `phaseArcProvider` watches. Worth doing rather than noting: F1 of round 1
  established that this flag has no release-build kill-switch at all, so the
  debug one being observably functional is the only reachability it has.
  The diagnose-doc's `provider_invalidations` field was corrected too — it said
  "no new invalidation added", which stopped being true.

## Finding 5 — P3 — FOB-8 tracking confirmed accurate

- **status:** accepted — no action. The reviewer independently verified that the
  hold-week identity issue is genuinely gated behind `enable_hold_weeks`
  (default OFF) and that FOB-8 plus closure entry `R4` describe it correctly.

## What the reviewer verified clean

Enumerated all writers of `week_character` and of the `current_plan` blob and
confirmed no live path produces a length outside 4 (so the `>= 4` guard is a
defensive floor, described as such, not dead code); re-derived every literal in
the new `labelFor` test group by hand; ran `flutter analyze lib/` live (44 issues,
0 warnings, 0 errors) and both contract files (22/22); independently re-ran
mutation M3 and observed exactly the 1 reddened test the diagnose-doc claims,
then reverted and confirmed clean against the staged index; confirmed zero live
readers of the old `enable_phase_arc` key remain across `lib/ test/ scripts/
docs/ .claude/`; confirmed the only new `unawaited(` call wraps a `logEvent`
whose body cannot throw; and re-checked nine cited line numbers across the
CLAUDE.md row, SoT registry, diagnose-doc and closure ledger, finding exactly the
one error in Finding 2.

## Founder triage notes

Not required — all five findings were dispositioned in-batch with no deferrals.
