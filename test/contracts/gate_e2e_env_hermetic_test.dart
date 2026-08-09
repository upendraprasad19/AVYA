// test/contracts/gate_e2e_env_hermetic_test.dart
//
// Diagnose c3f8e1. `10dffc90` taught the keystone gate to fall back to
// `GITHUB_EVENT_PATH` for its range base. Every GitHub Actions job sets that
// variable, so the gate e2e suites — which spawn the real gate inside a
// throwaway git repo — started reading the REAL push event, whose `before`
// names a commit that does not exist in the temp repo. The gate correctly
// refused an unresolvable base and two pre-existing tests went red in CI while
// staying green locally, where the variable does not exist at all.
//
// HONEST ABOUT WHAT THIS TEST IS. It is PRESENCE-ONLY, and deliberately so:
// the trigger is an ambient environment variable that only CI sets, and Dart
// cannot mutate its own process environment, so no in-process test can
// discriminate behaviourally. The discriminating verification was a manual
// reproduction (synthetic GITHUB_EVENT_PATH with an unreachable `before`:
// pre-fix FAILS exactly as CI did, post-fix 75 tests pass) and it is recorded
// in the diagnose-doc rather than pretended at here.
// See feedback_source_grep_false_confidence.md — a source-grep certifies the
// text, not the behaviour.
//
// What it DOES buy: if someone later "tidies" the helper back to a GIT_*-only
// filter, this fails immediately and cheaply, instead of main going red on the
// next push.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// HAND-ENUMERATED, and that is this list's one weakness: a new gate e2e helper
// is uncovered until someone remembers to add it here. Registering
// worktree_config_integrity_e2e_test.dart (2026-08-09) was an explicit step in
// its own plan for exactly that reason — the list is a green check only as wide
// as its input set.
const _helpers = <String>[
  'test/scripts/plan_review_record_gate_e2e_test.dart',
  'test/scripts/gate_input_family_e2e_test.dart',
  'test/scripts/worktree_config_integrity_e2e_test.dart',
];

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

void main() {
  group('gate e2e helpers declare their subprocess environment', () {
    for (final path in _helpers) {
      test('$path scrubs GIT_*, GITHUB_* and PUSH_BEFORE', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path must exist');
        // Comments are stripped first: this doc-comment block itself names all
        // three keys, and matching a comment would make the test self-passing.
        final src = _strip(file.readAsStringSync());

        expect(src.contains("startsWith('GIT_')"), isTrue,
            reason: 'GIT_DIR/GIT_WORK_TREE override both workingDirectory: and '
                '-C <path>, so a hook-spawned test would drive the REAL repo '
                '(feedback_mistake_git_hook_env_leak)');
        expect(src.contains("startsWith('GITHUB_')"), isTrue,
            reason: 'diagnose c3f8e1: the gate reads GITHUB_EVENT_PATH for its '
                'range base, and in CI that payload describes the real repo, '
                'not the temp one this test built');
        expect(src.contains("PUSH_BEFORE"), isTrue,
            reason: 'the explicit range base must come from the scenario via '
                'extra:, never from whatever the surrounding job exported');
      });
    }

    test('the gate really does read GITHUB_EVENT_PATH — the leak has a consumer',
        () {
      // Guards the premise. If the fallback were ever removed, the scrubbing
      // above would be cargo-cult and this test should be revisited rather than
      // silently kept.
      final gate =
          _strip(File('scripts/check_plan_review_record_exists.dart').readAsStringSync());
      expect(gate.contains('GITHUB_EVENT_PATH'), isTrue);
      expect(gate.contains('PUSH_BEFORE'), isTrue);
    });
  });
}
