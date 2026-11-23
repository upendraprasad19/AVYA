@Timeout(Duration(minutes: 3))
library;

// OI-348 Landing 1a-ii — the re-baseline (spec §4.11, S13, S16, §6).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_engine.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_merge.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_remote.dart';

import 'nutrition_slot_fake_server.dart';
import 'nutrition_slot_harness.dart';

const d1 = '2026-11-23';
const d2 = '2026-11-22';

Map<String, dynamic> _totals(num cal) => {
      'total_calories': cal,
      'total_protein': 10,
      'total_carbs': 20,
      'total_fat': 5,
      'total_fiber': 1,
    };

void main() {
  late Directory dir;
  late FakeNslotServer server;
  final open = <Dev>[];

  Future<Dev> dev(String name, {int offset = 0, NslotRemote? remote}) async {
    final d = await Dev.open(name, remote ?? server, clockOffsetMs: offset);
    open.add(d);
    return d;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('nslot_rebase');
    Hive.init(dir.path);
    server = FakeNslotServer();
  });
  tearDown(() async {
    for (final d in open) {
      await d.close();
    }
    open.clear();
    await Hive.deleteFromDisk();
    dir.deleteSync(recursive: true);
  });

  test('S13: a fresh install restores each meal as its own entry, own key',
      () async {
    final w = await dev('W');
    await w.sync();
    await w.log(d1, 'lunch', [('Dal', 150, 200)]);
    await w.log(d1, 'lunch', [('Rice', 200, 260)]);
    await w.sync();
    final x = await dev('X', offset: 900);
    await x.sync();
    expect(x.meta['rebaselined'], isTrue);
    expect(x.content(), w.content());
    expect(x.nut.keys.where((k) => '$k'.startsWith('nlog_')).toSet(),
        w.nut.keys.where((k) => '$k'.startsWith('nlog_')).toSet());
  });

  test('S16: pre-build rows become the cloud\'s content once, the same '
      'synthetic id on every device', () async {
    // The old build pushed both lunches merged into ONE legacy row.
    server.oldClientUpsertSlot(d1, 'lunch', totals: _totals(460), items: [
      {'name': 'Dal', 'quantity_g': 150, 'calories': 200},
      {'name': 'Rice', 'quantity_g': 200, 'calories': 260},
    ]);
    final p = await dev('P');
    final w = await dev('W', offset: 300);
    for (final d in [p, w]) {
      await d.log(d1, 'lunch', [('Dal', 150, 200)], withId: false);
      await d.log(d1, 'lunch', [('Rice', 200, 260)], withId: false);
    }
    await p.sync();
    await w.sync();
    expect(p.meals, hasLength(1));
    expect(p.dayCalories(d1), 460);
    expect(p.content(), w.content());
    final row = server.rowJson(d1, 'lunch')!;
    expect(p.meals.single['entry_id'],
        nslotSyntheticEntryId(row['id'] as String, row['rev'] as int));
    // Nothing was written to the cloud by either re-baseline.
    expect(server.calls.where((c) => c.startsWith('put')), isEmpty);
  });

  test('a tombstoned slot removes the legacy rows', () async {
    server.oldClientUpsertSlot(d1, 'dinner', totals: _totals(200), items: [
      {'name': 'Roti', 'quantity_g': 80, 'calories': 200},
    ]);
    server.oldClientDeleteSlot(d1, 'dinner');
    final p = await dev('P');
    await p.log(d1, 'dinner', [('Roti', 80, 200)], withId: false);
    await p.sync();
    expect(p.meals, isEmpty);
  });

  test('a slot with no cloud row keeps its rows, stamped, pushed once',
      () async {
    final p = await dev('P');
    await p.log(d2, 'snacks', [('Nuts', 30, 180)], withId: false);
    await p.sync();
    expect(p.meals, hasLength(1));
    expect(p.meals.single['entry_id'], isA<String>());
    expect(server.calls.where((c) => c.startsWith('put $d2 snacks')),
        hasLength(1));
    await p.sync();
    expect(server.calls.where((c) => c.startsWith('put $d2 snacks')),
        hasLength(1));
  });

  test('a UUID cloud_restore row in a slot with no cloud row → one nlog_ row',
      () async {
    final p = await dev('P');
    await p.nut.put('0b6f1a2e-1111-4222-8333-444455556666', {
      'date': d2,
      'meal_type': 'lunch',
      'total_calories': 300,
      'items': [
        {'name': 'Dal', 'quantity_g': 150, 'calories': 300},
      ],
      'source': 'cloud_restore',
      'created_at': '2026-11-22T06:00:00.000Z',
    });
    await p.sync();
    expect(p.nut.containsKey('0b6f1a2e-1111-4222-8333-444455556666'), isFalse);
    expect(p.meals, hasLength(1));
    expect('${p.meals.single['id']}', startsWith('nlog_${d2}_lunch_'));
  });

  test('a row changed during the read stops the run; the next pass commits',
      () async {
    server.oldClientUpsertSlot(d1, 'lunch', totals: _totals(200), items: [
      {'name': 'Dal', 'quantity_g': 150, 'calories': 200},
    ]);
    final p = await dev('P');
    final k = await p.log(d1, 'lunch', [('Dal', 150, 200)], withId: false);
    server.rowPageGate = Completer<void>();
    final run = p.pull();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final changed = Map<String, dynamic>.from(p.nut.get(k) as Map)
      ..['total_calories'] = 999;
    await p.nut.put(k, changed);
    server.rowPageGate!.complete();
    server.rowPageGate = null;
    await run;
    expect(p.lows, contains('nslot_rebaseline_stopped'));
    expect(p.meta['rebaselined'], isNot(isTrue));
    expect(p.nut.get(k), changed); // nothing changed
    await p.sync();
    expect(p.meta['rebaselined'], isTrue);
    expect(p.dayCalories(d1), 200);
  });

  test('a read failure changes nothing; the retry continues from the last page',
      () async {
    server.oldClientUpsertSlot(d1, 'lunch', totals: _totals(200), items: [
      {'name': 'Dal', 'quantity_g': 150, 'calories': 200},
    ]);
    final spy = SpyRemote(server);
    final p = await dev('P', remote: spy);
    await p.log(d1, 'lunch', [('Dal', 150, 200)], withId: false);
    final before = p.contentNoId();
    server.failNextTombPages = 1;
    await p.pull();
    await p.settle();
    expect(p.contentNoId(), before);
    expect(p.failures, contains('rebaseline_nutrition'));
    final pagesAfterFirst = spy.pages;
    await p.pull();
    await p.settle();
    expect(p.meta['rebaselined'], isTrue);
    // The first attempt finished the rows (a short page) and failed on the
    // tombstones; the retry reads ONLY the tombstones again (1 read), never
    // the rows from the start.
    expect(spy.pages - pagesAfterFirst, 1);
  });

  test('a crash after the rebuild writes + re-run gives the clean run\'s box',
      () async {
    Future<Dev> seeded(String name) async {
      final d = await dev(name);
      await d.log(d1, 'lunch', [('Dal', 150, 200)], withId: false);
      await d.log(d2, 'snacks', [('Nuts', 30, 180)], withId: false);
      return d;
    }

    server.oldClientUpsertSlot(d1, 'lunch', totals: _totals(200), items: [
      {'name': 'Dal', 'quantity_g': 150, 'calories': 200},
    ]);
    final clean = await seeded('C');
    await clean.pull();
    await clean.settle();

    final crash = await seeded('K');
    // Kill right after step 3's writes: the run sees itself stale before the
    // commit (the step-3 writes landed, the ledger and meta did not).
    crash.onInvalidate = () => crash.ownerChanged = true;
    await crash.pull();
    expect(crash.meta['rebaselined'], isNot(isTrue));
    expect(crash.meta['inflight_sigs'], isNotEmpty);
    // Re-run after a restart.
    crash.onInvalidate = null;
    crash.ownerChanged = false;
    crash.restart();
    await crash.pull();
    await crash.settle();
    expect(crash.meta['rebaselined'], isTrue);
    expect(crash.contentNoId(), clean.contentNoId());
    expect(crash.meals, hasLength(clean.meals.length));
  });

  test('legacy pass → FULL re-baseline makes the device equal to the cloud',
      () async {
    final p = await dev('P');
    await p.sync();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    // The kill switch: one legacy pass (a stand-in body that writes nothing).
    await p.section.legacyPass(kUser, () async {}, isPush: true);
    expect(p.meta['full'], 'legacy_pass');
    expect(p.meta['rebaselined'], isFalse);
    // A local change the cloud never saw is replaced by the cloud copy.
    await p.editQty(p.meals.single['id'] as String, 999);
    await p.sync();
    expect(p.meta['rebaselined'], isTrue);
    expect(p.meta.containsKey('full'), isFalse);
    expect(((p.meals.single['items'] as List).single as Map)['quantity_g'], 150);
  });

  test('legacy-seen FULL keeps a never-pushed meal and pushes it once',
      () async {
    final p = await dev('P');
    await p.sync();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    server.oldClientUpsertSlot(d1, 'dinner', totals: _totals(300), items: [
      {'name': 'Roti', 'quantity_g': 80, 'calories': 300},
    ]);
    await p.log(d2, 'breakfast', [('Oats', 60, 220)]); // never pushed
    await p.pull();
    // The pass that saw it stopped and scheduled ONE pull, which ran the FULL
    // re-baseline (R14 P2-1: no waiting for the next launch).
    await p.settle();
    expect(p.lows, contains('nslot_legacy_seen_rebaseline'));
    expect(p.meta['rebaselined'], isTrue);
    await p.sync();
    await p.sync();
    expect(p.meta['rebaselined'], isTrue);
    expect(p.meals.where((m) => m['date'] == d2), hasLength(1));
    expect(server.calls.where((c) => c.startsWith('put $d2 breakfast')),
        hasLength(1));
    expect(p.dayCalories(d1), 500);
  });

  test('restore on a not re-baselined device ignores preFetched and re-baselines',
      () async {
    server.oldClientUpsertSlot(d1, 'lunch', totals: _totals(200), items: [
      {'name': 'Dal', 'quantity_g': 150, 'calories': 200},
    ]);
    final p = await dev('P');
    var fetched = false;
    final r = await p.section.restoreBody(kUser,
        preFetched: const [], fetchRows: () async {
      fetched = true;
      return const [];
    });
    expect(r.ok, isTrue);
    expect(fetched, isFalse);
    expect(p.meals, hasLength(1));
  });

  test('a restore that meets a running re-baseline reports its result',
      () async {
    final p = await dev('P');
    server.rowPageGate = Completer<void>();
    final pulling = p.pull();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final restoring = p.section.restoreBody(kUser, fetchRows: () async => []);
    server.rowPageGate!.complete();
    server.rowPageGate = null;
    await pulling;
    final r = await restoring;
    expect(r.ok, isTrue);
  });

  group('undo refusal (§4.1)', () {
    test('an id already present, and an id-less payload after the re-baseline',
        () async {
      final p = await dev('P');
      await p.sync();
      final k = await p.log(d1, 'lunch', [('Dal', 150, 200)]);
      final row = Map<String, dynamic>.from(p.nut.get(k) as Map);
      expect(nslotUndoRefusal(row, p.nut, true), 'entry_already_present');
      await p.delete(k);
      expect(nslotUndoRefusal(row, p.nut, true), isNull);
      final idLess = Map<String, dynamic>.from(row)..remove('entry_id');
      expect(nslotUndoRefusal(idLess, p.nut, true), 'id_less_after_rebaseline');
      expect(nslotUndoRefusal(idLess, p.nut, false), isNull);
    });
  });
}
