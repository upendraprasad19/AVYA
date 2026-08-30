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
//
// Exit codes: 0 = ok / warn / skipped, 1 = past the hard band.
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

  // ── record mode ───────────────────────────────────────────────────────────
  if (record) {
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
      stdout.writeln('    ${f.path}  ${f.actual} B  (~${approxTokens(f.actual!)} tok)');
    }
    exit(0);
  }

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
