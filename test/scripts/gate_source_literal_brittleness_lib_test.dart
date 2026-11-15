// test/scripts/gate_source_literal_brittleness_lib_test.dart
//
// Unit tests for scripts/gate_source_literal_brittleness_lib.dart
// (check_gate_source_literal_whitespace_brittleness.dart's detection logic).
//
// Mutation-proof evidence lives in docs/audit/gate_test_ledger.yaml under
// check_gate_source_literal_whitespace_brittleness.dart.

import 'package:test/test.dart';

import '../../scripts/gate_source_literal_brittleness_lib.dart';

String _diff(String file, List<String> addedLines) {
  final buf = StringBuffer();
  buf.writeln('diff --git a/$file b/$file');
  buf.writeln('index 0000000..1111111 100644');
  buf.writeln('--- a/$file');
  buf.writeln('+++ b/$file');
  buf.writeln('@@ -0,0 +1,${addedLines.length} @@');
  for (final l in addedLines) {
    buf.writeln('+$l');
  }
  return buf.toString();
}

void main() {
  group('findBrittleLiteralComparisons', () {
    test(
        'BAD: multi-word .contains() literal in a check_*.dart file is flagged',
        () {
      final diff = _diff('scripts/check_something.dart', [
        "  if (line.contains('flutter analyze')) {",
      ]);
      final findings = findBrittleLiteralComparisons(diff);
      expect(findings, hasLength(1));
      expect(findings.first.literal, 'flutter analyze');
      expect(findings.first.file, 'scripts/check_something.dart');
    });

    test('BAD: multi-word == literal comparison in a *_lib.dart file is flagged',
        () {
      final diff = _diff('scripts/something_lib.dart', [
        "  if (token == 'git merge-tree extra') {",
      ]);
      final findings = findBrittleLiteralComparisons(diff);
      expect(findings, hasLength(1));
      expect(findings.first.literal, 'git merge-tree extra');
    });

    test(
        'GOOD mirror: the same intent written as a whitespace-tolerant RegExp '
        'is NOT flagged', () {
      final diff = _diff('scripts/check_something.dart', [
        r"  if (RegExp(r'flutter\s+analyze').hasMatch(line)) {",
      ]);
      final findings = findBrittleLiteralComparisons(diff);
      expect(findings, isEmpty);
    });

    test('GOOD: a single-token literal comparison is NOT flagged (no internal '
        'space to be brittle about)', () {
      final diff = _diff('scripts/check_something.dart', [
        "  if (status.contains('FAIL')) {",
        "  if (mode == '--warn-only') {",
      ]);
      final findings = findBrittleLiteralComparisons(diff);
      expect(findings, isEmpty);
    });

    test(
        'GOOD: the same multi-word literal comparison OUTSIDE gate-authoring '
        'scope (lib/, test/) is NOT flagged', () {
      final diffLib = _diff('lib/features/train/screen.dart', [
        "  if (label.contains('flutter analyze')) {",
      ]);
      final diffTest = _diff('test/widgets/some_widget_test.dart', [
        "  if (title == 'flutter analyze report') {",
      ]);
      expect(findBrittleLiteralComparisons(diffLib), isEmpty);
      expect(findBrittleLiteralComparisons(diffTest), isEmpty);
    });

    test('GOOD: a check_*.dart file OUTSIDE scripts/ (e.g. under test/) is '
        'not treated as gate-authoring code', () {
      final diff = _diff('test/fixtures/check_something.dart', [
        "  if (line.contains('flutter analyze')) {",
      ]);
      expect(findBrittleLiteralComparisons(diff), isEmpty);
    });

    test('multiple findings across multiple in-scope files are all reported', () {
      final diff = _diff('scripts/check_a.dart', [
        "  if (line.contains('flutter analyze')) {",
        "  if (ok) return;",
      ]) +
          _diff('scripts/b_lib.dart', [
            "  if (cmd == 'git merge tree') {",
          ]);
      final findings = findBrittleLiteralComparisons(diff);
      expect(findings, hasLength(2));
    });

    test('empty diff yields no findings', () {
      expect(findBrittleLiteralComparisons(''), isEmpty);
    });
  });
}
