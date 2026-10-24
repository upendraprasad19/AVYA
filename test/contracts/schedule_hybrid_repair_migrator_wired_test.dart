// Bug b6e1c8 — pins that the schedule-hybrid repair migrator is actually
// invoked in the post-auth boot sequence, right after WlogTypeBackfillMigrator
// (plan Task 23). Without the wiring the heal silently never runs and the 28
// live hybrid rows (spec §1.4) never self-repair on an existing install.
//
// closes-diagnose: b6e1c8

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth_provider invokes ScheduleHybridRepairMigrator.runIfNeeded at '
      'boot, directly after WlogTypeBackfillMigrator', () {
    final src = File('lib/features/auth/providers/auth_provider.dart')
        .readAsStringSync();
    final stripped = src
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    expect(
      stripped.contains(
          "import 'package:icanbefitter/core/services/schedule_hybrid_repair_migrator.dart'"),
      isTrue,
      reason: 'auth_provider must import the migrator.',
    );

    final wlogIdx = stripped.indexOf('WlogTypeBackfillMigrator.runIfNeeded()');
    final hybridIdx =
        stripped.indexOf('ScheduleHybridRepairMigrator.runIfNeeded()');
    expect(wlogIdx, greaterThan(-1),
        reason: 'sanity check on the precedent call this task orders itself against');
    expect(hybridIdx, greaterThan(-1),
        reason: 'auth_provider._ensureLocalUser must call '
            'ScheduleHybridRepairMigrator.runIfNeeded() in the boot migrator '
            'sequence — otherwise the 28 live hybrid rows never heal (b6e1c8).');
    expect(hybridIdx, greaterThan(wlogIdx),
        reason: 'plan Task 23 requires this migrator to run directly after '
            'WlogTypeBackfillMigrator, not merely "somewhere in boot".');
  });
}
