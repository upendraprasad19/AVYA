// A local stand-in for PostgREST + Edge Functions, for tests that drive the
// real SyncService (day-swapper + sync-load plan D6). Verified 2026-09-26: a
// real SupabaseClient pointed at a local HttpServer records every upsert,
// select, delete, rpc and functions call with its query and body inside
// `flutter test`, provided HttpOverrides.global is cleared (flutter_test
// installs an HttpClient that answers 400 to everything).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StubRequest {
  StubRequest(this.method, this.path, this.query, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;

  /// Decoded JSON body (a Map or a List), the raw string if it is not JSON,
  /// or null when empty.
  final Object? body;

  /// The PostgREST table, or null for rpc / functions / anything else.
  String? get table {
    if (!path.startsWith('/rest/v1/') || path.startsWith('/rest/v1/rpc/')) {
      return null;
    }
    return path.substring('/rest/v1/'.length);
  }

  bool get isWrite => table != null && method != 'GET';

  /// The row maps in a write body (an upsert may send one map or a list).
  List<Map<String, dynamic>> get rows {
    final b = body;
    if (b is Map) return [Map<String, dynamic>.from(b)];
    if (b is List) {
      return [for (final r in b) if (r is Map) Map<String, dynamic>.from(r)];
    }
    return const [];
  }
}

/// Filtering is NOT applied here: a GET answers whatever its table's
/// `getResponders` closure returns, whatever the `select=` / `eq.` query.
/// A test whose assertion depends on filtering must filter inside its
/// responder (it gets the full `StubRequest`, `query` included), or it
/// passes vacuously (plan-review round 2, slice A F2).
class SyncStubServer {
  HttpServer? _server;
  final List<StubRequest> requests = [];

  /// Writes to these tables answer 500, so a push throws PostgrestException.
  final Set<String> failWritesTo = {};

  /// GET responders per table; a table without one answers `[]`.
  final Map<String, Object? Function(StubRequest)> getResponders = {};

  Future<void> start() async {
    HttpOverrides.global = null;
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen(_handle);
  }

  String get url => 'http://127.0.0.1:${_server!.port}';

  SupabaseClient client() => SupabaseClient(url, 'stub-anon-key');

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void clear() => requests.clear();

  List<StubRequest> writesTo(String table) =>
      requests.where((r) => r.isWrite && r.table == table).toList();

  Future<void> _handle(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    Object? body;
    if (raw.isNotEmpty) {
      try {
        body = jsonDecode(raw);
      } catch (_) {
        body = raw;
      }
    }
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k] = v.join(','));
    final r = StubRequest(
        req.method, req.uri.path, req.uri.queryParameters, headers, body);
    requests.add(r);
    final res = req.response..headers.contentType = ContentType.json;
    if (r.isWrite && failWritesTo.contains(r.table)) {
      res
        ..statusCode = 500
        ..write(jsonEncode({'message': 'stub failure', 'code': 'XX000'}));
    } else if (r.method == 'GET' && r.table != null) {
      res
        ..statusCode = 200
        ..write(jsonEncode(getResponders[r.table]?.call(r) ?? const []));
    } else if (r.isWrite) {
      res.statusCode = r.method == 'POST' ? 201 : 204;
    } else {
      res
        ..statusCode = 200
        ..write(r.path.startsWith('/functions/') ? '{}' : 'null');
    }
    await res.close();
  }
}

/// Live columns per table (backups/live_schema_columns.json).
Map<String, Set<String>> loadLiveSchemaColumns() {
  final d = jsonDecode(File('backups/live_schema_columns.json').readAsStringSync())
      as Map<String, dynamic>;
  final tables = d['tables'] as Map<String, dynamic>;
  return {
    for (final e in tables.entries)
      e.key: {for (final c in e.value as List) c as String},
  };
}

/// Every key of every recorded write body is a live column of its table —
/// strictly stronger than check_schema_column_refs.dart, which validates only
/// keys on the `.upsert({` line itself (plan D11).
void expectWritesMatchLiveSchema(SyncStubServer server) {
  final schema = loadLiveSchemaColumns();
  for (final r in server.requests.where((r) => r.isWrite)) {
    final cols = schema[r.table];
    expect(cols, isNotNull,
        reason: '${r.table} is missing from backups/live_schema_columns.json');
    for (final row in r.rows) {
      final unknown = row.keys.where((k) => !cols!.contains(k)).toList();
      expect(unknown, isEmpty,
          reason: '${r.method} ${r.table}: $unknown are not live columns');
    }
  }
}
