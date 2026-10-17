// test/contracts/daily_snapshot_fitness_summary_omission_test.dart
//
// BEHAVIOURAL contract for a code-review finding on diagnose d8a2f6
// (docs/diagnoses/2026-09-21-morning-alert-snapshot-clobber-d8a2f6.md).
//
// d8a2f6 made `daily-snapshot`'s upsert merge-safe: `mergeSnapshotJson`
// spreads the EXISTING row first, so a cron-owned key the client's payload
// never mentions survives. That protects `morning_alert` because the client
// never sends it at all. It does NOT protect `fitness_summary` — the SAME
// AiSnapshotBuilder.buildAiContext() that feeds this push is ALSO the live
// ai-proxy chat request body, and for THAT use case it correctly includes
// the client's locally-synced-down mirror of fitness_summary
// (SyncService._syncFitnessSummary pulls it down from rolling-context's own
// cron write). Sending that same mirror back up as part of the
// daily-snapshot push lets `incoming` win the merge on a key the client
// does carry — clobbering rolling-context's fresher server-side write with
// the client's lagging (or, on first use today, empty-string) copy. This
// file pins that `compileDailySnapshot()` strips the key before it ever
// reaches the wire, regardless of what buildAiContext() itself carries.
//
// Run: flutter test test/contracts/daily_snapshot_fitness_summary_omission_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

const _userA = 'bbbb2222-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('daily_snapshot_fitsum_omit_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    // Cleanup is hygiene, never an assertion (§4.9) — a throw here would
    // stack a second failure that hides the real one.
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    await HiveUserSession.openForUser(_userA);
  });

  group('compileDailySnapshot — fitness_summary is never re-sent upstream', () {
    test('the key is absent even when the client has a local mirror set',
        () async {
      // Simulate what a real device looks like: rolling-context's cron
      // wrote a real value server-side at some point, and the client synced
      // it DOWN into coachBox for local chat-context use — SyncService's own
      // documented pull path, not something this test invents.
      await HiveService.instance.coachBox
          .put('fitness_summary', 'Client-cached summary from a prior sync.');

      final snapshot = SyncService.instance.compileDailySnapshot();

      expect(snapshot.containsKey('fitness_summary'), isFalse,
          reason: 'fitness_summary is cron-owned server-side data. Sending '
              "the client's own local mirror back up would let it win the "
              'merge-safe upsert on a key it DOES carry (unlike '
              'morning_alert, which the client never sends at all) and '
              "clobber rolling-context's fresher write with a stale or "
              'empty client-side copy — the exact class diagnose d8a2f6 '
              'exists to close.');
    });

    test('the key is absent even with no local mirror at all (default "")',
        () async {
      // AiSnapshotBuilder._getFitnessSummary() defaults to '' (never null),
      // so a naive null-aware omission upstream would NOT catch this case —
      // the key would still be present, just empty. Pin the stronger
      // guarantee: compileDailySnapshot() removes it unconditionally.
      await HiveService.instance.coachBox.delete('fitness_summary');

      final snapshot = SyncService.instance.compileDailySnapshot();

      expect(snapshot.containsKey('fitness_summary'), isFalse);
    });
  });
}
