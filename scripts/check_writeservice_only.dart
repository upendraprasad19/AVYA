// scripts/check_writeservice_only.dart
//
// Gate (E.13 — Audit 2026-05-16 framework deliverable):
// All writes to workoutBox / nutritionBox / healthBox must go through the
// canonical WriteService for that domain.
//
// Allowed-writers list (per E.13 spec + CLAUDE.md §15 SoT registry):
//   - WorkoutWriteService  (sole writer for workoutBox)
//   - NutritionWriteService (sole writer for nutritionBox)
//   - HealthWriteService   (sole writer for healthBox — built in E.7)
//   - WorkoutScheduleService (E.6 transitional — refactor target; flagged
//                             but allowed until E.6 lands)
//   - HiveService          (boot / clearAllData)
//   - SyncService          (restore from cloud)
//   - UserConfigMigrator   (one-shot configBox → userBox migration)
//   - ExlogKeyMigrator     (one-shot exlog_* key canonicalization)
//   - HiveFieldRenameMigrator (one-shot field-rename migration)
//
// Detection: source-grep `<box>.put(` / `<box>.delete(` in lib/ where
// `<box>` is workoutBox / nutritionBox / healthBox. The owning class
// (resolved by walking backwards to `class <Name>`) must be in the
// allowed list; otherwise the line is flagged as a violation.
//
// Exit 0 = pass.
// Exit 1 = fail.
//
// Usage: dart run scripts/check_writeservice_only.dart

import 'dart:io';

const allowedClasses = <String>{
  'WorkoutWriteService',
  'NutritionWriteService',
  'HealthWriteService',
  'WorkoutScheduleService', // E.6 transitional — refactor target
  // Tech-debt audit 2026-05-20 / A2 (B5 D13-D17, closes-diagnose d882ca) split
  // the 1970-LOC `WorkoutScheduleService` into three canonical owners. Each
  // remains a sole writer for its slice of the workout-schedule domain:
  //   - TemplateService            — assignTemplateToDate / unschedule /
  //                                   cleanSyncTemplateSchedule. Owns the
  //                                   `schedule_<date>` rows for template-
  //                                   scheduled days.
  //   - WorkoutScheduleReadService — plan-generation orchestration +
  //                                   calendar queries. Owns the
  //                                   `current_plan` summary blob and
  //                                   `phase_started_at` write on first plan
  //                                   generation.
  // Both are referenced by the train_provider + screens via the
  // workoutScheduleReadServiceProvider singleton-deprecation path; their
  // writes participate in the same syncWorkoutData fan-out + telemetry pair
  // as WorkoutScheduleService did pre-split.
  'TemplateService',
  'WorkoutScheduleReadService',
  'HiveService',
  'SyncService',
  'UserConfigMigrator',
  'ExlogKeyMigrator',
  'HiveFieldRenameMigrator',
  'LoggingTypeRepairMigrator', // existing one-shot
};

// Files whose top-level scope is OK (e.g. extension files / part files
// that extend an allowed class).
const allowedFilePathFragments = <String>[
  'lib/core/services/workout_write_service.dart',
  'lib/core/services/nutrition_write_service.dart',
  'lib/core/services/health_write_service.dart',
  'lib/core/services/hive_service.dart',
  'lib/core/services/user_config_migrator.dart',
  'lib/core/services/exlog_key_migrator.dart',
  'lib/core/services/hive_field_rename_migrator.dart',
  'lib/core/services/logging_type_repair_migrator.dart',
  'lib/core/services/workout_schedule_service.dart',
  // SyncService is part-split.
  'lib/core/services/sync_service.dart',
  'lib/core/services/sync/',
];

// Known pre-existing violations slated for remediation in audit phases
// E.5 / E.6 / E.7. Documented in docs/audit/2026-05-16/e13-discovered-violations.md.
// Each entry is `<relPath>:<class>:<box>.<op>`. When the corresponding
// remediation lands, REMOVE the entry from this allowlist — the script
// will then catch any regression.
const knownViolations = <String>{
  // E.7 — HealthWriteService build-out
  'lib/core/services/health_sync_service.dart:HealthSyncService:healthBox.put',
  'lib/features/ai_coach/services/conversational_log_handler.dart:ConversationalLogHandler:healthBox.put',
  // E.6 — WorkoutScheduleService refactor
  'lib/features/train/providers/train_provider.dart:ActiveWorkoutNotifier:workoutBox.put',
  'lib/features/train/providers/train_provider.dart:ActiveWorkoutNotifier:healthBox.put',
  'lib/features/train/providers/train_provider.dart:TemplatesNotifier:workoutBox.put',
  'lib/features/train/providers/train_provider.dart:TemplatesNotifier:workoutBox.delete',
  'lib/features/train/repositories/workout_repository.dart:WorkoutRepository:workoutBox.put',
  'lib/features/train/screens/active_workout_screen.dart:ActiveWorkoutScreen:workoutBox.put',
  // E.7-adjacent — ActiveWorkoutPersistence is a legitimate single-purpose
  // writer for `active_workout_session`; pending registry addition.
  'lib/features/train/services/active_workout_persistence.dart:ActiveWorkoutPersistence:workoutBox.put',
  'lib/features/train/services/active_workout_persistence.dart:ActiveWorkoutPersistence:workoutBox.delete',
  // 2026-05-27 (gate-cleanup batch, closes-diagnose `<gate-cleanup>`):
  // WarmupCooldownSection writes a per-day checkbox state cache at key
  // `warmup_checks_<ist-date>_<exercise-slug>` to survive scroll / reopen.
  // The key prefix `warmup_checks_` is intentionally NOT in the SoT
  // registry — it's pure widget UI state, not a domain mutation. The
  // matching read at `_loadChecks` lives in the same widget. Forcing this
  // through a WriteService would over-engineer a localStorage cache.
  'lib/features/train/screens/active_workout/warmup_cooldown_section.dart:<top-level>:workoutBox.put',
};

final boxAccessRegex = RegExp(
  r'\b(workoutBox|nutritionBox|healthBox)\s*\.\s*(put|delete)\s*\(',
);

final classDeclRegex = RegExp(r'^\s*class\s+([A-Z][A-Za-z0-9_]*)');

void main(List<String> args) async {
  final projectRoot = Directory.current.path.replaceAll('\\', '/');
  final libDir = Directory('$projectRoot/lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[check_writeservice_only] ERROR: lib/ not found');
    exit(1);
  }

  final violations = <String>[];

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path
        .replaceAll('\\', '/')
        .replaceFirst('$projectRoot/', '');

    if (_isAllowedFile(rel)) continue;

    final content = entity.readAsStringSync();
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final m = boxAccessRegex.firstMatch(line);
      if (m == null) continue;

      // Skip commented lines.
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;

      // Resolve owning class by walking up.
      String? owningClass;
      for (var j = i; j >= 0; j--) {
        final cm = classDeclRegex.firstMatch(lines[j]);
        if (cm != null) {
          owningClass = cm.group(1);
          break;
        }
      }

      if (owningClass == null || !allowedClasses.contains(owningClass)) {
        // Check known-violations allowlist before flagging.
        final signature = '$rel:${owningClass ?? "<top-level>"}:'
            '${m.group(1)}.${m.group(2)}';
        if (knownViolations.contains(signature)) {
          continue; // Pre-existing — already documented.
        }
        violations.add(
          '$rel:${i + 1} — ${m.group(1)}.${m.group(2)}(...) '
          'in class `${owningClass ?? "<top-level>"}` (not on allowed-writers list)',
        );
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln(
        '[check_writeservice_only] PASS — all workoutBox/nutritionBox/healthBox '
        'put/delete callsites are inside an allowed WriteService.');
    exit(0);
  } else {
    stderr.writeln('\n[check_writeservice_only] FAIL — ${violations.length} '
        'box.put/delete calls outside allowed WriteServices:');
    for (final v in violations.take(30)) {
      stderr.writeln('  $v');
    }
    if (violations.length > 30) {
      stderr.writeln('  ... and ${violations.length - 30} more.');
    }
    stderr.writeln('\n  Fix: route the write through WorkoutWriteService / '
        'NutritionWriteService / HealthWriteService.');
    exit(1);
  }
}

bool _isAllowedFile(String relPath) {
  for (final frag in allowedFilePathFragments) {
    if (relPath.contains(frag)) return true;
  }
  return false;
}
