---
bug_id: e3d8fa
date: 2026-09-16
batch: obs-batch-2026-09-16
status: fixed
blast_radius: feature
symptom: >-
  Founder completed an all-legs Phase 3 workout (Barbell Back Squat, Leg
  Extension, Leg Curl (Lying), Handstand Hold, Front Lever Hold) and the
  post-completion receipt card showed the caption "Lats lit. Standing taller
  already." — a pull/back-tagged quote, on a workout with zero back/lat
  exercises. Founder recalled this class of bug had been fixed before and
  asked to check.
concept: quote_picker_category_derivation
recurrence: >-
  Confirmed recurrence of the bug CLASS, not the same fix re-breaking.
  Diagnose d8f3a2 (2026-06-14, Unit 3 obs 2) fixed the original instance:
  `categoryForWorkout` used unbounded `.contains('LAT')`, which matched
  mid-word inside "test temp**lat**e" and mis-tagged an unrelated workout as
  pull. That fix added word-boundary regex (`_hasWord`) for LAT/LEG/ROW/ARM/
  ABS/RUN and made `categoryForExercises` vote across all logged exercises
  instead of trusting the workout name alone. **BACK and CURL were never
  added to that guarded list** — this instance is those two keywords
  recurring in NEW exercise names, not a regression of d8f3a2's own fix
  (still intact, still passing all 8 of its original tests unchanged).
  Additionally, `test/contracts/quote_picker_category_from_exercises_test.dart`
  line 26 (pre-fix) carried a comment explicitly naming this exact collision
  — "avoid 'Back Squat'→BACK→pull + 'Leg Press'→PRESS→push keyword-
  precedence quirks" — meaning the bug was KNOWN and worked around in the
  test suite rather than fixed, since d8f3a2 shipped. This diagnose closes
  that gap rather than continuing to route around it.
related_bugs: d8f3a2
sot_registry_entry: not_applicable — display-only motivational quote category derived from exercise names, not a Hive/Postgres writer/reader concept.
writers:
  - { file: lib/features/train/services/quote_picker.dart, method: categoryForWorkout, line: 80 }
readers:
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method: "async QuotePicker.pickForCategory(category: QuotePicker.categoryForExercises(...))", line: 670 }
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method: "sync _pickTagline fallback calling QuotePicker.categoryForExercises directly", line: 99 }
hive_key_prefix: n/a — no Hive key participates; category is derived per-render from the exercise-name list already in memory
hive_key_formula: n/a
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/quote_picker_category_from_exercises_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "categoryForWorkout checking PULL/PUSH keyword branches before the LEGS branch", absent_after_fix: true }
proposed_fix: >-
  Two independent, verified-necessary changes to `categoryForWorkout`:
  (1) reorder the LEGS keyword check to run FIRST, ahead of PULL and PUSH —
  a word-boundary fix on BACK/CURL alone does NOT resolve "Barbell Back
  Squat" or "Leg Curl (Lying)", because BACK and CURL are genuine, correctly
  spelled whole words in those names (a real cross-category keyword
  collision, not a substring bug); (2) word-bound BACK (`\bBACK\b`) to fix a
  SEPARATE, genuine mid-word substring bug the same audit surfaced —
  "Cable Tricep Kickback" / "Dumbbell Kickback" / "Glute Kickback" all
  matched `.contains('BACK')` inside "Kick**back**", the identical class
  d8f3a2 already fixed for LAT. Verified against the full
  `assets/data/exercise_library.json` (293 exercises) that every name
  matching both a pull keyword and a legs keyword now resolves to legs
  correctly, with zero new false positives introduced elsewhere (checked
  legs∩push overlap too — see impact_analysis).
regression_test_planned:
  - test/contracts/quote_picker_category_from_exercises_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter test test/contracts/quote_picker_category_from_exercises_test.dart -> 9/9 passed. Mutation-proven: reverted lib/features/train/services/quote_picker.dart to the exact pre-fix (committed HEAD) content and re-ran the same file -> exactly 1 of 9 reddened (the new 'BACK/CURL/PRESS cross-category collisions' test, Expected: legs / Actual: pull on 'Barbell Back Squat'), the other 8 pre-existing assertions (including d8f3a2's own LAT/LEG/ROW/ARM word-boundary tests) stayed green; restored the fix and re-ran -> 9/9 green again." }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive key participates" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no table read or written" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function involvement" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "assets/data/workout_quotes.json and exercise_library.json are bundled app assets, not Storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service call" }
  - { tier: 12_client_server_contract, status: not_applicable, evidence: "purely client-side derivation from an already-loaded exercise-name list; no client-server contract involved" }
impact_analysis: >-
  Feature-tier, cosmetic (a motivational quote/caption), no data integrity
  risk. Verified with a standalone script against the full 293-entry
  `assets/data/exercise_library.json` that reordering LEGS ahead of PULL/
  PUSH only changes the outcome for names matching keywords from BOTH
  categories — 7 such names exist (Barbell Back Squat, Leg Curl (Lying),
  Single Leg Romanian Deadlift, Glute Kickback (Cable), Standing Single Leg
  Curl, Glute Kickback, Sliding Leg Curl), all of which now resolve to the
  gym-conventional correct category (legs). Also checked legs∩push overlap
  (1 name: "Leg Press") and found the SAME reorder additionally fixes a
  PRE-EXISTING, previously-unreported miscategorization — "Leg Press" was
  matching PUSH's `PRESS` keyword and never reaching the legs check under
  the old pull→push→legs order. No exercise name in the library regresses:
  every name affected by the reorder was previously wrong and is now
  correct. "Single Leg Romanian Deadlift" is a genuinely ambiguous
  posterior-chain movement (commonly programmed on either leg day or
  pull/back day); resolving it to legs here is a reasonable default for a
  cosmetic quote category, not a claim about optimal program design.
  Deliberately out of scope: "Nordic Curl" / "Reverse Nordic Curl" remain
  categorized as 'pull' (via CURL) despite being hamstring/leg exercises in
  practice — the keyword list has no LEGS-side signal for "Nordic" at all
  (not a BACK/CURL collision, a missing keyword entirely), so this fix's
  reorder does not reach them. Not touched here to keep this fix scoped to
  the reported bug class; flagged for whoever next extends the keyword
  vocabulary.
  Second accepted residual gap, found by the B-pass (`docs/reviews/08821dc5a27b-review.md`
  Finding 1): the BACK word-boundary fix stops "Dumbbell Kickback" from
  wrongly landing on 'pull', but does not land it on its true ground-truth
  category either — `exercise_library.json` tags it `push` (primary muscle
  Triceps) via no keyword this classifier has (no TRICEP/PUSH/PRESS/CHEST/
  SHOULDER substring in the name), so it falls through to 'general'. This is
  a strict improvement (no longer wrong in the founder-reported direction)
  but not a full fix; a `KICKBACK`-qualifier allowlist would close it and is
  left for whoever next extends the vocabulary, same disposition as Nordic
  Curl above. "Cable Tricep Kickback" (has TRICEP) and "Glute Kickback" (has
  GLUTE) are unaffected and resolve correctly.
---

# "Lats lit" pull/back quote shown on an all-legs workout

## What was actually wrong

`QuotePicker.categoryForWorkout` (`lib/features/train/services/quote_picker.dart`)
checked its PULL branch — which included plain `.contains('BACK')` and
`.contains('CURL')` — BEFORE its LEGS branch. Two of the founder's five
logged exercises collided:

- `"Barbell Back Squat"` contains the whole word "BACK" → miscounted as
  **pull**.
- `"Leg Curl (Lying)"` contains the whole word "CURL" → miscounted as
  **pull**.
- `"Leg Extension"` correctly matched **legs**.
- `"Handstand Hold"` / `"Front Lever Hold"` matched no keyword → **general**
  (excluded from the vote).

Vote tally: pull=2, legs=1 → pull wins → the "Lats lit" pull/back quote
rendered on a workout with zero pull/back exercises.

## Why word-boundary alone would NOT have fixed this

The obvious-looking fix — "add BACK and CURL to the `_hasWord` word-boundary
guarded list, same as LAT/LEG" — was tried first and verified to be
**insufficient**. "Back" in "Barbell Back Squat" and "Curl" in "Leg Curl
(Lying)" are both genuine, correctly spelled WHOLE words, not mid-word
substrings — `\bBACK\b` and `\bCURLS?\b` still match them. This is a real
cross-category keyword COLLISION (a name legitimately contains signal words
for two different categories), not the substring-matching bug class d8f3a2
fixed. No amount of word-boundary tightening resolves a tie between two
equally-valid whole-word matches; the categories themselves needed a
priority order.

## The fix

1. **Reordered `categoryForWorkout` to check LEGS first**, ahead of PULL and
   PUSH. Verified via a standalone script against the full 293-exercise
   `assets/data/exercise_library.json`: every name matching keywords from
   both categories (7 total) now resolves to the gym-conventional correct
   category, and the reorder additionally fixed a pre-existing "Leg Press"
   → push miscategorization nobody had reported.
2. **Word-bounded `BACK`** (`\bBACK\b`) to fix a genuinely separate mid-word
   substring bug the same audit surfaced: "Cable Tricep Kickback" /
   "Dumbbell Kickback" / "Glute Kickback" all matched `.contains('BACK')`
   inside "Kick**back**" — the identical bug class d8f3a2 already fixed for
   LAT, just never applied to BACK.

## This bug was already known and routed around, not undiscovered

`test/contracts/quote_picker_category_from_exercises_test.dart`'s "leg
exercises" test carried this comment before the fix: *"Unambiguous leg
names (avoid 'Back Squat'→BACK→pull + 'Leg Press'→PRESS→push
keyword-precedence quirks)."* Someone — most likely during or shortly after
d8f3a2 — had already noticed both collisions and chose test exercise names
that dodged them, rather than fixing the classifier. That comment is
removed; the two "quirks" it named are now directly asserted in a new test
case instead of avoided.

## Regression test

`test/contracts/quote_picker_category_from_exercises_test.dart` gained a
new group covering: the exact founder-reported exercise list resolving to
'legs'; the two named "quirks" from the old avoidance comment
(`Barbell Back Squat`, `Leg Press`) resolving correctly; the Kickback-family
substring fix; and two more library-sourced LEG/CURL collisions
(`Standing Single Leg Curl`, `Sliding Leg Curl`). **Mutation-proven:**
reverted `quote_picker.dart` to its exact pre-fix committed content and
re-ran the file — exactly 1 of 9 tests reddened (the new collision test,
`Barbell Back Squat` expected `legs` got `pull`), the other 8 — including
d8f3a2's own original word-boundary tests — stayed green, confirming this
test isolates precisely this fix's protection. Restored the fix; 9/9 green
again.
