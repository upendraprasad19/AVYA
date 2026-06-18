// scripts/check_sot_registry_parity.dart
//
// Gate (E.13 — Audit 2026-05-16 framework deliverable):
// SoT registry parity — file:line references resolve AND no orphan
// WriteService / Repository classes outside the registry.
//
// This is COMPLEMENTARY to check_sot_registry_completeness.dart (which
// asserts write-pattern methods in lib/core/services/ are registered).
// This script does the INVERSE check at the CLASS level:
//
//   1. For every writer/reader entry in docs/sot_registry.yaml, verify
//      the cited `file:` exists AND the `line_range` is in-bounds AND
//      the cited `method:` name actually appears in non-comment code
//      inside the range (cheap heuristic — grep for the method name
//      in the file after stripping block and line comments).
//
//   2. Parses ist_sites inline maps: `- { file: PATH, line: N, fn: SYMBOL }`
//      (also `method:` instead of `fn:`). Verifies SYMBOL in non-comment
//      code of PATH; treats `line: N` as a 1-line range N-N for the
//      stale-range check.
//
//   3. Parses writer/reader inline maps with method but NO line_range:
//      `{ file: PATH, line: N, method: SYMBOL }`. Verifies SYMBOL in
//      non-comment code; no range check.
//
//   4. Source-grep `lib/` for class definitions matching `*WriteService`
//      or `*Repository`. Each match should appear somewhere in
//      docs/sot_registry.yaml (as a writer or as part of a reader file).
//      Unregistered service/repo classes are warnings — they indicate a
//      SoT concept that hasn't been documented.
//
// Symbol-vs-prose discrimination (avoid false positives):
//   - If the method: field contains a backticked token `X`, symbol =
//     the first identifier inside backticks.
//   - Else if the trimmed field matches a bare identifier or Dotted.Path
//     regex, symbol = its first identifier.
//   - Else it is prose → skip the symbol check entirely (still validate
//     file-exists + line_range bounds).
//
// Stale-line-range detection is an ERROR (not a warning):
//   Symbol is present in the file but outside the cited range.
//
// Exit 0 = pass.
// Exit 1 = fail (unless --warn-only is given).
//
// Usage:
//   dart run scripts/check_sot_registry_parity.dart
//   dart run scripts/check_sot_registry_parity.dart --warn-only

import 'dart:io';

// ---------------------------------------------------------------------------
// Comment stripping
// ---------------------------------------------------------------------------

/// Strip block comments (`/* … */`) and line comments (`// …`) from [s].
/// Replaced with spaces so character positions stay roughly aligned and
/// multi-line block comments don't collapse unrelated tokens together.
String _stripComments(String s) {
  s = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' '); // block comments
  s = s.replaceAll(RegExp(r'//[^\n]*'), ' '); // line comments
  return s;
}

// ---------------------------------------------------------------------------
// Symbol-vs-prose discrimination
// ---------------------------------------------------------------------------

/// Bare identifier OR Dotted.Path — considered a CODE SYMBOL.
final _bareSymbolRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$');

/// Backticked token.
final _backtickRe = RegExp(r'`([A-Za-z_][A-Za-z0-9_.]*)`');

/// Extract the first code identifier from a raw method field value.
///
/// Returns `null` when the field is prose (should be skipped for
/// symbol-existence checks).
String? _extractSymbol(String raw) {
  final trimmed = raw.trim();

  // 1. Backtick wins if present.
  final bt = _backtickRe.firstMatch(trimmed);
  if (bt != null) {
    final inner = bt.group(1)!;
    // First identifier inside the backtick (e.g. `Foo.bar` → `Foo`)
    return RegExp(r'[A-Za-z_][A-Za-z0-9_]*').firstMatch(inner)?.group(0);
  }

  // 2. Bare identifier / Dotted.Path → take first identifier.
  if (_bareSymbolRe.hasMatch(trimmed)) {
    return RegExp(r'[A-Za-z_][A-Za-z0-9_]*').firstMatch(trimmed)?.group(0);
  }

  // 3. Prose — skip symbol check.
  return null;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final projectRoot = Directory.current.path;
  final registryFile = File('$projectRoot/docs/sot_registry.yaml');

  if (!registryFile.existsSync()) {
    stderr.writeln('[check_sot_registry_parity] ERROR: docs/sot_registry.yaml not found');
    exit(1);
  }

  final registryContent = registryFile.readAsStringSync();
  final errors = <String>[];

  // ── Track matched ranges so inline parsers don't double-count ──
  // We record the byte-offsets of every match from blockRegex so the
  // inline parsers can skip entries that are sub-spans of a block match.
  // (Simpler approach: just de-duplicate by (relPath, firstId) pairs.)
  final checkedEntries = <String>{};

  // ── 1. Validate writer/reader file:line + method existence (block form) ──
  //
  // Entries look like:
  //   - file: lib/foo/bar.dart
  //     line_range: 10-200
  //     method: doThing          ← optional
  final blockRegex = RegExp(
    r'file:\s*([^\n]+)\n\s*line_range:\s*(\d+)-(\d+)(?:\n\s*method:\s*([^\n]+))?',
    multiLine: true,
  );

  for (final m in blockRegex.allMatches(registryContent)) {
    final relPath = m.group(1)!.trim();
    final startLine = int.parse(m.group(2)!);
    final endLine = int.parse(m.group(3)!);
    final methodRaw = m.group(4)?.trim();

    final f = File('$projectRoot/$relPath');
    if (!f.existsSync()) {
      errors.add('[file-missing] $relPath');
      continue;
    }

    final lines = f.readAsLinesSync();
    final lineCount = lines.length;

    if (startLine < 1) {
      errors.add('[range-start<1] $relPath:$startLine');
    }
    if (endLine != 9999 && endLine > lineCount) {
      errors.add('[range-overflow] $relPath line_range $startLine-$endLine vs $lineCount lines');
    }

    if (methodRaw != null && methodRaw.isNotEmpty && methodRaw != 'self-contained') {
      final firstId = _extractSymbol(methodRaw);
      if (firstId != null) {
        final entryKey = '$relPath::$firstId';
        checkedEntries.add(entryKey);

        // Strip comments before searching so a symbol that exists ONLY in
        // a comment is treated as missing.
        final whole = _stripComments(lines.join('\n'));
        if (!whole.contains(firstId)) {
          errors.add('[method-missing-in-code] $relPath method `$firstId` not found in non-comment code');
        } else {
          // In-range check — now an ERROR (was WARN).
          final lo = (startLine - 1).clamp(0, lineCount);
          final hi = (endLine == 9999 ? lineCount : endLine).clamp(0, lineCount);
          final slice = _stripComments(lines.sublist(lo, hi).join('\n'));
          if (!slice.contains(firstId)) {
            errors.add('[stale-line-range] $relPath:$startLine-$endLine method `$firstId` is elsewhere in file');
          }
        }
      }
      // If firstId == null → prose method, skip symbol check (no false positive).
    }
  }

  // ── 2. ist_sites inline maps: - { file: PATH, line: N, fn: SYMBOL } ──
  //    (Also handles `method:` key instead of `fn:` for completeness.)
  //    Treat line N as a 1-line range for the stale-range check.
  //
  // Regex: matches `{ file: <path>, line: <N>, fn: <symbol> }`
  // or `{ file: <path>, line: <N>, method: <symbol> }` (not inside "notes: ...")
  //
  // NOTE: The inline entries in the singleton_lifecycle_resets concept have
  // `method:` with prose values like `"SyncService._() constructor → _registerLifecycle()"`.
  // Those will parse as firstId=null → skipped. Correct.
  final inlineFnRegex = RegExp(
    r'\{\s*file:\s*([^,}]+),\s*line:\s*(\d+),\s*(?:fn|method):\s*"?([^",}\n]+)"?',
    multiLine: true,
  );

  for (final m in inlineFnRegex.allMatches(registryContent)) {
    final relPath = m.group(1)!.trim();
    final lineNum = int.parse(m.group(2)!);
    final symbolRaw = m.group(3)!.trim();

    // Skip entries already covered by the block-form parser (same file+symbol).
    final firstId = _extractSymbol(symbolRaw);
    if (firstId == null) continue; // prose → skip

    final entryKey = '$relPath::$firstId';
    if (checkedEntries.contains(entryKey)) continue;
    checkedEntries.add(entryKey);

    final f = File('$projectRoot/$relPath');
    if (!f.existsSync()) {
      errors.add('[file-missing] $relPath (ist_site fn: $firstId)');
      continue;
    }

    final lines = f.readAsLinesSync();
    final lineCount = lines.length;
    final whole = _stripComments(lines.join('\n'));

    if (!whole.contains(firstId)) {
      errors.add('[method-missing-in-code] $relPath ist_site fn `$firstId` not found in non-comment code');
    } else {
      // Stale-range check: symbol should be on or near line N.
      // We check a ±5-line window around the cited line to allow minor drift.
      final lo = (lineNum - 6).clamp(0, lineCount);
      final hi = (lineNum + 5).clamp(0, lineCount);
      final slice = _stripComments(lines.sublist(lo, hi).join('\n'));
      if (!slice.contains(firstId)) {
        errors.add('[stale-line-range] $relPath:$lineNum ist_site fn `$firstId` is elsewhere in file');
      }
    }
  }

  // ── 3. Orphan WriteService/Repository classes ──
  //
  // Scan lib/ for `class XxxWriteService` and `class XxxRepository`.
  // If the class name doesn't appear anywhere in the registry text, warn.
  final orphans = <String>[];
  final classDeclRegex = RegExp(
    r'\bclass\s+([A-Z][A-Za-z0-9_]*?(?:WriteService|Repository))\b',
  );

  final libDir = Directory('$projectRoot/lib');
  if (libDir.existsSync()) {
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      for (final m in classDeclRegex.allMatches(content)) {
        final cls = m.group(1)!;
        // Allow generic base classes / mixins.
        if (cls == 'Repository' || cls == 'WriteService') continue;
        if (!registryContent.contains(cls)) {
          final rel = entity.path
              .replaceAll('\\', '/')
              .replaceFirst('$projectRoot/', '');
          orphans.add('$cls  ($rel)');
        }
      }
    }
  }

  // ── Report ──
  var hasFailures = false;

  if (errors.isNotEmpty) {
    final tag = warnOnly ? 'WARN (--warn-only mode)' : 'FAIL';
    stderr.writeln('\n[check_sot_registry_parity] $tag — ${errors.length} registry parity errors:');
    for (final e in errors) {
      stderr.writeln('  $e');
    }
    if (!warnOnly) hasFailures = true;
  }

  if (orphans.isNotEmpty) {
    stderr.writeln('\n[check_sot_registry_parity] WARN — ${orphans.length} '
        'WriteService/Repository classes not mentioned in registry:');
    for (final o in orphans.take(20)) {
      stderr.writeln('  $o');
    }
    if (orphans.length > 20) {
      stderr.writeln('  ... and ${orphans.length - 20} more.');
    }
    // Orphans are warnings, not failures — registry can lag.
  }

  if (!hasFailures) {
    stdout.writeln(
        '[check_sot_registry_parity] ${warnOnly ? "WARN-ONLY BASELINE" : "PASS"} — '
        'registry file:line parity checked '
        '(${errors.length} errors, '
        '${orphans.length} orphan service/repo classes warned).');
    exit(0);
  } else {
    exit(1);
  }
}
