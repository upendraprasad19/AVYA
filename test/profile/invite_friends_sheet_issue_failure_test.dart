// OI-348 B2 (diagnose c2e8a4): the invite sheet never fails silently any more.
//
// Before the fix a REGENERATE that got no code did nothing at all (the walk's A10). Now a load or a
// regenerate that gets no code shows ReferralCopy.codeIssueFailed with a Retry, the button comes
// back, and a later success replaces the code and clears the line. Driven through the sheet's load
// seam and SupabaseService.issueReferralCodeRpcForTest (the real regenerate path, no client).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/referral_copy.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/referral_eligibility_provider.dart';
import 'package:icanbefitter/features/profile/providers/referral_summary_provider.dart';
import 'package:icanbefitter/features/profile/screens/invite_friends_sheet.dart';

class _FakeSub implements SubscriptionService {
  @override
  Future<bool> verifyFromServer({bool force = false}) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNotice extends ReferralCreditNoticeNotifier {
  @override
  ReferralCreditNotice? build() => null;

  @override
  Future<void> check({
    bool fromResume = false,
    ReferrerSummaryCall? callForTest,
    DateTime? nowForTest,
  }) async {}
}

List<Override> _overrides() => [
      authUserIdTokenProvider.overrideWithValue('tokenA'),
      subscriptionServiceProvider.overrideWithValue(_FakeSub()),
      referrerSummaryProvider.overrideWith((ref) async => null),
      referralCreditNoticeProvider.overrideWith(() => _FakeNotice()),
      referralEligibilityProvider.overrideWith((ref) async => ReferralEligibility(
          daysRemaining: 3, signupDate: DateTime(2026, 10, 1), hasRedeemed: false)),
    ];

Widget _host(Widget child) => ProviderScope(
      key: UniqueKey(),
      overrides: _overrides(),
      child: MaterialApp(home: Scaffold(body: child)),
    );

List<Map<String, dynamic>> _row(String code, {int days = 7}) => [
      {
        'out_code': code,
        'out_expires_at': DateTime.now().toUtc().add(Duration(days: days)).toIso8601String(),
      },
    ];

final _failed = find.byKey(const ValueKey('referral-code-issue-failed'));

void main() {
  testWidgets('typography warmup', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.bodyM),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.mono),
          Text('d', style: AppTypography.h2),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
  });

  tearDown(() => SupabaseService.issueReferralCodeRpcForTest = null);

  Future<void> open(WidgetTester tester,
      Future<({String code, DateTime expiresAt})?> Function() load) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(InviteFriendsSheet(loadCodeForTest: load)));
    await tester.pumpAndSettle();
  }

  testWidgets('a load that gets no code shows the error with Retry; Retry that succeeds shows the code',
      (tester) async {
    await open(tester, () async => null);
    expect(_failed, findsOneWidget);
    expect(find.text(ReferralCopy.codeIssueFailed), findsOneWidget);

    var calls = 0;
    SupabaseService.issueReferralCodeRpcForTest = () async {
      calls++;
      return _row('AVYA-RETRY001');
    };
    await tester.tap(find.text(ReferralCopy.codeIssueRetry));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('AVYA-RETRY001'), findsOneWidget);
    expect(_failed, findsNothing);
    expect(find.text('SHARE MY CODE'), findsOneWidget);
  });

  testWidgets('REGENERATE on an expired code that gets no code shows the error and re-enables the button',
      (tester) async {
    await open(tester, () async => (
          code: 'AVYA-OLDCODE1',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ));
    expect(_failed, findsNothing, reason: 'an expired code is not a failure');
    expect(find.text('REGENERATE  →'), findsOneWidget);

    final gate = Completer<dynamic>();
    SupabaseService.issueReferralCodeRpcForTest = () => gate.future;
    await tester.tap(find.text('REGENERATE  →'));
    await tester.pump();
    // While the call runs the button is disabled (a spinner replaces its label).
    expect(find.text('REGENERATE  →'), findsNothing);
    gate.complete(<dynamic>[]);
    await tester.pumpAndSettle();

    expect(_failed, findsOneWidget);
    expect(find.text('AVYA-OLDCODE1'), findsOneWidget, reason: 'the old code stays on screen');
    final button = tester.widget<ElevatedButton>(
        find.ancestor(of: find.text('REGENERATE  →'), matching: find.byType(ElevatedButton)));
    expect(button.onPressed, isNotNull, reason: 'the button comes back after a failure');
  });

  testWidgets('REGENERATE that succeeds replaces the code and the expiry, no error line', (tester) async {
    await open(tester, () async => (
          code: 'AVYA-OLDCODE1',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ));
    SupabaseService.issueReferralCodeRpcForTest = () async => _row('AVYA-NEWCODE1');
    await tester.tap(find.text('REGENERATE  →'));
    await tester.pumpAndSettle();
    expect(find.text('AVYA-NEWCODE1'), findsOneWidget);
    expect(find.text('AVYA-OLDCODE1'), findsNothing);
    expect(find.textContaining('EXPIRES IN'), findsOneWidget);
    expect(_failed, findsNothing);
  });

  testWidgets('a failure then a success clears the error line', (tester) async {
    await open(tester, () async => (
          code: 'AVYA-OLDCODE1',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ));
    SupabaseService.issueReferralCodeRpcForTest = () async => throw StateError('offline');
    await tester.tap(find.text('REGENERATE  →'));
    await tester.pumpAndSettle();
    expect(_failed, findsOneWidget);

    SupabaseService.issueReferralCodeRpcForTest = () async => _row('AVYA-NEWCODE2');
    await tester.tap(find.text(ReferralCopy.codeIssueRetry));
    await tester.pumpAndSettle();
    expect(find.text('AVYA-NEWCODE2'), findsOneWidget);
    expect(_failed, findsNothing);
  });
}
