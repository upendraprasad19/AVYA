// scripts/build_oi_index.dart
//
// Builds docs/audit/OPEN_INDEX.md — one line per OPEN issue, so "what's
// pending?" costs ~700 tokens instead of reading the whole board.
//
// WHY THIS EXISTS, and why it is a GENERATOR rather than a hand-kept file.
// docs/audit/open_issues.md went unread for 70 days while dozens of batches
// shipped. Its own reconciliation section diagnoses that correctly — "it had no
// mechanism: no gate, no hook, no CI job referenced it. Everything in this repo
// with a gate holds; everything on intention decays" — and then claims the cure
// was `scripts/check_open_issues_reconciled.dart` plus a SessionStart injection
// in `scripts/discipline_hook.dart`. Neither was ever written: `git log --all`
// has no record of that script, and discipline_hook.dart contains zero
// references to open_issues. The board diagnosed its own disease and then
// recorded a cure that did not exist. THIS is the mechanism, wired into
// pre-commit beside the other index regens.
//
// A hand-maintained index would rot the same way — and worse, silently, since
// nothing would contradict it. Compare docs/diagnoses/INDEX.md, which sat 237
// of 344 entries empty for months because nothing ever asserted its output was
// meaningful (c4e8a2). Hence the self-check below.
//
// SIZE DISCIPLINE: one line per OI, never a block. An index as large as the
// thing it indexes has stopped being an index.
//
// Usage: dart run scripts/build_oi_index.dart
// Exit codes: 0 = written, 1 = a field is missing/placeholder (fails closed).

import 'dart:io';

const _boardPath = 'docs/audit/open_issues.md';
const _indexPath = 'docs/audit/OPEN_INDEX.md';

final _sectionRe = RegExp(r'^## (OI-\d+)\s*—\s*(.*)$');
// `\**` strips a doubly-bolded value (`- **Status**: **OPEN**`). The sibling
// parser in check_closes_oi_cited.dart already did this; the two disagreeing on
// the same board text is how one gate stays silent while the other fires.
final _fieldRe =
    RegExp(r'^-\s+\*\*(Status|Blocked on|Verified)\*\*:\s*\**\s*(.*)$');

/// Status vocabulary this index understands. Anything else is an ERROR, never a
/// silent skip — see [_classify].
const _openWords = {'OPEN', 'IN_PROGRESS'};
const _closedWords = {'CLOSED'};

/// The first word of a status line: `CLOSED · 2026-07-28 · abc123` → `CLOSED`.
String statusWord(String raw) {
  final m = RegExp(r'^\**\s*([A-Za-z_-]+)').firstMatch(raw.trim());
  return (m?.group(1) ?? '').toUpperCase().replaceAll('-', '_');
}

class OpenIssue {
  OpenIssue(this.id, this.title, this.line, this.blockedOn, this.verified);
  final String id;
  final String title;
  final int line; // 1-based, for a surgical Read(offset:) into the board
  final String blockedOn;
  final String verified;
}

/// Every `## OI-NN` header whose status this parser does NOT recognise.
///
/// THE SCAR THIS EXISTS FOR — `open_issues.md` OI-68, "read before
/// re-attempting". Two earlier attempts at this exact mechanism were built and
/// withdrawn, and the third-generation failure is recorded verbatim: *"the
/// format gate validated shape but not vocabulary — `PENDING`, `BLOCKED`,
/// `REOPENED` and a one-character `IN-PROGRESS` typo all passed the gate and
/// vanished from the digest."*
///
/// A `continue` on an unrecognised status reproduces that exactly: the entry is
/// silently absent from the index, the generator exits 0, and the backlog looks
/// complete. Unknown vocabulary is therefore an ERROR, not a skip. Adding a new
/// status word is a deliberate one-line edit to [_openWords]/[_closedWords], not
/// something a typo can do by accident.
List<String> unrecognisedStatuses(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  final bad = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final head = _sectionRe.firstMatch(lines[i]);
    if (head == null) continue;
    String? raw;
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].startsWith('## ') || lines[j].startsWith('# ')) break;
      final f = _fieldRe.firstMatch(lines[j]);
      if (f != null && f.group(1) == 'Status') {
        raw = f.group(2)!.trim();
        break;
      }
    }
    if (raw == null) {
      bad.add('${head.group(1)} (line ${i + 1}): no `- **Status**:` line found');
      continue;
    }
    final w = statusWord(raw);
    if (!_openWords.contains(w) && !_closedWords.contains(w)) {
      bad.add('${head.group(1)} (line ${i + 1}): unknown status "$w" '
          '(known: ${{..._openWords, ..._closedWords}.join(', ')})');
    }
  }
  return bad;
}

/// Parses the board into its OPEN entries. Closed entries live in
/// `closed_issues.md`; unknown vocabulary is rejected by [unrecognisedStatuses]
/// before this result is ever rendered.
List<OpenIssue> parseOpenIssues(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  final out = <OpenIssue>[];
  for (var i = 0; i < lines.length; i++) {
    final head = _sectionRe.firstMatch(lines[i]);
    if (head == null) continue;
    var status = '', blocked = '', verified = '';
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].startsWith('## ') || lines[j].startsWith('# ')) break;
      final f = _fieldRe.firstMatch(lines[j]);
      if (f == null) continue;
      final v = f.group(2)!.trim();
      switch (f.group(1)) {
        case 'Status':
          if (status.isEmpty) status = v;
        case 'Blocked on':
          if (blocked.isEmpty) blocked = v;
        case 'Verified':
          if (verified.isEmpty) verified = v;
      }
    }
    if (!_openWords.contains(statusWord(status))) continue;
    out.add(OpenIssue(
        head.group(1)!, _shorten(head.group(2)!.trim()), i + 1, blocked, verified));
  }
  out.sort((a, b) => _num(a.id).compareTo(_num(b.id)));
  return out;
}

int _num(String id) => int.parse(id.split('-')[1]);

/// Titles are prose and some run long; the index must stay one line per entry.
String _shorten(String s, {int max = 74}) {
  final flat = s.replaceAll(RegExp(r'\s+'), ' ').replaceAll('|', '\\|').trim();
  if (flat.length <= max) return flat;
  final cut = flat.lastIndexOf(' ', max);
  return '${flat.substring(0, cut > 0 ? cut : max).trimRight()}…';
}

String renderIndex(List<OpenIssue> issues) {
  final b = StringBuffer()
    ..writeln('# Open Issues — index (auto-generated)')
    ..writeln('')
    ..writeln('**${issues.length} open.** One line each; full detail in '
        '[`open_issues.md`](open_issues.md) at the cited line, so a single entry '
        'can be read with `Read(open_issues.md, offset: <line>, limit: 60)` '
        'instead of loading the file. Closed history: '
        '[`closed_issues.md`](closed_issues.md).')
    ..writeln('')
    ..writeln('`Blocked on` answers "what can I pick up right now". `Verified` is '
        'when the entry was last checked against reality — `never` means the text '
        'has not been re-confirmed since it was filed and should be treated as a '
        'claim, not a fact. OI-47 read as authoritative for a day while being '
        'wrong; that is what this column exists to make visible.')
    ..writeln('')
    ..writeln('Re-run: `dart run scripts/build_oi_index.dart`')
    ..writeln('')
    ..writeln('| OI | Title | Blocked on | Verified | ↦ |')
    ..writeln('|---|---|---|---|---|');
  for (final i in issues) {
    b.writeln('| ${i.id} | ${i.title} | ${i.blockedOn} | ${i.verified} | '
        '[:${i.line}](open_issues.md#L${i.line}) |');
  }
  return b.toString();
}

void main() {
  final board = File(_boardPath);
  if (!board.existsSync()) {
    stderr.writeln('$_boardPath not found');
    exit(1);
  }
  final content = board.readAsStringSync();

  // Vocabulary check FIRST — an unrecognised status must not be able to vanish
  // an issue from the index. See unrecognisedStatuses() for the OI-68 scar.
  final unknown = unrecognisedStatuses(content);
  if (unknown.isNotEmpty) {
    stderr.writeln('[OI-INDEX] FAIL: ${unknown.length} issue(s) in $_boardPath '
        'carry a status this index does not recognise. They would be SILENTLY '
        'absent from the index, which is exactly the failure OI-68 records:');
    for (final u in unknown) {
      stderr.writeln('  - $u');
    }
    exit(1);
  }

  final issues = parseOpenIssues(content);

  // SELF-CHECK — fail closed. docs/diagnoses/INDEX.md sat 70% empty for months
  // because its generator exited 0 while writing placeholders. An index nobody
  // validates is indistinguishable from a working one right up until it is
  // needed.
  final bad = <String>[];
  for (final i in issues) {
    if (i.title.isEmpty) bad.add('${i.id}: empty title');
    if (i.blockedOn.isEmpty) {
      bad.add('${i.id}: missing `- **Blocked on**:` (use `none` if nothing '
          'blocks it)');
    }
    if (i.verified.isEmpty) {
      bad.add('${i.id}: missing `- **Verified**:` (use `never` if it has not '
          'been re-checked since filing)');
    }
  }
  if (bad.isNotEmpty) {
    stderr.writeln('[OI-INDEX] FAIL: ${bad.length} open issue(s) missing index '
        'fields in $_boardPath:');
    for (final b in bad) {
      stderr.writeln('  - $b');
    }
    exit(1);
  }
  if (issues.isEmpty) {
    stderr.writeln('[OI-INDEX] FAIL: parsed ZERO open issues from $_boardPath. '
        'Refusing to write an empty index — that is indistinguishable from a '
        'clean backlog and would hide every open item.');
    exit(1);
  }

  File(_indexPath).writeAsStringSync(renderIndex(issues));
  stdout.writeln('[OI-INDEX] OK: ${issues.length} open issues indexed → '
      '$_indexPath');
}
