import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/confirm_link_detector.dart';

/// Behavioral regression test for diagnose f92d17 (2026-09-23): live-verified
/// via `curl -D-` against the real Vercel deployment that `/confirm`'s
/// redirect rule (`destination: "/#/confirm"`) issues
/// `Location: /?token_hash=X&type=signup#/confirm` — the forwarded query
/// string lands BEFORE the literal `#/confirm`, not inside it. Reproduced
/// live on a real device (iPhone Safari via a genuine Gmail confirmation-link
/// tap, and again on Android with the app installed — App Links did not
/// claim the URL either, falling through to the same broken web path):
/// `ConfirmEmailScreen` rendered "This confirmation link is missing its
/// token" even though `token_hash` was genuinely present in the URL, one
/// component away from where GoRouter's HashUrlStrategy looks.
///
/// Fails on pre-fix code (nothing read `Uri.base.queryParameters` at all —
/// `app_router.dart`'s `/confirm` route relied solely on
/// `state.uri.queryParameters`, which HashUrlStrategy derives from
/// `location.hash` and therefore never sees a query string that landed in
/// `location.search`) and passes after the fix.
void main() {
  group('ConfirmLinkDetector.detect', () {
    test(
      'detects token_hash from the ACTUAL live-broken shape — query before '
      'the # (the real bug, confirmed by curl against the live deployment)',
      () {
        final result = ConfirmLinkDetector.detect(
          Uri.parse(
            'https://app.icanbefitter.com/?token_hash=pkce_abc123&type=signup#/confirm',
          ),
        );
        expect(result, 'pkce_abc123');
      },
    );

    test(
      'detects token_hash from the CORRECT shape too, if the hash route '
      'ever carries its own query string directly',
      () {
        final result = ConfirmLinkDetector.detect(
          Uri.parse(
            'https://app.icanbefitter.com/#/confirm?token_hash=pkce_xyz789&type=signup',
          ),
        );
        expect(result, 'pkce_xyz789');
      },
    );

    test('prefers the fragment-embedded value when BOTH are somehow present', () {
      final result = ConfirmLinkDetector.detect(
        Uri.parse(
          'https://app.icanbefitter.com/?token_hash=stale_query#/confirm?token_hash=fresh_fragment',
        ),
      );
      expect(result, 'fresh_fragment');
    });

    test('returns null when no token_hash is present anywhere', () {
      final result = ConfirmLinkDetector.detect(
        Uri.parse('https://app.icanbefitter.com/#/confirm'),
      );
      expect(result, isNull);
    });

    test('returns null for an unrelated URL', () {
      final result = ConfirmLinkDetector.detect(
        Uri.parse('https://app.icanbefitter.com/#/sign-in'),
      );
      expect(result, isNull);
    });

    test('an empty token_hash value does not match', () {
      final result = ConfirmLinkDetector.detect(
        Uri.parse('https://app.icanbefitter.com/?token_hash=&type=signup#/confirm'),
      );
      expect(result, isNull);
    });
  });
}
