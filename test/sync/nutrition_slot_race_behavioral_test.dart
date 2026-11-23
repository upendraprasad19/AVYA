@Timeout(Duration(minutes: 3))
library;

// OI-348 Landing 1a-ii (diagnose a6c4e2) — races and cross-slot cases the
// engine mutation run found unguarded (rule 21): each test names the
// mutant that survived the first suite and dies here.
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

/// Delegates to [inner]; runs [afterRows] once, after the first rows page
/// returned and before the tombstone pages are read.
class _HookRemote implements NslotRemote {
  _HookRemote(this.inner);
  final FakeNslotServer inner;
  Future<void> Function()? afterRows;

  @override
  Future<String> serverNow() => inner.serverNow();

  @override
  Future<NslotWriteResult> put({
    required String date,
    required String mealType,
    required int baseRev,
    required Map<String, dynamic> totals,
    required List<Map<String, dynamic>> entries,
    required List<Map<String, dynamic>> items,
  }) =>
      inner.put(
          date: date,
          mealType: mealType,
          baseRev: baseRev,
          totals: totals,
          entries: entries,
          items: items);

  @override
  Future<NslotWriteResult> delete({
    required String date,
    required String mealType,
    required int baseRev,
  }) =>
      inner.delete(date: date, mealType: mealType, baseRev: baseRev);

  @override
  Future<List<Map<String, dynamic>>> rowsPage(
      {String? since, NslotRowKey? after, int limit = kNslotPageSize}) async {
    final page = await inner.rowsPage(since: since, after: after, limit: limit);
    final hook = afterRows;
    afterRows = null;
    if (hook != null) await hook();
    return page;
  }

  @override
  Future<List<Map<String, dynamic>>> tombsPage(
          {String? since, NslotTombKey? after, int limit = kNslotPageSize}) =>
      inner.tombsPage(since: since, after: after, limit: limit);
}

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
    dir = Directory.systemTemp.createTempSync('nslot_race');
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

  // Mutant drop_apply_day_pass (applyLocked without nslotDayPass).
  test('both devices move one meal to DIFFERENT slots → one copy, newer move '
      'wins on both', () async {
    final p = await dev('P');
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
    final k = await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.sync();
    await w.sync();
    final wk = w.meals.single['id'] as String;
    await p.move(k, 'dinner'); // older
    w.advanceClock(const Duration(minutes: 1));
    await w.move(wk, 'snacks'); // newer
    await p.sync();
    // Right after W's pull (before any push stamps and dedupes), W already
    // shows ONE copy: the screen re-reads after every pull.
    await w.pull();
    await w.settle();
    expect(w.meals, hasLength(1));
    expect(w.meals.single['meal_type'], 'snacks');
    expect(w.dayCalories(d1), 200);
    await w.sync();
    await p.sync();
    expect(w.meals, hasLength(1));
    expect(p.meals, hasLength(1));
    expect(p.meals.single['meal_type'], 'snacks');
    expect(p.content(), w.content());
    expect(p.dayCalories(d1), 200);
    expect(server.liveSlots, hasLength(1));
  });

  // Mutant first_seen_winner (winnersOf keeps the first offer per slot).
  test('a slot deleted between the rows page and the tombstones page is '
      'deleted by THAT pull (largest rev wins over everything read)', () async {
    final hook = _HookRemote(server);
    final p = await dev('P', remote: hook);
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
    final k = await w.log(d1, 'lunch', [('Dal', 150, 200)]);
    await w.sync();
    await p.sync();
    expect(p.meals, hasLength(1));
    await w.editQty(k, 300);
    await w.push();
    await w.settle();
    hook.afterRows = () async {
      final rev = server.currentRev(d1, 'lunch');
      final r = await server.delete(date: d1, mealType: 'lunch', baseRev: rev);
      expect(r.ok, isTrue);
    };
    await p.pull();
    await p.settle();
    expect(hook.afterRows, isNull, reason: 'the hook ran');
    expect(p.meals, isEmpty);
  });

  // Mutant drop_legacy_rev_from_test (legacy-seen keyed on isLegacy only).
  test('an old-client write that another device already converted still '
      'reads as legacy-seen (legacy_rev outlives the next RPC put)', () async {
    final p = await dev('P');
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
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
    // P meets the legacy row, re-baselines and puts the slot back through
    // the RPC: entries non-null again, legacy_rev unchanged.
    await p.sync();
    await p.sync();
    await p.sync();
    expect(p.meta['rebaselined'], isTrue);
    final key = p.meals.single['id'] as String;
    await p.editQty(key, 160);
    await p.sync();
    final row = (await server.rowsPage())
        .firstWhere((r) => r['meal_type'] == 'lunch');
    expect(row['entries'], isNotNull, reason: 'converted by P');
    // W never saw the legacy write: its ledger rev predates legacy_rev.
    await w.pull();
    await w.settle();
    expect(w.lows, contains('nslot_legacy_seen_rebaseline'));
    await w.sync();
    await w.sync();
    expect(w.meta['rebaselined'], isTrue);
    expect(w.content(), p.content());
  });

  // B-pass seat A finding 3 (fake C5a, live-verify case M): an old client
  // re-pushing a slot unchanged is suppressed by the server, so no device may
  // see a legacy write or run a FULL re-baseline because of it.
  test('an identical old-client re-push of an RPC-written slot is invisible',
      () async {
    final p = await dev('P');
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
    await p.log(d1, 'lunch', [('Dal', 150, 200), ('Rice', 100, 130)]);
    await p.sync();
    await w.sync();
    Map<String, dynamic> lunch() => server.rowJson(d1, 'lunch')!;
    final before = lunch();
    expect(before['entries'], isNotNull);
    server.oldClientRepushIdentical(d1, 'lunch');
    final after = lunch();
    expect(after['rev'], before['rev']);
    expect(after['legacy_rev'], before['legacy_rev']);
    expect(after['updated_at'], before['updated_at']);
    expect(after['entries'], isNotNull);
    expect(
        [
          for (final i in after['nutrition_log_items'] as List)
            (i as Map)['entry_key'],
        ],
        everyElement(isNotNull),
        reason: 'the item DO UPDATE never sets entry_key');
    await w.pull();
    await w.settle();
    expect(w.lows, isNot(contains('nslot_legacy_seen_rebaseline')));
    // A CHANGED re-push is still a legacy write (the mirror).
    server.oldClientUpsertSlot(d1, 'lunch', totals: {
      'total_calories': 999,
      'total_protein': 0,
      'total_carbs': 0,
      'total_fat': 0,
      'total_fiber': 0,
    }, items: [
      {'name': 'Dal', 'quantity_g': 150, 'calories': 999},
    ]);
    expect(lunch()['entries'], isNull);
    await w.pull();
    await w.settle();
    expect(w.lows, contains('nslot_legacy_seen_rebaseline'));
  });

  // B-pass seat B P1: the push loop re-read the WHOLE box for every slot, and
  // every row it built was signed (SHA-1) at once, so one push cost
  // O(slots x rows) hashes on the UI isolate, before the skip decision.
  test('a push of many unchanged slots builds and signs O(rows), not '
      'O(slots x rows)', () async {
    final p = await dev('P');
    await p.sync();
    final start = DateTime.utc(2026, 9, 1);
    for (var i = 0; i < 40; i++) {
      final d = start.add(Duration(days: i)).toIso8601String().substring(0, 10);
      for (final m in ['breakfast', 'lunch', 'dinner']) {
        await p.log(d, m, [('Dal', 100, 150)]);
      }
    }
    await p.sync();
    await p.sync();
    final rows = p.meals.length;
    expect(rows, 120);
    NslotLocalRow.rowsBuilt = 0;
    await p.push();
    await p.settle();
    // One whole-box read, then each slot re-reads its own date only. Measured
    // 2026-11-23: 810 rows built (each signed once) for 120 rows, 6.75 per
    // row; the old per-slot whole-box read built about slots x rows (14,400+).
    expect(NslotLocalRow.rowsBuilt, lessThanOrEqualTo(8 * rows));
    expect(server.calls.where((c) => c.startsWith('put')), hasLength(120),
        reason: 'the first pass put every slot once; this pass sent nothing');

    // B-pass delta seat P2: the pass above skips every slot, so `_pushSlot`
    // never ran. A pass that PUTS (one changed meal on each of the 40 days)
    // re-reads the slot's date inside `_pushSlot` and writes it back through
    // `applyLocked`; both must stay date-scoped too.
    final firstOfDay = <String>{};
    for (final m in p.meals) {
      if (firstOfDay.add(m['date'] as String)) {
        await p.editQty(m['id'] as String, 120);
      }
    }
    NslotLocalRow.rowsBuilt = 0;
    await p.push();
    await p.settle();
    expect(server.calls.where((c) => c.startsWith('put')), hasLength(160),
        reason: 'this pass put the 40 changed slots');
    expect(NslotLocalRow.rowsBuilt, lessThanOrEqualTo(8 * rows),
        reason: 'a put pass stays O(rows)');

    // And a pull that applies all 40 dates on a fresh device.
    final w = await dev('W', offset: 500);
    await w.sync(); // re-baseline: reads everything once
    await p.editQty(p.meals.first['id'] as String, 130);
    for (final m in p.meals.skip(1)) {
      await p.editQty(m['id'] as String, 140);
    }
    await p.push();
    await p.settle();
    NslotLocalRow.rowsBuilt = 0;
    await w.pull();
    await w.settle();
    expect(w.meals, hasLength(120));
    expect(NslotLocalRow.rowsBuilt, lessThanOrEqualTo(8 * rows),
        reason: 'a pull applying 40 dates stays O(rows)');
  });

  // Mutant conflict_no_merge (a rejected put retries without merging the
  // cloud's state in).
  test('W puts the same slot between P\'s pull and P\'s put → the conflict '
      'merges: both meals on both devices', () async {
    final spy = SpyRemote(server);
    final p = await dev('P', remote: spy);
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    await p.pull();
    await p.settle();
    spy.beforePut = () async {
      spy.beforePut = null;
      await w.log(d1, 'lunch', [('Rice', 200, 260)]);
      await w.push();
      await w.settle();
    };
    await p.push();
    await p.settle();
    expect(spy.beforePut, isNull, reason: 'the race ran');
    expect(p.meals, hasLength(2));
    await w.sync();
    expect(w.meals, hasLength(2));
    expect(p.content(), w.content());
    expect(p.dayCalories(d1), 460);
  });

  // Mutant ledger_from_local_after_ok (the ledger records the rows on disk
  // after the put instead of the payload the server accepted).
  test('an edit that lands while its slot\'s put is in flight is pushed by '
      'the next pass', () async {
    final spy = SpyRemote(server);
    final p = await dev('P', remote: spy);
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
    final k = await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    spy.beforePut = () async {
      spy.beforePut = null;
      await p.editQty(k, 300);
    };
    await p.push();
    await p.settle();
    expect(spy.beforePut, isNull, reason: 'the race ran');
    await p.sync();
    await w.sync();
    expect(((w.meals.single['items'] as List).single as Map)['quantity_g'], 300);
    expect(w.content(), p.content());
  });

  // Mutant drop_pull_owed (a pull that meets a busy section is dropped).
  test('a pull asked for while a push holds the section runs after it '
      '(owed), so a resume pull is never lost', () async {
    final spy = SpyRemote(server);
    final p = await dev('P', remote: spy);
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    spy.beforePut = () async {
      spy.beforePut = null;
      await w.log(d1, 'dinner', [('Roti', 80, 200)]);
      await w.push();
      await w.settle();
      expect(p.section.busy, isTrue);
      await p.pull(); // busy → owed, returns at once
    };
    await p.push();
    await p.settle();
    expect(spy.beforePut, isNull, reason: 'the race ran');
    expect(p.meals.map((m) => m['meal_type']).toSet(), {'lunch', 'dinner'});
  });

  // B-pass seat B P2: the owed pull is fired with nobody awaiting it; a throw
  // past the engine's network catch must land in the sync failure sink, not
  // escape as an unhandled async error (the test zone fails on one).
  test('an owed pull that throws is reported as pull_nutrition_slots',
      () async {
    final spy = SpyRemote(server);
    final p = await dev('P', remote: spy);
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    spy.beforePut = () async {
      spy.beforePut = null;
      await w.log(d1, 'dinner', [('Roti', 80, 200)]);
      await w.push();
      await w.settle();
      await p.pull(); // busy → owed
    };
    var thrown = 0;
    p.onInvalidate = () {
      // The owed pull writes W's dinner, then invalidates: throw there once.
      if (p.meals.any((m) => m['meal_type'] == 'dinner') && thrown == 0) {
        thrown++;
        throw StateError('apply failed');
      }
    };
    p.failures.clear();
    await p.push();
    await p.settle();
    expect(spy.beforePut, isNull, reason: 'the race ran');
    expect(thrown, 1, reason: 'the owed pull reached the throwing step');
    expect(p.failures, contains('pull_nutrition_slots'));
  });

  // B-pass seat B P3: owed flags are keyed by user only. After A -> B -> A,
  // the OLD A holder (generation 0) released last and consumed the owed push
  // the NEW A body (generation 2) had recorded, so it was never sent.
  test('an older generation\'s release does not eat this generation\'s owed '
      'push (A -> B -> A)', () async {
    final spy = SpyRemote(server);
    final p = await dev('P', remote: spy);
    await p.sync();
    await p.log(d1, 'lunch', [('Dal', 150, 200)]);
    late int before;
    Future<bool>? gen2;
    spy.beforePut = () async {
      spy.beforePut = null;
      p.section.onUserChanged(); // to B
      p.section.onUserChanged(); // back to A: generation 2, a fresh slot
      before = p.pushesScheduled;
      gen2 = p.section.pushBody(kUser); // holds the NEW slot
      await p.section.pushBody(kUser); // busy → owed for generation 2
    };
    await p.push(); // generation 0: its put runs the hook, then it releases
    await gen2;
    await p.settle();
    expect(spy.beforePut, isNull, reason: 'the race ran');
    expect(p.pushesScheduled, before + 1,
        reason: 'generation 2 must fire its own owed push');
  });

  // Mutant restore_queues_behind_rebaseline (a restore that meets this
  // user's running re-baseline queues behind it and runs its own read).
  test('a restore that meets a running re-baseline reports THAT run\'s '
      'result and reads nothing itself', () async {
    final p = await dev('P');
    var fetched = 0;
    server.rowPageGate = Completer<void>();
    final pulling = p.pull();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final restoring = p.section.restoreBody(kUser, fetchRows: () async {
      fetched++;
      return [];
    });
    server.failNextRowPages = 1; // the running re-baseline fails
    server.rowPageGate!.complete();
    server.rowPageGate = null;
    await pulling;
    final r = await restoring;
    expect(r.ok, isFalse);
    expect(r.reason, 'rebaseline_not_committed');
    expect(fetched, 0);
    expect(p.meta['rebaselined'], isNot(true));
  });

  // Mutant keep_old_ledger_shards (a FULL re-baseline keeps the shards of
  // dates the cloud no longer backs).
  test('a FULL re-baseline forgets every ledger rev the cloud no longer '
      'holds (a server that lost a slot, e.g. a database restore)', () async {
    final p = await dev('P');
    final w = await dev('W', offset: 500);
    await p.sync();
    await w.sync();
    const d0 = '2026-11-20';
    final k = await w.log(d0, 'dinner', [('Roti', 80, 200)]);
    await w.sync();
    await p.sync();
    await w.editQty(k, 90);
    await w.sync();
    await w.editQty(k, 100);
    await w.sync();
    await p.sync();
    await w.delete(k);
    await w.sync();
    await p.sync();
    expect(p.meals, isEmpty);
    // P's ledger now holds a d0 dinner rev > 1 with no entries. The server
    // loses the slot and its history; the kill switch runs once on P.
    final fresh = FakeNslotServer();
    p.server = fresh;
    p.restart();
    await p.section.legacyPass(kUser, () async {}, isPush: true);
    await p.sync();
    expect(p.meta['rebaselined'], isTrue);
    // Another device logs that slot on the new server: rev 1.
    final w2 = await dev('W2', offset: 900, remote: fresh);
    await w2.sync();
    await w2.log(d0, 'dinner', [('Dal', 150, 210)]);
    await w2.sync();
    expect(fresh.currentRev(d0, 'dinner'), 1);
    await p.sync();
    expect(p.meals, hasLength(1));
    expect(p.content(), w2.content());
  });

  // Mutant stamp_before_gate (NslotEngine.push stamps before its own gate;
  // the section's gate masks it, so the engine is driven directly).
  test('the engine push gate stamps nothing before the re-baseline', () async {
    final box = await Hive.openBox<dynamic>('nslot_gate_engine');
    final p = await dev('P');
    await box.put('nlog_${d1}_lunch_aaaaaaaa', {
      'date': d1,
      'meal_type': 'lunch',
      'items': [
        {'name': 'Dal', 'quantity_g': 150.0, 'calories': 200.0},
      ],
      'total_calories': 200,
      'logged_at': '2026-11-23T04:00:00.000Z',
      'created_at': '2026-11-23T04:00:00.000Z',
    });
    final before = Map<String, dynamic>.from(
        box.get('nlog_${d1}_lunch_aaaaaaaa') as Map);
    final engine = NslotEngine(
      box: box,
      remote: server,
      stale: () => false,
      reportFailure: (_, __) {},
      logLow: (_, __) {},
      invalidate: () {},
      clearUndoStash: () {},
    );
    expect(engine.rebaselined, isFalse);
    final index = SyncSkipIndex(
      box: box,
      domain: SyncSkipDomain.nslot,
      disabled: false,
      ownerChangedNow: () => false,
      reportFailure: (_, __, ___) {},
    );
    final out = await engine.push(index, Stopwatch()..start());
    expect(out.gated, isTrue);
    expect(out.wroteLocal, isFalse);
    expect(Map<String, dynamic>.from(box.get('nlog_${d1}_lunch_aaaaaaaa') as Map),
        before);
    expect(server.calls, isEmpty);
    expect(p.meals, isEmpty);
    await box.close();
  });
}
