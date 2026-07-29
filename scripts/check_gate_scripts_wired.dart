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
// P1.H / F2 extension (discipline-overhaul, 2026-06-18): ALSO enumerate
// `scripts/validate_*.dart` and `scripts/audit_*.dart`. These are non-check_*
// enforcement scripts and the old gate was blind to them (G3 hole from the
// fool-proofing review). For each, require it be invoked SOMEWHERE in
// pre-commit.sh OR test.yml (an explicit `dart run scripts/<name>.dart`
// mention — they're not in the `check_*` loop), OR be in
// `_explicitAllowList` for genuinely on-demand validators (on-demand = run
// by a skill or hook, not the auto-loop). Library files with no `main()` are
// excluded from the scan.
//
// Exit 0 = pass: every check/validate/audit script invoked from both surfaces
//          (or allow-listed).
// Exit 1 = fail.
//
// Allowlist: gates that are intentionally NOT in both surfaces (e.g.
// build-only gates that run from /build-apk skill) are listed here with
// reason.

import 'dart:io';

import 'gate_scripts_wired_lib.dart';

const _allowList = <String, String>{
  // Gates that run from /build-apk skill, not pre-commit/CI (too slow
  // or require build artifacts).
  'check_apk_size_within_bounds.dart':
      'Needs an APK; runs from /build-apk Gate 13.',
  'check_apk_release_signed.dart':
      'Needs an APK + apksigner + JDK; runs from /build-apk Gate 48 (post-build).',
  'check_hooks_installed.dart':
      'Local-dev hook-presence check; CI runners never run setup-hooks.sh so .git/hooks is absent by design. Runs in pre-commit (hooks present) only; skipped in the CI workflow case-block.',
  'check_plan_review_record_exists.dart':
      'P1.A keystone (§4.12) — runs ONLY in the dedicated `plan-review-record` CI job (push-to-main, fetch-depth:0) where the PUSH_BEFORE..HEAD range base is reachable; the shallow pre-commit + main-test loops skip it via their case-blocks.',
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
  'check_two_user_cross_account.dart':
      'Requires live DB rollback-txn — runs in /build-apk skill alongside check_onconflict_live_arbiter.dart (two-user cross-account isolation, d4b8e2/f7e3a1).',
  'check_regression_catalog.dart':
      'Runs explicitly on merge commits via scripts/pre-commit.sh:48 (not auto-loop). 1 missing test for swap_undo_snackbar bug tracked separately.',
  'check_snapshot_contract.dart':
      'Requires generated snapshot manifest — runs in /build-apk skill. 1 reader-contract violation tracked separately.',
  'check_test_runtime_budget.dart':
      'Runs `flutter test --reporter json` internally — too slow for pre-commit. Manual / CI artifact gate (Gate 41 audit T9).',
  'check_no_deferral_euphemism.dart':
      'Scans the STAGED diff (git diff --cached) for deferral-euphemism phrases (§4.2) — meaningful ONLY at pre-commit; CI has no staged index. Hard-fail in scripts/pre-commit.sh (baseline soak cleared 2026-06-28); case-skipped from the auto-loop, invoked explicitly.',
  'check_closes_oi_cited.dart':
      'Commit-msg gate for the closes-oi convention (§7 pointer table / docs/audit/open_issues.md:17) — takes the proposed commit message file as its REQUIRED argument, which the check_*.dart loop never supplies. Bare invocation is a usage-error exit, not a real gate verdict. Case-skipped from BOTH scripts/pre-commit.sh and the .github/workflows/test.yml loop; wired instead in scripts/commit-msg.sh. Without this entry, the dynamic-wiring inference below (absence from a case-skip block reads as "covered by the loop") misclassifies a guaranteed crash as wired — a9f2c6.',
};

// Explicit allowlist for validate_*.dart and audit_*.dart scripts (P1.H/F2).
// These are NOT in the check_* dynamic loop, so they need an explicit
// `dart run scripts/<name>.dart` somewhere in pre-commit.sh OR test.yml,
// OR a matching entry here with a reason they are genuinely on-demand.
//
// "On-demand" means: the script is a per-artifact validator invoked by a
// skill/hook at authoring time (not a repo-wide gate that should fire on
// every commit). Library files without a main() are excluded from scanning
// entirely (they can never be `dart run`-ned).
const _explicitAllowList = <String, String>{
  // Library modules (no main() — cannot be dart-run directly).
  'validate_diagnose_doc_lib.dart':
      'Library module (no main()); imported by validate_diagnose_doc.dart and '
          'check_bugfix_commits_have_diagnose.dart.',
  'validate_agent_diagnose_stanza_lib.dart':
      'Library module (no main()); imported by validate_agent_diagnose_stanza.dart.',

  // Per-artifact on-demand validators (invoked by commit-msg.sh, skill hooks,
  // or manually at authoring time — NOT repo-wide loop gates).
  'validate_diagnose_doc.dart':
      'Per-artifact validator; invoked by scripts/commit-msg.sh:65 at commit '
          'time for bug-fix commits, and by /build-apk Gate 10. Not a loop gate.',
  'validate_agent_diagnose_stanza.dart':
      'Per-artifact validator for subagent diagnose stanza output; invoked '
          'manually by the /diagnose-bug skill. Not a repo-wide loop gate.',
  'validate_adr.dart':
      'Per-artifact validator; invoked by the /adr skill after authoring a new '
          'ADR. Not a repo-wide loop gate.',
  'validate_incident_doc.dart':
      'Per-artifact validator; invoked by the /incident skill after authoring an '
          'incident post-mortem. Not a repo-wide loop gate.',
  'validate_markdown_links.dart':
      'Advisory link-rot check; walks all docs/*.md + CLAUDE.md files. '
          'Too broad for pre-commit (touches .claude/worktrees links that may be '
          'stale by design). Run manually / in audit batches.',

  // On-demand audit scripts (require flutter test --reporter=json or full git
  // log scan — too slow for pre-commit, not suitable for the check_* loop).
  'audit_discipline_history.dart':
      'Discipline-history audit (full git log scan since 2026-04-24); too slow '
          'for pre-commit. Run manually or in quarterly audit batches.',
  'audit_test_pyramid.dart':
      'Test-pyramid classifier; requires `flutter test --reporter=json` — too '
          'slow for pre-commit. Run manually or in quarterly audit batches.',
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

  // --- check_*.dart (existing logic, unchanged) ---
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
  final preCommitCaseSkips = extractCaseSkips(preCommitContent, caseSkipRegex);
  final workflowCaseSkips = extractCaseSkips(workflowContent, caseSkipRegex);

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

  // --- validate_*.dart and audit_*.dart (P1.H/F2 extension) ---
  // These are NOT in the dynamic check_* loop. Each must either:
  //   (a) appear as an explicit `dart run scripts/<name>.dart` call in
  //       pre-commit.sh OR test.yml, OR
  //   (b) be in _explicitAllowList (genuinely on-demand).
  // Library files without main() are excluded via _explicitAllowList.
  final allNonCheck = scriptsDir
      .listSync()
      .whereType<File>()
      .map((f) => f.path.split(RegExp(r'[\\/]')).last)
      .where((n) =>
          (n.startsWith('validate_') || n.startsWith('audit_')) &&
          n.endsWith('.dart'))
      .toList();

  for (final script in allNonCheck) {
    if (_explicitAllowList.containsKey(script)) continue;
    // Must appear as an explicit invocation in at least one surface.
    final inPreCommit = preCommitContent.contains(script);
    final inWorkflow = workflowContent.contains(script);
    if (!inPreCommit && !inWorkflow) {
      unwired.add('$script [validate_*/audit_*] (not in pre-commit OR workflow, '
          'and no _explicitAllowList entry)');
    }
    // Note: validate_*/audit_* only need ONE surface (not both) when they're
    // single-surface by design (e.g. Gate 40 runs both, but a commit-msg-only
    // validator is acceptable with just one). If a script is wired to BOTH
    // surfaces that's fine — we only fail on zero coverage.
  }

  final tag = warnOnly ? '[Gate 33 WARN]' : '[Gate 33]';
  final total = allChecks.length + allNonCheck.length;
  if (unwired.isEmpty) {
    stdout.writeln('$tag PASS: all $total gate/validator scripts covered '
        '(${allChecks.length} check_*, ${allNonCheck.length} validate_*/audit_*).');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${unwired.length} script(s) not covered:');
  for (final u in unwired) {
    stderr.writeln('  - $u');
  }
  stderr.writeln('');
  stderr.writeln('Fix (check_*): add `dart run scripts/<name>.dart` to BOTH:');
  stderr.writeln('  - scripts/pre-commit.sh');
  stderr.writeln('  - .github/workflows/test.yml');
  stderr.writeln('Fix (validate_*/audit_*): add `dart run scripts/<name>.dart`');
  stderr.writeln('  to pre-commit.sh or test.yml, OR add an entry to');
  stderr.writeln('  _explicitAllowList with a reason (on-demand validators only).');
  exit(warnOnly ? 0 : 1);
}
