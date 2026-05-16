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
//      the cited `method:` name actually appears on a line inside the
//      range (cheap heuristic — grep for the method name in the file).
//
//   2. Source-grep `lib/` for class definitions matching `*WriteService`
//      or `*Repository`. Each match should appear somewhere in
//      docs/sot_registry.yaml (as a writer or as part of a reader file).
//      Unregistered service/repo classes are warnings — they indicate a
//      SoT concept that hasn't been documented.
//
// Exit 0 = pass.
// Exit 1 = fail.
//
// Usage: dart run scripts/check_sot_registry_parity.dart

import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final registryFile = File('$projectRoot/docs/sot_registry.yaml');

  if (!registryFile.existsSync()) {
    stderr.writeln('[check_sot_registry_parity] ERROR: docs/sot_registry.yaml not found');
    exit(1);
  }

  final registryContent = registryFile.readAsStringSync();
  final errors = <String>[];
  final staleLineRanges = <String>[];

  // ── 1. Validate writer/reader file:line + method existence ──
  //
  // Entries look like:
  //   - file: lib/foo/bar.dart
  //     line_range: 10-200
  //     method: doThing
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
      // Take only the first identifier — registry entries can be
      // "buildAiContext + _getMealsToday" or "EditWorkoutLogSheet.save".
      final firstId = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').firstMatch(methodRaw)?.group(0);
      if (firstId != null) {
        // Must appear SOMEWHERE in the file (cheap heuristic — methods
        // sometimes drift within the file but the registered line_range
        // can be stale by ±20 lines; we only hard-fail if the method
        // name has vanished entirely).
        final whole = lines.join('\n');
        if (!whole.contains(firstId)) {
          errors.add('[method-missing-in-file] $relPath method `$firstId` not found anywhere in file');
        } else {
          // In-range check is informational only.
          final lo = (startLine - 1).clamp(0, lineCount);
          final hi = (endLine == 9999 ? lineCount : endLine).clamp(0, lineCount);
          final slice = lines.sublist(lo, hi).join('\n');
          if (!slice.contains(firstId)) {
            // Warning, not error — record under `staleLineRanges`.
            staleLineRanges.add('$relPath:$startLine-$endLine method `$firstId` is elsewhere in file');
          }
        }
      }
    }
  }

  // ── 2. Inverse check — orphan WriteService/Repository classes ──
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
    stderr.writeln('\n[check_sot_registry_parity] FAIL — ${errors.length} registry parity errors:');
    for (final e in errors.take(20)) {
      stderr.writeln('  $e');
    }
    if (errors.length > 20) {
      stderr.writeln('  ... and ${errors.length - 20} more.');
    }
    hasFailures = true;
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

  if (staleLineRanges.isNotEmpty) {
    stderr.writeln('\n[check_sot_registry_parity] WARN — ${staleLineRanges.length} '
        'stale line_range hints (method present in file but outside the cited range):');
    for (final s in staleLineRanges.take(10)) {
      stderr.writeln('  $s');
    }
    if (staleLineRanges.length > 10) {
      stderr.writeln('  ... and ${staleLineRanges.length - 10} more.');
    }
  }

  if (!hasFailures) {
    stdout.writeln(
        '[check_sot_registry_parity] PASS — registry file:line parity OK '
        '(${staleLineRanges.length} stale line_ranges warned, '
        '${orphans.length} orphan service/repo classes warned).');
    exit(0);
  } else {
    exit(1);
  }
}
