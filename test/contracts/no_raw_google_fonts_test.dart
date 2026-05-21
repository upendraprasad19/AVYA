// Regression test for tech-debt audit 2026-05-20, finding C2:
// typography codemod.
//
// Before C2: 188 ad-hoc `GoogleFonts.getFont('DM Sans', ...)` callsites
// inlined across feature code (defeats font caching, theme overrides,
// palette-swap). AppTypography existed as SoT but only ~2 files used it.
//
// After C2 (2026-05-21, `feat/tech-debt-audit-resume-4`):
// - All DM Sans usage routed through `AppTypography.<scale>` /
//   `AppTypography.dmSansFamily()`.
// - Gate 37 (`scripts/check_no_raw_google_fonts.dart`) flipped to
//   hard-fail (exit 1 on any direct `GoogleFonts.getFont('DM Sans'...)`
//   outside `lib/core/theme/typography.dart`).
//
// This contract test invokes the gate and asserts exit 0. If the gate
// ever regresses (a new feature inlines `GoogleFonts.getFont('DM Sans'`),
// this test fails BEFORE the pre-commit hook would.
//
// closes-diagnose: 2026-05-21-typography-codemod-C2

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gate 37 — no raw GoogleFonts.getFont(\'DM Sans\') outside typography.dart',
      () {
    // Windows requires `runInShell: true` (or `dart.bat`) because the
    // bare `dart` token is resolved by cmd.exe via PATHEXT, not directly
    // by CreateProcessW.
    final result = Process.runSync(
      'dart',
      ['run', 'scripts/check_no_raw_google_fonts.dart'],
      workingDirectory: Directory.current.path,
      runInShell: true,
    );
    final out = (result.stdout as String) + (result.stderr as String);
    expect(result.exitCode, 0,
        reason:
            'Gate 37 must exit 0 (zero direct GoogleFonts.getFont(\'DM Sans\'...) '
            'callsites outside lib/core/theme/typography.dart). Use '
            'AppTypography.<scale>.copyWith(...) instead.\n\nGate output:\n$out');
  });
}
