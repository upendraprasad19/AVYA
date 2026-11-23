# OI-519: Android PRO purchase through RevenueCat + Play Billing (versionCode +51), v9 (after review rounds 1-6 + founder answers + U0 doc findings, section 18)

Branch `oi519-revenuecat-plan`, base `8eff2037` (origin/main, 2026-11-23). Decision record: ADR-0022. Predecessor plan:
`docs/plans/2026-11-20-android-play-billing.md` (its section 8 is the design sketch this plan replaces; facts there are
re-checked here, not inherited).

- **Tier: L** (CLAUDE.md 4.12.6: payment, auth-adjacent, schema, Edge Functions). **Blast radius: catastrophic** (a new
  writer of the PRO entitlement, a `subscriptions` schema change, live SQL function bodies). So: this plan gets two
  context-blind review rounds (4.12.1), the full gate loop + CI before each dispatch once a diff exists (4.12.8), the
  `/code-review` B-pass, the `/hermes-pass`, and a plan-review record `docs/plan-reviews/oi519-revenuecat-plan.md` with
  `review_rounds: 6` (section 17), `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`, `hermes: accepted`.
  Catastrophic tier: a local full suite (`sh scripts/run_full_suite.sh`) before the staged review, CI before merge.
- **Execution mode (4.12.7): inline.** One worktree, one writer, units in order. Reason: the units share files
  (`subscription_service.dart`, the migration, `_shared/revenuecat_mirror.ts`, the SoT registry), so parallel worktrees
  would only add cherry-pick conflicts.
- Closure ledger `docs/audit/2026-11-23-revenuecat-play-billing.closure.yaml` (more than 4 units, 4.2), created once
  every entry is terminal.
- **Nothing is committed, migrated, deployed or built by this document.** Live steps each need their own go (4.3).
- Review history: round 1 on v1 (context-blind Sonnet, 2026-11-23): 19 findings (5 P1, 10 P2, 4 P3), verdict NOT
  CONVERGED; every finding checked against code/live SQL by me and folded into v2 (dispositions in section 14).
  Round 2 on v2 (a fresh context-blind Sonnet): 10 findings (2 P1, 5 P2, 3 P3), NOT CONVERGED; all checked and folded
  into this v3 (section 15). The round-2 P1 on the client grace was solved by DELETING that mechanism (a server-side
  renewal window instead), not by patching it. Round 3 (focused on the v3 changes): 7 findings (1 P1, 3 P2, 3 P3),
  all checked and folded into this v4 (section 16); the P1 was in the new window itself (now defined inside the
  status test). Verdict after folding: converged (section 16).
  **v5 (2026-11-23):** founder answered Q1-Q6 (section 12). Q1 = B adds a NEW mechanism (referral days for a Play
  subscriber become a Google "defer" of the next charge, section 4 item 4), so v5 gets review round 4 focused on
  that mechanism and its seams before any code (section 17).

## 0. Founder decisions already binding (memory `project_play_billing_decisions_2026_11_20`)

- Play Billing on Android via RevenueCat; web stays Razorpay one-time orders (ADR-0019, ADR-0022). Auto-renewing.
- App User ID = Supabase user id. The `subscriptions` table stays the only source the gate reads (rules 5, 19).
- Already-PRO user on Android sees "PRO until <date>" and cannot buy.
- Price comes from the store, never from code. Founder 2026-11-23 (Q5): Play price Rs 449 / month, Rs 3,499 / year
  (web stays Rs 349 / Rs 2,999). Play Console holds 449 / 4,499 today; the founder changes the yearly base plan to
  3,499 (section 9).
- Promos on Android: our free-days codes (OI-347). No Play intro offer or free trial in +51 (Q3). Percent-off
  codes stay web-only.
- RevenueCat state (2026-11-22): project "Avya", entitlement `avya_pro`, offering `default` with `$rc_monthly`
  (`avya_pro:monthly`) and `$rc_annual` (`avya_pro:yearly`), public SDK key `goog_…` (public by design).

## 1. Facts (verified 2026-11-23 at `8eff2037` and against the live project `dedsavbjuwgarrhphgnl`)

- F1. Live `public.subscriptions`: `id uuid pk`, `user_id uuid NOT NULL -> users(id) ON DELETE CASCADE`, `plan text NOT
  NULL` (no CHECK), `status text default 'active'` (nullable, no CHECK), `start_date`/`end_date timestamptz NOT NULL`,
  `razorpay_order_id`, `razorpay_payment_id` (UNIQUE `unique_razorpay_payment_id`), `razorpay_signature`,
  `razorpay_subscription_id`, `created_at`, `cancelled_at`. Index `idx_subscriptions_active (user_id, end_date) WHERE
  status='active'`. RLS: one policy, `subscriptions_select_own` (SELECT where `auth.uid() = user_id`); no client write.
  Trigger `trg_set_subscription_cancelled_at` (BEFORE INSERT OR UPDATE) stamps/clears `cancelled_at` on status
  `cancelled` transitions. Live rows: monthly active 4, yearly active 2, referral_trial active 4, monthly cancelled 3,
  monthly expired 1 (all testing accounts, CLAUDE.md section 1). No `*event*` table exists.
- F2. Every PRO reader uses `status = 'active' AND end_date > now()` (latest-ending row): `verify-subscription/index.ts:67-71`,
  `_shared/subscription.ts:123-140` `isProUser` (+ `fetchProUserIds`, `fetchLatestActiveEndByUser`, `readProState`),
  `private.founder_metrics` (live body), client `subscription_service.dart:894-901` `refreshFromSupabase`. So a Play row
  with `status='active'` and `end_date = store expiry` is read correctly by ALL of them with no reader change. Same
  predicate (round 1 check): `enforce_progress_photo_pro`, `compute_coach_signals_for_user`, the chat / food / vision
  daily-limit triggers, `find_orphan_chat_media`, `weekly-report`, `readProState`.
- F3. Readers that define "paid" as `razorpay_payment_id IS NOT NULL` (would treat a Play subscriber as unpaid), live
  bodies read with `pg_get_functiondef` today: `public.redeem_referral_atomic` (twice: precondition and retry
  re-check), `private.process_referral_conversions` (step 1 `calc` lateral join). Edge: `redeem-referral/index.ts:132`.
- F4. Writers that change `end_date` in place: live `private.grant_referral_days` (UPDATE `end_date + days` on the
  latest active row, `FOR UPDATE NOWAIT`; INSERTs a `referral_trial` row when none / expired). If that row is a Play
  row the next mirror write overwrites it and the days vanish.
- F5. `expiry_reminder_daily` (cron `0 9 * * *`) runs `expiry-reminder`, which pushes "PRO plan expiring soon ... Renew"
  (`expiry-reminder/index.ts:170-171`) to rows ending within 3 days. A Play row that auto-renews must not get that push.
- F6. `create-razorpay-order` door (`index.ts:236-243`): any active row whose plan is not `referral_trial` is "paid" ->
  409 `already_pro`. A Play row with `plan` monthly/yearly is therefore already blocked from a web double purchase.
- F7. `delete-account/index.ts:242-293` cancels Razorpay subscriptions by `razorpay_subscription_id`; nothing stops a
  Play subscription. The FK cascade deletes our rows; Google keeps charging.
- F8. Client: `PurchaseMode.playBilling` exists and behaves as `none` (`lib/core/constants/purchase_mode.dart`:
  `showsPurchaseUi` and `showsRazorpay` true only for `razorpay`; `showsPlayBilling` has no reader). 29 lines outside
  that file read `showsPurchaseUi` / `showsUpgradeAffordance()`. `PaywallSheet` (`paywall_sheet.dart`, 908 lines)
  returns `PaywallUnavailableBody` (`:419-426`) when `showsPurchaseUi` is false. Hard-coded prices
  (`AppConstants.monthlyPriceInr` / `yearlyPriceInr`) are read in `paywall_sheet.dart`, `paywall_sheet_phase_variant.dart`,
  `subscription_service.dart`, `app_constants.dart`. `pubspec.yaml:86` `purchases_flutter: 11.0.4` (dormant, never
  configured).
- F9. `/build-apk` (`.claude/commands/build-apk.md:34-42`) refuses `--purchase-mode play_billing`.
- F10. `.env.example` keys: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `RAZORPAY_KEY_ID`, test creds. No RevenueCat key.
- F11. RevenueCat webhook docs (fetched 2026-11-23): optional Authorization header set in the dashboard and sent on
  every POST; optional HMAC `X-RevenueCat-Webhook-Signature: t=<ts>,v1=<hex>` over `"<ts>.<raw body>"`; only HTTP 200
  is success; up to 5 retries at about 2.5/5/10/20/40 min; 60 s timeout; retries keep the same `id`; no ordering
  guarantee; RevenueCat RECOMMENDS calling `GET /subscribers` on every event instead of per-event logic. A refund
  arrives as `CANCELLATION` with `cancel_reason = CUSTOMER_SUPPORT`; `environment` is `SANDBOX` | `PRODUCTION`.
- F12. **Doc-verified at U0 (section 18); the live shapes are re-checked at L2 before the switch goes ON:** the exact REST v1 shapes (`GET /v1/subscribers/{id}` creates a
  customer when missing; `subscriber.entitlements.avya_pro.expires_date`; `subscriptions[<product>]`
  `unsubscribe_detected_at`, `billing_issues_detected_at`, `refunded_at`, `is_sandbox`, `store`, `grace_period_expires_date`);
  the Google endpoints for cancel / revoke / defer and `DELETE /v1/subscribers/{id}`; the product identifier format
  for a base plan (`avya_pro:monthly` per the dashboard); that `purchases_flutter 11.0.4` exposes
  `Purchases.configure/logIn/logOut/getOfferings/purchasePackage/getCustomerInfo` with these names; the Play Billing
  Library version it bundles is still accepted. The OpenAPI file at revenuecat.com returned a 4 KB stub today.

## 2. The model in one paragraph

The phone buys through RevenueCat with App User ID = Supabase uid. The server never trusts the phone or the webhook
body: every trigger (webhook event, the user's own "sync me" call, the hourly reconcile) calls ONE shared function
`mirrorRevenueCatCustomer(uid)` that reads the customer from RevenueCat's REST API with the secret key and upserts ONE
`subscriptions` row per (user, store subscription) from THAT answer. The key is `(user_id, store_product_id)`, not a
transaction id: RevenueCat v1 keys `subscriber.subscriptions` by the Google subscription id WITHOUT the base-plan
suffix (`avya_pro`), returns the base plan separately in `product_plan_identifier` (`monthly` / `yearly`), and keeps ONE
entry per subscription describing the purchase with the furthest-out expiry (RevenueCat webhook doc, "Matching
`product_id` to the REST API"; U0, section 18); the Google order id changes on every renewal (round 1 #1). So a Play
subscriber has ONE row (`store_product_id = 'avya_pro'`), its `plan` taken from `product_plan_identifier`; a resubscribe
or a monthly <-> yearly switch updates that same row. So delivery order, retries, duplicates and forged events
cannot write a wrong end date; the worst a forged event can do is cause a re-read of the truth. Every existing reader
keeps working because a Play row is an ordinary `status='active'`, `plan in (monthly, yearly)` row whose `end_date` is
the store expiry (F2).

## 3. Schema (one migration, number from `sh scripts/mint_migration.sh <slug>`)

Additive only; rehearsed in the local `supabase/postgres` docker image first (memory: never rehearse on prod); applied
only on its own explicit go; `backups/applied_migrations.json` and `backups/live_schema_columns.json` in the same commit.

- `subscriptions` new nullable columns: `store text` (NULL = our own rows, `'play'` for Play; CHECK `store IS NULL OR
  store = 'play'`), `store_product_id text` (the REST subscriptions key, `avya_pro`; `plan` from `product_plan_identifier`, U0), `store_original_transaction_id
  text` (informational only, never an arbiter), `auto_renew boolean`, `store_environment text` (CHECK in `SANDBOX`,
  `PRODUCTION`), `store_expires_at timestamptz` (the store's own expiry, for display), `store_read_at timestamptz` (the instant the RevenueCat GET was ISSUED, never the DB write time;
  round 1 #6). CHECK: `store = 'play'` implies `store_product_id`, `store_environment`, `store_read_at` NOT NULL.
  Plain (non-partial) UNIQUE index `subscriptions_play_product_uq ON (user_id, store_product_id)`: every non-Play row
  has a NULL `store_product_id` and NULLs never collide, so it constrains Play rows only, and a non-partial index
  avoids the 42P10 trap (`supabase/migrations/CLAUDE.md`, "Partial UNIQUE index + ON CONFLICT"; round 2 #8). NULL for
  every existing row, so no backfill and no existing behaviour changes.
- The existing `subscriptions_select_own` policy now also shows the owner their own `store_*` values. Harmless (their
  own product id and order id); stated so nobody "fixes" it (round 1 #18).
- New `public.subscription_events` (id, `provider text` = 'revenuecat', `provider_event_id text UNIQUE`, `user_id uuid
  NULL` (FK users ON DELETE SET NULL), `event_type`, `product_id`, `environment`, `event_timestamp_ms bigint`,
  `received_at`, `outcome text`). NO payload column and NO raw `app_user_id` column: the webhook writes `user_id` only
  when the id is a UUID with a `public.users` row, else NULL (an unknown or forged id can neither break the insert on
  the FK nor be stored; round 1 #11). On account deletion `user_id` goes NULL by the FK, so nothing identifying stays
  (DPDP, round 1 #10). RLS enabled, NO policy (deny all clients), service role writes. ADR-0019 deferred this table to
  "the Play batch"; this is it.
- Live function bodies (read with `pg_get_functiondef`, the last `CREATE OR REPLACE` wins):
  - `redeem_referral_atomic`, `process_referral_conversions`: "paid" becomes `(razorpay_payment_id IS NOT NULL OR
    (store = 'play' AND store_environment = 'PRODUCTION'))`. Sandbox Play rows are NOT paid for referrals: Play test
    renewals run every few minutes and a tester could otherwise farm referrer rewards (round 1 #8). Every other clause
    verbatim. With zero Play rows this matches exactly the same rows (test T-SQL1).
  - `private.grant_referral_days(p_user_id, p_days)` (stays in schema `private`, signature unchanged; Q1 = B): today's
    body moves VERBATIM into
    `private.grant_referral_days_direct(p_user_id, p_days)` (same SECURITY DEFINER, search_path, grants). The new
    wrapper body first runs today's argument check verbatim (same 22023 error, round 5 P3-9); then, when the user has an active Play row (`store = 'play' AND status = 'active' AND
    end_date > now()`), INSERT one `pending` row into `store_reward_deferrals` and RETURN, changing no
    `subscriptions` row; otherwise `PERFORM private.grant_referral_days_direct(p_user_id, p_days)`. The direct body's
    in-place UPDATE also gains `AND s.store IS DISTINCT FROM 'play'` in the `SELECT … FOR UPDATE NOWAIT` (second
    guard: the mirror rewrites a Play row's `end_date` on every read, so an in-place extension would be silently
    overwritten). With no Play row the result is byte-identical (T-SQL1). Both callers (`redeem_referral_atomic`,
    `process_referral_conversions`; live `pg_proc` search 2026-11-23 found no other caller) need no change: they
    `PERFORM` it, the new first-branch SELECT takes no row lock, and the queue INSERT rolls back with the caller's
    sub-block (round 4 checked).
  - New table `public.store_reward_deferrals` (`id uuid pk default gen_random_uuid()`, `user_id uuid NOT NULL ->
    users(id) ON DELETE CASCADE`, `store text NOT NULL CHECK (store = 'play')`, `days integer NOT NULL CHECK (days
    BETWEEN 1 AND 30)`, `status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_flight', 'applied',
    'fell_back', 'needs_check'))`, `claim_token uuid`, `claimed_at timestamptz`,
    `created_at`, `updated_at`). RLS on, NO policy, service role only. Index `(status, created_at)`; partial UNIQUE
    index `(user_id) WHERE status = 'in_flight'` (one defer in flight per user, round 4 #2). The Apple build widens
    the `store` CHECK.
  - New `public.store_reward_fall_back(p_id uuid, p_token uuid) RETURNS text` (SECURITY DEFINER, revoked from
    public / anon / authenticated, granted to service_role). Its FIRST statement is the compare-and-set `UPDATE store_reward_deferrals SET status =
    'fell_back' WHERE id = p_id AND ((status = 'pending' AND p_token IS NULL) OR (status IN ('in_flight',
    'needs_check') AND claim_token = p_token)) RETURNING user_id, days`; 0 rows -> `'noop'` (round 6 #3: a runbook
    call cannot race a drain claim). `in_flight` / `needs_check` with the token is the founder's resolve path
    (section 10) (round 4 #1: a run can never fall back a row another run has
    claimed). In the SAME transaction it then runs `private.grant_referral_days_direct` (so two
    fall-backs STACK like any web reward, round 4 #4). Any other status, a token mismatch, or a user with no
    `users` row returns `'noop'` and writes nothing. A `55P03` from the direct body's `FOR UPDATE NOWAIT` rolls the whole
    call back, leaving the row as it was; the next run tries again (round 5 P3-7).
  - New `public.upsert_play_subscription(p_user_id, p_product_id, p_plan, p_status, p_start, p_end, p_auto_renew,
    p_environment, p_original_txn, p_store_expires_at, p_read_at) RETURNS text` (`p_store_expires_at` added at U1: the column
    needs a writer) SECURITY DEFINER, `REVOKE ALL FROM public, anon,
    authenticated`, `GRANT EXECUTE TO service_role` (the platform default grants on new `public` functions are revoked
    explicitly from `anon` and `authenticated`, migrations CLAUDE.md). Body: `INSERT … ON CONFLICT (user_id,
    store_product_id) DO UPDATE SET … WHERE subscriptions.store_read_at <= excluded.store_read_at` (non-partial
    arbiter, round 1 #2 / round 2 #8). First insert has no conflict; a later refund read has a later `read_at` and
    lowers `end_date` (round 2 check). `start_date` on UPDATE: `CASE WHEN subscriptions.status = 'active' THEN
    subscriptions.start_date ELSE excluded.start_date END`, so a running chain keeps its first period's purchase date
    across renewals (the referral 90-day window and 7-day vest anchor on the chain start, not on each renewal), and a
    resubscribe after expiry starts fresh. `original_purchase_date` is NOT used: it is the first purchase EVER of that
    product, which would anchor a later chain to an old one (round 3 #4). Returns `'written'` or `'stale_read'` (from `GET DIAGNOSTICS ROW_COUNT` = 0), so the caller can log a skipped
    stale read (round 1 #6). Owner change cannot happen: `user_id` is part of the key.
  - `record_paid_subscription` (web) is NOT changed: its stacking base can include a Play row's end only if a web
    payment is in flight while a Play row lands (the door 409s a paid Play row first). Noted so nobody "fixes" it
    (round 1 #17).
  - The migration header carries the three pre-change function bodies verbatim (from `pg_get_functiondef` at U1), and
    a `-- ROLLBACK` block that restores them, so rolling back the function changes is not "find it in git" (L35,
    round 1 #18). Columns, index, table stay on rollback (additive).

## 4. Server: one shared mirror, three thin entry points (+ the reward drain inside the third)

`supabase/functions/_shared/revenuecat_mirror.ts` (pure mapping + one IO function, Deno-tested):

- `mapCustomerToRows(customer, nowMs)` (pure): for each `subscriptions[productId]` with `store = play_store`: key
  `avya_pro` -> one row keyed by it, `plan` from `product_plan_identifier` (`monthly` | `yearly`); any other key or plan id,
  or an entry without `purchase_date` / `expires_date` / boolean `is_sandbox` -> no row + critical alert
  `revenuecat_unknown_product` (U0/U2). Paused (`auto_resume_date` set) counts as not renewing. Let `P` = the latest period's
  `purchase_date`, `E` = `expires_date`, `G` = `grace_period_expires_date` when a billing issue is open. Rules, first
  match wins (rounds 1 #14, 2 #2, 3 #1, #5):
  1. **Refunded:** `refunded_at IS NOT NULL AND refunded_at >= P` -> `status = 'cancelled'`, `end_date =
     refunded_at`. A refund of an OLD period followed by a rebuy has `refunded_at < P` and falls through, so it never
     cancels the new purchase. The refund-then-rebuy fixture is doc-derived (U0 could not read a live customer); the
     real shape is checked at L3 and T-MAP re-run before the switch goes ON (section 18).
  2. **Renewing (the renewal window):** `unsubscribe_detected_at IS NULL AND billing_issues_detected_at IS NULL` ->
     `effective_end = E + PLAY_RENEWAL_WINDOW` (3 hours); `status = active` iff `effective_end > now`; `end_date =
     effective_end`. The window is part of the STATUS test, so a read at `E + 10 min` before the renewal is posted
     keeps the row active (round 3 #1). The renewal is charged at `E` and its webhook may take minutes; hourly reconcile
     reads normally land 3 times inside the window (a probability, not a guarantee, if a cron run is skipped). Every
     reader (client `isPro`, `proStateSnapshot`, `verify-subscription`, `isProUser` for `ai-proxy`, the triggers) keeps
     PRO through the renewal with no reader change and no client network call. Worst case, stated: a renewal that
     silently never arrives gives at most 3 extra hours.
  3. **Not renewing:** `effective_end = max(E, G)`; `status = active` iff `effective_end > now`, else `expired`;
     `end_date = effective_end`. Cancelled-but-not-expired lands here as `active` with `auto_renew = false` (the
     trigger stamps `cancelled_at` only on status `cancelled`, so it stays NULL).
  Always: `store_expires_at = E` (true store expiry, for display); `auto_renew = (unsubscribe_detected_at IS NULL AND
  billing_issues_detected_at IS NULL)`; `start_date = P` (see the upsert for how a running chain keeps its first
  start); `store_environment` from `is_sandbox`. Paused / on hold (`auto_resume_date` set, past expiry) -> rule 3 ->
  `expired`, re-activated by the next read after resume. A monthly <-> yearly switch is the SAME row (one REST entry, the
  furthest-out purchase): `plan` follows `product_plan_identifier`; any value other than `monthly` / `yearly` -> no
  write + critical alert (U0).
- `mirrorRevenueCatCustomer(uid, deps)`: refuses a uid that is not a UUID or has no `public.users` row (a forged
  webhook must not create RevenueCat customers, since `GET /subscribers` creates one, F12); stamps `read_at = now()`
  BEFORE issuing the GET; reads the customer; upserts each row through `upsert_play_subscription`; returns `{rows,
  outcome}` with per-row `written` / `stale_read`. Secret key `REVENUECAT_SECRET_KEY` (Edge secret only). Timeout 10 s,
  one retry on 5xx/429. Never logs a response or request body (payment-log-safety, `_shared/payment_log_safe.ts`).
- Kill switch `ENABLE_PLAY_BILLING_MIRROR` (exact `"true"`, `isEnvExactlyTrue`). OFF: every entry point answers as
  today would (webhook 200 + event logged with `outcome = 'switch_off'`, sync returns the current row unchanged,
  reconcile does nothing). Unset = off. The `delete-account` RevenueCat leg does NOT read this switch: it runs whenever
  `REVENUECAT_SECRET_KEY` is set, so a deleted account is never left billing (round 1 #9).

Entry points (each `deno check --node-modules-dir=none`, each deployed with `.claude/emit_payload.js` +
`deploy_via_api.js`, each needs its own deploy go):

1. **`revenuecat-webhook`** (verify_jwt = false). Auth: `Authorization` header equals secret
   `REVENUECAT_WEBHOOK_AUTH`, compared with `timingSafeEqual` imported from `_shared/cron_auth.ts:83` (already exported
   and imported by `telegram-admin-bot`; not moved, round 2 #9); unset secret -> 500 and nothing written (fail closed, RevenueCat retries). Body
   capped at 64 KB. Steps: insert the event into `subscription_events` (ON CONFLICT `provider_event_id` DO NOTHING:
   a retry still re-mirrors, which is idempotent); `TEST` -> 200; `TRANSFER` -> mirror every uid in
   `transferred_from` + `transferred_to` + critical alert (should never happen, see founder step 3 in section 9); every
   other type -> `mirrorRevenueCatCustomer(app_user_id)` (also `original_app_user_id` when different). Mirror failure
   -> 503 so RevenueCat retries; after the last retry the reconcile cron catches it. The webhook is added to
   `test/contracts/payment_log_safety_writer_to_reader_test.dart`'s function list (today only the three Razorpay
   functions), together with `revenuecat-sync` and `revenuecat-reconcile` (round 1 #11).
2. **`revenuecat-sync`** (verify_jwt = true, the user's own row only, uid from
   `createClient(URL, SERVICE_ROLE).auth.getUser(token)`, rule 9 contract e8a1c3). Called by the client after a
   purchase and on RESTORE / CHECK MY PRO STATUS, nothing else (no call on sheet open, no call at expiry: the renewal
   window in the mirror covers that; round 2 #1, #7). Rate limit: `consume_quota(p_user_id, 'revenuecat_sync',
   p_window_start = <hour bucket>, p_limit = 20)` (live signature, 4 arguments) BEFORE any RevenueCat call, fail
   closed exactly as `create-razorpay-order` does: an RPC error answers 429 `rate_limit_unavailable`, a `-1` answers
   429 `rate_limited`, a non-integer or `< 1` result is `bad_result` -> 429 `rate_limit_unavailable`, all three exactly
   as `create-razorpay-order/index.ts:148-189`; never an unmetered read (round 1 #3, round 2 #7, round 3 #6). Budget:
   a purchase spends ONE sync call (right after `purchasePackage` returns; the confirming poll then uses
   `verify-subscription`, steps `kVerificationRetryDelays` in `payment_timing.dart`), RESTORE / CHECK spends one per
   tap, so 20 an hour is ample. The client call passes `spendsQuotaPerCall:
   true` (OI-414) and maps 429 to "Too many checks. Try again in an hour."; the post-purchase poll falls back to
   `verifyFromServer` only (the webhook still lands the row).
   Returns the same shape as `verify-subscription`.
3. **`revenuecat-reconcile`** (cron, `_shared/cron_auth.ts`, `_shared/cron_telemetry.ts` per 4.5): hourly, mirrors
   every user with a Play row whose `end_date` is within `[now - 3 days, now + 1 day]`, or that is `active` with
   `store_read_at` older than 24 hours (bounded batch, `paged_fetch_bounded`). This is what makes renewals, expiries
   and mid-term refunds land when every webhook retry failed. Accepted worst case, stated: a mid-term refund whose
   webhook and all 5 retries were lost keeps PRO for at most 24 hours (round 1 #15). Registered in
   `docs/operations/CRON_REGISTRY.md`.
4. **Referral days for a Play subscriber: Google defer (Q1 = B).** Drained by `revenuecat-reconcile`, at most 20
   oldest rows a run, each row with its own fresh customer read (no per-run cache, round 5 P3-5). Every write is
   compare-and-set. The claim is `UPDATE … SET status = 'in_flight', claim_token = gen_random_uuid(), claimed_at =
   now() WHERE id = $1 AND status = 'pending' RETURNING claim_token` (0 rows -> skip; a unique-index violation,
   another defer in flight for that user -> skip); every later mark is `WHERE id = $1 AND status = 'in_flight' AND
   claim_token = $token` (round 4 #1, round 5 P3-6).
   - **Stall alert first, even with the switch OFF:** a warn alert (counts only, no user id) when a row is `pending`
     over 24 h, `in_flight` over 2 h, or `needs_check` (round 4 #5). The drain itself runs only while
     `ENABLE_PLAY_BILLING_MIRROR` is on.
   - **Guard before every RevenueCat call:** the mirror's own check (the id is a UUID with a `users` row); else skip
     (the FK cascade removes the row). A GET would otherwise recreate a deleted user's RevenueCat customer (round 4
     #3).
   - **`pending` row:** read the customer and map it with the mirror's own rules. Exactly two outcomes act: the
     `avya_pro` subscription is active with its store expiry in the future -> claim; no `avya_pro` entitlement at all
     (not active, not in the renewal window, not in billing-issue grace) -> `store_reward_fall_back(id, NULL)`.
     Anything else (renewal window, grace, a read error) -> leave `pending` (round 4 #6, round 5 P3-4). Monthly and
     yearly are base plans of ONE Google subscription `avya_pro`, so there is one subscription to defer.
   - **The call:** `POST /v1/subscribers/{uid}/subscriptions/avya_pro/defer` with `{"extend_by_days": days}` (product
     id = the part before the colon, per RevenueCat's docs; confirmed at U0), 10 s timeout.
     - 2xx -> mark `applied` FIRST, then mirror the customer best-effort (a mirror failure is caught by the webhook
       and this cron; round 5 P3-3).
     - 429 -> back to `pending` (not applied, round 4 #7).
     - Other 4xx (the call was refused, so nothing was applied) -> re-read: no `avya_pro` entitlement ->
       `store_reward_fall_back(id, token)`; still active -> `needs_check`; the re-read itself fails -> back to
       `pending` (round 5 P3-2).
     - Timeout / 5xx / network error: the outcome is UNKNOWN -> `needs_check` at once.
   - **An unknown outcome is NEVER re-sent and NEVER auto-confirmed.** Defer is not idempotent (a second call adds
     the days twice). v6 tried to auto-confirm from a later `SUBSCRIPTION_EXTENDED` webhook; rounds 4 and 5 kept
     finding ways that confirmation could be wrong (Google sends the same event for its own deferred charge; a later
     reward's event satisfies an earlier row; a renewal in between; which expiry to compare). v7 DELETES that
     mechanism (and the ledger column and `expiry_before` it needed). Hazard it guarded, still covered: a timed-out
     defer is not lost, it is a `needs_check` row plus the stall alert, and the founder resolves it by hand from the
     RevenueCat customer page (runbook, section 10). Expected rate: a 10 s timeout on one call per reward, close to 0.
   - An `in_flight` row older than 1 hour (a run that crashed between claim and mark) -> `needs_check`.
   - The webhook already mirrors every non-TEST event type, so `SUBSCRIPTION_EXTENDED` needs no new branch.
   - Client: no change. The new expiry reaches `pro_store_expires_at`, so Profile's `RENEWS <date>` moves. Google
     sends the user no email; that date is the notice.
   - Apple (next build): Apple's renewal-date extension allows 2 per user per year, at most 90 days, and Apple
     documents it for outages; its promotional offers are the native alternative. The Apple build chooses; the
     table's `store` column is already there for it.

Readers changed:
- `expiry-reminder`: skip a user whose latest-ending active row is `store = 'play' AND auto_renew = true` (it renews;
  a Play row with `auto_renew = false` still gets the reminder, copy unchanged per the GO_LIVE 0.4 decision). The
  shared `fetchLatestActiveEndByUser` (`_shared/subscription.ts:236`, selects only `user_id, end_date`) is NOT changed:
  `telegram-admin-bot`, `founder_digest_content.ts` and `admin-dashboard-data` share it and their counts must not
  move. `expiry-reminder` gets its own select + reducer (round 1 #7). Test case: a renewing Play row plus a later
  trial row.
- `redeem-referral/index.ts:132`: same "paid" predicate as the SQL (F3).
- `delete-account`: for the Play row if not refunded (one per user since U0; the text below still reads per row), whatever its mapped status (a paused / on-hold row maps to
  `expired` but Google can still bill it; round 2 #6), FIRST RevenueCat's Google cancel endpoint `POST /v1/subscribers/{uid}/subscriptions/{store_transaction_id}/cancel`
  (stop renewal; path keyed by the entry's `store_transaction_id`, U0), 10 s timeout so it cannot eat the function's budget; ONLY on cancel success `DELETE
  /v1/subscribers/{uid}` (DPDP; deleting first would lose the handle needed to retry the cancel). The customer is
  deleted only when EVERY Play row's cancel succeeded; one failed cancel (e.g. monthly ok, yearly failed) skips the
  delete for the whole customer (round 3 #8). A failure is
  non-fatal, alerted, and recorded the same way the Razorpay leg records `cancelFailures` (`:257-293`) (round 1
  #10). The in-app delete screen in `play_billing` mode says "Cancel your subscription in Google Play" with the
  manage link before the final confirm.
- `admin-dashboard-data`, `founder_metrics`: no predicate change needed (F2); add a `store` split to the admin view
  (Q4, founder 2026-11-23: yes, one Play-vs-web count column). `founder_digest_content.ts` "New MRR" prices rows with `PLAN_PRICES_RUPEES` (349 / 2,999,
  `:226`), wrong for a Play row (Play 449 / 3,499, Q5): the digest excludes `store = 'play'` rows from MRR and prints
  their count separately, per Q4 (round 1 #16). The same plan-count x 349 / 2,999 MRR exists in
  `admin-dashboard-data/index.ts:43-44,282-283` and `telegram-admin-bot/index.ts:171-172,221` (`/revenue`): both get
  the same exclusion + separate Play count, with tests (round 2 #5).
- The paid-but-no-row alert (`_shared/payment_alert.ts`) is reused: a webhook event of type
  `INITIAL_PURCHASE`/`RENEWAL` whose mirror ends with no active row -> critical alert.

## 5. Client (mode `play_billing`; modes `razorpay` and `none` byte-identical, pinned by the existing tests)

- **PurchaseMode getters.** `showsPurchaseUi` becomes `razorpay || playBilling` (every upgrade affordance comes back on
  Android); `showsRazorpay` stays `razorpay` only (so `openCheckout`'s guard still blocks Razorpay in `play_billing`);
  `showsPlayBilling` gets its readers. New `showsWebLinks` = `razorpay` only. **Rule (round 1 #4): every place that
  draws a Razorpay-only thing (an `AppConstants` price, the promo box, the stacking line, a website link) branches on
  `showsPlayBilling` / `showsRazorpay` / `showsWebLinks` FIRST, never on `showsPurchaseUi` alone.** Reader audit
  (29 lines, measured 2026-11-23 with `grep -rn "showsUpgradeAffordance()\|showsPurchaseUi" lib`):

| Reader (file:line) | Today when true | In `play_billing` |
|---|---|---|
| `paywall_sheet.dart:180` default subtitle | "Upgrade to PRO …" | same text (no price): fine |
| `paywall_sheet.dart:199` `paywall_unavailable_shown` | not logged | not logged; add `paywall_play_shown` when the Play body renders |
| `paywall_sheet.dart:391` restore failure | snackbar | the Play body owns its status line: branch on `showsPlayBilling` first |
| `paywall_sheet.dart:419` build | Razorpay body with `AppConstants` prices (`:432-433`), promo box | **branch `showsPlayBilling` -> `PaywallPlayBody` before `:419`** |
| `paywall_sheet_phase_variant.dart:23` | own sheet with `₹349 / ₹2999 (save 28%)` (`:160`) | **routes to `showPaywallSheet(feature: 'Phases 2-12')` like `none`** (condition becomes `!showsRazorpay`) |
| `pro_pill_button.dart:49,54,102` | 'GO PRO', opens paywall | fine |
| `pro_locked_overlay.dart:173` | 'Upgrade to PRO' | fine |
| `home_provider.dart:515` expiry banner | amber `<7d`, red lapsed | **wrong for a renewing Play row**, see the banner bullet below |
| `nutrition_provider.dart:965`, `ai_coach_provider.dart:846,1257`, `prediction_card.dart:39`, `plan_expired_card.dart:267` (`PurchaseCopy` `purchaseUi:`) | "… upgrade to PRO" / "Upgrade in Profile -> Subscription" / "Deploy … go PRO" | fine (no price, no web) |
| `compact_header.dart:271`, `input_bar.dart:275,316`, `status_pill.dart:65,82,87` | upgrade link / 'UPGRADE' | fine |
| `weekly_report_card.dart:70,110` | 'Upgrade for weekly reports' | fine |
| `subscription_section.dart:194` | upgrade chip -> paywall | fine; the section also gets "PRO until" + manage link (below) |
| **`profile_content.dart:477`** | **'icanbefitter.com — Visit the website' row** | **must NOT show (steering): condition becomes `showsWebLinks`** |
| `phase_roadmap_screen.dart:185`, `preview_workout_screen.dart:234` | 'UPGRADE TO PRO →' | fine |
| *outside the two getters (round 2 #4):* | | |
| `shareable_card.dart:65` QR code | `AppConstants.appUrl` (`https://www.icanbefitter.com`) | QR points at the Play listing `https://play.google.com/store/apps/details?id=com.icanbefitter.icanbefitter` when `!showsWebLinks`. **This also affects the already-built `none` +50**; it is fixed here for +51 and every later build (+50 cannot change) |
| `delete_account_screen.dart:315` | "Your Razorpay payment receipts …" | Play variant: "Google Play keeps your purchase receipts."; `:145,163` `razorpay_cancel_failed` copy unchanged (web only) plus a Play cancel-failed message |
| `subscription_section.dart:109` | `RENEWS <date>` for every non-trial plan | `RENEWS` only when `pro_auto_renews`, else `EXPIRES` |
| `profile/screen.dart:256` `_onManageSubscription` | "no self-service, contact support" sheet | Play row -> Play manage link |

  The two `AppConstants` price readers outside these (`subscription_service.dart`, `app_constants.dart`) are
  Razorpay-path only (re-checked in U5). Test: render the paywall, the phase variant and Profile in `play_billing`
  with a fake store and find no `₹349`, `2999`, `349`, `save 28%` or `icanbefitter.com`; the same check on the share
  card and the delete-account screen.
- **Two Google accounts on one AVYA account (round 2 #10):** RevenueCat keeps one entry per product, so a second
  same-product purchase would be invisible. Covered by the already-PRO rule: any active paid row (Play included) hides
  the buy buttons, so a second purchase cannot start from the app.
- **Identity (`lib/core/services/play_billing_service.dart`, new, the only importer of `purchases_flutter`).**
  `configure` once after a session exists with `appUserID = uid` (`PurchasesConfiguration(<key>)..appUserID`); on a
  user change `logIn(newUid)`; on sign-out `logOut()` (wired at `auth_provider.dart:979` `signOut` and the
  `_onUserChanged` path). `logIn` / `logOut` are fire-and-forget (sign-out tears Hive down first, `auth_provider.dart:979`)
  and wrapped: `logOut` throws on an anonymous RevenueCat user (to verify in U0), which is logged, never surfaced.
  The buy buttons are DISABLED while a `logIn` is in flight. Before `purchasePackage` it re-reads `Purchases.appUserID`
  and refuses unless it equals the current Supabase uid AND the Hive owner (`auth_hive_owner_agreement`); no session ->
  no purchase UI (round 1 #13). The public key
  is `AppConstants.revenueCatGoogleKey = String.fromEnvironment('REVENUECAT_GOOGLE_API_KEY')` (const, per the
  2026-11-20 P1), `.env` + `.env.example`. Empty key in `play_billing` -> the sheet shows the unavailable body and logs
  `play_billing_key_missing` (no crash).
- **The Play paywall body (`lib/shared/widgets/paywall_play_body.dart`, new; still inside `PaywallSheet`, rule 7).**
  States: loading (skeleton) -> offerings loaded (two plan cards with `StoreProduct.priceString` and the period,
  never `AppConstants`; yearly-saving line computed from the two store prices or omitted) -> purchasing -> pending
  (Play `PENDING`: "Payment pending. PRO unlocks once Google confirms it.") -> confirming (poll `revenuecat-sync`, then
  `verifyFromServer(force: true)`, Razorpay poll constants from `payment_timing.dart`) -> done, or error with retry.
  **Same Google account, other Avya account (round 1 #13):** with transfer behaviour "keep with original App User ID"
  (section 9 step 3), Google refuses a second purchase ("already subscribed") or RevenueCat does not grant it to the
  new uid. The body maps that error to its own state: "This Google account already has PRO on another AVYA account.
  Sign in with that account, or manage it in Google Play." plus the manage link. No restore call.
  Offerings fail to load -> error state with retry, no price shown. User cancel -> back to the cards, no telemetry
  error. Benefits list, MAYBE LATER and RESTORE stay. No promo box (percent codes are web-only), no stacking line.
- **Already PRO.** On open the sheet reads `subscriptionInfoProvider` (server-verified; no `revenuecat-sync`
  call on open, round 2 #7). Active paid row (any source, `plan != referral_trial`) -> "PRO until <date>" (IST date), no plan cards, no buy
  button, and for a Play row a MANAGE IN GOOGLE PLAY link
  (`https://play.google.com/store/account/subscriptions?sku=avya_pro&package=com.icanbefitter.icanbefitter`). A
  `referral_trial` user may buy; the sheet says the subscription starts today (Play cannot start later; no stacking on
  Android).
- **Profile.** The subscription row reads "PRO until <date>" for every source, plus the manage link for a Play row.
  `verify-subscription` and `refreshFromSupabase` return / read `store`, `auto_renew` and `store_expires_at` (additive
  fields; old clients ignore them). Local keys are NEW names `pro_store` and `pro_auto_renews` (NOT `auto_renew`:
  `ai_snapshot_builder.dart:1597` already reads a config key `auto_renew` for the coach snapshot; round 2 #3).
  A third key `pro_store_expires_at` holds the true store expiry for DISPLAY (round 3 #2). `writeSubscriptionState`
  gains three OPTIONAL named params `store`, `autoRenews`, `storeExpiresAt`, default `null` meaning "not a Play row:
  DELETE the key". So the 10 existing non-Play callers compile unchanged and clear the keys on every write
  (`razorpay_service.dart:484,617,864,934,1046`, `dev_panel_screen.dart:222,233`, `simulation_service.dart:122`, tests
  `subscription_expiry_banner_behavioral_test.dart:131`, `state_changed_hook_test.dart:67,80,93`,
  `test/sim/lt_journey_plan_export.dart:199`), and only `refreshFromSupabase` (`:942`) and `verifyFromServer`
  (`:1070`) pass server values (round 3 #3). The signature line keeps `Future<void> writeSubscriptionState({`
  (source-grepped by `subscription_expiry_banner_test.dart:117`). The keys are written right after `isPro` /
  `expiresAt` / `plan` in the same sequential `MigratedKey.write` block (not one atomic `putAll`);
  `_downgradeLocally` deletes them; all three are registered in `UserConfigMigrator.userScopedKeys`
  (`user_config_migrator.dart:54`). Gating keeps using `expiresAt` (= `end_date`); every date STRING ("PRO until",
  `RENEWS`/`EXPIRES`, the already-PRO sheet) shows `pro_store_expires_at` when set, else `expiresAt`, so the 3-hour
  window never moves a shown date to the next IST day (a 21:00-23:59 IST expiry would otherwise read one day late).
  The `ai_snapshot_builder.dart:1597` `auto_renew` read has NO writer in `lib/` or `supabase/functions/` (always
  false today; round 3 #7): U5 points it at `pro_auto_renews`, with its test.
- **Manage subscription.** `profile/screen.dart:256` `_onManageSubscription` (today: "contact support" sheet) opens the
  Play manage link for a Play row; other rows keep today's sheet. `subscription_section.dart:109` prints `RENEWS`
  for every non-trial plan: it prints `RENEWS` only when `pro_auto_renews` is true, else `EXPIRES` (round 2 #4).
- **Expiry banner and lapse (round 1 #5, round 2 #1).** `SubscriptionService.expiryBannerSeverity` (pure) gains the
  input `renewsAutomatically` (read from `pro_auto_renews`): true -> no amber banner. There is NO client grace and NO
  sync at expiry: `isPro()` is synchronous (`subscription_service.dart:358`) and the server gates have no grace, so a
  client-only grace would disagree with `ai-proxy`. The 3-hour renewal window is in the row itself (section 4), so the
  client, the banner and every server gate see the same `end_date`. The red lapsed banner and `PlanExpiredCard`
  therefore show only for a real lapse.
- **Restore.** RESTORE = `revenuecat-sync` then `verifyFromServer(force: true)`. No `Purchases.restorePurchases()` call
  (it would move purchases between our accounts under some RevenueCat settings; the account is the identity).
- **Copy.** All new strings in `PurchaseCopy`, Wardroom voice + psychology-pass review before U5 is final; no web /
  website mention, no outside price (Play steering rules).

## 6. `/build-apk` change

`.claude/commands/build-apk.md`: accept `--purchase-mode play_billing`; for it, REQUIRE `REVENUECAT_GOOGLE_API_KEY` in
`.env` to be present and to start with `goog_` (else refuse), pass both defines, and record the mode in the
`built_versioncodes.json` entry. `--bundle` still requires `--purchase-mode`. The test that pins the refusal today is
updated to pin the new rule (both directions mutated).

## 7. Units (inline, in order)

| Unit | What | Files (main) |
|---|---|---|
| U0 | Verify F12 against RevenueCat docs + one sandbox `GET /v1/subscribers/<founder uid>` (secret key set by the founder 2026-11-23) and one sandbox defer on a license-tester subscription (call shape, response codes, what Google does to a test subscription, and to a CANCELLED-but-unexpired one: if Google refuses it, `auto_renew = false` falls back directly instead of claiming, decided and written here at U0, round 6 #4); record shapes as fixtures | `supabase/functions/_shared/testdata/revenuecat_customer_*.json` |
| U1 | Migration (section 3, incl. `store_reward_deferrals`, `store_reward_fall_back`, `grant_referral_days_direct` + the `grant_referral_days` branch) + local docker rehearsal + SQL tests | `supabase/migrations/<minted>_play_subscriptions.sql`, `test/sql/…` |
| U2 | `_shared/revenuecat_mirror.ts` + Deno tests | `_shared/` |
| U3 | `revenuecat-webhook`, `revenuecat-sync`, `revenuecat-reconcile` (incl. the defer drain) + Deno tests; `timingSafeEqual` imported | `supabase/functions/revenuecat-*` |
| U4 | Reader changes: `expiry-reminder`, `redeem-referral`, `delete-account`, `verify-subscription` additive fields | those EFs |
| U5 | Client: getters, `PlayBillingService`, `PaywallPlayBody`, already-PRO, Profile, restore, copy | `lib/core/…`, `lib/shared/widgets/…`, `lib/features/profile/…` |
| U6 | `/build-apk` + docs: ADR-0022 consequences, `payment.md`, `subscription.md`, naming glossary, `.env.example`, CRON_REGISTRY, SECRET_INVENTORY, SoT registry (`subscription_state` gains the Play writer; new concept `play_subscription_mirror`), CLAUDE.md Payments row | docs |

## 8. Tests (rule 21: each fails without its change; each mutated once, the record says what and how many reddened)

- T-SQL1 (local docker): on a copy of today's rows, the three changed functions return/write exactly what the old
  bodies did (old body in `BEGIN … ROLLBACK`, pitfall row "run it against the code it REPLACES"), including
  `process_referral_conversions` run with a Play fixture present. T-SQL2: a PRODUCTION Play row is "paid" for both
  referral functions, a SANDBOX one is not; `grant_referral_days` with an active Play row inserts one `pending`
  deferral row and leaves every `subscriptions` row byte-identical. T-SQL3: `upsert_play_subscription` runs (the non-partial unique index is the arbiter), returns
  `stale_read` for an older `read_at` (two calls with inverted finish order), and is not callable by `authenticated`.
- T-MAP (Deno, table-driven over U0's real fixtures): active monthly, active yearly, cancelled-but-not-expired
  (auto_renew false, still active, `cancelled_at` NULL), billing issue in grace, expired, refunded (and a later read of
  the same refunded chain stays cancelled), refund then a NEW purchase of the same product, resubscribe same product
  after expiry, monthly -> yearly -> monthly on ONE row (`plan` follows `product_plan_identifier`), unknown plan id -> no write +
  alert, paused / on hold, sandbox, unknown product, non-Play store ignored.
- T-WH: missing secret -> 500 and no write; wrong header -> 401; duplicate event id -> one ledger row, mirror still
  runs; switch off -> 200 and no `subscriptions` write; uid with no users row -> no RevenueCat call; mirror failure ->
  503; TRANSFER -> both uids + alert.
- T-WH (more): unknown uid -> ledger row with `user_id` NULL, no raw id stored; payment-log-safety list includes the
  three RevenueCat functions.
- T-SYNC: JWT uid only (a body uid is ignored); `consume_quota` called before any RevenueCat call; quota RPC error ->
  503 and no RevenueCat call (fail closed); same response shape as `verify-subscription`.
- T-REC: selects only the window and the 24-hour stale rule; bounded; telemetry row written.
- T-READERS: expiry-reminder skips a user whose latest row is a renewing Play row, keeps a Razorpay row, keeps a Play
  row with `auto_renew = false`, handles a renewing Play row plus a later trial row; redeem-referral rejects a
  PRODUCTION Play subscriber; delete-account calls cancel THEN delete, skips delete when cancel fails, still deletes
  the account on either failure, and runs with the mirror switch OFF; digest MRR excludes Play rows.
- Dart: resolver getters truth table; `PlayBillingService` refuses a uid mismatch (fake `Purchases` seam); the Play
  body never reads `AppConstants.*PriceInr` (literal inventory test extended) and renders the fake store's
  `priceString`; already-PRO shows the date and no buy button; trial user sees the cards; pending state unlocks
  nothing; the same-Google-account error state; buy buttons disabled while `logIn` is in flight; modes
  `razorpay`/`none` unchanged (existing `paywall_mode_none_behavioral`, `purchase_surfaces_mode_none`).
- Dart (round 1 #4/#5, round 2 #3/#4): `play_billing` renders of the paywall, the phase variant, Profile, the share
  card and the delete screen contain no `₹349`, `2999`, `save 28%` or `icanbefitter.com`; `expiryBannerSeverity` gives
  none for a renewing Play row at 3 days left and amber for `pro_auto_renews = false`; `writeSubscriptionState` from the
  Razorpay path resets `pro_store` / `pro_auto_renews`; `_downgradeLocally` deletes them; a second account on the same
  device never reads the first account's values; `RENEWS` vs `EXPIRES`.
- T-MAP (rounds 2-3): at `now = E + 1 h` with the renewal not posted, a renewing row stays `active` with `end_date = E
  + 3 h`; at `E + 4 h` it is `expired`; the window never applies with `unsubscribe_detected_at` or a billing issue
  set; a refund of the CURRENT period cancels; a refund of an old period does not cancel a later purchase (real U0
  fixture). T-SQL: `start_date` stays at the chain's first purchase across two renewals and resets after an expiry
  + resubscribe; `grant_referral_days` with an expired trial + an active Play row queues a deferral, no trial row.
- Dart (round 3 #2/#3): a Play expiry at 21:30 IST shows the same IST date in "PRO until" / `RENEWS`; the 10 non-Play
  callers leave all three keys deleted.
- T-SYNC (round 3 #6): `bad_result` -> 429 `rate_limit_unavailable`, no RevenueCat call.
- T-READERS (round 3 #8): two Play rows, one cancel fails -> no `DELETE /subscribers`, account still deleted.
- T-DEFER (v5-v7): drain 2xx -> `applied` + mirror ran; 4xx with the subscription gone -> `fell_back` and a trial row in
  the same transaction; 4xx with it active -> `needs_check` + alert; claim updating 0 rows -> no POST; switch OFF -> no drain; the POST path carries `avya_pro`,
  never `avya_pro:yearly`; `store_reward_fall_back` on an `applied` row -> `noop`, nothing written; the table and the
  function are not reachable by `authenticated`. v6/v7 (rounds 4-5): a run holding a stale read cannot fall back
  another run's `in_flight` row (token mismatch -> `noop`, no trial row); marks with a wrong token write nothing; a
  second reward for the same user is skipped while one is in flight; timeout -> `needs_check` at once and NO later run
  POSTs it again or marks it `applied` (a `SUBSCRIPTION_EXTENDED` ledger row for the user changes nothing); `in_flight`
  past 1 h -> `needs_check`; 2xx with the mirror throwing -> still `applied`; 4xx + re-read failure -> `pending`; a uid
  with no `users` row gets no GET and no POST; two fall-backs stack (end = now + d1 + d2); renewal window and grace
  -> `pending`; 429 -> `pending`; the stall alert fires with the switch OFF; a fall-back hitting `55P03` leaves the row
  unchanged; the wrapper with `p_days = 0` and a Play row raises 22023 (not 23514); `fall_back(id, token)` resolves a
  `needs_check` row; `grant_referral_days_direct` equals today's body (T-SQL1 runs the old body in `BEGIN …
  ROLLBACK`).
- T-SYNC (round 2 #7): `consume_quota` called with the 4-argument signature; RPC error -> 429
  `rate_limit_unavailable`; `-1` -> 429 `rate_limited`; neither calls RevenueCat.
- T-READERS (round 2 #5/#6): admin MRR and Telegram `/revenue` exclude Play rows and print their count;
  delete-account cancels a paused (`expired`) Play row too.
- build-apk pin: `play_billing` accepted with a `goog_` key, refused with no key, refused with a key not starting
  `goog_` (that clause mutated on its own).

## 9. What the founder does (never paste a secret in chat)

Steps 1-5 DONE 2026-11-23 (credentials and Google notifications green, test notification received 14:55 UTC;
"Track new purchases from server-to-server notifications" left OFF). Step 6: the key is in the VPS `.env`; the
laptop `.env` is the founder's. NEW step 8: Play Console > `avya_pro` > yearly base plan price -> Rs 3,499 (Q5).


1. RevenueCat > Project settings > API keys: create a **secret** key (v1). Put it in Supabase Dashboard > Edge
   Functions > Secrets as `REVENUECAT_SECRET_KEY`.
2. Make a long random value yourself (a password manager). Put it in Supabase secrets as `REVENUECAT_WEBHOOK_AUTH`,
   and the SAME value in RevenueCat > Integrations > Webhooks > Authorization header. Webhook URL:
   `https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/revenuecat-webhook`. Events: production AND sandbox (testers
   are sandbox until launch).
3. RevenueCat > Project settings > **Transfer behaviour: "Keep with original App User ID"** (stops a Play purchase
   moving between two of our accounts on the same Google account).
4. Finish "Can validate Google Play subscription purchases", then connect Google developer notifications (RTDN topic)
   in RevenueCat, so cancellations/refunds arrive in minutes, not on the next poll.
5. Play Console > License testing: add the tester Gmail accounts.
6. Put `REVENUECAT_GOOGLE_API_KEY=goog_…` into the laptop `.env` (public key; I add it to the VPS `.env`).
7. Say go, separately, for: the migration apply; each Edge Function deploy; setting `ENABLE_PLAY_BILLING_MIRROR=true`;
   the version bump to +51; `/build-apk --bundle --purchase-mode play_billing`.

## 10. Rollout and rollback

Order: U1 migration apply (go) -> U3/U4 deploys with the switch OFF (go each) -> founder steps 1-4 -> RevenueCat "Send
test event" -> `subscription_events` row with `outcome='switch_off'` -> switch ON -> sandbox `GET` via
`revenuecat-sync` for the founder uid -> +51 bump + bundle -> internal testing -> license-tester purchase.
Rollback: unset `ENABLE_PLAY_BILLING_MIRROR` (server stops writing; existing Play rows keep their end dates) and
release the `none` build. The migration columns/tables stay. The migration's ROLLBACK block restores the three
changed live bodies (`redeem_referral_atomic`, `process_referral_conversions`, `grant_referral_days`) and drops the
new functions (`grant_referral_days_direct`, `store_reward_fall_back`, `upsert_play_subscription`; round 5).
Reward rows, runbook (round 4 #5, round 5 P3-8): with the switch off, `grant_referral_days` still queues rewards for
users with an active Play row and the stall alert fires after 24 h. `pending` rows: `select store_reward_fall_back(id,
NULL) from store_reward_deferrals where status = 'pending'` (each becomes a normal trial-days reward). `needs_check`
(or a stuck `in_flight`) row: open the user's RevenueCat customer page; if the defer shows in the expiry history ->
`update store_reward_deferrals set status = 'applied' where id = <id> and claim_token = <token> and status in
('needs_check', 'in_flight')` (round 6 #2); if not -> `select store_reward_fall_back(<id>, <token>)`. Read `<id>`,
`<token>`, `days` and `claimed_at` with `select id, claim_token, days, claimed_at from store_reward_deferrals where
status in ('needs_check', 'in_flight')`. A `needs_check` row does not block later rewards for the same user, so with
several rows on one customer, count the deferred days in the expiry history after `claimed_at` against each row's
`days`. Never re-send a defer by hand without that check.
**Before launch this is safe** (testing accounts only). **After launch it is not a free rollback:** with the mirror
off, renewals are not mirrored and paying subscribers lose PRO at their next `end_date` (round 1 #9). So after
launch the switch is turned off only on a founder decision, with the paying-row count read first.

## 11. Done when (OI-519)

A license tester on the +51 internal build buys monthly: the row appears through the webhook (and, with the webhook
switched off for one test, through `revenuecat-sync`), the gate unlocks PRO on the phone and on web; a renewal (Play
test renewals run every few minutes), a cancellation (stays PRO to end_date, no renew push), a refund from Console
(PRO ends at once), restore on a second phone, and the already-PRO screen are each shown on the device and in the row;
the +51 AAB built through `/build-apk --purchase-mode play_billing`. Each step is a row in the device walk.

## 12. Founder answers (2026-11-23)

- Q1. Referral days for a Play subscriber: **B, Google defer** (section 3 `grant_referral_days`, section 4 item 4).
  Founder asked whether Apple gets the same: Apple's extension API is limited (2 a year, 90 days, documented for
  outages); the Apple build chooses between it and promotional offers.
- Q2. Sandbox purchases grant PRO on the real tables: **yes** (never paid for referral rewards).
- Q3. Play intro offer / free trial in +51: **none**.
- Q4. Admin dashboard, Telegram `/revenue` and founder digest: **one Play-vs-web count; MRR stays web-only**.
- Q5. Play price: **Rs 449 / month, Rs 3,499 / year** (founder changes the yearly base plan in Console, section 9).
- Q6. Secret key: **set** (founder step 1 done).

## 13. Review plan

Context-blind Sonnet reviewers in sequence, each on the post-previous-round plan (rounds 1-3 on v1-v3, round 4 on
the v5 defer change, round 5 on v6, round 6 on v7; section 17), each briefed with
`docs/agent_brief_preamble.md`, allowed commands listed, verifying sections 1, 3, 4 and 5 at file:line and against live
SQL (read-only). Lenses from `docs/audit/LENS_REGISTRY.md`: payment, writer/reader, auth/identity, idempotency and
ordering, secrets, migration safety, copy, test mutation. Then code -> gate loop + CI -> `/code-review` B-pass ->
`/hermes-pass` -> record -> `land_pr.sh`.

## 14. Review round 1 dispositions (context-blind Sonnet, 2026-11-23; each finding checked by me before folding)

| # | Sev | Finding | Checked | Disposition |
|---|---|---|---|---|
| 1 | P1 | arbiter `store_original_transaction_id` undefined; Google order id changes per renewal | v1 map keyed by product id | key is `(user_id, store_product_id)`; txn id informational (sections 2, 3) |
| 2 | P1 | ON CONFLICT cannot infer a partial index without the predicate | Postgres rule | predicate repeated; T-SQL3 (3) |
| 3 | P1 | sync rate limit has no row to compare for free users; GET creates customers | `consume_quota` exists (`daily-snapshot/index.ts:199`), `spendsQuotaPerCall` (`supabase_service.dart:405`) | quota fail-closed + client calls only with a reason (4.2) |
| 4 | P1 | Razorpay body / phase-variant prices render once `showsPurchaseUi` is true | `paywall_sheet.dart:419-433`, `paywall_sheet_phase_variant.dart:23,160` | branch-first rule + reader audit table + no-price test (5) |
| 5 | P1 | expiry banner and lapse wrong for a renewing Play row | `home_provider.dart:515-523` | `renewsAutomatically` input, sync-before-downgrade, grace (5) |
| 6 | P2 | ordering guard needs read-issue time and a return status | — | `store_read_at` = GET issue time, returns `written`/`stale_read` (3, 4) |
| 7 | P2 | shared reducer selects only `user_id, end_date` | `_shared/subscription.ts:236-247` | expiry-reminder gets its own select; shared helper unchanged (4) |
| 8 | P2 | sandbox rows paid for referrals | live bodies | paid = PRODUCTION only (3) |
| 9 | P2 | rollback OFF strands payers; delete-account must not depend on the switch | — | stated pre/post launch; delete leg independent (4, 10) |
| 10 | P2 | delete-account order/timeout/retention | `delete-account/index.ts:242-293` | cancel then delete, 10 s, no payload column (3, 4) |
| 11 | P2 | ledger FK on unknown uid; log safety list | `payment_log_safety_writer_to_reader_test.dart` exists | user_id NULL, no raw id, list extended (3, 4) |
| 12 | P2 | Play referrer reward worthless | live `process_referral_conversions` | surfaced in Q1 (3, 12) |
| 13 | P2 | same Google account on two Avya accounts; logOut throws; logIn in flight | — | error state, wrap, disable buttons (5) |
| 14 | P2 | mapping edge cases | — | precedence list + fixtures (4, 8) |
| 15 | P2 | reconcile gap up to 7 days | — | 24-hour stale rule, worst case stated (4) |
| 16 | P3 | digest MRR uses 349/2,999 | `founder_digest_content.ts:226` | Play rows excluded from MRR, counted separately; Q4 (4, 12) |
| 17 | P3 | `record_paid_subscription` stacking base | live body | noted, unchanged (3) |
| 18 | P3 | function rollback bodies; RLS exposes store_* | — | ROLLBACK block in migration; RLS note (3) |
| 19 | P3 | missing tests | — | added (8) |
| — | (mine) | `profile_content.dart:477` website row shows whenever selling | read | `showsWebLinks` (5) |

## 15. Review round 2 dispositions (fresh context-blind Sonnet, 2026-11-23; each finding checked by me before folding)

| # | Sev | Finding | Checked | Disposition |
|---|---|---|---|---|
| 1 | P1 | client sync-before-downgrade + grace cannot be built (`isPro` sync; server gates have no grace; downgrade wipes `plan`) | `subscription_service.dart:358,1198-1201` | mechanism DELETED; 3-hour renewal window in the row `end_date`, read identically by client and server (4, 5) |
| 2 | P1 | refund precedence contradicts rebuy | — | `refunded_at >= latest purchase_date`; real U0 fixture first (4) |
| 3 | P2 | `auto_renew` Hive key collides; write not atomic; other writers must reset; downgrade must delete | `ai_snapshot_builder.dart:1597`, `subscription_service.dart:296-298` | `pro_store` / `pro_auto_renews`, required params, deleted on downgrade (5) |
| 4 | P2 | share-card QR, delete-screen Razorpay copy, RENEWS label, manage sheet | `shareable_card.dart:65`, `delete_account_screen.dart:315`, `subscription_section.dart:109`, `profile/screen.dart:256` | audit table rows + tests (5, 8) |
| 5 | P2 | admin + Telegram MRR at web prices | `admin-dashboard-data/index.ts:43-44`, `telegram-admin-bot/index.ts:171-172,221` | Play excluded + counted (4) |
| 6 | P2 | delete-account cancels only active Play rows | — | every non-refunded Play row (4) |
| 7 | P2 | `consume_quota` has 4 args; 429 not 503; limit-hit UX; sheet-open calls | live `consume_quota(p_user_id, p_quota_key, p_window_start, p_limit) -> integer` | fixed (4) |
| 8 | P3 | partial-index arbiter trap | `supabase/migrations/CLAUDE.md` | non-partial unique index (3) |
| 9 | P3 | `timingSafeEqual` already exported | `cron_auth.ts:83` | import, not move (4) |
| 10 | P3 | two Google accounts on one AVYA account | — | covered by the already-PRO rule, stated (5) |

## 16. Review round 3 dispositions (focused context-blind Sonnet on the v3 changes, 2026-11-23; each checked by me)

| # | Sev | Finding | Checked | Disposition |
|---|---|---|---|---|
| 1 | P1 | the +3 h window was only an `end_date` adjustment; the status test on raw `E` would expire the row inside the window | plan text | window moved INTO the status test (rule 2, section 4); fixture at `E + 1 h` |
| 2 | P2 | +3 h moves the shown date to the next IST day for 21:00-23:59 expiries | `subscription_section.dart:15-16`, `subscription_service.dart:297` | `pro_store_expires_at` for display only (5) |
| 3 | P2 | required params break 12 production + test callers | `grep -rn "writeSubscriptionState(" lib test` | optional params, null = delete; callers listed (5) |
| 4 | P2 | `start_date = original_purchase_date` anchors referrals to the first-ever purchase | live `process_referral_conversions` | `start_date` = chain start via the upsert CASE (3) |
| 5 | P3 | precedence (1) text contradicted the rebuy rule | plan text | mapping rewritten once (4) |
| 6 | P3 | `bad_result` branch; call budget | `create-razorpay-order/index.ts:148-189` | added; budget stated (4) |
| 7 | P3 | `auto_renew` key has no writer | grep: only `ai_snapshot_builder.dart:1597` | pointed at `pro_auto_renews` in U5 (5) |
| 8 | P3 | delete ordering with two Play rows | — | delete customer only when every cancel succeeded (4) |

Round 3's checks also confirmed: the non-partial index and its `ON CONFLICT` are valid and no live row can violate it;
the reconcile window contains every window read; `expiry-reminder` is unaffected by +3 h; the QR and delete-account
rules are right. **Convergence:** round 3 found one P1, inside the round-2 change, and its fix is a precise rule
change (no new mechanism). I am stopping the plan rounds here; the code gets the B-pass and the hermes pass, both
required by the tier (superseded by v5: section 17).

## 17. v5 change and review round 4

v5 folds the founder answers. Only Q1 = B changes the mechanism: the `grant_referral_days` branch, the
`store_reward_deferrals` table, `store_reward_fall_back`, and the drain in `revenuecat-reconcile`. Round 4 (one
context-blind Sonnet, focused on those parts and their seams: the referral functions, the mirror, the webhook
ledger, delete-account) runs on v5 before U0. Its dispositions go below; the record carries the final round count (header).

### Review round 4 dispositions (focused context-blind Sonnet on v5, 2026-11-23; each checked by me)

| # | Sev | Finding | Checked | Disposition |
|---|---|---|---|---|
| 1 | P1 | fall-back accepted `in_flight` with no run token; an overlapping run could fall back a row whose defer then succeeds (days twice) | plan text | `claim_token`; every mark compare-and-set; fall-back takes the caller's token (3, 4) |
| 2 | P2 | `SUBSCRIPTION_EXTENDED` alone is not proof: Google sends it for its own deferred renewal charge; two rows per user; late webhook | RevenueCat Google renewal-extensions doc (fetched by me: "Deferred renewal charge: SUBSCRIPTION_EXTENDED, followed by RENEWAL or BILLING_ISSUE") | ledger `expiration_at_ms` + expiry test; one in flight per user (partial unique index); `needs_check` re-checked 48 h; U0 records the event (4) |
| 3 | P2 | a drain GET for a deleted user recreates the RevenueCat customer; fall-back FK error | F12 (GET creates) | mirror guard before every call; fall-back `noop` without a `users` row (3, 4) |
| 4 | P2 | fall-back inserted a plain trial row, so two fall-backs overlap instead of stacking | live `grant_referral_days` stacks | fall-back runs `grant_referral_days_direct` (today's body) (3) |
| 5 | P2 | queued rewards wait silently with the switch off or the drain broken; stall watch reads only `referral_redemptions` | live `process_referral_conversions` stall watch | stall alert runs even with the switch OFF; rollback runbook line (4, 10) |
| 6 | P2 | inside the 3 h renewal window the drain would fall back while the real renewal is about to post | section 4 rule 2 | window -> leave `pending` (4) |
| 7 | P3 | 429 treated as a 4xx | — | 429 -> `pending` (4) |
| 8 | P3 | stale text: T-SQL3 "partial index", review count | plan text | fixed (8, header, 13) |
| 9 | P3 | `expiry_before` never read | — | read by the confirmation rule (4) |

Round 4 also confirmed: callers with no Play row are unchanged (no row lock in the new branch, NOWAIT retry loop and
advisory locks unaffected, queue INSERT rolls back with the caller); the defer endpoint, body and product-id rule
match RevenueCat's docs; no per-year cap on Google. Round 4 found a P1 inside the new mechanism, so round 5 runs on v6.
(v7 note: the fixes for #2 and #9 were later DELETED with the auto-confirm, see round 5.)

### Review round 5 dispositions (focused context-blind Sonnet on v6, 2026-11-23; each checked by me)

| # | Sev | Finding | Checked | Disposition |
|---|---|---|---|---|
| P2-1 | P2 | a `needs_check` row does not block later rewards, so a later reward's event confirms it falsely | plan text | auto-confirm DELETED (memory: remove the mechanism when rounds chase its symptoms); `needs_check` is resolved by hand (4, 10) |
| P2-2 | P2 | `expiry_before` under-specified (E vs E + 3 h) makes the rule unsatisfiable | section 4 rule 2 | column deleted with the auto-confirm (3, 4) |
| P3-1 | P3 | confirmation rule has no upper bound (renewal + Google extension) | — | deleted with the auto-confirm |
| P3-2 | P3 | re-read failure after 4xx unspecified | — | -> `pending` (4) |
| P3-3 | P3 | mirror before `applied` can strand a success | — | `applied` first, mirror best-effort (4) |
| P3-4 | P3 | grace case unspecified | — | only two outcomes act; grace -> `pending` (4) |
| P3-5 | P3 | per-run customer cache | — | fresh read per row (4) |
| P3-6 | P3 | claim predicate not written out | — | written out (4) |
| P3-7 | P3 | fall-back and `55P03` | live `grant_referral_days` uses `FOR UPDATE NOWAIT` | row unchanged, next run retries (3) |
| P3-8 | P3 | runbook covers only `pending` | — | `needs_check` / stuck `in_flight` recipe (10) |
| P3-9 | P3 | wrapper must validate `p_days` first | live body raises 22023 | validation first (3) |
| C1 | P3 | wrapper is `private.grant_referral_days` | live `pg_proc`: no public one | stated (3) |
| C2 | P3 | heading says three entry points | — | heading names the drain (4) |
| C3 | P3 | ROLLBACK block must drop the new functions | — | listed (10) |

Round 5 also confirmed: the token compare-and-set closes the two-run and webhook-vs-drain interleavings; no path ends
`fell_back` AND applied; the direct/queue split changes no caller (the retry loop catches only `lock_not_available`).
Re-review of the deletion (memory `feedback_re_review_a_design_deletion`): the hazard the auto-confirm guarded (a
timed-out defer that really applied) is still never re-sent and never lost: it is a `needs_check` row, alerted, and
resolved by hand. Round 6 (narrow) checks v7.

### Review round 6 dispositions (narrow context-blind Sonnet on v7, 2026-11-23; each checked by me)

| # | Sev | Finding | Checked | Disposition |
|---|---|---|---|---|
| 1 | P2 | T-DEFER still specified the deleted auto-confirm (contradicted its own v7 clause) | plan lines 479-482 (read by me; my v7 fold missed that clause) | stale clauses deleted (8) |
| 2 | P3 | runbook `applied` update had no status guard; token / ambiguity guidance | plan text | `and status in (...)`, token query, day-count rule (10) |
| 3 | P3 | fall-back compare-and-set not spelled out | plan text | first statement written out (3) |
| 4 | P3 | cancelled-but-unexpired subscription and defer | RevenueCat doc silent | measured at U0, rule decided there (7) |

Round 6 confirmed: no interleaving double-grants, loses days silently, or re-sends an unknown outcome; every state
has an exit; the runbook covers every non-terminal state. Its verdict was NOT CONVERGED on text only and it stated no
further round is needed unless the edit adds mechanism; the v8 edits are text and one written-out SQL guard, no new
mechanism. **Verdict: converged after 6 rounds.** The code still gets the B-pass and the hermes pass.

## 18. U0 findings (2026-11-23, RevenueCat docs downloaded as Markdown; fixtures doc-derived)

Sources: `revenuecat.com/docs/api-v1/customers.md`, `api-v1/transactions.md`,
`integrations/webhooks/event-types-and-fields.md`, `integrations/webhooks/sample-events.md` (fetched 2026-11-23).

| # | F12 item | Doc says | Plan change |
|---|---|---|---|
| 1 | `GET /v1/subscribers/{id}` creates a missing customer | "or creates a new customer if it doesn't exist"; 200 found, 201 created | none (the uid guard stands) |
| 2 | `subscriptions` key for a Google base plan | key = subscription id WITHOUT suffix (`avya_pro`), plan in `product_plan_identifier`, one entry = furthest-out purchase | **one Play row per user**; `plan` from `product_plan_identifier` (sections 2, 3, 4, 8) |
| 3 | entry fields | `expires_date`, `purchase_date`, `original_purchase_date`, `period_type`, `store` (`play_store`), `is_sandbox`, `unsubscribe_detected_at`, `billing_issues_detected_at`, `grace_period_expires_date`, `refunded_at`, `auto_resume_date`, `ownership_type`, `store_transaction_id` | none (mapping uses exactly these) |
| 4 | Google endpoints | defer `…/subscriptions/{product_identifier}/defer`; revoke `…/subscriptions/{product_identifier}/revoke`; cancel `…/subscriptions/{store_transaction_identifier}/cancel`; `DELETE /subscribers/{id}` | cancel path uses `store_transaction_id` (4) |
| 5 | webhook `product_id` | carries the suffix (`avya_pro:monthly`) | the webhook never reads it for the row key; the mirror re-reads REST |

Not checkable from docs, moved to the live steps: the real `GET` for a license tester (L2/L3, `revenuecat-sync` with
the switch OFF returns the mapped result without writing; its response is saved as a fixture and T-MAP re-run before
L4), the sandbox defer (L7), and the `purchases_flutter` API names (checked against the package source at U5). The
secret key lives only in the Edge secret, so no read from this machine is possible before a function is deployed.

## 19. U1 record (2026-11-23)

- Migration 182 `play_subscriptions` (number reserved by `mint_migration.sh`; live latest is 181).
  Generated from the repo bodies 159:89 / 160:61 / 160:129, whose md5(prosrc) equal live (457ffc0c, ee24b1f0, 7a166314),
  by count-asserted replacements, so every untouched line is verbatim. The ROLLBACK block carries the three bodies.
- Until the live apply it is the draft `docs/plans/2026-11-23-revenuecat-play-billing-51.migration-182-draft.sql`
  (precedent: `streak-freeze-restore-ownership-addendum-a.migration-draft-c1.sql`): Gate 14 (`check_migrations_applied.dart`)
  fails any file in `supabase/migrations/` without a ledger entry, and the entry only exists after the apply. At L1 the
  draft is copied BYTE-IDENTICAL to `supabase/migrations/182_play_subscriptions.sql` and committed with its ledger entry.
- Local proof `test/sql/play_subscriptions_local.sh` (docker `oi519-pgtest`, never a live host): cases N (no Play row) pass
  on the pre-182 AND the 182 database (T-SQL1); cases P1-P13 pass on 182; S1 (a held users row) gives 55P03 in under 2 s
  and leaves the deferral `pending`; mutants M1-M7 (Play branch, direct guard, job paid predicate, redeem sandbox, fall-back
  token, upsert stale guard, start_date chain) each fail a named case.

## 20. U2 record (2026-11-24)

- `supabase/functions/_shared/revenuecat_mirror.ts`: pure `mapCustomerToRows`, `fetchRevenueCatCustomer` (10 s timeout, one
  retry on 5xx / 429 / network), `mirrorRevenueCatCustomer` (UUID + users-row guard and secret check BEFORE any GET;
  `read_at` stamped before the GET), `supabaseMirrorDb` adapter (RPC `upsert_play_subscription`, deduped alert).
- `_shared/revenuecat_mirror_test.ts`: 23 tests (T-MAP table, switch, IO). Mutants: no renewal window, refund rule
  disabled, billing issue treated as renewing, `read_at` after the GET, user check after the GET: each fails 1-4 tests.
