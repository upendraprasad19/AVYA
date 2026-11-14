# Diet plan Unit 3b-3: turn the diet strategy on

Revision 4, 2026-11-15 (round 1 dispositions in §7, round 2 in §8, the B-pass in §9). Parent plans: `docs/plans/diet-strategy.md` (Unit 3a, the targets, the selector, the column) and `docs/plans/diet-strategy-3b.md` (Units 3b-1a, 3b-1b, 3b-2). Founder decisions (2026-11-14): Balanced (default), Low carb, Keto; PRO; Option A (carbs and fat change everywhere, calories and protein never); a confirm dialog; no AI; the label "NON-VEG · KETO"; everyday keto foods for veg users; the Keto medical note.

## 1. What changes

One constant: `kDietStrategyDefaultOn = true` (`lib/features/nutrition/services/diet_strategy_flags.dart`). Everything it gates was built and reviewed dark in 3a, 3b-1a, 3b-1b and 3b-2. After the flip `DietStrategyFlags.enabled` is true unless `configBox['disable_diet_strategy'] == true` (the local kill switch, cleared at sign-out).

Branch `diet-strategy-3b3`, stacked on `diet-strategy-3b1b` (PR #277, itself on #275) with `diet-strategy-3b2` (PR #276) merged in. Its own diff is the flip, the tests that assumed the flag off, and the docs.

## 2. What every user sees after the flip (per reader of `DietStrategyFlags.enabled`)

| Reader | Free user / Balanced PRO user | PRO user who picks Low carb or Keto |
|---|---|---|
| `nutrition_provider.dart` `_resolveNutritionTargets` | unchanged numbers and the same map (Balanced carries no `strategy_index`: absent = Balanced) | carbs / fat from `BmrCalculator.macroSplit`, `strategy_index` 1 or 2 |
| `home_provider.dart` `NutritionSummaryNotifier` | unchanged; now watches the strategy inputs | the strategy's carbs / fat |
| `ai_snapshot_builder.dart` (the chat snapshot AND the daily snapshot push, `sync_service.dart` `buildAiContext`, into `user_daily_snapshot`) | `profile.diet_strategy: balanced` and its label added (about 60 characters; `profile` is in the trim keep set, far under the 8,500 budget); `daily_targets` unchanged | the strategy's carbs / fat and its key (the manual passage, live once ai-proxy carries 3b-2, plans to them) |
| `sync_profile.dart` push | a value only when the profile already holds a strategy (absent stays absent, `dietStrategyPushEntry`; a lapsed or restored PRO user pushes the held key, always canonical, so the 179 CHECK cannot fail) | `user_profile.diet_strategy` written (migration 179 live) |
| Diet Plan screen + `DietStrategySection` | the three chips (Low carb / Keto open the paywall for a free user), the plan note logic, saved plans stamped `balanced` | a Low carb / Keto plan, regenerated once per change, the notes, the PDF label |
| `diet_plan_provider.dart` | watches the strategy; a plan saved before the flip (no stamp) still matches Balanced, so it keeps loading and giving hints | a plan of another strategy gives no hints |
| Edit Profile | the chips and notes | the confirm dialog on Save |

A PRO user who already holds Low carb or Keto (a tester of a dev build, or restored from the cloud column) and has a plan saved before the flip (no stamp): that plan matches Balanced only, so after the flip it gives no hints and the screen generates a fresh strategy plan with no notice; the old plan stays saved until they press Save (round 2 finding 2; 3b-1b's design, pinned by the screen test "an unstamped plan with Keto effective"). Pre-launch this is only test accounts.

Two more user classes (round 1 finding 6):

- **A PRO user with a stored strategy but no stored macro pack** (a profile that never got its targets; onboarding writes all four, so not seen in practice): Nutrition applies the strategy to its recompute fallback, while Home and the coach apply it only to a complete stored pack and show Balanced. This split is 3a's stated limit (registry `diet_strategy_targets`, "Stated limit"), unchanged by the flip; accepted.
- **Signed out or before onboarding**: `_resolveNutritionTargets(null)` returns the hard-coded defaults and never applies a strategy; no chip is reachable. Unchanged.

No stored target is rewritten, no migration runs, and nothing is read that 3a did not already write (the column is NULL for every live row: measured at 3a's apply, 0 non-null rows).

## 3. Release order

1. #275 merges (3b-1a), then #277 (3b-1b), then #276 (3b-2): each with its own founder go. Every one is dark on its own.
2. `ai-proxy` and `weekly-report` are deployed from the merged `main` (one founder go each, rollback dry-run first), so the coach manual knows the strategy BEFORE any app sends it. **A hard gate for step 3** (round 1 finding 5): before asking for the 3b-3 go, read both functions' live versions (API `GET /functions/<slug>`) and confirm they are the step-2 deploys. Without them the deployed coach has no `daily_targets` instruction and no carb cap: a Keto user could be offered rice and protein powders beside a 30 g carb target.
3. Just before the go, re-measure the live column: `select count(*) filter (where diet_strategy is not null), count(*) from user_profile` (expected: only test accounts that tried a strategy on a dev build) and confirm migration 179 is listed (round 1 finding 7).
4. This PR (3b-3) merges with its own founder go. The web app (vercel) gets the flip at that merge; the Android app at the next `/build-apk`, which the founder starts.

3b-3 contains the code of all three, so merging it first would land everything at once, but it must NOT merge before step 2 even so: the Edge Functions deploy from `main` after a merge, so 3b-3 first would flip the web app before the coach knows the strategy (round 2 finding 3). The PR body carries the step-2 check as a box the founder ticks before the go (round 2 finding 1).

Order of #275 / #277 / #276 among themselves does not matter for the code (each is dark; 3b-3 contains all three), but #277 sits on #275.

## 4. Tests

- Every test that assumed the 3a default (flag off) is found by CI's full suite on this branch, never by a hand-picked subset (§4.12.8). Each one either sets `DietStrategyFlags.debugEnabledOverride = false` (when its subject is the flag-OFF path) or takes the flag-on value (when its subject is something else and the new key is correct), with a line saying which and why.
- The "2b ship-dark identity" group in `test/contracts/diet_strategy_targets_writer_to_reader_test.dart` now runs through the real kill switch (`configBox['disable_diet_strategy'] = true`, no seam) and still proves 3a's identity: after the flip the kill switch IS the off path. Its first test pins `kDietStrategyDefaultOn == true`, the switch, and that only exactly `true` is the switch.
- What the kill switch is pinned for: the snapshot, the push call site and the three targets readers (contract test 4, the identity group). An already-open screen is not (it reads the switch at its next build, §5).
- Mutants: the constant back to false (the pin goes red); the kill switch ignored (`enabled` returns true with the key set: the identity group goes red); the switch read as truthy (`'true'` string turns it off: red).

## 5. Rollback and device check

- One device: `configBox['disable_diet_strategy'] = true` (there is no UI for it; a debug build or the founder's test account via the Hive inspector). It is read when a provider builds, not watched (round 1 finding 1): the coach snapshot and the profile push follow it at once (both rebuild per call); the targets providers, the Diet Plan provider and an open Diet Plan screen follow it on their next rebuild, in practice the next app start. Fleet: a build with the constant false; web: revert the flip commit (vercel redeploys). There is no remote lever. That is acceptable only because every account is a testing account before the store launch (CLAUDE.md §1); the same basis covers rolling the gate at the web merge rather than after a manual check (CLAUDE.md §4.6 step 3): the founder's device check follows on the testing accounts. OI-511 removes the switch after that check, still before the launch: the old path's deletion is founder-scheduled after the device check (CLAUDE.md §4.6 step 4), tracked as OI-511. Sign-out clears the switch: `UserRepository.clearAllData` clears `configBox` (verified, `lib/shared/repositories/user_repository.dart`).
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

## 8. Round 2 dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | the new snapshot keys are not in `docs/snapshot_contract.yaml`; the daily snapshot push carries them too; the deploy gate is prose only | contract `profile` shape lists `diet_strategy` / `diet_strategy_label` and the `daily_targets` carbs/fat meaning; §2 names the daily push and the size; the PR body has the step-2 check box. The only server reader of `daily_targets` is `protein-gap-alert`, protein only |
| 2 | P2 | an unstamped pre-flip plan of a PRO Low carb / Keto user silently stops giving hints | stated in §2 (3b-1b's design); screen test "an unstamped plan with Keto effective" pins: no hints, a fresh plan, no snackbar |
| 3 | P3 | 3b-3 first would flip before the deploys | §3: must not merge before step 2 |
| 4 | P3 | the push cell overstated | reworded |
| 5 | P3 | what the switch is pinned for | §4 |
| 6 | P3 | `clearAllData` clearing configBox unverified | verified and cited (§5) |
| 7 | P3 | §4.6 step 4 framing | §5: founder-scheduled, OI-511 |

## 9. B-pass dispositions

Three context-blind seats on `248fe49e` (`docs/reviews/diet-strategy-3b3-bpass.md`). No P0 or P1.

| Seat / # | Sev | Finding | Disposition |
|---|---|---|---|
| A2 | P2 | `weekly-report` shows the week's average carbs with no target and no strategy: the model may tell a Keto user to eat more carbs | fixed on #276 (`3321a9f3`, merged here): `weeklyReportDietStrategyLine` under the protein target for a PRO Low carb / Keto user, off with `DISABLE_DIET_STRATEGY_MANUAL_RULES`; ships with the step-2 deploy (§3), so before this flip; mutants M1–M8 red |
| A3 | P2 | the client applies the strategy only on a complete stored pack; `suggestMeal` caps carbs for any PRO user holding Low carb / Keto | accepted: an incomplete pack is the 3a stated limit (§2, onboarding writes all four targets), and the server cap follows the user's own choice (fewer carbs for someone who picked Keto), the safe direction; the cloud value lags the local one only until the profile push lands |
| A1 | P3 | "only the chat snapshot carries `profile.diet_strategy`" was false (the daily push carries it) | reworded in the manual comment, `supabase/functions/CLAUDE.md`, the registry (on #276) and `docs/snapshot_contract.yaml`; no prompt builder reads a stored snapshot |
| A4 | P3 | a restore merges every non-null cloud key, so an unpushed local change can be reverted by an older cloud value | accepted: the same merge rule as every profile field (`_restoreUserProfile`); the window is a choice not yet pushed when a restore runs; pre-launch, test accounts only |
| A5 | P3 | an older build ignores the stamps and loads a Keto plan as a normal plan | accepted: pre-launch, test accounts only; the Android app gets the flip and the stamp check in the same build |
| B1 | P2 | the kill switch is client-only; the server cap still applies | the flag header names the server switches (`DISABLE_SUGGESTMEAL_DIET_STRATEGY`, `DISABLE_DIET_STRATEGY_MANUAL_RULES`); OI-510 holds them |
| B2 | P3 | an unreadable box reads as ON | accepted with the reason in the header: configBox opens before `runApp` and is cleared, never closed, at sign-out, so only Hive-less tests reach the catch (pinned) |
| B3 | P3 | the flag-on sweep | CI run 43636703531 ran the full suite on the flip: two failures, both in `diet_plan_screen_no_modal_test.dart`, fixed in `248fe49e` |
| B4 | P3 | no in-app lever | stated in the header and §5 |
| C1 | P2 | the push pin matched a commented-out call and any call outside the pushed map | comments stripped; the call must sit inside the `payload` map that `_syncUserProfile` upserts, once in the file; plus the call-site expression run against the real switch (no seam). Mutants N1 (commented), N2 (`enabled: true`) red |
| C2 | P2 | the build-constant guard cannot run while the constant is true | a pin on the order in `enabled`: seam, then the constant, then the box. Mutants N3 (guard deleted), N4 (guard before the seam) red |
| C3 | P2 | no screen test through the real switch | a screen test with no seam and the real key: no strategy section, a stamped Keto plan loads with no generation, nothing stamped on save. Mutants N5 (key ignored, 9 red), N6–N9 (each screen gate forced) red |
| C4 | P3 | the unstamped-plan test relied on the default food type | the seed names `non_veg` |
| C5 | P3 | the lock loop stopped at the first call | a second wait and a re-check that it is still exactly one |
| C6 | P3 | the no-Hive test did not assert its precondition | it asserts `configBox` throws first |

