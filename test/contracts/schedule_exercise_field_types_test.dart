import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// APK Test #15.1 / Bug A — schedule exercise `sets` must be int, not
/// String, in Hive.
///
/// Pre-fix: `_restoreWorkoutTemplates` (sync_service.dart) stringified
/// `prescribed_sets` ("3"). The value then flowed through
/// `WorkoutScheduleService._normalizeExercises` unchanged and landed in
/// `schedule_<date>` entries. Home screen + day_detail_sheet +
/// template_builder_screen all read with `(ex['sets'] as int?)` — the
/// cast crashed: `type 'String' is not a subtype of type 'int?' in type cast`.
///
/// Telemetry showed 5× `widget_error_fallback` events on the founder's
/// account immediately after scheduling a template for today.
///
/// Fix: coerce `sets` to int at BOTH writer sites:
///   1. sync_service.dart `_restoreWorkoutTemplates` → `_coerceInt(...)`
///   2. workout_schedule_service.dart `_normalizeExercises` → inline
///      defensive int coercion (handles legacy Hive rows already
///      carrying a stringified value).
///
/// closes-diagnose: 2026-05-12-schedule-int-coercion-a2f9e1
void main() {
  late String syncSrc;
  late String scheduleSrc;

  setUpAll(() {
    syncSrc =
        loadSyncServiceSource().readAsStringSync();
    scheduleSrc =
        File('lib/core/services/workout_schedule_service.dart')
            .readAsStringSync();
  });

  group('Writer 1 — _restoreWorkoutTemplates', () {
    test('_coerceInt helper exists in sync_service', () {
      expect(
        syncSrc.contains('int _coerceInt(dynamic value'),
        isTrue,
        reason:
            '_coerceInt(value, fallback:) helper must exist as a top-level '
            'function in sync_service.dart so the schedule exercise writer '
            'can coerce String / num / null → int. closes-diagnose: '
            '2026-05-12-schedule-int-coercion-a2f9e1',
      );
    });

    test('_restoreWorkoutTemplates uses _coerceInt for sets', () {
      expect(
        syncSrc.contains("'sets': _coerceInt(ex['prescribed_sets']"),
        isTrue,
        reason:
            '_restoreWorkoutTemplates must wrap prescribed_sets in '
            '_coerceInt(...) so the local Hive shape carries int sets '
            '(home_screen + day_detail_sheet cast as int?).',
      );
    });

    test('forbidden: stringification of prescribed_sets', () {
      // Pre-fix line was: 'sets': ex['prescribed_sets']?.toString() ?? '3'
      // Pin its absence so a future revert doesn't reintroduce the crash.
      expect(
        syncSrc.contains("'sets': ex['prescribed_sets']?.toString()"),
        isFalse,
        reason:
            'forbidden — _restoreWorkoutTemplates must NOT stringify '
            'prescribed_sets. The downstream reader cast crashes home '
            'on cold-start. Use _coerceInt(...) instead.',
      );
    });
  });

  group('Writer 2 — _normalizeExercises (defensive)', () {
    test('_normalizeExercises coerces sets defensively (handles legacy String)',
        () {
      // The writer wraps the rawSets in a coercion block before assigning
      // to the 'sets' key. Pin that the coercion is present.
      expect(
        scheduleSrc.contains('rawSets is int') &&
            scheduleSrc.contains('rawSets is num') &&
            scheduleSrc.contains('rawSets is String'),
        isTrue,
        reason:
            '_normalizeExercises must coerce rawSets across int / num / '
            'String / null paths before writing to the schedule. Legacy '
            'Hive rows from pre-fix _restoreWorkoutTemplates carry '
            'stringified sets; defensive coercion at the schedule '
            'writer protects readers regardless of the source.',
      );
    });

    test('_normalizeExercises sets field is int (not Object/dynamic)', () {
      // The final value assigned to 'sets' must be the coerced int var,
      // not the raw mixed-type expression.
      expect(
        scheduleSrc.contains("'sets': setsInt,"),
        isTrue,
        reason:
            '_normalizeExercises must assign the coerced int variable to '
            "the 'sets' key (NOT the raw m['sets'] ?? ... ?? 3 expression "
            'which can yield String).',
      );
    });
  });
}
