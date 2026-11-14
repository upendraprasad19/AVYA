---
reviewed_at: 2026-11-12T19:30:00+05:30
staged_against: 2a27c7dc (PR #253 head, CI green; three-dot diff origin/main...HEAD)
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 12
verdict: accepted
verdict_note: no P0/P1 in either seat; 5 P2 and 7 P3; every P2 fixed with a mutation-proven test; P3 fixed or closed with a reason
---

# Code Review (B-pass) - oi493b-duplicate-meals (OI-493 Landing B)

Two fresh Sonnet seats on the CI-green head `2a27c7dc`, each with `docs/agent_brief_preamble.md` and an exhaustive
command list. Seat A (lenses 1-5, 7, 8) read code only through `git show HEAD:`. Seat B (lens 6) ran 8 mutants on two
files with backup / sha256 restore (tree clean afterwards) and ran out of budget before the handler, card and screen
call sites; the coordinator covered those with the second mutant batch (diagnose 4cb58f, B8-B11).

## Seat A

### A1 — P2 — writer_reader_drift / unawaited_no_error_sink
- **file:line:** lib/features/nutrition/widgets/scan_meal_section.dart `_save` (the `clear()` sat after `if (!mounted) return;`)
- **claim:** a scan editor unmounted during its save kept the scan result; a remounted editor could save the same meal again, a second entry under F4.
- **status:** accepted, fixed: the notifier is captured before the await and cleared on success whether or not mounted (the LogConfirmCard rule); source pin in R7, mutant B10 red.

### A2 — P2 — writer_reader_drift (registry ranges)
- **claim:** the batch shifted existing registry ranges by the diff's delta; several were already stale on main and still did not bracket their method (`restoreFoodLog`, `deleteLog` x2, `saveMealPreset`, `relogSavedMeal`, `_logWater`, `_logSleep`, `_logSleep + _logMeasurement`, `_showEditMacrosSheet`, `_confirmAndDeleteFoodLog`).
- **status:** accepted, fixed: every range that cites a touched file re-derived from the tree (declaration to closing brace, class-aware), each flag checked by hand: 19 rows re-set, including six the reviewer did not list (`_confirmAndDeleteLog`, `ScanMealSection build`, the two water reads, the TODAY'S MEALS section, `ExerciseSet.fromMap`, `WeeklyNutritionNotifier` skip). Lesson below.

### A3 — P3 — writer_reader_drift (_restoreNutritionLogs)
- **claim:** when the cloud slot holds items this device lacks, the restore replaces all of the slot's local rows (occurrence rows included) with one merged row; separate entries and per-row total overrides are lost (items are not).
- **status:** accepted as a residual: pre-existing for any two meals in one slot (one cloud row per slot), reached only when a second device logs to the same slot; recorded in the plan's and the diagnose's residuals and in the registry reader note.

### A4 — P3 — missing_input (registry manifest)
- **claim:** `nlog_repeat_occurrence_key` declared `reader_manifest_complete: true` with two readers.
- **status:** accepted, fixed: `_restoreNutritionLogs`, TodaysMealsCard (row id), `_getMealsToday`, `recentLoggedItems` added with notes.

### A5 — P3 — asserted_fixture_value
- **claim:** the search, recent, barcode and scan guards are pinned by source only; R9 exercises the pure push / restore helpers, not `_restoreNutritionLogs`.
- **status:** accepted with a reason: `SingleFlight` itself and the AI-text notifier are behavioural; the keys are now unit-tested (food, grams, slot; mutant B9 red), and the four call sites are source-pinned to `SingleFlight.run` with those key functions. A widget-level double tap on the scan / barcode sheets needs the camera stack. `_restoreNutritionLogs` needs a Supabase client; the helpers it calls are the merge semantics.

### A6 — P3 — function_exception_swallow (pre-existing)
- **claim:** `_logWeight` invalidated providers on a possibly disposed ref after a successful write; the throw turned a stored weight into a failure.
- **status:** accepted, fixed in this batch (same rule as `_logFood`): try/catch around the refresh; source pin, mutant B11 red.

## Seat B

### B1 — P2 — guard_without_its_mirror
- **claim:** `firstFreeLogKey`'s loop was pinned only to a third serving (`while` -> `if` survived).
- **status:** accepted, fixed: R1 logs five servings, expects `_4` and `_5`; mutant B1 red.

### B2 — P2 — guard_without_its_mirror
- **claim:** `restoreFoodLog`'s stored `id` / `log_key` at the relocated key were not asserted (`put(target, log)` survived).
- **status:** accepted, fixed: asserted; mutant B2 red.

### B3 — P2 — guard_without_its_mirror
- **claim:** the one-shot owner record in `restoreFoodLog` and the 16-entry cap were unpinned.
- **status:** accepted, fixed: the same copy restored twice writes one row (B3 red); an UNDO survives 15 later deletes and is refused after 16 (cap 1 and cap 17 both red).

### B4 — P3 — guard_without_its_mirror
- **claim:** no test for a negative override.
- **status:** accepted, fixed: -50 / -5 fall back to the items; mutant B5 red.

### B5 — P3 — guard_without_its_mirror
- **claim:** the non-shape branch of `_restoreTargetKey` was untested.
- **status:** accepted, fixed: a taken legacy key is restored in place; mutant B6 red.

### B6 — P3 — guard_without_its_mirror
- **claim:** the migrator's oldest-first order was unpinned.
- **status:** accepted, fixed: the older legacy row takes the base key; mutant B7 red.

Not reached by seat B (budget), covered by the coordinator: two different coach actions at once (R6b, mutant B8 red); the
screen tap keys (B9); the scan unmount clear (B10); the weight refresh (B11). Not covered: SKIP during a running tag
save (the existing dismiss path; on success `markLogged` + `removeSettled` still clear the dismissed action).

## Founder triage notes
None needed: no finding asks for a product decision.

## Tuning entry
- **2026-11-12** - blast-radius account - 12 findings; 0 false_alarm; tuning: none. Seat A's registry finding is a new shape: a mechanical shift of line ranges through the batch's own diff moved ranges that were ALREADY stale on main, so they stayed wrong while looking maintained. When a batch touches a file, re-derive every registry range that cites it from the tree (declaration to closing brace), do not shift it. The mutation seat's six survivors were all "pinned at N, unpinned at N+1" or "one leg of a pair asserted": for every new collection bound or cap, test both sides of it.
