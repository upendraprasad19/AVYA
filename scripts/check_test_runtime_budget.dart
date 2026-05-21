// scripts/check_test_runtime_budget.dart
//
// Gate 41 (Tech-debt audit 2026-05-20, finding T9): assert no individual
// test exceeds the configured runtime budget.
//
// Per the audit: CLAUDE.md rule 20 says "Failing tests on main are P0
// blockers" but there was no per-test runtime telemetry. A single slow
// test can push the contract suite past its CI timeout silently — the
// no-deferrals discipline degrades because the developer can't tell
// which test caused the cliff.
//
// This gate operates in two modes:
//
//   (1) `--analyze <json-report>` — given a flutter test JSON reporter
//       output, report the top-10 slowest tests and fail if any exceeds
//       BUDGET_SECONDS_PER_TEST (default: 30s).
//
//   (2) Standalone — generates the JSON report fresh via
//       `flutter test --reporter json`. Slow because it runs the suite.
//
// Usage:
//   dart run scripts/check_test_runtime_budget.dart                    # default 30s budget
//   dart run scripts/check_test_runtime_budget.dart --budget 60        # 60s budget
//   dart run scripts/check_test_runtime_budget.dart --analyze test_report.json
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:convert';
import 'dart:io';

const _defaultBudgetSeconds = 30;
const _topN = 10;

Future<void> main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  var budgetSeconds = _defaultBudgetSeconds;
  String? analyzePath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--budget' && i + 1 < args.length) {
      budgetSeconds = int.parse(args[i + 1]);
    } else if (args[i] == '--analyze' && i + 1 < args.length) {
      analyzePath = args[i + 1];
    }
  }

  String reportContent;
  if (analyzePath != null) {
    final f = File(analyzePath);
    if (!f.existsSync()) {
      stderr.writeln('[Gate 41] FAIL: $analyzePath not found');
      exit(warnOnly ? 0 : 1);
    }
    reportContent = f.readAsStringSync();
  } else {
    stdout.writeln('[Gate 41] Running `flutter test --reporter json` to capture runtimes (slow)...');
    final result = await Process.run(
      'flutter',
      ['test', '--reporter', 'json'],
      runInShell: true,
    );
    reportContent = result.stdout as String;
    if (result.exitCode != 0 && reportContent.isEmpty) {
      stderr.writeln('[Gate 41] FAIL: flutter test exited ${result.exitCode}');
      exit(warnOnly ? 0 : 1);
    }
  }

  // Parse JSON-lines reporter output.
  final perTestMs = <String, int>{};
  for (final line in reportContent.split('\n')) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic>? event;
    try {
      event = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    final type = event['type'] as String?;
    if (type == 'testStart') {
      final test = event['test'] as Map<String, dynamic>?;
      final id = test?['id']?.toString();
      final name = test?['name']?.toString();
      if (id != null && name != null) {
        perTestMs[id] = -(event['time'] as int? ?? 0); // negative = start time
      }
    } else if (type == 'testDone') {
      final testID = event['testID']?.toString();
      final endMs = event['time'] as int? ?? 0;
      if (testID != null && perTestMs.containsKey(testID)) {
        final startMs = -perTestMs[testID]!;
        final durMs = endMs - startMs;
        perTestMs[testID] = durMs;
      }
    }
  }

  // Map id → name by re-scanning testStart events.
  final idToName = <String, String>{};
  for (final line in reportContent.split('\n')) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic>? event;
    try {
      event = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    if (event['type'] != 'testStart') continue;
    final test = event['test'] as Map<String, dynamic>?;
    final id = test?['id']?.toString();
    final name = test?['name']?.toString();
    if (id != null && name != null) idToName[id] = name;
  }

  // Filter to actual durations + sort.
  final durations = <MapEntry<String, int>>[];
  perTestMs.forEach((id, ms) {
    if (ms > 0) durations.add(MapEntry(idToName[id] ?? id, ms));
  });
  durations.sort((a, b) => b.value.compareTo(a.value));

  final overBudget = durations
      .where((e) => e.value > budgetSeconds * 1000)
      .toList();

  stdout.writeln('[Gate 41] Top $_topN slowest tests:');
  for (final e in durations.take(_topN)) {
    final s = (e.value / 1000).toStringAsFixed(1);
    final marker = e.value > budgetSeconds * 1000 ? ' OVER-BUDGET' : '';
    stdout.writeln('  ${s}s  ${e.key}$marker');
  }

  final tag = warnOnly ? '[Gate 41 WARN]' : '[Gate 41]';
  if (overBudget.isEmpty) {
    stdout.writeln('$tag PASS: all ${durations.length} tests under ${budgetSeconds}s budget.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${overBudget.length} test(s) over ${budgetSeconds}s budget.');
  exit(warnOnly ? 0 : 1);
}
