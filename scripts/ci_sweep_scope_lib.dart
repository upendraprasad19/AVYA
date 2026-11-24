// scripts/ci_sweep_scope_lib.dart
//
// Decision core of scripts/ci_sweep_scope.dart: does a pull request have to run the
// plan-generator SWEEPS (the test files under test/plan_generator/)?
// Plan: docs/plans/2026-11-24-ci-sweep-split.md (option A).
//
// WHY. The sweeps are 66-69% of all CI test time (measured 2026-11-24) and they are
// a pure function of the plan engine, the exercise library and their own fixtures.
// A pull request that changes none of those cannot change their result, so its
// sweep legs skip the test step. Every push to main / develop still runs them.
//
// HOW THE ANSWER IS DERIVED, NOT LISTED. The inputs of the sweeps are computed from
// the sweep files themselves on every run:
//   1. the transitive import / export / part closure of every
//      test/plan_generator/**/*_test.dart file (237 of the 671 lib/ files on the day
//      this was written: the engine reaches the repositories and through them most of
//      lib/core/services);
//   2. [declaredInputs]: files the closure READS without importing them (the
//      exercise library JSON, fixtures). A unit test scans every path literal in every
//      closure file and fails until a new one is classified;
//   3. [alwaysRunPaths]: what changes the meaning of every test (pubspec, the
//      workflow, these scripts).
//
// THE FAIL-SAFE DIRECTION IS ALWAYS "RUN". An empty change list, a deleted Dart
// file, an import this parser cannot resolve, any exception: run the sweeps. The
// only way to skip is a complete, successful walk that finds no changed input.
// The accepted residual risk (plan section 4): an input reached by a COMPUTED path
// is invisible here; the push to main runs the sweeps and is the net under it.
//
// Pure Dart, no package imports: it runs as plain `dart scripts/ci_sweep_scope.dart`.

import 'dart:io';

import 'ci_test_partition_lib.dart';

/// The Dart package name `package:<name>/x.dart` resolves to `lib/x.dart` for.
/// Pinned against pubspec.yaml by test/scripts/ci_sweep_scope_test.dart.
const String appPackageName = 'icanbefitter';

/// Files and directories (a trailing `/` marks a directory) the sweeps READ without
/// importing them. Keep each entry tied to the reader that needs it.
const List<String> declaredInputs = <String>[
  // The library every sweep generates plans from: read straight from disk by
  // test/helpers/injury_floor_sweep_lib.dart and about fifteen sweep tests.
  'assets/data/exercise_library.json',
  // The removed-rows list the r6 sweeps replay.
  'scripts/data/library_batch_c2_removals.json',
  // Golden hashes, baselines and recorded runs the sweeps compare against.
  'test/fixtures/',
  // Read as TEXT by test/plan_generator/edit_profile_regen_test.dart.
  'lib/features/profile/screens/edit_profile_screen.dart',
];

/// Path literals that appear in a closure file and are PROVABLY not read by any
/// sweep. Each needs its reason; the scan test fails on a literal that is in neither
/// list, so nothing lands here by default.
const List<(String path, String reason)> declaredNonInputs = <(String, String)>[
  (
    'assets/data/food_database.json',
    'named by lib/core/services/seed_service.dart (rootBundle), which is in the import closure but is '
        'never executed by a sweep: the sweeps read the exercise library straight from disk and nothing '
        'under test/helpers or test/plan_generator uses SeedService, rootBundle or the food box '
        '(plan review round 2, 2026-11-24)',
  ),
];

/// Paths whose change can alter every test's result, or this decision itself. An
/// entry ending in `*` is a prefix; any other entry is an exact path.
const List<String> alwaysRunPaths = <String>[
  'pubspec.yaml',
  'pubspec.lock',
  'dart_test.yaml',
  'analysis_options.yaml',
  'test/flutter_test_config.dart',
  '.github/workflows/test.yml',
  'scripts/ci_sweep_scope*',
  'scripts/ci_test_partition*',
  'scripts/data/ci_sweep_durations.json',
];

String _norm(String p) {
  var s = p.replaceAll('\\', '/').trim();
  while (s.startsWith('./')) {
    s = s.substring(2);
  }
  return s;
}

/// Collapses `a/b/../c` and `a/./c`. A path that climbs above the root keeps its
/// leading `..` (it then names no file in the checkout and is reported unresolved).
String normalizeRepoPath(String path) {
  final out = <String>[];
  for (final seg in _norm(path).split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..' && out.isNotEmpty && out.last != '..') {
      out.removeLast();
    } else {
      out.add(seg);
    }
  }
  return out.join('/');
}

/// [source] with comments removed: `//` to end of line and `/* ... */` (nested), but
/// not inside a string literal, so a comment that quotes an import is not an edge and
/// a `/*` inside a string does not swallow the code after it. Strings are tracked as
/// Dart reads them: a one-line string ends at its quote or at the line end, a
/// triple-quoted one (`'''` or `"""`) only at its closing triple, over any number of
/// lines. A raw string's backslash is treated as an escape too; that can only keep a
/// string open to the end of its line, never open a comment.
String stripDartComments(String source) {
  final b = StringBuffer();
  var i = 0;
  String? quote; // the closing delimiter of the string being read: one quote or three
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (quote != null) {
      if (c == '\\' && next.isNotEmpty) {
        b.write(c);
        b.write(next);
        i += 2;
        continue;
      }
      if (source.startsWith(quote, i)) {
        b.write(quote);
        i += quote.length;
        quote = null;
        continue;
      }
      b.write(c);
      if (quote.length == 1 && (c == '\n' || c == '\r')) quote = null;
      i++;
      continue;
    }
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      // Dart block comments NEST: `/* a /* b */ c */` is one comment.
      var depth = 1;
      i += 2;
      while (i < source.length && depth > 0) {
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      b.write(' ');
      continue;
    }
    if (c == "'" || c == '"') {
      quote = source.startsWith(c * 3, i) ? c * 3 : c;
      b.write(quote);
      i += quote.length;
      continue;
    }
    b.write(c);
    i++;
  }
  return b.toString();
}

// NOT anchored to the start of a line: `import 'a.dart'; import 'b.dart';`, `library x; import 'a.dart';` and
// `@pragma('x') import 'a.dart';` are all legal, and an edge this misses is an input the decision cannot see
// (B-pass finding 2, 2026-11-24). Matching the keyword anywhere it starts a word can only ADD edges; the
// string literal that must follow it at once keeps a variable named `part` or `export` from being one (delta
// round). Dart source quoted inside a string can still read as an edge: to a real file that is a harmless
// superset, to a missing one it is `unresolved`, and test/scripts/ci_sweep_scope_test.dart ("the walk is
// COMPLETE") goes red on it in the core set, so it cannot quietly make every pull request run the sweeps.
final RegExp _directive = RegExp(r'''(?<![\w$.'"])(import|export|part)\s+(?=r?['"])([^;]*);''');
// Adjacent string literals are ONE string in Dart (`import 'a' 'b.dart';` imports ab.dart).
final RegExp _adjacentLiterals = RegExp(r'''^\s*r?(['"])[^'"\n]*\1(?:\s*r?(['"])[^'"\n]*\2)+''');
final RegExp _stringLiteral = RegExp(r'''(['"])([^'"\n]*)\1''');

/// The URIs of every `import` / `export` / `part` directive in [source], read
/// STATEMENT by statement (up to the `;`), so a directive spread over several lines
/// is one directive, and several directives on one line are several. A conditional import (`import 'a.dart' if (x) 'b.dart';`)
/// contributes EVERY branch: a superset, so it can only add inputs. `part of` is
/// skipped (a part is reached through its library's `part` directive). Only string
/// literals ending in `.dart` count, so a condition such as `== 'true'` is not a URI.
List<String> directiveUris(String source) {
  final uris = <String>[];
  for (final m in _directive.allMatches(stripDartComments(source))) {
    final body = m.group(2)!;
    if (m.group(1) == 'part' && RegExp(r'^\s*of\b').hasMatch(body)) continue;
    for (final s in _stringLiteral.allMatches(body)) {
      final uri = s.group(2)!;
      if (uri.endsWith('.dart')) uris.add(uri);
    }
    final adjacent = _adjacentLiterals.firstMatch(body);
    if (adjacent != null) {
      final joined = _stringLiteral.allMatches(adjacent.group(0)!).map((s) => s.group(2)!).join();
      if (joined.endsWith('.dart')) uris.add(joined);
    }
  }
  return uris;
}

/// Where [uri], written in the file [from], points inside the checkout; `null` for a
/// `dart:` library or another package (leaves of the walk).
String? resolveUri(String from, String uri) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:$appPackageName/')) {
    return normalizeRepoPath('lib/${uri.substring('package:$appPackageName/'.length)}');
  }
  if (uri.startsWith('package:')) return null;
  final slash = from.lastIndexOf('/');
  final dir = slash < 0 ? '' : from.substring(0, slash + 1);
  return normalizeRepoPath('$dir$uri');
}

/// The result of the closure walk: every file reached, and every edge that pointed at
/// a file that does not exist (`<importer> -> <uri>`). A non-empty [unresolved] means
/// the walk is INCOMPLETE and the decision must be "run".
typedef SweepClosure = ({Set<String> files, List<String> unresolved});

/// The transitive closure of [roots] over import / export / part edges, reading files
/// through [read] (null = the file does not exist). Paths are repo-relative with
/// forward slashes.
SweepClosure closureOf(Iterable<String> roots, String? Function(String path) read) {
  final files = <String>{};
  final unresolved = <String>[];
  final queue = [for (final r in roots) normalizeRepoPath(r)];
  while (queue.isNotEmpty) {
    final f = queue.removeLast();
    if (files.contains(f)) continue;
    final source = read(f);
    if (source == null) continue; // reported by the edge that pointed here
    files.add(f);
    for (final uri in directiveUris(source)) {
      final target = resolveUri(f, uri);
      if (target == null || files.contains(target)) continue;
      if (read(target) == null) {
        unresolved.add('$f -> $uri');
      } else {
        queue.add(target);
      }
    }
  }
  return (files: files, unresolved: unresolved..sort());
}

/// Reads [path] under [root]; null when it is not a file.
String? Function(String) diskReader(Directory root) => (String path) {
      final f = File('${root.path}/$path');
      try {
        return f.existsSync() ? f.readAsStringSync() : null;
      } on FileSystemException {
        return null;
      }
    };

/// The sweep test files under [root] (the roots of the walk).
List<String> sweepRoots(Directory root) =>
    filesOfSet(discoverTestFiles(Directory('${root.path}/test')), 'sweep');

bool _matchesAlwaysRun(String p) {
  for (final e in alwaysRunPaths) {
    if (e.endsWith('*') ? p.startsWith(e.substring(0, e.length - 1)) : p == e) return true;
  }
  return false;
}

/// True when [p] is a declared input: an exact file, or under a declared directory.
bool isDeclaredInput(String p) {
  for (final e in declaredInputs) {
    if (e.endsWith('/') ? p.startsWith(e) : p == e) return true;
  }
  return false;
}

/// True when [p] is a declared NON-input.
bool isDeclaredNonInput(String p) => declaredNonInputs.any((e) => e.$1 == p);

final RegExp _plainPath = RegExp(r'^[\x20\x21\x23-\x5B\x5D-\x7E]+$');

/// True when [p] can be compared with a path of the tree byte for byte: printable
/// ASCII with no `"` and no `\`. `git diff --name-only` prints a path holding any
/// other byte QUOTED and octal-escaped (`"lib/caf\303\251.dart"`, core.quotePath), and
/// that string is in no closure, so such a path must mean "run" (B-pass finding 1).
bool isPlainPath(String p) => _plainPath.hasMatch(p);

/// The decision. [changed] are the pull request's changed paths (old AND new names
/// of a rename, as `git diff --no-renames` prints them); [closure] the walk over the
/// CURRENT tree; [exists] whether a path is a file in it. `run` is false ONLY when
/// the walk was complete and no changed path is an input; [reasons] says why.
({bool run, List<String> reasons}) decideSweeps({
  required Iterable<String> changed,
  required SweepClosure closure,
  required bool Function(String path) exists,
}) {
  final given = [
    for (final c in changed)
      if (c.trim().isNotEmpty) c.trim(),
  ];
  final paths = {for (final c in given) _norm(c)};
  if (paths.isEmpty) {
    return (run: true, reasons: ['no changed paths were given: cannot prove the sweeps are unaffected']);
  }
  final reasons = <String>[];
  for (final c in given) {
    if (!isPlainPath(c)) reasons.add('$c: not a plain path (quoted or escaped by git?), it cannot be compared');
  }
  if (closure.files.isEmpty) reasons.add('the closure is empty (no sweep files found?)');
  for (final u in closure.unresolved) {
    reasons.add('unresolved import, the closure is incomplete: $u');
  }
  for (final p in paths.toList()..sort()) {
    if (_matchesAlwaysRun(p)) {
      reasons.add('$p: always-run path');
    } else if (isSweepTestPath(p)) {
      reasons.add('$p: under $sweepDirPrefix');
    } else if (closure.files.contains(p)) {
      reasons.add('$p: in the import closure of the sweeps');
    } else if (isDeclaredInput(p)) {
      reasons.add('$p: a declared non-Dart input of the sweeps');
    } else if (p.endsWith('.dart') && (p.startsWith('lib/') || p.startsWith('test/')) && !exists(p)) {
      // Deleted or renamed away: the tree no longer says who imported it.
      reasons.add('$p: a Dart file that no longer exists (deleted or renamed)');
    }
  }
  if (reasons.isNotEmpty) return (run: true, reasons: reasons);
  return (
    run: false,
    reasons: ['none of the ${paths.length} changed path(s) is in the sweeps\' closure '
        '(${closure.files.length} files), a declared input or an always-run path'],
  );
}

final RegExp _pathLiteral =
    RegExp(r'''['"]((?:assets|test|scripts|lib|docs|backups|supabase)/[^'"\n]*)['"]''');

/// Every string literal in [source] that looks like a repo path, comments removed.
/// A literal containing `$` is cut at the interpolation and returned with a trailing
/// `*` (a computed path: only its fixed prefix is known).
List<String> pathLiterals(String source) => [
      for (final m in _pathLiteral.allMatches(stripDartComments(source)))
        m.group(1)!.contains(r'$') ? '${m.group(1)!.substring(0, m.group(1)!.indexOf(r'$'))}*' : m.group(1)!,
    ];

/// Whether a path literal found in a closure file is ACCOUNTED FOR: it is itself in
/// the closure, under the sweep directory, a declared input or a declared non-input.
/// A computed literal (`prefix*`) is accounted for only when its fixed prefix lies
/// inside the sweep directory or a declared input DIRECTORY, because then every path
/// it can form is an input already.
bool isLiteralAccountedFor(String literal, Set<String> closureFiles) {
  if (literal.endsWith('*')) {
    final prefix = literal.substring(0, literal.length - 1);
    if (prefix.startsWith(sweepDirPrefix)) return true;
    return declaredInputs.any((e) => e.endsWith('/') && prefix.startsWith(e));
  }
  final p = normalizeRepoPath(literal);
  final asDir = literal.endsWith('/') ? '$p/' : p;
  return closureFiles.contains(p) ||
      isSweepTestPath(asDir) ||
      asDir == sweepDirPrefix ||
      isDeclaredInput(asDir) ||
      declaredInputs.contains(asDir) ||
      isDeclaredNonInput(p);
}
