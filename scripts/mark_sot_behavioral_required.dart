// scripts/mark_sot_behavioral_required.dart
//
// One-shot helper (B5 D2): walk docs/sot_registry.yaml and for every
// concept missing `behavioral_test_path:`, insert `behavioral_test_required: true`
// right after the `description:` block (or right after the `domain:` line
// if no description). This honest-TODO marker fulfills the closure rule
// (every SoT entry has either behavioral_test_path or behavioral_test_required)
// while flagging the work that needs to land in future bug fixes.
//
// Idempotent: skips concepts that already have either field set.

import 'dart:io';

void main() async {
  final file = File('docs/sot_registry.yaml');
  final lines = file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');

  // Pass 1: find concept blocks, decide which need the marker.
  final conceptStarts = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (RegExp(r'^  - concept:\s*\S+').hasMatch(lines[i])) {
      conceptStarts.add(i);
    }
  }
  conceptStarts.add(lines.length); // sentinel for last block

  final out = <String>[];
  var lastEnd = 0;
  for (var c = 0; c < conceptStarts.length - 1; c++) {
    final start = conceptStarts[c];
    final end = conceptStarts[c + 1];

    // Copy any leading lines (top of file or between blocks) verbatim.
    for (var i = lastEnd; i < start; i++) out.add(lines[i]);

    final block = lines.sublist(start, end);
    final blockText = block.join('\n');
    final hasBehavioralPath = RegExp(r'^\s+behavioral_test_path\s*:', multiLine: true)
        .hasMatch(blockText);
    final hasRequiredFlag = RegExp(
            r'^\s+behavioral_test_required\s*:\s*true', multiLine: true)
        .hasMatch(blockText);
    if (hasBehavioralPath || hasRequiredFlag) {
      // Already satisfied — copy verbatim.
      out.addAll(block);
      lastEnd = end;
      continue;
    }
    // Need to insert. Find insertion point: AFTER the `domain:` line OR
    // after `description: |\n  ...\n  block end`. Simpler: insert right
    // after the `domain:` line (every concept has one and the indent is
    // consistent at 4 spaces).
    final domainLineIdx = block.indexWhere((l) => RegExp(r'^    domain:').hasMatch(l));
    if (domainLineIdx < 0) {
      // Fallback: insert right after the concept: line.
      out.add(block[0]);
      out.add('    behavioral_test_required: true  # B5 D2 (audit 2026-05-20) — Gate 42 TODO');
      for (var i = 1; i < block.length; i++) out.add(block[i]);
    } else {
      for (var i = 0; i <= domainLineIdx; i++) out.add(block[i]);
      out.add('    behavioral_test_required: true  # B5 D2 (audit 2026-05-20) — Gate 42 TODO');
      for (var i = domainLineIdx + 1; i < block.length; i++) out.add(block[i]);
    }
    lastEnd = end;
  }
  // Copy trailing lines after the last concept block.
  for (var i = lastEnd; i < lines.length; i++) out.add(lines[i]);

  file.writeAsStringSync(out.join('\n'));
  stdout.writeln('[mark_sot_behavioral_required] Done.');
}
