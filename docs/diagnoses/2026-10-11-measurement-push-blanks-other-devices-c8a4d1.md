---
bug_id: c8a4d1
date: 2026-10-11
batch: coach-measurement-entry
status: fixed
tier: m_fix
blast_radius: platform
symptom: >-
  The body_measurements push sent all four sites and notes from the day's Hive record, nulls included. A device that held only some sites (logMeasurement folds ONE part per call; restore writes explicit nulls) therefore blanked the sites another device had entered, because PostgREST assigns an explicit null and leaves an absent key alone.
concept: sync_body_measurement_payload_hash_index
sot_registry_entry: sync_body_measurement_payload_hash_index
writers:
  - { file: lib/core/services/sync/sync_health.dart, method: "_syncMeasurements (built the payload with every site and notes, nulls included)", line: 254 }
  - { file: lib/core/services/health_write_service.dart, method: "logMeasurement (folds ONE part into the day's record)", line: 209 }
readers:
  - { file: lib/core/services/sync/sync_health.dart, method_or_widget: "_restoreMeasurements (writes the cloud row with explicit nulls, local-wins)", line: 502 }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: "_getBodyMeasurements (latest per site)", line: 1609 }
  - { file: supabase/functions/restore-user-snapshot/paged_reads.ts, method_or_widget: "body_measurements paged read (select *)", line: 178 }
hive_key_prefix: measurement_
hive_key_formula: "'measurement_${istDateStr(date)}' (unchanged)"
sync_methods:
  - _syncMeasurements
restore_methods:
  - _restoreMeasurements
  - _pullMeasurements
cloud_table: body_measurements
cloud_columns:
  - chest
  - waist
  - hips
  - arms
  - notes
  - created_at
contract_test_path: test/sync/body_measurement_push_merge_safe_test.dart
ist_handling:
  - "no date logic added: the per-day key and the date column are the existing IST date strings; the builder passes the record's own date through"
provider_invalidations: []
telemetry_op_types:
  success:
    - upsert_body_measurements_success
  failure:
    - upsert_body_measurement
cross_account_guard: "unchanged: pushIfChanged checks ownerChangedNow before and after the push; the body's user_id is the live pass's user, never the record's"
forbidden_patterns_checked:
  - { pattern: "an upsert body that carries a null for a column the device does not hold", absent: true }
  - { pattern: "a second hard-coded measurement site list outside kBodyMeasurementSites", absent: true }
proposed_fix: >-
  One payload builder (sync/measurement_push_rules.dart): measurementLegacyPayload is the shape every earlier build sent (the fingerprint source and, with the kill switch set, the wire body byte for byte); measurementMergeSafeBody sends only the sites that are finite numbers, notes only when a String, and nothing for a record holding neither; measurementFingerprintContent normalises non-pushable values to null so SyncFingerprint.of equals HEAD's stored fingerprint for every record the in-repo writers produce, so an upgrade or a toggle of disable_measurement_merge_safe_push re-pushes nothing. The pull's merge rule is the pure mergeCloudSitesIntoLocal. The five hard-coded site lists derive from kBodyMeasurementSites (lib/core/constants/body_measurement_sites.dart) with a TS twin and a parity test against live_schema_columns.json and the two Edge Function prompt lists.
regression_test_planned: >-
  test/sync/body_measurement_push_merge_safe_test.dart (cloud model, negative control, upgrade fixture with HEAD's stored fingerprints, the two-device flow with the real restore and logMeasurement), test/sync/measurement_push_rules_test.dart (HEAD's wire bodies and fingerprints pinned as literals captured from the unmodified tree), test/contracts/body_measurement_sites_parity_test.dart, test/contracts/body_measurement_sites_derivation_test.dart (presence-only, said so). Run: TZ=Asia/Kolkata flutter test test/sync/body_measurement_push_merge_safe_test.dart test/sync/measurement_push_rules_test.dart test/contracts/body_measurement_sites_parity_test.dart test/contracts/body_measurement_sites_derivation_test.dart
mutation_proof: >-
  Rule 21. 25 mutants over the rules, the push wiring, the flag, the registry, the twin, a prompt line and the parity test, each applied once and restored: empty-row rule removed (3 red); notes is-String to != null (1); isFinite removed (3); isFinite to !isNaN (1, the Infinity fixtures); is num to != null (2); builder drops hips (4); body drops user_id (6) or created_at (7); fingerprint content drops nulls (2, the upgrade fixture); legacy key order (3, HEAD's literal); pull merge reduced to three sites (1) or overwriting a local value (1); onConflict dropped (4); kill switch ignored (2) or inverted (8); fingerprint taken from the body (2); liveKeys.add removed (4) and moved after the empty-row continue (1, the seeded index entry); flag getter inverted (8); registry gaining a token (10) or reordered (5); twin extra token (1); a prompt line edited (1); isBodyMeasurementSite null-only (1); snapshot list reduced to a literal (2); parity exclusion set widened (2). All 25 reddened at least one test; the unmutated baseline is 61 passed. The flag-read-per-record-versus-per-pass variant is equivalent (the fingerprint is mode-independent) and was not run. A first pass of three mutants hit anchors changed by dart format and were re-run with corrected anchors; a helper script that opened the file for writing before computing the mutation truncated sync_health.dart once and the file was restored from HEAD plus the intended edit (diff +18/-12, 61 passed).
impact_analysis: >-
  Before: a second device (or a restore-shaped record) pushing a day it holds only partly blanked the other device's sites in the cloud. After: the push carries only held sites, so disjoint sites survive every ordering. It ships on documented PostgREST semantics (omitted keys are not in the DO UPDATE SET list; supabase-dart sends no columns= for a Map body) and on repo precedent (sync_workout.dart, sync_profile.dart, a3e7d9 finding 2); a live observation is a founder-owned ledger row. If that assumption were false the new body would equal today's behaviour for unheld sites, so the change cannot be worse than HEAD. Residuals, both directions: (1) old APKs, and an out-of-repo Telegram writer OI-297 reports, still push nulls and an unchanged day is not re-pushed, so a blanking by an old client heals on the next local edit of that date (a sync_epoch bump is not recommended for multi-device users, SYNC_EPOCH_RESYNC.md:54); (2) the body still sends every held site, so a stale held value can overwrite a value another device corrected (triggers: a new site added on this device, a sync_epoch clearAll, disable_measurement_hash_skip set, the first push of each restored day, an offline-retried push) - the founder's standing rule 'last sync or write wins'; a per-site pending set is the L2b entry criterion. The kill switch disable_measurement_merge_safe_push is a local configBox lever (OI-95, ADR-0020: a fleet rollback needs a release), kept so the old path stays reachable per CLAUDE.md section 4.6, not deleted later because the old shape is the defect.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "sync/sync_health.dart _syncMeasurements, sync/measurement_push_rules.dart (new), sync_service.dart _pullMeasurements, sync_flags.dart, the five site lists derive from kBodyMeasurementSites" }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "no Hive shape change: the per-day record measurement_<istDate> and the skip index {date: fingerprint} are unchanged; the fingerprint content equals HEAD for every record the in-repo writers produce (HEAD literals pinned)" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "backups/live_schema_columns.json body_measurements = id,user_id,date,chest,waist,hips,arms,notes,created_at; no CHECK on the sites (migration 004); non-partial uniq_body_measurements_user_date (082); no schema change" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "OI-297 read-only 2026-10-03: body_measurements 0 rows / 0 users; re-read before the PR; nothing applied" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no Edge Function edited; supabase/functions/_shared/body_measurement_sites.ts is imported by nothing, so no deploy" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "no cron involved" }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "the upsert is an own-row write under the existing RLS; unchanged" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "none" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "PostgREST behaviour is asserted by repo precedent and documentation; the live probe is a founder-owned ledger row" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "test/sync/body_measurement_push_merge_safe_test.dart drives the real SyncService through pushMeasurementsForSyncDomain against a stub cloud model that assigns every body key (nulls included); no live call" }
recurrence: "recurrence of the null-clobber class: c4d8a2 (never clobber with null), a3e7d9 finding 2 (omitted vs explicit null), d8a2f6 (server-key preservation), bug class 2.51; prior fix docs/diagnoses/2026-09-28-merge-oi252-interaction-defects-a3e7d9.md"
related_bugs: [c4d8a2, a3e7d9, d8a2f6, e4a1b7]
---

# measurement push blanks other devices' sites

## What was wrong

The body_measurements push sent all four sites and notes from the day's Hive record, nulls included. A device that held only some sites (logMeasurement folds ONE part per call; restore writes explicit nulls) therefore blanked the sites another device had entered, because PostgREST assigns an explicit null and leaves an absent key alone.

## Fix

One payload builder (sync/measurement_push_rules.dart): measurementLegacyPayload is the shape every earlier build sent (the fingerprint source and, with the kill switch set, the wire body byte for byte); measurementMergeSafeBody sends only the sites that are finite numbers, notes only when a String, and nothing for a record holding neither; measurementFingerprintContent normalises non-pushable values to null so SyncFingerprint.of equals HEAD's stored fingerprint for every record the in-repo writers produce, so an upgrade or a toggle of disable_measurement_merge_safe_push re-pushes nothing. The pull's merge rule is the pure mergeCloudSitesIntoLocal. The five hard-coded site lists derive from kBodyMeasurementSites (lib/core/constants/body_measurement_sites.dart) with a TS twin and a parity test against live_schema_columns.json and the two Edge Function prompt lists.

## Verification

Plan: `docs/plans/coach-measurement-entry-l2a.md` (v3.1, three review rounds, record `docs/plan-reviews/coach-measurement-entry.md`). HEAD's two wire bodies and stored fingerprints were captured from the unmodified tree and pinned in the tests, so the byte-identical and no-re-push claims are not checked against the code under change. Tests and mutation proof as in the front matter. The live REST probe and the OI-297 board append are `blocked_on_user` rows in `docs/audit/coach-measurement-entry.closure.yaml`.
