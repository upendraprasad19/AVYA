// ADR-0022 / plan section 5.2: the Home expiry ("renew") banner is decided by
// ONE provider, and in a binary that sells nothing that provider answers
// "hide" before it reads any PRO state. BEHAVIOURAL (B-pass 2026-11-20, F4:
// the first version of this check only compared source offsets, which an
// inverted guard also satisfies).
//
// Same Hive harness as subscription_expiry_banner_behavioral_test.dart. The
// positive pair is the Razorpay mode: a PRO user 3 days from expiry MUST get
// the banner there, otherwise "hidden in none" would assert nothing.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
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

class _Sub extends SubscriptionInfoNotifier {
  @override
  SubscriptionInfoData build() => const SubscriptionInfoData();
}

ExpiryBannerState _read(PurchaseMode mode) {
  PurchaseMode.debugOverrideForTests = mode;
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('user-a'),
    subscriptionInfoProvider.overrideWith(() => _Sub()),
  ]);
  addTearDown(c.dispose);
  return c.read(subscriptionExpiryBannerProvider);
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('expiry_banner_mode_');
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
    final cfg = HiveService.instance.configBox;
    await cfg.clear();
    // A PRO user whose plan ends in 3 days: the amber "renew" case.
    await cfg.put('isPro', true);
    await cfg.put('expiresAt',
        DateTime.now().add(const Duration(days: 3, hours: 2)).toIso8601String());
  });

  tearDown(() => PurchaseMode.debugOverrideForTests = null);

  test('razorpay (positive pair): the banner shows for a PRO user 3 days out',
      () {
    final s = _read(PurchaseMode.razorpay);
    expect(s.show, isTrue);
    expect(s.severity, ExpiryBannerSeverity.expiringSoon);
  });

  for (final mode in [PurchaseMode.none, PurchaseMode.playBilling]) {
    test('${mode.wireName}: the SAME user gets no banner', () {
      final s = _read(mode);
      expect(s.show, isFalse);
      expect(s.severity, ExpiryBannerSeverity.none);
    });
  }
}
