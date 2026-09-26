// SessionStart hook script: queries unacknowledged alerts and emits a JSON
// summary to stdout for the Claude session to surface.
//
// Used by .claude/settings.json `hooks.SessionStart` entry.
//
// CREDENTIAL MODEL (2026-05-30 — item A of the cross-check follow-ups)
// -------------------------------------------------------------------
// The `alerts` table is RLS service-role-only, so this script needs the
// service-role key. CRITICAL: the key must NOT live in `.env`, because
// `.env` is compiled into the app via `--dart-define-from-file=.env`
// (CLAUDE.md §0) — a service-role key there would ship inside the APK
// (full RLS bypass = catastrophic).
//
// So the key lives in a SEPARATE gitignored tooling file that the Flutter
// build NEVER references:  `.claude/.alerts.env`  (one line:
// `SUPABASE_SERVICE_ROLE_KEY=<key>`). A `SUPABASE_SERVICE_ROLE_KEY` process
// env var overrides it (CI / alternate machines).
//
// (We tried the Supabase Management API token at
// `supabase/.supabase/supabase access token.txt` first — it is deploy-scoped
// and returns HTTP 403 on `/database/query`, so it can't read table data.)
//
// SUPABASE_URL is NOT secret and is read from `.env` as before.
//
// Output contract (JSON to stdout):
//   {"alerts": [ {id, detected_at, source, severity, summary, suggested_action} ],
//    "count": N, "queried_at": "<IST ISO8601>"}
//
// On any failure (missing key, network, non-200) it emits an empty list with
// a `note`/`error` and exits 0 — a SessionStart hook must NEVER break session
// start.

import 'dart:convert';
import 'dart:io';

const _alertsEnvPath = '.claude/.alerts.env';

void main() async {
  final url = _readEnvVar('SUPABASE_URL', files: ['.env']);
  final svcKey = _readEnvVar(
    'SUPABASE_SERVICE_ROLE_KEY',
    files: [_alertsEnvPath],
    allowProcessEnv: true,
  );

  if (url == null || url.isEmpty) {
    stdout.writeln(_empty(note: 'SUPABASE_URL not set in .env.'));
    return;
  }
  if (svcKey == null || svcKey.isEmpty) {
    stdout.writeln(_empty(
        note: 'SUPABASE_SERVICE_ROLE_KEY not found in "$_alertsEnvPath" '
            '(gitignored tooling file); skipping alert surfacing. '
            'Add one line: SUPABASE_SERVICE_ROLE_KEY=<key>'));
    return;
  }

  try {
    final uri = Uri.parse(
        '$url/rest/v1/alerts?acknowledged=eq.false'
        '&order=detected_at.desc&limit=20');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    final req = await client.getUrl(uri);
    req.headers.set('apikey', svcKey);
    req.headers.set('Authorization', 'Bearer $svcKey');
    final res = await req.close().timeout(const Duration(seconds: 12));
    final body = await res.transform(utf8.decoder).join();
    client.close();

    if (res.statusCode != 200) {
      stdout.writeln(jsonEncode({
        'alerts': <Map<String, dynamic>>[],
        'count': 0,
        'error': 'PostgREST HTTP ${res.statusCode}: ${_truncate(body, 200)}',
        'queried_at': _nowIst(),
      }));
      return;
    }

    final List<dynamic> rows = jsonDecode(body) as List<dynamic>;
    final alerts = rows.whereType<Map>().map((m) {
      return {
        'id': m['id'],
        'detected_at': m['detected_at'],
        'source': m['source'],
        'severity': m['severity'],
        'summary': m['summary'],
        'suggested_action': m['suggested_action'],
      };
    }).toList();

    stdout.writeln(jsonEncode({
      'alerts': alerts,
      'count': alerts.length,
      'queried_at': _nowIst(),
    }));
  } catch (e) {
    stdout.writeln(jsonEncode({
      'alerts': <Map<String, dynamic>>[],
      'count': 0,
      'error': e.toString(),
      'queried_at': _nowIst(),
    }));
  }
}

/// Reads a single env var, checking process env (optional) then the given
/// dotenv-style files in order. Returns the first non-empty value.
String? _readEnvVar(String key,
    {required List<String> files, bool allowProcessEnv = false}) {
  if (allowProcessEnv) {
    final p = Platform.environment[key];
    if (p != null && p.trim().isNotEmpty) return p.trim();
  }
  for (final path in files) {
    final f = File(path);
    if (!f.existsSync()) continue;
    for (final line in f.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final eq = t.indexOf('=');
      if (eq == -1) continue;
      if (t.substring(0, eq).trim() != key) continue;
      var v = t.substring(eq + 1).trim();
      if (v.length >= 2 &&
          ((v.startsWith('"') && v.endsWith('"')) ||
              (v.startsWith("'") && v.endsWith("'")))) {
        v = v.substring(1, v.length - 1);
      }
      if (v.isNotEmpty) return v;
    }
  }
  return null;
}

String _empty({required String note}) => jsonEncode({
      'alerts': <Map<String, dynamic>>[],
      'count': 0,
      'note': note,
      'queried_at': _nowIst(),
    });

String _truncate(String s, int n) => s.length <= n ? s : s.substring(0, n);

String _nowIst() {
  // IST = UTC+5:30. No DST.
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${p(ist.year, 4)}-${p(ist.month)}-${p(ist.day)}'
      'T${p(ist.hour)}:${p(ist.minute)}:${p(ist.second)}+05:30';
}
