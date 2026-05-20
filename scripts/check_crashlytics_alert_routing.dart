// scripts/check_crashlytics_alert_routing.dart
//
// Gate 30 (Tech-debt audit 2026-05-20, finding I9): assert that Firebase
// Crashlytics alert routing is documented at
// `android/app/firebase-alerts.json` (declarative record of velocity / ANR
// thresholds + notification channel).
//
// The audit finding: Crashlytics is wired in 7 source files but no
// dashboard alert routing is documented; founder finds crashes by visiting
// the dashboard. The actual Firebase Console alert config is per-project
// state; this gate verifies the documented intent exists in the repo so
// machine-readable audits can catch drift.
//
// Required fields:
//   - velocity_threshold: <%>
//   - anr_threshold: <%>
//   - notify: <channel description>
//   - dashboard_url: <link>
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final file = File('android/app/firebase-alerts.json');
  if (!file.existsSync()) {
    stderr.writeln('[Gate 30] FAIL: android/app/firebase-alerts.json missing');
    stderr.writeln('  Spec: declarative record of Crashlytics velocity + ANR threshold + notify channel.');
    exit(warnOnly ? 0 : 1);
  }
  final content = file.readAsStringSync();
  final required = ['velocity_threshold', 'anr_threshold', 'notify', 'dashboard_url'];
  final missing = required.where((k) => !content.contains(k)).toList();
  final tag = warnOnly ? '[Gate 30 WARN]' : '[Gate 30]';
  if (missing.isEmpty) {
    stdout.writeln('$tag PASS: Crashlytics alert routing documented.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: missing required keys in ${file.path}: $missing');
  exit(warnOnly ? 0 : 1);
}
