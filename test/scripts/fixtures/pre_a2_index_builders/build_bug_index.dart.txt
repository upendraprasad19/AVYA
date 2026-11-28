// scripts/build_bug_index.dart
//
// Builds docs/diagnoses/INDEX.md by scanning every docs/diagnoses/*.md
// for YAML frontmatter and emitting a multi-cut index:
//   - By recurrence class (cited feedback_*.md memory file)
//   - By concept (sot_registry_entry)
//   - By feature directory (derived from writers/readers file paths)
//   - Chronological
//
// Usage: dart run scripts/build_bug_index.dart
// Exit codes: 0 = success, 1 = parse error.

import 'dart:io';

import 'bug_index_lib.dart';

void main() {
  final dir = Directory('docs/diagnoses');
  if (!dir.existsSync()) {
    stderr.writeln('docs/diagnoses directory not found');
    exit(1);
  }

  final entries = <Map<String, dynamic>>[];
  for (final file in dir.listSync()) {
    if (file is! File) continue;
    if (!file.path.endsWith('.md')) continue;
    if (file.path.endsWith('INDEX.md')) continue;
    final content = file.readAsStringSync();
    final fm = parseFrontmatter(content);
    if (fm == null) {
      stderr.writeln('Warning: ${file.path} has no parseable frontmatter');
      continue;
    }
    fm['_path'] = file.path;
    entries.add(fm);
  }

  // SELF-CHECK: refuse to emit an index whose entries carry no usable symptom.
  //
  // `docs/diagnoses/INDEX.md` sat 237-of-344 empty for months because nothing
  // ever asserted its OUTPUT was meaningful — the generator exited 0 while
  // writing `— >` for every doc that used a YAML block scalar, and 8 older docs
  // carried their symptom only as a `## Symptom` markdown section. CLAUDE.md
  // §4.1.5 makes grepping this index the mandatory first step before any
  // root-cause hypothesis, so a blank symptom is a silent hole in the discipline.
  // Failing here is what stops it regrowing.
  final bad = <String>[];
  for (final e in entries) {
    final s = summarize(e['symptom']);
    if (s.isEmpty || blockScalarRe.hasMatch(s)) {
      bad.add('  ${e['_path']} (bug_id: ${e['bug_id'] ?? '<none>'}) -> "$s"');
    }
  }
  if (bad.isNotEmpty) {
    stderr.writeln(
        'FAIL: ${bad.length} diagnose-doc(s) would index with an empty or '
        'placeholder symptom.');
    stderr.writeln(
        'Add a `symptom:` frontmatter field (a folded `>-` block is fine — it '
        'is now parsed correctly).');
    for (final b in bad) {
      stderr.writeln(b);
    }
    exit(1);
  }

  // Sort chronologically (latest first by `date`), tiebreak by `_path` for a
  // STABLE TOTAL ORDER. `dir.listSync()` is filesystem-ordered and Dart's
  // List.sort is not guaranteed stable, so two diagnose-docs sharing a date
  // could swap on re-run and shift the regenerated INDEX — which shifts the
  // staged-diff hash the catastrophic review gate keys on. f4d1b7.
  entries.sort((a, b) {
    final byDate = (b['date'] as String).compareTo(a['date'] as String);
    if (byDate != 0) return byDate;
    return (a['_path'] as String).compareTo(b['_path'] as String);
  });

  final buf = StringBuffer();
  buf.writeln('# Bug Directory (auto-generated)');
  buf.writeln('');
  // f4d1b7: NO wall-clock `Generated:` timestamp — it made the regenerated
  // INDEX differ on every run, shifting the staged-diff hash the catastrophic
  // review gate keys on (and producing noisy no-op diffs). Git history records
  // when the INDEX changed; the content is now a pure function of the inputs.
  buf.writeln('Re-run: `dart run scripts/build_bug_index.dart`');
  buf.writeln('');

  // By recurrence class
  buf.writeln('## By recurrence class');
  buf.writeln('');
  final byClass = <String, List<Map<String, dynamic>>>{};
  for (final e in entries) {
    final rec = e['recurrence'];
    if (rec is Map && rec['class'] is String) {
      final cls = rec['class'] as String;
      byClass.putIfAbsent(cls, () => []).add(e);
    }
  }
  for (final cls in byClass.keys) {
    buf.writeln('### $cls (${byClass[cls]!.length} instances)');
    for (final e in byClass[cls]!) {
      buf.writeln('- ${e['date']} ${e['bug_id']} — ${summarize(e['symptom'], fallback: '(no symptom)')} — ${e['contract_test_path'] ?? '(no test)'}');
    }
    buf.writeln('');
  }

  // By concept
  buf.writeln('## By concept');
  buf.writeln('');
  final byConcept = <String, List<Map<String, dynamic>>>{};
  for (final e in entries) {
    final c = e['concept'] as String? ?? '(unspecified)';
    byConcept.putIfAbsent(c, () => []).add(e);
  }
  for (final c in byConcept.keys) {
    buf.writeln('### $c (${byConcept[c]!.length} bugs)');
    for (final e in byConcept[c]!) {
      buf.writeln('- ${e['date']} ${e['bug_id']} — ${summarize(e['symptom'])}');
    }
    buf.writeln('');
  }

  // By feature directory (heuristic from `writers:` field)
  buf.writeln('## By feature directory');
  buf.writeln('');
  final byDir = <String, List<Map<String, dynamic>>>{};
  for (final e in entries) {
    final writers = e['writers'];
    if (writers is! List) continue;
    for (final w in writers) {
      if (w is! Map) continue;
      final f = w['file'] as String?;
      if (f == null) continue;
      final dir = _featureDir(f);
      if (dir == null) continue;
      byDir.putIfAbsent(dir, () => []).add(e);
    }
  }
  for (final dir in byDir.keys) {
    final unique = byDir[dir]!.toSet().toList();
    buf.writeln('### $dir (${unique.length} bugs)');
    for (final e in unique) {
      buf.writeln('- ${e['date']} ${e['bug_id']} — ${summarize(e['symptom'])}');
    }
    buf.writeln('');
  }

  // Chronological table
  buf.writeln('## Chronological (latest first)');
  buf.writeln('');
  buf.writeln('| Date | Bug ID | Symptom | Concept | Test path |');
  buf.writeln('|---|---|---|---|---|');
  for (final e in entries) {
    buf.writeln('| ${e['date']} | ${e['bug_id']} | ${summarize(e['symptom']).replaceAll('|', '\\|')} | ${e['concept'] ?? ''} | ${e['contract_test_path'] ?? ''} |');
  }

  File('docs/diagnoses/INDEX.md').writeAsStringSync(buf.toString());
  stdout.writeln('INDEX.md regenerated: ${entries.length} bugs indexed.');
}


String? _featureDir(String path) {
  if (path.startsWith('lib/features/')) {
    final parts = path.split('/');
    if (parts.length >= 3) return 'lib/features/${parts[2]}';
  }
  if (path.startsWith('lib/core/services/')) return 'lib/core/services';
  if (path.startsWith('lib/shared/')) return 'lib/shared';
  if (path.startsWith('supabase/functions/')) return 'supabase/functions';
  if (path.startsWith('supabase/migrations/')) return 'supabase/migrations';
  return null;
}
