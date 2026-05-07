// APK Test #12.7 — pin that streak upsert payload does NOT carry a
// `source` field. The cloud `streaks` schema has columns
// (id, user_id, week_start, workouts_planned, workouts_completed,
// is_streak_maintained, created_at) — no `source` column.
//
// Pre-fix: `_syncStreaks` did `...data` spread + only removed
// `local_id`. After `_restoreStreaks` rehydrated rows with
// `source: 'cloud_restore'` into Hive, the next sync upserted that
// field back to cloud → PGRST204 ("Could not find the 'source' column
// of 'streaks'") on every push.
//
// Fix: explicit projection of schema-matching columns only.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relativePath) {
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

void main() {
  group('Test #12.7 — streaks payload omits source field', () {
    test('_syncStreaks does NOT spread the entire data map', () {
      final src = _src('lib/core/services/sync_service.dart');

      final mIdx = src.indexOf('Future<void> _syncStreaks(');
      expect(mIdx, greaterThan(0));
      final mEnd = src.indexOf('\n  /// ', mIdx + 10);
      final body = src.substring(mIdx,
          mEnd > mIdx ? mEnd : (mIdx + 2000).clamp(0, src.length));

      // The legacy `...data` spread is the smoking gun — it leaks
      // every Hive field (including `source: 'cloud_restore'`) into
      // the cloud upsert. Must NOT survive.
      expect(
        body.contains('...data,'),
        isFalse,
        reason: '_syncStreaks must NOT spread the Hive map directly into '
            'the upsert payload — that leaks `source` (and any other '
            'local-only fields) into the cloud schema.',
      );

      // The fix uses an explicit projection.
      expect(
        body,
        contains('workouts_planned'),
        reason: 'Explicit field projection — workouts_planned must be '
            'mapped by name.',
      );
      expect(
        body,
        contains('workouts_completed'),
        reason: 'Explicit field projection — workouts_completed must '
            'be mapped by name.',
      );
      expect(
        body,
        contains('is_streak_maintained'),
        reason: 'Explicit field projection — is_streak_maintained must '
            'be mapped by name.',
      );
    });

    test(
      '_syncStreaks payload does not reference the source field as a key',
      () {
        final src = _src('lib/core/services/sync_service.dart');

        final mIdx = src.indexOf('Future<void> _syncStreaks(');
        expect(mIdx, greaterThan(0));
        final mEnd = src.indexOf('\n  /// ', mIdx + 10);
        final body = src.substring(mIdx,
            mEnd > mIdx ? mEnd : (mIdx + 2000).clamp(0, src.length));

        // Strip line comments + block comments — informational docs may
        // legitimately MENTION the bug pattern.
        final codeOnly = body
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');

        // The buggy upsert-key form `'source':` (a map literal entry)
        // should not appear ANYWHERE in code.
        expect(
          codeOnly.contains("'source':"),
          isFalse,
          reason: '`source` is not a column on the cloud `streaks` '
              'table. _syncStreaks must not reference it as an upsert '
              'payload key.',
        );
      },
    );
  });
}
