# Phase E.13 — Discovered violations (framework deliverables)

Built 6 new gate scripts + 6 new contract tests under E.13. Several flag
PRE-EXISTING violations that are OUT OF SCOPE for E.13 (they're slated for
remediation in E.5 / E.6 / E.7 / E.8 of the same audit batch). Documenting
them here so the framework scripts can exit 0 against current `main` while
the remediation tasks land.

## scripts/check_writeservice_only.dart — 17 violations

All 17 pre-existing. Allowed-writers list per CLAUDE.md §15:
WorkoutWriteService / NutritionWriteService / HealthWriteService /
WorkoutScheduleService (E.6 transitional) / HiveService / SyncService /
*Migrator.

### Health domain (5 — all closed by E.7 `HealthWriteService` build-out)

- `lib/core/services/health_sync_service.dart:169,177,178,192` —
  `healthBox.put(...)` in class `HealthSyncService`. Refactor target for E.7.
- `lib/features/ai_coach/services/conversational_log_handler.dart:131` —
  `healthBox.put(...)` direct write of `sleep_log_<date>` from coach quick-log.
  Will route through `HealthWriteService.logSleep` after E.7.
- `lib/features/train/providers/train_provider.dart:1508` —
  `healthBox.put(...)` writing a measurement during workout-complete flow.

### Workout domain (12 — closed by E.6 `WorkoutScheduleService` refactor)

- `lib/features/train/providers/train_provider.dart:1242` — `ActiveWorkoutNotifier`
  writing active-workout state directly. E.6 / E.5 follow-up.
- `lib/features/train/providers/train_provider.dart:1664,1688,1714` —
  `TemplatesNotifier` put/delete. Route through `WorkoutScheduleService.saveTemplate`
  / `deleteTemplate` after E.6.
- `lib/features/train/repositories/workout_repository.dart:408,1192,1211` —
  `WorkoutRepository` legacy direct writes (streak, freezes, schedule). E.6.
- `lib/features/train/screens/active_workout_screen.dart:2248` —
  Mid-session persistence write. Move to ActiveWorkoutPersistence (already
  exists; this callsite is a duplicate path).
- `lib/features/train/services/active_workout_persistence.dart:21,36,50` —
  `ActiveWorkoutPersistence` IS a legitimate sole-writer for the
  `active_workout_session` Hive key but isn't yet on the allowed-writers
  list. E.7-adjacent: add as a registered single-purpose writer.

### Current gate behavior

Gate exits 1 on `main` until E.5 / E.6 / E.7 land. NOT yet wired into
`/build-apk` Gates 1-22; runs manually for now. Wire into gate runner
AFTER E.7 ships so the build pipeline isn't gated on pre-existing debt.

## scripts/check_sot_registry_parity.dart — 1 stale line_range + 5 orphan repos

### Stale line_range (informational warning, exits 0)

- `lib/core/services/sync/sync_coach.dart` registry block cites
  `line_range: 32-42` for `syncCoachMemoryNow`, which is now declared at
  line 12 (file shifted in E.1's coach_notes upward sync fix). Update
  the line_range in `docs/sot_registry.yaml` when next touching the
  coaching_notes concept.

### Orphan WriteService/Repository classes (informational warning, exits 0)

- `AiCoachRepository` — readers-only concept, registry coverage TODO.
- `ProgressPhotoRepository` — photos are PRO-gated; SoT entry pending.
- `ExerciseRepository` — read-only over `exerciseBox` + `customBox`.
- `FoodRepository` — read-only over `foodBox` + `customBox`.
- `SubmissionsRepository` — extracted in Test #11 Theme K.

Action: add stub registry entries marking these as "read-only,
no-writer concepts" so the orphan check goes quiet. Deferred to E.15
doc-updates batch.

## scripts/audit_discipline_history.dart

All `fix:` commits since 2026-04-24 are compliant — verified manually
on first run. Script is GREEN.

## scripts/check_ai_tool_dispatcher_coverage.dart

All 17 server-side WRITE tools have matching `case '<type>':` entries
in `tool_dispatcher.dart`. Script is GREEN.

## scripts/check_mutation_invalidation_set.dart

Source-grep heuristic. Several mutation methods invalidate a SUBSET of
the canonical workout / nutrition provider set. The script reports them
as warnings (not failures) because some methods only mutate a single
dimension and don't need every provider invalidated.

## test/contracts/applied_migrations_parity_test.dart

`backups/applied_migrations.json` lists `"024"` but no matching file
exists in `supabase/migrations/`. Verified: migration 024 was inlined
into another migration on apply (intentional historic decision). The
test tolerates the asymmetry — every FILE must have an entry, but
every ENTRY does not need a file (forward-only registry).
