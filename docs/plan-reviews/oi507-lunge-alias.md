---
branch: oi507-lunge-alias
date: 2026-11-23
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record: OI-523 library v28, drop the Forward Lunge -> "Reverse Lunge" alias

Plan: `docs/plans/2026-11-23-oi523-lunge-alias-v28.md` (rev 4). Tier L, blast radius `platform` (library asset, seed version, a seed migration).

Three context-blind Sonnet rounds, each verifying claims against the code and live data (read-only on `dedsavbjuwgarrhphgnl`):
- Round 1 (rev 1): not converged. P1: the planned ALIAS-RETIRE importer stage was dead code (G3470 is a SOURCE row rebuilt from the allow-list on every run; the only writer of its alias is `applyAliases` fed by E144 `alias_to`; an experiment on copies changed exactly one row and `--check` passed); P1: Fact 3 was false, `user_progress.plan_json` holds the name in 4 stale saved plans (verified again by the author); P1: the test chain was not enumerated (version pins, digest chain, batch label, blast-radius glob). Applied in rev 2.
- Round 2 (rev 2): not converged. P1: the build order committed before a migration could exist (tuples-match test and ledger pairing); P1: `_markSeeded(hive, 27)` mirrors and v16's `_currentVersion` missed; P1: the older upgrade tests' "others unchanged" snapshots would see G3470 change once the helper restores the alias. Verified against the files by the author; applied in rev 3 (helper, enumeration, build order).
- Round 3 (rev 3): converged, no P0/P1; eight P2/P3 (the gate loop with an unledgered file on disk, a safer commit-before-apply sequence, no hand-run broad suites, the two records the merge gate demands, wrong line numbers in the cloud-seeded test, a misattributed proof in Risks, the closed-entry shape). Applied in rev 4.

Ground truth checked live (read-only): cloud G3470 active with `{Reverse Lunge}`; 934 / 870 / 64 rows; 14 aliased active rows; the name appears only in `user_progress.plan_json` (4 stale plans, `plan_end_date` past) and `exercise_library` among all public text/jsonb columns.
