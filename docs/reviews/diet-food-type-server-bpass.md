---
reviewed_at: 2026-11-14T16:30:00+05:30
staged_against: b76694b1 (committed three-dot diff origin/main...b76694b1, base 94a021a0, review CI green on the head)
blast_radius: platform
reviewer: claude-sonnet-via-skill (one fresh agent, no conversation context; lens 6 with a mutate-and-restore protocol, tree clean at the end)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
verdict_note: all six findings fixed in the follow-up commit on this branch; each new guard was mutated and reddens a test (diagnose c9bc6a, rows B20 to B31)
---

# Code Review (B-pass) — diet plan Unit 2b, one food-type vocabulary on the server and in the coach (`diet-food-type-server`, PR #271) at b76694b1

No P0 or P1. Three P2 and three P3 findings, all fixed in the same branch. The reviewer's 94-test Deno baseline over the touched suites was green.

## Finding 1 — P2 — missing_input
- **file:line:** `supabase/functions/_shared/tools/nutrition/suggestMeal.ts` `animalRowAllowed` (regexes above it)
- **claim:** for an eggetarian an `is_veg = false` row passed as soon as an egg word matched and no meat word did; the fish rule was never checked, so "Tuna Egg Salad", "Egg and Prawn Fried Rice", "Egg Hot Dog" and "Egg McMuffin" passed. No such row is in the bundled asset today (a future-row hazard).
- **verification:** the three regexes replayed in Python over those names and the 196 `is_veg = false` asset rows.
- **suggested-fix:** reject fish and capsule names for an eggetarian even with an egg word; add hot dog, mcmuffin and similar to the meat check.
- **status:** fixed. Capsule first (both types), then meat (now with `hot ?dogs?`, `frankfurters?`, `mcmuffins?`, `jerky`), then fish for an eggetarian, then egg; `sushi`/`sashimi` are fish. Asset: eggetarian 35, pescatarian 91 rows kept (unchanged). Mutations B20, B21, B22.

## Finding 2 — P2 — missing_input
- **file:line:** `suggestMeal.ts` `VEGAN_DENY_RE` / `VEGAN_PLANT_RE` / `veganRowAllowed`
- **claim:** any plant word anywhere in the name cancelled every deny word ("Curd Rice", "Ghee Rice", "Peanut Butter with Honey", "Cheese Nut Sandwich", "Rice Kheer" passed), and the deny list missed lassi, buttermilk, chaas, raita, yogurt, kheer, rasmalai, kulfi, ice cream, mayo, egg, casein, gelatin. Nothing wrong is served from the bundled asset today.
- **verification:** Python replay of the regexes; the 637 `is_vegan` asset rows.
- **suggested-fix:** absolute deny words; a plant rescue only for milk / butter / cheese; extend the list.
- **status:** fixed. `VEGAN_ABSOLUTE_RE` (honey, ghee, paneer, whey, malai, cream, lassi, buttermilk, chaas, raita, kheer, rasmalai, shrikhand, kulfi, ice cream, mayo, egg but not "egg plant", casein, gelatin, khoa/khoya, rabri, cold coffee, pav) always drops; milk, butter, cheese, curd, dahi and yogurt are rescued only when a plant word comes right before them. Asset: the same 632 of 637 kept. Mutations B23, B24, B25 (the "egg plant" exemption was added when the fixture's "Egg Plant Curry" went red).

## Finding 3 — P2 — guard_without_its_mirror
- **file:line:** `suggestMeal.ts` `handler` (`stored ?? "non_veg"`, summary)
- **claim:** a failed profile read fell back to `non_veg`, so a vegan or veg user could be offered chicken; the "failed read names no food type" branch was unpinned (mutation M4 survived).
- **verification:** read of the handler; mutation M4 green across 77 tests.
- **suggested-fix:** fail safe (an error or a stricter filter), or pin the default.
- **status:** fixed. A failed read shows vegan options, which suit every food type, with the note "Could not read the user's food type; showing vegan options, which suit every food type." and the summary "vegan". Mutation B26.

## Finding 4 — P3 — blast_radius_mismatch
- **file:line:** `suggestMeal.ts` `isVeg` schema description
- **claim:** the new description ("the tool already applies the user's stored food type") stayed in force with `DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE=true`, so the old path was not byte-identical for what the model reads.
- **verification:** diff of the schema against `legacyHandler`.
- **suggested-fix:** choose the description by the switch.
- **status:** fixed. The tool's `schema` is a getter that returns the pre-2b schema (description byte-identical to `origin/main`, pinned by a literal) when the switch is ON. Mutation B27.

## Finding 5 — P3 — writer_reader_drift
- **file:line:** `daily-snapshot/index.ts` `dropFoodType`, `mergeCoachingNotes`
- **claim:** only the exact key `diet_preference` was dropped; a model-invented key (`diet`, `dietary_preference`) would reach the notes and embeddings. Old embeddings depend on the cleanup SQL.
- **verification:** `git grep` of every `coaching_notes` / `memory_embeddings` writer.
- **suggested-fix:** drop alias keys; make sure the cleanup covers the old rows.
- **status:** fixed. `FOOD_TYPE_FACT_KEYS` (12 alias keys, case-folded) dropped from the reply and from inherited notes; `food_preferences` kept. Live (read-only): only `diet_preference` exists, in 18 embeddings and 3 `coaching_notes` rows; the cleanup SQL now strips the notes rows too (all 10 JSON notes rows parse). Mutations B29, B30, B31 (B31 survived until a mixed-case reply key was added).

## Finding 6 — P3 — asserted_fixture_value
- **file:line:** `suggestMeal.ts` `foodQuery` (`limit(500)` with no order)
- **claim:** the veg tables hold more rows than the limit, so suggestions came from an arbitrary subset. Not a regression.
- **verification:** asset counts (veg 1,241, vegan 637).
- **suggested-fix:** order before the limit.
- **status:** fixed. Both queries order by `protein_std` descending before their literal limit. Mutation B28.

## Clean lenses (reviewer)
- **writer_reader_drift:** the extraction drop covers every write path (after the parse, the merge seam, the inherited copy); `normalizeFoodType` matches the Dart reader on `diet-food-type` entry for entry; the re-anchored registry ranges are right.
- **function_exception_swallow:** `readStoredFoodType` catches and returns null (Finding 3).
- **blast_radius_mismatch:** with each switch ON the extraction prompt line and the manual text are byte-identical to the old text; only the description gap (Finding 4).
- **secrets_in_tree:** none; the only new env reads are the three `DISABLE_*` switches, compared to exactly "true".
- **unawaited_no_error_sink:** every new async call is awaited; a failure of the egg/fish query becomes a note.
- **missing_input:** `normalizeFoodType` clean; Findings 1 and 2.
- **asserted_fixture_value:** the `fake_sb` numeric compare is correct (number pairs numeric, everything else string, ISO dates unchanged); Finding 3's survivor.

## Founder triage notes
Platform tier: the B-pass is required by the merge seam. Every finding was fixed in the branch before the merge go is asked. Order: this PR merges first, then the four Edge Function deploys (one go each), then the cleanup SQL (its own go), then Unit 2a (PR #270).

## Tuning entry
- **2026-11-14** - blast-radius platform - 6 findings; 0 false_alarm; tuning: none to the lens set. Observed: lens 7 (missing_input) earned its keep on name rules: the reviewer replayed the regexes against invented but realistic dish names, not only the bundled rows the build had measured, and found two rule shapes (an allow word that short-circuits a deny word; a rescue word anywhere in the name) that the asset happens not to exercise. For any allow/deny name rule, test the COMBINATIONS (allowed word + each deny word; deny word + rescue word elsewhere), not only the corpus.
