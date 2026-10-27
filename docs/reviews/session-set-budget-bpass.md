---
reviewed_at: 2026-10-25T01:30:00+05:30
staged_against: 011b5c497edc98a3b88d9fcbc826c8c8b8326ef6
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 36
verdict: accepted
---

# Code Review (B-pass) - branch session-set-budget (Batch B2)

Reviewed: `git diff 70f1237c..011b5c49` (base = main after the thin-day top-up merge; head = the branch after the env-manifest fix), the production code of the batch plus its tests and records. Three fresh, read-only Sonnet subagents, each with a different slice and no conversation context: (1) the core rules and the allocator, (2) the consumers and the `generateV4` wiring, (3) the display, the gate, the scripts and the records.

Severity count: P0 0 . P1 0 . P2 7 . P3 29. No false alarms. Three claims were marked PLAUSIBLE by the reviewers: Finding 12 (confirmed by reading, it is by design), Finding 20 (a latent divergence on duplicate names, fixed defensively) and Finding 24 (confirmed by measurement, below).

Fixes landed in four commits on this branch: `13349c27` (allocator and core rules), `95cd1b75` (consumers), `f2d656a1` (display), `1f2d2ce8` (gate, report, docs, drift-gate scope), plus `08b1c4ea` (mutation survivors). A finding below says which.

## Method note

The reviewers read the diff hunk by hunk and the full current files named in each slice; reviewer 1 also read all 285 library `primary_muscles` arrays, reviewer 3 the stored-plan-day writers (`swap_service`, `tool_dispatcher`, `template_service`, `warmup_cooldown`, restore) and the three scripts' diffs. They ran nothing (read-only git, Read, Grep, Glob), so every claim that needs execution was marked UNVERIFIED by them. The author then verified each claim against the code and, for the behaviour claims, wrote the failing test first: a finding is `accepted` only after a test reddens without the fix (or a measurement shows it), and every new protection was then mutated (section "Mutation proofs"). Numeric claims in the reports were re-derived from the gate, not copied.

## Findings, reviewer 1 (core rules and allocator)

## Finding 1 - P2 - asserted_fixture_value

- **file:line:** `lib/shared/repositories/plan_engine/session_set_allocator.dart:243-250` (call), `:391-409` (`_firstBlockingGroup`).
- **claim:** `boundBy` is computed after `ledger.add` with `granted + 1`, so it tests `week + granted + 1 > top`: it double-counts and names a group when only time bound the lead lift. The only test that reaches the branch gives the same answer under both formulas.
- **verification:** read `:243-250` beside `:391-409`; mutation `granted + 1` -> `1` left the old test green.
- **status:** accepted - fixed in `13349c27` (`_firstBlockingGroup(ledger, d, s, 1, later)`), new test 'boundBy is null when only TIME held the lead lift below its desired sets' RED then GREEN, mutation A1 killed.

## Finding 2 - P2 - guard_without_its_mirror

- **file:line:** `session_set_allocator.dart:215-284` (pass A, the empty-day guard, the reservation).
- **claim:** a lead lift can be dropped while accessories stay: the guard fires only when NOTHING is admitted. The old `slots.take(targetCount)` always kept the first N priority-ordered slots. Mirror cases: the reservation releases its room if the later day's lead lift is refused for time; more leads than the top allows removes the earliest day's lead; a day whose rank 0 is refused but rank >= 1 admitted has no lead lift; the forced add ignores time.
- **verification:** the repo's own pinned tests encode cases 1 and 3 (`crowdedChestWeek`, the Biceps-after-Chest test).
- **status:** accepted as POLICY, documented and measured, not changed - the user's minutes are authoritative, so a lead lift the time cannot afford is dropped (and reads `sets: 0`); it is protected from the week (the reservation) and from an empty day (the guard), not from the clock. Stated in the allocator class doc (`13349c27`), `plan-engine-detail.md` and the nested CLAUDE.md; measured in the gate (`1f2d2ce8`): lead lift not kept 0 of 9,966 allocated days; test 'R1 P2-2: a lead lift that does not fit is dropped while a cheaper lift stays; the stat says so'. Listed as item (5) on the flip review.

## Finding 3 - P3 - writer_reader_drift

- **file:line:** `session_budget.dart` (`dayIntensities`), `plan_generator.dart:296`, `session_set_allocator.dart:91`.
- **claim:** `SessionBudgetContext.dayIntensities` has a writer and no reader; a doc comment states a false requirement.
- **verification:** `git grep -n dayIntensities -- lib test`.
- **status:** accepted - removed in `13349c27`; the grep now returns nothing.

## Finding 4 - P3 - writer_reader_drift

- **file:line:** `session_set_allocator.dart:160-164` against `session_budget.dart:163-166`.
- **claim:** the "budgeted" predicate is implemented twice (rows vs `archetypeByName`) and agrees only because production builds both from one map.
- **verification:** read both; `apply` and titration use the second.
- **status:** accepted - fixed in `13349c27` (the allocator calls `SessionBudget.isBudgeted`); mutation A4 killed 13 tests.

## Finding 5 - P3 - writer_reader_drift

- **file:line:** `session_set_allocator.dart:11-13, 272-277, 374-433`.
- **claim:** `timeForcedFirst` is documented as the lead lift but counts any forced pick that is not the cap branch; in variant B `_label` returns `cap_limited` by fallthrough for a group whose only crediting slots sit on frozen copy days.
- **verification:** read the counter and `_whyFlags`.
- **status:** accepted - fixed in `13349c27`: doc rewritten, fifth floor label `copy_day_limited` (variant B only); mutation A6 killed; naming row updated.

## Finding 6 - P3 - missing_input

- **file:line:** `budget_muscle_groups.dart:28` and the muscle read at `session_set_allocator.dart:175`, `session_budget.dart:137`.
- **claim:** `lower back|erector|spinal` is a literal phrase (`Low Back`, `Lower-Back` miss it and the `back` keyword maps them to Back); `\blats?\b` rejects `Latissimus Dorsi`; `abs` rejects `Abdominals` / `Rectus Abdominis`; `quad` would match `Quadratus Lumborum`; a String `primary_muscles` throws a TypeError in the allocator; a null list element becomes the string "null" and the archetype B instead of the compound default. None occurs in the shipped library.
- **verification:** read the regexes; the shape claims were checked against the 285 rows by the reviewer.
- **status:** accepted - fixed in `13349c27` (regexes, `is List`, null elements skipped in `_groupsOf` and `_typesOf`); tests for each spelling, the non-list value and the null element; mutations G1 to G4, S1, A3b killed. A survivor (G5: the `quadratus` keyword is covered by `lumborum` for the full name) was pinned in `08b1c4ea` by a bare `Quadratus` case; G5b killed.

## Finding 7 - P3 - writer_reader_drift

- **file:line:** `volume_filter.dart:43-46, 3-10`.
- **claim:** the comment says the allocator trims "from the END of the priority order"; pass A skips refused slots and continues.
- **status:** accepted - docs rewritten in `13349c27`.

## Finding 8 - P3 - writer_reader_drift

- **file:line:** `plan-engine-detail.md:362`, `plan_engine/CLAUDE.md` B2 bullet.
- **claim:** the docs say all consumers take "one `BudgetLedger`" and that `WarmupCooldownSelector` takes it; each consumer builds its own and the selector reads `budget.minutes` only.
- **verification:** `git grep -n BudgetLedger -- lib`.
- **status:** accepted - fixed in `1f2d2ce8` (detail doc and nested CLAUDE.md).

## Finding 9 - P3 - guard_without_its_mirror

- **file:line:** `session_set_allocator.dart:192, 113-115`.
- **claim:** a partial copy (`i < mine.length && i < e.value.length`) is silent, and `sameNames` compares `List.toString()`, which is ambiguous for names that join alike.
- **status:** accepted - fixed in `13349c27` (`_sameNames` compares element names); test 'R1 P3-7: two A/B lists whose names only JOIN alike are not the same day'; mutation A5 killed.

## Finding 10 - P3 - missing_input

- **file:line:** `test/plan_generator/generator_matrix.dart:164`, `sample_plans_report.dart:35`, `v4_diagnostic/markdown_writer.dart:46`.
- **claim:** the scorecard mirrors never pass `keepAllSlots`.
- **status:** not a defect - documented in the nested CLAUDE.md ("the scorecard cannot measure them"); the ON instrument is the gate over real `generateV4` runs. Closure `verified_clean`.

## Finding 11 - P3 - missing_input

- **file:line:** `session_budget.dart:11-14` (Pelland 2026, Remmert 2025), `plan-engine-detail.md:368` ("1,802 runs ... 6 of 1,776 ... 27 minutes").
- **claim:** citations and gate numbers are unverifiable offline.
- **status:** accepted in part - the gate numbers were regenerated from the report (`1f2d2ce8`); the two literature citations cannot be source-checked from this session (they are header comments, no behaviour depends on them). Closure `upstream_blocked`, reopen when a source check is done.

## Findings, reviewer 2 (consumers and wiring)

## Finding 12 - P2 - guard_without_its_mirror

- **file:line:** `exercise_selector.dart:1059-1076` (`buildPinnedDays`), `session_set_allocator.dart` (`allocate`), `plan_generator.dart:195-211`.
- **claim:** a repeat phase (`pinnedExercisesByDay`) takes the previous phase's exercise names, which came out of an allocation that dropped what did not fit the minutes then; the allocator never adds exercises. A user who moves from 30 to 90 minutes between phases and repeats keeps the short list. The repeat gate tests adherence only.
- **verification:** `git grep -n "removed = true"` in the allocator: the only list change is dropping.
- **status:** accepted as a product question, not changed (pins are faithful by design) - recorded as item (6) of the flip review and in `plan-engine-detail.md` (f). Closure `upstream_blocked`, reopen at the flip review.

## Finding 13 - P3 - guard_without_its_mirror

- **file:line:** `volume_titration.dart:229-243`.
- **claim:** `_titrateWeekBudgeted` treats `delta == 0` as a trim (`if (delta > 0) ... else {trim}`), and `next` repeats the assumption.
- **status:** accepted - fixed in `95cd1b75` (`if (delta == 0) continue;`, `next = cur + delta.sign`). The first zero-delta test could not see the guard (the net change was zero either way; only `bumped` differs), so `08b1c4ea` added a fixture with a row shared by two groups and a +2 / -3 case; mutations C1b and C2b killed.

## Finding 14 - P3 - asserted_fixture_value

- **file:line:** `test/contracts/session_set_budget_consumers_test.dart:261-270`.
- **claim:** "null budget is today's path, byte for byte" compares `apply(...)` with `apply(..., budget: null)`: the same call.
- **status:** accepted - fixed in `95cd1b75`: the 4-week OFF grids are pinned as recorded literals (`4x10@75,4x13@75 | ...`); mutation C8 (the OFF 4-set minimum 3) killed 3.

## Finding 15 - P3 - asserted_fixture_value

- **file:line:** `session_set_budget_consumers_test.dart:411-421, 581-595`.
- **claim:** the titration tests do not isolate the weekly-top clause (each day sits at the session cap too); no deload-week trim test; no titration test where time refuses a +1.
- **status:** accepted - fixed in `95cd1b75` (Chest 6/6/4, a deload-week trim, a time refusal, the band bottom); mutations C3 (weekly clause, 3 red), C4 (session cap, 6), C5 (time clause, 3), C6 (time spend, 2), C7 (deload `workingSets`, 2), C13 (trim below bottom, 3), C14 (trim below one set, 1), C15 (past 5 sets, 1) all killed.

## Finding 16 - P3 - writer_reader_drift

- **file:line:** `lib/shared/repositories/plan_engine/CLAUDE.md:83`; `plan_generator.dart:26-29`.
- **claim:** the nested file says the allocator runs "after sequencing, before `apply`"; in `generateV4` it runs at `:298`, `apply` at `:307`, titration at `:340` and `SequencingEngine.sequence` last at `:344`. The pre-existing pipeline header in `plan_generator.dart` is stale the same way.
- **verification:** `git grep -n "SequencingEngine" -- lib`.
- **status:** accepted in part - the nested file is fixed in `1f2d2ce8` ("before apply, ahead of sequencing, so its rank is the split's slot order"). The `plan_generator.dart` header is a rule-14 file and the founder's F1 waiver covered the wiring only: closure `upstream_blocked`, reopen at an explicit instruction (a two-line comment fix).

## Finding 17 - P3 - writer_reader_drift

- **file:line:** `plan_generator.dart:147-150` against `training_history_analyzer.dart:290-300, 246-250`.
- **claim:** the sibling docs still list "tier is not `bodyweight`" as a null case of `resolveCapability` and say `resolveCapabilityFromProfile` is bodyweight-scoped (retired by OI-144).
- **status:** accepted - both docs rewritten in `95cd1b75`.

## Finding 18 - P3 - missing_input

- **file:line:** `docs/ship_dark_pending_review.yaml:333`, `plan-engine-detail.md:368`, `docs/sot_registry.yaml:16918`.
- **claim:** three docs cite `docs/audit/session-set-budget.closure.yaml`, which was not in the tree.
- **verification:** `git ls-files docs/audit | grep -i session-set`.
- **status:** accepted - the ledger is in the records commit (Gate 40 validates it).

## Finding 19 - P3 - writer_reader_drift

- **claim:** `SessionBudgetContext.dayIntensities` has a writer and no reader (same as Finding 3).
- **status:** accepted - fixed in `13349c27`.

## Finding 20 - P3 - writer_reader_drift

- **file:line:** `session_set_allocator.dart:175` against `periodization_engine.dart:307`, `volume_titration.dart:198`.
- **claim:** the allocator reads a row's muscles from `rowsByName` (last-wins by lowercased name, a hard `as List?` cast); the consumers read the exercise's own `primaryMuscles` (copied from the picked row). `getByExactName` is first-wins and a community row can share a bundled row's name.
- **status:** accepted - fixed in `13349c27`: the exercise's carried muscles win over the row's, `is List` instead of a cast, and `plan_generator.dart` builds `rowsByName` first-wins (`putIfAbsent`, wiring); mutation A2 killed; test 'R2 P3-8: a primary_muscles value that is not a list reads as no muscle, it does not throw'.

## Finding 21 - P3 - writer_reader_drift

- **file:line:** `periodization_engine.dart:356-360, 376-377`, `session_set_allocator.dart:88`.
- **claim:** the rep-based logging set exists in three places; the not-budgeted rule in two.
- **status:** accepted - `SessionBudget.isRepBased` and `SessionBudget.isBudgeted` are the only copies (`13349c27`); mutations S2 and A4 killed.

## Finding 22 - P3 - function_exception_swallow

- **file:line:** `plan_generator.dart:278-304`.
- **claim:** the ON block has no try/catch and no OFF fallback, so an exception in `getAll()`, `archetypeOfRow` or `allocate` stops generation for an ON user. The reviewer calls it an observation.
- **status:** no change - every other stage of `generateV4` behaves the same way, the flag is ship-dark, no input the reviewer read can throw, and a fallback would hide a real defect from the gate. Closure `verified_clean`.

## Findings, reviewer 3 (display, gate, scripts, records)

## Finding 23 - P2 - missing_input

- **file:line:** `session_budget.dart:119-121, 207-225, 253-264`.
- **claim:** the display prices a `cardio` / `distance` / long `timed` row as one 40 s set; a user-added Treadmill (E061, `default_reps: "20-40 min"`) reads about 1.4 minutes, so Train and Home understate such a day by 20-40 minutes. The gate shares the same B rule, so it cannot see it.
- **verification:** `git grep -n '"default_reps": "20-40 min"' -- assets/data/exercise_library.json`.
- **status:** accepted - fixed in `f2d656a1`: `SessionBudget.longEffortWorkSeconds` (a row whose `reps` names minutes works that long per set, capped at 7200 s) is used by the allocator's not-budgeted rows, apply week 2, titration and the display; seconds, metres and rep prescriptions keep the table. Test 'R3 P2-1: a cardio row prescribed in minutes spends those minutes, so the lift shrinks' and the display tests; mutations E1, E2, E3 killed.

## Finding 24 - P2 - writer_reader_drift

- **file:line:** `lib/core/services/swap_service.dart:718-727` (`_estimateExerciseListSeconds`, used at `:606, :637, :648`; reached from `tool_dispatcher.dart:618`).
- **claim:** a third session-length estimator (`sets * 60 + sets * rest`, no overhead, no 1.2, no warm-up) disagrees with the budget model once the flag is ON: the coach shortens a day "to 45" and Train and Home show about 55.
- **verification:** PLAUSIBLE for the reviewer; confirmed by measurement - the same stored day reads 21 minutes OFF and 26 minutes ON.
- **status:** accepted - fixed in `f2d656a1`: `_estimateSeconds` prices through `budgetedDaySeconds` when the flag is ON, the old sum stays OFF; mutation E9 killed.

## Finding 25 - P2 - guard_without_its_mirror

- **file:line:** `test/plan_generator/session_set_budget_gate_test.dart:266-267, 275, 329-352`; `session_set_allocator.dart:86, 122`.
- **claim:** `debugLastStats` is a static only `allocate` assigns; the gate never resets it before `gen(p)` nor asserts it is non-null, so a run where the allocator did not run reads the previous persona's stats, and if it never ran the forced / lead-lift / lost-lifts zeros are vacuous. They also read allocator self-reports, not the final plan.
- **status:** accepted - fixed in `1f2d2ce8`: `check()` resets `debugLastStats`, asserts the allocator ran, and an oracle-side lost-lifts zero reads the final plan; mutation GA1 (the allocator never sets the stats) killed 6.

## Finding 26 - P2 - asserted_fixture_value

- **file:line:** `test/contracts/session_estimate_display_test.dart`, the gate's `daySeconds` (`:228-231`).
- **claim:** `estimateDaySecondsFromPlanDay` / `budgetedDayMinutes` are called only from the hand-built display test; the oracle and the display each re-implement warm-up pricing and rest parsing, so a drift between them would pass every test.
- **status:** accepted - fixed in `1f2d2ce8`: the gate prices every stored day through `estimateDaySecondsFromPlanDay` and compares it with the oracle - equal to 1e-6 s on all 33,204 days; mutation GA2 (a timed item +1 s) killed 6.

## Finding 27 - P3 - function_exception_swallow

- **file:line:** `session_budget.dart:248, 256`; `session_estimate.dart:30-34`.
- **claim:** "never throws" is not true: `int.parse` on a rest string such as `"99999999999999999999 s"` or a 20-digit timed `reps` throws `FormatException`; one corrupt row would break the Train plan provider under ON; the empty `catch (_)` has no telemetry; huge `sets` / rest are not clamped.
- **status:** accepted - fixed in `f2d656a1` (`tryParse`, digit runs capped, sets 0..100, rest 0..3600, a failure reported as `session_estimate_day_minutes` and degraded to null). `08b1c4ea` pinned the parts the first tests missed (a parseable `99999 s` rest clamped to 3600; the telemetry call, through `ErrorTelemetry.debugOnRecordNonFatalForTests` and an unreadable stored list); mutations E3 to E5, E6b, E11b killed.

## Finding 28 - P3 - writer_reader_drift

- **file:line:** `session_budget.dart:253-258` against `train_provider.dart:326-370` (`parseTimedDurationSecs`).
- **claim:** the display takes the first digit run of `reps` (`"2 min"` becomes 2 s); the Train helper handles `min` units and averages ranges.
- **status:** accepted - fixed in `f2d656a1` (`SessionBudget.timedItemSeconds` follows the Train rules; the test runs both over the same cases); mutation E8 killed.

## Finding 29 - P3 - missing_input

- **file:line:** `template_service.dart:318-345`; `session_estimate_display_test.dart:205-235`.
- **claim:** template-built days carry no `exercise_id` or `rep_range`, so a heavy compound is priced M instead of H; 52 library rows are multi-type; the archetype-agreement test compares `archetypeOfRow(r)` with itself and skips multi-type fallback rows.
- **verification:** `git grep -c -E '"exercise_type": \[' assets/data/exercise_library.json` and the two-entry list grep (52).
- **status:** accepted - fixed in `f2d656a1`: exact-name lookup (alias matches rejected), and the agreement test compares to an independent oracle and covers multi-type rows. `08b1c4ea` added the alias-rejection case; mutations E7, E10b, E12 killed.

## Finding 30 - P3 - blast_radius_mismatch

- **file:line:** `scripts/check_hive_map_field_drift.dart:383-388`; `backups/gate19_drift_baseline.txt:172, 204`.
- **claim:** `session_duration_minutes` was added to the name-global `_alwaysOk` when a file-scoped baseline already existed, so any future misread of that field in any prefix-reading file is suppressed.
- **status:** accepted - fixed in `1f2d2ce8`: removed from `_alwaysOk`; the two real hits in `training_history_analyzer.dart` are baselined by file; `dart run scripts/check_hive_map_field_drift.dart` PASS (554 candidates, all in baseline).

## Finding 31 - P3 - writer_reader_drift

- **file:line:** `test/scripts/regression_catalog_lib_test.dart:253`.
- **claim:** the independent literal list of scrubbed control variables was not updated with `WRITE_SESSION_BUDGET_REPORT`.
- **status:** accepted - fixed in `1f2d2ce8`.

## Finding 32 - P3 - missing_input

- **claim:** docs cite a closure file that does not exist at HEAD (same as Finding 18).
- **status:** accepted - the ledger is in the records commit.

## Finding 33 - P3 - asserted_fixture_value

- **file:line:** `ship_dark_pending_review.yaml:340`, `plan-engine-detail.md:368` against `session_set_budget_report.md:104` and the gate `:291-293`.
- **claim:** (a) "6 of 1,776 personas" counts days; (b) "the one allowed overage" is wrong - the gate allows every day up to minutes + 2, the medians already exceed the user's minutes (30.2 at 30, 60.1 at 60); (c) "about 122 minutes" has no in-tree derivation; (d) "weekly tops bind first" is not measured. Checked and correct: 1,802 total runs, 90-minute median 27.3, founder case Quads 8 / Glutes 16, 998 golden personas.
- **status:** accepted - fixed in `1f2d2ce8`. The report now counts days (7 past minutes + 2 of 33,204; 3,965 over by any amount; median 0.70 min over; 911 over by more than a minute; worst 5.5), names the +2 slack as the warm-up calibration residual (Ruling 3), carries the flag-OFF table in tree (41 to 116 minutes), and states the 90-minute leftover (27.2) without a cause the report cannot attribute.

## Finding 34 - P3 - writer_reader_drift

- **file:line:** `docs/sot_registry.yaml` (`session_duration_minutes`, about 16960-16999).
- **claim:** "carried to the cloud and back" but the three cited carriers are push paths; the restore leg (`auth_session_bootstrapper.dart:866-886`) and two readers (`profile_completeness_provider.dart:7`, Edit Profile's initial read) are missing; migration 017's column comment still says the generator "no longer reads this" and will be wrong at the flip.
- **status:** accepted - the registry is fixed in `1f2d2ce8` (`hydrateFromCloud` writer, `kTier2Fields` and `edit_profile_screen initState` readers). The `COMMENT ON COLUMN` is a live-schema apply (own explicit go, root CLAUDE.md 4.3) and is TRUE while the flag is OFF, so it is on the flip checklist of the `enable_session_set_budget` entry; closure `upstream_blocked`.

## Finding 35 - P3 - asserted_fixture_value

- **file:line:** `session_estimate_display_test.dart:311-323`; the gate grid; `fitness_goals.dart:108-113`.
- **claim:** the Home card is covered by source-grep only (replacing `durationMin: estDuration` with a constant stays green); the grid omits the live fifth goal `recompose`, covers phases 1, 4, 5 only, and has no injured personas.
- **status:** accepted - the Home test now pins the assignment from `homeCardMinutes`, exactly one `durationMin: estDuration,` hand-off and the three card sites (`08b1c4ea`; it stays PRESENCE-ONLY by declaration, the card is built inside a screen). The gate gained "the recompose goal (plans as build_muscle) and injured users" (45 runs, `1f2d2ce8`). On phases: 1, 4 and 5 cover every reachable (effective level x lighter) pair - beginner 1 / 4 / 5, intermediate 1 / 4 / 5, advanced - and a phase changes only the reps in the time model (`periodization_engine.dart` sets rest from the day's intensity, not the archetype).

## Finding 36 - P3 - blast_radius_mismatch

- **claim:** `scripts/**` is feature tier (`blast_radius.yaml:495`), so `exercise_seam_lib.dart` and the drift gate clear no review gate on their own; `check_context_artifact_budget --record` re-baselined nine unrelated artifacts; the recorded values equal the HEAD sizes.
- **status:** informational. This batch is platform through `plan_engine/**` and carries this review; the drift-gate edit was narrowed (Finding 30). The tool records every entry at once; it is the documented way to re-baseline. Closure `verified_clean`.

## Founder triage notes

All 36 findings triaged by the author (not yet by the founder): 28 fixed in code or docs (1, 3 to 9, 13 to 15, 17 to 21, 23 to 33, 35); 1 policy documented and measured (2); 1 recorded as a flip-review question (12); 2 fixed in part with the remainder blocked by a rule or by a live apply that needs its own go (16: rule 14, 34: the migration-017 comment); 1 not source-checkable here (11); 3 no defect or informational (10, 22, 36). The two P2s that read hardest are 25 (a gate that could pass on stale data) and 23 (a displayed duration wrong by 20 to 40 minutes for a cardio row); no test that existed could see either.

## Lens results

1. **writer_reader_drift.** Writers: `SessionSetAllocator.allocate` (sets), `PeriodizationEngine.apply`, `VolumeTitration.applyToWeeks`, `WarmupCooldownSelector.attach`. Readers: `SessionBudget.estimateDaySecondsFromPlanDay` through `budgetedDayMinutes` / `homeCardMinutes` (Train day card and week list, Home), `swap_service.shortenDay`. The gate now prices every stored day through the reader and compares it with an independent oracle on 33,204 days. The drift found is Findings 3, 4, 7, 8, 16, 17, 19 to 21, 28, 31, 34.
2. **function_exception_swallow.** `git diff 70f1237c..HEAD -- lib test scripts | grep -cE "^\+.*(functions\.invoke|\.invoke\()"` gives 0. The new catches are `budgetedDaySeconds`'s (reports `session_estimate_day_minutes`), `sessionMinutesFromProfile`'s (reports and returns null), `_libraryRow`'s (a missing library box reads as no row, deliberately) and the flag getter's (default OFF).
3. **blast_radius_mismatch.** `plan_engine/**` is platform (`blast_radius.yaml:108`): flag (`enable_session_set_budget`, default OFF), regression and behavioural tests, this B-pass. Findings 30 and 36.
4. **secrets_in_tree.** Pattern scan of the added lines of `lib test scripts docs backups` (`sk-`, `rzp_`, `AKIA`, `-----BEGIN`, `eyJ`, `AIza`, `service_role`, `api_key`, `password`) hits nothing.
5. **unawaited_no_error_sink.** Two `unawaited(` in the production diff, both `ErrorTelemetry.recordNonFatal` calls and so themselves the error sink: `budgetedDaySeconds` (`session_estimate_day_minutes`, a test pins that it fires once) and `TrainingHistoryAnalyzer.sessionMinutesFromProfile` (`training_history_analyzer_session_minutes`).
6. **guard_without_its_mirror.** Mirrors named and tested: the empty-day guard (Finding 2: the day with accessories and no lead), the delta guard (Finding 13: a zero that consumes an exercise), the reservation (Finding 2), the alias rejection (Finding 29: an alias is another row), the debug-stats reset (Finding 25).
7. **missing_input.** Exists with the shape the code indexes: `assets/data/exercise_library.json` (285 rows, `primary_muscles` non-empty arrays, `exercise_type` arrays, `rep_range` strings). Did not exist when reviewed: the closure ledger (Findings 18, 32). Distribution of values counted: 52 multi-type rows, 11 rep-based rows with no budget group.
8. **asserted_fixture_value.** Findings 1, 14, 15, 26, 33, 35. Every literal in the OFF grids was computed from the engine's profile table, not read back from the function under test.

## Mutation proofs (rule 21)

Each mutation was applied once to the committed code, the test file run, and the file byte-restored (sha1 asserted). "red" is the number of failing tests.

| id | mutation | result |
|---|---|---|
| A1 | `boundBy` asks `granted + 1` | killed (1) |
| A2 | the row's muscles win over the exercise's carried | killed (1) |
| A3 -> A3b | a non-list `primary_muscles` is iterated | A3 did not compile; A3b killed (1) |
| A4 | budgeted decided by row presence | killed (13) |
| A5 | `_sameNames` by `toString` | killed (1) |
| A6 | copy-day label is `cap` | killed (1) |
| A7 | not-budgeted row priced as a plain B | killed (1) |
| A8 | first-lift groups empty | killed (2) |
| G1 to G4 | old erector regex; no `latissimus`; no `abdomin`; `abs` as substring | killed (1 each) |
| G5 -> G5b | no `quadratus` keyword | survived; pinned by a bare 'Quadratus' case; G5b killed (1) |
| S1, S2 | null type element read as "null"; `reps_only` not rep-based | killed (1 each) |
| C1 -> C1b | zero titration delta trims | survived; shared-row fixture; C1b killed (1) |
| C2 -> C2b | titration applies the full delta | survived; +2 / -3 case; C2b killed (1) |
| C3 to C6 | ledger weekly clause / session cap / time clause dropped; `add` spends no time | killed (3, 6, 3, 2) |
| C7 | deload trim writes `sets` | killed (2) |
| C8 | OFF 4-set minimum becomes 3 | killed (3) |
| C9 | week-2 gain ignores time | killed (2) |
| C10 | titration prices nothing | killed (1) |
| C11 | titration credits a not-budgeted row's sets | survived: EQUIVALENT (a not-budgeted row has an empty group set); the ternaries were removed in `08b1c4ea` |
| C12 -> C12b | week 4 without the floor of one | survived; one-set case; C12b killed (1) |
| C13 to C15 | trim below the bottom / below one set / grow past 5 sets | killed (3, 1, 1) |
| E1 to E5 | long effort never applies; uncapped; junk digit run parsed; sets unclamped; rest `int.parse` | killed (2, 1, 2, 1, 1) |
| E6 -> E6b | rest not clamped | survived; `99999 s` case; E6b killed (1) |
| E7, E8, E9 | name lookup removed; timed minutes not x60; shortenDay old sum | killed (2, 1, 1) |
| E10 -> E10b | alias match accepted | survived; alias test; E10b killed (1) |
| E11 -> E11b | failure not reported | survived; telemetry test; E11b killed (1) |
| E12 | name row not kept | killed (1) |
| GA1 | allocator never sets `debugLastStats` | killed (6, the gate file) |
| GA2 | a timed warm-up item priced +1 s | killed (6, the gate file) |

44 mutants: 35 killed first time, 1 did not compile (re-run killed), 8 survived (7 pinned and re-run killed, 1 equivalence removed). Zeros of the gate with NO B2 mutation that reddens them are stated, not hidden: the M6 precondition (bookkeeping over the plan's lead lifts, independent of the allocator), `forced` (`capForcedFirst` 0), empty days.

Earlier cycles of this batch (kept in the closure ledger): allocator 33 mutants (10 survivors: 2 equivalent, 8 killed by new reference fixtures), consumers 38, wiring 12/12, display 19/19, gate 10/10 (G10 first survived and exposed the missing lost-lifts zero).

## Unverified

- The literature citations in the `session_budget.dart` header (Pelland 2026, Remmert 2025): no source access from this session.
- The reviewers executed nothing; every execution claim above was re-run by the author (targeted tests, `flutter analyze lib/shared/repositories/plan_engine`, the generator golden over 998 personas, the ON-world gate over 1,847 runs).
- The full local `flutter test` and the pre-commit gate loop on the merged tree: run after the merge of `origin/main` (not part of this review).

## Tuning entry

- **2026-10-25** - blast-radius platform - 36 findings; 0 false_alarm; tuning: lens 6 (guard_without_its_mirror) gains one question for any new test of a guard: "which output changes if the guard is deleted?" - two guards in this batch (a zero delta, an alias rejection) had tests that stayed green with the guard deleted because the NET result was the same and only a side effect (`bumped`, the priced row) differed. Lens 8 gains "does the gate read the thing it checks, or a self-report of it?" (Finding 25: `debugLastStats` was both the fixture and the evidence).
