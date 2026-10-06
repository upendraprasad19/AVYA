// Contract: RestoringScreen.resolveRestoreDestination — the post-restore
// destination allowlist.
//
// A cold web load of `/admin` (or any session-gated route) is redirected by
// `_authRedirect` through `/restoring` while the Hive session opens. Before
// this fix RestoringScreen ALWAYS landed an onboarded user on `/home`,
// discarding the original `/admin` target (admin/CLAUDE.md:114, B-pass
// Finding 4) — so a bookmarked `/admin` bounced to Home.
//
// The fix threads a `next` query param through `/restoring` and honors it at
// the terminal navigations. `resolveRestoreDestination` is the pure guard: it
// returns `next` ONLY when it is in a tiny allowlist (currently just
// `/admin`), else `/home`. The allowlist stops the `next` query param from
// being abused as a general in-app open-redirect vector.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/router/app_router.dart';
import 'package:icanbefitter/features/auth/screens/restoring_screen.dart';

void main() {
  group('RestoringScreen.resolveRestoreDestination', () {
    test('null next defaults to /home (every ordinary returning user)', () {
      expect(RestoringScreen.resolveRestoreDestination(null), '/home');
    });

    test('allowlisted /admin is honored', () {
      expect(RestoringScreen.resolveRestoreDestination('/admin'), '/admin');
    });

    test('a non-allowlisted in-app route falls back to /home (redirect guard)',
        () {
      expect(
        RestoringScreen.resolveRestoreDestination('/profile/reports'),
        '/home',
      );
      expect(RestoringScreen.resolveRestoreDestination('/sign-in'), '/home');
      expect(RestoringScreen.resolveRestoreDestination('/home'), '/home');
    });

    test('an external/absolute URL is rejected (never an open redirect)', () {
      expect(
        RestoringScreen.resolveRestoreDestination('https://evil.example'),
        '/home',
      );
      expect(
        RestoringScreen.resolveRestoreDestination('//evil.example'),
        '/home',
      );
    });

    test('empty string falls back to /home', () {
      expect(RestoringScreen.resolveRestoreDestination(''), '/home');
    });
  });

  group('AppRouter.restoringRedirectFor (the writer side)', () {
    test('/admin threads an encoded next param', () {
      expect(
        AppRouter.restoringRedirectFor('/admin'),
        '/restoring?next=%2Fadmin',
      );
    });

    test('every other gated route gets the bare /restoring (unchanged)', () {
      expect(AppRouter.restoringRedirectFor('/home'), '/restoring');
      expect(AppRouter.restoringRedirectFor('/profile/reports'), '/restoring');
      expect(AppRouter.restoringRedirectFor('/train'), '/restoring');
    });

    // The writer/reader drift guard: the emitted %2Fadmin, when parsed by
    // GoRouter (Uri query decode), MUST yield '/admin' so the reader's
    // allowlist honors it. If the encoding or the allowlisted route drifts on
    // either side, this round-trip breaks.
    test('ROUND-TRIP: emitted next decodes back to the allowlisted /admin', () {
      final redirect = AppRouter.restoringRedirectFor('/admin');
      final decodedNext = Uri.parse(redirect).queryParameters['next'];
      expect(decodedNext, '/admin');
      expect(
        RestoringScreen.resolveRestoreDestination(decodedNext),
        '/admin',
      );
    });
  });
}
