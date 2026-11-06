// test/contracts/notification_preferences_writer_to_reader_test.dart
//
// Unit D — the emission contract for `notification_preferences`.
//
// THE BUG THIS CLOSES: verified live, **0 of 91** `user_daily_snapshots` rows
// carried the key. The client wrote preferences to Hive and nothing ever put
// them in the snapshot, so every server-side check fell through to its
// permissive default and every toggle was decorative.
//
// Three traps are pinned here, each of which silently un-does the feature:
//
//   TRAP 1 (trim) — `trimSnapshotToBudget` keeps a fixed allowlist and halves
//     the largest remaining map. `notification_preferences` is NOT in that
//     allowlist, so emitting it INSIDE buildAiContext would let it be dropped
//     for exactly the users whose snapshots are biggest. A dropped key reads to
//     the server as absent, which means SEND — the user's OFF is ignored.
//
//   TRAP 2 (rename) — the client historically stored `workout_reminder`
//     (singular). Emitting only the plural orphans that value → absent → SEND →
//     a user who deliberately turned the reminder off starts getting it again.
//
//   TRAP 3 (default) — any key that emits something other than enabled:true for
//     an untouched user darkens that notification for everyone at once.
//
// Run: flutter test test/contracts/notification_preferences_writer_to_reader_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
import 'package:icanbefitter/features/profile/services/notification_prefs_repository.dart';
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

const _user = 'cccc3333-cccc-cccc-cccc-cccccccccccc';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('notif_prefs_emit_');
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
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    await HiveUserSession.openForUser(_user);
    await HiveService.instance.userBox
        .delete(NotificationPrefsRepository.hiveKey);
  });

  group('emission — Hive write reaches the snapshot map', () {
    test('an untouched user emits ALL keys, every one enabled (TRAP 3)', () {
      final emitted = NotificationPrefsRepository.emissionMap();
      expect(emitted.keys.toSet(),
          NotificationPrefsRepository.allKeys.toSet(),
          reason: 'every registry key must be present, always');
      for (final entry in emitted.entries) {
        expect(entry.value['enabled'], isTrue,
            reason: '${entry.key} defaulted to something other than true — '
                'that darkens the notification for EVERY user at once.');
      }
    });

    test('a stored OFF round-trips: Hive write -> emission map', () async {
      await NotificationPrefsRepository.write({
        'streak_alerts': {'enabled': false},
      });
      final emitted = NotificationPrefsRepository.emissionMap();
      expect(emitted['streak_alerts']?['enabled'], isFalse);
      // Untouched siblings stay on — one OFF must not darken the rest.
      expect(emitted['weekly_recap']?['enabled'], isTrue);
      expect(emitted['pr_celebration']?['enabled'], isTrue);
    });

    test('TRAP 2 — an OFF stored under the LEGACY singular key survives',
        () async {
      // What a pre-fix client actually wrote.
      await HiveService.instance.userBox.put(
        NotificationPrefsRepository.hiveKey,
        <dynamic, dynamic>{
          'workout_reminder': <dynamic, dynamic>{'enabled': false},
        },
      );
      expect(
        NotificationPrefsRepository.emissionMap()['workout_reminders']
            ?['enabled'],
        isFalse,
        reason: 'Reading only the plural key orphans the stored value → absent '
            '→ the server SENDS → a user who turned this OFF starts receiving '
            'it again. The read-time alias is what prevents that.',
      );
    });

    test('a malformed stored value emits enabled:true and does not throw',
        () async {
      await HiveService.instance.userBox.put(
        NotificationPrefsRepository.hiveKey,
        <dynamic, dynamic>{'streak_alerts': 'garbage'},
      );
      late Map<String, Map<String, dynamic>> emitted;
      expect(() => emitted = NotificationPrefsRepository.emissionMap(),
          returnsNormally,
          reason: 'a throw here propagates through compileDailySnapshot into '
              'pushSnapshotNow and kills the user ENTIRE daily snapshot.');
      expect(emitted['streak_alerts']?['enabled'], isTrue);
    });

    test('the emitted map is JSON-encodable and small', () {
      final json = jsonEncode(NotificationPrefsRepository.emissionMap());
      expect(json, isNotEmpty);
      expect(json.length, lessThan(2000),
          reason: 'the snapshot has a server-side size budget; 10 keys should '
              'cost a few hundred bytes. Actual: ${json.length}');
    });
  });

  group('TRAP 1 — why emission happens OUTSIDE the trimmed map', () {
    test('trimSnapshotToBudget WOULD drop notification_preferences', () {
      // This is the load-bearing justification for emitting after the
      // buildAiContext spread in compileDailySnapshot. If a future refactor
      // "tidies up" by moving the emission inside buildAiContext, the key
      // becomes trimmable again and OFF toggles start being ignored for the
      // users with the biggest snapshots — silently.
      //
      // The realistic shape: `profile` is in the KEEP set, so the trimmer can
      // never shrink it. When keep-set content alone exceeds the budget, the
      // loop cannot reach its target however much it trims, so it goes on
      // halving every non-keep key — including this one — until the guard
      // trips. Halving a 10-key map drops keys outright, and a dropped key
      // reads to the server as absent, which means SEND.
      final oversized = <String, dynamic>{
        'profile': List.generate(1500, (i) => 'irreducible-profile-blob-$i'),
        'notification_preferences':
            NotificationPrefsRepository.emissionMap(),
      };
      expect(jsonEncode(oversized).length, greaterThan(8500),
          reason: 'fixture must exceed the default budget to exercise trimming');

      final trimmed =
          AiSnapshotBuilder.trimSnapshotToBudget(Map<String, dynamic>.from(oversized));
      final survivedIntact = trimmed['notification_preferences'] != null &&
          jsonEncode(trimmed['notification_preferences']) ==
              jsonEncode(oversized['notification_preferences']);

      expect(survivedIntact, isFalse,
          reason: 'notification_preferences is NOT in the trimmer keep-set, so '
              'it is trimmable. That is precisely why compileDailySnapshot '
              'emits it OUTSIDE the already-trimmed aiContext spread. If this '
              'assertion ever fails because the key was added to the keep-set, '
              'that is fine — but then say so explicitly rather than relying '
              'on placement.');
    });
  });
}
