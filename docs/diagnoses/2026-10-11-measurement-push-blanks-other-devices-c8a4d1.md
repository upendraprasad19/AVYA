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
  - { pattern: "an upsert body that carries a null for a column the device does not hold, in _syncMeasurements (sync_health.dart)", absent: true }
  - { pattern: "the same explicit-null pattern in _syncWeightLogs (notes, sync_health.dart:233) and _syncSleepLogs (quality, bed_time, wake_time, notes, :338-341)", absent: false, note: "present and LATENT, tracked as OI-332: each record is one atomic entry per day, no in-repo writer sets weight_logs.notes or sleep_logs.bed_time/wake_time, and live (read-only, 2026-10-11) sleep_logs has 0 rows and weight_logs 69 rows with 0 notes, so no value exists for a null to blank. The first writer of those columns owes the merge-safe shape BEFORE it ships" }
  - { pattern: "a hard-coded measurement site list under lib/ outside kBodyMeasurementSites", absent: true, note: "enforced by the lib-wide scan in body_measurement_sites_derivation_test.dart (measured on the real tree: exactly one flat multi-site literal, the registry)" }
  - { pattern: "a hard-coded measurement site list in the Edge Functions", absent: false, note: "ai-proxy/index.ts:983 and ai-media-proxy/index.ts:735 carry the prose list 'Measurement types: waist, chest, hips, arms.'; pinned to the registry by body_measurement_sites_parity_test.dart (as sets), not derived" }
proposed_fix: >-
  One payload builder (sync/measurement_push_rules.dart): measurementLegacyPayload is the shape every earlier build sent (the fingerprint source and, with the kill switch set, the wire body byte for byte); measurementMergeSafeBody sends only the sites that are finite numbers, notes only when a String, and nothing for a record holding neither; measurementFingerprintContent normalises non-pushable values to null so SyncFingerprint.of equals HEAD's stored fingerprint for every record the in-repo writers produce, so an upgrade or a toggle of disable_measurement_merge_safe_push re-pushes nothing (appending a token to the registry does re-fingerprint every stored day: one re-push). The pull's merge rule is the pure mergeCloudSitesIntoLocal. The five hard-coded site lists derive from kBodyMeasurementSites (lib/core/constants/body_measurement_sites.dart) with a TS twin and a parity test against live_schema_columns.json and the two Edge Function prompt lists.
regression_test_planned: >-
  test/sync/body_measurement_push_merge_safe_test.dart (cloud model, negative control, upgrade fixture with HEAD's stored fingerprints, the two-device flow with the real restore and logMeasurement, the empty-row rule with the empty day FIRST, the kill-switch all-null record, the cross-channel pull driven through SyncService.pullMeasurementsForTest including the RESIDUAL flow), test/sync/measurement_push_rules_test.dart (HEAD's wire bodies and fingerprints pinned as literals captured from the unmodified tree; boundary, identity and merge-key cases), test/contracts/body_measurement_sites_parity_test.dart, test/contracts/body_measurement_sites_derivation_test.dart (presence-only, said so: the five named consumers plus a lib-wide scan with scanner negative controls), test/ai_coach/log_measurement_site_whitelist_test.dart (the chat parser and the confirm handler executed), and the existing test/ai_coach/closeout_snapshot_keys_test.dart, test/sync/measurement_skip_test.dart and test/contracts/sync_body_measurement_payload_hash_index_writer_to_reader_test.dart. Run: TZ=Asia/Kolkata flutter test test/sync/body_measurement_push_merge_safe_test.dart test/sync/measurement_push_rules_test.dart test/contracts/body_measurement_sites_parity_test.dart test/contracts/body_measurement_sites_derivation_test.dart test/ai_coach/log_measurement_site_whitelist_test.dart test/ai_coach/closeout_snapshot_keys_test.dart test/sync/measurement_skip_test.dart test/contracts/sync_body_measurement_payload_hash_index_writer_to_reader_test.dart (82 passed).
mutation_proof: >-
  Rule 21. 42 mutants, each applied once and restored by ONE consolidated runner that checks the anchor occurs exactly once and computes the mutation BEFORE it opens the file for write, confirms the mutation applied, restores on exit and compares byte for byte afterwards; a compile error would have been reported as not a proof (there were none). All 42 reddened at least one test and none survived; the unmutated baseline is 82 passed over the 8 files named in regression_test_planned. The 26 original mutants, re-run on the final tree (the first text said 25: a miscount of its own list): empty-row rule removed (3 red); notes is-String to != null (1); isFinite removed (4); isFinite to !isNaN (2); is num to != null (3); body builder drops hips (4); body drops user_id (7) or created_at (8); fingerprint content drops nulls (3); legacy key order (4); pull merge reduced to three sites (1) or overwriting a local value (3); onConflict dropped (4); kill switch ignored (3) or inverted (10); fingerprint taken from the body (2); liveKeys.add removed (7) and moved after the empty-row continue (1); flag getter inverted (10); registry gaining a token (13) or reordered (6); twin extra token (1); a prompt line edited (1); isBodyMeasurementSite null-only (3); snapshot list reduced to a literal (3); parity exclusion set widened (2). The 16 added by the B-pass fixes: pull merge arguments swapped (2), the merged record never put (2), the no-local-record branch losing source (1); the merge also filling notes (2) or writing null cloud sites (2); empty-String notes mapped to null in the fingerprint content (1); isPushable excluding negatives (2) or zero (3); the empty-row skip applied before the kill-switch ternary (1); the empty-row continue turned into a break (1); the whitelist check removed in the chat parser (2) and in the confirm handler (2); a sixth hard-coded site list appearing in a lib file (1); the derivation scanner's threshold 2 to 3 (2) and its code-block exclusion removed (1); the pull seam never reaching _pullMeasurements (3). A second run of the 16 new mutants recorded the failing test NAMES, and each is killed by the test written for it (the pull tests for the three pull mutants, the rules tests for the merge, boundary and identity mutants, the kill-switch all-null test, the empty-day-first test, the two whitelist tests, the lib-wide scan, the scanner negative controls), not by an unrelated test. Equivalent and not run: the flag read per record instead of per pass (the fingerprint is mode-independent), a reversed site order in the merge-safe body (the cloud model does not observe key order), cloud.containsKey(site) in the merge. The first commit's run lost sync_health.dart once to a helper that opened the file for write before computing the mutation (restored from HEAD plus the intended edit); the runner now computes first.
impact_analysis: >-
  Before: a second device (or a restore-shaped record) pushing a day it holds only partly blanked the other device's sites in the cloud. After: the push carries only held sites, so disjoint sites survive every ordering. It ships on documented PostgREST semantics (omitted keys are not in the DO UPDATE SET list; supabase-dart sends no columns= for a Map body) and on repo precedent (sync_workout.dart, sync_profile.dart, a3e7d9 finding 2); a live observation is a founder-owned ledger row. If that assumption were false the new body would equal today's behaviour for unheld sites, so the change cannot be worse than HEAD. Residuals, both directions: (1) old APKs, and an out-of-repo Telegram writer OI-297 reports, still push nulls and an unchanged day is not re-pushed, so a blanking by an old client heals on the next local edit of that date (a sync_epoch bump is not recommended for multi-device users, SYNC_EPOCH_RESYNC.md:54); (2) the body still sends every held site, so a stale held value can overwrite a value another device corrected (triggers: a new site added on this device, a sync_epoch clearAll, disable_measurement_hash_skip set, the first push of each restored day, an offline-retried push, a cross-channel pull fill - a pulled site changes the record's fingerprint, so the next push sends every held site; pinned by the RESIDUAL test) - the founder's standing rule 'last sync or write wins'; a per-site pending set is the L2b entry criterion. The kill switch disable_measurement_merge_safe_push is a local configBox lever (OI-95, ADR-0020: a fleet rollback needs a release), kept so the old path stays reachable per CLAUDE.md section 4.6, not deleted later because the old shape is the defect; it is kept permanently on the exlogRestoreDedupeEnabled (oi83) precedent, sync_flags.dart:255-256, accepted at plan review R1-A8. Siblings: the weight and sleep pushes carry the same explicit-null pattern but are latent (see forbidden_patterns_checked); OI-332 holds the obligation for the first writer of those columns. The fingerprint is coupled to the site registry, so appending a registry token re-fingerprints every stored day once.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "sync/sync_health.dart _syncMeasurements, sync/measurement_push_rules.dart (new), sync_service.dart _pullMeasurements, sync_flags.dart, the five site lists derive from kBodyMeasurementSites" }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "no Hive shape change: the per-day record measurement_<istDate> and the skip index {date: fingerprint} are unchanged; the fingerprint content equals HEAD for every record the in-repo writers produce (HEAD literals pinned)" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "backups/live_schema_columns.json body_measurements = id,user_id,date,chest,waist,hips,arms,notes,created_at; no CHECK on the sites (migration 004); non-partial uniq_body_measurements_user_date (082); no schema change" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "OI-297 read-only 2026-10-03 and re-read 2026-10-11 (project dedsavbjuwgarrhphgnl, counts only): body_measurements 0 rows, sleep_logs 0 rows, weight_logs 69 rows with 0 notes; nothing applied" }
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

One payload builder (sync/measurement_push_rules.dart): measurementLegacyPayload is the shape every earlier build sent (the fingerprint source and, with the kill switch set, the wire body byte for byte); measurementMergeSafeBody sends only the sites that are finite numbers, notes only when a String, and nothing for a record holding neither; measurementFingerprintContent normalises non-pushable values to null so SyncFingerprint.of equals HEAD's stored fingerprint for every record the in-repo writers produce, so an upgrade or a toggle of disable_measurement_merge_safe_push re-pushes nothing (appending a token to the registry does re-fingerprint every stored day: one re-push). The pull's merge rule is the pure mergeCloudSitesIntoLocal. The five hard-coded site lists derive from kBodyMeasurementSites (lib/core/constants/body_measurement_sites.dart) with a TS twin and a parity test against live_schema_columns.json and the two Edge Function prompt lists.

## Verification

Plan: `docs/plans/coach-measurement-entry-l2a.md` (v3.1, three review rounds, record `docs/plan-reviews/coach-measurement-entry.md`). HEAD's two wire bodies and stored fingerprints were captured from the unmodified tree and pinned in the tests, so the byte-identical and no-re-push claims are not checked against the code under change. Tests and mutation proof as in the front matter. The live REST probe and the OI-297 board append are `blocked_on_user` rows in `docs/audit/coach-measurement-entry.closure.yaml`.

B-pass (`docs/reviews/coach-measurement-entry-bpass.md`, 2026-10-11): two fresh context-blind reviewers on dec69fc8, 13 findings, 0 P0/P1, 0 false alarms; the product code needed no change, the tests and the evidence did (see that file). Full suite on dec69fc8: 8624 passed, 9 skipped, exit 0.
