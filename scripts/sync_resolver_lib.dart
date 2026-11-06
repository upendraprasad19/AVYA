// scripts/sync_resolver_lib.dart
//
// Pure helpers for the record-aware resolver of landing C2 of the merge-conflict-treadmill plan
// (docs/plans/sync-resolver.md; parent docs/plans/merge-conflict-treadmill.md, OI-309). No IO:
// scripts/sync_with_main.dart reads the three stages of an unmerged path and calls into this.
//
// THE PROBLEM. After A1 (tuning entry inside the review file) and A2 (indexes untracked) the files
// that still conflict when a branch is synced with origin/main are append-only ledgers where both
// sides added DIFFERENT records at the same spot. Git sees overlapping insertions; a human sees two
// independent records.
//
// THE RULE. A file is a list of REGIONS (a run of records) separated by prose. A record starts at a
// line matching the region's start pattern, carries a key, owns the comment lines directly above it
// when the region has a leader, and ends where the next record starts. Per key the three versions
// (base = stage 1, ours = stage 2, theirs = stage 3) are decided like a three-way merge; a record
// both sides changed differently goes to the injected text merge (git merge-file) and keeps its
// markers around THAT record only. Two sides that both ADDED a key with different text conflict:
// a number is never renumbered here.
//
// SAFETY. Anything the parser cannot place is [Unresolvable] and the caller leaves git's file
// untouched. A result is only offered after three checks computed from the three inputs and the
// output (see [verifyResolution]): V-a line counts, V-b agreement with git's own merge outside its
// conflict hunks, V-c a re-parse of a clean output.
//
// The lib imports only dart:convert; git and the file system come in through [TextMerge].

import 'dart:convert';

/// Thrown when a file cannot be merged by record; [reason] is shown to the human.
class Unresolvable implements Exception {
  Unresolvable(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// How a record is followed by the next one.
enum Sep {
  /// Records end with their own trailing blank lines; a blank line is added only to a record that
  /// stops being last.
  blank,

  /// Records are single lines or bullets that keep their own bytes (tables, the changelog).
  none,

  /// JSON array elements: the trailing comma is stripped at parse time and re-added at emission.
  comma,
}

/// Extra structural check of a clean output (V-c).
enum YamlKind { none, registry, ledger }

/// One run of records inside a file.
class RegionSpec {
  RegionSpec({
    this.anchor,
    required this.start,
    required this.key,
    this.end,
    required this.sep,
    this.markdown = false,
    this.table = false,
    this.leader,
  });

  /// The region begins at the first record start after the first line matching this (null: file start).
  final RegExp? anchor;

  /// A record starts at a line (including its newline) matching this.
  final RegExp start;

  /// Applied to the record text (multi-line); group 1 is the key.
  final RegExp key;

  /// The first line after the region's first record that matches this (and is not a record start)
  /// ends the region (null: end of file).
  final RegExp? end;

  final Sep sep;

  /// Ignore record starts inside fenced code blocks.
  final bool markdown;

  /// Every line of the region must match [start].
  final bool table;

  /// Comment lines directly above a record start that belong to that record.
  final RegExp? leader;
}

class FileSpec {
  FileSpec(this.path, this.regions, {this.yaml = YamlKind.none});

  final String path;
  final List<RegionSpec> regions;
  final YamlKind yaml;
}

/// The allow-list of docs/plans/sync-resolver.md section 4.2. NOT in it, on purpose: the frozen tuning
/// archive, the two generated indexes, code, tests and prose.
final List<FileSpec> kResolvableFiles = [
  FileSpec('docs/audit/open_issues.md', [_oiBoard()]),
  FileSpec('docs/audit/closed_issues.md', [_oiBoard()]),
  FileSpec('.claude/skills/debugging/bug-classes.md', [
    RegionSpec(
      start: RegExp(r'^### \d+\.\d+(?:[ .\n]|$)'),
      key: RegExp(r'^### (\d+\.\d+(?:\.archived-[0-9-]+)?)', multiLine: true),
      sep: Sep.blank,
      markdown: true,
    ),
  ]),
  FileSpec('.claude/skills/debugging/SKILL.md', [
    RegionSpec(
      anchor: RegExp(r'^### Bug-class index'),
      start: RegExp(r'^\| \d+\.\d+ \|'),
      key: RegExp(r'^\| (\d+\.\d+) \|', multiLine: true),
      end: RegExp(r'^(?!\|)'),
      sep: Sep.none,
      markdown: true,
      table: true,
    ),
    RegionSpec(
      anchor: RegExp(r'^## Changelog'),
      start: RegExp(r'^- \*\*'),
      key: RegExp(r'^- \*\*([^*]+)\*\*', multiLine: true),
      sep: Sep.none,
      markdown: true,
    ),
  ]),
  FileSpec('docs/naming_conventions.md', [
    RegionSpec(
      anchor: RegExp(r'^## 8\. Reserved domain glossary'),
      start: RegExp(r'^\| \*\*'),
      key: RegExp(r'^\| (.+?) \| ', multiLine: true),
      end: RegExp(r'^(?!\|)'),
      sep: Sep.none,
      markdown: true,
      table: true,
    ),
  ]),
  FileSpec(
    'docs/sot_registry.yaml',
    [
      RegionSpec(
        anchor: RegExp(r'^concepts:'),
        start: RegExp(r'^  - concept: '),
        key: RegExp(r'^  - concept: (\S+)', multiLine: true),
        sep: Sep.blank,
        leader: RegExp(r'^  #'),
      ),
    ],
    yaml: YamlKind.registry,
  ),
  FileSpec(
    'docs/audit/gate_test_ledger.yaml',
    [
      RegionSpec(
        start: RegExp(r'^[a-z0-9_]+\.dart:\s*$'),
        key: RegExp(r'^([a-z0-9_]+\.dart):', multiLine: true),
        sep: Sep.blank,
        leader: RegExp(r'^#'),
      ),
    ],
    yaml: YamlKind.ledger,
  ),
  FileSpec('backups/applied_migrations.json', [
    RegionSpec(
      start: RegExp(r'^  \{\s*$'),
      key: RegExp(r'"migration":\s*"([^"]+)"', multiLine: true),
      end: RegExp(r'^\]'),
      sep: Sep.comma,
    ),
  ]),
];

RegionSpec _oiBoard() => RegionSpec(
      start: RegExp(r'^## OI-\d+ '),
      key: RegExp(r'^## (OI-\d+) ', multiLine: true),
      sep: Sep.blank,
      markdown: true,
    );

/// The spec for [path], or null when the path is not in the allow-list.
FileSpec? specFor(String path) {
  for (final f in kResolvableFiles) {
    if (f.path == path) return f;
  }
  return null;
}

/// `git merge-file -p --diff3` of three texts. [conflicted] is true when markers were written; a
/// failure of git itself (exit above 127, a spawn error) must be thrown as [Unresolvable].
typedef TextMerge = ({String text, bool conflicted}) Function(String base, String ours, String theirs);

// ---------------------------------------------------------------------------------------------------
// text helpers

/// Splits on `\n` only; every element keeps its terminator except possibly the last.
List<String> splitLines(String text) {
  final out = <String>[];
  var from = 0;
  while (from < text.length) {
    final nl = text.indexOf('\n', from);
    if (nl < 0) {
      out.add(text.substring(from));
      break;
    }
    out.add(text.substring(from, nl + 1));
    from = nl + 1;
  }
  return out;
}

/// Removes trailing empty or whitespace-only lines; the result has no trailing newline.
String trimEnd(String s) {
  final ls = s.split('\n');
  while (ls.isNotEmpty && ls.last.trim().isEmpty) {
    ls.removeLast();
  }
  return ls.join('\n');
}

int _trailingNewlines(String s) {
  var n = 0;
  for (var i = s.length - 1; i >= 0 && s[i] == '\n'; i--) {
    n++;
  }
  return n;
}

final RegExp _fenceRe = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// Mirrors scripts/bug_class_ids_lib.dart `_scanFences` (pinned by a test): a fence opens with up to
/// three spaces and at least three backticks or tildes (a backtick opener's info string may not
/// contain a backtick) and closes with a line of the same character, at least as long, followed by
/// nothing but whitespace. An unclosed fence runs to the end.
({List<bool> fenced, bool unclosed}) scanFences(List<String> lines) {
  final out = List<bool>.filled(lines.length, false);
  String? ch;
  var len = 0;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final m = _fenceRe.firstMatch(l);
    if (ch == null) {
      if (m == null) continue;
      final run = m.group(1)!;
      if (run[0] == '`' && l.substring(m.end).contains('`')) continue;
      ch = run[0];
      len = run.length;
      out[i] = true;
    } else {
      out[i] = true;
      if (m != null && m.group(1)![0] == ch && m.group(1)!.length >= len && l.substring(m.end).trim().isEmpty) {
        ch = null;
      }
    }
  }
  return (fenced: out, unclosed: ch != null);
}

// ---------------------------------------------------------------------------------------------------
// parsing

/// One record: [parts] holds one text, or several for a CHANGED group of a repeated key.
class Record {
  Record(this.key, this.occurrence, this.parts, {this.repeated = false, this.group = false});

  final String key;
  final int occurrence;

  /// The record texts, each ending with its own newline(s); no trailing comma in a comma region.
  final List<String> parts;

  /// The key occurs more than once in this version.
  final bool repeated;

  /// A collapsed group of a repeated key whose occurrences changed.
  final bool group;

  /// Identity inside one region: the key, plus the occurrence for a repeated key, `*` for a group.
  String get id {
    if (group) return '$key$_idSep*';
    if (repeated) return '$key$_idSep$occurrence';
    return key;
  }

  String get text => parts.join();

  /// Equality of the content: every part compared after trimming trailing blank lines.
  String get trimmed => parts.map(trimEnd).join(_partSep);

  String get raw => parts.join(_partSep);
}

final String _idSep = String.fromCharCode(31);
final String _partSep = String.fromCharCode(30);

abstract class Piece {}

class GapPiece extends Piece {
  GapPiece(this.text);

  final String text;
}

class RegionPiece extends Piece {
  RegionPiece(this.records, this.spec);

  final List<Record> records;
  final RegionSpec spec;
}

/// Parses [text] into gap and region pieces. Throws [Unresolvable].
List<Piece> parseFile(String text, List<RegionSpec> specs) {
  if (text.contains('\r\n')) throw Unresolvable('CRLF line endings');
  if (text.contains(String.fromCharCode(0))) throw Unresolvable('a NUL byte');
  final lines = splitLines(text);
  final n = lines.length;
  var i = 0;
  final pieces = <Piece>[];
  ({List<bool> fenced, bool unclosed})? fences;
  for (var si = 0; si < specs.length; si++) {
    final spec = specs[si];
    List<bool> fl = List<bool>.filled(n, false);
    if (spec.markdown) {
      fences ??= scanFences(lines);
      if (fences.unclosed) throw Unresolvable('an unclosed code fence');
      fl = fences.fenced;
    }
    var j = i;
    if (spec.anchor != null) {
      while (j < n && !(spec.anchor!.hasMatch(lines[j]) && !fl[j])) {
        j++;
      }
      if (j == n) throw Unresolvable('region ${si + 1}: the anchor ${spec.anchor!.pattern} was not found');
    }
    while (j < n && !(spec.start.hasMatch(lines[j]) && !fl[j])) {
      j++;
    }
    if (j == n) throw Unresolvable('region ${si + 1}: no record');
    var s0 = j;
    if (spec.leader != null) {
      while (s0 > i && spec.leader!.hasMatch(lines[s0 - 1])) {
        s0--;
      }
    }
    pieces.add(GapPiece(lines.sublist(i, s0).join()));
    final recs = <List<String>>[];
    var cur = <String>[];
    var curHasStart = false;
    var k = s0;
    while (k < n) {
      final l = lines[k];
      if (k > j && spec.end != null && spec.end!.hasMatch(l) && !spec.start.hasMatch(l)) break;
      if (spec.start.hasMatch(l) && !fl[k]) {
        if (curHasStart) {
          recs.add(cur);
          cur = <String>[];
        }
        cur.add(l);
        curHasStart = true;
      } else {
        cur.add(l);
      }
      k++;
    }
    recs.add(cur);
    final kend = k;
    if (spec.table) {
      for (var ln = j; ln < kend; ln++) {
        if (!spec.start.hasMatch(lines[ln])) {
          throw Unresolvable('region ${si + 1}: line ${ln + 1} is not a table row of the record pattern');
        }
      }
    }
    if (spec.leader != null) {
      for (var idx = 1; idx < recs.length; idx++) {
        final prev = recs[idx - 1];
        var mv = 0;
        while (mv < prev.length - 1 && spec.leader!.hasMatch(prev[prev.length - 1 - mv]) && prev[prev.length - 1 - mv].trim().isNotEmpty) {
          mv++;
        }
        if (mv > 0) {
          recs[idx] = [...prev.sublist(prev.length - mv), ...recs[idx]];
          recs[idx - 1] = prev.sublist(0, prev.length - mv);
        }
      }
    }
    var texts = recs.map((r) => r.join()).toList();
    if (spec.sep == Sep.comma) {
      texts = texts.map((t) {
        var body = t;
        while (body.endsWith('\n')) {
          body = body.substring(0, body.length - 1);
        }
        return '${body.replaceFirst(RegExp(r',\s*$'), '')}\n';
      }).toList();
    }
    final keys = <String>[];
    for (var r = 0; r < texts.length; r++) {
      final m = spec.key.firstMatch(texts[r]);
      if (m == null) throw Unresolvable('region ${si + 1}: record ${r + 1} has no key');
      keys.add(m.group(1)!);
    }
    final count = <String, int>{};
    for (final k2 in keys) {
      count[k2] = (count[k2] ?? 0) + 1;
    }
    final seen = <String, int>{};
    final records = <Record>[];
    for (var r = 0; r < texts.length; r++) {
      final k2 = keys[r];
      final occ = seen[k2] ?? 0;
      seen[k2] = occ + 1;
      records.add(Record(k2, occ, [texts[r]], repeated: count[k2]! > 1));
    }
    pieces.add(RegionPiece(records, spec));
    i = kend;
  }
  pieces.add(GapPiece(lines.sublist(i).join()));
  return pieces;
}

// ---------------------------------------------------------------------------------------------------
// merging

/// What was decided for one record id.
class Decided {
  Decided(this.id, this.parts, this.wasLast);

  final String id;
  final List<String> parts;

  /// The record was the last record of its source version.
  final bool wasLast;

  String get text => parts.join();
}

class RegionResult {
  RegionResult(this.decided, this.conflictedKeys, this.mergedByLine, this.oursLast);

  final List<Decided> decided;
  final List<String> conflictedKeys;
  final List<String> mergedByLine;
  final String oursLast;
}

List<Record> _collapse(List<Record> v, Set<String> changed) {
  final out = <Record>[];
  final at = <String, int>{};
  for (final r in v) {
    if (changed.contains(r.key)) {
      final idx = at[r.key];
      if (idx == null) {
        at[r.key] = out.length;
        out.add(Record(r.key, 0, [r.text], group: true));
      } else {
        out[idx] = Record(r.key, 0, [...out[idx].parts, r.text], group: true);
      }
    } else {
      out.add(r);
    }
  }
  return out;
}

/// Three-way merge of one region. Throws [Unresolvable].
RegionResult mergeRegion(List<Record> b0, List<Record> o0, List<Record> t0, TextMerge textMerge) {
  Set<String> repeatedKeys(List<Record> v) => {for (final r in v) if (r.repeated) r.key};
  final dups = {...repeatedKeys(b0), ...repeatedKeys(o0), ...repeatedKeys(t0)};
  List<String> groupList(List<Record> v, String key) => [for (final r in v) if (r.key == key) trimEnd(r.text)];
  final changed = <String>{
    for (final name in dups)
      if (!_listEq(groupList(b0, name), groupList(o0, name)) || !_listEq(groupList(b0, name), groupList(t0, name))) name,
  };
  final b = _collapse(b0, changed);
  final o = _collapse(o0, changed);
  final t = _collapse(t0, changed);
  Map<String, Record> index(List<Record> v) => {for (final r in v) r.id: r};
  final bd = index(b), od = index(o), td = index(t);
  final bo = [for (final r in b) r.id];
  final oo = [for (final r in o) r.id];
  final to = [for (final r in t) r.id];
  final oLast = oo.isEmpty ? null : oo.last;
  final tLast = to.isEmpty ? null : to.last;
  final decided = <String, Decided>{};
  final conflicts = <String>[];
  final byLine = <String>[];
  final all = <String>{...oo, ...to, ...bo};
  for (final id in all) {
    final bt = bd[id], ot = od[id], tt = td[id];
    final nb = bt?.trimmed, no = ot?.trimmed, nt = tt?.trimmed;
    if (no == nt) {
      if (tt != null && bt != null && tt.raw != bt.raw && ot!.raw == bt.raw) {
        decided[id] = Decided(id, tt.parts, id == tLast);
      } else if (ot != null) {
        decided[id] = Decided(id, ot.parts, id == oLast);
      }
    } else if (no == nb) {
      if (tt != null) decided[id] = Decided(id, tt.parts, id == tLast);
    } else if (nt == nb) {
      if (ot != null) decided[id] = Decided(id, ot.parts, id == oLast);
    } else {
      if (id.endsWith('$_idSep*')) {
        throw Unresolvable('the repeated key ${id.substring(0, id.length - 2)} was changed on both sides');
      }
      final m = textMerge(bt?.text ?? '', ot?.text ?? '', tt?.text ?? '');
      decided[id] = Decided(id, [m.text], id == oLast);
      (m.conflicted ? conflicts : byLine).add(id);
    }
  }
  final shared = [
    for (final id in bo)
      if (od.containsKey(id) && td.containsKey(id) && !id.endsWith('$_idSep*')) id,
  ];
  final oShared = [for (final id in oo) if (shared.contains(id)) id];
  final tShared = [for (final id in to) if (shared.contains(id)) id];
  if (!_listEq(oShared, shared)) throw Unresolvable('a side reordered records (ours)');
  if (!_listEq(tShared, shared)) throw Unresolvable('a side reordered records (theirs)');
  final order = [for (final id in oo) if (decided.containsKey(id)) id];
  for (var idx = 0; idx < to.length; idx++) {
    final id = to[idx];
    if (od.containsKey(id)) continue;
    if (!decided.containsKey(id)) continue;
    var pos = 0;
    for (var j = idx - 1; j >= 0; j--) {
      final at = order.indexOf(to[j]);
      if (at >= 0) {
        pos = at + 1;
        break;
      }
    }
    order.insert(pos, id);
  }
  final oursLastText = o.isEmpty ? '' : o.last.text;
  return RegionResult([for (final id in order) decided[id]!], conflicts, byLine, oursLastText);
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// True when the element body ENDS inside a conflict block (git's hunk reached the element's closing line): only then
/// does the separator comma have to move into the two sides. A hunk in the middle of an element leaves the closing line
/// outside the block, and the comma follows it as usual.
bool _hasMarkers(String body) => body.split('\n').last.startsWith('>>>>>>>');

/// Adds the separator comma to the last content line of the ours side and of the theirs side of every conflict
/// block in [body] (the base section of a diff3 block gets none).
String _commaIntoSides(String body) {
  final ls = body.split('\n');
  var section = 0; // 0 outside, 1 ours, 2 base, 3 theirs
  var sectionStart = 0;
  final first = ls.lastIndexWhere((l) => l.startsWith('<<<<<<<'));
  for (var i = first < 0 ? 0 : first; i < ls.length; i++) {
    final l = ls[i];
    final isOpen = l.startsWith('<<<<<<<');
    final isBase = l.startsWith('|||||||');
    final isMid = l == '=======';
    final isClose = l.startsWith('>>>>>>>');
    if (!(isOpen || isBase || isMid || isClose)) continue;
    final endsSide = (section == 1 && (isBase || isMid)) || (section == 3 && isClose);
    if (endsSide && i - 1 >= sectionStart) ls[i - 1] = '${ls[i - 1]},';
    if (isOpen) {
      section = 1;
    } else if (isBase) {
      section = 2;
    } else if (isMid) {
      section = 3;
    } else {
      section = 0;
    }
    sectionStart = i + 1;
  }
  return ls.join('\n');
}

String _emitRegion(RegionResult r, RegionSpec spec) {
  final out = StringBuffer();
  final n = r.decided.length;
  final oTail = _trailingNewlines(r.oursLast);
  for (var idx = 0; idx < n; idx++) {
    final d = r.decided[idx];
    final last = idx == n - 1;
    if (spec.sep == Sep.comma) {
      final body = d.parts.map(trimEnd).join(',\n');
      if (!last && _hasMarkers(body)) {
        // A human resolves a conflicted element by keeping a side and deleting the marker lines: the separator comma
        // must therefore sit on the last line of each SIDE, never on the closing marker line.
        out.write('${_commaIntoSides(body)}\n');
      } else {
        out.write('$body${last ? '' : ','}\n');
      }
      continue;
    }
    var body = d.text;
    if (spec.sep == Sep.blank) {
      if (!last && d.wasLast && !body.endsWith('\n\n')) body = '$body\n';
      if (last && !d.wasLast) body = '${trimEnd(body)}${'\n' * (oTail < 1 ? 1 : oTail)}';
    } else if (!last && !body.endsWith('\n')) {
      body = '$body\n';
    }
    out.write(body);
  }
  return out.toString();
}

/// The outcome of [resolveFile].
class Resolution {
  Resolution({
    required this.text,
    required this.conflictedKeys,
    required this.mergedByLine,
    required this.decisions,
    required this.partial,
  });

  /// The merged file; with conflict markers when [partial].
  final String text;

  /// Keys (or `<gap>`) whose text merge kept markers.
  final List<String> conflictedKeys;

  /// Keys merged cleanly by line: a human should read them.
  final List<String> mergedByLine;

  final List<RegionResult> decisions;

  /// Markers remain in [text].
  final bool partial;
}

List<Piece> _parseAs(String version, String text, List<RegionSpec> specs) {
  try {
    return parseFile(text, specs);
  } on Unresolvable catch (e) {
    throw Unresolvable('$version: ${e.reason}');
  }
}

/// Merges one file by record. Throws [Unresolvable]; runs no check (see [verifyResolution]).
Resolution resolveFile(FileSpec spec, {required String base, required String ours, required String theirs, required TextMerge textMerge}) {
  final pb = _parseAs('base', base, spec.regions);
  final po = _parseAs('ours', ours, spec.regions);
  final pt = _parseAs('theirs', theirs, spec.regions);
  final out = StringBuffer();
  final conflicts = <String>[];
  final byLine = <String>[];
  final decisions = <RegionResult>[];
  // parseFile yields the same sequence for every version (gap, region, ..., gap): one region per spec.
  for (var i = 0; i < pb.length; i++) {
    final x = pb[i], y = po[i], z = pt[i];
    if (x is GapPiece) {
      y as GapPiece;
      z as GapPiece;
      if (y.text == z.text) {
        out.write(y.text);
      } else if (y.text == x.text) {
        out.write(z.text);
      } else if (z.text == x.text) {
        out.write(y.text);
      } else {
        final m = textMerge(x.text, y.text, z.text);
        if (m.conflicted) {
          conflicts.add('<gap>');
        } else {
          byLine.add('<gap>');
        }
        out.write(m.text);
      }
    } else {
      final r = mergeRegion((x as RegionPiece).records, (y as RegionPiece).records, (z as RegionPiece).records, textMerge);
      conflicts.addAll(r.conflictedKeys);
      byLine.addAll(r.mergedByLine);
      decisions.add(r);
      out.write(_emitRegion(r, x.spec));
    }
  }
  return Resolution(text: out.toString(), conflictedKeys: conflicts, mergedByLine: byLine, decisions: decisions, partial: conflicts.isNotEmpty);
}

// ---------------------------------------------------------------------------------------------------
// checks

final String _open = '<' * 7;
final String _mid = '=' * 7;
final String _close = '>' * 7;
final String _baseMark = '|' * 7;

String _norm(String line, bool comma) {
  var l = line.replaceFirst(RegExp(r'\s+$'), '');
  if (comma && l.endsWith(',')) l = l.substring(0, l.length - 1);
  return l;
}

Map<String, int> _counts(Iterable<String> lines, bool comma) {
  final m = <String, int>{};
  for (final raw in lines) {
    if (raw.trim().isEmpty) continue;
    final l = _norm(raw, comma);
    m[l] = (m[l] ?? 0) + 1;
  }
  return m;
}

/// Output lines split into the part outside conflict blocks (x), the ours sections (ho) and the
/// theirs sections (ht); the diff3 base sections and the marker lines are dropped.
({List<String> outside, List<String> ours, List<String> theirs, bool markers}) _sections(String text) {
  final outside = <String>[], ours = <String>[], theirs = <String>[];
  var mode = 0; // 0 outside, 1 ours, 2 base, 3 theirs
  var markers = false;
  for (final l in text.split('\n')) {
    if (l.startsWith('$_open ') || l == _open) {
      mode = 1;
      markers = true;
      continue;
    }
    if (mode != 0 && (l.startsWith('$_baseMark ') || l == _baseMark)) {
      mode = 2;
      continue;
    }
    if (mode != 0 && l == _mid) {
      mode = 3;
      continue;
    }
    if (mode != 0 && (l.startsWith('$_close ') || l == _close)) {
      mode = 0;
      continue;
    }
    switch (mode) {
      case 0:
        outside.add(l);
      case 1:
        ours.add(l);
      case 3:
        theirs.add(l);
      default:
        break;
    }
  }
  return (outside: outside, ours: ours, theirs: theirs, markers: markers);
}

/// V-a: per-line count bounds. Returns the offending lines (empty: ok).
List<String> checkCounts(String base, String ours, String theirs, String out, {bool comma = false}) {
  final cb = _counts(base.split('\n'), comma), co = _counts(ours.split('\n'), comma), ct = _counts(theirs.split('\n'), comma);
  final sec = _sections(out);
  final cx = _counts(sec.outside, comma);
  final ch = sec.markers ? _counts(sec.ours, comma) : const <String, int>{};
  final ck = sec.markers ? _counts(sec.theirs, comma) : const <String, int>{};
  final bad = <String>[];
  final lines = <String>{...cb.keys, ...co.keys, ...ct.keys, ...cx.keys, ...ch.keys, ...ck.keys};
  for (final l in lines) {
    final b = cb[l] ?? 0, o = co[l] ?? 0, t = ct[l] ?? 0;
    final x = cx[l] ?? 0, ho = ch[l] ?? 0, ht = ck[l] ?? 0;
    final upper = b + _max0(o - b) + _max0(t - b);
    final lower = _max0(b + _min0(o - b) + _min0(t - b) + _max2(_max0(o - b), _max0(t - b)));
    if (sec.markers) {
      final lo = x + (ho < ht ? ho : ht), hi = x + ho + ht;
      if (lo > upper || hi < lower) bad.add('"${_cut(l)}": $lo..$hi outside $lower..$upper');
      continue;
    }
    if (x < lower || x > upper) {
      bad.add('"${_cut(l)}": $x outside $lower..$upper');
      continue;
    }
    if (b <= 1 && o <= 1 && t <= 1) {
      if (o == t) {
        if (b == 0 && o == 1) {
          if (x != 1 && x != 2) bad.add('"${_cut(l)}": $x, expected 1 or 2');
        } else if (x != o) {
          bad.add('"${_cut(l)}": $x, expected $o');
        }
      } else if (o == b) {
        if (x != t) bad.add('"${_cut(l)}": $x, expected $t');
      } else if (t == b) {
        if (x != o) bad.add('"${_cut(l)}": $x, expected $o');
      }
    }
  }
  return bad;
}

int _max0(int v) => v < 0 ? 0 : v;
int _min0(int v) => v > 0 ? 0 : v;
int _max2(int a, int b) => a > b ? a : b;
String _cut(String s) => s.length <= 60 ? s : '${s.substring(0, 60)}...';

/// V-b: the non-blank lines of git's own merge outside its conflict hunks, in order, are a
/// subsequence of the output's non-blank lines. Returns a message, or null when it holds.
String? checkAgreement(String base, String ours, String theirs, String out, TextMerge textMerge, {bool comma = false}) {
  final g = textMerge(base, ours, theirs).text;
  final seq = <String>[];
  var inHunk = false;
  for (final l in g.split('\n')) {
    if (l.startsWith('$_open ') || l == _open) {
      inHunk = true;
      continue;
    }
    if (inHunk && (l.startsWith('$_close ') || l == _close)) {
      inHunk = false;
      continue;
    }
    if (inHunk) continue;
    if (l.trim().isNotEmpty) seq.add(_norm(l, comma));
  }
  final o = [for (final l in out.split('\n')) if (l.trim().isNotEmpty) _norm(l, comma)];
  var pos = 0;
  for (var idx = 0; idx < seq.length; idx++) {
    while (pos < o.length && o[pos] != seq[idx]) {
      pos++;
    }
    if (pos == o.length) return 'git line ${idx + 1} of ${seq.length} is missing or out of order: ${_cut(seq[idx])}';
    pos++;
  }
  return null;
}

/// V-c: a clean output parses again to the decisions; JSON decodes; YAML shapes hold.
String? checkStructure(FileSpec spec, String out, List<RegionResult> decisions) {
  final List<Piece> again;
  try {
    again = parseFile(out, spec.regions);
  } on Unresolvable catch (e) {
    return 'the output does not parse again: ${e.reason}';
  }
  final regions = again.whereType<RegionPiece>().toList();
  for (var i = 0; i < regions.length; i++) {
    final got = [for (final r in regions[i].records) '${r.key}$_partSep${trimEnd(r.text)}'];
    final want = [
      for (final d in decisions[i].decided)
        for (final part in d.parts) '${_baseKey(d.id)}$_partSep${trimEnd(part)}',
    ];
    if (!_listEq(got, want)) return 'the re-parsed records differ from the decisions in region ${i + 1}';
  }
  if (spec.path.endsWith('.json')) {
    try {
      final v = jsonDecode(out);
      if (v is! List) return 'the JSON is not an array';
      const keyName = 'migration';
      for (final e in v) {
        if (e is! Map || !e.containsKey(keyName)) return 'a JSON element is not a map holding "$keyName"';
      }
    } on FormatException catch (e) {
      return 'the JSON does not decode: ${e.message}';
    }
  }
  if (spec.yaml == YamlKind.registry) {
    for (final p in regions) {
      for (final r in p.records) {
        final ls = splitLines(r.text);
        for (final l in ls) {
          if (l.trim().isEmpty || l.startsWith('#') || l.startsWith('  ')) continue;
          return 'registry record ${r.key} has a line at column 0: ${_cut(l.trimRight())}';
        }
      }
    }
  }
  if (spec.yaml == YamlKind.ledger) {
    final head = RegExp(r'^[a-z0-9_]+\.dart:\s*$');
    for (final l in splitLines(out)) {
      if (l.trim().isEmpty || l.startsWith('#') || l.startsWith(' ')) continue;
      if (!head.hasMatch(l)) return 'ledger line at column 0 is not a record: ${_cut(l.trimRight())}';
    }
  }
  return null;
}

String _baseKey(String id) {
  final at = id.indexOf(_idSep);
  return at < 0 ? id : id.substring(0, at);
}

/// Runs V-a, V-b and (for a clean result) V-c. Returns the first problem, or null.
String? verifyResolution(FileSpec spec, Resolution r, {required String base, required String ours, required String theirs, required TextMerge textMerge}) {
  final comma = spec.regions.any((s) => s.sep == Sep.comma);
  final a = checkCounts(base, ours, theirs, r.text, comma: comma);
  if (a.isNotEmpty) return 'check V-a (line counts): ${a.take(3).join('; ')}';
  final b = checkAgreement(base, ours, theirs, r.text, textMerge, comma: comma);
  if (b != null) return 'check V-b (agreement with git outside its conflict hunks): $b';
  if (!r.partial) {
    final c = checkStructure(spec, r.text, r.decisions);
    if (c != null) return 'check V-c (structure): $c';
  }
  return null;
}
