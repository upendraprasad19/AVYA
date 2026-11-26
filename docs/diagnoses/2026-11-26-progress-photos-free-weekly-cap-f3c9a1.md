---
bug_id: f3c9a1
date: 2026-11-26
batch: OI-348 Landing 3c (P2)
status: fixed_in_code_apply_pending
tier: full
blast_radius: account
symptom: |
  OI-348 walk P2 (founder, 2026-11-24): a free user has no way to add a progress photo. The Progress screen showed a free user with no photos the PRO locked card and no Add button (progress_photos_screen.dart:375-377 on main), and the database refused every non-PRO upload at both doors (migration 154). Founder calls 2026-11-26: free users may upload ONE photo per IST week, counted by the server; PRO has no cap; a lapsed PRO is free; photos resized to 2048 px. Two defects found on the way: (1) a WEB upload never worked: capture() uploaded `File(xfile.path)` (dart:io), which cannot open a web pick's blob URL; (2) the orphan sweeper `cleanupOrphanedStorage` compared ALL of a user's objects with ALL rows, so a truncated row read would have removed real photos (it had no caller, OI-315).
concept: subscription_state
sot_registry_entry: subscription_state
writers:
  - { file: lib/features/profile/repositories/progress_photo_repository.dart, method_or_widget: "ProgressPhotoRepository.capture (the Storage object + the progress_photos row)", line: 279 }
  - { file: test/sql/progress_photos_free_weekly_cap_draft.sql, method_or_widget: "enforce_progress_photo_pro: NEW.created_at := the object's created_at (row door writer of created_at)", line: 171 }
readers:
  - { file: test/sql/progress_photos_free_weekly_cap_draft.sql, method_or_widget: "enforce_progress_photo_object_cap (storage door: counts the owner's objects this IST week; reads subscriptions)", line: 97 }
  - { file: test/sql/progress_photos_free_weekly_cap_draft.sql, method_or_widget: "enforce_progress_photo_pro (row door: counts rows in the object's IST week; reads subscriptions)", line: 166 }
  - { file: lib/features/profile/repositories/progress_photo_repository.dart, method_or_widget: "freeSlotOpen / ensureFreeSlotOpen (client courtesy count of this week's objects)", line: 381 }
  - { file: lib/features/profile/screens/progress_photos_screen.dart, method_or_widget: "_reload (gateAndVerify verdict -> pro / free) and _onAddPhoto (free path: slot check before the picker)", line: 110 }
hive_key_prefix: "none (cloud-primary feature, no Hive mirror)"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: progress_photos
cloud_columns: [user_id, storage_path, created_at]
contract_test_path: test/contracts/progress_photos_free_weekly_cap_rule_test.dart
ist_handling: ["IST week = Monday 00:00 Asia/Kolkata: SQL public.progress_photo_week_start, client progressPhotoWeekStartUtc (built on istDateOf / istMidnightUtc); pinned at Sunday 23:59:59.999 / Monday 00:00 IST in progress_photo_client_rules_test.dart"]
provider_invalidations: ["none: the screen re-reads through its single writer _reload"]
telemetry_op_types:
  success: []
  failure: ["debugPrint only, as before: [ProgressPhotoRepository.capture] orphan kept / slot check failed, [ProgressPhotoRepository.cleanupOrphanedStorage] scan failed / remove failed"]
cross_account_guard: "Every path the client lists, reads rows for or removes is under the signed-in user's own folder (userId prefix) and rows are read with eq(user_id). Server: the storage trigger leaves an anon or authenticated caller writing into ANOTHER folder to RLS (no count, no lock, no answer about that user's week); the row door adopts an object's created_at only for an object under NEW.user_id's own folder."
forbidden_patterns_checked:
  - { pattern: "a policy conjunct as the only free-cap door (a signed upload URL is checked when minted, not when it lands)", absent: true }
  - { pattern: "counting rows by a client-settable created_at (the row door sets it server-side; an UPDATE cannot move it)", absent: true }
  - { pattern: "import 'dart:io' / File( in the progress-photo repository (web upload)", absent: true }
  - { pattern: "an orphan sweep over ALL objects vs ALL rows (bounded to this IST week's candidates, rows read by path)", absent: true }
  - { pattern: "an automatic paywall push on a free user's refusal; GO PRO without showsUpgradeAffordance() (ADR-0022)", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-landing3c.md (plan review x2, both rounds' findings folded: sections 2 and 6a). Server, one migration drafted at test/sql/progress_photos_free_weekly_cap_draft.sql (number minted after the founder's go): week-start function; a BEFORE INSERT trigger on storage.objects WHEN bucket = progress-photos (SECURITY DEFINER, advisory lock per owner, PRO passes, a non-PRO owner may hold one object created this IST week; anon/authenticated into another folder left to RLS; NULL / non-uuid folder refused); the INSERT policy back to own-folder only; the row door made SECURITY DEFINER and week-aware (created_at from the object, count in that week); a BEFORE UPDATE guard keeping created_at; EXECUTE revoked; inline rollback to 154's live state including its ACL. Client: capture makes no tier decision, picks 2048/2048/85, uploads bytes (uploadBinary), removes its own object after a failed row insert only once a read shows no row; ensureFreeSlotOpen (list, bounded sweep, count) before the picker for a free verdict; the screen shows everyone the gallery and Add, the free caption, the weekly-used snackbar (GO PRO behind showsUpgradeAffordance()); copy in lib/core/copy/progress_photo_copy.dart; paywall benefit and subtitle; hub subtitle.
regression_test_planned: |
  test/contracts/progress_photos_free_weekly_cap_rule_test.dart (19: whole-text pins + 15 in-process mutants + rollback = 154); test/contracts/progress_photo_client_rules_test.dart (week start, held count, orphan candidates, content type, classifier literal); test/contracts/progress_photo_free_slot_test.dart (14, repository seams); test/contracts/progress_photo_capture_wiring_test.dart (presence); screen: progress_photos_screen_gate_test.dart, progress_photos_lapsed_flow_test.dart, progress_photos_free_flow_test.dart; live: test/sql/progress_photos_free_weekly_cap_live_verify.sql (W1-W15, C1-C5).
mutation_proof: |
  SQL text: 15 mutants applied in-process by the rule test (each asserts its pattern occurs in the draft before rewriting it), 15 of 15 break at least one pin. Repository: see "Mutations" below. Screen: see "Mutations" below.
impact_analysis: |
  Free and lapsed users can add one progress photo per IST week from web and Android; PRO users add without a cap. Old +50 clients keep their PRO-only screen (the server change is a superset for PRO). Photos are smaller (2048 px, JPEG 85 instead of 3000 px, 95). The server rule now fails OPEN if the storage trigger is ever dropped (154's conjunct failed closed): accepted and named on OI-316.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "progress_photo_repository.dart, progress_photos_screen.dart, user_photos_screen.dart, paywall_sheet.dart, progress_photo_copy.dart (new); flutter analyze clean on the touched lib files." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive mirror for progress photos." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "Live 2026-11-26: progress_photos columns (created_at timestamptz default now() nullable), trigger trg_progress_photo_pro, enforce_progress_photo_pro prosecdef=false with ACL {=X,postgres,anon,authenticated,service_role}; postgres holds TRIGGER on storage.objects; auth.role()/auth.uid() definitions read." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "1 progress_photos row, 1 object in the bucket: the feature is unused; no data migration." }
  - { tier: 5, name: "Migrations applied", status: deferred, evidence: "The migration is applied only after the founder's go (draft + rehearsal first); ledger and snapshot in the apply commit." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed (ai-media-proxy and the purge list only name the bucket)." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None (clean-orphan-media sweeps chat-media only)." }
  - { tier: 8, name: "RLS policies", status: fixed_in_this_batch, evidence: "progress_photos_insert_own back to own-folder only (draft); live policy set read 2026-11-26: no UPDATE policy on the bucket; SELECT/DELETE own folder." }
  - { tier: 9, name: "Storage buckets", status: verified, evidence: "progress-photos: private, 8 MiB, jpeg/png/webp (live 2026-11-26); content type now from the picker's MIME within that set." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: deferred, evidence: "Supabase Storage's mapping of a trigger 42501 and its signed-upload path are checked by the founder's web upload after the apply (plan section 6)." }
  - { tier: 12, name: "Client -> server contract", status: fixed_in_this_batch, evidence: "Both refusals keep the literal progress_photo_pro_required the shipped classifier reads; the client also accepts the literal inside a StorageException." }
recurrence: "Not a recurrence. Related: d8f2a6 (migration 154, the PRO-only server rule this replaces; its 'no definer' choice was for a callable predicate, not a trigger), c2b7e4 (the lapsed-user screen this generalises), b7c1e4 (the screen's own gate)."
related_bugs: [d8f2a6, c2b7e4, b7c1e4]
---

# Free users get one progress photo per IST week; PRO unlimited (OI-348 Landing 3c)

## What happened
The founder's walk (P2) found no way for a free user to add a progress photo. That was the design of OI-314 / migration 154 (PRO only). The founder changed the product on 2026-11-26: one free photo per IST week, counted by the server; PRO uncapped; lapsed = free; 2048 px.

Reading the upload path turned up two defects that would have broken the new feature at once: the web upload used `dart:io File`, which cannot open a web pick (so no web user, free or PRO, could ever upload), and the orphan sweeper compared every object with every row.

## PROVEN
- The SQL draft's text, whole, and 15 regressions of it (rule test).
- The client week start, slot count, orphan selection and content type (pure tests); the slot check, sweep and cleanup through the repository seams.
- The screen's free / PRO / lapsed / refusal flows (widget tests, real SubscriptionService).

## NOT YET PROVEN (founder go needed)
- The migration on the live database: the always-aborting rehearsal (draft + live verify in one statement), then the apply and the live verify (W1-W15, C1-C5).
- Storage's answer to a trigger refusal and a real upload from the web app (the founder's check, plan section 6, including two tabs at once for the concurrency design).

## Mutations
Rule 21. Every mutant applied by a script that refuses unless its pattern matches EXACTLY once; the file restored
by `cp` from a snapshot and `cmp`-identical after every mutant (never `git checkout`).

- SQL text (rule test, in-process): 15 of 15 break at least one pin (WHEN dropped, week bound dropped, lock
  removed, INVOKER, PRO branch disabled, the role test of the early return replaced by the round-1 form, NULL owner
  allowed, the object's created_at never adopted, the owner prefix of the adoption dropped, the row week's upper
  bound dropped, the UPDATE guard dropped, 154's conjunct kept in the policy, a REVOKE dropped,
  `trg_progress_photo_pro` re-created, the storage door's SQLSTATE changed to P0001).
- Repository (scratchpad `m3c/mutate.js`; client rules + free slot + wiring, 55 tests): 12 of 12 red. Week start
  ignores the weekday [6]; cap 2 [7]; an unreadable created_at counted [1]; orphan age 0 [4]; last week's objects
  as candidates [3]; `removeIfNoRow` ignores the row [2]; the sweep removes candidates with rows [3]; a removed
  orphan still counted [2]; a failed cleanup not remembered [1]; an offset-less instant read as device-local [1];
  the storage literal not a refusal [1]; the picker MIME ignored [1].
- Screen (agent run; gate + lapsed + free-flow files, 64 tests): `await _repo.ensureFreeSlotOpen()` removed [17];
  the GO PRO action unconditional [3]; `_access = _Access.pro` for both verdicts [14].
- Not mutated: the PRO-path `unawaited(_repo.cleanupOrphanedStorage())` (pinned by presence in the screen gate
  test's one-caller pin; best effort, nothing observable on the screen).

## Residue, stated
- Concurrency of two parallel free uploads is designed (advisory lock, fresh snapshot), measured only by the founder's two-tab check.
- A device clock hours behind across Monday can make the courtesy pre-check refuse a free user whom the server would accept.
- The rule fails open if the storage trigger is dropped (OI-316).
