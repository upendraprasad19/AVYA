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
// Scope: only staged ADDED lines (git diff --cached) in *.md files. Scanning
// additions (not whole files) means pre-existing prose that merely DESCRIBES
// the rule (e.g. this gate's own doc, feedback files) is not re-flagged.
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

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[Gate-DEU WARN]' : '[Gate-DEU]';

  // Loaded BEFORE the staged-diff check on purpose: a missing or empty phrase
  // file must fail loudly everywhere the gate runs, including contexts with no
  // staged diff. Otherwise deleting it would look like a clean pass.
  final euphemisms = _loadPhrases(tag);

  // Staged additions only, no color, zero context lines.
  final result = Process.runSync(
    'git',
    ['diff', '--cached', '--unified=0', '--no-color', '--', '*.md'],
  );
  if (result.exitCode != 0) {
    // No staged diff / not a git repo / git unavailable → never block.
    stdout.writeln('$tag SKIP: git diff --cached unavailable.');
    exit(0);
  }

  final diff = result.stdout.toString();
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
    final lower = added.toLowerCase();
    for (final phrase in euphemisms) {
      if (lower.contains(phrase)) {
        violations.add('$currentFile:  "$phrase"  →  ${_trim(added)}');
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: no deferral euphemisms in staged Markdown additions.');
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
