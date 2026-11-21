@Timeout(Duration(minutes: 3))
library;

// Unit C (OI-336) - the per-user key's sign-out lifecycle (BEHAVIOURAL) and the
// presence pins that keep the unit's invariants from drifting (PRESENCE only;
// each is paired with a behavioural twin in referral_credit_notice_behavioral_
// test.dart / referral_unit_c_surfaces_test.dart). Plan:
// docs/plans/referral-unit-c-client.md (sections 2.3, 2.4, 3).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/user_config_migrator.dart';
import 'package:icanbefitter/features/profile/providers/referral_summary_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return s
      .split('\n')
      .map((l) {
        final m = RegExp(r'(?<!:)//').firstMatch(l);
        return m == null ? l : l.substring(0, m.start);
      })
      .join('\n');
}

String _read(String path) => _strip(File(path).readAsStringSync());

void main() {
  group('referral_credit_seen_days lifecycle (BEHAVIOURAL)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    test('the key is registered as user-scoped', () {
      expect(UserConfigMigrator.userScopedKeys,
          contains(kReferralCreditSeenKey));
    });

    test('written through MigratedKey it lands in the USER box, is readable, '
        'and is gone after clearAllData()', () async {
      await MigratedKey.write(kReferralCreditSeenKey, 14);
      expect(HiveService.instance.userBox.containsKey(kReferralCreditSeenKey),
          isTrue,
          reason: 'precondition: the write landed in the user box');
      expect(HiveService.instance.configBox.containsKey(kReferralCreditSeenKey),
          isFalse,
          reason: 'it must not be in the shared box');
      expect(MigratedKey.read<dynamic>(kReferralCreditSeenKey), 14);

      final result = await UserRepository.instance.clearAllData();
      expect(result.isClean, isTrue, reason: '$result');

      expect(HiveService.instance.userBox.containsKey(kReferralCreditSeenKey),
          isFalse);
      expect(HiveService.instance.configBox.containsKey(kReferralCreditSeenKey),
          isFalse);
      expect(MigratedKey.read<dynamic>(kReferralCreditSeenKey), isNull);
      expect(
          HiveService.instance.migrationBox.keys.map((e) => '$e'),
          isNot(contains(kReferralCreditSeenKey)),
          reason: 'no device-lifetime copy may survive a sign-out');
    });
  });

  group('presence pins (paired with the behavioural twins above)', () {
    test('no client file that touches referral_redemptions names a hidden '
        'payment-status column (migration 160 column-level SELECT)', () {
      const hidden = [
        'converted_at',
        'referrer_reward_days',
        'referrer_credited_at',
        'referrer_rewarded',
        'referee_rewarded',
      ];
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = _read(f.path);
        if (!src.contains('referral_redemptions')) continue;
        for (final c in hidden) {
          if (src.contains(c)) offenders.add('${f.path}: $c');
        }
      }
      expect(offenders, isEmpty,
          reason: 'select * fails with 42501 for these; use referrer_summary()');
    });

    test('the repository reads the referrer figures through the RPC only', () {
      final repo =
          _read('lib/features/profile/repositories/referral_repository.dart');
      expect(repo, contains(".rpc('referrer_summary')"));
      expect(repo, isNot(contains(".from('referral_redemptions')\n          .select('*'")));
    });

    test('the invite sheet funnels redeem through the repository and verifies '
        'with force: true', () {
      final sheet =
          _read('lib/features/profile/screens/invite_friends_sheet.dart');
      expect(sheet, contains('ReferralRepository.instance.redeem'));
      expect(sheet, contains('verifyFromServer(force: true)'));
      expect(sheet, isNot(contains('profile_apply_referral_code_failed')));
      final apply =
          _read('lib/features/profile/screens/apply_referral_sheet.dart');
      expect(apply, contains('verifyFromServer(force: true)'));
    });

    test('the Home screen mounts the credit slot and triggers the notice on '
        'resume and on a restore tick', () {
      final home = _read('lib/features/home/screens/home_screen.dart');
      expect(home, contains('const ReferralCreditSlot()'));
      expect(home, contains('check(fromResume: true)'));
      expect(home, contains('referralCreditNoticeProvider.notifier'));
    });

    test('every friend-facing code-entry surface renders the disclosure line',
        () {
      for (final f in [
        'lib/features/profile/screens/invite_friends_sheet.dart',
        'lib/features/profile/screens/apply_referral_sheet.dart',
        'lib/features/auth/screens/sign_in_screen.dart',
        'lib/features/onboarding/screens/welcome_screen.dart',
      ]) {
        expect(_read(f), contains('ReferralCopy.friendDisclosure'), reason: f);
      }
    });

    test('the root CLAUDE.md Auth row says Phone OTP is NOT live', () {
      final root = File('CLAUDE.md').readAsStringSync();
      final row = root.split('\n').firstWhere((l) => l.startsWith('| Auth |'));
      expect(row, contains('Phone OTP is NOT live'));
      expect(row, isNot(contains('+ Phone OTP')));
    });
  });
}
