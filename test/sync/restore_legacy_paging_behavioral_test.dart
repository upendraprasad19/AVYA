@Timeout(Duration(minutes: 5))
library;

// Diagnose c7e2a9, addendum A Slice B2 (Unit 5b): the client's LEGACY restore
// legs (the fallback when the single-call restore is unavailable) page and
// order deterministically.
//
// PostgREST clamps every response to 1000 rows with an HTTP 200 and no error,
// so three reads (`workout_schedule_completions`, `user_custom_exercises`,
// `user_custom_foods`) silently dropped every row past the 1000th, and the
// paged `_fetchAllRows` ordered by ONE column, so rows tied on it could be
// skipped or served twice across a page seam.
//
// For those THREE tables the real protection is the PAGING: live, completions
// are UNIQUE (user_id, scheduled_date) and custom items carry a UNIQUE
// (user_id, lower(name)) index, so a tie on their sort column cannot happen in
// production and their `id` tie-break is belt and braces. The tie-order tests
// below therefore feed the helper synthetic duplicate dates on purpose (an
// adversarial input for the pager itself); the tables whose sort column really
// is non-unique (created_at, date) are covered by the order-string cases.
//
// These tests run the REAL SyncService against a stub that really pages
// (`SyncStubServer.pagedTables`: filters, `order=`, offset/limit, the 1000-row
// clamp, optional adversarial tie reshuffle). A fake that ignores its
// parameters cannot catch the removal of those parameters; this one answers
// 400 / 42703 to any request shape it does not model, and every test's
// tearDown asserts it never had to.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_flags.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

const _since = '2020-01-01T00:00:00Z';
const _killSwitch = 'disable_restore_paging_fix';

String _day(int k) {
  final d = DateTime.utc(2019, 1, 1).add(Duration(days: k));
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}

String _id(int k) =>
    '00000000-0000-4000-8000-${k.toRadixString(16).padLeft(12, '0')}';

const _sameInstant = '2026-09-01T10:00:00+00:00';

/// A hang on an unanswered request must fail in minutes, not at the file timeout.
Future<void> _within(Future<void> Function() call) =>
    call().timeout(const Duration(minutes: 2));

/// [n] completions, [perDate] of them sharing each `scheduled_date`, ALL with
/// the same `completed_at` / `created_at` (the worst case for tie ordering).
List<Map<String, dynamic>> _completions(int n, {int perDate = 1}) => [
      for (var k = 0; k < n; k++)
        {
          'id': _id(k),
          'user_id': kTestUserId,
          'scheduled_date': _day(k ~/ perDate),
          'day_of_week': 1,
          'workout_name': 'Session $k',
          'duration_seconds': 1800,
          'completed_at': _sameInstant,
          'created_at': _sameInstant,
        },
    ];

List<Map<String, dynamic>> _customExercises(int n) => [
      for (var k = 0; k < n; k++)
        {
          'id': _id(k),
          'user_id': kTestUserId,
          'name': 'Move $k',
          'logging_type': 'weight_reps',
          'created_at': _sameInstant,
        },
    ];

List<StubRequest> _gets(SyncHarness h, String table) => h.server.requests
    .where((r) => r.method == 'GET' && r.table == table)
    .toList();

/// Every row the stub answered with, across all requests, in answer order.
List<Object?> _served(SyncHarness h, String table) => [
      for (final page in h.server.pagedServed[table] ?? const <List<Object?>>[])
        ...page,
    ];

void _expectEachServedOnce(SyncHarness h, String table, int total) {
  final served = _served(h, table);
  expect(served, hasLength(total),
      reason: '$table: the pages together carry exactly $total rows');
  expect(served.toSet(), hasLength(total),
      reason: '$table: no row is served twice (and so none is skipped)');
}

/// Every filter column and every order column the code SENT to a paged table is
/// a live column of that table. Checked against the recorded requests, not
/// against names this file typed, so a typo written the same way in the code
/// and in a seeded row (which the stub would happily match) cannot pass.
void _expectSentColumnsAreLive(SyncHarness h) {
  const reserved = {'select', 'order', 'limit', 'offset', 'columns', 'on_conflict'};
  final live = loadLiveSchemaColumns();
  for (final r in h.server.requests) {
    final table = r.table;
    if (r.method != 'GET' || table == null) continue;
    if (!h.server.pagedTables.containsKey(table)) continue;
    final cols = live[table];
    expect(cols, isNotNull, reason: '$table is in backups/live_schema_columns.json');
    final sent = <String>{
      for (final k in r.query.keys)
        if (!reserved.contains(k)) k,
      for (final term in (r.query['order'] ?? '').split(','))
        if (term.isNotEmpty) term.split('.').first,
    };
    for (final c in sent) {
      expect(cols, contains(c),
          reason: 'the code sent a filter or order on $table.$c, which is not a '
              'live column (request order=${r.query['order']})');
    }
  }
}

int _keysWithPrefix(Box<dynamic> box, String prefix) =>
    box.keys.where((k) => k is String && k.startsWith(prefix)).length;

void main() {
  // A FRESH harness (and so a fresh stub: its recorded requests, paged tables,
  // clamp and tie reshuffle) per test. One shared SyncHarness keeps every
  // request of every earlier test in `server.requests` and leaks its paged
  // tables, clamp and reshuffle flag into the next test.
  late SyncHarness h;
  setUp(() async {
    h = SyncHarness();
    await h.setUp();
  });
  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    final unmodelled = List<String>.of(h.server.pagedErrors);
    await h.tearDown();
    _expectSentColumnsAreLive(h);
    expect(unmodelled, isEmpty,
        reason: 'the stub answered 400 to a request it could not model: a '
            'swallowed 400 must not pass for an empty restore');
  });

  group('schedule completions (item 2): every row lands, paged, owner-scoped', () {
    test('2,500 completions all reach Hive through three owner-scoped pages; a row older than since stays out',
        () async {
      h.server.pagedTables['workout_schedule_completions'] = [
        ..._completions(2500),
        {
          ..._completions(1).single,
          'id': _id(9999),
          'scheduled_date': '2000-01-01',
          'completed_at': '2019-12-31T23:59:59+00:00',
        },
      ];

      await _within(() => SyncService.instance
          .restoreScheduleCompletionsForSyncDomain(since: _since));

      final gets = _gets(h, 'workout_schedule_completions');
      expect(gets.map((r) => r.query['offset']).toList(), ['0', '1000', '2000']);
      for (final r in gets) {
        expect(r.query['user_id'], 'eq.$kTestUserId');
        expect(r.query['completed_at'], 'gte.$_since');
        expect(r.query['limit'], '1000');
        expect(r.query['order'],
            'scheduled_date.desc.nullslast,id.desc.nullslast');
      }
      final box = HiveService.instance.workoutBox;
      expect(_keysWithPrefix(box, 'schedule_'), 2500);
      expect(box.get('schedule_2000-01-01'), isNull,
          reason: 'the completed_at >= since filter must have been sent');
      expect((box.get('schedule_${_day(2499)}') as Map)['status'], 'completed');
      expect((box.get('schedule_${_day(0)}') as Map)['status'], 'completed');
      _expectEachServedOnce(h, 'workout_schedule_completions', 2500);
    });

    test('exactly 2,000 rows: a full last page is followed by one empty confirming page', () async {
      h.server.pagedTables['workout_schedule_completions'] = _completions(2000);

      await _within(() => SyncService.instance
          .restoreScheduleCompletionsForSyncDomain(since: _since));

      final gets = _gets(h, 'workout_schedule_completions');
      expect(gets.map((r) => r.query['offset']).toList(), ['0', '1000', '2000']);
      expect(_served(h, 'workout_schedule_completions'), hasLength(2000));
      expect(_keysWithPrefix(HiveService.instance.workoutBox, 'schedule_'), 2000);
    });

    test('page seams on tied scheduled_date neither skip nor duplicate a row', () async {
      // 2,499 rows = 833 dates x 3. Tie groups start at result positions
      // 0, 3, 6, ...; 1000 mod 3 = 1 and 2000 mod 3 = 2, so a tie group
      // straddles BOTH page seams (positions 999..1001 and 1998..2000). The
      // stub reverses tied rows on alternate requests, exactly what an unstable
      // Postgres order may do. (Live, completions are unique per date: see the
      // file header. This is an adversarial input for the pager.)
      h.server.reshuffleTies = true;
      h.server.pagedTables['workout_schedule_completions'] =
          _completions(2499, perDate: 3);

      await _within(() => SyncService.instance
          .restoreScheduleCompletionsForSyncDomain(since: _since));

      _expectEachServedOnce(h, 'workout_schedule_completions', 2499);
      expect(_keysWithPrefix(HiveService.instance.workoutBox, 'schedule_'), 833,
          reason: 'a sanity count only: ties collapse to one key per date, so '
              'the wire-level assertion above is what proves no row was lost');
    });

    test('NEGATIVE CONTROL: a read ordered by the non-unique column alone DOES skip and duplicate across the seam',
        () async {
      // Proves the adversarial stub can fail the test above: with the
      // tie-break removed (what the mutation does) rows are lost and doubled.
      h.server.reshuffleTies = true;
      h.server.pagedTables['workout_schedule_completions'] =
          _completions(2499, perDate: 3);
      final client = SupabaseService.instance.client;
      final ids = <Object?>[];
      for (final offset in [0, 1000, 2000]) {
        final page = await client
            .from('workout_schedule_completions')
            .select()
            .eq('user_id', kTestUserId)
            .order('scheduled_date', ascending: false)
            .range(offset, offset + 999);
        ids.addAll(page.map((r) => r['id']));
      }
      expect(ids, hasLength(2499), reason: 'page sizes are still 1000/1000/499');
      expect(ids.toSet().length, lessThan(2499),
          reason: 'a row was served twice, so another was never served');
    });

    test('kill switch: one un-paged owner-scoped read, the pre-fix order, and the old 1000-row loss',
        () async {
      await HiveService.instance.configBox.put(_killSwitch, true);
      h.server.pagedTables['workout_schedule_completions'] = [
        ..._completions(2500),
        {
          ..._completions(1).single,
          'id': _id(9999),
          'scheduled_date': '2000-01-01',
          'completed_at': '2019-12-31T23:59:59+00:00',
        },
      ];

      await _within(() => SyncService.instance
          .restoreScheduleCompletionsForSyncDomain(since: _since));

      final gets = _gets(h, 'workout_schedule_completions');
      expect(gets, hasLength(1));
      expect(gets.single.query['user_id'], 'eq.$kTestUserId',
          reason: 'the verbatim revert is still owner-scoped');
      expect(gets.single.query['completed_at'], 'gte.$_since');
      expect(gets.single.query['order'], 'scheduled_date.desc.nullslast');
      expect(gets.single.query.containsKey('offset'), isFalse);
      expect(gets.single.query.containsKey('limit'), isFalse);
      final box = HiveService.instance.workoutBox;
      expect(_keysWithPrefix(box, 'schedule_'), 1000,
          reason: 'the clamped read lands only the newest 1000 dates');
      expect(box.get('schedule_${_day(2499)}'), isNotNull);
      expect(box.get('schedule_${_day(1499)}'), isNull);
      expect(box.get('schedule_2000-01-01'), isNull);
    });
  });

  group('custom exercises and foods (item 3): 1,500 each all land', () {
    test('both tables page through _fetchAllRows with the id tie-break, no since', () async {
      h.server.reshuffleTies = true;
      h.server.pagedTables['user_custom_exercises'] = _customExercises(1500);
      h.server.pagedTables['user_custom_foods'] = [
        for (var k = 0; k < 1500; k++)
          {
            'id': _id(k),
            'user_id': kTestUserId,
            'name': 'Food $k',
            'calories_per_100g': 100,
            'created_at': _sameInstant,
          },
      ];

      await _within(() => SyncService.instance.restoreCustomItemsForSyncDomain());

      for (final table in ['user_custom_exercises', 'user_custom_foods']) {
        final gets = _gets(h, table);
        expect(gets.map((r) => r.query['offset']).toList(), ['0', '1000'],
            reason: table);
        for (final r in gets) {
          expect(r.query['user_id'], 'eq.$kTestUserId');
          expect(r.query['order'], 'created_at.desc.nullslast,id.desc.nullslast');
          expect(r.query.keys.where((k) => k == 'created_at'), isEmpty,
              reason: 'no since filter: the custom restore takes every row');
        }
        _expectEachServedOnce(h, table, 1500);
      }
      final box = HiveService.instance.customBox;
      expect(_keysWithPrefix(box, 'custom_exercise_'), 1500);
      expect(_keysWithPrefix(box, 'custom_food_'), 1500);
    });

    test('kill switch: one owner-scoped bare select, no order, clamped to 1000 (the pre-fix read)',
        () async {
      await HiveService.instance.configBox.put(_killSwitch, true);
      h.server.pagedTables['user_custom_exercises'] = _customExercises(1500);

      await _within(() => SyncService.instance.restoreCustomItemsForSyncDomain());

      final gets = _gets(h, 'user_custom_exercises');
      expect(gets, hasLength(1));
      expect(gets.single.query['user_id'], 'eq.$kTestUserId',
          reason: 'the verbatim revert is still owner-scoped');
      expect(gets.single.query.containsKey('order'), isFalse);
      expect(gets.single.query.containsKey('offset'), isFalse);
      expect(_keysWithPrefix(HiveService.instance.customBox, 'custom_exercise_'),
          1000);
    });
  });

  group('the community-catalogue pull orders its pages by a unique column too', () {
    List<Map<String, dynamic>> approved(int n, String flag) => [
          for (var k = 0; k < n; k++)
            {
              'id': _id(k),
              'user_id': kTestUserId,
              'name': 'Community $k',
              flag: true,
              'created_at': _sameInstant,
            },
        ];

    test('1,200 approved foods and exercises tied on created_at: three pages each, id last, each row once',
        () async {
      h.server.reshuffleTies = true;
      h.server.pagedTables['user_custom_foods'] = approved(1200, 'approved');
      h.server.pagedTables['user_custom_exercises'] =
          approved(1200, 'approved_for_library');

      await _within(() => SyncService.instance.syncCommunityItems());

      final filters = {
        'user_custom_foods': 'approved',
        'user_custom_exercises': 'approved_for_library',
      };
      for (final e in filters.entries) {
        final gets = _gets(h, e.key);
        expect(gets.map((r) => r.query['offset']).toList(), ['0', '500', '1000'],
            reason: e.key);
        for (final r in gets) {
          expect(r.query[e.value], 'eq.true');
          expect(r.query['limit'], '500');
          expect(r.query['order'], 'created_at.asc.nullslast,id.asc.nullslast');
        }
        _expectEachServedOnce(h, e.key, 1200);
      }
      expect(
          _keysWithPrefix(HiveService.instance.foodBox, '00000000-0000-4000-8000-'),
          1200);
      expect(
          _keysWithPrefix(
              HiveService.instance.exerciseBox, '00000000-0000-4000-8000-'),
          1200);
    });

    test('a pull that fills its 10-page cap says so, naming the pull and the table', () async {
      final events = <(String, String?)>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (opType, {String? message}) => events.add((opType, message));
      // 10 pages x 500 = 5,000: the pull stops at its cap, then stamps
      // last_community_sync, so rows beyond it are never refetched.
      h.server.pagedTables['user_custom_foods'] = approved(5000, 'approved');
      h.server.pagedTables['user_custom_exercises'] =
          approved(5000, 'approved_for_library');

      await _within(() => SyncService.instance.syncCommunityItems());

      expect(_gets(h, 'user_custom_foods'), hasLength(10));
      expect(_gets(h, 'user_custom_exercises'), hasLength(10));
      expect(events.where((e) => e.$1 == 'restore_row_ceiling_hit').toList(), [
        ('restore_row_ceiling_hit', 'community_pull:user_custom_foods'),
        ('restore_row_ceiling_hit', 'community_pull:user_custom_exercises'),
      ]);
    });

    test('a pull that ends short of its cap emits no event (the mirror of the cap test)', () async {
      final events = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (opType, {String? message}) => events.add(opType);
      // 4,600 rows = nine full pages and a short tenth page: the cap is never
      // filled, so the pull has read EVERYTHING and must not cry wolf.
      h.server.pagedTables['user_custom_foods'] = approved(4600, 'approved');
      h.server.pagedTables['user_custom_exercises'] =
          approved(4600, 'approved_for_library');

      await _within(() => SyncService.instance.syncCommunityItems());

      expect(_gets(h, 'user_custom_foods'), hasLength(10));
      expect(_gets(h, 'user_custom_exercises'), hasLength(10));
      expect(events, isNot(contains('restore_row_ceiling_hit')));
    });

    test('kill switch: the pre-fix single-column order', () async {
      await HiveService.instance.configBox.put(_killSwitch, true);
      h.server.pagedTables['user_custom_foods'] = approved(10, 'approved');
      h.server.pagedTables['user_custom_exercises'] =
          approved(10, 'approved_for_library');

      await _within(() => SyncService.instance.syncCommunityItems());

      for (final table in ['user_custom_foods', 'user_custom_exercises']) {
        expect(_gets(h, table).single.query['order'], 'created_at.asc.nullslast');
      }
    });
  });

  group('readiness_daily has no id column: its tie-break is date', () {
    test('2,500 rows tied on created_at all land; the request orders by date and never by id',
        () async {
      h.server.reshuffleTies = true;
      h.server.pagedTables['readiness_daily'] = [
        for (var k = 0; k < 2500; k++)
          {
            'user_id': kTestUserId,
            'date': _day(k),
            'sleep': 3,
            'soreness': 2,
            'energy': 4,
            'level': 'green',
            'created_at': _sameInstant,
          },
      ];

      await _within(() =>
          SyncService.instance.restoreReadinessForSyncDomain(since: _since));

      final gets = _gets(h, 'readiness_daily');
      expect(gets, hasLength(3));
      for (final r in gets) {
        expect(r.query['order'], 'created_at.desc.nullslast,date.desc.nullslast');
        expect(r.query['order'], isNot(contains('id')),
            reason: 'readiness_daily has no id column: ordering by it would 400');
      }
      _expectEachServedOnce(h, 'readiness_daily', 2500);
      expect(_keysWithPrefix(HiveService.instance.healthBox, 'readiness_'), 2500);
    });
  });

  group('nutrition logs: the loop that is not _fetchAllRows pages and orders the same way', () {
    test('2,500 logs tied on created_at: three pages, id last, each served once, all land',
        () async {
      h.server.reshuffleTies = true;
      h.server.pagedTables['nutrition_logs'] = [
        for (var k = 0; k < 2500; k++)
          {
            'id': _id(k),
            'user_id': kTestUserId,
            'date': _day(k),
            'meal_type': 'lunch',
            'total_calories': 100,
            'created_at': _sameInstant,
            'nutrition_log_items': [
              {
                'food_id': 'f$k',
                'food_name': 'Rice $k',
                'quantity_g': 100,
                'calories': 100,
                'protein': 5,
                'carbs': 20,
                'fat': 1,
                'fiber': 1,
                'item_index': 0,
              },
            ],
          },
      ];

      await _within(() =>
          SyncService.instance.restoreNutritionLogsForSyncDomain(since: _since));

      final gets = _gets(h, 'nutrition_logs');
      expect(gets.map((r) => r.query['offset']).toList(), ['0', '1000', '2000']);
      for (final r in gets) {
        expect(r.query['user_id'], 'eq.$kTestUserId');
        expect(r.query['order'], 'created_at.desc.nullslast,id.desc.nullslast');
      }
      _expectEachServedOnce(h, 'nutrition_logs', 2500);
      expect(_keysWithPrefix(HiveService.instance.nutritionBox, 'nlog_'), 2500);
    });

    test('a nutrition table that fills the ceiling emits ONE restore_row_ceiling_hit naming the table',
        () async {
      final events = <(String, String?)>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (opType, {String? message}) => events.add((opType, message));
      // Rows with an empty id are skipped by the restore loop, so 50,000 of
      // them cost 50 stub pages but no Hive writes.
      h.server.pagedTables['nutrition_logs'] = [
        for (var k = 0; k < 50000; k++)
          {'id': '', 'user_id': kTestUserId, 'created_at': _sameInstant},
      ];

      await _within(() =>
          SyncService.instance.restoreNutritionLogsForSyncDomain(since: _since));

      expect(_gets(h, 'nutrition_logs'), hasLength(50));
      expect(events.where((e) => e.$1 == 'restore_row_ceiling_hit').toList(),
          [('restore_row_ceiling_hit', 'nutrition_logs')]);
    });
  });

  group('every paged caller sends its own unique tie-break, last', () {
    // table, driver, order with the fix, order with the kill switch set.
    final cases = <(String, Future<void> Function(), String, String)>[
      (
        'weight_logs',
        () => SyncService.instance.restoreWeightLogsForSyncDomain(since: _since),
        'created_at.desc.nullslast,id.desc.nullslast',
        'created_at.desc.nullslast',
      ),
      (
        'body_measurements',
        () => SyncService.instance.restoreMeasurementsForSyncDomain(since: _since),
        'created_at.desc.nullslast,id.desc.nullslast',
        'created_at.desc.nullslast',
      ),
      (
        'sleep_logs',
        () => SyncService.instance.restoreSleepLogsForSyncDomain(since: _since),
        'created_at.desc.nullslast,id.desc.nullslast',
        'created_at.desc.nullslast',
      ),
      (
        'daily_steps',
        () => SyncService.instance.restoreStepsLogsForSyncDomain(since: _since),
        'date.desc.nullslast,id.desc.nullslast',
        'date.desc.nullslast',
      ),
      (
        'readiness_daily',
        () => SyncService.instance.restoreReadinessForSyncDomain(since: _since),
        'created_at.desc.nullslast,date.desc.nullslast',
        'created_at.desc.nullslast',
      ),
      (
        'water_logs',
        () => SyncService.instance.restoreWaterLogsForSyncDomain(since: _since),
        'date.desc.nullslast,id.desc.nullslast',
        'date.desc.nullslast',
      ),
      (
        'nutrition_logs',
        () => SyncService.instance.restoreNutritionLogsForSyncDomain(since: _since),
        'created_at.desc.nullslast,id.desc.nullslast',
        'created_at.desc.nullslast',
      ),
      (
        'workout_logs',
        () => SyncService.instance.restoreWorkoutLogsForSyncDomain(since: _since),
        'created_at.desc.nullslast,id.desc.nullslast',
        'created_at.desc.nullslast',
      ),
      (
        'workout_log_exercises',
        () => SyncService.instance.restoreExerciseLogsForSyncDomain(since: _since),
        'completed_at.desc.nullslast,created_at.desc.nullslast,id.desc.nullslast',
        'completed_at.desc.nullslast',
      ),
      (
        'workout_log_sets',
        () => SyncService.instance.restoreExerciseLogsForSyncDomain(since: _since),
        'completed_at.desc.nullslast,created_at.desc.nullslast,id.desc.nullslast',
        'completed_at.desc.nullslast',
      ),
    ];

    for (final c in cases) {
      final (table, drive, fixed, legacy) = c;
      test('$table: $fixed', () async {
        // Seeded EMPTY, so the stub never evaluates the order columns: check
        // every column the expected string names against the live schema, or a
        // typo (or an id on an id-less table) written the same way here and in
        // production would pass.
        final liveColumns = loadLiveSchemaColumns()[table];
        expect(liveColumns, isNotNull, reason: '$table is in the live schema');
        for (final term in fixed.split(',')) {
          expect(liveColumns, contains(term.split('.').first),
              reason: '$table has no column ${term.split('.').first}');
        }
        h.server.pagedTables[table] = [];
        await _within(drive);
        final gets = _gets(h, table);
        expect(gets, isNotEmpty, reason: '$table was read');
        expect(gets.first.query['order'], fixed);
        expect(gets.first.query['user_id'], 'eq.$kTestUserId');
      });
      test('$table with the kill switch: $legacy', () async {
        await HiveService.instance.configBox.put(_killSwitch, true);
        h.server.pagedTables[table] = [];
        await _within(drive);
        final gets = _gets(h, table);
        expect(gets, isNotEmpty, reason: '$table was read');
        expect(gets.first.query['order'], legacy);
        expect(gets.first.query['user_id'], 'eq.$kTestUserId');
      });
    }
  });

  group('the coach read is untouched: newest 1000, descending, one request', () {
    test('1,200 interactions: one GET, created_at descending, limit 1000, the newest 1000 land',
        () async {
      h.server.pagedTables['ai_coach_interactions'] = [
        for (var k = 0; k < 1200; k++)
          {
            'id': _id(k),
            'user_id': kTestUserId,
            'user_message': 'q$k',
            'ai_response': 'a$k',
            'model_used': 'm',
            'channel': 'chat',
            'created_at': DateTime.utc(2026, 9, 1)
                .add(Duration(seconds: k))
                .toIso8601String(),
          },
      ];

      await _within(() => SyncService.instance
          .restoreCoachInteractionsForSyncDomain(since: _since));

      final gets = _gets(h, 'ai_coach_interactions');
      expect(gets, hasLength(1));
      expect(gets.single.query['order'], 'created_at.desc.nullslast');
      expect(gets.single.query['limit'], '1000');
      expect(gets.single.query.containsKey('offset'), isFalse);
      final served = _served(h, 'ai_coach_interactions');
      expect(served, hasLength(1000));
      expect(served.first, _id(1199), reason: 'newest first');
      expect(served.last, _id(200), reason: 'the 200 oldest are the ones left out');
      expect(HiveService.instance.coachBox.length, 1000);
    });
  });

  group('the loop stops on a short page, which is right only while db-max-rows == pageSize', () {
    test('a server clamp BELOW the page size ends the read after one page (the assumption, DOCUMENTED, not detected)',
        () async {
      // Production's db-max-rows is 1000 == _fetchAllRows's pageSize (measured
      // 2026-10-06). If the cap is ever LOWERED, a clamped page looks "short",
      // the loop stops, and every later row is silently lost. This test
      // DOCUMENTS that by modelling a lower cap in the stub; it cannot DETECT a
      // lowered production cap (a platform setting the client never reads). If
      // the loop is ever changed to continue past a short page, this test goes
      // red on purpose and must change with it. Closure ledger:
      // B2-SHORT-PAGE-STOP.
      h.server.dbMaxRows = 500;
      h.server.pagedTables['workout_schedule_completions'] = _completions(2500);

      await _within(() => SyncService.instance
          .restoreScheduleCompletionsForSyncDomain(since: _since));

      expect(_gets(h, 'workout_schedule_completions'), hasLength(1));
      expect(_keysWithPrefix(HiveService.instance.workoutBox, 'schedule_'), 500);
    });
  });

  group('the 50,000-row ceiling is announced, not silent', () {
    test('a table that fills the ceiling emits ONE restore_row_ceiling_hit naming only the table',
        () async {
      final events = <(String, String?)>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (opType, {String? message}) => events.add((opType, message));
      // Rows with a null `date` are skipped by _restoreReadiness, so 50,000 of
      // them cost 50 stub pages but no Hive writes.
      h.server.pagedTables['readiness_daily'] = [
        for (var k = 0; k < 50000; k++)
          {'user_id': kTestUserId, 'date': null, 'created_at': _sameInstant},
      ];

      await _within(() =>
          SyncService.instance.restoreReadinessForSyncDomain(since: _since));

      expect(_gets(h, 'readiness_daily'), hasLength(50));
      expect(events.where((e) => e.$1 == 'restore_row_ceiling_hit').toList(),
          [('restore_row_ceiling_hit', 'readiness_daily')]);
    });

    test('a normal restore emits no ceiling event', () async {
      final events = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (opType, {String? message}) => events.add(opType);
      h.server.pagedTables['workout_schedule_completions'] = _completions(2500);

      await _within(() => SyncService.instance
          .restoreScheduleCompletionsForSyncDomain(since: _since));

      expect(events, isNot(contains('restore_row_ceiling_hit')));
    });
  });

  group('the kill switch fails toward the fix', () {
    test('with the config box not open, restorePagingFixEnabled is TRUE', () async {
      await HiveService.instance.configBox.close();
      expect(SyncFlags.restorePagingFixEnabled, isTrue);
    });

    test('set, restorePagingFixEnabled is FALSE; unset, TRUE', () async {
      expect(SyncFlags.restorePagingFixEnabled, isTrue);
      await HiveService.instance.configBox.put(_killSwitch, true);
      expect(SyncFlags.restorePagingFixEnabled, isFalse);
    });
  });
}
