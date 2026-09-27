// OI-204 gate-before-refactor (CLAUDE.md §4.11). Verifies the sync-fingerprint
// atomicity invariant for the exlog/nlog hash-skip mechanism:
// docs/superpowers/specs/2026-09-19-oi204-delta-sync-design.md §6.
//
// Hard-fail from its first commit (not warn-only-for-24h): this is a brand-new
// mechanism with nothing pre-existing to baseline against.
//
// + the G1 structural rule (day-swapper + sync-load batch, spec §7) — see
// sync_hash_skip_atomicity_lib.dart.
import 'dart:io';

import 'sync_hash_skip_atomicity_lib.dart';
import 'sync_no_now_fallback_lib.dart' show isSyncLayerPath;

void main(List<String> args) {
  final workoutFile = File('lib/core/services/sync/sync_workout.dart');
  final nutritionFile = File('lib/core/services/sync/sync_nutrition.dart');

  var failed = false;

  if (workoutFile.existsSync()) {
    final v = checkDomainAtomicity(workoutFile.readAsStringSync(), exlogSpec);
    if (v != null) {
      stderr.writeln('FAIL sync_workout.dart: ${v.message}');
      failed = true;
    }
  }
  if (nutritionFile.existsSync()) {
    final v = checkDomainAtomicity(nutritionFile.readAsStringSync(), nlogSpec);
    if (v != null) {
      stderr.writeln('FAIL sync_nutrition.dart: ${v.message}');
      failed = true;
    }
  }

  // G1 structural rule (day-swapper + sync-load, spec §7). ⚠ WARN IS THE
  // BUILT-IN DEFAULT until Task 32 flips `_structuralHardFailByDefault`
  // (CLAUDE.md §4.11): the pre-commit loop and CI run this script with no
  // arguments. `--hard` forces the failing exit (e2e-tested).
  final structural = checkSyncStructure(_syncLayerSources());
  final hardStructural = _structuralHardFailByDefault || args.contains('--hard');
  if (structural.isNotEmpty) {
    stderr.writeln('${hardStructural ? 'FAIL' : 'WARN'} sync write structure '
        '(G1) — ${structural.length} violation(s):');
    for (final v in structural) {
      stderr.writeln('  $v');
    }
    if (hardStructural) failed = true;
  }

  if (failed) exit(1);
  print('check_sync_hash_skip_atomicity: OK');
}

const bool _structuralHardFailByDefault = false;

Map<String, String> _syncLayerSources() {
  final out = <String, String>{};
  final dir = Directory('lib/core/services/sync');
  if (dir.existsSync()) {
    for (final e in dir.listSync(recursive: true)) {
      if (e is! File) continue;
      final rel = e.path.replaceAll(r'\', '/');
      if (isSyncLayerPath(rel)) out[rel] = e.readAsStringSync();
    }
  }
  final svc = File('lib/core/services/sync_service.dart');
  if (svc.existsSync()) out[svc.path] = svc.readAsStringSync();
  return out;
}
