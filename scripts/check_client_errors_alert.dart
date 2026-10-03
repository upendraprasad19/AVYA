// scripts/check_client_errors_alert.dart
//
// Gate: 29
//
// Gate 29 (Tech-debt audit 2026-05-20, finding I4): assert an alert config
// exists at `supabase/alerts/client_errors.yaml` declaring a threshold rule
// on the `client_errors` table.
//
// The audit finding: there's no alert on `client_errors` spike — silent
// until founder manual SQL. `feedback_observability_silent_drop.md` already
// codified one burn from this surface (Test #16.1 D — log-client-error
// rate-limiter ate 100/24h overage as 200s for 8h).
//
// Required fields in the YAML:
//   - source: client_errors
//   - threshold: <description>
//   - notify: <channel>
//
// Exit 0 = pass.
// Exit 1 = fail: file missing or required field absent.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final file = File('supabase/alerts/client_errors.yaml');
  if (!file.existsSync()) {
    stderr.writeln('[Gate 29] FAIL: supabase/alerts/client_errors.yaml missing');
    stderr.writeln('  Spec: alert config declaring threshold + notify channel for client_errors spikes.');
    exit(warnOnly ? 0 : 1);
  }
  final content = file.readAsStringSync();
  final required = ['source:', 'threshold:', 'notify:'];
  final missing = required.where((k) => !content.contains(k)).toList();
  final tag = warnOnly ? '[Gate 29 WARN]' : '[Gate 29]';
  if (missing.isEmpty) {
    stdout.writeln('$tag PASS: client_errors alert config present + complete.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: missing required keys in ${file.path}: $missing');
  exit(warnOnly ? 0 : 1);
}
