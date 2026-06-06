// BEHAVIORAL contract for the PRO-expiry banner's cross-account safety
// (review P0, 2026-06-06). The source-grep test alone could not catch the
// leak: `pro_lapsed_at` / `expiry_banner_dismissed_date` were not user-scoped,
// so a configBox fall-through showed User B a "PRO expired" banner for an
// account that was never theirs. Only an open→write→switch→read sequence
// against real Hive boxes proves the per-user isolation + the session-gate.
//
// Run: flutter test test/contracts/subscription_expiry_banner_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
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

String _pastIso() =>
    DateTime.now().subtract(const Duration(days: 1)).toIso8601String();

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('expiry_banner_');
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
    await HiveService.instance.configBox.clear();
  });

  group('pro_lapsed_at — cross-account isolation (review P0)', () {
    test('a marker stamped under session A is NOT visible to session B', () async {
      const userA = 'aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      const userB = 'bbbb2222-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

      // A: simulate genuine expiry → isPro() stamps the lapsed marker.
      await HiveUserSession.openForUser(userA);
      await MigratedKey.write('isPro', true);
      await MigratedKey.write('expiresAt', _pastIso());

      // ignore: deprecated_member_use
      final sub = SubscriptionService.instance;
      expect(sub.isPro(), isFalse, reason: 'expired → not PRO');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(sub.proLapsedAt, isNotNull, reason: 'A: lapsed marker stamped');
      expect(HiveService.instance.configBox.get('pro_lapsed_at'), isNull,
          reason:
              'marker MUST land in the per-user userBox, NEVER the shared configBox');

      // B: a brand-new account on the same device must NOT see A's marker.
      await HiveUserSession.openForUser(userB);
      expect(sub.proLapsedAt, isNull,
          reason: 'no cross-account leak — B was never PRO');
      expect(
        SubscriptionService.expiryBannerSeverity(
            isPro: false, daysUntilExpiry: -1, isLapsed: sub.isLapsed),
        ExpiryBannerSeverity.none,
        reason: 'B sees no expiry banner',
      );
    });

    test('with NO open session, isPro() does NOT seed configBox with the marker',
        () async {
      // No session → MigratedKey falls back to configBox. The stamp must be
      // gated OFF so it never writes the marker into the shared box.
      await HiveUserSession.closeAll();
      await HiveService.instance.configBox.put('isPro', true);
      await HiveService.instance.configBox.put('expiresAt', _pastIso());

      // ignore: deprecated_member_use
      expect(SubscriptionService.instance.isPro(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(HiveService.instance.configBox.get('pro_lapsed_at'), isNull,
          reason:
              'the stamp is session-gated — never seeds configBox without a session');
    });

    test('renewal clears the lapsed marker', () async {
      const userA = 'cccc3333-cccc-cccc-cccc-cccccccccccc';
      await HiveUserSession.openForUser(userA);
      await MigratedKey.write('pro_lapsed_at', DateTime.now().toIso8601String());

      // ignore: deprecated_member_use
      final sub = SubscriptionService.instance;
      expect(sub.proLapsedAt, isNotNull);

      await sub.writeSubscriptionState(
        isPro: true,
        expiresAt:
            DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        plan: 'monthly',
      );
      expect(sub.proLapsedAt, isNull,
          reason: 'renewal must clear the lapsed marker so the banner clears');
    });
  });

  group('expiry_banner_dismissed_date — per-user isolation', () {
    test("a dismiss under A does not carry to B", () async {
      const userA = 'dddd4444-dddd-dddd-dddd-dddddddddddd';
      const userB = 'eeee5555-eeee-eeee-eeee-eeeeeeeeeeee';

      await HiveUserSession.openForUser(userA);
      await MigratedKey.write('expiry_banner_dismissed_date', '2026-06-06');
      expect(MigratedKey.read<dynamic>('expiry_banner_dismissed_date'),
          '2026-06-06');
      expect(
          HiveService.instance.configBox.get('expiry_banner_dismissed_date'),
          isNull,
          reason: 'dismiss flag is per-user, not shared');

      await HiveUserSession.openForUser(userB);
      expect(MigratedKey.read<dynamic>('expiry_banner_dismissed_date'), isNull,
          reason: "B must not inherit A's dismiss state");
    });
  });
}
