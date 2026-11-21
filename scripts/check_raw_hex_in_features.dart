// scripts/check_raw_hex_in_features.dart
//
// Gate (psych-skill-and-audit 2026-06-07, WS3 "gated full sweep"):
// Ban raw `Color(0x......)` hex literals under lib/features/**. Palette colours
// MUST come from `AppColors` (lib/core/theme/colors.dart — the Wardroom SoT) so a
// palette change is a one-file edit, not a feature-wide sweep. Mirrors the
// precedent set by check_no_raw_google_fonts.dart (typography SoT).
//
// §4.11 gates-before-refactor: ships with a transitional ALLOWLIST of the files
// that already contain violations on 2026-06-07. The gate HARD-FAILS on any NEW
// raw-hex literal in a non-allowlisted feature file immediately, and WARNs on the
// allowlisted baseline. As each baseline file is remediated to AppColors, remove
// it from ALLOWLIST. When ALLOWLIST is empty the gate is fully hard-fail.
//
// Exit 0 = pass (no new violations). Exit 1 = a non-allowlisted violation.

import 'dart:io';

// Transitional baseline DRAINED 2026-06-07 (in-sync sweep): all 9 files
// remediated to AppColors tokens. Gate is now fully hard-fail — any raw
// Color(0x..) literal under lib/features/** fails the build.
const allowlist = <String>{};

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final dir = Directory('lib/features');
  if (!dir.existsSync()) {
    stdout.writeln('[Gate raw-hex] SKIP: lib/features not present.');
    exit(0);
  }
  final pattern = RegExp(r'Color\(\s*(?:const\s+)?0x[0-9A-Fa-f]{6,8}');
  final newViolations = <String>[];
  final baselineHits = <String>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final norm = e.path.replaceAll('\\', '/');
    final content = e.readAsStringSync();
    final matches = pattern.allMatches(content);
    if (matches.isEmpty) continue;
    final allowlisted = allowlist.contains(norm);
    for (final m in matches) {
      final lineNum = content.substring(0, m.start).split('\n').length;
      final loc = '$norm:$lineNum';
      if (allowlisted) {
        baselineHits.add(loc);
      } else {
        newViolations.add(loc);
      }
    }
  }
  if (baselineHits.isNotEmpty) {
    stdout.writeln('[Gate raw-hex] WARN: ${baselineHits.length} baseline raw-hex literal(s) in '
        '${allowlist.length} allowlisted file(s) pending migration to AppColors.');
  }
  if (newViolations.isEmpty) {
    stdout.writeln('[Gate raw-hex] PASS: no NEW raw Color(0x..) literals in lib/features.');
    exit(0);
  }
  final tag = warnOnly ? '[Gate raw-hex WARN]' : '[Gate raw-hex FAIL]';
  stderr.writeln('$tag: ${newViolations.length} raw-hex literal(s) outside the allowlist:');
  for (final v in newViolations.take(15)) {
    stderr.writeln('  - $v');
  }
  if (newViolations.length > 15) {
    stderr.writeln('  ... and ${newViolations.length - 15} more');
  }
  stderr.writeln('');
  stderr.writeln('Fix: use an AppColors token (lib/core/theme/colors.dart). '
      'Add a new token there if the colour is genuinely new.');
  exit(warnOnly ? 0 : 1);
}
