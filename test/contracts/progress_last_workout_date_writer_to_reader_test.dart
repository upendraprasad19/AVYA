// Slice C1 (streak/freeze restore ownership, addendum A) — writer -> reader pin
// for `user_progress.current_streak_weeks` and `user_progress.last_workout_date`.
//
// The BEHAVIOURAL proof of the server side is
// test/sql/cross_device_progress_optimistic_lock_verify.sql, Cases 22-31 (live
// Postgres, rolled-back transaction). The behavioural proof of the client side is
// test/contracts/last_workout_date_latest_wins_behavioral_test.dart. THIS file
// pins the SHAPE of the migration text and the client call sites, so a rewrite of
// either side cannot silently drop a guard:
//
//   * migration: GREATEST on BOTH columns, the explicit NULL branch in DECLARE,
//     the IST-today + 1 clamp, SECURITY DEFINER + search_path, the two guards,
//     the closing assertion block, the unchanged 13-argument signature, and a
//     literal reverse block that equals migration 115's function body.
//   * client: both RPC writers pass `last_workout_date` / `current_streak_weeks`
//     through, and both restore callers hand `mergeCloudProgress` an IST today.
//
// The migration is read from supabase/migrations/ once it has been applied (the
// highest-numbered file that CREATEs the function, when that is above 115);
// before the apply it is read from the reviewed draft under docs/plans/.
//
// Run: flutter test test/contracts/progress_last_workout_date_writer_to_reader_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';

const String _fn = 'update_user_progress_snapshot';
const String _draftPath =
    'docs/plans/streak-freeze-restore-ownership-addendum-a.migration-draft-c1.sql';
const String _m115Path =
    'supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql';

/// Collapses whitespace so a reformat cannot redden a shape assertion.
String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The reverse block of the C1 file: every `-- ` line after the ROLLBACK marker,
/// un-commented. Returns '' when the marker is absent.
String _reverseBlock(String raw) {
  final i = raw.indexOf('-- ROLLBACK (inline');
  if (i < 0) return '';
  final out = <String>[];
  var seenSql = false;
  for (final line in raw.substring(i).split('\n')) {
    final m = RegExp(r'^--\s?(.*)$').firstMatch(line);
    if (m == null) continue;
    final body = m.group(1)!;
    if (!seenSql && !body.startsWith('CREATE OR REPLACE FUNCTION')) continue;
    seenSql = true;
    out.add(body);
  }
  return out.join('\n');
}

void main() {
  final applied = latestMigrationDefining(_fn);
  final appliedNumber =
      applied == null ? -1 : migrationNumber(applied.uri.pathSegments.last);
  final c1File = appliedNumber > 115 ? applied! : File(_draftPath);
  final c1Raw = c1File.readAsStringSync();
  final c1Block = functionBlock(c1Raw, _fn)!;
  final c1 = _squash(c1Block);
  final m115Block = functionBlock(File(_m115Path).readAsStringSync(), _fn)!;

  group('C1 migration text ($_fn)', () {
    test('the source under test is a real file that defines the function', () {
      expect(c1File.existsSync(), isTrue, reason: c1File.path);
      expect(functionBlock(c1Raw, _fn), isNotNull);
    });

    test('current_streak_weeks is GREATEST, not a bare COALESCE', () {
      expect(
        c1.contains(
            'current_streak_weeks = GREATEST(COALESCE(p_current_streak_weeks, current_streak_weeks), current_streak_weeks)'),
        isTrue,
      );
      expect(
        c1.contains(
            'current_streak_weeks = COALESCE(p_current_streak_weeks, current_streak_weeks),'),
        isFalse,
      );
    });

    test('last_workout_date is GREATEST over the clamped value', () {
      expect(c1.contains('last_workout_date = GREATEST(v_date, last_workout_date)'),
          isTrue);
      expect(
        c1.contains(
            'last_workout_date = COALESCE(p_last_workout_date, last_workout_date)'),
        isFalse,
      );
    });

    test('the clamp is IST-today + 1 and the NULL branch is explicit', () {
      expect(
        c1.contains(
            "v_date DATE := CASE WHEN p_last_workout_date IS NULL THEN NULL ELSE LEAST(p_last_workout_date, ((now() AT TIME ZONE 'Asia/Kolkata')::date + 1)) END;"),
        isTrue,
      );
    });

    test('the fresh INSERT stores the clamped value, not the raw parameter', () {
      expect(c1.contains('COALESCE(p_current_streak_days, 0), v_date,'), isTrue);
      expect(c1.contains('COALESCE(p_current_streak_days, 0), p_last_workout_date,'),
          isFalse);
    });

    test('the three sibling GREATEST guards and both security guards survive', () {
      for (final col in const [
        'total_workouts_done',
        'deployments_complete',
        'longest_gap_days',
      ]) {
        expect(
          c1.contains(
              '$col = GREATEST(COALESCE(p_$col, $col), $col)'),
          isTrue,
          reason: col,
        );
      }
      expect(c1.contains('p_user_id IS NULL'), isTrue);
      expect(
          c1.contains('auth.uid() IS NOT NULL AND p_user_id <> auth.uid()'), isTrue);
      expect(c1.contains('cross-account progress write blocked'), isTrue);
      expect(c1.contains('SECURITY DEFINER'), isTrue);
      expect(c1.contains('SET search_path = public'), isTrue);
    });

    test('the signature is unchanged: 13 parameters, in 115\'s order', () {
      List<String> params(String block) {
        final m = RegExp(r'\(([\s\S]*?)\)\s*RETURNS').firstMatch(block)!;
        return m
            .group(1)!
            .split(',')
            .map((p) => p.trim().split(RegExp(r'\s+')).take(2).join(' '))
            .toList();
      }

      final now = params(c1Block);
      expect(now.length, 13);
      expect(now, params(m115Block));
    });

    test('a closing assertion block pins the ACL, search_path and arity', () {
      final stripped = stripSqlComments(c1Raw);
      expect(stripped.contains(r'DO $assert_fn$'), isTrue);
      expect(stripped.contains('aclexplode'), isTrue);
      expect(stripped.contains("ARRAY['authenticated', 'postgres', 'service_role']"),
          isTrue);
      expect(stripped.contains("ARRAY['search_path=public']"), isTrue);
      expect(stripped.contains('v_nargs <> 13'), isTrue);
    });

    test('the literal reverse block equals migration 115\'s function body', () {
      final reverse = _reverseBlock(c1Raw);
      expect(reverse, isNotEmpty);
      final reverseBlock = functionBlock(reverse, _fn);
      expect(reverseBlock, isNotNull);
      expect(_squash(reverseBlock!), _squash(m115Block));
    });
  });

  group('C1 client call sites', () {
    final profile = stripDartComments(
        File('lib/core/services/sync/sync_profile.dart').readAsStringSync());
    final boot = stripDartComments(
        File('lib/core/services/auth_session_bootstrapper.dart')
            .readAsStringSync());

    test('both RPC writers pass the two columns through to the RPC', () {
      expect(
          RegExp(r"'p_last_workout_date':\s*(progressData|p)\['last_workout_date'\]")
              .allMatches(profile)
              .length,
          2);
      expect(RegExp(r"'p_current_streak_weeks':").allMatches(profile).length, 2);
    });

    test('both restore callers give mergeCloudProgress an IST today', () {
      expect(
          RegExp(r'istToday:\s*istDateStr\(nowWall\(\)\)').allMatches(profile).length,
          greaterThanOrEqualTo(1));
      expect(
          RegExp(r'istToday:\s*istDateStr\(nowWall\(\)\)').allMatches(boot).length,
          greaterThanOrEqualTo(1));
    });
  });
}
