// OI-305 (founder decision 2026-10-16): email sign-up has NO consent checkbox.
// "By tapping CREATE ACCOUNT, you agree to our Privacy Policy and Terms" sits
// above the button, the button is enabled without any tick, and the tap stamps
// terms_accepted_at and terms_version (the current AppConstants.termsVersion).
// Behavioural: drives the real SignInScreen sign-up step with a recording
// notifier, so a regression that disables the button, brings a checkbox back or
// stops stamping the acceptance fails here.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/auth/screens/sign_in_screen.dart';

class _RecordingAuthNotifier extends AuthNotifier {
  final calls = <Map<String, Object?>>[];

  @override
  Future<bool?> checkEmailRegistered(String email) async => false;

  @override
  Future<void> signUpWithEmail(
    String email,
    String password, {
    String? termsAcceptedAt,
    String? termsVersion,
    String? referralCode,
  }) async {
    calls.add({
      'email': email,
      'password': password,
      'termsAcceptedAt': termsAcceptedAt,
      'termsVersion': termsVersion,
      'referralCode': referralCode,
    });
  }
}

Future<_RecordingAuthNotifier> _openSignUpStep(WidgetTester tester) async {
  final notifier = _RecordingAuthNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authNotifierProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: SignInScreen()),
    ),
  );
  await tester.pumpAndSettle();
  final emailField = find.byType(TextFormField).first;
  await tester.ensureVisible(emailField);
  await tester.enterText(emailField, 'fresh@example.com');
  await tester.ensureVisible(find.text('CONTINUE'));
  await tester.tap(find.text('CONTINUE'));
  await tester.pumpAndSettle();
  expect(find.text('CREATE ACCOUNT'), findsOneWidget, reason: 'precondition');
  return notifier;
}

bool _hasRichText(String plain) => find
    .byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == plain,
    )
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('the sign-up step has no checkbox and shows the by-tapping '
      'notice with both links', (tester) async {
    await _openSignUpStep(tester);
    expect(find.byType(Checkbox), findsNothing);
    expect(
      _hasRichText(
        'By tapping CREATE ACCOUNT, you agree to our Privacy Policy and '
        'Terms.',
      ),
      isTrue,
      reason: 'the consent notice text above the button',
    );
    // The notice IS the consent mechanism: textDim (readable), not textMute
    // (about 3.5:1 on the form background, below the 4.5:1 AA floor).
    final notice = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText().startsWith('By tapping CREATE ACCOUNT'),
      ),
    );
    expect(notice.text.style?.color, AppColors.textDim);
  });

  testWidgets('CREATE ACCOUNT is enabled with no tick and a tap stamps the '
      'acceptance (time + current terms version)', (tester) async {
    final notifier = await _openSignUpStep(tester);
    final password = find.byType(TextFormField).first;
    await tester.ensureVisible(password);
    await tester.enterText(password, 'secret123');
    final button = find.text('CREATE ACCOUNT');
    await tester.ensureVisible(button);
    final before = DateTime.now().toUtc();
    await tester.tap(button);
    await tester.pump();
    final after = DateTime.now().toUtc();

    expect(notifier.calls, hasLength(1), reason: 'the tap must sign up');
    final call = notifier.calls.single;
    expect(call['email'], 'fresh@example.com');
    expect(call['termsVersion'], AppConstants.termsVersion);
    expect(AppConstants.termsVersion, 'v2');
    final stamp = DateTime.parse(call['termsAcceptedAt']! as String);
    expect(stamp.isUtc, isTrue, reason: 'the cloud column is timestamptz');
    expect(
      stamp.isBefore(before.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(stamp.isAfter(after.add(const Duration(seconds: 1))), isFalse);
  });
}
