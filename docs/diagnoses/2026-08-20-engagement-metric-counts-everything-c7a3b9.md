---
bug_id: c7a3b9
date: 2026-08-20
batch: fob5-hold-telemetry
blast_radius: account
status: fixed
symptom: >
  FOB-5 of OI-60, two defects in one function, one LIVE on the founder dashboard.
  (1) `founder_metrics_engagement().ai_messages_today` counted EVERY row of
  `ai_coach_interactions` with no channel predicate. AppEventsService writes UI
  analytics into that same table with `channel='app_event'`, so every event
  counted as an "AI message". Measured live 2026-08-20: 116 rows all-time, only
  22 of them real coach turns — a 5.3x overcount.
  (2) Hold weeks were unobservable: the five `phase_1_day_29_*` events have ZERO
  consumers repo-wide, so holds-taken / hold->convert / hold->churn were all
  unmeasurable while the free-tier retention thesis rests on that mechanic.
concept: founder_metrics_engagement
sot_registry_entry: hold_week_identity
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, line: 330, source: "holdWeek() now emits hold_week_started with its ordinal, at the LAST statement of the successful path — every earlier exit (no-plan early return, any throw) skips it, so the event cannot claim an unmaterialized hold" }
  - { file: lib/core/services/app_events_service.dart, line: 42, source: "AppEventsService.log — the writer whose channel='app_event' rows were being counted as AI messages; gains a debugCapture test seam so a caller's telemetry contract is assertable behaviourally" }
readers:
  - { file: supabase/functions/admin-dashboard-data/index.ts, line: 255, source: "spreads founder_metrics_engagement()'s row WHOLESALE (`...engagementRes.data`), which is why the three new hold_* columns reach the dashboard with NO Edge Function redeploy — and why a separate founder_metrics_holds() RPC was deliberately NOT created" }
  - { file: lib/features/ai_coach/repositories/coach_interaction_repository.dart, line: 282, source: "_coachChatChannels = {app, chat, in_app_orphan} — the repo's OWN definition of a coach message. The corrected metric mirrors it, so dashboard and app agree; FOB-5's prescribed `channel = 'app'` would have matched 7 of 116 rows" }
hive_key_prefix: n/a
hive_key_formula: "n/a — the metric reads the cloud table directly; the client half only WRITES an app_event row"
sync_methods: [n/a]
restore_methods: [n/a]
cloud_table: ai_coach_interactions
cloud_columns: [user_id, channel, user_message, ai_response, model_used, created_at]
contract_test_path: test/contracts/hold_week_mechanic_behavioral_test.dart
ist_handling:
  - { file: supabase/migrations/120_engagement_metric_channel_filter_and_hold_telemetry.sql, line: 89, fn: "every day-boundary in the function uses (now() at time zone 'Asia/Kolkata') — the new hold columns follow the same IST convention as the pre-existing ones, so a hold taken at 23:00 IST counts on the correct day" }
provider_invalidations: []
telemetry_op_types:
  success: [hold_week_started]
  failure: []
cross_account_guard: >
  AppEventsService.log returns early when currentUser is null, so no event is
  ever written for a signed-out session, and the row carries that user's id. The
  metric function is SECURITY DEFINER and, after the grant fix below, executable
  ONLY by service_role — reachable through admin-dashboard-data, whose own
  ADMIN_USER_IDS allowlist is the access control.
forbidden_patterns_checked:
  - "applying FOB-5's prescribed `where channel = 'app'` — NOT done. Verified live before writing any SQL: channel='app' is 7 rows of 116, so it would have swapped a 5.3x overcount for an ~89% undercount. §4.9 (never apply an audit finding without verifying the claimed cloud state) is exactly what caught it."
  - "CREATE OR REPLACE with a changed return type — impossible (42P13). The three added columns force a DROP + CREATE, which is why the grant handling below differs from migration 101's."
  - "a new founder_metrics_holds() RPC — NOT created. It would need an admin-dashboard-data redeploy (own §4.3 authorization) and would otherwise sit dormant, the shipped-but-uncalled shape OI-101 records."
proposed_fix: >
  Restrict ai_messages_today to the repo's own coach-chat channel set AND to
  rows with real content (both user_message and ai_response non-empty, which
  also drops the 38 stuck/pending in_app_orphan rows). Add three hold_* columns
  to the SAME function so hold telemetry reaches the dashboard without a
  redeploy, and emit hold_week_started from holdWeek().
regression_test_planned: >
  test/contracts/hold_week_mechanic_behavioral_test.dart — a new FOB-5 group (5
  cases) driving the REAL holdWeek() writer through an AppEventsService.debugCapture
  seam. Mutation-proven on three legs: removing the emit reddens 3, dropping the
  ordinal metadata reddens 2, and removing the try/catch around the emit reddens
  the throwing-sink case.
  PLUS test/contracts/admin_metrics_functions_role_revoke_test.dart — a second
  test added by the B-pass, asserting that EVERY post-103 migration which creates
  or drops a public.founder_metrics_* function re-asserts the anon+authenticated
  revoke. This is the SQL half made testable without credentials: it pins the
  committed migration source, not the live catalog. Mutation-proven — deleting
  migration 120's revoke line reddens it, and it carries a `checked > 0`
  assertion so it cannot pass by matching nothing.
  The LIVE privilege state is still verified out-of-band at apply time, since
  test/supabase/ is credential-blocked (OI-105/OI-121).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on both touched files; the analyzer also caught a dead null-guard in the first draft of the emit (Dart proved every path skipping the assignment also skips the emit), which was removed rather than suppressed" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "no Hive key added, read or written by this change" }
  - { tier: 3, name: postgres_schema, status: fixed_in_this_batch, evidence: "migration 120 applied; function signature 5 -> 8 columns, verified by calling it live" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "no row written or altered; the channel distribution was queried read-only before and after (116 rows unchanged, metric output 116 -> 22)" }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "backups/applied_migrations.json updated in this commit with BOTH applies — 120 and the follow-up grant revoke" }
  - { tier: 6, name: edge_function_deploy, status: verified, evidence: "NO redeploy needed and none done — admin-dashboard-data/index.ts:255 spreads the row, so new columns flow through. Confirmed by reading the EF source, not assumed" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron-dispatched function touched" }
  - { tier: 8, name: rls_policies, status: fixed_in_this_batch, evidence: "⚠ THE DROP CAUSED A REAL REGRESSION — see below. Final ACL verified {postgres=X,service_role=X}, matching both sibling metric functions; anon/authenticated execute = false; Supabase security advisor no longer lists this function under either SECURITY DEFINER exposure lint" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no bucket or object touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or added" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service touched" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "hold_week_started's serialized shape (Map.toString into user_message) is what the SQL LIKE predicate matches; both halves land in this commit" }
impact_analysis: >
  The dashboard's ai_messages_today will DROP sharply — 116 -> 22 all-time. That
  is the bug being removed, not new breakage, and it should be expected rather
  than investigated as a regression.

  ⚠ THE MOST IMPORTANT THING IN THIS DOC. The first live apply shipped an
  anon-executable SECURITY DEFINER function for a few minutes, and it was this
  batch's own doing. CREATE OR REPLACE preserves a function's ACL; DROP + CREATE
  does NOT — the new function picks up Supabase's DEFAULT PRIVILEGES on schema
  public, which grant EXECUTE to anon and authenticated. `revoke all ... from
  public`, copied verbatim from migration 101, does not remove those: PUBLIC and
  an explicit role grant are different things. Observed acl was
  {postgres=X,anon=X,authenticated=X,service_role=X} against siblings carrying
  only {postgres=X,service_role=X}. Caught by the tier-8 check in this very
  checklist and revoked immediately; migration 120's file now carries the extra
  revoke plus a comment explaining why 101's two lines are insufficient after a
  DROP. Exposure was aggregate counts only (no PII, no user rows) to anyone
  holding the public anon key, for the minutes between the two applies.
  The generalisable rule: ANY migration that DROPs and recreates a function must
  re-assert its grants explicitly and verify proacl afterwards.

  The hold columns read 0 until enable_hold_weeks flips. That is correct: no
  user can take a hold while the flag is OFF.
---

# c7a3b9 — the engagement metric counted everything, and holds counted nothing

## The measurement that decided the fix

FOB-5 says: *"add `where channel = 'app'` to the metric."* That is wrong, and one
live query showed it before a line of SQL was written:

| channel | rows | real turns | empty/pending | is it a coach message? |
|---|---:|---:|---:|---|
| `in_app_orphan` | 53 | 15 | **38** | yes — 38 are stuck rows |
| `food_text_analysis` | 24 | 24 | 0 | no — food AI |
| `app_event` | 22 | 0 | 22 | no — analytics |
| `app` | 7 | 7 | 0 | yes |
| `in_app` | 5 | 0 | 0 | no — not full turns |
| `promotion_ceremony` | 5 | 0 | 0 | no — templated |

`channel = 'app'` is **7 of 116**. Applying FOB-5 verbatim would have replaced a
5.3× overcount with an ~89% undercount — a worse number that *looks* like a fix.

The right predicate was already in the repo:
`_coachChatChannels = {'app','chat','in_app_orphan'}`
(`coach_interaction_repository.dart:282`). Mirroring it makes the dashboard and
the app agree on what a coach message is, instead of inventing a third answer.

The content filter is the half FOB-5 never mentions: 38 of the 53
`in_app_orphan` rows have no `ai_response` or are `model_used='pending'` — the
stuck-row class from the 2026-05-16 ai-proxy placeholder diagnose. A channel
filter alone still counts all 38.

**Result: 116 → 22.**

## Why the hold columns ride on an existing function

`admin-dashboard-data/index.ts:255` spreads the engagement row wholesale:

```ts
...(engagementRes.data as Record<string, unknown> ?? {}),
```

So new **columns** reach the dashboard with no Edge Function redeploy. A new
`founder_metrics_holds()` RPC would have needed one — a separate §4.3
authorization — and until then would have been a shipped-but-uncalled artifact,
which is exactly the dormant-gate shape OI-101 exists to record. FOB-5's
complaint was that the hold events had *no consumer*; adding a second one with
no consumer would not have closed it.

## The regression this batch caused, and how it was caught

`CREATE OR REPLACE` cannot change a return type (42P13), and this adds three
columns — so the migration must `DROP` first. That one word changes the grant
semantics completely:

- `CREATE OR REPLACE` **preserves** the existing ACL.
- `DROP` + `CREATE` starts fresh, and Supabase's **default privileges** on
  schema `public` grant `EXECUTE` to `anon` and `authenticated`.
- `REVOKE ALL ... FROM PUBLIC` — copied verbatim from migration 101 — does
  **not** remove those. `PUBLIC` and an explicit role grant are different things.

Observed immediately after the first apply:

```
founder_metrics_engagement    {postgres=X,anon=X,authenticated=X,service_role=X}   <-- mine
founder_metrics_ops           {postgres=X,service_role=X}
founder_metrics_for_admin_api {postgres=X,service_role=X}
```

A SECURITY DEFINER function was callable by anyone holding the public anon key,
via `/rest/v1/rpc/founder_metrics_engagement`, for the minutes between the two
applies. Exposure was aggregate counts only — no PII, no user rows.

Caught by walking tier 8 of the 12-tier checklist rather than by anything
automatic, revoked immediately, and confirmed closed two ways: the ACL now reads
`{postgres=X,service_role=X}`, and the Supabase security advisor no longer lists
this function under either SECURITY DEFINER exposure lint.

**The durable lesson, now written into the migration file itself:** any
migration that DROPs and recreates a function must re-assert its grants
explicitly and verify `proacl` afterwards. Inheriting the grant block from a
`CREATE OR REPLACE` migration is not safe.

**And the lesson is now MECHANICAL, not just written down** (added by this
batch's B-pass). A prose lesson in a diagnose-doc is exactly the kind of rule
that decays — §4.13 point 6 is the standing example. The existing regression
test for this bug class, `admin_metrics_functions_role_revoke_test.dart`, pinned
**migration 103 by name**, and 103 had stopped being the migration that owns
this function's ACL the moment 120 dropped and recreated it. The old test would
have stayed green through a replay that re-opened the leak. A second test in
that file now asserts the rule against the whole migration set — every migration
numbered `>103` that creates or drops a `public.founder_metrics_*` function must
carry its own `anon, authenticated` revoke. The `>103` cutoff is deliberate and
terminal: 101 *is* the original bug and 103 is its fix, so neither is rewritable.
Generalising one step further: **when a fix moves ownership of an invariant from
one artifact to another, the test that pins the invariant has to move with it —
or be rewritten to name the invariant rather than the artifact.**

## What the dashboard will look like

`ai_messages_today` drops sharply. That is the defect being removed. The three
`hold_*` columns read `0` until `enable_hold_weeks` flips — also correct, since
no user can take a hold while it is OFF.
