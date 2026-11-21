---
reviewed_at: 2026-11-18T22:10:00+05:30
staged_against: 3177bbdb8de3
reviewed_sha: 08507462
blast_radius: account
reviewer: claude-sonnet-via-skill (2 fresh Sonnet seats: A mechanism in lib/, B tests, registry and docs)
lens_set: [writer_reader_drift, guard_without_its_mirror, unawaited_no_error_sink, missing_input, test_honesty, value_semantics_sweep, blast_radius_mismatch]
findings_count: 19
verdict: accepted
verdict_note: every finding dispositioned by the session (founder merge word still pending); no P0; two P1 (test coverage), both fixed
---

# Code Review — 3177bbdb8de3 (goal-change-targets, PR 299)

Reviewed the committed three-dot diff `origin/main...08507462` (CI green on that SHA via `land_pr --ci-only`, base up to date). The fixes below are the staged diff this file is named for. Seat A read `lib/` (mechanism, seven questions answered); seat B read tests, registry, docs and the diagnose doc's mutation table. Neither found a P0.

## Finding 1 — P2 — guard_without_its_mirror (seat A: an unrelated Save rebuilds the targets silently after an in-band weigh-in)
- **file:line:** `edit_profile_screen.dart:2129-2133` with `target_impact.dart` (`targetImpactFor`).
- **claim:** an in-band weigh-in leaves `current_weight_kg` at the raw reading and the targets on `targets_basis_weight_kg` (up to 2 kg away); any later Save re-derives from the raw weight, moves calories, and no input differs from the open snapshot, so no dialog.
- **verification:** read `recalculateTargets` and the `derivationInputsChangedForDialog` gate.
- **status:** accepted, fixed. `_targetsRebasedOnWeight` counts "the basis moved" as a real change; test `edit_profile_target_impact_test.dart` (an unrelated Save after an in-band weigh-in), mutant `no-rebase-impact`.

## Finding 2 — P2 — writer_reader_drift (seat A: the launch restore recomputes from a single raw cloud weight)
- **file:line:** `sync_profile.dart:862-889` (untouched).
- **claim:** device B's restore sees a different cloud raw weight and rebuilds the targets from that one reading, bypassing the 2 kg band, and rewrites the basis.
- **status:** accepted_residual. Recorded in the plan (section 3 B2, "Cross-device residual (accepted)", three review rounds): the restore contract belongs to OI-150, and a change there moves the batch to platform tier (sync engine). Stated again in the diagnose doc's accepted consequences. Ledger: `verified_clean` with notes.

## Finding 3 — P3 — guard_without_its_mirror (seat A: stray keys count as a real local profile; raw DOB compare in the merge)
- **file:line:** `profile_cloud_merge.dart` (`existing.isEmpty` guard, `derivedTargetInputsChanged`).
- **status:** accepted, fixed. `_holdsRealProfile` (a goal or a height, the bootstrapper's own `hiveHasRealData` test) and `derivationInputsChangedForDialog`; tests in `bootstrapper_profile_merge_recompute_test.dart`, mutants `stray-keys-as-real`, `raw-dob-compare`.

## Finding 4 — P3 — guard_without_its_mirror (seat A: invalidation tied to calories/protein moving)
- **file:line:** `home_provider.dart` (`moved`).
- **status:** accepted, fixed. Invalidation and the snapshot push follow the RECOMPUTE (`patch` holds `daily_calories`); `targetsMoved` stays the snackbar's flag.

## Finding 5 — P3 — corrupt-profile reader (seat A: a NaN basis silences the refresh for good)
- **file:line:** `weigh_in_target_refresh.dart` `weighInTargetRefresh`.
- **status:** accepted, fixed. A non-finite, non-positive or non-number basis counts as absent and is re-seeded; test `a stored basis that is not a usable weight`, mutant `nan-basis-not-reseeded`.

## Finding 6 — P3 — integer tenths (seat A: each side rounded before the difference)
- **status:** accepted, fixed. The DIFFERENCE is rounded to tenths; cases that tell the two apart (82.06 vs 80.04, 82.04 vs 79.96) and mutant `band-each-side-rounded` (first run survived, test added, then red).

## Finding 7 — P3 — UX (seat A: the sheet says "Weight logged" when the profile write did not land)
- **status:** false_alarm. The weigh-in itself WAS logged (the health write is separate and succeeded); the line was unconditional before this change. The owner-flip case writes nothing by design.

## Finding 8 — P3 — performance (seat A: `healthBox.toMap()` copies the whole box inside the profile lock)
- **status:** accepted, fixed. Only the `weight_` keys are read.

## Finding 9 — P1 — test_honesty (seat B: the moved-targets side effects are unprotected)
- **file:line:** `home_provider.dart:978-983`.
- **claim:** deleting `invalidateProfileDerivedSurfaces` or the snapshot push left every test green.
- **status:** accepted, fixed. Seam `WeightLogNotifier.debugOnPushSnapshot`; the behavioral test watches `macroTargetsProvider` across an in-band and a drift weigh-in and counts the push. Mutants `no-push`, `no-invalidate` red.

## Finding 10 — P1 — test_honesty (seat B: the weigh-in snackbar and `TargetImpactCopy` have no test)
- **status:** accepted, fixed. `test/home/weight_sheet_target_snackbar_test.dart` (pure copy pins plus the sheet with a stub notifier); mutants `snackbar-swapped`, `snackbar-ternary-inverted`.

## Finding 11 — P2 — test_honesty (seat B: `bodyFatCalcDisabled` never exercised at a new door)
- **status:** accepted, fixed at all four doors: pure refresh, behavioral weigh-in (config switch), pure merge, hydrate call site. Mutants `bodyfat-hardcoded-home`, `bodyfat-dropped-refresh`, `bodyfat-dropped-merge`, `boot-bodyfat-hardcoded`.

## Finding 12 — P2 — test_honesty (seat B: the bootstrapper's kill-switch read is not covered)
- **status:** accepted, fixed. A hydrate case with `disable_profile_target_recompute` set; mutant `boot-killswitch-hardcoded` red.

## Finding 13 — P2 — test_honesty (seat B: the dialog's "to" numbers are never asserted)
- **status:** accepted, fixed. Full lines asserted against the stored profile; mutant `dialog-to-is-from`.

## Finding 14 — P2 — test_honesty (seat B: two absence assertions can pass when the screen never did its work)
- **status:** accepted, fixed. Positive anchors (`PROFILE` after the Save, the saved-plan check icon after reopen).

## Finding 15 — P2 — docs (seat B: two diagnose mutation rows read wrong)
- **claim:** B4-1 and B3-2 "red (1)".
- **status:** accepted, fixed. The red counts of widget runs are the failures printed before the known Hive-close hang of a failing widget test, so they are "at least"; the table says so.

## Finding 16 — P3 — test_honesty (seat B: "Cut never gets less than Build" asserted nothing about Build)
- **status:** accepted, fixed. `cut >= build` in the uncapped region.

## Finding 17 — P3 — dead code (seat B: the `nutrition_repository.dart` pass-through changes nothing observable)
- **status:** false_alarm. Plan round-2 A9 recorded this: kept for consistency, not claimed as a behavioural pin.

## Finding 18 — P3 — registry and doc nits (seat B)
- **status:** accepted, fixed: the registry cites the hydrate and snackbar tests, the `weight_logs` writer note names the refresh, two test headers corrected, diagnose line numbers recomputed.

## Finding 19 — P3 — hygiene (seat B: real-time waits in the positive widget tests)
- **status:** accepted. The waits follow the harness this file copies; they can only fail a positive test, never give a false green.

## Founder triage notes
Pending the founder's word to merge.

## Tuning entry
- **2026-11-18** - blast-radius account - 19 findings; 2 false_alarm; tuning: none (seat B's "surviving mutation" question per assertion found two real P1 coverage holes the author's own mutation pass had missed: ask every B-pass seat B for the five weakest assertions again).
