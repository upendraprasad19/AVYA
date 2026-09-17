// Pure lib for batch-close process telemetry (§4.12.6 companion).
// Reads nothing from disk — callers pass contents. Pure => testable.
// Mirror-rule note: absent/unparseable ledger => openEscapes null (unknown),
// never 0 (bad-news-vs-no-news: an unreadable ledger must not read as "no
// open escapes").
// Known blind spot (intentional): an UNPARSEABLE `review_rounds` value (e.g.
// `review_rounds: two`) is indistinguishable from an ABSENT one and reads as
// 0 — same shape, different meaning. Do not treat 0 as "review never ran"
// without checking the record's shape.
//
// NULL RENDERING RULE (composeReport): any null count renders the literal
// `unknown` for ITS OWN field only, never 0 — bad-news-vs-no-news, same rule
// as the ledger's openEscapes. Per-field, so s_tier_fixes can render
// `1/2`, `unknown/2` (diagnose dir missing, some other source knew s_fix),
// `1/unknown` or `unknown/unknown`; review_files_7d and open_s_escapes
// render `unknown` alone. A genuine 0 (dir present, nothing recent) renders
// as `0`, deliberately distinct.
//
// GATE-FAILURES LOG (parseGateFailuresLog): the writer is pre-commit.sh's
// aggregate loop ("<epoch-seconds> <gate-name>" per failed gate). Mirror-rule
// note: an ABSENT file is the CALLER's null (unknown); an UNPARSEABLE file
// (empty, or no epoch+name-shaped line at all) sets `unparseable` so the
// caller renders unknown, never 0 — an unreadable log must not read as "no
// gate failures". A PARSEABLE log with nothing inside the window is a
// genuine 0. Lines with a non-numeric first token (or wrong token count) are
// skipped, never fatal — the log is append-only debris from many runs.

class PlanReviewStats {
  final int reviewRounds;
  final bool mechanicalOnly;
  const PlanReviewStats({required this.reviewRounds, required this.mechanicalOnly});
}

class EscapeLedgerStats {
  final int? openEscapes;
  const EscapeLedgerStats({this.openEscapes});
}

PlanReviewStats parsePlanReviewRecord(String content) {
  final parts = content.split(RegExp(r'^---\s*$', multiLine: true));
  // Malformed frontmatter (e.g. starts `---title:`) yields a single part —
  // fall through to the whole content rather than throwing RangeError.
  final scope = content.startsWith('---') && parts.length > 1 ? parts[1] : content;
  int? field(String k) {
    final m = RegExp('^$k:\\s*(.+)\$', multiLine: true).firstMatch(scope);
    return m == null ? null : int.tryParse(m.group(1)!.trim());
  }

  return PlanReviewStats(
    reviewRounds: field('review_rounds') ?? 0,
    mechanicalOnly: RegExp(r'^mechanical_only:\s*true', multiLine: true).hasMatch(scope),
  );
}

/// Returns the ledger's stats; `openEscapes` is null when the content is not
/// a parseable escapes ledger (unknown, NOT zero).
EscapeLedgerStats parseEscapeLedger(String content) {
  if (!content.contains(RegExp(r'^escapes:', multiLine: true))) {
    return const EscapeLedgerStats(openEscapes: null);
  }
  // The `$` anchor is load-bearing: without it open-PREFIXED statuses
  // (`status: opened`, `status: open_ticket`) count as open. The trailing
  // `\s*` additionally tolerates trailing whitespace before the line ending.
  // (Empirically verified 2026-09-18: Dart/ECMAScript multiline `$` DOES
  // match before `\r`, so bare-`$` already handles CRLF — the trailing
  // `\s*` is belt-and-braces, and the CRLF test pins that behaviour.)
  return EscapeLedgerStats(
    openEscapes:
        RegExp(r'status:\s*open\s*$', multiLine: true).allMatches(content).length,
  );
}

class GateFailuresStats {
  /// Failed-gate lines within the last 7 days (epoch >= now-604800).
  final int recentTotal;

  /// Most frequent gate name among recent lines; null when none in-window.
  final String? topGate;

  /// True when the content does not look like a gate-failures log at all —
  /// empty, or no `<epoch> <name>`-shaped line. Caller renders unknown, never 0.
  final bool unparseable;

  const GateFailuresStats({
    required this.recentTotal,
    required this.topGate,
    required this.unparseable,
  });
}

/// The 7-day window, in seconds — 604800 = 7 * 86400.
const _gateWindowSeconds = 604800;

GateFailuresStats parseGateFailuresLog(String content, int nowEpochSeconds) {
  final cutoff = nowEpochSeconds - _gateWindowSeconds;
  final counts = <String, int>{};
  var sawValidShape = false;
  var recentTotal = 0;
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.length != 2) continue; // gate names never contain spaces
    final epoch = int.tryParse(tokens[0]);
    if (epoch == null) continue; // non-numeric first token: skip, don't abort
    sawValidShape = true;
    if (epoch < cutoff) continue; // outside the 7-day window
    recentTotal++;
    counts[tokens[1]] = (counts[tokens[1]] ?? 0) + 1;
  }
  if (!sawValidShape) {
    return const GateFailuresStats(
        recentTotal: 0, topGate: null, unparseable: true);
  }
  String? top;
  var best = 0;
  counts.forEach((gate, n) {
    if (n > best) {
      best = n;
      top = gate;
    }
  });
  return GateFailuresStats(
      recentTotal: recentTotal, topGate: top, unparseable: false);
}

String composeReport({
  required PlanReviewStats record,
  required int? openEscapes,
  required int? recentDiagnoseDocs,
  required int? sTierDocs,
  required int? recentReviewFiles,
  required int? gateFailures7d,
  required String? topGate,
}) {
  final esc = openEscapes == null ? 'unknown' : '$openEscapes';
  final total = recentDiagnoseDocs == null ? 'unknown' : '$recentDiagnoseDocs';
  final sFix = sTierDocs == null ? 'unknown' : '$sTierDocs';
  final reviews = recentReviewFiles == null ? 'unknown' : '$recentReviewFiles';
  final gf = gateFailures7d == null ? 'unknown' : '$gateFailures7d';
  return [
    'process-telemetry: review_rounds=${record.reviewRounds} '
        'mechanical_only=${record.mechanicalOnly}',
    'process-telemetry: open_s_escapes=$esc',
    'process-telemetry: s_tier_fixes=$sFix/$total '
        'review_files_7d=$reviews',
    // topGate null renders `none`, never `unknown`: with a parseable log it
    // genuinely means "no failures in-window"; an unparseable/absent log
    // already renders unknown via gate_failures_7d.
    'process-telemetry: gate_failures_7d=$gf '
        'top_gate=${topGate ?? 'none'}',
  ].join('\n');
}
