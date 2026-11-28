---
reviewed_at: 2026-10-16T22:30:00+05:30
staged_against: measurements-flag-flip, the staged working tree on 745bdc95 (plan docs/plans/measurements-flag-flip.md and its plan-review record) vs main 745bdc95; the commit this file ships in contains the tree AFTER the fixes below
blast_radius: platform
reviewer: 2 fresh context-blind Sonnet reviewers on one tree (A: production code and tests, with 15 proposed mutants; B: documents and claims), read-only, exhaustive command allow-list (Read, Grep, Glob, git diff --cached, git show, git log, git grep, grep, rg, ls, wc, sed -n, head, cat; no scripts, no tests, no database, no network)
lens_set: [writer_reader_drift, flag_off_identity, does_this_test_pass_for_the_wrong_reason, fixture_realism, evidence_truthfulness, plan_vs_code_drift, registry_gate_semantics, kill_switch_reachability, exposure_of_default_on]
findings_count: 21
verdict: accepted
---

# Code Review (B-pass) - L2b flag flip: `enable_body_measurements` default ON (`measurements-flag-flip`)

Plan `docs/plans/measurements-flag-flip.md` (two plan-review rounds, record `docs/plan-reviews/measurements-flag-flip.md`).

**Outcome:** no P0, 21 findings (3 P1, 6 P2, 12 P3). Reviewer A (code and tests) found no defect in the getter: for every stored type Hive can return it gives the stated result, and no other reader of the key uses a different expression. It found one real gap (A3, P2): every widget test that mounts the Home slot, the chip or the Progress card set the flag explicitly, so nothing exercised the production default (the key never written). Reviewer B (documents) found three P1, all in the documents: the plan cited decisions that exist only on PR #117, the ledger and record it described did not exist yet, and the published privacy policy says things the build does not yet do (13+ with a date-of-birth check). Those are why the plan now has a binding merge order (#117, then the age-floor and consent batch, then this flip).

## Reviewer A (production code and tests)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| A1 | P3 | Getter semantics hold for null, bool, int, double, String, List and Map; the unopened box and a throw read OFF. | Checked; no change. |
| A2 | P3 | No other reader of the key; no caching outside `measurementsEnabledProvider`. | Checked; no change. |
| A3 | P2 | No test mounts the Home slot, the chip or the card frame with Hive open and no flag put. | Fixed: `test/home/measurement_slots_test.dart` and `test/ai_coach/measurement_chip_slot_test.dart` got a row with `flag: null` (the key never written) that expects the banner / chip; mutated: default `false` and `== true` redden both. |
| A4 | P2 | A stored `false` is lost on sign-out (`user_repository.dart:1211`), and the release build has no writer. | Recorded: the getter doc, plan section 1 and the founder's audience statement say so; OI-345 removes the path. No code change (a remote switch is the founder's call). |
| A5 | P3 | The day-rollover "OFF" row cannot observe the flag (the rollover only invalidates). | Fixed: the fixture comment says so; the `false` put states the premise. |
| A6 | P3 | Stale comments (`progress_comparison_screen.dart:21`, the flag test header). | Fixed. |
| A7 | P3 | The dev toggle is correct; the toast text was unpinned. | Fixed: a source pin for the `'ON' : 'KILLED'` toast in `measurement_flag_off_identity_test.dart`. |
| A8 | P3 | The `user_scoped` test is sound. | Checked. |

**Mutant table (reviewer's 15 plus the author's).** Reddened by the staged tests according to the reviewer (by reading): 1, 2, 3, 4, 5, 6, 7, 10, 11, 13, 14; the author RAN 1, 2, 4, 7 and 10 (all RED). Survivors in the reviewer's run: 8 (`stored is! List && stored is! Map`), 9 (`stored is! double`) and 15 (the toast text); fixed by adding `0.5`, a List and a Map to the non-bool loop and the toast pin, then re-run: 8, 9 and 7 RED. 12 (`stored != false`, `stored is! bool || stored`) are equivalent to the getter. Author mutants: default `false`, catch `true`, `== true`, ignore a stored `false`, all RED on the flag test; default `false` and `== true` RED on both new widget rows; catch `true` is carried by the flag test only (a widget row cannot reach a thrown read).

## Reviewer B (documents and claims)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| B1 | P1 | The plan cited decisions and ledger edits as done that exist only on PR #117 (not on this tree). | Fixed: the gate table says "on PR #117, not yet on main"; merge order is binding. |
| B2 | P1 | The plan's ledger and its plan-review record did not exist. | Fixed: both are created in this commit. |
| B3 | P1 | The published policy says 13+ with a date-of-birth check; the build still accepts 10. The gate table presented OI-305 as answered. | Fixed: the OI-305 row says the code is not in this batch, and the plan makes the age-floor and consent batch land first; ledger row `AGE-POLICY-GAP`. |
| B4 | P2 | The plan said the policy check was pending while OI-310 said "fetched and read"; OI-310 "Blocked on" was stale. | Fixed: `POLICY-CHECK` verified_clean with the fetch evidence; the OI-310 line rewritten. |
| B5 | P2 | `docs/ship_dark_pending_review.yaml` still said the flip waits. | Fixed: marked as the earlier state, FLIP paragraph extended with the record paths. |
| B6 | P2 | OI-345 named the Landing C device rows, which describe a debug build. | Fixed: it names `FLIPPED-BUILD-CHECK` of the new ledger. |
| B7 | P2 | The audience wording put the web exposure last. | Fixed: it opens the audience paragraph. |
| B8 | P3 | The plan listed three nested CLAUDE.md files; PROF-20 and `lib/core/services/CLAUDE.md` also changed. | Fixed. |
| B9 | P3 | Leftover wording is historical only. | Checked. |
| B10 | P3 | Citations are true (line 535, 276, 171, 1211). | Checked. |
| B11 | P3 | OI-345 matches its neighbours' format. | Checked. |
| B12 | P3 | "separate batch" for the age code reads like a deferral. | Recorded: OI-305 and OI-310 stay OPEN and carry it, the merge order makes it a precondition, and a ledger row (`AGE-POLICY-GAP`, `upstream_blocked`) names the blocker and the reopen condition. |
| B13 | P3 | "No schema, no EF, no migration" is supported by the diff stat. | Checked. |

## Verification the author ran after the fixes

Full `flutter test --exclude-tags golden` on the final tree: see the closure ledger row TESTS. `flutter analyze lib/`: no error or warning (59 pre-existing infos).
