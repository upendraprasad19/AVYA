// scripts/capture_baseline.dart
//
// Snapshot current test + lint state. Run at start of any batch.
// Outputs: baseline.json (test results) + baseline-lints.json (analyze
// lint count).
//
// Usage: dart run scripts/capture_baseline.dart
// Exit codes: 0 = success, 1 = capture failed.

import 'dart:convert';
import 'dart:io';

void main() async {
  // Tests
  final testRes = await Process.run('flutter', ['test', '--reporter', 'json']);
  if (testRes.exitCode != 0) {
    stderr.writeln('flutter test failed; capturing failure baseline.');
  }
  File('baseline.json').writeAsStringSync(testRes.stdout.toString());

  // Lints
  final analyzeRes = await Process.run('flutter', ['analyze', '--no-fatal-infos']);
  final lintCount = RegExp(r'(\d+) issues? found').firstMatch(analyzeRes.stdout.toString())?.group(1) ?? '0';
  File('baseline-lints.json').writeAsStringSync(jsonEncode({
    'captured_at': DateTime.now().toIso8601String(),
    'lint_count': int.parse(lintCount),
  }));
  stdout.writeln('Baseline captured: lint_count=$lintCount.');
}
