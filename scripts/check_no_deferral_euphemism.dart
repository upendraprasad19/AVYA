// scripts/check_no_deferral_euphemism.dart
//
// Gate (discipline audit 2026-06-27): flag deferral-EUPHEMISM phrases in the
// STAGED additions of Markdown docs (plans, reviews, audits, diagnoses).
//
// CLAUDE.md §4.2 bans the SEMANTIC of deferral, not just the literal word
// "defer". The recurring failure (feedback_mistake_dedicated_batch_is_defer.md,
// ≥8 instances) is re-wrapping a deferral as a "dedicated batch" /
// "test-maintenance batch" / "next-batch baseline" / "its own careful batch".
// This gate is a commit-time backstop to the prompt-time hot-set
// (scripts/discipline_hook.dart) — it catches a deferral being WRITTEN into a
// plan/review doc.
//
// Scope: TWO scans, widened 2026-08-17 (diagnose d3f1a7).
//   1. staged ADDED lines (git diff --cached) in *.md — the original scan.
//   2. a FULL sweep of CLAUDE.md + every .claude/skills/**/SKILL.md.
// Scan 1 alone protects the FUTURE and can never see a violation older than the
// gate, no matter how often the file is touched. That is not hypothetical: a
// deferral instruction sat inside .claude/skills/update-docs/SKILL.md — the
// skill that walks the end-of-batch checklist — invisible for as long as the
// gate had existed. Scan 2 is deliberately NOT repo-wide: diagnose-docs,
// plan-reviews, retrospectives and closure YAMLs legitimately quote the banned
// phrases when recording a past violation, and sweeping them would make honest
// bug-history writing impossible.
// BOTH scans honour the `deu-quote` exemption (_isQuotingTheBan). Applying it to
// only one made a marked line pass the sweep and then fail the diff, i.e.
// correcting a §4.2 violation and recording what it used to say became
// unpublishable.
//
// HARD-FAIL since the baseline soak cleared 2026-06-28. pre-commit.sh:122
// invokes it with no --warn-only flag. (The header previously still described
// the soak window as pending — corrected in a3d7b1, which promoted this file to
// platform tier; leaving a stale comment in a platform-tier file would have
// made fixing it later cost a full review round.)
//
// PHRASE LIST LIVES IN docs/deferral_euphemisms.yaml, NOT HERE (a3d7b1).
// This script is platform tier, so changing how matching works needs a
// plan-review record + B-pass. The list is data and must stay cheap to extend —
// at feature tier, adding a banned phrase is a one-line edit. A gate whose
// phrase list is expensive to grow ossifies while violations invent new
// phrasings.
//
// Exit 0 = clean (or --warn-only). Exit 1 = euphemism found (hard-fail mode),
// or the phrase file is missing/unparseable (fails CLOSED — see _loadPhrases).

import 'dart:convert';
import 'dart:io';

const _phrasesPath = 'docs/deferral_euphemisms.yaml';

/// Reads the phrase list from [_phrasesPath].
///
/// FAILS CLOSED. A missing, unreadable or empty file exits non-zero rather than
/// returning an empty list — an empty list would make the gate pass everything
/// forever while looking healthy, which is indistinguishable from working. That
/// silent-disable shape is the exact failure this gate's own promotion to
/// platform tier exists to prevent, so it must not be reachable by deleting a
/// data file at feature tier.
///
/// Deliberately a minimal line parser, not a YAML dependency: this runs in the
/// pre-commit hot path and the format is a flat list of quoted strings.
List<String> _loadPhrases(String tag) {
  final f = File(_phrasesPath);
  if (!f.existsSync()) {
    stderr.writeln('$tag FAIL: $_phrasesPath not found. The phrase list is '
        'required — an absent file would silently disable this gate.');
    exit(1);
  }
  final phrases = <String>[];
  var inPhrases = false;
  for (final raw in f.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line == 'phrases:') {
      inPhrases = true;
      continue;
    }
    if (!inPhrases) continue;
    if (!line.startsWith('-')) break; // next top-level key ends the list
    var v = line.substring(1).trim();
    if (v.length >= 2 &&
        ((v.startsWith("'") && v.endsWith("'")) ||
            (v.startsWith('"') && v.endsWith('"')))) {
      v = v.substring(1, v.length - 1);
    }
    if (v.isNotEmpty) phrases.add(v.toLowerCase());
  }
  if (phrases.isEmpty) {
    stderr.writeln('$tag FAIL: $_phrasesPath parsed to ZERO phrases. Refusing '
        'to run as a no-op gate — fix the file rather than shipping a gate '
        'that passes everything.');
    exit(1);
  }
  return phrases;
}

/// True when a line CITES the ban rather than instructing a deferral.
///
/// The full-file sweep hit an obvious problem the moment it ran: §4.2 of
/// CLAUDE.md ENUMERATES the banned phrases, and several skills quote the rule
/// verbatim. 12 of the first 14 hits were the rule describing itself. A gate
/// that cannot read its own charter without failing is not usable.
///
/// The marker is EXPLICIT and greppable rather than a cleverness heuristic:
/// `deu-quote` anywhere on the line exempts it. The three organic markers below
/// (`banned`, `ban is on`, and a reference to the codifying feedback file) are
/// included because they are unambiguous and already present at the real
/// citation sites — but a new exemption should use `deu-quote` so it is
/// auditable by `grep -rn deu-quote`, the same self-attested-but-visible model
/// as rule 21's `presence_only:` and rule 24's ledger.
/// ONLY the explicit marker exempts a line.
///
/// The three "organic" markers this used to accept -- `banned`, `ban is on`,
/// and a reference to the codifying feedback file -- were removed on 2026-08-17
/// after review round 1 demonstrated the hole with a control:
///
///   "Roll the old path deletion into a follow-up batch."          -> FAIL (correct)
///   "That style is banned, so roll the old path deletion into a
///    follow-up batch."                                            -> PASS (wrong)
///
/// The word `banned` appears constantly in §4.2 and across the skills -- it is
/// the vocabulary of the rule itself -- so any real deferral instruction written
/// in the same sentence as the word was invisible. An exemption keyed on a word
/// the governed text uses habitually is not an exemption, it is an off switch.
///
/// `deu-quote` is deliberately a token nobody writes by accident, and every use
/// is auditable with `grep -rn deu-quote`. Same self-attested-but-visible model
/// as rule 21's `presence_only:` and rule 24's ledger.
bool _isQuotingTheBan(String line) =>
    line.toLowerCase().contains('deu-quote');

/// The documents that INSTRUCT an agent, swept in full rather than by diff.
///
/// Not repo-wide, and the exclusion is the point: diagnose-docs, plan-reviews,
/// retrospectives and closure YAMLs legitimately quote the banned phrases when
/// recording a past violation. Sweeping them would make honest bug-history
/// writing impossible and would train everyone to phrase around the gate.
///
/// `SKILL.md` files are discovered dynamically -- a hardcoded roster is exactly
/// the drift this repo has been bitten by before (see node 23 of
/// .claude/skills/update-docs/SKILL.md, where a hardcoded skill count went
/// stale and the fix was to make `ls` the source of truth).
List<String> _governingDocs() {
  final out = <String>['CLAUDE.md'];
  final skills = Directory('.claude/skills');
  if (skills.existsSync()) {
    for (final e in skills.listSync(recursive: true, followLinks: false)) {
      if (e is File && e.path.replaceAll(r'\', '/').endsWith('/SKILL.md')) {
        out.add(e.path.replaceAll(r'\', '/'));
      }
    }
  }
  out.sort();
  return out;
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[Gate-DEU WARN]' : '[Gate-DEU]';

  // Loaded BEFORE the staged-diff check on purpose: a missing or empty phrase
  // file must fail loudly everywhere the gate runs, including contexts with no
  // staged diff. Otherwise deleting it would look like a clean pass.
  final euphemisms = _loadPhrases(tag);

  // Staged additions only, no color, zero context lines.
  // stdoutEncoding: utf8 is load-bearing. Process.runSync defaults to
  // systemEncoding, which on Windows decodes this repo's em-dashes (U+2014) as
  // cp1252 mojibake -- every reported violation line rendered as `â€”` instead
  // of `—`, making the gate's own output harder to act on than the source it
  // quotes. Same defect class that made check_oi_numbering_unique.dart report
  // PASS against a board it had failed to parse (diagnose d3f1a7).
  final result = Process.runSync(
    'git',
    ['diff', '--cached', '--unified=0', '--no-color', '--', '*.md'],
    stdoutEncoding: utf8,
  );
  // A failed `git diff --cached` means the STAGED scan cannot run. It must NOT
  // skip the full-file sweep below, which needs no git at all and exists
  // precisely to see what a staged diff cannot. The original `exit(0)` here
  // short-circuited the whole gate: run it outside a git repo, or with git
  // unavailable, and it printed SKIP while the governing documents went
  // unread. Review round 1 confirmed it live.
  final diffUnavailable = result.exitCode != 0;
  if (diffUnavailable) {
    stdout.writeln('$tag NOTE: git diff --cached unavailable — the staged-diff '
        'scan did not run. The full-file sweep of the governing documents '
        'still runs below.');
  }

  final diff = diffUnavailable ? '' : result.stdout.toString();
  final violations = <String>[];
  String currentFile = '';
  for (final line in const LineSplitter().convert(diff)) {
    if (line.startsWith('+++ b/')) {
      currentFile = line.substring('+++ b/'.length).trim();
      continue;
    }
    if (_isGeneratedMirror(currentFile)) continue;
    // Added content lines start with a single '+'; skip the '+++' header and
    // any line that is just the marker.
    if (!line.startsWith('+') || line.startsWith('+++')) continue;
    final added = line.substring(1);
    // The SAME quoting exemption the full-file sweep uses. Applying it to only
    // one of the two scans meant a `deu-quote`-marked line passed the sweep and
    // was then flagged by the diff -- so correcting a §4.2 violation, and
    // recording what it used to say, became unpublishable. A marker that does
    // not hold on every path this gate reads is not an exemption.
    if (_isQuotingTheBan(added)) continue;
    final lower = added.toLowerCase();
    for (final phrase in euphemisms) {
      if (lower.contains(phrase)) {
        violations.add('$currentFile:  "$phrase"  →  ${_trim(added)}');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // FULL-FILE SWEEP of the governing documents.
  //
  // The staged-diff scan above protects the FUTURE and can never see the PAST:
  // a violation committed before this gate existed is invisible to it forever,
  // no matter how many times the file is touched afterwards. That is not
  // hypothetical. `.claude/skills/update-docs/SKILL.md` instructed writing a
  // "Follow-ups deferred" section -- the exact semantic §4.2 bans -- inside the
  // skill that walks the end-of-batch checklist, and it sat there unseen
  // because the gate only ever read `git diff --cached`.
  //
  // Scoped deliberately to the files that TELL AN AGENT WHAT TO DO: the skills
  // and the root CLAUDE.md. A repo-wide sweep would hit diagnose-docs and
  // retrospectives, which legitimately QUOTE the banned phrases when recording
  // a past violation -- exactly what this file's own header does.
  // COUNT WHAT WAS ACTUALLY READ, and say so in the verdict.
  //
  // `_governingDocs()` yields CLAUDE.md plus every discovered SKILL.md, and
  // both sources can silently come back empty: run from the wrong directory and
  // `CLAUDE.md` does not exist, `.claude/skills` does not exist, the list is
  // ['CLAUDE.md'], the `existsSync` guard skips it, and the gate printed
  // "PASS: ... nor in the governing skill/CLAUDE.md set" having read ZERO
  // files. Review round 1 confirmed that live. An empty input set reported
  // nothing in the same colour as nothing-wrong -- the exact shape
  // feedback_green_check_input_set_width names, in the gate modified alongside
  // the one that built _parseStrict to avoid it.
  var swept = 0;
  final missing = <String>[];
  for (final path in _governingDocs()) {
    final f = File(path);
    if (!f.existsSync()) {
      missing.add(path);
      continue;
    }
    swept++;
    final lines = const LineSplitter().convert(f.readAsStringSync());
    for (var i = 0; i < lines.length; i++) {
      if (_isQuotingTheBan(lines[i])) continue;
      final lower = lines[i].toLowerCase();
      for (final phrase in euphemisms) {
        if (lower.contains(phrase)) {
          violations.add('$path:${i + 1}:  "$phrase"  →  ${_trim(lines[i])}');
        }
      }
    }
  }

  // ORDER MATTERS: report violations FIRST.
  //
  // The first version of this block exited on `swept == 0` before looking at
  // `violations`, which meant a repo with no CLAUDE.md swallowed the STAGED
  // findings the scan had already made — turning a real FAIL into an exit 0.
  // Caught by this file's own positive control, which is why that control
  // exists. An "I checked nothing" report must never outrank "I found
  // something".
  if (violations.isEmpty && swept == 0) {
    // Never a PASS. Fails OPEN (a gate must not wedge a commit because the
    // working directory is unexpected) but says plainly that it checked nothing.
    stderr.writeln('$tag UNDETERMINED (passing): swept ZERO governing '
        'documents — CLAUDE.md and .claude/skills/**/SKILL.md were all absent '
        'from ${Directory.current.path}. The staged-diff scan '
        '${diffUnavailable ? "did not run either" : "ran and found nothing"}. '
        'This is NOT a pass; the governing set was not read.');
    exit(0);
  }

  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: no deferral euphemisms in '
        '${diffUnavailable ? "(staged scan skipped)" : "staged Markdown additions"}, '
        'nor in the $swept governing document(s) swept in full'
        '${missing.isEmpty ? "" : " (${missing.length} listed-but-absent)"}.');
    exit(0);
  }

  final levelTag = warnOnly ? '$tag WARN' : '$tag FAIL';
  stderr.writeln(
      '$levelTag: ${violations.length} deferral-euphemism phrase(s) in staged docs.');
  stderr.writeln('CLAUDE.md §4.2 bans the SEMANTIC of deferral, not just "defer".');
  stderr.writeln('If the work is genuinely out of scope, give it a terminal state');
  stderr.writeln('(closed_in_commit / upstream_blocked / blocked_on_user / verified_clean),');
  stderr.writeln('not a "next batch". See feedback_mistake_dedicated_batch_is_defer.md.');
  stderr.writeln('');
  for (final v in violations.take(15)) {
    stderr.writeln('  - $v');
  }
  if (violations.length > 15) {
    stderr.writeln('  ... and ${violations.length - 15} more');
  }
  exit(warnOnly ? 0 : 1);
}

String _trim(String s) {
  final t = s.trim();
  return t.length <= 100 ? t : '${t.substring(0, 100)}…';
}

/// Auto-generated index files that MIRROR prose living in other tracked docs.
///
/// Why they are exempt. This gate scans staged ADDED lines. A generated index
/// is rewritten wholesale whenever its generator runs, so every line it
/// contains becomes an "addition" — including sentences quoted verbatim from
/// historical documents that the current commit did not write and must not
/// rewrite. `docs/diagnoses/INDEX.md` mirrors `docs/diagnoses/*.md`, and bug
/// `7ad0e0` (2026-05-11) legitimately records that an EARLIER batch deferred
/// work; that diagnose-doc exists precisely because the deferral was then
/// closed. Gating the mirror made an unrelated commit fail for a phrase it
/// merely re-rendered, and the only "fixes" available were to falsify a
/// historical record or bypass the hook.
///
/// The source documents are still scanned when they themselves are staged, so
/// nothing is lost: this removes a double-report, not the coverage. Kept to an
/// explicit list rather than a glob so it cannot quietly widen into a general
/// escape hatch.
bool _isGeneratedMirror(String path) {
  const generated = <String>{
    'docs/diagnoses/INDEX.md',
    'docs/adr/INDEX.md',
    'docs/incidents/INDEX.md',
    'docs/handbook/INDEX.md',
    // Regenerated by scripts/build_oi_index.dart and `git add`ed at
    // pre-commit.sh:71 — BEFORE this gate runs at :139 — so every open entry's
    // title and `Blocked on` prose re-renders as an "added" line on any commit
    // that touches the board at all. Those fields are exactly where blocking
    // rationale gets written, which is exactly where a banned phrase would
    // legitimately appear. Missing from the first draft of this very list.
    'docs/audit/OPEN_INDEX.md',
  };
  // git's `+++ b/<path>` is always forward-slashed, on every platform.
  return generated.contains(path.trim());
}
