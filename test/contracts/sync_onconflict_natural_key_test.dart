// Audit 2026-05-12 P0-A + P0-B — Source-grep contract test pinning the
// onConflict targets for the two upserts that were raising 23505 in
// production telemetry (31 + 16 rows / 24h).
//
// Class of bug: PostgREST `onConflict: 'id'` does NOT tell Postgres to
// resolve conflicts on the natural unique index. When the partial
// UNIQUE on `(workout_log_id, exercise_id, set_number)` or
// `(user_id, date, meal_type)` trips first, PG raises 23505. The
// summary/parent row never lands, the per-set/per-item rows succeed
// in their own try-block → orphans. AI coach + weekly report then
// see exercises/meals with no parent row.
//
// Fix: switch onConflict to the natural key so PostgREST merges.
//
// This is a Class A SoT regression (same shape as Test #15 Theme A
// restore-completeness gaps — writer/reader contract mismatch). Per
// CLAUDE.md Rule 21 + 22.

import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

void main() {
  group('Audit 2026-05-12 P0-A + P0-B · sync onConflict natural-key contract',
      () {
    late String src;

    setUpAll(() {
      src = loadSyncServiceSource().readAsStringSync();
    });

    test('workout_log_exercises upsert uses natural-key onConflict, not "id"',
        () {
      // Locate the workout_log_exercises upsert block. There is exactly one
      // in the file. Slice 800 chars after the from('workout_log_exercises')
      // call to grab the surrounding onConflict argument.
      const marker = "from('workout_log_exercises').upsert";
      final start = src.indexOf(marker);
      expect(start, isNot(-1),
          reason: '_syncExerciseLogs must call workout_log_exercises.upsert');
      // Slice generously — the payload + comments grew when user_id was added
      // to the arbiter (diagnose d4b8e2).
      final slice =
          src.substring(start, start + 1400 < src.length ? start + 1400 : src.length);

      expect(
        slice.contains(
            "onConflict: 'user_id,workout_log_id,exercise_id,set_number'"),
        isTrue,
        reason: 'workout_log_exercises upsert MUST target the USER-INCLUSIVE '
            'natural unique (user_id, workout_log_id, exercise_id, set_number). '
            "Pre-2026-05-12 this was onConflict: 'id' (23505 + orphans); diagnose "
            'd4b8e2 (2026-06-02) added user_id because workout_log_id is date-only '
            '— without it two users on the same date+exercise+set collided / '
            'overwrote each other (cross-user corruption).',
      );
      expect(
        slice.contains("onConflict: 'id'"),
        isFalse,
        reason: 'The "id" conflict target was the original bug — must not regress.',
      );
    });

    test('nutrition_logs upsert uses natural-key onConflict, not "id"', () {
      const marker = 'from("nutrition_logs").upsert';
      final start = src.indexOf(marker);
      expect(start, isNot(-1),
          reason: '_syncNutritionLogs must call nutrition_logs.upsert');
      final slice = src.substring(start, start + 400);

      expect(
        slice.contains('onConflict: "user_id,date,meal_type"'),
        isTrue,
        reason: 'nutrition_logs upsert MUST target the natural unique '
            '(user_id, date, meal_type). Pre-fix this was onConflict: "id" '
            'which lost 16 rows / 24h to 23505 in prod and left orphan '
            'nutrition_log_items rows pointing at a never-created parent.',
      );
      expect(
        slice.contains('onConflict: "id"'),
        isFalse,
        reason: 'The "id" conflict target was the bug — must not regress.',
      );
    });
  });
}
