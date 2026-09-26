// scripts/check_onconflict_live_arbiter.dart
//
// 2026-05-15 — Runs `test/sql/onconflict_live_arbiter.sql` against the
// live Supabase Postgres (project `dedsavbjuwgarrhphgnl`) via the
// Management API and parses the returned `_v_results` rows.
//
// Why this script exists
// ----------------------
// Source-grep tests can confirm the client writer string says
// `onConflict: 'a,b,c'`, but cannot confirm Postgres has a UNIQUE /
// EXCLUDE constraint the arbiter resolver will accept. This script
// closes that gap by exercising every onConflict pair the sync layer
// uses against the real schema. See `test/sql/onconflict_live_arbiter.sql`
// for the inventory + expected outcomes.
//
// closes-diagnose: 25e91d
//
// Exit codes
//   0 — every row in _v_results has status='ok'
//   1 — at least one row has status='fail' (label / sqlstate / msg printed)
//   2 — usage error / missing token / network error
//
// Auth
//   The script resolves the Supabase Management API personal access
//   token in this order:
//     1. `--token <value>` CLI flag
//     2. `--token-file <path>` CLI flag
//     3. `SUPABASE_ACCESS_TOKEN_FITNESS` env var (preferred)
//     4. Default file: `supabase/.supabase/supabase access token.txt`
//        (gitignored, present in repo since 2026-04-20)
//     5. `SUPABASE_ACCESS_TOKEN` env var (fallback; may be wrong account)
//
// API call
//   POST https://api.supabase.com/v1/projects/{ref}/database/query
//     Authorization: Bearer <PAT>
//     Content-Type:  application/json
//     Body:          { "query": "<contents of .sql file>" }
//
// The Management API returns the result of the FINAL SELECT in the SQL
// payload as a JSON array of row objects. We parse that and decide.
//
// Usage
//   dart run scripts/check_onconflict_live_arbiter.dart \
//       [--project <ref>] [--token <pat>] [--token-file <path>] \
//       [--sql <path>] [--verbose]
//
//   Defaults:
//     --project   dedsavbjuwgarrhphgnl
//     --sql       test/sql/onconflict_live_arbiter.sql

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultProjectRef = 'dedsavbjuwgarrhphgnl';
const _defaultSqlPath = 'test/sql/onconflict_live_arbiter.sql';
const _managementApiBase = 'https://api.supabase.com';

void _usage() {
  stderr.writeln('Usage:');
  stderr.writeln(
      '  dart run scripts/check_onconflict_live_arbiter.dart [flags]');
  stderr.writeln('');
  stderr.writeln('Flags:');
  stderr.writeln('  --project <ref>      Supabase project ref '
      '(default: $_defaultProjectRef)');
  stderr.writeln('  --token <pat>        Management API PAT');
  stderr.writeln('  --token-file <path>  Read PAT from file');
  stderr.writeln('  --sql <path>         SQL file to execute '
      '(default: $_defaultSqlPath)');
  stderr.writeln('  --verbose            Print every result row, not just fails');
}

class _Args {
  String projectRef = _defaultProjectRef;
  String? tokenCli;
  String? tokenFile;
  String sqlPath = _defaultSqlPath;
  bool verbose = false;
}

_Args _parseArgs(List<String> argv) {
  final args = _Args();
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    switch (a) {
      case '--project':
        args.projectRef = argv[++i];
        break;
      case '--token':
        args.tokenCli = argv[++i];
        break;
      case '--token-file':
        args.tokenFile = argv[++i];
        break;
      case '--sql':
        args.sqlPath = argv[++i];
        break;
      case '--verbose':
        args.verbose = true;
        break;
      case '-h':
      case '--help':
        _usage();
        exit(0);
      default:
        stderr.writeln('Unknown flag: $a');
        _usage();
        exit(2);
    }
  }
  return args;
}

String? _resolveToken(_Args args) {
  if (args.tokenCli != null && args.tokenCli!.trim().isNotEmpty) {
    return args.tokenCli!.trim();
  }
  if (args.tokenFile != null) {
    final f = File(args.tokenFile!);
    if (!f.existsSync()) {
      stderr.writeln('Token file not found: ${args.tokenFile}');
      return null;
    }
    return f.readAsStringSync().trim();
  }
  final envFitness = Platform.environment['SUPABASE_ACCESS_TOKEN_FITNESS'];
  if (envFitness != null && envFitness.trim().isNotEmpty) {
    return envFitness.trim();
  }
  // Default repo file — gitignored via supabase/.gitignore.
  final defaultFile = File('supabase/.supabase/supabase access token.txt');
  if (defaultFile.existsSync()) {
    return defaultFile.readAsStringSync().trim();
  }
  final envFallback = Platform.environment['SUPABASE_ACCESS_TOKEN'];
  if (envFallback != null && envFallback.trim().isNotEmpty) {
    stderr.writeln('[warn] using SUPABASE_ACCESS_TOKEN env (fallback) — '
        'verify it belongs to the fitness-app account');
    return envFallback.trim();
  }
  return null;
}

Future<List<Map<String, dynamic>>> _runQuery({
  required String projectRef,
  required String token,
  required String sql,
}) async {
  final uri =
      Uri.parse('$_managementApiBase/v1/projects/$projectRef/database/query');
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Accept', 'application/json');
    req.add(utf8.encode(jsonEncode({'query': sql})));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'Management API HTTP ${res.statusCode} — ${body.length > 600 ? "${body.substring(0, 600)}…" : body}',
      );
    }
    final decoded = jsonDecode(body);
    // The /database/query endpoint returns the rows of the LAST resultset
    // as a JSON array. Multiple statements are concatenated; the SELECT
    // at the end of the SQL file is what we parse.
    if (decoded is List) {
      return decoded
          .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    // Some Management API versions wrap the result. Best-effort unwrap.
    if (decoded is Map && decoded['result'] is List) {
      return (decoded['result'] as List)
          .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    throw Exception(
      'Unexpected response shape: ${body.length > 400 ? "${body.substring(0, 400)}…" : body}',
    );
  } finally {
    client.close(force: true);
  }
}

Future<int> _main(List<String> argv) async {
  final args = _parseArgs(argv);

  final sqlFile = File(args.sqlPath);
  if (!sqlFile.existsSync()) {
    stderr.writeln('SQL file not found: ${args.sqlPath}');
    return 2;
  }
  final sql = sqlFile.readAsStringSync();

  final token = _resolveToken(args);
  if (token == null || token.isEmpty) {
    stderr.writeln('No Supabase Management API token resolved.');
    stderr.writeln('Provide one via --token, --token-file, '
        'SUPABASE_ACCESS_TOKEN_FITNESS, or '
        'supabase/.supabase/supabase access token.txt');
    return 2;
  }

  stdout.writeln('[arbiter] project=${args.projectRef} sql=${args.sqlPath}');
  stdout.writeln('[arbiter] token source resolved (${token.length} bytes)');

  List<Map<String, dynamic>> rows;
  try {
    rows = await _runQuery(
      projectRef: args.projectRef,
      token: token,
      sql: sql,
    );
  } catch (e) {
    stderr.writeln('[arbiter] FATAL — query failed: $e');
    return 2;
  }

  if (rows.isEmpty) {
    stderr.writeln('[arbiter] FATAL — empty resultset; '
        'the SQL did not emit _v_results rows');
    return 2;
  }

  final fails = rows.where((r) => r['status'] != 'ok').toList();

  if (args.verbose || fails.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Results (${rows.length} pairs):');
    stdout.writeln('  ${'LABEL'.padRight(64)}  STATUS  SQLSTATE  MSG');
    for (final r in rows) {
      final label = (r['label'] ?? '').toString().padRight(64);
      final status = (r['status'] ?? '').toString().padRight(6);
      final sqlstate = (r['sqlstate'] ?? '-').toString().padRight(8);
      final msg = r['msg']?.toString().replaceAll('\n', ' ') ?? '';
      stdout.writeln('  $label  $status  $sqlstate  $msg');
    }
    stdout.writeln('');
  }

  if (fails.isNotEmpty) {
    stdout.writeln('[arbiter] FAIL — ${fails.length} of ${rows.length} '
        'onConflict pairs do not resolve on live schema:');
    for (final r in fails) {
      stdout.writeln('  - ${r['label']}: SQLSTATE=${r['sqlstate']} '
          '${r['msg']}');
    }
    return 1;
  }

  stdout.writeln(
      '[arbiter] OK — all ${rows.length} onConflict pairs resolve cleanly.');
  return 0;
}

Future<void> main(List<String> argv) async {
  final code = await _main(argv);
  exit(code);
}
