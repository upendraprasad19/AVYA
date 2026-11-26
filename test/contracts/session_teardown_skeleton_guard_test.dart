// OBS-4 (b8e3f1 sibling, 2026-06-21) — behavioral contract for
// HiveTabScaffoldMixin.isSessionTearingDown.
//
// During sign-out the auth session tears down (Hive data + owner cleared) BEFORE
// the router redirect to /sign-in lands, and during the FIX-1 pre-open window the
// Hive owner is null while the user is authenticated. In BOTH cases
// authUserIdTokenProvider returns '<anon>'. A tab screen that renders user-scoped
// content then reads an empty box, throws, and flashes its "Failed to load…"
// error card (OBS-4 — the founder's logout flash). The 4 tab screens
// (home/train/nutrition/profile) OR `isSessionTearingDown` into their loading
// branch so they show the NEUTRAL skeleton instead. This pins that getter.
//
// Run: flutter test test/contracts/session_teardown_skeleton_guard_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/shared/mixins/hive_tab_scaffold.dart';

class _HarnessScreen extends ConsumerStatefulWidget {
  const _HarnessScreen();
  @override
  ConsumerState<_HarnessScreen> createState() => _HarnessScreenState();
}

class _HarnessScreenState extends ConsumerState<_HarnessScreen>
    with HiveTabScaffoldMixin<_HarnessScreen> {
  @override
  Widget build(BuildContext context) {
    // Mirrors the 4 tab screens: render the neutral skeleton when the session
    // is tearing down, the live content otherwise. (isLoading is intentionally
    // ignored here so the test isolates isSessionTearingDown.)
    return Directionality(
      textDirection: TextDirection.ltr,
      child: isSessionTearingDown
          ? const Text('SKELETON')
          : const Text('CONTENT'),
    );
  }
}

Future<void> _pumpWithToken(WidgetTester tester, String token) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserIdTokenProvider.overrideWith((ref) => token),
      ],
      child: const _HarnessScreen(),
    ),
  );
  await tester.pump(); // let the mixin initState microtask settle
}

void main() {
  group('HiveTabScaffoldMixin.isSessionTearingDown (OBS-4)', () {
    testWidgets(
        "token '<anon>' (sign-out / pre-open window) → skeleton, NOT content",
        (tester) async {
      await _pumpWithToken(tester, '<anon>');
      expect(find.text('SKELETON'), findsOneWidget,
          reason: 'a teardown/pre-open token must render the neutral skeleton, '
              'never the user-scoped content that would throw → error card.');
      expect(find.text('CONTENT'), findsNothing);
    });

    testWidgets('real auth uid (live session) → content, NOT skeleton',
        (tester) async {
      await _pumpWithToken(tester, 'cccc1111-cccc-cccc-cccc-cccccccccccc');
      expect(find.text('CONTENT'), findsOneWidget,
          reason: 'a live session must render content as normal — the guard '
              'must not over-fire and hide a healthy screen.');
      expect(find.text('SKELETON'), findsNothing);
    });
  });
}
