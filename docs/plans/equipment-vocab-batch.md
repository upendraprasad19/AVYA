# Focused plan — ⑥ slice A: equipment_needed vocabulary normalization

Branch `workout-equipment-vocab` off `0e3d0f84` (⑥ crash-fix shipped). Precedes code per §4.12 (this plan
→ ×2 context-blind review → `docs/plan-reviews/workout-equipment-vocab.md` converged → implement → B-pass →
land). Second slice of the founder-approved ⑥ split (crash-fix `0e3d0f84` → **A** → B → C).

**Tier: ACCOUNT** (hardened from an initial "feature" mislabel — R1 architecture P0-1). File→tier under
`blast_radius.yaml` (first-match-wins): `assets/data/exercise_library.json`→feature; **`lib/core/services/seed_service.dart`→account** (`lib/core/services/**` :105); **`lib/core/utils/equipment_vocab.dart`→account** (`lib/core/**` :109); `lib/features/train/**`, `scripts/**`, `test/**`, `docs/**`→feature. Max = **account** → `requires: [regression_test, behavioral_test_path, code_review_b_pass]` (NO feature_flag). Account triggers the §4.12.3 plan-review-record CI gate (review_rounds≥2 + ground_truth_verified + converged) + a self-initiated B-pass before the `--no-ff` merge.

## Scope — the SMALLEST converged piece (§4.12)
Normalize the library's free-text `equipment_needed` (87 tokens / 258 rows) to a CONTROLLED VOCABULARY,
add a central `EquipmentVocab` (mirrors `InjuryVocab`), and normalize the app's OWN custom-exercise write.
Data-quality PREREQUISITE for slice B's item-level exclusion filter — changes **no live plan generation**
(which filters on the separate clean `equipment_tier`).

**IN slice A** (account tier):
1. Normalize all 258 rows' `equipment_needed` → canonical tokens in `assets/data/exercise_library.json` (via the idempotent generator in step 3, so seed == `EquipmentVocab.normalize(library)` by construction).
2. Bump `seed_service.dart` `_exerciseLibraryVersion` 6→7 (re-seeds normalized JSON into existing installs).
3. New `lib/core/utils/equipment_vocab.dart` + `scripts/normalize_equipment_library.dart` (one-time, idempotent — applies `EquipmentVocab.normalize` to each row; re-runnable safely).
4. Normalize the OWNED custom-exercise write (`workout_repository.dart:1375`) via `EquipmentVocab.normalize`.
5. Contract gate + `normalize`/`fromProfile` unit tests + a behavioral write→read test for the owned seam.

**OUT of slice A — lands with its CONSUMER in a later ⑥ slice (founder-approved A→B→C decomposition, NOT a deferral — each has no reader until its slice):**
- The `queryV4` item-level exclusion filter = slice B (it IS the filter).
- The community-DOWNLOAD `equipment_needed` normalize — `sync_community.dart:504` (`syncCommunityItems` → `exerciseBox.put(id, map)`), **platform tier (`sync/**`)**. Its only reader is the dead V3 filter that slice B revives (the coach snapshot reads `customBox`, NOT `exerciseBox`, so community rows aren't read live now). Lands with slice B's filter. (NOT `:259-260` `_projectCustomExercise`, which is the own-custom UPLOAD projection, downstream of the `:1375` owned-write normalize — needs nothing.) (R2 P2-1)
- `EquipmentVocab.itemsForTier` (centralizing `plan_generator.dart:228-248` `_getEquipmentList`) — editing `plan_generator.dart` needs explicit instruction (**coding-rule #14**); belongs with slice C's tier-UI centralization. Omitted (YAGNI). ⇒ R1 vocab P1-4 (itemsForTier byte-identical test) is MOOT for slice A.

## Ground-truth (SELF-VERIFIED against code + JSON; both R1 reviewers independently confirmed)
- **Live V4 filter reads `equipment_tier`, NOT `equipment_needed`** — `plan_generator.dart:112` (sole `pickV4` caller) → `queryV4` filters `e['equipment_tier']` at `lib/shared/repositories/exercise_repository.dart:270`. The `equipment_needed` read at `exercise_repository.dart:129` is inside V3 `query()`, reached only via `ExerciseSelector.pick` (ZERO live callers; revived by slice B). (File is `lib/shared/repositories/exercise_repository.dart` — NOT under `plan_engine/`.)
- **258 rows, 87 distinct tokens (61 non-OR + 26 OR-compound), 0 bare Strings.** Row partition: 170 plain-single + 52 plain-multi + 36 OR-rows (33 single + 3 OR-mixed-AND) = 258. Total single-element = 203, multi = 55.
- **`equipment_tier` clean on all 258 rows** {bodyweight/home_dumbbells/basic_gym/full_gym}.
- **Only 3 OR-mixed-AND rows** (collapse the OR element per-token, keep the AND sibling): E041 `["Dumbbells or Barbell","Bench"]`→`[dumbbells, bench]`; E044 `["Dumbbell","Box or Bench"]`→`[dumbbells, bodyweight]` (Box→bodyweight wins over Bench; **corrects R1's stale `[dumbbells,bench]`**); E148 `["Bodyweight","Partner or Nordic Attachment"]`→`[bodyweight]`.
- **No BREAKING exact-string match on `equipment_needed`** — only `== 'none'` / `== 'bodyweight'` (dead V3 filter `exercise_repository.dart:135-136`), both canonical tokens normalization PRESERVES (R1 P2-6).
- **Seed re-propagation:** `seed_service.dart:81` `= 6`; reseed `storedExVersion < constant` (:113-114); `putAll` by id (:176; :178 writes the version). Bump 6→7.
- **Owned fresh-free-text write:** `workout_repository.dart:1375` `<String>[equipment]`. (`create_custom_exercise_sheet.dart:84` writes `<String>[]` → normalize is a no-op there → NOT a seam.)

## Founder decision (2026-07-14) + live-consumer precision (R2 P1-1 corrected)
**OR-compounds → collapse to the single MOST-ACCESSIBLE alternative.** Live-impact ground truth (R2-verified,
correcting my earlier overstatement): the SEED library's `equipment_needed` has **NO live UI reader at all** —
the V3 filter (`exercise_repository.dart:129`) is dead, V4 reads `equipment_tier`, and **no widget renders
equipment tokens** (`ExerciseSwapSheet` receives an `equipment` param but never displays it — `_buildDetail`
shows category·loggingType·difficulty only; a full `lib/` grep finds no `equipmentNeeded` text render). The
ONLY live delta is the OWNED custom-exercise write (`workout_repository.dart:1375` → `customBox`): after
normalize, a custom exercise's equipment reaches the AI-coach snapshot (`ai_snapshot_builder.dart:518` reads
`customBox`) as a canonical token ("cables" not "Cable Machine") — benign (an AI payload, not UI). So slice A
is SAFER than a display-changing batch: no UI churn, no generation change. **No `label()`** (nothing displays
these tokens — YAGNI; slice C's Customize UI adds display labels when it needs them). Rest of vocab
founder-delegated; ×2 review + B-pass verify.

## Canonical vocabulary (12 tokens, lowercase, space/hyphen-separated to match siblings)
`bodyweight`, `dumbbells`, `barbell`, `bench`, `pull-up bar`, `cables`, `machines`, `smith machine`,
`resistance band`, `kettlebell`, `ez-bar`, `cardio machine`. (11 non-`none` tier tokens + `cardio machine`
— SPACE, not `cardio_machine`, for consistency with `smith machine`/`resistance band`; §4.7 checked. `smith
machine` kept — 0 library rows, so the gate is SUBSET not equality, see below.)

## Total precedence (most→least accessible) — replaces the founder's 7-item list (R1 vocab P0-3)
`bodyweight > resistance band > dumbbells > kettlebell > pull-up bar > bench > barbell > ez-bar > cables > machines > smith machine > cardio machine`.
OR-collapse is TWO-STEP: map each `" or "` alternative to its canonical, then pick the min by this order.

## Exhaustive `_aliases` — every raw token (lowercased key) → canonical (round-2 verifies token-by-token)
**Non-OR (61):** bodyweight→bodyweight · barbell→barbell · dumbbells/dumbbell→dumbbells · bench→bench ·
incline/decline/flat/elevated/preacher/hyperextension bench→bench · cable machine→cables · rope→cables ·
machine + ghd/hack squat/hip abduction/hip adduction/leg curl/leg extension/leg press/pec deck/seated calf raise machine→machines ·
pull-up bar→pull-up bar · ez bar→ez-bar · kettlebell→kettlebell · resistance band→resistance band ·
treadmill/stationary bike/rowing machine/assault bike/battle ropes→cardio machine ·
landmine/landmine attachment/squat rack/power rack/t-bar/trap bar→barbell ·
prowler sled/sled/yoke frame/tire (100-200kg)→machines ·
box/box (30-45cm)/box (30-60cm)/medicine ball/wall/doorway/chair/lying/elevated surface/bodyweight (bent over position)/yoga mat/foam roller/ab wheel/jump rope/parallel bars/trx suspension trainer/ankle strap→bodyweight ·
weight plate/sandbag→dumbbells.
**OR sub-alternatives (only inside compounds — normalize's `" or "` split maps them):** band→resistance band · plate/weight→dumbbells · floor/freestanding/pole/broomstick/partner/nordic attachment/trx→bodyweight · rack/barbell on rack/light barbell→barbell · sissy squat bench→bench · reverse hyper machine→machines · cable machine→cables · kettlebells→kettlebell.
**26 OR-compounds resolve to:** bodyweight — barbell on rack or trx, bench or box, bodyweight or {band,barbell,dumbbells,medicine ball,plate,sissy squat bench}, box or bench, broomstick or band, flat bench or pole, parallel bars or floor, partner or nordic attachment, wall or freestanding; dumbbells — barbell or dumbbells, barbell or sandbag, dumbbell or {barbell,kettlebell}, dumbbells or {barbell,cable machine,kettlebells}, kettlebell or dumbbell, light barbell or weight; barbell — machine or barbell; pull-up bar — pull-up bar or rack; bench — reverse hyper machine or bench.

## EquipmentVocab (`lib/core/utils/equipment_vocab.dart`) — DOES NOT inherit InjuryVocab's `\s+` split (R1 vocab P1-1)
- `canonicalTokens` (12, `Set`), `_aliases` (above), `_precedence` (12-list). **No `_labels`/`label`** (R2 P1-1: nothing displays equipment tokens — YAGNI).
- `normalizeToken(String raw) → String?`: `lower=raw.toLowerCase().trim()`; **if it contains `" or "`** → split on `" or "`, map each part via `_aliases`, drop nulls, return min by `_precedence` (null if none map); **else** `_aliases[lower]`. **NO whitespace tokenization** ("cable machine" is ONE key — never split to cable+machine).
- `normalize(Iterable<String>?) → List<String>`: `normalizeToken` each element, drop nulls, **dedupe preserving order**. Unmappable → dropped ⇒ possibly `[]` = most-permissive (dead V3 `.every` on `[]` vacuously true; slice B treats `[]` as no-requirement → never over-excludes). Safe, documented, unit-tested. (Library gate guarantees 0 unmappable library tokens; drop only fires on future/unknown free-text.)
- `fromProfile(Object? raw)`: crash-safe (List→strings; String→[s]; never `as List`) → `normalize`.

## Apply
1. **Generator** `scripts/normalize_equipment_library.dart`: read `exercise_library.json`, `EquipmentVocab.normalize` each row's `equipment_needed`, write back (idempotent). Run once; commit the normalized asset. Bump `_exerciseLibraryVersion` 6→7.
2. **Owned write:** `EquipmentVocab.normalize` at `workout_repository.dart:1375`.
3. **Gate** `test/contracts/equipment_vocab_library_contract_test.dart`: every distinct library `equipment_needed` token (lowercased) ∈ `canonicalTokens` (**SUBSET** — code comment: `smith machine` is canonical with 0 rows, equality would fail; R1 P2-2). FAILS-without-fix (a new raw non-canonical token, or an incomplete rewrite). Plus `normalize`/`normalizeToken`/`fromProfile` unit tests incl. the 3 OR-mixed-AND rows + a "cable machine stays one token" assertion + drop→`[]`.
4. **Behavioral test (account `behavioral_test_path`, R1 vocab P1-2):** custom-exercise write via `workout_repository` with raw "Cable Machine" → Hive read-back asserts `["cables"]` stored (write→read chain; the ≥15× writer/reader-drift class).
5. **SoT** `docs/sot_registry.yaml` `equipment_vocab` concept (writers = normalized seed asset + `workout_repository.dart:1375`; readers = the dead V3 filter `exercise_repository.dart:129` [revived by slice B] + the AI-coach snapshot `ai_snapshot_builder.dart:518` [custom exercises via `customBox`]; NO swap-display reader — nothing renders equipment tokens, R2 P1-1) + `behavioral_test_path`.

## Slice-B forward constraints locked NOW (R1 vocab P2-1 — the vocab pins these tokens today)
- `cardio machine` is absent from every `itemsForTier` tier → slice B's item-filter MUST treat `cardio machine` (and, since they can appear on lower tiers by `equipment_tier`, `ez-bar` + `smith machine`) as **always-available-unless-explicitly-excluded**, like `bodyweight`/`none` — else a naïve `.every(contains)` filter excludes all cardio/ez-bar exercises for everyone.

## Review focus areas (round 2 — verify the HARDENED mapping, don't re-derive structure)
1. The 87-token `_aliases` maps every library token to exactly one canonical; no token unmapped; every value ∈ `canonicalTokens`.
2. Total-precedence collapse is correct for all 26 OR-compounds (esp. the 6 the 7-item list couldn't resolve) + the 3 OR-mixed-AND rows keep their AND sibling; no OR→AND flip.
3. `normalize` treats each list element as ONE token (no `\s+` split); `" or "` handled explicitly; drop→`[]` safe for every reader.
4. Tier honestly ACCOUNT; no `sync/**` or `plan_engine/**` path staged; the two deferred items are correctly scoped to their slice-B/C consumers (no reader now).
5. Gate is SUBSET + fails-without-fix; behavioral write→read seam test present; `equipment_needed_shape` gate stays green; `== none`/`== bodyweight` survive.
6. Seed v7 re-seeds by id; the generator is idempotent; no other owned `equipment_needed` writer missed.
7. Only live delta = owned custom-write → coach snapshot (canonical tokens to Gemini, benign); no UI displays equipment tokens; `cardio machine` naming matches siblings.
