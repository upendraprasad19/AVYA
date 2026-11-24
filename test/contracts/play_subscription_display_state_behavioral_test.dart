// BEHAVIORAL contract for the Play subscription display state (OI-519, plan
// section 5): `pro_store`, `pro_auto_renews`, `pro_store_expires_at`.
//
// Writer: SubscriptionService.writeSubscriptionState (a null argument DELETES
// the key) fed by the pure playDisplayFields (refreshFromSupabase,
// verifyFromServer); _downgradeLocally deletes them.
// Readers: proStore, proAutoRenews, displayExpiresAt (Profile, the paywall,
// the Home banner input, the coach snapshot `auto_renew`).
//
// Run: flutter test test/contracts/play_subscription_display_state_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/user_config_migrator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/pro_downgrade_waiter.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

const _storeExpiry = '2026-12-23T16:00:00.000Z'; // 21:30 IST on Dec 23
const _endDate = '2026-12-23T19:00:00.000Z'; // + 3 h window: 00:30 IST Dec 24

Map<String, dynamic> _playRow({bool autoRenew = true}) => {
      'plan': 'monthly',
      'end_date': _endDate,
      'store': 'play',
      'auto_renew': autoRenew,
      'store_expires_at': _storeExpiry,
    };

Future<void> _writeFrom(Map<String, dynamic> row) {
  final play = playDisplayFields(row);
  return SubscriptionService.instance.writeSubscriptionState(
    isPro: true,
    expiresAt: row['end_date'] as String,
    plan: row['plan'] as String,
    store: play.store,
    autoRenews: play.autoRenews,
    storeExpiresAt: play.storeExpiresAt,
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('play_display_');
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

  group('playDisplayFields (pure)', () {
    test('a Play row yields its three fields', () {
      final f = playDisplayFields(_playRow());
      expect(f.store, 'play');
      expect(f.autoRenews, isTrue);
      expect(DateTime.parse(f.storeExpiresAt!), DateTime.parse(_storeExpiry));
    });

    test('a Play row that will not renew yields autoRenews false, not null', () {
      expect(playDisplayFields(_playRow(autoRenew: false)).autoRenews, isFalse);
    });

    test('our own row (store null) and an old server body yield all null', () {
      for (final src in [
        {'plan': 'yearly', 'end_date': _endDate, 'store': null},
        {'is_pro': true, 'plan': 'monthly', 'expires_at': _endDate},
        // A non-Play store value never sets a Play field.
        {'store': 'app_store', 'auto_renew': true, 'store_expires_at': _storeExpiry},
      ]) {
        final f = playDisplayFields(src);
        expect([f.store, f.autoRenews, f.storeExpiresAt], [null, null, null],
            reason: '$src');
      }
    });

    test('an unparseable store_expires_at is dropped, the rest kept', () {
      final f = playDisplayFields({..._playRow(), 'store_expires_at': 'soon'});
      expect(f.store, 'play');
      expect(f.storeExpiresAt, isNull);
    });
  });

  group('write -> read through Hive', () {
    test('a Play write is readable; displayExpiresAt is the store expiry, not '
        'end_date (the 3-hour window never moves the shown IST day)', () async {
      await HiveUserSession.openForUser('aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final sub = SubscriptionService.instance;
      await _writeFrom(_playRow());
      expect(sub.proStore, 'play');
      expect(sub.proAutoRenews, isTrue);
      expect(sub.displayExpiresAt, DateTime.parse(_storeExpiry));
      expect(sub.expiresAt, DateTime.parse(_endDate),
          reason: 'gating keeps reading end_date');
    });

    test('a later non-Play write (Razorpay, dev grant) DELETES all three keys',
        () async {
      await HiveUserSession.openForUser('bbbb2222-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
      final sub = SubscriptionService.instance;
      await _writeFrom(_playRow());
      // The existing 10 callers pass only the three required params.
      await sub.writeSubscriptionState(
          isPro: true, expiresAt: _endDate, plan: 'yearly');
      expect(sub.proStore, isNull);
      expect(sub.proAutoRenews, isFalse);
      expect(MigratedKey.read<dynamic>('pro_auto_renews'), isNull);
      expect(MigratedKey.read<dynamic>('pro_store_expires_at'), isNull);
      expect(sub.displayExpiresAt, DateTime.parse(_endDate));
    });

    test('a downgrade deletes all three keys', () async {
      await HiveUserSession.openForUser('cccc3333-cccc-cccc-cccc-cccccccccccc');
      final sub = SubscriptionService.instance;
      await _writeFrom(_playRow());
      await MigratedKey.write(
          'expiresAt',
          DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String());
      final downgrade = ProDowngradeWaiter.arm();
      expect(sub.isPro(), isFalse);
      await downgrade.wait();
      for (final k in ['pro_store', 'pro_auto_renews', 'pro_store_expires_at']) {
        expect(MigratedKey.read<dynamic>(k), isNull, reason: k);
      }
    });

    test('the keys are per-user: account B never sees A\'s Play state',
        () async {
      await HiveUserSession.openForUser('dddd4444-dddd-dddd-dddd-dddddddddddd');
      await _writeFrom(_playRow());
      expect(HiveService.instance.configBox.get('pro_store'), isNull,
          reason: 'never the shared configBox');
      await HiveUserSession.openForUser('eeee5555-eeee-eeee-eeee-eeeeeeeeeeee');
      final sub = SubscriptionService.instance;
      expect(sub.proStore, isNull);
      expect(sub.proAutoRenews, isFalse);
    });

    test('all three keys are registered as user-scoped', () {
      expect(
          UserConfigMigrator.userScopedKeys,
          containsAll(
              ['pro_store', 'pro_auto_renews', 'pro_store_expires_at']));
    });
  });

  group('expiry banner input', () {
    test('an auto-renewing Play row inside 7 days shows no amber banner', () {
      expect(
          SubscriptionService.expiryBannerSeverity(
              isPro: true,
              daysUntilExpiry: 2,
              isLapsed: false,
              renewsAutomatically: true),
          ExpiryBannerSeverity.none);
    });

    test('a non-renewing row inside 7 days still shows amber', () {
      expect(
          SubscriptionService.expiryBannerSeverity(
              isPro: true, daysUntilExpiry: 2, isLapsed: false),
          ExpiryBannerSeverity.expiringSoon);
    });

    test('a real lapse is red even when the last row was auto-renewing', () {
      expect(
          SubscriptionService.expiryBannerSeverity(
              isPro: false,
              daysUntilExpiry: -1,
              isLapsed: true,
              renewsAutomatically: true),
          ExpiryBannerSeverity.lapsed);
    });
  });
}
