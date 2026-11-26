@Timeout(Duration(minutes: 20))
library;

// OI-348 Landing 1a-ii — S15: seeded randomized convergence. 2-3 devices
// start from a pre-build state with overlapping histories, re-baseline at a
// random point, then run random offline ops (log, edit, delete, move, undo,
// relog, a legacy pass of the kill switch, an old client's write) and random
// sync interleavings against the fake server. After quiescing, every device
// holds the same meals as each other and as the cloud, the day total is the
// sum of live entries, and no entry id appears twice in a date.
// NSLOT_SEEDS overrides the seed count (default 500; CI runs the default).
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_engine.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_merge.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_remote.dart';

import 'nutrition_slot_fake_server.dart';
import 'nutrition_slot_harness.dart';

const _dates = ['2026-11-21', '2026-11-22'];
const _meals = ['breakfast', 'lunch', 'dinner', 'snacks'];
const _foods = ['Dal', 'Rice', 'Roti', 'Poha', 'Egg'];

/// The cloud's meals as `date|meal|id|signature` (what a fresh device would
/// restore).
Future<List<String>> _cloudContent(FakeNslotServer s) async {
  final rows = await s.rowsPage(limit: 100000);
  final out = <String>[];
  for (final raw in rows) {
    final r = NslotCloudRow.fromJson(raw)!;
    for (final e in r.toLocalEntries()) {
      out.add('${r.date}|${r.mealType}|${e['entry_id']}|${nslotSignature(e)}');
    }
  }
  return out..sort();
}

Future<void> _legacyPush(Dev d, FakeNslotServer s) async {
  // Today's legacy push: every local slot merged and upserted by natural key
  // (an emptied slot is never sent), through the wrapper.
  await d.section.legacyPass(kUser, () async {
    final bySlot = <String, List<Map>>{};
    for (final m in d.meals) {
      bySlot.putIfAbsent('${m['date']}|${m['meal_type']}', () => []).add(m);
    }
    for (final e in bySlot.entries) {
      final parts = e.key.split('|');
      final items = [
        for (final m in e.value)
          for (final i in (m['items'] as List)) Map<String, dynamic>.from(i as Map),
      ];
      num sum(String f) => e.value.fold<num>(0, (a, m) => a + ((m[f] as num?) ?? 0));
      s.oldClientUpsertSlot(parts[0], parts[1], totals: {
        'total_calories': sum('total_calories'),
        'total_protein': sum('total_protein'),
        'total_carbs': sum('total_carbs'),
        'total_fat': sum('total_fat'),
        'total_fiber': sum('total_fiber'),
      }, items: items);
    }
  }, isPush: true);
}

/// The server-time text shapes the seeds actually produced (fake C6): `full`
/// (6 fraction digits), `trimmed` (1-5) and `none` (whole second). The test
/// requires all three, so the cursor's text comparisons ran over each.
final _timeShapes = <String>{};

String _shapeOf(String ts) {
  final plus = ts.lastIndexOf('+');
  final dot = ts.indexOf('.');
  if (dot < 0 || dot > plus) return 'none';
  return plus - dot - 1 == 6 ? 'full' : 'trimmed';
}

Future<String?> _runSeed(int seed, Directory dir) async {
  final rng = Random(seed);
  final server = FakeNslotServer(seed: seed);
  final devs = <Dev>[];
  final nDevs = 2 + rng.nextInt(2);
  try {
    for (var i = 0; i < nDevs; i++) {
      devs.add(await Dev.open('s${seed}d$i', server, clockOffsetMs: rng.nextInt(5000)));
    }
    // Pre-build history: a legacy cloud row per slot the "old build" pushed,
    // and id-less local rows on each device (overlapping, not identical).
    for (final date in _dates) {
      for (final meal in _meals) {
        if (rng.nextDouble() < 0.4) {
          final items = [
            for (var k = 0; k < 1 + rng.nextInt(2); k++)
              {
                'name': _foods[rng.nextInt(_foods.length)],
                'quantity_g': 50 + rng.nextInt(4) * 50,
                'calories': 100 + rng.nextInt(5) * 20,
              },
          ];
          server.oldClientUpsertSlot(date, meal, totals: {
            'total_calories': items.fold<num>(0, (a, i) => a + ((i['calories'] as num?) ?? 0)),
            'total_protein': 10,
            'total_carbs': 20,
            'total_fat': 5,
            'total_fiber': 1,
          }, items: items);
        }
        for (final d in devs) {
          if (rng.nextDouble() < 0.3) {
            await d.log(date, meal, [(_foods[rng.nextInt(5)], 100, 150)], withId: false);
          }
        }
      }
    }
    final undo = <Dev, Map<String, dynamic>>{};
    final steps = 20 + rng.nextInt(30);
    for (var step = 0; step < steps; step++) {
      final d = devs[rng.nextInt(devs.length)];
      final roll = rng.nextDouble();
      final keys = [
        for (final k in d.nut.keys)
          if (nslotIsMealRow(k, d.nut.get(k))) k as String,
      ];
      if (roll < 0.15) {
        await d.log(_dates[rng.nextInt(2)], _meals[rng.nextInt(4)],
            [(_foods[rng.nextInt(5)], 50 + rng.nextInt(5) * 25, 80 + rng.nextInt(9) * 20)]);
      } else if (roll < 0.25 && keys.isNotEmpty) {
        await d.editQty(keys[rng.nextInt(keys.length)], 10 + rng.nextInt(300));
      } else if (roll < 0.33 && keys.isNotEmpty) {
        final k = keys[rng.nextInt(keys.length)];
        undo[d] = Map<String, dynamic>.from(d.nut.get(k) as Map);
        await d.delete(k);
      } else if (roll < 0.38 && undo[d] != null) {
        final payload = undo.remove(d)!;
        if (nslotUndoRefusal(payload, d.nut, true) == null) {
          await d.nut.put(payload['id'] as String, payload);
        }
      } else if (roll < 0.46 && keys.isNotEmpty) {
        final k = keys[rng.nextInt(keys.length)];
        final cur = (d.nut.get(k) as Map)['meal_type'];
        final to = _meals.where((m) => m != cur).toList()[rng.nextInt(3)];
        await d.move(k, to, killBeforeDelete: rng.nextDouble() < 0.1);
      } else if (roll < 0.50 && keys.isNotEmpty) {
        // relog: logMeal of an existing meal's items (a NEW entry).
        final m = d.nut.get(keys[rng.nextInt(keys.length)]) as Map;
        await d.log(m['date'] as String, m['meal_type'] as String,
            [(_foods[rng.nextInt(5)], 100, 120)]);
      } else if (roll < 0.53) {
        await _legacyPush(d, server);
      } else if (roll < 0.56) {
        final date = _dates[rng.nextInt(2)];
        final meal = _meals[rng.nextInt(4)];
        if (rng.nextBool()) {
          server.oldClientUpsertSlot(date, meal, totals: {
            'total_calories': 140,
            'total_protein': 10,
            'total_carbs': 20,
            'total_fat': 5,
            'total_fiber': 1,
          }, items: [
            {'name': 'Old', 'quantity_g': 70, 'calories': 140},
          ]);
        } else {
          server.oldClientDeleteSlot(date, meal);
        }
      } else if (roll < 0.78) {
        await d.push();
        await d.settle();
      } else {
        await d.pull();
        await d.settle();
      }
    }
    // Quiesce.
    for (var round = 0; round < 8; round++) {
      for (final d in devs) {
        await d.sync();
      }
    }
    final cloud = await _cloudContent(server);
    for (final d in devs) {
      if (d.meta['rebaselined'] != true) return 'seed $seed: ${d.name} not re-baselined';
      final c = d.content();
      if (c.join('\n') != cloud.join('\n')) {
        return 'seed $seed: ${d.name} differs from cloud\n'
            'device: $c\ncloud:  $cloud';
      }
      for (final date in _dates) {
        final ids = d.meals.where((m) => m['date'] == date).map((m) => m['entry_id']).toList();
        if (ids.toSet().length != ids.length) return 'seed $seed: duplicate id on $date';
      }
    }
    return null;
  } finally {
    _timeShapes.addAll(server.writtenTimes.map(_shapeOf));
    for (final d in devs) {
      await d.close();
    }
  }
}

void main() {
  late Directory dir;
  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('nslot_random');
    Hive.init(dir.path);
  });
  tearDownAll(() async {
    await Hive.deleteFromDisk();
    dir.deleteSync(recursive: true);
  });

  test('S15: every seed converges (no double count, no lost delete)', () async {
    final n = int.tryParse(Platform.environment['NSLOT_SEEDS'] ?? '') ?? 500;
    final failures = <String>[];
    for (var seed = 0; seed < n; seed++) {
      final f = await _runSeed(seed, dir);
      if (f != null) {
        failures.add(f);
        // ignore: avoid_print
        print('FAILING $f');
        if (failures.length >= 3) break;
      }
    }
    expect(failures, isEmpty);
    expect(_timeShapes, containsAll(<String>['full', 'trimmed', 'none']),
        reason: 'the seeds must cover every PostgREST timestamptz text shape');
  });
}
