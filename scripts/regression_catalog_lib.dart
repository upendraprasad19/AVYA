// scripts/regression_catalog_lib.dart
//
// Pure parsing logic for check_regression_catalog.dart, split out so it's
// unit-testable without needing a real docs/diagnoses/INDEX.md on disk or a
// `flutter test` invocation. Named WITHOUT the `check_` prefix, matching
// every other gate's `_lib.dart` companion in this directory (e.g.
// worktree_guard_lib.dart, plan_review_record_lib.dart) -- pre-commit.sh's
// bounded-parallel gate runner globs literally `scripts/check_*.dart` and
// `dart run`s each match with no arguments; a `check_`-prefixed lib file
// with no `main()` would be swept into that loop and fail as a bogus gate.
// See test/scripts/regression_catalog_lib_test.dart.

/// Extracts every distinct test-file path referenced by an INDEX.md row
/// dated on/after [cutoff].
///
/// The "Test path" column is free text (mirrors a diagnose-doc's
/// `regression_test_planned` field), so a single row's cell routinely holds
/// several comma/period-separated paths plus prose annotations in parens --
/// e.g. `test/a_test.dart, test/b_test.dart (NEW, round-2).` This scans for
/// every `test/**.dart` / `test/**.sql` TOKEN in the row instead of trying
/// to capture the whole cell as one path -- prose and punctuation around
/// each token are simply not matched. A stray space right after a path
/// separator (a known typo shape in a couple of historical entries, e.g.
/// `test/contracts/ foo_test.dart`) is normalized away first so the token
/// regex still finds it.
Set<String> extractRecentTestPaths(String indexContent, DateTime cutoff) {
  final testPaths = <String>{};
  final rowDatePattern = RegExp(r'^\|\s*(\d{4}-\d{2}-\d{2})\s*\|');
  final pathToken = RegExp(r'test/[A-Za-z0-9_/]+\.(?:dart|sql)');
  for (final line in indexContent.split('\n')) {
    final rowMatch = rowDatePattern.firstMatch(line);
    if (rowMatch == null) continue;
    final date = DateTime.tryParse(rowMatch.group(1)!);
    if (date == null || date.isBefore(cutoff)) continue;
    if (!line.contains('test/')) continue; // e.g. "n/a" rows, no token to find
    final normalized = line.replaceAll(RegExp(r'/[ \t]+'), '/');
    for (final m in pathToken.allMatches(normalized)) {
      testPaths.add(m.group(0)!);
    }
  }
  return testPaths;
}

/// `.sql` regression paths aren't Dart tests -- `flutter test` cannot
/// "load" them. Splits an extracted path set into the Dart paths (runnable
/// via `flutter test`) and the `.sql` paths (existence-checked only; each
/// runs against live Postgres via its own dedicated harness, not this gate).
({List<String> dartPaths, List<String> sqlPaths}) splitDartAndSqlPaths(
  Iterable<String> paths,
) {
  final dartPaths = <String>[];
  final sqlPaths = <String>[];
  for (final p in paths) {
    if (p.endsWith('.sql')) {
      sqlPaths.add(p);
    } else {
      dartPaths.add(p);
    }
  }
  return (dartPaths: dartPaths, sqlPaths: sqlPaths);
}
