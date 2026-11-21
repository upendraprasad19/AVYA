// test/contracts/sync_nutrition_log_id_resolved_before_upsert_test.dart
//
// Diagnose c9f2a7 (2026-06-01) — found live driving the AI coach as amar
// (year-sim power user): a coach `logMealByText` wrote to Hive correctly
// (Nutrition summary bumped 4314 -> 4644 kcal) but EVERY nutrition sync
// failed in the console with:
//
//   [SyncService._syncNutritionLogs] PostgrestException(... violates
//   foreign key constraint "nutrition_log_items_log_id_fkey", code: 23503,
//   ... Key is still referenced from table "nutrition_log_items".)
//
// Root cause: `_syncNutritionLogs` upserted `nutrition_logs` onConflict on the
// natural key (user_id,date,meal_type) while sending `id: _deterministicId(key)`.
// The `nlog_` Hive key embeds an itemsHash, so the SAME (date,meal_type) yields
// a DIFFERENT deterministic id whenever the item set changes (re-log / edit /
// coach-merge), and other writers (the headless sim, legacy keys) seeded rows
// under yet other ids. When a cloud row already exists for the natural key under
// a DIFFERENT id, ON CONFLICT DO UPDATE tries to rewrite the row's PK `id`.
// `nutrition_log_items.log_id` FK-references that PK with ON DELETE CASCADE but
// ON UPDATE NO ACTION (verified live: confdeltype='c', confupdtype='a'), so the
// PK change is rejected (23503) and the WHOLE parent upsert + its child items
// silently fail to reach cloud.
//
// Fix (recurrence of workout_templates APK Test #12.8 / Bug #4, diagnose a8b2c7,
// and scheduled_workouts APK Test #14 / Bug B.1, diagnose c8e4a1 — nutrition_logs
// was the last sync still sending a derived id): OMIT `id` from the upsert
// payload so PostgREST keeps the existing row's id on conflict (DO UPDATE sets
// only the columns present) and uses the column default gen_random_uuid() on
// first insert — the PK is never rewritten. Then resolve the real cloud id by
// the natural key for the children's `log_id`.
//
// This is a SOURCE-GREP contract (payload shape + ordering). The behavioral
// proof is the live FK mechanism check (ON DELETE CASCADE means a delete would
// not 23503 → the failing op must be the PK update) and the live web
// re-verification documented in the diagnose-doc (the sync layer has no fakeable
// Supabase client harness). Per feedback_source_grep_strip_comments_first.md,
// comments are stripped FIRST so assertions match CODE — the comments quote
// 23503 / `id` / ON CONFLICT and would produce false matches otherwise.
//
// Run: flutter test test/contracts/sync_nutrition_log_id_resolved_before_upsert_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Remove `/* ... */` block comments and `// ...` line comments so the
/// assertions below match the actual executable source, not the explanatory
/// comments (which deliberately quote 23503 / `id` / `ON CONFLICT`).
String _stripComments(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
  return s;
}

void main() {
  final file = File('lib/core/services/sync/sync_nutrition.dart');
  late String code;

  setUpAll(() {
    expect(file.existsSync(), isTrue,
        reason: 'lib/core/services/sync/sync_nutrition.dart must exist');
    code = _stripComments(file.readAsStringSync());
  });

  group('_syncNutritionLogs never rewrites the nutrition_logs PK (Diagnose c9f2a7)',
      () {
    test('the nutrition_logs upsert payload OMITS `id`', () {
      // Sending a derived `id` on a natural-key upsert is what rewrote the
      // existing PK and tripped nutrition_log_items_log_id_fkey (23503).
      // Omitting it keeps the existing PK on conflict / uses the column
      // default gen_random_uuid() on insert.
      final start = code.indexOf('final parentPayload = <String, dynamic>{');
      expect(start, greaterThanOrEqualTo(0),
          reason: 'the parentPayload map literal must exist');
      final end = code.indexOf('};', start);
      expect(end, greaterThan(start),
          reason: 'the parentPayload literal must close');
      final payloadBlock = code.substring(start, end);
      expect(payloadBlock.contains("'id':"), isFalse,
          reason:
              "the nutrition_logs upsert payload MUST NOT send 'id' — a derived "
              'id rewrites a FK-referenced PK → 23503 (recurrence of '
              'a8b2c7/templates + c8e4a1/scheduled_workouts)');
      expect(payloadBlock, contains("'user_id': userId"));
      expect(payloadBlock, contains("'meal_type': nlogMeal"));
    });

    test('resolves the real cloud id AFTER the upsert for the children log_id',
        () {
      expect(code, contains("from('nutrition_logs')"),
          reason: 'must read nutrition_logs to resolve the real id');
      expect(code, contains(".select('id')"));
      expect(code, contains(".eq('meal_type', nlogMeal)"),
          reason: 'resolve keys on the (user,date,meal_type) natural key');
      expect(code, contains('.maybeSingle()'),
          reason: 'natural key is UNIQUE → 0-or-1 rows');
      expect(code, contains("parentRow?['id']"),
          reason: 'children attach to the resolved real cloud id');

      // Omit-id pattern ordering: upsert the parent FIRST (preserving its PK),
      // THEN resolve the id for the children.
      final upsertIdx = code.indexOf('from("nutrition_logs").upsert');
      final resolveIdx = code.indexOf(".eq('meal_type', nlogMeal)");
      expect(upsertIdx, greaterThanOrEqualTo(0),
          reason: 'the nutrition_logs upsert must be present');
      expect(resolveIdx, greaterThan(upsertIdx),
          reason:
              'omit-id pattern: upsert the parent (PK untouched) before '
              'resolving the real cloud id for the children');
    });

    test('skips children when the parent id cannot be resolved', () {
      expect(code, contains('if (logCloudId == null || logCloudId.isEmpty)'),
          reason:
              'without the resolved parent id the children would FK to a wrong/'
              'absent parent — skip this pass and let the next sync retry');
      expect(code, contains("'log_id': logCloudId"),
          reason: 'children must attach to the resolved parent id');
    });

    test('still merges on the natural key (preserves the 2026-05-12 P0-B fix)',
        () {
      expect(code, contains('onConflict: "user_id,date,meal_type"'),
          reason:
              'natural-key merge must be preserved so a rotated dedup key does '
              'not 23505; the omit-id fix layers on top of it');
    });
  });
}
