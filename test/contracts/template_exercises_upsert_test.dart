import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// APK Test #15 closeout / Backlog #2 — template_exercises upsert contract.
///
/// Migration 051 added UNIQUE (template_id, order_index). Now
/// _syncWorkoutTemplates can upsert children with onConflict instead of
/// the fragile DELETE-then-INSERT pattern.
///
/// Pre-fix failure mode: DELETE succeeded, subsequent INSERT errored
/// mid-loop (network blip, FK constraint, payload error). Template was
/// left with PARTIAL children — half the exercises gone, no audit trail.
/// Next sync re-DELETED + tried again. Steady-state idempotent but lossy
/// on partial failure.
///
/// Post-fix: each row independently upserted. Network blip on row N
/// leaves the rest intact. Re-sync retries row N alone.
///
/// Source-grep contract pins:
///   1. `from('template_exercises').delete()` — FORBIDDEN. The DELETE
///      block was removed; bringing it back recreates the lossy mode.
///   2. `from('template_exercises').upsert(` present.
///   3. `onConflict: 'template_id,order_index'` literal present.
///   4. Migration 051 file exists.
///
/// closes-diagnose: 2026-05-10-template-exercises-upsert-a8b2c7
void main() {
  late String syncSrc;

  setUpAll(() {
    final f = loadSyncServiceSource();
    expect(f.existsSync(), isTrue, reason: 'sync_service.dart must exist');
    syncSrc = f.readAsStringSync();
  });

  group('template_exercises upsert contract', () {
    test('forbidden: DELETE-then-INSERT pattern absent', () {
      // The pre-fix block:
      //   await _supabase.client.from('template_exercises').delete()
      //     .eq('template_id', cloudTmplId);
      // brought back, the pattern reintroduces the lossy partial-failure
      // mode. Pin its absence.
      expect(
        syncSrc.contains("from('template_exercises').delete()") ||
            syncSrc.contains("from('template_exercises')\n              .delete()"),
        isFalse,
        reason:
            'forbidden — the DELETE-then-INSERT pattern on template_exercises '
            'was replaced by upsert with onConflict (migration 051). Bringing '
            'the DELETE back recreates the partial-failure data-loss class. '
            'closes-diagnose: 2026-05-10-template-exercises-upsert-a8b2c7',
      );
    });

    test('upsert with onConflict (template_id,order_index) present', () {
      expect(
        syncSrc.contains("from('template_exercises').upsert("),
        isTrue,
        reason:
            '_syncWorkoutTemplates must call upsert (NOT insert) on '
            'template_exercises so partial-failure recovery is row-level '
            'instead of template-level.',
      );
      expect(
        syncSrc.contains("onConflict: 'template_id,order_index'"),
        isTrue,
        reason:
            'upsert must specify onConflict: \'template_id,order_index\' '
            'so the UNIQUE constraint added by migration 051 is the '
            'conflict target. Without onConflict, upsert behaves as '
            'INSERT and re-introduces the duplicate-row failure mode '
            'that bit pre-Test-#12.8.',
      );
    });
  });

  group('migration 051 file exists', () {
    test('migration file present in supabase/migrations/', () {
      final f = File(
          'supabase/migrations/051_template_exercises_unique_order_index.sql');
      expect(f.existsSync(), isTrue,
          reason:
              'Migration 051 must exist as a tracked SQL file so future '
              'reset / branch / rebase rebuilds the cloud schema correctly. '
              'Source-grep contract this — the upsert above depends on the '
              'UNIQUE constraint that migration 051 adds.');

      final src = f.readAsStringSync();
      expect(
        src.contains('UNIQUE (template_id, order_index)'),
        isTrue,
        reason:
            'Migration 051 SQL must contain UNIQUE (template_id, order_index) '
            'as the constraint definition. The client upsert\'s onConflict '
            'target must match.',
      );
    });
  });
}
