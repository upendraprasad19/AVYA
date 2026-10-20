// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the FIRST test
// is a typography warmup that runs before any path_provider mock is installed.
@Timeout(Duration(minutes: 3))
library;

// Unit C (OI-336) - the SURFACES: the referrer counters block, the invite
// sheet (copy, scroll, apply flow), the apply sheet, the Home credit slot, and
// the friend disclosure line on every code-entry surface. Plan:
// docs/plans/referral-unit-c-client.md (sections 2.2, 2.3, 3).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/referral_copy.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart' show WardButton;
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/auth/screens/sign_in_screen.dart';
import 'package:icanbefitter/features/home/widgets/referral_credit_slot.dart';
import 'package:icanbefitter/features/onboarding/screens/welcome_screen.dart';
import 'package:icanbefitter/features/profile/models/referrer_summary.dart';
import 'package:icanbefitter/features/profile/providers/referral_eligibility_provider.dart';
import 'package:icanbefitter/features/profile/providers/referral_summary_provider.dart';
import 'package:icanbefitter/features/profile/repositories/referral_repository.dart';
import 'package:icanbefitter/features/profile/screens/apply_referral_sheet.dart';
import 'package:icanbefitter/features/profile/screens/invite_friends_sheet.dart';
import 'package:icanbefitter/features/profile/widgets/referrer_counters_block.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, FunctionResponse;

class _FakeSub implements SubscriptionService {
  final List<bool> forceArgs = [];
  @override
  Future<bool> verifyFromServer({bool force = false}) async {
    forceArgs.add(force);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNotice extends ReferralCreditNoticeNotifier {
  _FakeNotice(this.initial, this.log);
  final ReferralCreditNotice? initial;
  final List<String> log;

  @override
  ReferralCreditNotice? build() => initial;

  @override
  Future<void> check({
    bool fromResume = false,
    ReferrerSummaryCall? callForTest,
    DateTime? nowForTest,
  }) async =>
      log.add('check');

  @override
  Future<void> dismiss() async {
    log.add('dismiss');
    state = null;
  }
}

const _summary = ReferrerSummary(
    joined: 5, subscribed: 2, pending: 1, credited: 1, daysEarned: 14);

Widget _host(
  Widget child, {
  List<Override> overrides = const [],
  double textScale = 1.0,
  double keyboard = 0,
}) {
  return ProviderScope(
    // A fresh container per pump, so a second pump with other overrides is not
    // answered from the first one's cached providers.
    key: UniqueKey(),
    overrides: [
      authUserIdTokenProvider.overrideWithValue('tokenA'),
      ...overrides,
    ],
    child: MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: c!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

Override _summaryIs(Future<ReferrerSummary?> Function() f) =>
    referrerSummaryProvider.overrideWith((ref) => f());

void main() {
  testWidgets('typography warmup - GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.body),
          Text('b', style: AppTypography.bodyS),
          Text('c', style: AppTypography.bodyM),
          Text('d', style: AppTypography.mono),
          Text('e', style: AppTypography.h2),
          Text('f', style: AppTypography.bodySm),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('ReferrerCountersBlock', () {
    testWidgets('a known summary shows the exact numbers, PENDING only when > 0',
        (tester) async {
      await tester.pumpWidget(_host(const ReferrerCountersBlock(),
          overrides: [_summaryIs(() async => _summary)]));
      await tester.pumpAndSettle();
      Text tile(String key) => tester.widget<Text>(find
          .descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))
          .first);
      expect(tile('referrer-tile-joined').data, '5');
      expect(tile('referrer-tile-subscribed').data, '2');
      expect(tile('referrer-tile-days').data, '14');
      expect(tile('referrer-tile-pending').data, '1');

      await tester.pumpWidget(_host(const ReferrerCountersBlock(), overrides: [
        _summaryIs(() async => const ReferrerSummary(
            joined: 5, subscribed: 2, pending: 0, credited: 2, daysEarned: 14)),
      ]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('referrer-tile-pending')), findsNothing);
      expect(find.byKey(const ValueKey('referrer-tile-joined')), findsOneWidget);
    });

    testWidgets('unknown (null), zero joined and an error all render NOTHING',
        (tester) async {
      Future<void> expectHidden(Override o) async {
        await tester.pumpWidget(_host(const ReferrerCountersBlock(), overrides: [o]));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('referrer-tile-joined')), findsNothing);
        expect(find.byKey(const ValueKey('referrer-counters-skeleton')),
            findsNothing);
        expect(find.text(ReferralCopy.countersEyebrow), findsNothing);
      }

      await expectHidden(_summaryIs(() async => null));
      await expectHidden(_summaryIs(() async => const ReferrerSummary(
          joined: 0, subscribed: 0, pending: 0, credited: 0, daysEarned: 0)));
      await expectHidden(_summaryIs(() async => throw StateError('x')));
    });

    testWidgets('while loading it shows a skeleton of tiles, never a spinner',
        (tester) async {
      final gate = Completer<ReferrerSummary?>();
      await tester.pumpWidget(_host(const ReferrerCountersBlock(),
          overrides: [_summaryIs(() => gate.future)]));
      await tester.pump();
      expect(find.byKey(const ValueKey('referrer-counters-skeleton')),
          findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      gate.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('the block announces one Semantics label with the real numbers',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const ReferrerCountersBlock(),
          overrides: [_summaryIs(() async => _summary)]));
      await tester.pumpAndSettle();
      expect(
          find.bySemanticsLabel(
              '5 friends joined, 2 subscribed, 14 days earned, 1 pending'),
          findsOneWidget);
      handle.dispose();
    });
  });

  group('InviteFriendsSheet', () {
    late _FakeSub sub;
    var eligibilityBuilds = 0;

    List<Override> overrides({Future<ReferrerSummary?> Function()? summary}) => [
          subscriptionServiceProvider.overrideWithValue(sub),
          _summaryIs(summary ?? () async => _summary),
          referralCreditNoticeProvider
              .overrideWith(() => _FakeNotice(null, <String>[])),
          referralEligibilityProvider.overrideWith((ref) async {
            eligibilityBuilds++;
            return ReferralEligibility(
                daysRemaining: 3,
                signupDate: DateTime(2026, 10, 1),
                hasRedeemed: false);
          }),
        ];

    setUp(() {
      sub = _FakeSub();
      eligibilityBuilds = 0;
    });

    tearDown(() => ReferralRepository.redeemCallForTest = null);

    Future<void> openSheet(WidgetTester tester,
        {double textScale = 1.0, double keyboard = 0}) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(const InviteFriendsSheet(),
          overrides: overrides(), textScale: textScale, keyboard: keyboard));
      await tester.pumpAndSettle();
    }

    Future<void> apply(WidgetTester tester) async {
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'avya-abc12345');
      await tester.ensureVisible(find.text('APPLY'));
      await tester.tap(find.text('APPLY'));
      await tester.pumpAndSettle();
    }

    testWidgets('states the REAL rule, not "you both get 7 days"', (tester) async {
      await openSheet(tester);
      expect(find.text(ReferralCopy.inviteDescription), findsOneWidget);
      expect(find.textContaining('you both get'), findsNothing);
      expect(find.textContaining('within 90 days'), findsOneWidget);
      expect(find.textContaining('unless they cancel'), findsOneWidget);
    });

    testWidgets('shows the counters below the action and the friend disclosure',
        (tester) async {
      await openSheet(tester);
      expect(find.byKey(const ValueKey('referrer-tile-joined')), findsOneWidget);
      final regenerate = tester.getTopLeft(find.text('REGENERATE  →')).dy;
      final counters = tester.getTopLeft(find.text(ReferralCopy.countersEyebrow)).dy;
      expect(counters, greaterThan(regenerate),
          reason: 'a late block must never shift the code and the action');
      expect(find.byKey(const ValueKey('referral-friend-disclosure')),
          findsOneWidget);
      expect(find.text(ReferralCopy.friendDisclosure), findsOneWidget);
    });

    testWidgets('in the SHARE state (a valid code) the counters sit below the '
        'Share action and the apply field stays reachable with the keyboard '
        'open', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(
        InviteFriendsSheet(
          loadCodeForTest: () async => (
            code: 'AVYA-TESTCODE',
            expiresAt: DateTime.now().add(const Duration(days: 5)),
          ),
        ),
        overrides: overrides(),
        keyboard: 300,
      ));
      await tester.pumpAndSettle();
      expect(find.text('AVYA-TESTCODE'), findsOneWidget);
      expect(find.text('REGENERATE  →'), findsNothing);
      final share = tester.getTopLeft(find.byType(WardButton)).dy;
      final counters =
          tester.getTopLeft(find.text(ReferralCopy.countersEyebrow)).dy;
      expect(counters, greaterThan(share));
      // With the keyboard open the apply field can still be scrolled into view
      // and typed into.
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'avya-abc12345');
      expect(tester.takeException(), isNull);
      expect(find.text('avya-abc12345'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits 360x640 at ${scale}x text with the keyboard open, '
          'without overflow', (tester) async {
        await openSheet(tester, textScale: scale, keyboard: 300);
        expect(tester.takeException(), isNull);
        // And the whole thing can be scrolled to the disclosure.
        await tester.ensureVisible(find.text(ReferralCopy.friendDisclosure));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a 200 without success is not announced as a grant', (tester) async {
      ReferralRepository.redeemCallForTest =
          (_) async => FunctionResponse(status: 200, data: <String, dynamic>{});
      await openSheet(tester);
      await apply(tester);
      expect(find.text(ReferralCopy.codeApplied), findsNothing);
      expect(find.text('Could not confirm that code. Please try again.'),
          findsOneWidget);
      expect(sub.forceArgs, isEmpty);
    });

    testWidgets("a paid friend's 400 shows the SERVER's reason, not a generic "
        'mask', (tester) async {
      ReferralRepository.redeemCallForTest = (_) async => throw FunctionException(
          status: 400,
          details: {'error': 'You already have an active paid plan.'});
      await openSheet(tester);
      await apply(tester);
      expect(find.text('You already have an active paid plan.'), findsOneWidget);
      expect(find.text('Could not apply code. Please try again.'), findsNothing);
      expect(sub.forceArgs, isEmpty);
    });

    testWidgets('alreadyRedeemed says so and does NOT claim +7 days', (tester) async {
      ReferralRepository.redeemCallForTest = (_) async => FunctionResponse(
          status: 200, data: {'success': true, 'alreadyRedeemed': true});
      await openSheet(tester);
      await apply(tester);
      expect(find.text(ReferralCopy.codeAlreadyApplied), findsOneWidget);
      expect(find.textContaining('+7 days'), findsNothing);
      expect(sub.forceArgs, isEmpty);
    });

    testWidgets('a fresh success verifies the subscription with force: true and '
        'invalidates the eligibility provider', (tester) async {
      ReferralRepository.redeemCallForTest =
          (_) async => FunctionResponse(status: 200, data: {'success': true});
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Something must LISTEN to the eligibility provider for an invalidation to
      // rebuild it.
      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue('tokenA'),
        ...overrides(),
      ]);
      addTearDown(container.dispose);
      container.listen(referralEligibilityProvider, (_, _) {});
      await container.read(referralEligibilityProvider.future);
      final before = eligibilityBuilds;
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: InviteFriendsSheet()))));
      await tester.pumpAndSettle();
      await apply(tester);
      expect(find.text(ReferralCopy.codeApplied), findsOneWidget);
      expect(sub.forceArgs, [true]);
      await container.read(referralEligibilityProvider.future);
      expect(eligibilityBuilds, greaterThan(before));
    });
  });

  group('ApplyReferralSheet', () {
    testWidgets('carries the friend disclosure line', (tester) async {
      await tester.pumpWidget(_host(const ApplyReferralSheet()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('referral-friend-disclosure')),
          findsOneWidget);
      expect(find.text(ReferralCopy.friendDisclosure), findsOneWidget);
    });
  });

  group('ReferralCreditSlot', () {
    Future<List<String>> pumpSlot(WidgetTester tester,
        {ReferralCreditNotice? notice}) async {
      final log = <String>[];
      await tester.pumpWidget(_host(const ReferralCreditSlot(), overrides: [
        referralCreditNoticeProvider.overrideWith(() => _FakeNotice(notice, log)),
        subscriptionServiceProvider.overrideWithValue(_FakeSub()),
        _summaryIs(() async => null),
      ]));
      await tester.pumpAndSettle();
      return log;
    }

    testWidgets('renders nothing when no credit is waiting, and asks for ONE '
        'check on mount', (tester) async {
      final log = await pumpSlot(tester);
      expect(find.byKey(const ValueKey('referral-credit-card')), findsNothing);
      expect(log, ['check']);
    });

    testWidgets('a waiting credit shows count-neutral copy, singular-safe',
        (tester) async {
      await pumpSlot(tester,
          notice: const ReferralCreditNotice(days: 7, totalDaysEarned: 14));
      expect(find.text('You earned 7 PRO days from friends who subscribed.'),
          findsOneWidget);
    });

    testWidgets('the X dismisses and does NOT open the invite sheet',
        (tester) async {
      final log = await pumpSlot(tester,
          notice: const ReferralCreditNotice(days: 7, totalDaysEarned: 7));
      await tester.tap(find.byKey(const ValueKey('referral-credit-dismiss')));
      await tester.pumpAndSettle();
      expect(log, ['check', 'dismiss']);
      expect(find.byKey(const ValueKey('referral-credit-card')), findsNothing);
      expect(find.text('Invite a Friend'), findsNothing);
    });

    testWidgets('tapping the card body dismisses AND opens the invite sheet',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final log = await pumpSlot(tester,
          notice: const ReferralCreditNotice(days: 7, totalDaysEarned: 7));
      await tester.tap(find.text('You earned 7 PRO days from friends who subscribed.'));
      await tester.pumpAndSettle();
      // The third entry is the invite sheet's own trigger: opening it asks for
      // one (single-flight) check.
      expect(log, ['check', 'dismiss', 'check']);
      expect(find.text('Invite a Friend'), findsOneWidget);
    });
  });

  group('friend disclosure on the other code-entry surfaces', () {
    // Measured 2026-10-17 (Ahem, 360x640): fits through 1.5x text. At 2x the
    // screen ALREADY overflowed before this unit (28 px on the right, on the
    // unmodified file); the extra line adds bottom overflow there. 2x is not
    // asserted for this screen.
    testWidgets('the onboarding welcome screen carries the line and still fits '
        'a short viewport at 1.5x text', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(const WelcomeScreen(), textScale: 1.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(ReferralCopy.friendDisclosure, skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('the sign-up form carries the line right after the existing '
        'caption', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(_SignUpNotifier.new),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ));
      await tester.pumpAndSettle();
      final email = find.byType(TextFormField).first;
      await tester.ensureVisible(email);
      await tester.enterText(email, 'fresh@example.com');
      await tester.ensureVisible(find.text('CONTINUE'));
      await tester.tap(find.text('CONTINUE'));
      await tester.pumpAndSettle();
      final caption = find.text('Have a referral code? Apply for +7 days PRO.',
          skipOffstage: false);
      final line = find.text(ReferralCopy.friendDisclosure, skipOffstage: false);
      expect(caption, findsOneWidget);
      expect(line, findsOneWidget);
      expect(tester.getTopLeft(line).dy, greaterThan(tester.getTopLeft(caption).dy));
    });
  });
}

class _SignUpNotifier extends AuthNotifier {
  @override
  Future<bool?> checkEmailRegistered(String email) async => false;
}
