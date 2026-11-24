// OI-519 (+51, ADR-0022), plan docs/plans/2026-11-23-revenuecat-play-billing-51.md section 5, the audit-table rows
// outside the paywall: the share-card QR, the delete-account screen, the Profile subscription row and its manage
// action, and the SubscriptionInfoData getters they read.
//
// BEHAVIOURAL: shareCardQrUrl per mode; the getters; the REAL DeleteAccountScreen per mode and store.
// PRESENCE ONLY (the Profile screen needs the whole Hive + Supabase bootstrap): the RENEWS / EXPIRES choice and the
// manage branch, each pinned by its exact shape.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/screens/delete_account_screen.dart';
import 'package:icanbefitter/shared/widgets/paywall_play_body.dart';
import 'package:icanbefitter/shared/widgets/shareable_card.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.data);
  final SubscriptionInfoData data;
  @override
  SubscriptionInfoData build() => data;
}

const _razorpayReceipts =
    'Your Razorpay payment receipts (Razorpay retains these per Indian tax law).';

final _playRow = SubscriptionInfoData(
  isPro: true,
  plan: 'monthly',
  expiresAt: DateTime.utc(2026, 12, 24),
  store: 'play',
  autoRenews: true,
);
final _webRow = SubscriptionInfoData(
  isPro: true,
  plan: 'monthly',
  expiresAt: DateTime.utc(2026, 12, 24),
);

late int _opens;

Future<void> _pumpDelete(
    WidgetTester tester, PurchaseMode mode, SubscriptionInfoData info) async {
  PurchaseMode.debugOverrideForTests = mode;
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      subscriptionInfoProvider.overrideWith(() => _Sub(info)),
      playManageOpenerProvider.overrideWithValue(() async => _opens++),
    ],
    child: const MaterialApp(home: DeleteAccountScreen()),
  ));
  await tester.pumpAndSettle();
}

final _cancelCard = find.byKey(const ValueKey('delete-account-play-cancel'));

String _strip(String s) => s
    .replaceAll(RegExp(r'//[^\n]*'), '')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  testWidgets('typography warmup: GoogleFonts caches every family first',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.h3),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.monoXs),
          Text('d', style: AppTypography.body),
          Text('e', style: AppTypography.h1),
          Text('f', style: AppTypography.mono),
          const WardButton(label: 'x', onPressed: null),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  setUp(() => _opens = 0);
  tearDown(() => PurchaseMode.debugOverrideForTests = null);

  group('share-card QR', () {
    test('the website only where web links are allowed', () {
      expect(shareCardQrUrl(PurchaseMode.razorpay), AppConstants.appUrl);
      expect(shareCardQrUrl(PurchaseMode.none), AppConstants.playListingUrl);
      expect(
          shareCardQrUrl(PurchaseMode.playBilling), AppConstants.playListingUrl);
      expect(AppConstants.playListingUrl, isNot(contains('icanbefitter.com')));
    });

    test('the card draws the mode-aware URL', () {
      final src = _strip(
          File('lib/shared/widgets/shareable_card.dart').readAsStringSync());
      expect(src.contains('data: shareCardQrUrl(PurchaseMode.current),'),
          isTrue);
      expect(src.contains('data: AppConstants.appUrl'), isFalse);
    });
  });

  group('SubscriptionInfoData getters', () {
    test('isPlayStore needs an active PRO and store play', () {
      expect(_playRow.isPlayStore, isTrue);
      expect(_webRow.isPlayStore, isFalse);
      expect(const SubscriptionInfoData(store: 'play').isPlayStore, isFalse,
          reason: 'a lapsed Play row has nothing to manage here');
    });

    test('hasActivePaidPlan: any paid store, never referral days', () {
      expect(_playRow.hasActivePaidPlan, isTrue);
      expect(_webRow.hasActivePaidPlan, isTrue);
      expect(
          const SubscriptionInfoData(isPro: true, plan: 'referral_trial')
              .hasActivePaidPlan,
          isFalse);
      expect(const SubscriptionInfoData().hasActivePaidPlan, isFalse);
    });
  });

  group('delete account', () {
    testWidgets('play_billing + a Play row: cancel-first card with the manage '
        'link; Google keeps the receipts', (tester) async {
      await _pumpDelete(tester, PurchaseMode.playBilling, _playRow);
      expect(_cancelCard, findsOneWidget);
      expect(find.text(PurchaseCopy.playDeleteCancelFirst), findsOneWidget);
      expect(find.textContaining(PurchaseCopy.playReceiptsKept), findsOneWidget);
      expect(find.textContaining('Razorpay'), findsNothing);
      await tester.tap(find.text(PurchaseCopy.playManageButton));
      await tester.pump();
      expect(_opens, 1);
    });

    testWidgets('play_billing + a web row: no cancel card, still no Razorpay',
        (tester) async {
      await _pumpDelete(tester, PurchaseMode.playBilling, _webRow);
      expect(_cancelCard, findsNothing);
      expect(find.textContaining(PurchaseCopy.playReceiptsKept), findsOneWidget);
      expect(find.textContaining('Razorpay'), findsNothing);
    });

    for (final mode in [PurchaseMode.razorpay, PurchaseMode.none]) {
      testWidgets('${mode.wireName}: unchanged (Razorpay line, no card)',
          (tester) async {
        await _pumpDelete(tester, mode, _playRow);
        expect(_cancelCard, findsNothing);
        expect(find.textContaining(_razorpayReceipts), findsOneWidget);
        expect(find.textContaining(PurchaseCopy.playReceiptsKept), findsNothing);
      });
    }
  });

  group('Profile (presence only: the screen needs the full bootstrap)', () {
    final section = _strip(File(
            'lib/features/profile/screens/profile/subscription_section.dart')
        .readAsStringSync());
    final screen = _strip(
        File('lib/features/profile/screens/profile/screen.dart')
            .readAsStringSync());

    test('RENEWS only for a plan that renews by itself, else EXPIRES', () {
      expect(
          section.contains(
              r"'${subInfo.autoRenews ? 'RENEWS' : 'EXPIRES'} $expiryStr'"),
          isTrue);
      expect(section.contains("contains('trial') ? 'EXPIRES' : 'RENEWS'"),
          isFalse);
    });

    test('the shown date is the display date, as the IST day', () {
      expect(
          section.contains(
              'final shownExpiry = subInfo.displayExpiresAt ?? subInfo.expiresAt;'),
          isTrue);
      expect(
          section.contains(
              'final shownIst = shownExpiry == null ? null : istDateOf(shownExpiry);'),
          isTrue);
    });

    test('MANAGE on a Play row opens Google Play, before the support sheet',
        () {
      final i = screen.indexOf('void _onManageSubscription() {');
      expect(i, greaterThanOrEqualTo(0));
      final body = screen.substring(i, i + 600);
      final branch = body.indexOf(
          'if (ref.read(subscriptionInfoProvider).isPlayStore) {');
      final open = body.indexOf('ref.read(playManageOpenerProvider)()');
      final ret = body.indexOf('return;');
      final sheet = body.indexOf('showModalBottomSheet');
      expect(branch, greaterThanOrEqualTo(0));
      expect(open, greaterThan(branch));
      expect(ret, greaterThan(open));
      expect(sheet, greaterThan(ret));
    });
  });
}
