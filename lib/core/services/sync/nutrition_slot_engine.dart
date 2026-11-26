// OI-348 Landing 1a-ii — the nutrition slot sync engine (spec
// docs/plans/nutrition-slot-sync.md §4.4, §4.7-§4.12). One instance per body
// run; every method here is a LOCKED helper: the caller (NslotSection) holds
// the nutrition ticket. Nothing here takes the ticket, calls a body, or
// schedules a sync; it returns outcomes and the section acts on them.
//
// Every Hive write is preceded by [stale] (owner changed OR the section
// generation moved, §4.7), and every read-decide-write runs with no `await`
// between the read of the box and the START of both writes (§4.10).
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_merge.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_remote.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:uuid/uuid.dart';

/// §4.4 keys, all in the per-user `nutritionBox`.
const String kNslotLedgerPrefix = 'nslot_ledger_';
const String kNslotCursorKey = 'nslot_cursor';
const String kNslotMetaKey = 'nslot_meta';

/// §4.6 the ONLY way into legacy mode.
const String kDisableNutritionSlotSyncKey = 'disable_nutrition_slot_sync';

/// §4.8 / §4.9 budgets and timeouts.
const Duration kNslotRpcTimeout = Duration(seconds: 10);
const Duration kNslotPageTimeout = Duration(seconds: 20);
const Duration kNslotPushBudget = Duration(seconds: 15);
const int kNslotPushMaxSlots = 50;
const Duration kNslotPullBudget = Duration(seconds: 25);
const Duration kNslotOverlap = Duration(minutes: 5);
const int kNslotConflictRounds = 3;

final RegExp _kUuidKey = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

const Uuid _uuid = Uuid();

/// True for a key every nutrition-slot store helper owns (ledger, cursor,
/// meta). Whole-box readers and the export skip these (§4.4, §5).
bool isNslotStoreKey(Object? key) =>
    key is String &&
    (key.startsWith(kNslotLedgerPrefix) ||
        key == kNslotCursorKey ||
        key == kNslotMetaKey);

/// A local meal row of this build's shape (`nlog_` key, Map value).
bool nslotIsMealRow(Object? key, Object? value) =>
    key is String && key.startsWith('nlog_') && value is Map;

/// §4.11: a UUID-keyed meal-shaped row that is not a saved meal or template
/// (the pre-Test-12.8 restore shape 1a-i keeps on purpose).
bool nslotIsUuidMealRow(Object? key, Object? value) {
  if (key is! String || !_kUuidKey.hasMatch(key) || value is! Map) {
    return false;
  }
  if (value['date'] is! String || value['meal_type'] is! String) return false;
  if (value['is_saved_meal'] == true) return false;
  if (value.containsKey('is_template')) return false;
  return true;
}

/// §4.1 undo rules. Returns the reason an undo of [payload] must be refused,
/// or null when it may go back. [box] is the live nutrition box; [newMode] is
/// false in legacy mode (no refusal there).
String? nslotUndoRefusal(
    Map<dynamic, dynamic> payload, Box<dynamic> box, bool newMode) {
  if (!newMode) return null;
  final id = payload['entry_id'];
  if (id is String && id.isNotEmpty) {
    for (final k in box.keys) {
      final v = box.get(k);
      if (nslotIsMealRow(k, v) && (v as Map)['entry_id'] == id) {
        return 'entry_already_present';
      }
    }
    return null;
  }
  final meta = box.get(kNslotMetaKey);
  if (meta is Map &&
      (meta['rebaselined'] == true || meta['inflight_since'] != null)) {
    return 'id_less_after_rebaseline';
  }
  return null;
}

/// One local meal row as the engine sees it.
class NslotLocalRow {
  NslotLocalRow(this.key, this.value)
      : id = value['entry_id'] is String ? value['entry_id'] as String : null,
        date = (value['date'] ?? '').toString(),
        meal = (value['meal_type'] ?? '').toString(),
        signature = nslotSignature(value),
        loggedAt = nslotNormLoggedAt(value['logged_at']) {
    rowsBuilt++;
  }

  /// How many rows were built, each with one SHA-1 signature. A push must
  /// keep this O(rows): B-pass seat B P1 (2026-11-23) found the push loop
  /// rebuilding the whole box per slot, O(slots x rows) on the UI isolate.
  @visibleForTesting
  static int rowsBuilt = 0;

  final String key;
  final Map<dynamic, dynamic> value;
  final String? id;
  final String date;
  final String meal;
  final String signature;
  final String loggedAt;

  NslotEntryView get view =>
      NslotEntryView(id: id ?? '', signature: signature, loggedAt: loggedAt);
}

/// A ledger slot (§4.4): the 3-way base.
class NslotLedgerSlot {
  NslotLedgerSlot({required this.rev, required this.ua, required this.e});
  final int rev;
  final String ua;
  final Map<String, String> e;

  static NslotLedgerSlot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rev = raw['rev'];
    if (rev is! num) return null;
    final e = raw['e'];
    return NslotLedgerSlot(
      rev: rev.toInt(),
      ua: (raw['ua'] ?? '').toString(),
      e: {
        if (e is Map)
          for (final x in e.entries) x.key.toString(): x.value.toString(),
      },
    );
  }

  Map<String, dynamic> toJson() => {'rev': rev, 'ua': ua, 'e': e};
}

/// What a push pass did (the section decides owed flags and follow-ups).
class NslotPushOutcome {
  bool gated = false;
  bool legacySeen = false;
  bool rpcMissing = false;
  bool stoppedOnBudget = false;
  bool wroteLocal = false;
  int confirmedRpcs = 0;
}

class NslotPullOutcome {
  bool rebaselineRan = false;
  bool rebaselineCommitted = false;
  bool legacySeen = false;
  bool failed = false;
  bool wroteLocal = false;
  bool dirty = false;
}

class NslotRestoreOutcome {
  bool legacySeen = false;
  bool wroteLocal = false;
}

/// One pass of the engine for [userId]. The section builds a fresh one per
/// body run (the probe memo and the re-baseline page cache live there).
class NslotEngine {
  NslotEngine({
    required this.box,
    required this.remote,
    required this.stale,
    required this.reportFailure,
    required this.logLow,
    required this.invalidate,
    required this.clearUndoStash,
    String Function()? newEntryId,
    DateTime Function()? clock,
  })  : _newId = newEntryId ?? (() => _uuid.v4()),
        _clock = clock ?? DateTime.now;

  final Box<dynamic> box;
  final NslotRemote remote;

  /// Owner changed OR section generation moved (§4.7).
  final bool Function() stale;
  final void Function(String opType, Object error) reportFailure;
  final void Function(String event, String message) logLow;
  final void Function() invalidate;
  final void Function() clearUndoStash;
  final String Function() _newId;
  final DateTime Function() _clock;

  // ---------------------------------------------------------------- store

  Map<String, dynamic> readMeta() {
    final raw = box.get(kNslotMetaKey);
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  bool get rebaselined => readMeta()['rebaselined'] == true;

  Future<bool> writeMeta(Map<String, dynamic> meta) async {
    if (stale()) return false;
    await box.put(kNslotMetaKey, meta);
    return true;
  }

  Map<String, NslotLedgerSlot> readLedger(String date) {
    final raw = box.get('$kNslotLedgerPrefix$date');
    final out = <String, NslotLedgerSlot>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final s = NslotLedgerSlot.fromJson(e.value);
        if (s != null) out[e.key.toString()] = s;
      }
    }
    return out;
  }

  Map<String, Map<String, NslotLedgerSlot>> readAllLedgers() {
    final out = <String, Map<String, NslotLedgerSlot>>{};
    for (final k in box.keys) {
      if (k is String && k.startsWith(kNslotLedgerPrefix)) {
        out[k.substring(kNslotLedgerPrefix.length)] =
            readLedger(k.substring(kNslotLedgerPrefix.length));
      }
    }
    return out;
  }

  Future<bool> _writeLedgerShards(
      Map<String, Map<String, NslotLedgerSlot>> byDate) async {
    if (byDate.isEmpty) return true;
    if (stale()) return false;
    await box.putAll({
      for (final e in byDate.entries)
        '$kNslotLedgerPrefix${e.key}': {
          for (final s in e.value.entries) s.key: s.value.toJson(),
        },
    });
    return true;
  }

  Map<String, dynamic> readCursor() {
    final raw = box.get(kNslotCursorKey);
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  /// [ts] minus the overlap, as text (a parse is fine inside the overlap).
  static String? overlapStart(String? ts) {
    if (ts == null || ts.isEmpty) return null;
    final p = DateTime.tryParse(ts);
    if (p == null) return null;
    return p.toUtc().subtract(kNslotOverlap).toIso8601String();
  }

  // ---------------------------------------------------------- local reads

  /// Every `nlog_` row grouped by date (rows with an `entry_id` only when
  /// [withIdOnly]).
  Map<String, List<NslotLocalRow>> _rowsByDate({bool withIdOnly = true}) {
    final out = <String, List<NslotLocalRow>>{};
    for (final k in box.keys) {
      // The key alone decides most rows: no value read for a non-meal key.
      if (k is! String || !k.startsWith('nlog_')) continue;
      final v = box.get(k);
      if (!nslotIsMealRow(k, v)) continue;
      final r = NslotLocalRow(k, v as Map);
      if (withIdOnly && r.id == null) continue;
      if (r.date.isEmpty) continue;
      (out[r.date] ??= []).add(r);
    }
    return out;
  }

  /// The id-bearing `nlog_` rows of ONE date, read fresh. The stored date is
  /// checked before any row is built, so a per-slot re-read inside the push
  /// loop costs one key walk and signs only that date's rows (B-pass seat B
  /// P1: re-reading the whole box per slot made a push O(slots x rows) SHA-1
  /// hashes on the UI isolate).
  List<NslotLocalRow> _rowsOfDate(String date) {
    final out = <NslotLocalRow>[];
    for (final k in box.keys) {
      if (k is! String || !k.startsWith('nlog_')) continue;
      final v = box.get(k);
      if (!nslotIsMealRow(k, v)) continue;
      if ('${(v as Map)['date'] ?? ''}' != date) continue;
      final r = NslotLocalRow(k, v);
      if (r.id != null) out.add(r);
    }
    return out;
  }

  /// §4.5 duplicate-id rule, read-only: per date, an entry id held by two
  /// rows counts only in the newer copy. Returns {meal: {id: row}} for slots
  /// with admitted meal types.
  Map<String, Map<String, NslotLocalRow>> _slotsOfDate(
      List<NslotLocalRow> rows) {
    final losers = nslotDayPass([
      for (final r in rows)
        NslotDayCopy(view: r.view, mealType: r.meal, key: r.key),
    ]);
    final out = <String, Map<String, NslotLocalRow>>{};
    for (final r in rows) {
      if (losers.contains(r.key)) continue;
      if (!nslotAdmitMealType(r.meal)) continue;
      (out[r.meal] ??= {})[r.id!] = r;
    }
    return out;
  }

  // ---------------------------------------------------------- stampLocked

  /// §4.7 / §4.8: stamps an `entry_id` on every id-less `nlog_` row (new mode
  /// AND re-baselined only — the caller checks), normalises missing
  /// timestamps, and removes the OLDER of two same-date rows holding one id
  /// (a kill between `moveMealLog`'s put and delete).
  Future<bool> stampLocked() async {
    if (stale()) return false;
    final now = _clock().toUtc().toIso8601String();
    final puts = <String, Map<String, dynamic>>{};
    final rows = <NslotLocalRow>[];
    for (final k in box.keys) {
      final v = box.get(k);
      if (!nslotIsMealRow(k, v)) continue;
      final m = v as Map;
      final hasId = m['entry_id'] is String && (m['entry_id'] as String).isNotEmpty;
      final ca = m['created_at'];
      final la = m['logged_at'];
      if (hasId && ca is String && la is String) {
        rows.add(NslotLocalRow(k as String, m));
        continue;
      }
      final copy = Map<String, dynamic>.from(m);
      if (!hasId) copy['entry_id'] = _newId();
      final created = (ca is String ? ca : null) ?? (la is String ? la : null) ?? now;
      copy['created_at'] = created;
      copy['logged_at'] = la is String ? la : created;
      puts[k as String] = copy;
      rows.add(NslotLocalRow(k, copy));
    }
    final byDate = <String, List<NslotLocalRow>>{};
    for (final r in rows) {
      (byDate[r.date] ??= []).add(r);
    }
    final deletes = <String>{};
    for (final dayRows in byDate.values) {
      deletes.addAll(nslotDayPass([
        for (final r in dayRows)
          NslotDayCopy(view: r.view, mealType: r.meal, key: r.key),
      ]));
    }
    puts.removeWhere((k, _) => deletes.contains(k));
    if (puts.isEmpty && deletes.isEmpty) return false;
    if (stale()) return false;
    final w1 = puts.isEmpty ? Future<void>.value() : box.putAll(puts);
    final w2 = deletes.isEmpty ? Future<void>.value() : box.deleteAll(deletes);
    await Future.wait([w1, w2]);
    return true;
  }

  // ------------------------------------------------------------- payload

  /// §4.2 / §4.3: the RPC payload of one slot's rows, or null when a bound
  /// is breached (§3.5: checked BEFORE any call; permanent).
  static ({
    Map<String, dynamic> totals,
    List<Map<String, dynamic>> entries,
    List<Map<String, dynamic>> items,
    Map<String, String> sigs,
  })? buildPayload(List<NslotLocalRow> rows) {
    final sorted = [...rows]..sort((a, b) => a.key.compareTo(b.key));
    if (sorted.isEmpty || sorted.length > kNslotMaxEntriesPerSlot) return null;
    final entries = <Map<String, dynamic>>[];
    final items = <Map<String, dynamic>>[];
    final sigs = <String, String>{};
    final sums = {'calories': 0.0, 'protein': 0.0, 'carbs': 0.0, 'fat': 0.0, 'fiber': 0.0};
    bool tooLong(Object? s) => s is String && s.length > kNslotMaxStringLength;
    bool over(String f, double v, {bool item = false}) {
      if (v < 0) return true;
      if (f == 'calories') return v > (item ? 10000 : 15000);
      if (f == 'fiber') return v > 500;
      return v > 2000;
    }

    for (final r in sorted) {
      final v = r.value;
      final rawItems = v['items'] is List ? v['items'] as List : const [];
      final own = <Map<String, dynamic>>[];
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final name = (raw['name'] ?? raw['food_name'] ?? '').toString().trim();
        if (tooLong(name)) return null;
        final it = <String, dynamic>{
          'entry_key': r.id,
          'food_name': name,
          'quantity_g': nslotProjectNum(raw['quantity_g']),
        };
        for (final f in const ['calories', 'protein', 'carbs', 'fat', 'fiber']) {
          final x = nslotProjectNum(raw[f]);
          if (over(f, x, item: true)) return null;
          it[f] = x;
        }
        own.add(it);
      }
      final t = <String, dynamic>{};
      for (final f in sums.keys.toList()) {
        final x = nslotProjectNum(v['total_$f']);
        if (over(f, x)) return null;
        t[f] = x;
        sums[f] = sums[f]! + x;
      }
      final entry = <String, dynamic>{
        'id': r.id,
        'k': r.key,
        's': r.signature,
        'la': v['logged_at'],
        'ca': v['created_at'],
        'src': v['source']?.toString(),
        't': t,
        'n': own.length,
      };
      for (final k in const ['id', 'k', 's', 'la', 'ca', 'src']) {
        if (tooLong(entry[k])) return null;
      }
      entries.add(entry);
      items.addAll(own);
      sigs[r.id!] = r.signature;
    }
    if (items.length > kNslotMaxItemsPerSlot) return null;
    return (
      totals: {
        for (final f in sums.keys) 'total_$f': nslotProjectNum(sums[f]),
      },
      entries: entries,
      items: items,
      sigs: sigs,
    );
  }

  // ---------------------------------------------------------- legacy-seen

  /// §4.5: an ADMITTED row winner newer than the ledger that is legacy or
  /// carries a legacy write newer than the ledger. The stale-skip gate
  /// (rev <= ledger rev) is the caller's and runs first.
  static bool isLegacySeen(NslotWinner w, NslotLedgerSlot? ledger) {
    final row = w.row;
    if (row == null) return false;
    if (!nslotAdmitMealType(row.mealType)) return false;
    final base = ledger?.rev ?? 0;
    if (row.rev <= base) return false;
    return row.isLegacy || row.legacyRev > base;
  }

  Future<void> _markLegacySeen(String where) async {
    final meta = readMeta();
    meta['rebaselined'] = false;
    // A kill-switch FULL outranks a pending legacy-seen one (§4.6).
    if (meta['full'] != 'legacy_pass') meta['full'] = 'legacy_seen';
    logLow('nslot_legacy_seen_rebaseline', 'where=$where');
    await writeMeta(meta);
  }

  // --------------------------------------------------------- applyLocked

  /// §4.10: merges [winners] (per meal of [date]) into the local rows with
  /// [bases] as the 3-way base, runs the day pass over the whole date, and
  /// writes once. Returns (wrote, dirtyMeals): a meal whose local result
  /// differs from its winner is dirty (the next push sends it).
  Future<({bool wrote, Set<String> dirty})> applyLocked(
    String date,
    Map<String, NslotWinner> winners,
    Map<String, Map<String, String>> bases,
  ) async {
    if (stale()) return (wrote: false, dirty: <String>{});
    // ---- synchronous from here to the start of both writes ----
    final all = _rowsOfDate(date);
    // Per slot, two rows of one id: the newer counts (the older is removed).
    final removed = <String>{};
    final localByMeal = <String, Map<String, NslotLocalRow>>{};
    for (final r in all) {
      final slot = localByMeal[r.meal] ??= {};
      final prev = slot[r.id!];
      if (prev == null) {
        slot[r.id!] = r;
        continue;
      }
      final c = nslotCompareNewer(r.view, prev.view);
      final rWins = c > 0 || (c == 0 && r.key.compareTo(prev.key) > 0);
      if (rWins) {
        removed.add(prev.key);
        slot[r.id!] = r;
      } else {
        removed.add(r.key);
      }
    }

    final kept = <NslotDayCopy>[]; // rows that stay at their key
    final incoming = <({Map<String, dynamic> row, String meal, String? sameKey, String? k})>[];
    final winnerSigs = <String, Map<String, String>>{};
    for (final meal in localByMeal.keys.toSet().union(winners.keys.toSet())) {
      final local = localByMeal[meal] ?? const <String, NslotLocalRow>{};
      final w = winners[meal];
      if (w == null) {
        for (final r in local.values) {
          kept.add(NslotDayCopy(view: r.view, mealType: meal, key: r.key));
        }
        continue;
      }
      final cloudRows = <String, Map<String, dynamic>>{};
      for (final e in w.row?.toLocalEntries() ?? const <Map<String, dynamic>>[]) {
        cloudRows[e['entry_id'] as String] = e;
      }
      final cloudViews = {
        for (final e in cloudRows.entries)
          e.key: NslotEntryView(
            id: e.key,
            signature: nslotSignature(e.value),
            loggedAt: nslotNormLoggedAt(e.value['logged_at']),
          ),
      };
      winnerSigs[meal] = {
        for (final e in cloudViews.entries) e.key: e.value.signature,
      };
      final choices = nslotMergeSlot(
        base: bases[meal] ?? const {},
        local: {for (final e in local.entries) e.key: e.value.view},
        cloud: cloudViews,
      );
      for (final c in choices.entries) {
        final l = local[c.key];
        switch (c.value) {
          case NslotChoice.keepLocal:
            if (l != null) {
              kept.add(NslotDayCopy(view: l.view, mealType: meal, key: l.key));
            }
          case NslotChoice.takeCloud:
            final row = cloudRows[c.key]!;
            incoming.add((
              row: row,
              meal: meal,
              sameKey: l?.key,
              k: row['_k'] as String?,
            ));
          case NslotChoice.remove:
            if (l != null) removed.add(l.key);
        }
      }
    }

    // Placement (§4.5) against: keys now − removed + placed so far.
    final placed = <String, Map<String, dynamic>>{};
    bool taken(String k) =>
        placed.containsKey(k) || (box.containsKey(k) && !removed.contains(k));
    final placedCopies = <NslotDayCopy>[];
    for (final inc in incoming) {
      final id = inc.row['entry_id'] as String;
      final key = nslotPlaceKey(
        date: date,
        meal: inc.meal,
        entryId: id,
        cloudKey: inc.k ??
            NutritionWriteService.logKeyForMaps(
                date, inc.meal, (inc.row['items'] as List?) ?? const []),
        sameSlotKey: inc.sameKey,
        taken: (k) => k != inc.sameKey && taken(k),
      );
      final row = Map<String, dynamic>.from(inc.row)
        ..remove('_k')
        ..['id'] = key
        ..['log_key'] = key;
      NutritionWriteService.clampRestoredNutritionRow(row);
      placed[key] = row;
      removed.remove(key);
      placedCopies.add(NslotDayCopy(
        view: NslotEntryView(
          id: id,
          signature: nslotSignature(row),
          loggedAt: nslotNormLoggedAt(row['logged_at']),
        ),
        mealType: inc.meal,
        key: key,
      ));
    }

    // Day pass over the whole date (S4, S4b).
    final losers = nslotDayPass([...kept, ...placedCopies]);
    for (final k in losers) {
      if (placed.remove(k) == null) removed.add(k);
    }
    removed.removeAll(placed.keys);

    // Dirty: the local result of a merged meal differs from its winner.
    final dirty = <String>{};
    final resultSigs = <String, Map<String, String>>{};
    for (final c in [...kept, ...placedCopies]) {
      if (losers.contains(c.key)) continue;
      (resultSigs[c.mealType] ??= {})[c.view.id] = c.view.signature;
    }
    for (final meal in winners.keys) {
      final a = resultSigs[meal] ?? const {};
      final b = winnerSigs[meal] ?? const {};
      if (a.length != b.length || a.entries.any((e) => b[e.key] != e.value)) {
        dirty.add(meal);
      }
    }
    // Days touched outside the winners (the day pass removed a copy there).
    for (final k in losers) {
      final meal = [...kept, ...placedCopies].firstWhere((c) => c.key == k).mealType;
      dirty.add(meal);
    }

    if (placed.isEmpty && removed.isEmpty) return (wrote: false, dirty: dirty);
    if (stale()) return (wrote: false, dirty: <String>{});
    final w1 = placed.isEmpty ? Future<void>.value() : box.putAll(placed);
    final w2 = removed.isEmpty ? Future<void>.value() : box.deleteAll(removed);
    // ---- end of the synchronous run ----
    await Future.wait([w1, w2]);
    return (wrote: true, dirty: dirty);
  }

  // ---------------------------------------------------------------- push

  /// §4.8. [index] is the `nslot` skip index of this pass; [budget] started
  /// when the body started.
  Future<NslotPushOutcome> push(SyncSkipIndex index, Stopwatch budget) async {
    final out = NslotPushOutcome();
    if (!rebaselined) {
      out.gated = true;
      return out;
    }
    if (await stampLocked()) out.wroteLocal = true;
    if (stale()) return out;

    final rowsByDate = _rowsByDate();
    final ledgers = readAllLedgers();
    final dates = {...rowsByDate.keys, ...ledgers.keys}.toList()..sort();
    final putSlots = <(String, String)>[];
    final deleteSlots = <(String, String)>[];
    for (final d in dates) {
      final slots = _slotsOfDate(rowsByDate[d] ?? const []);
      final ledger = ledgers[d] ?? const <String, NslotLedgerSlot>{};
      for (final m in {...slots.keys, ...ledger.keys}.toList()..sort()) {
        if ((slots[m] ?? const {}).isNotEmpty) {
          putSlots.add((d, m));
        } else if ((ledger[m]?.e ?? const {}).isNotEmpty) {
          deleteSlots.add((d, m));
        }
      }
    }
    final visited = <String>{};
    var issued = 0;
    for (final (date, meal) in [...putSlots, ...deleteSlots]) {
      if (index.aborted || out.legacySeen || out.rpcMissing) break;
      if (stale()) break;
      final slotKey = '$date $meal';
      visited.add(slotKey);
      if (issued >= kNslotPushMaxSlots || budget.elapsed > kNslotPushBudget) {
        out.stoppedOnBudget = true;
        continue; // keep it live in the index; sent next pass
      }
      // Fresh view of the slot for the fingerprint and the closure (one
      // date only: see _rowsOfDate).
      final local = _slotsOfDate(_rowsOfDate(date))[meal] ??
          const <String, NslotLocalRow>{};
      final ledger = readLedger(date)[meal];
      final sortedPairs = (local.entries.map((e) => '${e.key}:${e.value.signature}')
              .toList()
            ..sort())
          .join(',');
      final fp = '${ledger?.rev ?? 0}|${ledger?.ua ?? ''}|$sortedPairs';
      final isDelete = local.isEmpty;
      var rpcIssued = false;
      await index.pushIfChanged(
        slotKey,
        () => fp,
        () async {
          final r = await _pushSlot(date, meal, out);
          rpcIssued = r.issued;
          return r.confirmed;
        },
        opType: isDelete ? 'sync_nslot_delete' : 'sync_nslot_put',
      );
      if (rpcIssued) issued++;
    }
    await index.commit(liveKeys: visited);
    return out;
  }

  /// One slot: put or delete, conflict merge and retry (max 3 rounds).
  /// Returns confirmed (the slot equals the ledger after this call) and
  /// whether any RPC was issued. A network error is rethrown (the skip index
  /// reports it as an outage-shaped `sync_nslot_*` failure).
  Future<({bool confirmed, bool issued})> _pushSlot(
      String date, String meal, NslotPushOutcome out) async {
    var issued = false;
    for (var round = 0; round <= kNslotConflictRounds; round++) {
      if (stale()) return (confirmed: false, issued: issued);
      final local = _slotsOfDate(_rowsOfDate(date))[meal] ??
          const <String, NslotLocalRow>{};
      final ledger = readLedger(date)[meal];
      final base = ledger?.e ?? const <String, String>{};
      final localSigs = {
        for (final e in local.entries) e.key: e.value.signature,
      };
      if (localSigs.length == base.length &&
          localSigs.entries.every((e) => base[e.key] == e.value)) {
        return (confirmed: true, issued: issued);
      }
      if (round == kNslotConflictRounds) {
        logLow('nslot_conflict_rounds_exhausted', 'slot=$date $meal');
        return (confirmed: false, issued: issued);
      }
      final baseRev = ledger?.rev ?? 0;
      NslotWriteResult res;
      Map<String, String> sent;
      try {
        if (local.isEmpty) {
          sent = const {};
          if (stale()) return (confirmed: false, issued: issued);
          issued = true;
          res = await remote
              .delete(date: date, mealType: meal, baseRev: baseRev)
              .timeout(kNslotRpcTimeout);
        } else {
          final p = buildPayload(local.values.toList());
          if (p == null) {
            logLow('nslot_slot_too_large', 'slot=$date $meal');
            return (confirmed: false, issued: issued);
          }
          sent = p.sigs;
          if (stale()) return (confirmed: false, issued: issued);
          issued = true;
          res = await remote
              .put(
                date: date,
                mealType: meal,
                baseRev: baseRev,
                totals: p.totals,
                entries: p.entries,
                items: p.items,
              )
              .timeout(kNslotRpcTimeout);
        }
      } on NslotRpcMissing {
        out.rpcMissing = true;
        return (confirmed: false, issued: issued);
      }
      if (stale()) return (confirmed: false, issued: issued);
      if (res.ok) {
        out.confirmedRpcs++;
        final shard = readLedger(date);
        shard[meal] =
            NslotLedgerSlot(rev: res.rev, ua: res.stamp ?? '', e: sent);
        await _writeLedgerShards({date: shard});
        return (confirmed: true, issued: issued);
      }
      // Conflict: merge the reply like a pulled winner (§4.8).
      final w = res.winner;
      if (w != null && w.row != null && !nslotAdmitMealType(w.row!.mealType)) {
        logLow('nslot_bad_meal_type', 'slot=$date');
        return (confirmed: false, issued: issued);
      }
      if (w != null && isLegacySeen(w, ledger)) {
        await _markLegacySeen('push_conflict');
        out.legacySeen = true;
        return (confirmed: false, issued: issued);
      }
      final shard = readLedger(date);
      if (w == null) {
        // Nothing at all on the server (rev 0): local entries are all new.
        shard[meal] = NslotLedgerSlot(rev: res.rev, ua: '', e: const {});
      } else {
        final applied = await applyLocked(
            date, {meal: w}, {meal: ledger?.e ?? const {}});
        if (applied.wrote) out.wroteLocal = true;
        shard[meal] = NslotLedgerSlot(
          rev: w.rev,
          ua: w.stamp,
          e: {
            for (final e in w.row?.toLocalEntries() ?? const <Map<String, dynamic>>[])
              e['entry_id'] as String: nslotSignature(e),
          },
        );
      }
      if (!await _writeLedgerShards({date: shard})) {
        return (confirmed: false, issued: issued);
      }
    }
    return (confirmed: false, issued: issued);
  }

  // ---------------------------------------------------------------- pull

  /// §4.9 steady pull (the caller runs [rebaseline] instead when not
  /// re-baselined). A page failure applies nothing and keeps both cursors.
  Future<NslotPullOutcome> pull() async {
    final out = NslotPullOutcome();
    if (await stampLocked()) out.wroteLocal = true;
    if (stale()) return out;
    final cursor = readCursor();
    final rowsCur = cursor['rows'] is Map ? cursor['rows'] as Map : const {};
    final tombsCur = cursor['tombs'] is Map ? cursor['tombs'] as Map : const {};
    final budget = Stopwatch()..start();

    final rows = <Map<String, dynamic>>[];
    final tombs = <Map<String, dynamic>>[];
    NslotRowKey? lastRow;
    NslotTombKey? lastTomb;
    try {
      // Rows.
      final since = overlapStart(rowsCur['ts'] as String?);
      final curTs = rowsCur['ts'] as String?;
      var pastOverlap = curTs == null;
      NslotRowKey? after;
      while (true) {
        if (stale()) return out;
        final page = await remote
            .rowsPage(since: after == null ? since : null, after: after)
            .timeout(kNslotPageTimeout);
        rows.addAll(page);
        if (page.isNotEmpty) {
          final last = page.last;
          after = NslotRowKey(
              (last['updated_at'] ?? '').toString(), (last['id'] ?? '').toString());
          lastRow = after;
          if (curTs != null && after.updatedAt.compareTo(curTs) > 0) {
            pastOverlap = true;
          }
        }
        if (page.length < kNslotPageSize) break;
        if (pastOverlap && budget.elapsed > kNslotPullBudget) break;
      }
      // Tombstones.
      final tSince = overlapStart(tombsCur['ts'] as String?);
      final tCurTs = tombsCur['ts'] as String?;
      var tPast = tCurTs == null;
      NslotTombKey? tAfter;
      while (true) {
        if (stale()) return out;
        final page = await remote
            .tombsPage(since: tAfter == null ? tSince : null, after: tAfter)
            .timeout(kNslotPageTimeout);
        tombs.addAll(page);
        if (page.isNotEmpty) {
          final last = page.last;
          tAfter = NslotTombKey(
            (last['deleted_at'] ?? '').toString(),
            (last['date'] ?? '').toString(),
            (last['meal_type'] ?? '').toString(),
          );
          lastTomb = tAfter;
          if (tCurTs != null && tAfter.deletedAt.compareTo(tCurTs) > 0) {
            tPast = true;
          }
        }
        if (page.length < kNslotPageSize) break;
        if (tPast && budget.elapsed > kNslotPullBudget) break;
      }
    } catch (e) {
      if (e is NslotRpcMissing) return out;
      out.failed = true;
      reportFailure('pull_nutrition_slots', e);
      return out;
    }

    final winners = winnersOf(rows, tombs);
    final r = await _applyWinners(winners, out: out, where: 'pull');
    if (r == null) return out; // legacy-seen stop or stale
    if (stale()) return out;
    // Advance each cursor ONCE, to the last fully read position.
    final next = Map<String, dynamic>.from(cursor);
    if (lastRow != null) {
      next['rows'] = {'ts': lastRow.updatedAt, 'row': lastRow.id};
    }
    if (lastTomb != null) {
      next['tombs'] = {
        'ts': lastTomb.deletedAt,
        'd': lastTomb.date,
        'm': lastTomb.mealType,
      };
    }
    if (lastRow != null || lastTomb != null) {
      if (stale()) return out;
      await box.put(kNslotCursorKey, next);
    }
    return out;
  }

  /// One winner per slot over EVERYTHING read (largest rev; a row beats a
  /// tombstone of the same rev, which cannot happen under the revision rule).
  /// Admission (§4.11) first: a bad meal type is skipped with LOW.
  Map<String, NslotWinner> winnersOf(
      List<Map<String, dynamic>> rows, List<Map<String, dynamic>> tombs) {
    final out = <String, NslotWinner>{};
    var bad = 0;
    void offer(NslotWinner w) {
      final k = '${w.date}|${w.mealType}';
      final prev = out[k];
      if (prev == null || w.rev > prev.rev) out[k] = w;
    }

    for (final raw in rows) {
      final r = NslotCloudRow.fromJson(raw);
      if (r == null) continue;
      if (!nslotAdmitMealType(r.mealType)) {
        bad++;
        continue;
      }
      offer(NslotWinner.row(r));
    }
    for (final raw in tombs) {
      final t = NslotTomb.fromJson(raw);
      if (t == null) continue;
      if (!nslotAdmitMealType(t.mealType)) {
        bad++;
        continue;
      }
      offer(NslotWinner.tomb(t));
    }
    if (bad > 0) logLow('nslot_bad_meal_type', 'count=$bad');
    return out;
  }

  /// Shared by the pull and the steady restore: stale-skip, legacy-seen
  /// stop, apply per date, ledger := winner. Returns null on a stop.
  Future<bool?> _applyWinners(Map<String, NslotWinner> winners,
      {NslotPullOutcome? out,
      NslotRestoreOutcome? restoreOut,
      required String where}) async {
    final byDate = <String, Map<String, NslotWinner>>{};
    final ledgers = <String, Map<String, NslotLedgerSlot>>{};
    for (final w in winners.values) {
      final ledger = (ledgers[w.date] ??= readLedger(w.date))[w.mealType];
      if (ledger != null && w.rev <= ledger.rev) continue; // stale (first)
      if (isLegacySeen(w, ledger)) {
        await _markLegacySeen(where);
        out?.legacySeen = true;
        restoreOut?.legacySeen = true;
        return null;
      }
      (byDate[w.date] ??= {})[w.mealType] = w;
    }
    final shards = <String, Map<String, NslotLedgerSlot>>{};
    for (final d in byDate.keys.toList()..sort()) {
      if (stale()) return null;
      final ws = byDate[d]!;
      final shard = ledgers[d] ??= readLedger(d);
      final res = await applyLocked(d, ws, {
        for (final m in ws.keys) m: shard[m]?.e ?? const <String, String>{},
      });
      if (res.wrote) {
        out?.wroteLocal = true;
        restoreOut?.wroteLocal = true;
      }
      if (res.dirty.isNotEmpty) out?.dirty = true;
      final next = Map<String, NslotLedgerSlot>.from(shard);
      for (final e in ws.entries) {
        final w = e.value;
        next[e.key] = NslotLedgerSlot(
          rev: w.rev,
          ua: w.stamp,
          e: {
            for (final x in w.row?.toLocalEntries() ?? const <Map<String, dynamic>>[])
              x['entry_id'] as String: nslotSignature(x),
          },
        );
      }
      shards[d] = next;
      ledgers[d] = next;
    }
    if (!await _writeLedgerShards(shards)) return null;
    return true;
  }

  // ------------------------------------------------------- steady restore

  /// §4.12 steady restore: apply the rows read with the ledger as base;
  /// never treat an absent slot as deleted; never move a cursor.
  Future<NslotRestoreOutcome> restoreSteady(
      List<Map<String, dynamic>> rows) async {
    final out = NslotRestoreOutcome();
    if (await stampLocked()) out.wroteLocal = true;
    if (stale()) return out;
    await _applyWinners(winnersOf(rows, const []),
        restoreOut: out, where: 'restore');
    return out;
  }

  // ----------------------------------------------------------- re-baseline

  /// §4.11. [cache] keeps pages read by a failed attempt (per user, owned by
  /// the section). Returns true when it committed.
  Future<bool> rebaseline(NslotRebaselineCache cache) async {
    if (stale()) return false;
    final meta = readMeta();
    final full = meta['full'] as String?;
    final inflight = <String, String>{
      if (meta['inflight_sigs'] is Map)
        for (final e in (meta['inflight_sigs'] as Map).entries)
          e.key.toString(): e.value.toString(),
    };

    // 1. Snapshot (synchronous).
    final s0 = <String, Map<dynamic, dynamic>>{};
    for (final k in box.keys) {
      final v = box.get(k);
      final isNlog = nslotIsMealRow(k, v);
      final isUuid = nslotIsUuidMealRow(k, v);
      if (!isNlog && !isUuid) continue;
      final m = v as Map;
      final id = m['entry_id'];
      final hasId = id is String && id.isNotEmpty;
      final inflightEqual =
          hasId && inflight[id] != null && inflight[id] == nslotSignature(m);
      if (full != null || !hasId || isUuid || inflightEqual) {
        s0[k as String] = m;
      }
    }
    if (meta['inflight_since'] != null) {
      logLow('nslot_rebaseline_resumed', 'full=${full ?? 'none'}');
    }
    meta['inflight_since'] = _clock().toUtc().toIso8601String();
    if (!await writeMeta(meta)) return false;

    // 2. Read (pages kept across a failed attempt).
    try {
      cache.t0 ??= await remote.serverNow().timeout(kNslotRpcTimeout);
      while (!cache.rowsDone) {
        if (stale()) return false;
        final page = await remote
            .rowsPage(after: cache.lastRow)
            .timeout(kNslotPageTimeout);
        cache.rows.addAll(page);
        if (page.isNotEmpty) {
          cache.lastRow = NslotRowKey((page.last['updated_at'] ?? '').toString(),
              (page.last['id'] ?? '').toString());
        }
        if (page.length < kNslotPageSize) cache.rowsDone = true;
      }
      // Tombstones are always read in the attempt that finishes.
      cache.tombs.clear();
      NslotTombKey? tAfter;
      while (true) {
        if (stale()) return false;
        final page =
            await remote.tombsPage(after: tAfter).timeout(kNslotPageTimeout);
        cache.tombs.addAll(page);
        if (page.isNotEmpty) {
          final l = page.last;
          tAfter = NslotTombKey((l['deleted_at'] ?? '').toString(),
              (l['date'] ?? '').toString(), (l['meal_type'] ?? '').toString());
        }
        if (page.length < kNslotPageSize) break;
      }
    } catch (e) {
      if (e is NslotRpcMissing) return false;
      reportFailure('rebaseline_nutrition', e);
      return false;
    }
    if (stale()) return false;
    final winners = winnersOf(cache.rows, cache.tombs);

    // 3. Rebuild — ONE synchronous run to the start of both writes.
    for (final e in s0.entries) {
      final now = box.get(e.key);
      if (!identical(now, e.value)) {
        logLow('nslot_rebaseline_stopped', 'reason=s0_changed');
        return false;
      }
    }
    if (full == null) {
      for (final k in box.keys) {
        final v = box.get(k);
        if (nslotIsMealRow(k, v) &&
            (v as Map)['entry_id'] == null &&
            !s0.containsKey(k)) {
          logLow('nslot_rebaseline_stopped', 'reason=new_idless_row');
          return false;
        }
      }
    }
    final cloudIds = <String>{};
    for (final w in winners.values) {
      for (final x in w.row?.toLocalEntries() ?? const <Map<String, dynamic>>[]) {
        cloudIds.add(x['entry_id'] as String);
      }
    }
    final ledgerIds = <String>{
      for (final l in readAllLedgers().values)
        for (final s in l.values) ...s.e.keys,
    };
    // R and the rows of S0 kept as they are.
    final rKeys = <String>{};
    final keptAsIs = <String>{};
    for (final e in s0.entries) {
      final m = e.value;
      final id = m['entry_id'];
      final hasId = id is String && id.isNotEmpty;
      if (hasId && inflight[id] != null && inflight[id] != nslotSignature(m)) {
        keptAsIs.add(e.key); // a user edit of an interrupted run's output
        continue;
      }
      if (full == 'legacy_seen' &&
          hasId &&
          nslotIsMealRow(e.key, m) &&
          !ledgerIds.contains(id) &&
          !cloudIds.contains(id) &&
          !(inflight[id] != null)) {
        keptAsIs.add(e.key); // never pushed: cannot be inside any cloud row
        continue;
      }
      rKeys.add(e.key);
    }

    String slotOf(Map<dynamic, dynamic> m) => '${m['date']}|${m['meal_type']}';
    final rBySlot = <String, List<String>>{};
    for (final k in rKeys) {
      (rBySlot[slotOf(s0[k]!)] ??= []).add(k);
    }

    // Holders of ids among rows NOT in R (by date → id → meal).
    final holders = <String, Map<String, String>>{};
    for (final k in box.keys) {
      if (rKeys.contains(k)) continue;
      final v = box.get(k);
      if (!nslotIsMealRow(k, v)) continue;
      final m = v as Map;
      final id = m['entry_id'];
      if (id is! String) continue;
      (holders[(m['date'] ?? '').toString()] ??= {})[id] =
          (m['meal_type'] ?? '').toString();
    }

    final removeKeys = <String>{};
    final puts = <String, Map<String, dynamic>>{};
    final keptKeys = <String>{...keptAsIs};
    final candidates = <({String date, String meal, Map<String, dynamic> row})>[];
    final kRows = <String, Map<String, dynamic>>{}; // stamped / re-keyed

    final allSlots = {...rBySlot.keys, ...winners.keys};
    for (final slot in allSlots) {
      final w = winners[slot];
      final rs = rBySlot[slot] ?? const <String>[];
      if (w != null) {
        removeKeys.addAll(rs);
        final row = w.row;
        if (row == null) continue;
        for (final x in row.toLocalEntries()) {
          final id = x['entry_id'] as String;
          final heldIn = holders[row.date]?[id];
          if (heldIn != null) continue; // same slot: left as it is; other: the push sends the move
          candidates.add((date: row.date, meal: row.mealType, row: x));
        }
      } else {
        for (final k in rs) {
          final m = Map<String, dynamic>.from(s0[k]!);
          final id = m['entry_id'];
          if (nslotIsUuidMealRow(k, m)) {
            m['entry_id'] = _newId();
            removeKeys.add(k);
            kRows['rekey:$k'] = m; // re-keyed below
          } else {
            if (id is! String || id.isEmpty) m['entry_id'] = _newId();
            kRows[k] = m;
          }
        }
      }
    }

    // Day pass over the cloud candidates and the kept rows together.
    final dayCopies = <String, List<NslotDayCopy>>{};
    final candKey = <String, int>{};
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final pseudo = 'cand:$i';
      candKey[pseudo] = i;
      (dayCopies[c.date] ??= []).add(NslotDayCopy(
        view: NslotEntryView(
          id: c.row['entry_id'] as String,
          signature: nslotSignature(c.row),
          loggedAt: nslotNormLoggedAt(c.row['logged_at']),
        ),
        mealType: c.meal,
        key: pseudo,
      ));
    }
    for (final e in kRows.entries) {
      final m = e.value;
      (dayCopies[(m['date'] ?? '').toString()] ??= []).add(NslotDayCopy(
        view: NslotEntryView(
          id: m['entry_id'] as String,
          signature: nslotSignature(m),
          loggedAt: nslotNormLoggedAt(m['logged_at']),
        ),
        mealType: (m['meal_type'] ?? '').toString(),
        key: e.key,
      ));
    }
    final dropCand = <int>{};
    for (final copies in dayCopies.values) {
      for (final loser in nslotDayPass(copies)) {
        final ci = candKey[loser];
        if (ci != null) {
          dropCand.add(ci);
        } else {
          final m = kRows.remove(loser);
          if (m != null && !loser.startsWith('rekey:')) removeKeys.add(loser);
        }
      }
    }

    // Placement of the kept rows first (their keys are fixed or re-keyed).
    bool taken(String k) =>
        puts.containsKey(k) ||
        keptKeys.contains(k) ||
        (box.containsKey(k) && !removeKeys.contains(k));
    final now = _clock().toUtc().toIso8601String();
    for (final e in kRows.entries) {
      final m = e.value;
      m['created_at'] ??= m['logged_at'] ?? now;
      m['logged_at'] ??= m['created_at'];
      if (e.key.startsWith('rekey:')) {
        final base = NutritionWriteService.logKeyForMaps(
            (m['date'] ?? '').toString(),
            (m['meal_type'] ?? '').toString(),
            (m['items'] as List?) ?? const []);
        final key = NutritionWriteService.firstFreeLogKey(taken, base);
        m['id'] = key;
        m['log_key'] = key;
        puts[key] = m;
        keptKeys.add(key);
      } else {
        puts[e.key] = m;
        keptKeys.add(e.key);
      }
    }
    final inflightOut = <String, String>{};
    for (var i = 0; i < candidates.length; i++) {
      if (dropCand.contains(i)) continue;
      final c = candidates[i];
      final key = nslotPlaceKey(
        date: c.date,
        meal: c.meal,
        entryId: c.row['entry_id'] as String,
        cloudKey: (c.row['_k'] as String?) ??
            NutritionWriteService.logKeyForMaps(
                c.date, c.meal, (c.row['items'] as List?) ?? const []),
        sameSlotKey: null,
        taken: taken,
      );
      final row = Map<String, dynamic>.from(c.row)
        ..remove('_k')
        ..['id'] = key
        ..['log_key'] = key;
      NutritionWriteService.clampRestoredNutritionRow(row);
      puts[key] = row;
      inflightOut[row['entry_id'] as String] = nslotSignature(row);
    }
    final placedKeys = puts.keys.toSet();
    removeKeys.removeAll(placedKeys);

    if (stale()) return false;
    final metaOut = Map<String, dynamic>.from(meta)
      ..['inflight_sigs'] = inflightOut;
    clearUndoStash();
    final w1 = box.putAll({...puts, kNslotMetaKey: metaOut});
    final w2 = removeKeys.isEmpty ? Future<void>.value() : box.deleteAll(removeKeys);
    // ---- end of the synchronous run ----
    await Future.wait([w1, w2]);
    invalidate();

    // 4. Commit.
    if (stale()) return false;
    for (final k in s0.keys) {
      if (box.containsKey(k) && !placedKeys.contains(k) && !keptKeys.contains(k)) {
        logLow('nslot_rebaseline_not_committed', 'reason=s0_key_back');
        return false;
      }
    }
    for (final k in box.keys) {
      final v = box.get(k);
      if (nslotIsMealRow(k, v) && (v as Map)['entry_id'] == null) {
        logLow('nslot_rebaseline_not_committed', 'reason=idless_row');
        return false;
      }
    }
    // (i) the WHOLE ledger and the cursors.
    final shards = <String, Map<String, dynamic>>{};
    for (final w in winners.values) {
      (shards['$kNslotLedgerPrefix${w.date}'] ??= {})[w.mealType] =
          NslotLedgerSlot(
        rev: w.rev,
        ua: w.stamp,
        e: {
          for (final x in w.row?.toLocalEntries() ?? const <Map<String, dynamic>>[])
            x['entry_id'] as String: nslotSignature(x),
        },
      ).toJson();
    }
    final oldShards = [
      for (final k in box.keys)
        if (k is String &&
            k.startsWith(kNslotLedgerPrefix) &&
            !shards.containsKey(k))
          k,
    ];
    final start = overlapStart(cache.t0);
    if (stale()) return false;
    await Future.wait([
      box.putAll({
        ...shards,
        kNslotCursorKey: {
          'rows': {'ts': start, 'row': null},
          'tombs': {'ts': start, 'd': null, 'm': null},
        },
      }),
      if (oldShards.isNotEmpty) box.deleteAll(oldShards),
    ]);
    // (ii) THEN the meta alone.
    if (stale()) return false;
    await box.put(kNslotMetaKey, {'rebaselined': true});
    cache.reset();
    return true;
  }
}

/// Pages a re-baseline already read, kept per user across a failed attempt
/// (§4.11 step 2). Owned by the section; reset on commit and on user change.
class NslotRebaselineCache {
  String? t0;
  final List<Map<String, dynamic>> rows = [];
  NslotRowKey? lastRow;
  bool rowsDone = false;
  final List<Map<String, dynamic>> tombs = [];

  void reset() {
    t0 = null;
    rows.clear();
    lastRow = null;
    rowsDone = false;
    tombs.clear();
  }
}
