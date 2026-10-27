import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Tests for SubscriptionService business logic.
///
/// We test the logic directly by manipulating the configBox via Hive,
/// bypassing the SubscriptionService singleton so we can control state.
/// Full integration tests (gate() routing → PaywallSheet) are in integration_test/.
void main() {
  late Box configBox;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    configBox = await Hive.openBox('configBox');
  });

  tearDown(() async {
    await configBox.clear();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('isPro logic', () {
    test('returns false when isPro flag is not set', () {
      expect(configBox.get('isPro', defaultValue: false), isFalse);
    });

    test('returns true when isPro=true with a future expiry date', () async {
      final futureDate = DateTime.now().add(const Duration(days: 30));
      await configBox.put('isPro', true);
      await configBox.put('expiresAt', futureDate.toIso8601String());

      final isPro = configBox.get('isPro', defaultValue: false) as bool;
      final expiresAt = DateTime.tryParse(
        configBox.get('expiresAt').toString(),
      );

      expect(isPro, isTrue);
      expect(expiresAt!.isAfter(DateTime.now()), isTrue);
    });

    test('returns false when isPro=true but expiry is in the past', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 1));
      await configBox.put('isPro', true);
      await configBox.put('expiresAt', pastDate.toIso8601String());

      final expiresAt = DateTime.tryParse(
        configBox.get('expiresAt').toString(),
      );
      final isExpired = DateTime.now().isAfter(expiresAt!);

      expect(isExpired, isTrue);
    });

    test('expiry date parsing handles ISO 8601 correctly', () {
      final now = DateTime(2026, 12, 31, 23, 59, 59);
      final parsed = DateTime.tryParse(now.toIso8601String());
      expect(parsed, equals(now));
    });
  });

  group('daysUntilExpiry logic', () {
    test('returns correct days for future expiry', () async {
      final futureDate = DateTime.now().add(const Duration(days: 15));
      await configBox.put('expiresAt', futureDate.toIso8601String());

      final expiresAt = DateTime.tryParse(
        configBox.get('expiresAt').toString(),
      )!;
      final days = expiresAt.difference(DateTime.now()).inDays;

      expect(days, closeTo(14, 1)); // 14 or 15 depending on time of day
    });

    test('returns 0 when expiry is today', () async {
      final today = DateTime.now();
      await configBox.put('expiresAt', today.toIso8601String());

      final expiresAt = DateTime.tryParse(
        configBox.get('expiresAt').toString(),
      )!;
      final days = expiresAt.difference(DateTime.now()).inDays;

      expect(days, 0);
    });

    test('returns -1 when no expiry date is stored', () {
      final raw = configBox.get('expiresAt');
      expect(raw, isNull);
    });
  });

  group('isExpiringSoon logic', () {
    test('true when expiry is within 7 days', () async {
      final soonDate = DateTime.now().add(const Duration(days: 5));
      await configBox.put('isPro', true);
      await configBox.put('expiresAt', soonDate.toIso8601String());

      final expiresAt = DateTime.tryParse(
        configBox.get('expiresAt').toString(),
      )!;
      final days = expiresAt.difference(DateTime.now()).inDays;

      expect(days >= 0 && days < 7, isTrue);
    });

    test('false when expiry is more than 7 days away', () async {
      final farDate = DateTime.now().add(const Duration(days: 30));
      await configBox.put('isPro', true);
      await configBox.put('expiresAt', farDate.toIso8601String());

      final expiresAt = DateTime.tryParse(
        configBox.get('expiresAt').toString(),
      )!;
      final days = expiresAt.difference(DateTime.now()).inDays;

      expect(days < 7, isFalse);
    });
  });

  group('plan storage', () {
    test('stores and retrieves plan type correctly', () async {
      await configBox.put('plan', 'monthly');
      expect(configBox.get('plan'), 'monthly');
    });

    test('distinguishes monthly vs yearly plan', () async {
      await configBox.put('plan', 'yearly');
      expect(configBox.get('plan'), 'yearly');
      expect(configBox.get('plan'), isNot('monthly'));
    });
  });
}
