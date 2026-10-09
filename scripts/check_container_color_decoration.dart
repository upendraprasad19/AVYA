// scripts/check_container_color_decoration.dart
//
// Gate — a Flutter `Container` must not pass BOTH `color:` and `decoration:`.
// The framework asserts `color == null || decoration == null`
// (container.dart:277). In DEBUG that assert THROWS during build; if the throw
// lands inside a screen's defensive try/catch it silently degrades to an error
// state (diagnose b1f4d2: TrainScreen._buildContent caught it → "Failed to load
// workouts" — the whole Train tab was dead in debug/web). In RELEASE the assert
// is stripped so it renders (decoration wins, color is dead) — which is exactly
// why no release test and no analyzer lint catches it. This gate does.
//
// Detection: for every `Container(` in lib/, parse its DIRECT arguments by
// tracking paren/bracket/brace depth from the opening paren. A direct argument
// is a `name:` token at depth 1. If both `color:` and `decoration:` appear at
// depth 1 for the same Container, fail. Nested `BoxDecoration(color: ...)` is
// at depth >1 and correctly ignored.
//
// Usage: dart run scripts/check_container_color_decoration.dart

import 'dart:io';

class _Violation {
  final String file;
  final int line;
  _Violation(this.file, this.line);
}

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[container-color-decoration] FAIL: lib/ does not exist');
    exit(1);
  }

  final violations = <_Violation>[];
  var containersScanned = 0;

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in dartFiles) {
    final rel = file.path.replaceAll('\\', '/');
    final src = file.readAsStringSync();

    // Find each `Container(` and scan its argument list at depth 1.
    final containerRe = RegExp(r'\bContainer\s*\(');
    for (final cm in containerRe.allMatches(src)) {
      containersScanned++;
      final openParen = cm.end - 1; // index of '('
      var depth = 0;
      var i = openParen;
      var hasColor = false;
      var hasDecoration = false;
      // depth-1 argument detection: look for ", color:" / "(color:" tokens that
      // sit exactly at depth 1 inside this Container's parens.
      while (i < src.length) {
        final ch = src[i];
        if (ch == '(' || ch == '[' || ch == '{') {
          depth++;
        } else if (ch == ')' || ch == ']' || ch == '}') {
          depth--;
          if (depth == 0) break; // closed this Container
        } else if (depth == 1) {
          // At the Container's own argument level. Detect `color:` /
          // `decoration:` named-argument starts. They begin after `(` or `,`.
          if (src.startsWith('color:', i) && _argStart(src, i)) {
            hasColor = true;
          } else if (src.startsWith('decoration:', i) && _argStart(src, i)) {
            hasDecoration = true;
          }
        }
        i++;
      }
      if (hasColor && hasDecoration) {
        final lineNo = '\n'.allMatches(src.substring(0, cm.start)).length + 1;
        violations.add(_Violation(rel, lineNo));
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('[container-color-decoration] FAIL: '
        '${violations.length} Container(s) set BOTH color: and decoration: '
        '(throws in debug, silent in release):');
    for (final v in violations) {
      stderr.writeln('  - ${v.file}:${v.line}  — remove the top-level color:; '
          'fold it into the decoration\'s BoxDecoration(color: ...).');
    }
    exit(1);
  }

  stdout.writeln('[container-color-decoration] OK: $containersScanned '
      'Container(...) call sites scanned; none set both color and decoration.');
}

/// A named arg starts right after `(` or `,` (ignoring whitespace). Avoids
/// matching e.g. `backgroundColor:` (which doesn't start with `color:` at a
/// boundary) or a `color:` that's part of a longer identifier.
bool _argStart(String src, int i) {
  // char before the token (skipping back over whitespace) must be ( or ,
  var j = i - 1;
  while (j >= 0 && (src[j] == ' ' || src[j] == '\n' || src[j] == '\r' || src[j] == '\t')) {
    j--;
  }
  if (j < 0) return false;
  final prev = src[j];
  return prev == '(' || prev == ',';
}
