/// Title-cases a person's name for storage/display.
///
/// OBS-13 (2026-06-23): `textCapitalization.words` on the identity field is only
/// a mobile-keyboard hint — on web a lowercase-typed name ("test three") is
/// saved verbatim and greets the user as "Recruit test". `completeOnboarding`
/// routes `full_name` through this at the writer so the stored value is canonical.
///
/// Capitalizes the FIRST letter of each whitespace-separated word and leaves the
/// rest untouched (so "McDonald" / "O'Brien" survive). Collapses runs of
/// whitespace and trims. Empty / whitespace-only input → empty string.
String titleCaseName(String input) => input
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');
