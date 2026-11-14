---
bug_id: c9bc6a
date: 2026-11-14
batch: diet-food-type-server (diet plan Unit 2b, plan docs/plans/diet-food-type-server.md revision 3, 2 review rounds, converged)
status: fixed
blast_radius: platform
symptom: >-
  The server and the coach read the user's food type (user_profile.
  diet_preference) in four different ways and wrote it in a fifth. The
  nightly coach extraction (daily-snapshot) proposed a food type from chat
  text in its own vocabulary (vegetarian|vegan|non_veg|keto|pescatarian),
  copied it into the coach notes that are re-embedded and retrieved by the
  coach every run, and upserted it into user_profile (lock permitting). The
  protein-gap push gave a vegan paneer and milk and an eggetarian chicken.
  The coach's suggestMeal tool ignored the stored food type and guessed
  vegetarian from food names (dropping Eggplant and Eggless dishes, missing
  "McChicken"), with a comment claiming the table had no is_veg column
  (false since migration 041). The captain manual said "Vegetarian-first ...
  eggs (where eggetarian)" with no definitions; the weekly report passed the
  raw stored string. The founder (2026-11-14): "Everywhere it should be
  same. The coach should be aware about this."
concept: diet_preference_vocabulary
recurrence: >-
  RECURRENCE of a2b2f1 (2026-09-27, the same column's two-writer drift: the
  coach extraction vs the user's Edit Profile; that fix added the lock and
  taught one reader two spellings, OI-257). Pairs with Unit 2a's client
  diagnose 6f5aaa (same class, client half). Known-good fix applied: one
  closed vocabulary and one normaliser every reader goes through, and the
  AI extraction stops being a writer of a user's explicit choice at all.
related_bugs: [a2b2f1, 6f5aaa]
sot_registry_entry: diet_preference_vocabulary (new, server half); coach_extraction_locked_fields; user_preferences_coaching_notes
writers:
  - { file: supabase/functions/_shared/food_types.ts, method: normalizeFoodType / knownFoodType / dietPreferenceLine, line: 75 }
  - { file: supabase/functions/daily-snapshot/index.ts, method: dropFoodType + extractCoachingNotes prompt + mergeCoachingNotes (no longer writes diet_preference), line: 109 }
readers:
  - { file: supabase/functions/protein-gap-alert/message.ts, method_or_widget: pickQuickFix, line: 40 }
  - { file: supabase/functions/_shared/tools/nutrition/suggestMeal.ts, method_or_widget: readStoredFoodType + handler, line: 164 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: "'Diet preference:' prompt line", line: 513 }
  - { file: supabase/functions/_shared/captain_manual.ts, method_or_widget: captainManual (the food-type rule), line: 482 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "promptParts = [captainManual(), ...]", line: 1094 }
hive_key_prefix: n/a (server only)
hive_key_formula: n/a
sync_methods: []
restore_methods: []
cloud_table: user_profile
cloud_columns: [diet_preference]
contract_test_path: supabase/functions/_shared/food_types_test.ts
ist_handling:
  - { file: supabase/functions/daily-snapshot/index.ts, line: 109, fn: "dropFoodType (no date key; IST unchanged elsewhere)" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: "a raw diet_preference string compared on the server without normalizeFoodType / knownFoodType", absent_after_fix: true }
  - { pattern: "diet_preference in the extraction prompt schema, the coaching_notes upsert, the embedding text or the user_profile candidate upsert (switch off)", absent_after_fix: true }
  - { pattern: "paneer, milk, whey or egg in a vegan quick fix; chicken or mutton for eggetarian / pescatarian", absent_after_fix: true }
  - { pattern: "suggestMeal filtering by a name keyword list instead of is_veg / is_vegan (switch off)", absent_after_fix: true }
  - { pattern: "a prompt builder reading CAPTAIN_MANUAL directly instead of captainManual()", absent_after_fix: true }
proposed_fix: >-
  _shared/food_types.ts mirrors the Dart vocabulary (same fixture). The
  extraction stops producing a food type (prompt line removed, dropFoodType
  before the empty check and at the top of mergeCoachingNotes, an inherited
  notes copy deleted). protein-gap-alert's quick fix is a 5 x 3 table keyed
  by the normalised type. suggestMeal reads the caller's stored food type
  and filters with is_veg / is_vegan (egg / fish name rules for the
  is_veg = false rows, a vegan dairy/honey deny-list); the model's isVeg
  narrows. The captain manual defines the five types and the older
  spellings; weekly-report's line is a closed label. Three kill switches,
  each exactly "true": DISABLE_FOOD_TYPE_EXTRACTION_RULES,
  DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE, DISABLE_FOOD_TYPE_MANUAL_RULES
  (removal: OI-510). protein-gap-alert's closed table is strictly more
  correct for every stored value and rolls back by redeploy.

touched_layers_checked:
  - { tier: 1_client_code, status: verified, evidence: "one Dart source pin repointed (coach_write_claim_wiring_test.dart, green); no lib/ change in 2b" }
  - { tier: 2_hive, status: not_applicable, evidence: "server only" }
  - { tier: 3_postgres_schema, status: verified, evidence: "live read-only 2026-11-14: user_profile.diet_preference text, no CHECK; food_database has is_veg / is_vegan (1,431 rows: is_veg true 1,235 / false 196 / null 0; is_vegan true 631)" }
  - { tier: 4_postgres_data, status: verified, evidence: "live read-only 2026-11-14: user_profile.diet_preference veg 32, non_veg 4, null 1, non_vegetarian 1 (all test accounts); every value is a fixture row. The stale-copy cleanup (memory_embeddings daily_summary content, coach_memory.locked_field_conflicts) runs only with its own founder go, rehearsed locally first; its SQL and before/after counts are added here then" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "four functions change: daily-snapshot, protein-gap-alert, weekly-report, ai-proxy; deployed from the merged main SHA with per-function founder go; versions recorded here at deploy" }
  - { tier: 7_cron_jobs, status: verified, evidence: "protein-gap-alert is cron-dispatched; no schedule change; its next run is the deploy proof (cron_call_log)" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "service-role reads; suggestMeal's user_profile read is scoped .eq(user_id, ctx.userId) (test pins the filter)" }
  - { tier: 9_storage, status: not_applicable, evidence: "no Storage object" }
  - { tier: 10_secrets, status: verified, evidence: "three new optional secrets, all absent by default (absent = new behaviour); none set" }
  - { tier: 11_external_services, status: not_applicable, evidence: "Gemini prompt text changes only (extraction schema line, manual rule); no new call" }
  - { tier: 12_client_server_contract, status: verified, evidence: "the five canonical keys are the shared fixture rows both the Dart (Unit 2a) and TS normalisers are tested against; every legacy value today's clients store is a fixture row" }
impact_analysis: >-
  Platform tier (daily-snapshot, _shared/**). Before Unit 2a merges the
  stored values are today's (veg, vegetarian, non_veg, keto, null, ...);
  every 2b reader normalises them, so deploying 2b first changes only what
  is wrong today: a vegan's quick fix, an eggetarian/pescatarian's meal
  suggestions, a coach rule with definitions, a weekly label, and the
  extraction no longer overwriting or re-embedding a food type. Users
  notice: the coach no longer "remembers" a food type from chat (the
  profile is the only source); a stored keto user reads as Non-veg (the
  low-carb signal returns with Unit 3's strategy). Rollback: the three
  switches (no redeploy) or a redeploy of the previous versions.
regression_test_planned:
  - supabase/functions/_shared/food_types_test.ts (T1, every fixture row, both readers)
  - supabase/functions/daily-snapshot/index_test.ts (T2: 6 new + 8 rewritten)
  - supabase/functions/protein-gap-alert/index_test.ts (T3: the 5 x 3 table)
  - supabase/functions/_shared/captain_manual_food_type_test.ts (T4 / T6)
  - supabase/functions/_shared/tools/__tests__/suggestMeal_test.ts (T5, incl. a seed scan of the bundled asset)
---

# One food-type vocabulary on the server and in the coach (c9bc6a)

## Writers and readers (named before the fix)

Writer: `daily-snapshot` `extractCoachingNotes` (the prompt's
`diet_preference` line) → `mergeCoachingNotes` (coaching_notes JSON, a new
`daily_summary` embedding row every run, the user_profile candidate upsert
and the lock/conflict loop). Readers: `protein-gap-alert/message.ts`
`pickQuickFix`, `suggestMeal` (model-chosen `isVeg` + name keywords),
`weekly-report`'s prompt line, the captain manual's diet lines (via the
snapshot), and `ai-proxy`'s retrieval of the embedded notes.

## Fix

See `proposed_fix`. The decision that matters: the extraction is no longer
a writer of the food type at all. A chat sentence ("I'm vegetarian now") is
not the user's choice; the choice lives in the profile, set by the app's two
doors (Unit 2a), and the coach reads it from the snapshot.

## Build-time corrections

Plan §8 (and Unit 2a's B-pass finding 1, mirrored here: `normalizeFoodType` reads null/undefined as the default and any other non-string as `veg`; the shared fixture gained three rows). The two watermark tests needed a different reply; the profile read
runs before the queries; `captainManual(` is a sanitiser safe marker; one
Dart pin repointed; the SoT entry is created here and completed by 2a.

## Seed scan (bundled asset, the `is_veg = false` rows)

196 rows. Eggetarian keeps 35 (every one an egg row: boiled, raw, whites,
omelettes incl. Cheese and Veg Omelette, Egg Biryani, Egg Fried Rice, Egg
Chowmein, Kathi Roll (Egg), Quail Egg, Duck Egg, Egg Salad). Pescatarian
keeps 91 (those plus fish and seafood: curries, fries, cooked fillets,
tinned tuna/sardines/salmon, prawns, crab, squid, lobster, shellfish,
Sushi Roll (Salmon), Tuna Salad). None contains a meat word (independent
oracle). "Biryani (Veg)" is tagged `is_veg = false` in the asset and is
dropped for both (safe).

## Mutation proof (rule 21)

Each guard was broken by a script that asserted the anchor matched exactly
once and the edit APPLIED, ran the listed Deno tests, restored the file and
asserted it byte-equal (sha256). No result is a compile error (`--no-check`
runs; every mutant is valid TS).

| # | Guard broken | Tests | Failing |
|---|---|---|---|
| B1 | `knownFoodType` returns non_veg for unknown | food_types_test | 1 |
| B2 | `mergeCoachingNotes` does not drop the food type | daily-snapshot | 2 |
| B3 | extraction does not drop before the empty check | daily-snapshot | 1 |
| B4 | inherited notes copy kept | daily-snapshot | 1 |
| B5 | extraction switch inverted | daily-snapshot | 6 |
| B6 | prompt always asks for a food type | daily-snapshot | 1 |
| B7 | vegan quick fix uses paneer | protein-gap-alert | 2 |
| B8 | quick fix bypasses the normaliser | protein-gap-alert | 1 |
| B9 | meat rule loses `murgh` (survived the first set; mixed-dish list added) | suggestMeal | 1 |
| B10 | egg rule unanchored (`egg` substring) | suggestMeal | 1 |
| B11 | stored food type ignored | suggestMeal | 2 |
| B12 | vegan deny-list off | suggestMeal | 1 |
| B13 | `isVeg` no longer narrows | suggestMeal | 2 |
| B14 | suggestMeal switch inverted | suggestMeal | 6 |
| B15 | manual switch inverted | captain_manual_food_type | 1 |
| B16 | weekly-report keeps the raw line | captain_manual_food_type | 1 |
| B17 | `fake_sb` numeric compare reverted | suggestMeal | 3 |
| B18 | pescatarian capsule exclusion off | suggestMeal | 2 |
| B19 | a corrupt non-string reads as the default again (Unit 2a B-pass F1 mirror) | food_types_test | 1 (the whole non-string test; the shared fixture rows also fail) |
| B20 | eggetarian fish check dropped (B-pass 1) | suggestMeal | 1 |
| B21 | hot dog / mcmuffin / jerky not meat (B-pass 1) | suggestMeal | 1 |
| B22 | capsule checked only on the fish branch (B-pass 1) | suggestMeal | 3 |
| B23 | a plant word anywhere rescues every deny word (B-pass 2, the old rule) | suggestMeal | 1 |
| B24 | the plant rescue no longer needs the word right before (B-pass 2) | suggestMeal | 1 |
| B25 | "egg plant" exemption dropped (B-pass 2) | suggestMeal | 2 |
| B26 | a failed read falls back to non_veg (B-pass 3) | suggestMeal | 2 |
| B27 | schema getter ignores the switch (B-pass 4) | suggestMeal | 1 |
| B28 | no protein order before the limit (B-pass 6) | suggestMeal | 1 |
| B29 | alias key `diet` not dropped (B-pass 5) | daily-snapshot | 1 |
| B30 | an inherited alias key kept (B-pass 5) | daily-snapshot | 1 |
| B31 | key case not folded (B-pass 5; survived until a mixed-case reply key was added) | daily-snapshot | 1 |

Declared limits: weekly-report's prompt line and the two `captainManual()`
call sites are presence pins (the handlers build the prompt inline under a
module-scope `serve()`); the behaviour of `dietPreferenceLine` and
`captainManual()` is tested directly. Whole-tree Deno run on the VPS: 1,707
passed, 2 failed with `AddrInUse` on :8000 (`future-prediction`,
`re-engagement`: they `serve()` at import and a docker container holds the
port; known VPS quirk, CI has no conflict); both import nothing this unit
changed except `future-prediction`'s use of `fake_sb.ts`, whose filters
there compare ISO date strings (unchanged semantics).

## B-pass fixes (2026-11-14, `docs/reviews/diet-food-type-server-bpass.md`)

Three P2 and three P3 findings on b76694b1, all fixed here (plan §8 lists
each): the eggetarian egg rule no longer admits fish, a capsule or a hot
dog; vegan deny words are absolute and the plant rescue needs the plant word
right before the dairy word; a failed profile read shows vegan options; the
kill switch restores the old `isVeg` description; alias food-type keys are
dropped from the extraction and from inherited notes; the veg queries keep
the most protein-rich rows past the limit. Measured on the bundled asset:
eggetarian 35 and pescatarian 91 rows kept (unchanged), vegan 632 of 637
(unchanged; the dropped five are the old five). Live (read-only): only
`diet_preference` exists as a food-type key, in 18 embeddings and 3
`coaching_notes` rows; the cleanup SQL now strips all 21 (all 10 JSON
notes rows parse). Mutations B20 to B31.

## Deploys and cleanup (filled in at deploy time)

Order: daily-snapshot, protein-gap-alert, weekly-report, ai-proxy, from the
merged `main` SHA, each with the founder's go and a rollback dry-run first.
Then the stale-copy cleanup with its own go. Then Unit 2a's PR merges.
