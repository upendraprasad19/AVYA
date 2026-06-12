// Bug f1c8e4 — pins that the wlog-type backfill migrator is actually invoked
// in the post-auth boot sequence. Without the wiring the heal silently never
// runs and legacy installs keep undercounting. Mirrors
// streak_freeze_clamp_migrator_wired_test.
//
// closes-diagnose: f1c8e4

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth_provider invokes WlogTypeBackfillMigrator.runIfNeeded at boot', () {
    final src = File('lib/features/auth/providers/auth_provider.dart')
        .readAsStringSync();
    // Strip line comments so the explanatory block doesn't false-positive.
    final stripped =
        src.split('\n').map((l) => l.replaceFirst(RegExp(r'//.*$'), '')).join('\n');
    expect(
      stripped.contains(
          "import 'package:icanbefitter/core/services/wlog_type_backfill_migrator.dart'"),
      isTrue,
      reason: 'auth_provider must import the migrator.',
    );
    expect(
      stripped.contains('WlogTypeBackfillMigrator.runIfNeeded()'),
      isTrue,
      reason: 'auth_provider._ensureLocalUser must call '
          'WlogTypeBackfillMigrator.runIfNeeded() in the boot migrator '
          'sequence — otherwise legacy type-less wlog rows never heal (f1c8e4).',
    );
  });
}
