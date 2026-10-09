// test/contracts/nutrition_slot_merge_test.dart
//
// audit-fixwave 2026-07-02 / F5 (NUT-02) — same-slot meal data-loss.
//
// mergeNutritionLogsBySlot coalesces all same-(date, meal_type) nutrition logs
// into ONE payload (union items + summed totals) so the cloud natural-key upsert
// (user_id,date,meal_type) never drops a second same-slot meal. Pre-fix each
// nlog_ key synced independently → the second same-slot log OVERWROTE the first
// cloud row → the first meal was lost on reinstall (the NUT-02 data-loss).
//
// The behavioral core is the pure merge (below). The restore-side per-slot
// local-wins + the F18 glasses fill are pinned by comment-stripped structural
// gates (they need a live Supabase to drive end-to-end; the live re-test on
// test7 is the runtime proof).
//
// closes-diagnose: e5c4b9

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

Map<String, dynamic> _log({
  required String? date,
  required String meal,
  required List<Map<String, dynamic>> items,
  num cals = 0,
  num protein = 0,
  num carbs = 0,
  num fat = 0,
  num fiber = 0,
  String? createdAt,
}) =>
    {
      'date': date,
      'meal_type': meal,
      'items': items,
      'total_calories': cals,
      'total_protein': protein,
      'total_carbs': carbs,
      'total_fat': fat,
      'total_fiber': fiber,
      if (createdAt != null) 'created_at': createdAt,
    };

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('mergeNutritionLogsBySlot (F5 / NUT-02 behavioral)', () {
    test('two logs in the SAME slot merge into one (union items + summed totals)',
        () {
      final merged = mergeNutritionLogsBySlot([
        _log(
            date: '2026-07-03',
            meal: 'lunch',
            items: [
              {'name': 'Salad', 'quantity_g': 100, 'calories': 150}
            ],
            cals: 150,
            protein: 5,
            createdAt: '2026-07-03T12:00:00Z'),
        _log(
            date: '2026-07-03',
            meal: 'lunch',
            items: [
              {'name': 'Shake', 'quantity_g': 250, 'calories': 300}
            ],
            cals: 300,
            protein: 30,
            createdAt: '2026-07-03T12:30:00Z'),
      ]);
      expect(merged.length, 1, reason: 'same slot → ONE payload (no overwrite)');
      final m = merged.single;
      expect((m['items'] as List).length, 2,
          reason: "both meals' items preserved (the data that was lost pre-fix)");
      expect(m['total_calories'], 450, reason: '150 + 300 summed');
      expect(m['total_protein'], 35);
      expect(m['created_at'], '2026-07-03T12:00:00Z',
          reason: 'earliest created_at kept for stable ordering');
    });

    test('different slots stay separate', () {
      final merged = mergeNutritionLogsBySlot([
        _log(date: '2026-07-03', meal: 'lunch', items: [
          {'name': 'A'}
        ]),
        _log(date: '2026-07-03', meal: 'dinner', items: [
          {'name': 'B'}
        ]),
        _log(date: '2026-07-04', meal: 'lunch', items: [
          {'name': 'C'}
        ]),
      ]);
      expect(merged.length, 3, reason: 'distinct (date,meal) slots never merge');
    });

    test('duplicate identical items APPEND (two servings), not de-duped', () {
      final merged = mergeNutritionLogsBySlot([
        _log(date: '2026-07-03', meal: 'breakfast', items: [
          {'name': 'Roti', 'quantity_g': 60}
        ], cals: 200),
        _log(date: '2026-07-03', meal: 'breakfast', items: [
          {'name': 'Roti', 'quantity_g': 60}
        ], cals: 200),
      ]);
      expect(merged.length, 1);
      expect((merged.single['items'] as List).length, 2,
          reason: 'logging the same food twice = two servings, not one');
      expect(merged.single['total_calories'], 400);
    });

    test('null/empty natural-key logs pass through unmerged (never dropped)', () {
      final merged = mergeNutritionLogsBySlot([
        _log(date: '2026-07-03', meal: 'lunch', items: [
          {'name': 'A'}
        ]),
        _log(date: null, meal: 'lunch', items: [
          {'name': 'orphan'}
        ]),
        _log(date: '2026-07-03', meal: '', items: [
          {'name': 'orphan2'}
        ]),
      ]);
      expect(merged.length, 3,
          reason: 'the 2 null-key logs pass through so the sync loop still '
              'fires its null-key telemetry guard (no silent drop)');
    });
  });

  group('F5/F18 structural gates (comment-stripped)', () {
    final src = _strip(
        File('lib/core/services/sync/sync_nutrition.dart').readAsStringSync());

    test('sync push iterates the slot-merged list, flag-gated', () {
      expect(src.contains('_nutritionLogsMergedBySlot()'), isTrue);
      expect(src.contains('disable_nutrition_slot_merge'), isTrue,
          reason: 'kill-switch present for rollback');
    });

    test('restore is a 3-way MULTISET merge (skip if local superset; else union)',
        () {
      // Local-wins only when local already holds >= every cloud item (multiset);
      // else union local+cloud into one merged row — no silent loss, no dup, and
      // genuine duplicate servings preserved (re-Hermes P1).
      expect(src.contains('nutritionLocalSlotIsSuperset'), isTrue,
          reason: 'skip only when local is a multiset superset of the cloud row');
      expect(src.contains('nutritionSlotUnion') && src.contains('mergedKey'),
          isTrue,
          reason: 'else path multiset-unions local+cloud into one merged row');
    });

    test('sync item tail-vacuum removes orphaned tail on a shrunk slot (B-pass)',
        () {
      expect(
          src.contains("from('nutrition_log_items')") &&
              src.contains('.delete()') &&
              src.contains("gte('item_index'"),
          isTrue,
          reason: 'a shrunk merged slot must vacuum orphaned item_index >= count '
              'so a deleted meal cannot resurrect on restore');
    });

    test('water glasses column is populated (F18)', () {
      expect(src.contains("'glasses'"), isTrue,
          reason: 'glasses derived from total_ml, no longer a stale 0');
    });
  });

  // audit-fixwave re-Hermes — the restore-side MULTISET union must PRESERVE a
  // genuine duplicate serving (a food logged twice) while NOT double-counting an
  // already-synced item present in both local and cloud. The first cut set-deduped
  // and silently dropped the second serving (a Hermes P1). These pin the fix.
  Map<String, dynamic> _item(String name, num qty, {num cal = 0}) =>
      {'name': name, 'quantity_g': qty, 'calories': cal};

  group('nutritionSlotUnion — multiset (duplicate servings preserved)', () {
    test('two identical servings survive (local {Roti,Roti} + cloud {Roti,Roti})',
        () {
      final u = nutritionSlotUnion(
        [_item('Roti', 60, cal: 200), _item('Roti', 60, cal: 200)],
        [_item('Roti', 60, cal: 200), _item('Roti', 60, cal: 200)],
      );
      expect(u.length, 2,
          reason: 'both servings are already-synced → keep 2, not 4 (no over-count) '
              'and NOT 1 (no silent drop of a real duplicate)');
    });

    test('cloud has an extra serving local lacks → restore it (max count)', () {
      final u = nutritionSlotUnion(
        [_item('Roti', 60, cal: 200)], // local 1
        [_item('Roti', 60, cal: 200), _item('Roti', 60, cal: 200)], // cloud 2
      );
      expect(u.length, 2, reason: 'max(1,2)=2 — the missing 2nd serving restores');
    });

    test('local has an unsynced extra serving → keep it (superset skip)', () {
      final local = [_item('Roti', 60), _item('Roti', 60)]; // 2 (one unsynced)
      final cloud = [_item('Roti', 60)]; // 1
      expect(nutritionLocalSlotIsSuperset(local, cloud), isTrue,
          reason: 'local multiset ⊇ cloud → skip restore, keep the unsynced 2nd');
      expect(nutritionSlotUnion(local, cloud).length, 2);
    });

    test('distinct items union without loss (partial-restore)', () {
      final u = nutritionSlotUnion(
        [_item('Salad', 100)],
        [_item('Salad', 100), _item('Shake', 250)],
      );
      expect(u.map((e) => (e as Map)['name']).toSet(), {'Salad', 'Shake'},
          reason: 'the cloud-only Shake must restore (no partial-restore loss)');
      expect(nutritionLocalSlotIsSuperset(
          [_item('Salad', 100)], [_item('Salad', 100), _item('Shake', 250)]),
          isFalse);
    });
  });

  group('mergeNutritionLogsBySlot — shrink produces a smaller item count', () {
    test('deleting one same-slot meal shrinks the merged item count', () {
      // Two meals in lunch → 2 items merged.
      final full = mergeNutritionLogsBySlot([
        _log(date: '2026-07-03', meal: 'lunch', items: [
          {'name': 'Salad', 'quantity_g': 100}
        ], cals: 150),
        _log(date: '2026-07-03', meal: 'lunch', items: [
          {'name': 'Shake', 'quantity_g': 250}
        ], cals: 300),
      ]);
      expect((full.single['items'] as List).length, 2);
      // After deleting the shake locally, only salad remains → 1 item. The sync
      // tail-vacuum (asserted structurally above) then clears cloud item_index>=1.
      final shrunk = mergeNutritionLogsBySlot([
        _log(date: '2026-07-03', meal: 'lunch', items: [
          {'name': 'Salad', 'quantity_g': 100}
        ], cals: 150),
      ]);
      expect((shrunk.single['items'] as List).length, 1,
          reason: 'the merged payload shrinks; the vacuum clears the orphan tail');
      expect(shrunk.single['total_calories'], 150);
    });
  });
}
