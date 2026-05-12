// APK Test #15.3 / Bug 4a — restore-completeness contract for the
// `scheduled_workouts` → `workout_templates` JOIN.
//
// Symptom (founder on +22 fresh install, 2026-05-12):
//   Monday's day card header rendered "PUSH A" (plan-generator default)
//   instead of "Leg Day A" (the assigned template), even though cloud
//   `scheduled_workouts.template_id = 06f6e0bd-...(Leg Day A)`. Logged
//   exercises restored correctly via `workout_log_exercises`, but the
//   schedule header is sourced from Hive `schedule_<date>.workout_name`
//   which was left at the plan-gen default because the restore path
//   never JOINed to `workout_templates` to hydrate it.
//
// Cloud schema (verified live 2026-05-12 against dedsavbjuwgarrhphgnl):
//   scheduled_workouts columns = id, user_id, template_id,
//     scheduled_date, week_number, day_of_week, status,
//     completed_at, created_at
//   NO workout_name. NO exercises column. Template content lives
//   in workout_templates.name + template_exercises.* and must be
//   resolved via JOIN.
//
// This is a Class A restore-completeness gap (same shape as Test #11
// Theme A freezes/inbox/diet plan). Per CLAUDE.md §15: "Any Hive
// surface paying users lose on reinstall needs cloud column/table +
// sync write + restore method + contract test."
//
// Source-grep contract test pinning the JOIN/embed behavior in
// `SyncService._restoreScheduledWorkouts`.
//
// See docs/diagnoses/2026-05-12-restore-template-schedule-gap-9e2c1a.md.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
      'APK Test #15.3 · Bug 4a · _restoreScheduledWorkouts template JOIN '
      '(closes-diagnose: 9e2c1a)', () {
    late String src;
    late String methodSrc;

    setUpAll(() {
      src = File('lib/core/services/sync_service.dart').readAsStringSync();
      // Slice out just _restoreScheduledWorkouts so the assertions can't
      // accidentally match an unrelated occurrence elsewhere in the file
      // (e.g. _restoreWorkoutTemplates also embeds template_exercises).
      const startMarker =
          'Future<void> _restoreScheduledWorkouts(String userId, String since)';
      final start = src.indexOf(startMarker);
      expect(start, isNot(-1),
          reason: '_restoreScheduledWorkouts method must exist');
      // Find the next top-level method or end-of-file.
      final after = src.indexOf('\n  Future<', start + startMarker.length);
      methodSrc = after == -1 ? src.substring(start) : src.substring(start, after);
    });

    test(
        'restore fetches scheduled_workouts with PostgREST embed of '
        'workout_templates (name + template_exercises)', () {
      // The embed string can take a few shapes — accept any PostgREST
      // alias that resolves the template along with its exercises.
      final hasEmbed = methodSrc.contains('template:template_id') ||
          methodSrc.contains('workout_templates:template_id') ||
          methodSrc.contains('workout_templates!template_id');
      expect(hasEmbed, isTrue,
          reason:
              '_restoreScheduledWorkouts must embed the parent workout_templates '
              'row via PostgREST select syntax. The cloud scheduled_workouts '
              'table has no workout_name / no exercises columns; the only way '
              'to hydrate the Hive schedule_<date> map\'s display content is '
              'to JOIN to workout_templates(name, template_exercises(*)).');
      // The exercises must also be embedded (or fetched alongside).
      expect(methodSrc.contains('template_exercises'), isTrue,
          reason:
              '_restoreScheduledWorkouts must pull template_exercises so the '
              'Hive map\'s exercises[] is hydrated. The receipt path is fine '
              'without this (logs come back via workout_log_exercises), but '
              'the active-workout / today-card / weekly-calendar surfaces '
              'all read schedule_<date>.exercises and would render an empty '
              'list on fresh install.');
    });

    test('restore hydrates workout_name from the embedded template name', () {
      // We expect a hydration line that maps the embedded template's
      // name onto the merged Hive map's workout_name key. Accept any
      // variable name; the load-bearing pattern is the workout_name
      // key being assigned conditionally based on template presence.
      expect(methodSrc.contains("'workout_name'"), isTrue,
          reason:
              '_restoreScheduledWorkouts must write workout_name into the '
              'merged Hive map when a template is resolved. Pre-fix this '
              'method never touched workout_name, so the plan-generator '
              'default ("PUSH A") survived cloud restore even when '
              'template_id pointed at "Leg Day A".');
    });

    test(
        'restore hydrates exercises[] using prescribed_sets via _coerceInt '
        '(matches _restoreWorkoutTemplates mapping shape)', () {
      // The exercise-shape mapping must reuse the same normalization
      // _restoreWorkoutTemplates uses (lines ~3938-3962): prescribed_sets
      // → sets (int via _coerceInt, fallback 3), prescribed_reps → reps
      // (String). Without _coerceInt the int-coercion bug from APK Test
      // #15.1 / Bug A would re-emerge (Hive readers cast sets as int?).
      expect(methodSrc.contains('prescribed_sets'), isTrue,
          reason:
              'Exercise normalization must map prescribed_sets → sets. '
              'Pulling raw template_exercises into Hive without this '
              'translation leaves consumers (active_workout_screen, '
              'WorkoutReceiptCard) looking for a non-existent "sets" key.');
      expect(methodSrc.contains('_coerceInt'), isTrue,
          reason:
              'sets must be coerced via _coerceInt(fallback: 3) — the '
              'same path _restoreWorkoutTemplates uses. Pre-Test-#15.1 '
              'this field was stringified, which crashed home_screen'
              '._buildTodayRow with `type \'String\' is not a subtype of '
              'type \'int?\'`. closes-diagnose: a2f9e1.');
    });

    test(
        'restore is non-destructive when template_id is null '
        '(plan-generator entries preserved)', () {
      // The original existingMap merge must still spread first so plan
      // generator's local workout_name / exercises survive when no
      // template is assigned. Look for the ...existingMap pattern still
      // present.
      expect(methodSrc.contains('...existingMap'), isTrue,
          reason:
              'Pre-fix merge spread existingMap first so non-template rows '
              'kept their plan-gen defaults. The template-hydration fix must '
              'NOT remove this spread — only override workout_name/exercises '
              'when a template actually resolves. Otherwise rest days / '
              'plan-gen days lose their content on cold restore.');
    });

    test('telemetry path preserved for restore_scheduled_workouts failure',
        () {
      // The existing catch-block telemetry contract (op_type =
      // restore_scheduled_workouts) must survive the rewrite.
      expect(methodSrc.contains("'restore_scheduled_workouts'"), isTrue,
          reason:
              'Telemetry op_type "restore_scheduled_workouts" must remain '
              'wired so the audit-2026-05-11 H-42 retrofit (CLAUDE.md §6) '
              'continues to surface restore-side failures.');
    });
  });
}
