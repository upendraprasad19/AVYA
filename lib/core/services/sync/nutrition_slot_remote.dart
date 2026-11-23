// OI-348 Landing 1a-ii — the cloud side of the nutrition slot sync, as one
// small interface (spec docs/plans/nutrition-slot-sync.md §3, §4.3, §4.9).
// `SupabaseNslotRemote` talks to migration 181; tests use the fake in
// `test/sync/nutrition_slot_fake_server.dart`, which implements the same
// contract table.
import 'dart:async';

import 'package:icanbefitter/core/services/sync/nutrition_slot_merge.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

/// §4.9: one page size for every read here, equal to `_fetchAllRows`'s and to
/// the project's `db-max-rows` (1000). A capped page is never a short page.
const int kNslotPageSize = 1000;

/// The RPCs are missing (`PGRST202` / 404 / `42883`): no nutrition sync this
/// pass, never legacy mode (§4.6, R10 P1).
class NslotRpcMissing implements Exception {
  const NslotRpcMissing(this.detail);
  final String detail;
  @override
  String toString() => 'NslotRpcMissing($detail)';
}

/// True for the three "function is not there" answers of §4.6.
bool nslotIsRpcMissing(Object e) {
  if (e is NslotRpcMissing) return true;
  if (e is PostgrestException) {
    final c = e.code ?? '';
    return c == 'PGRST202' || c == '42883' || c == '404';
  }
  return false;
}

/// One cloud row of `nutrition_logs`, as the pull, the re-baseline, a conflict
/// reply and the steady restore read it (`*, nutrition_log_items(*)`).
class NslotCloudRow {
  NslotCloudRow({
    required this.id,
    required this.date,
    required this.mealType,
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
  final String mealType;
  final int rev;
  final int legacyRev;

  /// The server's own text, never round-tripped through `DateTime` (§4.4).
  final String updatedAt;
  final String? createdAt;

  /// `null` = a legacy row (written outside the RPCs: no per-meal split).
  final List<Map<String, dynamic>>? entries;

  /// Sorted by `item_index` (§4.3: the embed has no guaranteed order).
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> totals;

  bool get isLegacy => entries == null;

  /// Parses a PostgREST row. Returns null for a row this client cannot place
  /// (no id, no date, no rev); slot admission (§4.11) is the caller's.
  static NslotCloudRow? fromJson(Map<dynamic, dynamic> m) {
    final id = m['id'];
    final date = m['date'];
    final rev = m['rev'];
    if (id is! String || id.isEmpty || date is! String || rev is! num) {
      return null;
    }
    final rawItems = m['nutrition_log_items'];
    final items = <Map<String, dynamic>>[
      if (rawItems is List)
        for (final i in rawItems)
          if (i is Map) Map<String, dynamic>.from(i),
    ]..sort((a, b) => ((a['item_index'] as num?) ?? 0)
        .compareTo((b['item_index'] as num?) ?? 0));
    final rawEntries = m['entries'];
    return NslotCloudRow(
      id: id,
      date: date.length >= 10 ? date.substring(0, 10) : date,
      mealType: (m['meal_type'] ?? '').toString(),
      rev: rev.toInt(),
      legacyRev: (m['legacy_rev'] as num?)?.toInt() ?? 0,
      updatedAt: (m['updated_at'] ?? '').toString(),
      createdAt: m['created_at'] as String?,
      entries: rawEntries is List
          ? [
              for (final e in rawEntries)
                if (e is Map) Map<String, dynamic>.from(e),
            ]
          : null,
      items: items,
      totals: {
        for (final k in const [
          'total_calories',
          'total_protein',
          'total_carbs',
          'total_fat',
          'total_fiber',
        ])
          k: m[k],
      },
    );
  }

  /// §4.1 / §4.3: the local `nlog_` rows (without key) this cloud row stands
  /// for. A new-format row → one per entry, items grouped by `entry_key` in
  /// `item_index` order; a legacy row → ONE synthetic entry holding the whole
  /// slot (`logged_at` = the row's `created_at`, `source: 'cloud_restore'`).
  List<Map<String, dynamic>> toLocalEntries() {
    final e = entries;
    if (e == null) {
      return [
        {
          'date': date,
          'meal_type': mealType,
          ...totals,
          'items': [for (final i in items) _localItem(i)],
          'source': 'cloud_restore',
          'logged_at': createdAt,
          'created_at': createdAt,
          'entry_id': nslotSyntheticEntryId(id, rev),
          '_k': null,
        },
      ];
    }
    final byEntry = <String, List<Map<String, dynamic>>>{};
    for (final i in items) {
      final k = i['entry_key'];
      if (k is String) (byEntry[k] ??= []).add(_localItem(i));
    }
    final out = <Map<String, dynamic>>[];
    for (final entry in e) {
      final eid = entry['id'];
      if (eid is! String || eid.isEmpty) continue;
      final t = entry['t'] is Map ? entry['t'] as Map : const {};
      out.add({
        'date': date,
        'meal_type': mealType,
        'total_calories': t['calories'],
        'total_protein': t['protein'],
        'total_carbs': t['carbs'],
        'total_fat': t['fat'],
        'total_fiber': t['fiber'],
        'items': byEntry[eid] ?? <Map<String, dynamic>>[],
        'source': entry['src'] ?? 'cloud_restore',
        'logged_at': entry['la'],
        'created_at': entry['ca'],
        'entry_id': eid,
        '_k': entry['k'],
      });
    }
    return out;
  }

  static Map<String, dynamic> _localItem(Map<String, dynamic> i) => {
        'name': (i['food_name'] ?? '').toString(),
        'quantity_g': i['quantity_g'],
        'calories': i['calories'],
        'protein': i['protein'],
        'carbs': i['carbs'],
        'fat': i['fat'],
        'fiber': i['fiber'],
      };
}

/// One tombstone (a deleted slot).
class NslotTomb {
  NslotTomb({
    required this.date,
    required this.mealType,
    required this.rev,
    required this.legacyRev,
    required this.deletedAt,
  });

  final String date;
  final String mealType;
  final int rev;
  final int legacyRev;
  final String deletedAt;

  static NslotTomb? fromJson(Map<dynamic, dynamic> m) {
    final date = m['date'];
    final rev = m['rev'];
    if (date is! String || rev is! num) return null;
    return NslotTomb(
      date: date.length >= 10 ? date.substring(0, 10) : date,
      mealType: (m['meal_type'] ?? '').toString(),
      rev: rev.toInt(),
      legacyRev: (m['legacy_rev'] as num?)?.toInt() ?? 0,
      deletedAt: (m['deleted_at'] ?? '').toString(),
    );
  }
}

/// The newest thing the server holds for one slot: a row or a tombstone.
class NslotWinner {
  NslotWinner.row(NslotCloudRow this.row) : tomb = null;
  NslotWinner.tomb(NslotTomb this.tomb) : row = null;

  final NslotCloudRow? row;
  final NslotTomb? tomb;

  int get rev => row?.rev ?? tomb!.rev;
  String get date => row?.date ?? tomb!.date;
  String get mealType => row?.mealType ?? tomb!.mealType;

  /// The ledger's `ua` for this version (server text).
  String get stamp => row?.updatedAt ?? tomb!.deletedAt;
}

/// The answer of a put or a delete.
class NslotWriteResult {
  NslotWriteResult.ok({required this.rev, required this.stamp})
      : ok = true,
        winner = null;
  NslotWriteResult.conflict({required this.rev, required this.winner})
      : ok = false,
        stamp = null;

  final bool ok;
  final int rev;

  /// ok: the server text of `updated_at` (put) or `deleted_at` (delete).
  final String? stamp;

  /// conflict: what the slot holds now (null = nothing at all).
  final NslotWinner? winner;

  /// Parses an RPC reply (§3.5, §3.6).
  static NslotWriteResult fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('nslot: rpc reply is not an object');
    }
    final status = raw['status'];
    final rev = (raw['rev'] as num?)?.toInt() ?? 0;
    if (status == 'ok') {
      return NslotWriteResult.ok(
        rev: rev,
        stamp: (raw['updated_at'] ?? raw['deleted_at'])?.toString(),
      );
    }
    if (status == 'conflict') {
      NslotWinner? w;
      final row = raw['row'];
      final tomb = raw['tombstone'];
      if (row is Map) {
        final r = NslotCloudRow.fromJson(row);
        if (r != null) w = NslotWinner.row(r);
      } else if (tomb is Map) {
        final t = NslotTomb.fromJson(tomb);
        if (t != null) w = NslotWinner.tomb(t);
      }
      return NslotWriteResult.conflict(rev: rev, winner: w);
    }
    throw FormatException('nslot: unknown rpc status $status');
  }
}

/// Keyset position in the row stream `(updated_at, id)`.
class NslotRowKey {
  const NslotRowKey(this.updatedAt, this.id);
  final String updatedAt;
  final String id;
}

/// Keyset position in the tombstone stream `(deleted_at, date, meal_type)`.
class NslotTombKey {
  const NslotTombKey(this.deletedAt, this.date, this.mealType);
  final String deletedAt;
  final String date;
  final String mealType;
}

abstract class NslotRemote {
  /// `nutrition_server_now()` as the server's text. Throws [NslotRpcMissing]
  /// (or a `PostgrestException` [nslotIsRpcMissing] accepts) when absent.
  Future<String> serverNow();

  Future<NslotWriteResult> put({
    required String date,
    required String mealType,
    required int baseRev,
    required Map<String, dynamic> totals,
    required List<Map<String, dynamic>> entries,
    required List<Map<String, dynamic>> items,
  });

  Future<NslotWriteResult> delete({
    required String date,
    required String mealType,
    required int baseRev,
  });

  /// Rows ordered by `(updated_at, id)` ascending. With [after]: strictly
  /// after that position. Else with [since]: `updated_at >= since`. Else all.
  Future<List<Map<String, dynamic>>> rowsPage({
    String? since,
    NslotRowKey? after,
    int limit = kNslotPageSize,
  });

  /// Tombstones ordered by `(deleted_at, date, meal_type)` ascending; same
  /// [since] / [after] rule as [rowsPage].
  Future<List<Map<String, dynamic>>> tombsPage({
    String? since,
    NslotTombKey? after,
    int limit = kNslotPageSize,
  });
}

/// PostgREST quoting for a value inside an `or=(...)` filter.
String nslotQuote(String v) => '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

class SupabaseNslotRemote implements NslotRemote {
  SupabaseNslotRemote(this._client, this._userId);

  final SupabaseClient _client;
  final String _userId;

  Never _rethrow(Object e, StackTrace st) {
    if (nslotIsRpcMissing(e)) throw NslotRpcMissing(e.toString());
    Error.throwWithStackTrace(e, st);
  }

  @override
  Future<String> serverNow() async {
    try {
      final r = await _client.rpc('nutrition_server_now');
      return r.toString();
    } catch (e, st) {
      _rethrow(e, st);
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
    try {
      final r = await _client.rpc('nutrition_slot_put', params: {
        'p_date': date,
        'p_meal_type': mealType,
        'p_base_rev': baseRev,
        'p_totals': totals,
        'p_entries': entries,
        'p_items': items,
      });
      return NslotWriteResult.fromJson(r);
    } catch (e, st) {
      _rethrow(e, st);
    }
  }

  @override
  Future<NslotWriteResult> delete({
    required String date,
    required String mealType,
    required int baseRev,
  }) async {
    try {
      final r = await _client.rpc('nutrition_slot_delete', params: {
        'p_date': date,
        'p_meal_type': mealType,
        'p_base_rev': baseRev,
      });
      return NslotWriteResult.fromJson(r);
    } catch (e, st) {
      _rethrow(e, st);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> rowsPage({
    String? since,
    NslotRowKey? after,
    int limit = kNslotPageSize,
  }) async {
    var q = _client
        .from('nutrition_logs')
        .select('*, nutrition_log_items(*)')
        .eq('user_id', _userId);
    if (after != null) {
      final ts = nslotQuote(after.updatedAt);
      q = q.or('updated_at.gt.$ts,'
          'and(updated_at.eq.$ts,id.gt.${nslotQuote(after.id)})');
    } else if (since != null) {
      q = q.gte('updated_at', since);
    }
    final page = await q
        .order('updated_at', ascending: true)
        .order('id', ascending: true)
        .limit(limit);
    return [for (final r in page) Map<String, dynamic>.from(r as Map)];
  }

  @override
  Future<List<Map<String, dynamic>>> tombsPage({
    String? since,
    NslotTombKey? after,
    int limit = kNslotPageSize,
  }) async {
    var q = _client
        .from('nutrition_slot_tombstones')
        .select()
        .eq('user_id', _userId);
    if (after != null) {
      final ts = nslotQuote(after.deletedAt);
      final d = nslotQuote(after.date);
      final m = nslotQuote(after.mealType);
      q = q.or('deleted_at.gt.$ts,'
          'and(deleted_at.eq.$ts,date.gt.$d),'
          'and(deleted_at.eq.$ts,date.eq.$d,meal_type.gt.$m)');
    } else if (since != null) {
      q = q.gte('deleted_at', since);
    }
    final page = await q
        .order('deleted_at', ascending: true)
        .order('date', ascending: true)
        .order('meal_type', ascending: true)
        .limit(limit);
    return [for (final r in page) Map<String, dynamic>.from(r as Map)];
  }
}
