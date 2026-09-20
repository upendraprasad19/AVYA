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
    test('any template_exercises delete is the bounded tail-vacuum, not a blanket DELETE-then-INSERT',
        () {
      // Two legitimate patterns coexist:
      //   (1) per-row UPSERT with onConflict (migration 051) — the children writer.
      //   (2) a bounded TAIL VACUUM that removes ONLY orphaned rows when a
      //       template shrinks:
      //         .delete().eq('template_id', X).gte('order_index', length)
      //       (diagnose 2026-05-12-template-exercises-tail-vacuum-b3c8d2).
      // The FORBIDDEN pattern is the old lossy blanket delete-then-insert:
      //   .delete().eq('template_id', X)  with NO order_index bound, followed
      //   by a re-insert loop (diagnose 2026-05-10-template-exercises-upsert-a8b2c7).
      // So: every template_exercises delete MUST be order_index-bounded.
      final deletes = RegExp(
        r"from\('template_exercises'\)\s*\.delete\(\)([\s\S]{0,220})",
      ).allMatches(syncSrc);
      for (final m in deletes) {
        expect(
          (m.group(1) ?? '').contains(".gte('order_index'"),
          isTrue,
          reason:
              "a template_exercises delete without .gte('order_index', ...) is "
              'the lossy blanket DELETE-then-INSERT (data-loss on partial failure). '
              'Only the bounded tail-vacuum is allowed. '
              'closes-diagnose: 2026-05-12-template-exercises-tail-vacuum-b3c8d2 '
              '(supersedes the over-broad no-delete pin from '
              '2026-05-10-template-exercises-upsert-a8b2c7).',
        );
      }
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
