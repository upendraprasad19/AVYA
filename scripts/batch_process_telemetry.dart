// scripts/batch_process_telemetry.dart — batch-close process telemetry printer.
// Called by scripts/batch_close_hook.dart after the checklist is built; its
// stdout is appended to the hook's block reason. Print-only: ANY failure
// prints nothing and the hook carries on (telemetry must never break batch
// close — same contract as the hook itself).
import 'dart:io';

import 'batch_process_telemetry_lib.dart';

ProcessResult? _git(List<String> args) {
  try {
    return Process.runSync('git', args, stdoutEncoding: systemEncoding);
  } catch (_) {
    return null;
  }
}

String? _gitOut(List<String> args) {
  final r = _git(args);
  if (r == null || r.exitCode != 0) return null;
  return (r.stdout as String).trim();
}

/// Files under [dir] modified within the last 7 days; when [match] is given,
/// only files whose content contains it. Missing/unreadable dir counts 0.
int _recentCount(Directory dir, DateTime cutoff, {RegExp? match}) {
  try {
    if (!dir.existsSync()) return 0;
    var n = 0;
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      try {
        if (e.statSync().modified.isBefore(cutoff)) continue;
        if (match != null && !match.hasMatch(e.readAsStringSync())) continue;
        n++;
      } catch (_) {}
    }
    return n;
  } catch (_) {
    return 0;
  }
}

void main() {
  try {
    final root = _gitOut(['rev-parse', '--show-toplevel']);
    if (root == null) return;

    final branch = _gitOut(['branch', '--show-current']) ?? '';
    var record = const PlanReviewStats(reviewRounds: 0, mechanicalOnly: false);
    if (branch.isNotEmpty) {
      try {
        // Same slug shape as docs/plan-reviews/<branch>.md ('/'→'-').
        final f =
            File('$root/docs/plan-reviews/${branch.replaceAll('/', '-')}.md');
        if (f.existsSync()) record = parsePlanReviewRecord(f.readAsStringSync());
      } catch (_) {}
    }

    int? openEscapes;
    try {
      final ledger = File('$root/docs/audit/s_tier_escapes.yaml');
      if (ledger.existsSync()) {
        openEscapes = parseEscapeLedger(ledger.readAsStringSync()).openEscapes;
      }
    } catch (_) {}

    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final diagnoses = Directory('$root/docs/diagnoses');
    stdout.writeln(composeReport(
      record: record,
      openEscapes: openEscapes,
      recentDiagnoseDocs: _recentCount(diagnoses, cutoff),
      sTierDocs: _recentCount(diagnoses, cutoff,
          match: RegExp(r'^tier:\s*s_fix', multiLine: true)),
      recentReviewFiles: _recentCount(Directory('$root/docs/reviews'), cutoff),
    ));
  } catch (_) {
    // Telemetry must never break batch close.
  }
}
