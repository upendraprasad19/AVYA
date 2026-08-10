// Gate — rule 24 enforcement — every `scripts/check_*.dart` carries exactly one state
// in docs/audit/gate_test_ledger.yaml, and a `mutation_proven` claim is backed
// by a test that exists, names the gate, and asserts a FAILING path.
//
// WHY THIS EXISTS
//   "Gate 44's own test never invoked main()" — a test that passes whether or
//   not the gate works. 84 gates existed on 2026-08-10 and only 6 test files in
//   the entire repo asserted a red path at all. A gate whose test never fails
//   is not a gate; it is a comment with a CI bill.
//
// WHAT IT PROVES, AND WHAT IT DOES NOT
//   It cannot prove a mutation was RUN. It CAN prove the named test exists,
//   references the gate, and asserts a failing path — which makes the Gate-44
//   class mechanically impossible. The residue is self-attested and read by the
//   ×2 plan review, the same trust model as Gate 42's `presence_only:` and the
//   plan-review gate's `tier:` field. Stated plainly so it is not mistaken for
//   a solved problem.
//
// THE GRANDFATHER LIST IS CLOSED BY NAME, NOT BY DATE.
//   A date-equality check closes nothing: any future gate could write
//   `grandfathered: 2026-08-10` and pass, and the two gates born in this batch
//   carry that very date, so the boundary would have been ambiguous on day one.
//   Membership below is literal and final. Adding a name to it is a visible,
//   reviewable diff — which is the point.

import 'dart:io';

import 'gate_test_ledger_lib.dart';

const _ledgerPath = 'docs/audit/gate_test_ledger.yaml';

/// The 84 `check_*.dart` gates that existed on 2026-08-10, before rule 24.
/// CLOSED. Not a backlog and not a deferral (§4.2) — an enumerated exemption is
/// terminal; "backfill later" would not be.
const _grandfathered = <String>{
  'check_adr_index_fresh.dart',
  'check_ai_tool_dispatcher_coverage.dart',
  'check_alerts.dart',
  'check_apk_release_signed.dart',
  'check_apk_size_within_bounds.dart',
  'check_app_version_matches_pubspec.dart',
  'check_applied_migrations_ledger.dart',
  'check_authed_invoke_fresh_token.dart',
  'check_blast_radius_coverage.dart',
  'check_bugfix_commits_have_diagnose.dart',
  'check_ci_flutter_version.dart',
  'check_claude_md_citations.dart',
  'check_client_errors_alert.dart',
  'check_closes_oi_cited.dart',
  'check_code_review_pass_exists.dart',
  'check_commit_from_worktree.dart',
  'check_container_color_decoration.dart',
  'check_copy_centralization.dart',
  'check_cqrs_query_naming.dart',
  'check_crashlytics_alert_routing.dart',
  'check_cron_registry.dart',
  'check_device_tests_exist.dart',
  'check_diagnose_index_fresh.dart',
  'check_doc_internal_consistency.dart',
  'check_edge_function_auth_pattern.dart',
  'check_edge_function_payloads.dart',
  'check_edge_function_rollback_script.dart',
  'check_exlog_key_canonical.dart',
  'check_gate_scripts_wired.dart',
  'check_generic_error_telemetry.dart',
  'check_goal_token_exhaustiveness.dart',
  'check_god_screen_max_lines.dart',
  'check_hardcoded_pricing_and_limits.dart',
  'check_hive_map_field_drift.dart',
  'check_hooks_installed.dart',
  'check_id_injection_on_get.dart',
  'check_import_map_present.dart',
  'check_incident_index_fresh.dart',
  'check_jose_version.dart',
  'check_local_date_key_drift.dart',
  'check_migration_ledger_paired.dart',
  'check_migrations_applied.dart',
  'check_migrations_live.dart',
  'check_mutation_invalidation_set.dart',
  'check_naming_audit.dart',
  'check_naming_conventions.dart',
  'check_nested_claude_md_content.dart',
  'check_nlog_key_canonical.dart',
  'check_no_deferral_euphemism.dart',
  'check_no_http_package.dart',
  'check_no_raw_google_fonts.dart',
  'check_no_raw_ispro_read.dart',
  'check_onconflict_live_arbiter.dart',
  'check_plan_review_record_exists.dart',
  'check_profile_write_service_only.dart',
  'check_raw_hex_in_features.dart',
  'check_razorpay_key_flavor.dart',
  'check_reader_manifest_complete.dart',
  'check_regression_catalog.dart',
  'check_restore_round_trip_coverage.dart',
  'check_saved_meal_key_canonical.dart',
  'check_schema_column_refs.dart',
  'check_schema_payload_parity.dart',
  'check_secrets_gitignored.dart',
  'check_singleton_provider_migration.dart',
  'check_skipped_discipline_budget.dart',
  'check_snapshot_contract.dart',
  'check_sot_behavioral_test_paths.dart',
  'check_sot_registry_completeness.dart',
  'check_sot_registry_parity.dart',
  'check_std_encoding_import_rot.dart',
  'check_sync_fanout.dart',
  'check_tab_screen_uses_hive_scaffold.dart',
  'check_telemetry_pii_classification.dart',
  'check_test_runtime_budget.dart',
  'check_two_user_cross_account.dart',
  'check_unawaited_has_error_sink.dart',
  'check_unbounded_cron_reads.dart',
  'check_week_selector_phase_labels.dart',
  'check_widget_no_direct_supabase.dart',
  'check_workout_schedule_split.dart',
  'check_worktree_config_integrity.dart',
  'check_writeservice_contracts.dart',
  'check_writeservice_only.dart',
};

void main() {
  final ledgerFile = File(_ledgerPath);
  if (!ledgerFile.existsSync()) {
    stderr.writeln('[gate-test-ledger] FAIL: $_ledgerPath does not exist.');
    exit(1);
  }

  final scriptsDir = Directory('scripts');
  if (!scriptsDir.existsSync()) {
    stderr.writeln('[gate-test-ledger] FAIL: scripts/ not found. Run from repo root.');
    exit(1);
  }
  final gatesOnDisk = scriptsDir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.startsWith('check_') && n.endsWith('.dart'))
      .toSet();

  Map<String, LedgerEntry> ledger;
  try {
    ledger = parseLedger(ledgerFile.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('[gate-test-ledger] FAIL: $_ledgerPath is malformed — ${e.message}');
    exit(1);
  }

  final violations = checkLedger(
    ledger: ledger,
    gatesOnDisk: gatesOnDisk,
    grandfathered: _grandfathered,
    testFileExists: (p) => File(p).existsSync(),
    readTestFile: (p) {
      try {
        return File(p).readAsStringSync();
      } on FileSystemException {
        return null;
      }
    },
  );

  if (violations.isEmpty) {
    stdout.writeln('[gate-test-ledger] PASS — ${gatesOnDisk.length} gates, '
        'all with exactly one ledger state '
        '(${_grandfathered.length} grandfathered 2026-08-10, closed).');
    exit(0);
  }

  stderr.writeln('[gate-test-ledger] ${violations.length} problem(s) in $_ledgerPath:');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  exit(1);
}
