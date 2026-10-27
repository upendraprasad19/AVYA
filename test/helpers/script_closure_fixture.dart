// test/helpers/script_closure_fixture.dart
//
// The ONE way a fixture copies a repo script into a throwaway repo.
//
// WHY. A fixture that runs a script in a temp repo must copy everything that script imports.
// A hand-written copy list rots the moment the script gains an import, and it rots LOUDLY only
// when the missing file is a compile error: landing A2 of the merge-conflict-treadmill plan gave
// both index builders a shared lib, and every fixture that named the builders by hand failed
// (18 cases in two files) with a compile error inside the child, far from the cause. The
// fixture that was written with `if (src.existsSync()) src.copySync(...)` would have gone on
// silently skipping a file that no longer existed.
//
// WHAT. [scriptImportClosure] returns the transitive closure of RELATIVE `import` / `export` /
// `part` directives from the named entry scripts, as repo-relative `/` paths, sorted. A
// non-Dart entry (a shell hook) is just itself. [copyScriptClosure] copies that closure into a
// destination root, preserving the relative layout. Every fixture calls this; a grep test
// (test/scripts/script_closure_fixture_test.dart) asserts that no test lists an index builder
// in a hand-written copy list.
//
// STRICT BY DESIGN: a `package:` import in the closure throws, because a throwaway repo has no
// package config and the child would fail to resolve it (the builders must stay import-light);
// an import that resolves to a missing file throws; a path that climbs out of the repo throws.

import 'dart:io';

// `import 'x.dart'`, `export 'x.dart'`, `part 'x.dart'` and `part of 'x.dart'` at the start of a
// line. A `//` comment line never matches, because the directive must be the first thing on its
// line.
final RegExp _directive = RegExp(
    r'''^[ \t]*(?:import|export|part)[ \t]+(?:of[ \t]+)?['"]([^'"]+)['"]''',
    multiLine: true);

/// Resolves [rel] against the directory of the repo-relative file [fromFile].
String _resolve(String fromFile, String rel) {
  final parts = fromFile.split('/')..removeLast();
  for (final seg in rel.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isEmpty) {
        throw StateError('$fromFile imports "$rel", which climbs out of the repo');
      }
      parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

/// The repo-relative files [entries] need: themselves plus, for each `.dart` file, every file
/// its relative directives name, transitively. Cycles are fine.
List<String> scriptImportClosure(String repoRoot, List<String> entries) {
  final seen = <String>{};
  final queue = <String>[...entries];
  while (queue.isNotEmpty) {
    final f = queue.removeLast();
    if (!seen.add(f)) continue;
    if (!f.endsWith('.dart')) continue;
    final file = File('$repoRoot/$f');
    if (!file.existsSync()) { // file-only: a source FILE the closure names
      throw StateError('$f is part of the import closure but does not exist under $repoRoot');
    }
    for (final m in _directive.allMatches(file.readAsStringSync())) {
      final target = m.group(1)!;
      if (target.startsWith('dart:')) continue;
      if (target.contains(':')) {
        throw StateError('$f imports "$target": a fixture repo has no package config, so the '
            'script must keep to relative imports and dart: libraries');
      }
      queue.add(_resolve(f, target));
    }
  }
  return seen.toList()..sort();
}

/// Copies the closure of [entries] from [repoRoot] into [destRoot], creating directories, and
/// returns the copied repo-relative paths.
List<String> copyScriptClosure(
    String repoRoot, String destRoot, List<String> entries) {
  final files = scriptImportClosure(repoRoot, entries);
  for (final f in files) {
    final dest = File('$destRoot/$f');
    dest.parent.createSync(recursive: true);
    File('$repoRoot/$f').copySync(dest.path);
  }
  return files;
}
