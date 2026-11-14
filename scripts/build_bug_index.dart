// scripts/build_bug_index.dart
//
// Builds docs/diagnoses/INDEX.md by scanning every docs/diagnoses/*.md
// for YAML frontmatter and emitting a multi-cut index:
//   - By recurrence class (cited feedback_*.md memory file)
//   - By concept (sot_registry_entry)
//   - By feature directory (derived from writers/readers file paths)
//   - Chronological
//
// A2 (merge-conflict-treadmill): the output is a LOCAL BUILD PRODUCT. It is gitignored and
// untracked, line 1 is the stamp from local_indexes_lib.dart, and the write is atomic.
//
// Usage: dart run scripts/build_bug_index.dart [--lenient]
// Exit codes: 0 = written, 1 = a doc failed validation (nothing written; `--lenient` skips
// the bad docs, says so, and writes the rest), 3 = validation passed but the write failed.

import 'dart:io';

import 'bug_index_lib.dart';
import 'local_indexes_lib.dart';

void main(List<String> args) {
  exit(runBugIndex(Directory.current.path, strict: !args.contains('--lenient')));
}

/// Builds the diagnose index under [root]. Returns the exit code (see the header).
///
/// Every `exit(1)` of the old script is a `return 1` here, so the orchestrator
/// (build_local_indexes.dart) can run both builders and report the worst code.
int runBugIndex(String root, {bool strict = true}) {
  final dir = Directory('$root/$kBugDocsDir');
  if (!dir.existsSync()) {
    stderr.writeln('$kBugDocsDir directory not found');
    return 1;
  }

  // The stats are captured BEFORE any doc is read (local_indexes_lib.dart, R5D-8). An unreadable
  // directory (a permission bit, a share that went away) is a reported failure in both modes:
  // there is no index to build from a directory that cannot be listed.
  final String digest;
  final List<String> names;
  try {
    digest = statDigest(root, indexInputPaths(root, kBugIndexSpec));
    names = diagnoseDocNames(root);
  } catch (e) {
    stderr.writeln('$kBugDocsDir: cannot list the diagnose docs ($e)');
    return 1;
  }

  final docs = <DiagnoseDocInput>[];
  final unreadable = <String>[];
  for (final name in names) {
    try {
      docs.add(DiagnoseDocInput(
          name, File('$root/$kBugDocsDir/$name').readAsStringSync()));
    } catch (e) {
      unreadable.add('$kBugDocsDir/$name: unreadable ($e)');
    }
  }
  final v = validateDiagnoseDocs(docs, dir: kBugDocsDir);
  final problems = [...unreadable, ...v.problems];

  // SELF-CHECK: refuse to emit an index that would lose a doc or carry an empty symptom.
  //
  // `docs/diagnoses/INDEX.md` sat 237-of-344 empty for months because nothing
  // ever asserted its OUTPUT was meaningful — the generator exited 0 while
  // writing `— >` for every doc that used a YAML block scalar, and 8 older docs
  // carried their symptom only as a `## Symptom` markdown section. CLAUDE.md
  // §4.1.5 makes grepping this index the mandatory first step before any
  // root-cause hypothesis, so a blank symptom is a silent hole in the discipline.
  // Failing here is what stops it regrowing. The rules live in the pure
  // validateDiagnoseDocs (bug_index_lib.dart).
  if (problems.isNotEmpty) {
    if (strict) {
      stderr.writeln('FAIL: ${problems.length} diagnose-doc(s) cannot be indexed.');
      stderr.writeln(
          'Fix the frontmatter (a bare `date: YYYY-MM-DD`, a `symptom:` — a folded `>-` '
          'block is fine — and a `bug_id:` equal to the 6-character file-name suffix), or '
          'run `dart run scripts/build_local_indexes.dart --lenient` to build without them.');
      for (final p in problems) {
        stderr.writeln('  $p');
      }
      return 1;
    }
    stderr.writeln('[BUG-INDEX] WARNING (lenient): ${problems.length} diagnose-doc(s) '
        'SKIPPED, so they are absent from the index below:');
    for (final p in problems) {
      stderr.writeln('  $p');
    }
  }

  final entries = v.entries;

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

  final rc = writeLocalIndex(
      root, kBugIndexPath, stampedOutput(digest, renderBugIndex(entries)));
  if (rc == 0) {
    stdout.writeln('INDEX.md regenerated: ${entries.length} bugs indexed.');
  }
  return rc;
}

/// The index body for [entries] (already validated and sorted newest first). Pure.
String renderBugIndex(List<Map<String, dynamic>> entries) {
  final buf = StringBuffer();
  buf.writeln('# Bug Directory (auto-generated)');
  buf.writeln('');
  // f4d1b7: NO wall-clock `Generated:` timestamp — it made the regenerated
  // INDEX differ on every run, shifting the staged-diff hash the catastrophic
  // review gate keys on (and producing noisy no-op diffs). The content is a
  // pure function of the inputs; the stamp in line 1 is a digest of their stats.
  buf.writeln('Re-run: `dart run scripts/build_local_indexes.dart --lenient`');
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
  return buf.toString();
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
