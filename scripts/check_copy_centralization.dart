// scripts/check_copy_centralization.dart
//
// Gate (psych-skill-and-audit 2026-06-07, WS3) — WARN-ONLY diagnostic.
// User-facing copy should live in WardroomCopy (lib/core/copy/wardroom_copy.dart)
// so brand-voice edits are one-file changes. This gate counts inline
// `Text('<sentence>')` string literals in lib/features that are NOT sourced from
// WardroomCopy/AppConstants/a variable, establishing a baseline that should trend
// DOWN over time. It NEVER hard-fails (the long tail drains progressively) — it
// exists to make the drift visible and trackable (CLAUDE.md §4.11 warn-only tier).
//
// Always exits 0.

import 'dart:io';

void main(List<String> args) {
  final dir = Directory('lib/features');
  if (!dir.existsSync()) {
    stdout.writeln('[Gate copy] SKIP: lib/features not present.');
    exit(0);
  }
  // Text('<inner>') where <inner> is >= 8 chars; we then keep only sentence-like
  // literals (has a space, has a lowercase letter, no interpolation).
  final pattern = RegExp(r"Text\(\s*'([^']{8,})'");
  var count = 0;
  final perFile = <String, int>{};
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final norm = e.path.replaceAll('\\', '/');
    final content = e.readAsStringSync();
    for (final m in pattern.allMatches(content)) {
      final s = m.group(1)!;
      if (!s.contains(' ')) continue; // single tokens / labels — skip
      if (!RegExp(r'[a-z]').hasMatch(s)) continue; // ALL-CAPS eyebrows — skip
      if (s.contains(r'$')) continue; // interpolated — skip
      count++;
      perFile[norm] = (perFile[norm] ?? 0) + 1;
    }
  }
  stdout.writeln('[Gate copy] WARN-ONLY baseline: $count inline user-facing Text() sentence '
      'literal(s) in lib/features not sourced from WardroomCopy.');
  final top = perFile.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final t in top.take(8)) {
    stdout.writeln('  ${t.value.toString().padLeft(4)}  ${t.key}');
  }
  stdout.writeln('Trend this DOWN by moving copy into lib/core/copy/wardroom_copy.dart. (Non-blocking.)');
  exit(0);
}
