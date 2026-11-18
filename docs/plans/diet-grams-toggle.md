# Diet chart: Portions / Grams view (OI-517) — DRAFT 1, brainstorm output, not yet reviewed

Status: brainstorm done with the founder 2026-11-17/18. NO code until this plan has passed two independent review rounds (CLAUDE.md 4.12).

## 1. Founder decisions
1. "Raw weight" = grams of the food AS SERVED (cooked rice 158 g, not dry rice). No cooked-to-raw conversion; macros untouched.
2. Grams view shows grams for EVERY food with the count in brackets: "60 g (2 idli)", "50 g (1 egg)", "158 g (1 cup)".
3. Liquids show millilitres: "250 ml (1 glass)". The data holds only grams, so 1 g is taken as 1 ml (within a few percent for these drinks).
4. A food already described in grams/ml ("100g") shows once: "100 g", never "100 g (100g)".
5. One switch for the whole screen: plan rows, swap sheet, portion picker, Search-any-food rows and the PDF. Not per meal.
6. It is the 4th control in the settings row under the title (food type, strategy, supplements, view).
7. Default: existing users see Portions; NEW users start on Grams.
8. Macros are identical in both views (display only).

## 2. Measurements (assets/data/food_database.json, 1444 rows)
- Every row has `standard_serving_g` (0 missing, 0 outside 1..1500) and `standard_serving_desc`. Where the desc is a gram figure the two agree (0 mismatches).
- By desc shape: 803 volume/vague ("1 cup", "1 bowl"), 466 countable ("1 roti", "2 idli"), 175 gram/ml. (The founder-facing 462/773/209 at filing used a looser parse; the exact split is re-run by the audit script, section 5.)
- Liquids CANNOT be found by name: a name match returns 111 rows incl. Broccoli (steamed), Watermelon, Tuna in Water. Category `beverages` (99) plus liquid dairy rows is closer but still needs a row-by-row decision. So liquid status is an audited per-row field, not a regex at render time.

## 3. Design (display only, nothing stored changes)
- Plan items already carry `servingDesc` (portion text, scaled by the multiplier) and `servingG` (scaled grams) (`diet_plan_screen_models.dart:27-28`). The saved plan JSON (`serving_desc`, `serving_g`, `diet_plan_screen.dart:387-388`, restore `:438`) therefore needs NO change: no migration, no regeneration, old saved plans work.
- NEW pure function `servingLabel(desc, grams, view, isLiquid)` in a new service file. Portions: returns `desc` unchanged (byte-identical to today, pinned by a test). Grams: `"{round(grams)} g ({desc})"` / `ml`; gram-shaped desc (the existing `_servingRe` grammar, `curated_diet_plan_generator.dart:577`) collapses to the figure alone.
- Liquid flag: new asset field `weight_unit: "ml"` on audited liquid rows only (absent = g). Resolved at render by `foodId` through the food repository, so old saved plans get it too. Custom foods: user-entered, treated as g unless the user's own description says ml.
- Readers to switch to `servingLabel`: meal card `diet_plan_screen.dart:701`, swap sheet `diet_plan_swap_sheet.dart:89`, portion sheet `diet_plan_portion_sheet.dart:143`, search sheet rows, PDF `diet_plan_pdf.dart:174` (the PDF follows the on-screen view at share time).
- Placement (founder, 2026-11-18): the 4th column of the first settings row under the title, order Food type, Strategy, Supplements, View. With Supplements hidden (minor / flag off) View takes the 3rd slot. Label "View", options Portions / Grams; shorten text only if the 360 dp measurement demands it, never wrap to a second row without a founder call.
- Control: `DietPlanSettingsRow` (`diet_plan_settings_row.dart`) gains a 4th column, a small Portions/Grams dropdown in the same `DietPlanDropdown` style (4 columns at 360 dp: measure with the real font, not Ahem).
- State: Riverpod provider reading the profile key `diet_serving_view` ('portions' | 'grams'). Writer: the control only, plus the one default write at onboarding completion (new users = 'grams'). Reader: the provider. Key ABSENT = 'portions' (so every existing account is unchanged with no write).

## 4. Decisions closed (founder, 2026-11-18) and open points
a. Storage: PHONE ONLY (local profile Hive key `diet_serving_view`), no cloud column, no migration. A reinstall or second device falls back to the default.
b. New user = anyone who finishes onboarding after this batch ships (gets 'grams'); existing accounts keep Portions (key absent). Pre-launch every account is a test account (CLAUDE.md section 1).
c. Amounts that look odd in grams ("1 tsp" = 5 g, "10 almonds" = 14 g): shown as computed; the audit flags rows whose gram figure is implausible for the desc.

## 5. The audit (done-when item 2)
A script `scripts/audit_serving_weights.dart` (read-only, prints a table, no writes) over all 1444 rows + catalog + the rows Search-any-food can return:
- desc shape (count / volume / gram), liquid candidate (category + name + per-100 g density hint), grams vs desc plausibility (e.g. "1 cup" outside 100-300 g, "1 roti" outside 20-80 g).
- Output is reviewed row by row; fixes land as asset edits (gram value or `weight_unit`). A row is never silently inferred.

## 6. Tests (each must fail without the change; mutate each once)
- servingLabel: Portions view byte-identical to the input for every catalog row; Grams view for count, volume, gram-shaped and liquid rows; scaled multipliers ("3 rotis" -> "120 g (3 rotis)").
- Macros: the same item renders identical kcal/P/C/F in both views.
- Default: absent key = portions; onboarding completion on a fresh profile = grams; an existing profile untouched.
- Toggle flips every surface (meal card, swap sheet, portion sheet, search rows, PDF text).
- Asset audit contract: every row with a liquid `weight_unit` is in the audited list; no row desc/grams mismatch.
- 4-column settings row at 360 dp with the real font: no overflow.

## 7. Files (est.)
New: `services/diet_serving_label.dart`, `providers/diet_serving_view_provider.dart`, the audit script, tests. Edited: settings row, the five readers, onboarding completion write, `food_database.json`. Line ceilings per the 800-line screen rule.

## 8. Process
Tier L-adjacent (asset + onboarding write): full 4.12 pipeline: this draft -> review round 1 -> revise -> review round 2 -> record `docs/plans/../plan-reviews/<branch>.md` -> build -> B-pass. Execution mode (inline vs subagent) to be written here at batch start.

## 9. Execution mode (decided at batch start, 4.12.7)
INLINE in this worktree (one writer, small tightly coupled change). Not switched mid-batch. Reviewers: fresh Sonnet seats, read-only, at most 4 concurrent, briefs prefixed with `docs/agent_brief_preamble.md` and listing allowed commands exhaustively. Founder pre-authorised the merge (2026-11-18, "Ok" to: merge once CI is green and the B-pass has no open findings, via `land_pr.sh`); APK build and the device check stay the founder's.
