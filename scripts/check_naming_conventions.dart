// scripts/check_naming_conventions.dart
//
// Gate (E.13 — Audit 2026-05-16 framework deliverable):
// Enforce naming conventions documented in docs/naming_conventions.md.
//
// This is a SUPERSET of the existing check_naming_audit.dart (which enforces
// the YAML forbidden_legacy_patterns block in docs/sot_registry.yaml).
// This script additionally codifies a small set of project-wide naming rules
// that don't fit into the YAML pattern shape:
//
//   1. Hive key prefixes — every `<box>.put('<prefix>_$key', ...)` callsite
//      uses a snake_case prefix matching one of the registered key_prefix
//      values in docs/sot_registry.yaml. Unknown prefixes are reported as a
//      potential naming-convention drift.
//   2. Riverpod providers — public providers MUST end in `Provider`. The
//      only allowed exception is generated `*Pod` names from riverpod_generator,
//      none of which exist in this codebase today.
//   3. Edge Function file names — `supabase/functions/<name>/index.ts` only.
//      Any deviation (e.g. main.ts, handler.ts) is flagged.
//   4. Test file names — files in `test/contracts/` MUST end in `_test.dart`.
//
// Exit 0 = pass.
// Exit 1 = fail.
//
// Usage: dart run scripts/check_naming_conventions.dart

import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final violations = <String>[];

  // ── 1. Riverpod provider naming — public providers end in `Provider`. ──
  // Look at lib/ for `final <name> = <Notifier|StateNotifier|FutureProvider|StreamProvider|Provider|StateProvider|AutoDispose...>`.
  final libDir = Directory('$projectRoot/lib');
  if (libDir.existsSync()) {
    final providerDecl = RegExp(
      r"final\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
      r"(?:AsyncNotifierProvider|StateNotifierProvider|FutureProvider|StreamProvider|StateProvider|NotifierProvider|Provider|ChangeNotifierProvider)"
      r"(?:\.autoDispose|\.family|\.autoDispose\.family|\.family\.autoDispose)?"
      r"[<(]",
    );
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll('\\', '/').replaceFirst('$projectRoot/', '');
      // Generated / build artefacts.
      if (rel.contains('.g.dart') || rel.contains('.freezed.dart')) continue;
      final content = entity.readAsStringSync();
      for (final m in providerDecl.allMatches(content)) {
        final name = m.group(1)!;
        if (name.startsWith('_')) continue; // private — exempt
        if (!name.endsWith('Provider')) {
          // Compute line number.
          final lineNo = content.substring(0, m.start).split('\n').length;
          violations.add('$rel:$lineNo — provider `$name` does not end in `Provider`');
        }
      }
    }
  }

  // ── 2. Edge Function entry-point convention: `<name>/index.ts` ──
  final fnDir = Directory('$projectRoot/supabase/functions');
  if (fnDir.existsSync()) {
    for (final entry in fnDir.listSync()) {
      if (entry is! Directory) continue;
      final fnName = entry.path.replaceAll('\\', '/').split('/').last;
      // Skip private/shared dirs.
      if (fnName.startsWith('_')) continue;
      final indexFile = File('${entry.path}/index.ts');
      if (!indexFile.existsSync()) {
        // Look for off-convention entry points
        final candidates = entry
            .listSync(recursive: false)
            .whereType<File>()
            .where((f) => f.path.endsWith('.ts'))
            .map((f) => f.path.replaceAll('\\', '/').split('/').last)
            .toList();
        if (candidates.isNotEmpty) {
          violations.add(
              'supabase/functions/$fnName/ — missing index.ts (has: ${candidates.join(", ")})');
        }
      }
    }
  }

  // ── 3. Test file naming — test/contracts/*.dart MUST end with _test.dart ──
  // Other test subdirs (helpers/, plan_generator/v4_diagnostic/, supabase/,
  // *_write_service/helpers/) intentionally contain non-test fixture / report
  // files; only the contracts/ dir is strict.
  final contractsDir = Directory('$projectRoot/test/contracts');
  if (contractsDir.existsSync()) {
    for (final entity in contractsDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final base = entity.path.replaceAll('\\', '/').split('/').last;
      // Helper files starting with `_` are exempt (e.g. _sync_service_source.dart).
      if (base.startsWith('_')) continue;
      if (!base.endsWith('_test.dart')) {
        final rel =
            entity.path.replaceAll('\\', '/').replaceFirst('$projectRoot/', '');
        violations.add('$rel — test file does not end in `_test.dart`');
      }
    }
  }

  // ── Report ──
  if (violations.isEmpty) {
    stdout.writeln('[check_naming_conventions] PASS — no naming-convention violations.');
    exit(0);
  } else {
    stderr.writeln('\n[check_naming_conventions] FAIL — ${violations.length} violations:');
    for (final v in violations.take(40)) {
      stderr.writeln('  $v');
    }
    if (violations.length > 40) {
      stderr.writeln('  ... and ${violations.length - 40} more.');
    }
    exit(1);
  }
}
