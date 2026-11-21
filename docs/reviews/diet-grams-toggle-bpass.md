---
reviewed_at: 2026-11-18T19:00:00+05:30
staged_against: 0dc3f563..7d18cb22 (branch diet-grams-toggle, three-dot diff against origin/main)
blast_radius: account
reviewer: claude-sonnet-via-skill (3 fresh seats)
lens_set: [writer_reader_drift, unawaited_no_error_sink, guard_without_its_mirror, missing_input]
findings_count: 6
verdict: accepted
verdict_note: every finding fixed or stated in commit 7d18cb22; the CI run on the pushed head is the remaining gate
---

# Code Review — OI-517 Portions / Grams view (diet-grams-toggle)

Findings from the fresh seats, each closed in `7d18cb22`:

1. **Registry ranges stale (C1/C2, P2).** `docs/sot_registry.yaml` line ranges were not shifted for the files this branch
   edits, and the `diet_serving_view` entry for `diet_plan_screen.dart` cited only `build` although it also names
   `_sharePlanAsPdf`. Fixed: ranges recomputed against the merge's main parent (`0dc3f563^2`), the entry now spans
   484-710; the whole-file `1-9999` sentinels are untouched. `check_sot_registry_parity.dart` passes.
2. **Liquid audit incomplete (P2).** Thirteen more drink / soup rows (F1379, F0740-F0746, F0188-F0192) carried grams
   where ml is meant. Fixed: 145 rows now carry `weight_unit: "ml"`; `food_weight_unit_asset_test.dart` pins the id set
   and a solid-exemption set.
3. **Captions could be truncated at large text scale (P3).** BMR / TDEE / TARGET captions did not shrink. Fixed with a
   `FittedBox` on the calorie card only; the toggle test asserts no figure and no caption is ellipsised at scale 2.0 and
   at 320 dp.
4. **A failed profile write escaped the tap handler (A4, P2).** `setDietServingView` was unawaited with no error sink.
   Fixed with `.catchError` at the call site; test pins no uncaught error and an unmoved switch.
5. **Saved plan without `serving_g` (B5, P3).** A restored plan item missing the key must degrade, not throw. Fixed
   (`?? 0` with the Portions fallback in `servingLabel` for grams below 1) with a screen test.
6. **Switch hit area (P3).** The tappable area was shorter than the card's inner height. Fixed with vertical padding;
   the test requires the switch at least 40 dp tall.

Mutation: each new protection was mutated once and run (red counts recorded in the commit series); a compile error was
not accepted as proof.

## Founder triage notes

Accepted by the author under the standing rule (no deferrals): all six are fixed; `false_alarm` count 0. On-device
real-font check and the APK build remain the founder's.

## Tuning entry
- **2026-11-18** - blast-radius account - 6 findings; 0 false_alarm; tuning: none (a registry range shift must be mapped from the merge's main parent, not the moving `origin/main`).
