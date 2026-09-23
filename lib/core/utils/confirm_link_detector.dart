/// Pure detection of a signup-confirmation link's `token_hash` from a [Uri].
///
/// Extracted from `main.dart` so it can be exercised with constructed [Uri]s
/// in tests — `Uri.base` is a static browser global and can't be mocked —
/// same reasoning as the sibling `PasswordRecoveryDetector`.
///
/// Live-verified 2026-09-23 (diagnose f92d17, `curl -D-` against
/// `https://app.icanbefitter.com/confirm?token_hash=X&type=signup`):
/// `vercel.json`'s `/confirm` redirect rule (`destination: "/#/confirm"`)
/// issues `Location: /?token_hash=X&type=signup#/confirm` — Vercel appends
/// the forwarded query string BEFORE the literal `#/confirm`, not inside
/// it. The browser follows that to a URL whose `location.search` carries
/// `token_hash` but whose `location.hash` is bare `#/confirm` with NO
/// query. Flutter web's default HashUrlStrategy (no `setUrlStrategy`
/// anywhere in this app) means GoRouter — and therefore
/// `state.uri.queryParameters` in `app_router.dart`'s `/confirm` route —
/// only ever reads `location.hash`, so `token_hash` is invisible to it even
/// though it's present, one URL component over, in `location.search`. This
/// reproduced on every real device tested (iPhone Safari via a Gmail tap;
/// confirmed independently by direct `curl`), so it's a genuine server-side
/// routing defect, not a client/device quirk. [detect] reads BOTH possible
/// locations so it works regardless of whether a future Vercel config
/// change ever fixes the redirect shape.
class ConfirmLinkDetector {
  ConfirmLinkDetector._();

  static String? detect(Uri uri) {
    // Correct shape, if the hash route ever carries its own query string
    // directly (e.g. `#/confirm?token_hash=X&type=signup`).
    final fragment = uri.fragment;
    final queryStart = fragment.indexOf('?');
    if (queryStart != -1) {
      final fromFragment =
          Uri.splitQueryString(fragment.substring(queryStart + 1))['token_hash'];
      if (fromFragment != null && fromFragment.isNotEmpty) return fromFragment;
    }

    // The actual live shape (see class doc): token_hash landed in the
    // document's own query string, one component before the `#`.
    final fromQuery = uri.queryParameters['token_hash'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

    return null;
  }
}
