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
// A2 (merge-conflict-treadmill): the output is a LOCAL BUILD PRODUCT. It is gitignored and
// untracked, line 1 is the stamp from local_indexes_lib.dart, and the write is atomic.
//
// Usage: dart run scripts/build_oi_index.dart [--lenient]
// Exit codes: 0 = written, 1 = the board is missing or unreadable, a field or status is
// missing/unknown, a header cannot be read, an id is duplicated, or no open issue parsed (fails
// closed, nothing written), 3 = validation passed but the write failed.
// `--lenient` renders an unknown-status or missing-field row FLAGGED and lists the offenders
// (the OI-68 scar below: nothing may vanish silently), and lists a header it cannot read under
// "Needs attention"; a duplicate id still fails closed, because a duplicate corrupts every
// pointer below it.

import 'dart:io';

import 'local_indexes_lib.dart';

const _boardPath = kOiBoardPath;
const _indexPath = kOiIndexPath;

final _sectionRe = RegExp(r'^## (OI-\d+)\s*—\s*(.*)$');
final _headingPrefixRe = RegExp(r'^## OI-\d+');
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
  OpenIssue(this.id, this.title, this.line, this.blockedOn, this.verified,
      {this.flag = ''});
  final String id;
  final String title;
  final int line; // 1-based, for a surgical Read(offset:) into the board
  final String blockedOn;
  final String verified;

  /// Non-empty only in a LENIENT build: why this row is flagged (an unknown or absent status).
  final String flag;
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

/// Every line that STARTS like an issue header (`## OI-<digits>`) but does not match
/// [_sectionRe], as `"line N: <the line, shortened>"`.
///
/// THE SAME SCAR, ONE STEP EARLIER. [unrecognisedStatuses], [duplicateIds] and
/// [parseOpenIssues] all begin with `_sectionRe`, so a header typed with a hyphen or an en dash
/// instead of the em dash (`## OI-409 - title`: no em dash on most keyboards), or carrying a
/// Unicode line separator in its title (`.` does not match U+2028 / U+2029), is invisible to all
/// three: the issue is absent from the index, every check passes and the generator exits 0
/// (B-pass seat 1, F8; `check_oi_numbering_unique` only notices when NO header parses). The raw
/// prefix is the discriminator, as in `countHeadingPrefixes` (oi_numbering_lib.dart).
List<String> unparseableHeadings(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  final bad = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (!_headingPrefixRe.hasMatch(lines[i])) continue;
    if (_sectionRe.hasMatch(lines[i])) continue;
    bad.add('line ${i + 1}: ${_shorten(lines[i], max: 60)} '
        '(expected `## OI-N — title` with an em dash and no line separators)');
  }
  return bad;
}

/// Every `## OI-NN` id that appears more than once, as `"OI-NN appears N times"`.
///
/// Scans ALL headers deliberately, NOT [parseOpenIssues]' OPEN-only result: the
/// board is a lookup table keyed by id, so an OPEN entry colliding with a CLOSED
/// one is the same corruption. Filtering to OPEN first would make this check
/// narrower than the claim it makes.
///
/// THE SCAR THIS EXISTS FOR — OI numbers were minted by eyeballing the board's
/// tail. Until 2026-09-12 there was no allocator; `scripts/mint_oi.sh` now
/// reserves numbers as `oi/N` branches. This check remains the LANDING backstop.
/// On 2026-08-13 six ids (OI-100..105) existed twice — once on `main`, once on a
/// branch — naming entirely different issues. The two boards **merged cleanly**:
/// git saw additions in different regions of one file, so there was no conflict
/// to notice. This generator then rendered the corrupt board and exited 0,
/// because it iterates a List and never asked whether an id repeats. Two index
/// rows share an id, and `closes-oi: OI-NN` stops naming one thing.
///
/// Recorded as OI-112, which predicted this before it happened.
List<String> duplicateIds(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  final counts = <String, int>{};
  for (final line in lines) {
    final head = _sectionRe.firstMatch(line);
    if (head == null) continue;
    final id = head.group(1)!;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  final dupes = counts.entries.where((e) => e.value > 1).toList()
    ..sort((a, b) => _num(a.key).compareTo(_num(b.key)));
  return [for (final d in dupes) '${d.key} appears ${d.value} times'];
}

/// Parses the board into its OPEN entries. Closed entries live in
/// `closed_issues.md`; unknown vocabulary is rejected by [unrecognisedStatuses]
/// before this result is ever rendered.
///
/// [includeUnknown] is for the LENIENT build only: an entry whose status is neither open nor
/// closed (including one with no `- **Status**:` line) is returned too, carrying a non-empty
/// [OpenIssue.flag], so it appears in the index as a flagged row instead of vanishing (OI-68).
List<OpenIssue> parseOpenIssues(String content, {bool includeUnknown = false}) {
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
    final word = statusWord(status);
    var flag = '';
    if (!_openWords.contains(word)) {
      if (!includeUnknown || _closedWords.contains(word)) continue;
      flag = status.isEmpty ? 'no Status line' : 'unknown status "$word"';
    }
    out.add(OpenIssue(head.group(1)!, _shorten(head.group(2)!.trim()), i + 1,
        blocked, verified,
        flag: flag));
  }
  out.sort((a, b) => _num(a.id).compareTo(_num(b.id)));
  return out;
}

int _num(String id) => int.parse(id.split('-')[1]);

/// How much of `Blocked on` / `Verified` a row renders.
///
/// These two were emitted RAW while the title was capped at 74, and the board's
/// prose grew into them: measured 2026-08-30, `Blocked on` reached 212 chars and
/// `Verified` 312, against a title max of 75. That made the index — the artifact
/// whose entire purpose is to be the CHEAP read — 18,958 bytes (~5,266 tokens),
/// 5.0x the "~950 tokens" CLAUDE.md §7 advertised. The claim was true when
/// written (`e4bc9040`, 2026-07-29: 3,759 bytes); nothing measured the drift.
///
/// 40 is chosen so the load-bearing part of each field always survives: a
/// `Verified` value leads with its date or the bare word `never`, and `never` is
/// the signal the column exists for (OI-47 read as authoritative for a day while
/// being wrong). Full text is always one anchored read away.
const int _fieldMax = 40;

/// Titles are prose and some run long; the index must stay one line per entry.
String _shorten(String s, {int max = 74}) {
  final flat = s.replaceAll(RegExp(r'\s+'), ' ').replaceAll('|', '\\|').trim();
  if (flat.length <= max) return flat;
  final cut = flat.lastIndexOf(' ', max);
  return '${flat.substring(0, cut > 0 ? cut : max).trimRight()}…';
}

/// [attention] is the LENIENT build's list of offenders (an unknown status, a missing field);
/// when non-empty it is rendered as a trailing section so nothing vanishes silently.
String renderIndex(List<OpenIssue> issues, {List<String> attention = const []}) {
  final b = StringBuffer()
    ..writeln('# Open Issues — index (auto-generated)')
    ..writeln('')
    ..writeln('**${issues.length} open.** One line each; full detail in '
        '[`open_issues.md`](open_issues.md) at the cited line, so a single entry '
        'can be read with `Read(open_issues.md, offset: <line>, limit: 60)` '
        'instead of loading the file. The first line that read returns must be '
        '`## OI-N —`; if it is not, this index is stale, so rebuild it. Closed '
        'history: [`closed_issues.md`](closed_issues.md).')
    ..writeln('')
    ..writeln('`Blocked on` answers "what can I pick up right now". `Verified` is '
        'when the entry was last checked against reality — `never` means the text '
        'has not been re-confirmed since it was filed and should be treated as a '
        'claim, not a fact. OI-47 read as authoritative for a day while being '
        'wrong; that is what this column exists to make visible.')
    ..writeln('')
    ..writeln('Re-run: `dart run scripts/build_local_indexes.dart --lenient`')
    ..writeln('')
    ..writeln('| OI | Title | Blocked on | Verified | ↦ |')
    ..writeln('|---|---|---|---|---|');
  for (final i in issues) {
    // Shortened HERE, at render, and deliberately not in the parser: the parse
    // contract is pinned by oi_index_test.dart (`captures Blocked on and
    // Verified`, plus the no-bleed cases), and a consumer other than this
    // renderer must still see the whole field.
    // A flagged row (lenient build only) says so in the title cell; an empty field renders as
    // `⚠ missing` there as well, since a strict build never reaches this point with one.
    final title = i.flag.isEmpty ? i.title : '⚠ ${i.flag}: ${i.title}';
    String cell(String v) => v.isEmpty ? '⚠ missing' : _shorten(v, max: _fieldMax);
    b.writeln('| ${i.id} | $title '
        '| ${cell(i.blockedOn)} '
        '| ${cell(i.verified)} '
        '| [:${i.line}](open_issues.md#L${i.line}) |');
  }
  if (attention.isNotEmpty) {
    b
      ..writeln('')
      ..writeln('## Needs attention (lenient build)')
      ..writeln('')
      ..writeln('These rows are flagged above; a strict build (CI, pre-commit) refuses '
          'to run until each is fixed on the board.');
    for (final a in attention) {
      b.writeln('- $a');
    }
  }
  return b.toString();
}

void main(List<String> args) {
  exit(runOiIndex(Directory.current.path, strict: !args.contains('--lenient')));
}

/// Builds the open-issues index under [root]. Returns the exit code (see the header).
///
/// Every `exit(1)` of the old script is a `return 1` here, so the orchestrator
/// (build_local_indexes.dart) can run both builders and report the worst code.
int runOiIndex(String root, {bool strict = true}) {
  final board = File('$root/$_boardPath');
  if (!board.existsSync()) {
    stderr.writeln('$_boardPath not found');
    return 1;
  }
  // The stats are captured BEFORE the board is read (local_indexes_lib.dart, R5D-8). A board
  // that cannot be read (not valid UTF-8 after a Windows editor re-saved an em dash as 0x97, a
  // permission bit) is a reported failure in both modes, not an exception: the orchestrator
  // promises to run both builders and every caller maps a code, not a stack trace.
  final digest = statDigest(root, indexInputPaths(root, kOiIndexSpec));
  final String content;
  try {
    content = board.readAsStringSync();
  } catch (e) {
    stderr.writeln('[OI-INDEX] FAIL: $_boardPath is unreadable ($e)');
    return 1;
  }

  // Header shape FIRST — a header the section regexp cannot read is invisible to every check
  // below, so the issue would vanish from the index with exit 0. See unparseableHeadings().
  final unparsed = unparseableHeadings(content);
  if (unparsed.isNotEmpty) {
    if (strict) {
      stderr.writeln('[OI-INDEX] FAIL: ${unparsed.length} header(s) in $_boardPath start '
          'like an issue but cannot be read, so they would be SILENTLY absent from the '
          'index (the OI-68 failure again):');
      for (final u in unparsed) {
        stderr.writeln('  - $u');
      }
      return 1;
    }
    stderr.writeln('[OI-INDEX] WARNING (lenient): ${unparsed.length} header(s) in '
        '$_boardPath cannot be read; they have no row, and are listed under "Needs '
        'attention" so they do not vanish:');
    for (final u in unparsed) {
      stderr.writeln('  - $u');
    }
  }

  // Vocabulary check — an unrecognised status must not be able to vanish
  // an issue from the index. See unrecognisedStatuses() for the OI-68 scar.
  final unknown = unrecognisedStatuses(content);
  if (unknown.isNotEmpty) {
    if (strict) {
      stderr.writeln('[OI-INDEX] FAIL: ${unknown.length} issue(s) in $_boardPath '
          'carry a status this index does not recognise. They would be SILENTLY '
          'absent from the index, which is exactly the failure OI-68 records:');
      for (final u in unknown) {
        stderr.writeln('  - $u');
      }
      return 1;
    }
    stderr.writeln('[OI-INDEX] WARNING (lenient): ${unknown.length} issue(s) carry a '
        'status this index does not recognise; they are rendered FLAGGED, not dropped:');
    for (final u in unknown) {
      stderr.writeln('  - $u');
    }
  }

  // Duplicate-id check — BEFORE the OPEN-only parse, deliberately. An OPEN
  // entry colliding with a CLOSED one is the same corruption, and
  // parseOpenIssues cannot see it. It fails closed in a LENIENT build too: a
  // duplicate corrupts every pointer below it, and nothing can flag that.
  final dupes = duplicateIds(content);
  if (dupes.isNotEmpty) {
    stderr.writeln('[OI-INDEX] FAIL: ${dupes.length} OI id(s) appear more than '
        'once in $_boardPath. The board is a lookup table keyed by id — two '
        'entries sharing one makes `closes-oi: OI-NN` ambiguous and the index '
        'silently wrong:');
    for (final d in dupes) {
      stderr.writeln('  - $d');
    }
    stderr.writeln('  This is the concurrent-minting collision recorded as '
        'OI-112: six ids were minted twice, on two branches, and the boards '
        'MERGED CLEANLY because the additions sat in different regions.\n'
        '  Fix: renumber the NEWER side to the next free id — and sweep EVERY '
        'branch for the ceiling, not just this one. It moves.');
    return 1;
  }

  final issues = parseOpenIssues(content, includeUnknown: !strict);

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
    if (strict) {
      stderr.writeln('[OI-INDEX] FAIL: ${bad.length} open issue(s) missing index '
          'fields in $_boardPath:');
      for (final b in bad) {
        stderr.writeln('  - $b');
      }
      return 1;
    }
    stderr.writeln('[OI-INDEX] WARNING (lenient): ${bad.length} open issue(s) '
        'missing index fields in $_boardPath; rendered FLAGGED:');
    for (final b in bad) {
      stderr.writeln('  - $b');
    }
  }
  if (issues.isEmpty) {
    stderr.writeln('[OI-INDEX] FAIL: parsed ZERO open issues from $_boardPath. '
        'Refusing to write an empty index — that is indistinguishable from a '
        'clean backlog and would hide every open item.');
    return 1;
  }

  final rc = writeLocalIndex(
      root,
      _indexPath,
      stampedOutput(
          digest, renderIndex(issues, attention: [...unparsed, ...unknown, ...bad])));
  if (rc == 0) {
    stdout.writeln('[OI-INDEX] OK: ${issues.length} open issues indexed → '
        '$_indexPath');
  }
  return rc;
}
