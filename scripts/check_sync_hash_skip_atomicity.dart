// OI-204 gate-before-refactor (CLAUDE.md §4.11). Verifies the sync-fingerprint
// atomicity invariant for the exlog/nlog hash-skip mechanism:
// docs/superpowers/specs/2026-09-19-oi204-delta-sync-design.md §6.
//
// Hard-fail from its first commit (not warn-only-for-24h): this is a brand-new
// mechanism with nothing pre-existing to baseline against.
import 'dart:io';

import 'sync_hash_skip_atomicity_lib.dart';

void main() {
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

  if (failed) exit(1);
  print('check_sync_hash_skip_atomicity: OK');
}
