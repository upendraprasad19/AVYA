// scripts/check_equipment_vocab_lockstep.dart
//
// ⑦ OI-89 — pre-commit gate: EquipmentVocab's four token structures must agree.
//
// Adding a token to `canonicalTokens` alone is NOT enough. `_precedence`,
// `_chipLabels` and `_aliases` all key on the same set, and all three fail
// SILENTLY when they drift — see equipment_vocab_lockstep_lib.dart for what each
// silent failure actually produces. This gate makes the drift loud.
//
//   dart run scripts/check_equipment_vocab_lockstep.dart
//
// Exit 0 = in lockstep. Exit 1 = drift (the commit is blocked).
import 'dart:io';

import 'equipment_vocab_lockstep_lib.dart';

void main() {
  final violations = liveLockstepViolations();
  if (violations.isEmpty) {
    stdout.writeln('PASS: EquipmentVocab lockstep (canonicalTokens / '
        '_precedence / _chipLabels / _aliases agree).');
    exit(0);
  }
  stderr.writeln('FAIL: EquipmentVocab is out of lockstep '
      '(${violations.length} violation(s)):');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix in lib/core/utils/equipment_vocab.dart. A canonical token '
      'needs a _precedence rank AND a _chipLabels entry, and must not also be '
      'an _aliases key.');
  exit(1);
}
