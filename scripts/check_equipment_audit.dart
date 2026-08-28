// scripts/check_equipment_audit.dart
//
// ⑦ OI-89 Gate B — flags library rows whose PROSE contradicts their
// `equipment_needed`. Evidence from outside the field the capability predicate
// reads: an oracle sharing a field with its predicate proves threading, never
// truth. See equipment_audit_lib.dart for the four rows that motivated it.
//
//   dart run scripts/check_equipment_audit.dart            # report, exit 0
//   dart run scripts/check_equipment_audit.dart --strict    # fail on any finding
//   dart run scripts/check_equipment_audit.dart --all-tiers # not just bodyweight
//
// §4.11 (gate before refactor): the DEFAULT is warn-only, deliberately. The gate
// lands BEFORE the library correction so each retag commit can see its own drift,
// and `--strict` becomes the default in the commit that finishes the correction.
// Shipping it hard today would block every commit on 33 pre-existing findings --
// a ship-stop for a problem the gate exists to help fix.
import 'dart:convert';
import 'dart:io';

import 'package:icanbefitter/core/utils/equipment_vocab.dart';

import 'equipment_audit_lib.dart';

const _libraryPath = 'assets/data/exercise_library.json';

void main(List<String> args) {
  final strict = args.contains('--strict');
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

  final scope = allTiers ? 'all tiers' : 'bodyweight-tier rows only';
  if (findings.isEmpty) {
    stdout.writeln('[equipment-audit] PASS — ${rows.length} rows scanned '
        '($scope); no prose contradicts equipment_needed.');
    exit(0);
  }

  final sink = strict ? stderr : stdout;
  sink.writeln('[equipment-audit] ${findings.length} finding(s) across '
      '${rows.length} rows ($scope):');
  for (final f in findings) {
    sink.writeln('  - $f');
  }
  sink.writeln('');
  sink.writeln('These are TRIAGE INPUT, not verdicts — a pro_tip may mention a '
      'barbell only to contrast with it. Correct the row or accept the mention.');

  if (!strict) {
    stdout.writeln('[equipment-audit] warn-only (§4.11) — not failing. '
        'Pass --strict once the library is corrected.');
    exit(0);
  }
  exit(1);
}
