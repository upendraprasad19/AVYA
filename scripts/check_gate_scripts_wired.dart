// scripts/check_gate_scripts_wired.dart
//
// Gate: 33
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
// Allowlist: gates that are intentionally NOT in both loops are listed here
// with a TYPED runner (gate_scripts_wired_lib.dart `GateRunner`) that this
// gate re-verifies on every commit — never free prose.
//
// OI-155 (gate-integrity batch, 2026-09-19): until this fix `_allowList` was
// `Map<String, String>` and its prose was read by nothing. Six entries claimed
// runners that did not exist ("runs in /build-apk skill Gate 14b" — no such
// section; `grep -ic 14b .claude/commands/build-apk.md` → 0), so six gates ran
// NOWHERE while this gate reported PASS. Three runner kinds now exist:
//   file(path)   — path INVOKES the gate (`run scripts/<gate>`, non-comment)
//   loop(name)   — the named dynamic loop does NOT case-skip it
//   manual(OI-N) — nothing runs it; the OI is OPEN/IN_PROGRESS on the boards
//                  (CLOSED / absent / unreadable board ⇒ FAIL — closing the
//                  blocker without giving the gate a runner turns this red)
// and an allowlist key with no scripts/<key> on disk is itself a violation.
// The dynamic-wiring inference for non-allowlisted gates now also requires an
// INVOCATION (`invokesGate`), not a `contains(name)` mention.

import 'dart:io';

import 'gate_scripts_wired_lib.dart';
import 'oi_closure_lib.dart' show mergedBoardStatuses;

const _allowList = <String, List<GateRunner>>{
  // Gates that run from /build-apk skill, not pre-commit/CI (too slow
  // or require build artifacts).
  'check_apk_size_within_bounds.dart': [
    GateRunner.file('.claude/commands/build-apk.md',
        'Needs an APK; /build-apk Gate 13.'),
  ],
  'check_apk_release_signed.dart': [
    GateRunner.file('.claude/commands/build-apk.md',
        'Needs an APK + apksigner + JDK; /build-apk Gate 48 (post-build).'),
  ],
  'check_hooks_installed.dart': [
    GateRunner.loop('preCommit',
        'Local-dev hook-presence check; CI runners never run setup-hooks.sh, so .git/hooks is absent there by design. Case-skipped in test.yml only.'),
  ],
  'check_plan_review_record_exists.dart': [
    GateRunner.file('.github/workflows/test.yml',
        'P1.A keystone (§4.12) -- runs ONLY in the dedicated `plan-review-record` CI job (fetch-depth:0) where the PUSH_BEFORE..HEAD range base is reachable; the shallow pre-commit + main-test loops case-skip it.'),
  ],
  // check_app_version_matches_pubspec.dart was REMOVED from this allowlist
  // 2026-06-07 (in-sync sweep): the constant kept lagging pubspec, so the gate
  // now runs every commit (pre-commit + CI) — not build-time-only.
  // Gates that are advisory-only by design (per their own headers).
  // check_telemetry_pii_classification.dart was exempted here as "advisory per
  // L40; surfaced in audit reports, not pre-commit gate" — but it was surfaced
  // in NOTHING. Zero invocation sites: skip-listed in pre-commit.sh AND
  // test.yml AND absent from build-apk.md. "Advisory" described how it reports,
  // not where it runs, and nothing ran it. Wired into both loops 2026-08-17;
  // it is a pure lib/ source scan (436 callsites, 1.5s) with no live dependency.
  'check_unawaited_has_error_sink.dart': [
    GateRunner.loop('ci',
        'ADVISORY (exit 0 by design, --strict to fail). CI\'s log is its only reader: pre-commit.sh runs every loop gate as >/dev/null 2>&1, so it stays case-skipped there -- a 1.7 s no-op nobody can read. Removed from test.yml\'s case-skip 2026-09-19 (OI-155).'),
  ],
  'check_razorpay_key_flavor.dart': [
    GateRunner.file('.claude/commands/build-apk.md',
        '.env.prod is gitignored; runs locally before a prod release only (see docs/operations/SECRET_INVENTORY.md).'),
  ],
  // The next three gates need live Supabase state and run NOWHERE automated.
  // Each `manual:` cites the OPEN OI that owns the reason, and this gate
  // re-checks that status on every commit. Until 2026-09-19 these entries
  // read "runs in /build-apk skill" — build-apk.md never invoked any of them.
  'check_onconflict_live_arbiter.dart': [
    GateRunner.manual('OI-165',
        'Live rollback-txn SQL via the Management API; 403s with the current PAT. No automated runner until OI-165 names the token.'),
  ],
  'check_two_user_cross_account.dart': [
    GateRunner.manual('OI-165',
        'Wrapper over check_onconflict_live_arbiter.dart; inherits its 403. Documented by-hand runner: docs/runbooks/restore-drill.md:71.'),
  ],
  'check_regression_catalog.dart': [
    GateRunner.file('scripts/pre-commit.sh',
        'Explicit merge-commit invocation (MERGE_HEAD present), not the auto-loop.'),
  ],
  // check_snapshot_contract.dart has NO entry since 2026-09-19 (OI-155): it
  // runs in BOTH loops (its case-skip lines were deleted; passes today). Its
  // old entry claimed "runs in /build-apk skill" — nothing ran it.
  'check_test_runtime_budget.dart': [
    GateRunner.manual('OI-101',
        'Spawns the FULL `flutter test --reporter json`; re-arm-or-delete is OI-101 (founder scope call).'),
  ],
  'check_no_deferral_euphemism.dart': [
    GateRunner.file('scripts/pre-commit.sh',
        'Scans the STAGED diff (git diff --cached) for deferral-euphemism phrases (§4.2) -- meaningful ONLY at pre-commit (CI has no staged index); explicit invocation after the loop, hard-fail since the 2026-06-28 soak.'),
  ],
  'check_closes_oi_cited.dart': [
    GateRunner.file('scripts/commit-msg.sh',
        'Commit-msg gate for the closes-oi convention (docs/audit/open_issues.md) -- takes the proposed commit message file as its REQUIRED argument, which the check_*.dart loop never supplies; bare invocation is a usage-error exit (a9f2c6). Case-skipped from BOTH loops.'),
  ],
};

/// A file's content, or `null` when it does not exist. A plain top-level
/// function placed AFTER the map on purpose: gate_wiring_args_required_test
/// slices this file from `const _allowList` to the FIRST `};`, so nothing
/// that closes with `};` may sit above the map.
String? _readOrNull(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsStringSync() : null;
}

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
  'validate_food_tag_export.dart':
      'Per-artifact validator for the food-DB tagged export (takes the export '
          'file PATH as an argument — nothing to validate at commit time unless '
          'an export is being swapped). Invoked manually by the '
          'diet-plan-meal-quality batch flow (diagnose d3c7a9) before replacing '
          'assets/data/food_database.json.',

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
  final preCommitDynamic = preCommitContent.contains(dynamicLoopMarker);
  final workflowDynamic = workflowContent.contains(dynamicLoopMarker);

  // Extract case-block skip patterns (e.g. `check_foo.dart|\\` lines after
  // a `case "$NAME" in` block). If a script appears here, it's intentionally
  // skipped by the dynamic loop and we should NOT count it as wired even if
  // the loop nominally covers it.
  final preCommitCaseSkips = extractCaseSkips(preCommitContent, caseSkipRegex);
  final workflowCaseSkips = extractCaseSkips(workflowContent, caseSkipRegex);

  // The merged OI boards, for `manual:` runners. `null` = the OPEN board is
  // unreadable, which every manual runner treats as FAIL (an unverifiable
  // claim is not a satisfied one). An unreadable CLOSED board degrades to
  // "not on the closed board" — a target that exists only there then reads
  // as absent and fails, which is the fail-closed direction.
  final open = _readOrNull('docs/audit/open_issues.md');
  final boardStatuses = open == null
      ? null
      : mergedBoardStatuses(
          openContent: open,
          closedContent: _readOrNull('docs/audit/closed_issues.md') ?? '');

  for (final script in allChecks) {
    if (_allowList.containsKey(script)) {
      // Allowlisted: the entry's typed runners are CLAIMS; verify each one.
      unwired.addAll(runnerViolations(
        gate: script,
        runners: _allowList[script]!,
        read: _readOrNull,
        caseSkipsOf: (c) => extractCaseSkips(c, caseSkipRegex),
        boardStatuses: boardStatuses,
      ));
      continue;
    }
    // Not allowlisted: an explicit INVOCATION in the surface, or coverage by
    // its dynamic loop. A comment or prose mention is not an invocation
    // (OI-155) — `contains(script)` used to count one.
    final inPreCommit = invokesGate(preCommitContent, script) ||
        (preCommitDynamic && !preCommitCaseSkips.contains(script));
    final inWorkflow = invokesGate(workflowContent, script) ||
        (workflowDynamic && !workflowCaseSkips.contains(script));
    if (!inPreCommit && !inWorkflow) {
      unwired.add('$script (not in pre-commit OR workflow)');
    } else if (!inPreCommit) {
      unwired.add('$script (not in scripts/pre-commit.sh)');
    } else if (!inWorkflow) {
      unwired.add('$script (not in .github/workflows/test.yml)');
    }
  }

  // Mirror (gate_test_ledger_lib.dart's "entry but no script on disk"): an
  // allowlist key whose script is gone is stale bookkeeping — the retire
  // path of OI-101 / OI-223 must delete the entry too.
  unwired.addAll(staleAllowlistViolations(allChecks.toSet(), _allowList.keys));

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
  stderr.writeln('Fix (allowlisted check_*): make the _allowList runner TRUE --');
  stderr.writeln('  file(): that file must `run scripts/<name>` on a live line;');
  stderr.writeln('  loop(): remove the gate from that loop\'s case-skip block;');
  stderr.writeln('  manual(): cite an OPEN/IN_PROGRESS OI (a CLOSED one means the');
  stderr.writeln('  gate needs a real runner now, or must be retired with its entry).');
  stderr.writeln('Fix (validate_*/audit_*): add `dart run scripts/<name>.dart`');
  stderr.writeln('  to pre-commit.sh or test.yml, OR add an entry to');
  stderr.writeln('  _explicitAllowList with a reason (on-demand validators only).');
  exit(warnOnly ? 0 : 1);
}
