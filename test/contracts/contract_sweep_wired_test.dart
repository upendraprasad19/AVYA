// test/contracts/contract_sweep_wired_test.dart
//
// Pins the OI-220 wiring of scripts/contract_sweep.dart into scripts/pre-push.sh.
//
// WHY A SOURCE PIN: the sweep is deliberately NOT a check_* gate (the
// pre-commit + CI loops enumerate check_*.dart and would spawn flutter test at
// every commit), so rule 24's ledger -- which enumerates check_* only -- has no
// entry for it and Gate 33 (check_gate_scripts_wired.dart) does not see it.
// Without this file a "tidy" could un-wire it and every gate would stay green.
//
// WHAT IT PROVES AND WHAT IT DOES NOT: source ORDER, by line index, on a
// comment-stripped read. It cannot show the line is REACHED -- an
// `if false; then ... fi` wrapper would pass here. That half is
// test/scripts/pre_push_analyze_always_e2e_test.dart's PRE_PUSH_FULL placement
// scenario, which runs the real hook and asserts the runner's skip verdict
// appears before run_full_suite()'s exit 0. Same split as
// hook_gate_placement_test (order) + pre_push_analyze_always_e2e_test (behaviour).

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Pins the OI-220 wiring: no ledger entry covers scripts/contract_sweep.dart
/// (it is not a check_* gate), so without this a "tidy" could un-wire it green.
void main() {
  test('pre-push.sh invokes contract_sweep.dart on a live line below analyze and above run_full_suite', () {
    final lines = File('scripts/pre-push.sh').readAsLinesSync();
    int idx(bool Function(String) p) => lines.indexWhere((l) => !l.trim().startsWith('#') && p(l));
    final analyze = idx((l) => l.contains('flutter analyze --no-fatal-infos'));
    final sweep = idx((l) => l.contains('run scripts/contract_sweep.dart'));
    final suite = idx((l) => l.contains('run_full_suite()'));
    expect(analyze, greaterThanOrEqualTo(0));
    expect(sweep, greaterThan(analyze), reason: 'the sweep runs after the unconditional analyze');
    expect(suite, greaterThan(sweep), reason: 'the sweep runs for every tier, above the full-suite block');
    expect(lines[sweep], contains(r'"$DART_BIN" run'), reason: 'resolved via _dart_bin.sh, not bare dart');
  });
}
