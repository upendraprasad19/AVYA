/// Shape check for the password-recovery code a user types from the email
/// Supabase sends (diagnose fa621a).
///
/// The code is the numeric `{{ .Token }}` GoTrue mints. Its LENGTH is the
/// hosted project's `mailer_otp_length` — a dashboard setting this client does
/// not own and cannot read. GoTrue clamps that setting to 6–10 (supabase/auth,
/// `internal/conf/configuration.go`, `ApplyDefaults`: a value outside 6–10
/// becomes 6) and zero-pads the code, so a code is all digits, may start with
/// 0, and is never shorter than 6. Supabase's own pages call the token
/// "6-digit"; the hosted project was nevertheless set to 8, and a client that
/// hard-coded 6 (c9e2b7) could not accept the code it had just been emailed.
///
/// The contract here is deliberately one-sided: a floor GoTrue itself enforces
/// and NO ceiling. Do not add an upper bound or a `maxLength` to the field that
/// uses this — a ceiling only catches over-long typos and turns any future
/// change of the hosted setting into a silent, total lockout again.
const int kRecoveryCodeMinLength = 6;

final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

/// Every character a user cannot SEE in the field and so cannot delete: the
/// Unicode separator (Z*), control (Cc) and format (Cf) categories. That is
/// ordinary and no-break spaces, the narrow no-break space some locales use to
/// group digits, newlines and tabs, the zero-width space / non-joiner / joiner,
/// the word joiner, bidi marks, the soft hyphen and the byte-order mark.
///
/// A category, not a hand-picked list: a list is exactly the guess that was
/// wrong here once already (fa621a). `\s` alone would miss every format
/// character in that list.
final RegExp _invisible = RegExp(r'[\p{Z}\p{Cc}\p{Cf}]', unicode: true);

/// [raw] with every invisible character removed ANYWHERE in it, not only at the
/// ends the way `trim()` works.
///
/// Copying a code out of a mail client or a chat app can drag any of these
/// along, and the user has no way to see or remove them: a trailing zero-width
/// space, or a code shown in two groups. Refusing such a paste with "Enter the
/// code from your email" is a dead end — it IS the code from the email. (The
/// old 6-character field only coped with a trailing one by accident: its
/// `maxLength` cut everything after the sixth character, for a 6-digit code.)
///
/// VISIBLE junk (letters, `-`, `+`, `.`) is deliberately left in place for
/// [isPlausibleRecoveryCode] to refuse: the user can see it and fix it.
String normalizeRecoveryCode(String raw) => raw.replaceAll(_invisible, '');

/// Whether [code] could be a recovery code GoTrue issued: ASCII digits only
/// and at least [kRecoveryCodeMinLength] long. The caller passes the text
/// through [normalizeRecoveryCode] first.
///
/// Rejects what `int.tryParse` used to wave through (`+12345`, `-123456`,
/// `0x1234`) because none of those can ever be issued.
bool isPlausibleRecoveryCode(String code) =>
    code.length >= kRecoveryCodeMinLength && _digitsOnly.hasMatch(code);
