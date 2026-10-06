// OI-252 B-pass finding 2 (2026-09-27) — `_restoreWorkoutTemplates` must run
// `TemplateIdentityMigrator.runIfNeeded` before restoring, exactly like its
// sibling `_syncWorkoutTemplates` already does. Pre-fix, `restoreLightweightAlways`
// (the path that fires on every normal sign-in once Hive has local data — the
// common case for a returning user) called `_restoreWorkoutTemplates` directly
// with no migrator gate at all, so a device holding a pre-rework legacy-keyed
// template (`tmpl_<ms>` / `tmpl_<namehash>`) never got it rekeyed on this path:
// the cloud-authoritative copy landed under a NEW `tmpl_<uuid>` key while the
// old legacy row sat untouched, rendering as a duplicate in the Train tab until
// `weeklyFullSync` happened to run days later.
//
// The migrator's own legacy-key-resolve logic makes a live Supabase query
// once any legacy key is found, and this repo has NO Supabase-mocking seam
// anywhere (`SupabaseService.client` hardcodes `Supabase.instance.client`,
// never initialized in unit tests — see `test/helpers/hive_test_setup.dart`).
// That branch is therefore untestable here without disproportionate new
// mocking infrastructure (verified: zero existing tests reference
// `TemplateIdentityMigrator` at all, zero mock-http/mock-Supabase packages in
// pubspec.yaml). What IS testable, and what this fix actually changed, is
// whether `_restoreWorkoutTemplates` REACHES the gate at all — pinned via
// `TemplateIdentityMigrator.invocationCountForTest`, a test-only counter
// incremented as the first statement of `runIfNeeded` (before any Hive scan
// or network call) for exactly this purpose.
//
// closes-diagnose: 2026-09-27-deleted-workout-template-resurrects-via-restore-f4a8c2
// BEHAVIORAL: seeds the real workoutBox + runs the REAL `_restoreWorkoutTemplates`
// via the `restoreWorkoutTemplatesForTest` seam (preFetched rows, no Supabase
// query for the row read). FAILS against the pre-fix code (the gate call
// deleted, or its `if (!migrated) return;` inverted).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/template_identity.dart';
import 'package:icanbefitter/core/services/template_identity_migrator.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
    TemplateIdentityMigrator.invocationCountForTest = 0;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    TemplateIdentityMigrator.invocationCountForTest = 0;
    await tearDownHiveForTests(tempDir);
  });

  test(
      '_restoreWorkoutTemplates invokes the legacy-key migrator before '
      'restoring (OI-252 B-pass finding 2)', () async {
    await SyncService.instance
        .restoreWorkoutTemplatesForTest(kTestUserId, preFetched: const []);

    expect(TemplateIdentityMigrator.invocationCountForTest, 1,
        reason: 'pre-fix, restoreLightweightAlways\'s call to '
            '_restoreWorkoutTemplates never ran the legacy-key migrator at '
            'all on this path — only _syncWorkoutTemplates (a different, '
            'less-frequently-run entry point) did. This counter, incremented '
            'as the FIRST statement of TemplateIdentityMigrator.runIfNeeded, '
            'would read 0 without the fix.');
  });

  test(
      'restore still hydrates a live cloud template normally after the '
      'migrator gate (no legacy keys present — the common case)', () async {
    const cloudId = 'ffffffff-1111-2222-3333-444444444444';
    final hiveKey = templateKeyFor(cloudId);

    await SyncService.instance.restoreWorkoutTemplatesForTest(
      kTestUserId,
      preFetched: [
        {
          'id': cloudId,
          'name': 'Push Day',
          'description': null,
          'workout_type': 'strength',
          'created_at': '2026-09-01T00:00:00Z',
          'last_used_at': null,
          'deleted_at': null,
          'template_exercises': [],
        },
      ],
    );

    final row = HiveService.instance.workoutBox.get(hiveKey) as Map?;
    expect(row, isNotNull,
        reason: 'a live (non-deleted) cloud template must still be written '
            'to Hive after the added migrator gate — an inverted gate '
            '(`if (migrated) return;` instead of `if (!migrated) return;`) '
            'would short-circuit this, since the no-legacy-keys fast path '
            'makes `runIfNeeded` resolve to `true`.');
    expect(row!['name'], 'Push Day');
    expect(row['type'], 'template');
  });
}
