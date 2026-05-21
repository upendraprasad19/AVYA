// scripts/check_edge_function_rollback_script.dart
//
// Gate 38 (Tech-debt audit 2026-05-20, finding I3): assert that the
// Edge Function deploy script supports rollback + post-deploy smoke
// verification, AND that the payload-archive directory exists.
//
// The audit finding: Edge Function deploys were forward-only. Rolling
// back required `git checkout <SHA>` → re-emit payload → redeploy under
// pressure. MTTR was unbounded.
//
// This gate asserts the script's reversibility contract:
//   1. .claude/deploy_via_api.js exists.
//   2. It defines a --rollback flag AND processes a git-SHA / "previous"
//      revspec (the I3 path, not the legacy snapshot-only path).
//   3. It runs a post-deploy smoke check assertion (synthetic payload
//      against the deployed function URL).
//   4. backups/edge_function_payloads/ exists (archive root).
//
// Exit 0 = pass.
// Exit 1 = fail.
//
// Usage: dart run scripts/check_edge_function_rollback_script.dart
//        dart run scripts/check_edge_function_rollback_script.dart --warn-only

import 'dart:io';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final failures = <String>[];

  // 1. Deploy script present.
  final deployScript = File('.claude/deploy_via_api.js');
  if (!deployScript.existsSync()) {
    failures.add('.claude/deploy_via_api.js missing');
    _report(failures, warnOnly);
    return;
  }
  final src = deployScript.readAsStringSync();

  // 2. --rollback flag definition.
  //    The script parses `a === '--rollback'` in its CLI loop. We also
  //    require the I3 git-SHA branch (looksLikeGitRevspec / gitShowAtSha)
  //    so the legacy snapshot-only path doesn't satisfy the gate alone.
  if (!src.contains("'--rollback'") && !src.contains('"--rollback"')) {
    failures.add('deploy_via_api.js does not define a --rollback flag');
  }
  if (!src.contains('gitShowAtSha') && !src.contains('git show')) {
    failures.add(
      'deploy_via_api.js --rollback exists but no git-SHA reconstruction '
      '(I3 requires `git show <SHA>:supabase/functions/<fn>/index.ts` path)',
    );
  }
  if (!src.contains('looksLikeGitRevspec') &&
      !src.contains("=== 'previous'") &&
      !src.contains("== 'previous'")) {
    failures.add(
      'deploy_via_api.js --rollback does not accept the "previous" '
      'keyword (HEAD~1 alias)',
    );
  }

  // 3. Post-deploy smoke check.
  if (!src.contains('runSmokeStep') &&
      !src.contains('smoke check') &&
      !src.contains('smoke:true') &&
      !src.contains('"smoke":true') &&
      !src.contains("smoke: true")) {
    failures.add(
      'deploy_via_api.js has no post-deploy smoke step (I3 requires a '
      'synthetic {smoke:true} POST against the deployed function URL)',
    );
  }
  if (!src.contains('SMOKE_TOLERATED_CODES') &&
      !src.contains('tolerated')) {
    failures.add(
      'deploy_via_api.js smoke step has no tolerated-code allowlist '
      '(some functions legitimately return 401 to {smoke:true})',
    );
  }

  // 4. Archive directory.
  final archiveDir = Directory('backups/edge_function_payloads');
  if (!archiveDir.existsSync()) {
    failures.add(
      'backups/edge_function_payloads/ directory missing (every deploy '
      'archives <fn>/v<N>_<sha>.json here; pruned to 3 most recent)',
    );
  }

  // 5. --help flag (low-cost sanity).
  if (!src.contains("'--help'") &&
      !src.contains('"--help"') &&
      !src.contains('printHelp')) {
    failures.add(
      'deploy_via_api.js has no --help flag (operators need a discoverable '
      'usage surface for rollback)',
    );
  }

  _report(failures, warnOnly);
}

void _report(List<String> failures, bool warnOnly) {
  final tag = warnOnly ? '[Gate 38 WARN]' : '[Gate 38]';
  if (failures.isEmpty) {
    stdout.writeln(
      '$tag PASS: edge function deploy script supports rollback + smoke + archive.',
    );
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${failures.length} rollback contract violation(s):');
  for (final f in failures) {
    stderr.writeln('  - $f');
  }
  stderr.writeln('');
  stderr.writeln('Fix: see docs/runbooks/edge-function-rollback.md for the I3 contract.');
  exit(warnOnly ? 0 : 1);
}
