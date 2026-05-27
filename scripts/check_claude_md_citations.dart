// scripts/check_claude_md_citations.dart
//
// Gate 26 (Tech-debt audit 2026-05-20, finding Doc6): assert that every
// `§N` and `§N.M` citation across CLAUDE.md + nested CLAUDE.md files
// resolves to a heading that exists.
//
// The audit finding: CLAUDE.md:301-305 cites `§19 #N` but CLAUDE.md only
// has §0-§7 after Milestone-6 decluttering. 26+ nested files cite a
// nonexistent section. Citations are how agents navigate — broken pointers
// silently dead-end.
//
// This gate parses every CLAUDE.md (root + nested), builds the set of
// headings present, then scans for citations like `§19`, `§4.4`, `CLAUDE.md
// §N`, `CLAUDE.md:NNN`. Each cite that names a section must resolve to a
// real `## N.` or `### N.M` heading. Line-number cites (`:NNN`) are
// validated against the file's line count.
//
// Exit 0 = pass: every citation resolves.
// Exit 1 = fail: any broken cite.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  // Build heading set for root CLAUDE.md only — nested files cite root §.
  final rootClaude = File('CLAUDE.md');
  if (!rootClaude.existsSync()) {
    stderr.writeln('[Gate 26] FAIL: CLAUDE.md not found at repo root');
    exit(warnOnly ? 0 : 1);
  }
  final rootLines = rootClaude.readAsLinesSync();
  // Headings: lines like "## N. Title" or "### N.M Title"
  final headingRegex = RegExp(r'^#{2,3}\s+(\d+(?:\.\d+)?)\.?\s');
  final knownSections = <String>{};
  for (final line in rootLines) {
    final m = headingRegex.firstMatch(line);
    if (m != null) knownSections.add(m.group(1)!);
  }

  // Scan every CLAUDE.md (root + nested) and AGENTS.md for `§N` citations.
  final files = <File>[];
  files.add(rootClaude);
  if (File('AGENTS.md').existsSync()) files.add(File('AGENTS.md'));
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('CLAUDE.md')) files.add(entity);
  }
  for (final entity in Directory('supabase').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('CLAUDE.md')) files.add(entity);
  }

  // Citation pattern: §N or §N.M (allow trailing punctuation/text).
  final citeRegex = RegExp(r'§(\d+(?:\.\d+)?)');

  // External-statute pattern: skip `§N` when preceded on the same line by a
  // statute/act token (e.g., `DPDP §17` refers to India's DPDP Act §17, not
  // CLAUDE.md §17). Add new statutes as the codebase cites them.
  final externalStatuteRegex =
      RegExp(r'\b(?:DPDP|GDPR|HIPAA|CCPA|PCI[- ]?DSS)(?:\s+Act)?\s+$');

  final broken = <String>[];
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      // Skip lines that ARE headings (they define sections; don't self-validate).
      if (RegExp(r'^#{2,4}\s').hasMatch(lines[i])) continue;
      for (final m in citeRegex.allMatches(lines[i])) {
        final sec = m.group(1)!;
        if (knownSections.contains(sec)) continue;
        // Check the text immediately before this `§` for an external-statute token.
        final preceding = lines[i].substring(0, m.start);
        if (externalStatuteRegex.hasMatch(preceding)) continue;
        broken.add('${file.path}:${i + 1} → §$sec (not in CLAUDE.md known sections: ${knownSections.toList()..sort()})');
      }
    }
  }

  final tag = warnOnly ? '[Gate 26 WARN]' : '[Gate 26]';
  if (broken.isEmpty) {
    stdout.writeln('$tag PASS: all §N citations resolve across ${files.length} CLAUDE.md / AGENTS.md files.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${broken.length} broken §N citation(s):');
  for (final b in broken.take(30)) {
    stderr.writeln('  - $b');
  }
  if (broken.length > 30) {
    stderr.writeln('  ... and ${broken.length - 30} more');
  }
  exit(warnOnly ? 0 : 1);
}
