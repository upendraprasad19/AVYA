// Guards the timeout raise from diagnose c3f9a7 against a silent revert.
//
// Three contract files spawn REAL subprocesses (git plus `dart run`, and every
// `dart run` boots a VM — slow on Windows). At the 30s default they timed out
// whenever `flutter test` parallelised them, which is what the merge-commit
// regression walk does: five merge attempts failed with 11 / 7 / 8 / 4
// TimeoutExceptions on an UNCHANGED tree, and ZERO assertion failures. The same
// files run alone passed 38/38.
//
// WHY THIS TEST EXISTS. c3f9a7's own `regression_test_planned:` field said "None
// added, deliberately" — a test that proves "does not time out under suite-wide
// parallelism" would have to reproduce the expensive nondeterministic condition
// being fixed. Its B-pass (P2-1) accepted that reasoning and then made the
// sharper point: the DECLARATION is still checkable, and without a check, a merge
// conflict or an IDE tidy-up could quietly restore 30s and the bug would return
// disguised as flakiness — which the diagnose-doc itself calls the dangerous
// shape, "how a real red would get waved through".
//
// WHAT THIS PROVES AND WHAT IT DOES NOT — stated plainly, per rule 21's
// presence-only convention. It proves the declarations still exist and are
// generous. It does NOT prove the tests pass under load; nothing cheap can. Do
// not read a green here as evidence the timeouts are sufficient.
//
// Do not "fix" a failure here by lowering the bound. If these files stop needing
// a long timeout, the honest change is to fix OI-116 (the unbounded
// `flutter test` in check_regression_catalog.dart) first, then lower the values
// and this floor together, in one commit that says so.
@Timeout(Duration(seconds: 30))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Minimum acceptable declared timeout. Below this, the merge-commit regression
/// walk starts producing TimeoutExceptions again under normal parallelism.
/// 90s rather than the declared 120s so a deliberate, documented adjustment
/// downward has room to breathe without tripping this floor.
const int _minSeconds = 90;

/// The files whose tests spawn real subprocesses. Each MUST declare a
/// non-default timeout — either library-level `@Timeout(...)` or per-test.
const _guardedFiles = <String>[
  'test/contracts/git_safety_hook_integration_test.dart',
  'test/contracts/review_gate_staged_content_not_working_tree_test.dart',
  'test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart',
];

/// Parses every `Duration(...)` appearing inside a `Timeout(` — library
/// annotation or per-test argument — and returns each as whole seconds.
///
/// Deliberately matched by REGEX on the argument shape rather than by a literal
/// string: `feedback_mistake_guard_without_its_mirror` records a guard in this
/// repo defeated by ONE EXTRA SPACE because it matched source text literally.
List<int> _declaredTimeoutSeconds(String source) {
  final out = <int>[];
  final timeoutCall = RegExp(r'Timeout\s*\(\s*Duration\s*\(([^)]*)\)');
  for (final m in timeoutCall.allMatches(source)) {
    final args = m.group(1)!;
    final mins = RegExp(r'minutes\s*:\s*(\d+)').firstMatch(args);
    final secs = RegExp(r'seconds\s*:\s*(\d+)').firstMatch(args);
    var total = 0;
    if (mins != null) total += int.parse(mins.group(1)!) * 60;
    if (secs != null) total += int.parse(secs.group(1)!);
    if (total > 0) out.add(total);
  }
  return out;
}

void main() {
  // Resolve against the repo root, not the CWD: `flutter test` may be invoked
  // from either, and a path that silently resolves to nothing would make every
  // assertion below vacuous.
  final root = _repoRoot();

  test('the guarded-file list itself is not empty or silently mismatched', () {
    // Mirror check: if someone renames a guarded file, the loop below would
    // otherwise iterate over a shrinking set and still pass.
    expect(_guardedFiles, hasLength(3),
        reason: 'the c3f9a7 fix covered exactly three files; if that set '
            'changed, update this list deliberately rather than letting the '
            'loop below quietly guard fewer files');
    for (final rel in _guardedFiles) {
      expect(File('$root/$rel').existsSync(), isTrue,
          reason: '$rel is missing — renamed or deleted? This guard cannot '
              'protect a file it cannot find, so fix the list, do not delete '
              'the entry');
    }
  });

  for (final rel in _guardedFiles) {
    test('$rel declares a subprocess-safe timeout (>= ${_minSeconds}s)', () {
      final source = File('$root/$rel').readAsStringSync();
      final declared = _declaredTimeoutSeconds(source);

      expect(declared, isNotEmpty,
          reason: '$rel declares NO Timeout at all, so its tests inherit the '
              '30s package:test default. That is the exact pre-c3f9a7 state '
              'for review_gate_staged_content_not_working_tree_test.dart, and '
              'it is what made the merge-commit regression walk flaky.');

      final tooShort = declared.where((s) => s < _minSeconds).toList();
      expect(tooShort, isEmpty,
          reason: '$rel declares timeout(s) of $tooShort second(s), below the '
              '${_minSeconds}s floor. This file spawns real subprocesses; under '
              'suite-wide parallelism a short timeout reddens it for reasons '
              'that have nothing to do with its assertions. See diagnose '
              'c3f9a7 and OI-116.');
    });
  }
}

/// Walks up from the CWD to the directory containing `pubspec.yaml`.
String _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
      'could not locate pubspec.yaml walking up from ${Directory.current.path} '
      '— this guard would otherwise pass vacuously against missing files');
}
