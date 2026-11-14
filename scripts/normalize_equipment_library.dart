// scripts/normalize_equipment_library.dart
//
// ⑥ slice A — one-time, IDEMPOTENT normalizer of the exercise library's
// free-text `equipment_needed` field to `EquipmentVocab.canonicalTokens`.
//
// Uses `EquipmentVocab.normalize` as the SINGLE source of truth (so the seed and
// the runtime read-seam can never diverge), and does a TARGETED text replacement
// of each `"equipment_needed": [ ... ]` block ONLY — every other field (incl.
// the `5.0`/`10.0` float formatting a full JSON re-emit would collapse to `5`/
// `10`) is preserved byte-for-byte. Re-running on already-normalized data is a
// no-op (normalize is idempotent).
//
//   dart run scripts/normalize_equipment_library.dart          # write
//   dart run scripts/normalize_equipment_library.dart --check  # verify only (CI-safe)

import 'dart:io';

import 'package:icanbefitter/core/utils/equipment_vocab.dart';

const _path = 'assets/data/exercise_library.json';

void main(List<String> args) {
  final check = args.contains('--check');
  final file = File(_path);
  if (!file.existsSync()) {
    stderr.writeln('FAIL: $_path not found (run from repo root).');
    exit(1);
  }
  final original = file.readAsStringSync();

  // Match each `"equipment_needed": [ ... ]` block (arrays hold only strings, so
  // the first `]` closes the array). dotAll so it spans the pretty-printed lines.
  final blockRe = RegExp(r'"equipment_needed": \[(.*?)\]', dotAll: true);
  final tokenRe = RegExp(r'"([^"]*)"');

  var changed = 0;
  final updated = original.replaceAllMapped(blockRe, (m) {
    final raw = tokenRe
        .allMatches(m.group(1)!)
        .map((t) => t.group(1)!)
        .toList();
    final norm = EquipmentVocab.normalize(raw);
    final rebuilt = norm.isEmpty
        ? '"equipment_needed": []'
        : '"equipment_needed": [\n'
            '${norm.map((t) => '      "$t"').join(',\n')}\n'
            '    ]';
    if (rebuilt != m.group(0)) changed++;
    return rebuilt;
  });

  if (check) {
    if (updated != original) {
      stderr.writeln(
          'FAIL: $_path has $changed equipment_needed block(s) not normalized. '
          'Run `dart run scripts/normalize_equipment_library.dart`.');
      exit(1);
    }
    stdout.writeln('OK: all equipment_needed blocks already normalized.');
    exit(0);
  }

  if (updated == original) {
    stdout.writeln('OK: no change ($changed blocks already canonical).');
    exit(0);
  }
  file.writeAsStringSync(updated);
  stdout.writeln('normalized $changed equipment_needed block(s) in $_path.');
}
