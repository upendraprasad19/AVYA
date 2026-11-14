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
// HISTORY. This file used to hold a hand-enumerated token list (`_helpers`) that checked each gate
// e2e file for `startsWith('GIT_')` and friends: PRESENCE-ONLY, and exactly as wide as someone
// remembered to make it. PR 2 of batch spawn-tests-env-and-stderr replaced it with the strict
// site guards of test/contracts/spawn_sites_guard_test.dart (no raw spawn, no whole-parent
// environment, every startSpawn reported) plus the literal former-files pin there (G5). What is
// left here is the premise test.
//
// WHY THE PREMISE MATTERS. The old comment below describes the original, presence-only check:
//
// HONEST ABOUT WHAT THIS TEST IS. It WAS PRESENCE-ONLY, and deliberately so:
// the trigger is an ambient environment variable that only CI sets, and Dart
// cannot mutate its own process environment, so no in-process test can
// discriminate behaviourally. The discriminating verification was a manual
// reproduction (synthetic GITHUB_EVENT_PATH with an unreachable `before`:
// pre-fix FAILS exactly as CI did, post-fix 75 tests pass) and it is recorded
// in the diagnose-doc rather than pretended at here.
// See feedback_source_grep_false_confidence.md — a source-grep certifies the
// text, not the behaviour.
//
// What the premise test buys: if the keystone gate ever stops reading GITHUB_EVENT_PATH /
// PUSH_BEFORE, the scrubbing the helper does for them is cargo-cult and should be revisited
// rather than silently kept.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

void main() {
  group('gate e2e helpers declare their subprocess environment', () {
    test('the gate really does read GITHUB_EVENT_PATH — the leak has a consumer', () {
      final gate = _strip(File('scripts/check_plan_review_record_exists.dart').readAsStringSync());
      expect(gate.contains('GITHUB_EVENT_PATH'), isTrue);
      expect(gate.contains('PUSH_BEFORE'), isTrue);
    });
  });
}
