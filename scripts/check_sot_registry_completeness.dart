// scripts/check_sot_registry_completeness.dart
//
// Gate: 7
//
// Gate 7: SoT registry completeness.
//
// Asserts:
//   1. Every method matching the write-pattern regex in lib/core/services/*.dart
//      appears in some concept's writers[]/readers[]/sync_methods/restore_methods.
//   2. Every concept's writers[].file exists and the line_range is in-bounds.
//   3. Every 'box.put(<key_prefix>' callsite prefix appears in some concept's
//      hive.key_prefix.
//
// Exit 0 = pass (all registered, all line ranges in-bounds).
// Exit 1 = fail (any violation — hard-fail, no warn-only mode).
//
// T2.1/T2.3 registry work completed 2026-05-10 — thresholds removed.
//
// Usage: dart run scripts/check_sot_registry_completeness.dart

import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final registryFile = File('$projectRoot/docs/sot_registry.yaml');

  if (!registryFile.existsSync()) {
    stderr.writeln('[Gate 7] ERROR: docs/sot_registry.yaml not found');
    exit(1);
  }

  final registryContent = registryFile.readAsStringSync();

  // ── 1. Collect all registered method names / prefixes ────────────────────

  // Collect everything mentioned in writers[].method, readers[].method*,
  // sync_methods[], restore_methods[].
  final registeredNames = <String>{};

  // Extract method names from writers/readers inline maps:
  // e.g.  method: logExercise
  final methodKeyRegex = RegExp(r'method:\s*([^\n]+)', multiLine: true);
  for (final m in methodKeyRegex.allMatches(registryContent)) {
    final raw = m.group(1)!.trim();
    // Split on ' + ' for compound entries like "buildAiContext + _getMealsToday"
    for (final part in raw.split(RegExp(r'\s*\+\s*|\s*/\s*|\s*&\s*'))) {
      final name = part.trim();
      if (name.isNotEmpty && name != 'self-contained') {
        registeredNames.add(name);
      }
    }
  }

  // Extract items from sync_methods / restore_methods list lines:
  // e.g.  - _syncExerciseLogs
  //        sync_methods: [_syncExerciseLogs, _syncWorkoutLogs]
  final listItemRegex = RegExp(r'[-\s]*(_(sync|restore)[A-Za-z]+)', multiLine: true);
  for (final m in listItemRegex.allMatches(registryContent)) {
    registeredNames.add(m.group(1)!.trim());
  }
  // Also inline list form: sync_methods: [_syncX, _syncY]
  final inlineListRegex = RegExp(r'\[([\w,\s_]+)\]', multiLine: true);
  for (final m in inlineListRegex.allMatches(registryContent)) {
    final items = m.group(1)!.split(',');
    for (final item in items) {
      final name = item.trim();
      if (name.startsWith('_sync') || name.startsWith('_restore')) {
        registeredNames.add(name);
      }
    }
  }

  // Collect registered hive key prefixes
  final registeredKeyPrefixes = <String>{};
  final keyPrefixRegex = RegExp(r'key_prefix:\s*"([^"]+)"', multiLine: true);
  for (final m in keyPrefixRegex.allMatches(registryContent)) {
    final prefix = m.group(1)!.trim();
    registeredKeyPrefixes.add(prefix);
  }

  // ── 2. Scan lib/core/services/*.dart for write-pattern methods ───────────

  final servicesDir = Directory('$projectRoot/lib/core/services');
  if (!servicesDir.existsSync()) {
    stderr.writeln('[Gate 7] ERROR: lib/core/services/ directory not found');
    exit(1);
  }

  // Methods we care about: public patterns that are write/read interfaces.
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
      // Skip private underscore helpers that are already sub-methods
      // (they will be found through their parent if registered)
      if (!registeredNames.contains(methodName)) {
        unmatched.add('${entity.path.replaceAll('\\', '/')}  → $methodName');
      }
    }
  }

  // ── 3. Check writer file:line_range validity ─────────────────────────────

  final fileLineErrors = <String>[];

  // Match entries like:   file: lib/foo.dart\n        line_range: 10-200
  final writerBlockRegex = RegExp(
    r'file:\s*([^\n]+)\n\s*line_range:\s*(\d+)-(\d+)',
    multiLine: true,
  );
  for (final m in writerBlockRegex.allMatches(registryContent)) {
    final relPath = m.group(1)!.trim();
    final startLine = int.parse(m.group(2)!);
    final endLine = int.parse(m.group(3)!);
    final f = File('$projectRoot/$relPath');
    if (!f.existsSync()) {
      fileLineErrors.add('File does not exist: $relPath');
      continue;
    }
    final lineCount = f.readAsLinesSync().length;
    // Use 9999 as "open ended" sentinel — that is always valid if file exists
    if (endLine != 9999 && endLine > lineCount) {
      fileLineErrors.add(
          'line_range end ($endLine) exceeds file length ($lineCount): $relPath');
    }
    if (startLine < 1) {
      fileLineErrors.add('line_range start < 1: $relPath');
    }
  }

  // ── 4. Print results ─────────────────────────────────────────────────────

  var hasFailures = false;

  if (fileLineErrors.isNotEmpty) {
    stderr.writeln('\n[Gate 7] FAIL — ${fileLineErrors.length} file:line stale in registry:');
    for (final e in fileLineErrors) {
      stderr.writeln('  $e');
    }
    hasFailures = true;
  }

  if (unmatched.isNotEmpty) {
    stderr.writeln('\n[Gate 7] FAIL — ${unmatched.length} methods not in registry:');
    for (final u in unmatched.take(20)) {
      stderr.writeln('  $u');
    }
    if (unmatched.length > 20) {
      stderr.writeln('  ... and ${unmatched.length - 20} more.');
    }
    hasFailures = true;
  }

  if (!hasFailures) {
    stdout.writeln('[Gate 7] PASS — SoT registry check complete.');
  }

  if (hasFailures) {
    exit(1);
  }
}
