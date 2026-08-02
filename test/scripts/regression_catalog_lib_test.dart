import 'package:flutter_test/flutter_test.dart';

import '../../scripts/regression_catalog_lib.dart';

void main() {
  final recent = DateTime.now().subtract(const Duration(days: 1));
  final recentDateStr =
      '${recent.year}-${recent.month.toString().padLeft(2, '0')}-${recent.day.toString().padLeft(2, '0')}';
  final old = DateTime.now().subtract(const Duration(days: 60));
  final oldDateStr =
      '${old.year}-${old.month.toString().padLeft(2, '0')}-${old.day.toString().padLeft(2, '0')}';

  test(
    'a cell with multiple comma-separated paths + prose extracts each real '
    'path as its own token, not one bogus blob',
    () {
      final index = '''
| Date | Bug ID | Symptom | Concept | Test path |
|---|---|---|---|---|
| $recentDateStr | f4a7c2 | Some symptom text with… | some_concept | test/contracts/a_test.dart, test/contracts/b_test.dart (extended), test/widgets/c_test.dart (NEW, B-pass finding 2) |
''';
      final paths = extractRecentTestPaths(index, DateTime(2000));

      expect(paths, {
        'test/contracts/a_test.dart',
        'test/contracts/b_test.dart',
        'test/widgets/c_test.dart',
      });
      // This is the exact regression this test guards: the old
      // single-capture-group parser returned the WHOLE cell (prose,
      // commas, parens and all) as one string, which
      // File(path).existsSync() would always report missing regardless of
      // whether every real path inside it existed.
      expect(
        paths.any((p) => p.contains(',') || p.contains('(')),
        isFalse,
        reason: 'no extracted path should contain comma/paren prose',
      );
    },
  );

  test('a stray space right after a path separator is still found', () {
    final index = '''
| Date | Bug ID | Symptom | Concept | Test path |
|---|---|---|---|---|
| $recentDateStr | d5c8a3 | Some symptom text with… | some_concept | test/contracts/ health_sync_service_dedup_test.dart (source-grep) |
''';
    final paths = extractRecentTestPaths(index, DateTime(2000));

    expect(paths, {'test/contracts/health_sync_service_dedup_test.dart'});
  });

  test('rows older than the cutoff are excluded', () {
    final index = '''
| Date | Bug ID | Symptom | Concept | Test path |
|---|---|---|---|---|
| $oldDateStr | aaaaaa | Old bug | old_concept | test/contracts/old_test.dart |
| $recentDateStr | bbbbbb | Recent bug | recent_concept | test/contracts/new_test.dart |
''';
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final paths = extractRecentTestPaths(index, cutoff);

    expect(paths, {'test/contracts/new_test.dart'});
  });

  test('a single clean path per cell still works (the common case)', () {
    final index = '''
| Date | Bug ID | Symptom | Concept | Test path |
|---|---|---|---|---|
| $recentDateStr | c8f1d3 | A bug | a_concept | test/contracts/password_reset_redirect_flow_test.dart |
''';
    final paths = extractRecentTestPaths(index, DateTime(2000));

    expect(paths, {'test/contracts/password_reset_redirect_flow_test.dart'});
  });

  test('a .sql regression path is extracted too', () {
    final index = '''
| Date | Bug ID | Symptom | Concept | Test path |
|---|---|---|---|---|
| $recentDateStr | e6b9c4 | A bug | a_concept | test/sql/some_verify.sql (live A/B leak check) |
''';
    final paths = extractRecentTestPaths(index, DateTime(2000));

    expect(paths, {'test/sql/some_verify.sql'});
  });

  test('a non-table line (no leading "| YYYY-MM-DD |") contributes nothing', () {
    final index = '- $recentDateStr c8f1d3 — free-text summary line, not a table row';
    final paths = extractRecentTestPaths(index, DateTime(2000));

    expect(paths, isEmpty);
  });

  test(
    'splitDartAndSqlPaths separates .sql (not runnable via `flutter test`) '
    'from .dart paths',
    () {
      final split = splitDartAndSqlPaths([
        'test/contracts/a_test.dart',
        'test/sql/some_verify.sql',
        'test/contracts/b_test.dart',
      ]);

      expect(split.dartPaths, [
        'test/contracts/a_test.dart',
        'test/contracts/b_test.dart',
      ]);
      expect(split.sqlPaths, ['test/sql/some_verify.sql']);
    },
  );
}
