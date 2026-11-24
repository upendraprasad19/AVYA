// test/scripts/ci_sweep_scope_test.dart
//
// scripts/ci_sweep_scope{,_lib}.dart decides whether a pull request runs the
// plan-generator SWEEPS (docs/plans/2026-11-24-ci-sweep-split.md, option A). The
// danger is one-sided: a wrong "run" costs minutes, a wrong "skip" lets a pull request
// that changed the plan engine merge with the sweeps never run on it. So every test
// here pushes on the SKIP side:
//
//   - EXHAUSTIVE over the real tree: a change to ANY file in the real closure, to any
//     declared input, to any always-run path, runs the sweeps;
//   - the closure is checked against the real tree's own facts (the engine is in it, a
//     conditional import contributes every branch, a multi-line directive is read);
//   - the DERIVED CHECK: every path literal in every closure file is accounted for, so
//     a sweep that starts reading a new fixture or asset reddens this file until someone
//     classifies it (a declared input, or a declared non-input with its reason);
//   - every fail-safe branch ends in "run", in the lib and in the CLI run for real.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/ci_sweep_scope_lib.dart';
import '../../scripts/ci_test_partition_lib.dart';
import '../helpers/spawn.dart';

/// An in-memory tree for the pure-function tests.
String? Function(String) _tree(Map<String, String> files) => (p) => files[p];

void main() {
  group('directiveUris — statement-based, comment-aware', () {
    test('single-line import, export and part; `part of` is skipped', () {
      expect(
          directiveUris("import 'a.dart';\nexport 'b.dart' show X;\npart 'c.dart';\npart of 'lib.dart';\npart of some.lib;\n"),
          ['a.dart', 'b.dart', 'c.dart']);
    });

    test('a directive spread over several lines is ONE directive', () {
      expect(
          directiveUris("import 'package:icanbefitter/x/y.dart'\n    show A,\n        B\n    hide C;\nimport\n  'z.dart'\n  as z;\n"),
          ['package:icanbefitter/x/y.dart', 'z.dart']);
    });

    test('a conditional import contributes EVERY branch, also over several lines', () {
      expect(
          directiveUris("import 'stub.dart'\n    if (dart.library.html) 'web.dart'\n    if (dart.library.io) 'io.dart';\n"),
          ['stub.dart', 'web.dart', 'io.dart']);
      expect(directiveUris("import 'a.dart' if (dart.library.io == 'true') 'b.dart';"), ['a.dart', 'b.dart'],
          reason: 'a string inside the condition is not a URI');
    });

    test('an import quoted in a comment or a doc comment is not an edge', () {
      expect(directiveUris("// import 'no.dart';\n/// import 'no2.dart';\n/* import 'no3.dart'; */\nimport 'yes.dart';\n"),
          ['yes.dart']);
    });

    test('an import at the START OF A LINE inside a block comment is not an edge', () {
      // The line-start anchor alone would read this one: only comment stripping removes it.
      expect(directiveUris("/*\nimport 'no.dart';\n*/\nimport 'yes.dart';\n"), ['yes.dart']);
    });

    // B-pass finding 2 (2026-11-24): each of these was read as NO edge, or as the first edge only.
    test('a directive that does not start its line is still an edge', () {
      expect(directiveUris("import 'a.dart'; import 'b.dart';\n"), ['a.dart', 'b.dart']);
      expect(directiveUris("library x; import 'a.dart';\n"), ['a.dart']);
      expect(directiveUris("import 'dart:io'; export 'e.dart' hide X;\n"), ['e.dart']);
      expect(directiveUris("@pragma('x') import 'a.dart';\n"), ['a.dart']);
      expect(directiveUris("/* c */ import 'a.dart'; part 'p.dart';\n"), ['a.dart', 'p.dart']);
    });

    test('block comments NEST: an import after a nested comment is an edge, one inside it is not', () {
      expect(directiveUris("/* a /* b */ import 'no.dart'; */ import 'yes.dart';\n"), ['yes.dart']);
      expect(directiveUris("/* never closed /* b */ import 'no.dart';\n"), isEmpty);
    });

    test('a word that only ENDS in a keyword is not a directive', () {
      expect(directiveUris("reimport 'no.dart'; x.part 'no2.dart'; \$export 'no3.dart';\n"), isEmpty);
    });

    // Delta round on the B-pass fixes (2026-11-24).
    test('a variable NAMED like a keyword is not a directive (an invented edge makes every pull request run)', () {
      expect(directiveUris("final part = 'a.dart';\nString export\n = 'x.dart';\nvar import = x; f('y.dart');\n"), isEmpty);
    });

    test('a `/*` inside a triple-quoted string does not swallow the directive after it', () {
      expect(directiveUris("const s='''\n/* \n''';\nimport 'a.dart';\n// */\n"), ['a.dart']);
      expect(directiveUris('const s="""\n/* \' \n""";\nimport "b.dart";\n'), ['b.dart']);
      expect(directiveUris("const s='/* ';\nimport 'c.dart';\n/* */\n"), ['c.dart']);
    });

    test('a one-line string ends at the line end even when its quote never closes', () {
      expect(directiveUris("x = 'unterminated\n// import 'no.dart';\nimport 'yes.dart';\n"), ['yes.dart']);
    });

    test('adjacent string literals are one URI: the joined file is an edge', () {
      expect(directiveUris("import 'a' 'b.dart';\n"), containsAll(['ab.dart']));
      expect(directiveUris("import 'dir/'\n    'c.dart' as c;\n"), contains('dir/c.dart'));
      expect(directiveUris("import 'a.dart' if (dart.library.io) 'b.dart';\n"), ['a.dart', 'b.dart']);
    });

    test('CRLF line endings: every directive is still read', () {
      expect(directiveUris("import 'a.dart';\r\nexport 'b.dart' show X;\r\npart 'c/d.dart';\r\n"), ['a.dart', 'b.dart', 'c/d.dart']);
    });

    test('double quotes and a `//` inside a URI string survive comment stripping', () {
      expect(directiveUris('import "a.dart";\nimport \'b//c.dart\';\n'), ['a.dart', 'b//c.dart']);
    });
  });

  group('resolveUri', () {
    test('dart: and other packages are leaves; the app package maps to lib/; relative resolves', () {
      expect(resolveUri('lib/a/b.dart', 'dart:io'), isNull);
      expect(resolveUri('lib/a/b.dart', 'package:flutter/material.dart'), isNull);
      expect(resolveUri('test/x_test.dart', 'package:icanbefitter/core/c.dart'), 'lib/core/c.dart');
      expect(resolveUri('lib/a/b.dart', '../c/d.dart'), 'lib/c/d.dart');
      expect(resolveUri('lib/a/b.dart', 'e.dart'), 'lib/a/e.dart');
      expect(resolveUri('test/plan_generator/s_test.dart', '../../scripts/x_lib.dart'), 'scripts/x_lib.dart');
    });

    test('the app package name is pubspec.yaml\'s', () {
      expect(File('pubspec.yaml').readAsLinesSync().first.trim(), 'name: $appPackageName',
          reason: 'package:<name>/ is resolved to lib/ by this constant');
    });
  });

  group('closureOf', () {
    test('walks import, export and part edges transitively, through a cycle', () {
      final c = closureOf(['test/plan_generator/s_test.dart'], _tree({
        'test/plan_generator/s_test.dart': "import 'package:icanbefitter/e.dart';\nimport '../helpers/h.dart';",
        'lib/e.dart': "export 'f.dart';\npart 'e_part.dart';",
        'lib/e_part.dart': "part of 'e.dart';",
        'lib/f.dart': "import 'e.dart';\nimport 'dart:io';\nimport 'package:other/o.dart';",
        'test/helpers/h.dart': '',
        'lib/unrelated.dart': "import 'e.dart';",
      }));
      expect(c.files, {
        'test/plan_generator/s_test.dart',
        'lib/e.dart',
        'lib/e_part.dart',
        'lib/f.dart',
        'test/helpers/h.dart',
      });
      expect(c.unresolved, isEmpty);
    });

    test('an edge to a file that does not exist is REPORTED, never dropped', () {
      final c = closureOf(['test/plan_generator/s_test.dart'], _tree({
        'test/plan_generator/s_test.dart': "import 'package:icanbefitter/gone.dart';\nimport 'here.dart';",
        'test/plan_generator/here.dart': '',
      }));
      expect(c.unresolved, ['test/plan_generator/s_test.dart -> package:icanbefitter/gone.dart']);
    });
  });

  group('decideSweeps', () {
    final closure = (files: {'test/plan_generator/s_test.dart', 'lib/e.dart'}, unresolved: <String>[]);
    bool exists(String p) => p != 'lib/deleted.dart' && p != 'test/helpers/renamed_away.dart';
    ({bool run, List<String> reasons}) decide(List<String> changed, {SweepClosure? c}) =>
        decideSweeps(changed: changed, closure: c ?? closure, exists: exists);

    test('SKIP only when no changed path is an input', () {
      final d = decide(['lib/features/nutrition/n.dart', 'docs/x.md', 'supabase/functions/f/index.ts']);
      expect(d.run, isFalse, reason: d.reasons.join('\n'));
    });

    for (final (why, path) in [
      ('a closure file', 'lib/e.dart'),
      ('a sweep test', 'test/plan_generator/new_test.dart'),
      ('a sweep-directory report', 'test/plan_generator/core_list_pool_report.md'),
      ('the exercise library', 'assets/data/exercise_library.json'),
      ('a fixture', 'test/fixtures/generator_golden_hashes.json'),
      ('the removals list', 'scripts/data/library_batch_c2_removals.json'),
      ('a file read as text', 'lib/features/profile/screens/edit_profile_screen.dart'),
      ('pubspec.yaml', 'pubspec.yaml'),
      ('pubspec.lock', 'pubspec.lock'),
      ('dart_test.yaml', 'dart_test.yaml'),
      ('the workflow', '.github/workflows/test.yml'),
      ('this script', 'scripts/ci_sweep_scope_lib.dart'),
      ('the partition', 'scripts/ci_test_partition.dart'),
      ('the duration table', 'scripts/data/ci_sweep_durations.json'),
      ('a test config', 'test/flutter_test_config.dart'),
      ('a deleted lib file', 'lib/deleted.dart'),
      ('a renamed-away helper', 'test/helpers/renamed_away.dart'),
      ('a Windows-spelled closure path', r'lib\e.dart'),
      ('a ./-prefixed closure path', './lib/e.dart'),
    ]) {
      test('RUN: $why changed, among unrelated changes', () {
        final d = decide(['docs/x.md', path, 'lib/features/nutrition/n.dart']);
        expect(d.run, isTrue, reason: '$path must run the sweeps');
        expect(d.reasons.join('\n'), contains(path.replaceAll('\\', '/').replaceFirst('./', '')));
      });
    }

    // B-pass finding 1 (2026-11-24): `git diff --name-only` QUOTES a path holding a non-ASCII byte, a quote or a
    // backslash, and the quoted string is in no closure. `lib/caf\303\251.dart` is a closure file here.
    for (final (why, path) in [
      ('quoted and octal-escaped by git', r'"lib/caf\303\251.dart"'),
      ('non-ASCII, unquoted (core.quotePath=false)', 'lib/caf\u00e9.dart'),
      ('a backslash', r'lib\e2.dart'),
      ('a control character', 'docs/a\tb.md'),
      ('a quote inside', 'docs/a"b.md'),
    ]) {
      test('RUN: a changed path that is not plain ASCII cannot be compared ($why)', () {
        final c = (files: {...closure.files, 'lib/caf\u00e9.dart'}, unresolved: <String>[]);
        final d = decide(['docs/x.md', path], c: c);
        expect(d.run, isTrue);
        expect(d.reasons.join('\n'), contains('not a plain path'));
      });
    }

    test('plain paths, spaces and punctuation included, are still compared and can skip', () {
      for (final p in ['docs/a b.md', 'docs/a+b-c_d.e@f(1)[2]~#%.md', "docs/it's.md"]) {
        expect(isPlainPath(p), isTrue, reason: p);
        expect(decide([p]).run, isFalse, reason: p);
      }
    });

    test('RUN: no changed paths at all (an empty or blank list proves nothing)', () {
      expect(decide([]).run, isTrue);
      expect(decide(['', '  ']).run, isTrue);
    });

    test('RUN: an incomplete closure, whatever changed', () {
      final d = decide(['docs/x.md'], c: (files: closure.files, unresolved: ['a -> b']));
      expect(d.run, isTrue);
      expect(d.reasons.join('\n'), contains('incomplete'));
    });

    test('RUN: an empty closure (no sweep files found)', () {
      expect(decide(['docs/x.md'], c: (files: <String>{}, unresolved: <String>[])).run, isTrue);
    });

    test('a deleted file that is NOT Dart, or not under lib/ or test/, does not force a run', () {
      bool none(String p) => false;
      expect(decideSweeps(changed: ['docs/gone.md', 'supabase/functions/x.ts', 'scripts/gone.dart'], closure: closure, exists: none).run,
          isFalse);
    });

    test('food_database.json is a declared NON-input: it does not run the sweeps', () {
      expect(isDeclaredNonInput('assets/data/food_database.json'), isTrue);
      expect(decide(['assets/data/food_database.json']).run, isFalse);
    });
  });

  group('the REAL tree', () {
    late SweepClosure closure;
    late List<String> roots;
    final root = Directory.current;
    bool exists(String p) => FileSystemEntity.isFileSync(p);

    setUpAll(() {
      roots = sweepRoots(root);
      closure = closureOf(roots, diskReader(root));
    });

    test('the walk is COMPLETE: no unresolved import (else every PR runs the sweeps)', () {
      expect(closure.unresolved, isEmpty,
          reason: 'the parser met an import it cannot map to a file. The decision is then always '
              '"run" and option A is switched off: fix the resolver, do not weaken this test');
    });

    test('the roots are the sweep files, and the engine and their helpers are in the closure', () {
      expect(roots, isNotEmpty);
      expect(roots.every(isSweepTestPath), isTrue);
      expect(closure.files, containsAll(roots));
      expect(
          closure.files,
          containsAll([
            'lib/shared/repositories/plan_engine/plan_generator.dart',
            'lib/shared/repositories/exercise_repository.dart',
            'test/helpers/injury_floor_sweep_lib.dart',
            'test/helpers/day_floor_gate_lib.dart',
          ]));
    });

    test('a conditional import in the closure contributes EVERY branch (measured: razorpay_web_checkout)', () {
      const f = 'lib/core/services/razorpay_web_checkout.dart';
      expect(closure.files, contains(f), reason: 'if this file left the closure, pick another conditional import');
      final uris = directiveUris(File(f).readAsStringSync());
      final conditional = RegExp(r"import\s+'([^']+)'\s+if\s*\([^)]*\)\s*'([^']+)'").firstMatch(stripDartComments(File(f).readAsStringSync()));
      expect(conditional, isNotNull);
      for (final g in [1, 2]) {
        expect(uris, contains(conditional!.group(g)));
        final target = resolveUri(f, conditional.group(g)!);
        if (target != null) expect(closure.files, contains(target));
      }
    });

    test('EXHAUSTIVE: a change to ANY single closure file runs the sweeps', () {
      for (final f in closure.files) {
        final d = decideSweeps(changed: [f], closure: closure, exists: exists);
        expect(d.run, isTrue, reason: '$f is an input of the sweeps');
      }
    });

    test('a real file OUTSIDE the closure does not run the sweeps', () {
      final outside = [
        for (final f in Directory('lib/features/nutrition').listSync(recursive: true))
          if (f is File && f.path.endsWith('.dart') && !closure.files.contains(f.path.replaceAll('\\', '/')))
            f.path.replaceAll('\\', '/'),
      ];
      expect(outside, isNotEmpty, reason: 'setup: some nutrition file must be outside the closure');
      final d = decideSweeps(changed: [outside.first, 'docs/architecture/hooks.md'], closure: closure, exists: exists);
      expect(d.run, isFalse, reason: d.reasons.join('\n'));
    });

    test('DERIVED CHECK: every path literal in EVERY closure file is accounted for', () {
      // lib/ included: lib/core/services/seed_service.dart names two assets and is in the
      // closure. A literal that is in none of {the closure, the sweep directory,
      // declaredInputs, declaredNonInputs} is a file the sweeps may read that no rule
      // watches. Classify it in scripts/ci_sweep_scope_lib.dart; a non-input needs a reason.
      final loose = <String>[];
      for (final f in closure.files) {
        for (final lit in pathLiterals(File(f).readAsStringSync())) {
          if (!isLiteralAccountedFor(lit, closure.files)) loose.add('$f: $lit');
        }
      }
      expect(loose, isEmpty, reason: 'unclassified path literals:\n${loose.join('\n')}');
    });

    test('every declared input and non-input still exists and still has a reader', () {
      final allText = [for (final f in closure.files) File(f).readAsStringSync()].join('\n');
      for (final e in declaredInputs) {
        expect(e.endsWith('/') ? Directory(e).existsSync() : File(e).existsSync(), isTrue, reason: '$e is gone');
        expect(allText, contains(e.endsWith('/') ? e : e.split('/').last), reason: 'no closure file names $e any more');
      }
      for (final (path, reason) in declaredNonInputs) {
        expect(File(path).existsSync(), isTrue);
        expect(reason.length, greaterThan(40), reason: 'a non-input needs a real reason');
        expect(allText, contains(path.split('/').last));
      }
    });

    test('the food database really is not read by a sweep (the non-input\'s reason, re-checked)', () {
      final nonLib = [for (final f in closure.files) if (!f.startsWith('lib/')) f];
      for (final f in nonLib) {
        final text = stripDartComments(File(f).readAsStringSync());
        for (final banned in ['SeedService', 'rootBundle', 'food_database', 'foodBox']) {
          expect(text, isNot(contains(banned)),
              reason: '$f uses $banned: assets/data/food_database.json may now be a sweep input; '
                  'move it from declaredNonInputs to declaredInputs');
        }
      }
    });
  });

  group('the CLI, run for real', () {
    final script = File('scripts/ci_sweep_scope.dart').absolute.path;

    ({int code, String out, String err}) run(String stdinText, {String? cwd}) {
      final r = runSpawn('sh', ['-c', 'printf "%s" "\$CHANGED" | "\$DART" "\$SCRIPT"'],
          why: 'ci_sweep_scope with a change list',
          workingDirectory: cwd,
          extraEnv: {'CHANGED': stdinText, 'DART': dartBin(), 'SCRIPT': script});
      return (code: r.exitCode, out: (r.stdout as String).trim(), err: r.stderr as String);
    }

    test('prints exactly `run=false` for a change outside the closure, with the reason on stderr', () {
      final r = run('docs/architecture/hooks.md\nsupabase/functions/ai-proxy/index.ts\n');
      expect(r.code, 0);
      expect(r.out, 'run=false');
      expect(r.err, contains('none of the 2 changed path(s)'));
    });

    test('prints exactly `run=true` for the engine, the library, and an empty list', () {
      for (final changed in [
        'lib/shared/repositories/plan_engine/plan_generator.dart\n',
        'docs/x.md\nassets/data/exercise_library.json\n',
        '',
      ]) {
        final r = run(changed);
        expect(r.code, 0);
        expect(r.out, 'run=true', reason: 'change list: "$changed"');
      }
    });

    test('a sweep file that cannot be read (not UTF-8) is run=true, exit 0', () {
      final tmp = Directory.systemTemp.createTempSync('ci_sweep_scope_bad_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      File('${tmp.path}/test/plan_generator/bad_test.dart')
        ..createSync(recursive: true)
        ..writeAsBytesSync([0x69, 0x6d, 0xff, 0xfe, 0xfd]);
      final r = run('docs/x.md\n', cwd: tmp.path);
      expect(r.code, 0);
      expect(r.out, 'run=true');
    });

    test('in a directory with no sweep files it still exits 0 and says run=true', () {
      final tmp = Directory.systemTemp.createTempSync('ci_sweep_scope_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final r = run('docs/x.md\n', cwd: tmp.path);
      expect(r.code, 0);
      expect(r.out, 'run=true');
    });
  });
}
