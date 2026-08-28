# Equipment capability model — design

**Status:** COMPLETE. Supersedes `2026-08-27-equipment-vocabulary-design.md` (sections 1–3 only;
2 reviewers, 8 P0) and `docs/plans/oi89-bodyweight-floor-plan.md` (3 reviewers, 20 P0).

**Why those failed, so this one doesn't repeat it:** both were written from partial knowledge of a
highly-coupled surface — a vocabulary constant read by a UI widget, a contract test, a seed
version, a cloud column and an Edge Function. The reviews were the enumeration. This design is
written against that completed map, and every claim below carries a `file:line` verified against
the working tree on 2026-08-28.

**Board:** OI-89. ⚠ Its entry is wrong twice: `open_issues.md:1937` says `blast_radius: account`
(live classifier returns **`platform`** — `blast_radius.yaml:67` puts `plan_engine/**` at platform
*before* the `:264` repositories→account rule) and says *"no migration, no schema"* (§7 adds a
column). Update the board in this batch; do not re-inherit either error.

---

## 0. The root cause, corrected

Earlier framing — *"the vocabulary cannot express an ab wheel"* — was wrong. It could. It did.

`scripts/normalize_equipment_library.dart` (commit `632a10b8`, *"equipment_needed vocabulary
normalization (⑥ slice A)"*) rewrote `assets/data/exercise_library.json` in place, collapsing every
free-text value through `EquipmentVocab.normalize` → `_aliases`.

**87 distinct tokens before. 11 after. `bodyweight` went 82 → 119 rows.**

`632a10b8^` still holds all of it. **49 rows had non-bodyweight equipment collapsed**, and the
recovered values — not anyone's reading of the exercise names — are this design's source of truth.

Roughly 20 of those 49 are true losses. The rest were `X or Bodyweight` compounds where the
collapse was legitimate (`Curtsy Lunge`, `Lateral Lunge`, `Reverse Lunge`, `Sumo Squat`,
`Walking Lunge`, `Glute Bridge`, `Russian Twist` were all `['Bodyweight or Dumbbells']`-shaped).

---

## 1. Locked decisions (founder)

| # | decision |
|---|---|
| 1 | The **bodyweight tier gets a HARD floor**. `details_screen.dart:105` already promises *"No equipment needed — anywhere, anytime."* Scope: bodyweight only; the other three tiers keep soft tier curation. |
| 2 | Batch scope: **OI-89 only** (the OI-98 notification half is out). |
| 3 | **Expand the vocabulary.** Both alternatives (split the chip / replace tiers with a checklist) require this first. |
| 4 | Profile adjustment works in **both directions** — subtract *and* an "I also have…" add path. Forcing case: a bodyweight user who owns a pull-up bar. |
| 5 | The ladder cut is **"nothing you have to buy."** |
| 6 | **Pull-up bar is OUT of the bodyweight baseline**, one tap away via "I also have…". |
| 7 | Baseline tokens go into **all four** `tierItems` — a gym has walls and benches, and `effective` must be true for the AI coach. But the **Customize chips for them appear at bodyweight only**; a gym user is never asked "do you have a chair". Grants and questions are two different lists. |
| 8 | **`wall` is un-excludable**, protected exactly as `bodyweight` is. `doorway` / `elevated surface` / `foot anchor` / `towel` stay excludable at bodyweight. (`floor` needs no token — `bodyweight` already covers it and is already protected.) |
| 9 | **Yoga mat and foam roller are not equipment.** General rule: *if the exercise is performable without the item, the item is not in `equipment_needed`.* |
| 10 | **`vertical_pull` gets filled, not substituted** — three new bodyweight exercises. The door-frame towel pull-up is excluded by name on safety grounds (loads a residential door and its hinges with full bodyweight). |

---

## 2. The vocabulary

**12 new canonical tokens, derived from the 87 recovered originals — not invented.**

### Baseline (in all four `tierItems`; Customize chips at bodyweight only)

| token | recovered originals it replaces | excludable at bodyweight? |
|---|---|---|
| `wall` | `Wall`, `Wall or Freestanding` | **NO** — decision 8 |
| `doorway` | `Doorway` | yes |
| `elevated surface` | `Elevated Surface`, `Elevated Bench`, `Chair`, `Bench or Box`, `Box or Bench`, `Flat Bench or Pole` | yes |
| `foot anchor` | `Partner or Nordic Attachment` | yes |
| `towel` | (new; also absorbs `Broomstick or Band` for Shoulder Dislocate) | yes |

### Accessory (never in the bodyweight baseline; addable from any tier)

`ab wheel` · `jump rope` · `suspension trainer` · `parallel bars` · `plyo box` · `medicine ball` ·
`battle ropes`

Recovered originals: `Ab Wheel`, `Jump Rope`, `TRX Suspension Trainer` / `Barbell on Rack or TRX`,
`Parallel Bars` / `Parallel Bars or Floor`, `Box` / `Box (30-45cm)` / `Box (30-60cm)`,
`Medicine Ball` / `Bodyweight or Medicine Ball`, `Battle Ropes`.

Note `parallel bars`, not "parallettes" — the library's own authored word, and it correctly covers
a dip station.

### Recovered tokens deliberately NOT promoted

| original | resolution | why |
|---|---|---|
| `Yoga Mat` (10 rows) | drop from `equipment_needed` | decision 9 — every one is a stretch or floor drill performable on a carpet |
| `Foam Roller` (4 rows) | drop | decision 9 |
| `Rope` (3 rows) | → `cables` | always paired with `Cable Machine`; it is a cable *attachment*, not equipment |
| `Pole` (Dragon Flag) | → `elevated surface` | the row was `Flat Bench or Pole`; the bench alternative is already covered |
| `Sissy Squat Bench` | → `bodyweight` | the row was `Bodyweight or Sissy Squat Bench` — bodyweight is an authored alternative |
| `Broomstick` | → `towel` | the row was `Broomstick or Band`; a towel is the standard substitute and keeps the drill at baseline |

### Three constants move in lockstep — this is a P0 if missed

Adding a token to `canonicalTokens` alone is **not** enough. Three other structures key on it:

1. **`_precedence` (`:48-61`)** — `normalizeToken:170` does `_precedence.indexOf(c)` and the
   `rank >= 0` guard **skips** any token not in the list. An unlisted token is silently *dropped*
   from an OR-compound, yielding `[]` = "no requirement" — the most permissive possible result.
   Full new order, most→least accessible (baseline first so an OR-compound resolves to the
   *easier* alternative, preserving the documented conservative rule at `:44-47`):

   ```
    1 bodyweight        7 resistance band  13 kettlebell          19 ez-bar
    2 wall              8 jump rope        14 suspension trainer  20 battle ropes
    3 towel             9 ab wheel         15 parallel bars       21 cables
    4 foot anchor      10 medicine ball    16 pull-up bar         22 machines
    5 doorway          11 plyo box         17 bench               23 smith machine
    6 elevated surface 12 dumbbells        18 barbell             24 cardio machine
   ```

   Exactly 24 — the 12 existing plus the 12 new. A set-equality gate
   (`_precedence` ⊇ `canonicalTokens`) is listed in §10; without it this list
   silently rots the next time a token is added.

2. **`_chipLabels` (`:274-286`)** — `chipLabel` is `_chipLabels[token] ?? token` (`:289`), and
   `equipment_chip_vocab_contract_test.dart:51-57` asserts a non-fallback label for **every**
   canonical token except `bodyweight`. All 12 need entries: `Wall`, `Doorway`,
   `Chair / Step / Bench`, `Foot Anchor`, `Towel`, `Ab Wheel`, `Jump Rope`, `Suspension Trainer
   (TRX)`, `Parallel Bars`, `Plyo Box`, `Medicine Ball`, `Battle Ropes`.

3. **`_aliases` (`:67-147`)** — `_mapPart:151-154` checks `canonicalTokens` **first**, so 7 alias
   rows become unreachable dead code the moment their key is promoted: `medicine ball` (`:126`),
   `wall` (`:127`), `doorway` (`:128`), `elevated surface` (`:131`), `yoga mat` (`:133`),
   `ab wheel` (`:135`), `jump rope` (`:136`). Delete those 7. **Re-point** these to the new
   tokens rather than `bodyweight`: `trx` / `trx suspension trainer` (`:138-139`) →
   `suspension trainer`; `parallel bars` (`:137`) → itself; `box` / `box (30-45cm)` /
   `box (30-60cm)` (`:123-125`) → `plyo box`; `partner` (`:145`) / `nordic attachment` (`:146`) →
   `foot anchor`; `chair` (`:129`) → `elevated surface`. Keep `floor` (`:141`), `lying` (`:130`),
   `freestanding` (`:142`) → `bodyweight`.

   ⚠ Live seam, not just tests: `normalizedEquipmentRow(:233)` normalizes community-downloaded
   rows at the write, and `createCustomExercise` normalizes user/AI free text.

---

## 3. The data model

**One new profile field:** `equipment_owned: List<String>`.

```dart
// EquipmentVocab.effectiveItems(tier, owned, exclusions) -> Set<String>
effective = tierItems[tier] ∪ owned − exclusions
```

Strip the `none` sentinel at this boundary — every `tierItems` value begins with it (`:250-260`)
and `:246-248` states it is explicitly not a canonical token. It is inert inside `canPerform` but
leaks into chip labels and the AI snapshot if not stripped.

**Two lists, not one (decision 7):**

```dart
tierItems[tier]              // what the tier GRANTS  -> feeds effective / canPerform
tierAskableItems(tier)       // what we ASK about     -> feeds the Customize chips
```

`tierAskableItems('bodyweight')` = `{doorway, elevated surface, foot anchor, towel}` — `wall` is
excluded by decision 8. For the three gym tiers it returns exactly today's list, so a gym user's
Customize UI is unchanged. This replaces the current `tierExcludableItems` in the UI; keep the old
function name only if nothing else reads it.

**Disjointness is a READ-side derivation, not a write-side prune.**

The previous design claimed the both-lists state was unreachable. It is not: `pruneToTier`
(`equipment_vocab.dart:307` — note the real name; `sanitizeExclusions` does not exist) has exactly
**one** call site, `edit_profile_screen.dart:418`, inside a dropdown callback. `equipment_access`
is also written by `onboarding_provider.dart:466`, `plan_screen.dart:512`, `details_screen.dart:144`,
`onboarding_chat_screen.dart:931`, and — worst — cloud restore at
`auth_session_bootstrapper.dart:571` and `sync_service.dart:1135`. A restore writes tier and owned
independently and lands exactly the state the design says cannot exist.

So `effectiveItems` reconciles at read time: `owned` members already in `tierItems[tier]` are
absorbed, and exclusions outside it are ignored. A writer nobody enumerated cannot corrupt it.
Keep `pruneToTier` for UI tidiness; do not rely on it for correctness.

---

## 4. The capability predicate

```dart
EquipmentCapability.canPerform(Object? equipmentNeeded, Set<String> effective) -> bool
```

Tier-agnostic. Named `EquipmentCapability`, **not** "bodyweight floor" — that term already means
the un-excludable `none`/`bodyweight` tokens in six files (`equipment_vocab.dart:210`, `:264`,
`plan_generator.dart:131`, `training_history_analyzer.dart:168`, `sot_registry.yaml:8724`,
`plan_engine/CLAUDE.md:279`) and in OI-89's own entry.

**Fails CLOSED on unreadable input.** `normalize` *drops* unmappable tokens (`:187-196`), so an
all-unmappable list yields `[]`, and `[] ⊆ effective` is vacuously true — the permissive answer.
Correct for soft curation, wrong for a hard floor. Today 0 of 259 seed rows are affected; the live
population is community-synced rows, which is exactly what seam 5 exists for.

```dart
final needed = EquipmentVocab.fromProfile(equipmentNeeded);
if (needed.isEmpty) return false;            // fail CLOSED
return needed.every(effective.contains);
```

---

## 5. Enforcement — seven seams

| # | seam | today |
|---|---|---|
| 1 | `_cascadeFill` attempt 4 (~`:1129`) | drops the tier constraint by design |
| 2 | `_cascadeFill` attempt 5 (~`:1152`) | `universalPoolV4` bypasses `queryV4` |
| 3 | `buildPinnedDays.resolve()` (`:706-740`) | exclusion + injury only, **no equipment check**; reached via `plan_generator.dart:176`, the other branch of the `:175-206` ternary |
| 4 | `_applyHistoryAdjustments` (`:841` L6 re-query, `:880` L2 custom-append) | phase ≥ 2; appends user customs with an exclusion check only |
| 5 | attempts 1–3 via `queryV4` (`exercise_repository.dart:302`) | the tier filter's `return true` fires inside the **fused** predicate, so a row with empty `equipment_tier` also skips `exercise_type`, `suitable_for`, `foundational`, `excludeNames` **and injury** |
| 6 | `ExerciseSwapSheet._loadExercises` (`exercise_swap_sheet.dart:66-73`) | `repo.getAll()`, **no filter of any kind**. The widget declares `final List<String>? equipment;` at `:13`, accepts it at `:25`, and reads it **nowhere**. A bodyweight user tapping swap is offered all 259 rows including Barbell Back Squat. **Live in the shipped APK.** |
| 7 | `template_builder_screen.dart:528` | `repo.search(query).take(30)`, same shape |

**Coverage is enforced by the compiler.** The capability set is a **required, non-defaulted**
parameter on `queryV4`, `pickV4`, `_fillSlots`, `_cascadeFill`, `buildPinnedDays` and
`_applyHistoryAdjustments`. Precedent, verbatim at `exercise_repository.dart:243-247`:

> *REQUIRED (not optional) so a missed cascade call site fails to COMPILE rather than silently skip
> the drop.*

⚠ `pickV4`'s existing `exclusions` is `= const {}` at `:532` and `buildPinnedDays`' at `:695` —
already the defaulted shape this design rejects. Make the new param required on both. Cost, counted:
`queryV4` 5 call sites (0 in tests), `buildPinnedDays` 1, `pickV4` 2 in `lib/` **plus 3 in
`test/contracts/injury_safe_omission_production_test.dart:98,114,128`**.

Seams 6 and 7 are widgets that call none of those six functions, so the compile guarantee does not
reach them. They take the filter explicitly and each gets its own behavioural test.

**Attempt 5 keeps its tail.** The superseded plan inserted an unguarded
`if (matches.isEmpty) continue;`, deleting `_buildUniversalFallback(name,'A')` (`:1189`) for every
user on every tier. Only the capability check moves above the `matches.isNotEmpty` branch.

---

## 6. The floor guarantee — the P0 that killed the last design

`floorSanitizedExclusions` (`:215-217`) strips only `none`/`bodyweight`. Once `elevated surface`
and `doorway` are baseline tokens they become excludable, and
`exercise_selector.dart:1170-1173`'s written proof — *"Floor-sanitize guarantees ≥1 pure-bodyweight
move per movement_pattern, so a skip NEVER empties the slot"* — becomes false. Measured: four
patterns have exactly **one** bodyweight option, and §7's retag moves two of them onto excludable
tokens. A user ticking "no chair" + "no doorway" takes `elbow_extension` and `elbow_flexion` to
zero; `_cascadeFill` returns null (`:1196`), `_fillSlots` drops it silently, and
`scorecard_gate_test.dart:70-73` treats `missing > 0` as a HARD failure.

**Resolution — the guarantee moves from per-token to per-pattern.** `wall` is un-excludable
(decision 8), and a new invariant replaces the old proof:

> For every `movement_pattern`, at least one library row must be performable using only
> `{bodyweight, wall}` — the un-excludable core. §8's new exercises are chosen to satisfy this.

Pinned by a new test that enumerates all 11 patterns against the un-excludable core, and the
`:1167-1178` comment is rewritten to state the new proof. The old comment must not survive — it
would document a guarantee that no longer holds.

---

## 7. Restoring the library

Restore the 49 rows from `632a10b8^` and map through §2's table. **Not** hand-authored from names:
the recovered values are authored data with better provenance, and they already corrected one of my
guesses — I had classified `Inverted Row` as "a sturdy table"; the author wrote
`['Barbell on Rack or TRX']`, neither of which is free, which moves it out of the baseline.

Plus the four over-tag corrections, re-derived as complete by two independent reviewers:
`Standing Calf Raise` (`barbell`), `Chin Up` (`pull-up bar`), `Decline Push Up` (`bench`),
`Reverse Crunch` (`bench`) — all four carry `bodyweight` in `equipment_tier` and must lose it.
⚠ Do **not** give the two bench rows `home_dumbbells`: `tierItems['home_dumbbells']`
(`:251`) has no `bench`, which would reintroduce the same over-tag class.

`equipment_tier` is re-derived in the same commit from the restored `equipment_needed`, per the SoT
rule at `sot_registry.yaml:8531-8534`. Note that rule's "90 rows" is the **ADD-only deepening**
count, not an over-tag count.

---

## 8. New exercises

**`vertical_pull` — 0 → 3.** Every one of the library's 10 `vertical_pull` rows needs equipment
(5 × pull-up bar, 2 × cables, machines, dumbbells, dumbbells+bench), so nothing can be promoted.

| exercise | `equipment_needed` | note |
|---|---|---|
| Prone Lat Pull | `['bodyweight']` | face down, arms overhead, drive elbows to the ribs. The standard no-equipment lat movement. Satisfies §6's un-excludable core. |
| Sliding Lat Pull | `['towel']` | kneeling, hands on towels on a smooth floor, pull back to the hips. The hardest of the three. |
| Doorway Isometric Lat Pull | `['doorway']` | isometric; teaches a lat contraction a beginner cannot yet feel. |

**Excluded by name:** the door-frame towel pull-up — a genuine calisthenics staple needing only
baseline items, rejected because it loads a residential door and its hinges with full bodyweight.

**Thin-pattern backfill.** After §7's retag, recompute depth per pattern and add exercises until
every pattern has ≥3 options at baseline **and** ≥1 using only `{bodyweight, wall}`. §4.2 makes
this in-batch. Every new row must carry **all 38 keys** — `exercise_library_schema_contract_test.dart:35-47`
requires exactly that set, missing *and* extra both failing — and the row-count assertion at
`:68-72` (`259`) must be updated to the new total.

---

## 9. Persistence — where the last design lost the plot

| obligation | detail |
|---|---|
| **Hive re-seed** | `SeedService._exerciseLibraryVersion` **9 → 10** (`seed_service.dart:89`). The re-seed is gated on `storedExVersion < _exerciseLibraryVersion` (`:121-122`). Without the bump the retag is **inert for every existing install** and live only for fresh ones — the worst possible A/B. Precedent in the same comment block: `:82` (v8) and `:85-88` (v9). |
| **Cloud column** | migration **122** adding `user_profile.equipment_owned text[]`, paired with `backups/applied_migrations.json` in the same commit (§4.5), 4-tag header per `supabase/migrations/CLAUDE.md:16-24`. Verified: `user_profile` has 38 columns, `equipment_access` and `equipment_exclusions` present, `equipment_owned` absent. |
| **Deploy ordering** | The migration must be applied to prod **before** the client that writes the field ships. `user_repository.dart:721-724` upserts a **spread** of the whole profile map and `_sanitize` (`:818-836`) does not whitelist columns, so a client carrying `equipment_owned` against a DB without it gets a PostgREST 400 and the **entire row is rejected** — the all-null `user_profile` failure documented at `:704-713`. |
| **Cloud library re-seed** | `exercise_library.equipment_needed` **is** a cloud column (verified in `live_schema_columns.json`; `equipment_tier` is not, matching `074_seed_exercise_library.sql:15-19`). `beat-my-coach/index.ts:193-198` filters `equipment_needed.cs.{bodyweight}`. Re-apply 074 in this batch or cloud and client permanently disagree on what "bodyweight" means. Other readers: `promote-community-item/index.ts:191`, `_shared/tools/exercise/getFormCues.ts:65,92`. |
| **Gate 19** | `scripts/check_hive_map_field_drift.dart` `_alwaysOk` (`:278`) needs `equipment_owned`, exactly as `equipment_exclusions` was added at `:324-329` (precedent recorded at `sot_registry.yaml:8766`). |
| **Schema snapshot** | Regenerate `backups/live_schema_columns.json`. ⚠ `check_schema_column_refs.dart` would **not** catch a stale snapshot here — it skips spreads and bare `select()`, which is exactly what `sync_profile.dart:254`, `user_repository.dart:673,722` and `_restoreUserProfile:512` use. Regenerating is mandatory and unenforced. |
| **Restore** | **Nothing owed.** `_restoreUserProfile` (`sync_profile.dart:505-585`) uses a bare `.select()` at `:512` and merges every non-null cloud key at `:558-570` — column-agnostic. `equipment_owned` restores with zero restore-side code. An earlier draft's L11 worry was unfounded. The **write** side does need the `sync_profile.dart:200-201` conditional-entry pattern. |

---

## 10. Tests that change deliberately

Not incidental breakage — these pin the behaviour being reversed, and each needs a considered rewrite.

| test | assertion | why it changes |
|---|---|---|
| `equipment_chip_vocab_contract_test.dart:25` | `tierItems['bodyweight'] == ['none','bodyweight']` | 5 baseline tokens join |
| `:42` | `tierExcludableItems('bodyweight')` isEmpty | becomes 4 (decision 7/8); comment *"the UI hides the section"* is now false |
| `:46`, `:48` | full_gym == 11, basic_gym == 7 | baseline tokens enter all four tiers |
| `:51-57` | chipLabel non-fallback for every canonical token | 12 new `_chipLabels` entries |
| `equipment_vocab_library_contract_test.dart:89` | `normalizeToken('Medicine Ball') == 'bodyweight'` | now `'medicine ball'` |
| `:77,78,110,111-112` | OR-compounds collapsing to `bodyweight` | `_precedence` + alias re-points |
| `exercise_library_schema_contract_test.dart:68-72` | 259 rows | new total |
| `exercise_selector.dart:1167-1178` | the floor proof, in a comment | replaced by §6's per-pattern invariant |

**New tests:** per-pattern un-excludable-core invariant (§6); `canPerform` fail-closed
(mutation-proven); a bodyweight-persona behavioural test asserting zero off-capability picks with
an oracle reading `equipment_needed` (**never** `equipment_tier` — the previous oracle read the
same field as its predicate and was tautological with the harm); swap-sheet and template-builder
filters; `_precedence` ⊇ `canonicalTokens` set-equality.

⚠ **The v4 diagnostic cannot verify any of this.** `test/plan_generator/v4_diagnostic/cascade_tracer.dart`
is a **mirror** — it never calls `ExerciseSelector.pickV4` and holds zero references to
`HiveService` or `PlanEngineFlags`. Mirroring the new logic into it would reproduce the
tautological-oracle defect. Verification runs through the behavioural tests above.

---

## 11. Rollout

Ship-dark behind a kill-switch, default OFF (§4.6) — gating **the hard enforcement only**. The
vocabulary, the library restoration and the seed bump are **not** behind the flag; they change
generated plans for every user the moment they land. The superseded plan claimed "byte-identical
when OFF" and that was false. This design does not claim it.

The flip-on commit is separate and takes its own full §4.12 ×2 review. Logged in
`docs/ship_dark_pending_review.yaml` with `flip_reviewed: false` and `flip_commit: null`.

`test/plan_generator/baseline/baseline_scorecard.json` freezes
`equipment_violation_plan_count: 201`. State the before/after and require **non-increase** — a rise
means the batch shipped the symptom and re-froze it as the new floor.

**Closure:** `docs/audit/oi89-equipment-capability.closure.yaml`, per-entry `terminal_state:` ∈
{`closed_in_commit`, `upstream_blocked`, `blocked_on_user`, `verified_clean`}, no `deferred:` key,
`closed_count` recomputed (`scripts/validate_audit_closure.dart:22-31`, `:57-61`).
