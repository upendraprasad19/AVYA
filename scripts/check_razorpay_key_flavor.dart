// scripts/check_razorpay_key_flavor.dart
//
// Gate 24 (Tech-debt audit 2026-05-20, finding I14): assert that Razorpay
// key prefixes match the build flavor. `rzp_live_*` MUST appear only in
// prod-flavor build configuration; `rzp_test_*` in dev-flavor.
//
// The audit risk: shipping prod APK with `rzp_test_*` key (or vice versa)
// silently fails payments or hits the wrong ledger.
//
// Verification target: `.env`, `.env.dev`, `.env.prod` (gitignored, on disk
// only). This gate checks the files exist + their RAZORPAY_KEY_ID prefix
// matches the flavor. CI cannot verify .env files (gitignored), so this
// gate is run locally via pre-commit + the /build-apk skill.
//
// Exit 0 = pass / files absent (CI mode — skip with informational note).
// Exit 1 = fail: flavor/prefix mismatch detected.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final violations = <String>[];
  var checked = 0;

  final checks = <String, String>{
    '.env.dev': 'rzp_test_',
    '.env.prod': 'rzp_live_',
  };

  for (final entry in checks.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) continue;
    checked++;
    final content = file.readAsStringSync();
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('RAZORPAY_KEY_ID')) continue;
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final value = line.substring(eq + 1).trim().replaceAll('"', '').replaceAll("'", '');
      if (value.isEmpty) continue;
      if (!value.startsWith(entry.value)) {
        violations.add('${entry.key}:${i + 1} expects prefix `${entry.value}`, got `${value.split('_').take(2).join('_')}_...`');
      }
    }
  }

  final tag = warnOnly ? '[Gate 24 WARN]' : '[Gate 24]';
  if (checked == 0) {
    stdout.writeln('$tag SKIP: no .env.dev/.env.prod present (CI mode — only checked locally).');
    exit(0);
  }
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: $checked env file(s) checked, Razorpay key prefix matches flavor.');
    exit(0);
  }
  stderr.writeln('$tag FAIL:');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  exit(warnOnly ? 0 : 1);
}
