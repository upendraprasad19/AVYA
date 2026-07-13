---
scope: train
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
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
| `exercise_logs_read_path` | `WorkoutWriteService.logExercise` | `workout_read_service.exerciseLogsForIstDate` (canonical READ — every other reader delegates here). Hive key: `exlog_${istDateStr(date)}_${exerciseName.hashCode.toUnsigned(32).toRadixString(16)}`. |
| `workout_log_edit_surface` | `edit_workout_log_sheet.dart` `save` — rewrites Hive row in place, recomputes `volume_kg`, chronologically rescans `is_pr`, invalidates full provider batch, fires `syncWorkoutData()` + `pushSnapshot()` | 4 entry points: receipt sheet Edit button, Home View Card, calendar day detail, Train expanded view. |
| `workout_completion_status` | `WorkoutWriteService.markCompleted` (the canonical completion writer — there is no `completeWorkout` method on `WorkoutWriteService`; `ActiveWorkoutNotifier.completeWorkout` in `train_provider` routes here). Also **auto-derived** from a coach `logSet` on a scheduled day via `tool_dispatcher._maybeCompleteScheduledDay → markCompleted` (replaces the removed `markWorkoutComplete` tool — ADR-0012). | `train_screen` completed-day expanded view + home Today's Workout Card. |
| `scheduled_workouts_mutations` | `WorkoutScheduleService.upsertScheduled` → routes through `WorkoutWriteService` (APK Test #16.2 / E retrofit — 9 callsites migrated). Generation now stamps `'phase'` on every `schedule_*` row (F-B 7d2e6b). | `train_screen` week renderer. |
| `week_completion_check` | `WorkoutWriteService.markCompleted` sets `schedule_*` `status='completed'` | `WorkoutScheduleReadService.completedWeekNumbers` → `week_selector._WeekChip` ✓ (any completed day that week — current AND past phases; Obs 3a 2c9f7a). Past chips use `_PastPhase.hasCompletedDayInWeek`. `pastPhaseBlocks`/`phaseForDate` group via the pure `bucketPastRows` (phase-identity when all rows stamped, else 28-day fallback — F-B 7d2e6b). |
| `workout_templates` | `WorkoutWriteService.saveTemplate` / `deleteTemplate` (PRO) | `template_builder_screen`, `train_screen` template picker. |
| `exercise_personal_records` | **DERIVED — no dedicated writer.** `WorkoutWriteService.logExercise` → `_rescanPrFor` stamps `is_pr` on `exlog_*` rows (strict `>`); `WorkoutRepository.loadAllExercisePRs` (workout_repository.dart:632) computes best-per-set from `exlog_*`. The AI `logPR` tool was **removed 2026-05-31** (derive-only surface, ADR-0012) — PRs are never AI-asserted, only computed from logged sets. | home `PRSnapshot`, profile `rank_ladder` (PR-derived rank promotions). |
| `custom_exercises_mutations` | `WorkoutWriteService.upsertCustomExercise` | `swap_picker_sheet`, exercise pickers. |
| `hive_field_name_exlog` | `WorkoutWriteService` field names: `exercise_name`, `set_number`, `reps_completed`, `weight_kg`, `volume_kg`, `is_pr`, `logging_type`, `workout_log_id`, `duration_seconds`, `distance_km` | `EditLogExerciseRow.fromLog` accepts dual names (canonical `sets[]` OR legacy `sets_detail`; per-set `duration_sec` OR `duration_seconds`) for restore back-compat. |
| `exercise_coaching_content` (W3.6) | **Read-only display** — the seeded library (`exerciseBox`) carries `coaching_cues`/`common_mistakes` (arrays, 258/258), `breathing_cue` (string, 258/258), `warmup_protocol` (string, 213/258). `ExerciseRepository.getByExactName(name)` fetches the full row by EXACT name (NOT `search`, which is substring — "Push Up"→"Pike Push Up"). | `CoachingContentPanel` (`active_workout/coaching_content_panel.dart`, a `part of screen.dart`) — collapsible/collapsed-by-default "FORM & CUES" panel in the expanded exercise card. Resolves the map in `initState`/`didUpdateWidget` (the card rebuilds ~1×/sec from the workout timer — never in `build()`); hides empty sections (null-or-empty-STRING for `warmup_protocol`); casts arrays via `List<dynamic>`→`toString()` (never `as List<String>` — red-screens). Null map (swap/custom) → renders nothing. FREE. |
| `session_detraining_cut` (⑦b) | **Session-only, ship-dark** (`enable_session_detraining_cut`, default OFF). `ActiveWorkoutNotifier.startWorkout` (`train_provider.dart:907`) sets `ActiveWorkoutData.sessionDetrainingFactor = detrainingFactorForGap(getDaysSinceLastWorkout())`, **threaded through `copyWith`** (round-2 F1 — else the 1×/sec elapsed-timer `copyWith(elapsedSeconds:)` reverts it to 1.0 within a frame). Band table shared with ⑦a via `lib/core/utils/detraining.dart` (one copy). | `exercise_card._initControllers` scales ONLY the last-logged-weight prefill (`:81-86`) — never the ⑦a-decayed prescribed `exercise.weight` (disjoint, no double-count); `_OverloadIndicator` compares vs the cut target `last×factor` (unedited reduced prefill reads →, not red↓); the "TRY:" hint is suppressed while cut-active ("LAST:" kept); `screen.dart` shows a non-shaming resume banner when `factor < 1.0`. Behavioral: `session_detraining_cut_test.dart`. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Warm-up sets counted in completedSets | `completedSets` getter filters out `warmUpSets` keys. Exercise name matching uses exact-first, fuzzy only for names >= 6 chars. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| WarmupCooldownSection RangeError | `didUpdateWidget` resets `_checked` list when `widget.exercises.length` changes. Always guard list length on rebuild. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Phase 2-12 invisible to free users | Train screen previously capped the week selector at 4 weeks — free users couldn't see what they were paying for. APK Test #2 / Q7 extends the selector to 12 weeks (3 phases) with PHASE I / II (PRO) / III (PRO) headers + lock glyph on weeks 5–12 for free users. Tap any locked week → `/train/preview?phase=II&week=5&day=1` renders a real workout via `previewPlanProvider` (calls `PlanGenerator.instance.generateV4()` with the user's actual profile — goal/equipment/days/experience). State-aware banner: "Complete Phase I to unlock Phase II — your AI coach generates the next 4 weeks the moment you finish." Free users see UPGRADE TO PRO bottom CTA + cross-link to `/train/roadmap`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Receipt shows wrong exercises after a multi-session day | `WorkoutReceiptData.fromExerciseLogs` filters by `workout_log_id` when present. Legacy rows (no `workout_log_id`) always pass through. APK Test #16.1 / Agent A added `workoutBox 'date == dateKey'` fallback for rogue-restore writers. | `workout_receipt_rendering` SoT |
| Edit log saves but volume / PR flag doesn't update | `EditWorkoutLogSheet.save` MUST: (1) rewrite the Hive map in place, (2) recompute `volume_kg = weight_kg × reps_completed`, (3) chronologically rescan `is_pr`, (4) invalidate the full provider batch, (5) fire `syncWorkoutData()` + `pushSnapshot()`. Skipping any step = stale UI. | `workout_log_edit_surface` SoT |
| Rogue `exlog_*` key formula on restore | APK Test #16.1 — 3 restore-path writers used wrong hash formula; `ExlogKeyMigrator v8` rewrites them on next mount. Gate 17 source-grep test pins the canonical formula. | `feedback_writer_reader_field_drift_recurring.md` + `exlog_key_canonical_test.dart` |
| Phase Unlock card surfaces from Monday of Week 4 | Theme E (APK Test #16.2 / 0e7714) — gate is `plan.currentWeek != 4 \|\| DateTime.now().weekday < DateTime.thursday`. Surfaces from Thursday of Phase Week 4 (LOCAL weekday, not IST — UI presence is perceptual, not calendar). Founder expectation 2026-05-21: "should open up on thursday of the last week". 4-day runway (Thu-Sun) for completing + tapping unlock. The COPY gate (locked "PHASE 2 AVAILABLE" vs unlocked "PHASE 1 COMPLETE!") stays driven by `completionRate >= AppConstants.phaseUnlockCompletionRate`. | `test/contracts/phase_unlock_card_thursday_gate_test.dart` |
| Past completed phases invisible after unlock | Theme K (APK Test #16.2 / b9d2a8) — `lib/features/train/widgets/week_selector.dart` walks `workoutBox` for `schedule_*` keys with `date < planStart`, buckets by 28-day phases, renders one `_PastPhaseGroup` per past phase LEFT of the current phase. Past chips use textDim border + `✓` check_circle glyph when ≥1 day in that week has `status=='completed'`. Tap → modal `_PastWeekSheet` showing the 7-day breakdown (read-only). Depends on Theme H (`b0baa5`) which protects past `schedule_*` entries from planGenerator overwrite — without that fix this scroll-back would show clobbered data. | `test/contracts/week_selector_past_phases_test.dart` |
| Graduation Phase 2 preview hardcoded `5 DAYS/WEEK` + static day labels | Theme J (APK Test #16.2 / ea1059) — `lib/features/train/screens/graduation_screen.dart:294` dry-runs `PlanGenerator.instance.generateV4` with the user's actual `profile['days_per_week']` + `nextPhase` derived from progress. Renders `phase.weekPlans[0].workoutDays` for the day strip. Pure call — no Hive writes, no telemetry. Failure path emits `graduation_phase2_preview_failed` + falls back to a single descriptive line. | `test/contracts/graduation_phase2_preview_dynamic_test.dart` |

## Tests pinning the rules here

- `test/contracts/exercise_logs_read_path_writer_to_reader_test.dart`
- `test/contracts/exlog_key_canonical_test.dart`
- `test/contracts/exlog_migrator_handles_rogue_shapes_test.dart`
- `test/contracts/edit_log_field_normalization_test.dart`
- `test/contracts/edit_log_id_injection_test.dart`
- `test/contracts/edit_workout_log_sets_field_contract_test.dart`
- `test/contracts/exercise_personal_records_writer_to_reader_test.dart`
- `test/contracts/custom_exercise_writer_to_reader_test.dart`
- `test/contracts/workout_completion_status_test.dart`
- `test/contracts/workout_templates_writer_to_reader_test.dart`
- `test/contracts/duration_seconds_aggregate_populated_test.dart`
- `test/contracts/coaching_content_test.dart` (W3.6 — `getByExactName` exact-not-substring + library coaching-field population).

## See also

- `lib/shared/repositories/plan_engine/CLAUDE.md` — plan generator V4 + cascade.
- `lib/features/home/CLAUDE.md` — Today's Workout Card + receipt entry point.
- `lib/core/services/CLAUDE.md` — `WorkoutWriteService` + sync fan-out.
- `docs/reference/exercise-library.md` — exercise_library Hive box (movement patterns, suitable_for, equipment_needed).
