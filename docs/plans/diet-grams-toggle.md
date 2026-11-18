# Diet chart: Portions / Grams view (OI-517) — REVISION 4 (after review rounds 1 and 2 and the founder's placement call, section 12; a short delta check follows)

Status: brainstorm done with the founder 2026-11-17/18. NO code until this plan has passed two independent review rounds (CLAUDE.md 4.12).

## 1. Founder decisions
1. "Raw weight" = grams of the food AS SERVED (cooked rice 158 g, not dry rice). No cooked-to-raw conversion; macros untouched.
2. Grams view shows grams for EVERY food with the count in brackets: "60 g (2 idli)", "50 g (1 egg)", "158 g (1 cup)".
3. Liquids show millilitres: "250 ml (1 glass)". The data holds only grams, so 1 g is taken as 1 ml (within a few percent for these drinks).
4. A food already described in grams/ml ("100g") shows once: "100 g", never "100 g (100g)".
5. One switch for the whole screen: plan rows, swap sheet, portion picker, Search-any-food rows and the PDF. Not per meal.
6. PLACEMENT (founder, 2026-11-18, option C after the 4th-column geometry proved infeasible at 360 dp): the View control sits BESIDE THE TITLE "Diet chart" in the app bar, not in the settings row. The settings row keeps its three columns untouched.
7. Default: existing users see Portions; NEW users start on Grams.
8. Macros are identical in both views (display only).

## 2. Measurements (assets/data/food_database.json, 1444 rows)
- Every row has `standard_serving_g` (0 missing, 0 outside 1..1500) and `standard_serving_desc`. Where the desc is a gram figure the two agree (0 mismatches).
- By desc shape: 803 volume/vague ("1 cup", "1 bowl"), 466 countable ("1 roti", "2 idli"), 175 gram/ml. (The founder-facing 462/773/209 at filing used a looser parse; the exact split is re-run by the audit script, section 5.)
- Liquids CANNOT be found by name: a name match returns 111 rows incl. Broccoli (steamed), Watermelon, Tuna in Water. Category `beverages` (99) plus liquid dairy rows is closer but still needs a row-by-row decision. So liquid status is an audited per-row field, not a regex at render time.

## 3. Design (display only, nothing stored changes)
- Plan items already carry `servingDesc` (portion text, scaled by the multiplier) and `servingG` (scaled grams) (`diet_plan_screen_models.dart:27-28`). The saved plan JSON (`serving_desc`, `serving_g`, `diet_plan_screen.dart:387-388`, restore `:438`) therefore needs NO change: no migration, no regeneration, old saved plans work.
- NEW pure function `servingLabel(desc, grams, view, isLiquid)` in a new service file (NOT in `diet_plan_screen.dart`, 743 of 800 lines, Gate 43). Portions: returns `desc` unchanged (byte-identical to today, pinned by a test). Grams: unit = `ml` when the row is a liquid, else `g`; figure = `round(grams)`. Label table, measured on all 1444 rows (`_servingRe`, `curated_diet_plan_generator.dart:578`):
  | desc shape | rows | Grams label |
  |---|---|---|
  | parses, no paren ("1 cup", "2 idli", "1 oz") | most | `158 g (1 cup)`; "oz" is kept: `28 g (1 oz)` |
  | leading gram/ml figure ("100g", "250 ml", "100 g") | 175 | the figure alone, in the row's unit: `100 g` / `250 ml` |
  | trailing gram/ml paren, parses ("1 portion (150 g)", "1 can (330 ml)") | 28+ | paren stripped from the bracket: `150 g (1 portion)` |
  | trailing paren that does NOT parse ("1 packet (52g)", "1 peg (60ml)", "1 scoop (10g)") | 14 | same strip rule: `52 g (1 packet)`, `60 ml (1 peg)` |
  | bare number or unparseable ("180", "52.3") | 8 | grams only: `100 g` (the number is NOT a weight; `standard_serving_g` is 100 on all 8) |
  | non-gram paren ("1 cup (2 eggs)" x6 egg dishes, "13g (6 biscuits)") | 7 | the paren moves INTO the bracket, never nested: `200 g (1 cup, 2 eggs)`; a leading-gram desc keeps a non-gram paren: `13 g (6 biscuits)` |
  Unit rule: a desc whose own unit is ml/mL forces `ml` regardless of the flag (21 rows), so an unflagged ml row never reads "250 g" against its own "250 ml". Scaled forms: `scaleServingDesc` returns "2 × 1 packet (52g)" for an unparseable desc, so a SCALED unparseable row gives grams only (`104 g`), the strip rule applies to unscaled descs. The Portions quirk `0.667 cup (170 g)` x1.5 -> "1. cup (255 g)" (`formatServingQty` strips `0+$` and leaves the dot) is verified at build; if real it is fixed in `formatServingQty` in this batch with its own test and diagnose-doc, because the Grams bracket would otherwise inherit it.
  The 22 rows that do not parse, the 43 with a paren, the 7 non-gram-paren rows and the 17 oz rows are listed as fixtures in the test. A scaled desc that `scaleServingDesc` turned into "1.5 × desc" is treated as unparseable (grams only).
- Liquid flag: new asset field `weight_unit: "ml"` on audited liquid rows only (absent = g). Liquids are NOT only `beverages` (Milk (Toned) and Lassi are in `dairy`, Falooda in `sweets`), so the audit decides each row. The flag reaches installed devices only through a seed bump: `seed_service.dart:228` `_foodLibraryVersion` 7 -> 8 (without it installed Hive food rows never gain the field and every liquid silently shows g). The pin `test/contracts/food_library_v4_upgrade_behavioral_test.dart:120,156,174,192,209,217` is repointed to 8; `scripts/patch_food_database_v4.dart` and the exact-key tests `food_database_v2_test` / `food_database_tagged_test` are checked and updated.
- Resolver (`weightUnitFor(foodId)`): a Hive foodBox lookup that tolerates a missing id (retired id in an old saved plan), a custom food (not in the asset) and the protein shake's synthetic id (`diet_plan_shake.dart:48-53`): all fall back to g. No network; works in the PDF path and on saved-plan restore (`diet_plan_screen.dart:438`).
- Free picks write desc `"N g"` even for a liquid (`diet_plan_free_item.dart:135`): Portions view keeps today's text byte-identical; Grams view takes the unit from the resolver, so a liquid reads `ml`.
- Readers to switch to `servingLabel` (all verified by round 1): meal card `diet_plan_screen.dart:701`; swap sheet `diet_plan_swap_sheet.dart:89` (reads `alt.servingDesc`, already scaled); portion sheet `diet_plan_portion_sheet.dart:143` (label applied at the widget; its Weight field `suffixText: 'g'` shows `ml` in Grams view for a liquid); Search-any-food row `diet_plan_food_search_sheet.dart:137` (reads the raw row `standard_serving_desc`, UNSCALED, so it passes the row's own `standard_serving_g`); PDF `diet_plan_pdf.dart:20,174` (a string typedef: the caller `diet_plan_screen.dart:~501` passes the already-labelled string at share time; the PDF has no `ref`).
- NOT covered, stated: Log Food search (`search_mode_body.dart:190-198`), barcode sheet (`barcode_scan_sheet.dart:559`), custom food sheet, coach, home. "One switch for the whole screen" means the Diet chart surfaces only.
- Placement (founder, option C): a compact two-segment control (Portion | g, at most ~96 dp) in the app bar `actions` of `diet_plan_screen.dart:552-600`, before the refresh and save icons. Measured budget at 360 dp: back arrow 48 + 3 actions 48+48+96 leaves ~168 dp for the title column; "Diet chart" (18 px, w800) needs ~100 dp, the tag line under it ("NON-VEG · KETO", 10 px, letter-spaced) may ellipsise, which the plan accepts. The control is its own widget file (`widgets/diet_serving_view_toggle.dart`) because the screen is 743 of 800 lines (Gate 43). If the real-font measurement shows the title or the tag clipping, the control moves to a right-aligned line under the title text inside the same title column, still beside the title; any other spot is a founder call. The Supplements pins (`diet_plan_supplements_screen_test.dart:566-596`) and the strategy-selector source-greps are UNTOUCHED, since the settings row does not change.
- Control: the app-bar toggle above (not the settings row). Keys `diet_serving_view_toggle`, segment keys `diet_serving_view_portions` / `_grams`. 360 dp measurement with the real font (JetBrains/DM Sans advance, not Ahem) is a test: no overflow, title and control both visible.
- State contract: the provider watches `authUserIdTokenProvider`, rebuilds on the restore tick and sets state on write, read-into-locals before any session open (memory `feedback_restore_never_refreshes_profile_provider_state`, `feedback_session_open_rebuilds_notifier`; precedent `diet_supplements_active_provider.dart`). A toggle through `patchProfile` stamps `updated_at` and triggers a profile sync (`profile_write_service.dart:60-70`): ACCEPTED, the pushed payload is a column whitelist so the key itself never leaves the phone. Custom foods are never liquids (the resolver falls back to g): accepted.
- State: Riverpod provider reading the profile key `diet_serving_view` ('portions' | 'grams'). Writer: the control only, plus the one default write at onboarding completion (new users = 'grams'). Reader: the provider. Key ABSENT = 'portions' (so every existing account is unchanged with no write).

## 4. Decisions closed (founder, 2026-11-18) and open points
a. Storage: PHONE ONLY (local profile Hive key `diet_serving_view`), no cloud column, no migration. A reinstall or second device falls back to the default.
b. New user = anyone who finishes onboarding after this batch ships (gets 'grams'); existing accounts keep Portions (key absent). Pre-launch every account is a test account (CLAUDE.md section 1).
c. Amounts that look odd in grams ("1 tsp" = 5 g, "10 almonds" = 14 g): shown as computed; the audit flags rows whose gram figure is implausible for the desc.

## 5. The audit (done-when item 2)
A report script `scripts/report_serving_weights.dart` (read-only, on demand; named outside the `audit_*` / `validate_*` prefixes because Gate 33 `check_gate_scripts_wired.dart:281-292` requires every `scripts/audit_*.dart` to be wired or allow-listed; it is not a `check_*` gate, so no rule-24 ledger entry), prints a table, no writes) over all 1444 rows + catalog + the rows Search-any-food can return:
- desc shape (count / volume / gram), liquid candidate (category + name + per-100 g density hint), grams vs desc plausibility (e.g. "1 cup" outside 100-300 g, "1 roti" outside 20-80 g).
- Output is reviewed row by row. The audit may ONLY (a) add `weight_unit: "ml"` and (b) FLAG an implausible gram value to the founder. It never edits `standard_serving_g`: that value feeds `calories_std` and every plan item (`curated_diet_plan_generator.dart:178-196`, `diet_plan_generator.dart:1155-1157,1404-1416`, `diet_plan_free_item.dart:14`), so a change moves macros, portions and the golden-pinned catalog and contradicts decision 8. A flagged gram value is a separate founder decision with its golden footprint measured first (memory: measure a shared rule's golden footprint). A row is never silently inferred.

## 6. Tests (each must fail without the change; mutate each once)
- servingLabel: Portions view byte-identical to the input for every catalog row; Grams view for count, volume, gram-shaped and liquid rows; scaled multipliers ("3 rotis" -> "120 g (3 rotis)").
- Macros: the same item renders identical kcal/P/C/F in both views.
- Default: absent key = portions; onboarding completion on a fresh profile = grams; an existing profile untouched.
- Toggle flips every surface (meal card, swap sheet, portion sheet, search rows, PDF text).
- Asset audit contract: every row with a liquid `weight_unit` is in the audited list; no row desc/grams mismatch.
- App-bar toggle at 360 dp with the real font: no overflow, title "Diet chart" not clipped, refresh and save still reachable (44 dp targets). The settings row is unchanged, so these existing pins stay valid and are re-run, not edited: `test/nutrition/diet_plan_supplements_screen_test.dart:575-596` (Supplements slot width >= 26 on the narrow surface; the row is unchanged so it must stay green as is) and `test/nutrition/diet_strategy_selector_test.dart:519-526` (source-greps `diet_plan_settings_row.dart` lines; keep those lines verbatim).
- Seed bump behavioural test (the existing v4-upgrade tests build their old rows FROM THE ASSET, so once the asset has `weight_unit` they prove nothing about it): strip `weight_unit` from the rows, mark the box v7, run the real `SeedService.seedIfNeeded()`, assert Milk (Toned), Lassi and Falooda have `weight_unit == 'ml'` and the version key is 8. Mutant: leave the constant at 7. The `:217` mirror test ("a box already at the current version is not re-seeded") becomes `_markSeeded(hive, 8)`; repointing the "7" literals alone is wrong there.
- Missing grams: `serving_g ?? 100` at `diet_plan_screen.dart:439` is defensive; the label falls back to the Portions text when grams are absent or <= 0 (never "100 g (2 rotis)").
- Existing pin `test/nutrition/diet_plan_supplements_screen_test.dart:566-571`: all three controls `greaterThan(90)` wide at 360 dp (named here after round 2 found it missing).
- Label table fixtures: the 22 unparseable rows, the 43 paren rows, 17 oz rows, 21 ml-desc rows, the 8 bare-number rows; a liquid free pick; a missing foodId; a custom food; the shake.
- Reinstall / second device of a new user reads an absent key and shows Portions (accepted phone-only consequence, pinned so it is deliberate). `saveProfile` is a whole-map write, so a re-onboarding resets the key to 'grams'.

## 7. Files (est.)
New: `widgets/diet_serving_view_toggle.dart`, `services/diet_serving_label.dart`, `providers/diet_serving_view_provider.dart`, the audit script, tests. Edited: the app bar in `diet_plan_screen.dart` (one line adding the toggle widget), the five readers, `food_database.json` (`weight_unit` only), `seed_service.dart` (v8) + its pin test, `onboarding_provider.dart` (the profile map built ~535-575 and written by `saveProfile` :587: the one door every fresh sign-up, email and Google, runs; the `already_onboarded` early return :436-441 stamps nothing), `docs/sot_registry.yaml` concept `diet_serving_view` (writer: the control via `ProfileWriteService.patchProfile` / `updateProfileFields`, never a `saveProfile` of a stale map, plus `completeOnboarding`; reader: the provider; `behavioral_test_path:` per Gate 42), `docs/naming_conventions.md` row, notes in `lib/features/nutrition/CLAUDE.md` and `lib/features/onboarding/CLAUDE.md`; check `scripts/check_hive_map_field_drift.dart`; update every doc surface that cites the seed version in the same commit (`lib/features/nutrition/CLAUDE.md:59,90`, `docs/naming_conventions.md:677`, `docs/sot_registry.yaml:1598,1995`, the header comments of `food_library_v4_upgrade_behavioral_test.dart`) and recompute registry line ranges from their anchors; the claim that `food_database_v2_test` / `food_database_tagged_test` hold exact-key assertions was not reproduced by round 2: re-check at build, drop if absent; `patch_food_database_v4.dart:133` rewrites the asset with `JsonEncoder.withIndent`, so `weight_unit` survives, run order: patch script first, then the audited flag edit; check and the known-profile-keys listings. Verified by round 1: restore merges `{...existingMap, ...cloud non-null}` (`sync_profile.dart:~830-840`) and the profile push is a column whitelist, so a local-only key is neither wiped nor sent. Line ceilings per the 800-line screen rule.

## 8. Process
Tier L-adjacent (asset + onboarding write): full 4.12 pipeline: this draft -> review round 1 -> revise -> review round 2 -> record `docs/plan-reviews/<branch>.md` -> build -> B-pass. Execution mode (inline vs subagent) to be written here at batch start.

## 9. Execution mode (decided at batch start, 4.12.7)
INLINE in this worktree (one writer, small tightly coupled change). Not switched mid-batch. Reviewers: fresh Sonnet seats, read-only, at most 4 concurrent, briefs prefixed with `docs/agent_brief_preamble.md` and listing allowed commands exhaustively. Founder pre-authorised the merge (2026-11-18, "Ok" to: merge once CI is green and the B-pass has no open findings, via `land_pr.sh`); APK build and the device check stay the founder's.

## 10. Review round 1 (one fresh Sonnet seat, read-only) and dispositions
Reviewer verified TRUE: plan-item fields and saved JSON keys, the four reader lines, the 3-column `Expanded` row, 1444 rows / 0 missing grams / 175 gram-shaped / 0 mismatches, liquids not findable by name, restore merge and push whitelist. I re-ran the key numbers myself (22 unparseable, 8 bare-number, seed version 7 and its pin, screen 743 lines, the two settings-row tests): all confirmed.
| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P0 | gram edits move macros and goldens | ACCEPTED: audit never edits grams (section 5) |
| 2 | P0 | `weight_unit` needs a seed bump | ACCEPTED: seed v8 + pin repoint (section 3, 7) |
| 3 | P1 | label grammar fails on 22 rows, duplicate figures | ACCEPTED: label table (section 3), fixtures (section 6) |
| 4 | P1 | unit conflicts (g desc on a liquid, oz, portion-sheet suffix) | ACCEPTED: unit from the resolver in Grams view, oz kept, suffix follows |
| 5 | P1 | reader list incomplete, line budget | ACCEPTED: readers with lines, NOT-covered list, helper outside the 743-line screen |
| 6 | P1 | two existing tests pin the settings row | ACCEPTED: section 6 |
| 7 | P1 | resolver under-specified | ACCEPTED: section 3 |
| 8 | P2 | new-user default not durable across reinstall | ACCEPTED as the founder's phone-only choice, pinned by a test (section 6); the founder decided this knowingly, not re-asked |
| 9 | P2 | key plumbing, registry, naming, CLAUDE.md notes | ACCEPTED: section 7 |
| 10 | P2 | hygiene (counts, record path, gate loop) | ACCEPTED: path fixed; gate loop runs before round 2 per 4.12.8 once a diff exists (this plan is prose) |
Round 2 reviews THIS revision.

## 11. Review round 2 (a second fresh seat, on revision 2) and dispositions
Verdict NOT CONVERGED: 0 P0, 4 P1, 5 P2. I re-checked the layout arithmetic against `diet_supplements_section.dart:85-150` and the pin at `diet_plan_supplements_screen_test.dart:566-571`.
| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | 4 columns at 360 dp: (328-24)/4 = 76 dp per column against 104 today; the pin needs each control > 90; the Supplements field (border 2 + padding 14 + switch box 48 = 64) leaves ~12 dp for "On/Off" | CONFIRMED infeasible as a plain 4th `Expanded`; FOUNDER CALL pending (options below); pin named in section 6 |
| 2 | P1 | label table incomplete (7 non-gram-paren rows, ml unit rule, scaled forms, "1. cup") | ACCEPTED: section 3 rows + rules + fixtures |
| 3 | P1 | `audit_*.dart` fails Gate 33 | ACCEPTED: renamed `report_serving_weights.dart` (section 5) |
| 4 | P1 | no behavioural test for the seed bump | ACCEPTED: section 6 |
| 5 | P2 | `serving_g ?? 100` fallback | ACCEPTED: section 6 |
| 6 | P2 | provider contract unspecified | ACCEPTED: section 3 |
| 7 | P2 | `patchProfile` stamps `updated_at` | ACCEPTED explicitly: section 3 |
| 8 | P2 | v2/tagged test exact-key claim unverified | ACCEPTED: section 7, re-check at build |
| 9 | P2 | doc surfaces citing v7, garbled gate sentence | ACCEPTED: section 7, section 5 reworded |
Geometry options put to the founder: (A) View as a full-width second row under the first (segmented Portions | Grams), nothing else changes; (B) keep one row of four and rebuild the Supplements field as a tappable On/Off pill (no switch), then re-measure every dropdown at 76 dp ("Eggetarian", "Balanced"), loosening two layout pins; (C) View beside the title "Diet chart", not a column. Recommendation: A.

## 12. Founder call on the geometry (2026-11-18)
Option C chosen: View beside the title (app bar). Supersedes the 4th-column placement in sections 1, 3, 6 and the round-2 item 1 (resolved: the settings row is not touched, so the layout pins are not at risk). The delta check of revision 4 covers this placement.
