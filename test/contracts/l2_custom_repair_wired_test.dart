// c3e9a4 (d4b8e1 Batch 0b) — PRESENCE ONLY (source-grep, said plainly): the
// L2 repair migrator is called from BOTH post-restore paths, after the
// plan-integrity heal (it must see the restored, re-filled rows) and before
// the weekly refill / rollover. Its behaviour is pinned by
// l2_custom_append_repair_migrator_test.dart; the restore-settled gate inside
// the migrator, not these call sites, decides whether it acts.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [src] without `//` line comments (none of these files puts `//` in a string
/// on the lines that matter).
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  const heal = 'lib/features/auth/screens/restoring/heal_after_restore.dart';
  const screen = 'lib/features/auth/screens/restoring_screen.dart';

  test('the shared helper runs the migrator and records a non-fatal', () {
    final src = _code(heal);
    expect(src, contains('Future<void> _runL2CustomRepair() async'));
    expect(src, contains('L2CustomAppendRepairMigrator.runIfNeeded()'));
    expect(src, contains("reason: 'bg_heal_l2_custom_repair'"));
  });

  test('background heal: after PlanIntegrityReconciler, before the refill',
      () {
    final src = _code(heal);
    final body = src.substring(
        src.indexOf('Future<void> _healAfterRestoreInBackground()'),
        src.indexOf('Future<void> _runL2CustomRepair()'));
    final reconcile = body.indexOf('PlanIntegrityReconciler.reconcile(');
    final repair = body.indexOf('await _runL2CustomRepair();');
    final refill = body.indexOf('refillIfNewWeek()');
    expect(reconcile, greaterThan(-1));
    expect(repair, greaterThan(reconcile));
    expect(refill, greaterThan(repair));
    expect('await _runL2CustomRepair();'.allMatches(body).length, 1);
  });

  test('foreground (_ensureOwnershipBeforeHome): after the plan-integrity '
      'heal, before the rollover', () {
    final src = _code(screen);
    // From the method's own definition: `_goHome` calls runRolloverNow too.
    final body = src.substring(
        src.indexOf('Future<void> _ensureOwnershipBeforeHome('));
    final reconcile = body.indexOf('PlanIntegrityReconciler.reconcile(');
    final repair = body.indexOf('await _runL2CustomRepair();');
    final rollover = body.indexOf('runRolloverNow(ref)');
    expect(reconcile, greaterThan(-1));
    expect(repair, greaterThan(reconcile));
    expect(rollover, greaterThan(repair));
    expect('await _runL2CustomRepair();'.allMatches(src).length, 1);
    expect(src, contains('core/services/l2_custom_append_repair_migrator.dart'));
  });
}
