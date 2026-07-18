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
}
