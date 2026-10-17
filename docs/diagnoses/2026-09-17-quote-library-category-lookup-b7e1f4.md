---
bug_id: b7e1f4
date: 2026-09-17
batch: obs-batch-2026-09-17
status: fixed
blast_radius: feature
symptom: >-
  Founder completed a Push + Core Phase 3 workout (Hanging Leg Raise 4 sets,
  Self-Resisted Triceps Extension 1 set, Dumbbell Fly 1 set) and the
  post-completion receipt card showed "Glute work. Powerhouse confirmed." — a
  legs/glutes-tagged quote — on a workout with zero glutes or leg-day
  exercises. Founder reported the same symptom the prior day; deterministic.
concept: quote_picker_category_derivation
recurrence: >-
  Recurrence of the quote-picker category misderivation CLASS (same symptom as
  diagnose e3d8fa, 2026-09-16), but a DIFFERENT root cause that e3d8fa's fix
  did not cover, and a different FIX SHAPE than the keyword-patch first drafted
  this session. e3d8fa fixed whole-word BACK/CURL collisions and reordered
  LEGS ahead of PULL/PUSH. This instance has two independent causes neither
  addressed there: (1) "Hanging Leg Raise" is a CORE exercise per the library
  (assets/data/exercise_library.json E057: category "core", movement_pattern
  ["core"], primary_muscles ["Core","Obliques"]) but the keyword classifier
  returns 'legs' because \bLEGS?\b matches the whole word "LEG" in its name —
  a domain false positive; (2) "Dumbbell Fly" is a PUSH exercise per the
  library (E006: category "push", horizontal_push, primary_muscles ["Chest"])
  but matches no PUSH keyword and falls to 'general'. Together: legs=1 vs
  push=1 tie resolved to legs by Dart map insertion order
  (categoryForExercises's counts.keys.first).
  A first-draft fix (three more keyword correction rules) was written,
  tested, and then REVERTED unused after the founder asked the design
  question "are we resolving votes from the muscles exercises target?" —
  the right fix reads the library's category field instead of guessing from
  names. See related memory: feedback_observation_workflow.md 2026-09-17
  entry (wrote the fix before the design debate).
related_bugs: e3d8fa
sot_registry_entry: not_applicable — display-only motivational quote category derived per-render from already-loaded data; no Hive/Postgres writer/reader concept.
writers:
  - { file: lib/features/train/services/quote_picker.dart, method: categoryForExercise (NEW — library lookup + keyword floor), line: 87 }
  - { file: lib/features/train/services/quote_picker.dart, method: categoryForWorkout (unchanged keyword classifier — now the FALLBACK floor), line: 130 }
readers:
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method: "async QuotePicker.pickForCategory(category: QuotePicker.categoryForExercises(...))", line: 669 }
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method: "sync _pickTagline calling QuotePicker.categoryForExercises directly", line: 99 }
hive_key_prefix: n/a — reads exerciseBox rows (seeded library + user custom_exercise rows) by EXACT name via ExerciseRepository.getByExactName; writes nothing
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
  - { pattern: "categoryForExercises resolving a library exercise by name keywords when the box holds its category", absent_after_fix: true }
  - { pattern: "Hanging Leg Raise resolving as 'legs' instead of 'core'", absent_after_fix: true }
  - { pattern: "Dumbbell Fly resolving as 'general' instead of 'push'", absent_after_fix: true }
proposed_fix: >-
  NEW QuotePicker.categoryForExercise(name): ExerciseRepository.getByExactName
  → row['category'] trimmed+lowercased (library values are already lowercase
  and 1:1 with quote tags; custom_exercise rows in the same box carry
  CAPITALIZED values ('Push'), hence normalization) → return it when
  non-empty; else (name absent from the box, or Hive unavailable —
  widget tests without seeding, early startup) fall back to the unchanged
  keyword classifier categoryForWorkout. The try/catch floor is deliberate:
  categoryForExercises is also called from the receipt card's sync
  _pickTagline path, which runs in contexts that may not have Hive open;
  fallback == exact pre-lookup behavior, and the lookup path itself is
  pinned by the Hive-backed WHOLE-LIBRARY sweep test. categoryForExercises
  now votes per-exercise through categoryForExercise; the workout-NAME
  fallback stays keyword-classified (workout names are not exercise-library
  rows). "Reverse Fly" needs no special-case guard — the library says pull,
  so ground truth resolves it directly (the keyword-patch draft needed a
  REVERSE guard; the library fix makes it unnecessary).
regression_test_planned:
  - test/contracts/quote_picker_category_from_exercises_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter test test/contracts/quote_picker_category_from_exercises_test.dart -> 13/13 passed (9 pre-existing assertions all still hold under library lookup; +4 new: founder case, Reverse-Fly/Cable-Fly library truths, keyword fallback for absent names, whole-library sweep >200 rows zero mismatches). Mutation-proven with TWO mutations, one per protection leg (details in the Mutation-proof section): mutation 1 (vote wiring reverted to categoryForWorkout(n)) reddened the founder-case VOTE assertion (Expected push / Actual legs) and left the sweep green; mutation 2 (categoryForExercise's lookup neutered via '&& false') reddened founder-case at the Hanging Leg Raise assertion (Expected core / Actual legs), the Reverse Fly library-truth assertion, and the sweep with 24+ mismatches. Restored -> 13/13 green. The diagnose-doc's first draft mis-predicted mutation 1 would redden the sweep; the actual run corrected it and the doc was amended." }
  - { tier: 2_hive, status: verified, evidence: "READ-ONLY on exerciseBox via ExerciseRepository.getByExactName (exact, case-insensitive, substring-safe). No key written. Custom_exercise rows living in the same box resolve through the same lookup (category lowercased). Seeded-box behavior pinned by the sweep test (test seeds from the real assets/data/exercise_library.json)." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no table read or written" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function involvement" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "workout_quotes.json and exercise_library.json are bundled app assets, not Storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service call" }
  - { tier: 12_client_server_contract, status: not_applicable, evidence: "purely client-side derivation from an already-open local box; no client-server contract involved" }
impact_analysis: >-
  Feature-tier, cosmetic (a motivational quote/caption), no data integrity
  risk. The fix resolves the ENTIRE misclassification class for every
  exercise whose row carries a category — not just the two reported —
  because per-exercise resolution now reads ground truth instead of name
  heuristics. Names absent from the box (free-text custom entries, typos)
  keep the pre-fix keyword behavior exactly (same-code fallback floor).
  Performance: getByExactName is a linear scan of exerciseBox (~300 rows)
  per exercise name; receipts render 3-10 exercises, once per render —
  sub-millisecond, same box the receipt card already reads. 'flexibility'
  rows resolve to 'flexibility', which has no quote pool and falls through
  to 'general' quotes in pickForCategory — same visible behavior as the
  pre-fix keyword path for stretch/cool-down exercises. Custom rows with a
  capitalized category ('Push') normalize to the quote tag via lowercase.
  No other caller of categoryForWorkout changes meaning: it is now
  exclusively the fallback floor + workout-name classifier; the 9
  pre-existing keyword assertions in the contract test still pass unchanged.
---

# "Glute work" legs quote shown on a Push + Core workout (root fix: library ground truth)

## What was actually wrong

`QuotePicker.categoryForExercises` voted per-exercise through
`categoryForWorkout` — a pure NAME-KEYWORD classifier
(`lib/features/train/services/quote_picker.dart`). Two of the founder's three
exercises were misresolved by it:

| Exercise | Library says | Keyword classifier said | Why |
|---|---|---|---|
| Hanging Leg Raise | `core` (E057) | `legs` | `\bLEGS?\b` matches the whole word "LEG" — here it means movement direction, not leg-day |
| Dumbbell Fly | `push` (E006) | `general` | No PUSH keyword (PUSH/CHEST/PRESS/SHOULDER/TRICEP) fits "Fly" |
| Self-Resisted Triceps Extension | `push` | `push` ✓ | TRICEP keyword |

`categoryForExercises` excludes `general` from the vote → legs=1 vs push=1
**tie** → Dart map iteration is insertion order → `counts.keys.first` = legs
(Hanging Leg Raise processed first) → legs quote. The founder saw it on two
consecutive days because the vote is deterministic.

## Why the first-drafted fix was rejected (design lesson)

The first draft patched the KEYWORDS (three more correction rules:
HANGING+LEG/KNEE→core, REVERSE+FLY→pull, FLY→push). It tested green. Then the
founder asked: *"are we resolving the exercises votes based on the muscles
they are targeting or what are we checking?"* — and the honest answer was that
the classifier was guessing from names when the exercise library ALREADY
carries the authoritative `category` for every row, and the app already reads
it this way elsewhere (`train_provider.dart:369-382`: category →
getById(exercise_id) → search(name) fallback chain). Keyword patches fix
instances; the library fix kills the class. The draft was fully reverted
(diagnose-doc included) and this root fix written instead. Note the concrete
simplification the root fix bought: the keyword draft needed a REVERSE+FLY
guard to keep "Reverse Fly" on pull — the library lookup needs no guard at
all, because the library row already says `pull`.

## The fix

`lib/features/train/services/quote_picker.dart`:

1. **NEW `categoryForExercise(String exerciseName)`** —
   `ExerciseRepository.instance.getByExactName(name)` →
   `raw['category']` trimmed + lowercased → return when non-empty; on any
   miss (name not in the box, box not open) fall back to the unchanged
   `categoryForWorkout(name)`. Lowercasing covers custom_exercise rows,
   which store capitalized categories ('Push').
2. **`categoryForExercises`** now votes per-exercise through
   `categoryForExercise`; the workout-NAME fallback
   (`categoryForWorkout(workoutName)`) is deliberately unchanged — workout
   names ("Push + Core", custom template names) are not exercise-library
   rows.

With the fix the founder's vote is core=1 (Hanging Leg Raise, from library)
vs push=2 (Triceps Extension + Dumbbell Fly, from library) → **push wins** →
a push-tagged quote renders.

## Safety of the try/catch floor (stated, because this repo has been burned by silent catches)

`categoryForExercises` is called from the receipt card's SYNC `_pickTagline`
path (workout_receipt_card.dart:99), which runs in widget-test and early-
startup contexts where exerciseBox may not be open. Without the catch, every
such context would throw where it previously got keyword behavior. The catch
returns EXACTLY the pre-lookup behavior (keyword floor), so no context can
regress — and the lookup path itself is independently pinned by the
Hive-backed tests below, which seed the real library. A regression in the
lookup reddens the sweep even though the catch would silently absorb it at
runtime; the test is the detector, not the catch.

## Regression test

`test/contracts/quote_picker_category_from_exercises_test.dart` (Hive seeded
in `setUpAll`, mirroring `coaching_content_test.dart`):

- **Founder case**: `categoryForExercise('Hanging Leg Raise')` → `core`;
  `categoryForExercise('Dumbbell Fly')` → `push`; the exact 3-exercise vote →
  `push`.
- **Library truths**: `Reverse Fly` → `pull`, `Cable Fly` → `push`,
  `Incline Dumbbell Fly` → `push` (no guard needed — ground truth).
- **Fallback floor**: a name absent from the box still resolves via keywords;
  empty exercise list still falls back to the workout NAME.
- **WHOLE-LIBRARY sweep (the class-killer)**: every seeded library row with a
  non-empty category resolves through `categoryForExercise` to its OWN
  category (>200 rows, zero mismatches). This is what makes the fix a class
  fix: any future name that keyword-guesses wrong cannot surface while its
  library row exists.
- All 9 pre-existing keyword assertions still pass — they now pin the
  FALLBACK floor's contract (and `categoryForWorkout`'s pure behavior,
  unchanged).

## Mutation-proof (TWO mutations — one per protection leg)

The fix has two distinct protection legs, and the first mutation attempt
proved they are independent: mutation 1 reddened the vote wiring's test while
the sweep stayed green. Both legs were therefore mutated separately, and the
diagnose-doc's first draft was corrected to record what ACTUALLY reddened
rather than what was predicted (the "read the failure, do not just count it"
rule).

**Mutation 1 — vote wiring reverted** (categoryForExercises's per-exercise
call changed from `categoryForExercise(n)` to `categoryForWorkout(n)`, the
exact pre-fix wiring):

- `founder case` — RED at the FINAL vote assertion: `Expected: 'push' /
  Actual: 'legs'` (the exact founder-facing defect; the per-exercise
  assertions INSIDE that test stayed green because they call
  `categoryForExercise` directly, which mutation 1 does not touch).
- `WHOLE-LIBRARY sweep` — **stayed GREEN**, and `REVERSE/library truths` and
  `fallback floor` stayed GREEN. This is the honest result: the sweep pins
  `categoryForExercise`, not the vote wiring — one mutation cannot prove both
  legs, which is exactly why mutation 2 exists.

**Mutation 2 — lookup neutered** (inside `categoryForExercise`, the return of
the resolved library category disabled: `&& false` — code still compiles and
runs, it just never uses what it fetched; a compile error would not have been
a valid mutation):

- `founder case` — RED at the FIRST assertion: `Expected: 'core' /
  Actual: 'legs'` on `categoryForExercise('Hanging Leg Raise')`.
- `REVERSE/library truths` — RED: `Expected: 'pull' / Actual: 'general'` on
  `Reverse Fly`.
- `WHOLE-LIBRARY sweep` — RED with **24+ reported mismatches**, e.g.
  `Dumbbell Fly: library=push resolved=general`, `Lateral Raise:
  library=push resolved=general`, `Step Up: library=legs resolved=general`,
  `Romanian Deadlift: library=legs resolved=pull`, `Nordic Curl:
  library=legs resolved=pull`, `Rowing Machine: library=cardio
  resolved=general`, `Hanging Leg Raise: library=core resolved=legs` —
  independent confirmation that the sweep covers dozens of rows the keyword
  classifier mislabels, not just the two founder-reported ones.
- `fallback floor` — GREEN under BOTH mutations (correct: it pins the
  keyword path, which neither mutation touches).

Restored the fix → **13/13 green again**. Between the two mutations, every
new assertion reddens under at least one of them and the pre-existing 9 stay
green under both — the test file isolates precisely this fix's protection.

## Verification of current live behavior (founder-facing)

The founder's Push + Core receipt will now render a push-tagged quote
(e.g. "Chest carved. Tomorrow walks easier." / "Push day. Posture
upgraded."), because the vote is push=2 vs core=1 with no `general`
absorbers. The "Glute work. Powerhouse confirmed." quote (tags `["legs",
"glutes"]`) can only render when the resolved category is `legs` — i.e. on
workouts whose exercises genuinely are legs rows per the library.
