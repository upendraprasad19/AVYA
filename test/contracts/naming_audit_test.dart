// test/contracts/naming_audit_test.dart
//
// Lightweight mirror of /build-apk Gate 8 (check_naming_audit.dart).
//
// Rather than spawning a subprocess, re-implements the core forbidden-pattern
// scan inline. Same logic as the gate script but without Dart compilation overhead.
//
// Gate 8 (the CLI script) remains the authoritative hard-fail gate in /build-apk.
// This test is a fast pre-commit belt-and-suspenders that runs under flutter test.
//
// Usage: flutter test test/contracts/naming_audit_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Files/directories that are allowed to contain forbidden patterns
// (mirrors _allowedPathFragments in check_naming_audit.dart).
const _allowedPathFragments = [
  'scripts/check_naming_audit.dart',
  'docs/sot_registry.yaml',
  'docs/diagnoses/',
  'CLAUDE.md',
  'MEMORY.md',
  'lib/features/nutrition/screens/nutrition_screen.dart',
  'test/contracts/naming_audit_test.dart',
];

bool _isAllowed(String relPath) {
  for (final fragment in _allowedPathFragments) {
    if (relPath.contains(fragment)) return true;
  }
  return false;
}

void main() {
  late String projectRoot;
  late String registryContent;

  setUpAll(() {
    projectRoot = Directory.current.path;
    final registryFile = File('$projectRoot/docs/sot_registry.yaml');
    expect(registryFile.existsSync(), isTrue,
        reason: 'docs/sot_registry.yaml must exist');
    registryContent = registryFile.readAsStringSync();
  });

  test('[Gate 8 mirror] no forbidden legacy patterns present in lib/', () {
    // Extract forbidden patterns from registry (same regex as gate script).
    final patternLineRegex = RegExp(
      r'\{\s*pattern:\s*"([^"]+)"\s*,\s*reason:\s*"([^"]+)"\s*\}',
      multiLine: true,
    );

    final patterns = <(String, String)>[];
    for (final m in patternLineRegex.allMatches(registryContent)) {
      patterns.add((m.group(1)!, m.group(2)!));
    }

    if (patterns.isEmpty) {
      // No patterns defined — trivially passes.
      return;
    }

    // Only scan lib/ (same as Gate 8 — production code only).
    final libDir = Directory('$projectRoot/lib');
    expect(libDir.existsSync(), isTrue);

    final filesToScan = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    final violations = <String>[];

    for (final (patternStr, reason) in patterns) {
      RegExp regex;
      try {
        regex = RegExp(patternStr, multiLine: true);
      } catch (_) {
        continue; // invalid regex — skip (gate script warns and continues too)
      }

      for (final file in filesToScan) {
        final relPath = file.path
            .replaceAll(r'\', '/')
            .replaceFirst('$projectRoot/', '');
        if (_isAllowed(relPath)) continue;

        final content = file.readAsStringSync();
        final matches = regex.allMatches(content);
        if (matches.isEmpty) continue;

        final lines = content.split('\n');
        for (final match in matches) {
          final lineNo = content.substring(0, match.start).split('\n').length;
          final lineContent =
              lineNo <= lines.length ? lines[lineNo - 1].trim() : '';
          // Skip comment-only lines.
          if (lineContent.startsWith('//') ||
              lineContent.startsWith('/*') ||
              lineContent.startsWith('*')) {
            continue;
          }
          violations.add('$relPath:$lineNo — pattern: $patternStr ($reason)');
        }
      }
    }

    expect(violations, isEmpty,
        reason: 'Forbidden legacy patterns found in lib/:\n'
            '  ${violations.take(10).join('\n  ')}');
  });
}
