// test/contracts/plan_review_gate_harness_copies_imports_test.dart
//
// WHY THIS EXISTS (OI-275 batch B2). The CI keystone gate
// (scripts/check_plan_review_record_exists.dart) is exercised by e2e tests that COPY
// the script and its relative imports into a throwaway git repo and run it there. Those
// copy lists are hand-maintained string lists in three places. B2 gave the gate a new
// relative import (version_bump_git_lib.dart); a harness that forgets to copy it does
// not fail "obviously" - the spawned `dart` dies with a compile error, every gate
// assertion in that file reddens at once, and the first suspicion falls on the gate.
//
// So the property is pinned as a property: for EVERY harness, the copy list contains the
// gate and its whole TRANSITIVE closure of relative imports. The closure is computed from
// the source, not written down, so the next import the gate grows is caught here, by name,
// before it can break three e2e files. MIRROR direction: the lists must not name a script
// that no longer exists (a stale entry makes `copySync` throw at setup).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _gate = 'check_plan_review_record_exists.dart';

/// The relative `.dart` URIs named by the `import` / `export` / `part` directives in [source]
/// (`package:` and `dart:` URIs have a colon and never match).
///
/// A directive has many spellings, and a detector that knows only `import 'x.dart';` goes blind to the
/// rest (B-pass F3 of OI-275 batch B2: the first version, `^import '([^':]+\.dart)';`, missed
/// `import 'x.dart' as y;`, so a gate that grew a prefixed import would have broken three e2e files
/// without this test noticing): a prefix (`as`), a combinator (`show` / `hide`), `deferred`, double
/// quotes, `export`, `part`, a directive wrapped over several lines, and a CONDITIONAL import, which
/// names more than one file (`import 'a.dart' if (dart.library.io) 'b.dart';`). So the statement is
/// found first (up to its `;`) and EVERY quoted `.dart` URI inside it is taken.
Set<String> relativeImportsOf(String source) {
  final statement = RegExp(r'^[ \t]*(?:import|export|part)[ \t][^;]*;', multiLine: true);
  final uri = RegExp(r'''["']([^"':]+\.dart)["']''');
  return {
    for (final s in statement.allMatches(source))
      for (final u in uri.allMatches(s.group(0)!)) u.group(1)!,
  };
}

/// Relative imports of [file].
Set<String> _relativeImports(File file) => relativeImportsOf(file.readAsStringSync());

/// The gate plus everything it reaches through relative imports.
Set<String> _closure() {
  final seen = <String>{};
  final queue = <String>[_gate];
  while (queue.isNotEmpty) {
    final f = queue.removeLast();
    if (!seen.add(f)) continue;
    final file = File('scripts/$f');
    expect(file.existsSync(), isTrue, reason: 'scripts/$f is imported but does not exist');
    queue.addAll(_relativeImports(file));
  }
  return seen;
}

/// Every list literal `[ ... ]` in [path] that names the gate by its BARE file name - i.e. the
/// copy lists. Deliberately independent of how the list is spelled: the three known harnesses write
/// `for (final f in const [...])`, but a fourth written as `const _copy = [...]`, `final x = <String>[...]`
/// or `var y = [...]` must be found too (mutation HC4 survived the first version of this regex,
/// which required the text `const [`). `'scripts/check_...'` (a path, not a bare name) never matches.
/// Residue, stated: a list assembled with `add`/`addAll`, read from a file, or spelled with double
/// quotes is invisible to this (single quotes are the repo's style).
List<Set<String>> _copyLists(String path) => [
      for (final m in RegExp(r'\[([^\]]*)\]').allMatches(File(path).readAsStringSync()))
        if (m.group(1)!.contains("'$_gate'"))
          {for (final s in RegExp(r"'([^']+\.dart)'").allMatches(m.group(1)!)) s.group(1)!},
    ];

void main() {
  final harnesses = <String, int>{
    // path -> the number of copy lists it is known to contain (a vacuity floor: if a refactor
    // renames the list shape this test must fail, not pass over zero lists).
    'test/scripts/gate_input_family_e2e_test.dart': 2,
    'test/scripts/plan_review_record_gate_e2e_test.dart': 1,
  };

  group('the import detector itself (a spelling it misses is an import this test cannot see)', () {
    test('every spelling of a relative directive is found', () {
      const source = '''
import 'plain.dart';
import 'prefixed.dart' as p;
import 'shown.dart' show A, B;
import 'hidden.dart' hide C;
import 'lazy.dart' deferred as lazy;
import "double.dart";
export 'exported.dart';
export 'exp_show.dart' show D;
part 'piece.dart';
import 'wrapped.dart'
    show E;
import 'cond_a.dart'
    if (dart.library.io) 'cond_b.dart'
    if (dart.library.html) 'cond_c.dart';
  import 'indented.dart';
''';
      expect(relativeImportsOf(source), {
        'plain.dart',
        'prefixed.dart',
        'shown.dart',
        'hidden.dart',
        'lazy.dart',
        'double.dart',
        'exported.dart',
        'exp_show.dart',
        'piece.dart',
        'wrapped.dart',
        'cond_a.dart',
        'cond_b.dart',
        'cond_c.dart',
        'indented.dart',
      });
    });

    test('MIRROR: package:, dart: and non-.dart URIs are not relative imports', () {
      const source = '''
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'data.json';
import 'real.dart';
''';
      expect(relativeImportsOf(source), {'real.dart'});
    });

    test('MIRROR: a directive that is only mentioned in a comment is not an import', () {
      const source = '''
// import 'commented.dart';
/// import 'documented.dart';
final x = 1; // import 'trailing.dart';
import 'real.dart';
''';
      expect(relativeImportsOf(source), {'real.dart'});
    });

    test('the real gate and its libs are read: version_bump_git_lib.dart is among the gate\'s imports', () {
      expect(_relativeImports(File('scripts/$_gate')), contains('version_bump_git_lib.dart'));
    });
  });

  test('the gate has relative imports at all (the closure is not trivially just the gate)', () {
    final closure = _closure();
    expect(closure, contains(_gate));
    expect(closure.length, greaterThan(1));
    expect(closure, contains('plan_review_record_lib.dart'));
    expect(closure, contains('version_bump_git_lib.dart'),
        reason: 'B2 added this import; if it is gone, the exemption moved and this test needs a look');
  });

  for (final entry in harnesses.entries) {
    test('${entry.key}: every copy list contains the gate\'s whole import closure', () {
      final closure = _closure();
      final lists = _copyLists(entry.key);
      expect(lists.length, entry.value,
          reason: '${entry.key} is expected to hold ${entry.value} copy list(s) naming $_gate; '
              'the harness shape changed - update this test deliberately');
      for (var i = 0; i < lists.length; i++) {
        final missing = closure.difference(lists[i]);
        expect(missing, isEmpty,
            reason: 'copy list #${i + 1} in ${entry.key} does not copy $missing. The spawned gate '
                'would fail to COMPILE in the throwaway repo and every assertion would redden at once.');
      }
    });

    test('${entry.key}: no copy list names a script that does not exist (stale entry)', () {
      for (final list in _copyLists(entry.key)) {
        for (final f in list) {
          expect(File('scripts/$f').existsSync(), isTrue,
              reason: '$f is in a copy list in ${entry.key} but scripts/$f does not exist: '
                  'copySync would throw during setup');
        }
      }
    });
  }

  test('no OTHER test names the gate in a copy-list literal behind this test\'s back', () {
    // A fourth harness (a new file, or an existing one growing a second list) would escape the
    // table above. Any test that names the gate by bare file name inside a list literal, however
    // the list is spelled, must be one of them.
    final known = harnesses.keys.toSet();
    final offenders = <String>[];
    for (final e in Directory('test').listSync(recursive: true, followLinks: false)) {
      if (e is! File || !e.path.endsWith('_test.dart')) continue;
      final p = e.path.replaceAll('\\', '/');
      if (known.contains(p) || p.endsWith('plan_review_gate_harness_copies_imports_test.dart')) continue;
      if (_copyLists(p).isNotEmpty) offenders.add(p);
    }
    expect(offenders, isEmpty,
        reason: 'these tests name the gate in a list literal but are not in the harness table: '
            '$offenders. Add them to `harnesses` so their copy lists are checked too.');
  });
}
