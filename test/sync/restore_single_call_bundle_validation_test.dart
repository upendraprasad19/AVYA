// test/sync/restore_single_call_bundle_validation_test.dart
//
// C3 single-call restore — BEHAVIORAL test of the FAIL-CLOSED bundle contract
// (Hermes H-2; plan `restore-single-call-c3.md` §2/§5). This is the silent-data-loss
// guard: `SyncService.validatedSnapshotTables` returns the `tables` map ONLY for a
// complete, well-formed `restore-user-snapshot` bundle, and `null` for ANY fault, so
// the orchestrator (`_attemptSingleCallRestore`) falls through to the VERBATIM legacy
// fan-out THIS pass rather than writing a PARTIAL bundle as a complete restore.
//
// The critical nuance (Hermes): a present key with a null/`[]` value is a
// LEGITIMATELY-EMPTY table (the user has no rows there) — NOT a fault. Only an
// ABSENT key, a non-200, a bad `schema_version`, or a malformed shape is a fault.
//
// This is the behavioral_test_path for the `restore_single_call` SoT entry — it
// fails if the fail-closed contract regresses, even though the source text remains
// (feedback_source_grep_false_confidence). The apply/merge semantics the single-call
// path reuses unchanged are covered by the existing pure-helper behavioral tests
// (restore_freezes_merge_test.dart, restore_plan_json_authoritative_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

void main() {
  // A well-formed bundle: every canonical key present. `overrideTables` swaps the
  // tables map; `schemaVersion` swaps the sentinel.
  Map<String, dynamic> bundle({
    Map<dynamic, dynamic>? overrideTables,
    Object? schemaVersion = 1,
  }) =>
      {
        'schema_version': schemaVersion,
        'generated_at': '2026-06-30T00:00:00Z',
        'tables': overrideTables ??
            {for (final k in SyncService.singleCallBundleKeys) k: <dynamic>[]},
      };

  group('validatedSnapshotTables — fail-closed bundle contract (Hermes H-2)', () {
    test('valid 200 bundle with EVERY key → returns the tables map', () {
      final tables = SyncService.validatedSnapshotTables(200, bundle());
      expect(tables, isNotNull);
      expect(tables!.length, SyncService.singleCallBundleKeys.length);
    });

    test('non-200 status → null (an EF table-query error returns non-200 → '
        'legacy fallback, never a partial write; H-2b)', () {
      expect(SyncService.validatedSnapshotTables(500, bundle()), isNull);
      expect(SyncService.validatedSnapshotTables(401, bundle()), isNull);
      expect(SyncService.validatedSnapshotTables(503, bundle()), isNull);
    });

    test('ANY single ABSENT key → null (a partial bundle is a fault → legacy '
        'fallback; H-2a — the silent-data-loss guard)', () {
      for (final missing in SyncService.singleCallBundleKeys) {
        final tables = {
          for (final k in SyncService.singleCallBundleKeys)
            if (k != missing) k: <dynamic>[]
        };
        expect(
          SyncService.validatedSnapshotTables(200, bundle(overrideTables: tables)),
          isNull,
          reason: 'a bundle missing "$missing" must be a FAULT — never written '
              'as a complete restore',
        );
      }
    });

    test('present key with null OR empty value → NOT a fault '
        '(a user with no rows is legitimately empty)', () {
      final allNull = {
        for (final k in SyncService.singleCallBundleKeys) k: null
      };
      expect(
        SyncService.validatedSnapshotTables(200, bundle(overrideTables: allNull)),
        isNotNull,
        reason: 'an EF returning null/[] for an empty table is legitimately '
            'empty (key present) — must NOT trigger fallback',
      );
    });

    test('unrecognised schema_version → null (forward-incompatible bundle → '
        'legacy fallback)', () {
      expect(SyncService.validatedSnapshotTables(200, bundle(schemaVersion: 2)), isNull);
      expect(SyncService.validatedSnapshotTables(200, bundle(schemaVersion: null)), isNull);
      expect(SyncService.validatedSnapshotTables(200, bundle(schemaVersion: '1')), isNull);
    });

    test('non-Map data / missing tables / non-Map tables → null', () {
      expect(SyncService.validatedSnapshotTables(200, null), isNull);
      expect(SyncService.validatedSnapshotTables(200, 'not a map'), isNull);
      expect(SyncService.validatedSnapshotTables(200, <dynamic>[]), isNull);
      expect(SyncService.validatedSnapshotTables(200, {'schema_version': 1}), isNull,
          reason: 'tables key absent');
      expect(
          SyncService.validatedSnapshotTables(
              200, {'schema_version': 1, 'tables': 'nope'}),
          isNull,
          reason: 'tables not a Map');
    });
  });
}
