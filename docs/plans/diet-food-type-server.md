# Plan — diet plan Unit 2b: one food-type vocabulary on the server and in the coach (`diet-food-type-server`)

- **Date:** 2026-11-14 · **Revision:** 3 (rounds 1-2 applied, §7; round 2 verdict: converged)
- **Pairs with:** Unit 2a (`diet-food-type.md`, client). **Release order:** 2b's Edge Functions deploy FIRST, then 2a's PR merges (a `main` push deploys the web app, `vercel.json`). Therefore every 2b change must behave correctly for BOTH today's stored values (`veg`, `vegetarian`, `non_veg`, `vegan`, `pescatarian`, `keto`, null) and 2a's canonical keys (`veg`, `non_veg`, `eggetarian`, `pescatarian`, `vegan`).
- **Branch base:** `main` (2b touches no Unit 1 file; never base it on `diet-food-quality`, round 2 finding 7).
- **Plan-review record (platform):** `review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted` (B-pass before the merge). The commit that later deletes the switches needs a full x2 review again (CLAUDE.md §4.12.4).
- **Blast radius:** `platform` (`daily-snapshot/**` and `_shared/**`, `docs/blast_radius.yaml:103, :106`): plan-review record with `bpass: accepted`; §4.6 gates below. Deploys: `daily-snapshot`, `protein-gap-alert`, `weekly-report`, `ai-proxy` (captain manual + `suggestMeal`), each with the founder's go, rollback payload built first (edge-function-deploy-rollback skill).
- **Bug class:** writer/reader vocabulary drift (a2b2f1, OI-257): 2b has its own FULL diagnose doc, `related_bugs: [a2b2f1, <2a id>]`.
- **Landing order (round 1 finding 11):** 2b's PR lands on `main` FIRST via `land_pr` (it has no client files, so the Vercel build changes nothing user-visible), then the Edge Functions are deployed from that merged `main` SHA (synced with `origin/main`; the live version's source SHA must be an ancestor), then 2a's PR merges. A deploy from an unmerged branch would be reverted by the next deploy from `main`, and a branch behind `main` would roll back `ai-proxy`'s newer merged changes.

## 0. Founder decisions (2026-11-14)

Food types Veg, Non-veg, Eggetarian, Pescatarian, Vegan; default Non-veg; "Everywhere it should be same. The coach should be aware about this." Keto/low carb are a later PRO strategy (Unit 3). Pre-launch: test accounts only.

## 1. Writers and readers (read at `3da92d26`)

| Site | Role | Today |
|---|---|---|
| `supabase/functions/daily-snapshot/index.ts:82` `extractCoachingNotes` (prompt `:238` `"vegetarian|vegan|non_veg|keto|pescatarian"`, returns `{ok, facts}` at `:335`, `:358`) | AI writer | raw value |
| `daily-snapshot/index.ts:365` `mergeCoachingNotes` (exported; tests call it directly) | writer: `user_preferences.coaching_notes` (raw merged JSON, spread over `existing`, `:386-391`; zero prompt readers, SoT `user_preferences_coaching_notes` :7180), `memory_embeddings` (a NEW `daily_summary` row of the flattened merged notes every run, `:395-419`; READ by `ai-proxy` retrieval, top 5 above 0.65, `ai-proxy/index.ts:1030-1040, :1152`: the coach-visible copy), `user_profile.diet_preference` via `candidateUpdates` (`:439`), `coach_memory.locked_field_conflicts` (`:480-510`, `valuesEqualForLockCheck` `===` for strings) | raw value everywhere |
| `protein-gap-alert/message.ts:17` `pickQuickFix` | reader | `veg|vegetarian|vegan` → paneer/milk; else chicken/eggs (vegan gets paneer + milk: wrong) |
| `weekly-report/index.ts:518` | reader → prompt | sanitised free text |
| `_shared/captain_manual.ts:282, :341-343` | prompt prose | "Vegetarian-first … eggs (where eggetarian)" |
| `_shared/tools/nutrition/suggestMeal.ts` | coach tool | model-chosen `isVeg` + name keywords (`NON_VEG_KEYWORDS` `:63-87`, includes `egg` and `biryani`); comment says the table has no `is_veg` column (false: migration 041; live 2026-11-14: 1,431 rows, `is_veg` true 1,235 / false 196 / null 0, `is_vegan` true 631, 0 chicken rows marked veg) |

## 2. Design

### 2.1 `_shared/food_types.ts`

Mirror of 2a's `lib/core/constants/food_types.dart`:
- `FOOD_TYPE_KEYS = ["veg","non_veg","eggetarian","pescatarian","vegan"] as const`; `foodTypeLabel(key)`.
- `normalizeFoodType(raw: unknown): FoodTypeKey`: the SAME table as Dart (`-`/space → `_`, trim, lower; spellings; null/'' and keto/low_carb → non_veg; unknown non-null → veg).
- `knownFoodType(raw: unknown): FoodTypeKey | null`: STRICT: the spelling table only (null for null, '', keto, low_carb and unknown). Used where a guess must not become a value (extraction).
- Both are pinned by the shared fixture `_shared/testdata/food_type_vocabulary.json`. 2b lands first, so **2b owns it** (round 1 finding 13); 2a's Dart test reads `expected` and ignores `known`. Rows: `{input, expected, known}`; `known` is null for null, '', whitespace, `keto`, `low_carb` and unknown strings. Non-string input: `normalizeFoodType` → `non_veg` (same as Dart `foodTypeOf`: a non-string is treated as never chosen), `knownFoodType` → null.
- `dietPreferenceLine(raw): string` (round 1 finding 8): the weekly-report prompt label, pure and tested.

### 2.2 daily-snapshot (behind `DISABLE_FOOD_TYPE_EXTRACTION_RULES`, exactly `"true"` = today's path verbatim)

- **The extraction stops producing a food type at all** (round 1 finding 1, P1): the user's choice (`user_profile.diet_preference`, written only by 2a's two doors) is the ONLY food-type source; a copy in the coach notes would be re-embedded every run and retrieved by the coach after the user changed it.
  - Prompt: the `diet_preference` line is removed from the extraction schema (`:238`).
  - `dropFoodType(facts)` (pure, returns a copy without `diet_preference`) is applied immediately after the `parsed as ExtractedFacts` assignment (~`:305`, before the `Object.keys(extracted).length > 0` gate and before `mergeCoachingNotesFn` is called; a result that becomes `{}` skips the merge but still advances the watermark exactly like today's empty result; round 1 finding 3), AND as the first statement of the exported `mergeCoachingNotes`.
  - In `mergeCoachingNotes`, `merged` also DELETES an inherited `diet_preference` from `existing` before the notes upsert and the embedding text, so old rows heal on the user's next extraction.
  - `candidateUpdates` no longer gets `diet_preference`; `lifestyle_activity` and `injuries` unchanged. With the switch OFF, `diet_preference` never enters the lock loop: no write, no conflict marker; the lock select still reads the column (harmless). 2a's client lock call is the guard for the switch-ON path.
- Switch ON (`DISABLE_FOOD_TYPE_EXTRACTION_RULES` exactly `"true"`, read per call inside `dropFoodType`'s callers like `:457`/`:649`/`:728`): the prompt keeps today's schema line (kept as a constant), nothing is dropped, `candidateUpdates` includes the raw value: today's behaviour verbatim.
- **One-time cleanup of stale copies (live data, test accounts only):** an UPDATE, not a DELETE (round 2 finding 1: a `daily_summary` row holds ALL the merged facts, and an empty later extraction writes no new row): strip the `diet_preference: <value>` segment from `memory_embeddings.content` (rows with `source_type = 'daily_summary'`) and the `diet_preference` entry from `metadata.keys`, keeping the vector (a slight stale diet signal in it is harmless); remove the `diet_preference` key from `coach_memory.locked_field_conflicts`. A stale `coaching_notes.diet_preference` JSON key survives until the user's next non-empty extraction (zero readers; harmless). Ad-hoc data-only SQL, not a migration (round 1 finding 2): rehearsed in the local docker Postgres first, its text plus before/after counts recorded in the diagnose doc, and run only with its OWN founder go, separate from the deploy go.
- `valuesEqualForLockCheck` unchanged.

### 2.3 protein-gap-alert

`pickQuickFix(gap, diet)` takes `normalizeFoodType(diet)`:

| Food type | gap ≥ 40 | gap ≥ 20 | else |
|---|---|---|---|
| veg | 200g paneer + a glass of milk (unchanged) | 100g paneer or a scoop of whey (unchanged) | a glass of milk + 30g almonds (unchanged) |
| eggetarian | 4 boiled eggs + 100g paneer | 3 boiled eggs + a glass of milk | 2 boiled eggs |
| pescatarian | 200g fish (rohu, tuna) or 3 boiled eggs + a glass of milk | 100g fish + a glass of milk | 2 boiled eggs |
| vegan | 200g firm tofu + a cup of soy milk, or 50g dry soya chunks | 50g dry soya chunks or a cup of roasted chana | 30g roasted peanuts + a cup of soy milk |
| non_veg | 150g chicken breast or 4 boiled eggs (unchanged) | 100g chicken or 3 boiled eggs (unchanged) | 2 boiled eggs (unchanged) |

Protein roughly: each new cell covers its band's lower bound (round 1 finding 14; the unchanged non-veg "or 4 eggs" shares the existing weakness and is kept as copy the founder already ships).

Copy follows the existing format ("Quick fix: …"). Header comment rewritten (the "eggetarian does not exist" note goes). No switch: closed set, strictly more correct than today for every stored value (veg/vegetarian unchanged; vegan loses dairy; pescatarian/eggetarian/keto/null as tabled). The index.ts comment at `:270-275` is rewritten; `index_test.ts:6-8` ("vegan counts as veg" asserting paneer) is rewritten.

### 2.4 weekly-report

The line becomes `- Diet preference: ${dietPreferenceLine(raw)}` (a closed label set from `_shared/food_types.ts`, behaviourally tested; a source pin that `index.ts` calls it, the SoT wiring leg `presence_only`: the handler builds the prompt inline under a module-scope `serve()`). Null now reads `Non-veg` (the founder default) instead of `no preference`; a stored `keto` reads `Non-veg` (the keto signal returns with Unit 3's strategy). `weekly-report` imports `CAPTAIN_MANUAL`, so it is deployed after the manual edit too.

### 2.5 Captain manual (`ai-proxy` system prompt)

Replace §5 `:282` and §7 `:341-343` lines with: "Respect snapshot.profile.diet_preference: veg (no meat, fish or eggs), non_veg (anything), eggetarian (veg plus eggs), pescatarian (veg plus eggs, fish and seafood), vegan (no animal products: no dairy, eggs, meat, fish, honey or whey; plant protein instead). Never suggest a food outside it. Many Indian users are vegetarian. Check diet_preference before whey vs plant protein." Plus (round 1 finding 5, the window before 2a merges): "Older values: vegetarian = veg; keto or low_carb = non_veg with a low-carb emphasis; empty or missing = non_veg." Keep B12/omega-3 and Jain lines. Vegan line drops "honey" (the food table tags Honey `is_vegan`, finding 6). **Gate (round 1 finding 4, §4.6; shape per round 2 finding 3):** `CAPTAIN_MANUAL` (module-scope const, `captain_manual.ts:14`, imported by `captain_manual_hold_test.ts` and `captain_manual_day_swap_routing_test.ts`) becomes the NEW text, so those tests are unchanged; `CAPTAIN_MANUAL_LEGACY_FOOD` keeps today's text; `captainManual(): string` reads `DISABLE_FOOD_TYPE_MANUAL_RULES` (exactly "true") per call and returns the legacy text when set; `ai-proxy/index.ts:1092`, `weekly-report/index.ts:457` and `captainPrompt()` (`:497`) call it; same switch read by `weekly-report` for its label line (ON = today's `sanitizeIdentifier(raw)` line).

### 2.6 suggestMeal (behind `DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE`, exactly `"true"` = today's handler verbatim)

- Read the caller's food type: `ctx.sb.from("user_profile").select("diet_preference").eq("user_id", ctx.userId).limit(1)` → `data?.[0]` (no `maybeSingle`: `fake_sb.ts` has none); `normalizeFoodType`. A read error or exception → today's behaviour (`isVeg` only) plus a note "Could not read the user's food type; filtered by the request only." **Changed by the B-pass (§8): a failed read now shows vegan options.**
- Query per food type (round 2 finding 3; `fake_sb` supports `eq`, `lte`, `limit`, no `.or`):
  - vegan: `.eq("is_vegan", true)`; veg: `.eq("is_veg", true)`; both keep `.lte(calories)` + `.limit(500)`.
  - vegan also applies a TS name deny-list on top of `is_vegan` (round 1 finding 6: the table tags Honey, Honey Chilli Potato, Cold Coffee, Pav Bhaji, Vada Pav `is_vegan`): `\b(honey|ghee|paneer|curd|dahi|whey|cheese|malai|butter|milk|cold coffee|pav)\b` drops a row unless it also matches `\b(soy|almond|oat|coconut|peanut|cashew|rice|hemp|nut|cocoa)\b` (plant milks and nut butters; round 2 finding 5: with this list only Honey, Honey Chilli Potato, Cold Coffee, Pav Bhaji and Vada Pav drop of the 643 `is_vegan` rows). **Tightened by the B-pass (§8).**
  - eggetarian / pescatarian: query A `.eq("is_veg", true)` (limit 500) + query B `.eq("is_veg", false)` (limit 250; 196 live), run with the profile read under `Promise.all` (latency); a query-B error degrades to A only plus a note (A's error throws as today); B filtered in TS: keep a row only if its name matches the allowed animal word AND no meat word (whole-word regexes, round 2 finding 4): egg `\begg(s)?\b|\banda\b|\bomelet(te)?\b`; fish `\b(fish|macher|prawns?|shrimps?|crabs?|lobsters?|pomfret|surmai|rohu|bangda|tuna|salmon|sardines?|mackerel|hilsa|basa|tilapia|squid|seafood|cod|scallops?|mussels?|oysters?|anchov(y|ies)|bass|halibut|trout|swordfish|snapper|catfish|mahi)\b` with "Fish Oil Capsule" excluded (`\bcapsule\b`); meat, matched WITHOUT word boundaries for the chain-brand case (round 1 finding 7: `McChicken`): `(chicken|murgh|mutton|gosht|lamb|goat|keema|kheema|kabab|kebab|seekh|tangdi|nihari|haleem|rogan|beef|pork|bacon|\bham\b|sausage|salami|pepperoni|turkey|duck|quail|veal|goose|ribs|lard|meat)`, matched AFTER stripping `\b(quail|duck|goose)\s+eggs?\b` and `crab meat` from the name; `tikka` is not in the list (round 2 finding 4: Fish Tikka, Quail Egg, Duck Egg and Crab Meat (canned) were false negatives; real chicken tikka is caught by `chicken`/`murgh`, and Paneer Tikka is an `is_veg` row in query A). A seed scan of the 196 `is_veg = false` rows is part of T5 (every kept row listed). (`tikka` appears in Paneer Tikka, but query B only holds `is_veg = false` rows, so a veg Paneer Tikka is in query A.)
  - non_veg: no food-type filter (today's query).
- The model's `isVeg: true` NARROWS: veg rule on top (`.eq("is_veg", true)`), replacing today's name-keyword list, which also wrongly dropped `is_veg` rows like Eggplant/Eggless (round 2 finding 4). `NON_VEG_KEYWORDS` stays only on the switch-ON path.
- `total_candidates_searched` counts the merged candidate list; the stale "no is_veg column" comment and note are replaced; the query summary names the food type.

## 3. Kill switches and tracking

`DISABLE_FOOD_TYPE_EXTRACTION_RULES` (daily-snapshot), `DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE` (suggestMeal), `DISABLE_FOOD_TYPE_MANUAL_RULES` (captain manual + weekly-report line). protein-gap-alert's closed-set table is strictly more correct for every stored value and rolls back by redeploy (stated exemption). One OI (minted at build) tracks deleting both switches and their old paths after the founder's coach check. Both names go in `docs/naming_conventions.md` and the `supabase/functions/CLAUDE.md` SoT table.

## 4. Tests (Deno, `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/`, whole tree)

- **T1** `_shared/food_types_test.ts`: every fixture row through `normalizeFoodType` and `knownFoodType`.
- **T2 daily-snapshot** (`daily-snapshot/index_test.ts`):
  - New: an extraction answering `diet_preference` (any value) → absent from the notes upsert, the embedding text and `user_profile`; `existing` notes holding `diet_preference: keto` → removed on the next merge; `mergeCoachingNotes` called DIRECTLY with `diet_preference` drops it (the seam); a reply holding ONLY `diet_preference` → no merge, watermark advanced; prompt has no diet line; switch `"true"` → today's prompt, notes and candidate upsert.
  - REWRITTEN (they pin today's diet_preference upsert/conflict behaviour, round 2 finding 1): `:759`, `:797`, `:954-962`, `:970-996`, `:1002-1011`, `:1066-1095`, `:1127-1143`, `:1161-1173`. The lock/conflict mechanism tests move to `lifestyle_activity` (a string compared with `===`, same assertions); the `:1060` "existing conflict for a DIFFERENT field" test uses `injuries` (array, sorted compare) as its second field; `:759`/`:797` only inject a Gemini reply and need no assertion change; the diet_preference cases become "never upserted, never a conflict" and "switch ON: today's behaviour".
- **T3 protein-gap-alert** (`index_test.ts` + message tests): the 5x3 table above; `vegetarian`, `veg ` (space), `keto`, null, `xyz` rows; vegan copy contains no paneer/milk/whey/egg.
- **T4 weekly-report**: `dietPreferenceLine` behavioural (`vegetarian` → `Veg`, null → `Non-veg`, `keto` → `Non-veg`, `eggetarian` → `Eggetarian`); source pin that `weekly-report/index.ts` uses it under the switch.
- **T5 suggestMeal** (`_shared/tools/__tests__/suggestMeal_test.ts`, today schema-only, + `fake_sb.ts` tables `user_profile` and `food_database`; `fake_sb`'s `lte` compares as STRINGS (`fake_sb.ts:34-35`, round 1 finding 9), so `gte`, `gt`, `lt` and `lte` compare as numbers when both sides are numbers (ISO date strings stay string comparisons) and every importer is re-run: the `_shared/tools/__tests__` suites, `future-prediction/index_test.ts`, `i-see-you-callout/streak_gate_test.ts` (round 2 finding 8)): eggetarian keeps "Egg Bhurji", drops "Chicken Egg Roll", "Murgh Tikka"; pescatarian keeps "Prawn Curry", "Fish Cake", drops "Chicken and Prawn Curry"; vegan returns only `is_vegan`; veg keeps "Egg Plant Curry"(`is_veg` true) and "Eggless Cake"; profile read error → `isVeg`-only path + note; `isVeg: true` narrows a non_veg user; switch `"true"` → today's handler (golden on a fixed table); vegan drops Honey/Cold Coffee/Pav Bhaji fixtures and keeps Black Coffee, Cashew Milk, Almond Butter; pescatarian keeps Macher Jhol, Cod, Fish Tikka, Crab Meat (canned), Duck Egg; eggetarian keeps Quail Egg; drops Fish Oil Capsule, McChicken, Spare Ribs; a seed scan over the bundled asset's `is_veg = false` rows prints the kept rows per type and asserts none matches the meat list.
- **T6 captain manual**: a pin that the new rule text is present and "Vegetarian-first" / "where eggetarian" are gone.
- **Mutations** (diagnose table): `knownFoodType` returns non_veg for unknown; sanitiser not called in `mergeCoachingNotes`; candidate update re-added; vegan quick fix uses paneer; meat regex loses `murgh`; egg regex unanchored (`egg` substring); switch read inverted.

## 5. Deploy plan (each needs the founder's go)

Order: `daily-snapshot`, `protein-gap-alert`, `weekly-report`, `ai-proxy`, from the merged `main` SHA. Before any deploy: whole-tree `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/` and `deno check --node-modules-dir=none` on the four `index.ts`.

| Function | verify_jwt (`test/contracts/runbook_deploy_verify_jwt_test.dart:47-86`) | Rollback | Smoke / proof |
|---|---|---|---|
| daily-snapshot | true | rollback dry-run built first | authenticated call with a real test-user token (skill §6.5/6.7): 2xx/own 4xx, then the next extraction's notes have no `diet_preference` |
| protein-gap-alert | false (cron) | rollback dry-run, `verify_jwt` false passed explicitly (skill §6.13: a SHA rollback otherwise flips it to true) | no authed smoke (it sends real pushes): unauth call answers the function's own 401; proof = the next cron run in `cron_call_log` + unit tests |
| weekly-report | true | rollback dry-run | authenticated call with a PRO test account (one report) only if the founder agrees; else unit tests + boot check |
| ai-proxy | false | rollback dry-run, `verify_jwt` false passed explicitly | a PRO test-account chat asking for a meal idea; read `ai_coach_interactions.tool_calls` for `suggestMeal` and its food-type note |

Rollback dry-run (round 2 finding 6): `node .claude/deploy_via_api.js --rollback <fn> <live sha> --yes --dry-run`, run from a scratch full-history clone (never a worktree: the gitignored `_payload_*` file makes it unretirable); the live SHA is identified by comparing the live `index.ts` sha256 (MCP `get_edge_function`) with git. Versions recorded in the diagnose doc. Then the stale-copy cleanup (§2.2, founder's go). Then 2a's PR merges.

## 6. Docs

Diagnose doc (FULL); `supabase/functions/CLAUDE.md` (shared module + switches); `lib/features/ai_coach/CLAUDE.md` (the extraction no longer produces a food type; the coach reads it from the snapshot profile only); SoT: `diet_preference_vocabulary` server readers (extends 2a's entry), `coach_extraction_locked_fields` (`:16447`: diet no longer proposed; its `behavioral_test_path` file's rewritten tests), `user_preferences_coaching_notes` (`:7180`, `mergeCoachingNotes` range), the daily-snapshot `serve` handler entry (~`:1102`), all ranges recomputed from anchors; `docs/naming_conventions.md` (three switches); OI for the switches; task board.

## 7. Review dispositions

### Round 1 (on revision 1)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | notes spread `existing`; every run re-embeds `diet_preference`, retrieved by the coach after the user changed it; old conflict markers persist | The extraction stops producing a food type: dropped after parsing and at the top of `mergeCoachingNotes`, inherited key deleted; one-time cleanup of embeddings + markers with the founder's go (§2.2). |
| 2 | P2 | the Hive `coaching_notes` read is a different concept; retrieval is the coach-visible path | §1 and §6 corrected. |
| 3 | P2 | sanitiser too late in `extractCoachingNotes`; switch ON must restore the prompt | Placed after parsing, before the gate and the merge; prompt line kept as a constant for switch ON (§2.2). |
| 4 | P2 | manual and weekly-report prompt change without a gate | `DISABLE_FOOD_TYPE_MANUAL_RULES` (§2.5); protein-gap exemption stated (§3). |
| 5 | P2 | manual must cover raw values before 2a merges; section number wrong | Older-values clause; §5 :282 (§2.5). |
| 6 | P2 | `is_vegan` tags honey, cold coffee, pav bhaji | Vegan name deny-list + test; honey dropped from the manual line (§2.5, §2.6). |
| 7 | P2 | fish regex misses 13 rows; `McChicken` beats `\bchicken\b` | Lists widened; meat list without word boundaries; seed scan test (§2.6, T5). |
| 8 | P2 | weekly-report line not testable | Pure `dietPreferenceLine` + source pin (§2.1, §2.4, T4). |
| 9 | P2 | `fake_sb.lte` compares strings | Fake fixed for numbers; all tool suites re-run (T5). |
| 10 | P2 | deploy facts missing | verify_jwt table, dry-run rollbacks, per-function proof (§5). |
| 11 | P2 | deploy from an unmerged / behind branch | 2b lands on main first, deploy from the merged SHA (header). |
| 12 | P2 | tier is platform; SoT entries missing | Header + §6. |
| 13 | P2 | fixture ownership; non-string input | 2b owns it; semantics defined (§2.1). |
| 14 | P2 | quick-fix protein maths | Table revised (§2.3). |
| 15 | P3 | test list details | T2 list completed; protein-gap `index_test.ts:6-8` added. |
| 16 | P3 | query-B failure, latency | `Promise.all`; B degrades to A with a note (§2.6). |
| 17 | P3 | null/keto now read Non-veg | Stated (§2.4). |

### Round 2 (on revision 2) — verdict: converged

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | DELETE loses all embedded facts; not regenerated on an empty extraction | UPDATE that strips the diet segment, vector kept; survivors stated (§2.2). |
| 2 | P2 | migration or ad-hoc SQL? | Ad-hoc data-only SQL, rehearsed locally, recorded, own go (§2.2). |
| 3 | P2 | `CAPTAIN_MANUAL` is a module const | New text in the const, legacy const + `captainManual()` per call, three call sites (§2.5). |
| 4 | P2 | meat list false negatives (Fish Tikka, Quail/Duck Egg, Crab Meat) | Strip phrases first, `tikka` removed; T5 rows (§2.6). |
| 5 | P2 | vegan deny-list over-drops | `cold coffee`; allow-list widened; T5 rows (§2.6). |
| 6 | P2 | rollback command name wrong | `deploy_via_api.js --rollback … --dry-run` from a scratch clone (§5). |
| 7 | P3 | base on `diet-food-quality` | Always `main` (header). |
| 8 | P3 | fake_sb ops and importers | All four comparisons; two more importers named (T5). |
| 9 | P3 | stale round labels | Relabelled where they referred to round 1 of this plan. |
| 10 | P3 | record tier | Header line. |

## 8. Build-time corrections (2026-11-14, diagnose `c9bc6a`)

- **Execution mode (§4.12.7):** inline, one worktree (`.claude/worktrees/diet-food-type-server`), based on `main` `94a021a0`.
- **T2:** the two watermark tests at `:759`/`:797` DID need a change: their Gemini reply held only `diet_preference`, which is now dropped before the merge, so the failing merge fn was never reached. Their reply is now `lifestyle_activity` (same assertions).
- **§2.6 latency:** the profile read runs first, then the food-type queries (eggetarian / pescatarian run their two queries under `Promise.all`). Putting the profile read in the same `Promise.all` would need every type's query to run speculatively; the read is one indexed row.
- **§2.6 isVeg on a read error:** the query summary says `veg` when the model asked for it, even though the stored type was unreadable.
- **Prompt-sanitiser gate:** `captainManual(` joins `captainPrompt(` and `CAPTAIN_MANUAL` in `prompt_sites_sanitized.test.ts`'s safe markers (it returns authored text only).
- **Pinned source repointed, not loosened:** `test/contracts/coach_write_claim_wiring_test.dart` now pins `[captainManual(), icbfLogInstructions(ruleOn)]`.
- **SoT:** 2b lands first, so it CREATES `diet_preference_vocabulary` with the server half; Unit 2a folds its client writers/readers into the same entry when it syncs with `main`.
- **Mutation B9** (meat rule loses `murgh`) survived the first test set: every fixture with `murgh` lacked an egg/fish word and was dropped anyway. A hand list of mixed egg/fish + meat dishes (one meat word each) was added.
- **Switch removal:** OI-510.
- **B-pass (`docs/reviews/diet-food-type-server-bpass.md`, six findings, all fixed):**
  1. Eggetarian: an egg word no longer admits a fish dish (`FISH_RE` checked first, `sushi`/`sashimi` added), a capsule is dropped for both types, and `hot dog`, `frankfurter`, `mcmuffin`, `jerky` are meat.
  2. Vegan: honey, ghee, paneer, whey, malai, cream, lassi, buttermilk, chaas, raita, kheer, rasmalai, shrikhand, kulfi, ice cream, mayo, egg (not "egg plant"), casein, gelatin, khoa/khoya, rabri, cold coffee and pav always drop the row; milk, butter, cheese, curd, dahi and yogurt are rescued only when a plant word comes RIGHT before them (Almond Milk, Peanut Butter, Soy Curd). On the bundled asset the same 632 of 637 `is_vegan` rows are kept.
  3. A failed profile read shows VEGAN options (they suit every food type), with a note; the summary names "vegan".
  4. The kill switch restores the pre-2b `isVeg` description the model reads (`get schema()`).
  5. The extraction drops a food type under any alias key (`FOOD_TYPE_FACT_KEYS`, case-folded) from the reply and from inherited notes; `food_preferences` is kept. The cleanup SQL also strips the 3 live `coaching_notes` copies (live: only `diet_preference`, no alias keys).
  6. Both queries order by `protein_std` descending before their literal limit, so a truncated veg list keeps the most protein-rich rows.
  Mutations B20 to B31.
- **Unit 2a B-pass F1 mirror:** `normalizeFoodType` now reads null/undefined as the default (Non-veg) and any other non-string (a corrupt value) as `veg`, the strictest common type, matching Dart `foodTypeOf`. The shared fixture (`_shared/testdata/food_type_vocabulary.json`) is byte-identical to Unit 2a's and gained the rows `42`, `true`, `["non_veg"]`. Mutation B19.
