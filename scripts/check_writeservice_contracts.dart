// scripts/check_writeservice_contracts.dart
//
// Gate 9: Every WriteService concept with a hive block has a contract test.
//
// For every concept in docs/sot_registry.yaml that has a hive.key_prefix,
// asserts that test/contracts/<concept>_writer_to_reader_test.dart exists.
//
// Exit 0 = pass (all contract tests present).
// Exit 1 = fail (any missing — hard-fail, no warn-only mode).
//
// T3.1 contract-test work completed 2026-05-10 — threshold removed.
//
// Usage: dart run scripts/check_writeservice_contracts.dart

import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final registryFile = File('$projectRoot/docs/sot_registry.yaml');

  if (!registryFile.existsSync()) {
    stderr.writeln('[Gate 9] ERROR: docs/sot_registry.yaml not found');
    exit(1);
  }

  final registryContent = registryFile.readAsStringSync();

  // ── 1. Find all concepts that have a hive.key_prefix ────────────────────
  // Parse concept blocks: look for "- concept: <name>" followed eventually
  // by "key_prefix:".

  final conceptsWithHive = <String>[];

  // Split into concept blocks by "  - concept:"
  final conceptBlocks = registryContent.split(RegExp(r'\n  - concept:\s*'));
  for (var i = 1; i < conceptBlocks.length; i++) {
    final block = conceptBlocks[i];
    // First line is the concept name
    final nameMatch = RegExp(r'^(\S+)').firstMatch(block);
    if (nameMatch == null) continue;
    final conceptName = nameMatch.group(1)!.trim();

    // Does this block have a key_prefix?
    if (block.contains('key_prefix:')) {
      conceptsWithHive.add(conceptName);
    }
  }

  // ── 2. Check for contract test existence ─────────────────────────────────

  final contractsDir = '$projectRoot/test/contracts';
  final missing = <String>[];

  for (final concept in conceptsWithHive) {
    final expectedPath = '$contractsDir/${concept}_writer_to_reader_test.dart';
    if (!File(expectedPath).existsSync()) {
      missing.add('$concept → test/contracts/${concept}_writer_to_reader_test.dart');
    }
  }

  // ── 3. Report ─────────────────────────────────────────────────────────────

  if (missing.isEmpty) {
    stdout.writeln('[Gate 9] PASS — all ${conceptsWithHive.length} hive-bearing'
        ' concepts have contract tests.');
    exit(0);
  }

  stderr.writeln(
      '\n[Gate 9] FAIL — ${missing.length} contract tests missing'
      ' (add test/contracts/<concept>_writer_to_reader_test.dart for each):');
  for (final m in missing) {
    stderr.writeln('  MISSING: $m');
  }
  exit(1);
}
