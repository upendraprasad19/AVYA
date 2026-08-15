---
bug_id: d3b8f1
date: 2026-08-15
batch: supabase-creds-test6
status: fixed
blast_radius: account
symptom: >-
  `SupabaseTestHelper.cleanup()` issues `DELETE ... eq('user_id', id)` across 12
  tables of the PRODUCTION project `dedsavbjuwgarrhphgnl`, and CI runs it on
  every push to `main`. On `main` there is NO boundary of any kind on which user
  it may target — whatever account the test credentials name is the account it
  wipes. The risk was bounded only by accident: `qa@icanbefitter.com` does not
  exist, so sign-in fails and `cleanup()` early-returns on a null id. The moment
  the credentials are repointed at an account that DOES exist — which is exactly
  what this batch is for — the accident stops protecting anything.
concept: delete_boundary_independent_of_credential
sot_registry_entry: not_applicable
writers:
  - "test/supabase/supabase_test_helper.dart cleanup() — issues the DELETE for
     each of 12 tables. It is the only writer on that path, and before this fix
     it had no target check at all."
  - "test/edge_functions/pgvector_test.dart setUp + tearDownAll — issue their OWN
     `memory_embeddings` deletes, bypassing cleanup() entirely. A guard placed
     only inside cleanup() would leave both of these uncovered."
readers:
  - "The production Postgres tables themselves: user_daily_snapshots,
     ai_coach_interactions, memory_embeddings, streaks, weight_logs,
     nutrition_logs, workout_logs, body_measurements, sleep_logs, user_progress,
     user_profile, user_preferences. There is no in-app reader — the damage is
     the deletion, and it is silent because each delete sits inside `catch (_)`."
  - "test/supabase/cleanup_target_guard_test.dart — the new reader of the
     boundary itself, asserting both that refusals happen AND that no delete is
     issued when one does."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: >-
  user_daily_snapshots, ai_coach_interactions, memory_embeddings, streaks,
  weight_logs, nutrition_logs, workout_logs, body_measurements, sleep_logs,
  user_progress, user_profile, user_preferences
cloud_columns: user_id
contract_test_path: test/supabase/cleanup_target_guard_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: >-
  This IS the cross-account guard. assertDisposableTarget refuses three ways: no
  session at all; a target absent from the qaUserIds allow-list; and a target
  that is not the current session's own id (so a stray `uid` argument cannot
  reach another QA account either).
forbidden_patterns_checked: >-
  Checked the prior art before designing: branch `supabase-ci-http-mock` already
  carries a guard, and it is DEFEATED — `testEmail = disposableTestEmail`, so its
  `signedInEmail != disposableTestEmail` clause compares a value to itself and
  can never fire. Its own error string names the scenario it cannot catch. That
  design was deliberately NOT harvested; its null-session and
  `targetId != signedInId` clauses were.
proposed_fix: >-
  Key the boundary on a `const Set<String> qaUserIds` of UUIDs rather than on an
  email. The set does not move when the credential moves, so repointing the
  credential yields a signedInId absent from the set and the delete is refused.
  Call assertDisposableTarget at ALL THREE delete sites, outside every
  `catch (_)`. Route cleanup()'s deletes through an overridable `deleteRows`
  seam so a test can assert zero deletes were issued. Separately, guard both
  `tearDownAll`s on a `setUpSucceeded` flag so a failed `setUpAll` no longer
  raises LateInitializationError over the top of the real failure.
regression_test_planned: >-
  test/supabase/cleanup_target_guard_test.dart — 9 tests, and deliberately
  credential-free so they run in the dart-define-less "Unit Tests" CI job.
  Mutation-proven three ways, each RUN: neutering the qaUserIds membership check
  reddens 1; removing the guard call from cleanup() reddens 1; MOVING the guard
  to after the delete loop reddens exactly the mirror test — the throw still
  happens, the rows are already gone.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ code touched — this is test infrastructure plus documentation." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "No Hive box or adapter involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No migration; no schema change." }
  - { tier: 4, name: postgres_data, status: fixed_in_this_batch, evidence: "This is the whole point: production rows across 12 tables were reachable by an unbounded DELETE. They are now reachable only for uuids in qaUserIds. Verified by the mutation runs — with the guard neutered the mirror test records deletes; with it intact, zero." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration applied." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy changed. RLS does not help here — the deletes run as the signed-in user against that user's own rows, which RLS permits by design." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read or written by this commit — the credential change is a separate commit." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "9/9 green with NO --dart-define, matching the Unit Tests job invocation exactly. Three mutations run and restored, baseline re-verified green after each." }
impact_analysis: >-
  No user-facing behaviour changes; nothing here ships in an APK. The exposure
  being closed is to the production DATABASE via CI. Before: any credential
  repoint silently made a real account deletable on every push to main, across
  12 tables, with each delete swallowed by `catch (_)` so the loss would be
  silent. Accounts at risk included `test2@gmail.com` … `test7@gmail.com`
  (test7 alone holds 133 memory_embeddings rows) and every human account.
  After: the target must be a uuid on an explicit const list AND the session's
  own id. Widening it is a visible diff a reviewer can see. The second fix
  (LateInitializationError) has no safety weight but removes a misleading error
  that would otherwise sit on top of the real one during the very triage this
  batch's next commit is expected to need.
related_bugs: []
recurrence: >-
  Second instance of the guard-defeated-by-aliasing shape in this repo. The
  first is the guard on branch `supabase-ci-http-mock`, which OI-115 documents
  and which is superseded here rather than fixed in place. No diagnose-doc
  exists for that one — it was written and reviewed but never merged — so there
  is no id to cite, which is why related_bugs is empty rather than populated
  with a guess. The broader class ("the guard shares an input with the thing it
  guards") is recorded in the harness memory as the guard-without-its-mirror
  family.
---

# The cleanup() delete boundary, keyed on UUID rather than email

## What was wrong

`cleanup()` on `main` had no target check. It took whatever id the session
carried and deleted that user's rows from 12 production tables. CI runs it on
every push to `main`.

Nothing bad had happened yet, and the reason is uncomfortable: the configured QA
account does not exist, so sign-in fails, `_userId` stays null, and `cleanup()`
returns early. The safety came from a broken credential, not from a guard. This
batch exists to fix that credential — so the protection was about to evaporate
in the same change that made the tests work.

## Why not the guard that already existed

Branch `supabase-ci-http-mock` carries an `assertDisposableTarget` with three
clauses. The middle one is:

```dart
static const String disposableTestEmail = 'qa@icanbefitter.com';
static const String testEmail = disposableTestEmail;      // alias
...
if (signedInEmail != disposableTestEmail) { throw ... }   // value vs itself
```

`testEmail` **is** `disposableTestEmail`, so signing in as one and comparing
against the other compares a value to itself. It can never fire. Its own error
message names the case it fails to catch — *"If you repointed testEmail to make
sign-in work…"* — which is precisely this batch.

Two of its three clauses are sound and are carried over: the null-session
refusal, and `targetId != signedInId`. Only the email comparison is replaced.

## Why a UUID set

The property that matters is that **the boundary must not move when the
credential moves**. A uuid set satisfies that: repointing the credential (or,
after the next commit, the secret behind it) produces a `signedInId` that is
simply absent from the set. Widening the set means editing a literal list of ids
— a visible, reviewable act rather than a side effect.

It has a second, non-obvious benefit. `qaUserIds` is `const`, so it evaluates
identically in the **Unit Tests** CI job, which runs `flutter test test/` with no
`--dart-define` at all. An email pin would evaluate to `''` there the moment the
credential became environment-backed — greening one CI job by reddening another.
That trap is real and was caught in review before it shipped.

## Coverage — all three delete sites

`git grep -n ".delete()"` over `test/` and `integration_test/` returns 12 lines,
of which 9 are string literals inside `test/contracts/` source-grep tests. The
LIVE call sites are three: `supabase_test_helper.dart` (the 12-table loop) and `pgvector_test.dart`
twice, in `setUp` and `tearDownAll`. The pgvector pair bypass `cleanup()`
entirely, so each gets its own call to the same guard — placed **outside** the
surrounding `try/catch (_)`, or the refusal would be swallowed and a blocked
delete would look like one that merely found no rows.

## What "fails closed" does and does not mean here

`cleanup()` still returns silently when there is no session at all. That is
deliberate and narrow: it runs in `setUp`, so throwing there would replace the
real `setUpAll` failure in every test of the file. No delete can be issued on
that path, so it is not a hole — but it is not the guard either, and an earlier
draft of this batch described it as "fails closed, loudly", which was wrong. It
fails closed *silently*. The guard is `assertDisposableTarget`, and it runs
whenever there IS an id.

## Mutation proof

Run, not asserted. Baseline 9/9 green before and after each restore.

| mutation | tests red |
|---|---|
| `qaUserIds` membership check neutered | 1 |
| guard call removed from `cleanup()` | 1 |
| **guard moved to AFTER the delete loop** | 1 — *the mirror test specifically* |

The third is the one worth keeping. Under it `cleanup()` still throws, so a test
asserting only `throwsA` would pass — while the rows had already been deleted.
Only the seam-backed "zero deletes were issued" assertion catches it.

## Also in this commit — the free-tier doc drift

Root `CLAUDE.md:171` and SIX other live documents claimed the free AI tier is a
"30-day trial, 15 msg/day". Both authoritative sources — `ai-proxy/index.ts:71`
(`FREE_DAILY_LIMIT = 10`, with an explicit "never re-introduce a trial window"
comment) and the live `enforce_chat_app_daily_limit` trigger — say **10/day
forever, no trial**. Three docs already said it correctly, so this was drift.

It is in this commit because it nearly mis-planned the batch: an earlier draft
budgeted a whole unit for a quota-exhaustion problem that does not exist.
Corrected in `CLAUDE.md`, `docs/architecture/ai.md`,
`docs/architecture/subscription.md`, `testing/web_test_plan.md`,
`testing/e2e/04_ai_coach.md`, and two **active agent instruction** files
(`backend-agent.md`, `auth-agent.md`) that would otherwise have had subagents
enforcing a rule the server does not implement. Dated records — ADR-0004, the
design specs, `.claude/tasks/` — are left alone: superseded is not wrong.
