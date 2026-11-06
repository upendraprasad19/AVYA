// scripts/batch_process_telemetry.dart — batch-close process telemetry printer.
// Called by scripts/batch_close_hook.dart after the checklist is built; its
// stdout is appended to the hook's block reason. Print-only: ANY failure
// prints nothing and the hook carries on (telemetry must never break batch
// close — same contract as the hook itself).
import 'dart:io';

import 'batch_process_telemetry_lib.dart';

// _git/_gitOut mirror the twins in batch_close_hook.dart — fix one, check the other.
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

/// Markdown files under [dir] modified within the last 7 days. Null when the
/// DIRECTORY itself is missing/unreadable (unknown, NOT 0 — the lib's ledger
/// rule); a per-file read failure counts that file as 0 and never nulls the
/// result. `.md`-only so editor temp/lock files cannot inflate the count
/// (B-pass 2026-09-18).
int? _recentCount(Directory dir, DateTime cutoff) {
  try {
    if (!dir.existsSync()) return null;
    var n = 0;
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      if (!e.path.endsWith('.md')) continue;
      try {
        if (e.statSync().modified.isBefore(cutoff)) continue;
        n++;
      } catch (_) {}
    }
    return n;
  } catch (_) {
    return null;
  }
}

/// ONE pass over [dir] for both diagnose counts — (total recent, recent
/// s_fix) — replacing the earlier double listSync+statSync sweep. Both null
/// when the directory itself is missing/unreadable (unknown, NOT 0); a
/// per-file read failure counts that file as 0 and never nulls the pair.
({int? total, int? sFix}) _diagnoseSweep(Directory dir, DateTime cutoff) {
  final sFixPattern = RegExp(r'^tier:\s*s_fix', multiLine: true);
  // Scan only the FRONTMATTER block (rule 22 places the stamp there) — a body
  // line that merely QUOTES `tier: s_fix` at line start must not count.
  String frontmatterOf(String content) {
    if (!content.startsWith('---')) return content;
    final parts = content.split(RegExp(r'^---\s*$', multiLine: true));
    return parts.length > 1 ? parts[1] : content;
  }

  try {
    if (!dir.existsSync()) return (total: null, sFix: null);
    var total = 0;
    var sFix = 0;
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      try {
        if (e.statSync().modified.isBefore(cutoff)) continue;
        total++;
        if (sFixPattern.hasMatch(frontmatterOf(e.readAsStringSync()))) sFix++;
      } catch (_) {}
    }
    return (total: total, sFix: sFix);
  } catch (_) {
    return (total: null, sFix: null);
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

    // Reader for the writer at pre-commit.sh:385 (<epoch> <gate> per failed
    // gate). Absent file => nulls (unknown); unparseable content => nulls too,
    // so it renders unknown, never 0 (bad-news-vs-no-news).
    int? gateFailures7d;
    String? topGate;
    try {
      final log = File('$root/.claude/.gate_failures.log');
      if (log.existsSync()) {
        final stats = parseGateFailuresLog(
          log.readAsStringSync(),
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        if (!stats.unparseable) {
          gateFailures7d = stats.recentTotal;
          topGate = stats.topGate;
        }
      }
    } catch (_) {}

    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final sweep = _diagnoseSweep(Directory('$root/docs/diagnoses'), cutoff);
    stdout.writeln(composeReport(
      record: record,
      openEscapes: openEscapes,
      recentDiagnoseDocs: sweep.total,
      sTierDocs: sweep.sFix,
      recentReviewFiles: _recentCount(Directory('$root/docs/reviews'), cutoff),
      gateFailures7d: gateFailures7d,
      topGate: topGate,
    ));
  } catch (_) {
    // Telemetry must never break batch close.
  }
}
