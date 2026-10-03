// scripts/check_two_user_cross_account.dart
//
// WI-2 (regression-prevention batch 2026-06-08) — live-DB TWO-USER
// cross-account isolation gate. Thin wrapper that runs
// `test/sql/two_user_cross_account.sql` through the shared live-arbiter runner
// (which resolves the fitness-app Management-API PAT + parses _v_results).
//
// It inserts a synthetic Alice + Bob with IDENTICAL natural keys (same date /
// name / workout_log_id) across every per-user table and asserts BOTH rows
// coexist (count == 2). A user-less sync key would collapse the two users onto
// one row (the catastrophic d4b8e2 / f7e3a1 cross-account corruption class) →
// count == 1 → fail. Everything runs in a ROLLBACK txn; nothing persists.
//
// Live-DB gate: SKIPPED in pre-commit + CI (the PAT file is gitignored and
// absent on CI runners). Runs at /build-apk alongside
// check_onconflict_live_arbiter.dart — see the case-skip allowlist in
// scripts/pre-commit.sh + .github/workflows/test.yml, and the _allowList in
// scripts/check_gate_scripts_wired.dart.
//
// related-diagnose: d4b8e2, f7e3a1
//
// Usage: dart run scripts/check_two_user_cross_account.dart

import 'dart:io';

Future<void> main() async {
  final result = await Process.run(
    'dart',
    [
      'run',
      'scripts/check_onconflict_live_arbiter.dart',
      '--sql',
      'test/sql/two_user_cross_account.sql',
    ],
    runInShell: true,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exit(result.exitCode);
}
