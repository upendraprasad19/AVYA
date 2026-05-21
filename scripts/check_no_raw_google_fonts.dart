// scripts/check_no_raw_google_fonts.dart
//
// Gate 37 (Tech-debt audit 2026-05-20, finding C2 prep): assert that
// `GoogleFonts.getFont('DM Sans', ...)` is invoked only via
// `lib/core/theme/typography.dart` (the AppTypography SoT).
//
// The audit precedent: 188 ad-hoc `GoogleFonts.getFont('DM Sans', ...)`
// call sites scattered across 20 files. AppTypography exists as SoT but
// only 2 files use the canonical `AppTypography.body.copyWith(...)`.
// Defeats font caching + theme overrides + makes palette-swap a 188-site
// sweep.
//
// Allowed: lib/core/theme/typography.dart only.
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stdout.writeln('[Gate 37] SKIP: lib/ not present.');
    exit(0);
  }

  // Pattern: GoogleFonts.getFont('DM Sans' ... ) — any whitespace.
  final pattern = RegExp(r"""GoogleFonts\.getFont\(\s*['"]DM Sans['"]""");

  final violations = <String>[];
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normPath = entity.path.replaceAll('\\', '/');
    if (normPath.endsWith('lib/core/theme/typography.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
      if (pattern.hasMatch(line)) {
        violations.add('${entity.path}:${i + 1}');
      }
    }
  }

  final tag = warnOnly ? '[Gate 37 WARN]' : '[Gate 37]';
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: all DM Sans usage routes through AppTypography.');
    exit(0);
  }
  // B2 transitional — 188 known callsites. Always warn-only until codemod
  // lands later in B2 step 13.
  stderr.writeln('$tag WARN (B2-transitional): ${violations.length} direct GoogleFonts.getFont(\'DM Sans\'...) callsite(s):');
  for (final v in violations.take(10)) {
    stderr.writeln('  - $v');
  }
  if (violations.length > 10) stderr.writeln('  ... and ${violations.length - 10} more');
  stderr.writeln('');
  stderr.writeln('Fix: route through AppTypography.<scale>.copyWith(...) in lib/core/theme/typography.dart.');
  // Warn-only — flips to hard-fail after codemod in B2 step 13.
  exit(0);
}
