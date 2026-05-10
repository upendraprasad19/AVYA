// APK Test #14 / Bug B.1 — pins the self-healing 23503 recovery in
// `_syncScheduledWorkouts`.
//
// Source-grep contract test (matches the established pattern in
// test/contracts/ist_sweep_no_utc_substring_test.dart). Pins:
//   • per-call cache `templateNameToCloudId` exists
//   • `'23503'` literal present (FK-violation discriminator)
//   • `scheduled_workout_fk_recovered` op_type emitted on retry success
//   • `scheduled_workout_template_orphaned` op_type emitted on null fallback
//   • forbidden: `_deterministicId(rawTemplateId)` (the v5 hash that
//     never matched cloud's gen_random_uuid()) is gone
//
// See docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('_syncScheduledWorkouts FK resilience (APK Test #14 / Bug B.1)', () {
    late String src;

    setUpAll(() {
      src = File('lib/core/services/sync_service.dart').readAsStringSync();
    });

    test('per-call cache `templateNameToCloudId` is present', () {
      expect(
        src.contains('templateNameToCloudId'),
        isTrue,
        reason: 'Per-call cache eliminates N×SELECT on shared template names',
      );
    });

    test('23503 literal present (FK-violation discriminator)', () {
      expect(
        src.contains("'23503'"),
        isTrue,
        reason:
            'Catch must distinguish 23503 (FK violation) from other errors',
      );
    });

    test('telemetry op_type `scheduled_workout_fk_recovered` present', () {
      expect(
        src.contains("'scheduled_workout_fk_recovered'"),
        isTrue,
        reason:
            'Successful 23503 recovery logs a telemetry event for audit',
      );
    });

    test('telemetry op_type `scheduled_workout_template_orphaned` present', () {
      expect(
        src.contains("'scheduled_workout_template_orphaned'"),
        isTrue,
        reason:
            'Null-template fallback logs a telemetry event so we can audit lost template attribution',
      );
    });

    test('forbidden: `_deterministicId(rawTemplateId)` removed', () {
      // The v5 hash never matched cloud's gen_random_uuid() id,
      // produced 23503 on every push that carried a non-null
      // template_id. Replaced by a name-based lookup.
      // Strip line/block comments so commentary about the bad pattern
      // doesn't trigger the test.
      final stripped = src
          .replaceAll(RegExp(r'//.*'), '')
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
      expect(
        stripped.contains('_deterministicId(rawTemplateId)'),
        isFalse,
        reason:
            'v5 hash on raw Hive template_id was the FK-violation root cause; '
            'replaced by lookup-by-name in resolveCloudTemplateId().',
      );
    });
  });
}
