// test/scripts/merge_tree_write_tree_form_lib_test.dart
//
// Unit tests for the pure logic behind scripts/check_merge_tree_write_tree_form.dart
// (scripts/merge_tree_write_tree_form_lib.dart).
// Rule 24 (CLAUDE.md §4.4): this test carries the red-path assertion that
// proves the gate's own protection -- see MUTATION PROOF note below.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/merge_tree_write_tree_form_lib.dart';

String _diff(List<String> addedLines, {String file = 'scripts/example.sh'}) {
  final buf = StringBuffer();
  buf.writeln('diff --git a/$file b/$file');
  buf.writeln('+++ b/$file');
  for (final l in addedLines) {
    buf.writeln('+$l');
  }
  return buf.toString();
}

void main() {
  group('findLegacyMergeTreeInvocations', () {
    test('BAD: plain shell 3-arg invocation is flagged', () {
      final violations = findLegacyMergeTreeInvocations(
        _diff(['git merge-tree main feature-x feature-x-rebased']),
      );
      expect(violations, hasLength(1));
      expect(violations.single.file, 'scripts/example.sh');
    });

    test('BAD: markdown-wrapped piped invocation is flagged', () {
      final violations = findLegacyMergeTreeInvocations(
        _diff([
          '`git merge-tree "\$BASE" "\$A" "\$B" | grep \'<<<<<<<\'`',
        ]),
      );
      expect(violations, hasLength(1));
    });

    test('GOOD mirror: --write-tree form is NOT flagged', () {
      final violations = findLegacyMergeTreeInvocations(
        _diff(['git merge-tree --write-tree "\$BASE" "\$A" "\$B"']),
      );
      expect(violations, isEmpty);
    });

    test('GOOD: bare prose naming the command in a short code span is NOT flagged', () {
      final violations = findLegacyMergeTreeInvocations(
        _diff([
          'confirmed via `git merge-tree` in a form that emits no conflict markers.',
        ]),
      );
      expect(violations, isEmpty);
    });

    test('GOOD: prose already citing the fixed form is NOT flagged', () {
      final violations = findLegacyMergeTreeInvocations(
        _diff([
          'used `git merge-tree --write-tree` and confirmed the conflict sets independently: 2 conflicts',
        ]),
      );
      expect(violations, isEmpty);
    });

    test('GOOD: bare command with zero trailing tokens is NOT flagged', () {
      final violations = findLegacyMergeTreeInvocations(
        _diff(['See `git merge-tree` for the merge simulation primitive.']),
      );
      expect(violations, isEmpty);
    });

    test('unrelated added lines produce no violations', () {
      final violations = findLegacyMergeTreeInvocations(
        _diff(['echo hello world', 'git status']),
      );
      expect(violations, isEmpty);
    });

    test('only ADDED (+) lines are scanned, not context or removed lines', () {
      final diff = '''
diff --git a/scripts/example.sh b/scripts/example.sh
+++ b/scripts/example.sh
-git merge-tree main feature-x feature-x-rebased
 unchanged context line
''';
      final violations = findLegacyMergeTreeInvocations(diff);
      expect(violations, isEmpty);
    });

    test('violation carries the file it was found in', () {
      final violations = findLegacyMergeTreeInvocations(
        _diff(
          ['git merge-tree main feature-x feature-x-rebased'],
          file: 'docs/runbook.md',
        ),
      );
      expect(violations.single.file, 'docs/runbook.md');
    });
  });

  // -------------------------------------------------------------------------
  // MUTATION PROOF (CLAUDE.md rule 24): _isLegacyInvocation was deliberately
  // neutered (forced to `return false`, i.e. the gate always passes) and this
  // suite re-run. Result: 3 of 9 reddened -- the two BAD-case tests (plain
  // shell invocation, markdown-wrapped piped invocation), PLUS "violation
  // carries the file it was found in" (which also exercises a BAD-case
  // input and crashed on `.single` over an empty list once detection found
  // nothing). The six GOOD-case tests and the two other negative tests
  // stayed green, because they assert emptiness either way. Restored
  // afterward and re-confirmed all 9 green. (First draft of this comment
  // claimed "2 of 8 reddened" before the mutation was actually run --
  // corrected to the real, run count per feedback_green_check_input_set_width
  // instance #33/#41: never cite a mutation count you didn't produce against
  // the artifacts as they now stand.)
  // -------------------------------------------------------------------------
}
