---
bug_id: c2b7e4
date: 2026-10-08
batch: progress-photos-client-b2 (unit B2, OI-314 and OI-322)
status: fixed
tier: m_fix
blast_radius: feature
symptom: >-
  (1) A user whose PRO lapsed could not open the Progress screen to view or delete the progress photos they already
  held: the Photos hub row ran the PRO gate and showed the paywall without opening the screen, and the screen's own entry
  gate showed a locked card (founder decision 6, 2026-10-06, says a lapsed user may VIEW and DELETE old photos). The
  repository still carried a free tier (2/day, 2048 px / 85 %) although the database now refuses a free caller (migration
  154, decision 5). A server refusal of a new photo was swallowed into `null` and shown as a generic "Upload failed".
  (2) `capture` sent `taken_at` as `takenAt.toIso8601String()`, a local time with no offset, to a timestamptz column the
  server reads under UTC, so an IST user's value was stored 5.5 h late; the client daily-cap window (device-local midnight
  in UTC) was misaligned with it (OI-322).
concept: subscription_state — the screen is now the one place that decides what a not-PRO user sees of their progress photos; the repository makes no PRO decision.
sot_registry_entry: subscription_state (reader entries for the repository, the screen and the hub updated in docs/sot_registry.yaml)
writers:
  - { file: lib/features/profile/repositories/progress_photo_repository.dart, method_or_widget: "ProgressPhotoRepository.capture: the row's taken_at and the cap window", line: 147 }
  - { file: lib/features/profile/screens/progress_photos_screen.dart, method_or_widget: "_ProgressPhotosScreenState._reload: the only assigner of _access/_photos/_error", line: 106 }
readers:
  - { file: lib/features/profile/screens/progress_photos_screen.dart, method_or_widget: "_buildBody / the Add button: what each user sees", line: 467 }
  - { file: lib/features/profile/screens/user_photos_screen.dart, method_or_widget: "the Progress row's onTap: now a plain push", line: 81 }
  - { file: lib/features/profile/repositories/progress_photo_repository.dart, method_or_widget: "listStrict: the ordering by taken_at and the only reader of the value", line: 240 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: progress_photos
cloud_columns: [taken_at]
contract_test_path: test/contracts/progress_photo_client_rules_test.dart
ist_handling:
  - { file: lib/features/profile/repositories/progress_photo_repository.dart, line: 90, fn: progressPhotoCapWindowStartUtc }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "reads and deletes stay scoped by .eq('user_id', userId) and by the table's own-row RLS; capture takes user_id from the session."
forbidden_patterns_checked:
  - "a verify-after-refusal step in the repository — REJECTED after four review rounds attacked every variant (a bare 403 sending a payer to the paywall; a forced verify whose side effects re-enter the screen; a just-paid user parked on the locked card). The classifier is pure and synchronous; the screen alone asks the server, bounded, and never opens the paywall for a payer."
  - "a bare Storage 403 read as a PRO refusal — REJECTED: an expired token also gives 403; a misread refusal sends a payer to the paywall, a missed one costs 'Upload failed'. The rule is conservative on purpose."
  - "several async writers of the screen state — REPLACED by one guarded writer (_reload) after three rounds found out-of-order writes."
proposed_fix: >-
  Repository: delete the free branch (one cap of 5 per IST day, one quality 3000/95); `taken_at` sent as UTC
  (`progressPhotoTakenAtWire`); the cap window is IST midnight in UTC (`progressPhotoCapWindowStartUtc`); a pure
  `isProgressPhotoProRefusal` and a `ProgressPhotoProRequiredException` thrown by `capture`; `listStrict` (propagates) with
  `list` a swallowing wrapper; test seams. Screen: a single writer `_reload` (sequence number, mounted check after each
  await, catch-all) giving four states (checking, granted, readOnly, denied); a failed read keeps the photos or shows the
  error state, only a successful empty read reaches `denied`; the Add button for PRO or for a lapsed user who holds photos
  (its tap goes through the gate to the paywall); the refusal outcomes (payment in flight: 'still activating'; server says
  NOT PRO: paywall + reload; server says PRO or unreachable: 'couldn't confirm'). Hub: the Progress row pushes for everyone.
regression_test_planned:
  - "test/contracts/progress_photo_client_rules_test.dart (19: classifier truth table, cap boundary 4/5/6, UTC wire value, IST window at the boundary)"
  - "test/contracts/progress_photos_lapsed_flow_test.dart (20 incl. a font warmup: lapsed gallery/delete/Add, failed reads, overlapping reloads, upgrade mid-reload, a payer's re-check vs a stale verdict, dispose, every refusal outcome)"
  - "test/contracts/progress_photo_capture_wiring_test.dart (8, presence only)"
  - "test/contracts/progress_photos_screen_gate_test.dart, test/profile/user_photos_hub_test.dart, test/profile/user_photos_gate_behavioral_test.dart, test/contracts/audit_2026_06_07_batch5_regression_test.dart (rewritten for the new behaviour)"
mutation_proof: >-
  34 mutants applied one at a time to the repository, the screen and the hub (each confirmed applied by an exact-one-match
  replace and a byte-compare restore), every one reddened at least one test: window = device-local midnight (red only under
  a non-IST device zone: 4 tests), window boundary +1 minute, wire value not UTC, call-site `taken_at` offset-less, the RLS
  message leg dropped, a bare 403 as a refusal, the in-flight leg widened to any StorageException / without the upload
  stage / with a constant `paymentInFlight: false` at the call site, P0001 without the marker, the refusal swallowed to
  `null` (class 2.49), the upload stage set before the picker, the free quality back, the stale read not dropped (sequence
  check removed), PRO-with-no-photos denied (13 red), a failed read treated as empty (4), Add's onFree hiding the photos,
  the in-flight and could-not-confirm branches opening the paywall, the Add button for read-only without photos, the
  listener dropping a mid-reload flip, no optimistic tile removal, the post-capture and post-delete reloads re-running the
  gate, `_uploading` never released, no reload after a server-confirmed lapse, the dirty re-run dropped, and the hub row
  doing nothing; after the B-pass: the cap boundary `>` for `>=`, a device-local window (red in the CI zone through a source pin), the cap query without the user filter, and a known verdict trusted over a running full re-check. First pass: 27 of 29 red; the two survivors (a re-gate after a capture or delete; no reload after a
  confirmed lapse) exposed real gaps, a gate-count assertion and a new no-photos test were added, and they then reddened.
impact_analysis: >-
  A PRO user sees no change except a spinner-first entry and that a delete or capture reuses the last verdict instead of
  re-gating. A never-PRO user now takes one RLS-scoped read of their own photos before the locked card (was synchronous);
  offline they see 'Couldn't load photos' with Retry instead of the upsell. A lapsed user keeps their photos. The
  `taken_at` change leaves old rows as stored (5.5 h late for IST users; another zone's skew is UNVERIFIED): effects on
  deploy day are a photo from the previous evening possibly counting toward the first day's cap and the sort order mixing
  old and new rows up to 5.5 h, both gone within a day; no backfill (it would have to guess each user's zone). Nothing
  outside this repository file reads `taken_at` (git grep over lib, supabase/functions, scripts, test).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "repository, screen, hub; flutter analyze lib clean of new findings; tests above" }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "progress photos are cloud-primary (no Hive mirror); the screen reads the subscription flag through SubscriptionService only" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "no migration; progress_photos.taken_at is timestamptz NOT NULL (022_progress_photos.sql:22), so the UTC value with Z is stored as the right instant" }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "B1's live-verify V4a/V4b/V4e (2026-10-07): a lapsed user can SELECT and DELETE their own rows; the INSERT refusal is migration 154" }
  - { tier: 9, name: "Storage buckets + objects", status: verified, evidence: "B1 V8d: the bucket's SELECT and DELETE policies are not subscription-gated (catalog text); createSignedUrl for a LAPSED account was NOT exercised live" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the refusal shapes (P0001 progress_photo_pro_required; Storage 'row-level security' message) come from migration 154's own header; the live Storage error shape is UNVERIFIED and the classifier is conservative for that reason" }
recurrence: "Class 2.49 (a failed read treated as 'absent') is the shape the single-writer screen guards against; this is a new instance class (several async writers of one screen state), recorded as bug class 2.96. The hub gate that locked out a lapsed user was b7c1e4's (2026-10-05) design, changed by founder decision 6."
related_bugs:
  - b7c1e4
  - d8f2a6
---

# A lapsed user could not reach their own progress photos, and `taken_at` was stored 5.5 h late

## What was wrong

Two gates on the way to the Progress screen (the hub row and the screen's entry) treated "not PRO" as "no access", so a user whose PRO lapsed could neither view nor delete photos they already held. The repository still had a free tier the database now refuses, and it swallowed the server's refusal into a generic failure. Separately, `capture` wrote an offset-less local time to a timestamptz column.

## Writer and reader

Writers: `capture` (row, `taken_at`, cap window), and the screen's state (now only `_reload`). Readers: `listStrict` (ordering), the Add button and gallery (what a user sees), the hub row (a push). The decision of what a not-PRO user may see moved from two doors to one place.

## The fix

See `proposed_fix`. Plan: `docs/plans/progress-photos-client-b2.md` (v5 after four review rounds).

## How it was verified

Four plan-review rounds, each by a fresh reader, severities falling (5 P1, 3 P1, 2 P1, 1 P1); then the tests and mutation run above; then a code-level B-pass on the real diff (`docs/reviews/`): no P0 or P1, three P2 (a known-verdict reload could overwrite a payer's running full re-check; the OI-322 window regression invisible under the CI zone; the cap boundary unpinned), all fixed in this batch with a test that fails without the fix. The zone matrix (Asia/Kolkata, UTC, America/Los_Angeles) is run BY HAND and is self-attested: CI pins Asia/Kolkata, where a device-local midnight equals IST midnight, so what guards the window in CI is a source pin on `progressPhotoCapWindowStartUtc`. Not verified, stated: a real Storage refusal's error shape, an image render for a lapsed account, anything on a device (founder device check, ledger).

## Candid notes

- Round 2 and round 3 each found P1s inside one mechanism (a verify after a refusal), so the mechanism was deleted rather than patched (the founder's own lesson).
- Round 4 still found a loop hazard in the upgrade listener; the plan states the guard (`_inFlight`, `_dirty`, one re-run) and a test proves a payer who upgrades mid-reload ends on the PRO gallery.
- The first mutation pass left two survivors; both were genuine test gaps and were closed.
