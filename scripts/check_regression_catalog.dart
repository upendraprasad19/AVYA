// scripts/check_regression_catalog.dart
//
// Pre-merge gate: walks docs/diagnoses/INDEX.md, verifies every bug
// class from the last 30 days still has its regression test green +
// no test was deleted in this batch.
//
// Usage: dart run scripts/check_regression_catalog.dart
// Exit codes: 0 = pass, 1 = regression detected, 2 = config error.

import 'dart:io';

void main() async {
  // Step 1: Parse INDEX.md for test paths from last 30 days.
  final indexFile = File('docs/diagnoses/INDEX.md');
  if (!indexFile.existsSync()) {
    stderr.writeln('docs/diagnoses/INDEX.md not found. Run build_bug_index.dart first.');
    exit(2);
  }
  final content = indexFile.readAsStringSync();
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  final testPaths = <String>{};
  for (final line in content.split('\n')) {
    final m = RegExp(r'\|\s+(\d{4}-\d{2}-\d{2})\s+\|.*\|\s+(test/[^|]+)\s*\|').firstMatch(line);
    if (m == null) continue;
    final date = DateTime.tryParse(m.group(1)!);
    if (date == null || date.isBefore(cutoff)) continue;
    final path = m.group(2)!.trim();
    if (path.isEmpty || path.contains('n/a')) continue;
    testPaths.add(path);
  }

  // Step 2: For each test path, verify file exists.
  final missing = <String>[];
  for (final p in testPaths) {
    if (!File(p).existsSync()) missing.add(p);
  }
  if (missing.isNotEmpty) {
    stderr.writeln('Regression catalog: test files missing for ${missing.length} recent bugs:');
    for (final m in missing) stderr.writeln('  - $m');
    exit(1);
  }

  // Step 3: Run those tests.
  if (testPaths.isEmpty) {
    stdout.writeln('Regression catalog: no recent tests in window — pass.');
    exit(0);
  }
  final result = await Process.run(
    'flutter',
    ['test', ...testPaths],
    // Windows: Dart's Process.run cannot resolve `flutter.bat` without a shell,
    // so the merge-commit regression walk threw ProcessException ("cannot find
    // the file specified") whenever the recent-window test list was non-empty.
    // runInShell is cross-platform safe (cmd.exe on Windows, /bin/sh on Unix).
    runInShell: true,
  );
  if (result.exitCode != 0) {
    stderr.writeln('Regression catalog: at least one recent regression test FAILED:');
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    exit(1);
  }
  stdout.writeln('Regression catalog: ${testPaths.length} recent tests all green.');
  exit(0);
}
