---
bug_id: 5a65bd
date: 2026-05-15
batch: APK Test #16 audit A4
status: in-progress
symptom: pr-detection Edge Function cron returns 401 every 15 minutes; same shape affects 6 other C-4-gated proactive trigger functions (re-engagement, plateau-alert, protein-gap-alert, workout-window-closing, evaluate-rank-promotions, streak-guardian, i-see-you-callout, clean-orphan-media — every function with verify_jwt=false that imports the C-4 in-function cron-auth-gate).
concept: cron_auth
sot_registry_entry: null
writers:
  - { file: supabase/functions/pr-detection/index.ts, method_or_widget: cron-auth-gate, line: 44 }
  - { file: supabase/functions/re-engagement/index.ts, method_or_widget: cron-auth-gate, line: 72 }
  - { file: supabase/functions/streak-guardian/index.ts, method_or_widget: cron-auth-gate, line: 44 }
  - { file: supabase/migrations/061_cron_vault_key_retrofit.sql, method_or_widget: morning_alert_get_service_key, line: 1 }
readers:
  - { file: supabase/migrations/<061-derived cron jobs>, method_or_widget: pg_cron Authorization header, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: "n/a — operational/config drift, not field-rename class"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["cron-auth-gate.unauthorized"]
cross_account_guard: n/a
forbidden_patterns_checked:
  - "hardcoded service-role JWT in cron.job.command (none found; all migrated to Vault per P1-D)"
proposed_fix: |
  Two-prong fix.

  1. **Operational (main thread + founder):** Refresh the Vault row
     `service_role_key` so its value equals the project's
     CURRENT env-injected `SUPABASE_SERVICE_ROLE_KEY`. Audit 2026-05-12
     P0 closed a NULL-Vault → "Bearer null" failure mode by populating
     the row; but somewhere between 2026-05-11 (audit C-4 deploy) and
     2026-05-15, the Edge Function project-level service-role JWT was
     rotated by Supabase OR the Vault value was overwritten with a
     different JWT, so the two no longer agree. Test: when the cron
     job dispatches `Bearer ` || `private.morning_alert_get_service_key()`
     against `pr-detection`, the in-function gate compares
     `token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` and the
     equality fails → 401 `{"error":"Unauthorized"}` from line 56 of
     pr-detection/index.ts. Same body confirmed via manual
     `net.http_post` test 2026-05-15.

  2. **Code (separate batch, deferred per founder direction — out of A4
     scope):** Replace the equality check with JWT signature + role
     claim decode in a new `_shared/cron_auth.ts` helper. Any service-role-
     signed JWT (regardless of rotation) would then pass. This is the
     class fix that eliminates Vault drift as a class of bug.

  Migration `065_fix_pr_detection_cron_auth.sql`: Audits the 9 affected
  cron jobs (every job whose Authorization Bearer is
  `private.morning_alert_get_service_key()`) and PROVIDES THE OPERATIONAL
  steps + verification SQL. It does NOT rewrite the cron.job entries —
  they are already structurally correct. The fix is in Supabase Dashboard
  Vault, not in Postgres cron schedules.

regression_test_planned:
  - "Post-fix: invoke pr-detection manually via `net.http_post(...)` with `Bearer ' || private.morning_alert_get_service_key()` from SQL editor and confirm 200."
  - "Post-fix: query Edge Function logs for last 30 min; pr-detection should show 200 not 401."
  - "Per CLAUDE.md §22 + memory feedback_audit_findings_require_live_verification.md: cite the live SQL verification command in this doc body."
---
# Body

## Diagnosis trail

1. `cron.job` for `proactive_pr_detection` (jobid 9) — schedule `*/15 * * * *`,
   command uses `private.morning_alert_get_service_key()` correctly (not
   a hardcoded JWT). Pattern matches every other C-4 retrofit job.
2. `private.morning_alert_get_service_key()` returns a 219-char string
   prefixed `eyJhbGciOi` — a real JWT (Vault row IS populated;
   2026-05-12 P0 NULL-Vault gap is NOT in play).
3. `cron.job_run_details` reports `succeeded`/`1 row` for every
   pr-detection run — but `pg_cron` reports succeeded for any
   `net.http_post` dispatch regardless of HTTP response (documented
   gotcha in CLAUDE.md M2 follow-up). Symptom invisible from
   `cron.job_run_details`.
4. Edge Function logs (last 24h) — `pr-detection` returns 401 on every
   single invocation; execution_time ~325–371 ms.
5. Inspected deployed pr-detection v3 source via MCP get_edge_function:
   in-function `cron-auth-gate` (lines 44–60) compares
   `token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` and rejects
   mismatches with the exact body `{"error":"Unauthorized"}`.
6. Manual `net.http_post` test 2026-05-15:
   ```sql
   SELECT net.http_post(
     url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/pr-detection',
     headers := jsonb_build_object(
       'Content-Type', 'application/json',
       'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
     ),
     body := '{}'::jsonb
   );
   -- response: status_code=401, body={"error":"Unauthorized"}
   ```
   Same body confirms it's the in-function gate firing, not Supabase gateway.
7. Same test against `streak-guardian` (same gate code, same Vault key,
   `verify_jwt: false`): also returns 401. Both functions therefore
   share the same auth drift, but `streak-guardian` runs only daily at
   14:30 UTC so the 401 only fires once/day (less visible in 24h log
   sample); `pr-detection` runs every 15 min so it dominates the log.
8. Functions with `verify_jwt: true` (morning-alert, daily-snapshot,
   compute-coach-signals, rolling-context, promote-community-item) all
   succeed because the gateway accepts ANY valid JWT (including the
   Vault-stored one) and the function code itself doesn't compare
   tokens. Only the 7 `verify_jwt: false` C-4-gated functions are 401ing.

## Root cause

The in-function `cron-auth-gate` from audit 2026-05-11 (closes-diagnose
7ad0c4) compares `token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")`.
For this equality to hold across cron retries, the Vault row
`service_role_key` MUST contain a byte-identical copy of the JWT that
the Supabase Edge Functions runtime injects into the function's env.

Between 2026-05-11 (audit C-4 deploy) and 2026-05-15, those two values
drifted. Most likely culprit: the project's service-role JWT was
rotated platform-side (or someone re-saved the Vault row with a
different copy). Result: every cron-triggered call to a C-4-gated
function fails the equality check → 401.

## Affected functions (verify_jwt=false + C-4 gate)

- `pr-detection`           (every 15 min — most visible)
- `re-engagement`          (daily 06:30 UTC)
- `plateau-alert`          (daily 13:30 UTC)
- `protein-gap-alert`      (daily 14:30 UTC)
- `workout-window-closing` (daily 15:30 UTC)
- `streak-guardian`        (daily 14:30 UTC)
- `evaluate-rank-promotions` (daily 18:30 UTC)
- `i-see-you-callout`      (daily 14:00 UTC)
- `clean-orphan-media`     (daily 03:00 UTC)
- `expiry-reminder`        (daily 09:00 UTC)
- `weekly-recap-ready`     (Sunday 14:30 UTC)

## Fix (operational — main thread executes)

1. Dashboard → Settings → API → copy the current `service_role` JWT.
2. Dashboard → Settings → Vault → edit the row named `service_role_key`
   → paste the JWT from step 1 → save.
3. Verify via SQL editor:
   ```sql
   SELECT private.morning_alert_get_service_key() = current_setting('request.jwt.claim.role', true)
   -- not directly testable; use the http_post test instead
   SELECT net.http_post(
     url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/pr-detection',
     headers := jsonb_build_object(
       'Content-Type', 'application/json',
       'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
     ),
     body := '{}'::jsonb
   ) AS req_id;
   -- then within ~1s:
   SELECT status_code, content::text FROM net._http_response WHERE id = <req_id>;
   -- expect status_code = 200 with a JSON body like {"checked":0,"sent":0} or {"pr_rows":N,...}
   ```
4. Monitor Edge Function logs for the next 30 minutes — pr-detection
   should flip from 401 to 200 within one cron tick (15 min).

## Why no schema/cron migration

The cron.job entries are already structurally correct (Vault-backed
Bearer pattern from audit P1-D / migration 061). Re-scheduling them
won't change the body of `private.morning_alert_get_service_key()`.
The fix is in Vault, not in `cron.job`. Migration
`065_fix_pr_detection_cron_auth.sql` exists as a NO-OP placeholder
that documents the operational steps + provides a verification query
runnable from `mcp__execute_sql`.

## Other cron jobs audited (no 401 risk)

- jobid 7 `promote_community_item_daily` uses
  `current_setting('app.settings.service_role_key', true)` which
  returns NULL on this project (verified via
  `SELECT current_setting(..., true)` → empty string). That job has
  been silently sending `Bearer ` (with nothing after) since deploy →
  guaranteed 401, but its function has `verify_jwt: true` and rejects
  at the gateway anyway. **Separate bug**, out of A4 scope; flagged
  for follow-up.

- All other jobs (5, 8, 10–22) use the same
  `private.morning_alert_get_service_key()` pattern → same drift root
  cause, fixed by the same Vault refresh.
