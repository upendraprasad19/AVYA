@Timeout(Duration(minutes: 8))
library;

// test/scripts/merge_scope_git_fuzz_test.dart
//
// S13 of docs/plans/sync-merge-scope.md section 5: a seeded fuzz of REAL branch syncs.
// Both sides apply random edits, deletes, renames, rename+edits, adds, mode changes, symlinks and
// directory renames; the merge runs plain, `-X ours` or `-X theirs`; the human resolves each
// unmerged path at random (take ours, take theirs, accept git's text, delete) and sometimes edits a
// staged file. Three oracles, each computed from `ls-files -s` and `ls-tree -r` and NOT from the lib:
//
//   1. soundness: every staged path outside the graded set has an index entry equal to HEAD's or to
//      the tip's at that path;
//   2. new bytes: every index blob whose object id exists at NO path of HEAD's or the tip's tree is
//      graded (the oracle that catches a rename-aware rule: a relocated file is byte-identical to a
//      blob that exists elsewhere, and a NEW byte sequence is never allowed to hide);
//   3. exact equality with an independent reimplementation of the rule (the over-grading oracle: the
//      old behavior, grading everything, satisfies 1 and 2).
//
// Chunked so each test names its seeds and stays well under the timeout.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/merge_scope_lib.dart';
import '../helpers/merge_scope_repo.dart';
import '../helpers/spawn.dart';

const List<String> _dirs = <String>[
  'docs',
  'lib',
  'supabase/functions/verify-payment',
  'supabase/functions/rolling-context',
  'pkg/a',
  'pkg/b',
];

String _content(Random rnd, String tag) => '${<String>[for (var i = 0; i < 8; i++) 'line $i of $tag ${rnd.nextInt(1000)}'].join('\n')}\n';

List<String> _tracked(ScopeRepo r) =>
    r.must(['ls-files']).split('\n').where((s) => s.isNotEmpty && !s.contains('link_')).toList();

void _ops(ScopeRepo r, Random rnd, int n, String tag) {
  for (var i = 0; i < n; i++) {
    final files = _tracked(r);
    if (files.isEmpty) return;
    // 60% of the operations hit one of three hot files, so both sides collide often
    final f = rnd.nextInt(10) < 6 ? files[rnd.nextInt(min(3, files.length))] : files[rnd.nextInt(files.length)];
    final dir = _dirs[rnd.nextInt(_dirs.length)];
    switch (rnd.nextInt(9)) {
      case 0: // edit one line
        final lines = File('${r.dir}/$f').readAsLinesSync();
        if (lines.isNotEmpty) lines[rnd.nextInt(lines.length)] = 'EDITED $tag ${rnd.nextInt(1000)}';
        r.write(f, '${lines.join('\n')}\n');
      case 1: // delete
        r.must(['rm', '-q', '-f', '--', f]);
      case 2: // rename
        final to = '$dir/${tag}_${i}_${f.split('/').last}';
        Directory('${r.dir}/$dir').createSync(recursive: true);
        r.must(['mv', '-f', f, to]);
      case 3: // rename + edit
        final to = '$dir/${tag}_${i}_${f.split('/').last}';
        Directory('${r.dir}/$dir').createSync(recursive: true);
        r.must(['mv', '-f', f, to]);
        final lines = File('${r.dir}/$to').readAsLinesSync();
        if (lines.isNotEmpty) lines[0] = 'RENAMED+EDITED $tag ${rnd.nextInt(1000)}';
        r.write(to, '${lines.join('\n')}\n');
      case 4: // add
        r.write('$dir/new_${tag}_$i.txt', _content(rnd, 'new_$tag'));
      case 5: // mode change
        if (!Platform.isWindows) {
          runSpawn('chmod', ['+x', '${r.dir}/$f'], why: 'fuzz: chmod +x');
        }
      case 6: // symlink
        if (!Platform.isWindows) {
          Link('${r.dir}/link_${tag}_$i').createSync('target_${rnd.nextInt(5)}');
        }
      case 7: // directory rename
        final src = f.contains('/') ? f.substring(0, f.lastIndexOf('/')) : null;
        if (src != null && Directory('${r.dir}/$src').existsSync()) {
          final to = '$dir/moved_${tag}_$i';
          Directory('${r.dir}/$dir').createSync(recursive: true);
          if (!Directory('${r.dir}/$to').existsSync()) r.git(['mv', src, to]);
        }
      case 8: // append
        final cur = File('${r.dir}/$f').readAsStringSync();
        r.write(f, '$cur// appended $tag ${rnd.nextInt(1000)}\n');
    }
  }
}

class _Result {
  _Result(this.conflicted, this.graded, this.staged);
  final bool conflicted;
  final int graded;
  final int staged;
}

_Result _scenario(int seed) {
  final rnd = Random(seed);
  final r = ScopeRepo.create(prefix: 'merge_scope_fuzz_');
  for (var i = 0; i < 12; i++) {
    r.write('${_dirs[i % _dirs.length]}/base_$i.txt', _content(rnd, 'base$i'));
  }
  r.commitAll('base');
  r.checkoutNew('feature');
  _ops(r, rnd, 1 + rnd.nextInt(4), 'f');
  r.commitAll('feature');
  r.checkout('main');
  _ops(r, rnd, 1 + rnd.nextInt(4), 'm');
  final main = r.commitAll('main');
  r.setOriginMain(main);
  r.checkout('feature');
  final strategy = rnd.nextInt(5);
  final merged = r.merge('refs/remotes/origin/main',
      extra: strategy == 0 ? const <String>['-X', 'ours'] : strategy == 1 ? const <String>['-X', 'theirs'] : const <String>[]);
  final conflicted = merged.exitCode != 0;
  expect(merged.exitCode, anyOf(0, 1), reason: 'seed $seed: merge: ${merged.stdout}${merged.stderr}');

  // the human resolves each unmerged path at random
  final unmerged = r
      .must(['ls-files', '-u'])
      .split('\n')
      .where((l) => l.isNotEmpty)
      .map((l) => l.substring(l.indexOf('\t') + 1))
      .toSet()
      .toList()
    ..sort();
  for (final p in unmerged) {
    switch (rnd.nextInt(4)) {
      case 0:
        r.git(['checkout', '--ours', '--', p]);
      case 1:
        r.git(['checkout', '--theirs', '--', p]);
      case 2:
        break; // accept git's text as it is
      case 3:
        r.git(['rm', '-q', '-f', '--', p]);
    }
    if (File('${r.dir}/$p').existsSync() || Link('${r.dir}/$p').existsSync()) {
      r.git(['add', '--', p]);
    } else {
      r.git(['rm', '-q', '--cached', '--ignore-unmatch', '--', p]);
    }
  }
  // paths git placed (renames, directory moves, ~HEAD leftovers) and the rest of the worktree
  r.stageAll();
  expect(r.must(['ls-files', '-u']), isEmpty, reason: 'seed $seed: unresolved entries remain');
  // sometimes the human edits a staged file
  if (rnd.nextInt(3) == 0) {
    final staged = r.stagedPaths().where((p) => File('${r.dir}/$p').existsSync()).toList();
    if (staged.isNotEmpty) {
      final p = staged[rnd.nextInt(staged.length)];
      final cur = File('${r.dir}/$p').readAsStringSync();
      r.write(p, '$cur// human edit\n');
      r.stage([p]);
    }
  }

  final scope = r.scope();
  final graded = gradedOf(scope);
  final gradedBytes = graded.map(byteString).toSet();

  final idx = indexEntries(r);
  final head = treeEntries(r, 'HEAD');
  final tip = treeEntries(r, 'refs/remotes/origin/main');
  final known = <String>{...blobIds(r, 'HEAD'), ...blobIds(r, 'refs/remotes/origin/main')};
  final stagedBytes = r.stagedPaths().map(byteString).toSet();

  // 1. soundness
  for (final p in stagedBytes.difference(gradedBytes)) {
    final e = idx[p];
    expect(e == head[p] || e == tip[p], isTrue, reason: 'seed $seed: $p is staged, not graded, and matches neither HEAD nor the tip');
  }
  // 2. new bytes
  for (final entry in idx.entries) {
    final parts = entry.value.split(' ');
    if (parts[0] == '160000') continue;
    if (!known.contains(parts[1])) {
      expect(gradedBytes, contains(entry.key), reason: 'seed $seed: ${entry.key} holds bytes no reviewed state holds but is not graded');
    }
  }
  // 3. exact equality with the independent reimplementation
  expect(gradedBytes, oracleGraded(r), reason: 'seed $seed: graded set differs from the oracle');
  expect(gradedBytes.difference(stagedBytes), isEmpty, reason: 'seed $seed: graded is not a subset of staged');
  return _Result(conflicted, graded.length, stagedBytes.length);
}

void main() {
  const chunks = <(int, int)>[(1, 20), (21, 40), (41, 60), (61, 80)];
  for (var c = 0; c < chunks.length; c++) {
    final (from, to) = chunks[c];
    test('S13 chunk ${c + 1}: seeds $from..$to hold all three oracles', () {
      var conflicts = 0;
      var nonEmpty = 0;
      var staged = 0;
      for (var seed = from; seed <= to; seed++) {
        final res = _scenario(seed);
        if (res.conflicted) conflicts++;
        if (res.graded > 0) nonEmpty++;
        staged += res.staged;
      }
      // The chunk must exercise the interesting shapes, or the oracles pass vacuously. Measured on git 2.43.0
      // (this VPS): 3-5 conflicted merges, 10-13 scenarios with graded paths and 56-79 staged paths per chunk;
      // the floors are lower so a different git version that resolves one more seed cleanly does not turn the
      // suite red, and high enough that an all-clean or all-empty chunk still does.
      final shape = 'conflicts=$conflicts withGraded=$nonEmpty staged=$staged of ${to - from + 1} seeds';
      expect(conflicts, greaterThanOrEqualTo(1), reason: 'too few conflicted merges to mean anything ($shape)');
      expect(nonEmpty, greaterThanOrEqualTo(5), reason: 'too few scenarios with graded paths ($shape)');
      expect(staged, greaterThan(20), reason: 'too few staged paths ($shape)');
    });
  }
}
