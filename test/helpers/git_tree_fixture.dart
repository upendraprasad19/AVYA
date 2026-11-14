// test/helpers/git_tree_fixture.dart
//
// Fixtures for tests that need a commit holding a file NAME that the porcelain cannot
// create: a control character or line terminator in a name (NTFS cannot hold one, and git for
// Windows refuses it in `update-index`: "Invalid path"), or a name whose bytes are not valid
// UTF-8 at all. `git mktree -z` stores any name, so the tree is built from raw records and the
// commit is made with `commit-tree`; the index and the working tree are never touched.
//
// Shared by test/scripts/gate_input_family_e2e_test.dart and
// test/scripts/version_bump_git_lib_test.dart (OI-275 batch B2 - the B-pass asked for the
// invalid-UTF-8 case in both, which is why these stopped being private to one file).
//
// A "latin-1 name" below is a Dart string in which EVERY CHAR IS ONE RAW BYTE of the path -
// the only way to carry arbitrary bytes through a `String`. [latin1Name] makes one from an
// ordinary (UTF-8) name; for a name that must stay invalid UTF-8, write it directly
// (`'docs/ÿþ.md'` is the two bytes FF FE) and pass `rawNames: true`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'spawn.dart';

ProcessResult _git(String repo, List<String> args, {Encoding? stdoutEncoding}) => runSpawn('git', args,
    why: 'git_tree_fixture: git ${args.join(' ')}',
    workingDirectory: repo,
    stdoutEncoding: stdoutEncoding ?? systemEncoding);

/// `git mktree -z` over [records] (`mode type sha<TAB>name`, each char one raw name BYTE, so a
/// name is [latin1Name]d first). The input goes through a file and an `sh -c` redirect because the
/// spawn helper has no stdin and `runInShell` single-quotes every argument on POSIX (a bare `<`
/// would reach git as a word); the file lives in the repo under a relative name.
String mktree(String repo, List<String> records) {
  File('$repo/.rec').writeAsBytesSync(latin1.encode(records.map((r) => '$r\u0000').join()));
  final r = runSpawn('sh', ['-c', 'git mktree -z < .rec'],
      why: 'git_tree_fixture: mktree', workingDirectory: repo);
  File('$repo/.rec').deleteSync();
  expect(r.exitCode, 0, reason: 'setup: mktree: ${r.stdout}${r.stderr}');
  return (r.stdout as String).trim();
}

/// [name] as the Latin-1 string that carries its UTF-8 bytes, the form [mktree] takes.
String latin1Name(String name) => String.fromCharCodes(utf8.encode(name));

/// [base] (a tree sha, or null for an empty one) with `[segs]` added as a file, merged into the
/// directories that already exist. With [rawNames] the segments are ALREADY latin-1 byte strings
/// (see the header) and are not re-encoded.
String treeWith(String repo, String? base, List<String> segs, String blob, {bool rawNames = false}) {
  final entries = base == null
      ? <String>[]
      : (_git(repo, ['ls-tree', '-z', base], stdoutEncoding: latin1).stdout as String)
          .split('\u0000')
          .where((e) => e.isNotEmpty)
          .toList();
  final name = rawNames ? segs.first : latin1Name(segs.first);
  String? child;
  entries.removeWhere((e) {
    final tab = e.indexOf('\t');
    if (e.substring(tab + 1) != name) return false;
    final f = e.substring(0, tab).split(' ');
    if (segs.length > 1 && f[1] == 'tree') child = f[2];
    return true;
  });
  entries.add(segs.length == 1
      ? '100644 blob $blob\t$name'
      : '040000 tree ${treeWith(repo, child, segs.sublist(1), blob, rawNames: rawNames)}\t$name');
  return mktree(repo, entries);
}

/// Commits a new file at [path] on top of HEAD without touching the index or the working tree,
/// and returns the new commit's sha. Asserts the commit really carries exactly that path (compared
/// as raw bytes, so a path that is not valid UTF-8 is checked too).
///
/// [rawNames]: [path] is a latin-1 byte string (see the header), not an ordinary UTF-8 name.
String commitFileNamed(String repo, String path, String message, {bool rawNames = false}) {
  String head() => (_git(repo, ['rev-parse', 'HEAD']).stdout as String).trim();
  final before = head();
  File('$repo/.payload').writeAsStringSync('// x\n');
  final blob = (_git(repo, ['hash-object', '-w', '.payload']).stdout as String).trim();
  File('$repo/.payload').deleteSync();
  final root = (_git(repo, ['rev-parse', 'HEAD:']).stdout as String).trim();
  final tree = treeWith(repo, root, path.split('/'), blob, rawNames: rawNames);
  final commit = (_git(repo, ['commit-tree', tree, '-p', before, '-m', message]).stdout as String).trim();
  _git(repo, ['update-ref', 'HEAD', commit]);
  final changed = _git(repo, ['diff', '--no-renames', '--name-only', '-z', '$before..$commit'], stdoutEncoding: latin1);
  expect(changed.stdout, '${rawNames ? path : latin1Name(path)}\u0000',
      reason: 'setup: the commit must change exactly the intended path');
  return commit;
}
