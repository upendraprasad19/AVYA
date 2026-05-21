// scripts/check_diagnose_index_fresh.dart
//
// Gate 25 (Tech-debt audit 2026-05-20, finding Doc2): assert that
// `docs/diagnoses/INDEX.md` enumerates every diagnose-doc on disk.
//
// The audit finding: INDEX.md last regenerated 2026-05-18; 152 diagnose-doc
// files on disk but only ~40 referenced in the index. Bug-history lookup
// (CLAUDE.md §4.1.5) was grepping a stale snapshot — first-instance claims
// could be falsely codified.
//
// Pre-commit hook in scripts/pre-commit.sh:33-38 already regenerates +
// `git add`s INDEX.md when a docs/diagnoses/*.md changes — but somehow
// the add didn't survive. Likely root cause: `--no-verify` reflex or
// commit-amend losing the staged file. This gate catches it after the fact.
//
// Exit 0 = pass: every docs/diagnoses/<date>-*.md (excluding INDEX.md and
//                README.md) appears in INDEX.md by filename.
// Exit 1 = fail: any diagnose-doc missing from index.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final indexFile = File('docs/diagnoses/INDEX.md');
  if (!indexFile.existsSync()) {
    stderr.writeln('[Gate 25] FAIL: docs/diagnoses/INDEX.md not found');
    exit(warnOnly ? 0 : 1);
  }
  final indexContent = indexFile.readAsStringSync();

  final dir = Directory('docs/diagnoses');
  final docs = dir
      .listSync()
      .whereType<File>()
      .map((f) => f.path.split(RegExp(r'[\\/]')).last)
      .where((n) => n.endsWith('.md'))
      .where((n) => n != 'INDEX.md' && n != 'README.md' && n != 'TEMPLATE.md')
      .toList();

  // The INDEX uses short bug IDs (the trailing hash in the filename), not the
  // full filename. Extract the bug ID from filenames like
  // `2026-05-04-restore-completeness-pull-239999.md` → `239999`.
  final idPattern = RegExp(r'-([a-zA-Z0-9]{6})\.md$');
  final missing = <String>[];
  for (final doc in docs) {
    final m = idPattern.firstMatch(doc);
    if (m == null) {
      // Filename doesn't follow convention. Fall back to full-name match.
      if (!indexContent.contains(doc.replaceAll('.md', ''))) {
        missing.add('$doc (filename does not end in -<6char-id>.md)');
      }
      continue;
    }
    final bugId = m.group(1)!;
    if (!indexContent.contains(bugId)) {
      missing.add('$doc (bug ID $bugId absent from INDEX.md)');
    }
  }

  final tag = warnOnly ? '[Gate 25 WARN]' : '[Gate 25]';
  if (missing.isEmpty) {
    stdout.writeln('$tag PASS: all ${docs.length} diagnose-docs indexed.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${missing.length} of ${docs.length} diagnose-docs missing from INDEX.md:');
  for (final m in missing.take(20)) {
    stderr.writeln('  - $m');
  }
  if (missing.length > 20) {
    stderr.writeln('  ... and ${missing.length - 20} more');
  }
  stderr.writeln('');
  stderr.writeln('Fix: run `dart run scripts/build_bug_index.dart` then `git add docs/diagnoses/INDEX.md`.');
  exit(warnOnly ? 0 : 1);
}
