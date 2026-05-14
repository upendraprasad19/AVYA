// scripts/check_sync_fanout.dart
//
// Gate 11: Every sync_method and restore_method declared in the registry
//          exists as a Future<...> declaration in sync_service.dart.
//
// Exit 0 = pass.
// Exit 1 = fail.
//
// Usage: dart run scripts/check_sync_fanout.dart

import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final registryFile = File('$projectRoot/docs/sot_registry.yaml');
  final syncServiceFile =
      File('$projectRoot/lib/core/services/sync_service.dart');

  if (!registryFile.existsSync()) {
    stderr.writeln('[Gate 11] ERROR: docs/sot_registry.yaml not found');
    exit(1);
  }
  if (!syncServiceFile.existsSync()) {
    stderr.writeln(
        '[Gate 11] ERROR: lib/core/services/sync_service.dart not found');
    exit(1);
  }

  final registryContent = registryFile.readAsStringSync();

  // refactor/sync-service-part-split (2026-05-13) — SyncService is now
  // split across `sync_service.dart` plus N part files under
  // `lib/core/services/sync/`. Concatenate all of them so the
  // declaration scan finds methods that moved into part-file extensions.
  final rootSyncContent = syncServiceFile.readAsStringSync();
  final partsDir = Directory('$projectRoot/lib/core/services/sync');
  final partSources = partsDir.existsSync()
      ? partsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .toList()
      : <String>[];
  final syncContent = [rootSyncContent, ...partSources].join('\n\n');

  // ── 1. Extract declared sync/restore method names from sync_service.dart ──

  final declaredMethods = <String>{};

  // Match: "Future<void> _syncXxx(" or "Future<void> syncXxx(" or
  //        "Future<void> pushSnapshot(" or any "Future<X> <methodName>(" pattern.
  // We capture ANY Future-returning method to handle names like pushSnapshot.
  final declarationRegex = RegExp(
    r'Future<[\w<>?]+>\s+([a-zA-Z_][a-zA-Z0-9_]+)\s*\(',
    multiLine: true,
  );
  for (final m in declarationRegex.allMatches(syncContent)) {
    declaredMethods.add(m.group(1)!);
  }
  // Also match void declarations:
  final voidDeclRegex = RegExp(
    r'\bvoid\s+([a-zA-Z_][a-zA-Z0-9_]+)\s*\(',
    multiLine: true,
  );
  for (final m in voidDeclRegex.allMatches(syncContent)) {
    declaredMethods.add(m.group(1)!);
  }

  // ── 2. Extract sync_methods / restore_methods from registry ───────────────

  final requiredMethods = <String>{};

  // List-form:
  //   sync_methods:
  //     - _syncExerciseLogs
  final listItemRegex = RegExp(
      r'(sync_methods|restore_methods):\s*\n((?:\s*-\s*\S+\n)+)',
      multiLine: true);
  for (final m in listItemRegex.allMatches(registryContent)) {
    final items = m.group(2)!;
    for (final item in items.split('\n')) {
      final name = item.replaceAll(RegExp(r'[-\s]'), '').trim();
      if (name.isNotEmpty) requiredMethods.add(name);
    }
  }

  // Inline-list form: sync_methods: [_syncX, _syncY]
  final inlineListRegex = RegExp(
      r'(sync_methods|restore_methods):\s*\[([^\]]+)\]',
      multiLine: true);
  for (final m in inlineListRegex.allMatches(registryContent)) {
    for (final part in m.group(2)!.split(',')) {
      final name = part.trim();
      if (name.isNotEmpty && !name.startsWith('#')) {
        requiredMethods.add(name);
      }
    }
  }

  // ── 3. Find mismatches ────────────────────────────────────────────────────

  final missing = <String>[];
  for (final method in requiredMethods) {
    if (!declaredMethods.contains(method)) {
      missing.add(method);
    }
  }

  // ── 4. Report ─────────────────────────────────────────────────────────────

  if (missing.isEmpty) {
    stdout.writeln('[Gate 11] PASS — all ${requiredMethods.length} registry'
        ' sync/restore methods declared in sync_service.dart.');
    exit(0);
  } else {
    stderr.writeln(
        '\n[Gate 11] FAIL — ${missing.length} methods in registry not found'
        ' in sync_service.dart:');
    for (final m in missing) {
      stderr.writeln('  $m');
    }
    stderr.writeln('\n  Fix: add the missing method(s) to sync_service.dart'
        ' OR remove them from docs/sot_registry.yaml if they are stale.');
    exit(1);
  }
}
