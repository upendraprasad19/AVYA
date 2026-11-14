/// Pure detection of a password-recovery deep link from a [Uri].
///
/// Extracted from `main.dart` so it can be exercised with constructed [Uri]s
/// in tests — `Uri.base` is a static browser global and can't be mocked.
///
/// Supabase sends two different recovery-link shapes depending on the auth
/// flow type:
/// - **Implicit flow** (legacy): tokens in the URL fragment,
///   `#access_token=...&refresh_token=...&type=recovery`.
/// - **PKCE flow** (supabase_flutter's default since 2.x): just an
///   authorization code in the query string, `?code=<uuid>`, on whatever
///   path `redirectTo` pointed at. `detectSessionInUrl` (default true on
///   web) already exchanges this code for a session during
///   `Supabase.initialize()` — this detector only needs to recognize the
///   shape so routing can send the user to `/reset` instead of falling
///   through to the normal authenticated-user flow.
class PasswordRecoveryResult {
  const PasswordRecoveryResult({
    required this.isRecovery,
    this.accessToken,
    this.refreshToken,
  });

  final bool isRecovery;
  final String? accessToken;
  final String? refreshToken;
}

class PasswordRecoveryDetector {
  PasswordRecoveryDetector._();

  /// The path `forgot_password_sheet.dart`'s `redirectTo` points at. Scoping
  /// the PKCE `code` check to this exact path avoids misclassifying some
  /// other PKCE flow (e.g. OAuth sign-in) as a password reset.
  static const String resetPath = '/reset';

  static PasswordRecoveryResult detect(Uri uri) {
    final fragment = uri.fragment;
    if (fragment.contains('type=recovery')) {
      final params = Uri.splitQueryString(fragment);
      return PasswordRecoveryResult(
        isRecovery: true,
        accessToken: params['access_token'],
        refreshToken: params['refresh_token'],
      );
    }

    if (uri.path == resetPath && uri.queryParameters.containsKey('code')) {
      return const PasswordRecoveryResult(isRecovery: true);
    }

    return const PasswordRecoveryResult(isRecovery: false);
  }
}
