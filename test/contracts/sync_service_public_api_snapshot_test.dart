import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Locks the public API surface of `SyncService` during the part-file
/// refactor (refactor/sync-service-part-split, 2026-05-13).
///
/// Scans `lib/core/services/sync_service.dart` AND every file under
/// `lib/core/services/sync/` for `Future<...>` / `Stream<...>` / `void`
/// methods on either `class SyncService` or `extension X on SyncService`
/// that DO NOT start with an underscore. The sorted set of names must
/// exactly match `expectedPublicApi`.
///
/// If a method is renamed or accidentally privatised during the refactor,
/// this test fails. If a new public method is added (e.g. by a parallel
/// bug-fix batch landing mid-refactor), update `expectedPublicApi` after
/// confirming the addition is intentional.
void main() {
  group('SyncService public API snapshot (refactor lock)', () {
    test('public method list is unchanged', () {
      const expectedPublicApi = <String>{
        'cancelInflightRestore',
        'checkAndSync',
        'drainTelemetryQueue',
        'initQueue',
        'pullRecentCrossChannelLogs',
        'pushSnapshot',
        'reportSyncFailure',
        'restoreFromCloud',
        'restoreFromCloudForUser',
        'restoreLightweightAlways',
        'subscribeToRealtimeSync',
        'syncCoachMemoryNow',
        'syncCommunityItems',
        'syncCustomItemsNow',
        'syncFreezes',
        'syncMeasurementsNow',
        'syncNotificationsInboxEntry',
        'syncNutritionData',
        'syncProfileNow',
        'syncProgressNow',
        'syncSavedDietPlan',
        'syncSavedMealsNow',
        'syncSleepNow',
        'syncWeightNow',
        'syncWorkoutData',
        'unsubscribeRealtime',
        'weeklyFullSync',
        // Getters that look like methods (counted as public API surface):
        'healthSyncDone',
        'onRestoreComplete',
      };

      final files = <File>[
        File('lib/core/services/sync_service.dart'),
        ...Directory('lib/core/services/sync')
            .let((dir) => dir.existsSync() ? dir.listSync() : <FileSystemEntity>[])
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      ];

      // Match instance method signatures at exactly 2-space indent
      // (class instance methods + extension methods). Excludes
      // statics (no `static ` prefix possible at this indent in
      // current source) and nested helper functions (4+ space indent).
      // Matches: `Future<...>` / `Stream<...>` / `void` returns +
      //          optional `get ` for getters + name + ( or = .
      final methodPattern = RegExp(
        r'^  (?:Future<[^>]*>|Stream<[^>]*>|void)\s+(?:get\s+)?([a-zA-Z]\w*)\s*[\(\=]',
        multiLine: true,
      );

      final found = <String>{};
      for (final f in files) {
        final src = f.readAsStringSync();
        for (final m in methodPattern.allMatches(src)) {
          final name = m.group(1)!;
          if (name.startsWith('_')) continue;
          found.add(name);
        }
      }

      expect(found, equals(expectedPublicApi),
          reason:
              'SyncService public API surface changed. If this is '
              'intentional (new public method added), update '
              'expectedPublicApi in this test after confirming the '
              'change is reviewed. If this is unintentional (method '
              'accidentally renamed/privatised during refactor), '
              'revert the rename.');
    });
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
