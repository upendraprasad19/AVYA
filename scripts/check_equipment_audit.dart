// scripts/check_equipment_audit.dart
//
// ⑦ OI-89 Gate B — flags library rows whose PROSE contradicts their
// `equipment_needed`. Evidence from outside the field the capability predicate
// reads: an oracle sharing a field with its predicate proves threading, never
// truth. See equipment_audit_lib.dart for the four rows that motivated it.
//
//   dart run scripts/check_equipment_audit.dart              # STRICT, fails on a finding
//   dart run scripts/check_equipment_audit.dart --warn-only   # report, exit 0
//   dart run scripts/check_equipment_audit.dart --all-tiers   # not just bodyweight
//
// §4.11 (gate before refactor): this shipped warn-only, deliberately, so each retag
// commit could see its own drift without 33 pre-existing findings blocking every
// commit. FLIPPED STRICT 2026-08-28 in the commit that finished the correction,
// exactly as that plan said it would be.
//
// _accepted is the residue: a mention the audit correctly FOUND and a human
// correctly JUDGED not to be a defect -- a pro_tip naming a barbell to contrast
// with it, or offering kit as a progression. Each entry carries the reason, so the
// next audit does not re-litigate it, and an entry is a claim about ONE (row,
// token) pair -- never a blanket row exemption, or a genuinely new finding on an
// accepted row would pass silently.
import 'dart:convert';
import 'dart:io';

import 'package:icanbefitter/core/utils/equipment_vocab.dart';

import 'equipment_audit_lib.dart';

const _libraryPath = 'assets/data/exercise_library.json';

void main(List<String> args) {
  // Strict is the DEFAULT since the 2026-08-28 correction landed. --warn-only is
  // for in-branch debugging and must never reach main (rule 21's convention).
  final strict = !args.contains('--warn-only');
  final allTiers = args.contains('--all-tiers');

  final file = File(_libraryPath);
  if (!file.existsSync()) {
    stderr.writeln('SKIP: $_libraryPath not found (run from repo root).');
    exit(0); // fail OPEN — an environment quirk must not wedge every commit
  }

  final rows = (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  final findings = auditFindings(
    rows: rows,
    normalizeNeeded: EquipmentVocab.fromProfile,
    bodyweightTierOnly: !allTiers,
  );

  final split = partitionAccepted(findings);
  final findings2 = split.unaccepted;
  final accepted = split.accepted;

  final scope = allTiers ? 'all tiers' : 'bodyweight-tier rows only';
  if (findings2.isEmpty) {
    stdout.writeln('[equipment-audit] PASS — ${rows.length} rows scanned '
        '($scope); no prose contradicts equipment_needed '
        '(${accepted.length} judged-accepted mention(s) held).');
    exit(0);
  }

  final sink = strict ? stderr : stdout;
  sink.writeln('[equipment-audit] ${findings2.length} finding(s) across '
      '${rows.length} rows ($scope):');
  for (final f in findings2) {
    sink.writeln('  - $f');
  }
  sink.writeln('');
  sink.writeln('These are TRIAGE INPUT, not verdicts — a pro_tip may mention a '
      'barbell only to contrast with it. Correct the row or accept the mention.');

  if (!strict) {
    stdout.writeln('[equipment-audit] --warn-only — not failing. '
        'Strict is the default; this flag is for in-branch debugging only.');
    exit(0);
  }
  sink.writeln('');
  sink.writeln('If a mention is genuinely not a defect, add "<id>|<token>" to '
      '_accepted WITH the reason. Do not widen it to a bare row id.');
  exit(1);
}
