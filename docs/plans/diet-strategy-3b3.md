# Diet plan Unit 3b-3: turn the diet strategy on

Revision 1, 2026-11-15. Parent plans: `docs/plans/diet-strategy.md` (Unit 3a, the targets, the selector, the column) and `docs/plans/diet-strategy-3b.md` (Units 3b-1a, 3b-1b, 3b-2). Founder decisions (2026-11-14): Balanced (default), Low carb, Keto; PRO; Option A (carbs and fat change everywhere, calories and protein never); a confirm dialog; no AI; the label "NON-VEG · KETO"; everyday keto foods for veg users; the Keto medical note.

## 1. What changes

One constant: `kDietStrategyDefaultOn = true` (`lib/features/nutrition/services/diet_strategy_flags.dart`). Everything it gates was built and reviewed dark in 3a, 3b-1a, 3b-1b and 3b-2. After the flip `DietStrategyFlags.enabled` is true unless `configBox['disable_diet_strategy'] == true` (the local kill switch, cleared at sign-out).

Branch `diet-strategy-3b3`, stacked on `diet-strategy-3b1b` (PR #277, itself on #275) with `diet-strategy-3b2` (PR #276) merged in. Its own diff is the flip, the tests that assumed the flag off, and the docs.

## 2. What every user sees after the flip (per reader of `DietStrategyFlags.enabled`)

| Reader | Free user / Balanced PRO user | PRO user who picks Low carb or Keto |
|---|---|---|
| `nutrition_provider.dart` `_resolveNutritionTargets` | unchanged numbers; the targets map gains `strategy_index` 0 | carbs / fat from `BmrCalculator.macroSplit`, `strategy_index` 1 or 2 |
| `home_provider.dart` `NutritionSummaryNotifier` | unchanged; now watches the strategy inputs | the strategy's carbs / fat |
| `ai_snapshot_builder.dart` | `profile.diet_strategy: balanced` and its label added; `daily_targets` unchanged | the strategy's carbs / fat and its key (the manual passage, live once ai-proxy carries 3b-2, plans to them) |
| `sync_profile.dart` push | no new column value (absent stays absent, `dietStrategyPushEntry`) | `user_profile.diet_strategy` written (migration 179 live) |
| Diet Plan screen + `DietStrategySection` | the three chips (Low carb / Keto open the paywall for a free user), the plan note logic, saved plans stamped `balanced` | a Low carb / Keto plan, regenerated once per change, the notes, the PDF label |
| `diet_plan_provider.dart` | watches the strategy; a plan saved before the flip (no stamp) still matches Balanced | a plan of another strategy gives no hints |
| Edit Profile | the chips and notes | the confirm dialog on Save |

No stored target is rewritten, no migration runs, and nothing is read that 3a did not already write (the column is NULL for every live row: measured at 3a's apply, 0 non-null rows).

## 3. Release order

1. #275 merges (3b-1a), then #277 (3b-1b), then #276 (3b-2): each with its own founder go. Every one is dark on its own.
2. `ai-proxy` and `weekly-report` are deployed from the merged `main` (one founder go each, rollback dry-run first), so the coach manual knows the strategy BEFORE any app sends it.
3. This PR (3b-3) merges with its own founder go. The web app (vercel) gets the flip at that merge; the Android app at the next `/build-apk`, which the founder starts.

If step 2 has not happened, the flip is still safe: the old manual ignores the new snapshot key, `suggestMeal` (old) ignores the column, the coach plans to the snapshot's `daily_targets` (already the strategy's numbers). Only the keto food rules and the carb cap in suggestions are missing.

## 4. Tests

- Every test that assumed the 3a default (flag off) is found by CI's full suite on this branch, never by a hand-picked subset (§4.12.8). Each one either sets `DietStrategyFlags.debugEnabledOverride = false` (when its subject is the flag-OFF path) or takes the flag-on value (when its subject is something else and the new key is correct), with a line saying which and why.
- The "2b ship-dark identity" group in `test/contracts/diet_strategy_targets_writer_to_reader_test.dart` now runs through the real kill switch (`configBox['disable_diet_strategy'] = true`, no seam) and still proves 3a's identity: after the flip the kill switch IS the off path. Its first test pins `kDietStrategyDefaultOn == true`, the switch, and that only exactly `true` is the switch.
- Mutants: the constant back to false (the pin goes red); the kill switch ignored (`enabled` returns true with the key set: the identity group goes red); the switch read as truthy (`'true'` string turns it off: red).

## 5. Rollback and device check

- One device: `configBox['disable_diet_strategy'] = true` (there is no UI for it; a debug build or the founder's test account via the Hive inspector). Fleet: a build with the constant false; web: revert the flip commit (vercel redeploys).
- Device check by the founder after the build (OI-511 waits on it): a Keto day on a veg and a non-veg profile (the plan has no grain, the label reads "NON-VEG · KETO", the medical note shows); Low carb (one grain at lunch); a PRO lapse (Balanced shown, the choice kept, back with PRO); a change from Edit Profile (the confirm dialog); Vegan + Keto (Keto disabled for a new choice; a held Keto gives a Low carb plan with the vegan line); the PDF label; the coach on a Keto profile (the manual passage, the suggestions without grains or protein powders).
- OI-511 deletes the switch and its OFF paths after that check (CLAUDE.md §4.6 step 4); OI-510 holds the server switches.

## 6. Ship-dark ledger

`docs/ship_dark_pending_review.yaml`: the `kDietStrategyDefaultOn` entry moves to `resolved:` in this commit, with `flip_reviewed: true` and `flip_review_record: docs/plan-reviews/diet-strategy-3b3.md` (full ×2 review + `bpass: accepted`); `flip_commit` is stamped after the merge.
