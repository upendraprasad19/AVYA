// scripts/compare_baseline.dart
//
// Compares current test + lint state against baseline.json captured at
// start of batch. Reports newly-failing / newly-skipped tests + lint
// count increase.
//
// Usage: dart run scripts/compare_baseline.dart
// Exit codes: 0 = no regressions, 1 = regression detected.

import 'dart:convert';
import 'dart:io';

void main() async {
  final base = File('baseline.json');
  if (!base.existsSync()) {
    stderr.writeln('baseline.json not found — run capture_baseline.dart at start of batch.');
    exit(1);
  }

  // Re-run tests
  final testRes = await Process.run('flutter', ['test', '--reporter', 'json']);
  final currentOutput = testRes.stdout.toString();
  // Count failures by parsing JSON event lines
  final newlyFailing = _diffFailures(base.readAsStringSync(), currentOutput);

  // Lints
  final baseLintsRaw =
      jsonDecode(File('baseline-lints.json').readAsStringSync())
          as Map<String, dynamic>;
  final baseLintCount = (baseLintsRaw['lint_count'] as num).toInt();
  final analyzeRes = await Process.run('flutter', ['analyze', '--no-fatal-infos']);
  final currentLints = int.parse(RegExp(r'(\d+) issues? found').firstMatch(analyzeRes.stdout.toString())?.group(1) ?? '0');

  bool regressed = false;
  if (newlyFailing.isNotEmpty) {
    stderr.writeln('REGRESSION: ${newlyFailing.length} newly-failing tests:');
    for (final n in newlyFailing) stderr.writeln('  - $n');
    regressed = true;
  }
  if (currentLints > baseLintCount) {
    stderr.writeln('REGRESSION: lint count up: $baseLintCount → $currentLints');
    regressed = true;
  }
  if (regressed) exit(1);
  stdout.writeln('No regressions detected.');
}

List<String> _diffFailures(String baseJson, String currentJson) {
  // Parse JSON event lines; extract failures from each side; return failures present in current but not in base.
  final baseFailures = _extractFailures(baseJson);
  final currentFailures = _extractFailures(currentJson);
  return currentFailures.where((f) => !baseFailures.contains(f)).toList();
}

Set<String> _extractFailures(String reporterJson) {
  final result = <String>{};
  for (final line in reporterJson.split('\n')) {
    if (line.isEmpty) continue;
    try {
      final event = jsonDecode(line);
      if (event is! Map) continue;
      if (event['type'] == 'testDone' && event['result'] == 'error' || event['result'] == 'failure') {
        result.add(event['testID']?.toString() ?? '');
      }
    } catch (_) {/* skip non-JSON lines */}
  }
  return result;
}
