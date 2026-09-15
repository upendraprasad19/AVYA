import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/auth/screens/confirm_email_screen.dart';

/// Fails the test if [confirmEmail] is ever called — proves the missing/empty
/// token_hash guard short-circuits before touching Supabase at all, rather
/// than merely happening to render the right text on top of a real call.
class _CallCountingAuthNotifier extends AuthNotifier {
  int confirmEmailCallCount = 0;

  @override
  Future<void> confirmEmail(String tokenHash) async {
    confirmEmailCallCount++;
  }
}

void main() {
  testWidgets(
    'a missing token_hash shows the invalid-link message without calling confirmEmail',
    (tester) async {
      final notifier = _CallCountingAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(home: ConfirmEmailScreen(tokenHash: null)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('missing its token'),
        findsOneWidget,
        reason: 'a null token_hash must show the malformed-link message',
      );
      expect(
        notifier.confirmEmailCallCount,
        0,
        reason:
            'a null token_hash must never reach confirmEmail — there is '
            'nothing valid to verify',
      );
    },
  );

  testWidgets(
    'an empty token_hash shows the invalid-link message without calling confirmEmail',
    (tester) async {
      final notifier = _CallCountingAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(home: ConfirmEmailScreen(tokenHash: '')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('missing its token'), findsOneWidget);
      expect(notifier.confirmEmailCallCount, 0);
    },
  );

  testWidgets(
    'a present token_hash calls confirmEmail exactly once and shows the loading state',
    (tester) async {
      final notifier = _CallCountingAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(
            home: ConfirmEmailScreen(tokenHash: 'real-token-hash'),
          ),
        ),
      );
      // NOT pumpAndSettle: the loading state's CircularProgressIndicator
      // animates forever, so pumpAndSettle would time out waiting for it.
      await tester.pump();

      expect(find.textContaining('Confirming your account'), findsOneWidget);
      expect(notifier.confirmEmailCallCount, 1);

      // A rebuild (e.g. a parent re-layout) must not re-trigger verification
      // — the _started guard is the whole point, mirroring
      // ResetPasswordScreen's identical initState guard.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(
            home: ConfirmEmailScreen(tokenHash: 'real-token-hash'),
          ),
        ),
      );
      await tester.pump();
      expect(notifier.confirmEmailCallCount, 1);
    },
  );
}
