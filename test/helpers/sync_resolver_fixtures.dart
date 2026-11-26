// test/helpers/sync_resolver_fixtures.dart
//
// Shared fixtures for the record-aware resolver tests (landing C2, docs/plans/sync-resolver.md):
// a REAL `git merge-file` as the text merge, a scripted fake that records its calls, and the record
// builders for the synthetic files. Marker lines are built from repeated characters (the marker gate
// flags a literal in its own source).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/sync_resolver_lib.dart';
import 'spawn.dart';

final String kOpen = '<' * 7;
final String kMid = '=' * 7;
final String kClose = '>' * 7;
final String kBaseMark = '|' * 7;

/// `git merge-file -p --diff3 -L HEAD -L base -L origin/main` on three temp files (what the CLI injects).
({String text, bool conflicted}) realMerge(String base, String ours, String theirs) {
  final d = Directory.systemTemp.createTempSync('sync_merge_');
  try {
    File('${d.path}/o').writeAsStringSync(ours);
    File('${d.path}/b').writeAsStringSync(base);
    File('${d.path}/t').writeAsStringSync(theirs);
    final r = runSpawn(
      'git',
      ['merge-file', '-p', '--diff3', '-L', 'HEAD', '-L', 'base', '-L', 'origin/main', '${d.path}/o', '${d.path}/b', '${d.path}/t'],
      why: 'sync_resolver_fixtures: git merge-file',
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (r.exitCode < 0 || r.exitCode > 127) throw Unresolvable('merge-file exit ${r.exitCode}');
    return (text: utf8.decode(r.stdout as List<int>), conflicted: r.exitCode != 0);
  } finally {
    d.deleteSync(recursive: true);
  }
}

/// A text merge that records its calls and answers from a script; an unscripted call fails the test.
class FakeMerge {
  FakeMerge([List<({String text, bool conflicted})> script = const []]) : _script = List.of(script);

  final List<({String text, bool conflicted})> _script;
  final List<({String base, String ours, String theirs})> calls = [];

  ({String text, bool conflicted}) call(String base, String ours, String theirs) {
    calls.add((base: base, ours: ours, theirs: theirs));
    if (_script.isEmpty) fail('unexpected text merge #${calls.length}: base=${_q(base)} ours=${_q(ours)} theirs=${_q(theirs)}');
    return _script.removeAt(0);
  }

  TextMerge get fn => call;

  static String _q(String s) => s.length > 80 ? '${s.substring(0, 80)}...' : s;
}

/// A merge that must never be called (the decision table settles the case).
TextMerge noMerge() => FakeMerge().fn;

/// A conflicted answer shaped like git's diff3 output for one record.
({String text, bool conflicted}) conflictOf(String ours, String base, String theirs) => (
      text: '$kOpen HEAD\n$ours$kBaseMark base\n$base$kMid\n$theirs$kClose origin/main\n',
      conflicted: true,
    );

FileSpec specOf(String path) {
  final s = specFor(path);
  if (s == null) fail('no spec for $path');
  return s;
}

// ---- synthetic files ---------------------------------------------------------------------------------

/// One OI-board record, blank-line terminated.
String oi(int n, {String title = 'probe', String body = '- **Status**: OPEN'}) => '## OI-$n — $title\n\n$body\n\n';

String board(List<String> records, {String head = '# Board\n\n'}) => '$head${records.join()}';

String bugClass(String id, {String body = 'body'}) => '### $id probe\n\n$body\n\n';

String ledgerRec(String name, {String body = '  mutation_proven: true'}) => '$name.dart:\n$body\n\n';

String registryRec(String concept, {String comment = '', String body = '    writer: x'}) =>
    '$comment  - concept: $concept\n$body\n\n';

String migrationEl(String id, {String extra = ''}) => '  {\n    "migration": "$id"$extra\n  }';

String migrations(List<String> els) => '[\n${els.join(',\n')}\n]\n';

String glossaryRow(String term, {String def = 'a definition'}) => '| **$term** | $def |\n';

String glossary(List<String> rows, {String before = '', String after = '\nnext prose\n'}) =>
    '$before## 8. Reserved domain glossary\n\nintro prose\n\n| Term | Meaning |\n|---|---|\n${rows.join()}$after';

String skillMd({List<String> rows = const [], List<String> changelog = const []}) =>
    '# Debugging\n\n### Bug-class index\n\n| ID | Name |\n|---|---|\n${rows.join()}\nprose after the table\n\n## Changelog\n\n${changelog.join()}';

String skillRow(String id) => '| $id | name $id |\n';

String bullet(String lead, {String text = 'text'}) => '- **$lead** $text\n';

/// Keys of every record of every region of [text] under [spec], in order.
List<String> keysOf(FileSpec spec, String text) => [
      for (final p in parseFile(text, spec.regions))
        if (p is RegionPiece)
          for (final r in p.records) r.key,
    ];
