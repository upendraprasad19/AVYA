// Pure lib for batch-close process telemetry (§4.12.6 companion).
// Reads nothing from disk — callers pass contents. Pure => testable.
// Mirror-rule note: absent/unparseable ledger => openEscapes null (unknown),
// never 0 (bad-news-vs-no-news: an unreadable ledger must not read as "no
// open escapes").
// Known blind spot (intentional): an UNPARSEABLE `review_rounds` value (e.g.
// `review_rounds: two`) is indistinguishable from an ABSENT one and reads as
// 0 — same shape, different meaning. Do not treat 0 as "review never ran"
// without checking the record's shape.

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

String composeReport({
  required PlanReviewStats record,
  required int? openEscapes,
  required int recentDiagnoseDocs,
  required int sTierDocs,
  required int recentReviewFiles,
}) {
  final esc = openEscapes == null ? 'unknown' : '$openEscapes';
  return [
    'process-telemetry: review_rounds=${record.reviewRounds} '
        'mechanical_only=${record.mechanicalOnly}',
    'process-telemetry: open_s_escapes=$esc',
    'process-telemetry: s_tier_fixes=$sTierDocs/$recentDiagnoseDocs '
        'review_files_7d=$recentReviewFiles',
  ].join('\n');
}
