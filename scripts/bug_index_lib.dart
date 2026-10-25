// scripts/bug_index_lib.dart
//
// Pure helpers for scripts/build_bug_index.dart, split out so they are
// unit-testable (test/contracts/bug_index_frontmatter_test.dart). Same reason
// plan_review_record_lib.dart exists: a decision that gates discipline should
// be exercisable without spawning the whole generator.
//
// THE BUG THESE EXIST TO PREVENT. `docs/diagnoses/INDEX.md` carried no symptom
// text for 237 of its 344 entries. The generator did
// `symptom?.toString().split('\n').first`, which on a YAML block scalar
// (`symptom: >`) returns the bare INDICATOR — the folded body sits on the
// following lines and was never read. CLAUDE.md §4.1.5 makes grepping that
// index the mandatory first step before any root-cause hypothesis, so 70% of
// bug history was unsearchable by symptom while the file looked populated.

/// A YAML block-scalar indicator: `|`, `|-`, `|+`, `>`, `>-`, `>+`, and the
/// explicit-indentation forms `|2`, `>2-`, `|-2` …
///
/// The digit forms were missing from the first draft: `symptom: |2` parsed as
/// the literal two-character string `"|2"`, which the self-check accepted as a
/// perfectly good symptom because it is neither empty nor a *bare* indicator.
/// That is the same "looked populated but wasn't" failure this file exists to
/// kill, wearing a slightly different hat.
final blockScalarRe = RegExp(r'^[|>](?:[-+]?\d*|\d*[-+]?)$');

/// One-line, greppable summary of a possibly multi-paragraph field.
///
/// `.split('\n').first` is wrong twice over: on an unfolded block scalar it
/// yields the indicator, and on a correctly folded one it yields only the FIRST
/// PARAGRAPH — which for `2026-05-15-sync-null-key-guard-9f4ab2.md` is
/// "Hypothetical (defence-in-depth) — no production occurrence yet." and drops
/// the entire data-loss description. Flatten instead, then cap.
String summarize(Object? value, {String fallback = '', int maxLen = 200}) {
  final flat = (value?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return fallback;
  if (flat.length <= maxLen) return flat;
  final cut = flat.lastIndexOf(' ', maxLen);
  return '${flat.substring(0, cut > 0 ? cut : maxLen).trimRight()}…';
}

/// Folded (`>`) semantics: consecutive lines join with a space, a blank line
/// becomes a paragraph break.
String foldScalar(List<String> lines) {
  final buf = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].isEmpty) {
      buf.write('\n');
      continue;
    }
    if (i > 0 && lines[i - 1].isNotEmpty) buf.write(' ');
    buf.write(lines[i]);
  }
  return buf.toString();
}

/// Minimal YAML frontmatter reader — top-level scalar keys plus block scalars.
/// Complex shapes (`writers:` lists) are intentionally not parsed; the
/// diagnose-doc validator covers those.
Map<String, dynamic>? parseFrontmatter(String content) {
  // Normalize line endings so CRLF (Windows) files parse the same as LF.
  final normalized = content.replaceAll('\r\n', '\n');
  final all = normalized.split('\n');
  if (all.isEmpty || all.first.trimRight() != '---') return null;

  // Find the closing delimiter by scanning LINES for one that is exactly `---`,
  // not with a lazy `.*?` regex over the raw string. A folded `symptom:` block
  // can legitimately contain an unindented `---` (a markdown rule, a pasted
  // frontmatter fence), and the lazy form ended the frontmatter THERE — silently
  // dropping every field written after it (concept, contract_test_path,
  // recurrence, writers) while `symptom` itself still looked fine, so the
  // self-check never fired.
  var close = -1;
  for (var i = 1; i < all.length; i++) {
    if (all[i].trimRight() != '---') continue;
    // A line indented under an open block scalar belongs to that scalar.
    if (all[i].startsWith(' ') || all[i].startsWith('\t')) continue;
    close = i;
    break;
  }
  if (close < 0) return null;

  final out = <String, dynamic>{};
  final lines = all.sublist(1, close);
  final keyRe = RegExp(r'^([a-z_]+):\s*(.*)$');

  for (var i = 0; i < lines.length; i++) {
    final m = keyRe.firstMatch(lines[i]);
    if (m == null) continue;
    final key = m.group(1)!;
    final value = m.group(2)!.trim();
    if (value.isEmpty) continue;

    if (!blockScalarRe.hasMatch(value)) {
      out[key] = value;
      continue;
    }

    // Block scalar — the real text is on the following indented lines.
    //
    // A BLANK LINE IS CONTENT, NOT A TERMINATOR. 36 diagnose docs have a
    // paragraph break inside `symptom:`; stopping at the first blank line
    // truncates them to their opening sentence while STILL passing a
    // placeholder check, because the value is no longer literally `>`. Only a
    // line that is non-blank AND back at key indentation ends the scalar.
    final collected = <String>[];
    var j = i + 1;
    while (j < lines.length) {
      final l = lines[j];
      if (l.trim().isEmpty) {
        collected.add('');
        j++;
        continue;
      }
      if (!l.startsWith(' ') && !l.startsWith('\t')) break;
      collected.add(l.trim());
      j++;
    }
    while (collected.isNotEmpty && collected.last.isEmpty) {
      collected.removeLast();
    }
    // Literal (`|`) keeps line breaks; folded (`>`) joins.
    out[key] =
        value.startsWith('|') ? collected.join('\n') : foldScalar(collected);
    i = j - 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// A2 (merge-conflict-treadmill, plan section 6): STRICT validation of the diagnose docs.
//
// docs/diagnoses/INDEX.md is a local build product now, so nothing commits it and nothing
// compares a committed copy with the docs any more (that was Gate 25,
// scripts/check_diagnose_index_fresh.dart, deleted in the same landing). What Gate 25 really
// protected was "every doc is findable in the index"; the builder now refuses to write an
// index that would lose a doc, and that refusal is the same pure function a unit test can
// drive without spawning anything.
// ---------------------------------------------------------------------------

/// One diagnose doc as the builder reads it: its file name (no directory) and its text.
class DiagnoseDocInput {
  const DiagnoseDocInput(this.name, this.content);
  final String name;
  final String content;
}

/// The outcome of [validateDiagnoseDocs].
class DiagnoseValidation {
  const DiagnoseValidation(this.entries, this.problems);

  /// The docs that passed: parsed frontmatter maps with `_path` set to `<dir>/<name>`.
  final List<Map<String, dynamic>> entries;

  /// One line per doc that did not pass, `"<dir>/<name>: <what is wrong>"`.
  final List<String> problems;
}

/// The ids a doc's `bug_id:` may carry: the 6-character suffix of its file name
/// (`...-239999.md` -> `239999`) or the whole stem. The stem form exists for 12 legacy docs
/// (ten `2026-05-16-*` files with no suffix and two whose suffix is a word), measured
/// 2026-10-22: 648 docs carry the suffix and those 12 the stem.
Set<String> allowedBugIds(String fileName) {
  final stem = fileName.endsWith('.md')
      ? fileName.substring(0, fileName.length - 3)
      : fileName;
  final suffix = RegExp(r'-([a-zA-Z0-9]{6})$').firstMatch(stem)?.group(1);
  return {stem, ?suffix};
}

/// [v] without ONE pair of matching surrounding quotes: `bug_id: "132315"` is valid YAML for
/// the string `132315` and one doc (2026-10-23-dow-skip-rate-132315.md) is written that way,
/// while [parseFrontmatter] keeps scalars raw. Only the comparison is unquoted; the index still
/// renders the raw value, exactly as the pre-A2 builder did. Used for `bug_id:` only: a `date:`
/// must be bare ([_bareIsoDateRe]).
String _unquoted(String v) {
  final t = v.trim();
  if (t.length >= 2 &&
      ((t.startsWith('"') && t.endsWith('"')) ||
          (t.startsWith("'") && t.endsWith("'")))) {
    return t.substring(1, t.length - 1);
  }
  return t;
}

/// A `date:` every reader of the index can use: bare `YYYY-MM-DD`, no quotes. The chronological
/// table is sorted on the raw string, `check_regression_catalog.dart` keeps only the rows whose
/// first cell has exactly this shape (`regression_catalog_lib.dart`, `extractRecentTestPaths`),
/// and `validate_diagnose_doc_lib.dart` enforces the newer required fields only for a date that
/// starts with it. A quoted or free-text date therefore sorted out of order and silently dropped
/// that doc's regression test from the merge-commit walk (B-pass seat 1, F2). Gate 25 is gone,
/// so this rule is the only guard. Every doc of the repo carries a bare date
/// (`bug_index_strict_test.dart` walks the real corpus).
final RegExp _bareIsoDateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Validates every doc and returns the ones that pass plus a problem line for each that does
/// not. PURE: no file access, no exit.
///
/// A doc is a problem when it has no parseable frontmatter (the old builder only printed a
/// warning and skipped it, so the index silently lost the doc); no `date:` or one that is not
/// a bare `YYYY-MM-DD` (the sort below the builder used to crash with a TypeError on
/// `null as String`); no usable `symptom:` (c4e8a2: the index sat 237 of 344 entries empty);
/// or a `bug_id:` that is neither the file name's 6-character suffix nor its whole stem (the
/// id Gate 25 used to look for). A STRICT build fails on any problem and writes nothing; a
/// LENIENT build skips the docs named here, says so, and writes the rest.
DiagnoseValidation validateDiagnoseDocs(List<DiagnoseDocInput> docs,
    {String dir = 'docs/diagnoses'}) {
  final entries = <Map<String, dynamic>>[];
  final problems = <String>[];
  for (final doc in docs) {
    final path = '$dir/${doc.name}';
    final fm = parseFrontmatter(doc.content);
    if (fm == null) {
      problems.add('$path: no parseable frontmatter (missing or unclosed `---`)');
      continue;
    }
    final why = <String>[];
    final date = fm['date'];
    if (date is! String || date.trim().isEmpty) {
      why.add('missing `date:`');
    } else if (!_bareIsoDateRe.hasMatch(date.trim())) {
      why.add('`date:` "$date" is not a bare YYYY-MM-DD date (no quotes, no free text)');
    }
    final symptom = summarize(fm['symptom']);
    if (symptom.isEmpty) {
      why.add('missing `symptom:`');
    } else if (blockScalarRe.hasMatch(symptom)) {
      why.add('`symptom:` is a bare block-scalar indicator "$symptom"');
    }
    final id = fm['bug_id'];
    if (id is! String || !allowedBugIds(doc.name).contains(_unquoted(id))) {
      why.add('`bug_id:` ${id == null ? 'is missing' : '"$id"'} is neither the '
          '6-character file-name suffix nor the whole stem '
          '(${allowedBugIds(doc.name).join(' or ')})');
    }
    if (why.isNotEmpty) {
      problems.add('$path: ${why.join('; ')}');
      continue;
    }
    fm['_path'] = path;
    entries.add(fm);
  }
  return DiagnoseValidation(entries, problems);
}
