# OI-341 Piece B1: the serialised stacking writer and the payment alert, dark (v4.1)

## History and why this is B1

- **Round 1** (v1, context-blind Sonnet, read-only): 0 P0, 2 P1, 3 P2, 3 P3. All folded in, giving v2.
- **Round 2** (fresh reviewer, on v2): 0 P0, 3 P1, 5 P2, 3 P3. Its main P1 was that the global writer switch is read per warm isolate. Skew between the door and the writers could silently lose trial days.
- **v3** removed the writer switch.
- **Round 3** (fresh reviewer, on v3): 0 P0, 3 new P1:
  1. Removing the switch breaks CLAUDE.md 4.6 (the new path behind a default-OFF gate, the old path preserved verbatim).
  2. Every ordinary payment would depend on an unprobed PostgREST function.
  3. The "equivalence to `origin/main`" test is circular without a preserved old path.

Three rounds in a row each surfaced new material issues. CLAUDE.md 4.12.1 then says the unit is too large: **split it and ship the smallest converged piece.**

The split follows round 3's own findings:
- **B1 (this plan).** The serialised Postgres writer, plus the payment alert, behind Piece A's EXISTING default-OFF switch `ENABLE_SUBSCRIPTION_STACKING`.
  - The OFF path stays verbatim, so Piece A's golden recordings of the `origin/main` writers stay genuine proof (round 3 P1-3).
  - It complies with 4.6 (round 3 P1-1).
  - The new function is probed through PostgREST before any writer depends on it (round 3 P1-2).
  - The door stays shut, so nothing a user sees changes.
- **B2 (section 9, its own plan, branch and reviews).** The door on `create-razorpay-order` behind `ENABLE_TRIAL_PURCHASE`, the client surfaces, both flips, and the rollback order. Round 2 and round 3 findings 4, 7 and 8 are about B2's mechanisms, and are recorded there so none is lost.

**Tier and review bookkeeping.** B1 is a catastrophic-tier build behind a default-OFF switch, with a behavioural test that OFF is byte-identical.
- That is CLAUDE.md 4.12.4 ship-dark tiering: `tier: ship_dark_build` with `review_rounds: 1` on the post-round-3 plan (this v4), plus `bpass: accepted` and `hermes: accepted`.
- The full x2 review is required again on the commit that flips the switch, which is B2.
- Rounds 1 to 3 are history of the unsplit unit. Round 4, on v4, is B1's build review: 0 P0, 0 P1, 4 P2, P3s. All are folded into v4.1 (section 8b); the v4.1 edits are plan-text and test-design only (`mechanical_only: true`).

**Why a live migration still counts as 'dark' (round 4 Q1).** The new function is INERT: only `service_role` may execute it, and no code path calls it while `ENABLE_SUBSCRIPTION_STACKING` is unset. The ship-dark exception in `check_plan_review_record_exists.dart` is self-attested, not detected; this sentence is the attestation.

Branch `oi341-piece-b-door`, from `main` `efb20c4c` (2026-10-20). Live today: `verify-payment` v25 and `razorpay-webhook` v29 (Piece A), with `ENABLE_SUBSCRIPTION_STACKING` never set.

**Execution mode (CLAUDE.md 4.12.7): inline, one worktree, one coordinator.**

## 0. Founder decisions (all recorded; the B2-only ones apply in B2)

- **2026-10-13:** purchase during the referral trial, with the paid cycle stacked after the current PRO.
- **2026-10-16:** testing phase, so no client-first ordering.
- **2026-10-20:**
  1. The "deployed and quiet" precondition is waived.
  2. The banner keeps "RENEW TO STAY PRO" (B2).
  3. The Profile `TrialUpgradeDoor` is dropped. It was never built.
  4. Add "Your paid plan starts when your free days end." to the paywall and the checkout description (B2).
  5. Concurrent payments are serialised per user on the server (B1).
  6. The final stacked purchase runs in Razorpay test mode (B2).

## 1. What B1 fixes (verified 2026-10-20 at `efb20c4c`)

- **G10, concurrency.**
  - Piece A's ON path is a read (`resolveEndDate`, `subscription_stacking.ts:114-137`) followed by an insert, as two PostgREST requests (`verify-payment/index.ts:566-660`, `razorpay-webhook/index.ts:585-640`).
  - Two payments for one user that interleave overlap.
  - `private.grant_referral_days` (migration 159: the referee's 7 days, and the referrer's credit) extends the latest active row under `hashtextextended('redeem_referral_atomic:' || user_id, 0)`. A payment that reads before that extension and inserts after it absorbs those days.
- **No alert.** A failed ON-path record after Razorpay captured the money only logs (Piece A runbook item 4, a hard precondition of the flip).

Neither defect is reachable today, because the switch is unset and the door is shut. B1 removes both BEFORE B2 makes them reachable.

## 2. Design

### 2.1 Migration (number from `sh scripts/mint_migration.sh oi341-piece-b-door`; 161 expected)

**Signature.** `public.record_paid_subscription(p_user_id uuid, p_plan text, p_payment_id text, p_order_id text, p_signature text) RETURNS TABLE(out_end_date timestamptz, out_start_date timestamptz, out_inserted boolean)`.
- The `out_` prefix keeps `RETURNING` unambiguous (round 2 P2).
- PostgREST returns the result as a one-element array. The TS caller reads `[0]`.

**Attributes.** `LANGUAGE plpgsql`, `VOLATILE` (stated, round 4 P3: a `STABLE` function would freeze its snapshot before the lock and miss rows committed while it waited), `SECURITY INVOKER`, `SET search_path = public, pg_temp`, `SET TimeZone = 'UTC'`, `SET lock_timeout = '5s'`.
- Both `SET` attributes are scoped to the call, and are restored on exit.
- The lock timeout bounds every wait inside the call: the advisory lock, an `ON CONFLICT` wait on an uncommitted same-id insert, and the foreign-key key-share wait behind an uncommitted account deletion (159:29-35).

**Body:**
1. **Argument checks.**
   - `p_plan IN ('monthly','yearly')`. Days are derived inside the function: 30 or 365.
   - `p_payment_id ~ '^pay_[A-Za-z0-9]{1,64}$'`.
   - A failure raises 22023.
2. **Lock.** `PERFORM pg_advisory_xact_lock(hashtextextended('redeem_referral_atomic:' || p_user_id::text, 0))`. This is the same key the redeem RPC and the referral job take. Round 1 verified there is one lock per path and no deadlock.
3. **Time.** `v_now := clock_timestamp()`, taken after the lock.
   - `start_date` and `created_at` are `v_now`.
   - Migration 159's job compares `start_date` with `created_at` windows that are also DB-clock values. Round 3 P3 found no boundary hazard.
   - The handler's own `now` in its log lines differs from the stored start by seconds. That is stated, not a defect.
4. **Idempotency, under the lock.**
   - A row with this payment id for `p_user_id` returns `(end, start, false)`.
   - The same row for another user raises `P0001` `payment_owned_by_other_user`.
5. **Base.** `v_base := greatest(v_now, coalesce(max(s.end_date), v_now))`. If `v_base` is not finite (`isfinite(v_base)` false, for example an `infinity` end date on some row) or is later than `9999-12-31` minus 366 days (B-pass P3: the end, base + up to 365 days, must keep a 4-digit year that JS `Date.parse` can read), RAISE SQLSTATE `22008` `invalid_base_end_date` BEFORE the insert (round 4 P2: Piece A's TS path refused an unparseable end with `bad_end_date`, runbook item 2; `infinity + interval` would insert and commit a row the TS side could not parse, then answer 500 with a misleading alert). The `max` is taken over the user's rows that are `status = 'active'`, have `s.end_date > v_now`, and have `s.razorpay_payment_id IS DISTINCT FROM p_payment_id`. A NULL-payment-id trial row counts.
6. **Insert.**
   - `INSERT ... VALUES (..., v_now, v_base + make_interval(days => v_days), ...) ON CONFLICT (razorpay_payment_id) DO NOTHING RETURNING subscriptions.end_date, subscriptions.start_date`.
   - The conflict target is the plain `unique_razorpay_payment_id` constraint (010:9), nulls distinct (094).
   - If nothing is returned, re-select. If the re-select finds NO row (the conflicting row was removed or is invisible in the gap), raise retryable `40001` `payment_row_vanished` (B-pass P3; tested through an RLS seam, R16). If the row belongs to another user, raise as in step 4. Otherwise return `inserted = false`.
   - Step 4 is an EQUIVALENT fast path of this conflict path (B-pass P2: dropping it changes no result); a replay returns the stored row whatever its status, plan, order id or signature.

**Grants.** `REVOKE ALL ... FROM PUBLIC, anon, authenticated; GRANT EXECUTE ... TO service_role`, plus a `DO` block that aborts the apply if a client role can still execute it (bug class 2.32).

**Accepted risk, stated (round 4 P3).** `process_referral_conversions` holds a referrer's key for the rest of its transaction (up to 50 credits). A payment by that referrer arriving in that moment waits up to 5 s, then 55P03: a 500 and an alert, and the webhook's retry succeeds. It is rare (a referrer paying during the hourly minute-41 run) and visible.

**Rollback.** `DROP FUNCTION`. While the switch is unset no writer calls it, so the drop is safe at any time.

**Tier.** `blast_radius.yaml:53`'s content rule may rate a `SECURITY INVOKER` body with grants below catastrophic. The batch is catastrophic anyway because of the writers, and the classifier output is recorded in the build record.

### 2.2 Writers: the ON path calls the function; the OFF path is untouched

`_shared/subscription_stacking.ts`:
- **Keeps** `isValidPaymentId`.
- **Gains** an exported `isStackingEnabled(env = (name) => Deno.env.get(name))` (the arrow wrapper, not the unbound `Deno.env.get`, matching `:46`), the exact `"true"` read that is already inline at `:122`. It is made public so B2's door can share the rule. The writers read it ONCE per request and pass the result down.
- **Gains** `recordPaidSubscription(db, {userId, plan, paymentId, orderId, signature})`. It returns either `{ok: true, endDate, startDate, inserted}` or `{ok: false, code}`, and catches a thrown rejection.
  - There is NO `retryable` flag (round 3 P2: nothing would read it).
- **Deletes** `readLatestActiveEnd` and the ON branch of `resolveEndDate`, because the function replaces them.
- **`resolveEndDate` is collapsed** to the OFF arithmetic only (round 4 P3: with the ON branch gone, its `db` and `env` parameters would be dead and invite a second, drifting switch read). The writers' OFF branch output stays byte-identical to today, and Piece A's golden OFF tests apply unchanged; the golden side loads the `origin_main.ts.txt` fixtures as separate modules (`payment_writer_harness.ts:44-60`), so the new import graph cannot change it.
- **`_shared/payment_alert.ts` has no module-scope code** (no env read, no client creation, no I/O at import), so importing it changes nothing on the OFF path; a test imports it and asserts no side effect.

Each writer's insert branch, after its unchanged idempotency pre-SELECT:

```
if (!isStackingEnabled()):  today's code, verbatim (resolveEndDate OFF -> now+days, insert, 23505 arms)
else:
  r = recordPaidSubscription(...)
  ok:   canonicalEndDateIso (verify-payment) / endDate (webhook, returned as expires_at) := r.endDate,
        on BOTH inserted values;
        verify-payment: weInsertedTheRow := r.inserted   webhook: alreadyProcessed := !r.inserted
        (these drive today's promo-ownership rule unchanged); verify-payment's raceRow re-read
        is DELETED on the ON path (the function absorbs the race)
  !ok:  the writer's existing 500 body + the reconcile log line (ids + code) + reportPaymentRecordFailure
```

- **The webhook's idempotent-skip branch** (`:575-595`, a row already exists) returns the handler's local `endDate` as `expires_at`. That is pre-existing, identical on `origin/main`, and only Razorpay receives it (Piece A ledger H-S1-2). B1 does not change that branch; this is stated so the "stored end on both values" sentence is read as covering the RPC branch only (round 3 P2).
- **`payment_owned_by_other_user`** is reachable only by a race. `verify-payment` checks ownership at `:468-478` and its pre-SELECT is user-scoped (`:555`); the webhook pre-SELECT (`:575`) skips the insert when any row exists. It is a 500 plus an alert, and the retry's pre-SELECT finds the row, so there is no retry storm.
- **An info line** `[<fn>] stacking=on payment_id=... inserted=...` is logged on the ON path.
- **The reconcile line keeps its prefix** `[<fn>] stacking read failed` on the ON-path failure (the payment.md runbook and the closure procedure grep it), with the same fields as today (ids, plan, amount, code; no message, so no new PII).
- **`recordPaidSubscription` rejects a malformed answer:** non-array or empty `data`, or an `out_end_date` that does not parse to a finite `Date`, returns `ok:false` with code `bad_rpc_response` (round 4: the harness's `fallbackRpc` answers `1` for any unrouted RPC, so a missing route must not read as success).

### 2.3 Alert: `_shared/payment_alert.ts` `reportPaymentRecordFailure`

- **The row.** It inserts into `public.alerts` (columns at 076:13-24; the 133 trigger pages `critical` to Telegram):
  - `summary` (`TEXT NOT NULL`, no default, 076:18; round 4 P2): `"<fn>: paid payment not recorded (code <code>)"`, ids only;
  - `source: 'payment_record_failed'`;
  - `context_json` holding `{fn, request_id, payment_id, user_id, plan, amount_paise, code}`;
  - `suggested_action` naming the reconcile step;
  - no message text, email or name.
- **Severity and dedup.**
  - `critical` when no UNRESOLVED (`resolved_at IS NULL`) `payment_record_failed` alert with the same `context_json->>payment_id` exists in the last 24 hours.
  - Otherwise `warn`, which shows in the digest without paging.
  - If the dedup read fails, severity falls back to `critical`.
  - It follows the pattern in `_shared/gemini_failure_alert.ts:100-140`. The existing `alerts_source_idx (source, detected_at)` serves it. Unlike Gemini's, the dedup matches ANY unresolved row for that payment, not only `critical` ones: deliberate, because one payment needs one page.
  - Both round trips (dedup read and insert) are bounded by a 3 s timeout each (`AbortSignal.timeout`), so a slow alerts table cannot push the webhook past Razorpay's response clock (round 4 P3).
- **Races and failures.**
  - A webhook and a `verify-payment` failing at the same instant can both page. That is accepted and stated, since it is one payment and two pages.
  - A failed alert insert is logged and does not change the response.

## 3. Tests (every protection has a named mutant that must redden it; each mutation's application is confirmed, CLAUDE.md 4.4 rule 21)

**3a. SQL**, in the disposable `rpoc-pgtest` replica (159/160 harness), under `test/sql/`. This is where the stored-value equivalence lives (round 3 P1-3).

| Case | Mutant |
|---|---|
| **Ordinary payment:** no active row gives `start` = the DB clock (within the call), `end = start + 30 days` exactly in UTC, and yearly + 365. This is the same arithmetic as the old `now + days` | days swapped; base := a constant |
| Payment during an active trial gives `end = trial end + days` | base := `v_now` |
| Expired and cancelled rows are ignored | the `status` or `end_date > v_now` filter dropped |
| A NULL-payment-id trial row counts | bare `<>` |
| The payment's own row is excluded | exclusion dropped |
| A replay gives the stored row, `inserted = false` | idempotency dropped |
| Stored values: `plan`, `status = 'active'`, `razorpay_order_id`, `razorpay_signature` are the arguments | each column swapped |
| `start_date` is taken after the lock: with session 1 holding the key for 2 s, session 2's stored `start_date` is at or after session 1's commit time | `now()` instead of `clock_timestamp()`; the assignment moved above the lock |
| An `infinity` end date on an active row raises 22008 `invalid_base_end_date` and inserts nothing | the finiteness check dropped |
| `SET search_path`: a same-named `subscriptions` table in a schema earlier on the caller's path is ignored | the `SET search_path` dropped |
| The `DO` grant self-check aborts the migration when a client role keeps EXECUTE (run the migration with the REVOKE line removed: it must fail) | the `DO` block dropped |
| Another user's row raises `payment_owned_by_other_user` (step 4 and the step-6 re-select, separately) | each check dropped |
| A bad plan or bad id raises 22023 | check dropped |
| Grants: `anon` and `authenticated` refused, `service_role` succeeds | REVOKE dropped |
| **lock_timeout:** session 1 holds the key; session 2's call raises 55P03 within about 6 s, inside a 15 s bound | `SET lock_timeout` dropped |
| **TimeZone:** session `TimeZone` `America/New_York`; a seeded trial row ending at `2099-03-07 12:00:00+00`, which is BEFORE the 2099-03-08 US daylight-saving change, so `end - trial_end = 30 * 86400` seconds exactly. The 2099 date is chosen so the test never goes red on a calendar date (round 3 P2; lesson "test clock = authoring day") | `SET TimeZone` dropped |

Concurrency, with two sessions:
- Two different payments for one user give non-overlapping ends (trial + 30 + 30). Mutant: the lock dropped.
- A payment against a referral grant, specified per order (round 4 P2: through `redeem_referral_atomic` a payment-first order REFUSES the redeem with `referee_has_paid_plan`, and the job try-lock SKIPS rather than waits, so "either order" was not one call):
  - (i) `private.grant_referral_days(user, 7)` run directly in session 1 under the key (holding it), then the payment in session 2: session 2 waits, and the stored end = (trial end + 7) + 30.
  - (ii) the payment in session 1 holding the key, then `private.grant_referral_days(user, 7)` in session 2 under the same key: session 2 waits, then extends the LATEST row (the paid one): its end = (trial end + 30) + 7.
  - (iii) the payment holding the key while `private.process_referral_conversions()` runs: the job's try-lock skips that referrer this run (counted as skipped), and a second run credits it.
  - Mutant: a different key string in the function (i and ii then interleave).
- The referral job's try-lock skips while a payment holds the key.

**3b. Deno: request shape and response mapping** (round 3 P1-3: this is NOT an equivalence proof). The fake gains an `rpc/record_paid_subscription` route returning fixed rows in PostgREST's format (`"2026-..T..:..:..123456+00:00"`, an array of one).

| Case | Mutant |
|---|---|
| **OFF, every one of six switch values:** the request list and response are identical to the `origin/main` golden. These are Piece A's existing tests, unchanged; they are the 4.6 proof | any OFF-branch edit |
| ON: each writer calls the RPC with the exact arguments and NO insert POST | argument changed; insert left in |
| ON: the response end is the RPC's `out_end_date`, normalised through `new Date(...).toISOString()` so the client sees the same ISO shape as today, on `inserted` true and false | `endDate` left local |
| ON: `inserted = false` leaves the promo unredeemed; `inserted = true` redeems it once | promo redeemed unconditionally |
| ON: an RPC error gives the existing 500 body, the reconcile line and the alert insert | the alert call dropped |
| ON: a malformed RPC answer (non-array, empty, unparseable `out_end_date`) gives `ok:false` `bad_rpc_response` and the 500 | the shape check dropped |
| ON: an `out_end_date` with a non-zero offset (`+05:30`) maps to the right instant | parse by string slicing |
| Alert row carries a non-empty `summary` | `summary` dropped |
| Importing `payment_alert.ts` performs no env read and no fetch | module-scope code added |
| ON: a failed alert insert leaves the response unchanged | alert error propagated |
| Alert: a second failure for the same payment is `warn`; a failed dedup read is `critical`; a resolved earlier alert pages again | dedup read dropped; `resolved_at` filter dropped; fallback inverted |
| `isStackingEnabled` table (the six values) | loose compare |

Piece A's ON-path tests in `verify-payment/index_test.ts` and `razorpay-webhook/index_test.ts` (the `helperReads` GET with `end_date=gt.`, the "stacking read failed" read-error cases) are REWRITTEN for the RPC path, not kept: "unchanged" above means the OFF golden tests only (round 4 P3).

**3c. Sweep.**
- The source-grep contracts that read the writers' insert blocks: `razorpay_webhook_*`, `verify_payment_*`, `audit_2026_06_07_batch6_server`, `usage_quota_ledger_*` (the fake's `fallbackRpc` must still not count as a call site for `consume_quota`), `no_client_subscriptions_writes`, and `pro_predicate_adoption`.
- The full gate loop runs before the B-pass dispatch (CLAUDE.md 4.12.8).

## 4. Docs, registry and board (all in the build commit)

- **`docs/blast_radius.yaml`:** `_shared/payment_alert*.ts` as catastrophic, above `_shared/**`, classified after the file exists. `create-razorpay-order/**` is pinned in B2.
- **`docs/sot_registry.yaml`:**
  - `subscription_end_date_stacking`: the ON writer becomes `record_paid_subscription`.
  - Remove the `readLatestActiveEnd` reader row (`:16016`).
  - Refresh every shifted `line_range`.
  - New concept `payment_record_failed_alert`, with a `behavioral_test_path`.
- **`docs/naming_conventions.md`:** remove `readLatestActiveEnd` (`:376`); add `record_paid_subscription`, `payment_record_failed`, `isStackingEnabled`.
- **`docs/architecture/payment.md`:** rule 9 gains "ON path = `record_paid_subscription`, serialised; alert on failure". The "Piece B prerequisite" sentence on concurrent different payments is marked done; runbook item 4's ALERT half is marked done and its retry-timestamp half stays open for B2 (round 4 P3: item 3 is the deploy order, not concurrency). Rule 8 is unchanged in B1, because the friend still cannot buy.
- **`supabase/functions/CLAUDE.md`:** the `subscription_end_date_stacking` row.
- **Deno files:** `_shared/payment_writer_harness.ts` (the RPC route), `_shared/postgrest_fake_fetch.ts`, and `_shared/subscription_stacking_test.ts` (the `readLatestActiveEnd` and ON-branch tests are removed; `isStackingEnabled` and `recordPaidSubscription` tests are added).
- **`docs/audit/open_issues.md`:**
  - OI-341 becomes "B1 built (serialised writer + alert, dark); B2 = door + client + flips";
  - OI-351 notes that the function-error path is a new way into its loop once ON;
  - `OPEN_INDEX` is regenerated.
- **Closure ledger** `docs/audit/oi341-piece-b-door.closure.yaml`. Piece A's ledger row G10 and the runbook-item-4 rows are re-pointed here. EVERY section-9 B2 item gets its own row, `terminal_state: upstream_blocked`, `blocker: B1 merged and deployed`, `reopen_when: B2 plan starts`, so no B2 item lives only in plan prose (round 4 P3, CLAUDE.md 4.2): the door and its 503 fail-open fix, the client items, the flip and its per-writer proof, the isolate lag, the rollback order and reconcile query, the retry-timestamp check, the Razorpay timeout check, the pre-created-orders note, rule 8, and the first LIVE happy-path call of `record_paid_subscription` (round 4 Q7: B1 exercises only its error path live).
- **B2 uses a different branch name** (for example `oi341-piece-b2-door`), so its plan-review record does not collide with this one (round 4 P3).
- **Ship-dark ledger** `docs/ship_dark_pending_review.yaml` (round 4 P2): the `ENABLE_SUBSCRIPTION_STACKING` entry records B1 explicitly: a second build `branch: oi341-piece-b-door`, its build commit (stamped after the merge), `review_rounds: 1` (`tier: ship_dark_build`), and the note "B1 REPLACED the Piece A ON path with `record_paid_subscription`; the flip's full x2 review (B2) must re-review the SQL body and the new ON path, not only the door". It stays pending until B2's flip.
- **Review records:** the plan-review record `docs/plan-reviews/oi341-piece-b-door.md` (`tier: ship_dark_build`), the B-pass file and the hermes report (one `docs/audit/` path each, `verdict: accepted`). The record goes in its own later commit, and the merge-time gate is replayed before the merge.
- **The migration apply** goes in its own commit, with `backups/applied_migrations.json` and the ledger hash.
- **History is not edited:** Piece A's plan, ledger, review file, the tuning-history entry, the 159 ledger and `backups/edge_function_payloads/*` keep their references to the deleted helpers (round 3 P3).

## 5. Not in B1

- **B2 (section 9).**
- **OI-350:** untouched.
- **OI-351:** unchanged while OFF.
- **The admin row-count views (ledger H-S3-1):** display only, and B2 territory.

## 6. Live sequence (each step its own founder go)

1. **Apply the migration** to `dedsavbjuwgarrhphgnl`, confirming the project id first.
   - Run the live-verify in aborting chunks of about 10 KB or less.
   - Commit the ledger with the apply.
2. **PostgREST probe** (round 3 P1-2).
   - Through the REST endpoint with the service-role key, call `rpc/record_paid_subscription` with ALL FIVE named arguments, a well-formed uuid, `p_plan: 'x'` and a well-formed `pay_` id (round 4: a missing or misnamed argument is itself PGRST202, the result being excluded).
   - The answer must be HTTP 400 with the function's own SQLSTATE 22023, not `PGRST202` (function not in the schema cache). If PGRST202 appears right after the apply, run `NOTIFY pgrst, 'reload schema'` (read-only for data) and retry once.
   - This writes nothing.
   - Also read the `statement_timeout` that applies to `service_role` requests, from BOTH `pg_roles.rolconfig` (for `service_role` and `authenticator`) and `pg_db_role_setting` (database-level and role-in-database settings), read-only (round 4 P3). It must be unset or above 5 s, or the lock timeout cannot act as designed; if it is lower, B1 lowers `lock_timeout` to fit, in the same commit.
   - Also read `has_table_privilege('service_role', 'public.subscriptions', 'SELECT')` and `... 'INSERT'` live, read-only. The function is `SECURITY INVOKER`, so it runs with `service_role`'s own table privileges; the build found that the disposable replica does not model Supabase's default grant (the SQL proof grants it in setup, stating why), so the live grant is read before any writer depends on it.
   - Also read the live arbiter (hermes P3, L14): `select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.subscriptions'::regclass and contype = 'u'` must show a plain `UNIQUE (razorpay_payment_id)`; the migration history says so (010), but `backups/live_schema_columns.json` records columns only, and the 6.2 probe exercises only the error path.
3. **Deploy `verify-payment`** (`verify_jwt=true`) with the Piece A procedure:
   - rollback payload v25 copied out first;
   - explicit flag;
   - anon-key boot probe (expect the module's own 401);
   - flag read back.
4. **Deploy `razorpay-webhook`** (`verify_jwt=false`) the same way:
   - rollback v29 copied out first;
   - probe with NO Authorization header, expecting `Missing x-razorpay-signature header`;
   - flag read back.
5. **Nothing changes for any user.** The switch stays unset, so the OFF branch runs, and the golden tests prove it equals `origin/main`. Optional: one test-mode purchase by a free tester, read back (`end = start + 30`).

**Rollback:** redeploy v25/v29. The function can stay; it is unused while OFF.

## 7. Review round 1 dispositions (unsplit v1 -> v2)

| # | Sev | Finding | Disposition in B1/B2 |
|---|---|---|---|
| 1 | P1 | The door not tied to the switch | B2 (section 9) |
| 2 | P1 | Unbounded advisory lock | B1: `SET lock_timeout`, SQL test with mutant |
| 3 | P2 | Idempotency not user-scoped | B1: `payment_owned_by_other_user` at both sites, tests |
| 4 | P2 | Stored-end assignment | B1: 2.2, Deno test |
| 5 | P2 | Order-guard details | B2 |
| 6 | P2/P3 | Deploy order and isolate proof | B1: migration, then probe, then writers; B2: isolate lag |
| 7 | P3 | OI-351 reachability | B1: section 4 |
| 8 | P3 | `_pendingStacksAfter` | B2 |
| - | open | Session TimeZone | B1: `SET TimeZone`, seeded-2099 test |

## 8. Review rounds 2 and 3 dispositions

| Round.# | Sev | Finding | Disposition |
|---|---|---|---|
| 2.1 | P1 | Writer-switch skew loses trial days at rollback | B2: the rollback order (shut the door, bounded drain, then the writer switch) is B2's first design item; in B1 the door is shut, so ON and OFF both store `now + days` and skew is harmless |
| 2.2 | P1 | Missing killing tests | B1: section 3 names a mutant for every protection; B2 owns the door, client and reset tests |
| 2.3 | P1 | Non-deterministic both-writers proof | B2 (flip verification); B1 does not flip |
| 2.4 | P2 | `RETURNS TABLE` ambiguity | B1: `out_` columns |
| 2.5 | P2 | `create-razorpay-order` tier | B2 |
| 2.6 | P2 | Deleting `readLatestActiveEnd` | B1: 2.2 and section 4 |
| 2.7 | P2 | lock_timeout breadth; timeouts | B1: 2.1; `statement_timeout` read at 6.2; the Razorpay webhook timeout is B2's flip concern (B1 never runs ON) |
| 2.8 | P2 | Alert reachability and flood | B1: 2.2 and 2.3 |
| 2.9 | P2 | Section 4 omissions | B1: section 4 |
| 2.10-12 | P3 | Window claim, stale `now`, hint | B1: `clock_timestamp()`; the rest B2 |
| 3.1 | P1 | 4.6 deviation and round bookkeeping | B1: the switch is kept and the OFF path is verbatim, so there is no deviation; bookkeeping is stated at the top |
| 3.2 | P1 | Unprobed PostgREST dependency | B1: step 6.2 probe plus the `statement_timeout` read; ordinary payments stay OFF |
| 3.3 | P1 | Circular equivalence | B1: equivalence = the OFF golden plus the 3a SQL ordinary case; 3b relabelled as shape and mapping, with PostgREST-format strings |
| 3.4 | P2 | "Ordinary payment" claim | B1: OFF is unchanged; the stacking of a second pre-created order is a B2/flip note; the skip branch is stated (2.2) |
| 3.5 | P2 | Unread `retryable` | B1: deleted |
| 3.6 | P2 | DST red-date | B1: trial end seeded in 2099 |
| 3.7 | P2 | Rollback not executable | B1: rollback = redeploy, function kept; B2 owns the open-door rollback, reconcile query and drain bound |
| 3.8 | P2 | Isolate lag on SET/UNSET | B2 |
| 3.9 | P2 | Dedup race, `resolved_at`, failed read | B1: 2.3 plus tests |
| 3.10 | P3 | DB clock vs handler clock | B1: 2.1 step 3 |
| 3.11 | P3 | Section 4 completeness | B1: section 4 |

## 9. B2, recorded for its own plan (not built here)

**Scope:**
- `create-razorpay-order`:
  - `export async function handler` with the `import.meta.main` tail;
  - `ENABLE_TRIAL_PURCHASE` via the shared exact-`"true"` rule;
  - OFF = today's guard plus an `error` check returning 503 (diagnose-doc for the fail-open read);
  - ON = `.neq("plan","referral_trial")` (`plan` is NOT NULL), a second read for `stacks_after`, and 503 on either read error;
  - blast-radius pin for `create-razorpay-order/**`.
- The client:
  - `_pendingStacksAfter`, set at `:~190` and reset with `_pendingPlan` at `:63`;
  - optimistic `max(now, stacksAfter) + days`;
  - the checkout description and the paywall line (copy file, Wardroom read);
  - the `_estSealDate` clamp;
  - a banner test.

**Live order:**
1. Flip `ENABLE_SUBSCRIPTION_STACKING`, proving each writer separately by a controlled replay (round 2 P1-3).
2. Deploy the door with its switch OFF (a trial order still gets 409).
3. Set `ENABLE_TRIAL_PURCHASE`, stating the isolate lag; the 200 may take minutes (round 3 P2-8).
4. A test-mode stacked purchase on a trial tester.

**Rollback order (round 2 P1-1, round 3 P2-7):**
1. Shut the door.
2. A bounded drain of at least N minutes, N stated, for isolates.
3. Only then unset the writer switch.
4. A reconcile query, with its owner named: rows whose `start_date` falls inside a `referral_trial` window and whose `end_date` is earlier than the trial end plus the plan days.

**Also in B2:**
- The webhook retry-timestamp check in test mode (Piece A runbook item 4, part 2).
- The Razorpay webhook response timeout against the 5 s lock timeout.
- The concurrent pre-created-orders note (round 3 P2-4).
- `payment.md` rule 8 ("the friend CAN buy").
- The full x2 review, because it flips the switch.

## 8b. Review round 4 dispositions (v4 -> v4.1, mechanical only)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| P2-1 | P2 | Ship-dark ledger entry would not show that B1 had one round and replaced the ON path | FIXED: entry records B1's branch, commit, `review_rounds: 1` and the re-review obligation (section 4) |
| P2-2 | P2 | No guard for an infinite or unparseable base (Piece A had `bad_end_date`) | FIXED: 22008 `invalid_base_end_date` before the insert (2.1); TS `bad_rpc_response` (2.2); SQL and Deno tests with mutants |
| P2-3 | P2 | Alert row lacked the NOT NULL `summary` | FIXED (2.3); test with mutant |
| P2-4 | P2 | The referral concurrency case was not one call | FIXED: three specified cases (3a) |
| Q1 | P3 | "Behind the switch" for a live function | Attestation sentence added (top) |
| Q1 | P3 | B2 record key collision | B2 branch name differs (section 4) |
| Q2 | P3 | Unbound `Deno.env.get`; double read; dead `resolveEndDate` params; alert module scope | FIXED (2.2) |
| Q2 | P3 | Piece A ON tests silently "unchanged" | Stated as rewritten (3b) |
| Q3 | P3 | Volatility unstated; non-UTC offset in fixtures; referral-job hold | `VOLATILE` stated; `+05:30` fixture test; accepted risk stated (2.1) |
| Q4 | P3 | Both variables, raceRow deletion, log prefix | Stated (2.2) |
| Q5 | P3 | Dedup scope deliberate; alert round trips unbounded | Stated; 3 s timeouts (2.3) |
| Q6 | P3 | No test for clock-after-lock, `DO` self-check, stored columns, search_path; fallbackRpc | Tests with mutants added (3a); `bad_rpc_response` (2.2) |
| Q7 | P3 | Probe needs all five args; schema-cache reload; timeout read sources; live happy path | Fixed (6.2); the live happy path is a closure-ledger row for B2 |
| Q8 | P3 | B2 items only in prose; payment.md item labels | Ledger rows for every B2 item; labels corrected (section 4) |
