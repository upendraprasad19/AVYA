// scripts/check_regression_catalog.dart
//
// Pre-merge gate: walks docs/diagnoses/INDEX.md, verifies every bug
// class from the last 30 days still has its regression test green +
// no test was deleted in this batch.
//
// Usage: dart run scripts/check_regression_catalog.dart
// Exit codes: 0 = pass, 1 = regression detected, 2 = config error.

import 'dart:io';

import 'regression_catalog_lib.dart';

void main() async {
  // Step 1: Parse INDEX.md for test paths from last 30 days.
  final indexFile = File('docs/diagnoses/INDEX.md');
  if (!indexFile.existsSync()) {
    stderr.writeln('docs/diagnoses/INDEX.md not found. Run build_bug_index.dart first.');
    exit(2);
  }
  final content = indexFile.readAsStringSync();
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  final testPaths = extractRecentTestPaths(content, cutoff);

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

  // Step 3: Run the Dart tests. `.sql` regression paths (e.g.
  // test/sql/*.sql) are NOT Dart tests -- `flutter test` cannot "load" them
  // and errors out. They're each meant to run live against Postgres inside
  // a rolled-back transaction via their own dedicated harness (e.g.
  // `dart run scripts/check_onconflict_live_arbiter.dart --sql <path>`,
  // per the convention documented alongside each .sql file's own INDEX.md
  // entry), which needs live DB credentials this gate doesn't have and
  // isn't the right place to wire up. Step 2 above already confirmed the
  // .sql file itself wasn't deleted, which is this gate's actual job for
  // those paths; only hand the .dart paths to `flutter test`.
  final split = splitDartAndSqlPaths(testPaths);
  final dartPaths = split.dartPaths;
  final sqlPaths = split.sqlPaths;
  if (dartPaths.isEmpty) {
    stdout.writeln(
      'Regression catalog: no recent Dart tests in window'
      '${sqlPaths.isEmpty ? '' : ' (${sqlPaths.length} .sql path(s) present-checked only)'} — pass.',
    );
    exit(0);
  }
  final result = await Process.run(
    'flutter',
    ['test', ...dartPaths],
    // Git exports GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE into every hook, and
    // this gate runs only from pre-commit on a merge commit. Those override both
    // `workingDirectory:` and `-C <path>`, so any test building its own git repo
    // gets pointed at the REAL repo — mid-merge — and fails on unrelated state.
    // See scrubbedChildEnvironment's doc comment for the measured evidence.
    environment: scrubbedChildEnvironment(Platform.environment),
    includeParentEnvironment: false,
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
  stdout.writeln(
    'Regression catalog: ${dartPaths.length} recent Dart tests all green'
    '${sqlPaths.isEmpty ? '' : ' (${sqlPaths.length} .sql path(s) present-checked only)'}.',
  );
  exit(0);
}
