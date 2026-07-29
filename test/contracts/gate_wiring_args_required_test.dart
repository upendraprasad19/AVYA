// test/contracts/gate_wiring_args_required_test.dart
//
// Regression control for a9f2c6's sibling: scripts/check_closes_oi_cited.dart
// requires a <commit-msg-file> argument. scripts/pre-commit.sh's dynamic
// `for GATE in scripts/check_*.dart` loop case-skipped it correctly; the
// SEPARATE, hand-maintained copy of that same loop inside
// .github/workflows/test.yml did not. CI bare-invoked it, got a usage-error
// exit, and reported "Gate failed: check_closes_oi_cited.dart" on a merge
// commit that had already landed on main (96c6fac2).
//
// The deeper hole: scripts/check_gate_scripts_wired.dart (Gate 33) exists
// specifically to catch "not wired everywhere" — but its dynamic-loop
// inference (`workflowDynamic && !workflowCaseSkips.contains(script)`) reads
// ABSENCE from the case-skip block as PRESENCE in coverage. That is correct
// for a gate that tolerates bare invocation, and silently wrong for one that
// crashes on it. Gate 33 reported PASS on the exact commit that broke CI,
// because the missing skip-list entry was the thing that made the script
// look "covered by the loop." Same shape as a9f2c6: an absence read as a
// success signal instead of being classified and possibly failing closed.
//
// These three assertions each fail independently against the pre-fix
// content (verified by hand before writing this file, per
// feedback_source_grep_false_confidence.md) and all three must hold for the
// crash to be structurally prevented, not just patched once.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _gate = 'check_closes_oi_cited.dart';

Set<String> _extractCaseSkips(String content) {
  final pattern = RegExp(r'check_[a-z0-9_]+\.dart');
  final skips = <String>{};
  var inCase = false;
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('case ') && trimmed.contains(' in')) {
      inCase = true;
      continue;
    }
    if (inCase && trimmed == 'esac') {
      inCase = false;
      continue;
    }
    if (!inCase) continue;
    for (final m in pattern.allMatches(line)) {
      skips.add(m.group(0)!);
    }
  }
  return skips;
}

void main() {
  test('check_closes_oi_cited.dart is case-skipped in scripts/pre-commit.sh', () {
    final src = File('scripts/pre-commit.sh').readAsStringSync();
    expect(_extractCaseSkips(src), contains(_gate),
        reason: 'a bare `dart run scripts/$_gate` with no commit-msg-file '
            'argument prints its Usage line and exits non-zero — the '
            'dynamic check_*.dart loop must skip it, not invoke it');
  });

  test(
      'check_closes_oi_cited.dart is case-skipped in '
      '.github/workflows/test.yml (the a9f2c6-sibling bug: this exact line '
      'was missing when it broke CI on 96c6fac2)', () {
    final src = File('.github/workflows/test.yml').readAsStringSync();
    expect(_extractCaseSkips(src), contains(_gate),
        reason: 'CI\'s "Run all check_*.dart gates" step is a SEPARATE, '
            'hand-maintained copy of the same loop+case-skip pattern as '
            'pre-commit.sh — being skip-listed in one does not skip-list '
            'the other');
  });

  test(
      'check_closes_oi_cited.dart is in check_gate_scripts_wired.dart\'s '
      '_allowList (closes Gate 33\'s blind spot, not just this one crash)',
      () {
    final src =
        File('scripts/check_gate_scripts_wired.dart').readAsStringSync();
    final allowListSection =
        src.substring(src.indexOf('const _allowList'), src.indexOf('};') + 2);
    expect(allowListSection, contains("'$_gate'"),
        reason: 'without an _allowList entry, Gate 33\'s dynamic-wiring '
            'inference treats "absent from a case-skip block" as "covered '
            'by the loop" — which is exactly backwards for an args-required '
            'gate, and is why Gate 33 reported PASS on the commit that '
            'broke CI');
  });
}
