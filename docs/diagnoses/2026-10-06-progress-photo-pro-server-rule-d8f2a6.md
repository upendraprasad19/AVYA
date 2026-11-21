---
bug_id: d8f2a6
date: 2026-10-07
batch: progress-photos-pro-server-rule (unit B1)
status: fixed
tier: l_fix
blast_radius: catastrophic
symptom: >-
  The PRO gate on progress photos existed only in the client (the Photos hub row, the Progress screen entry and its Add button,
  and ProgressPhotoRepository.capture's own isPro read). A free user calling Supabase Storage or PostgREST directly could upload
  a progress photo object (the COST: capture() uploads first, then inserts the row) and insert a progress_photos row, because
  the progress_photos table policies were own-row only with no subscription test and the Storage bucket policy
  progress_photos_insert_own held only the bucket and own-folder conjuncts (live read E1, 2026-10-06). It is row C5 of
  docs/audit/progress-screen-pro-gate.closure.yaml, blocked_on_user until the founder's explicit go for a live apply.
concept: subscription_state — the server's one definition of PRO, status = 'active' AND end_date > now(), gains a new reader (the database itself, at both doors of a NEW progress photo).
sot_registry_entry: subscription_state (a reader entry for supabase/migrations/154_progress_photos_pro_insert_rls_rule.sql, docs/sot_registry.yaml). The plan's separate presence-only concept progress_photos_pro_insert_rule was replaced by this reader entry plus the contract test; recorded in the closure ledger.
writers:
  - { file: supabase/functions/verify-subscription/index.ts, method_or_widget: "the server definition of PRO (status = active and end_date > now), the copy the rule is pinned against", line: 1 }
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "writes the public.subscriptions rows the rule reads", line: 1 }
  - { file: supabase/migrations/038_redeem_referral_atomic.sql, method_or_widget: "redeem_referral_atomic writes referral_trial rows the rule also honours (OI-320: no per-referrer cap)", line: 1 }
readers:
  - { file: supabase/migrations/154_progress_photos_pro_insert_rls_rule.sql, method_or_widget: "policy progress_photos_insert_own (Storage) and trigger trg_progress_photo_pro / enforce_progress_photo_pro (row)", line: 1 }
  - { file: lib/features/profile/repositories/progress_photo_repository.dart, method_or_widget: "capture(): uploads first, then inserts the row; both doors now refuse a lapsed or free caller (the refusal handling lands in unit B2)", line: 81 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [user_id, status, end_date]
contract_test_path: test/contracts/progress_photos_pro_insert_rule_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "the trigger reads NEW.user_id under the caller's own RLS on subscriptions; a payer inserting a row for ANOTHER user's id is refused (P0001) and never accepted (live-verify V3f); the Storage policy keeps the own-folder conjunct."
forbidden_patterns_checked:
  - "a PRO conjunct on the table's UPDATE or DELETE policies — rejected (founder decision 6, 2026-10-06): a lapsed user may still VIEW and DELETE old photos; the rule is INSERT only."
  - "a SECURITY DEFINER helper function for the predicate — rejected: a definer would read subscriptions past RLS and widen the surface; the function is SECURITY INVOKER with a pinned search_path, the predicate copied not wrapped."
  - "a second narrower INSERT policy for the bucket — rejected: permissive policies OR together, so it would admit what the PRO conjunct refuses (live-verify V8a pins exactly one INSERT/ALL policy reaching the bucket; a tripwire in the contract test refuses a later one)."
  - "a branch-only dry run — rejected by the founder in favour of an always-aborting production dry run (the branch replays repo migrations with known gaps)."
proposed_fix: >-
  One DO block (migration 154): ALTER (or, on a fresh database, CREATE) the Storage policy progress_photos_insert_own on
  storage.objects with a third conjunct, EXISTS (an active unexpired subscription row of the caller); a SECURITY INVOKER function
  enforce_progress_photo_pro (search_path public, pg_temp) raising P0001 progress_photo_pro_required; a BEFORE INSERT row trigger
  trg_progress_photo_pro on public.progress_photos; DROP POLICY IF EXISTS users_own_subscriptions on public.subscriptions
  (a no-op live; it makes a database rebuilt from the repo match live, and the rule depends on there being no client write path
  into subscriptions). lock_timeout 5 s inside the block, so a lock wait aborts everything and a re-run is idempotent.
regression_test_planned:
  - "test/contracts/progress_photos_pro_insert_rule_test.dart (211 tests): the statement-level pins of the policy and the function, the INSERT-only pins, the cross-copy predicate pins (verify-subscription, the shared Edge helper, the cap functions' LIVE definitions through migration_cap_reader), a lexical SQL reader, a tripwire over every later migration (with hash-bound allow-list), the second-door scan, the subscriptions-policy census, the arbiter script pin and the live-verify structural pins."
  - "test/sql/progress_photos_pro_insert_rule_live_verify.sql: one always-aborting DO block, 30 cases (V0-V9), read on live after the apply: 30 of 30 ok; before the apply 16 failed exactly where the rule was missing."
  - "test/sql/onconflict_live_arbiter.sql: case 16 seeds an active subscription before the photo upsert (the trigger fires for the postgres role too) and removes it right after; 28 of 28 ok on live."
mutation_proof: >-
  Round 1 to 3 pins were mutated in a local replica (a supabase/postgres 17.6 container holding the live objects of evidence E1-E16):
  16 deliberately wrong policies and trigger functions, each flagged by the live-verify file (an OR-widened policy fails V3d, a
  `>=` fails V6c/V6d, a function reading auth.uid() fails V3e, an early return for non-authenticated roles fails V4f). The Dart
  pins were mutated against the real draft file: H1-H11 (grace window, is_pro: true, a dropped user_id filter, the cutoff
  argument, the ON CONFLICT arbiter, V8c reverted to qual-only, V3f dropped) all reddened. Round 5 (B-pass) added and mutated:
  the GRANT/REVOKE tripwire for table lists and schema-wide forms (3 and 2 red when reverted), the anchored predicate parity pin
  (a grace window in the function: 8 red; in the policy: 3 red), the unqualified-objects patterns (1-2 red each) and
  session_replication_role (2 red). The apply itself was proved on live by reading the catalog back and by the before/after
  live-verify (16 failing cases before, 0 after).
impact_analysis: >-
  Behavioural: a FREE or lapsed caller can no longer create a progress_photos object or row through any door; a PRO caller is
  unaffected (V3a/V3b/V7a/V7b ok). A lapsed user can still SELECT and DELETE (V4a/V4b/V4e ok). Existing writers are unaffected
  (arbiter 28 of 28 ok, including the ON CONFLICT photo upsert through the trigger). The trigger fires for every role, including
  postgres and service_role (V4f); only the table owner can step around it (session_replication_role = replica, DISABLE
  TRIGGER). The lock footprint of the apply was wider than first stated: supautils hooks (policy_grants on policy DDL,
  drop_trigger_grants on DROP TRIGGER) lock the same 24 auth, realtime and storage tables ACCESS EXCLUSIVE until commit; the 5 s
  lock_timeout bounds the wait. Debug builds can show PRO with no subscriptions row and will now be refused by the server (named in the
  migration header and in lib/features/profile/CLAUDE.md). Unverified: the out-of-repo Telegram bot project (ledger row S9) —
  the founder must confirm it does not insert progress_photos rows.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "capture() reads isPro and uploads first, then inserts; read, unchanged in this unit (the refusal handling and the free-branch deletion are unit B2)" }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "no Hive access" }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "policy progress_photos_insert_own now carries the subscriptions EXISTS; trigger trg_progress_photo_pro enabled (tgenabled O), function proconfig search_path=public, pg_temp, prosecdef false; read back on live 2026-10-07" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "1 progress_photos row on live before and after; the live-verify and arbiter residue reads were 0 seed rows, 0 synthetic users, 0 open transactions" }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "list_migrations shows 20261007181916 154_progress_photos_pro_insert_rls_rule; backups/applied_migrations.json carries migration 154 with the file hash (Gate 39)" }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "deployed verify-subscription v16 carries the repo predicate (evidence E28); no Edge Function changed" }
  - { tier: 8, name: "RLS policies", status: fixed_in_this_batch, evidence: "public.subscriptions has exactly subscriptions_select_own:SELECT (V9 ok); the table's four own-row policies unchanged (V8f ok)" }
  - { tier: 9, name: "Storage buckets + objects", status: fixed_in_this_batch, evidence: "the only INSERT/ALL policy reaching the progress-photos bucket is the altered one (V8a ok); every INSERT/ALL policy names one bucket (V8b ok); UPDATE policies scoped on both qual and check (V8c ok); SELECT and DELETE policies unchanged (V8d ok)" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "a refusal surfaces to the client as 42501 (Storage) or P0001 progress_photo_pro_required (row); capture() maps both to its generic upload failure today and unit B2 adds the paywall handling; the just-paid window is covered by verify-subscription writing the row before it tells the client" }
recurrence: "Not a recurrence of a fixed bug; the closest class is the cap triggers (111/113/114/127/129/132/153), which this rule's error idiom and predicate copy follow. The guards over the migration TEXT (a lexical reader and a tripwire over later migrations) are new; the B-pass found their GRANT/REVOKE and unqualified-name patterns too narrow (bug class 2.95)."
related_bugs:
  - b7c1e4
  - e6c4a9
---

# The PRO rule for progress photos lived only in the client

## What was wrong

A free user could not reach the upload button, but nothing in the database stopped a direct call. The cost sits at the Storage object (capture() uploads first), the gallery at the table row; both were own-row only. A paid-feature gate that only the app enforces is a convention, not a rule.

## Writer and reader

Writer of the predicate's data: the payment and referral paths write `public.subscriptions`. Readers: the client gate (display), `verify-subscription` (the server definition), the cap triggers, and now the database at both doors of a new progress photo. The migration is the new reader; its predicate is a copy, pinned against the others by `test/contracts/progress_photos_pro_insert_rule_test.dart`.

## The fix

See `proposed_fix`. INSERT only, by the founder's decision 6 (a lapsed PRO user may view and delete old photos). The migration file's header carries the intent, the destructive marker (`DROP ... IF EXISTS`, a no-op live), the inline rollback and the lock analysis.

## How it was verified

Five review rounds before the apply: six smaller-model seats, then a Hermes pass of seven Opus lens seats (`docs/audit/2026-10-06-hermes-progress-photos-pro-server-rule.md`, 24 findings, none P0 or P1), then a B-pass (`docs/reviews/`, five findings, all fixed). A production always-aborting dry run reached its `dry_run_rollback` line with nothing persisted. The live apply was done by the founder in the dashboard SQL editor because the Claude Code permission classifier denied `apply_migration` as a production deploy; the ledger row was inserted in the same session. After the apply the catalog read-back, the 30-case live-verify and the 28-row arbiter all passed, and the residue reads were clean.

## Candid notes

- The arbiter was run in a wrapped form (no `BEGIN ... ROLLBACK`; the results raised as a final error) because its own `BEGIN ... ROLLBACK` is unsafe through `execute_sql`. The 28 cases are the file's.
- The live-verify "before" run pasted the script without its comments; the statements are the file's.
- Reviewer models: rounds 1-3 smaller-model seats; the Hermes seats were Opus, run before the founder's Sonnet-only rule of 2026-10-07; the B-pass seat's model is not asserted.
- Another session applied `155_wle_single_live_summary` and `156_user_progress_snapshot_monotonic_weeks_and_date` to live around this apply; their repo files are not on `main` yet, and the tripwire may need an allow-list line when they land.
- Pre-existing items found on the way: OI-320 (no per-referrer cap on `referral_trial` credit), OI-321 (`clean-orphan-media` `.maybeSingle()` with two active rows), OI-322 (`taken_at` stored without an offset).
