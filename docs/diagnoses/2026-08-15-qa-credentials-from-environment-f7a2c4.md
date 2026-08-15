---
bug_id: f7a2c4
date: 2026-08-15
batch: supabase-creds-test6
status: fixed
blast_radius: platform
symptom: >-
  The CI job `Supabase Integration Tests` fails on every push to `main` with
  `AuthApiException: Invalid login credentials, statusCode: 400`. The suites
  sign in as `qa@icanbefitter.com`, and a live query of `auth.users` on
  `dedsavbjuwgarrhphgnl` returns ZERO rows for that address — the account does
  not exist and never did on this project. Because setUpAll dies, **zero
  assertions in either integration file have ever executed** (OI-121). The
  password for that non-existent account, `QA_Test_2024!`, is a literal
  committed to git in six files (OI-116).
concept: qa_credentials_from_environment
sot_registry_entry: not_applicable
writers:
  - "test/supabase/supabase_test_helper.dart:signIn() — the single sign-in for
     test/supabase/. Read testEmail/testPassword, which were literals."
  - "test/edge_functions/ai_proxy_test.dart + pgvector_test.dart setUpAll — each
     INLINED the same pair rather than using the helper, so changing the helper
     alone would have fixed one of three sign-in sites."
  - "integration_test/helpers/auth_helper.dart — kTestEmail/kTestPassword, typed
     into the sign-in form by the device flows. Had no skip-gate at all."
readers:
  - ".github/workflows/test.yml — the two integration steps, which pass the
     values through as --dart-define. Their `if:` guards and the announce step
     decide whether the job verifies anything or silently reports green."
  - "supabase/seed_qa.sql — seeds the QA row; carried both the old email and a
     fixed uuid 00000000-0000-0000-0000-000000000001 that no grep for the email
     would ever surface."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: auth.users, users
cloud_columns: email
contract_test_path: test/supabase/cleanup_target_guard_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: >-
  Supplied by the sibling commit d3b8f1 — the uuid-keyed delete boundary. That
  ordering is the point: repointing a credential is only safe once the boundary
  has stopped reading the credential.
forbidden_patterns_checked: >-
  Ran `git grep -n "qa@icanbefitter"` and `git grep -n "QA_Test_2024"` to EMPTY
  rather than until failures stopped. Two sites surfaced only after the first
  sweep looked clean, and seed_qa.sql's fixed uuid was invisible to both greps —
  it had to be read.
proposed_fix: >-
  testEmail/testPassword become String.fromEnvironment('SUPABASE_TEST_EMAIL' /
  'SUPABASE_TEST_PASSWORD'). hasCredentials widens from TWO inputs to FOUR via a
  pure credentialsComplete(url, key, email, password). Both edge_functions files
  drop their own two-value skip-gates and delegate to it. auth_helper gains
  kTestCredentialsPresent, which it never had. test.yml gets both secrets at job
  level, four-input guards on both steps, quoted --dart-define values, and an
  announce step widened to name all four. seed_qa.sql, the email-as-data upserts
  and the prose sites are repointed.
regression_test_planned: >-
  test/supabase/cleanup_target_guard_test.dart gains a credentialsComplete
  group — one case per clause, so deleting any clause reddens exactly that case.
  The email case is the one this batch introduced and the one whose absence is
  indistinguishable from a wrong password. Credential-free by construction, so
  it runs in the dart-define-less Unit Tests job.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ code touched." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "No Hive box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No migration." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "test6@gmail.com confirmed present in auth.users (039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4, last sign-in 2026-08-13 17:33 UTC). Its subscriptions row reads status='active' but end_date 2026-07-03 — EXPIRED, so checkPro is false and it is a FREE-tier account." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration applied." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function changed or deployed." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy changed." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket involved." }
  - { tier: 10, name: secrets, status: verified, evidence: "SUPABASE_TEST_EMAIL and SUPABASE_TEST_PASSWORD confirmed present by NAME via `gh api repos/:owner/:repo/actions/secrets` (updated 2026-08-14T17:49Z). The API never exposes values, so their CORRECTNESS is unverified — see impact_analysis." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "All three sign-in sites now read the same environment-driven constants; `git grep` for both literals returns empty outside dated records. 14/14 green in the credential-free guard+predicate suite." }
impact_analysis: >-
  This is the commit that flips the integration job. Nothing user-facing changes
  and nothing ships in an APK.

  WHAT REMAINS UNVERIFIABLE BY ME, STATED PLAINLY: I do not have and will not
  handle the password, so I cannot prove the secret's VALUE is right. If it is
  wrong the job fails with `Invalid login credentials` — the identical string it
  fails with today. That would be the secret, not this change; the founder can
  distinguish it in one step by signing into the app as test6.

  EXPECT GENUINE FIRST-RUN FAILURES. OI-121 records that zero assertions in
  either file have ever executed, and OI-105 and OI-116 both predict real
  defects surfacing the first time they do. A red run after this lands is more
  likely to be those tests working than this change being wrong.

  Deleting test6's rows is the intended behaviour — the founder created it for
  testing only. `cleanup()` also wipes its chat history on every run, and
  ai_proxy_test spends 3 of its 10 daily free messages per run; both are
  cosmetic for a test account but would look like bugs during a hand-test.
related_bugs: []
recurrence: >-
  Not a recurrence of a fixed bug, but the second half of a pair: d3b8f1 (the
  uuid delete boundary) is its precondition. The input-set-width class recurs
  here in the predicate — widening from two inputs to four is exactly the shape
  of that family, and it was caught in review rather than by me.
---

# QA credentials from the environment, and the four-input gate

## The three sign-in sites

Changing the helper alone fixes one of three. `ai_proxy_test.dart` and
`pgvector_test.dart` each inlined their own copy of the email and password, and
each carried its own two-value skip-gate that never consulted the helper. Both
now delegate to `SupabaseTestHelper.hasCredentials`.

## Why the gate had to widen to four, not three

The prior work on the unmerged branch converted the **password** to an
environment read and left the **email** bound to a constant that still named the
dead account. Harvesting that as-is would have wired up both secrets, passed its
own tests, and left CI failing with the byte-identical error it fails with now.

Then the predicate itself: it checked url + anonKey. Adding two environment
inputs without widening it converts a credential-absent run from a loud SKIP
into a live `signInWithPassword(email: '', password: '')`, whose failure is
`Invalid login credentials` — the same string as a wrong password, and the same
string as today's bug. A missing secret would present as a code defect.

## The silent-green trap

`test.yml`'s announce step existed precisely because a previous version of this
job reported green while running nothing (OI-105). Widening the two step guards
to four inputs while leaving the announce narrower would have recreated that
exactly: with a missing `SUPABASE_TEST_EMAIL` both steps skip, the job goes
green, and nothing says why. The announce now names all four and lists which are
missing.

## What a grep could not find

`supabase/seed_qa.sql` carried the old email on three lines *and* a fixed uuid
`00000000-0000-0000-0000-000000000001` on a fourth. No search for the email
surfaces that uuid. Repointing only the email lines would have left the seed
asserting test6's address under a phantom id. It was found by reading the file,
which is the only thing that finds it.

## Ordering

The uuid boundary (`d3b8f1`) lands in the commit before this one, and that is
not cosmetic. Under the previous email-comparing guard, making the email
environment-driven would have recreated the aliasing tautology by a new route —
both sides of the comparison moving together again. The boundary had to stop
reading the credential before the credential could move.
