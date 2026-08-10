# Gate index

> **GENERATED — do not edit by hand.** Run `dart run scripts/build_gate_index.dart`.
> Regenerated automatically by `scripts/pre-commit.sh` when a baked input changes.

The registry keys on the **script filename** — that is the real, already-unique identity that every
wiring surface uses. A gate **number is an optional alias**: most gates have none and do not need one.

**Forward minting rule.** A new gate takes NO number. If a `/build-apk` section needs one, it takes
the next free number: **55**. Declare it canonically as `// Gate: N` on its
own line in the first 10 lines — that exact form is the only one this generator reads.

Total gates: **86** (49 numbered, 37 by filename only).

| Gate | Script | Purpose | Test ledger |
|---|---|---|---|
| — | `check_adr_index_fresh.dart` | confirms docs/adr/INDEX.md is up-to-date relative to docs/adr/NNNN-*.md. | — |
| — | `check_ai_tool_dispatcher_coverage.dart` | Every WRITE-kind AI tool registered server-side must have a matching | — |
| — | `check_alerts.dart` | SessionStart hook script: queries unacknowledged alerts and emits a JSON | — |
| 48 | `check_apk_release_signed.dart` | the built APK is signed with the RELEASE certificate, not the | — |
| 13 | `check_apk_size_within_bounds.dart` | APK size within ±10% of last shipped size. | — |
| 51 | `check_app_version_matches_pubspec.dart` | Build-gate script: asserts `AppConstants.appVersion` in | — |
| 39 | `check_applied_migrations_ledger.dart` | assert that `backups/applied_migrations.json` is in the structured-record shape | — |
| — | `check_authed_invoke_fresh_token.dart` | every authed Edge Function call from the client sends a FRESH token | — |
| — | `check_blast_radius_coverage.dart` | . | — |
| 10 | `check_bugfix_commits_have_diagnose.dart` | Bug-fix commits since last APK build reference a valid diagnose-doc. | — |
| — | `check_ci_flutter_version.dart` | CI / dev / Vercel Flutter-version parity. | — |
| 26 | `check_claude_md_citations.dart` | assert that every `§N` and `§N.M` citation across CLAUDE.md + nested CLAUDE.md files | — |
| 29 | `check_client_errors_alert.dart` | assert an alert config exists at `supabase/alerts/client_errors.yaml` declaring a threshold rule | — |
| — | `check_closes_oi_cited.dart` | Commit-msg gate: a commit that flips an OI from OPEN to CLOSED in | — |
| — | `check_code_review_pass_exists.dart` | . | — |
| — | `check_commit_from_worktree.dart` | Worktree-per-session enforcement (codified 2026-07-07 after 2 cross-session | — |
| — | `check_container_color_decoration.dart` | a Flutter `Container` must not pass BOTH `color:` and `decoration:`. | — |
| — | `check_copy_centralization.dart` | WARN-ONLY diagnostic. User-facing copy should live in WardroomCopy (lib/core/copy/wardroom_copy.dart) | — |
| — | `check_cqrs_query_naming.dart` | a method whose NAME promises a query must not MUTATE. | — |
| 30 | `check_crashlytics_alert_routing.dart` | assert that Firebase Crashlytics alert routing is documented at | — |
| 31 | `check_cron_registry.dart` | assert that every `cron.schedule(...)` call in `supabase/migrations/*.sql` is also recorded | — |
| 54 | `check_device_tests_exist.dart` | assert that the 4 named Patrol device-CI flow files exist in `integration_test/device/` and | — |
| 25 | `check_diagnose_index_fresh.dart` | assert that `docs/diagnoses/INDEX.md` enumerates every diagnose-doc on disk. | — |
| 18 | `check_doc_internal_consistency.dart` | known-drift pairs across CLAUDE.md + AGENTS.md must agree. | — |
| — | `check_edge_function_auth_pattern.dart` | Edge Function auth-pattern validation (e8a1c3 class, 2026-06-12). | — |
| 12 | `check_edge_function_payloads.dart` | Flutter caller body keys ⊆ Edge Function validator shape. | — |
| 38 | `check_edge_function_rollback_script.dart` | assert that the Edge Function deploy script supports rollback + post-deploy smoke | — |
| 17 | `check_exlog_key_canonical.dart` | APK Test #16.1 / Agent A — source-grep gate. Pins the rule that | — |
| — | `check_gate_index_fresh.dart` | confirms docs/audit/GATE_INDEX.md is up-to-date relative to its baked | — |
| 33 | `check_gate_scripts_wired.dart` | assert that every `scripts/check_*.dart` file is invoked from BOTH: - scripts/pre-commit.sh (local enforcement) | — |
| 15 | `check_generic_error_telemetry.dart` | every user-facing generic error message in lib/ must be | — |
| — | `check_goal_token_exhaustiveness.dart` | guarantees a fitness-goal | — |
| 43 | `check_god_screen_max_lines.dart` | God-screen line ceiling. | — |
| — | `check_hardcoded_pricing_and_limits.dart` | ban hardcoded price figures | — |
| 19 | `check_hive_map_field_drift.dart` | Hive Map field-key drift detector (Theme G, closes-diagnose | — |
| 32 | `check_hooks_installed.dart` | assert that the repo's pre-commit hook is installed (i.e. `.git/hooks/pre-commit` exists | — |
| 16 | `check_id_injection_on_get.dart` | repository methods that return List<Map<...>> from a Hive | — |
| 27 | `check_import_map_present.dart` | assert `supabase/functions/import_map.json` exists + pins every shared | — |
| — | `check_incident_index_fresh.dart` | confirms docs/incidents/INDEX.md is up-to-date. | — |
| 28 | `check_jose_version.dart` | assert `jose` is at or above the configured minimum version across every Edge Function. | — |
| — | `check_local_date_key_drift.dart` | Ban device-local `YYYY-MM-DD` date-key construction in lib/, i.e. | — |
| — | `check_migration_ledger_paired.dart` | assert that whenever a new | — |
| 14 | `check_migrations_applied.dart` | Local migrations match the prod state snapshot. | — |
| 14b | `check_migrations_live.dart` | Local migrations match LIVE Supabase migration state. | — |
| — | `check_mutation_invalidation_set.dart` | Mutation methods must invalidate the canonical provider set per | — |
| 8 | `check_naming_audit.dart` | Forbidden legacy patterns absent. | — |
| — | `check_naming_conventions.dart` | Enforce naming conventions documented in docs/naming_conventions.md. | — |
| 44 | `check_nested_claude_md_content.dart` | Nested CLAUDE.md content quality | — |
| 53 | `check_nlog_key_canonical.dart` | Drift-fix batch 2026-05-24 / F2 nutrition — source-grep gate. Pins | — |
| — | `check_no_deferral_euphemism.dart` | flag deferral-EUPHEMISM phrases in the | — |
| 45 | `check_no_http_package.dart` | Tech-debt audit 2026-05-20 / finding D8 — source-grep gate. | — |
| 37 | `check_no_raw_google_fonts.dart` | assert that `GoogleFonts.getFont('DM Sans', ...)` is invoked only via | — |
| 34 | `check_no_raw_ispro_read.dart` | assert that no production code reads `configBox.get('isPro')` / `config.get('isPro')` | — |
| — | `check_onconflict_live_arbiter.dart` | 2026-05-15 — Runs `test/sql/onconflict_live_arbiter.sql` against the | — |
| — | `check_plan_review_record_exists.dart` | P1.A keystone (discipline overhaul 2026-06-18) — the plan-quality forcing | — |
| 35 | `check_profile_write_service_only.dart` | assert that no production code outside `ProfileWriteService` writes to userBox under | — |
| — | `check_raw_hex_in_features.dart` | Ban raw `Color(0x......)` hex literals under lib/features/**. Palette colours | — |
| 24 | `check_razorpay_key_flavor.dart` | assert that Razorpay key prefixes match the build flavor. `rzp_live_*` MUST appear only in | — |
| 50 | `check_reader_manifest_complete.dart` | enforces the reader-side manifest in | — |
| — | `check_regression_catalog.dart` | Pre-merge gate: walks docs/diagnoses/INDEX.md, verifies every bug | — |
| 21 | `check_restore_round_trip_coverage.dart` | every `syncX()` method in `lib/core/services/sync/` must | — |
| — | `check_saved_meal_key_canonical.dart` | Diagnose b8d5c2 (2026-06-03) — source-grep gate. Pins the rule that | — |
| — | `check_schema_column_refs.dart` | Supabase column-reference validation against the live schema. | — |
| 52 | `check_schema_payload_parity.dart` | every NOT NULL column on user-tagged Supabase tables must | — |
| 23 | `check_secrets_gitignored.dart` | assert that Android signing artifacts and other sensitive secret patterns are never tracked | — |
| 46 | `check_singleton_provider_migration.dart` | assert the 7 singleton services targeted by A7 have: | — |
| — | `check_skipped_discipline_budget.dart` | assert that no `regression-test-skipped:` waiver entry in `docs/skipped-discipline.md` | — |
| — | `check_snapshot_contract.dart` | OI-03 gate — enforces the snapshot contract in docs/snapshot_contract.yaml. | — |
| 42 | `check_sot_behavioral_test_paths.dart` | assert every SoT registry concept entry carries either: - `behavioral_test_path:` (cite a real behavioral contract test) | — |
| 7 | `check_sot_registry_completeness.dart` | SoT registry completeness. | — |
| — | `check_sot_registry_parity.dart` | SoT registry parity — file:line references resolve AND no orphan | — |
| — | `check_std_encoding_import_rot.dart` | ban importing the REMOVED | — |
| 11 | `check_sync_fanout.dart` | Every sync_method and restore_method declared in the registry | — |
| — | `check_tab_screen_uses_hive_scaffold.dart` | Tech-debt audit 2026-05-20 / B5 / C1 — pins the contract that every | — |
| 22 | `check_telemetry_pii_classification.dart` | every `ErrorTelemetry.recordNonFatal` / `logEvent` callsite | — |
| 41 | `check_test_runtime_budget.dart` | assert no individual test exceeds the configured runtime budget. | — |
| — | `check_two_user_cross_account.dart` | WI-2 (regression-prevention batch 2026-06-08) — live-DB TWO-USER | — |
| 20 | `check_unawaited_has_error_sink.dart` | every `unawaited(...)` call in lib/ must be near (within | — |
| — | `check_unbounded_cron_reads.dart` | every fan-out read in a cron-dispatched Edge Function must be bounded. | — |
| — | `check_week_selector_phase_labels.dart` | the Train week selector must derive phase labels from the real current_phase, never hardcode | — |
| 36 | `check_widget_no_direct_supabase.dart` | enforce CLAUDE.md rule #4 (Repository pattern) — widgets / screens must NEVER | — |
| 47 | `check_workout_schedule_split.dart` | assert the 4-way split of `WorkoutScheduleService` is in place. | — |
| — | `check_worktree_config_integrity.dart` | Asserts that NO `core.worktree` is configured in any git scope for this repo. | — |
| 9 | `check_writeservice_contracts.dart` | Every WriteService concept with a hive block has a contract test. | — |
| 49 | `check_writeservice_only.dart` | All writes to workoutBox / nutritionBox / healthBox must go through the | — |
| 40 | `validate_audit_closure.dart` | validate audit closure YAML files in `docs/audit/*_audit_closures.yaml`. | — |

## Reserved

`/build-apk` procedural steps with no script — a gate must never mint one of these:

`1`, `2`, `3`, `3.5`, `4`, `5`, `6`

## Historical aliases

Diagnose-docs, `closed_issues.md`, closure ledgers, `docs/reviews/` and `docs/plan-reviews/` record what was
true when written and are never rewritten. Use this table to resolve an old number found there.

- **Gate 7** — kept by check_sot_registry_completeness.dart. check_writeservice_only.dart also claimed 7 (closure ledger) → now 49.
- **Gate 18** — kept by check_doc_internal_consistency.dart. Also claimed by check_reader_manifest_complete.dart → 50 and check_app_version_matches_pubspec.dart → 51.
- **Gate 19** — kept by check_hive_map_field_drift.dart (owns backups/gate19_drift_baseline.txt). check_schema_payload_parity.dart → 52.
- **Gate 23** — kept by check_secrets_gitignored.dart. check_nlog_key_canonical.dart (build-apk.md section) → 53.
- **Gate 44** — kept by check_nested_claude_md_content.dart. check_device_tests_exist.dart → 54. NOTE: "the Gate-44 lesson" in CLAUDE.md and diagnose d7b3e9 names the LESSON, not either script — no test for either claimant exists in the tree. That prose is deliberately left alone.

### Superseded ledger mints

A closure ledger minted these numbers before the script declared its own. The ledger is a historical
record and is never rewritten, so the script's own `// Gate: N` wins and the old mint is listed here.

- `check_device_tests_exist.dart` — ledger says Gate 44; now Gate 54.
- `check_schema_payload_parity.dart` — ledger says Gate 19; now Gate 52.
- `check_writeservice_only.dart` — ledger says Gate 7; now Gate 49.
