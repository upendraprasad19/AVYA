// test/scripts/ci_test_partition_test.dart
//
// scripts/ci_test_partition{,_lib}.dart splits the CI unit-test job into WHOLE-FILE
// shards (OI-275 batch B3). The danger is not a crash, it is a SILENT gap: a file
// that lands in no shard (or twice) is a test that never runs (or runs twice) while
// every job is green. So the properties asserted here are the partition laws —
// disjoint, complete, deterministic, balanced — each with the mutation it kills:
//
//   off-by-one in the modulo      -> "element i goes to shard (i % total) + 1", disjoint
//   skip the last file            -> complete (union == input)
//   drop the sort                 -> sorted + deterministic for shuffled input
//   `e is File` instead of isFileSync (a linked test file dropped) -> the symlink case
//   `endsWith('test.dart')`, no underscore (helpers become tests)  -> the `contest.dart` fixture
//   `followLinks: true` (files behind a directory link counted)    -> the linked-directory fixture
//
// Four layers: the pure functions on synthetic lists; the REAL test/ tree (the
// shell-safety mirror lives here, so a future file named `a b_test.dart` reddens a
// unit test BEFORE it can make a CI shard run the wrong files; and an independent
// oracle - git's own listing - so discovery is not only checked against itself); the
// discovery rules on throwaway trees; and the CLI run for real in a throwaway tree,
// including every refusal path.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/ci_test_partition_lib.dart';
import '../helpers/spawn.dart';

/// Synthetic test paths in the canonical (sorted) order `shardFiles` is defined over.
/// Directory names `d0, d1, d10, d2` do NOT sort numerically, so the list is passed
/// through [sortedTestFiles] rather than trusted to be generated in order.
List<String> _files(int n) => sortedTestFiles([
      for (var i = 0; i < n; i++) 'test/d${i ~/ 7}/f${i.toString().padLeft(4, '0')}_test.dart',
    ]);

void main() {
  group('shardFiles — the partition laws on synthetic lists', () {
    for (final total in [1, 2, 3, 4, 5, 7, 9]) {
      for (final n in [0, 1, 2, 3, 7, 8, 9, 10, 33, 100]) {
        test('total=$total over $n files: disjoint, complete, balanced, ordered', () {
          final all = _files(n);
          final shards = [for (var s = 1; s <= total; s++) shardFiles(all, s, total)];

          // Complete: every input file appears (union == input) ...
          expect(shards.expand((x) => x).toSet(), all.toSet(),
              reason: 'a file in NO shard is a test that never runs');
          // ... and disjoint: the sizes add up, so nothing appears twice.
          expect(shards.fold<int>(0, (a, s) => a + s.length), n,
              reason: 'a file in TWO shards runs twice and inflates the longest job');

          // Balanced to within one file.
          final sizes = shards.map((s) => s.length);
          expect(sizes.reduce(max) - sizes.reduce(min), lessThanOrEqualTo(1));

          // The exact rule, not just its consequences: file i -> shard (i % total) + 1.
          for (var i = 0; i < n; i++) {
            final owner = [for (var s = 0; s < total; s++) if (shards[s].contains(all[i])) s + 1];
            expect(owner, [(i % total) + 1], reason: 'file $i of $n, total $total');
          }

          // Each shard keeps the sorted order it was dealt in.
          for (final s in shards) {
            expect(s, [...s]..sort());
          }
          // No shard is empty while there are at least as many files as shards.
          if (n >= total) {
            expect(shards.every((s) => s.isNotEmpty), isTrue);
          }
        });
      }
    }

    test('deterministic: the same input twice gives the same shards', () {
      final all = _files(50);
      expect(shardFiles(all, 3, 4), shardFiles(all, 3, 4));
    });

    test('argument validation: shard and total are range-checked', () {
      final all = _files(10);
      expect(() => shardFiles(all, 0, 4), throwsArgumentError);
      expect(() => shardFiles(all, 5, 4), throwsArgumentError);
      expect(() => shardFiles(all, -1, 4), throwsArgumentError);
      expect(() => shardFiles(all, 1, 0), throwsArgumentError);
      expect(() => shardFiles(all, 1, -3), throwsArgumentError);
      // The boundaries themselves are valid.
      expect(shardFiles(all, 1, 4), isNotEmpty);
      expect(shardFiles(all, 4, 4), isNotEmpty);
    });
  });

  group('sortedTestFiles — the list the partition is defined over', () {
    test('keeps only *_test.dart, normalises separators, de-duplicates, sorts', () {
      final got = sortedTestFiles([
        'test/b/z_test.dart',
        r'test\b\a_test.dart', // Windows spelling of the same family
        'test/b/a_test.dart', // duplicate of the line above after normalising
        'test/helpers/spawn.dart', // not a test
        'test/notes_test.dart.bak', // not a test either
        'test/README.md',
        'test/A_test.dart',
      ]);
      expect(got, ['test/A_test.dart', 'test/b/a_test.dart', 'test/b/z_test.dart']);
    });

    test('order is by UTF-16 code unit, not locale: uppercase sorts before lowercase', () {
      expect(sortedTestFiles(['test/b_test.dart', 'test/B_test.dart']),
          ['test/B_test.dart', 'test/b_test.dart'],
          reason: 'a locale-aware sort would differ between the Windows and Linux machines '
              'and move files between shards');
    });

    test('input order does not matter (shuffled input -> identical shards)', () {
      final base = _files(60);
      final shuffled = [...base]..shuffle(Random(7));
      expect(sortedTestFiles(shuffled), sortedTestFiles(base));
      for (var s = 1; s <= 4; s++) {
        expect(shardFiles(sortedTestFiles(shuffled), s, 4), shardFiles(sortedTestFiles(base), s, 4));
      }
    });
  });

  group('shell safety — the workflow passes the list through UNQUOTED expansion', () {
    test('accepts the paths this repo uses', () {
      for (final p in [
        'test/contracts/a_test.dart',
        'test/sync/x_y_2_test.dart',
        'test/goldens/wardroom/btn_test.dart',
        'test/a+b/c-d_test.dart',
        'test/v1.2/e_test.dart',
      ]) {
        expect(isShellSafeTestPath(p), isTrue, reason: p);
      }
    });

    test('refuses everything that unquoted expansion would split, glob or reinterpret', () {
      for (final p in [
        'test/has space_test.dart',
        'test/a*_test.dart',
        'test/a?_test.dart',
        'test/a[1]_test.dart',
        r'test/a$b_test.dart',
        'test/a;b_test.dart',
        "test/a'b_test.dart",
        'test/a"b_test.dart',
        'test/a`b_test.dart',
        'test/a&b_test.dart',
        'test/a|b_test.dart',
        'test/é_test.dart',
        '-rf/a_test.dart', // would be read as an option
        'lib/a_test.dart', // not under test/
        '',
      ]) {
        expect(isShellSafeTestPath(p), isFalse, reason: 'must refuse "$p"');
      }
      expect(unsafeTestPaths(['test/ok_test.dart', 'test/no good_test.dart']), ['test/no good_test.dart']);
    });
  });

  group('the REAL test/ tree', () {
    late List<String> all;
    setUpAll(() => all = discoverTestFiles());

    test('is found, rooted at test/, and includes this very file', () {
      expect(all, isNotEmpty);
      expect(all.every((p) => p.startsWith('test/')), isTrue);
      expect(all, contains('test/scripts/ci_test_partition_test.dart'));
      expect(all, equals(sortedTestFiles(all)), reason: 'discovery returns the canonical sorted list');
    });

    test('goldens are IN the list (they are excluded at run time by --exclude-tags, not here)', () {
      expect(all.any((p) => p.startsWith('test/goldens/')), isTrue,
          reason: 'the list must not depend on the platform; the tag filter does the exclusion');
    });

    test('MIRROR: every real test path is safe for unquoted expansion', () {
      expect(unsafeTestPaths(all), isEmpty,
          reason: 'a test file whose path contains a space or glob character would be split or '
              'expanded by the shell in the CI step and silently run the wrong files. Rename it.');
    });

    test('INDEPENDENT ORACLE: discovery equals git\'s own listing of test/ (tracked + untracked)', () {
      // Every other assertion in this group compares discoverTestFiles() with itself or with
      // a property of its own output. This one asks a different program: git enumerates the
      // index plus the untracked files (ignore rules NOT applied, so a stray ignored file is
      // counted exactly as the directory walk counts it) and the set must be identical.
      final r = runSpawn('git', ['ls-files', '-z', '--cached', '--others', '--', 'test'],
          why: 'independent listing of the real test/ tree');
      expect(r.exitCode, 0, reason: 'git must be able to list the tree this test runs in');
      final fromGit = {
        for (final p in (r.stdout as String).split('\u0000'))
          if (p.endsWith('_test.dart') && FileSystemEntity.isFileSync(p)) p,
      };
      expect(fromGit, isNotEmpty);
      expect(all.toSet(), fromGit,
          reason: 'a test file one side lists and the other does not runs in no shard (or in the '
              'wrong set) while every job is green');
    });

    for (final total in [2, 3, 4, 5, 8]) {
      test('the real tree split $total ways: disjoint, complete, none empty, within one file', () {
        final shards = [for (var s = 1; s <= total; s++) shardFiles(all, s, total)];
        expect(shards.expand((x) => x).toSet(), all.toSet());
        expect(shards.fold<int>(0, (a, s) => a + s.length), all.length);
        expect(shards.every((s) => s.isNotEmpty), isTrue);
        final sizes = shards.map((s) => s.length);
        expect(sizes.reduce(max) - sizes.reduce(min), lessThanOrEqualTo(1));
      });
    }
  });

  group('discoverTestFiles — mirrors flutter_tools _findTests', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ci_partition_disc_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best effort on Windows file locks */}
    });

    test('finds nested *_test.dart under any directory name, ignores other files, prefixes test/', () {
      Directory('${tmp.path}/t/a/b').createSync(recursive: true);
      for (final f in ['t/x_test.dart', 't/a/y_test.dart', 't/a/b/z_test.dart', 't/helper.dart', 't/a/notes.md']) {
        File('${tmp.path}/$f').writeAsStringSync('// $f\n');
      }
      expect(discoverTestFiles(Directory('${tmp.path}/t')),
          ['test/a/b/z_test.dart', 'test/a/y_test.dart', 'test/x_test.dart']);
    });

    test('a missing directory is an empty list, not an exception', () {
      expect(discoverTestFiles(Directory('${tmp.path}/nope')), isEmpty);
    });

    test('a symlink to a test file is counted, as `flutter test` counts it', () {
      // flutter_tools _findTests keeps `path.endsWith('_test.dart') && isFileSync(path)`
      // and lists with followLinks:false, so a LINK to a file is a test file. A
      // `e is File` check drops it from every shard and the test runs nowhere.
      Directory('${tmp.path}/t').createSync(recursive: true);
      File('${tmp.path}/real_test.dart').writeAsStringSync('//\n');
      try {
        Link('${tmp.path}/t/linked_test.dart').createSync('${tmp.path}/real_test.dart');
      } on FileSystemException {
        markTestSkipped('symlinks cannot be created here (Windows without developer mode)');
        return;
      }
      expect(discoverTestFiles(Directory('${tmp.path}/t')), ['test/linked_test.dart']);
    });

    test('a directory named *_test.dart is not a test file', () {
      Directory('${tmp.path}/t/looks_like_test.dart').createSync(recursive: true);
      File('${tmp.path}/t/real_test.dart').writeAsStringSync('//\n');
      expect(discoverTestFiles(Directory('${tmp.path}/t')), ['test/real_test.dart']);
    });

    test('only the exact suffix `_test.dart` counts: contest.dart and mytest.dart are not tests', () {
      // `flutter test` keeps `path.endsWith('_test.dart')`. The underscore matters: a suffix
      // of `test.dart` alone would also pick up `contest.dart` / `latest.dart` helpers, which
      // `flutter test` would then be asked to run as test files in some shard.
      Directory('${tmp.path}/t').createSync(recursive: true);
      for (final f in ['contest.dart', 'mytest.dart', 'latest.dart', 'test.dart', '_test.dart', 'real_test.dart']) {
        File('${tmp.path}/t/$f').writeAsStringSync('//\n');
      }
      expect(discoverTestFiles(Directory('${tmp.path}/t')), ['test/_test.dart', 'test/real_test.dart'],
          reason: '`_test.dart` itself ends with the suffix, as it does for flutter_tools');
    });

    test('a symlinked DIRECTORY is not traversed (followLinks: false, as flutter_tools lists)', () {
      // flutter_tools `_findTests` lists with followLinks:false, so a test file that is only
      // reachable THROUGH a directory link is not a test `flutter test test/` runs. Following
      // links here would put it in a shard, and (with a link cycle) never terminate.
      Directory('${tmp.path}/outside').createSync(recursive: true);
      File('${tmp.path}/outside/inner_test.dart').writeAsStringSync('//\n');
      Directory('${tmp.path}/t').createSync(recursive: true);
      File('${tmp.path}/t/real_test.dart').writeAsStringSync('//\n');
      try {
        Link('${tmp.path}/t/linkdir').createSync('${tmp.path}/outside');
      } on FileSystemException {
        markTestSkipped('symlinks cannot be created here (Windows without developer mode)');
        return;
      }
      expect(discoverTestFiles(Directory('${tmp.path}/t')), ['test/real_test.dart']);
    });
  });

  group('the CLI, run for real in a throwaway tree', () {
    final script = File('scripts/ci_test_partition.dart').absolute.path;
    late Directory tmp;

    ProcessResult run(List<String> args, {Directory? cwd}) => runSpawn(dartBin(), [script, ...args],
        why: 'ci_test_partition ${args.join(' ')}', workingDirectory: (cwd ?? tmp).path);

    void touch(String rel) {
      final f = File('${tmp.path}/$rel')..createSync(recursive: true);
      f.writeAsStringSync('// $rel\n');
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('ci_partition_cli_');
      for (final f in ['a_test.dart', 'b/c_test.dart', 'b/d_test.dart', 'e_test.dart']) {
        touch('test/$f');
      }
      touch('test/helper.dart');
    });
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best effort on Windows file locks */}
    });

    List<String> lines(ProcessResult r) =>
        (r.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    test('prints each shard\'s whole files, one per line, sorted, and nothing else', () {
      // sorted: a, b/c, b/d, e  ->  shard 1 of 2 = {a, b/d}, shard 2 of 2 = {b/c, e}
      final one = run(['1', '2']);
      final two = run(['2', '2']);
      expect(one.exitCode, 0);
      expect(two.exitCode, 0);
      expect(lines(one), ['test/a_test.dart', 'test/b/d_test.dart']);
      expect(lines(two), ['test/b/c_test.dart', 'test/e_test.dart']);
      expect((one.stderr as String).trim(), isEmpty);
    });

    test('1 of 1 prints every test file (the unsharded case)', () {
      expect(lines(run(['1', '1'])),
          ['test/a_test.dart', 'test/b/c_test.dart', 'test/b/d_test.dart', 'test/e_test.dart']);
    });

    for (final bad in [
      <String>[],
      ['1'],
      ['1', '2', '3'],
      ['x', 'y'],
      ['0', '2'],
      ['3', '2'],
      ['1', '0'],
      ['-1', '2'],
      ['1.5', '2'],
    ]) {
      test('usage error (exit 64, NOTHING on stdout): ${bad.isEmpty ? '<no args>' : bad.join(' ')}', () {
        final r = run(bad);
        expect(r.exitCode, 64);
        expect((r.stdout as String).trim(), isEmpty,
            reason: 'a caller that ignores the exit status must still not receive a file list');
        expect((r.stderr as String).trim(), isNotEmpty);
      });
    }

    test('an EMPTY shard is refused (exit 3), never printed as an empty list', () {
      // 4 test files, 5 shards: shard 5 is empty.
      final r = run(['5', '5']);
      expect(r.exitCode, 3);
      expect((r.stdout as String).trim(), isEmpty);
      expect(r.stderr as String, contains('EMPTY'));
    });

    test('no test/ directory is refused (exit 4) — wrong working directory', () {
      final empty = Directory.systemTemp.createTempSync('ci_partition_empty_');
      addTearDown(() {
        try {
          empty.deleteSync(recursive: true);
        } catch (_) {}
      });
      final r = run(['1', '2'], cwd: empty);
      expect(r.exitCode, 4);
      expect((r.stdout as String).trim(), isEmpty);
    });

    test('a path unsafe for unquoted expansion is refused (exit 2), listing it', () {
      touch('test/has space_test.dart');
      final r = run(['1', '2']);
      expect(r.exitCode, 2);
      expect((r.stdout as String).trim(), isEmpty,
          reason: 'the unsafe path must not be handed to `flutter test \$FILES`');
      expect(r.stderr as String, contains('has space_test.dart'));
    });
  });
}
