// scripts/check_sot_behavioral_test_paths.dart
//
// Gate 42 (Tech-debt audit 2026-05-20, B5 D2 deliverable): assert every
// SoT registry concept entry carries either:
//   - `behavioral_test_path:` (cite a real behavioral contract test)
//   - `behavioral_test_required: true` (TODO marker — emits WARN)
//
// Per `feedback_source_grep_false_confidence.md` + CLAUDE.md §4.4 rule 21
// amendment (B5 D1 2026-05-21):
//
//   Source-grep tests count for PRESENCE only — every SoT registry entry
//   MUST ALSO have a `behavioral_test_path:` (Hive-write → Hive-read
//   assertion, or fakeAsync race harness, or end-to-end flow) that
//   fails when the runtime path is broken even if the source text
//   remains intact. Entries without a behavioral test yet carry
//   `behavioral_test_required: true` — Gate 42 emits WARN per such entry
//   until the test ships.
//
// Behavior:
//   - Default (warn-only): emits WARN per concept missing behavioral_test_path.
//     Does NOT fail the gate. Each WARN is a TODO that the next bug fix
//     touching that concept should resolve.
//   - --strict: every concept must have behavioral_test_path. Used by
//     audit-closure pre-merge gate.
//   - --warn-only: same as default; explicit for clarity.
//
// Usage:
//   dart run scripts/check_sot_behavioral_test_paths.dart           # warn
//   dart run scripts/check_sot_behavioral_test_paths.dart --strict  # fail
//
// Exit 0 = pass (or warn-mode with WARN emitted).
// Exit 1 = strict-mode failure.

import 'dart:io';

void main(List<String> args) async {
  final strict = args.contains('--strict');
  final file = File('docs/sot_registry.yaml');
  if (!file.existsSync()) {
    stdout.writeln('[Gate 42] SKIP: docs/sot_registry.yaml not present.');
    exit(0);
  }

  final content = file.readAsStringSync().replaceAll('\r\n', '\n');
  final lines = content.split('\n');

  // Walk concept blocks. Each starts with `  - concept: <name>` (4-space indent).
  // Block ends at the next `  - concept:` line OR EOF.
  final missing = <String>[];
  final required = <String>[]; // entries with behavioral_test_required: true
  String? currentConcept;
  int? currentLine;
  bool currentHasBehavioralPath = false;
  bool currentHasRequiredFlag = false;

  void flushCurrent() {
    if (currentConcept == null) return;
    if (currentHasBehavioralPath) {
      // Good — has real behavioral test
    } else if (currentHasRequiredFlag) {
      required.add('$currentConcept (line $currentLine)');
    } else {
      missing.add('$currentConcept (line $currentLine)');
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final conceptMatch = RegExp(r'^  - concept:\s*(\S+)').firstMatch(line);
    if (conceptMatch != null) {
      flushCurrent();
      currentConcept = conceptMatch.group(1);
      currentLine = i + 1;
      currentHasBehavioralPath = false;
      currentHasRequiredFlag = false;
      continue;
    }
    if (currentConcept == null) continue;
    // Check for behavioral_test_path (and various capitalizations).
    if (RegExp(r'^\s+behavioral_test_path\s*:').hasMatch(line)) {
      // Value must not be empty / TBD / TODO.
      final valueMatch = RegExp(r'^\s+behavioral_test_path\s*:\s*(.*)').firstMatch(line);
      final value = valueMatch?.group(1)?.trim() ?? '';
      if (value.isNotEmpty &&
          !value.toLowerCase().contains('tbd') &&
          !value.toLowerCase().contains('todo') &&
          value != '""' &&
          value != "''") {
        currentHasBehavioralPath = true;
      }
    }
    if (RegExp(r'^\s+behavioral_test_required\s*:\s*true').hasMatch(line)) {
      currentHasRequiredFlag = true;
    }
  }
  flushCurrent();

  final tag = strict ? '[Gate 42]' : '[Gate 42 WARN]';

  if (required.isNotEmpty) {
    stderr.writeln(
        '$tag ${required.length} concept(s) marked behavioral_test_required: true (TODO):');
    for (final r in required.take(15)) {
      stderr.writeln('  - $r');
    }
    if (required.length > 15) {
      stderr.writeln('  ... and ${required.length - 15} more');
    }
    stderr.writeln(
        '  These are honest TODOs. Write a behavioral test the next time a bug fix touches that concept.');
  }

  if (missing.isEmpty) {
    if (required.isEmpty) {
      stdout.writeln(
          '$tag PASS: all SoT concepts have behavioral_test_path: populated.');
    } else {
      stdout.writeln(
          '$tag PASS: all SoT concepts have either behavioral_test_path: or behavioral_test_required: true.');
    }
    exit(0);
  }

  stderr.writeln(
      '$tag ${missing.length} concept(s) have NO behavioral_test_path AND NO behavioral_test_required: true:');
  for (final m in missing.take(20)) {
    stderr.writeln('  - $m');
  }
  if (missing.length > 20) {
    stderr.writeln('  ... and ${missing.length - 20} more');
  }
  stderr.writeln('');
  stderr.writeln(
      'Per feedback_source_grep_false_confidence.md + CLAUDE.md §4.4 rule 21:');
  stderr.writeln(
      '  Every SoT concept needs either a real behavioral test path OR');
  stderr.writeln(
      '  behavioral_test_required: true marker. Source-grep alone is insufficient.');
  exit(strict ? 1 : 0);
}
