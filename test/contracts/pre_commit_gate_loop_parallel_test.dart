// test/contracts/pre_commit_gate_loop_parallel_test.dart
//
// Lean-workflow batch (2026-06-01). Pins the SAFETY contract of the
// bounded-parallel pre-commit gate loop (scripts/pre-commit.sh):
//
//   - It STILL preserves the two textual markers that Gate 33
//     (scripts/check_gate_scripts_wired.dart) relies on to prove every gate is
//     wired: the literal `scripts/check_*.dart` glob + the
//     `case "$GATE_NAME" in ... esac` allowlist block. Dropping either would
//     make every gate read as "unwired" (silent loss of enforcement).
//   - It runs gates with BOUNDED concurrency (PRE_COMMIT_GATE_JOBS) — not 28
//     Dart VMs at once.
//   - It still AGGREGATES per-gate failures and BLOCKS the commit on any failure.
//   - It prints the non-blocking >=account /code-review reminder.
//
// Comment-stripped source-grep (per feedback_source_grep_strip_comments_first.md)
// so the explanatory header can't false-pass the assertions.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    final f = File('scripts/pre-commit.sh');
    expect(f.existsSync(), isTrue, reason: 'scripts/pre-commit.sh must exist');
    src = _stripShellComments(f.readAsStringSync());
  });

  test('preserves Gate 33 wiring markers (glob + case allowlist)', () {
    expect(src.contains('scripts/check_*.dart'), isTrue,
        reason: 'check_gate_scripts_wired.dart detects dynamic wiring via the '
            'literal scripts/check_*.dart glob — parallelization must keep it');
    expect(src.contains(r'case "$GATE_NAME" in'), isTrue,
        reason: 'Gate 33 parses the `case "\$GATE_NAME" in ... esac` block for '
            'the allowlist of intentionally-skipped gates — it must remain');
    expect(src.contains('check_apk_size_within_bounds.dart'), isTrue,
        reason: 'the build-only gate allowlist must stay inside the case block');
  });

  test('runs gates with bounded concurrency (no 28-Dart-VM fork bomb)', () {
    expect(src.contains('PRE_COMMIT_GATE_JOBS'), isTrue,
        reason: 'concurrency must be bounded + configurable, default 4');
    expect(src.contains('wait || true'), isTrue,
        reason: 'the loop must drain each background batch before the next '
            '(bounded parallelism), tolerating a failed job\'s exit');
  });

  test('aggregates per-gate failures and blocks the commit', () {
    expect(src.contains('GATE_FAILDIR'), isTrue,
        reason: 'failures must be collected (one marker file per failed gate)');
    expect(src.contains('GATE_FAIL=1'), isTrue,
        reason: 'any failed gate must set the failure flag');
    expect(src.contains('One or more gates failed'), isTrue,
        reason: 'the commit must be blocked (exit 1) when any gate fails');
  });

  test('prints the >=account /code-review reminder', () {
    expect(src.contains('account|platform|catastrophic'), isTrue,
        reason: 'the reminder must fire for the >=account tiers');
    expect(src.contains('code-review'), isTrue,
        reason: 'the reminder must point the founder at /code-review (B-pass)');
  });
}

/// Strips shell comments (`#!` shebang, full-line `# ...`, inline ` # ...`) so
/// assertions match real CODE, not the explanatory header. Safe for these hooks
/// — they contain no `#` inside string literals (verified).
String _stripShellComments(String shell) {
  final out = StringBuffer();
  for (final line in shell.split('\n')) {
    if (line.trimLeft().startsWith('#')) continue; // full-line comment / shebang
    final idx = line.indexOf(' #'); // inline comment (space-hash to EOL)
    out.writeln(idx >= 0 ? line.substring(0, idx) : line);
  }
  return out.toString();
}
