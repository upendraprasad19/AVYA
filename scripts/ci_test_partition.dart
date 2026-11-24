// scripts/ci_test_partition.dart
//
// Usage:  dart scripts/ci_test_partition.dart <shard> <total> --set core|sweep
//
// Prints the WHOLE test files shard <shard> (1-based) of <total> runs for one of
// the two sets, one repo-relative path per line:
//   core   every `test/**/*_test.dart` NOT under test/plan_generator/; the 0-based
//          file i of that sorted list goes to the 1-based shard `(i % total) + 1`;
//   sweep  the files under test/plan_generator/, packed longest-first by the
//          measured durations in scripts/data/ci_sweep_durations.json.
// `--set` is REQUIRED: there is no all-files form, so no caller can silently get
// one set when it meant the whole suite (docs/plans/2026-11-24-ci-sweep-split.md).
// Used by the CI `unit-test` and `sweep-test` matrices in .github/workflows/test.yml:
//
//     FILES="$(dart scripts/ci_test_partition.dart "$SHARD" "$TOTAL" --set core)" || exit 1
//     flutter test $FILES --exclude-tags golden --reporter expanded
//
// A local run of everything except the sweeps is the same list unsharded:
//     flutter test $(dart scripts/ci_test_partition.dart 1 1 --set core) --exclude-tags golden
//
// Run it with plain `dart scripts/ci_test_partition.dart`, NOT `dart run`: `dart
// run` prints a "Running build hooks..." line on stdout that would become a bogus
// path in the list (the same trap documented at the TIER pipeline in
// scripts/pre-push.sh).
//
// Why and how the split works: scripts/ci_test_partition_lib.dart.
//
// Exit codes (every non-zero one prints a reason on stderr and NOTHING on stdout,
// so a caller that ignores the status still cannot run an empty or wrong list --
// an empty `flutter test` argument list would run the ENTIRE suite):
//   0   ok, the shard's files are on stdout
//   64  usage: not two integers, total < 1, shard outside 1..total, or `--set`
//       missing or not `core` / `sweep`
//   5   the duration table exists but is not a JSON object of numbers > 0
//   2   a test path is not safe for unquoted shell expansion (space, glob char)
//   3   the shard is empty (more shards than test files in the set)
//   4   no test files were found under ./test

import 'dart:io';

import 'ci_test_partition_lib.dart';

int _run(List<String> args) {
  if (args.length != 4 || args[2] != '--set' || !partitionSets.contains(args[3])) {
    stderr.writeln('usage: dart scripts/ci_test_partition.dart <shard> <total> --set core|sweep');
    return 64;
  }
  final set = args[3];
  final shard = int.tryParse(args[0]);
  final total = int.tryParse(args[1]);
  if (shard == null || total == null || total < 1 || shard < 1 || shard > total) {
    stderr.writeln('ci_test_partition: <shard> and <total> must be integers with '
        '1 <= shard <= total (got "${args[0]}" "${args[1]}")');
    return 64;
  }

  final all = discoverTestFiles();
  if (all.isEmpty) {
    stderr.writeln('ci_test_partition: no *_test.dart files found under ./test '
        '(wrong working directory?)');
    return 4;
  }
  final unsafe = unsafeTestPaths(all);
  if (unsafe.isNotEmpty) {
    stderr.writeln('ci_test_partition: refusing — these test paths are not safe to '
        'pass through unquoted shell expansion (allowed: test/ then [A-Za-z0-9_./+-]): '
        '${unsafe.take(5).join(', ')}${unsafe.length > 5 ? ', …' : ''}');
    return 2;
  }

  var durations = const <String, num>{};
  if (set == 'sweep') {
    final table = File(sweepDurationsPath);
    if (table.existsSync()) {
      try {
        durations = parseDurationTable(table.readAsStringSync());
      } on FormatException catch (e) {
        stderr.writeln('ci_test_partition: $sweepDurationsPath is not usable: ${e.message}');
        return 5;
      }
      // A stale row costs balance, not correctness: every file is still dealt once.
      final stale = staleDurationKeys(durations, all);
      if (stale.isNotEmpty) {
        stderr.writeln('::warning::ci_test_partition: $sweepDurationsPath names '
            '${stale.length} file(s) that no longer exist: ${stale.take(5).join(', ')}');
      }
    } else {
      stderr.writeln('::warning::ci_test_partition: $sweepDurationsPath not found; '
          'the sweep files are packed with equal weights');
    }
  }

  final mine = shardFilesOfSet(all, set, shard, total, durations);
  if (mine.isEmpty) {
    stderr.writeln('ci_test_partition: $set shard $shard/$total is EMPTY '
        '(${filesOfSet(all, set).length} $set test files, $total shards)');
    return 3;
  }
  stdout.writeln(mine.join('\n'));
  return 0;
}

void main(List<String> args) => exit(_run(args));
