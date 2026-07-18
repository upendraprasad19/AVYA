import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/auth/screens/sign_in_screen.dart';

/// Fake notifier that answers the email-registration check directly, with
/// no real Supabase call, so the runtime enterEmail → signIn/signUp
/// transition can be exercised without network/Hive setup.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._registered);
  final bool? _registered;

  @override
  Future<bool?> checkEmailRegistered(String email) async => _registered;
}

/// Fake notifier that counts calls and defers its result past a microtask
/// boundary, so a same-frame double-tap (before `isLoading` flips on the
/// next build) has a real window to fire the check twice if unguarded.
class _CountingDelayedAuthNotifier extends AuthNotifier {
  int callCount = 0;

  @override
  Future<bool?> checkEmailRegistered(String email) async {
    callCount++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return true;
  }
}

Future<void> _openEmailStep(WidgetTester tester, String email) async {
  await tester.tap(find.text('ENLIST VIA EMAIL'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, email);
  await tester.tap(find.text('CONTINUE'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a registered email routes to the sign-in step: password only, no referral/checkbox',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(() => _FakeAuthNotifier(true)),
          ],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await _openEmailStep(tester, 'existing@example.com');

      expect(find.text('SIGN IN WITH EMAIL'), findsOneWidget,
          reason: 'registered=true must land on the sign-in step');
      expect(find.text('CREATE ACCOUNT'), findsNothing);
      expect(find.text('REFERRAL CODE (OPTIONAL)'), findsNothing,
          reason: 'sign-in step must not show sign-up-only fields');
    },
  );

  testWidgets(
    'an unregistered email routes to the sign-up step: password + referral + checkbox',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(() => _FakeAuthNotifier(false)),
          ],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await _openEmailStep(tester, 'fresh@example.com');

      expect(find.text('CREATE ACCOUNT'), findsOneWidget,
          reason: 'registered=false must land on the sign-up step');
      expect(find.text('SIGN IN WITH EMAIL'), findsNothing);
      expect(find.text('REFERRAL CODE (OPTIONAL)'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed registration check stays on the enterEmail step (no silent branch)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(() => _FakeAuthNotifier(null)),
          ],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await _openEmailStep(tester, 'error@example.com');

      expect(find.text('CONTINUE'), findsOneWidget,
          reason: 'a null (error) result must not branch to either sign-in '
              'or sign-up');
      expect(find.text('SIGN IN WITH EMAIL'), findsNothing);
      expect(find.text('CREATE ACCOUNT'), findsNothing);
    },
  );

  testWidgets('"CHANGE EMAIL" returns to the enterEmail step', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(() => _FakeAuthNotifier(false)),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await _openEmailStep(tester, 'fresh@example.com');
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);

    // The sign-up step is taller than the 600px test viewport, so scroll the
    // CHANGE EMAIL link into view before tapping (on-device the sub-view
    // scrolls; the test env doesn't auto-scroll for a tap).
    await tester.ensureVisible(find.text('CHANGE EMAIL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CHANGE EMAIL'));
    await tester.pumpAndSettle();

    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text('CREATE ACCOUNT'), findsNothing);
  });

  testWidgets(
    'a same-frame double-tap on CONTINUE only fires checkEmailRegistered once',
    (tester) async {
      final notifier = _CountingDelayedAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(() => notifier),
          ],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ENLIST VIA EMAIL'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextFormField).first, 'racer@example.com');

      // Two taps before any pump — both land in the same frame, before the
      // reentrancy guard's setState has a chance to rebuild the button.
      await tester.tap(find.text('CONTINUE'));
      await tester.tap(find.text('CONTINUE'));
      await tester.pumpAndSettle();

      expect(notifier.callCount, 1,
          reason: 'the synchronous _checkingEmail guard must reject the '
              'second same-frame tap before it reaches checkEmailRegistered');
      expect(find.text('SIGN IN WITH EMAIL'), findsOneWidget);
    },
  );
}
