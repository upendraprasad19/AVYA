// test/scripts/gate_existssync_file_vs_dir_lib_test.dart
//
// Unit tests for the pure logic behind scripts/check_gate_existssync_file_vs_dir.dart
// (scripts/gate_existssync_file_vs_dir_lib.dart). Pure, no git, no filesystem
// — synthetic unified-diff text only.
//
// Mutation-proof (CLAUDE.md rule 24): temporarily neutering
// `findDirBlindExistsSyncCalls`'s detection regex (`_existsSyncCall`) to
// something that can never match reddens the "flags a bare File().existsSync()"
// and "flags an arbitrary-expression File().existsSync()" tests — 2 of 5.
// Neutering the `_gateAuthoringFile` scope check to match everything reddens
// the "ignores files outside the gate-authoring pathset" test — 1 of 5.
// Removing the `// file-only:` escape-hatch check reddens the
// "file-only comment suppresses" test — 1 of 5. Run:
//   dart test test/scripts/gate_existssync_file_vs_dir_lib_test.dart

import 'package:flutter_test/flutter_test.dart';
import '../../scripts/gate_existssync_file_vs_dir_lib.dart';

String diffFor(String path, List<String> addedLines) {
  final buf = StringBuffer();
  buf.writeln('diff --git a/$path b/$path');
  buf.writeln('--- a/$path');
  buf.writeln('+++ b/$path');
  for (final l in addedLines) {
    buf.writeln('+$l');
  }
  return buf.toString();
}

void main() {
  group('findDirBlindExistsSyncCalls', () {
    test('flags a bare File().existsSync() added in a check_*.dart gate', () {
      final diff = diffFor('scripts/check_something.dart', [
        '  if (!File(citedPath).existsSync()) {',
      ]);
      final violations = findDirBlindExistsSyncCalls(diff);
      expect(violations, hasLength(1));
      expect(violations.first, contains('scripts/check_something.dart'));
      expect(violations.first, contains('existsSync'));
    });

    test('flags File().existsSync() with an arbitrary expression inside the parens', () {
      final diff = diffFor('scripts/some_thing_lib.dart', [
        '  final ok = File(p.join(root, entry.path)).existsSync();',
      ]);
      expect(findDirBlindExistsSyncCalls(diff), hasLength(1));
    });

    test('GOOD mirror: FileSystemEntity.typeSync is NOT flagged', () {
      final diff = diffFor('scripts/check_something.dart', [
        '  final exists = FileSystemEntity.typeSync(citedPath) != FileSystemEntityType.notFound;',
      ]);
      expect(findDirBlindExistsSyncCalls(diff), isEmpty);
    });

    test('a trailing // file-only: comment suppresses the flag', () {
      final diff = diffFor('scripts/check_something.dart', [
        '  if (!File(configPath).existsSync()) { // file-only: config.yaml is never a directory',
      ]);
      expect(findDirBlindExistsSyncCalls(diff), isEmpty);
    });

    test('ignores files outside the gate-authoring pathset (defense in depth)', () {
      // Same bad shape, but in a widget file and in a non-check_*/non-*_lib/
      // non-validate_* script — both must be invisible to this gate even if
      // the caller's git pathspec were ever loosened or bypassed.
      final widgetDiff = diffFor('lib/features/train/widgets/foo.dart', [
        '  if (!File(citedPath).existsSync()) {',
      ]);
      expect(findDirBlindExistsSyncCalls(widgetDiff), isEmpty);

      final nonGateScriptDiff = diffFor('scripts/build_gate_index.dart', [
        '  if (!File(citedPath).existsSync()) {',
      ]);
      expect(findDirBlindExistsSyncCalls(nonGateScriptDiff), isEmpty);
    });

    test('a 220-existing-call file with no NEW violating line stays clean', () {
      // Simulates touching an existing gate-authoring file for an unrelated
      // reason: only genuinely ADDED lines are evaluated, never context lines.
      final diff = diffFor('scripts/check_something.dart', [
        '  // unrelated added comment, no existsSync here',
      ]);
      expect(findDirBlindExistsSyncCalls(diff), isEmpty);
    });

    test(
        'GOOD: a comment quoting the exact call shape in prose is not a '
        'call site (scripts/check_sot_behavioral_test_paths.dart:46,76 '
        'verbatim shapes — false-positived before this fix)', () {
      final diff = diffFor('scripts/check_something.dart', [
        '//     `# <id> — note`) and must resolve via File(...).existsSync() from CWD.',
        '/// EXISTENCE is the contract, not file-ness: `File(...).existsSync()` answers',
      ]);
      expect(findDirBlindExistsSyncCalls(diff), isEmpty);
    });

    test(
        'BAD: still catches a real call with a TRAILING comment on the same '
        'line (the fix must not weaken real detection)', () {
      final diff = diffFor('scripts/check_something.dart', [
        '  if (!File(citedPath).existsSync()) { // trailing note, not the whole line',
      ]);
      expect(findDirBlindExistsSyncCalls(diff), hasLength(1));
    });
  });
}
