@Timeout(Duration(minutes: 3))
library;

// OI-348 Landing 1a-ii — behavioural tests of the new-mode push / pull /
// restore against the fake server (spec §2 S1-S12, S14; §6).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_engine.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_remote.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';

import 'nutrition_slot_fake_server.dart';
import 'nutrition_slot_harness.dart';

const d1 = '2026-11-23';

void main() {
  late Directory dir;
  late FakeNslotServer server;
  final open = <Dev>[];

  Future<Dev> dev(String name, {int offset = 0, NslotRemote? remote}) async {
    final d = await Dev.open(name, remote ?? server, clockOffsetMs: offset);
    open.add(d);
    return d;
  }

  /// Both devices re-baselined on an empty server.
  Future<(Dev, Dev)> pair() async {
    final p = await dev('P');
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
    expect(p.meta['rebaselined'], isTrue);
    expect(w.meta['rebaselined'], isTrue);
    return (p, w);
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('nslot_behav');
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

  test('S1: a meal logged on W appears ONCE on P with its items', () async {
    final (p, w) = await pair();
    await w.log(d1, 'breakfast', [('Poha', 150, 250), ('Tea', 200, 60)]);
    await w.sync();
    await p.sync();
    expect(p.content(), w.content());
    expect(p.meals, hasLength(1));
    expect((p.meals.single['items'] as List), hasLength(2));
    expect(p.dayCalories(d1), w.dayCalories(d1));
  });

  test('S2: an edit on P reaches W, and only the edit', () async {
    final (p, w) = await pair();
    final k = await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    await w.sync();
    await p.editQty(k, 220);
    await p.sync();
    await w.sync();
    expect(w.meals, hasLength(1));
    expect(((w.meals.single['items'] as List).single as Map)['quantity_g'], 220);
    expect(w.content(), p.content());
  });

  test('S3: a delete on P empties the cloud slot and W', () async {
    final (p, w) = await pair();
    final k = await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    await w.sync();
    expect(w.meals, hasLength(1));
    await p.delete(k);
    await p.sync();
    expect(server.rowJson(d1, 'lunch'), isNull);
    expect(server.tombJson(d1, 'lunch'), isNotNull);
    await w.sync();
    expect(w.meals, isEmpty);
  });

  test('S4: a move lunch → dinner shows under dinner only; put before delete',
      () async {
    final (p, w) = await pair();
    final k = await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    await w.sync();
    server.calls.clear();
    await p.move(k, 'dinner');
    await p.sync();
    final rpcs = server.calls.where((c) => !c.startsWith('now')).toList();
    expect(rpcs.first, startsWith('put $d1 dinner'));
    expect(rpcs, contains(startsWith('delete $d1 lunch')));
    await w.sync();
    expect(w.meals.single['meal_type'], 'dinner');
    expect(w.content(), p.content());
  });

  test('S4b: move on P while W edits it in lunch → one copy, newer wins',
      () async {
    final (p, w) = await pair();
    final k = await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    await w.sync();
    final wk = w.meals.single['id'] as String;
    await p.move(k, 'dinner'); // P's clock is older
    w.advanceClock(const Duration(minutes: 1));
    await w.editQty(wk, 300); // W's edit is newer
    await p.sync();
    await w.sync();
    await p.sync();
    expect(p.meals, hasLength(1));
    expect(w.meals, hasLength(1));
    expect(p.content(), w.content());
    expect(((p.meals.single['items'] as List).single as Map)['quantity_g'], 300);
  });

  test('S5: P deletes offline, W adds another meal → only W\'s meal', () async {
    final (p, w) = await pair();
    final k = await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    await w.sync();
    await p.delete(k);
    await w.log(d1, 'lunch', [('Rice', 200, 260)]);
    await w.sync();
    await p.sync(); // conflict → merge → retry
    await w.sync();
    expect(p.meals, hasLength(1));
    expect(((p.meals.single['items'] as List).single as Map)['name'], 'Rice');
    expect(p.content(), w.content());
  });

  test('S6/S7: offline adds on both (even identical food) → both, no doubling',
      () async {
    final (p, w) = await pair();
    await p.log(d1, 'snacks', [('Banana', 100, 90)]);
    await w.log(d1, 'snacks', [('Banana', 100, 90)]);
    await p.sync();
    await w.sync();
    await p.sync();
    expect(p.meals, hasLength(2));
    expect(w.meals, hasLength(2));
    expect(p.content(), w.content());
    expect(p.dayCalories(d1), 180);
  });

  test('S8: both edit one meal offline → the later edit wins on both', () async {
    final (p, w) = await pair();
    final k = await p.log(d1, 'dinner', [('Roti', 80, 200)]);
    await p.sync();
    await w.sync();
    await p.editQty(k, 100);
    w.advanceClock(const Duration(minutes: 5));
    await w.editQty(w.meals.single['id'] as String, 120);
    await p.sync();
    await w.sync();
    await p.sync();
    expect(p.content(), w.content());
    expect(((p.meals.single['items'] as List).single as Map)['quantity_g'], 120);
  });

  test('S9: P deletes while W edits → the edit survives on both', () async {
    final (p, w) = await pair();
    final k = await p.log(d1, 'dinner', [('Roti', 80, 200)]);
    await p.sync();
    await w.sync();
    await p.delete(k);
    await w.editQty(w.meals.single['id'] as String, 90);
    await p.sync();
    await w.sync();
    await p.sync();
    expect(p.meals, hasLength(1));
    expect(p.content(), w.content());
  });

  test('S10: repeated round trips never change revs or signatures', () async {
    final (p, w) = await pair();
    await p.log(d1, 'lunch', [('Dal', 150.04, 200.3)]);
    await w.log(d1, 'dinner', [('Rice', 0.1 + 0.2, 260)]);
    await p.sync();
    await w.sync();
    await p.sync();
    final revs = server.liveSlots
        .map((s) => server.currentRev(s.split('|')[0], s.split('|')[1]))
        .toList();
    final before = p.content();
    for (var i = 0; i < 10; i++) {
      p.restart();
      w.restart();
      await p.sync();
      await w.sync();
    }
    expect(p.content(), before);
    expect(w.content(), before);
    expect(
        server.liveSlots
            .map((s) => server.currentRev(s.split('|')[0], s.split('|')[1]))
            .toList(),
        revs);
  });

  test('gate: before the re-baseline the push sends nothing, LOW once',
      () async {
    final p = await dev('P');
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.push();
    await p.push();
    expect(server.calls, isEmpty);
    expect(p.lows.where((e) => e == 'nslot_push_gated_not_rebaselined'),
        hasLength(1));
    expect(p.failures, isEmpty);
  });

  test('a missing RPC sends nothing, records no failure, never legacy mode',
      () async {
    final (p, _) = await pair();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    server.rpcMissing = true;
    p.restart(); // probe again
    await p.push();
    await p.pull();
    expect(server.liveSlots, isEmpty);
    expect(p.failures, isEmpty);
    expect(p.meta['rebaselined'], isTrue);
    expect(p.lows, contains('nslot_rpc_missing'));
    server.rpcMissing = false;
    p.restart();
    await p.push();
    expect(server.liveSlots, hasLength(1));
  });

  test('a network failure of the probe in the push is an outage-shaped failure',
      () async {
    final (p, _) = await pair();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    p.restart();
    server.failNextRpc = 1;
    await p.push();
    expect(p.failures, ['sync_nslot_put']);
    await p.push();
    expect(server.liveSlots, hasLength(1));
  });

  test('a failed page applies nothing and keeps the cursor', () async {
    final (p, w) = await pair();
    await w.log(d1, 'lunch', [('Dal', 150, 200)]);
    await w.sync();
    final cursor = p.nut.get(kNslotCursorKey);
    server.failNextRowPages = 1;
    await p.pull();
    await p.settle();
    expect(p.meals, isEmpty);
    expect(p.nut.get(kNslotCursorKey), cursor);
    expect(p.failures, contains('pull_nutrition_slots'));
    await p.pull();
    await p.settle();
    expect(p.meals, hasLength(1));
  });

  test('conflict retry stops after 3 rounds with LOW', () async {
    final (p, w) = await pair();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    await w.sync();
    final spy = SpyRemote(server);
    p.server = spy;
    p.restart();
    // Another device writes before every put of P.
    var n = 0;
    spy.beforePut = () async {
      n++;
      await w.log(d1, 'lunch', [('Extra$n', 10, 10)]);
      await w.push();
    };
    await p.log(d1, 'lunch', [('Mine', 50, 50)]);
    await p.push();
    expect(p.lows, contains('nslot_conflict_rounds_exhausted'));
    expect(spy.puts, kNslotConflictRounds);
  });

  test('a busy section makes the push owed; it runs after release', () async {
    final (p, _) = await pair();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    // pair() already scheduled pushes; count only what this pull adds. The
    // pull itself reads nothing new, so the one extra push is the owed one.
    final before = p.pushesScheduled;
    server.rowPageGate = Completer<void>();
    final pulling = p.pull();
    await Future<void>.delayed(Duration.zero);
    expect(p.section.busy, isTrue);
    await p.push(); // returns at once
    expect(server.liveSlots, isEmpty);
    server.rowPageGate!.complete();
    server.rowPageGate = null;
    await pulling;
    expect(p.pushesScheduled, before + 1);
  });

  test('an account change mid-pull writes nothing afterwards (generation)',
      () async {
    final (p, w) = await pair();
    await w.log(d1, 'lunch', [('Dal', 150, 200)]);
    await w.sync();
    server.rowPageGate = Completer<void>();
    final pulling = p.pull();
    await Future<void>.delayed(Duration.zero);
    p.section.onUserChanged();
    server.rowPageGate!.complete();
    server.rowPageGate = null;
    await pulling;
    expect(p.meals, isEmpty);
  });

  test('a slot over the bounds is refused locally (no RPC, LOW)', () async {
    final (p, _) = await pair();
    await p.log(d1, 'lunch', [('x' * 201, 10, 10)]);
    server.calls.clear();
    await p.push();
    expect(server.calls.where((c) => c.startsWith('put')), isEmpty);
    expect(p.lows, contains('nslot_slot_too_large'));
    // B-pass seat B P3: the slot stays unconfirmed, so every pass retries it;
    // the event is logged once per launch, not once per meal log.
    await p.push();
    await p.push();
    expect(p.lows.where((e) => e == 'nslot_slot_too_large'), hasLength(1));
    // An account change starts a new session: logged once more, not never.
    p.section.onUserChanged();
    await p.push();
    expect(p.lows.where((e) => e == 'nslot_slot_too_large'), hasLength(2));
  });

  test('a slot over 15,000 kcal in SUM puts fine (per-entry ceilings)',
      () async {
    final (p, _) = await pair();
    for (var i = 0; i < 4; i++) {
      await p.log(d1, 'dinner', [('Feast$i', 1000, 9000)]);
    }
    await p.push();
    expect(server.rowJson(d1, 'dinner'), isNotNull);
  });

  test('a kill between move put and delete: stamp removes the older copy',
      () async {
    final (p, _) = await pair();
    final k = await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.move(k, 'dinner', killBeforeDelete: true);
    expect(p.meals, hasLength(2));
    await p.push();
    expect(p.meals, hasLength(1));
    expect(p.meals.single['meal_type'], 'dinner');
  });

  test('S12: an old-client write after the re-baseline → FULL re-baseline, '
      'no double count', () async {
    final (p, w) = await pair();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    await w.sync();
    server.oldClientUpsertSlot(d1, 'lunch', totals: {
      'total_calories': 400,
      'total_protein': 20,
      'total_carbs': 40,
      'total_fat': 10,
      'total_fiber': 2,
    }, items: [
      {'name': 'Dal', 'quantity_g': 150, 'calories': 200},
      {'name': 'Rice', 'quantity_g': 150, 'calories': 200},
    ]);
    await w.pull();
    await w.settle();
    expect(w.lows, contains('nslot_legacy_seen_rebaseline'));
    await w.sync();
    await w.sync();
    expect(w.meta['rebaselined'], isTrue);
    expect(w.meals, hasLength(1));
    expect(w.dayCalories(d1), 400);
    await p.sync();
    await p.sync();
    expect(p.dayCalories(d1), 400);
    expect(p.content(), w.content());
  });

  test('S14: a steady restore never moves a cursor and never regresses a slot',
      () async {
    final (p, w) = await pair();
    final k = await w.log(d1, 'lunch', [('Dal', 150, 200)]);
    await w.sync();
    final snapshot = await server.rowsPage();
    await w.editQty(k, 300);
    await w.sync();
    await p.sync();
    final cursor = p.nut.get(kNslotCursorKey);
    final before = p.content();
    final r = await p.section.restoreBody(kUser,
        preFetched: snapshot, fetchRows: () async => snapshot);
    expect(r.ok, isTrue);
    expect(p.content(), before);
    expect(p.nut.get(kNslotCursorKey), cursor);
  });

  test('the new push never writes the legacy nlog skip index', () async {
    final (p, _) = await pair();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    expect(server.liveSlots, hasLength(1));
    expect(p.nut.get(SyncSkipDomain.nlog.indexKey), isNull);
    expect(p.nut.get(SyncSkipDomain.nslot.indexKey), isNotNull);
  });

  test('a gated push stamps nothing: pre-build rows stay id-less until the '
      're-baseline', () async {
    final p = await dev('P');
    await p.log(d1, 'lunch', [('Dal', 150, 200)], withId: false);
    await p.push();
    expect(p.meals.single.containsKey('entry_id'), isFalse);
  });

  test('R16 P2-2: a cloud row with a bad meal_type is skipped by the pull, '
      'never a FULL re-baseline, no loop', () async {
    final (p, _) = await pair();
    server.oldClientUpsertSlot(d1, 'supper', totals: {
      'total_calories': 100,
      'total_protein': 1,
      'total_carbs': 1,
      'total_fat': 1,
      'total_fiber': 1,
    }, items: [
      {'name': 'X', 'quantity_g': 10, 'calories': 100},
    ]);
    for (var i = 0; i < 3; i++) {
      await p.sync();
    }
    expect(p.lows, contains('nslot_bad_meal_type'));
    expect(p.lows, isNot(contains('nslot_legacy_seen_rebaseline')));
    expect(p.meta['rebaselined'], isTrue);
    expect(p.meals, isEmpty);
  });

  test('a shuffled item embed gives the same signatures (no put)', () async {
    final (p, w) = await pair();
    await w.log(d1, 'lunch', [('A', 1, 1), ('B', 2, 2), ('C', 3, 3)]);
    await w.sync();
    server.shuffleItems = true;
    await p.sync();
    server.calls.clear();
    await p.push();
    expect(server.calls.where((c) => c.startsWith('put')), isEmpty);
    expect(p.content(), w.content());
  });
}
