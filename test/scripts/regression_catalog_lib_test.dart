import 'dart:io';

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

  group('scrubbedChildEnvironment (diagnose 4f2a9e)', () {
    test('removes every git hook variable that overrides workingDirectory', () {
      final out = scrubbedChildEnvironment({
        'GIT_DIR': '/repo/.git',
        'GIT_WORK_TREE': '/repo',
        'GIT_INDEX_FILE': '/repo/.git/index',
        'PATH': '/usr/bin',
      });
      expect(out.containsKey('GIT_DIR'), isFalse);
      expect(out.containsKey('GIT_WORK_TREE'), isFalse);
      expect(out.containsKey('GIT_INDEX_FILE'), isFalse);
      expect(out['PATH'], '/usr/bin',
          reason: 'PATH must survive — the child still has to find `flutter`');
    });

    test('removes GITHUB_* and PUSH_BEFORE (gate-e2e hermetic contract)', () {
      final out = scrubbedChildEnvironment({
        'GITHUB_EVENT_PATH': '/e.json',
        'GITHUB_ACTIONS': 'true',
        'PUSH_BEFORE': 'abc',
        'HOME': '/home/u',
      });
      expect(out.keys, ['HOME'],
          reason: 'one affected file reads GITHUB_EVENT_PATH (diagnose c3f8e1)');
    });

    test('is case-insensitive on the prefix', () {
      final out = scrubbedChildEnvironment({'git_dir': '/x', 'Git_Work_Tree': '/y'});
      expect(out, isEmpty,
          reason: 'Windows env vars are case-insensitive; a lowercase GIT_DIR '
              'leaks just as effectively as an uppercase one');
    });

    test('keeps unrelated vars, including ones merely CONTAINING git', () {
      final out = scrubbedChildEnvironment({
        'FLUTTER_ROOT': '/f',
        'MY_GIT_TOKEN': 'keep', // does not START with GIT_
        'GIT_DIR': '/drop',
      });
      expect(out.keys.toSet(), {'FLUTTER_ROOT', 'MY_GIT_TOKEN'},
          reason: 'the filter is a PREFIX match, not a substring match — '
              'over-scrubbing would strip unrelated config');
    });

    test('does not mutate the caller\'s map', () {
      final parent = {'GIT_DIR': '/x', 'PATH': '/usr/bin'};
      scrubbedChildEnvironment(parent);
      expect(parent.containsKey('GIT_DIR'), isTrue,
          reason: 'Platform.environment is unmodifiable; copying first also '
              'keeps this usable on an ordinary map');
    });
  });

  group('the gate actually USES the scrub', () {
    // STRUCTURAL, and labelled as such. Driving check_regression_catalog.dart
    // end-to-end would mean standing up a throwaway Flutter project with its own
    // docs/diagnoses/INDEX.md and running a real `flutter test` inside it —
    // minutes per run for one assertion. The house pattern for I/O that cannot
    // be driven cheaply is: mutation-prove the pure DECISION (above) and pin the
    // wrapper structurally, stating the limit rather than implying coverage.
    // See feedback_mistake_guard_without_its_mirror.
    //
    // What this does NOT prove: that the arguments reach the child correctly.
    // What it DOES prove: the two lines cannot be deleted silently.
    test('Process.run passes the scrubbed env and disables inheritance', () {
      final src = File('scripts/check_regression_catalog.dart').readAsStringSync();
      final code = src.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
      expect(code, contains('scrubbedChildEnvironment(Platform.environment)'),
          reason: 'without this the child inherits GIT_DIR and every test that '
              'builds its own repo is redirected at the real one');
      expect(code, contains('includeParentEnvironment: false'),
          reason: 'passing `environment:` alone MERGES with the parent, so the '
              'scrubbed keys would come straight back — this flag is what makes '
              'the scrub take effect');
    });
  });
}
