// scripts/check_gate_scripts_wired.dart
//
// Gate 33 (Tech-debt audit 2026-05-20, finding I2): assert that every
// `scripts/check_*.dart` file is invoked from BOTH:
//   - scripts/pre-commit.sh (local enforcement)
//   - .github/workflows/test.yml (CI enforcement)
//
// The audit finding: 25 of 27 gate scripts were dormant — written but never
// wired. Pre-commit only invoked check_naming_conventions.dart +
// check_regression_catalog.dart. CI didn't invoke any. The drift detection
// these gates promised was illusory.
//
// Exit 0 = pass: every check script invoked from both surfaces.
// Exit 1 = fail.
//
// Allowlist: gates that are intentionally NOT in both surfaces (e.g.
// build-only gates that run from /build-apk skill) are listed here with
// reason.

import 'dart:io';

const _allowList = <String, String>{
  // Gates that run from /build-apk skill, not pre-commit/CI (too slow
  // or require build artifacts).
  'check_apk_size_within_bounds.dart':
      'Needs an APK; runs from /build-apk Gate 13.',
  'check_apk_release_signed.dart':
      'Needs an APK + apksigner + JDK; runs from /build-apk Gate 48 (post-build).',
  'check_hooks_installed.dart':
      'Local-dev hook-presence check; CI runners never run setup-hooks.sh so .git/hooks is absent by design. Runs in pre-commit (hooks present) only; skipped in the CI workflow case-block.',
  // check_app_version_matches_pubspec.dart was REMOVED from this allowlist
  // 2026-06-07 (in-sync sweep): the constant kept lagging pubspec, so the gate
  // now runs every commit (pre-commit + CI) — not build-time-only.
  // Gates that are advisory-only by design (per their own headers).
  'check_telemetry_pii_classification.dart':
      'Advisory per L40; surfaced in audit reports, not pre-commit gate.',
  'check_unawaited_has_error_sink.dart':
      'Advisory per L34; surfaced in audit reports, not pre-commit gate.',
  'check_razorpay_key_flavor.dart':
      '.env.prod is gitignored; runs locally before prod release only (see docs/operations/SECRET_INVENTORY.md).',
  // The next 4 gates require live Supabase / build state and were dormant
  // for that reason. Audit 2026-05-20 B1 wiring surfaced existing tech-debt
  // they detect — those issues are tracked separately and these gates run
  // manually via /build-apk skill or in dedicated remediation batches.
  'check_migrations_live.dart':
      'Requires live Supabase MCP — runs in /build-apk skill Gate 14b, not pre-commit. 1 unapplied migration tracked separately.',
  'check_onconflict_live_arbiter.dart':
      'Requires live DB rollback-txn — runs in /build-apk skill, not pre-commit. 3 schema-arbiter conflicts tracked separately.',
  'check_regression_catalog.dart':
      'Runs explicitly on merge commits via scripts/pre-commit.sh:48 (not auto-loop). 1 missing test for swap_undo_snackbar bug tracked separately.',
  'check_snapshot_contract.dart':
      'Requires generated snapshot manifest — runs in /build-apk skill. 1 reader-contract violation tracked separately.',
  'check_test_runtime_budget.dart':
      'Runs `flutter test --reporter json` internally — too slow for pre-commit. Manual / CI artifact gate (Gate 41 audit T9).',
};

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final scriptsDir = Directory('scripts');
  final preCommit = File('scripts/pre-commit.sh');
  final workflow = File('.github/workflows/test.yml');

  if (!preCommit.existsSync()) {
    stderr.writeln('[Gate 33] FAIL: scripts/pre-commit.sh missing');
    exit(warnOnly ? 0 : 1);
  }
  if (!workflow.existsSync()) {
    stderr.writeln('[Gate 33] FAIL: .github/workflows/test.yml missing');
    exit(warnOnly ? 0 : 1);
  }
  final preCommitContent = preCommit.readAsStringSync();
  final workflowContent = workflow.readAsStringSync();

  final unwired = <String>[];
  final allChecks = scriptsDir
      .listSync()
      .whereType<File>()
      .map((f) => f.path.split(RegExp(r'[\\/]')).last)
      .where((n) => n.startsWith('check_') && n.endsWith('.dart'))
      .toList();

  // Dynamic-wiring detection: a `for GATE in scripts/check_*.dart` loop
  // in pre-commit.sh / test.yml wires EVERY gate file (any new check_*.dart
  // is picked up automatically). If we detect this pattern, treat as wired
  // unless the script is in the allowlist or explicitly skipped in a case
  // block right after the loop.
  final preCommitDynamic = preCommitContent.contains('scripts/check_*.dart');
  final workflowDynamic = workflowContent.contains('scripts/check_*.dart');

  // Extract case-block skip patterns (e.g. `check_foo.dart|\\` lines after
  // a `case "$NAME" in` block). If a script appears here, it's intentionally
  // skipped by the dynamic loop and we should NOT count it as wired even if
  // the loop nominally covers it.
  final caseSkipRegex = RegExp(r'check_[a-z0-9_]+\.dart');
  final preCommitCaseSkips = _extractCaseSkips(preCommitContent, caseSkipRegex);
  final workflowCaseSkips = _extractCaseSkips(workflowContent, caseSkipRegex);

  for (final script in allChecks) {
    if (_allowList.containsKey(script)) continue;
    final inPreCommit = preCommitContent.contains(script) ||
        (preCommitDynamic && !preCommitCaseSkips.contains(script));
    final inWorkflow = workflowContent.contains(script) ||
        (workflowDynamic && !workflowCaseSkips.contains(script));
    if (!inPreCommit && !inWorkflow) {
      unwired.add('$script (not in pre-commit OR workflow)');
    } else if (!inPreCommit) {
      unwired.add('$script (not in scripts/pre-commit.sh)');
    } else if (!inWorkflow) {
      unwired.add('$script (not in .github/workflows/test.yml)');
    }
  }

  final tag = warnOnly ? '[Gate 33 WARN]' : '[Gate 33]';
  if (unwired.isEmpty) {
    stdout.writeln('$tag PASS: all ${allChecks.length} gate scripts wired (or allow-listed).');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${unwired.length} gate(s) not wired:');
  for (final u in unwired) {
    stderr.writeln('  - $u');
  }
  stderr.writeln('');
  stderr.writeln('Fix: add `dart run scripts/<name>.dart` invocation to BOTH:');
  stderr.writeln('  - scripts/pre-commit.sh');
  stderr.writeln('  - .github/workflows/test.yml');
  exit(warnOnly ? 0 : 1);
}

// Return script filenames that appear inside a shell `case "$NAME" in` block —
// these are intentionally skipped by the dynamic loop.
Set<String> _extractCaseSkips(String content, RegExp pattern) {
  final skips = <String>{};
  final lines = content.split('\n');
  var inCase = false;
  for (final line in lines) {
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
