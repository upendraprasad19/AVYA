# Plan - Train header: hero label follows the week, no phase arc strip, no 0/6 bar (batch train-header-b2)

Date 2026-11-02. Tier L (touches `deload_evaluator.dart`, plan-engine flags, restore-free display code) so full pipeline:
plan review x2, B-pass, closure ledger, diagnose-doc. Execution mode: INLINE (decided at start, not switched).
Founder asks (2026-11-02): (1) the hero label follows the week: Baseline / Overreach / Peak / Deload, one shared
source for the Train hero card and the Home today card; (2) remove the "THIS PHASE" strip entirely with its kill
switches `disable_phase_arc` and `disable_deload_reason_line`; (3) remove the `0 / 6` bar in the Train plan header,
keep the hold-week sessions count.

## 1. Writers and readers (named before any change)

| Thing | Writer | Reader (today) |
|---|---|---|
| hero label word | none (constant map keyed by PHASE number) | `hero_cards.dart:81-87,121` (Train), `home_screen.dart:837-843,889,916` (Home) |
| `week_character` per schedule row | `workout_schedule_read_service.dart:304,325,579,600` and `regenerate_plan_planner.dart:376,455`, `hotel_workout_planner.dart:215` stamp it on every `schedule_*` row; `deload_evaluator.dart:222` rewrites a lifted week to `working` | `deload_evaluator.dart:96`, `day_swap_rules.dart:22` (preserved on swap) - NO display reader of the ROW field |
| `week_plans[i].week_character` (blob) | `models.dart:82` | `currentWaveCharacters()` (`workout_schedule_read_service.dart:1581`) -> `phaseArcProvider` AND `planWeekAndCharacterFor` (`:1567`, feeds the hotel stamp `hotel_workout_planner.dart:149/215`) |
| deload "why" `deload_reason_phase_<P>` | `deload_evaluator.dart:158` (local Hive only; not in any push/restore list - grep of `lib/core/services/sync*` and `supabase/` finds no reference) | `currentDeloadReason()` -> `deloadReasonProvider` -> `PhaseArcStrip` only |
| `0 / 6` + bar | `plan_header.dart` row 3 | same widget |

## 2. Design

### 2.1 Hero label (single shared source)
- NEW pure `lib/core/utils/week_mode_label.dart`: `String? weekModeLabel(Object? rawWeekCharacter)` (token mapper only, no service calls). Normalises once
  (`toString().toLowerCase().trim()`): `baseline`->`Baseline`, `overreach`->`Overreach`, `peak`->`Peak`,
  `deload`->`Deload`, `working`->`Working` (the lifted-deload state, written by `deload_evaluator.dart:222`; NOT one of the founder's four words, so it is named in the PR for a founder call: keep `Working`, or fold into Deload/Baseline),
  empty/null -> `null` (no word is invented), any other token -> capitalised raw token (a future vocabulary still renders).
- Source of the raw value = the SCHEDULE ROW of the day shown (`row['week_character']`), because the row is what the
  card already renders and needs no clamped `getCurrentWeekNumber()`. When the row carries NO stamp (template /
  `custom_template` rows, restored rows whose bundle lacks it) the fallback is the plan blob's character for that
  row's date: `WorkoutScheduleReadService.planWeekAndCharacterFor(date).character` (already the OI-166 date-keyed
  reader). Only when both are empty is the label null (run omitted; `today_workout_card.dart:199-204` already
  handles a null `workoutMode`). ONE service-aware resolver `WorkoutScheduleReadService.weekModeForRow(Map? row, DateTime? date)` (+ a
  `WorkoutScheduleService` forwarder) does row-then-blob and calls the pure mapper; BOTH Train constructors AND BOTH Home
  sites call it, so Train and Home cannot diverge. Fallback rules (round 3: the resolver does NOT use the clamped
  `planWeekAndCharacterFor`, which stays untouched because the hotel stamp writer and its tests pin the clamp): it reads
  `plan_start` and computes `rawWeekNumberFor(date, planStart)` itself and returns null when that is <1 or >4, when
  `date` is null, when `date` is before `plan_start` (explicit date comparison, `rawWeekNumberFor` truncates toward
  zero), when the row's `week` is >4, or when `is_hold == true` (a cloud-restored hold row has `week = 4+n` and no
  `is_hold`); otherwise it reads `currentWaveCharacters()[week-1]`. Callers pass the row's own `date` key (parsed), not
  the clock.
- Hold rows are COPIES of the phase's Peak week (`workout_schedule_write_service.dart:300-316`, `Map.from(raw)`,
  and the deload week row on every 4th hold, `isDeloadHold`), so they carry `peak` / `deload` verbatim. That is
  the honest label (a hold repeats Peak; every 4th is a deload) and it is pinned from a REAL `holdWeek()` row.
- A lifted deload week can be mixed (`deload_evaluator.dart:222` lifts only planned, clean, today-or-future rows): a
  past/shortened row keeps `deload` while its siblings say `working`. Each card shows its own row's word; pinned.
- Train: `WorkoutDayData` gets `final String? weekMode` filled from the row at the two constructors that read rows
  (`train_provider.dart:933` = the week list that `CurrentPlanData.todayWorkout` (`:482-505`) and `plan.getWeek` read, i.e.
  the NORMAL hero path; `:722` = `workoutDayForDate`, used by the hero only while holding and by Home's START; the `:955`
  placeholder constructor leaves it null). Both real constructors call `weekModeForRow`; `hero_cards.dart:_buildWorkoutHeroCard` renders `workout.weekMode` as the
  italic-gold run, and omits the run and its leading space when null. Home: `home_screen.dart` calls
  `WorkoutScheduleService.instance.weekModeForRow(schedule, <the row's date>)` at the done (889) and planned (916) cards; `workoutMode` is already
  nullable and `today_workout_card.dart:199-204` already omits it when null. The rest-day card keeps `weekLabel`
  (`Week N` / `Holding · Hn`) unchanged.
- Deleted: both `phaseMode` maps (`Relaxed/Focused/Capacity/Peak`). The `PHASE n` tag (`workoutTag`) stays.

### 2.2 Remove the strip chain
Delete `widgets/phase_arc_strip.dart`, `PhaseArcData`, `phaseArcProvider`, `deloadReasonProvider` (`train_provider.dart`),
the mount at `screen.dart:315` (+ comment lines 312-314), `PlanEngineFlags.phaseArcEnabled` and
`deloadReasonLineEnabled`, the two dev-panel toggles and their helpers (`dev_panel_screen.dart:362-400,569-575`), the
event `phase_arc_truncated_week_plans`. `currentWaveCharacters()` and its `WorkoutScheduleService` forwarder STAY: `planWeekAndCharacterFor` reads it (hotel
stamp writer + the new fallback). Only the doc comments naming the strip change.

### 2.3 Remove the reason chain (no write without a reader)
With the strip gone `deload_reason_phase_<P>` has zero readers, so the writer goes too: the stamp block in
`deload_evaluator.dart` (~148-175) and its `deload_reason.dart` import, `lib/core/utils/deload_reason.dart`,
`WorkoutScheduleReadService.deloadReasonKeyPrefix`, `currentDeloadReason`, `validatedDeloadReason`
(+ the `WorkoutScheduleService` forwarder). `deloadPhaseFromWeek4` STAYS (flag key + marker). Existing
`deload_reason_phase_*` keys on a tester's device are inert (never read, never synced) and are not migrated.
The evaluator's decision logic, its idempotency flag and every other write are untouched.

### 2.4 Plan header
`plan_header.dart` ROW 3 (the `0 / 6` text + `WardBar` + percent) is removed WHOLE for the normal week, including the `SizedBox(height: 10)` above it, the tallies loop, `progressPercent` and the `WardBar` import if unused. When
`holdStatus.isHolding` the row stays as TEXT ONLY: `'$completedDays / $totalWorkoutDays SESSIONS'` (no bar, no
percent). The tallies loop stays only for the hold branch (non-hold tallies are deleted as dead).

### 2.5 Kill-switch residue
Hive `configBox` keys `disable_phase_arc` / `disable_deload_reason_line` may exist on a dev device; with no reader
they are inert. The dev panel rows that set them are deleted. `docs/naming_conventions.md` has no rows for the two switches or the event
(grep: zero hits), so only the new util + field rows are appended.

## 3. Tests (every fix: regression test, mutation-checked)
- NEW `test/contracts/week_mode_label_test.dart`: pure mapping (5 tokens, padded/mixed case, empty/null -> null,
  unknown token), plus a source pin that BOTH `hero_cards.dart` and `home_screen.dart` call/consume the single
  source and that the `Relaxed|Focused|Capacity` maps are gone.
- NEW behavioral `test/contracts/train_hero_week_mode_behavioral_test.dart`: through BOTH seams (`workoutDayForDate`
  AND a built `currentPlanProvider` / `CurrentPlanData.todayWorkout`) for each token; a stamp-less template row falls
  back to the blob word; a stamp-less hold row -> null; a REAL `holdWeek()` row -> `Peak` (and `Deload` on the 4th);
  a mixed lifted week (past row `Deload`, later row `Working`); a stamp-less row at plan_start+28 WITHOUT `is_hold` -> null; a date one day before plan_start -> null; a null date -> null. Assert through `plan.getWeek(n)` rows (NOT `CurrentPlanData.todayWorkout`, which reads `istTodayStr()` and would go red on another day), dates pinned relative to a fixed `plan_start`.
- PRESENCE pins (strip-comments style of `hold_week_identity_behavioral_test.dart:411+`; the two cards are not pumpable): `weekModeForRow(` appears exactly twice in `home_screen.dart`, `workout.weekMode` in `hero_cards.dart`, no `phaseMode` / `Relaxed` / raw `['week_character']` at either label site. The `train_hero_week_mode` registry entry carries `presence_only: true` with that reason for those two call sites, and `behavioral_test_path` for the resolver + provider seams.
- MOVE the 5 `currentWaveCharacters` crash-safety tests of `phase_arc_reader_behavioral_test.dart:79-107` into
  `plan_week_for_date_behavioral_test.dart` (the function stays) before deleting the rest of that file.
- DELETE `phase_arc_reader_behavioral_test.dart`, `deload_reason_test.dart`, `deload_reason_staleness_behavioral_test.dart`
  and the two flag assertions in `readiness_flag_no_hive_default_test.dart:26-39` (a delete, not a repoint);
  EDIT `deload_eval_behavioral_test.dart` (the reason-key assertions at ~624-724 become "no `deload_reason_phase_*`
  key is written" + the decision assertions stay; the source-grep order pins for `await box.put(_kPlanKey, plan)` and
  `pushWorkoutPlanForSyncDomain()` (~751) must stay green after the stamp block is removed), `test/train/header_layout_test.dart` (`train_screen_compact_layout_test.dart` needs no edit) (NOT the home/nutrition namesakes; its "progress-bar row" test and reason text are rewritten, the `$completedDays / $totalWorkoutDays` source pin now targets the hold branch only), `tab_header_no_clip_test.dart` and `phase_relative_week_label_test.dart` checked, `hold_display_read_path_test.dart` swept (repoint: no THIS PHASE strip, no bar in the plan header, hold keeps the sessions text),
  `oi166_unit2_regen_content_cycling_behavioral_test.dart` and `plan_week_for_date_behavioral_test.dart` and
  `readiness_flag_no_hive_default_test.dart` where they reference the deleted symbols.
- Mutation matrix to run (each call site separately): the `weekMode` fill removed at `:933`; at `:722`; the Home call replaced by a raw row read; fallback dropped; hold guard dropped; label map entry removed; `working` mapped to Deload; hero ignoring `weekMode`; Home using a
  different source; evaluator stamp reinstated; hold branch dropped from the plan header; strip re-mounted.

## 4. Registry / docs
`docs/sot_registry.yaml`: delete by CONCEPT boundary (never by line range): `phase_arc_display` (10345-10426) and
`deload_decision_reason` (10513-10604); grep `triggered_deload_eval` and `deload_working_base_stash` for the reason key
and edit their prose; drop every `contract_test_path`/`behavioral_test_path` that cited a deleted test (Gate 42
resolves them); add `train_hero_week_mode` (writer = row stamps, reader = `weekModeLabel`, behavioral test above);
nested CLAUDE.md `train/CLAUDE.md:69`, `plan_engine/CLAUDE.md:76`, `docs/architecture/train-detail.md:50-57`,
`plan-engine-detail.md:51-68`, `docs/ship_dark_pending_review.yaml:569-616,882-904` (a "removed 2026-11-02, flag and feature deleted" note on both records, rows kept), `.claude/skills/debugging/SKILL.md:160-161` and `bug-classes.md:585,615` (the cited regression tests are deleted: annotate "test removed with the feature"), `sync_flags.dart:102` comment, `plan_engine_flags.dart:275-276`, `deload_evaluator.dart:33,71,154-157` (unused import + comments), old closure ledgers `phase-arc-flip` / `unitb-deload-reason` / `regen-wave-unit2` (verify Gate 40 does not resolve test paths), `open_issues.md` mentions (prose only), `plan_engine_flags.dart` doc blocks; `schedule_row_builder_gate_lib.dart:25` comment;
bug-class entry only if a class emerges. Closure ledger `docs/audit/train-header-b2.closure.yaml` (>=4 units).
Value-semantics sweep (4.1.5 point 3) of `test/` and `supabase/functions/` for `week_character`, `deload_reason`,
`phase_arc` before coding; EFs: grep shows none.

## 4b. Additional gate sweep (review round 2)
- `check_sot_registry_citations.dart` (cutoff 2026-08-01): five diagnose docs cite the deleted concepts
  (`2026-09-05-...-e3b7d1.md:36`, `2026-09-06-...-c5a8f3.md:32`, `2026-09-06-...-d9e1b4.md:28`,
  `2026-09-08-...-a9f3c7.md:32`, `2026-09-11-...-d7f3b2.md:149`): their `sot_registry_entry:` line becomes
  `Not applicable — concept removed 2026-11-02 (feature deleted)` (em dash: `isSentinelValue` cuts at it) (a recognised sentinel), then
  `validate_diagnose_doc.dart` is re-run on each.
- `check_sot_registry_parity.dart`: recompute EVERY surviving range in the registry for `workout_schedule_service.dart`, `train/screen.dart`, `plan_header.dart`, `hero_cards.dart`, `sync_flags.dart`, `train_provider.dart`,
  `workout_schedule_read_service.dart`, `home_screen.dart`, `plan_engine_flags.dart`, `deload_evaluator.dart` from
  HEAD ranges through the diff hunks, per commit.
- Analyzer-clean by construction: `deload_evaluator.dart` `liftedAny` becomes `await _liftWeekFour(wk4);`; drop the
  `error_telemetry.dart` import in `train_provider.dart` (its only use was the deleted provider) and the
  `phase_arc_strip.dart` import at `screen.dart:35`; `hero_cards.dart:80` `final plan = ref.read(currentPlanProvider);` (only used by the deleted `phaseMode` lookup: unused-local warning) is removed; `_buildPlanHeader`'s `weekDays` parameter is removed with the
  tallies (call site `screen.dart:167`); `WardBar` import checked. Dev panel: delete both `_btn` blocks whole (568-579)
  and the toggle methods (361-400). `plan-engine-detail.md` prose to ~78. Run `check_context_artifact_budget.dart`
  and `--record` if drifted. Plan header: the hold text row gets its own top gap (the pill branch keeps its own).

## 5. Out of scope / explicit decisions
- The row's `week_character` stays a plan-engine field; nothing here changes how it is stamped.
- The hero PHASE tag and the Train eyebrow `WK n OF m` stay.
- No migration, no Edge Function, no live DB action.

## 6. Sizing and commit structure (review round 1, rev 2)
One batch, two commits on one branch, one push/CI cycle: commit A = hero label + strip removal + plan header; commit B
= reason-chain removal (stamp, reader, text builder, tests, registry prose). B has no user-visible effect. Compile
order keeps the tree green at each commit. Pre-coding: run `dart run scripts/blast_radius_from_diff.dart` on
positional paths after writing a scratch copy of the new util (the registry fails open on a missing path), and the
value-semantics sweep named in section 4.
