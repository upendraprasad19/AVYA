// Regression test for audit-2026-05-17 OI-06 — Partial UNIQUE arbiter
// audit closure.
//
// Background (`feedback_partial_unique_arbiter_trap.md` + APK Test #16):
// Partial UNIQUE indexes (WITH WHERE clause) can trip 42P10 when used
// as ON CONFLICT arbiters AND any arbiter column is nullable, because
// the planner can't statically prove the predicate matches the
// inserting row. Migration 064 dropped 3 partial uniques on
// workout_logs / workout_log_exercises / nutrition_logs after silent
// data loss on 2026-05-15.
//
// Live audit 2026-05-17: only 2 partial UNIQUE indexes remain in
// public schema:
//   user_custom_exercises  (user_id, lower(name))
//                          WHERE user_id IS NOT NULL AND name IS NOT NULL
//   user_custom_foods      (user_id, lower(name))
//                          WHERE user_id IS NOT NULL AND name IS NOT NULL
//
// Both have nullable user_id (NULL for "deleted user" pseudonymization
// per migration 049 DPDP §17). Both could trip 42P10 IF used as
// ON CONFLICT arbiter with a NULL user_id row.
//
// Client safety: both upsert paths use `onConflict: 'id'` (the PK,
// non-partial). NOT the partial UNIQUE. So no 42P10 trap from client
// code today.
//
// This test PINS the safety: any new upsert call to these 2 tables
// that uses `onConflict` containing `user_id` or `name` (i.e. the
// partial-unique arbiter columns) will fail this gate. Forces the
// author to either:
//   (a) target the PK instead, OR
//   (b) make the partial index non-partial in a migration.
//
// closes-diagnose: 2026-05-17-partial-unique-arbiter-audit-9d2a47
// closes-oi: OI-06

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OI-06 — partial UNIQUE arbiter safety', () {
    test('user_custom_exercises upserts target onConflict: id (PK, non-partial)',
        () {
      final src = File('lib/core/services/sync/sync_community.dart')
          .readAsStringSync();
      // Slice the source from each `from('user_custom_exercises')` for
      // up to 600 chars (covers the multi-line upsert form with
      // _projectCustomExercise call). Within each slice, REQUIRE
      // `onConflict: 'id'`.
      const tbl = "user_custom_exercises";
      final marker = "from('$tbl')";
      var pos = 0;
      var hits = 0;
      while (true) {
        final ix = src.indexOf(marker, pos);
        if (ix < 0) break;
        hits++;
        final slice = src.substring(ix, (ix + 600).clamp(0, src.length));
        // The slice may include OTHER from() blocks; trim at the next
        // `from('` to keep the assertion scoped to THIS upsert.
        final nextFrom = slice.indexOf("from('", marker.length);
        final scoped =
            nextFrom > 0 ? slice.substring(0, nextFrom) : slice;
        // The upsert call must include `onConflict: 'id'`. We allow
        // either inline or on a following line.
        if (scoped.contains('.upsert(')) {
          expect(scoped.contains("onConflict: 'id'"), isTrue,
              reason: '$tbl upsert MUST target onConflict: id (PK). '
                  'Partial UNIQUE (user_id, lower(name)) WHERE user_id '
                  'IS NOT NULL is 42P10-unsafe because user_id is '
                  'nullable. Slice:\n$scoped');
        }
        pos = ix + marker.length;
      }
      expect(hits, greaterThan(0),
          reason: 'Expected at least one $tbl reference.');
    });

    test('user_custom_foods upserts target onConflict: id (PK, non-partial)',
        () {
      final src = File('lib/core/services/sync/sync_community.dart')
          .readAsStringSync();
      const tbl = "user_custom_foods";
      final marker = "from('$tbl')";
      var pos = 0;
      var hits = 0;
      while (true) {
        final ix = src.indexOf(marker, pos);
        if (ix < 0) break;
        hits++;
        final slice = src.substring(ix, (ix + 600).clamp(0, src.length));
        final nextFrom = slice.indexOf("from('", marker.length);
        final scoped =
            nextFrom > 0 ? slice.substring(0, nextFrom) : slice;
        if (scoped.contains('.upsert(')) {
          expect(scoped.contains("onConflict: 'id'"), isTrue,
              reason: '$tbl upsert MUST target onConflict: id (PK). '
                  'Same trap as user_custom_exercises.');
        }
        pos = ix + marker.length;
      }
      expect(hits, greaterThan(0));
    });

    test(
        'no other upsert references the partial-unique arbiter columns of '
        'these 2 tables', () {
      // Scan ALL sync files for upserts to either table that include
      // user_id or name in the onConflict arbiter list.
      final syncDir = Directory('lib/core/services/sync');
      expect(syncDir.existsSync(), isTrue);
      for (final entity in syncDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        for (final tbl in const [
          'user_custom_exercises',
          'user_custom_foods',
        ]) {
          final partialArbiterRe = RegExp(
            "from\\('$tbl'\\)[\\s\\S]{0,400}?onConflict:\\s*'[^']*(user_id|name|lower)[^']*'",
          );
          expect(
            partialArbiterRe.hasMatch(src),
            isFalse,
            reason:
                'File ${entity.path} contains a $tbl upsert with '
                'onConflict referencing user_id / name / lower(...). '
                'These columns back the partial UNIQUE index — using '
                'them as ON CONFLICT arbiter trips 42P10 silently. '
                'Use onConflict: id (PK) instead, OR drop the partial '
                'predicate in a migration.',
          );
        }
      }
    });
  });
}
