# Live DB, Schema Drift, Edge Function, Sync, and Telemetry Audit - 2026-05-12

> Handoff report for a fresh Claude Code agent. Audit only. No fixes, deploys,
> migrations, commits, pushes, or APK builds were performed in this pass.

## Scope

Requested audit areas:

1. Live DB audit.
2. Schema drift.
3. Edge Function execution audit.
4. Sync completeness audit with live data.
5. Analytics / telemetry audit.

Production project verified by read-only Management API:

- Project ref: `dedsavbjuwgarrhphgnl`
- Project name: `Avya Project`
- Region: `ap-southeast-1`
- Status: `ACTIVE_HEALTHY`
- DB user for SQL endpoint: `postgres`
- PostgreSQL: `17.6`
- Evidence timestamp: 2026-05-12 08:03-08:20 UTC

Access path used:

- Token source: `supabase/.supabase/supabase access token.txt` (not printed)
- API path: `https://api.supabase.com/v1/projects/dedsavbjuwgarrhphgnl/...`
- SQL path: Management API `/database/query`
- All SQL was `SELECT` only.

## Executive Summary

Verdict: request changes before wider beta.

The production database is reachable, active, and has the expected high-level
shape: 46 public base tables, 1 public view, all public tables have RLS enabled,
and migrations through `060_workout_log_exercises_realistic_bounds` are applied.
However, live data and telemetry show current production failures:

- Sync is actively failing on natural-key unique constraints for both exercise
  logs and nutrition logs.
- Cron-driven Edge Function execution is returning repeated 401s in `pg_net`.
- Two deployed cloud Edge Functions do not exist in local source.
- `workout_log_sets` accepts the same bad values that migration 060 blocked only
  on `workout_log_exercises`.
- `docs/sot_registry.yaml` contains multiple cloud-column claims that do not
  match live schema.

## Critical Findings

### C1. Live sync is actively failing on unique constraints

Severity: Critical

Production telemetry in the last 24h shows repeated sync failures:

- `upsert_exercise_log`: 31 rows
- `sync_service_catch_5`: 16 rows
- `upsert_nutrition_log`: 16 rows
- `sync_service_catch_6`: 8 rows

Representative live errors:

```text
PostgrestException(message: duplicate key value violates unique constraint
"uniq_workout_log_exercises_wlog_ex_set", code: 23505)

PostgrestException(message: duplicate key value violates unique constraint
"uniq_nutrition_logs_user_date_meal", code: 23505)
```

Code path:

- `lib/core/services/sync_service.dart`
- `_syncExerciseLogs` upserts `workout_log_exercises` with `onConflict: 'id'`
- `_syncNutritionLogs` upserts `nutrition_logs` with `onConflict: 'id'`

Live schema has natural unique indexes:

- `uniq_workout_log_exercises_wlog_ex_set` on `(workout_log_id, exercise_id, set_number)`
- `uniq_nutrition_logs_user_date_meal` on `(user_id, date, meal_type)`

Root-cause hypothesis to verify before fixing:

The client replays or rewrites the same natural event with a different
deterministic `id`, so PostgREST receives `ON CONFLICT (id)` while the actual
conflict is on the natural unique index. PostgreSQL raises 23505 instead of
merging.

Why this matters:

Cloud backup is not production reliable if background replay can repeatedly fail
on existing user data. This directly affects restore, AI context, reports, and
cross-device continuity.

Recommended next-agent investigation:

1. Reproduce locally with one existing natural-key duplicate for nutrition and
   exercise logs.
2. Decide whether the intended conflict target is `id` or the natural key.
3. Update the sync contract and regression tests before changing code.
4. Preserve Hive-first behavior and avoid deleting production rows as a first
   response.

### C2. Cron Edge Function execution is failing with repeated 401s

Severity: Critical

Live `net._http_response` for the last 24h:

```text
status_code=401 count=44
first_seen=2026-05-12 02:30:00+00
last_seen=2026-05-12 08:15:00+00
content examples:
  {"error":"Unauthorized"}
  {"code":"UNAUTHORIZED_NO_AUTH_HEADER","message":"Missing authorization header"}
```

The failures recur every 15 minutes, matching one or more cron schedules.

Relevant active cron jobs:

- `proactive_pr_detection`: `*/15 * * * *`
- `morning_alert_deliver_late`: `*/15 22-23 * * *`
- `morning_alert_deliver_early`: `*/15 0-6 * * *`
- other proactive jobs call Edge Functions with `Authorization: Bearer ...`

Risk:

Proactive features may be non-functional in production while the app still looks
healthy. Client telemetry does not capture these server cron failures.

Important nuance:

Some older cron commands still embed the anon key as `apikey` only
(`rolling-context-nightly`, `streak-guardian-daily`). Others use
`private.morning_alert_get_service_key()`. Do not assume one fix covers all 401s.

Recommended next-agent investigation:

1. Map each `net._http_response.id` back to cron request if possible, or run
   one safe dry invocation per suspect cron endpoint with the same headers.
2. Verify `private.morning_alert_get_service_key()` returns a non-empty current
   service key.
3. Verify whether affected functions are configured `verify_jwt=true` and
   whether code also manually requires `Authorization`.
4. Add server-side cron execution telemetry; `client_errors` is not enough.

### C3. Two deployed Edge Functions are not present in local source

Severity: Critical

Management API reports 36 active functions. Local source has 34 function
directories. Cloud-only functions:

```text
admin-verify-payment v7 jwt=true status=ACTIVE
admin-wipe-storage v7 jwt=true status=ACTIVE
```

Risk:

Production contains executable code that cannot be reviewed, diffed, tested, or
reproduced from this repo. One name is storage-destructive by design. Even with
JWT enabled, this violates source-of-truth and incident-response requirements.

Recommended next-agent investigation:

1. Fetch cloud source via Management API body endpoint or Supabase Dashboard.
2. Classify each as retired stub, admin-only tool, or unsafe leftover.
3. Either add source to `supabase/functions/` with tests or formally decommission
   after explicit user approval.
4. Do not invoke `admin-wipe-storage`.

### C4. `workout_log_sets` is missing the realistic bounds guard applied to `workout_log_exercises`

Severity: Critical

Migration 060 added checks only to `workout_log_exercises`:

```text
wle_reps_realistic: reps IS NULL OR reps BETWEEN 0 AND 60
wle_set_number_realistic: set_number IS NULL OR set_number BETWEEN 0 AND 10
```

Live `workout_log_sets` has no equivalent checks. Live bad rows still exist:

```text
wls_reps_out_of_bounds: 7
wls_set_number_out_of_bounds: 15
```

Examples:

- `Jump Rope`, reps `540`
- `Leg Press`, set_number `15`
- `Leg Curl (Lying)`, set_number `11-15`

Risk:

The app now has two per-set cloud tables with different integrity guarantees.
AI analytics or restore paths that use `workout_log_sets` can still ingest
impossible values.

Recommended next-agent investigation:

1. Confirm whether high-rep cardio/bodyweight entries should live as reps,
   duration, or a separate logging type.
2. Decide whether `workout_log_sets` needs the same checks, a logging-type-aware
   check, or data normalization before constraints.
3. Add a contract test covering both tables, not only `workout_log_exercises`.

## High Findings

### H1. `user_preferences` is missing for one active onboarded user

Severity: High

Live identity completeness:

```text
users_total: 2
onboarded: 2
profiles: 2
progress_rows: 2
preference_rows: 1
active_users_missing_preferences: 1
```

Affected active user:

```text
sumitt@gmail.com
created_at=2026-05-12 06:58:48+00
last_active_at=2026-05-12 12:29:16+00
```

Code path:

- `_syncUserPreferences` returns early when `userBox['preferences']` is null.
- Restore also returns if cloud has no row.

Risk:

AI personalization and coaching style can silently fall back for a real active
user. If preferences are optional, docs/tests should say so. If not, onboarding
or auth bootstrap must create defaults.

### H2. One nutrition parent row has no item rows

Severity: High

Live check:

```text
nutrition_logs_without_items: 1
```

Example:

```text
id=f2c6754e-258c-5824-a122-58c529639896
date=2026-05-03
meal_type=snacks
total_calories=78
```

Risk:

Restore reads `nutrition_logs` joined with `nutrition_log_items`. Parent-only
rows restore without food item detail, so AI and weekly reports can see calories
without the actual food source.

### H3. `docs/sot_registry.yaml` has schema claims that do not exist live

Severity: High

Selected SOT registry column claims checked against live schema:

```text
ai_coach_interactions.assistant_response: missing
nutrition_logs.logged_at: missing
nutrition_logs.source: missing
saved_diet_plans.updated_at: missing
sleep_logs.sleep_hours: missing
user_daily_snapshots.token_count: missing
water_logs.logged_at: missing
weight_logs.logged_at: missing
workout_log_exercises.volume_kg: missing
```

Some of these may be docs-only drift rather than runtime breakage, but
`docs/sot_registry.yaml` is used as a source-of-truth artifact and should not
claim columns that do not exist.

Risk:

Future agents will implement against incorrect schema assumptions and create
new production drift.

### H4. Migration reconciliation doc is stale after migration 060

Severity: High

Live migration summary:

```text
migration_rows: 55
last_version: 20260511132538
last_name: 060_workout_log_exercises_realistic_bounds
```

Local `backups/applied_migrations.json` includes `060`.

But `supabase/migrations/README_RECONCILIATION_2026-05-11.md` says:

```text
Prod migration count: 53 rows
Recent additions: 052 through 058
```

Risk:

The reconciliation doc is no longer current for production. A future agent may
misdiagnose migration drift or re-apply already-applied work.

### H5. `account_deletion_log` has RLS enabled with zero policies

Severity: High, likely intentional but must be documented

Live RLS exception list:

```text
account_deletion_log rls_enabled=true policy_count=0
```

This may be correct for a server-only audit table. However, because it is the
only public table with zero policies, document the intended write/read path and
add a guard test or comment.

## Medium Findings

### M1. Deprecated `ai-proxy-pro` is still active and `verify_jwt=false`

Severity: Medium

Cloud:

```text
ai-proxy-pro v17 jwt=false status=ACTIVE
```

Local source confirms it is a 410 Gone stub. This is probably intentional for
old clients, but keep it in the retired-function inventory and verify it never
performs work.

### M2. Telemetry taxonomy is still noisy

Severity: Medium

Live `client_errors` quality:

```text
total rows: 381
last_24h: 90
missing_op_type: 0
generic_error_code_count: 170
distinct_op_types: 46
distinct_error_codes: 5
```

The table now receives data, which is a major improvement over earlier
blackouts, but `error_code` remains broad (`PostgrestException`,
`FunctionException`, `event`). The useful root cause is buried in
`error_message`.

Recommended next-agent investigation:

- Normalize server/client telemetry into stable codes such as
  `db_unique_violation_nutrition_log`, `db_unique_violation_exercise_log`,
  `edge_boot_error_daily_snapshot`, `cron_auth_401`.

### M3. Snapshot coverage exists but is thin for one new active user

Severity: Medium

Active users in last 14 days:

```text
sumitt@gmail.com: latest_snapshot_at=2026-05-12 06:59:22+00, snapshot_count=1
upendraprasad19@gmail.com: latest_snapshot_at=2026-05-12 05:11:05+00, snapshot_count=12
```

This is not automatically a bug because the first user is new, but the missing
`user_preferences` row plus only one snapshot means restore/AI coverage should
be rechecked after the user's next app launch and mutation cycle.

## Live DB Inventory

Schema inventory:

```text
auth BASE TABLE: 23
public BASE TABLE: 46
public VIEW: 1
storage BASE TABLE: 8
```

Public view:

```text
coach_tool_invocations_v
```

RLS:

```text
All public base tables have RLS enabled.
Only account_deletion_log has zero policies.
```

Security definer functions:

```text
private.compute_coach_signals_function_url
private.morning_alert_function_url
private.morning_alert_get_service_key
public.active_users_for_signals
public.auto_approve_community_item
public.compute_coach_signals_for_user
public.extend_subscription
public.handle_new_auth_user
public.increment_promo_used_count
public.redeem_referral_atomic
public.rls_auto_enable
public.update_streak_progress
public.update_user_subscription_status
```

Extensions:

```text
pg_cron 1.6.4
pg_net 0.20.0
pg_stat_statements 1.11
pgcrypto 1.3
plpgsql 1.0
supabase_vault 0.3.1
uuid-ossp 1.1
vector 0.8.0
```

Core row counts:

```text
users: 2
user_profile: 2
user_progress: 2
user_preferences: 1
workout_logs: 27
workout_log_exercises: 72
workout_log_sets: 221
scheduled_workouts: 56
workout_templates: 3
template_exercises: 14
nutrition_logs: 8
nutrition_log_items: 7
water_logs: 10
user_daily_snapshots: 13
ai_coach_interactions: 114
client_errors: 381
```

Recent activity:

```text
snapshots_last_24h: 3
snapshots_last_7d: 8
users_active_last_7d: 2
workout_logs_last_7d: 14
nutrition_logs_last_7d: 5
client_errors_last_24h: 90
ai_interactions_last_24h: 4
```

## Edge Function Deployment Inventory

Cloud functions not in local source:

```text
admin-verify-payment
admin-wipe-storage
```

Local functions not deployed:

```text
none
```

Cloud summary:

```text
admin-verify-payment v7 jwt=true ACTIVE
admin-wipe-storage v7 jwt=true ACTIVE
ai-media-proxy v16 jwt=true ACTIVE
ai-proxy v64 jwt=false ACTIVE
ai-proxy-pro v17 jwt=false ACTIVE
assess-body-composition v12 jwt=true ACTIVE
beat-my-coach v6 jwt=true ACTIVE
clean-orphan-media v2 jwt=false ACTIVE
compute-coach-signals v6 jwt=true ACTIVE
create-razorpay-order v7 jwt=false ACTIVE
daily-snapshot v19 jwt=true ACTIVE
delete-account v2 jwt=true ACTIVE
evaluate-rank-promotions v3 jwt=false ACTIVE
expiry-reminder v12 jwt=false ACTIVE
future-prediction v12 jwt=true ACTIVE
i-see-you-callout v2 jwt=false ACTIVE
log-client-error v6 jwt=true ACTIVE
morning-alert v23 jwt=true ACTIVE
plateau-alert v3 jwt=false ACTIVE
pr-detection v3 jwt=false ACTIVE
promote-community-item v8 jwt=true ACTIVE
protein-gap-alert v3 jwt=false ACTIVE
razorpay-webhook v17 jwt=false ACTIVE
redeem-referral v10 jwt=true ACTIVE
re-engagement v3 jwt=false ACTIVE
rolling-context v12 jwt=true ACTIVE
streak-guardian v14 jwt=false ACTIVE
validate-promo v12 jwt=true ACTIVE
verify-payment v12 jwt=true ACTIVE
verify-subscription v9 jwt=true ACTIVE
video-render-trigger v10 jwt=true ACTIVE
video-status v11 jwt=false ACTIVE
weekly-recalc v15 jwt=true ACTIVE
weekly-recap-ready v14 jwt=false ACTIVE
weekly-report v20 jwt=true ACTIVE
workout-window-closing v3 jwt=false ACTIVE
```

Do not invoke without explicit approval:

- `delete-account`
- `admin-wipe-storage`
- `admin-verify-payment`
- payment/referral mutation flows
- cron functions that send notifications or mutate user state

## Suggested Fix Order For Future Agent

Do not implement from this audit report blindly. First reproduce and diagnose.

1. C1 sync 23505 failures.
   - This is user-data integrity and restore-critical.
   - Start with tests proving current `onConflict: id` behavior fails against
     natural unique indexes.

2. C2 cron 401 failures.
   - Production server-side automation is failing now.
   - Map exact cron job to 401 response before changing secrets.

3. C3 cloud-only admin functions.
   - Bring deployed code under source control or retire with explicit approval.

4. C4 `workout_log_sets` integrity.
   - Avoid a naive `reps <= 60` if cardio/bodyweight semantics need a different
     representation.

5. H1/H2 live data gaps.
   - Decide whether to backfill after root cause is fixed.

6. H3/H4 docs drift.
   - Update `docs/sot_registry.yaml` and reconciliation docs after code/schema
     decisions are finalized.

## Commands Used

Representative read-only commands:

```powershell
$token = (Get-Content -Raw -Path 'supabase\.supabase\supabase access token.txt').Trim()
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
Invoke-RestMethod -Method Get `
  -Uri 'https://api.supabase.com/v1/projects/dedsavbjuwgarrhphgnl'

Invoke-RestMethod -Method Post `
  -Uri 'https://api.supabase.com/v1/projects/dedsavbjuwgarrhphgnl/database/query' `
  -Headers $headers `
  -Body (@{ query = 'select ...' } | ConvertTo-Json -Compress)
```

No token values, service-role keys, anon JWTs, or user secrets are included in
this report.

