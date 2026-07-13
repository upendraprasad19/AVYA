// scripts/check_hive_map_field_drift.dart
//
// Gate 19 — Hive Map field-key drift detector (Theme G, closes-diagnose
// 2026-05-22 ec4d27 sibling + the durable mitigation for the 10th
// writer/reader drift caught this batch).
//
// THE CLASS WE'RE CATCHING
// ------------------------
// Writer puts a literal map into Hive under a key prefixed `concept_*`:
//
//   await box.put('exlog_${date}_$hash', {
//     'exercise_name': name,
//     'set_number': sets.length,
//     'weight_kg': weight,
//     ...
//   });
//
// Reader later does `map['field_name']` on a value pulled out of the
// same prefix:
//
//   for (final raw in box.values) {
//     if (raw is! Map) continue;
//     final log = Map<String, dynamic>.from(raw);
//     final sets = log['sets_completed'] as int?;   // ← BUG
//   }
//
// The writer field is `set_number`. The reader field is `sets_completed`.
// Both pass type checks. Source-grep tests for each side pass. The bug
// is silent. 10 instances of this class since APK Test #6.
//
// WHAT THIS GATE DOES (v1, regex-based)
// -------------------------------------
// For each KNOWN concept prefix (canonical writers identified in the
// SoT registry), maintain an expected EMIT set of field names. Scan
// the codebase for `['field_name']` accesses on variables that LOOK
// LIKE they came from the corresponding Hive map (i.e. variable
// names matching `log` / `entry` / `raw` / `m` / `record` / `value`
// followed by `Map<String, dynamic>.from(...)` patterns).
//
// Any read field NOT in the expected EMIT set for the corresponding
// prefix is flagged as a DRIFT CANDIDATE.
//
// BASELINE
// --------
// `backups/gate19_drift_baseline.txt` grandfathers all candidates
// present on landing-day commit. NEW occurrences (not in baseline)
// hard-fail. Per-file granularity. Refresh the baseline with
// `--update-baseline` after closing a true drift in a separate commit.
//
// PER-CONCEPT EMIT FIELD MAP
// --------------------------
// Source of truth is THIS FILE for v1 (we maintain it by hand pinning
// only canonical writers). The SoT registry `hive.emit_fields` schema
// extension proposed in the Theme G spec is a follow-up — landing the
// detector + baseline first lets us catch regressions immediately
// while the schema work proceeds independently.

import 'dart:io';

const _expectedEmitFields = <String, Set<String>>{
  // exlog_* writer: WorkoutWriteService.logExercise
  // (lib/core/services/workout_write_service.dart:166)
  'exlog': {
    'exercise_name', 'date', 'set_number', 'reps_completed', 'weight_kg',
    'volume_kg', 'is_pr', 'logging_type', 'workout_log_id',
    'duration_seconds', 'distance_km', 'sets', 'warm_up_sets',
    'source', 'updated_at_ms', 'created_at', 'id', 'notes',
    // Legacy fields accepted in dual-name fallback (Test #6 transition):
    'sets_completed', 'sets_detail',
    // EditLogExerciseRow.fromLog accepts these:
    'duration_sec', 'volume',
    // Restore writers stamp these:
    'is_swapped', 'original_date',
  },
  // nlog_* writer: NutritionWriteService.logMeal
  'nlog': {
    'food_name', 'meal_type', 'date', 'calories', 'protein_g',
    'carbs_g', 'fat_g', 'fiber_g', 'servings', 'serving_unit',
    'logged_at_ms', 'source', 'is_pr', 'id', 'cloud_id',
    'updated_at_ms', 'created_at', 'notes',
    // saveMealPreset writes:
    'meal_name', 'items',
    // Cart auditor + scan meal output:
    'image_url', 'analysis_type',
    // Conversational tool dispatcher:
    'kcal',
    // Restore-path legacy field names (Test #6 dual-name fallback):
    'name', 'calories_kcal',
  },
  // schedule_* writer: WorkoutScheduleService → WorkoutWriteService.upsertScheduled
  'schedule': {
    // `phase` stamped at generation (F-B 2026-06-05) — bucketPastRows groups by it.
    'date', 'phase', 'week', 'day_of_week', 'type', 'workout_day_index',
    'workout_name', 'workout_focus', 'exercises', 'warmup',
    'cooldown', 'finisher', 'week_character', 'status',
    'completed_at', 'is_swapped', 'original_date', 'source',
    'updated_at_ms', 'workout_log_id', 'id',
    // Per-exercise nested map fields (inside `exercises`):
    'name', 'sets', 'reps', 'rest_sec', 'logging_type', 'order',
    'movement_pattern', 'suitable_for', 'equipment_needed',
    // SwapService.swapExercise stamps the replacement exercise map with the
    // swap marker + the name it replaced (LEVER 6 demotion source).
    'swapped_via', 'swapped_from',
  },
  // wlog_* writer: WorkoutWriteService.markCompleted (workout summary row).
  // f1c8e4: markCompleted stamps type:'workout_log' + completed_at (ISO) +
  // completed_at_ms + duration_seconds + optional rpe — count/history readers
  // filter on `type` and read `completed_at`; extend the emit set to match.
  'wlog': {
    'type', 'date', 'completed_at', 'completed_at_ms', 'started_at',
    'workout_name', 'workout_focus', 'workout_log_id', 'sets_completed',
    'total_volume_kg', 'duration_minutes', 'duration_seconds', 'rpe',
    'exercises', 'id', 'updated_at_ms', 'created_at', 'source',
    // Legacy alternate names:
    'set_number', 'total_sets',
  },
};

/// File paths to scan (relative to repo root). Limited to high-risk
/// reader surfaces — providers + repositories + screens + services.
const _readerScanPaths = <String>[
  'lib/features',
  'lib/shared/repositories',
  'lib/core/services',
];

/// Files to skip (writers themselves + canonical aggregators that
/// legitimately use the full emit set as part of their writer contract).
const _skipFiles = <String>[
  'lib/core/services/workout_write_service.dart',
  'lib/core/services/nutrition_write_service.dart',
  'lib/core/services/health_write_service.dart',
  'lib/core/services/workout_schedule_write_service.dart',
  // Debug-only year-simulation harness (kDebugMode-gated, release-inert). It
  // references many Hive prefixes (for reset) and reads profile/progress/
  // schedule maps, which the prefix heuristic mis-attributes to exlog_* drift.
  // Not a production reader of canonical maps. Added 2026-05-31.
  'lib/features/dev/simulation_service.dart',
];

void main(List<String> args) {
  final updateBaseline = args.contains('--update-baseline');
  final warnOnly = args.contains('--warn-only');

  final baselineFile = File('backups/gate19_drift_baseline.txt');
  final baseline = <String>{};
  if (baselineFile.existsSync()) {
    baseline.addAll(baselineFile
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#')));
  }

  final candidates = <String>{};

  for (final scanRoot in _readerScanPaths) {
    final dir = Directory(scanRoot);
    if (!dir.existsSync()) continue;
    final dartFiles = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
      final normalized = f.path.replaceAll('\\', '/');
      return !_skipFiles.any((s) => normalized.endsWith(s));
    });

    for (final file in dartFiles) {
      final content = file.readAsStringSync();
      // Strip line + block comments so the comment containing the
      // pre-fix pattern doesn't flag.
      final stripped = content
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');

      for (final entry in _expectedEmitFields.entries) {
        final prefix = entry.key;
        final expected = entry.value;
        // Heuristic for "this file reads from the `prefix_*` Hive map":
        //   - Contains a `keyStr.startsWith('${prefix}_')` predicate
        //     (the canonical exlog walk-back pattern from
        //     loadAllExercisePRs / graduation_provider), OR
        //   - Contains a `box.get('${prefix}_...')` literal that maps
        //     to the same prefix.
        final looksLikePrefixReader =
            RegExp("startsWith\\('${prefix}_'\\)").hasMatch(stripped) ||
                RegExp("box\\.get\\('${prefix}_").hasMatch(stripped) ||
                RegExp("'${prefix}_'").hasMatch(stripped);
        if (!looksLikePrefixReader) continue;

        // Extract every `['field']` literal access in the file.
        final accessPattern = RegExp(r"\['([a-z_][a-z0-9_]*)'\]");
        final reads = accessPattern.allMatches(stripped).map((m) =>
            m.group(1)!).toSet();

        // Drift candidates = reads MINUS expected set.
        for (final read in reads) {
          if (expected.contains(read)) continue;
          // Skip common non-Hive accesses that often look like map reads
          // (provider state, JSON request bodies, response data, etc.)
          // — heuristically these are short fields we already vetted.
          if (_alwaysOk.contains(read)) continue;
          final candidate =
              '${file.path.replaceAll('\\', '/')} :: ${prefix}_* :: $read';
          candidates.add(candidate);
        }
      }
    }
  }

  if (updateBaseline) {
    baselineFile.parent.createSync(recursive: true);
    final sorted = candidates.toList()..sort();
    baselineFile.writeAsStringSync(
      '# Gate 19 — Hive Map field-key drift baseline\n'
      '# Auto-generated by scripts/check_hive_map_field_drift.dart --update-baseline.\n'
      '# Grandfathered entries below — NEW occurrences hard-fail the gate.\n'
      '# Refresh after closing a true drift in a separate commit.\n'
      '#\n'
      '# Format: <file_path> :: <prefix>_* :: <field_name>\n'
      '\n${sorted.join('\n')}\n',
    );
    stdout.writeln(
        '[Gate 19] BASELINE UPDATED: ${sorted.length} drift candidates recorded.');
    exit(0);
  }

  // Diff against baseline.
  final novel = candidates.where((c) => !baseline.contains(c)).toList()
    ..sort();
  if (novel.isEmpty) {
    stdout.writeln('[Gate 19] PASS: '
        '${candidates.length} drift candidates (all in baseline).');
    exit(0);
  }

  stderr.writeln('[Gate 19] FAIL: ${novel.length} NEW drift candidate(s):');
  for (final n in novel.take(20)) {
    stderr.writeln('  - $n');
  }
  if (novel.length > 20) {
    stderr.writeln('  ... and ${novel.length - 20} more');
  }
  stderr.writeln(
      '\n  Each line is a `[\'field_name\']` access in a file that reads a '
      'Hive map with the prefix, where `field_name` is NOT in the\n'
      '  canonical writer\'s emit set. Either:\n'
      '    (a) The field IS in the writer\'s emit set — extend \n'
      '        `_expectedEmitFields` in scripts/check_hive_map_field_drift.dart.\n'
      '    (b) The field is legitimately unrelated to the Hive map — add \n'
      '        to `_alwaysOk` set, OR explicitly clone the map and rename \n'
      '        the variable to avoid heuristic match.\n'
      '    (c) THIS IS REAL DRIFT — fix the reader to use the canonical \n'
      '        field name (or extend the writer\'s emit set).\n'
      '\n  After closing a true drift, run with --update-baseline.\n'
      '\n  See lib/features/train/CLAUDE.md `feedback_writer_reader_field_'
      'drift_recurring.md` for the bug class history.');

  exit(warnOnly ? 0 : 1);
}

/// Fields that are common across many non-Hive contexts (provider state,
/// JSON request bodies, response bodies). These get suppressed so the
/// gate noise stays low. NOT a license to drift — extend with care.
const _alwaysOk = <String>{
  // Provider state + UI render:
  'value', 'label', 'icon', 'title', 'subtitle', 'message', 'error',
  'isLoading', 'error_class', 'status', 'data', 'items', 'result',
  // JSON request/response bodies for Edge Functions:
  // restore-user-snapshot (C3) bundle ENVELOPE — read off the EF JSON response
  // (data['schema_version'] / data['tables']), NOT off any exlog_/wlog_ Hive map.
  'schema_version', 'tables',
  'text', 'image', 'image_url', 'type', 'meal_name', 'analysis_type',
  'kcal', 'protein', 'carbs', 'fat', 'fiber', 'quantity', 'name',
  'meal_type',
  // Common non-Hive map shapes:
  'id', 'created_at', 'updated_at', 'user_id', 'date',
  // Subscription / billing:
  'plan', 'expires_at', 'is_pro',
  // user_progress map (read by phaseForDate — NOT a schedule_* field; Obs 1):
  'current_phase',
  // user_progress map — read by _persistCurrentStreakDays (reckon decay persist,
  // OBS-8b e9d4b7); NOT an exlog/schedule/wlog field. The prefix heuristic
  // mis-attributes it because workout_repository also walks those prefixes for
  // the streak/PR calc.
  'current_streak_days',
  // Profile canonical TARGET fields — read by the AI snapshot's daily_targets +
  // daily_calorie_target (f3c8d1) from userBox['profile'], NOT from exlog/nlog/
  // wlog rows. The prefix heuristic mis-attributes them because ai_snapshot_builder
  // also reads those prefixes for PRs / meals / logs.
  'daily_calories', 'protein_grams', 'carb_grams', 'carbs_grams', 'fat_grams',
  // Profile injuries field (U4 a1f6c3) — read via InjuryVocab.fromProfile(
  // profile['injuries']) / merged['injuries'] in the generation entry points to
  // thread contraindications into the plan engine. NOT a schedule_*/exlog_*
  // field; the prefix heuristic mis-attributes it because train_provider +
  // hotel_workout_planner also handle those Hive maps.
  'injuries',
  // W2.1 (graded_progression, Batch 3b-ii) — `fitness_experience` +
  // `onboarding_completed_at` are canonical userBox['profile'] fields, read by
  // ProgressionResolver.resolve() via UserRepository.getProfile() for the beginner
  // auto-linear window. NOT exlog_* fields (no exlog writer emits them); the prefix
  // heuristic mis-attributes them because progression_resolver also reads exlog_*
  // rows for the weight scan.
  'fitness_experience', 'onboarding_completed_at',
  // ⑤ (physique_focus_bringup, Batch 4) — `physique_focus` is a canonical
  // userBox['profile'] field, read by TrainingHistoryAnalyzer.physiqueFocusMuscles()
  // for the body-focus +1-set bring-up. NOT an exlog_*/schedule_* field (no such
  // writer emits it); the prefix heuristic mis-attributes it because
  // training_history_analyzer also reads exlog_* rows (weakMuscles).
  'physique_focus',
  // plan_json cloud-bundle fields — read by _restoreWorkoutPlan +
  // PlanIntegrityReconciler from `user_progress.plan_json`, NOT from a
  // `schedule_*` entry. The prefix heuristic mis-attributes them because both
  // files also read `schedule_*` keys (diagnose a7d3f1).
  'plan_start_date', 'plan_end_date', 'plan_json', 'schedules',
  // AI-coach ToolIntent payload field — `intent.payload['goal']` in
  // tool_dispatcher._executeRegeneratePlanBlock's FitnessGoals.isKnown guard.
  // NOT a schedule_*/exlog/nlog/wlog Hive field (no emit set carries `goal` —
  // the goal lives on the profile / plan_json). The prefix heuristic
  // mis-attributes it because the same file also reads `schedule_*` keys
  // (B-pass b7c8040 / diagnose a4f7e1).
  'goal',
  // Exercise-library / template-exercise canonical prescription DEFAULTS —
  // read on the `ex` exercise sub-object in _syncWorkoutTemplates (F17,
  // audit-fixwave) as a fallback when the builder's saved map omits sets/reps,
  // so the cloud `template_exercises` row carries prescribed_* instead of NULL.
  // NOT fields of the schedule_*/exlog_* Hive maps (those emit `sets`/`reps`,
  // never `default_*`); the prefix heuristic mis-attributes them because
  // sync_workout.dart also walks those prefixes for the schedule/log sync.
  'default_sets', 'default_reps',
  // Unit 3 (coach-memory-snapshot) — snapshot OUTPUT key names in
  // ai_snapshot_builder.proactiveTrimKeys + the enrich re-add branches. These
  // are health-domain SERIES keys of the snapshot MAP (populated by _getSleep7d
  // / _getStepHistory / _getWater7d), NOT fields of the exlog_/nlog_/wlog_ Hive
  // maps. The prefix heuristic mis-attributes them because the same file also
  // reads those log prefixes for PRs / meals / logs.
  'sleep_7d', 'step_history_7d', 'water_7d',
  // Unit 1 (coach-completion-tap-card) — `swapped_from` is a field of the
  // PER-EXERCISE sub-map inside `schedule_<date>['exercises']` (it IS in the
  // `schedule` emit set, line ~103). ai_snapshot_builder._plannedExerciseHasLog
  // reads `ex['swapped_from']` (the swap-tolerant all-logged check) on that
  // exercise sub-object, NOT on an exlog_/nlog_/wlog_ row. The prefix heuristic
  // mis-attributes it to exlog/nlog/wlog because ai_snapshot_builder also walks
  // those prefixes for the PR / meals / logs snapshot. (Sibling `exercise_name`
  // is already grandfathered in the baseline for the same reader.)
  'swapped_from',
  // Unit 1 (coach-completion-tap-card) — `resolved_at` is a field of the
  // LOCAL-ONLY `completion_prompt_<date>` coachBox action row (kind-tagged;
  // written by tool_dispatcher._writeCompletionPrompt, read back by
  // _resolveCompletionPromptIfPresent + ChatHistoryNotifier.build). It is NOT a
  // `schedule_*` field. The prefix heuristic mis-attributes it because
  // tool_dispatcher.dart also reads `schedule_<date>` keys in
  // _maybeCompleteScheduledDay. Sibling completion_prompt fields (kind /
  // planned_count / logged_count) already suppressed via emit set / this list.
  'resolved_at',
};
