// OI-348 Landing 1a-ii — test devices for the nutrition slot sync: each
// device is a real Hive nutrition box + config box + its own NslotSection,
// all talking to one FakeNslotServer. Local writes mimic NutritionWriteService
// (logMeal / editLog / moveMealLog / deleteLog shapes) without its singletons.
import 'dart:async';

import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_engine.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_merge.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_remote.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_section.dart';
import 'package:uuid/uuid.dart';

import 'nutrition_slot_fake_server.dart';

const String kUser = 'u1';

class Dev {
  Dev._(this.name, this.server, this.nut, this.cfg, int clockOffsetMs)
      : _clock = DateTime.utc(2026, 11, 23, 4).millisecondsSinceEpoch +
            clockOffsetMs;

  static int _seq = 0;

  static Future<Dev> open(String name, NslotRemote server,
      {int clockOffsetMs = 0}) async {
    final n = ++_seq;
    final nut = await Hive.openBox<dynamic>('nut_${name}_$n');
    final cfg = await Hive.openBox<dynamic>('cfg_${name}_$n');
    final d = Dev._(name, server, nut, cfg, clockOffsetMs);
    d._build();
    return d;
  }

  final String name;
  NslotRemote server;
  final Box<dynamic> nut;
  final Box<dynamic> cfg;
  late NslotSection section;
  int _clock;
  bool ownerChanged = false;

  final List<String> failures = [];
  final List<String> lows = [];
  int invalidations = 0;

  /// Test hook (e.g. simulate a kill right after the re-baseline's writes).
  void Function()? onInvalidate;
  int pushesScheduled = 0;
  int pullsFired = 0;

  void _build() {
    section = NslotSection(
      nutritionBox: () => nut,
      configBox: () => cfg,
      remoteFor: (_) => server,
      ownerChangedSince: (_) => ownerChanged,
      reportFailure: (op, e) => failures.add(op),
      logLow: (e, m) => lows.add(e),
      invalidate: () {
        invalidations++;
        onInvalidate?.call();
      },
      clearUndoStash: () {},
      schedulePush: () => pushesScheduled++,
    );
  }

  /// A new section (an app restart): the probe memo and caches are gone.
  void restart() => _build();

  String nowIso() {
    _clock += 1000;
    return DateTime.fromMillisecondsSinceEpoch(_clock, isUtc: true)
        .toIso8601String();
  }

  void advanceClock(Duration d) => _clock += d.inMilliseconds;

  // ---- local writes (NutritionWriteService shapes) -----------------------

  Future<String> log(String date, String meal, List<(String, num, num)> items,
      {String? entryId, bool withId = true}) async {
    final its = [
      for (final (n, q, kcal) in items)
        {
          'name': n,
          'quantity_g': q.toDouble(),
          'calories': kcal.toDouble(),
          'protein': 10.0,
          'carbs': 20.0,
          'fat': 5.0,
          'fiber': 1.0,
        },
    ];
    final base = NutritionWriteService.logKeyForMaps(date, meal, its);
    final key = NutritionWriteService.firstFreeLogKey(nut.containsKey, base);
    final ts = nowIso();
    final row = <String, dynamic>{
      'id': key,
      'log_key': key,
      'date': date,
      'meal_type': meal,
      'total_calories': its.fold<double>(0, (a, i) => a + ((i['calories'] as double?) ?? 0)).round(),
      'total_protein': its.length * 10,
      'total_carbs': its.length * 20,
      'total_fat': its.length * 5,
      'total_fiber': its.length,
      'items': its,
      'source': 'manualSearch',
      'logged_at': ts,
      'created_at': ts,
      if (withId) 'entry_id': entryId ?? const Uuid().v4(),
    };
    await nut.put(key, row);
    return key;
  }

  /// editLog: same key, new items, fresh logged_at.
  Future<void> editQty(String key, num qty) async {
    final m = Map<String, dynamic>.from(nut.get(key) as Map);
    final items = [
      for (final i in m['items'] as List)
        {...Map<String, dynamic>.from(i as Map), 'quantity_g': qty.toDouble()},
    ];
    m['items'] = items;
    m['logged_at'] = nowIso();
    await nut.put(key, m);
  }

  /// moveMealLog: put at the first free key of the new slot, then delete.
  Future<String> move(String key, String newMeal, {bool killBeforeDelete = false}) async {
    final m = Map<String, dynamic>.from(nut.get(key) as Map);
    final base = NutritionWriteService.logKeyForMaps(
        m['date'] as String, newMeal, m['items'] as List);
    final nk = NutritionWriteService.firstFreeLogKey(nut.containsKey, base);
    m['meal_type'] = newMeal;
    m['logged_at'] = nowIso();
    m['id'] = nk;
    m['log_key'] = nk;
    await nut.put(nk, m);
    if (!killBeforeDelete) await nut.delete(key);
    return nk;
  }

  Future<void> delete(String key) => nut.delete(key);

  // ---- sync -------------------------------------------------------------

  Future<void> push() => section.pushBody(kUser);
  Future<void> pull() => section.pullBody(kUser);

  /// pull (re-baselines first time) + push, then settle.
  Future<void> sync() async {
    await pull();
    await settle();
    await push();
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(Duration.zero);
      if (!section.busy) {
        await Future<void>.delayed(Duration.zero);
        if (!section.busy) return;
      }
    }
  }

  // ---- views -------------------------------------------------------------

  List<Map<dynamic, dynamic>> get meals => [
        for (final k in nut.keys)
          if (nslotIsMealRow(k, nut.get(k))) nut.get(k) as Map,
      ];

  /// Canonical content: sorted `date|meal|entry_id|signature` lines.
  List<String> content() => [
        for (final m in meals)
          '${m['date']}|${m['meal_type']}|${m['entry_id']}|${nslotSignature(m)}',
      ]..sort();

  /// Content without identity (for legacy rows with no id).
  List<String> contentNoId() => [
        for (final m in meals)
          '${m['date']}|${m['meal_type']}|${nslotSignature(m)}',
      ]..sort();

  num dayCalories(String date) => meals
      .where((m) => m['date'] == date)
      .fold<num>(0, (a, m) => a + ((m['total_calories'] as num?) ?? 0));

  Map<String, dynamic> get meta =>
      Map<String, dynamic>.from((nut.get(kNslotMetaKey) as Map?) ?? const {});

  Future<void> close() async {
    await nut.close();
    await cfg.close();
  }
}

/// Wraps a server to count or alter calls.
class SpyRemote implements NslotRemote {
  SpyRemote(this.inner);
  final NslotRemote inner;
  int puts = 0;
  int deletes = 0;
  int pages = 0;
  Future<void> Function()? beforePut;

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
  }) async {
    puts++;
    final b = beforePut;
    if (b != null) await b();
    return inner.put(
        date: date,
        mealType: mealType,
        baseRev: baseRev,
        totals: totals,
        entries: entries,
        items: items);
  }

  @override
  Future<NslotWriteResult> delete({
    required String date,
    required String mealType,
    required int baseRev,
  }) {
    deletes++;
    return inner.delete(date: date, mealType: mealType, baseRev: baseRev);
  }

  @override
  Future<List<Map<String, dynamic>>> rowsPage(
      {String? since, NslotRowKey? after, int limit = kNslotPageSize}) {
    pages++;
    return inner.rowsPage(since: since, after: after, limit: limit);
  }

  @override
  Future<List<Map<String, dynamic>>> tombsPage(
      {String? since, NslotTombKey? after, int limit = kNslotPageSize}) {
    pages++;
    return inner.tombsPage(since: since, after: after, limit: limit);
  }
}

/// Unused-import guard for analyzer (FakeNslotServer is the usual server).
typedef ServerFactory = FakeNslotServer Function();
