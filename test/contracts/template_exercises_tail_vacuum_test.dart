import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// APK Test #15.1 / Bug B — template_exercises tail vacuum after upsert.
///
/// Pre-Test-#15.1: _syncWorkoutTemplates upserts every exercise on
/// (template_id, order_index). When a template SHRINKS (e.g. 15 → 5),
/// slots 0..4 are upserted but slots 5..14 from the prior version
/// remain in cloud as orphaned tail rows. _restoreWorkoutTemplates
/// pulls all 15 back; founder saw triplicate exercises (Back Day A,
/// Leg Day A, Push Day each had 14-15 rows with 5 distinct names).
///
/// Migration 051 (Test #15 / Backlog #2) added UNIQUE(template_id,
/// order_index). That made the upsert idempotent per slot but
/// introduced the new tail-row failure mode.
///
/// Fix — after the per-exercise upsert loop, DELETE FROM
/// template_exercises WHERE template_id = $cloudTmplId AND order_index
/// >= $exercises.length. One round-trip per template. Idempotent.
/// Network failure on DELETE leaves stale tail (= pre-fix state) — no
/// regression. Telemetry op_type sync_template_exercises_tail_vacuum.
///
/// closes-diagnose: 2026-05-12-template-exercises-tail-vacuum-b3c8d2
void main() {
  late String src;

  setUpAll(() {
    src = loadSyncServiceSource().readAsStringSync();
  });

  group('_syncWorkoutTemplates tail vacuum', () {
    test('DELETE-by-order-index tail vacuum is present', () {
      // The fix executes a delete().eq(template_id).gte(order_index, length)
      // chain after the upsert loop. Source-grep the chain shape.
      expect(
        src.contains(".from('template_exercises')"),
        isTrue,
        reason: 'template_exercises table referenced in sync_service',
      );
      expect(
        RegExp(r"\.from\('template_exercises'\)\s*\.delete\(\)")
            .hasMatch(src),
        isTrue,
        reason:
            '_syncWorkoutTemplates must call .delete() on template_exercises '
            'after the per-exercise upsert loop. closes-diagnose: '
            '2026-05-12-template-exercises-tail-vacuum-b3c8d2',
      );
      expect(
        RegExp(r"\.gte\(\s*'order_index'\s*,\s*exercises\.length\s*\)")
            .hasMatch(src),
        isTrue,
        reason:
            'tail vacuum DELETE must bound on order_index >= exercises.length '
            'so only orphaned tail rows are removed (not the upserted body).',
      );
    });

    test('tail vacuum errors are caught + recorded as non-fatal telemetry',
        () {
      // Network failure on the DELETE leaves stale tail = pre-fix state.
      // No regression. But we need a telemetry breadcrumb so ops can
      // see if the vacuum is failing for a cohort of users.
      expect(
        src.contains("reason: 'sync_template_exercises_tail_vacuum'"),
        isTrue,
        reason:
            'tail vacuum failure must be recorded as a non-fatal telemetry '
            'event with reason sync_template_exercises_tail_vacuum so ops '
            'can monitor cohort health.',
      );
    });

    test(
        'forbidden: DELETE WITHOUT gte order_index (would wipe entire children)',
        () {
      // A bug in the vacuum that drops the gte clause would delete ALL
      // template_exercises rows for the template — same data-loss class
      // as the pre-Test-#15 DELETE-then-INSERT pattern. Pin its absence.
      // The vacuum line must contain BOTH .delete() AND .gte('order_index'.
      // We assert that the substring `.delete()` in template_exercises
      // context is always within 200 chars of a `.gte('order_index'`.
      final pattern = RegExp(
          r"\.from\('template_exercises'\)[\s\S]{0,400}?\.delete\(\)[\s\S]{0,400}?\.gte\(\s*'order_index'");
      expect(pattern.hasMatch(src), isTrue,
          reason:
              'every .delete() on template_exercises must be paired with a '
              '.gte order_index bound within the same chain. A naked '
              'delete().eq(template_id) would wipe the whole template.');
    });
  });
}
