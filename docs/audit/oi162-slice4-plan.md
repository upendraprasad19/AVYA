# OI-162 slice 4 — windowed rate-limit counters onto `usage_counters`

**Branch**: `oi162-slice4-windowed-counters` · **Date**: 2026-09-10
**Blast radius**: **catastrophic** — `blast_radius.yaml:42-43` pins BOTH
`supabase/functions/verify-payment/**` and `supabase/functions/delete-account/**`
catastrophic by path. Requires `hermes: accepted`.
**Status**: hardened after review round 1 (8 findings, 0 false alarms). Round 1
CHANGED THE SCOPE — see the round-1 section.

## Scope

| unit | what | file |
|---|---|---|
| A | `delete_account` 5 / 60 min onto the ledger | `supabase/functions/delete-account/index.ts` |
| B | `verify_payment` 20 / 10 min onto the ledger | `supabase/functions/verify-payment/index.ts` |
| C | REVOKE `consume_quota` EXECUTE from PUBLIC | `supabase/migrations/130_*.sql` (**added by round 1**) |
| D | SoT registry + EF CLAUDE.md contract rows | `docs/sot_registry.yaml`, `supabase/functions/CLAUDE.md` |
| E | land the channel-reader enumeration as a repo artifact | `docs/audit/` |

The free-image LIFETIME quota is NOT in scope — folded into OI-153, because a
lifetime quota must never be pruned while a windowed one must be.

## Ground truth (live, 2026-09-10, re-verified independently in round 1)

- `prompt_snippet` / `response_snippet` **do not exist** on `ai_coach_interactions`
  (12 columns). `user_message` is **NOT NULL, no default**. Instance A's insert
  fails two independent ways — PGRST204 and 23502 — into a `.then()` that only
  `console.warn`s. `attemptCount` is structurally always 0.
- ⚠ **The row count is NOT the evidence for instance A.** `user_id` is
  `ON DELETE CASCADE`, so a successful deletion erases its own attempt rows. The
  SCHEMA is the proof.
- `consume_quota(uuid, text, timestamptz, int) -> int`: returns the new count, or
  **`-1`** as an explicit refusal sentinel; atomic
  `INSERT ... ON CONFLICT DO UPDATE ... WHERE used < p_limit`. A refused call
  touches ZERO rows, so a refusal does not itself consume.
- `usage_counters`: PK `(user_id, quota_key, window_start)`, FK CASCADE,
  **no CHECK/trigger/index/enum constraining `quota_key`**.
- Retention GENERIC and LIVE: `cleanup_usage_counters()` deletes
  `window_start <> 'epoch' AND window_start < now() - interval '7 days'`, via
  **active** cron job 37 (`45 3 * * *`) — the only cron touching the table.
- `service_role` has `rolbypassrls = true`; `anon` / `authenticated` do not.

## Design

Both instances collapse a broken/awkward **count-then-insert** pair into ONE
atomic `consume_quota` call. Refusal is `-1`.

### Window: fixed buckets

`consume_quota`'s PK includes `window_start`, so the ledger is a FIXED bucket, not
the rolling window both limits use today.

⚠ **A fixed bucket permits a 2x burst across a boundary** — 5 at 10:59 and 5 at
11:00. Caps stay unchanged (5, 20). `delete-account`'s primary control is JWT auth
plus a confirmation token containing the caller's own 8-char user-id prefix
(`DELETE-MY-ACCOUNT-${userId.substring(0,8)}`), so its limit is genuinely
secondary; verify-payment's protects Razorpay quota, where a transient 2x is
harmless. Tightening caps would be a product change and is not made here.

Buckets are epoch-floor in **UTC**:

```ts
const bucket = new Date(Math.floor(Date.now() / MS) * MS).toISOString();
```

⚠ §4.5 mandates IST for "date keys + cloud `date` columns + counter resets". Both
endpoints return a **relative** `Retry-After` in seconds and never a date-keyed
reset, so only bucket DURATION is user-visible and UTC epoch-floor is correct.
Stated rather than deviating silently.

**`Retry-After` is computed from the bucket's true remaining time**
(`bucketStart + MS - now`, floored to at least 1s), NOT the full window length.
Round 1 finding 7: a naive constant over-reports the wait by up to a whole window
for a refusal early in a bucket.

### Unit A — delete-account

Replace the count (`:143-149`) and the fire-and-forget insert (`:172-190`) with one
`consume_quota` call keyed `delete_account`, limit 5, hourly bucket.

- `error` → **fail OPEN** (log + continue), PRESERVING the deliberate decision
  documented at `:151-155`: a DPDP §17 erasure is a legal right and must not be
  blocked by a counter outage. ⚠ Deliberately differs from unit B below; the
  difference is the point and both are now explicit.
- `-1` → 429 `rate_limited` + `Retry-After`.
- else proceed.

Removes the `delete_account_attempt` channel — its only reader was the count.

### Unit B — verify-payment

Replace the count (`:222-228`) and the un-awaited `.then()` insert (`:248-260`)
with one `consume_quota` call keyed `verify_payment`, limit 20, 10-minute bucket.
Named constants replace inline `20` / `600` / `10 * 60 * 1000`.

⚠ **No cutover backfill, unlike migration 129's pattern** — 129 backfilled
`usage_counters` from the live `ai_coach_interactions` count before swapping each
trigger (`129:38-64`), so a user already mid-window at cutover kept their true
remaining count rather than getting a fresh allowance. `verify_payment` and
`delete_account` introduce no equivalent backfill. This is deliberate, not an
oversight: `verify_payment_attempt` has 0 live rows (see Finding 2 disposition
above — most likely never reached, not provably broken) and `delete_account`'s
counter has NEVER worked (schema-proven), so there is no real prior count to
carry forward for either key. The effect, if any, is strictly LOOSENING for one
cutover window — the opposite direction of a lockout risk — so it's noted rather
than engineered around.

⚠ **Today it fails OPEN BY OMISSION**: `:223` destructures only `count`, never
`error`; on failure `(null ?? 0) >= 20` is false and the request proceeds.
Meanwhile `delete-account:152` documents *"Diff from verify-payment which
fail-closes."* **That comment is factually wrong about its sibling** — both fail
open, only one meant to.

**CHANGED BY ROUND 1: unit B becomes fail-CLOSED.** The original plan kept
fail-open on "blocking a legitimate verification is worse than extra Razorpay
calls". That is wrong on this codebase, because the user-visible cost is *near*
zero:

- PRO is activated **optimistically in Hive immediately** on Razorpay success
  (`razorpay_service.dart:366-378`) — verify-payment is background confirmation.
- The webhook is authoritative and independent.
- The client retries at 60s / 5m / 15m regardless.

Meanwhile fail-open releases the brake exactly when a shared-Postgres hiccup makes
a correlated retry storm most dangerous to the Razorpay quota this limit exists to
protect. A fail-closed 429 costs almost nothing here; a fail-open one costs the only
thing the limit defends. The `delete-account` comment is corrected in the same commit.

⚠ **ROUND 2 (P1) — "zero" was an overclaim; the residual window is named here
rather than asserted away.** `SubscriptionService._paymentGraceWindow` is
**10 minutes** (`subscription_service.dart:162`) while the retry schedule's last
attempt fires at **15 minutes** (`razorpay_service.dart:734-738`) — the grace
window closes 5 minutes BEFORE the final verify-payment retry. A
`verifyFromServer()` landing in that 10-15 min gap with the webhook also delayed
sees `isPaymentInFlight == false` and runs `_downgradeLocally()`
(`subscription_service.dart:1087-1089`) for a user who really paid. This gap is
PRE-EXISTING and not caused by slice 4, but fail-closed removes one of the four
verify-payment attempts precisely during the correlated-outage scenario this plan
invokes to justify the change, and `verify-payment:341-364`'s
authorized-but-not-captured auto-capture step has no equivalent on any other path.
Requires three coincident rare conditions, so it is not a blocker — but the plan
says so instead of claiming zero.

**FILED as OI-182, not fixed here.** Confirmed with the founder 2026-09-11: the
mismatch is a genuinely separate bug (a client-side Dart timing constant,
unrelated to this slice's EF-side rate-limit / ACL work) that pre-dates slice 4 —
bundling it in would widen a catastrophic-tier change's blast radius for no
coupling reason. Per §4.2 this is filing a distinct issue, not re-wrapping this
slice's own scope as deferred.

⚠ Round 1's supporting citation of `SubscriptionService.gate()`'s
`verifyFromServer()` is **withdrawn as a non-sequitur**: it calls
**`verify-subscription`** (`subscription_service.dart:1027`), a DIFFERENT Edge
Function untouched by this slice. Harmless — it means `gate()` really is unaffected
either way — but it was not evidence for what it was cited to support.

### Unit C — migration 130 (ADDED BY ROUND 1)

`consume_quota` is **SECURITY INVOKER** (`prosecdef = false`) with EXECUTE granted
to **PUBLIC** (`=X/postgres`), `anon` and `authenticated`, and it does **no
ownership check on `p_user_id`**. It is un-exploitable today only because
`usage_counters` has RLS enabled with **ZERO policies** and neither role bypasses
RLS — an undocumented invariant.

Slice 4 puts a **DPDP-erasure lockout** and a **payment throttle** behind that
invariant. One future permissive policy on `usage_counters` would let any
authenticated caller run `consume_quota(<victim>, 'delete_account', <bucket>, 5)`
five times and deny a targeted user their erasure right for an hour.

Fixed here rather than filed, per §4.2 — it is two statements and this slice is
what makes it dangerous:

```sql
-- Intent: Remove PUBLIC/anon/authenticated EXECUTE on consume_quota() — it is
--   SECURITY INVOKER with no ownership check on p_user_id, and is un-exploitable
--   today only by the accident of usage_counters having RLS enabled with ZERO
--   policies. OI-162 slice 4 puts a DPDP-erasure lockout and a payment throttle
--   behind that accident, so it is hardened deliberately here.
-- Destructive?: no — revokes a privilege nothing currently depends on.
--   Verified: grep -rn consume_quota lib/ is empty (no client caller); both
--   Edge Functions that call it use a service_role client (unaffected — this
--   revoke targets PUBLIC/anon/authenticated only); the three live cap triggers
--   that call it are only ever invoked via ai-proxy's service_role client, never
--   from an authenticated-role insert (the two channels a client CAN write —
--   'app_event', 'in_app_orphan' — early-return in all three triggers).
-- Rollback strategy: inline — see commented block at end of file.
-- Linked diagnose-doc: f2c8d5
REVOKE EXECUTE ON FUNCTION public.consume_quota(uuid, text, timestamptz, integer)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.consume_quota(uuid, text, timestamptz, integer)
  TO service_role;

-- Rollback (not executed; restores the pre-migration ACL if this must be undone):
-- GRANT EXECUTE ON FUNCTION public.consume_quota(uuid, text, timestamptz, integer)
--   TO PUBLIC;
```

**Diagnose-doc**: this is a `fix:`-shaped batch (repairing two silently-broken
rate limiters), so rule 22 requires one regardless of unit C specifically — round
2 left this undecided; settled here. Single doc covers all three units, id
`f2c8d5`, filed at implementation time as
`docs/diagnoses/2026-09-11-rate-limit-counters-and-quota-acl-gap-f2c8d5.md`. All
three commits (A, B, C) carry `closes-diagnose: f2c8d5` in the body.

⚠ **CORRECTED BY ROUND 2 (P0). `FROM PUBLIC` ALONE IS NOT ENOUGH HERE** — the
opposite of the lesson migration `090`/`091` teaches, and the reason is visible in
the live ACL:
```
{=X/postgres, postgres=X/postgres, anon=X/postgres, authenticated=X/postgres, service_role=X/postgres}
```
`=X/postgres` is PUBLIC, but `anon=X/postgres` and `authenticated=X/postgres` are
**separate DIRECT grants**. `REVOKE ... FROM PUBLIC` removes only the first entry
and leaves both roles' own grants intact, so `has_function_privilege('anon', ...)`
would still be true and the migration would not close the hole it exists to close.
`091` genuinely worked because ITS functions predate the schema-wide
`ALTER DEFAULT PRIVILEGES` and carried only a PUBLIC-sourced grant; `consume_quota`
was created under that default-ACL regime (and migration `128:128-129` also GRANTs
to `authenticated` explicitly), so it has two independent non-PUBLIC sources.
**Read the ACL; do not apply the 091 rule by analogy.**

**Safe — verified on the WIDER input set than round 2 used.** Round 2 checked
Edge-Function writers only. The authenticated-role writers are in the Dart client,
and there are exactly two cloud writes to `ai_coach_interactions`:
`app_events_service.dart:60` (`channel` = the const `'app_event'`) and
`sync_coach.dart:149` (literal `'in_app_orphan'`); `sync_coach.dart:121` and `:178`
are SELECTs and `:205` is a Hive `coachBox.put`, not a cloud write. All three cap
triggers early-return on both values, so `consume_quota` is **never reached from an
authenticated-role insert**. All three triggers are `prosecdef = false` (INVOKER),
but every insert that DOES reach `consume_quota` originates from a service-role
client (`ai-proxy/index.ts:232`). `grep -rn consume_quota lib/` is EMPTY.

⚠ **This re-introduces a live apply.** Slice 4 is no longer EF-only and needs an
`apply_migration` authorization in addition to the two EF deploys.

### Unit D — documentation (three sites named by round 2, not left implicit)

Round 2 found this unit's SCOPE stated but never enumerated — fixed here rather
than left to be discovered later:

1. `docs/architecture/payment.md:38` — Payment Security Rule 6 currently reads
   *"20 calls per user per 10 minutes, counted via `ai_coach_interactions` rows
   with `channel='verify_payment_attempt'`. Over-limit returns 429 with
   `Retry-After: 600`."* All three specifics go stale post-slice: mechanism
   (now `consume_quota` / `usage_counters`), channel name (removed), and
   `Retry-After` (now the bucket's exact remaining time, not a constant 600).
   Rewrite this rule to match. This is the primary doc CLAUDE.md §7 points to
   for "Payment flow + DPDP delete-account" — the exact drift §5's checklist
   row exists to catch.
2. `docs/sot_registry.yaml:4290` — the `coach_interactions` concept's
   description still lists `'verify_payment_attempt'` among live channel
   values for "rate-limit counters also live in `ai_coach_interactions`." This
   line was ALREADY stale since migration 129 moved chat/food/vision off that
   table (2026-09-05) and nobody corrected it; slice 4 retires the fifth name
   too. Drop `'verify_payment_attempt'` from the list and correct the
   surrounding sentence to reflect that rate-limit counters now live in
   `usage_counters`.
3. `coach_interaction_repository.dart:279-281` — a doc-comment (not logic)
   names `verify_payment_attempt` as an example excluded channel; the real
   exclusion is the allowlist at `:282`, so nothing breaks functionally, but
   the comment goes stale. Drop the dead name from the example list.

⚠ **Also noted, not fixed here**: round 2 separately found
`docs/architecture/payment.md:47` (not `:26` as first cited — re-verified by
reading the file) describes the OLD `delete-account` cancel-failure behaviour
("MUST SUCCEED... non-200 → return 502, abort"), contradicting the deliberate
`a2c8e6` fix already live (cancel failure is now non-fatal and recorded
durably). Pre-existing, unrelated to slice 4's scope, and this doc clearly
doesn't get routine maintenance — flagged for the founder rather than filed as
a new OI, since it's a one-line prose correction with no code behind it to
verify against.

## What this does NOT introduce

**No new `channel` value.** Two dead values are REMOVED and none added, so the
board's trap — rolling-context's 4-site `.neq("channel","app_event")` denylist, the
two unfiltered EF readers, and the unfiltered live `get_users_with_message_count()`
and `compute_coach_signals_for_user()` — is out of scope here. Those remain real
and belong to OI-153.

DPDP chain preserved: `usage_counters.user_id -> users(id) CASCADE` and
`users.id -> auth.users(id) CASCADE`.

## Review round 1 — findings and disposition

| # | sev | finding | disposition |
|---|---|---|---|
| 1 | P2 | verify-payment fail-open argued one-sided | **ADOPTED — switched to fail-CLOSED** |
| 2 | P2 | `verify_payment_attempt`'s zero borrowed A's proof | **ADOPTED — see below** |
| 3 | P2 | `consume_quota` INVOKER + PUBLIC EXECUTE, no ownership check | **ADOPTED — unit C added** |
| 4 | P2 | plan omitted SoT registry / EF CLAUDE.md updates (§4.5) | **ADOPTED — unit D** |
| 5 | P2 | plan cited an enumeration artifact absent from the repo | **ADOPTED — unit E** |
| 6 | P3 | line citations off by 1-2 | **ADOPTED — corrected above** |
| 7 | P3 | `Retry-After` over-reports under fixed buckets | **ADOPTED — exact remaining time** |
| 8 | P3 | device/patrol flows not run | **ACCEPTED as residue — see below** |

### Finding 2, resolved with new evidence

Instance A's inertness is schema-proven. Instance B's is NOT, and the plan must not
imply otherwise. New evidence gathered for this round: `ai_coach_interactions`'
oldest row is **2026-05-11** and **17 rows predate the last payment (2026-07-04)**,
so payment-era rows demonstrably survive; `rolling-context` has never swept anyone
(`MESSAGE_THRESHOLD = 50` vs a live max of 25 non-`app_event` rows per user); and
the insert is schema-VALID (all four columns exist, `user_message` supplied).

⇒ **The most consistent explanation is that verify-payment has never been reached
in production, not that its insert fails.** Round 1 also found
`razorpay_signature LIKE 'verified_via_api:%'` = 0 of 9 subscriptions, i.e. its
subscription-creation branch has never won the race against the webhook.
**This cannot be settled from data alone and the plan no longer claims it is.**
Unit B's defects — non-atomic count-then-insert, un-awaited write, fail-open by
omission, magic numbers — are real regardless.

## Tests

1. Source-grep contracts: neither file may reference `prompt_snippet` /
   `response_snippet`; both must call `consume_quota`; neither may retain its
   `*_attempt` channel literal; unit B must destructure `error`.
2. `scripts/usage_counter_source_lib.dart` — ratchet BOTH entries `1 -> 0`, keeping
   the keys (a deleted key would let a revert pass; `sweep()` flags
   `count > allowed`). ⚠ `usage_counter_source_lib_test.dart:107,121` use
   `firstWhere((e) => e.value >= 1)`; `ai-media-proxy` stays at 1 so they still pass.
3. Live SQL in `test/sql/`: drive `consume_quota` with both new keys through
   limit-1 / limit / limit+1 inside `BEGIN ... ROLLBACK`; assert the `-1` sentinel
   and bucket independence. Also assert unit C:
   `has_function_privilege('anon', ..., 'EXECUTE')` is false afterwards.
4. Mutation proof per rule 21 — mutate the `-1` comparison and the bucket
   arithmetic; confirm each reddens AND that the mutation actually APPLIED.

## Round 2 — remaining items, disposition

All folded into the design sections above rather than left as a checklist:
grace-window mismatch → filed **OI-182**, deliberately not fixed here (Unit B);
`payment.md`/registry/comment drift → **Unit D**, three sites named exactly;
migration header + diagnose-doc pairing → **Unit C**, id `f2c8d5`; cutover
backfill → **Unit B**, one paragraph explaining why none is needed. Nothing left
open from round 2. A third full review round was judged unnecessary — see
`docs/audit/oi162-slice4-review-continuity.md` for the §4.12 split reasoning.

## Residue, stated

- **One live apply (migration 130) + two EF deploys**, each its own §4.3
  authorization. Until deployed, instance A stays inert in prod — its status today,
  so not a regression.
- **Device/patrol flows not run** (round 1 finding 8): `delete_account_patrol_test`
  and `razorpay_payment_patrol_test` are device-gated and were not executed. Round 1
  read `delete_account_e2e_test.dart` and `razorpay_purchase_flow_test.dart` and
  found no repeated-invocation loops a now-live cap would trip. Measured client
  volume is ~4 verify-payment calls per payment over 15 min against a cap of
  20 / 10 min.
- The NULL-channel guard asymmetry (`enforce_vision_analysis_daily_limit` uses
  `NOT IN`, its siblings use NULL-safe `IS DISTINCT FROM`) is a TRIGGER defect
  needing its own migration; it belongs with OI-153's channel work, not here.
