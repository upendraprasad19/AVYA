# Hand-pick any exercise: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** a user adding or swapping an exercise by hand can pick ANY exercise, whatever equipment their profile
lists. Plans the app builds still follow equipment. Duplicate exercise names stay refused.

**Spec (founder, 2026-11-28, verbatim):** "A user should be able to add any exercise as he feels fit. As he is
adding it so he must be able to do it. Else he can add some thing else right? He should not be able to add
duplicate exercise name though."

**Architecture:** one new pure helper arranges every hand-pick list (all rows, the user's equipment first, one row
per name). The four lists use it, the swap service stops refusing on equipment, and the injury planner,
the one caller of that service where the APP picks the exercise, gets the equipment filter itself.

**Tech:** Flutter, Hive. No migration, no Edge Function change, no cloud write.

**Reviews:** three independent rounds on this document (2026-11-28). Rounds 1 and 2 did not converge (2 P1, then
1 P1); round 3 on the folded text found no P0 or P1 and two P2s, folded here with its smaller points.

**Tier:** `platform` (`blast_radius_from_diff.dart`: the two comment fixes under `plan_engine/` raise it from
`account`). Process: two plan reviews, B-pass before merge; not catastrophic, so no Hermes. Execution mode: **inline** (the tasks share files). No feature flag: the diff is not payment,
sync, auth, AI prompt or plan generator (§4.6). `disable_equipment_capability_floor` keeps working: it turns the
ordering and the planner filter off.

## History (read before touching code)

- `b6f4d1` (2026-08-28, OI-89) added the block. Symptom: a bodyweight user was offered all rows, Barbell Back
  Squat included, in swap, add and template; the coach could swap onto anything. **This plan reverses its
  hand-pick half on the founder's call.** The harm it named is answered by ordering (their equipment first), not
  hiding. Its coach half is split: see D1 and Task 3.
- `e7b2d4` (own customs with no equipment were hidden), `a6f3d9` (coach list hid every built-in), `f2a6c8`
  (duplicate-name refusal, with one exception for a row no list could show), `e7c4a1` (a community copy of the
  user's own custom must never stand in for it).
- OI-403 note (2026-11-28): the injury planner never checks equipment. Task 3 closes that note. OI-403 itself
  (injury tags) stays open and is not touched.
- Not a recurrence of a defect: a founder rule change plus one older planner gap.

## Writers and readers today

| Seam | Where | Today |
|---|---|---|
| Mid-workout "+ Add Exercise" | `exercise_picker_sheet.dart:35-67` | hides rows the equipment cannot do |
| Swap sheet | `exercise_swap_sheet.dart:88-113` (capability passed at `swap_sheets.dart:86`) | hides |
| Template builder search | `template_builder_screen.dart:561-611` | hides; default and search both capped at 30 |
| Coach "Swap exercise" list | `swap_exercise_coach_sheet.dart:137-181` | hides; drops the community copy of an own custom (`:172-180`) |
| Swap write | `swap_service.dart:727-747` | throws `equipment_unavailable` |
| Injury planner (app picks) | `injury_swap_planner.dart:225-252` | **no check**; relies on the swap write to refuse |
| Create-custom name guard | `exercise_repository.dart:501-532` | exception: a community row no list can show does not hold its name |
| Refusal copy | `wardroom_copy.dart:209` | "Can't find it? Check your equipment in Edit Profile." |

Callers of the swap write: `workout_schedule_service.dart:254` from `tool_dispatcher.dart:357` (coach swap,
behind a confirm card) and `:779` (injury swaps from the planner's cache).

Unchanged app-made paths (they keep `canPerform` / `canOfferInPicker`): `exercise_repository.dart:358` (queryV4),
`core_list_selector.dart:250`, `cardio_finisher.dart:222`, `warmup_cooldown.dart:192`,
`exercise_selector.dart:432` (repeat pins).

## Decisions

- **D1. A coach swap the user APPLIES is the user's choice.** The swap write loses its refusal, so `tool_dispatcher`
  `_executeSwapExercise` can write an exercise outside the listed equipment once the user taps APPLY on the card
  that names it. The coach still receives the user's equipment (`equipment_effective` in the snapshot); its tool
  and prompt are unchanged. Nothing is written without that tap.
- **D2. Order, never hide.** Rows the equipment covers come first, in today's order; the rest follow in list order.
  The user's own matching customs never sink below non-matching rows. One new header only, in the swap sheet
  (Task 2). With the rule off or no profile, order is today's.
- **D3. One row per name in every list** ("no duplicate exercise name"; review 1 P1-2). Showing hidden rows would
  show one name twice in four ways: a community copy of an own custom (same id); an own custom created beside an
  equipment-less community row through the exception D5 removes, or beside a built-in before `f2a6c8`; a community
  row sharing a built-in name (`exercise_repository.dart:70-71`); two community rows from different authors
  (`sync_community.dart:521-537` keys by id only). Winner by `exerciseDuplicateKey(name)` or shared id: **the
  user's own custom**, then a built-in, then a community row (the first that matches the equipment, else the
  first). Own wins because it is the
  user's row, its logs share that name, and `e7c4a1` already prefers it. The cost: a user with an old own copy of a
  built-in name picks their copy, so its stored details (logging type, category, muscles) are used. Animations and
  cues are still looked up by name in the library (`exercise_media_resolver.dart:19-20`, `plate_resolver.dart:61`),
  not taken from the picked row; which same-named library row that lookup finds is Hive key order, as today. Two of the user's own
  customs with one name (older data) are both kept: they are the user's rows, and a day still takes the name once.
- **D4. Template builder:** the empty-search view stays capped at 30 (for anyone with 30 or more matching rows it
  is today's first 30, except where D3 drops one of them). **Search results lose the cap**, or a typed name could still be unreachable behind 30
  matching rows. The list is lazy (`ListView.builder`).
- **D5. The name exception goes.** Every list now shows every row, so every list name is taken (`f2a6c8`'s
  2026-11-26 exception existed only because no list could show the row).
- **D7. The injury preview says what it could not place** (review 1 P1-1). Today `plan()` drops an affected
  exercise with no substitute, and the preview then says nothing hits the body part
  (`injury_modify_diff.dart:91-101`). The new filter makes that likely (a bodyweight shoulder plan has very few
  `push` substitutes), so the preview must name those exercises.
- **D8. Accepted:** if the user narrows their equipment between the injury preview and Confirm, the cached swaps
  run unchecked; reopening the preview recomputes them.
- **D6. Not changed:** when the app repeats a phase, `buildPinnedDays` still re-checks equipment, so a hand-added
  exercise outside the listed equipment can drop out of that app-made repeat. The founder was told on 2026-11-28.

## Global constraints

- Duplicate names stay refused: `exercise_name_unique_in_day` (all `takenNames` greying, `addExercise` /
  `swapExercise` / `createTemplate` / `swapExerciseInDay` guards) and `createCustomExercise`'s `duplicate_name`.
- No plan-generator CODE changes (`lib/shared/repositories/plan_engine/**`, `plan_generator.dart`): only the
  stale comments named in Task 5; the generator golden must be unchanged.
- A commit that moves lines cited by `docs/sot_registry.yaml` updates those ranges in the SAME commit
  (`check_sot_registry_parity.dart` runs at pre-commit); that covers ranges and readers a task moves or DELETES
  (Task 2 the four lists, Task 3 the swap-service and planner entries, Task 4 `isNameTaken`). Task 5 rewrites the
  descriptions only. Task commits use `feat(...)` subjects; the diagnose-doc lands in Task 3's commit, which
  carries `closes-diagnose: <id>`, and Task 4 adds its mutation count to it.
- Copy, exact: name refusal `“{exercise}” is already in the exercise list. Search its name to add it.`; coach list
  subtitle `Exercises that match your equipment are listed first.`; coach empty list `No other exercises found.`;
  swap-sheet header `MORE FROM THE LIBRARY`; injury card after Confirm with no swap made `No workouts changed`;
  injury preview heading
  `No substitute found for these. They stay in your plan:` with one line `{date} · {exercise}` each.
- Every new or rewritten test is mutated once and must redden (§4.4 rule 21); counts go in the diagnose-doc.
- `grep -rn "<old literal>" test/ scripts/ docs/` before moving or rewording anything (§4.9).

## Review Focus

1. A community copy of the user's own custom, with different equipment or logging type: only the own row is
   listed, and picking it writes the own row (Task 1, Task 2).
2. A bodyweight user's injury plan: the planner must not offer a barbell movement now that nothing downstream
   refuses it (Task 3).
3. A name already in today's workout or template, now visible among non-matching rows: still greyed and dead
   (Task 2).
4. Typing a full exercise name in the template builder when 30 or more matching rows contain it (Task 2).
5. A community row with no readable equipment: listed last, pickable, and its name refused on create (Task 4).
6. A bodyweight injury plan with no substitute: the preview must name the exercise, never "nothing to change"
   (Task 3).
7. One name from two rows (own, built-in, community): listed once, and still found by either row's older names
   (Task 1).

---

### Task 1: `PickerRows`, the one list arrangement

**Files:** create `lib/shared/repositories/picker_rows.dart`; create `test/contracts/picker_rows_behavioral_test.dart`.

**Produces:**

```dart
class PickerRows {
  final List<Map<String, dynamic>> matchingLibrary, matchingCustom, otherLibrary, otherCustom;
  List<Map<String, dynamic>> get custom;  // [...matchingCustom, ...otherCustom]
  List<Map<String, dynamic>> get merged;  // matchingLibrary, matchingCustom, otherLibrary, otherCustom
  static PickerRows arrange({
    required List<Map<String, dynamic>> library, // the WHOLE of ExerciseRepository.getAll(), never search results
    required List<Map<String, dynamic>> custom,  // ALL of getCustomExercises(), never search-filtered
    required Set<String>? capability,            // resolveCapabilityFromProfile()
  });
}
```

Rules:
1. One row per name (D3), applied in this order.
   a. Each `custom` row claims its `exerciseDuplicateKey(name)` and its `id`. A `library` row with a claimed name
      loses to that custom; a COMMUNITY row (`!isLibraryRow`, `core/services/auto_appended_custom.dart`) with a
      claimed id loses too. A built-in is never dropped by id: the swap write lets a built-in win an id clash
      (`swap_service.dart:683-688`).
   b. Among the rows left, a community row loses to a built-in of the same name.
   c. Of several community rows with one name, the first MATCHING one stays; if none matches, the first.
   Blank names and blank ids claim nothing. Two built-ins and two customs never drop each other.
   Who collects a loser (so the result does not depend on implementation order): in 1a the custom that claimed its
   NAME, else the one that claimed its id; whenever several rows could claim, the first in list order.
2. The survivor stays findable as every row it replaced (two customs with one name: the first collects). When
   losers carry a different name, `name_aliases` or another `category`, the survivor is returned as a COPY with
   `name_aliases` extended by those names and aliases, and `picker_categories` listing the losers' categories.
   `category` itself is never changed (the pickers write it into the session). Input maps are not mutated.
3. matching = `capability == null`, or `canPerform` (library) / `canOfferInPicker(isCustom: true)` (custom).
4. Order inside each bucket is input order. Nothing else is dropped.

Two more statics, used by all four lists:
`static bool inCategory(Map row, String category)` (case-insensitive match on `category` or any
`picker_categories` entry) and `static bool isTaken(String name, Set<String> takenNames)` (compares
`exerciseDuplicateKey` of both sides, so a day holding `Child's Pose` greys a surviving curly-apostrophe custom;
the writers keep `exerciseNameKey`).

- [ ] Write the failing tests: bodyweight capability returns every row (count and id set) with matching rows first
  and input order kept in each bucket; `null` capability puts every row in `matchingLibrary` / `matchingCustom`;
  one test per D3 pair (own and community with the SAME id but DIFFERENT names, so only the id half can drop it;
  own and an equipment-less community row with the same name and different ids; own beside a built-in; community
  beside a built-in; two community rows: first matching wins, and with none matching the first); the three-way
  community + built-in + own case leaves only the own row, which carries both losers' names and categories;
  mirrors: a built-in sharing an id with a custom of another name stays; blank names never drop each other;
  `inCategory` and `isTaken` cases including the curly apostrophe; different names all stay, two
  built-ins with one name stay, two customs with one name stay, rows with empty ids never drop each other by id;
  the survivor carries the loser's alias and the input maps are not mutated; an own custom with `[]` equipment is
  in `matchingCustom` while one naming a barbell is in `otherCustom`.
- [ ] Run `flutter test test/contracts/picker_rows_behavioral_test.dart`: FAIL (no such file/class).
- [ ] Implement. Re-run: PASS. Mutate separately: the id half of 1a, the name half of 1a, 1b, 1c's
  matching preference, rule 2's aliases, rule 2's categories, rule 3 (return only matching rows). Each reddens.
- [ ] Commit through `scripts/safe_commit.sh`.

### Task 2: the four lists show everything

**Files:** modify
- `exercise_picker_sheet.dart`: `_loadAllExercises` uses `.merged`; `_applyFilter`'s chip test becomes
  `PickerRows.inCategory`; greying uses `PickerRows.isTaken`.
- `exercise_swap_sheet.dart`: `_loadExercises` arranges the WHOLE of `getAll()` FIRST, then removes the current
  exercise from the two library buckets (as today it is not removed from the custom list), comparing with
  `exerciseDuplicateKey`, so a surviving custom keeps the removed row's names. Keep the getter names
  `_filteredCustom` and `filtered` (source greps read them). Render order:
  `matchingLibrary`, the `YOUR CUSTOM EXERCISES` section (`custom`), then `otherLibrary` under
  `MORE FROM THE LIBRARY` (header only when it has rows: a `full_gym` user with only built-ins sees today's sheet;
  `basic_gym` and `home_dumbbells` users will see the header, as intended). The category chip
  filters the two LIBRARY buckets only, through `PickerRows.inCategory`; the custom section ignores the chip, as
  today (`:139-146`), or every custom filed under another category (or under one with no chip) would vanish from
  the default sheet. Search filters all three; the custom search also matches `name_aliases`. Keep `filtered`
  (both library buckets, split at render) and `filteredCustom`, and keep the literal
  `filtered.isEmpty && filteredCustom.isEmpty` and both `id: ex['id'] as String?` sites: source greps in
  `swap_sheet_custom_exercises_test.dart:94` and `exlog_exercise_id_swap_threading_test.dart` read them.
  `_isTaken` uses `PickerRows.isTaken`. Rewrite the `capability` doc comment: it ORDERS.
- `template_builder_screen.dart` `_refresh`: always `arrange` the whole of `getAll()` with ALL customs, THEN
  filter every bucket by name OR alias with `exerciseDuplicateKey` (the match `repo.search` does), so winners
  never depend on the query. `repo.search(` leaves this file: lower its exercise-seam count by one and say so in
  its `reason`. Greying uses `PickerRows.isTaken`. Result order: `matchingCustom`,
  `matchingLibrary`, `otherCustom`, `otherLibrary`. Empty query: 30 library rows in total, `matchingLibrary`
  first. Search: no cap.
- `swap_exercise_coach_sheet.dart`: `_substitutesFor` arranges, then walks the four buckets in `merged` order
  separately so each option keeps `isCustom` (the `·CUSTOM` label); its own equipment skip and copy-drop go.
  `searchKeys` keeps name plus `name_aliases`; the taken label uses `PickerRows.isTaken`. The two copy strings
  and the file header comment change.
- `active_workout/screen.dart` (drop the `equipment_capability` import if unused), `swap_sheets.dart` comment.

**Interfaces:** consumes `PickerRows.arrange`.

- [ ] Tests first. Each list gets its OWN behavioural proof; seed keys so a non-matching row sorts FIRST in Hive
  (otherwise an order assertion passes with no ordering at all); seed the profile inside `runAsync`.
  - `coach_swap_picker_equipment_behavioral_test.dart`: rewrite. Full gym and bodyweight users are offered all
    seven seeded names; re-key the built-ins so the barbell row sorts first, and assert bodyweight sees
    `Floor Press Test` and `Own Move Test` above `Barbell Row Test` and `Own Barbell Test`; a search for
    `unlisted gear` now finds the row; a name already in today's workout stays labelled and not tappable; the
    own/community test (the `·CUSTOM` row) and the short-phone test stay.
  - new `test/widgets/swap_sheet_any_equipment_test.dart` (public `ExerciseSwapSheet`): bodyweight capability;
    order is bodyweight library row, own matching custom, `MORE FROM THE LIBRARY`, barbell row; SELECT on the
    barbell row calls `onSelect` with its id; a `takenNames` barbell row has no SELECT; gym capability shows no
    new header for `full_gym`; an older-name search finds an own custom that replaced a library row; an own custom
    named like a `core` built-in but filed `Flexibility` appears EXACTLY once (`findsOneWidget`: this is D3's
    proof, not a chip proof); an `indian_traditional` custom is shown when the sheet opens on another chip (this one
    reddens the "chip on the custom section" mutation). The taken-row case also asserts the row IS listed and that
    another row keeps SELECT, or it passes on main.
  - `test/features/train/template_builder_unique_names_test.dart` harness: bodyweight user; a barbell row keyed to
    sort FIRST in Hive and an own custom with a community twin (same name). Assert a matching row is listed above
    the barbell row and the twin name appears exactly once. Then 31 bodyweight rows named `Press N` plus
    `Barbell Press`: searching `press`, scroll to `Barbell Press` (lazy list, `scrollUntilVisible`) and tap: it is
    added (`scrollUntilVisible` with an explicit `scrollable:`, the search field is a second Scrollable). Empty
    query: the list delegate's child count is 30 library rows plus customs (passes on main too).
  - `test/features/train/exercise_name_unique_screen_test.dart` harness, same two seeds: in the mid-workout picker
    a matching row is above the first-keyed barbell row, the twin name appears exactly once, the own custom filed
    under another category than its NON-matching built-in twin is found under the twin's chip by search, asserted
    by something only the custom shows (its muscles or category badge), and adding the barbell exercise puts it in
    the session.
  - Both of those harnesses share one Hive directory per file and `seedLibrary` keeps the profile: delete the
    profile in teardown, or the bodyweight profile leaks into later tests.
  - `custom_picker_capability_wiring_test.dart`, picker group: rewrite to "each of the four list files calls
    `PickerRows.arrange` and calls neither `canPerform(` nor `canOfferInPicker(`" on comment-stripped source.
    This is presence only: it cannot see a list that drops the `other` buckets, so the four widget tests carry that.
- [ ] Run them: FAIL for the new expectations.
- [ ] Implement. Re-run: PASS. For EACH of the four lists, two mutations, each reddening that list's own widget
  test: drop its non-matching buckets; render the unarranged `[...getAll(), ...customs]`. Also restore
  `.take(30)` on the template search, and apply the chip to the swap sheet's custom section.
- [ ] Commit (with the registry ranges for the four lists).

### Task 3: the swap write stops refusing; the injury planner filters for itself and reports what it left

One commit: removing the refusal alone would let the planner write unusable exercises, and filtering without the
report would let the preview claim nothing is affected.

**Files:** modify
- `swap_service.dart`: delete the `:727-747` block, `targetIsCustom` and any unused import; keep not-found,
  own-custom-over-community and `exercise_already_in_workout`. Move the own-custom scan (`:689-701`) into
  `static Map<String, dynamic>? ownCustomRow(HiveService hive, String idOrName)` and use it there.
- `injury_swap_planner.dart`: `plan()` returns `InjuryPlan` (`final List<InjurySwap> swaps; final
  List<InjuryUnplaced> unplaced;`, `InjuryUnplaced {date, exerciseName}`), adding an `unplaced` entry wherever an
  affected exercise gets no substitute (both call sites, `:92-129`; NOT the "library says unaffected" `continue`).
  Read `resolveCapabilityFromProfile()` once per `plan()`. In `_findSubstitute`, for a non-library candidate
  `own = SwapService.ownCustomRow(hive, id)` and `row = own ?? ex` (the same lookup the write uses); skip the
  candidate when capability is not null and
  `!EquipmentCapability.canOfferInPicker(row['equipment_needed'], capability, isCustom: own != null)`. The class
  doc says equipment is checked here and nowhere downstream. `cacheSwaps` / `getCachedSwaps` are unchanged.
- `tool_confirm_card.dart` (`:484-497`, `executedMessageFor`): for `modify_workout_for_injury` whose result `swaps`
  list is empty the base text is `No workouts changed`, not `Workouts updated`; the injury suffix still appends.
- `tool_confirm_sheet.dart` (`:60-65`): this intent is `destructive`, so it is confirmed in the sheet, never on the
  chat card (`chat_area.dart:146-149`). The success snackbar shows when `profileInjuryAdded` is not null (as today)
  OR the intent is `modify_workout_for_injury` with an empty `swaps` list; without the second case the new text is
  never seen when the injury was already on the profile. The applied pill is unchanged.
- `injury_modify_diff.dart`: keep `unplaced` in state. A block (key `injury_unplaced_block`) with the D7 copy shows
  whenever `unplaced` is not empty, above the change list. The "No exercises in the next N days hit this body
  part" text shows ONLY when both lists are empty; with swaps empty and unplaced not, the block is followed by
  today's confirm sentence (`Confirm to record the injury anyway.` / `Confirm to save the injury to your profile.`).

- [ ] Tests first.
  - `exercise_name_unique_in_day_behavioral_test.dart`: the two "mirror: ... stays refused / still held to
    equipment" tests become: the swap succeeds and the day holds `My Move`. "Library row wins" and the own-custom
    resolution stay. Add: a swap to a name already in the day still throws `exercise_already_in_workout` for a
    non-matching target (a guard; it passes on main too, so it is not a red-first proof).
  - new planner group in that file. It seeds its OWN bodyweight profile (the other planner groups have none, so
    the rule is off there). Red first: the barbell skips and the `unplaced` entries; guards that already pass on
    main: the own `[]` custom and the switched-off rule. Cases: barbell candidate first, bodyweight second: only the second is offered; an own custom
    with `[]` equipment beside a community copy of the same id (the planner iterates `exerciseBox` only) is
    offered; an own custom naming a barbell is not, although its community copy says bodyweight; rule switched off
    (`disable_equipment_capability_floor`): the first is offered; no candidate: no swap AND one `unplaced` entry,
    once for EACH branch (the stored row carries the muscles, `:83-106`; only the library row does, `:108-129`);
    mirror: the "library says unaffected" `continue` adds nothing.
  - widget tests beside `test/ai_coach/injury_modify_diff_adds_line_test.dart`: all unplaced (block shown, the
    "no exercises hit" text absent); partial (block and change list); truly unaffected (today's text, no block).
  - `cardio_finisher_shown_pure_test.dart:271-275` (pure function): with `swaps: []` expect `No workouts changed`
    (with and without the knee suffix); add a non-empty-swaps case reading `Workouts updated`; `null` data keeps
    `Workouts updated`.
  - `test/ai_coach/tool_confirm_sheet_injury_line_test.dart`: the saved-injury case with `swaps: []` expects
    `No workouts changed · Knee added to your injuries`; "a success that added nothing says nothing" moves to a
    NON-empty `swaps` list; new: empty `swaps`, nothing added: the snackbar reads `No workouts changed`.
  - `injury_modify_diff_adds_line_test.dart` seeds a profile with no `equipment_access` (so bodyweight) and a
    `Leg Curl` with no equipment: add `equipment_needed: ['bodyweight']` to the substitute rows, here and in the
    new partial fixture.
  - update the `plan()` readers: `exercise_name_unique_in_day`, `coach_unique_exercise_names_test.dart`.
    No fixture needs new equipment unless its test seeds a profile (`coach_injury_profile_write` never calls
    `plan()`); if one reddens, fix the fixture, never the filter.
- [ ] Run: FAIL. Implement. PASS.
- [ ] Mutate: remove the planner's skip; restore the service block; drop EACH `unplaced` add separately; restore
  `Workouts updated` for the empty case; remove the sheet's empty-swaps condition. Each reddens.
- [ ] Write the diagnose-doc (Task 5's first bullet) and commit with `closes-diagnose: <id>`.

### Task 4: the name guard and its message

**Files:** modify `exercise_repository.dart` (`isNameTaken` drops `equipmentRuleOn` and `_noPickerCanShow`;
rewrite its doc and `customNamesLower`'s; remove imports only if unused), `wardroom_copy.dart:209` (copy above;
read `lib/shared/widgets/wardroom/CLAUDE.md` first).

- [ ] Tests first, `custom_exercise_name_unique_behavioral_test.dart`: replace the group "the ONE exception" with
  "every list name is taken": a community row with `[]` equipment, with no equipment field, and an older name of
  such a row, are all refused with `duplicate_name` and nothing is written (KEEP the old group's bodyweight
  profile seed: without it the rule is off, the tests pass on main and the mutation reddens nothing); the message test expects
  `Search its name to add it` and no `equipment`. The similar-name mirrors stay.
- [ ] Run: FAIL. Implement. PASS. Mutation: restore the skip, the three tests redden.
- [ ] Commit.

### Task 5: records

- [ ] Diagnose-doc `docs/diagnoses/2026-11-28-hand-pick-equipment-block-<id>.md` (full template, tier platform;
  `related_bugs: [b6f4d1, e7b2d4, a6f3d9, f2a6c8, e7c4a1]`; states the founder rule change AND the planner gap;
  12-tier field; mutation counts). `dart run scripts/validate_diagnose_doc.dart <path>`.
- [ ] `docs/naming_conventions.md`: rewrite the `effective` (equipment) row (:359): it ORDERS the hand-pick lists
  and constrains the generator, warm-up, finisher, injury planner and snapshot; add a `PickerRows` row (list
  arrangement; matching / other buckets; not a filter).
- [ ] Stale comments (no code change): `training_history_analyzer.dart:243-248`,
  `equipment_capability.dart:37-57` ("all three pickers"), `scripts/check_hive_map_field_drift.dart:401-404`.
- [ ] `docs/audit/open_issues.md` OI-211: if its rationale leans on the picker exemption, reword to what is left.
- [ ] `docs/sot_registry.yaml`: the custom-exercise concept's `isNameTaken` and four list readers (semantic
  `display`, ordering, new line ranges), the `equipment_capability_floor` concept (`:13537`, NOT `exercise_equipment_tier`): rewrite its description of
  what the floor covers and its readers (drop the swap-service `refuse`
  row, the coach-list `hard-filter` row and the `isNameTaken` row; add `injury_swap_planner._findSubstitute` as
  `hard-filter` and `PickerRows.arrange` as ordering), and the line ranges of every other entry that cites a moved
  line (`exercise_name_unique_in_day`, InjurySwapPlanner).
- [ ] `scripts/exercise_seam_lib.dart`: rewrite the `reason` for the four list files. Counts: the template builder
  goes 3 to 2 (Task 2 removes its `repo.search(`), in Task 2's commit; the other three are unchanged.
- [ ] Docs: `lib/features/train/CLAUDE.md` `custom_exercises_mutations` row (drop the exception and "pickers
  hide"), a short row or pitfall "hand-pick lists order by equipment, never hide: use `PickerRows.arrange`";
  `lib/features/ai_coach/CLAUDE.md` if it states the coach-list rule; `lib/features/profile/CLAUDE.md` equipment
  row if it says pickers filter. Update the header comments of `ui_seam_capability_test.dart` and
  `can_offer_in_picker_behavioral_test.dart` where they say the four seams filter.
- [ ] OI-403: replace the "Also: no equipment check" paragraph with a one-line closed note naming the bug id.
- [ ] Commit.

### Task 6: verify

- [ ] `flutter analyze --no-fatal-infos` (whole project): no warning or error.
- [ ] Targeted: every test file named above (including `cardio_finisher_shown_pure_test.dart` and
  `tool_confirm_sheet_injury_line_test.dart`), `test/widgets/swap_sheet_custom_exercises_test.dart`, plus
  `test/contracts/*capability*`, `test/contracts/swap_*`, `test/scripts/exercise_seam_lib_test.dart`.
- [ ] Gate loop (pre-commit), then CI on the PR (`sh scripts/land_pr.sh <pr> --ci-only`) before the B-pass.
- [ ] `dart run scripts/blast_radius_from_diff.dart` on the real diff; record the tier it prints.
- [ ] Plan-review record `docs/plan-reviews/hand-pick-any-exercise.md`; `/code-review` before any merge.
- [ ] Owed after merge, on a build or the web app (no phone run happens in this batch): with a bodyweight profile,
  add a barbell exercise mid-workout, by swap, in a template and from the coach list.
