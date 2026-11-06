// scripts/ci_test_partition_lib.dart
//
// Decision core of scripts/ci_test_partition.dart: which WHOLE test files a CI
// shard runs (OI-275, docs/plans/2026-10-10-release-cycle-speedup.md batch B3).
//
// WHY THIS EXISTS. The CI `Unit Tests` job ran every test file in one job:
// 13.0-13.5 min, the critical path of the whole workflow (the other jobs are all
// under 4 min). B3 turns it into a matrix of N jobs that each run a DISJOINT set
// of whole files, then an aggregator job named exactly `Unit Tests` that passes
// only when every shard did.
//
// WHY WHOLE FILES, NOT `--total-shards`. Within-suite sharding was tried and
// REVERTED on 2026-08-10 (comment above the `unit-test` job in test.yml): it
// slices test BODIES inside every suite, so each shard still compiled and loaded
// all ~700 files (measured 18.3% faster, under the pre-committed 25% floor), and
// it handed a shard an assertion without the earlier test in the SAME file that
// had injected the state it asserted on. Handing each job whole files removes
// both: a file is never split (a later test never loses its predecessor), and a
// shard compiles only its own files.
//
// WHY ROUND-ROBIN OVER THE SORTED PATH LIST (the 0-based file i of the sorted list
// goes to the 1-based shard `(i % total) + 1`), and not a weighted partition.
// Round 2 of the plan review measured that declared `@Timeout`s do not predict
// wall-clock (per-file spans are at most ~23 s; a file declared 14 minutes is
// invisible in the log), and a simulated longest-processing-time packing produced
// 262/263/262/263 files anyway. Sorted order also deals neighbouring files (which
// tend to share fixtures and cost) to different shards. The first matrix run logs
// per-shard durations; a slowest/fastest skew above 1.5x re-balances with a
// committed measured-duration table in the same batch.
//
// The only I/O in this file is the directory listing in [discoverTestFiles]; the
// rest is a pure function of its arguments, so the whole contract is unit-tested.

import 'dart:io';

/// A test file is a `*_test.dart` file under `test/` -- the set `flutter test
/// test/` discovers (golden-tagged tests are excluded at run time by
/// `--exclude-tags golden`, not here, so a shard's file list is identical on every
/// platform).
bool isTestFilePath(String path) => path.endsWith('_test.dart');

/// Repo-relative, forward-slash form (`test/contracts/x_test.dart`), identical on
/// Windows and Linux.
String normalizeTestPath(String path) => path.replaceAll('\\', '/');

/// Characters a path may contain so the workflow can hand the list to
/// `flutter test $FILES` through UNQUOTED word-splitting. A path with a space or a
/// glob character would be split or expanded by the shell and silently run the
/// wrong files; [unsafeTestPaths] lets the CLI refuse loudly instead.
final RegExp _shellSafePath = RegExp(r'^test/[A-Za-z0-9_./+-]+$');

/// True when [path] survives unquoted shell expansion unchanged.
bool isShellSafeTestPath(String path) => _shellSafePath.hasMatch(path);

/// The paths in [paths] that are NOT safe to pass through unquoted expansion.
List<String> unsafeTestPaths(Iterable<String> paths) =>
    [for (final p in paths) if (!isShellSafeTestPath(p)) p];

/// The list the partition is defined over: test files only, normalised,
/// de-duplicated, sorted by UTF-16 code unit (locale independent, so the order is
/// the same on every machine).
List<String> sortedTestFiles(Iterable<String> paths) {
  final set = <String>{
    for (final p in paths)
      if (isTestFilePath(normalizeTestPath(p))) normalizeTestPath(p),
  };
  return set.toList()..sort();
}

/// Lists the test files under [testDir] (default: `test` in the current
/// directory), recursively, without following links, as sorted paths of the form
/// `test/<path inside testDir>` -- the same spelling CI passes to `flutter test`,
/// whatever directory [testDir] actually is. Returns an empty list when the
/// directory does not exist.
List<String> discoverTestFiles([Directory? testDir]) {
  final dir = testDir ?? Directory('test');
  if (!dir.existsSync()) return const <String>[];
  final base = normalizeTestPath(dir.path).replaceAll(RegExp(r'/+$'), '');
  final found = <String>[];
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    // The same predicate `flutter test` applies (flutter_tools commands/test.dart
    // `_findTests`: `path.endsWith('_test.dart') && isFileSync(path)`). isFileSync
    // follows a symlink to a file, so a linked test file is counted like Flutter
    // counts it; `e is File` would drop it from every shard and run it nowhere.
    if (!FileSystemEntity.isFileSync(e.path)) continue;
    final p = normalizeTestPath(e.path);
    if (!isTestFilePath(p)) continue;
    found.add(p.startsWith('$base/') ? 'test/${p.substring(base.length + 1)}' : p);
  }
  return sortedTestFiles(found);
}

/// The files of shard [shard] (1-based) out of [total]: file `i` of the sorted
/// list [sortedFiles] belongs to shard `(i % total) + 1`. Throws [ArgumentError]
/// for a shard outside `1..total` or a non-positive total.
List<String> shardFiles(List<String> sortedFiles, int shard, int total) {
  if (total < 1) throw ArgumentError.value(total, 'total', 'must be >= 1');
  if (shard < 1 || shard > total) {
    throw ArgumentError.value(shard, 'shard', 'must be in 1..$total');
  }
  return <String>[
    for (var i = 0; i < sortedFiles.length; i++)
      if (i % total == shard - 1) sortedFiles[i],
  ];
}
