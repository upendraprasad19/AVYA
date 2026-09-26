// scripts/check_context_artifact_budget.dart
//
// Guards the size of the artifacts an AGENT loads, the way
// `check_apk_size_within_bounds.dart` (Gate 13) guards the artifact USERS
// download. Same shape on purpose: recorded baselines in a JSON under
// `backups/`, a tolerance band, and `--record` to re-baseline deliberately.
//
// Rationale, bands, and the four reasons this drift went unseen for a month
// live in `scripts/context_budget_lib.dart` — the pure half, where they can be
// unit-tested.
//
// Usage:
//   dart run scripts/check_context_artifact_budget.dart              # check
//   dart run scripts/check_context_artifact_budget.dart --record     # re-baseline
//   dart run scripts/check_context_artifact_budget.dart --warn-only  # never exit 1
//   dart run scripts/check_context_artifact_budget.dart --record --force-record
//                                                       # re-baseline OVER a hard breach
//
// Exit codes: 0 = ok / warn / skipped, 1 = past a hard band, or a --record
// refused because it would have blessed one.
//
// WHERE THE WARN TIER IS ACTUALLY VISIBLE, because it is not where you would
// assume. `scripts/pre-commit.sh:368` runs every gate as
// `"$DART_BIN" run "$GATE" >/dev/null 2>&1`, so locally a PASS-with-WARN prints
// NOTHING and the soft band gives no local notice at all. CI does NOT suppress
// (`.github/workflows/test.yml:264` is a bare `dart run "$GATE"`), so it does
// surface there — but per CLAUDE.md §0 that job runs only on push to
// main/develop and on PRs, which most working branches never get. Treat the
// soft band as a CI-and-merge signal, never a local one. The §5 checklist row
// is what carries it in between.
//
// FAILS OPEN by construction. A missing baseline file, an unreadable artifact,
// or unparseable JSON all report SKIPPED and exit 0. A hygiene gate must never
// be able to wedge every commit in the repo.

import 'dart:convert';
import 'dart:io';

import 'context_budget_lib.dart';

/// The always-loaded / always-read set.
///
/// Adding a doc here is how it enters the budget; it reports SKIPPED until a
/// `--record` run gives it a baseline, which is why `evaluateAll` unions the key
/// sets rather than iterating the baselines alone.
const List<String> kTrackedArtifacts = [
  'CLAUDE.md',
  'docs/audit/OPEN_INDEX.md',
  'docs/audit/open_issues.md',
];

const String kBaselinePath = 'backups/context_artifact_sizes.json';

void main(List<String> args) {
  final record = args.contains('--record');
  final warnOnly = args.contains('--warn-only');
  final forceRecord = args.contains('--force-record');
  final root = Directory.current.path;

  // ── baselines (absent / unreadable / malformed → all empty, never fatal) ──
  var baselines = <String, int>{};
  final baselineFile = File('$root/$kBaselinePath');
  if (baselineFile.existsSync()) {
    try {
      final raw = jsonDecode(baselineFile.readAsStringSync());
      if (raw is Map) {
        for (final e in raw.entries) {
          final v = e.value;
          final bytes = v is Map ? v['bytes'] : null;
          if (bytes is int) baselines[e.key.toString()] = bytes;
        }
      } else {
        // VALID JSON, WRONG SHAPE — e.g. a top-level array. Round 1 found this
        // silently no-opped, so every artifact then reported "no baseline
        // recorded — run with --record" and the operator would go looking for a
        // missing baseline rather than a malformed one. Failing open is right;
        // failing open QUIETLY, with a message that names the wrong cause, is
        // not. Same family as feedback_bad_news_vs_no_news.
        stdout.writeln('[context-budget] SKIPPED — $kBaselinePath is valid JSON '
            'but not an object (got ${raw.runtimeType}); treating every '
            'artifact as unbaselined. Re-create it with --record.');
      }
    } catch (_) {
      stdout.writeln('[context-budget] SKIPPED — $kBaselinePath unreadable or '
          'malformed; treating every artifact as unbaselined.');
      baselines = {};
    }
  }

  // ── measure ───────────────────────────────────────────────────────────────
  final actuals = <String, int?>{};
  for (final p in kTrackedArtifacts) {
    try {
      final f = File('$root/$p');
      actuals[p] = f.existsSync() ? f.lengthSync() : null;
    } catch (_) {
      actuals[p] = null;
    }
  }

  final findings = evaluateAll(baselines, actuals);


  // ── report ────────────────────────────────────────────────────────────────
  //
  // ⚠ The band NAMED here must be the band actually crossed. Review round 2
  // caught these branches hardcoding kSoftBand/kHardBand and the verb "grew"
  // while the LOGIC had already been fixed to two-sided bands — so the very
  // fixture round 1 built to expose the missing shrink floor (a CLAUDE.md
  // truncated to 0 B) printed "grew past the hard band ... Past the 50% hard
  // band", naming a threshold it had not crossed in a direction it had not
  // moved. Fixing a classifier and leaving its report describing the old
  // classifier is the same defect as P2-6 in the commit that introduced it:
  // failing correctly while explaining it wrong.
  for (final f in findings) {
    final shrank = (f.drift ?? 0) < 0;
    final verb = shrank ? 'shrank' : 'grew';
    final softPct = ((shrank ? kSoftShrink : kSoftBand).abs() * 100).round();
    final hardPct = ((shrank ? kHardShrink : kHardBand).abs() * 100).round();
    switch (f.status) {
      case BudgetStatus.skipped:
        stdout.writeln('[context-budget] SKIPPED ${f.path} — ${f.reason}');
      case BudgetStatus.warn:
        stdout.writeln('[context-budget] WARN ${f.path} '
            '${f.baseline} → ${f.actual} B (${f.driftLabel}, '
            '~${approxTokens(f.actual!)} tok). It $verb past the $softPct% soft '
            '${shrank ? 'shrink floor' : 'band'}. Not blocking — but this is the '
            'drift nobody was measuring when OPEN_INDEX.md reached 5x its '
            'advertised size.');
      case BudgetStatus.fail:
        stderr.writeln('[context-budget] FAIL ${f.path} '
            '${f.baseline} → ${f.actual} B (${f.driftLabel}, '
            '~${approxTokens(f.actual!)} tok). It $verb past the $hardPct% hard '
            '${shrank ? 'shrink floor' : 'band'}.');
      case BudgetStatus.ok:
        break;
    }
  }

  // ── record mode — DELIBERATELY AFTER THE REPORT ───────────────────────────
  //
  // Placement is the whole guard. The first version recorded BEFORE evaluating,
  // so `--record` blessed whatever was on disk with no old->new comparison and
  // no mention of the pass/warn/fail it had just computed. Worse than silent:
  // the FAIL path PRINTS this exact command as its escape hatch, so an operator
  // who trips the new shrink floor would erase the evidence with one paste and
  // see nothing describing what they accepted.
  //
  // `check_apk_size_within_bounds.dart` — the gate this one is modelled on —
  // does not have that hole, and not by documentation: its `exit(1)` at :119
  // sits ABOVE its record step at :129, so on a breach the record branch is
  // structurally UNREACHABLE. This gate claimed to mirror Gate 13 while
  // inverting the one ordering that made Gate 13 safe. Caught by the B-pass;
  // rounds 1 and 2 both read this file and did not.
  if (record) {
    if (anyBlocking(findings) && !forceRecord) {
      stderr.writeln('');
      stderr.writeln('[context-budget] REFUSING to record — at least one '
          'artifact is past a HARD band (see FAIL above). Recording now would '
          'make the breach the new normal and leave no trace of it.');
      stderr.writeln('  If that is genuinely what you want — a deliberate '
          'split into modules, say — repeat with --force-record.');
      exit(1);
    }
    final out = <String, dynamic>{};
    final stamp = DateTime.now().toUtc().toIso8601String();
    for (final f in findings) {
      if (f.actual == null) continue;
      out[f.path] = {'bytes': f.actual, 'recorded_at': stamp};
    }
    baselineFile
      ..createSync(recursive: true)
      ..writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
    stdout.writeln('[context-budget] RECORDED ${out.length} baseline(s) '
        '→ $kBaselinePath');
    for (final f in findings.where((f) => f.actual != null)) {
      final was = f.baseline == null ? 'new ' : '${f.baseline} B -> ';
      stdout.writeln('    ${f.path}  $was${f.actual} B  '
          '(~${approxTokens(f.actual!)} tok, ${f.driftLabel})');
    }
    exit(0);
  }

  final blocking = anyBlocking(findings);
  if (!blocking) {
    final ok = findings.where((f) => f.status == BudgetStatus.ok).length;
    final warn = findings.where((f) => f.status == BudgetStatus.warn).length;
    final skip = findings.where((f) => f.status == BudgetStatus.skipped).length;
    stdout.writeln('[context-budget] PASS: $ok within band, $warn warned, '
        '$skip skipped.');
    exit(0);
  }

  if (warnOnly) {
    stdout.writeln('[context-budget] --warn-only: hard-band breach(es) '
        'reported, exiting 0. Never use this on main.');
    exit(0);
  }

  stderr.writeln('');
  stderr.writeln('An always-loaded artifact moved past a hard band — see the '
      'FAIL line(s) above for the direction and the threshold. This is a '
      'cumulative check, not a diff check — no single commit looks guilty, '
      'which is exactly why nothing else catches it.');
  stderr.writeln('If the change is intended — including a deliberate split of a '
      'big doc into modules, which is a legitimate large SHRINK — re-baseline:');
  stderr.writeln('    dart run scripts/check_context_artifact_budget.dart --record');
  exit(1);
}
