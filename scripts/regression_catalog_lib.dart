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

/// The environment to hand the child `flutter test`, with git's hook variables
/// removed.
///
/// WHY THIS EXISTS. This gate runs ONLY on merge commits, i.e. always as a child
/// of the `pre-commit` hook — and git exports `GIT_DIR`, `GIT_WORK_TREE` and
/// `GIT_INDEX_FILE` into every hook. Those override BOTH `workingDirectory:` and
/// `-C <path>`, so a test that builds its OWN throwaway git repo is silently
/// redirected at the real repository (feedback_mistake_git_hook_env_leak). The
/// real repo is mid-merge at that moment, so those tests fail on state that has
/// nothing to do with the change under review.
///
/// Measured, not theorised (2026-08-13, merging supabase-http-fix): the walk
/// reported 9 failures across git_safety_hook_integration_test.dart,
/// review_gate_staged_content_not_working_tree_test.dart and
/// blast_radius_content_rule_wired_all_scripts_test.dart. The same three files
/// run standalone against the same mid-merge repo: 38/38 PASS. Re-running one of
/// them with `GIT_DIR`/`GIT_INDEX_FILE` exported reproduces the failures exactly.
/// The gate was manufacturing false failures on every conflicted merge.
///
/// `GITHUB_*` and `PUSH_BEFORE` are scrubbed too, matching the hermetic contract
/// the gate-e2e family already shares (test/contracts/gate_e2e_env_hermetic_test.dart)
/// — one of the affected files reads `GITHUB_EVENT_PATH` (diagnose c3f8e1).
///
/// Everything else — PATH above all — is preserved: the child still has to find
/// `flutter`.
Map<String, String> scrubbedChildEnvironment(Map<String, String> parent) {
  final env = Map<String, String>.from(parent);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  return env;
}
