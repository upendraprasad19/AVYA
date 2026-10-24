// test/contracts/sot_registry_completeness_test.dart
//
// Lightweight mirror of /build-apk Gate 7 (check_sot_registry_completeness.dart).
//
// Rather than spawning a subprocess (slow, PATH-sensitive on Windows), this test
// re-implements the two key assertions of Gate 7 as fast source-grep checks:
//
//  1. Every method matching the write-pattern regex in lib/core/services/*.dart
//     appears by name somewhere in docs/sot_registry.yaml.
//
//  2. Every file:line_range entry in the registry resolves to a real file whose
//     line count encompasses the declared range.
//
// Gate 7 (the CLI script) remains the authoritative hard-fail gate in /build-apk.
// This test is a fast pre-commit belt-and-suspenders that runs under flutter test.
//
// Usage: flutter test test/contracts/sot_registry_completeness_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String registryContent;
  late String projectRoot;

  setUpAll(() {
    projectRoot = Directory.current.path;
    final registryFile = File('$projectRoot/docs/sot_registry.yaml');
    expect(registryFile.existsSync(), isTrue,
        reason: 'docs/sot_registry.yaml must exist');
    registryContent = registryFile.readAsStringSync();
  });

  test('[Gate 7 mirror] every write-pattern method in lib/core/services/ appears in registry', () {
    final servicesDir = Directory('$projectRoot/lib/core/services');
    expect(servicesDir.existsSync(), isTrue);

    final writeMethodPattern = RegExp(
      r'(async\s+)?(Future<\w+>\s+|void\s+)'
      r'(_sync[A-Z][A-Za-z]+|_restore[A-Z][A-Za-z]+|'
      r'log[A-Z][A-Za-z]+|upsert[A-Z][A-Za-z]+|'
      r'complete[A-Z][A-Za-z]+|delete[A-Z][A-Za-z]+)\s*\(',
      multiLine: true,
    );

    final unmatched = <String>[];

    for (final entity in servicesDir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      for (final m in writeMethodPattern.allMatches(content)) {
        final methodName = m.group(3)!;
        if (!registryContent.contains(methodName)) {
          unmatched.add(
              '${entity.path.replaceAll(r'\', '/')} → $methodName');
        }
      }
    }

    expect(unmatched, isEmpty,
        reason: 'Methods not registered in docs/sot_registry.yaml:\n'
            '  ${unmatched.take(10).join('\n  ')}');
  });

  test('[Gate 7 mirror] every file:line_range entry resolves to real file within bounds', () {
    final writerBlockRegex = RegExp(
      r'file:\s*([^\n]+)\n\s*line_range:\s*(\d+)-(\d+)',
      multiLine: true,
    );

    final errors = <String>[];

    for (final m in writerBlockRegex.allMatches(registryContent)) {
      final relPath = m.group(1)!.trim();
      final startLine = int.parse(m.group(2)!);
      final endLine = int.parse(m.group(3)!);
      final f = File('$projectRoot/$relPath');

      if (!f.existsSync()) {
        errors.add('File does not exist: $relPath');
        continue;
      }

      final lineCount = f.readAsLinesSync().length;
      // 9999 is the "open-ended" sentinel — always valid if file exists
      if (endLine != 9999 && endLine > lineCount) {
        errors.add(
          'line_range end ($endLine) exceeds file length ($lineCount): $relPath',
        );
      }
      if (startLine < 1) {
        errors.add('line_range start < 1: $relPath');
      }
    }

    expect(errors, isEmpty,
        reason: 'Stale file:line_range entries in docs/sot_registry.yaml:\n'
            '  ${errors.take(10).join('\n  ')}');
  });
}
