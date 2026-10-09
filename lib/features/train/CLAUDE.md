---
scope: train
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-08-30
status: active
---

# Train (Active Workout + Templates) — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/train/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/features/train/` owns the 🏋️ Train tab — the active workout flow, phase
plan, week selector (12 weeks / 3 phases), exercise swap, template builder, and
the receipt + edit log sheets that complete the post-workout loop.

Screens:

- `train_screen.dart` — phase plan + week selector + today's workout + completed-day expanded view.
- `active_workout_screen.dart` — live logging UI driven by `logging_type` (see below).
- `template_builder_screen.dart` — user-built workout template (PRO).
- `roadmap_screen.dart` — 12-week phase roadmap (added Test #2).
- `preview_screen.dart` — locked-week real workout preview (Test #2 / Q7).

Widgets: `workout_receipt_card.dart` (canonical reader for receipts),
`workout_receipt_sheet.dart`, `edit_workout_log_sheet.dart` (single edit
surface — 4 entry points route through it), `warmup_cooldown_section.dart`,
`exercise_set_row.dart`, `swap_picker_sheet.dart`.

Service layer: `WorkoutWriteService` (single writer for `exlog_*` + `wlog_*`
Hive rows + cloud) + `WorkoutScheduleService` (routes scheduled-workout writes
through the WriteService — APK Test #16.2 / E).

## Single-source-of-truth contracts

### Logging types (drives Active Workout UI)

| logging_type | UI Shows |
|---|---|
| `weight_reps` | Weight (kg) + Reps + Sets |
| `bodyweight_reps` | Reps + Sets (no weight input) |
| `weighted_bodyweight` | Added Weight + Reps + Sets |
| `timed` | Sets + Duration (seconds) + rest timer |
| `cardio` | Duration (min) + Distance (km) |
| `distance` | Distance + load |

### SoT concepts owned here

| Concept | Writer | Reader |
|---|---|---|
| `workout_receipt_rendering` | `WorkoutWriteService.logExercise` (stamps `workout_log_id` on every `exlog_*` row — Test #12 / Task A-3) | `workout_receipt_card.dart` `WorkoutReceiptData.fromExerciseLogs` (dedupes by name, sums sets, max weight, scopes by `workout_log_id`; resolves the PHASE label via `WorkoutScheduleReadService.phaseForDate(date)` — Obs 1 6f1a2c, was a hardcoded `phase = 1`). |
| `exercise_logs_read_path` | `WorkoutWriteService.logExercise` | `workout_read_service.exerciseLogsForIstDate` (canonical READ — every other reader delegates here). Hive key: `WorkoutWriteService.exlogKey(date, exerciseName)` = `exlog_${istDateStr(date)}_${first 8 hex of UUID-v5(exerciseName)}` (H-16 — NOT the dead `hashCode` scheme). |
| `workout_log_edit_surface` | `edit_workout_log_sheet.dart` `save` — rewrites Hive row in place, recomputes `volume_kg`, chronologically rescans `is_pr`, invalidates full provider batch, fires `syncWorkoutData()` + `pushSnapshot()` | 4 entry points: receipt sheet Edit button, Home View Card, calendar day detail, Train expanded view. |
| `workout_completion_status` | `WorkoutWriteService.markCompleted` (the canonical completion writer — there is no `completeWorkout` method on `WorkoutWriteService`; `ActiveWorkoutNotifier.completeWorkout` in `train_provider` routes here). Also **auto-derived** from a coach `logSet` on a scheduled day via `tool_dispatcher._maybeCompleteScheduledDay → markCompleted` (replaces the removed `markWorkoutComplete` tool — ADR-0012). | `train_screen` completed-day expanded view + home Today's Workout Card. |
| `scheduled_workouts_mutations` | `WorkoutScheduleService.upsertScheduled` → routes through `WorkoutWriteService` (APK Test #16.2 / E retrofit — 9 callsites migrated). Generation now stamps `'phase'` on every `schedule_*` row (F-B 7d2e6b). | `train_screen` week renderer. |
| `week_completion_check` | `WorkoutWriteService.markCompleted` sets `schedule_*` `status='completed'` | `WorkoutScheduleReadService.completedWeekNumbers` → `week_selector._WeekChip` ✓ (any completed day that week — current AND past phases; Obs 3a 2c9f7a). Past chips use `_PastPhase.hasCompletedDayInWeek`. `pastPhaseBlocks`/`phaseForDate` group via the pure `bucketPastRows` (phase-identity when all rows stamped, else 28-day fallback — F-B 7d2e6b). |
| `workout_templates` | `WorkoutWriteService.upsertTemplate` / `deleteTemplate` (PRO). OI-252: identity is `newTemplateKey()`'s client-minted UUID, minted once at create; delete is a rename-on-delete tombstone (migration 145), not a row drop. | `template_builder_screen`, `train_screen` template picker. |
| `exercise_personal_records` | **DERIVED — no dedicated writer.** `WorkoutWriteService.logExercise` → `_rescanPrFor` stamps `is_pr` on `exlog_*` rows (strict `>`); `WorkoutRepository.loadAllExercisePRs` (workout_repository.dart:632) computes best-per-set from `exlog_*`. The AI `logPR` tool was **removed 2026-05-31** (derive-only surface, ADR-0012) — PRs are never AI-asserted, only computed from logged sets. | home `PRSnapshot`, profile `rank_ladder` (PR-derived rank promotions). |
| `custom_exercises_mutations` | `WorkoutWriteService.upsertCustomExercise`. **CREATE has one path: `WorkoutRepository.createCustomExercise`** — the AI tool AND `CreateCustomExerciseSheet` both call it (diagnose `d5c2e8`; the sheet used a raw `customBox.put`, skipping the duplicate guard, the 60-char cap and the writer stamps). Never put a custom row from a widget. | `swap_picker_sheet`, exercise pickers. |
| `hive_field_name_exlog` | **TWO writers, DIFFERENT field subsets (d4e7c2).** `WorkoutWriteService.logExercise`: `exercise_name`, `set_number`, `reps_completed`, `weight_kg`, `volume_kg`, `is_pr`, `logging_type`, `workout_log_id`, `sets[]`, `distance_km`, sticky Hive-LOCAL `exercise_id` — **no top-level `duration_seconds`** (that is on `wlog_*`). The **restore** writer (`sync/sync_workout.dart`) emits `set_number` + **top-level `duration_seconds`**, never `sets_completed`, and `sets[]` ONLY when the `workout_log_sets` join is non-empty. | ⚠ **Never hand-roll the aggregate read — delegate to `WorkoutReadService.aggregateSetCount` / `aggregateDurationSeconds` / `hasAggregateSetCount`** (seven readers each got it wrong for restored rows; treat seven as a floor). Behavioral `exlog_aggregate_read_behavioral_test.dart`; gate `no_top_level_duration_seconds_reads_test.dart`. Best single set → `bestPerSetDuration`; total → `aggregateDurationSeconds`. History: `docs/architecture/train-detail.md`. |
| `exercise_coaching_content` (W3.6) | **Read-only display** — seeded library (`exerciseBox`) carries `coaching_cues`/`common_mistakes` (arrays), `breathing_cue`, `warmup_protocol`. `ExerciseRepository.getByExactName(name)` fetches by EXACT name (NOT substring `search`). | `CoachingContentPanel` (collapsed-by-default "FORM & CUES"). Resolve the map in `initState`/`didUpdateWidget`, never in `build()` (card rebuilds ~1×/sec); hide empty sections; cast arrays via `List<dynamic>`→`toString()` (never `as List<String>`). Null map → nothing. FREE. |
| `hold_display_read_path` | Display half of the free-tier hold (writer `holdWeek()` stamps `is_hold` + `hold_ordinal`). `WorkoutScheduleReadService.holdWeeks()` / `holdOrdinalForDate()` / `holdWeekSessionProgress()` + pure `isDeloadHold(n) = n % 4 == 0` (never persisted). | `holdStatusProvider` is the **single branch point** (`HoldStatusData.empty` when `enable_hold_weeks` is OFF). ⚠ **Hold chips must NEVER drive `selectedWeekProvider`** (hold rows are `week = 4 + ordinal`; `CurrentPlanData.weeks` stops at 4). Behavioral: `hold_display_read_path_test.dart`. |
| `hold_week_identity` (OI-60) | `WorkoutScheduleReadService.weekIdentity()` → `WeekIdentity` = `weekInPhase` **XOR** `holdOrdinal` (never a projected `4 + ordinal`, `c9f4a2`); `getCurrentWeekNumber()` clamps to `[1,4]`. `activeHoldWeeks()` / `activeHoldOrdinalFor()` are the ONE read-side `enable_hold_weeks` gate. | `weekIdentityProvider` (widgets; must `ref.watch`, never call the singleton from `build()`); labels via pure formatters in `lib/core/utils/hold_week_labels.dart`. Do NOT branch inputs where the clamped 4 is HONEST (journey `/4` bar, roadmap %). Behavioral: `hold_week_identity_behavioral_test.dart`. |
| `readiness_checkin` (⑥ W2.3) | **LIVE** (kill-switch `disable_readiness`). `readiness_sheet.dart` resolves sleep via `HealthReadService.sleepHoursForDate` → `sleepAxisFromHours` (>6.5h→0, 4.5-6.5→1, <4.5→2); null → ask, with a nudge that calls `syncSleepOnly()`, **never `syncToHive()`** (steps+weight dialog). | `train_provider.startWorkout`: RED drops ONE isolation set (`_applyReadinessSetDrop`) and cuts compound PREFILL (`_readinessLoadFactor`) via `effectiveLoadFactor` — SHARED with ⑦b, never delete. Feeds `deload_evaluator`. Behavioral: `readiness_checkin_behavioral_test.dart`, `readiness_sleep_axis_test.dart`. |
| `phase_arc_display` (⑥ W3.2) | **LIVE** (kill-switch `disable_phase_arc`). **Read-only, no writer.** Source: `current_plan` blob's `week_plans[i]['week_character']` (`periodization_engine.dart`; `deload_evaluator.dart` rewrites it to `working`). Every regen writer SPLICES a clamped 4-node window via `contentFlavorIndex` (`(w-1) % 4`); every phase-layout writer is bounded by the stored `plan_end` (OI-189, `sweepNonCompletedRowsPastPlanEnd`); every writer that MOVES the window on an existing account pushes `plan_json` immediately (never reinstall/boot/repair callers). Behavioral: `oi166_unit2_regen_content_cycling_behavioral_test.dart`. | `phaseArcProvider` → `PhaseArcStrip`. Vocabulary is FIVE tokens (`working` included). Provider requires `waves.length >= 4` (renders first 4); 1-3 emits `phase_arc_truncated_week_plans`, 0 stays SILENT. Deload-reason line LIVE (`disable_deload_reason_line`): `currentDeloadReason()` returns text ONLY while the stamped `week_character` still equals week 4's. Reads `getCurrentWeekNumber()` DIRECTLY (make hold-aware before OI-60 flips `enable_hold_weeks`). Behavioral: `phase_arc_reader_behavioral_test.dart`. |
| `session_detraining_cut` (⑦b) | **Session-only. LIVE** (`disable_session_detraining_cut`). `startWorkout` sets `sessionDetrainingFactor = detrainingFactorForGap(...)`, **threaded through `copyWith`** (else the 1×/sec timer reverts it). Bands shared with ⑦a in `lib/core/utils/detraining.dart`. | `exercise_card._initControllers` scales ONLY the last-logged-weight prefill (never the ⑦a-decayed prescribed weight); `screen.dart` resume banner when `factor < 1.0`. Behavioral: `session_detraining_cut_test.dart`. |
| `duration_controller_seeding_leak` (e8f95e) | `exercise_card.dart` `_initControllers` — `_durationControllers` must NOT be seeded with `repsValue` (third instance of the "reps renders as seconds" class); `_captureSetValues` parses it unconditionally, and a phantom duration mis-resolves a CUSTOM exercise to `'timed'` in `_resolveLoggingType`. | `train_provider.dart` `completeWorkout` → `workout_write_service.dart` `logExercise` aggregate fields (read from POST-normalization `cleanedSets`). Diagnose `2026-09-28-duration-controller-seeding-leak-e8f95e.md`. |
| `active_workout_resume_guard` (`e8f4a1`) | **Session-only.** `ActiveWorkoutData.hasInProgressSession` (derived getter) gates the ONE writer every START button shares, `ActiveWorkoutNotifier.startWorkout` (unconditional reset). `beginWorkoutWithReadiness` awaits `showResumeOrDiscardGuard`: RESUME leaves the session; DISCARD runs `startWorkout()` + `ActiveWorkoutPersistence.clearState()`. | `hero_cards.dart`, `planned_expansion.dart`, `today_workout_card.dart` (label → `RESUME`). Behavioral: `active_workout_resume_guard_behavioral_test.dart`. |
| `day_swap_engine` | **`SwapService.swapDays` (`lib/core/services/swap_service.dart`) is the ONE entry point** (Train drag, ⇅ picker, Home long-press, coach `swapWorkoutDays`); every check re-runs at CONFIRM inside `WorkoutWriteService.swapScheduledDays`'s two-date lock. Counted (`DaySwapAllowance.recordSwap`) only after the write succeeds. Kill switch `disable_day_swap_train_ui` hides NEW-swap affordances on Train only. SoT rows `day_swap_engine`, `day_swap_allowance`, `schedule_arrangement_stamp`: `lib/core/services/CLAUDE.md`. | `day_swap_provider.dart`, `week_rows.dart`, `SwapPickerSheet` / `SwapConfirmSheet`. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Warm-up sets counted in completedSets | `completedSets` getter filters out `warmUpSets` keys. Exercise name matching uses exact-first, fuzzy only for names >= 6 chars. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| WarmupCooldownSection RangeError | `didUpdateWidget` resets `_checked` list when `widget.exercises.length` changes. Always guard list length on rebuild. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Phase 2-12 invisible to free users | Week selector spans 12 weeks (3 phases), PHASE I / II (PRO) / III (PRO) headers, lock glyph on weeks 5–12 for free users; tapping a locked week → `/train/preview?phase=II&week=5&day=1` (`previewPlanProvider` → `PlanGenerator.instance.generateV4()` with the user's real profile). Free users see UPGRADE TO PRO + cross-link to `/train/roadmap`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Receipt shows wrong exercises after a multi-session day | `WorkoutReceiptData.fromExerciseLogs` filters by `workout_log_id` when present. Legacy rows (no `workout_log_id`) always pass through. APK Test #16.1 / Agent A added `workoutBox 'date == dateKey'` fallback for rogue-restore writers. | `workout_receipt_rendering` SoT |
| Edit log saves but volume / PR flag doesn't update | `EditWorkoutLogSheet.save` MUST: (1) rewrite the Hive map in place, (2) recompute `volume_kg = weight_kg × reps_completed`, (3) chronologically rescan `is_pr`, (4) invalidate the full provider batch, (5) fire `syncWorkoutData()` + `pushSnapshot()`. Skipping any step = stale UI. | `workout_log_edit_surface` SoT |
| Rogue `exlog_*` key formula on restore | APK Test #16.1 — 3 restore-path writers used wrong hash formula; `ExlogKeyMigrator v8` rewrites them on next mount. Gate 17 source-grep test pins the canonical formula. | `feedback_writer_reader_field_drift_recurring.md` + `exlog_key_canonical_test.dart` |
| Phase Unlock card surfaces from Monday of Week 4 | Gate is `plan.currentWeek != 4 \|\| DateTime.now().weekday < DateTime.thursday` — surfaces from Thursday of Phase Week 4 (LOCAL weekday, not IST). COPY gate stays on `completionRate >= AppConstants.phaseUnlockCompletionRate`. | `test/contracts/phase_unlock_card_thursday_gate_test.dart` |
| Past completed phases invisible after unlock | `week_selector.dart` renders `_PastPhaseGroup`s via `pastPhaseBlocksForDisplay(currentPhase)`, NOT the strict `pastPhaseBlocks()`; `PhaseProgressReconciler` must keep the STRICT set (over-advance of `current_phase` is unrecoverable). | `test/contracts/week_selector_past_phases_test.dart` |
| Graduation Phase 2 preview hardcoded `5 DAYS/WEEK` | `Phase2PreviewCard` dry-runs `PlanGenerator.instance.generateV4` with the real profile (pure; failure emits `graduation_phase2_preview_failed`). | `test/contracts/graduation_phase2_preview_dynamic_test.dart` |
| Graduation unlock logic living in the screen | The generate + `commitPhaseAdvance` + repeat-nudge block is **`runGraduationPhaseAdvance` in `lib/shared/services/pro_phase_advance.dart`**; the screen is UI only (pre-lock abort and `ref.invalidate(phaseRepeatNudgeProvider)` stay there). Returns a 4-case outcome enum. | `test/contracts/pro_phase_advance_behavioral_test.dart` |
| A PRO user paging ahead into a not-yet-generated future PHASE sees a generic empty state | `isFutureUngeneratedPhase` + `futurePhaseUnlockCopy` (`lib/core/utils/hold_week_labels.dart`) in `empty_states.dart`'s `_buildEmptyWeek`. Diagnose `c4f9a1`. | `hold_week_labels_test.dart`, `train_phase_lock_empty_state_test.dart` |
| Deployment eyebrow hardcoded to "DEPLOYMENT 01" | Use `deploymentEyebrowLabel` (`hold_week_labels.dart`), driven by the same `plan.phase` read as `WeekSelector`. Diagnose `b7f1c8`. | `hold_week_labels_test.dart`, `past_phase_display_recovery_behavioral_test.dart` |

| An input controller seeded with a copy-pasted value from an unrelated field | If a `TextEditingController` has no prefill source (check `LastPerformanceData`), leave it EMPTY — never seed it from a sibling controller. Code that parses every controller unconditionally lets a phantom value reach type-resolution logic. | `docs/diagnoses/2026-09-28-duration-controller-seeding-leak-e8f95e.md` |

## Tests pinning the rules here

- `test/contracts/`: `exercise_logs_read_path_writer_to_reader_test`, `exlog_key_canonical_test`, `exlog_migrator_handles_rogue_shapes_test`, `edit_log_field_normalization_test`, `edit_log_id_injection_test`, `edit_workout_log_sets_field_contract_test`, `exercise_personal_records_writer_to_reader_test`, `custom_exercise_writer_to_reader_test`, `workout_completion_status_test`, `workout_templates_writer_to_reader_test`, `duration_seconds_aggregate_populated_test`, `coaching_content_test`, `hold_week_labels_test` (also `phaseRoman`/`isFutureUngeneratedPhase`/`futurePhaseUnlockCopy`), `train_phase_lock_empty_state_test`.
- `test/train/duration_controller_seeding_writer_to_reader_test.dart` (source-grep, presence only) + `test/workout_write_service/aggregate_reflects_cleaned_sets_test.dart` (BEHAVIORAL, canonical `behavioral_test_path` for `duration_controller_seeding_leak`).

## See also

- `lib/shared/repositories/plan_engine/CLAUDE.md` — plan generator V4 + cascade.
- `lib/features/home/CLAUDE.md` — Today's Workout Card + receipt entry point.
- `lib/core/services/CLAUDE.md` — `WorkoutWriteService` + sync fan-out.
- `docs/architecture/train-detail.md` — moved-out history, provenance and full test inventory for this file.
- `docs/reference/exercise-library.md` — exercise_library Hive box (movement patterns, suitable_for, equipment_needed).
