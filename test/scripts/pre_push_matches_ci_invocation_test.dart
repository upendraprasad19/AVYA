// Pins scripts/pre-push.sh's full-suite invocation to CI's.
//
// WHY THIS EXISTS. pre-push ran a bare `flutter test` while
// .github/workflows/test.yml runs `flutter test test/ --exclude-tags golden`
// under `TZ: Asia/Kolkata`. A gate that is STRICTER than CI in the wrong
// direction is worse than no gate: every failure it produces is a false red,
// the only way past a false red is `--no-verify`, and `--no-verify` disables
// the real gates too. Measured 2026-08-20 — 4 failures under the bare form
// (2 Windows goldens + 2 IST date-boundary contracts), 0 under CI's form, same
// commit, same machine.
//
// Written as a COMPARISON between the two files rather than as a hardcoded
// expected string, so it stays true when CI's invocation legitimately changes:
// edit one side only and this reddens.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// The `flutter test ...` COMMAND in pre-push, comments stripped so a
/// commented-out example can never satisfy the assertion.
///
/// The pattern is anchored at the start of the line (allowing only leading
/// `VAR=value` env assignments) rather than matching `flutter test` anywhere.
/// The loose form matched pre-push's own progress `echo`, whose message quotes
/// the command it is about to run — so the test read the echo, saw no flags,
/// and reported the gap as still open while the real invocation was correct.
final _invocation = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*=\S+\s+)*flutter\s+test(\s|$)');

String _prePushSuiteInvocation() {
  for (final raw in File('scripts/pre-push.sh').readAsLinesSync()) {
    final line = raw.trim();
    if (line.startsWith('#') || line.startsWith('echo ')) continue;
    if (_invocation.hasMatch(line)) return line;
  }
  return '';
}

String _ciSuiteInvocation() {
  final lines = File('.github/workflows/test.yml').readAsLinesSync();
  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('#')) continue;
    final cmd = line.replaceFirst(RegExp(r'^run:\s*'), '').trim();
    if (!_invocation.hasMatch(cmd)) continue;
    // The analyze-and-unit-test job's suite line; skip integration/device jobs
    // that invoke a different target.
    if (cmd.contains('integration_test')) continue;
    return cmd;
  }
  return '';
}

void main() {
  test('pre-push runs the full suite with the SAME tag filter as CI', () {
    final pre = _prePushSuiteInvocation();
    final ci = _ciSuiteInvocation();
    expect(pre, isNotEmpty, reason: 'no flutter test line found in pre-push.sh');
    expect(ci, isNotEmpty, reason: 'no flutter test line found in test.yml');

    expect(ci.contains('--exclude-tags golden'), isTrue,
        reason: 'baseline assumption: CI excludes the golden tag. If CI stopped '
            'doing that, this whole test needs rethinking rather than updating.');
    expect(pre.contains('--exclude-tags golden'), isTrue,
        reason: 'pre-push must exclude the golden tag exactly as CI does '
            '(test.yml). The goldens are rendered on Windows and fail on font '
            'rasterisation everywhere else, so without this every non-Windows '
            'push is a false red — and the only way past a false red is '
            '--no-verify, which disables the real gates too.\n'
            '  pre-push: $pre\n  CI:       $ci');
  });

  test('pre-push runs the full suite in the SAME timezone as CI', () {
    final pre = _prePushSuiteInvocation();

    final ciEnvTz = File('.github/workflows/test.yml')
        .readAsLinesSync()
        .map((l) => l.trim())
        .firstWhere((l) => RegExp(r'^TZ:\s*\S').hasMatch(l), orElse: () => '');
    expect(ciEnvTz, isNotEmpty,
        reason: 'baseline assumption: CI pins TZ at workflow level.');
    final zone = ciEnvTz.split(':').sublist(1).join(':').trim();
    expect(zone, isNotEmpty);

    expect(pre.contains('TZ=$zone'), isTrue,
        reason: 'pre-push must run the suite under the same zone CI pins '
            '($zone). Several date-boundary contracts assert IST behaviour and '
            'read the ambient zone; under UTC they fail for reasons that have '
            'nothing to do with the pushed change.\n  pre-push: $pre');
  });

  test('the invocation is inside run_full_suite, not stranded in a comment', () {
    final body = File('scripts/pre-push.sh').readAsStringSync();
    final start = body.indexOf('run_full_suite() {');
    expect(start, greaterThan(-1), reason: 'run_full_suite must still exist');
    final end = body.indexOf('\n}', start);
    expect(end, greaterThan(start));

    final fnBody = body
        .substring(start, end)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => !l.startsWith('#'))
        .join('\n');
    expect(RegExp(r'TZ=\S+\s+flutter\s+test\s').hasMatch(fnBody), isTrue,
        reason: 'the CI-equivalent invocation must be the one run_full_suite '
            'actually executes — a correct command sitting in a comment above '
            'the function protects nothing (the Gate-44 shape).');
  });
}
