// test/contracts/pre_push_blast_radius_failsafe_test.dart
//
// Lean-workflow batch (2026-06-01). Pins the SAFETY contract of the
// blast-radius-tiered pre-push hook (scripts/pre-push.sh):
//
//   - It computes the pushed-range tier from `origin/main..HEAD` via
//     scripts/blast_radius_from_diff.dart.
//   - It SKIPS the local full suite ONLY for `feature` tier.
//   - It is FAIL-SAFE: an empty/undetermined range (or any other tier) RUNS
//     the full `flutter test` — it must never skip on uncertainty.
//   - `PRE_PUSH_FULL=1` always forces the full suite.
//
// Source-grep over the COMMENT-STRIPPED script so the explanatory header (which
// mentions the same tokens in prose) can't false-pass the assertions — the
// asserted strings must live in real shell CODE. Per
// feedback_source_grep_strip_comments_first.md.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    final f = File('scripts/pre-push.sh');
    expect(f.existsSync(), isTrue, reason: 'scripts/pre-push.sh must exist');
    src = _stripShellComments(f.readAsStringSync());
  });

  test('computes the pushed-range tier from origin/main..HEAD via the helper', () {
    expect(src.contains('origin/main..HEAD'), isTrue,
        reason: 'pre-push must derive the range from the unpushed commits '
            '(origin/main..HEAD), not the staged diff');
    expect(src.contains('blast_radius_from_diff.dart'), isTrue,
        reason: 'pre-push must compute the tier via blast_radius_from_diff.dart');
  });

  test('skips the local full suite ONLY on feature tier', () {
    expect(src.contains(r'"$TIER" = "feature"'), isTrue,
        reason: 'the skip must be gated on tier == feature (not unconditional)');
  });

  test('is fail-safe: empty/undetermined range runs the full suite', () {
    // The empty-range guard must exist AND route to running the suite.
    expect(src.contains(r'-z "$RANGE_FILES"'), isTrue,
        reason: 'must guard an empty push range and fall through to running');
    expect(src.contains('run_full_suite'), isTrue,
        reason: 'a shared helper must run the full suite on the safe-default paths');
    expect(src.contains('flutter test'), isTrue,
        reason: 'the full suite (flutter test) must still run for >=account / unknown');
    // origin/main absence must also fail-safe (guard present → run_full_suite).
    expect(src.contains('rev-parse --verify --quiet origin/main'), isTrue,
        reason: 'an absent origin/main must be guarded and fall back to running the suite');
  });

  test('PRE_PUSH_FULL=1 escape hatch forces the full suite', () {
    expect(src.contains('PRE_PUSH_FULL'), isTrue,
        reason: 'an explicit override must always be able to force the full suite');
  });
}

/// Strips shell comments (`#!` shebang, full-line `# ...`, and inline ` # ...`)
/// so assertions match real CODE, not the explanatory header. Safe for these
/// hooks — they contain no `#` inside string literals (verified).
String _stripShellComments(String shell) {
  final out = StringBuffer();
  for (final line in shell.split('\n')) {
    if (line.trimLeft().startsWith('#')) continue; // full-line comment / shebang
    final idx = line.indexOf(' #'); // inline comment (space-hash to EOL)
    out.writeln(idx >= 0 ? line.substring(0, idx) : line);
  }
  return out.toString();
}
