# Diet plan Unit 4: supplements (opt-in, PRO)

Revision 3, 2026-11-15 (round 1 dispositions in §10, round 2 in §11). Parent: the four-unit diet overhaul (Unit 1 food quality, Unit 2 food type, Unit 3 diet strategy, all shipped). Founder decisions (2026-11-14): an opt-in toggle, PRO; a protein shake (generic whey, plant protein for a vegan) placed in a slot; a daily stack card (creatine, vitamin D3, omega-3 with an algal source for non-fish eaters, B12 for veg / eggetarian / vegan, multivitamin optional); NO pre-workout product, and a line "Optional: black coffee 30-45 min before training"; no brands; doses from `captain_manual.ts` SECTION 5 only; hidden for under-18.

Creatine is 5 g, not the board's "3-5 g": SECTION 5 says "5g daily" and "Never recommend doses outside the bands above".

Nutrition CLAUDE.md already says "Unit 4 whey closes it": veg / vegan CUT plans average about 80 % of the protein target by design of the curated catalog. The shake is the closer.

## 1. What the user gets

A PRO user turns on **Supplements** on the Diet Plan screen (a switch under the strategy chips). Then:

1. **A protein shake item** in the day's evening snack slot (`slotKey == 'evening'`; both generators always emit it) when the day is short of the protein target by 15 g or more (§3 says how it makes room when the day has no calories to spare). One scoop, generic row: Whey Isolate (Generic, `F0823`) for every food type except vegan; Plant Protein (Pea, `F0831`) for a vegan. Calories, protein, carbs, fat come from the food row, so the day's totals include it.
2. **A stack card** under the plan (rows and wording in §4).
3. The PDF carries the shake (it is an ordinary item) and the stack card.
4. Free user: the switch opens the paywall. A lapsed PRO user with the switch on sees "Supplements paused while PRO is off" (like `dietStrategyPausedHint`), and the stored choice is kept. Under-18: the whole section is absent. No readable date of birth: one line, "Add your date of birth in Edit Profile to unlock Supplements", and nothing else (a blank date of birth is documented history, `onboarding_chat_screen.dart`, so real users reach it).

A user who NEVER set the key (absent): every output is byte-identical to today: the generated plan, the saved plan JSON, the snapshot, the profile push, the PDF inputs (§7 states how each is pinned). A user who turned it on and then off has `diet_supplements: false` stored and PUSHED, so off reaches the cloud (a restore merge ignores a cloud NULL, so dropping the `false` would let a stale cloud `true` switch it back on); that case has its own pin.

## 2. State, the one rule, the write door

- **Storage.** Profile key `diet_supplements` (a bool; absent = off): Hive profile and a new nullable column `user_profile.diet_supplements boolean` (migration number from `scripts/mint_migration.sh`, not assumed; no default, NULL = off). Push: `dietSupplementsPushEntry(profile, enabled: flag)` adds the key only when the profile holds a bool. Restore needs no change (`_restoreUserProfile` merges every non-null cloud key; the restore edge function selects `*`).
- **The ONE rule.** `lib/core/utils/diet_supplements_rule.dart` `dietSupplementsActive({profile, pro, enabled, now})` = `enabled && pro && profile['diet_supplements'] == true && adult`, with `adult = ageYearsOn(profile['date_of_birth'], now) >= 18`.
  - `ageYearsOn` is new and pure. Of the eight or so existing age readers (`ai_snapshot_builder._calculateAge`, `stat_snapshot_service._ageFromDob`, `nutrition_provider`, `profile_target_recompute`, `onboarding_provider`, `edit_profile_screen`, `user_repository`, `nutrition_repository`) most fall back to an age (25, 0), the wrong direction for a minors gate, and the one that returns null (`_ageFromDob`) is private to a stat service; this one returns null for a missing, blank or unparseable value, a future date, or an age over 120, and null is NOT adult. Birthday compare is by month and day, so 29 February counts as 1 March in a non-leap year (the conservative choice for "under 18"; `latestAllowedDob` clamps the other way, for a different question). `now` is the injected device clock (`DateTime.now()` at the call site; no IST, an age is not a day key).
  - The gate is self-attested: onboarding stores whatever date the user picks, and the conversational step seeds an unanswered date at 1 Jan 1998 (`onboarding_chat_screen.dart`), so a minor who taps Next reads as an adult. That is an existing hole in every age reader. Pre-launch every account is a test account (CLAUDE.md §1), so it is parked on the OI board with `reopen_when: store launch`, not fixed here.
  - Every reader calls this function. The eligibility helper `dietSupplementsEligible(profile, enabled, now)` (flag and adult, no PRO, no toggle) decides whether the section is shown at all.
- **Provider.** `dietSupplementsActiveProvider` (in `lib/features/nutrition/providers/diet_supplements_active_provider.dart`): `ref.watch(userProfileProvider.select(...))` for the two keys, `subscriptionInfoProvider.select((s) => s.isPro)` and `restoreCompletedTickProvider`, like `_watchDietStrategyInputs`; with the flag off it watches none of them (a flag-off reader keeps exactly its pre-Unit-4 dependency set, an identity pin). `DietPlanNotifier` reads it; nothing invalidates `dietPlanProvider` from inside the profile notifier (that is a `CircularDependencyError`, noted at `setDietStrategy`). `now` is read when the provider builds, so a long-lived web session does not see a birthday pass until a watched input changes; that only delays an adult (fail safe).
- **Placement.** The section is mounted OUTSIDE the `if (DietStrategyFlags.enabled)` block, so the strategy kill switch does not hide it, and inside its own `DietSupplementsFlags.enabled` check.
- **Write door.** `UserProfileNotifier.setDietSupplements(bool)`, the only writer: serialised through a chain like `setDietStrategy`, drops the call when the account changed while queued, writes through `updateProfile`, then pushes the snapshot. Returns true when the stored value equals the request afterwards.
- **Flag.** `DietSupplementsFlags.enabled` = `kDietSupplementsDefaultOn` (true) unless `configBox['disable_diet_supplements'] == true`; seam `debugEnabledOverride`; the catch returns the build default; `clearAllData` clears the switch. Default ON is safe because the per-user opt-in is itself off for everyone until chosen. The switch is client-only (the coach manual has its own, §6); the header says so. Removal of the client flag and its OFF paths is ONE new OI minted in the first commit (§4.6 step 4, after the founder's device check); the manual switch joins OI-510's existing list.
- **PRO.** `AppConstants.featureDietSupplements`, listed in `subscription_service.dart` beside `featureDietStrategy`; the screen asks `gateAndVerify` (`gate()` is deprecated); this is a local PRO check like the strategy, not a CLAUDE.md rule-19 server-verified feature. Paywall copy: a label constant `kDietSupplementsPaywallLabel = 'Diet Supplements'`, a `case 'Diet Supplements'` subtitle in `paywall_sheet.dart`, and an entry in `test/contracts/paywall_feature_label_test.dart`. A PRO lapse reads as inactive; the stored choice is kept.

## 3. The shake (a pure post-process)

`lib/features/nutrition/services/diet_plan_shake.dart`:

- `kSupplementShakeFoodIds = {'F0823', 'F0831'}` (a test asserts it is disjoint from `kDietPlanCatalog` ids, so a future catalog addition cannot make a generated item look like a shake) and `isSupplementShake(foodId)`. The shake is identified by its food id, a pure function: no new item key is written to the saved plan (item roles are deliberately never saved; a saved or restored plan must behave the same as a fresh one).
- `addProteinShake({meals, proteinTarget, calorieTarget, foodType, row})`: the day's items summed; gap = `proteinTarget - protein`. When `gap >= 15`: if `dayCalories + shakeKcal <= calorieTarget * 1.08` the shake (one scoop, multiplier 1.0) is appended to the evening slot. If it does not fit, the evening slot's items are removed in ascending protein-per-kcal order until it fits; the shake is added only if the net protein gain is more than 8 g, otherwise nothing changes (the card still shows). A missing food row (`getById` null: a stale food box is documented) means no shake and no throw. The item is built from the food row by a small `shakeItem(row)` builder (a synthetic item: no `CatalogEntry`, no role). Pure, input not mutated.
- Why replace instead of a plain ceiling: measured on the real generator (16 archetypes x 50 seeds, scratch test, deleted; numbers in §12), a plain 1.08 ceiling put the shake on 1 of 50 days for the 1200 kcal veg archetype, 13 of 47 for cut female veg and 23 of 45 for cut vegan, exactly where the protein gap is. Replacing the lowest-protein-density snack item(s) reaches 49 of 50, 47 of 47 and 45 of 45, ends the day at 1.03 to 1.05 of the calorie target, and removes under one item per shake on average. The user sees the shake in the Evening Snack in place of a fruit or similar item; nothing else moves.
- Called by the Diet Plan screen only when `dietSupplementsActive`, on the service-level plan right after it is obtained, reading the row through `FoodRepository.instance` like `_swapItem`. It is outside `generatePlan`, so G1/G2 and every generator test are untouched; `plan_generator.dart` is not touched (rule 14). Two existing source pins constrain the edit and must stay green: `test/contracts/diet_plan_curated_switch_test.dart` (it slices `_generateFreshPlan` up to `_servicePlanToScreenPlan`, asserts the exact `generatePlan(inputs)` ternary and that the body has no `HiveService`) and `test/nutrition/diet_plan_pdf_test.dart` (the literal `planNote: _planNote(targets),`).
- Under Keto the shake is allowed (isolate 0.3 g carbs, pea 1.8 g, under `kKetoItemCarbCap` 6 g); a vegan Keto request is already a Low carb plan (3b-1a). `suggestMeal` leaves powders out of its own suggestions under a carb cap (3b-2); that is intended and separate (the coach picks foods for a meal, the plan places a defined scoop).
- Swap icon: the screen renders none for an item where `isSupplementShake(foodId)` (a saved or restored plan too). The catalog-only swap sheet knows no powder; turning the switch off removes the shake.
- Saved-plan stamp: a screen field `_planSupplements` (like `_planStrategy`) is set at generation and at load; `diet_supplements: true` is written from it ONLY when true (absent = false; the strategy stamp is conditional the same way), so an off user's saved plan JSON, and the cloud `plan_json`, are unchanged. `savedPlanMatchesSupplements(plan, active)` is consulted only with `DietSupplementsFlags.enabled` (with the kill switch a stamped plan simply loads: the shake shows, nothing disappears). A plan whose stamp differs from the active value does not load (no hints; a fresh plan). A change of `dietSupplementsActive` regenerates once, like `_onEffectiveStrategy` (the listener resets `_checkedSaved` and `_regenerations` as that one does), guarded by a pure `dietPlanNeedsRegenerationForSupplements(planEpoch, planActive, active)` in `lib/features/nutrition/services/diet_plan_supplements_state.dart`; toggling restarts from the day's seed, so unsaved swaps are lost (as with a strategy change).
- Calorie effect: the shake adds about 110 kcal and counts in the day's totals; with the replacement rule the day ends within 1.08 of the target (a test over the 16 archetypes asserts it).

## 4. The stack card

`lib/core/constants/diet_supplement_doses.dart` is the one place a number appears. Each row has a rendered `dose` string for the card and a `manualToken` (§6) that the coach manual contains. `supplementCardFor(FoodType)` (the user-facing term is the supplement card, not "stack", which already means subscription stacking in the glossary) returns the ordered rows:

| Row | Who | Card dose | Manual token |
|---|---|---|---|
| Creatine monohydrate | everyone | 5 g daily, any time | `5g daily` |
| Vitamin D3 | everyone | 1000-2000 IU a day; get a 25(OH)D serum test before taking a high dose | `1000-2000 IU/day` |
| B12 | veg, eggetarian, vegan | 500-1000 mcg a week, under the tongue | `500-1000 mcg/wk` |
| Omega-3 EPA+DHA | everyone | 2-3 g a day; algal source for veg, eggetarian, vegan, fish oil or oily fish for non-veg and pescatarian | `2-3g/day` |
| Multivitamin | everyone, optional | one a day as its label says; not a substitute for food (no number) | (added to the manual in 4b-server) |

Footer lines (constants, ASCII only because the PDF uses its default font): "Optional: black coffee 30-45 min before training. No pre-workout product is needed."; "Talk to your doctor first if you have a heart, kidney or liver condition, or if you are pregnant or breastfeeding." (pregnancy goes beyond the manual's list on purpose: it is the conservative direction, and the manual passage carries the same words); "The plan, the protein and sleep do most of the work."

`lib/features/nutrition/widgets/diet_supplements_section.dart` holds the switch and the card: a `WardCard` with a titled row and a Material `Switch` in a `ListTile`-sized row (the 36x20 `WardToggle` is a small tap target), Wardroom palette, `AppTypography` fonts (no raw `GoogleFonts`; Gate 37), the Wardroom brand soul (`lib/shared/widgets/wardroom/CLAUDE.md`) loaded before the copy is written. A static list needs no loading / error state; the empty state is the switch off. It is built only when `dietSupplementsEligible`; free users see the switch locked.

## 5. The 800-line ceiling

`diet_plan_screen.dart` is 794 lines and `scripts/check_god_screen_max_lines.dart` fails at 800. The FIRST commit of 4a extracts the pure TDEE / stat / macro-circle builders (`_buildTdeeCard`, `_statColumn`, `_buildMacroTargets`, `_macroCircle`, about 90 lines) into `lib/features/nutrition/widgets/diet_plan_macro_cards.dart` with no behaviour change (the existing screen tests are the pin, run before and after). The seams the feature adds to the screen are then (the `_planSupplements` field, its guard call, and the above): the generation call, the `_savePlan` stamp, the `_loadSavedPlan` match, the swap-icon condition, the section mount, the regeneration listener (kept to the strategy listener's size by reading `dietSupplementsActiveProvider`), and the PDF argument; budget 35 lines, so the screen ends under 760.

## 6. Coach and manual: landing 4b-server FIRST

Server-only, merged and deployed BEFORE the client (Unit 3's order), inert until an app sends the key:

- `captain_manual.ts` SECTION 5 gains ONE passage `DIET_SUPPLEMENTS_MANUAL_PASSAGE`, outside the food-type and strategy strings, removed by the kill switch with the same `base.replace(PASSAGE, "")` mechanism as `DIET_STRATEGY_MANUAL_PASSAGE`. Every line in it is conditional on `snapshot.profile.diet_supplements` being true, so nothing is standing text for a free user or a 13-17 year old: "If snapshot.profile.diet_supplements is true the user turned on Supplements: their plan MAY have a protein shake in the evening snack (a post-workout scoop works too) and the app shows a supplement card with the same doses; refer to them, never change a dose in chat. B12 and an algal omega-3 are for vegetarians, eggetarians and vegans; non-veg and pescatarian users take fish oil or oily fish. Multivitamin: optional, one a day as its label says, not a substitute for food. Black coffee, no sugar, 30-45 min before training is fine; still no pre-workout product. Anyone with a heart, kidney or liver condition, or who is pregnant or breastfeeding, checks with their doctor first." Kill switch `DISABLE_DIET_SUPPLEMENTS_MANUAL_RULES` (exactly `"true"`, read per call), composed in `captainManual()` after the strategy switch, added to OI-510's list; a test shows the switch removes the passage byte-exactly (like `captain_manual_diet_strategy_test.ts`). `ai-proxy` and `weekly-report` bundle the manual (weekly-report never receives the snapshot key, so the passage is inert there): deploy one founder go each, rollback dry-run first, versions read back.
- `supabase/functions/_shared/testdata/supplement_card.json`: food type -> row keys and manual tokens. A Deno test reads it and asserts every token is a substring of the manual's SECTION 5 text (token-level, not the card's sentences: the card says "5 g daily", the manual "5g daily, any time"), and that the food-type rows for B12 and the algal omega-3 equal the mapping the new passage states (vegetarian, eggetarian, vegan), so the test has something to assert.
- `docs/snapshot_contract.yaml` lists `profile.diet_supplements`: present as `true` ONLY when `dietSupplementsActive` holds (the builder reads `SubscriptionService.instance.proStateSnapshot()` like `_dietStrategyTargets`), absent otherwise, so the coach never talks about a card a lapsed-PRO user or a minor does not see. The chat snapshot and the daily snapshot push both carry it; no prompt builder reads a stored snapshot. The builder lands with 4a (it needs the rule); the contract entry lands with 4b-server with the note that the key is sent by app builds from 4a on.

## 7. Landing 4a (client + migration) and its tests

Order of work: (1) extraction commit (§5); (2) the migration file written and kept OUT of the commit; the order is Unit 3's: B-pass accepted, then the apply go, then the ledger commit (`backups/applied_migrations.json` + `live_schema_columns.json`), then CI and merge; (3) pure files, flag, provider, write door, section, screen seams, PDF argument, snapshot key; (4) the docs below; (5) gates, mutants, plan-review record, B-pass, review CI. 

- Pure: `dietSupplementsActive` table (flag x pro x toggle x age: 17 years 364 days, 18th birthday today, 29 February birthday in a non-leap year, blank, garbage, future, over 120, an ISO datetime with a time part); `supplementCardFor` per food type; `addProteinShake` (gap 14.9 / 15 / 40 g, vegan, Keto, the 1.08 boundary, the replacement order and the net-gain-over-8 rule, a missing food row = no shake and no throw, one scoop, input not mutated); `isSupplementShake`; the id set disjoint from the catalog. A reach test over the 16 archetypes x 50 seeds: the share of gap-15 days that get a shake and the mean protein ratio, with floors written from the measured numbers (§12) that may only be raised, and every post-shake day within 1.08 of the calorie target when the generator's own day was.
- Identity (flag on, toggle off / absent): (a) the screen's generated plan item list (food ids, servings) for a fixed seed equals a fixture recorded from the BASE commit before any change (the fixture lands in commit 1); (b) the saved plan JSON key set has no `diet_supplements`; (c) the snapshot map key set and the profile push map are equal to the base for a profile that never set the key; a separate pin: stored `false` IS pushed (`diet_supplements: false`), stored `true` pushed, flag off pushes neither (mutant: `false` not pushed); (d) the PDF: `buildDietPlanPdf` is called with `stack: null` and the header lines (`dietPlanPdfHeaderLines`) and the item list passed to it are equal (the table is built inline and bytes are compressed, so text equality is not available; a source pin shows the stack section sits behind `if (stack != null)`); (e) a flag-off provider's dependency set is unchanged: a rebuild probe counts the provider's rebuilds while PRO state flips with the flag off (zero).
- Screen (with Hive; runAsync traps as in 3b): the switch is locked for a free user; on for PRO regenerates once, adds the shake and the card; off regenerates and removes both; under 18 shows no section; a PRO lapse hides both; the stamp round trip (stamped true loads while active; a plan built before Unit 4 loads while inactive and regenerates while active); a SAVED plan holding F0823 shows no swap icon; the real kill switch (no seam) hides the section and a stamped plan still loads.
- Snapshot builder: a table test over flag x PRO x age x toggle: the key is `true` exactly when `dietSupplementsActive` holds, absent otherwise (mutant: the raw stored bool emitted).
- Dart <-> Deno vector: a Dart test reads `supplement_card.json` and compares `supplementCardFor` per food type.
- Source pins (comment-stripped): the push call site gates on the flag and sits in the upserted map (the 3b-3 seat C lesson, with the queued send and no later change of the map); no reader of `diet_supplements` in the new files other than through `dietSupplementsActive` (presence-only, with that reason: `date_of_birth` is read in 20+ files, so a whole-tree grep cannot hold); the migration adds exactly one nullable column.
- Mutants (each applied once, count-checked): age `>= 18` to `> 18` and to `>= 13`; blank date of birth read as adult; leap-day compare off by one; `pro` ignored; toggle ignored; the 15 g threshold and the 1.08 ceiling; vegan row swapped to whey; the stamp ignored on load; the stamp written when inactive; the push key written when absent; a dose token changed (the vector test reddens); the flag read inverted; the swap-icon condition removed; the replacement order reversed; the net-gain guard removed; the push of `false` dropped; the snapshot key emitted from the raw bool.
- Whole-project `flutter analyze --no-fatal-infos`, the pre-commit gate loop, the full suite from CI, then the 4a plan-review record and B-pass. Tier: the default-ON flag with a per-user opt-in is NOT the CLAUDE.md §4.12.4 ship-dark tier, so the full x2 review and `bpass: accepted` apply and no `ship_dark_pending_review.yaml` entry is needed.

## 8. Documents and registry

`docs/sot_registry.yaml`: a concept `diet_supplements` (writer `setDietSupplements`, readers the rule, the provider, the screen seams, the snapshot builder, the push; `behavioral_test_path` set, Gate 42), plus shifted ranges for the saved-plan concept (`_savePlan`, `_loadSavedPlan`, `DietPlanNotifier`) recomputed from anchors. `docs/naming_conventions.md`: rows for `diet_supplements`, `DietSupplementsFlags`, `featureDietSupplements`, the shake, the supplement card, `DISABLE_DIET_SUPPLEMENTS_MANUAL_RULES`. Nested CLAUDE.md: nutrition, profile (the new key), ai_coach (the snapshot key), `supabase/functions`. OIs minted with `scripts/mint_oi.sh` (two): removal of `DietSupplementsFlags` and its OFF paths (§4.6 step 4, after the founder's device check; the manual switch is added to OI-510's list instead); the date-of-birth default seed (`reopen_when: store launch`). Naming rows also name `supplementCard` as a glossary term distinct from subscription stacking.

## 9. Release order

1. 4b-server: PR, B-pass, CI green, merge on the founder's go; deploy `ai-proxy` and `weekly-report` (one go each); versions read back. Inert.
2. 4a: PR, plan-review record, B-pass accepted; then the migration apply (its own go) and the ledger commit; CI green; merge (its own go). The web app then shows the switch; nobody has it on.
3. Before the 4a merge go: read the live `ai-proxy` and `weekly-report` versions (the step-1 deploys) and the live `diet_supplements` count (expected 0 non-null).
4. APK only on the founder's word.

## 10. Round 1 dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | the "verbatim" dose pin cannot pass: manual says "5g daily, any time", the card "5 g daily" | token-level pin (§4 column, §6): the vector holds manual tokens; the card keeps its readable sentences; the coffee and multivitamin lines are added to the manual in 4b-server |
| 2 | P1 | the shake marker is not persisted or loaded: the swap icon returns after save / restore, the PDF cannot tell it apart | the shake is identified by `isSupplementShake(foodId)`, a pure function; no item key is written; a saved plan with F0823 gets a screen test; "the PDF can tell it apart" dropped |
| 3 | P2 | the stamp written as `false` breaks identity; the match must follow the flag | written only when active; consulted only with the flag on; saved-plan JSON added to the identity pins (§3, §7) |
| 4 | P2 | no write door, no reactive provider; `gate()` deprecated | `setDietSupplements`, `dietSupplementsActiveProvider`, no invalidation from the profile notifier, `gateAndVerify`, local PRO check (§2) |
| 5 | P2 | paywall copy and label test omitted | label constant, subtitle case, contract-test entry (§2) |
| 6 | P2 | 794 lines vs the 800 ceiling | extraction commit first, 35-line budget, under 760 (§5) |
| 7 | P2 | the shake adds about 110 kcal beyond the calorie band | ceiling rule 1.08 and a 16-archetype test (§3, §7) |
| 8 | P2 | the coffee line and the coach text are not in the manual; "plan already has a shake" is wrong | coffee and multivitamin lines move into the manual; the coach line says "MAY have a shake" (§6) |
| 9 | P2 | the age gate: format, default seed, leap day, other helpers, clock | §2: a new helper and why, 1 March convention, null is not adult, injected device clock, the default-seed hole named and parked for the store launch |
| 10 | P2 | registry, naming, nested CLAUDE.md, OI steps missing | §8 |
| 11 | P2 | two identity pins cannot be built; a whole-tree grep cannot hold | §7 restates each: fixture from the base commit, the pure header lines and item list, the presence-only pin with its reason |
| 12 | P3 | evening slot, item builder, lost unsaved edits, migration number, `AppTypography`, Keto and suggestMeal, release order | §1, §3, §2, §4, §9 |

## 11. Round 2 dispositions

Round 2 (context-blind, on revision 2): no P0, no P1; 5 P2 and 8 P3.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | only the first manual line was conditional; the multivitamin and coffee lines would go live for everyone, including 13-17 year olds | ONE passage, every line conditional on the key, removed by the kill switch with the `replace` mechanism, byte-exact test (§6) |
| 2 | P2 | the snapshot key's value was unspecified | `true` only when `dietSupplementsActive` holds, absent otherwise; builder table test (§6, §7) |
| 3 | P2 | "off is byte-identical" is false for on-then-off (a `false` is pushed, and must be) | identity scoped to "never set"; stored `false` pushed and pinned; mutant (§1, §7) |
| 4 | P2 | the shake's reach was never measured; the 1.08 ceiling blocks it where it matters; "12 archetypes" is 16 | measured (§12): replacement rule adopted (§3); reach test with floors; 16 everywhere |
| 5 | P2 | source pins on `_generateFreshPlan` and the PDF; no handling of a missing food row | the post-process sits after `built`, both pins named, missing row = no shake, no throw, test (§3) |
| 6 | P3 | helper count; empty date of birth is real | corrected; one hint line for an unreadable date of birth (§1, §2) |
| 7 | P3 | `now` cached in the provider | one sentence (§2) |
| 8 | P3 | vitamin D wording looser than the manual; B12 mapping circular; pregnancy | manual wording; the passage states the mapping; pregnancy added on purpose (§4, §6) |
| 9 | P3 | the stamp needs a screen field and a pure guard | `_planSupplements`, `dietPlanNeedsRegenerationForSupplements`, listener resets (§3) |
| 10 | P3 | file basename clashes; "stack" is taken; the OI named three ways | distinct file names, "supplement card", two OIs named once (§2, §4, §8) |
| 11 | P3 | the section must not nest under the strategy flag; WardToggle tap target; brand soul; paused hint | §1, §2, §4 |
| 12 | P3 | PDF ASCII; tier statement; rebuild probe; migration order; F0830 | §4, §7; F0830 (soy isolate) is a product option not adopted (the vegan row is pea) |
| 13 | P3 | the shake ids must stay out of the catalog | disjointness test (§3) |

## 12. Measurement (scratch test, deleted; 16 archetypes x 50 seeds, `CuratedDietPlanGenerator.forTest`, base `b463ceef`)

Days with a protein gap of 15 g or more, and what the two rules do:

| Archetype | gap >= 15 | plain ceiling 1.08 | ceiling 1.10 | replace (adopted) | protein ratio before -> after (replace) | calorie ratio after |
|---|---|---|---|---|---|---|
| cut male veg | 49/50 | 41 | 48 | 49 | 0.83 -> 1.00 | 1.05 |
| cut female veg | 47/50 | 13 | 29 | 47 | 0.78 -> 0.97 | 1.03 |
| cut vegan | 45/50 | 23 | 43 | 45 | 0.83 -> 0.97 | 1.04 |
| cut male eggetarian | 46/50 | 41 | 46 | 45 | 0.84 -> 1.01 | 1.05 |
| 1200 floor veg | 50/50 | 1 | 11 | 49 | 0.65 -> 0.86 | 1.03 |
| 1200 floor non-veg | 41/50 | 6 | 14 | 41 | 0.79 -> 0.97 | 1.03 |
| cut female pescatarian | 10/50 | 2 | 8 | 10 | 0.90 -> 0.94 | 1.03 |
| cut female non-veg / recomp non-veg | 4/50, 3/50 | 0, 3 | 3, 3 | 4, 3 | 0.95 -> 0.97, 0.97 -> 0.98 | 1.02, 1.01 |
| the other six (non-veg cut male, maintain x4, build x2) | 0/50 | n/a | n/a | n/a | unchanged | unchanged |

Average items removed per shake: 0.16 (cut male veg), 0.77 (cut female veg), 0.49 (cut vegan), 1.02 (1200 floor veg). The 1200 kcal veg archetype stays at 0.86 of its protein target even with the shake (a 100 g protein target on 1200 kcal for a vegetarian): the card and the shake help, they do not make that target reachable, and the plan does not claim to.

## 13. Landing 4b-server B-pass dispositions (docs/reviews/diet-supplements-bpass.md)

Three context-blind seats on `d5e1c9ca`; no P0 or P1. 24 findings: 5 P2, 19 P3. All fixed except three accepted.

| Seat / # | Sev | Finding | Disposition |
|---|---|---|---|
| B1 | P2 | the header "none of the lines below apply" had no end | bounded to the next `---`; pinned |
| B2 | P2 | "a post-workout scoop works too" reads as a second scoop | "one scoop a day in total ... not both"; pinned |
| B3 | P2 | multivitamin vs the Never rule; doctor line without an object and after the coffee; no caffeine bound | rewritten; doctor line first; one cup; order pinned |
| A1 | P2 | the OI-510 edit told the editor to delete the passage; stale title and Blocked-on; duplicate | rewritten |
| C1 | P2 | the card-rows mapping test was circular | keys tied to `FOOD_TYPE_KEYS`, split parsed from the passage; the Dart reader is a named step of 4a (section 7) |
| B4 / A2 | P3 | the age / PRO guarantee is client-only | the header repeats the age condition; comments say the server does not verify the key |
| B5, B6, A3, A5 | P3 | wording: powder type and keto, "Their plan", vocabulary keys, "same doses as above" | fixed |
| A4 | P3 | legacy food-type text does not define eggetarian / pescatarian | accepted: the 2b rollback case, harmless, said in the comment |
| A6 | P3 | no PRO / paywall line for the coach | accepted: the diet strategy has the same shape; noted for the coach check |
| A7, A8 | P3 | "stack" in file names; CLAUDE.md size | `supplement_card.json`; row shortened |
| B7/C7, C2, C3, C4, C5, C6, C8 | P3 | captainPrompt path, a vacuous assertion, an unguarded slice, tokens without units, digits only, weekly-report inertness unpinned, ambient env | each fixed and pinned; mutants S12-S21 red |

Accepted-with-reasons count: three (A4, A6, and the 4b mapping test's Dart reader, which lands with 4a by name).

One plan change from 4a work: the identity pin (a) in section 7 compares the screen's saved plan against `generatePlan` for the same seed at runtime (`dietPlanSeed(DateTime.now(), 0)`), instead of a fixture recorded at the base commit, because the screen's seed is date-derived and a recorded fixture would go stale; G1/G2 already pin the generator itself.
