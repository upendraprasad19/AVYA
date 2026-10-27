// scripts/check_skipped_discipline_budget.dart
//
// Gate (P1.G, discipline-overhaul 2026-06-18): assert that no
// `regression-test-skipped:` waiver entry in `docs/skipped-discipline.md`
// is OPEN (not marked resolved/closed) AND older than 14 days.
//
// Motivation: the `regression-test-skipped:` escape hatch in commit-msg.sh
// is intentionally narrow — it is for SQL-only migrations and tightly scoped
// cases where a behavioral regression test is structurally impossible. Without
// a budget gate, old open waivers silently accumulate and the discipline file
// becomes a permanent parking lot rather than a tracked time-bounded exception.
// 14 days is enough time to add a behavioral test; longer = tracked debt.
//
// File format (append-only lines):
//   `- <date> · <sha> · <reason>`
// where <date> is YYYY-MM-DD (ISO date prefix on the line).
// A waiver is considered CLOSED if the line contains the word "resolved" or
// "closed" (case-insensitive) anywhere after the date prefix.
//
// File missing → PASS (no waivers).
// No open-old waivers → PASS.
// Open waiver older than 14 days → FAIL (or WARN if --warn-only).
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

const _waiversPath = 'docs/skipped-discipline.md';
const _maxAgeDays = 14;

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final file = File(_waiversPath);

  if (!file.existsSync()) {
    stdout.writeln('[Gate-SDB] PASS: $_waiversPath not found — no waivers.');
    exit(0);
  }

  final lines = file.readAsLinesSync();
  final today = DateTime.now();

  // Parse waiver lines: `- YYYY-MM-DD · ...`
  // Date may be at the start of the line after the leading `- `.
  final waiverLineRegex =
      RegExp(r'^\s*-\s+(\d{4}-\d{2}-\d{2})\s');

  final overdueEntries = <String>[];

  for (final line in lines) {
    final m = waiverLineRegex.firstMatch(line);
    if (m == null) continue; // header, blank, or non-waiver line

    // Determine if this waiver is closed.
    final lowerLine = line.toLowerCase();
    final isClosed =
        lowerLine.contains('resolved') || lowerLine.contains('closed');
    if (isClosed) continue;

    // Parse date.
    DateTime waiverDate;
    try {
      waiverDate = DateTime.parse(m.group(1)!);
    } catch (_) {
      // Unparseable date — skip rather than false-positive.
      continue;
    }

    final ageDays = today.difference(waiverDate).inDays;
    if (ageDays > _maxAgeDays) {
      overdueEntries.add('(${ageDays}d old) $line');
    }
  }

  final tag = warnOnly ? '[Gate-SDB WARN]' : '[Gate-SDB]';
  if (overdueEntries.isEmpty) {
    stdout.writeln('$tag PASS: no open waivers older than $_maxAgeDays days.');
    exit(0);
  }

  stderr.writeln(
      '$tag FAIL: ${overdueEntries.length} regression-test-skipped waiver(s) '
      'open and older than $_maxAgeDays days — these should have a behavioral test '
      'by now. Mark as "resolved" with a commit SHA, or add the behavioral test.');
  for (final e in overdueEntries) {
    stderr.writeln('  - $e');
  }
  exit(warnOnly ? 0 : 1);
}
