// scripts/check_week_selector_phase_labels.dart
//
// Gate (§4.11 gates-before-refactor; diagnose a3f8c1): the Train week selector
// must derive phase labels from the real current_phase, never hardcode
// "PHASE I / II / III" for the forward groups. A hardcoded forward label
// re-introduces the two-Phase-1 bug (a completed phase + the current phase both
// rendering "PHASE I"). Pre-commit's `scripts/check_*.dart` glob auto-runs this.
//
// Exit 0 = OK, 1 = violation.

import 'dart:io';

void main() {
  final file = File('lib/features/train/widgets/week_selector.dart');
  if (!file.existsSync()) {
    stderr.writeln('check_week_selector_phase_labels: '
        'lib/features/train/widgets/week_selector.dart not found');
    exit(1);
  }

  // Strip comments so a commented reference never trips the gate.
  final src = file
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  final problems = <String>[];

  if (!src.contains('this.currentPhase')) {
    problems.add('WeekSelector must accept a `currentPhase` parameter '
        '(reads the real user_progress.current_phase).');
  }
  if (!src.contains('_phaseRoman(widget.currentPhase')) {
    problems.add('Forward phase-group labels must derive from '
        '`_phaseRoman(widget.currentPhase ...)`, not a hardcoded literal.');
  }
  for (final lit in const [
    "label: 'PHASE I'",
    "label: 'PHASE II'",
    "label: 'PHASE III'",
  ]) {
    if (src.contains(lit)) {
      problems.add('Hardcoded forward phase label found ($lit) — re-introduces '
          'the two-Phase-1 duplicate. Derive from current_phase instead.');
    }
  }

  if (problems.isEmpty) {
    stdout.writeln('check_week_selector_phase_labels: OK');
    exit(0);
  }
  stderr.writeln('check_week_selector_phase_labels FAILED:');
  for (final p in problems) {
    stderr.writeln('  - $p');
  }
  exit(1);
}
