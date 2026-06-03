import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Pins the cross-user sync-ID collision fix (diagnose d4b8e2): every per-user
/// sync upsert uses a USER-INCLUSIVE onConflict, the health upserts no longer
/// send a date-only deterministic id, and migration 082 backs the keys with
/// user-inclusive UNIQUE indexes + widens wls_reps_realistic.
void main() {
  final w = _strip(
      File('lib/core/services/sync/sync_workout.dart').readAsStringSync());
  final h = _strip(
      File('lib/core/services/sync/sync_health.dart').readAsStringSync());
  final n = _strip(
      File('lib/core/services/sync/sync_nutrition.dart').readAsStringSync());
  final mig = File(
          'supabase/migrations/082_user_scoped_sync_natural_keys.sql')
      .readAsStringSync();
  final mig83 = File(
          'supabase/migrations/083_nutrition_sync_natural_keys.sql')
      .readAsStringSync();

  group('sync upserts are user-scoped', () {
    test('workout_logs + workout_log_exercises/sets use user-inclusive onConflict',
        () {
      expect(w.contains("onConflict: 'user_id,date,workout_name'"), isTrue);
      expect(
          w.contains(
              "onConflict: 'user_id,workout_log_id,exercise_id,set_number'"),
          isTrue);
    });

    test('weight/sleep/body upserts use onConflict user_id,date', () {
      expect(h.contains("onConflict: 'user_id,date'"), isTrue);
    });

    test('health upserts no longer send a date-only deterministic id', () {
      expect(h.contains('SyncService._deterministicId'), isFalse,
          reason: 'omit id → gen_random_uuid + user-inclusive natural key');
    });

    test('migration 082 adds user-inclusive unique indexes + widens wls reps',
        () {
      expect(mig.contains('uniq_weight_logs_user_date'), isTrue);
      expect(mig.contains('uniq_sleep_logs_user_date'), isTrue);
      expect(mig.contains('uniq_body_measurements_user_date'), isTrue);
      expect(mig.contains('uniq_wle_user_wlog_ex_set'), isTrue);
      expect(mig.contains('uniq_wls_user_wlog_ex_set'), isTrue);
      expect(mig.contains('wls_reps_realistic'), isTrue);
      expect(mig.contains('1000'), isTrue);
    });
  });

  // ── Same class, nutrition tables (diagnose f7e3a1) ──
  group('nutrition sync upserts are user/parent-scoped', () {
    test('nutrition_log_items: (log_id,item_index) onConflict + omits the '
        'user-independent deterministic item id', () {
      expect(n.contains("onConflict: 'log_id,item_index'"), isTrue);
      expect(n.contains("'item_index': i"), isTrue);
      // the old per-item deterministic id (no user component) is gone from code
      expect(n.contains("'id': itemCloudId"), isFalse,
          reason: 'omit id → gen_random_uuid; identity = (log_id,item_index)');
    });

    test('user_saved_meals: (user_id,name) onConflict + omits the '
        'name-only deterministic id', () {
      expect(n.contains("onConflict: 'user_id,name'"), isTrue);
      expect(n.contains('SyncService._deterministicId(hiveId)'), isFalse,
          reason: 'omit id → gen_random_uuid; identity = (user_id,name)');
    });

    test('item key is POSITION-based, never food_name (a meal can hold the '
        'same food twice → food_name would merge + lose data)', () {
      // The arbiter must be the per-item position, not its name.
      expect(n.contains("onConflict: 'log_id,food_name'"), isFalse);
      expect(mig83.contains('uniq_nli_logid_itemidx'), isTrue);
    });

    test('migration 083 backs the keys (item_index backfill + 2 unique indexes)',
        () {
      expect(mig83.contains('item_index'), isTrue);
      expect(mig83.contains('uniq_nli_logid_itemidx'), isTrue);
      expect(mig83.contains('uniq_user_saved_meals_user_name'), isTrue);
      // a deterministic per-log backfill so the unique index creates cleanly
      expect(mig83.contains('row_number() over'), isTrue);
      expect(mig83.contains('set not null'), isTrue);
    });
  });
}
