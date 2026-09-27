import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/sync_hash_skip_atomicity_lib.dart';

const _p = 'lib/core/services/sync/sync_x.dart';

Map<String, String> _one(String src) => {_p: src};

void main() {
  group('findSyncWriteCalls', () {
    test('finds a Supabase upsert and its table, both quote styles', () {
      const src = "Future<void> _a() async {\n"
          "  await _supabase.client.from('water_logs').upsert({'x': 1});\n"
          "  await _supabase.client.from(\"nutrition_logs\").upsert({'y': 2});\n"
          "}";
      final calls = findSyncWriteCalls(_p, src);
      expect(calls.map((c) => c.table), ['water_logs', 'nutrition_logs']);
      expect(calls.map((c) => c.line), [2, 3]);
    });

    test('ignores Hive and List writes (no .from literal in the statement)', () {
      const src = "void f() {\n"
          "  final m = Map<String, dynamic>.from(raw);\n"
          "  box.delete(k);\n"
          "  queue.insert(0, {'a': 1});\n"
          "}";
      expect(findSyncWriteCalls(_p, src), isEmpty);
    });

    test('finds a chained .delete() on a multi-line statement', () {
      const src = "void f() async {\n"
          "  await _supabase.client\n"
          "      .from('template_exercises')\n"
          "      .delete()\n"
          "      .eq('template_id', id);\n"
          "}";
      final calls = findSyncWriteCalls(_p, src);
      expect(calls, hasLength(1));
      expect(calls.single.verb, 'delete');
      expect(calls.single.table, 'template_exercises');
    });
  });

  group('checkSyncStructure', () {
    test('an unwrapped history write is a violation', () {
      const src = "Future<void> _syncWaterLogs(String u) async {\n"
          "  for (final e in rows) {\n"
          "    await _supabase.client.from('water_logs').upsert(e);\n"
          "  }\n"
          "}";
      final violations = checkSyncStructure(_one(src));
      expect(violations, hasLength(1));
      expect(violations.single.kind, 'unwrapped_write');
      expect(violations.single.line, 3);
    });

    test('a write inside a pushIfChanged closure passes', () {
      const src = "Future<void> _syncWaterLogs(String u) async {\n"
          "  for (final e in rows) {\n"
          "    await idx.pushIfChanged(e.key, () => fp(e), () async {\n"
          "      await _supabase.client.from('water_logs').upsert(e);\n"
          "      return true;\n"
          "    });\n"
          "  }\n"
          "}";
      expect(checkSyncStructure(_one(src)), isEmpty);
    });

    test('a write in an allowlisted method passes', () {
      const src = "Future<void> _syncUserProfile(String u) async {\n"
          "  await _supabase.client.from('user_profile').upsert(p);\n"
          "}";
      expect(checkSyncStructure(_one(src)), isEmpty);
    });

    test('the same write in a method NOT on the allowlist is a violation', () {
      const src = "Future<void> _syncUserProfileTwo(String u) async {\n"
          "  await _supabase.client.from('user_profile').upsert(p);\n"
          "}";
      final violations = checkSyncStructure(_one(src));
      expect(violations, hasLength(1));
    });

    test('a swallowing catch inside pushIfChanged is a violation', () {
      const src = "Future<void> f() async {\n"
          "  await idx.pushIfChanged(k, () => fp, () async {\n"
          "    try {\n"
          "      await _supabase.client.from('water_logs').upsert(e);\n"
          "    } catch (e) {\n"
          "      debugPrint('\$e');\n"
          "    }\n"
          "    return true;\n"
          "  });\n"
          "}";
      final violations = checkSyncStructure(_one(src));
      expect(violations.map((v) => v.kind), ['swallowing_catch']);
    });

    test('a catch that returns false or rethrows passes', () {
      const src = "Future<void> f() async {\n"
          "  await idx.pushIfChanged(k, () => fp, () async {\n"
          "    try { await _supabase.client.from('water_logs').upsert(e); } catch (_) { return false; }\n"
          "    try { await _supabase.client.from('water_logs').upsert(e); } on StateError { rethrow; }\n"
          "    return true;\n"
          "  });\n"
          "}";
      expect(checkSyncStructure(_one(src)), isEmpty);
    });

    test('.catchError inside pushIfChanged is a violation', () {
      const src = "Future<void> f() async {\n"
          "  await idx.pushIfChanged(k, () => fp, () async {\n"
          "    await _supabase.client.from('water_logs').upsert(e).catchError((_) {});\n"
          "    return true;\n"
          "  });\n"
          "}";
      final violations = checkSyncStructure(_one(src));
      expect(violations.map((v) => v.kind), ['catch_error_in_push']);
    });

    test('an index-key literal outside sync_skip_index.dart is a violation', () {
      const src = "const k = 'sync_water_payload_hash_index';";
      final violations = checkSyncStructure(_one(src));
      expect(violations.map((v) => v.kind), ['index_literal_outside_helper']);
    });

    test('the same literal inside sync_skip_index.dart passes', () {
      const src = "const k = 'sync_water_payload_hash_index';";
      expect(
          checkSyncStructure(
              {'lib/core/services/sync/sync_skip_index.dart': src}),
          isEmpty);
    });

    test('a commented-out write is ignored', () {
      const src = "void f() {\n  // await _supabase.client.from('water_logs').upsert(e);\n}";
      expect(checkSyncStructure(_one(src)), isEmpty);
    });

    test('files outside the sync layer are ignored', () {
      const src = "Future<void> g() async { await c.from('water_logs').upsert(e); }";
      expect(
          checkSyncStructure(
              {'lib/core/services/workout_write_service.dart': src}),
          isEmpty);
    });

    test('an aliased query builder stored in a variable is a violation '
        '(fix round 1: it evades findSyncWriteCalls entirely, since the '
        'eventual .upsert( call carries no .from( of its own)', () {
      const src = "Future<void> f() async {\n"
          "  final row = _supabase.client.from('water_logs');\n"
          "  await idx.pushIfChanged(k, () => fp, () async {\n"
          "    await row.upsert(e);\n"
          "    return true;\n"
          "  });\n"
          "}";
      final violations = checkSyncStructure(_one(src));
      expect(violations, hasLength(1));
      expect(violations.single.kind, 'aliased_query_builder');
      expect(violations.single.line, 2);
    });

    test('an executed read assigned to a variable is not flagged as aliased '
        '(.select( is a terminal read, not a stored builder)', () {
      const src =
          "final res = await _supabase.client.from('t').select();";
      expect(checkSyncStructure(_one(src)), isEmpty);
    });

    test('an executed write assigned to a variable is not flagged as '
        'aliased (it has a write verb; existing unwrapped_write rules '
        'apply instead)', () {
      const src = "final r = await client.from('t').upsert(x);";
      final violations = checkSyncStructure(_one(src));
      expect(violations.map((v) => v.kind), ['unwrapped_write']);
    });

    test('an aliased builder inside a comment is not flagged', () {
      const src =
          "void f() {\n  // final row = _supabase.client.from('t');\n}";
      expect(checkSyncStructure(_one(src)), isEmpty);
    });

    test('a realtime stream subscription assigned to a variable is not '
        'flagged as aliased (fix round 1 false positive found live in '
        'sync_realtime.dart:78 — .stream(...).listen(...) is a terminal '
        'op that opens a channel, never later called with a write verb)',
        () {
      const src = "void f() {\n"
          "  _realtimeSubscription = _supabase.client\n"
          "      .from('weight_logs')\n"
          "      .stream(primaryKey: ['id'])\n"
          "      .eq('user_id', userId)\n"
          "      .listen((rows) {});\n"
          "}";
      expect(checkSyncStructure(_one(src)), isEmpty);
    });
  });

  group('the real sync layer', () {
    Map<String, String> realSources() {
      final out = <String, String>{
        'lib/core/services/sync_service.dart':
            File('lib/core/services/sync_service.dart').readAsStringSync(),
      };
      for (final f in Directory('lib/core/services/sync')
          .listSync(recursive: true)
          .whereType<File>()) {
        final rel = f.path.replaceAll(r'\', '/');
        if (rel.endsWith('.dart')) out[rel] = f.readAsStringSync();
      }
      return out;
    }

    test('writes exactly the 26 known tables (spec §13 #6 source list)', () {
      expect(enumerateSyncWriteTables(realSources()), {
        'ai_coach_interactions', 'body_measurements', 'coach_memory',
        'daily_steps', 'notifications_inbox', 'nutrition_log_items',
        'nutrition_logs', 'readiness_daily', 'saved_diet_plans',
        'scheduled_workouts', 'sleep_logs', 'streaks', 'template_exercises',
        'user_custom_exercises', 'user_custom_foods', 'user_preferences',
        'user_profile', 'user_progress', 'user_saved_meals', 'water_logs',
        'weight_logs', 'workout_log_exercises', 'workout_log_sets',
        'workout_logs', 'workout_schedule_completions', 'workout_templates',
      });
    });

    test('every allowlisted method still exists (a stale entry is a silent hole)', () {
      final all = realSources().values.join('\n');
      for (final name in kSyncWriteAllowlist) {
        expect(
            RegExp(r'(?:Future(?:<[^;{()]*>)?|void)\s+' + name + r'\s*\(')
                .hasMatch(all),
            isTrue,
            reason: '$name is allowlisted but no longer declared');
      }
    });
  });
}
