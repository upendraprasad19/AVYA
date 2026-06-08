// scripts/check_hardcoded_pricing_and_limits.dart
//
// Gate (psych-skill-and-audit 2026-06-07, WS3): ban hardcoded price figures
// (₹349 / ₹2,999) and AI free-tier limit/trial literals ("15/day", "30-day
// trial") in code OUTSIDE their single source of truth. Prices live in
// AppConstants (monthlyPriceInr / yearlyPriceInr); the AI daily cap lives in the
// ai_limits SoT (pinned to the server FREE_DAILY_LIMIT). Hardcoded copies drift —
// the 2026-06-07 audit found the client declaring 15/day + a 30-day trial while
// the server enforces 10/day forever (OQ-1).
//
// Comments are stripped (newline-preserving) before matching
// (feedback_source_grep_strip_comments_first): a price in a doc comment is
// documentation, not a runtime drift.
//
// §4.11: transitional ALLOWLIST of files violating on 2026-06-07; drain to empty.
// Exit 0 = pass; Exit 1 = a non-allowlisted hardcoded price/limit literal.

import 'dart:io';

// Transitional baseline DRAINED 2026-06-07: paywall_sheet_phase_variant now
// interpolates AppConstants.{monthly,yearly}PriceInr; the 30-day-trial + 15/day
// strings were removed from ai_coach_provider in Batch 3. Gate now fully hard-fail.
const allowlist = <String>{};

// SoT files ALLOWED to contain the canonical figures.
const sotAllowed = <String>{
  'lib/core/constants/app_constants.dart',
  'lib/core/constants/ai_limits.dart',
};

/// Strip /* */ and // comments, preserving line count so reported line numbers
/// still line up with the source file.
String stripComments(String src) {
  final noBlock = src.replaceAllMapped(RegExp(r'/\*[\s\S]*?\*/'), (m) {
    final nl = '\n'.allMatches(m.group(0)!).length;
    return '\n' * nl;
  });
  return noBlock
      .split('\n')
      .map((l) {
        final idx = l.indexOf('//');
        return idx >= 0 ? l.substring(0, idx) : l;
      })
      .join('\n');
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    stdout.writeln('[Gate price/limit] SKIP: lib/ not present.');
    exit(0);
  }
  final patterns = <RegExp>[
    RegExp(r'₹\s?349'),
    RegExp(r'₹\s?2,?999'),
    RegExp(r'349\s*/\s*month'),
    RegExp(r'2,?999\s*/\s*year'),
    RegExp(r'\b15\s*/\s*day'),
    // NB: a broad `30[-\s]day` pattern would false-positive on unrelated copy
    // (e.g. edit_profile's "try again in 30 days" reassessment cooldown). The
    // vestigial 30-day AI trial is removed by the AI-limit fix + pinned by
    // ai_message_limit_parity_test.dart, not by a substring gate here.
  ];
  final newViolations = <String>[];
  final baselineHits = <String>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final norm = e.path.replaceAll('\\', '/');
    if (sotAllowed.contains(norm)) continue;
    final content = stripComments(e.readAsStringSync());
    for (final p in patterns) {
      for (final m in p.allMatches(content)) {
        final lineNum = content.substring(0, m.start).split('\n').length;
        final loc = '$norm:$lineNum ("${m.group(0)}")';
        if (allowlist.contains(norm)) {
          baselineHits.add(loc);
        } else {
          newViolations.add(loc);
        }
      }
    }
  }
  if (baselineHits.isNotEmpty) {
    stdout.writeln('[Gate price/limit] WARN: ${baselineHits.length} baseline hardcoded '
        'price/limit literal(s) pending centralization.');
  }
  if (newViolations.isEmpty) {
    stdout.writeln('[Gate price/limit] PASS: no NEW hardcoded price/limit literals outside the SoT.');
    exit(0);
  }
  final tag = warnOnly ? '[Gate price/limit WARN]' : '[Gate price/limit FAIL]';
  stderr.writeln('$tag: ${newViolations.length} hardcoded price/limit literal(s):');
  for (final v in newViolations.take(15)) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: reference AppConstants.monthlyPriceInr / yearlyPriceInr or the ai_limits '
      'SoT (AppConstants.freeAiMessagesPerDay); never hardcode the figure.');
  exit(warnOnly ? 0 : 1);
}
