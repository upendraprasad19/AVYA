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
// Ships --warn-only (§4.11 gates-before-refactor baseline window). Flip to
// hard-fail after a 24h soak by removing the explicit --warn-only invocation
// from pre-commit.sh + test.yml and dropping it from their skip allowlists.
//
// Exit 0 = clean (or --warn-only). Exit 1 = euphemism found (hard-fail mode).

import 'dart:convert';
import 'dart:io';

/// High-signal, deferral-as-scope-cut phrases. Curated to be distinctive enough
/// to rarely false-positive — bare "defer"/"deferred" is intentionally EXCLUDED
/// (too common in legit technical prose: "deferred to pre-push", "deferred
/// init", etc.). Lowercased; matched case-insensitively.
const List<String> _euphemisms = [
  'dedicated batch',
  'follow-up batch',
  'followup batch',
  'follow up batch',
  'test-maintenance batch',
  'test maintenance batch',
  'cleanup batch',
  'clean-up batch',
  'next-batch baseline',
  'baseline for next batch',
  'documented baseline for next batch',
  'its own careful batch',
  'own careful batch',
  'gradual population',
  'can be folded into',
  'folded into a future',
  'fresh session pickup',
  'responsible handoff',
  'defer-friendly',
  'minimum viable ship',
  'responsible focus management',
  'contingency to pull out',
];

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[Gate-DEU WARN]' : '[Gate-DEU]';

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
    // Added content lines start with a single '+'; skip the '+++' header and
    // any line that is just the marker.
    if (!line.startsWith('+') || line.startsWith('+++')) continue;
    final added = line.substring(1);
    final lower = added.toLowerCase();
    for (final phrase in _euphemisms) {
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
