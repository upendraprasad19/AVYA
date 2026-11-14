# Diet plan Unit 3b-3: turn the diet strategy on

Revision 2, 2026-11-15 (round 1 dispositions in §7). Parent plans: `docs/plans/diet-strategy.md` (Unit 3a, the targets, the selector, the column) and `docs/plans/diet-strategy-3b.md` (Units 3b-1a, 3b-1b, 3b-2). Founder decisions (2026-11-14): Balanced (default), Low carb, Keto; PRO; Option A (carbs and fat change everywhere, calories and protein never); a confirm dialog; no AI; the label "NON-VEG · KETO"; everyday keto foods for veg users; the Keto medical note.

## 1. What changes

One constant: `kDietStrategyDefaultOn = true` (`lib/features/nutrition/services/diet_strategy_flags.dart`). Everything it gates was built and reviewed dark in 3a, 3b-1a, 3b-1b and 3b-2. After the flip `DietStrategyFlags.enabled` is true unless `configBox['disable_diet_strategy'] == true` (the local kill switch, cleared at sign-out).

Branch `diet-strategy-3b3`, stacked on `diet-strategy-3b1b` (PR #277, itself on #275) with `diet-strategy-3b2` (PR #276) merged in. Its own diff is the flip, the tests that assumed the flag off, and the docs.

## 2. What every user sees after the flip (per reader of `DietStrategyFlags.enabled`)

| Reader | Free user / Balanced PRO user | PRO user who picks Low carb or Keto |
|---|---|---|
| `nutrition_provider.dart` `_resolveNutritionTargets` | unchanged numbers and the same map (Balanced carries no `strategy_index`: absent = Balanced) | carbs / fat from `BmrCalculator.macroSplit`, `strategy_index` 1 or 2 |
| `home_provider.dart` `NutritionSummaryNotifier` | unchanged; now watches the strategy inputs | the strategy's carbs / fat |
| `ai_snapshot_builder.dart` | `profile.diet_strategy: balanced` and its label added; `daily_targets` unchanged | the strategy's carbs / fat and its key (the manual passage, live once ai-proxy carries 3b-2, plans to them) |
| `sync_profile.dart` push | no new column value (absent stays absent, `dietStrategyPushEntry`) | `user_profile.diet_strategy` written (migration 179 live) |
| Diet Plan screen + `DietStrategySection` | the three chips (Low carb / Keto open the paywall for a free user), the plan note logic, saved plans stamped `balanced` | a Low carb / Keto plan, regenerated once per change, the notes, the PDF label |
| `diet_plan_provider.dart` | watches the strategy; a plan saved before the flip (no stamp) still matches Balanced | a plan of another strategy gives no hints |
| Edit Profile | the chips and notes | the confirm dialog on Save |

Two more user classes (round 1 finding 6):

- **A PRO user with a stored strategy but no stored macro pack** (a profile that never got its targets; onboarding writes all four, so not seen in practice): Nutrition applies the strategy to its recompute fallback, while Home and the coach apply it only to a complete stored pack and show Balanced. This split is 3a's stated limit (registry `diet_strategy_targets`, "Stated limit"), unchanged by the flip; accepted.
- **Signed out or before onboarding**: `_resolveNutritionTargets(null)` returns the hard-coded defaults and never applies a strategy; no chip is reachable. Unchanged.

No stored target is rewritten, no migration runs, and nothing is read that 3a did not already write (the column is NULL for every live row: measured at 3a's apply, 0 non-null rows).

## 3. Release order

1. #275 merges (3b-1a), then #277 (3b-1b), then #276 (3b-2): each with its own founder go. Every one is dark on its own.
2. `ai-proxy` and `weekly-report` are deployed from the merged `main` (one founder go each, rollback dry-run first), so the coach manual knows the strategy BEFORE any app sends it. **A hard gate for step 3** (round 1 finding 5): before asking for the 3b-3 go, read both functions' live versions (API `GET /functions/<slug>`) and confirm they are the step-2 deploys. Without them the deployed coach has no `daily_targets` instruction and no carb cap: a Keto user could be offered rice and protein powders beside a 30 g carb target.
3. Just before the go, re-measure the live column: `select count(*) filter (where diet_strategy is not null), count(*) from user_profile` (expected: only test accounts that tried a strategy on a dev build) and confirm migration 179 is listed (round 1 finding 7).
4. This PR (3b-3) merges with its own founder go. The web app (vercel) gets the flip at that merge; the Android app at the next `/build-apk`, which the founder starts.

Order of #275 / #277 / #276 among themselves does not matter for the code (each is dark; 3b-3 contains all three), but #277 sits on #275.

## 4. Tests

- Every test that assumed the 3a default (flag off) is found by CI's full suite on this branch, never by a hand-picked subset (§4.12.8). Each one either sets `DietStrategyFlags.debugEnabledOverride = false` (when its subject is the flag-OFF path) or takes the flag-on value (when its subject is something else and the new key is correct), with a line saying which and why.
- The "2b ship-dark identity" group in `test/contracts/diet_strategy_targets_writer_to_reader_test.dart` now runs through the real kill switch (`configBox['disable_diet_strategy'] = true`, no seam) and still proves 3a's identity: after the flip the kill switch IS the off path. Its first test pins `kDietStrategyDefaultOn == true`, the switch, and that only exactly `true` is the switch.
- Mutants: the constant back to false (the pin goes red); the kill switch ignored (`enabled` returns true with the key set: the identity group goes red); the switch read as truthy (`'true'` string turns it off: red).

## 5. Rollback and device check

- One device: `configBox['disable_diet_strategy'] = true` (there is no UI for it; a debug build or the founder's test account via the Hive inspector). It is read when a provider builds, not watched (round 1 finding 1): the coach snapshot and the profile push follow it at once (both rebuild per call); the targets providers, the Diet Plan provider and an open Diet Plan screen follow it on their next rebuild, in practice the next app start. Fleet: a build with the constant false; web: revert the flip commit (vercel redeploys). There is no remote lever. That is acceptable only because every account is a testing account before the store launch (CLAUDE.md §1); the same basis covers rolling the gate at the web merge rather than after a manual check (CLAUDE.md §4.6 step 3): the founder's device check follows on the testing accounts. OI-511 removes the switch after that check, still before the launch.
- Device check by the founder after the build (OI-511 waits on it): a Keto day on a veg and a non-veg profile (the plan has no grain, the label reads "NON-VEG · KETO", the medical note shows); Low carb (one grain at lunch); a PRO lapse (Balanced shown, the choice kept, back with PRO); a change from Edit Profile (the confirm dialog); Vegan + Keto (Keto disabled for a new choice; a held Keto gives a Low carb plan with the vegan line); the PDF label; the coach on a Keto profile (the manual passage, the suggestions without grains or protein powders).
- OI-511 deletes the switch and its OFF paths after that check (CLAUDE.md §4.6 step 4); OI-510 holds the server switches.

## 6. Ship-dark ledger

`docs/ship_dark_pending_review.yaml`: the `kDietStrategyDefaultOn` entry moves to `resolved:` with `flip_review_record: docs/plan-reviews/diet-strategy-3b3.md`. `flip_reviewed` turns true in the SAME commit that sets the record to `verdict: converged` and `bpass: accepted` (round 1 finding 4), never before. `flip_commit` is the merge commit; it is stamped by the session that lands the merge, in the OI-511 commit at the latest (it cannot be known before the merge).

## 7. Round 1 dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | the kill switch is read at build, not watched; "at once" was wrong; test 4 used the seam | §5 and the flag header say which readers follow at once and which on the next rebuild; test 4 now sets the real key |
| 2 | P2 | the profile push call site had no test | a source pin on `dietStrategyPushEntry(p, enabled: DietStrategyFlags.enabled)` in `sync_profile.dart`, mutated |
| 3 | P2 | record said account | platform (`docs/blast_radius.yaml`: `diet_strategy_flags.dart` is platform) |
| 4 | P2 | §4.6 step 3 basis unstated; ledger resolved before its evidence | the pre-launch basis in §5; `flip_reviewed` turns true with the converged record; `flip_commit` owner named (§6) |
| 5 | P2 | "safe without the deploys" overstated | the deploys are a hard gate before the 3b-3 go, verified by version (§3) |
| 6 | P3 | row 1 wrong; two user classes missing | row 1 fixed; rows added under the table |
| 7 | P3 | ai_coach CLAUDE.md said "shipped dark"; the 0-row figure is old | row updated; the count is re-measured before the go (§3 step 3) |
| 8 | P3 | the catch fallback now means ON for a test with no Hive | a test pins `enabled == true` with no Hive and no seam (mutant: the catch returns false); sign-out clearing the key is `clearAllData` clearing configBox, unchanged |
| 9 | P3 | no remote lever | stated in §5 with the launch ordering |

