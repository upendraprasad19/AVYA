---
bug_id: c3f8a1
date: 2026-07-26
batch: batch-0-restore-push
status: fixed
blast_radius: platform
symptom: >-
  Every cron-dispatched Edge Function that carries the isAuthorizedCronCall gate
  returns HTTP 401 on every tick — 17 of the 18 HTTP cron jobs. No push
  notification has been delivered to any user for at least 24h, and plausibly
  since 2026-05-30. Invisible from cron.job_run_details, which reports
  "succeeded" for all 22 jobs. The single exception is compute-coach-signals,
  which works precisely because it has NO auth gate at all.
concept: cron_auth_gate
recurrence: >-
  Third instance of the cron 401-storm class. Prior: 5a65bd (2026-05-15,
  pr-detection 401 loop, same function list) and the 2026-05-12 audit P0
  (Vault service_role_key row unpopulated). This instance was CAUSED BY the
  "class fix" authored to close 5a65bd permanently.
related_bugs: 5a65bd, 7ad0c4
sot_registry_entry: n/a — cron auth is an Edge Function request-gate, not a Hive/cloud state concept with a writer-reader pair
writers:
  - { file: supabase/functions/_shared/cron_auth.ts, method: isAuthorizedCronCall, line: 97 }
  - { file: supabase/functions/_shared/cron_auth.ts, method: isAuthorizedCronCall_cron_secret_branch, line: 91 }
readers:
  - { file: supabase/functions/streak-guardian/index.ts, method_or_widget: serve_auth_gate, line: 52 }
hive_key_prefix: n/a — server-side only, no Hive participation
hive_key_formula: n/a — server-side only, no Hive participation
sync_methods: []
restore_methods: []
cloud_table: cron.job
cloud_columns: [jobid, jobname, schedule, command, active, username]
contract_test_path: test/contracts/cron_auth_adoption_test.dart
ist_handling:
  - { file: supabase/functions/_shared/cron_auth.ts, line: 91, fn: no_date_logic_in_auth_gate }
provider_invalidations: []
telemetry_op_types:
  success: [cron_call_log_started, cron_call_log_finished]
  failure: [cron_auth_401_unlogged]
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "SUPABASE_JWT_SECRET", absent_after_fix: true }
  - { pattern: "app.settings.service_role_key", absent_after_fix: true }
proposed_fix: >-
  Migration 107 repoints the 16 verify_jwt=false HTTP cron jobs plus the
  proactive-coach-promotion trigger onto the CRON_SECRET path, adds a
  locked-down private.cron_get_secret() Vault accessor that RAISES rather than
  returning NULL, and revokes the default PUBLIC execute grant from
  private.morning_alert_get_service_key(). Migration 108 handles the two
  verify_jwt=true jobs after their gateway flags flip. Migration 109 adds the
  absence-based alert_cron_silence and creates the missing
  cleanup_cron_call_log(). _shared/cron_auth.ts is rewritten to a pure shared
  secret, dropping the dead JWT branch and the deno.land/x/jose dependency.
regression_test_planned:
  - test/contracts/cron_auth_no_reserved_prefix_env_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "server-side cron auth only; no Dart touched" }
  - { tier: 2_hive, status: not_applicable, evidence: "no local state participates" }
  - { tier: 3_postgres_schema, status: verified, evidence: "no schema change; migration rewrites cron.job.command text and two function ACLs only" }
  - { tier: 4_postgres_data, status: verified, evidence: "vault.decrypted_secrets shows cron_secret present (len 20, no surrounding whitespace) alongside service_role_key (len 219)" }
  - { tier: 5_migrations_applied, status: fixed_in_this_batch, evidence: "migration 107 authored; backups/applied_migrations.json to be updated in the same commit at apply time" }
  - { tier: 6_edge_function_code_vs_deploy, status: verified, evidence: "cron_auth.ts:91-94 CRON_SECRET branch confirmed present in the deployed source; no redeploy needed per Supabase docs on secret propagation" }
  - { tier: 7_cron_jobs, status: verified, evidence: "22 jobs, all username=postgres; 17 use morning_alert_get_service_key, 1 uses the NULL-returning app.settings.service_role_key, 18 HTTP total, 4 pure-SQL untouched" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no table RLS involved; function-level ACL handled in migration section 2" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects touched" }
  - { tier: 10_secrets, status: verified, evidence: "SUPABASE_JWT_SECRET absent from both custom and default Edge secret lists AND rejected by the dashboard as a reserved prefix; Vault service_role JWT decoded valid (HS256, role=service_role, exp 2089829852)" }
  - { tier: 11_external_services, status: verified, evidence: "OneSignal REST send path is downstream of the auth gate and never reached; nothing to change OneSignal-side" }
  - { tier: 12_client_server_contract, status: verified, evidence: "edge-function logs show only client-invoked log-client-error and daily-snapshot returning 200; every cron-invoked function 401" }
impact_analysis: >-
  All 11 user-facing scheduled notifications are dead: re-engagement,
  streak-guardian, workout-window-closing, expiry-reminder, protein-gap-alert,
  plateau-alert, morning-alert (x3 jobs), weekly-recap-ready, i-see-you-callout
  and pr-detection. Also dead: rolling-context, evaluate-rank-promotions (rank
  progression frozen server-side), clean-orphan-media (orphaned storage never
  reclaimed), promote-community-item, and compute-admin-metrics-daily (the
  founder dashboard reads stale numbers — admin_metrics_daily has 0 rows
  despite 13 dispatches). The proactive-coach-promotion trigger on
  rank_promotions is dead by the same cause though it is not a cron job.
  compute-coach-signals is the sole survivor and only because it has no auth
  gate, so dropout_risk_score and plateau_risk_score are in fact CURRENT.
  Revenue-adjacent: expiry-reminder has not warned a single expiring PRO user,
  so silent lapses are unmitigated. Detection was structurally impossible
  because logCronStart runs after the auth gate, pg_cron reports success for
  any dispatched net.http_post, and alert_edge_function_health reads from the
  cron_call_log table that the failure prevents being written.
  Security finding surfaced while fixing this: compute-coach-signals is
  verify_jwt=true with no module gate, so ANY holder of the anon key — which
  ships in every APK and web bundle — can invoke it and drive up to 5000 RPC
  round-trips. Closed by adding the gate as part of this batch.
---

# Cron auth gate depends on an environment variable Supabase forbids creating

## What broke

`supabase/functions/_shared/cron_auth.ts` authorises a cron call two ways: an
opaque `CRON_SECRET` string match (line 91), or JWT signature verification
against `SUPABASE_JWT_SECRET` (line 97). Only the second was ever wired up.

`SUPABASE_JWT_SECRET` is not injected by Supabase, and **cannot be created** —
the platform reserves the `SUPABASE_` prefix for secret names. The gate
therefore returns `false` at line 98-101 on every single request, forever.

This is not a misconfiguration. It is unsatisfiable by construction.

## Why the two previous fixes missed it

Both prior instances were diagnosed as *credential drift* and fixed by
re-pasting the service_role key into Vault. That diagnosis was correct for the
2026-05-12 instance and for 5a65bd. It is wrong here: the Vault token was
decoded live during this investigation and is entirely valid — HS256,
`role: service_role`, `ref: dedsavbjuwgarrhphgnl`, expiring 2036.

The token was never the problem. The verifier was.

## The compounding failure

The 5a65bd write-up proposed, as its permanent class fix, *"replace the brittle
env-equality check in `_shared/cron_auth.ts` with a JWT signature+role decode."*
That change was authored, carried a `DO NOT DEPLOY in this batch` header note,
and was deployed later without anyone verifying the new dependency existed.

A fix intended to end a recurring bug made it permanent instead.

## Why nobody noticed for weeks

Three safeguards existed. All three were defeated by the same call-ordering
mistake:

1. `logCronStart` runs *after* the auth gate, so a 401 leaves no telemetry row.
   `cron_call_log` holds 6 rows across its entire history, the last from
   2026-05-30.
2. pg_cron marks a job `succeeded` once `net.http_post()` is dispatched,
   regardless of the HTTP status that comes back.
3. `alert_edge_function_health` (jobid 27, every 15 min) computes its error rate
   *from `cron_call_log`* — the table the failure prevents from being written.
   Its `WHERE total >= 5` guard never matches an empty set, so it has never
   fired once.

The alarm was wired to a sensor the fire cuts power to.

## The fix

Migration 107 switches every HTTP-dispatching cron job to the `CRON_SECRET`
branch, which already ships in every deployed function — so no Edge Function
redeploy is needed. A plain string comparison is also immune to the JWT signing
key migration now in progress on this project and to the pending deprecation of
`SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`.

Migration 107 fails closed twice: the accessor itself raises if the Vault secret
is missing or empty, and the job loop aborts unless it accounts for exactly the
16 `verify_jwt=false` jobs measured at authoring time.

It also fixes a job that has never worked at all — `promote_community_item_daily`
reads `current_setting('app.settings.service_role_key', true)`, which returns
NULL on this project. Since `'Bearer ' || NULL` evaluates to NULL in Postgres,
that job has been sending a **null** Authorization header since the day it was
created, not an empty `Bearer `.

## What review round 1 caught, and why it mattered

The first draft of this migration repointed all 18 HTTP cron jobs uniformly. It
would have **broken the only cron job that currently works.**

`verify_jwt` is not uniform across the fleet. Where it is true, the Supabase
gateway validates the bearer as a project-signed JWT *before the module loads* —
so an opaque `CRON_SECRET` dies at the gateway and the module never runs. Two
cron-targeted functions are `verify_jwt: true`:

- **`compute-coach-signals`** — no module gate at all, so the service_role JWT
  clears the gateway and the function simply runs. Verified working:
  `signals_computed_at` max is five seconds after its last dispatch. A uniform
  repoint would have killed it.
- **`compute-admin-metrics-daily`** — has the module gate, so it 401s today and
  would have gone on 401ing after a repoint, at the gateway instead of the
  module. Zero rows despite 13 dispatches.

Worse, the original `n <> 18` guard would have reported complete success on a
fleet where 16 were fixed, one regressed and one was untouched.

Both are now handled by migration 108, which applies only after their gateway
flags are flipped — and, for `compute-coach-signals`, after it is given the auth
gate it has never had.

The same review found the `proactive-coach-promotion` **trigger** function,
which calls the same Vault accessor but is not a `cron.job` row, so the original
loop could never have seen it. It is now repointed in 107 section 5.

## Restoring visibility — and the fix that was rejected

Restoring auth without restoring *visibility* would leave the next instance
just as invisible. The obvious move is to run `logCronStart` **before** the auth
gate so a 401 leaves a row. **That was considered and deliberately rejected.**

16 of the 18 cron functions are `verify_jwt=false`, so their URLs accept
unauthenticated POSTs from anywhere and the module gate is the only check.
Logging before that gate would hand every anonymous caller on the internet an
unauthenticated INSERT into `public.cron_call_log` — a storage and cost
amplification vector on 16 public endpoints. It would trade an observability
gap for a real vulnerability.

Migration 109 uses an **absence** signal instead — `alert_cron_silence` fires
when no cron execution has succeeded in 2+ hours. It needs no reorder, adds no
attack surface, and detects the outcome rather than one particular cause (so it
also catches dispatch failures, boot failures and pg_cron itself stopping). It
would have fired on day one of this incident.

That also explains why the existing `alert_edge_function_health` never fired
once: it computes an error *rate* from `cron_call_log`, and a 401 writes no row,
so its `WHERE total >= 5` guard never matched. The alarm was wired to a sensor
the fire cuts power to.

Because nothing in SQL can prove the Vault value matches the Edge Function
value, a **positive post-apply smoke is a required step, not an optional one**:
POST one `verify_jwt=false` cron function with the secret and confirm a 200. A
mismatch would otherwise reproduce this exact silent outage.
