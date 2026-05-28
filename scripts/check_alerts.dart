// SessionStart hook script: queries unacknowledged alerts via Supabase REST
// and emits a JSON summary to stdout for the Claude session to surface.
//
// Used by .claude/settings.json `hooks.SessionStart` entry.
//
// Output contract (JSON to stdout):
//   {
//     "alerts": [
//       {
//         "id": 123,
//         "detected_at": "2026-05-28T08:30:00+05:30",
//         "source": "alert_client_errors_spike",
//         "severity": "warn",
//         "summary": "client_errors spike: 47 rows in last hour",
//         "suggested_action": "Inspect docs/diagnoses for recent regression..."
//       }
//     ],
//     "count": 1,
//     "queried_at": "2026-05-28T09:00:01+05:30"
//   }
//
// If no alerts, emits {"alerts": [], "count": 0, "queried_at": "..."}.
// If error, emits {"error": "...", "queried_at": "..."} and exits 0
// (hooks should not break session start).
//
// CONFIG
// ------
// Reads .env via line-parse (no flutter_dotenv). Requires SUPABASE_URL.
// Uses anon key for the REST query — the alerts RLS policy blocks anon,
// so this script will return an empty list unless a service-role key is
// available via SUPABASE_SERVICE_ROLE_KEY env var. We do not require it
// to be set; absence = no surfacing, which is a safe default.

import 'dart:convert';
import 'dart:io';

void main() async {
  final env = _loadEnv();
  final url = env['SUPABASE_URL'];
  final svcKey = env['SUPABASE_SERVICE_ROLE_KEY'];

  if (url == null || svcKey == null || svcKey.isEmpty) {
    // Not a failure — just no surfacing today.
    stdout.writeln(jsonEncode({
      'alerts': <Map<String, dynamic>>[],
      'count': 0,
      'note': svcKey == null
          ? 'SUPABASE_SERVICE_ROLE_KEY not set; skipping alert surfacing.'
          : 'SUPABASE_URL not set.',
      'queried_at': _nowIst(),
    }));
    return;
  }

  try {
    final uri = Uri.parse(
        '$url/rest/v1/alerts?acknowledged=eq.false&order=detected_at.desc&limit=20');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final req = await client.getUrl(uri);
    req.headers.set('apikey', svcKey);
    req.headers.set('Authorization', 'Bearer $svcKey');
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = await res.transform(utf8.decoder).join();
    client.close();

    if (res.statusCode != 200) {
      stdout.writeln(jsonEncode({
        'alerts': <Map<String, dynamic>>[],
        'count': 0,
        'error': 'HTTP ${res.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}',
        'queried_at': _nowIst(),
      }));
      return;
    }

    final List<dynamic> rows = jsonDecode(body) as List<dynamic>;
    final alerts = rows.map((r) {
      final m = r as Map<String, dynamic>;
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

Map<String, String> _loadEnv() {
  final env = <String, String>{};
  final envFile = File('.env');
  if (envFile.existsSync()) {
    for (final line in envFile.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final eq = t.indexOf('=');
      if (eq == -1) continue;
      final k = t.substring(0, eq).trim();
      var v = t.substring(eq + 1).trim();
      if (v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1);
      }
      env[k] = v;
    }
  }
  // Process env overrides .env (CI / harness).
  for (final entry in Platform.environment.entries) {
    if (env[entry.key] == null) env[entry.key] = entry.value;
  }
  // Process env precedence for service-role.
  if (Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] != null) {
    env['SUPABASE_SERVICE_ROLE_KEY'] =
        Platform.environment['SUPABASE_SERVICE_ROLE_KEY']!;
  }
  return env;
}

String _nowIst() {
  // IST = UTC+5:30. No DST.
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  final y = ist.year.toString().padLeft(4, '0');
  final mo = ist.month.toString().padLeft(2, '0');
  final d = ist.day.toString().padLeft(2, '0');
  final h = ist.hour.toString().padLeft(2, '0');
  final mi = ist.minute.toString().padLeft(2, '0');
  final s = ist.second.toString().padLeft(2, '0');
  return '$y-$mo-${d}T$h:$mi:$s+05:30';
}
