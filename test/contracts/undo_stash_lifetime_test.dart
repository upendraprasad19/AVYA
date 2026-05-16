// test/contracts/undo_stash_lifetime_test.dart
//
// Contract (E.13 — Audit 2026-05-16 framework deliverable):
// Pin the `undo_<logKey>` Hive key shape + 1-hour TTL semantics on
// `WorkoutWriteService.deleteLog`.
//
// Writer:
//   lib/core/services/workout_write_service.dart `deleteLog`
//
// Reader (restore path):
//   The restore counterpart `restoreDeletedLog` is currently
//   accomplished via direct callsite read (no canonical helper yet —
//   slated for follow-up).
//
// Failure modes this prevents:
//   - TTL silently extended/shortened (e.g. 1h → 1m) — undo expires
//     before the snackbar UNDO button is tapped.
//   - Key prefix renamed without updating the restore lookup.
//   - `expires_at_ms` field renamed in the stash map.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String writerSrc;

  setUpAll(() {
    writerSrc = File('lib/core/services/workout_write_service.dart')
        .readAsStringSync();
  });

  group('undo_<logKey> stash contract', () {
    test('deleteLog writes `undo_<logKey>` key', () {
      expect(
        writerSrc,
        contains("'undo_"),
        reason: 'deleteLog must stash under the `undo_<logKey>` prefix',
      );
    });

    test('stash includes `data` (JSON-encoded log) and `expires_at_ms`', () {
      expect(writerSrc, contains("'data'"));
      expect(writerSrc, contains("'expires_at_ms'"));
    });

    test('TTL is exactly 1 hour', () {
      // Pin the literal — drift from 1h is a UX regression.
      expect(
        writerSrc,
        contains('Duration(hours: 1)'),
        reason: 'TTL constant must be Duration(hours: 1) — '
            'do not drop or extend without explicit founder approval',
      );
    });

    test('deleteLog has an `allowUndo` flag (default true)', () {
      // Some flows (e.g. orphan cleanup) need to delete without
      // creating a stash. The flag must exist.
      expect(
        writerSrc,
        contains('allowUndo'),
        reason: 'deleteLog must expose `allowUndo` parameter',
      );
    });

    test('deleteLog drops key from exercise_log_index_<date> on success', () {
      // Stale index causes the legacy-row fallback in
      // WorkoutReceiptCard to surface deleted entries (APK Test #16.1
      // a16c1a).
      expect(writerSrc, contains('exercise_log_index_'));
      // Either delete() the index or rewrite it without the logKey.
      final mentionsIndexDeleteOrRewrite =
          writerSrc.contains('box.delete(indexKey)') ||
              writerSrc.contains('box.put(indexKey,');
      expect(
        mentionsIndexDeleteOrRewrite,
        isTrue,
        reason: 'must update exercise_log_index_ after delete',
      );
    });
  });
}
