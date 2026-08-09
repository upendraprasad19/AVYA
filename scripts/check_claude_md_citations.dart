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
// §N`. Each cite that names a section must resolve to a real `## N.` or
// `### N.M` heading.
//
// Exit 0 = pass: every citation resolves.
// Exit 1 = fail: any broken cite.
//
// ---------------------------------------------------------------------------
// CODE ZONE (OI-91, 2026-08-07)
// ---------------------------------------------------------------------------
// The markdown zone above never looked at `.dart` / `.ts` / `.sql` / `.sh`
// source comments, so 138 dead citations accumulated there while the gate
// reported PASS. This adds a second zone covering those files.
//
// It does NOT reuse the markdown zone's bare-section pattern. Measured on this
// repo at filing time: code files carry 526 bare section tokens, of which only
// 227 refer to this file — the other 299 cite OTHER documents (`Plan` 24,
// `DPDP` 24, `spec` 19, `DEVICE_TESTING.md`, various design docs). Scanning
// code with the bare pattern would therefore fail ~299 times on day one, and
// the statute allow-list would have to grow without bound. The code zone
// instead requires the citation be ANCHORED to this filename, using the same
// shape as OI-91's own survey grep so the gate's count reconciles with the
// board's.
//
// Both zones resolve against the ROOT file's headings, including citations
// written with a nested path prefix. That is not an approximation: no nested
// contract file defines numbered headings at all (all 14 use prose headings),
// so a numbered citation is always a root citation — a nested prefix on one is
// a mis-attribution, not a different target.
//
// Per §4.11 (gate before refactor), the code zone was developed report-only
// first — [_codeZoneEnforced] toggled `false` while the 138-citation baseline
// was measured and the sweep was written — then flipped to `true` before this
// commit landed, so it ships already enforcing in a single commit rather than
// as a separate follow-up. See [_codeZoneEnforced] for the current value.

import 'dart:io';

/// Whether code-zone findings BLOCK, or are reported without failing.
///
/// Currently `true`: the code zone is enforced. It was toggled `false` during
/// development (see the file header) so the 138-citation baseline could be
/// measured without every commit failing mid-sweep; that never shipped as its
/// own commit. §4.11 — the gate ships before the change it judges, which is
/// what makes the fix stay fixed rather than silently regrow.
const bool _codeZoneEnforced = true;

/// Directories whose source comments are scanned by the code zone.
const List<String> _codeRoots = [
  'lib',
  'test',
  'scripts',
  'supabase',
  'integration_test',
];

/// Extensions the code zone reads. Comment syntax is irrelevant — the anchored
/// pattern is specific enough that scanning whole lines is safe.
///
/// `.js` carries zero dead citations today (its one citation is live) and is
/// listed anyway: leaving it out would be a hole that only shows up the day
/// someone writes a dead citation into it.
const List<String> _codeExtensions = ['.dart', '.ts', '.js', '.sql', '.sh'];

/// Report paths with FORWARD slashes on every platform.
///
/// `File.path` yields OS-native separators, so this gate printed
/// `lib	hing.dart:1` on Windows and `lib/thing.dart:1` in CI. Two regression
/// tests asserting the forward-slash form therefore passed in CI and failed
/// locally — the local-vs-CI divergence class (feedback_local_ci_env_divergence).
/// A report string is a contract with its readers (tests, humans, greps); it
/// should not vary by the machine that produced it.
String _rel(String p) => p.replaceAll(r'\', '/');

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  // Build heading set for root CLAUDE.md only — nested files cite root §.
  final rootClaude = File('CLAUDE.md');
  if (!rootClaude.existsSync()) {
    stderr.writeln('[Gate 26] FAIL: CLAUDE.md not found at repo root');
    exit(warnOnly ? 0 : 1);
  }
  final rootLines = rootClaude.readAsLinesSync();
  // Headings: lines like "## N. Title", "### N.M Title", or "## Na. Title"
  // (single-letter-suffixed sections, e.g. root CLAUDE.md's "## 2a.").
  final headingRegex = RegExp(r'^#{2,3}\s+(\d+[a-z]?(?:\.\d+)?)\.?\s');
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

  // Citation pattern: §N, §N.M, or §Na (allow trailing punctuation/text).
  // The letter suffix MUST be captured here too, not just in headingRegex --
  // otherwise `§2a` truncates to captured group "2", which coincidentally
  // collides with an unrelated real section "2" instead of being validated
  // as "2a" specifically (repo-gate-pattern-sweep Unit 2, 2026-08-03).
  final citeRegex = RegExp(r'§(\d+[a-z]?(?:\.\d+)?)');

  // External-statute pattern: skip `§N` when preceded on the same line by a
  // statute/act token (e.g., `DPDP §17` refers to India's DPDP Act §17, not
  // to a section of this file). Add new statutes as the codebase cites them.
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
        broken.add('${_rel(file.path)}:${i + 1} → §$sec (not in CLAUDE.md known sections: ${knownSections.toList()..sort()})');
      }
    }
  }

  // --- Code zone: anchored citations in source comments (OI-91) ------------
  //
  // Anchored deliberately: see the header note on the 299 non-root section
  // tokens a bare pattern would swallow. The `.{0,3}` window is the same one
  // OI-91's survey grep used, so this gate's count reconciles with the board's.
  final anchoredCiteRegex =
      RegExp(r'CLAUDE\.md.{0,3}§(\d+[a-z]?(?:\.\d+)?)');

  final codeFiles = <File>[];
  for (final root in _codeRoots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (_codeExtensions.any((e) => entity.path.endsWith(e))) {
        codeFiles.add(entity);
      }
    }
  }

  final brokenInCode = <String>[];
  for (final file in codeFiles) {
    final List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } on FormatException {
      // Non-UTF8 blob — nothing citable in it, but say so: a PASS that
      // silently skipped a file it couldn't read is a false confidence, the
      // exact class this gate exists to catch in others.
      stdout.writeln('[Gate 26] NOTE: skipped non-UTF8 file ${file.path}');
      continue;
    }
    for (var i = 0; i < lines.length; i++) {
      for (final m in anchoredCiteRegex.allMatches(lines[i])) {
        final sec = m.group(1)!;
        if (knownSections.contains(sec)) continue;
        brokenInCode.add('${_rel(file.path)}:${i + 1} → §$sec');
      }
    }
  }

  if (_codeZoneEnforced) {
    broken.addAll(brokenInCode);
  } else if (brokenInCode.isNotEmpty) {
    stdout.writeln(
        '[Gate 26 CODE-ZONE report-only] ${brokenInCode.length} dead citation(s) '
        'in ${codeFiles.length} source files (OI-91 sweep in flight; flips to '
        'blocking when _codeZoneEnforced is true):');
    for (final b in brokenInCode.take(10)) {
      stdout.writeln('  - $b');
    }
    if (brokenInCode.length > 10) {
      stdout.writeln('  ... and ${brokenInCode.length - 10} more');
    }
  }

  final tag = warnOnly ? '[Gate 26 WARN]' : '[Gate 26]';
  if (broken.isEmpty) {
    stdout.writeln('$tag PASS: all §N citations resolve across ${files.length} CLAUDE.md / AGENTS.md files'
        '${_codeZoneEnforced ? ' and ${codeFiles.length} source files' : ''}.');
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
