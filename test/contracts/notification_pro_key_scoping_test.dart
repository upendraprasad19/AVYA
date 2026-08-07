// test/contracts/notification_pro_key_scoping_test.dart
//
// Contract for OI-76 — the Profile row's "N/M enabled" notification subtitle
// counted PRO-locked keys a free user cannot reach, and the locked rows opened
// the paywall under the wrong feature identity.
//
// TWO claims are pinned here, and the second matters more than the first.
//
// 1. THE COUNT (the reported bug). `protein_alerts` and `plateau_alert` are
//    PRO-only. A free user cannot toggle them and their server functions
//    PRO-gate anyway, so counting them left the subtitle permanently reading at
//    least 2/10 "enabled" for notifications that could never fire.
//
// 2. THE EMISSION MUST NOT NARROW (the dangerous wrong fix). The obvious way to
//    implement #1 is to drop the two keys from `allKeys` or filter them out of
//    `emissionMap()`. That would be a live regression in the opposite
//    direction: the server's rule is ABSENT ⇒ SEND (repository header, decision
//    N2), so an omitted key turns the notification ON. A free user would start
//    RECEIVING the two PRO notifications they were never supposed to get.
//    `emissionMap()` must keep emitting all 10 keys no matter the tier — this
//    test fails if a future change narrows it.
//
// Both assertions are negative-controlled: #1 fails if `controllableKeys`
// stops subtracting, #2 fails if emission is scoped by tier.
//
// Run: flutter test test/contracts/notification_pro_key_scoping_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
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

const _user = 'ffff9999-ffff-ffff-ffff-ffffffffffff';

void main() {
  late Directory tmp;

  // Mirrors the harness in notification_prefs_rescope_behavioral_test.dart.
  // `testBypassOwnership` is what keeps this a UNIT test: GuardedBox otherwise
  // resolves the current owner through Supabase, which is not initialised here.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('oi76_pro_key_scoping_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    Hive.init(tmp.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
    await HiveUserSession.openForUser(_user);
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('OI-76 — PRO-only keys are display-scoped, never emission-scoped', () {
    test('proOnlyKeys is exactly the two PRO-gated registry keys', () {
      expect(NotificationPrefsRepository.proOnlyKeys,
          <String>{'protein_alerts', 'plateau_alert'});

      // Every PRO-only key must be a real registry key. A typo here would
      // silently subtract nothing and the count bug would return unnoticed.
      for (final key in NotificationPrefsRepository.proOnlyKeys) {
        expect(NotificationPrefsRepository.allKeys, contains(key),
            reason: '$key is not in allKeys, so subtracting it is a no-op');
      }
    });

    test('a free user is offered only the keys they can actually toggle', () {
      final free =
          NotificationPrefsRepository.controllableKeys(isPro: false);

      expect(free.length, 8,
          reason: 'the free denominator must exclude the 2 PRO-only keys');
      expect(free, isNot(contains('protein_alerts')));
      expect(free, isNot(contains('plateau_alert')));
    });

    test('a PRO user is offered every registry key', () {
      final pro = NotificationPrefsRepository.controllableKeys(isPro: true);

      expect(pro.length, NotificationPrefsRepository.allKeys.length);
      expect(pro, containsAll(NotificationPrefsRepository.proOnlyKeys));
    });

    test(
        'emissionMap still emits ALL 10 keys — narrowing it would turn PRO '
        'notifications ON for free users via the server ABSENT => SEND rule',
        () async {
      // Write a realistic partial map: the user has touched only one key.
      await NotificationPrefsRepository.write(<String, dynamic>{
        'streak_alerts': <String, dynamic>{'enabled': false},
      });

      final emitted = NotificationPrefsRepository.emissionMap();

      expect(emitted.keys.toSet(),
          NotificationPrefsRepository.allKeys.toSet(),
          reason: 'emission is tier-independent; every key must be present');

      // The two PRO keys specifically must still be emitted, and must emit
      // enabled:true (the untouched default) rather than being dropped.
      for (final key in NotificationPrefsRepository.proOnlyKeys) {
        expect(emitted, contains(key),
            reason: 'dropping $key makes the server default it to SEND');
        expect(emitted[key]!['enabled'], isTrue);
      }

      // The one key the user did turn off is still honoured — proving the
      // emission map was not simply rebuilt from defaults.
      expect(emitted['streak_alerts']!['enabled'], isFalse);
    });
  });
}
