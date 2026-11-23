// OI-348 Landing 1a-ii — an in-memory stand-in for migration 181, for ONE
// user. It mirrors the SQL contract by hand (spec §9 (e)); the live-verify SQL
// `supabase/tests/nutrition_slot_rpc_live_verify.sql` checks the real thing.
//
// CONTRACT TABLE (written before any test case; every rule names its SQL)
//
// C1  Revision rule. current(slot) = row.rev, else tomb.rev, else 0. Every
//     successful write sets current + 1. `rev` never decreases for a slot.
//     (§3.4; put/delete RPC bodies; trg_zz_nutrition_rev)
// C2  put(base): base != current → conflict {rev: current, row|tombstone|none},
//     nothing changes. base == current → row := {entries, items, totals},
//     rev := current + 1, updated_at := now(), tombstone removed. Insert after
//     a tombstone takes the tombstone's legacy_rev; an update keeps the row's.
//     created_at of a new row = min(entries[].ca) (bad/absent → now).
// C3  delete(base): conflict as C2. base == current and a row → row removed,
//     tombstone {rev: current + 1, legacy_rev: row.legacy_rev, deleted_at:
//     now()}. A conflict changes nothing (no deleted_at move). base == current
//     and no row → ok, noop, nothing changes.
// C4  Bounds (put): meal_type in the four; 1..100 entries; <= 500 items;
//     unique entry ids; every string <= 200; n per entry 0..500 and equal to
//     its items; sum n = items; per-entry totals 0..15000 kcal, macros
//     0..2000, fiber 0..500; per-item kcal 0..10000, macros 0..2000, fiber
//     0..500; round(p_totals, 3) == round(sum of entry totals, 3). A breach
//     throws [FakeRpcError] code 22023 and changes nothing.
// C5  Old-client writes (no RPC): [oldClientUpsertSlot] = a PostgREST parent
//     upsert (insert: rev = tomb.rev + 1 or 1, tombstone consumed; update:
//     rev + 1 unless nothing changed) then one item upsert per item (each a
//     parent bump) and the vacuum (a bump per removed item). Every such write
//     sets entries := null, legacy_rev := rev.
// C5a A write that changes nothing is INVISIBLE: trg_suppress_redundant_updates
//     (migration 149, BEFORE UPDATE, sorts before trg_zz_*) drops an UPDATE
//     whose new row equals the old one, so rev, legacy_rev, entries and
//     updated_at all stay. An item is compared on its payload columns only;
//     the DO UPDATE never sets entry_key, so an RPC item keeps it.
//     (B-pass seat A finding 3; live-verify case M.) [oldClientDeleteSlot] = a
//     top-level delete: tombstone {rev: row.rev + 1, legacy_rev: row.rev + 1}.
// C6  Every write moves `updated_at` (or `deleted_at`) to a fresh, strictly
//     later server time; times are server TEXT in PostgREST's shape: the
//     fraction trimmed of trailing zeros, none when zero
//     (`…:SS.ffffff+00:00`, `…:SS.12+00:00`, `…:SS+00:00`).
// C4a Strings are bounded by Dart `String.length` (UTF-16 units) in the client
//     and here, by `length()` (characters) in SQL. The client is the stricter
//     side (an emoji counts 2 here, 1 in SQL), so nothing the client sends is
//     rejected by the server for length. SQL casts a numeric string total
//     ("5") where this fake rejects it; the client never sends one
//     (nslotProjectNum returns a double). (B-pass seat A finding 5.)
// C7  rowsPage / tombsPage: ascending keyset order ((updated_at, id) and
//     (deleted_at, date, meal_type)); `after` = strictly after; `since` =
//     >=; limit honoured (a full page is exactly `limit` long).
// C8  Reads return the PostgREST shape: row columns + `nutrition_log_items`
//     (in a SHUFFLED order when [shuffleItems] is set: the embed has no order).
// C9  [rpcMissing] → every RPC throws NslotRpcMissing (PGRST202 stand-in).
// C10 Failure injection: [failNextRowPages] / [failNextTombPages] /
//     [failNextRpc] throw [FakeNetworkError]; [rowPageGate] holds a page until
//     the test completes it.
import 'dart:async';
import 'dart:math';

import 'package:icanbefitter/core/services/sync/nutrition_slot_remote.dart';

class FakeRpcError implements Exception {
  FakeRpcError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'FakeRpcError($code: $message)';
}

class FakeNetworkError implements Exception {
  @override
  String toString() => 'FakeNetworkError(SocketException: connection failed)';
}

class _Row {
  _Row({
    required this.id,
    required this.date,
    required this.meal,
    required this.rev,
    required this.legacyRev,
    required this.updatedAt,
    required this.createdAt,
    required this.entries,
    required this.items,
    required this.totals,
  });
  final String id;
  final String date;
  final String meal;
  int rev;
  int legacyRev;
  String updatedAt;
  String createdAt;
  List<Map<String, dynamic>>? entries;
  List<Map<String, dynamic>> items;
  Map<String, dynamic> totals;
}

class _Tomb {
  _Tomb(this.date, this.meal, this.rev, this.legacyRev, this.deletedAt);
  final String date;
  final String meal;
  int rev;
  int legacyRev;
  String deletedAt;
}

const _meals = {'breakfast', 'lunch', 'dinner', 'snacks'};

class FakeNslotServer implements NslotRemote {
  FakeNslotServer({int seed = 1}) : _rng = Random(seed);

  final Random _rng;
  final Map<String, _Row> _rows = {};
  final Map<String, _Tomb> _tombs = {};
  int _clockUs = DateTime.utc(2026, 11, 23).microsecondsSinceEpoch;
  int _idSeq = 0;

  bool rpcMissing = false;
  bool shuffleItems = false;
  int failNextRowPages = 0;
  int failNextTombPages = 0;
  int failNextRpc = 0;
  Completer<void>? rowPageGate;

  /// Every RPC call, for assertions (`put <date> <meal> <base>`).
  final List<String> calls = [];

  String _slot(String d, String m) => '$d|$m';

  /// C6: strictly increasing server time, as server text. Now and then the
  /// clock lands on a whole millisecond or a whole second, so the trimmed
  /// shapes PostgREST really sends are exercised (B-pass seat A finding 6).
  String _now() {
    _clockUs += 1000 + _rng.nextInt(5000);
    final roll = _rng.nextInt(8);
    if (roll == 0) {
      _clockUs += 1000000 - _clockUs % 1000000; // next whole second
    } else if (roll == 1) {
      _clockUs += 1000 - _clockUs % 1000; // next whole millisecond
    }
    return _text(_clockUs);
  }

  /// PostgREST's `timestamptz` text: the fraction without trailing zeros, and
  /// no fraction at all when it is zero (`…:05.12+00:00`, `…:05+00:00`).
  static String _text(int us) {
    final t = DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);
    String two(int v) => v.toString().padLeft(2, '0');
    var frac = (us % 1000000).toString().padLeft(6, '0');
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
    return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:'
        '${two(t.minute)}:${two(t.second)}${frac.isEmpty ? '' : '.$frac'}+00:00';
  }

  /// `ts >= since` is false. A `since` from the client (`overlapStart`,
  /// `…:05.000Z`) and a server text (`…:05+00:00`) are compared as INSTANTS,
  /// like timestamptz `>=`: as text, `+` sorts below `.`, so a row at exactly
  /// `since` would be dropped (B-pass delta seat, P3). Keyset `after` keys
  /// are server texts on both sides, whose text order is the instant order.
  static bool _before(String ts, String since) {
    final a = DateTime.tryParse(ts);
    final b = DateTime.tryParse(since);
    if (a == null || b == null) return ts.compareTo(since) < 0;
    return a.microsecondsSinceEpoch < b.microsecondsSinceEpoch;
  }

  /// Every server text this fake has written (rows and tombstones), for the
  /// shape-coverage assertion.
  List<String> get writtenTimes => [
        for (final r in _rows.values) r.updatedAt,
        for (final t in _tombs.values) t.deletedAt,
      ];

  /// Advances the server clock (e.g. past the 5-minute overlap).
  void advance(Duration d) => _clockUs += d.inMicroseconds;

  int currentRev(String d, String m) =>
      _rows[_slot(d, m)]?.rev ?? _tombs[_slot(d, m)]?.rev ?? 0;

  // ---- inspection --------------------------------------------------------

  Map<String, dynamic>? rowJson(String d, String m) {
    final r = _rows[_slot(d, m)];
    return r == null ? null : _rowJson(r);
  }

  Map<String, dynamic>? tombJson(String d, String m) {
    final t = _tombs[_slot(d, m)];
    return t == null ? null : _tombJson(t);
  }

  List<String> get liveSlots => _rows.keys.toList()..sort();

  Map<String, dynamic> _rowJson(_Row r) {
    final items = [
      for (var i = 0; i < r.items.length; i++)
        {
          ...r.items[i],
          'log_id': r.id,
          'item_index': i,
        },
    ];
    if (shuffleItems) items.shuffle(_rng);
    return {
      'id': r.id,
      'user_id': 'u1',
      'date': r.date,
      'meal_type': r.meal,
      'rev': r.rev,
      'legacy_rev': r.legacyRev,
      'updated_at': r.updatedAt,
      'created_at': r.createdAt,
      'entries': r.entries == null
          ? null
          : [for (final e in r.entries!) Map<String, dynamic>.from(e)],
      ...r.totals,
      'nutrition_log_items': items,
    };
  }

  Map<String, dynamic> _tombJson(_Tomb t) => {
        'user_id': 'u1',
        'date': t.date,
        'meal_type': t.meal,
        'rev': t.rev,
        'legacy_rev': t.legacyRev,
        'deleted_at': t.deletedAt,
      };

  Map<String, dynamic> _state(String d, String m, int rev) {
    final r = _rows[_slot(d, m)];
    final t = _tombs[_slot(d, m)];
    return {
      'status': 'conflict',
      'rev': rev,
      'row': r == null ? null : _rowJson(r),
      'tombstone': t == null ? null : _tombJson(t),
    };
  }

  void _rpcGate() {
    if (rpcMissing) throw const NslotRpcMissing('PGRST202');
    if (failNextRpc > 0) {
      failNextRpc--;
      throw FakeNetworkError();
    }
  }

  // ---- RPCs --------------------------------------------------------------

  @override
  Future<String> serverNow() async {
    _rpcGate();
    calls.add('now');
    return _now();
  }

  static num _r3(num v) => (v * 1000).round() / 1000;

  void _bounds(String meal, Map<String, dynamic> totals,
      List<Map<String, dynamic>> entries, List<Map<String, dynamic>> items) {
    void bad(String why) => throw FakeRpcError('22023', why);
    if (!_meals.contains(meal)) bad('bad slot');
    if (entries.isEmpty || entries.length > 100) bad('entry count');
    if (items.length > 500) bad('item count');
    final ids = entries.map((e) => e['id']).toSet();
    if (ids.length != entries.length) bad('duplicate entry id');
    final sums = <String, num>{
      'calories': 0,
      'protein': 0,
      'carbs': 0,
      'fat': 0,
      'fiber': 0,
    };
    var nTotal = 0;
    for (final e in entries) {
      final id = e['id'];
      if (id is! String || id.isEmpty) bad('entry without id');
      for (final k in const ['id', 'k', 's', 'la', 'ca', 'src']) {
        final v = e[k];
        if (v != null && v is! String) bad('entry field $k not text');
        if (v is String && v.length > 200) bad('entry field $k too long');
      }
      final n = e['n'];
      if (n is! int || n < 0 || n > 500) bad('entry n');
      final own = items.where((i) => i['entry_key'] == id).length;
      if (own != n) bad('entry item count mismatch');
      nTotal += n as int;
      final t = e['t'];
      if (t is! Map) bad('entry totals missing');
      for (final k in sums.keys) {
        final v = (t as Map)[k];
        if (v is! num) bad('entry total $k missing');
        final x = v as num;
        if (x < 0 ||
            (k == 'calories' && x > 15000) ||
            ((k == 'protein' || k == 'carbs' || k == 'fat') && x > 2000) ||
            (k == 'fiber' && x > 500)) {
          bad('entry total $k out of bounds');
        }
        sums[k] = sums[k]! + x;
      }
    }
    if (nTotal != items.length) bad('item count mismatch');
    for (final i in items) {
      final name = i['food_name'];
      if (i['entry_key'] is! String || name is! String || name.length > 200) {
        bad('bad item');
      }
      for (final k in const [
        'quantity_g',
        'calories',
        'protein',
        'carbs',
        'fat',
        'fiber',
      ]) {
        final v = i[k];
        if (v is! num) bad('item $k missing');
        final x = v as num;
        if ((k != 'quantity_g' && x < 0) ||
            (k == 'calories' && x > 10000) ||
            ((k == 'protein' || k == 'carbs' || k == 'fat') && x > 2000) ||
            (k == 'fiber' && x > 500)) {
          bad('item $k out of bounds');
        }
      }
    }
    for (final k in sums.keys) {
      final p = totals['total_$k'];
      if (p is! num || _r3(p) != _r3(sums[k]!)) bad('totals mismatch $k');
    }
  }

  @override
  Future<NslotWriteResult> put({
    required String date,
    required String mealType,
    required int baseRev,
    required Map<String, dynamic> totals,
    required List<Map<String, dynamic>> entries,
    required List<Map<String, dynamic>> items,
  }) async {
    _rpcGate();
    calls.add('put $date $mealType $baseRev');
    if (baseRev < 0) throw FakeRpcError('22023', 'bad base rev');
    _bounds(mealType, totals, entries, items);
    final slot = _slot(date, mealType);
    final current = currentRev(date, mealType);
    if (current != baseRev) {
      return NslotWriteResult.fromJson(_state(date, mealType, current));
    }
    final row = _rows[slot];
    final now = _now();
    final cleanItems = [
      for (final i in items)
        {
          'entry_key': i['entry_key'],
          'food_name': i['food_name'],
          'quantity_g': i['quantity_g'],
          'calories': i['calories'],
          'protein': i['protein'],
          'carbs': i['carbs'],
          'fat': i['fat'],
          'fiber': i['fiber'],
        },
    ];
    final cleanTotals = {
      for (final k in const [
        'total_calories',
        'total_protein',
        'total_carbs',
        'total_fat',
        'total_fiber',
      ])
        k: totals[k],
    };
    final cleanEntries = [for (final e in entries) Map<String, dynamic>.from(e)];
    if (row != null) {
      row
        ..rev = current + 1
        ..entries = cleanEntries
        ..items = cleanItems
        ..totals = cleanTotals
        ..updatedAt = now;
    } else {
      String? created;
      for (final e in entries) {
        final ca = e['ca'];
        final p = ca is String ? DateTime.tryParse(ca) : null;
        if (p != null) {
          final t = _text(p.microsecondsSinceEpoch);
          if (created == null || t.compareTo(created) < 0) created = t;
        }
      }
      _rows[slot] = _Row(
        id: 'row-${++_idSeq}-${_rng.nextInt(1 << 30)}',
        date: date,
        meal: mealType,
        rev: current + 1,
        legacyRev: _tombs[slot]?.legacyRev ?? 0,
        updatedAt: now,
        createdAt: created ?? now,
        entries: cleanEntries,
        items: cleanItems,
        totals: cleanTotals,
      );
    }
    _tombs.remove(slot);
    return NslotWriteResult.ok(rev: current + 1, stamp: now);
  }

  @override
  Future<NslotWriteResult> delete({
    required String date,
    required String mealType,
    required int baseRev,
  }) async {
    _rpcGate();
    calls.add('delete $date $mealType $baseRev');
    if (!_meals.contains(mealType)) throw FakeRpcError('22023', 'bad slot');
    final slot = _slot(date, mealType);
    final current = currentRev(date, mealType);
    if (current != baseRev) {
      return NslotWriteResult.fromJson(_state(date, mealType, current));
    }
    final row = _rows.remove(slot);
    if (row == null) return NslotWriteResult.ok(rev: current, stamp: null);
    final now = _now();
    _tombs[slot] = _Tomb(date, mealType, current + 1, row.legacyRev, now);
    return NslotWriteResult.ok(rev: current + 1, stamp: now);
  }

  // ---- old client (C5) ---------------------------------------------------

  /// An AAB +50 push of one slot: parent upsert, one upsert per item, vacuum.
  void oldClientUpsertSlot(String date, String meal,
      {required Map<String, dynamic> totals,
      required List<Map<String, dynamic>> items}) {
    final slot = _slot(date, meal);
    var row = _rows[slot];
    if (row == null) {
      final t = _tombs.remove(slot);
      final rev = (t?.rev ?? 0) + 1;
      final now = _now();
      row = _rows[slot] = _Row(
        id: 'row-${++_idSeq}-${_rng.nextInt(1 << 30)}',
        date: date,
        meal: meal,
        rev: rev,
        legacyRev: rev,
        updatedAt: now,
        createdAt: now,
        entries: null,
        items: [],
        totals: Map<String, dynamic>.from(totals),
      );
    } else {
      // C5a: an identical totals upsert is suppressed and changes nothing.
      if (row.totals.toString() != totals.toString()) {
        row
          ..rev = row.rev + 1
          ..totals = Map<String, dynamic>.from(totals)
          ..entries = null
          ..legacyRev = row.rev // the cascade already raised rev
          ..updatedAt = _now();
      }
    }
    final r = row;
    void bump() {
      r
        ..rev = r.rev + 1
        ..entries = null
        ..legacyRev = r.rev
        ..updatedAt = _now();
    }

    for (var i = 0; i < items.length; i++) {
      final payload = {
        'food_name': items[i]['name'] ?? '',
        'quantity_g': items[i]['quantity_g'],
        'calories': items[i]['calories'],
        'protein': items[i]['protein'],
        'carbs': items[i]['carbs'],
        'fat': items[i]['fat'],
        'fiber': items[i]['fiber'] ?? 0,
      };
      if (i < r.items.length) {
        // C5a: compare the payload columns only; the update keeps entry_key.
        final old = r.items[i];
        final same = payload.keys.every((k) => '${old[k]}' == '${payload[k]}');
        if (same) continue; // suppressed
        r.items[i] = {'entry_key': old['entry_key'], ...payload};
      } else {
        r.items.add({'entry_key': null, ...payload});
      }
      bump();
    }
    while (r.items.length > items.length) {
      r.items.removeLast();
      bump();
    }
  }

  /// An old client (or a device in legacy mode) re-pushing exactly the slot
  /// the server already holds: the same totals and the same item payloads
  /// (C5a). The real server suppresses every UPDATE, so nothing moves.
  void oldClientRepushIdentical(String date, String meal) {
    final row = _rows[_slot(date, meal)]!;
    oldClientUpsertSlot(date, meal,
        totals: Map<String, dynamic>.from(row.totals),
        items: [
          for (final i in row.items)
            {
              'name': i['food_name'],
              'quantity_g': i['quantity_g'],
              'calories': i['calories'],
              'protein': i['protein'],
              'carbs': i['carbs'],
              'fat': i['fat'],
              'fiber': i['fiber'],
            },
        ]);
  }

  /// A top-level non-RPC delete of a live user's slot (C5).
  void oldClientDeleteSlot(String date, String meal) {
    final slot = _slot(date, meal);
    final row = _rows.remove(slot);
    if (row == null) return;
    _tombs[slot] =
        _Tomb(date, meal, row.rev + 1, row.rev + 1, _now());
  }

  // ---- reads (C7, C8) ----------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> rowsPage({
    String? since,
    NslotRowKey? after,
    int limit = kNslotPageSize,
  }) async {
    final gate = rowPageGate;
    if (gate != null) await gate.future;
    if (failNextRowPages > 0) {
      failNextRowPages--;
      throw FakeNetworkError();
    }
    final all = _rows.values.toList()
      ..sort((a, b) {
        final c = a.updatedAt.compareTo(b.updatedAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final out = <Map<String, dynamic>>[];
    for (final r in all) {
      if (after != null) {
        final c = r.updatedAt.compareTo(after.updatedAt);
        if (c < 0 || (c == 0 && r.id.compareTo(after.id) <= 0)) continue;
      } else if (since != null && _before(r.updatedAt, since)) {
        continue;
      }
      out.add(_rowJson(r));
      if (out.length == limit) break;
    }
    return out;
  }

  @override
  Future<List<Map<String, dynamic>>> tombsPage({
    String? since,
    NslotTombKey? after,
    int limit = kNslotPageSize,
  }) async {
    if (failNextTombPages > 0) {
      failNextTombPages--;
      throw FakeNetworkError();
    }
    int cmp(_Tomb a, String ts, String d, String m) {
      var c = a.deletedAt.compareTo(ts);
      if (c != 0) return c;
      c = a.date.compareTo(d);
      if (c != 0) return c;
      return a.meal.compareTo(m);
    }

    final all = _tombs.values.toList()
      ..sort((a, b) => cmp(a, b.deletedAt, b.date, b.meal));
    final out = <Map<String, dynamic>>[];
    for (final t in all) {
      if (after != null) {
        if (cmp(t, after.deletedAt, after.date, after.mealType) <= 0) continue;
      } else if (since != null && _before(t.deletedAt, since)) {
        continue;
      }
      out.add(_tombJson(t));
      if (out.length == limit) break;
    }
    return out;
  }
}
