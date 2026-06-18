// scripts/check_sot_behavioral_test_paths.dart
//
// Gate 42 (Tech-debt audit 2026-05-20, B5 D2 deliverable): assert every
// SoT registry concept entry carries either:
//   - `behavioral_test_path:` (cite a real behavioral contract test)
//   - `presence_only: true`   (source-grep / static / Deno-EF-only, no Flutter seam)
//
// `presence_only: true` is the authorised escape hatch for exactly these cases:
//   - Dep-canonicalization (dependency_canonical_http_client): source-grep IS the test
//   - Static structural (typography_canonical_source): source-grep only
//   - Presentation (ui_header_no_clip): source-grep only
//   - Cross-user Deno EF (community_review_queue): not Flutter-unit-testable
//   - Deno EF placeholder (ai_proxy_placeholder_resolution): no Flutter unit-test seam
//
// Per `feedback_source_grep_false_confidence.md` + CLAUDE.md §4.4 rule 21
// amendment (B5 D1 2026-05-21, tightened P1.D part 2 2026-06-18):
//
//   Source-grep tests count for PRESENCE only — every SoT registry entry
//   MUST have a `behavioral_test_path:` (Hive-write → Hive-read assertion,
//   fakeAsync race harness, or end-to-end flow) that fails when the runtime
//   path is broken even if the source text remains intact, UNLESS the entry
//   explicitly carries `presence_only: true` documenting WHY a behavioral
//   test is not feasible.
//
//   There is NO `behavioral_test_required: true` backlog allowed — the gate
//   is STRICT by default. Any remaining TODO markers block the commit.
//
// Behaviour (P1.D part 2: strict by default):
//   - Default: STRICT — exit 1 if any concept lacks behavioral_test_path AND
//     does not carry presence_only: true. Zero TODOs are allowed.
//   - --warn-only: demote to WARN, exit 0. Use ONLY for temporary debugging
//     of a large refactor in a feature branch; never merge to main with warn-only.
//
// Usage:
//   dart run scripts/check_sot_behavioral_test_paths.dart            # strict (default)
//   dart run scripts/check_sot_behavioral_test_paths.dart --strict   # explicit strict
//   dart run scripts/check_sot_behavioral_test_paths.dart --warn-only
//
// Exit 0 = PASS.
// Exit 1 = FAIL (unresolved entries in strict mode).

import 'dart:io';

void main(List<String> args) async {
  // Default is now STRICT. --warn-only downgrades.
  final warnOnly = args.contains('--warn-only');
  final strict = !warnOnly; // strict unless explicitly overridden

  final file = File('docs/sot_registry.yaml');
  if (!file.existsSync()) {
    stdout.writeln('[Gate 42] SKIP: docs/sot_registry.yaml not present.');
    exit(0);
  }

  final content = file.readAsStringSync().replaceAll('\r\n', '\n');
  final lines = content.split('\n');

  // Walk concept blocks. Each starts with `  - concept: <name>` (2-space + dash).
  // Block ends at the next `  - concept:` line OR EOF.
  final missing = <String>[]; // no behavioral_test_path AND no presence_only
  final staleRequired = <String>[]; // legacy behavioral_test_required: true still present
  final presenceOnly = <String>[]; // counted for reporting
  final behavioralPaths = <String>[]; // counted for reporting

  String? currentConcept;
  int? currentLine;
  bool currentHasBehavioralPath = false;
  bool currentHasPresenceOnly = false;
  bool currentHasRequiredFlag = false;

  void flushCurrent() {
    if (currentConcept == null) return;
    final concept = currentConcept; // non-null: guard above returned early
    if (currentHasRequiredFlag) {
      // Legacy TODO marker — now a HARD blocker
      staleRequired.add('$concept (line $currentLine)');
    } else if (currentHasBehavioralPath) {
      behavioralPaths.add(concept);
    } else if (currentHasPresenceOnly) {
      presenceOnly.add(concept);
    } else {
      // No behavioral_test_path, no presence_only, no required flag
      missing.add('$concept (line $currentLine)');
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
      currentHasPresenceOnly = false;
      currentHasRequiredFlag = false;
      continue;
    }
    if (currentConcept == null) continue;

    // behavioral_test_path: <non-empty, non-TBD value>
    if (RegExp(r'^\s+behavioral_test_path\s*:').hasMatch(line)) {
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

    // presence_only: true  — authorised escape hatch (Deno-EF, static, source-grep-only)
    if (RegExp(r'^\s+presence_only\s*:\s*true').hasMatch(line)) {
      currentHasPresenceOnly = true;
    }

    // behavioral_test_required: true  — STALE marker; now a gate blocker
    if (RegExp(r'^\s+behavioral_test_required\s*:\s*true').hasMatch(line)) {
      currentHasRequiredFlag = true;
    }
  }
  flushCurrent();

  final tag = strict ? '[Gate 42]' : '[Gate 42 WARN]';
  final problems = <String>[...staleRequired, ...missing];

  // Report stale required markers (hard blocker even in warn-only when present)
  if (staleRequired.isNotEmpty) {
    stderr.writeln(
        '$tag ${staleRequired.length} concept(s) still have STALE behavioral_test_required: true:');
    for (final r in staleRequired.take(15)) {
      stderr.writeln('  - $r');
    }
    if (staleRequired.length > 15) {
      stderr.writeln('  ... and ${staleRequired.length - 15} more');
    }
    stderr.writeln(
        '  Fix: add behavioral_test_path: OR presence_only: true, then delete the flag.');
  }

  // Report missing (no path, no presence_only, no required flag)
  if (missing.isNotEmpty) {
    stderr.writeln(
        '$tag ${missing.length} concept(s) have NO behavioral_test_path AND NO presence_only: true:');
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
        '  Every SoT concept needs either behavioral_test_path: OR presence_only: true.');
    stderr.writeln(
        '  Source-grep alone is insufficient. presence_only: true is only for');
    stderr.writeln(
        '  Deno-EF / static-structural / source-grep-gated concepts with no Flutter seam.');
  }

  if (problems.isEmpty) {
    stdout.writeln(
        '$tag PASS: all ${behavioralPaths.length} SoT concepts have behavioral_test_path; '
        '${presenceOnly.length} carry presence_only: true (Deno-EF/static). '
        'Zero behavioral_test_required TODOs remain.');
    exit(0);
  }

  // Summary
  stderr.writeln('');
  stderr.writeln(
      '$tag SUMMARY: ${behavioralPaths.length} with behavioral_test_path, '
      '${presenceOnly.length} presence_only, '
      '${staleRequired.length} stale-required (BLOCKER), '
      '${missing.length} missing (BLOCKER).');

  exit(strict ? 1 : 0);
}
