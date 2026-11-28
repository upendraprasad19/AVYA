// scripts/bug_class_ids_lib.dart
//
// Pure parsing and checking for the debugging skill's bug-class numbers (landing B of the
// merge-conflict-treadmill plan, docs/plans/bug-class-uniqueness.md; closes OI-167). No IO:
// scripts/check_bug_class_numbers_unique.dart reads the two files and calls into this.
//
// THE TWO FILES. `.claude/skills/debugging/bug-classes.md` holds one `### 2.N Title` heading per
// class; `.claude/skills/debugging/SKILL.md` holds ONE index table under `### Bug-class index`
// with one `| 2.N | title | trigger | test |` row per class. A new class appends a heading and a
// row, and the next number used to be "max + 1" read by eye. Nine numbers ended up on two
// classes each (2.36-2.41, 2.53-2.55) because the natural survey, `tail -1` on the file, answers
// "the last-POSITIONED entry" when the question was "the highest number" (2.61 was minted twice
// on 2026-09-07). This library is the single reader that gets the answer right.
//
// WHAT IT CHECKS (check): an id used twice in either file; an id in one file and not the other;
// an id whose major is not 2; a numeric `### N.M` heading inside SKILL.md (a class body appended
// to the wrong file); a line that LOOKS like a heading or row but does not parse (so an unparsed
// class cannot hide); and an id whose title differs between the two files (the first 16
// alphanumeric characters), which is the drift a renumber can leave behind.
//
// The numbers are compared as INTEGER PAIRS: 2.9 < 2.10 < 2.100, never lexically, never by
// position in the file.
//
// DELIBERATE EDGES (each fails CLOSED, with a message that names the line):
//   - A line outside a code fence that starts with up to three spaces, one to six `#` and a
//     number like `2.5` is read as a class heading that did not parse, so a prose line must not
//     start that way. A class heading itself must start at column 0.
//   - An unclosed code fence is a finding: everything after it would otherwise vanish from the
//     parse and hide a duplicate.
//   - HTML comments are NOT modelled: a heading or row inside `<!-- -->` counts. No file has one.
//   - Titles are compared by their letters and digits in any script, lowercased.

/// The two files the catalog lives in, relative to the repository root.
const String kBugClassesPath = '.claude/skills/debugging/bug-classes.md';
const String kBugClassSkillPath = '.claude/skills/debugging/SKILL.md';

/// The line that opens the index table in SKILL.md.
const String kIndexHeadingPrefix = '### Bug-class index';

/// `major.minor` as an integer pair. `2.05` and `2.5` are the same id.
class BugClassId implements Comparable<BugClassId> {
  const BugClassId(this.major, this.minor);

  final int major;
  final int minor;

  @override
  int compareTo(BugClassId other) {
    final byMajor = major.compareTo(other.major);
    return byMajor != 0 ? byMajor : minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) =>
      other is BugClassId && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}

/// A `### N.M Title` heading in bug-classes.md. [line] is 1-based.
class ClassHeading {
  const ClassHeading(this.id, this.title, this.line);

  final BugClassId id;
  final String title;
  final int line;
}

/// A `| N.M | title | ... |` row in the SKILL.md index table. [line] is 1-based.
class IndexRow {
  const IndexRow(this.id, this.title, this.line);

  final BugClassId id;
  final String title;
  final int line;
}

/// A line the parser saw but could not accept. [line] is 1-based.
class LineNote {
  const LineNote(this.line, this.text);

  final int line;
  final String text;
}

/// One problem found by [checkBugClassNumbers]. [line] is 1-based.
class BugClassFinding {
  const BugClassFinding(this.file, this.line, this.message);

  final String file;
  final int line;
  final String message;
}

class HeadingScan {
  const HeadingScan(this.headings, this.lookalikes, this.unclosedFenceLine);

  final List<ClassHeading> headings;

  /// The 1-based line of a code fence that is never closed (it swallows the rest of the text), or null.
  final int? unclosedFenceLine;

  /// Lines that look like a numbered heading but are not accepted (see [scanHeadings]).
  final List<LineNote> lookalikes;
}

class IndexScan {
  const IndexScan(this.rows, this.malformed);

  final List<IndexRow> rows;

  /// Table lines that are not rows, headers or separators, or that have fewer than four cells.
  final List<LineNote> malformed;
}

final RegExp _headingRe = RegExp(r'^### (\d+)\.(\d+)(?: ([^\n]*))?$');
final RegExp _lookalikeRe = RegExp(r'^ {0,3}#{1,6}\s*\d+\.\d+');
final RegExp _archivedRe = RegExp(r'^### \d+\.\d+\.archived-');
final RegExp _fenceRe = RegExp(r'^ {0,3}(`{3,}|~{3,})');
final RegExp _cellSplitRe = RegExp(r'(?<!\\)\|');
final RegExp _idCellRe = RegExp(r'^(\d+)\.(\d+)$');

/// Splits [text] into lines, dropping a trailing `\r` of each (a Windows checkout).
List<String> _lines(String text) => text
    .split('\n')
    .map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l)
    .toList();

/// `fenced` is true for every line that belongs to a fenced code block (opener, body and closer);
/// `unclosedOpener` is the 1-based line of a fence that never closes, or null.
///
/// A fence opens with up to three spaces of indent and at least three backticks or tildes
/// (a backtick opener's info string may not contain a backtick, so a line that merely starts
/// with an inline ```code``` span is not an opener). It closes with a line of the SAME
/// character, at least as long as the opener, followed by nothing but whitespace. Four spaces
/// of indent is not a fence. An unclosed fence runs to the end of the text.
({List<bool> fenced, int? unclosedOpener}) _scanFences(List<String> lines) {
  final out = List<bool>.filled(lines.length, false);
  String? ch;
  var len = 0;
  var openedAt = 0;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final m = _fenceRe.firstMatch(l);
    if (ch == null) {
      if (m == null) continue;
      final run = m.group(1)!;
      if (run[0] == '`' && l.substring(m.end).contains('`')) continue;
      ch = run[0];
      len = run.length;
      openedAt = i + 1;
      out[i] = true;
    } else {
      out[i] = true;
      if (m != null &&
          m.group(1)![0] == ch &&
          m.group(1)!.length >= len &&
          l.substring(m.end).trim().isEmpty) {
        ch = null;
      }
    }
  }
  return (fenced: out, unclosedOpener: ch == null ? null : openedAt);
}

/// Reads the `### N.M Title` headings of [text]. A heading inside a fence is ignored.
///
/// A line outside a fence that matches `^#{1,6}\s*\d+\.\d+` but is not accepted (for example
/// `### 2.124: Title`, `###2.124`, `##### 2.124`, `### 2.7x`, or a number too large for an int)
/// is returned in [HeadingScan.lookalikes]; the `### 2.5.archived-YYYY-MM-DD` shape of a
/// superseded entry (SKILL.md section 5) is not a lookalike.
HeadingScan scanHeadings(String text) {
  final lines = _lines(text);
  final scan = _scanFences(lines);
  final fenced = scan.fenced;
  final headings = <ClassHeading>[];
  final lookalikes = <LineNote>[];
  for (var i = 0; i < lines.length; i++) {
    if (fenced[i]) continue;
    final l = lines[i];
    final m = _headingRe.firstMatch(l);
    if (m != null) {
      final major = int.tryParse(m.group(1)!);
      final minor = int.tryParse(m.group(2)!);
      if (major != null && minor != null) {
        headings.add(ClassHeading(BugClassId(major, minor), (m.group(3) ?? '').trim(), i + 1));
        continue;
      }
      lookalikes.add(LineNote(i + 1, l));
      continue;
    }
    if (_lookalikeRe.hasMatch(l) && !_archivedRe.hasMatch(l)) {
      lookalikes.add(LineNote(i + 1, l));
    }
  }
  return HeadingScan(headings, lookalikes, scan.unclosedOpener);
}

/// Reads the index table of SKILL.md: the lines under the line that starts
/// [kIndexHeadingPrefix], up to the next line that starts `## ` or `### ` or is a `---` rule.
/// Returns null when that heading line is absent.
///
/// A table line is split on unescaped `|`. Cell 1 is the id, cell 2 (trimmed) the title.
/// A header row (`id`) and a separator row (`---`, `:--`) are skipped; any other line that does
/// not carry an id in cell 1, or that has fewer than four cells, is [IndexScan.malformed].
IndexScan? scanIndex(String text) {
  final lines = _lines(text);
  final fenced = _scanFences(lines).fenced;
  int? start;
  for (var i = 0; i < lines.length; i++) {
    if (!fenced[i] && lines[i].startsWith(kIndexHeadingPrefix)) {
      start = i;
      break;
    }
  }
  if (start == null) return null;
  final rows = <IndexRow>[];
  final malformed = <LineNote>[];
  for (var i = start + 1; i < lines.length; i++) {
    if (fenced[i]) continue;
    final l = lines[i];
    if (l.startsWith('## ') || l.startsWith('### ') || l.trim() == '---') break;
    final t = l.trim();
    if (!t.startsWith('|')) continue;
    var inner = t.substring(1);
    if (inner.endsWith('|')) inner = inner.substring(0, inner.length - 1);
    final cells = inner.split(_cellSplitRe).map((c) => c.trim()).toList();
    final idCell = cells.first;
    final m = _idCellRe.firstMatch(idCell);
    if (m == null) {
      final isHeader = idCell.toLowerCase() == 'id';
      final isSeparator = cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c));
      if (!isHeader && !isSeparator) malformed.add(LineNote(i + 1, l));
      continue;
    }
    final major = int.tryParse(m.group(1)!);
    final minor = int.tryParse(m.group(2)!);
    if (major == null || minor == null || cells.length < 4) {
      malformed.add(LineNote(i + 1, l));
      continue;
    }
    rows.add(IndexRow(BugClassId(major, minor), cells[1], i + 1));
  }
  return IndexScan(rows, malformed);
}

/// Lowercase and keep only letters and digits of any script: the form two titles are compared in.
String normalizeTitle(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// The next free id in major 2: one above the highest minor over [ids], or null when [ids]
/// holds no major-2 id. Numeric, never lexical, never "the last one in the file".
BugClassId? nextFreeId(Iterable<BugClassId> ids) {
  int? highest;
  for (final id in ids) {
    if (id.major != 2) continue;
    if (highest == null || id.minor > highest) highest = id.minor;
  }
  return highest == null ? null : BugClassId(2, highest + 1);
}

Map<BugClassId, List<T>> _groupById<T>(Iterable<T> items, BugClassId Function(T) idOf) {
  final out = <BugClassId, List<T>>{};
  for (final item in items) {
    out.putIfAbsent(idOf(item), () => <T>[]).add(item);
  }
  return out;
}

/// Everything [checkBugClassNumbers] learned from the two files.
class CatalogReport {
  const CatalogReport({
    required this.headings,
    required this.rows,
    required this.indexSectionMissing,
    required this.findings,
  });

  final List<ClassHeading> headings;
  final List<IndexRow> rows;

  /// True when SKILL.md has no `### Bug-class index` line; [findings] is then empty because the
  /// caller must report that single reason instead of one finding per heading.
  final bool indexSectionMissing;

  /// Every problem, ordered by file then line. Empty means the catalog is clean.
  final List<BugClassFinding> findings;

  /// The next free id over the union of both files' ids, or null when there is no major-2 id.
  BugClassId? get nextFree =>
      nextFreeId([...headings.map((h) => h.id), ...rows.map((r) => r.id)]);
}

/// Checks the two files against each other. [bugClassesText] and [skillText] are the full file
/// contents.
CatalogReport checkBugClassNumbers(String bugClassesText, String skillText) {
  final headingScan = scanHeadings(bugClassesText);
  final skillScan = scanHeadings(skillText);
  final indexScan = scanIndex(skillText);
  if (indexScan == null) {
    return CatalogReport(
      headings: headingScan.headings,
      rows: const <IndexRow>[],
      indexSectionMissing: true,
      findings: const <BugClassFinding>[],
    );
  }
  final out = <BugClassFinding>[];
  final headingsById = _groupById(headingScan.headings, (h) => h.id);
  final rowsById = _groupById(indexScan.rows, (r) => r.id);

  // 1. an id used more than once in either file (every line is named)
  for (final e in headingsById.entries) {
    if (e.value.length < 2) continue;
    final lines = e.value.map((h) => h.line).join(', ');
    out.add(BugClassFinding(kBugClassesPath, e.value.first.line,
        'id ${e.key} is used by ${e.value.length} headings (lines $lines)'));
  }
  for (final e in rowsById.entries) {
    if (e.value.length < 2) continue;
    final lines = e.value.map((r) => r.line).join(', ');
    out.add(BugClassFinding(kBugClassSkillPath, e.value.first.line,
        'id ${e.key} is used by ${e.value.length} index rows (lines $lines)'));
  }

  // 2. an id in one file and not the other
  for (final e in headingsById.entries) {
    if (!rowsById.containsKey(e.key)) {
      out.add(BugClassFinding(kBugClassesPath, e.value.first.line,
          'id ${e.key} has a heading but no row in the SKILL.md index'));
    }
  }
  for (final e in rowsById.entries) {
    if (!headingsById.containsKey(e.key)) {
      out.add(BugClassFinding(kBugClassSkillPath, e.value.first.line,
          'id ${e.key} has an index row but no heading in bug-classes.md'));
    }
  }

  // 3. an id whose major is not 2
  for (final h in headingScan.headings) {
    if (h.id.major != 2) {
      out.add(BugClassFinding(kBugClassesPath, h.line, 'id ${h.id} is not in major 2'));
    }
  }
  for (final r in indexScan.rows) {
    if (r.id.major != 2) {
      out.add(BugClassFinding(kBugClassSkillPath, r.line, 'id ${r.id} is not in major 2'));
    }
  }

  // 4. a numeric `### 2.N` heading in SKILL.md: a class body appended to the wrong file (another
  // major, such as a `### 5.1` sub-section, is not a bug class and is left alone)
  for (final h in skillScan.headings) {
    if (h.id.major != 2) continue;
    out.add(BugClassFinding(kBugClassSkillPath, h.line,
        'numeric heading "### ${h.id}" in SKILL.md: class bodies belong in bug-classes.md'));
  }

  // 5. lines that look like a heading or row but do not parse, in BOTH files
  for (final n in headingScan.lookalikes) {
    out.add(BugClassFinding(kBugClassesPath, n.line,
        'line looks like a class heading but does not parse: "${n.text}"'));
  }
  for (final n in skillScan.lookalikes) {
    out.add(BugClassFinding(kBugClassSkillPath, n.line,
        'line looks like a class heading but does not parse: "${n.text}"'));
  }
  for (final entry in [
    (kBugClassesPath, headingScan.unclosedFenceLine),
    (kBugClassSkillPath, skillScan.unclosedFenceLine),
  ]) {
    final line = entry.$2;
    if (line == null) continue;
    out.add(BugClassFinding(entry.$1, line,
        'code fence opened here is never closed: everything after it is ignored by the parser'));
  }
  for (final n in indexScan.malformed) {
    out.add(BugClassFinding(kBugClassSkillPath, n.line,
        'index table line is not a row with an id and four cells: "${n.text}"'));
  }

  // 6. title pairing: only an id that occurs exactly ONCE in each file is paired (a duplicated
  // id is finding 1, and pairing it would only repeat it). The first min(16, shorter length)
  // alphanumeric characters of the two titles must agree; an empty title is a finding.
  for (final e in headingsById.entries) {
    final rows = rowsById[e.key];
    if (e.value.length != 1 || rows == null || rows.length != 1) continue;
    final h = e.value.single;
    final r = rows.single;
    final a = normalizeTitle(h.title);
    final b = normalizeTitle(r.title);
    if (a.isEmpty || b.isEmpty) {
      out.add(BugClassFinding(kBugClassSkillPath, r.line,
          'id ${e.key} has an empty title (heading line ${h.line}, row line ${r.line})'));
      continue;
    }
    final n = a.length < b.length ? a.length : b.length;
    final take = n < 16 ? n : 16;
    if (a.substring(0, take) != b.substring(0, take)) {
      out.add(BugClassFinding(kBugClassSkillPath, r.line,
          'id ${e.key} names different classes: heading line ${h.line} "${h.title}" '
          'versus index row "${r.title}"'));
    }
  }

  out.sort((x, y) {
    final byFile = x.file.compareTo(y.file);
    return byFile != 0 ? byFile : x.line.compareTo(y.line);
  });
  return CatalogReport(
    headings: headingScan.headings,
    rows: indexScan.rows,
    indexSectionMissing: false,
    findings: out,
  );
}
