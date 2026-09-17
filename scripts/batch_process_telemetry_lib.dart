// Pure lib for batch-close process telemetry (§4.12.6 companion).
// Reads nothing from disk — callers pass contents. Pure => testable.
// Mirror-rule note: absent/unparseable ledger => openEscapes null (unknown),
// never 0 (bad-news-vs-no-news: an unreadable ledger must not read as "no
// open escapes").

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
  final scope = content.startsWith('---')
      ? content.split(RegExp(r'^---\s*$', multiLine: true))[1]
      : content;
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
  // `$` anchor is load-bearing: without it `status: reopened` counts as open.
  return EscapeLedgerStats(
    openEscapes:
        RegExp(r'status:\s*open$', multiLine: true).allMatches(content).length,
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
