---
bug_id: a7d2e9
date: 2026-07-26
batch: notif-prefs-unit-b
status: fixed
blast_radius: account
symptom: >-
  morning-alert sends Gemini-generated PRO-tier copy to users whose
  subscription lapsed. Live at discovery: zero users were genuinely PRO, yet
  six were being treated as PRO and receiving paid-tier content.
concept: subscription_state
recurrence: >-
  Same class as the documented "subscriptions.status is not PRO" scar, but a
  degree worse — this reads users.subscription_status, a denormalized column
  with NO expiry term at all, rather than the status-only form.
related_bugs: none
sot_registry_entry: subscription_state
writers:
  - { file: supabase/functions/_shared/subscription.ts, method: fetchProUserIds, line: 55 }
  - { file: supabase/functions/_shared/subscription.ts, method: isProUser, line: 102 }
readers:
  - { file: supabase/functions/morning-alert/index.ts, method_or_widget: generateAndStoreAlert, line: 374 }
hive_key_prefix: n/a — server-side tier decision, no Hive participation
hive_key_formula: n/a — server-side tier decision, no Hive participation
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [user_id, status, end_date]
contract_test_path: test/contracts/pro_predicate_adoption_test.dart
ist_handling:
  - { file: supabase/functions/_shared/subscription.ts, line: 63, fn: uses_absolute_utc_instant_not_a_date_key }
provider_invalidations: []
telemetry_op_types:
  success: [morning_alert_generate_batch_done]
  failure: [subscription_fetch_pro_ids_failed]
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "users.subscription_status read for a tier decision", absent_after_fix: true }
  - { pattern: "status='active' without an end_date term", absent_after_fix: true }
proposed_fix: >-
  Add supabase/functions/_shared/subscription.ts as the single definition of
  PRO — status='active' AND end_date > now() — exposing fetchProUserIds for
  batch callers and isProUser for single-user callers. Adopt it in
  morning-alert, fetching the set once per run rather than per user, since that
  function paginates. Remove subscription_status from its working-set select and
  from the ActiveUser interface. Correct the file header, which claimed a
  subscriptions gate the code never had.
regression_test_planned:
  - test/contracts/pro_predicate_adoption_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "server-side tier decision; no Dart changed" }
  - { tier: 2_hive, status: not_applicable, evidence: "no local state participates" }
  - { tier: 3_postgres_schema, status: verified, evidence: "no schema change; subscriptions.status + end_date already exist and are read-only here" }
  - { tier: 4_postgres_data, status: verified, evidence: "9 subscription rows, 5 status='active', 0 unexpired; newest active end_date 2026-07-13; users.subscription_status='pro' = 6, all 6 lapsed" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration in this fix" }
  - { tier: 6_edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "DEPLOYED 2026-07-27 v27->v28 (verify_jwt=false preserved). Verified in the deployed bytes with comments stripped: fetchProUserIds x8, proUserIds.has x1, `isPro = user.subscription_status` x0, the subscription_status select x0, .eq(status,active) x2 + .gt(end_date) x2. Cron tick 23:45:02Z ran v28 -> cron_call_log success, HTTP 200, 3972ms." }
  - { tier: 7_cron_jobs, status: verified, evidence: "morning_alert_generate (jobid 5) and the two delivery jobs unchanged; they invoke the same slug" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "service-role read, no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects touched" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret added or read" }
  - { tier: 11_external_services, status: verified, evidence: "Gemini spend is the thing being reduced; OneSignal delivery path unchanged" }
  - { tier: 12_client_server_contract, status: verified, evidence: "no client contract; the removed column was read server-side only" }
impact_analysis: >-
  Six users with a lapsed subscription were classified PRO and took the
  Gemini-generated branch of the daily morning alert instead of the free
  template. Two costs. First, direct spend: a paid LLM call per user per day for
  people who had stopped paying. Second, and worse for the business, the churn
  signal was destroyed — a lapsed user who keeps receiving the premium
  experience has no reason to notice they lapsed and no prompt to resubscribe,
  while the operator sees no drop in engagement to investigate. The blast radius
  is bounded to notification copy: no payment, entitlement or data-access
  decision reads this column, so no user gained access to a PRO feature. The
  fix is fail-safe in the other direction — if the subscriptions query errors,
  fetchProUserIds returns an empty set and every user gets the free template,
  which spends nothing and denies nobody anything they paid for.
---

# morning-alert decided PRO from a column that never expires

## What was wrong

`morning-alert/index.ts` classified users with:

```ts
const isPro = user.subscription_status === "pro";
```

`users.subscription_status` is a denormalized cache. It has **no expiry
component**, and — verified by grep across the repo — **three code paths set it
to `'pro'` and none ever set it back to `'free'`**: the
`update_user_subscription_status` trigger (migration 010, hardened in 094),
`razorpay-webhook`, and `verify-payment`.

So once a user has ever paid, that column says `pro` forever.

## Why it went unnoticed

The function's own header claimed the opposite:

```
 *   - subscriptions.status = 'active' (PRO gating)
```

Anyone auditing tier behaviour by reading the header would have concluded it was
correctly gated. The header has been corrected in the same commit, with the
history noted inline so the next reader sees why it says what it says.

## Live state at discovery

| Measure | Value |
|---|---|
| Subscription rows | 9 |
| `status = 'active'` | 5 |
| **Genuinely PRO** (`active` AND `end_date > now()`) | **0** |
| Newest `active` row's end_date | **2026-07-13** (13 days prior) |
| `users.subscription_status = 'pro'` | **6 — all lapsed** |

Note the column claimed **more** PRO users than even a status-only check would
have (6 vs 4): two users carry `subscription_status='pro'` with no
`status='active'` subscription row at all. The cache has drifted beyond its own
source.

## The fix

`_shared/subscription.ts` becomes the single definition of PRO. Both terms are
mandatory and the file documents why at length, because the failure mode is
silent and the correct predicate is not self-evident.

`morning-alert` fetches the PRO set **once per run** rather than per user. That
function paginates its working set, so a per-user check would have been one
query per user per night — the reason the helper exposes a set-fetch at all, not
just a single-user predicate.

## Why a shared helper rather than a local fix

Five distinct hand-rolled PRO predicates existed across the Edge Functions with
no shared definition. Fixing only this call site would have left the class
intact. `test/contracts/pro_predicate_adoption_test.dart` now fails the build if
any Edge Function reads `users.subscription_status` to make a tier decision —
while still permitting the writes, since the column remains a legitimate cache
for the admin dashboard.

Six further hand-rolled predicates remain (`ai-proxy`, `clean-orphan-media`,
`ai-media-proxy`, `future-prediction`, `weekly-report`, `verify-subscription`).
All were checked and all use a correct predicate; migrating them onto the shared
helper is scoped as its own unit rather than widened into this one.

## Verification

`flutter test test/contracts/pro_predicate_adoption_test.dart` — 4 assertions,
including a positive control proving the detector flags the exact pre-fix line,
so the absence assertions cannot pass vacuously.

## Deploy (2026-07-27)

`morning-alert` **v27 → v28**, `verify_jwt=false` preserved. Verified three ways
rather than by version number alone:

1. **Deployed bytes**, comments stripped — `fetchProUserIds` ×8,
   `proUserIds.has` ×1, `isPro = user.subscription_status` ×**0**, the
   `subscription_status` select ×**0**, `.eq("status","active")` ×2 and
   `.gt("end_date")` ×2. The redeploy also removed `jwtVerify` /
   `SUPABASE_JWT_SECRET` and with them a live `deno.land/x/jose` remote import.
2. **Boot** — the post-deploy smoke returned the module's own 401
   (`verify_jwt=false`, so the request reaches the module; the 401 is the cron
   gate, not the gateway).
3. **End-to-end** — the 23:45:02Z cron tick, after the 23:32:19Z deploy, logged
   `cron_call_log` success / HTTP 200 / 3972 ms on version 28.

### Correction to this batch's own record

The batch notes claimed the cron auth fix was "not live pending redeploy". That
was **wrong**, and it is recorded here because it nearly caused 18 needless
production deploys. The **deployed** `_shared/cron_auth.ts` checks a legacy
`CRON_SECRET` opaque-token hatch *before* the unreachable `SUPABASE_JWT_SECRET`
path — so migrations 107-110 plus the dashboard secret restored cron auth with
no deploy at all. `cron_call_log` showed 15 functions succeeding on 2026-07-26.

The trap: the obvious probe (`list_edge_functions` version + `updated_at`) would
have *confirmed* the error — `morning-alert` genuinely sat at v27 since May. Old
code can be working through a path you forgot about. **Ask what artifact success
would produce and look for THAT** — here `cron_call_log`, which is only written
after the auth gate passes. Ref `memory/feedback_mistake_unverified_done_claims.md` §8b.

Only the PRO fix in this doc actually required the deploy.
