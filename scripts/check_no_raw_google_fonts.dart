// scripts/check_no_raw_google_fonts.dart
//
// Gate: 37
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
  // Hard-fail mode (audit 2026-05-21, finding C2 codemod landed). All 175
  // multi-line callsites rewritten to AppTypography.<scale>.copyWith(...).
  // Use `--warn-only` for diagnostic sweeps only.
  final warnOnly = args.contains('--warn-only');
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stdout.writeln('[Gate 37] SKIP: lib/ not present.');
    exit(0);
  }

  // Pattern: GoogleFonts.getFont('DM Sans' ... ) — multi-line aware.
  // The `\s+` between `(` and `'DM Sans'` matches whitespace INCLUDING
  // newlines (Dart RegExp `.` doesn't cross lines by default but `\s` does).
  // Fixed in audit 2026-05-21: previous single-line regex false-passed
  // multi-line calls (per feedback_source_grep_false_confidence.md).
  //
  final pattern = RegExp(
    r"""GoogleFonts\.getFont\(\s*['"]DM Sans['"]""",
    multiLine: true,
    dotAll: true,
  );

  final violations = <String>[];
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normPath = entity.path.replaceAll('\\', '/');
    if (normPath.endsWith('lib/core/theme/typography.dart')) continue;
    // Scan whole-file content so multi-line `GoogleFonts.getFont(\n 'DM Sans',`
    // calls are caught.
    final content = entity.readAsStringSync();
    for (final m in pattern.allMatches(content)) {
      // Compute line number from match offset.
      final prefix = content.substring(0, m.start);
      final lineNum = prefix.split('\n').length;
      violations.add('${entity.path}:$lineNum');
    }
  }

  final tag = warnOnly ? '[Gate 37 WARN]' : '[Gate 37]';
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: all DM Sans usage routes through AppTypography.');
    exit(0);
  }
  // Tech-debt audit 2026-05-20 finding C2: codemod landed 2026-05-21
  // (`feat/tech-debt-audit-resume-4`). Gate now hard-fails. Use the
  // `--warn-only` flag for transitional sweeps only.
  final levelTag = warnOnly ? '$tag WARN' : '$tag FAIL';
  stderr.writeln('$levelTag: ${violations.length} direct GoogleFonts.getFont(\'DM Sans\'...) callsite(s):');
  for (final v in violations.take(10)) {
    stderr.writeln('  - $v');
  }
  if (violations.length > 10) stderr.writeln('  ... and ${violations.length - 10} more');
  stderr.writeln('');
  stderr.writeln('Fix: route through AppTypography.<scale>.copyWith(...) in lib/core/theme/typography.dart.');
  exit(warnOnly ? 0 : 1);
}
