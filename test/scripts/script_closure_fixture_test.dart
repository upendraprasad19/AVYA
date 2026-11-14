// test/scripts/script_closure_fixture_test.dart
//
// Controls for test/helpers/script_closure_fixture.dart, the one way a fixture copies a repo
// script into a throwaway repo (landing A2 of the merge-conflict-treadmill plan).
//
// Two halves:
//   1. the helper itself, on a SYNTHETIC import chain and on the REAL builders;
//   2. a source scan: no test file may list an index builder in a hand-written COPY LIST. A
//      copy list is a list literal naming two or more `scripts/` paths; the only list that may
//      name a builder is the argument of `copyScriptClosure(` / `scriptImportClosure(`. A spawn
//      argument list (`['run', 'scripts/build_oi_index.dart']`) names one script and is fine.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/script_closure_fixture.dart';

/// Builder entry points whose files must reach a fixture only through the closure helper.
const _builderNames = <String>[
  'build_oi_index.dart',
  'build_bug_index.dart',
  'build_local_indexes.dart',
];

/// Every list literal in [source] that names an index builder AND at least one other
/// `scripts/` path (the shape of a copy list) and is NOT directly an argument of
/// `copyScriptClosure(` / `scriptImportClosure(`. Returns one `line N: <text>` per violation.
///
/// A small scanner, not a regex over the whole file: it skips comments and string contents
/// when matching brackets, and tracks the call that encloses each `[`.
List<String> literalBuilderCopyLists(String source) {
  final violations = <String>[];
  final stack = <_Frame>[]; // open (, [ and { with what precedes them
  var line = 1;
  var i = 0;
  String? idBefore() {
    var j = i - 1;
    while (j >= 0 && (source[j] == ' ' || source[j] == '\n' || source[j] == '\t')) {
      j--;
    }
    final end = j + 1;
    while (j >= 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(source[j])) {
      j--;
    }
    return end > j + 1 ? source.substring(j + 1, end) : null;
  }

  while (i < source.length) {
    final c = source[i];
    if (c == '\n') {
      line++;
      i++;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      i += 2;
      while (i + 1 < source.length && !(source[i] == '*' && source[i + 1] == '/')) {
        if (source[i] == '\n') line++;
        i++;
      }
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final triple = source.startsWith(c * 3, i);
      final q = triple ? c * 3 : c;
      final start = i;
      i += q.length;
      while (i < source.length && !source.startsWith(q, i)) {
        if (source[i] == r'\' && !triple) i++;
        if (i < source.length && source[i] == '\n') line++;
        i++;
      }
      i += q.length;
      // Attribute the string to the innermost open list so its content can be inspected.
      if (stack.isNotEmpty && stack.last.open == '[') {
        stack.last.text.write(source.substring(start, i < source.length ? i : source.length));
        stack.last.text.write('\n');
      }
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      stack.add(_Frame(c, idBefore(), line));
      i++;
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      if (stack.isNotEmpty) {
        final f = stack.removeLast();
        if (f.open == '[') {
          final text = f.text.toString();
          final scriptPaths = RegExp(r'''["']scripts/[A-Za-z0-9_./-]+["']''')
              .allMatches(text)
              .map((m) => m.group(0)!)
              .toSet();
          final namesBuilder = _builderNames.any(text.contains);
          final parentCall = stack.isNotEmpty && stack.last.open == '(' ? stack.last.before : null;
          final allowed =
              parentCall == 'copyScriptClosure' || parentCall == 'scriptImportClosure';
          if (namesBuilder && scriptPaths.length >= 2 && !allowed) {
            violations.add('line ${f.line}: ${scriptPaths.join(', ')}');
          }
        }
      }
      i++;
      continue;
    }
    i++;
  }
  return violations;
}

class _Frame {
  _Frame(this.open, this.before, this.line);
  final String open;
  final String? before;
  final int line;
  final StringBuffer text = StringBuffer();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('closure_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  void write(String rel, String body) {
    final f = File('${tmp.path}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(body);
  }

  group('scriptImportClosure on a synthetic tree', () {
    test('follows relative imports transitively, across directories and through `..`', () {
      write('scripts/a.dart', "import 'b.dart';\nvoid main() {}\n");
      write('scripts/b.dart', "import '../lib/c.dart' show c;\nexport 'd.dart';\n");
      write('lib/c.dart', "import '../scripts/e.dart';\n");
      write('scripts/d.dart', '// leaf\n');
      write('scripts/e.dart', '// leaf\n');
      write('scripts/unrelated.dart', '// not imported\n');
      expect(scriptImportClosure(tmp.path, ['scripts/a.dart']), [
        'lib/c.dart',
        'scripts/a.dart',
        'scripts/b.dart',
        'scripts/d.dart',
        'scripts/e.dart',
      ]);
    });

    test('a cycle terminates and a `dart:` import is skipped', () {
      write('scripts/a.dart', "import 'dart:io';\nimport 'b.dart';\n");
      write('scripts/b.dart', "import 'a.dart';\n");
      expect(scriptImportClosure(tmp.path, ['scripts/a.dart']),
          ['scripts/a.dart', 'scripts/b.dart']);
    });

    test('an import inside a comment is NOT followed', () {
      write('scripts/a.dart', "// import 'ghost.dart';\n/// import 'ghost2.dart';\nvoid main() {}\n");
      expect(scriptImportClosure(tmp.path, ['scripts/a.dart']), ['scripts/a.dart']);
    });

    test('`part` and `part of` directives are followed', () {
      write('scripts/a.dart', "part 'a_part.dart';\n");
      write('scripts/a_part.dart', "part of 'a.dart';\n");
      expect(scriptImportClosure(tmp.path, ['scripts/a.dart']),
          ['scripts/a.dart', 'scripts/a_part.dart']);
    });

    test('a non-Dart entry is just itself, and several entries are unioned', () {
      write('scripts/hook.sh', "echo '#!/bin/sh import x.dart'\n");
      write('scripts/a.dart', "import 'b.dart';\n");
      write('scripts/b.dart', '\n');
      expect(scriptImportClosure(tmp.path, ['scripts/hook.sh', 'scripts/a.dart']),
          ['scripts/a.dart', 'scripts/b.dart', 'scripts/hook.sh']);
    });

    test('a package: import throws, naming the file and the import', () {
      write('scripts/a.dart', "import 'package:crypto/crypto.dart';\n");
      expect(
          () => scriptImportClosure(tmp.path, ['scripts/a.dart']),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              allOf(contains('scripts/a.dart'), contains('package:crypto')))));
    });

    test('an import of a file that does not exist throws instead of being skipped', () {
      write('scripts/a.dart', "import 'missing.dart';\n");
      expect(
          () => scriptImportClosure(tmp.path, ['scripts/a.dart']),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('scripts/missing.dart'))));
    });

    test('a path that climbs out of the repo throws', () {
      write('a.dart', "import '../outside.dart';\n");
      expect(() => scriptImportClosure(tmp.path, ['a.dart']),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('climbs out'))));
    });
  });

  test('copyScriptClosure preserves layout and content, and returns what it copied', () {
    final src = Directory('${tmp.path}/src')..createSync();
    final dst = Directory('${tmp.path}/dst')..createSync();
    File('${src.path}/scripts/a.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync("import 'sub/b.dart';\n// payload\n");
    File('${src.path}/scripts/sub/b.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('// b\n');
    final copied = copyScriptClosure(src.path, dst.path, ['scripts/a.dart']);
    expect(copied, ['scripts/a.dart', 'scripts/sub/b.dart']);
    expect(File('${dst.path}/scripts/a.dart').readAsStringSync(),
        "import 'sub/b.dart';\n// payload\n");
    expect(File('${dst.path}/scripts/sub/b.dart').readAsStringSync(), '// b\n');
  });

  group('the REAL builders', () {
    final repoRoot = Directory.current.path;

    test('build_oi_index.dart pulls in the shared lib and the sha256 helper it imports', () {
      final c = scriptImportClosure(repoRoot, ['scripts/build_oi_index.dart']);
      expect(c, containsAll([
        'scripts/build_oi_index.dart',
        'scripts/local_indexes_lib.dart',
        'scripts/migration_ledger_hash_lib.dart',
      ]));
    });

    test('build_bug_index.dart pulls in bug_index_lib.dart as well', () {
      final c = scriptImportClosure(repoRoot, ['scripts/build_bug_index.dart']);
      expect(c, containsAll([
        'scripts/build_bug_index.dart',
        'scripts/bug_index_lib.dart',
        'scripts/local_indexes_lib.dart',
        'scripts/migration_ledger_hash_lib.dart',
      ]));
    });

    test('the orchestrator pulls in BOTH builders (transitive, two levels)', () {
      final c = scriptImportClosure(repoRoot, ['scripts/build_local_indexes.dart']);
      expect(c, containsAll([
        'scripts/build_oi_index.dart',
        'scripts/build_bug_index.dart',
        'scripts/bug_index_lib.dart',
        'scripts/local_indexes_lib.dart',
      ]));
    });
  });

  group('the copy-list scanner', () {
    test('flags the OLD shape: a for-in over a literal list naming a builder and another script', () {
      const old = '''
    for (final f in const [
      'scripts/pre-commit.sh',
      'scripts/build_oi_index.dart',
      'scripts/build_bug_index.dart',
      'scripts/bug_index_lib.dart',
    ]) {
      File('\$repoRoot/\$f').copySync('\$work/\$f');
    }
''';
      expect(literalBuilderCopyLists(old), hasLength(1));
    });

    test('flags a list assigned to a variable first', () {
      const src = "final files = ['scripts/_dart_bin.sh', 'scripts/build_oi_index.dart'];\n";
      expect(literalBuilderCopyLists(src), hasLength(1));
    });

    test('allows the list that is an argument of copyScriptClosure / scriptImportClosure', () {
      const src = '''
copyScriptClosure(repoRoot, work, const [
  'scripts/pre-commit.sh',
  'scripts/build_oi_index.dart',
]);
final c = scriptImportClosure(repoRoot, ['scripts/build_oi_index.dart', 'scripts/x.sh']);
''';
      expect(literalBuilderCopyLists(src), isEmpty);
    });

    test('allows a spawn argument list that names ONE script', () {
      const src = "_run(dart, ['run', 'scripts/build_oi_index.dart', '--lenient'], work);\n";
      expect(literalBuilderCopyLists(src), isEmpty);
    });

    test('ignores a list that names two scripts but no builder', () {
      const src = "const x = ['scripts/pre-commit.sh', 'scripts/_dart_bin.sh'];\n";
      expect(literalBuilderCopyLists(src), isEmpty);
    });

    test('ignores comments and strings that merely contain brackets', () {
      const src = '''
// ['scripts/pre-commit.sh', 'scripts/build_oi_index.dart']
/* ['scripts/pre-commit.sh', 'scripts/build_oi_index.dart'] */
const s = "['scripts/pre-commit.sh', 'scripts/build_oi_index.dart']";
''';
      expect(literalBuilderCopyLists(src), isEmpty);
    });

    test('a list nested in an unrelated call is NOT excused by an earlier closure call', () {
      const src = '''
copyScriptClosure(repoRoot, work, ['scripts/pre-commit.sh']);
other(const ['scripts/pre-commit.sh', 'scripts/build_oi_index.dart']);
''';
      expect(literalBuilderCopyLists(src), hasLength(1));
    });
  });

  test('no test file hand-lists an index builder in a copy list', () {
    final offenders = <String>[];
    for (final e in Directory('test').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final p = e.path.replaceAll('\\', '/');
      // This file's own fixtures of the OLD shape, and the helper's.
      if (p.endsWith('test/scripts/script_closure_fixture_test.dart') ||
          p.endsWith('test/helpers/script_closure_fixture.dart')) {
        continue;
      }
      for (final v in literalBuilderCopyLists(e.readAsStringSync())) {
        offenders.add('$p $v');
      }
    }
    expect(offenders, isEmpty,
        reason: 'A fixture must copy a builder through copyScriptClosure(repoRoot, work, [...]) '
            '(test/helpers/script_closure_fixture.dart), never a hand-written list: the next '
            'import a builder gains would fail it far from the cause.');
  });
}
