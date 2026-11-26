---
branch: train-history-sheet-style
date: 2026-11-26
blast_radius: account
review_rounds: 4
ground_truth_verified: true
verdict: converged
---

# Plan-review record: past weeks inside the Train list (retire the "Completed history" sheet)

Plan: `docs/plans/train-past-week-in-place.md` (v3 + the round-4 wording patch). Mockup:
`docs/mockups/2026-11-26-train-past-week-in-place-v4.html` (gitignored local artefact).

**Tier `account`, RE-COMPUTED 2026-11-26 after the last edit (the tool reported `account`, matching this record)** with
`dart run scripts/blast_radius_from_diff.dart <changed paths as positional args>` (never the
stdin form). Reason: a new reader in `lib/core/services/workout_read_service.dart` and a copy string in
`lib/core/copy/wardroom_copy.dart` (`lib/core/services/**` and `lib/core/**` are account in
`docs/blast_radius.yaml`). If the tool reports a different tier, this record is corrected before merge.

## Rounds (all reviewers fresh, context-blind Sonnet subagents, read-only; every finding was verified
against the code by the coordinator before it was applied)

| Round | Seats | Outcome |
|---|---|---|
| 1 | A mechanism, B regression/tests | 15 findings applied (raw row read vs `getScheduleForDate`; invalidation; header/hero/week card contradiction; lit chips in the other groups; tier; missing tests/docs; a non-existent registry concept; restored rows losing name/exercises; line cites; mutants) |
| 2 | A mechanism, B behaviour/tests (on the post-round-1 plan) | applied (local-midnight `DateTime` re-keying `getScheduleForDate`; per-row whole-box scan in `exerciseLogsForIstDate`; D1 body range; name precedence vs `completed_title_follows_log`; unkillable M7/M13; the box-scan rewrite dropped as unmeasured; hold fixture; D7; dropped old-sheet behaviour; registry re-pin scope) |
| 3 | one convergence seat | not converged: 5 P1 plan-text errors, all patched |
| 4 | one verification seat | converged; one wording patch (fixture A) applied |

Ground truth: facts in plan section 2 were re-read from the code by the coordinator and by each seat;
the live-data claims (Fri 16 Oct, 40 exercise rows, `plan_json` size) were read-only SQL on project
`dedsavbjuwgarrhphgnl`.

## Self-attested residue (named, for the code-review B-pass)

- The golden-values-first order for D1 (capture from the unmodified provider, then refactor) is
  self-attested within one branch; the captured output is pasted into the diagnose-doc.
- Mutation results (rule 21) are run by the author; the diagnose-doc lists each mutant, the `grep -c`
  proof it applied, and the test that reddened.
- The scale budget is set from a measurement on this VPS when the guard test is written.
