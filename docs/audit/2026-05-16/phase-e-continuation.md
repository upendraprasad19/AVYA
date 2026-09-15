# Phase E · Continuation Memo — 2026-05-16

This session completed Phase A → D + Phase E.1 + E.2. Remaining 20 Phase E tasks listed below. Each is self-contained enough for a fresh session to pick up.

**Branch:** `audit/2026-05-16-comprehensive` (uncommitted at session end)
**Plan file:** `C:\Users\upend\.claude\plans\i-want-to-do-moonlit-fiddle.md`
**Findings doc:** `docs/audit/2026-05-16/findings-verified.md`
**Per-agent reports:** `docs/audit/2026-05-16/findings-agent-{1..7}.md`
**Verification log:** `docs/audit/2026-05-16/phase-c-verification-log.md`

## Founder-approved NEEDS_DECISIONs (Phase D)

1. **WorkoutScheduleService fix:** refactor through `WorkoutWriteService.upsertScheduled`
2. **HealthWriteService:** build it now (mirror Workout/Nutrition pattern)
3. **Legacy widgets:** migrate `RankChip` + `RankInsignia` callsites + delete legacy
4. **Dead code:** delete `featureActiveWorkoutMode`, `featureVoiceNotes`, `featureDietPlanPdf`, `UserRepository.softDeleteAccount`, `MySubmissionsScreen` route

## Completed this session

### E.1 — coach_notes upward sync fix ✅
- File: `lib/core/services/sync/sync_coach.dart` — added 7 lines after `body_part_priorities` projection.
- Test: `test/contracts/coach_notes_upward_sync_test.dart` — passes.
- Bug shape: cloud column `coach_notes` was 100% NULL across all 4 users; Hive key `coaching_notes` never projected upward. AI memory lost on every reinstall.
- closes-diagnose: 2026-05-16-coach-notes-upward-sync (diagnose-doc still needs writing per rule 22)

### E.2 — appVersion bump + parity gate ✅
- `pubspec.yaml`: `1.0.0+26` → `1.0.0+27`
- `lib/core/constants/app_constants.dart`: `1.0.0+23` → `1.0.0+27` (was 4 versions behind)
- New gate: `scripts/check_app_version_matches_pubspec.dart` — exits 0 on parity, 1 on drift
- Run-check: `dart run scripts/check_app_version_matches_pubspec.dart` → "OK — both at 1.0.0+27"

## Remaining Phase E tasks (priority order)

### E.3 — `terms_accepted_at` sign-up write (F3-1.2 DPDP gap)
- **File:** `lib/features/auth/screens/sign_in_screen.dart` (sign-up branch where checkbox is ticked)
- **Fix:** On `SIGN UP` button tap with checkbox checked, before calling Supabase signUp, write to userBox:
```dart
await HiveService.instance.userBox.put('terms_accepted_at', DateTime.now().toIso8601String());
await HiveService.instance.userBox.put('terms_version', AppConstants.termsVersion);
```
- Existing upstream `_ensureLocalUser` projection (`auth_provider.dart:508-516`) will pick up automatically.
- Regression test: `test/contracts/terms_signup_writes_test.dart` — source-grep that sign_in_screen contains the write before signUp call.
- diagnose-doc: write at `docs/diagnoses/2026-05-16-terms-accepted-at-dpdp.md`

### E.4 — `workout_schedule_completions.duration_seconds` join fix (F3-1.3)
- **File:** `lib/core/services/sync/sync_workout.dart:424-432`
- **Bug:** Writer projects `entry['duration_seconds']` from `schedule_<date>` Hive entry, but that field doesn't exist there. It lives on `wlog_<ms>`.
- **Fix:** Before projecting, look up `wlog_<date>` from workoutBox and pull `duration_seconds`:
```dart
final wlogKey = 'wlog_$dateStr';
final wlog = workoutBox.get(wlogKey) as Map?;
final duration = (wlog?['duration_seconds'] as num?)?.toInt();
if (duration != null) payload['duration_seconds'] = duration;
```
- Test: extend `test/contracts/scheduled_workouts_mutations_writer_to_reader_test.dart` to assert duration_seconds is populated.

### E.5 — AI coach drift bundle (F6-1 + F6-2 + F6-3 + F6-4)
Four sub-tasks:
- **F6-2 logPR through WriteService:** `lib/features/ai_coach/services/tool_dispatcher.dart:349`. Replace `WorkoutRepository.instance.logSetWithPrRescan(...)` call with `WorkoutWriteService.instance.logExercise(date: date, exerciseName: name, sets: [ExerciseSet(weightKg: weightKg, reps: reps, loggedAtMs: DateTime.now().millisecondsSinceEpoch)])`. Move PR rescan inside WriteService.
- **F6-3 ai-proxy await UPDATE:** `supabase/functions/ai-proxy/index.ts:319`. Change `supabaseClient.from(...).update(...).then(...)` to `await supabaseClient.from(...).update(...)`. Promote any error to telemetry. Deploy v66 via `.claude/deploy_via_api.js`.
- **F6-4 cross-channel dedup:** `lib/core/services/sync/sync_coach.dart:67` `_syncCoachInteractions`. Before each orphan upsert, SELECT `ai_coach_interactions WHERE user_id AND user_message AND channel='app' AND created_at > now() - interval '5 minutes'`. Skip if hit. Alternative: deprecate the orphan path entirely (comment at L60-66 acknowledges they're rare; 8 in 5 days proves otherwise).
- **F6-1 docs:** Update CLAUDE.md §11 to say "24 tools across Workout (8), Progress (5), Nutrition (5), Plan (5), Exercise (1)" + tier split "11 FREE / 13 PRO".
- One-shot SQL: `UPDATE ai_coach_interactions SET model_used='unknown_legacy' WHERE model_used='pending' AND ai_response IS NOT NULL AND created_at < now() - interval '24 hours'`
- Tests: extend existing AI contract tests in `test/contracts/ai_*.dart`.

### E.6 — WorkoutScheduleService refactor (NEEDS_DECISION 3)
- **Largest single task.** 13 direct `workoutBox.put` callsites at L248, L412, L717, L844, L855, L1159, L1302, L1430, L1515, L1595, L1605, L1669, L1851.
- Route each through `WorkoutWriteService.upsertScheduled` (already exists at L427 of WorkoutWriteService).
- After each call, fire `unawaited(SyncService.instance.syncWorkoutData())` + invalidate `currentPlanProvider, calendarWeekProvider, todayWorkoutProvider`.
- Add `WorkoutScheduleService` to allowed-writers list in CLAUDE.md §15 only if direct-write paths remain (ideally none).
- Test: extend `test/contracts/scheduled_workouts_mutations_writer_to_reader_test.dart` to cover all 13 callsites.
- Risk: high — touches plan generation, copy week, reschedule, days/week change. Manual smoke test required after refactor.

### E.7 — Build `HealthWriteService` (NEEDS_DECISION 4)
- New file: `lib/core/services/health_write_service.dart`. Mirror `NutritionWriteService` pattern (singleton, mutex per `(userId, date, kind)`, telemetry hooks, fire-and-forget sync).
- Methods: `logSleep`, `logWeight`, `logMeasurement`, `logSteps` (refactor of `profile_provider.dart` direct writes).
- IST fix for sleep_log (F2-R2) folds in here — date key uses `istDateStr(DateTime.now())`.
- Update CLAUDE.md §15 to add HealthWriteService to allowed-writers + add SoT registry entries for `sleep_log_*` / `weight_log_*` / `measurement_*` Hive prefixes.
- Contract tests: `test/contracts/health_write_to_read_contract_test.dart`.

### E.8 — Gate coverage + dead code deletion (F8.1 + DEAD 1/2/3/4 + MySubmissionsScreen)
- Add `gate(featurePhotoAnalysis, ...)` at `ai-media-proxy` client upload site (locate in `ai_service.dart` or `ai_coach_provider.dart`).
- Add `gate(featurePredictionMonthly, ...)` at the re-trigger path for prediction card (locate in `prediction_service.dart`).
- Delete constants: `featureActiveWorkoutMode`, `featureVoiceNotes`, `featureDietPlanPdf`.
- Delete `lib/shared/repositories/user_repository.dart` method `softDeleteAccount`.
- Delete `lib/features/profile/screens/my_submissions_screen.dart` + remove `/profile/my-submissions` route.
- New gate: `scripts/check_gate_coverage.dart` — every `feature*` constant has ≥1 `gate()` callsite, OR `@Deprecated`, OR is in a known server-only-enforcement allowlist.
- New test: `test/contracts/gate_coverage_test.dart`.

### E.9 — Inline `if (isPro)` → reactive `ref.watch(subscriptionInfoProvider).isPro` (F8.3)
9 sites listed in Agent 7's findings. Per-callsite audit; most should already be reactive (constructor-prop reads from a watched provider) but verify each. Same shape as Test #12 PRO-upgrade-unlock fix.

### E.10 — Restore-completeness referrals (F4-S2)
- Add `_restoreReferralCodes` to `sync_restore_completeness.dart` — SELECT `referral_codes WHERE user_id` and stash result into `userBox['referral_code']` (or wherever the UI reads it).
- Add `_restoreReferralRedemptions` — SELECT `referral_redemptions WHERE referee_id=user_id` for audit display in Profile → Invite Friends.
- Test: extend `test/contracts/restore_completeness_writes_test.dart`.

### E.11 — Migrate `RankChip` / `RankInsignia` → Wardroom (NEEDS_DECISION 1)
5+ callsites: `profile_screen.dart`, `profile_identity.dart`, `rank_chip_full_width.dart`, `train_screen.dart`, `phase_roadmap_screen.dart`. Migrate to `WardRankPill` / `WardRankInsignia`. Delete `lib/shared/widgets/wardroom/rank_chip.dart` + `rank_insignia.dart`. Update CLAUDE.md §9 Legacy section.

### E.12 — Drop ~17 dead columns (DEAD 2.1 + 2.2 + 2.3 + 2.4 + 2.5 + 2.6 + 2.7)
- New migration: `supabase/migrations/067_drop_dead_columns.sql`
- Tables: `workout_logs` (8 cols: scheduled_workout_id, template_id, exercise_id, sets_completed, reps_completed, weight_kg, distance_km, rpe), `workout_templates` (description, estimated_duration_mins), `template_exercises` (exercise_id, rest_seconds, prescribed_weight, prescribed_time_secs, notes), `user_progress` (experience_last_calculated), `user_preferences` (biggest_obstacle), `ai_coach_interactions` (was_helpful), `workout_log_exercises` (notes).
- Update `applied_migrations.json` (per CLAUDE.md `feedback_migration_apply_record_pair.md`).
- Test: `test/contracts/no_dead_columns_referenced_test.dart` — source-grep that no Dart/TS code references the dropped names.

### E.13 — 6 remaining new framework deliverables
- `scripts/check_naming_conventions.dart` — extend existing
- `scripts/check_sot_registry_parity.dart` — rename/extend existing `_completeness.dart`
- `scripts/check_writeservice_only.dart` — source-grep for raw workoutBox/nutritionBox/healthBox `put`/`delete` outside allowed-writers list
- `scripts/check_mutation_invalidation_set.dart` — verify mutation methods invalidate canonical provider sets per CLAUDE.md §15
- `scripts/check_ai_tool_dispatcher_coverage.dart` — every registered tool has dispatcher entry (for write tools) and points at canonical WriteService
- `scripts/audit_discipline_history.dart` — every `^fix:` commit since 2026-04-24 has diagnose-doc OR waiver
- New contract tests: `applied_migrations_parity_test.dart`, `type_consistency_test.dart`, `high_priority_op_types_parity_test.dart`, `migrated_key_contracts_test.dart`, `custom_exercise_writer_to_reader_test.dart`, `undo_stash_lifetime_test.dart`

### E.14 — Telemetry hardening
- Add `upsert_<table>_success` op_type emission to `_syncSavedMeals`, `_syncSleepLogs`, `_syncMeasurements`, `_syncSavedDietPlan`, `_syncCustomFoods`. Distinguishes "feature not used" from "sync silently failing".
- Create `supabase/migrations/068_cron_call_log.sql` — new table `cron_call_log (id, function_name, started_at, status, http_status, request_id)`. Each cron Edge Function INSERTs at top of handler.
- Create `supabase/functions/_shared/cron_auth.ts` — JWT signature + role-claim decode helper. Replace inline env-equality in each cron function.
- Add to `scripts/check_generic_error_telemetry.dart` (extend existing) — ban op_types matching `_catch_\d+$` and `_for$` patterns.
- HIGH_PRIORITY_OP_TYPES parity test.

### E.15 — Doc updates
- CLAUDE.md §11: 24 tools / 11 FREE / 13 PRO (F6-1)
- CLAUDE.md §9: drop "slated for removal" from rank chip/insignia after E.11 deletion
- CLAUDE.md §15: add `WorkoutScheduleService` and `HealthWriteService` to allowed-writers list, add Hive prefix contracts for `sleep_log_*` / `weight_log_*` / `measurement_*` / `undo_*`
- CLAUDE.md §19: add new bug-class entries for F3-1.1, F6-2, F11-C11-2, F10.1
- `docs/sot_registry.yaml`: add concepts for `coach_notes`, `sleep_log_<date>`, `weight_log_<date>`, `measurement_<date>`, `undo_<logKey>`, MigratedKey-backed values

### E.16 — Regenerate `applied_migrations.json` from live `supabase_migrations.schema_migrations` (F5-S1)

### E.17 — One-shot SQL backfill
- `UPDATE ai_coach_interactions SET model_used='unknown_legacy' WHERE model_used='pending' AND ai_response IS NOT NULL AND created_at < now() - interval '24h'`
- (Optional cosmetic) `UPDATE client_errors SET client_version='1.0.0+23-legacy' WHERE client_version='0.0.0+release'`

## Phase F · Verification + ship

1. Bump `applied_migrations.json` after every new migration in E.12 / E.14.
2. Full suite: `flutter test` — target ≥1700 pass / 0 fail.
3. Run every new + existing `scripts/check_*.dart` — all exit 0.
4. `/build-apk` — pre-flight Gates 1–22 must all pass.
5. Manual smoke test post-WorkoutScheduleService refactor (E.6): assign template → days/week change → copy week → confirm calendar + AI coach see fresh state.
6. Retrospective: `project_audit_2026_05_16.md` + memory-index entry.

## State at session end

- 6 of 22 audit-deliverable findings docs at `docs/audit/2026-05-16/`: per-agent reports × 7 + `findings-verified.md` + `phase-a-*.md` + `phase-c-verification-log.md` + this file.
- 2 of 22 Phase E tasks complete: E.1 (coach_notes), E.2 (appVersion bump + gate).
- 1 new contract test passes locally.
- 1 new gate script exits 0 locally.
- Worktree dirty — nothing committed yet (per `feedback_apk_build_explicit_approval.md` + global rule "never commit unless explicitly asked").
