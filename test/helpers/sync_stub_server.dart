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

/// A canned answer for a table's GETs (status + body). A String body is sent
/// verbatim (a Cloudflare-style plain-text 521); anything else is JSON-encoded.
class StubReadReply {
  const StubReadReply(this.status, this.body);
  final int status;
  final Object? body;
}

/// Filtering is NOT applied here: a GET answers whatever its table's
/// `getResponders` closure returns, whatever the `select=` / `eq.` query.
/// A test whose assertion depends on filtering must filter inside its
/// responder (it gets the full `StubRequest`, `query` included), or it
/// passes vacuously (plan-review round 2, slice A F2).
class SyncStubServer {
  HttpServer? _server;
  final List<StubRequest> requests = [];

  /// Day-swapper + sync-load Task 17 (diagnose a9d3f6). Set the instant
  /// [stop] is called, BEFORE the actual close -- narrows the dropped-
  /// connection catch in [_handle] to genuinely in-progress shutdowns only,
  /// so it can never mask a real client/network fault during ordinary test
  /// execution (only during the deliberate window this class itself opens).
  bool _stopping = false;

  /// Writes to these tables answer 500, so a push throws PostgrestException.
  final Set<String> failWritesTo = {};

  /// Optional per-table 500 body for [failWritesTo] -- lets a test make the
  /// failure carry a real Postgres `details` shape (e.g. `Failing row
  /// contains (...)`) instead of the fixed `stub failure` body. Hermes h6F2.
  final Map<String, Map<String, Object?>> failBodies = {};

  /// Per-table CONDITIONAL write failure: return a Postgres error body to
  /// fail this request with 409, or null to let it succeed. Checked before
  /// [failWritesTo]. Lets a test model state the cloud holds, e.g. a
  /// 23503 FK violation until the parent row is written again.
  final Map<String, Map<String, Object?>? Function(StubRequest)> writeFailers =
      {};

  /// GET responders per table; a table without one answers `[]`.
  final Map<String, Object? Function(StubRequest)> getResponders = {};

  /// A table listed here answers EVERY GET with the given status + body (an
  /// outage / auth-rejection simulation). Checked before [getResponders]. Note
  /// the SDK retries a GET answered 503/520 three more times unless the query
  /// opts out — use 500/504 for a "one failing request" assertion.
  final Map<String, StubReadReply> readReplies = {};

  Future<void> start() async {
    HttpOverrides.global = null;
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen(_handle);
  }

  String get url => 'http://127.0.0.1:${_server!.port}';

  SupabaseClient client() => SupabaseClient(url, 'stub-anon-key');

  Future<void> stop() async {
    _stopping = true;
    try {
      await _server?.close(force: true);
    } catch (_) {
      // Teardown must never throw (CLAUDE.md §4.9) — a failing close here
      // must not stop the harness's other cleanup steps from running.
    } finally {
      _server = null;
    }
  }

  void clear() => requests.clear();

  List<StubRequest> writesTo(String table) =>
      requests.where((r) => r.isWrite && r.table == table).toList();

  Future<void> _handle(HttpRequest req) async {
    String raw;
    try {
      raw = await utf8.decoder.bind(req).join();
    } on HttpException {
      // Day-swapper + sync-load Task 17 (diagnose a9d3f6) -- an unawaited
      // caller (e.g. SyncService._reportSyncFailure's fire-and-forget
      // log-client-error POST) can still be in flight when the OWNING
      // test's tearDown calls stop() with force:true, which destroys this
      // connection mid-read. That is a legitimate outcome of a
      // fire-and-forget call outliving its test, not a bug in the request
      // itself -- silently drop it rather than let an unhandled exception
      // surface (attributed to whichever test happens to be running next)
      // and crash the suite. Never recorded in `requests`.
      // Gated on `_stopping` so this can NEVER swallow a genuine connection
      // fault during ordinary (non-shutdown) test execution -- narrowed
      // after a full-suite run showed a DIFFERENT test's dual-post count
      // assertion (`sync_nutrition_log_payload_hash_index_writer_to_reader_
      // test.dart`) drop from 2 to 1 under contention; that turned out to be
      // a pre-existing timing flake unrelated to this catch (confirmed
      // green 3/3 in isolation), but the narrowing removes any doubt.
      if (_stopping) return;
      rethrow;
    } on SocketException {
      if (_stopping) return;
      rethrow;
    }
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
    final conditionalFailure =
        r.isWrite ? writeFailers[r.table]?.call(r) : null;
    if (conditionalFailure != null) {
      res
        ..statusCode = 409
        ..write(jsonEncode(conditionalFailure));
    } else if (r.isWrite && failWritesTo.contains(r.table)) {
      res
        ..statusCode = 500
        ..write(jsonEncode(failBodies[r.table] ??
            {'message': 'stub failure', 'code': 'XX000'}));
    } else if (r.method == 'GET' &&
        r.table != null &&
        readReplies.containsKey(r.table)) {
      final reply = readReplies[r.table]!;
      res
        ..statusCode = reply.status
        ..write(reply.body is String ? reply.body : jsonEncode(reply.body));
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
