
@Timeout(Duration(minutes: 3))
library;

// TIMEOUT RAISED FROM THE 30s DEFAULT (2026-08-13, diagnose 4f2a9e).
// This file spawns real subprocesses (`dart run` / shell), and a cold `dart run`
// costs seconds on its own — VM start plus kernel compile. Under the
// merge-commit regression-catalog walk, which runs ~700 tests concurrently,
// those subprocesses take long enough to blow the 30s PER-TEST default, and the
// walk reports failures for tests that pass standalone every time. Measured: one
// such file takes 33s wall with ZERO contention.
// Applied to the whole subprocess-spawning class, not only the files observed
// failing — fixing just the observed instances is what let this recur twice.

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

  test(
    'a cited .dart that is not a _test.dart (a shared harness) is NOT run: '
    'flutter test cannot load a file with no main',
    () {
      final split = splitDartAndSqlPaths([
        'test/sync/sync_domain_skip_harness.dart',
        'test/sync/a_test.dart',
      ]);

      expect(split.dartPaths, ['test/sync/a_test.dart']);
      expect(split.helperPaths, ['test/sync/sync_domain_skip_harness.dart']);
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

    // d81f3c. 4f2a9e scrubbed what a MACHINE sets — git's GIT_*, Actions'
    // GITHUB_*. These two are set by a PERSON, in the shell, immediately before
    // the merge that runs this gate, so they are at least as likely to be
    // present and were the ones it missed.
    test('removes the operator escape hatches (diagnose d81f3c)', () {
      final out = scrubbedChildEnvironment({
        'ALLOW_RAW_GIT': '1',
        'FOUNDER_APPROVED_NO_VERIFY': '1',
        'PATH': '/usr/bin',
      });
      expect(out.keys, ['PATH'],
          reason: 'git_safety_hook.dart:126-127 reads both and treats either as '
              'permission to allow a raw commit/push — a leak does not just '
              'misdirect the child, it INVERTS the deny assertions in '
              'git_safety_hook_integration_test.dart');
    });

    test('the hatches are removed case-insensitively too', () {
      final out = scrubbedChildEnvironment({
        'allow_raw_git': '1',
        'Founder_Approved_No_Verify': '1',
      });
      expect(out, isEmpty,
          reason: 'same Windows case-insensitivity that motivated the GIT_ '
              'case — an exact-case match would leak a lowercase spelling');
    });

    test('keeps vars that merely CONTAIN a hatch name', () {
      final out = scrubbedChildEnvironment({
        'ALLOW_RAW_GIT_LEGACY': 'keep',
        'MY_ALLOW_RAW_GIT': 'keep',
        'ALLOW_RAW_GIT': '/drop',
      });
      expect(out.keys.toSet(), {'ALLOW_RAW_GIT_LEGACY', 'MY_ALLOW_RAW_GIT'},
          reason: 'these are EXACT matches, not prefixes like GIT_ — widening '
              'them to startsWith would silently eat unrelated vars');
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

  // 2026-10-06 (class 2.56, fifth instance): the scrub covers EVERY variable the
  // repo's own scripts read as a control switch. The expectations below are a
  // LITERAL list written independently of the exported constants, so deleting a
  // constant cannot delete its own assertion (the derived two-way check against
  // what the scripts actually read is test/contracts/spawn_env_manifest_test.dart).
  group('scrubbedChildEnvironment: every repo control variable (class 2.56)', () {
    const stripped = <String>[
      'CONTRACT_SWEEP_NESTED', 'CONTRACT_SWEEP_SKIP',
      'PRE_COMMIT_FULL', 'PRE_COMMIT_LEGACY', 'PRE_COMMIT_GATE_JOBS', 'PRE_PUSH_FULL',
      'PRE_COMMIT_HOME', // the pre-commit.com framework's own name: the family prefix over-strips it, harmlessly, and that is pinned
      'DISCIPLINE_HOOK_MEMORY_PATH', 'DISCIPLINE_HOOK_SYNC_SKIP',
      'MINT_OI_TRANSPORT', 'MINT_OI_REMOTE', 'MINT_OI_OWNER_REPO', 'MINT_OI_GH_BIN',
      'MINT_OI_TEST_HOOK_BEFORE_PUSH',
      'MINT_MIG_TRANSPORT', 'MINT_MIG_REMOTE', 'MINT_MIG_OWNER_REPO', 'MINT_MIG_GH_BIN',
      'MINT_MIG_TEST_HOOK_BEFORE_PUSH',
      'ALLOW_MAIN_COMMIT', 'ALLOW_RAW_GIT', 'FOUNDER_APPROVED_NO_VERIFY', 'PUSH_BEFORE',
      'SUPABASE_ACCESS_TOKEN', 'SUPABASE_ACCESS_TOKEN_FITNESS', 'SUPABASE_SERVICE_ROLE_KEY',
      'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'RAZORPAY_KEY_ID', 'USDA_API_KEY',
      '_SKIP_RENDER_CHECK', 'ANDROID_DEVICE_ID',
      'GIT_DIR', 'GIT_SSH_COMMAND', 'GITHUB_ACTIONS', 'GITHUB_EVENT_PATH', 'GITHUB_REF',
      'GITHUB_REPOSITORY_OWNER',
      'EMAIL', // git's author-identity fallback (d9e4b1): an external reader
    ];

    test('every one is removed, in any letter case', () {
      for (final name in stripped) {
        expect(scrubbedChildEnvironment({name: 'x', 'PATH': '/p'}).keys, ['PATH'],
            reason: '$name must not reach a spawned test');
        expect(scrubbedChildEnvironment({name.toLowerCase(): 'x', 'PATH': '/p'}).keys, ['PATH'],
            reason: '${name.toLowerCase()} (Windows is case-insensitive)');
      }
    });

    test('the sweep recursion guard is the observed case: CONTRACT_SWEEP_NESTED is gone', () {
      // contract_sweep_e2e_test.dart inherited this from the sweep that ran it.
      expect(scrubbedChildEnvironment({'CONTRACT_SWEEP_NESTED': '1'}), isEmpty);
    });

    test('kept: the variables the child needs, DART_BIN_OVERRIDE and non-owned look-alikes', () {
      const kept = {
        'PATH': '/usr/bin', 'HOME': '/home/u', 'USERPROFILE': 'C:/u', 'TZ': 'Asia/Kolkata',
        'JAVA_HOME': '/jdk', 'ANDROID_HOME': '/a', 'ANDROID_SDK_ROOT': '/a', 'LOCALAPPDATA': 'C:/l',
        'SystemRoot': 'C:/Windows', 'PATHEXT': '.EXE',
        // the merge walk's flutter-test child contains tests that read this one to find dart
        'DART_BIN_OVERRIDE': '/dart',
        // prefixes are NOT widened beyond the repo-owned families (class 2.56): Supabase and
        // the pre-commit framework own these namespaces, so only exact names are stripped
        'SUPABASE_PROJECT_REF': 'keep', 'XPRE_COMMIT_X': 'keep', 'MY_CONTRACT_SWEEP_X': 'keep',
        'ANDROID_SERIAL': 'keep',
      };
      expect(scrubbedChildEnvironment(kept), kept);
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

  group('chunkPathsByCommandLength', () {
    test('keeps every path, in order, and every group under the cap', () {
      final paths = List.generate(145, (i) => 'test/contracts/some_long_regression_name_$i\_test.dart');
      final chunks = chunkPathsByCommandLength(paths, maxChars: 6000);
      expect(chunks.expand((c) => c).toList(), paths);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.join(' ').length, lessThanOrEqualTo(6000));
      }
    });

    test('an empty list gives no groups and one path gives one group', () {
      expect(chunkPathsByCommandLength(const <String>[]), isEmpty);
      expect(chunkPathsByCommandLength(const ['a_test.dart']), [
        ['a_test.dart'],
      ]);
    });

    test('the gate script runs flutter test once per group, not once for all', () {
      final src = File('scripts/check_regression_catalog.dart').readAsStringSync();
      final code = src.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
      expect(code, contains('chunkPathsByCommandLength(dartPaths)'));
      expect(code, contains("['test', ...chunk]"));
      expect(code, isNot(contains("['test', ...dartPaths]")));
    });
  });
  });
}
