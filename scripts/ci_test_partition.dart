// scripts/ci_test_partition.dart
//
// Usage:  dart scripts/ci_test_partition.dart <shard> <total>
//
// Prints the WHOLE test files shard <shard> (1-based) of <total> runs, one repo-
// relative path per line, from the sorted list of `test/**/*_test.dart` (the
// 0-based file i of the sorted list goes to the 1-based shard `(i % total) + 1`).
// Used by the CI `unit-test` matrix in .github/workflows/test.yml:
//
//     FILES="$(dart scripts/ci_test_partition.dart "$SHARD" "$TOTAL")" || exit 1
//     flutter test $FILES --exclude-tags golden --reporter expanded
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
//   64  usage: not two integers, total < 1, or shard outside 1..total
//   2   a test path is not safe for unquoted shell expansion (space, glob char)
//   3   the shard is empty (more shards than test files)
//   4   no test files were found under ./test

import 'dart:io';

import 'ci_test_partition_lib.dart';

int _run(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart scripts/ci_test_partition.dart <shard> <total>');
    return 64;
  }
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

  final mine = shardFiles(all, shard, total);
  if (mine.isEmpty) {
    stderr.writeln('ci_test_partition: shard $shard/$total is EMPTY '
        '(${all.length} test files, $total shards)');
    return 3;
  }
  stdout.writeln(mine.join('\n'));
  return 0;
}

void main(List<String> args) => exit(_run(args));
