# OI-341 Piece B2a: the server door, the switch-mismatch alarm, the replay window, and both flips (v4.3)

Branch `oi341-piece-b2-door`, from `main` `b8385b6c` (2026-10-20, after PR #133 / Piece B1).
Execution mode (CLAUDE.md 4.12.7): **inline, one worktree, one coordinator.**
Tier: **catastrophic** (payment writers + a new door on `create-razorpay-order`). This batch FLIPS
`ENABLE_SUBSCRIPTION_STACKING` and adds and flips `ENABLE_TRIAL_PURCHASE`, so it takes the **full x2 plan review**
(4.12.4), a B-pass and a hermes pass. No `ship_dark_build` tier.

**Review history and the SPLIT (CLAUDE.md 4.12.1).**
- Round 1 (on v1): 0 P0, 5 P1, 6 P2, P3s; all folded into v2 (section 7).
- Round 2 (on v2): 0 P0, 2 NEW P1, 4 P2, P3s (section 8).
- Its P1-A showed the unit was too large to ship in one order: the WEB client deploys on every merge to `main`
  (`vercel.json` `ignoreCommand`), so client copy merged with the server code would go live while the door is still
  shut. The unit is therefore SPLIT:
  - **B2a (this plan, branch `oi341-piece-b2-door`):** server only. The door, the switch-mismatch alarm, the switch log
    lines, the webhook alert timeout, the replay window for `payment.captured`, both flips, and the reconcile queries.
  - **B2b (its own plan and branch; AMENDED 2026-10-22: built BEFORE the live session, merged between steps 4a and 4b, see section 4 step 5):** the client. The paywall line, the checkout
    description, `estimatePaidEndDate` + the retry closure, the trial-409 copy, the EST clamp, `isReferralTrial`, and
    the copy constants. Old sections 2.5-2.7 move there verbatim as its starting point (section 9). It merges to
    `main` (web + APK) only AFTER B2a step 4a opens the door, so the line is true from its first deploy.
- Round 3 (on v3): 0 P0, 2 P1, 5 P2, 3 P3 (section 10). Both P1s were in the parts v3 had just added (the notes-based
  alarm, step 3(b)); v4 replaces the alarm with a database check, which a client cannot forge.
- Round 4 (on v4): **0 P0, 0 P1**, 4 P2, P3s; all plan-text, folded into v4.1 (section 11, `mechanical_only`).
  Rounds 3 and 4 are the two reviews of the post-split B2a plan (4.12.1): **converged**.

## 0. Founder decisions in force

- 2026-10-13: a referral-trial user may buy, and the paid cycle starts when the free days end (stacking).
- 2026-10-20 answers:
  - (2) keep "RENEW TO STAY PRO" on the banner;
  - (3) no Profile `TrialUpgradeDoor`;
  - (4) add **"Your paid plan starts when your free days end."** to the paywall and the Razorpay checkout description;
  - (5) server serialisation (done in B1);
  - (6) the first stacked purchase runs in **Razorpay test mode**. SUPERSEDED 2026-10-21, see below.
- 2026-10-21 answers (v4.2):
  - the server secrets hold the **live** key pair, and no test secret exists on the VPS. The live steps therefore run in
    **live mode**: small real payments with ONE dedicated **90%** promo code (allowed by
    `promo_codes_discount_pct_check` 1..90, migration 160:457; ₹34.90 monthly), with `max_uses` 5 and a short
    `valid_until` set for the record only (neither is enforced anywhere, OI-366; only `is_active` stops the code, step
    0 (c)), deactivated after step 4. The founder refunds each payment in the Razorpay dashboard; each row correction is its own
    go. The 76.7% break-even rule (OI-342) guards real customers' referral economics and does not bind tester purchases
    that are refunded;
  - the purchases are made on the **web app** (app.icanbefitter.com), assumed to carry the live key ID; no build is
    needed for B2a;
  - order (AMENDED 2026-10-22, founder order of 2026-10-21): B2a steps 1-3, 4a (door), the B2b merge, 4b (the stacked
    purchase through the new web client), refunds and corrections, then the next AAB. Before that `/build-apk`, the VPS `.env`
    `RAZORPAY_KEY_ID` must be the LIVE key ID (today it is `rzp_test_`, and the client opens checkout with its own key,
    `app_constants.dart:193`, so a test key against a live order would fail). Added to OI-348.
- Testing phase: the app is not live, and every account is a tester (CLAUDE.md section 1).

## 1. Facts (verified 2026-10-20 at `b8385b6c`; survey plus round-1 re-verification)

**Server door: `supabase/functions/create-razorpay-order/index.ts`.**
- `serve(async (req) => ...)` at :66 is an anonymous callback: no exported `handler`, no `import.meta.main`, no test
  file.
- Module-scope env reads at :45-48.
- The 409 guard (:97-119) reads the latest active unexpired row and answers `409 already_pro {current_plan,
  current_expires_at}` for ANY such row, a `referral_trial` included.
- The read's `error` is NOT checked (`const { data: existing } = ...`, :98). A failed read creates the order. It fails
  OPEN, a pre-existing double-payment hole.
- `verify_jwt` is false; the JWT is checked in-handler (:74-82). `runbook_deploy_verify_jwt_test.dart:58` pins it.
- No `blast_radius.yaml` entry of its own (it falls under the catch-all `supabase/functions/**`, platform).
- Orders set no expiry (:184-208): an order created while a door is open can be paid later.

**Subscription data.**
- `subscriptions.plan` is NOT NULL (migration 006:9). Live plan values are `monthly`, `yearly` and `referral_trial`
  (`admin-dashboard-data/index.ts:264-266`).
- `private.grant_referral_days` (159:104-117) inserts or extends the user's LATEST active row. A referrer's credit to a
  payer therefore extends the paid row, and a referrer with no paid row gets a `referral_trial` row, so referrers can
  buy under B2 too (intended).

**Writers (B1, live v26 / v30).**
- The ON path is `record_paid_subscription`. It stacks after the latest active end of any other row (161:105-111,
  `greatest(now, coalesce(max(end), now))`), so with no active row the ON end equals the OFF end, `now + days`.
- The servers compute their own base, so `stacks_after` from the door is informational (the client estimate and the
  order notes) and never an input to entitlement.
- `verify-payment`'s ON branch runs only when its pre-SELECT found no row (`verify-payment/index.ts:575`,
  `paymentSubRow === null && stackingOn`). In the normal flow the webhook writes first: the client polls for the row by
  payment id for 12 attempts (`razorpay_service.dart:733-745`) and calls verify-payment only after that (:816). So a
  normal payment proves only the WEBHOOK's ON path.
- The OFF branch logs nothing about the switch.

**Razorpay webhook rules** (docs: [FAQ](https://razorpay.com/docs/webhooks/faqs), [best
practices](https://razorpay.com/docs/webhooks/best-practices.md)):
- A 5-second response timeout, after which the event counts as unprocessed and is resent.
- Retries use exponential backoff "for 24 hours after event creation", and delivery is at-least-once.
- `razorpay-webhook` rejects an event whose `payload.created_at` is more than 300 s old (:340-350); that also applies to
  a stale `payment.authorized`.
- The comment at :334-339 (the age check is :340-347; round 3: it reads "Razorpay stamps each event (and every 24h retry) with a fresh top-level
  `created_at`") ASSUMES Razorpay re-stamps `created_at` on a retry. Nothing evidences it, and the docs' "from
  event creation" suggests it does NOT.
- The alert module awaits 2 round trips of up to 3 s each (`payment_alert.ts:30`), so the B1 failure 500 can take
  ~11 s (its own header).

**Client.**
- `razorpay_service.dart`:
  - `_pendingPlan` is set at :135 and reset in `_onUserChanged` (:63).
  - The order body is `{plan, promo_code?}` (:148-155).
  - The 409 `already_pro` is handled through `_handleAlreadyProResponse` (:408-425), and the caller then calls
    `onSuccess` (:172, and the catch path :205-225). A trial user's 409 is shown as "already PRO".
  - The checkout `'description'` is at :330.
  - `_computeEndDate(plan)` = `now + 30/365` (:674-679) is used at the optimistic write (:505), the poll fallback
    (:783), the verify fallback (:853) and as a TEAR-OFF `fallbackEndDate: _computeEndDate` (:957). Its type is
    `String Function(String plan)` (`payment_retry_attempt.dart:62, :93, :128, :150`), and the retry fires minutes
    later or after a restart.
- **Paywall:** `paywall_sheet.dart` `showPaywallSheet` (:22) has no PRO guard; it is reached from the Home expiry
  banner (`home_screen.dart:612`), the Profile subscription card and settings. The paywall's existing
  `ref.read(subscriptionServiceProvider).isPro()` (:340) is the DECISION path and must not be reused for copy.
- **`SubscriptionInfoData`** (`profile_provider.dart:343-362`) has `isPro`, `plan`, `expiresAt` and `isVerifying`.
  `refreshFromSupabase` (`subscription_service.dart:904-909`) stores the latest active row's `plan` verbatim, so a
  trial user's local plan is `'referral_trial'`. After a stacked purchase the paid row ends later and wins.
- **Banner:** `expiryBannerSeverity` (:1165-1175) is a pure function of days with no plan check. A trial user near the
  end sees "RENEW TO STAY PRO", and RENEW opens the paywall.
- **EST seal:** `_estSealDate` (`profile/screen.dart:242`) is a private static that reads `DateTime.now()` and
  back-computes `expiresAt - planDays`. For a stacked purchase that is the trial END, a future date.
- **Client retries:** `retryColdStart` (`supabase_service.dart:372-440`) retries 502/503/504 up to 3 times, and
  `supabase/functions/CLAUDE.md` reads a 503 as boot-broken.

**Two-row count readers.**
- `admin-dashboard-data:243` labels per-plan ROW counts (its comment: monthly+yearly+trial+other == active).
- `telegram-admin-bot` `cmdRevenue` (:197-215) counts rows per plan.
- Neither presents them as users. `referral_trial` contributes 0 to MRR.

**Referral timing.** A stacked purchase made DURING the trial has `start_date` = the payment instant, so the reward job
(159:245-250) qualifies it at once and credits the referrer at payment + 7 days, not about 14 days after joining as
documented today.

## 2. Design

### 2.1 One strict switch rule for both secrets

`_shared/subscription_stacking.ts` gains `isEnvExactlyTrue(name, env)`. `isStackingEnabled` and a new
`isTrialPurchaseEnabled` (`ENABLE_TRIAL_PURCHASE`) are thin wrappers over it, so neither switch can drift to a
different reading.

### 2.2 The door: `create-razorpay-order`

1. **Testable shape.**
   - `export async function handler(req)`; the tail is `if (import.meta.main) serve(handler)`.
   - The env reads move into the handler, so an import does no I/O.
   - A Deno harness on `postgrest_fake_fetch.ts` (Razorpay orders API faked).
   - The OFF recording is taken from the unmodified file (`git show origin/main:...`) BEFORE the restructure, run as a
     subprocess with a stubbed network (its module-scope `serve()` binds a server).
   - What it can honestly pin (round 2 P2-A):
     - the response status and body for no row, a trial row and a paid row;
     - the Razorpay order request and body;
     - the guard read's table and filters.
   - It does NOT pin the guard read's URL: the read changes from `order + limit 1 + maybeSingle` to one unlimited read.
     It also does not pin the read-error case, a deliberate behaviour change with its own test.
2. **ONE guard read, both switch states:**
   - `select plan, end_date where user_id = me and status = 'active' and end_date > now` (no `limit 1`, a user has
     few rows).
   - A read `error` answers **500** `{error: "Could not verify your subscription. Please try again.", error_code:
     "subscription_check_unavailable", request_id}` and creates no order.
   - 500, not 503, so the client's cold-start retry does not repeat it and the deploy smoke does not read it as
     boot-broken.
   - This is a deliberate change on the OFF path, the fix for the fail-open hole. It gets its own diagnose-doc and a
     test that fails without it.
3. **The decision, in code over the rows:**
   - **OFF** (`!(isTrialPurchaseEnabled() && isStackingEnabled())`, read once per request): any row gives 409
     `already_pro` with `current_plan` / `current_expires_at` from the row with the latest end, exactly today's
     answer.
   - **ON:**
     - any row whose `plan !== 'referral_trial'` gives 409 `already_pro`, with `current_plan` / `current_expires_at`
       from the latest-ending NON-trial row (round 2 P2-B). A paid user whose trial row ends later is therefore told
       they are PRO, not that an upgrade is unavailable;
     - otherwise `stacks_after = max(end_date)` over the rows (null when none);
     - the order is created as today, with the response adding `stacks_after` and the order `notes` adding
       `stacks_after` for dashboard reconciliation. Notes are never read back for entitlement (payment.md rule 1).
   - The door requires BOTH switches in its own isolate, so a door isolate never sells a trial purchase while it
     believes stacking is off. Writer isolates are handled by section 4.
4. **The OFF response and order notes carry NO `stacks_after` key** (golden-pinned).

### 2.3 Writer switch log line (both writers)

- At the top of the insert branch, after the switch is read once: `console.log(`[<fn>] stacking_switch=<on|off>
  payment_id=<id>`)`.
- It is log only: the response, the queries and the row are unchanged. The OFF golden tests assert requests and
  responses, not logs, so it does not disturb them (they are re-run to show it).
- It is the evidence for section 4: after a flip, every payment shows which state its isolate read.

### 2.4 Alert round trips shorter for the webhook (instead of v1's `waitUntil`)

- `reportPaymentRecordFailure` gains an optional `timeoutMs` (default 3000, so verify-payment is unchanged). The
  webhook passes **1000**.
- Worst case for the webhook failure arm: RPC failure plus 2 x 1 s.
- A 55P03 lock timeout (5 s) still exceeds Razorpay's 5 s. That is accepted and stated: a timeout is retried like the
  500, the SQL is idempotent, and the alert row is still attempted.
- `waitUntil` is dropped: it is unused in the repo, unverifiable on this runtime from here, and a non-awaited page could
  be lost on isolate teardown (round 1 P1-4).

### 2.5 Switch-mismatch alarm in both writers (round 2 P1-B; round 3 P1-1, database-based)

**The unsafe event.** A trial user's order, created while the door was ON, is RECORDED by a writer isolate that reads
stacking OFF. The paid row then ends at `now + days` and silently loses the trial days.

**The detector reads the DATABASE, not notes.** Payment notes come from the client's checkout options
(`razorpay_service.dart:244-258, :335`), not from the order's notes, so a notes-based check would never fire. Instead,
in each writer's OFF insert branch, AFTER a successful insert (`!insertError` in the webhook; `weInsertedTheRow` in
verify-payment), read:

```
select id, end_date from subscriptions
 where user_id = <verified userId> and status = 'active'
   and plan = 'referral_trial' and end_date > <the new row's start_date>
 limit 1
```

**What a hit means.** A trial user was charged while this isolate read OFF, a real loss of trial days. There are three
ways it happens (round 4 P2-2; the third from the hermes pass, seat 3):
- an order created while the door was ON, recorded by a stale OFF isolate;
- a free user who opens checkout (door OFF, order created), redeems a referral code mid-checkout (migration 159 refuses
  only a referee who has PAID; `grant_referral_days` inserts a `referral_trial` row), then pays. This one is possible
  today. With stacking ON, B1 already handles it;
- a free REFERRER whose own referral credit lands (the hourly job's `grant_referral_days` gives them a `referral_trial`
  row) while their checkout is open, then pays. Same shape, same remedy.

So the alarm's wording names neither cause as certain. On a hit:
- log `[<fn>] stacking_switch_mismatch payment_id=... user_id=...`;
- call `reportStackingMismatch` (below);
- the row stays exactly as OFF wrote it. The alarm detects; it never changes entitlement, the response status or the
  body.

**Read failure** (round 4 P2-1).
- The whole check (read + alert) sits in ONE try/catch.
- It is placed AFTER the promo redemption (webhook after `redeemPromo` ~:688; verify-payment after its promo block
  ~:710), so no failure in it can skip the promo.
- The read is bounded by the same 1 s race the alert module uses.
- A returned error, a thrown exception or a hang is logged and ignored. A recorded payment never becomes a 500.
- Cost on the webhook's 5 s clock: one indexed read, normally a few ms; bounded at 1 s + 2 x 1 s alert.

**It adds one request to the OFF path.** The OFF goldens are amended deliberately to expect it, and the amendment is
called out in the B-pass.

**`_shared/payment_alert.ts` gains `reportStackingMismatch`** (round 3 P2-1):
- its own source `stacking_switch_mismatch`, severity `critical` (migration 133 pages any critical insert; migration
  076 has no source CHECK);
- the summary `<fn>: paid row recorded without stacking over an active trial (row ends <end>, trial ends
  <trial_end>)`;
- the source is parametrised in BOTH the dedup query and the insert (today `PAYMENT_ALERT_SOURCE` is hard-coded,
  `payment_alert.ts:~66`);
- a `suggested_action` that says the row WAS written and gives the correction to consider (move its end to trial end +
  plan days);
- the same dedup by `payment_id` and the same bounded, never-throws contract;
- `timeoutMs: 1000` from BOTH writers (round 3 P2-2), so a hung alerts table adds at most about 2 s (3 s counting a slow-but-answering
  check read) to a SUCCESS
  response.

### 2.6 Replay window for `payment.captured` (decided, not conditional; round 2 P2-C)

**Decision.**
- Razorpay retries "for 24 hours after event creation" (docs). The repo's assumption that retries re-stamp
  `created_at` is unproven, and a manual Resend cannot settle it for automatic retries.
- So B2a stops depending on it.

**Change in `razorpay-webhook`.**
- Non-payment events already return before the age check (:293-300), and `payload.event` is read at :292.
- The age limit now depends on the event. For `payment.captured` it becomes **24 h + 10 min**.
- `payment.authorized` keeps **300 s**, because its path calls Razorpay's capture API.
- Every event keeps the future-skew rejection (`ageSec < -120`).
- Signature verification is unchanged and still runs first.

**Why it is safe.** A stale signed `payment.captured` reaches only idempotent code: the H-19 pre-SELECT, the second
pre-SELECT, then the B1 function (it returns the stored row) or the OFF 23505 catch, and the promo redemption runs only
when `!alreadyProcessed`.

**Residual risks, stated.**
- A signed event up to 24 h old can re-create a row an operator deleted by hand within that day. Testing phase; an
  operator removing a paid row also checks the webhook log.
- A stale captured event for an account deleted since then fails the insert (FK) and pages `payment_record_failed`
  (ON path; the OFF path answers 500 without a page). Accepted: one page per such event, deduped, and Razorpay retries
  for up to the window.
- A stale captured event for a payment REFUNDED since, whose row was deleted, re-grants PRO for up to 24 h. This is the
  same class as the deleted-row risk, stated.
- The widening is harmless either way: if Razorpay does re-stamp, it changes nothing.

**Evidence.** Step 0's Resend outcome is still recorded, but it no longer gates anything.

### 2.7 Docs and registry (same commit)

- `docs/architecture/payment.md`: rule 8 becomes "the friend can buy during the trial; the paid days start at the trial
  end; a purchase during the trial qualifies at once, so the referrer's credit lands at payment + 7 days". Rule 9's B2
  items are closed.
- ADR-0021 (amendment note), and the SoT concept `referral_reward_on_conversion`.
- `supabase/functions/CLAUDE.md`: the referral row ("the friend cannot buy during the 7-day trial") and the stacking
  row.
- Client referral copy that states the ~14-day timing: grepped in B2a, changed in B2b.
- `docs/blast_radius.yaml`: `supabase/functions/create-razorpay-order/**` is **catastrophic**.
- `docs/sot_registry.yaml`:
  - new concept `trial_purchase_door` (writer: the door; readers: the order notes, the writers' mismatch alarm, and
    B2b's client later);
  - `subscription_end_date_stacking` changes from dark to live after the flip;
  - `payment_record_failed_alert` gains the `stacking_switch_mismatch` source;
  - the replay-window rule is recorded on the webhook's concept.
- `docs/naming_conventions.md`: `ENABLE_TRIAL_PURCHASE`, `isEnvExactlyTrue`, `isTrialPurchaseEnabled`,
  `stacks_after`, `subscription_check_unavailable`, `stacking_switch`, `stacking_switch_mismatch`.
- Comments in `admin-dashboard-data` and `telegram-admin-bot`: "counts are ROWS per plan, not users" (no logic
  change).
- `docs/ship_dark_pending_review.yaml`: the `ENABLE_SUBSCRIPTION_STACKING` entry gets `flip_reviewed: true` and
  `flip_commit` once this batch lands with its full x2 record plus the B-pass, then is removed. `ENABLE_TRIAL_PURCHASE`
  never ships dark without that, so it gets no entry.
- OI-348 (the founder's post-build checks) gains, after B2b: a trial tester sees the line and buys, and the stacked end
  is shown.

## 3. Tests (every protection names a mutant that must redden it; mutations confirmed applied)

**Deno, `create-razorpay-order/index_test.ts` (new):**
- **OFF recording** from origin/main, through the harness transform `loadOriginMainHandler`
  (`payment_writer_harness.ts:46-62`) on a committed `fixtures/` copy (round 3 P2-3: no subprocess, no port bind): no row gives 200 (same response, same Razorpay
  order body, NO `stacks_after` key); a trial row gives the same 409 body; a paid row gives the same 409 body. The
  guard read's table and filters are pinned, not its URL.
- **The read error** gives 500 `subscription_check_unavailable` and NO Razorpay call, in BOTH switch states. Mutant:
  the error check dropped.
- **ON:**
  - A trial row gives 200, `stacks_after` = its end, and the notes carry it. Mutant: the filter dropped.
  - Paid alone gives 409. Paid plus trial gives 409 (mutant: the filter inverted, or `some` changed to `every`).
  - A trial ending LATER than a paid row gives 409 with the PAID row's `current_plan` / `current_expires_at` (mutant:
    the body taken from the latest row of any plan).
  - No row gives 200 with `stacks_after: null`.
  - Two trial rows give the max end (mutant: min).
- **Switch matrix:** door ON with stacking OFF gives OFF (mutant: `&& isStackingEnabled()` dropped). `" true"` and
  `"TRUE"` are OFF.
- **Import:** no env read and no fetch (a permissionless subprocess, the B1 pattern).

**Deno, the writers:**
- The `stacking_switch=on|off` line is printed once per insert-branch request, with the right value. Mutant: the line
  prints the wrong variable.
- The OFF goldens are re-run, unchanged.
- The webhook passes `timeoutMs: 1000`, and a hung alert releases the 500 within about 2.2 s in a test with fake
  timers. Mutant: the timeout dropped back to the default.
- **Mismatch alarm**, in each writer (round 3 P1-1). The payment entity carries NO `stacks_after` note in every case:
  - OFF + an active trial row ending after the new start gives the same 200 and body and the same inserted row, plus a
    `stacking_switch_mismatch` alert and log (mutant: the check removed);
  - OFF + a trial row that already ended, or no trial row, gives no alert (mutant: the `end_date >` filter dropped);
  - OFF + the check read returning an error, THROWING, or HANGING each give the same 200 with the promo redeemed
    (mutants: the error rethrown; the try/catch removed; the 1 s bound removed);
  - OFF + a hung alerts table gives the same 200 within about 2.2 s (mutant: the default 3 s timeout);
  - ON gives no check request at all (mutant: the check also run on ON);
  - the idempotent skip paths give no check;
  - the 23505 race arms give no check: webhook :659-661 `alreadyProcessed = true` and verify-payment :644-670 (mutant:
    the check run on any `insertError`, or when `weInsertedTheRow` is false). The winning writer owns the check.
- **The OFF goldens** are amended for the one added request; nothing else in them changes.
- **Replay window:**
  - `payment.captured` aged 6 min with the row present gives 200 idempotent (mutant: the old 300 s for every event);
  - aged 6 min with no row gives a recorded row;
  - aged 25 h gives 400;
  - `payment.authorized` aged 6 min gives 400 (mutant: the 24 h applied to every event);
  - future skew of -3 min gives 400 for both events;
  - promo redemption is not repeated on a stale idempotent event;
  - boundaries at 24 h 5 min (accepted) and 24 h 15 min (400) (mutant: a wider window).
- **Door env reads per request:** a `withTrialPurchaseSwitch` helper beside the existing `withSwitch`. One import, with
  the env toggled between requests, must change the answer (mutant: the env read moved back to module scope).

**Dart:** none in B2a (the client is B2b, section 9).

**End to end:** live steps 3 and 4 below (the only door-to-writer chain proof). No new SQL; B1's function is unchanged.

## 4. Live sequence (each step its own founder go; testing phase, Razorpay LIVE mode, 90% code, refunds)

**Step 0, before any deploy (answered 2026-10-21, section 0).**
- (a) **Keys: live, unchanged.** The project secrets `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` hold the live pair;
  they are used for the Orders API AND as the webhook signing secret (`razorpay-webhook/index.ts:12-20, :270`). No
  secret is changed in B2a, so no swap and no restore. The purchases use the web app, whose checkout key must be the
  live key ID (the client opens checkout with its own build-time key, `app_constants.dart:193`; a `rzp_test_` key
  cannot open a live order, round 3 P3-3). Step 1's free-tester probe proves the web app's key matches before any money
  moves.
- (b) The Resend observation: evidence only, since 2.6 is decided.
- (c) **The 90% code.** One dedicated `promo_codes` row: `discount_pct` 90, `is_active` true, an UNGUESSABLE code
  string (random, shared only with the testers), `max_uses` and `valid_until` set for the record. **Only `is_active`
  limits it** (B-pass seat B finding 1): the door honours an expired or exhausted code at order creation
  (`create-razorpay-order/index.ts:195-232` only logs `isExpired || isExhausted`), and both writers honour an expired,
  exhausted OR inactive code when deriving the plan (`razorpay-webhook/index.ts:131-150`, `verify-payment/index.ts:105-120`),
  while `increment_promo_used_count` has no ceiling. So until it is deactivated anyone who knows the code can buy at 90%
  off. It is deactivated (`is_active` false) right after step 4's payment is recorded, its own go. Deactivating while a
  purchase is in flight is SAFE for that purchase (the writers honour an inactive code, so the 90% amount still records);
  the next order is simply quoted at full price, which the buyer sees before paying. The code is stored in UPPERCASE,
  A-Z and 0-9 only (the door and `validate-promo` upper-case the typed code and match it exactly, so a lower-case row
  never matches; hermes seat 3 F4). A live write: created by the founder in the admin surface, or by Claude with its own
  go.
  **Testers (hermes seat 3 F1).** FIVE distinct accounts that have NEVER paid, plus one referrer account:
  - drill testers 1 and 2 (step 2) and the step 4 trial tester must have SIGNED UP within the last 7 days
    (`redeem-referral` accepts a referee only in its first 7 days and refuses one that has ever paid; a referee redeems
    once ever);
  - the step 4 tester redeems the referrer's code IMMEDIATELY before step 4 (the trial row must still be active when it
    pays), so the referrer's code is redeemed THREE times in all;
  - 3(a) and 3(b) may be any free accounts that have never paid;
  - no account can be reused after it pays. The referrer cannot be the step 4 trial user (its own credit lands only at a
    payment + 7 days).
- (d) **Every purchase is refunded** by the founder in the Razorpay dashboard after its step's proof is read. A refund
  does not touch the subscription row (the webhook answers 200 "ignored" to refund events); the row corrections (step 2)
  and the post-step-4 clean-up of tester rows are each their own go. **Clean-up is a STATUS change, never a delete**
  (hermes seat 3 F2): `status = 'cancelled'` (the trigger stamps `cancelled_at`, and the referral job then skips the
  row). A deleted row can be RE-CREATED by a signed `payment.captured` redelivery for up to 24 h 10 min (2.6), which
  would also redeem the promo again and could reward the referrer; a cancelled row still blocks the re-insert, because
  the idempotency pre-SELECT matches on the payment id only. A delete, if ever wanted, waits until the payment is older
  than 24 h 10 min. A referral credit earned by a drill tester's paid conversion lands at payment + 7 days on a tester
  account; it is listed in the clean-up and reverted only if the founder asks.

1. **Deploy `create-razorpay-order`** (verify_jwt **false**, explicit), both switches unset, so the OFF path runs. The
   previous payload is copied out first. It now imports `../_shared/subscription_stacking.ts` (its first `_shared`
   import), so the deploy is the host-shell path (`node .claude/emit_payload.js create-razorpay-order --auto
   --functions-dir <worktree>/supabase/functions`, then `deploy_via_api.js ... false`), never the legacy MCP deploy; the
   rollback payload is the single-file `b8385b6c` one (hermes seat 3 F5). Probes:
   - no auth gives 401 from the module;
   - a free tester gets an order and the web checkout OPENS on it (no payment; this proves the web app's live key ID
     matches the server's keys);
   - a trial tester gets 409.
2. **Deploy `razorpay-webhook` and `verify-payment`** (2.3-2.6; switches unset). Probes as in B1. The switch log
   shows `stacking_switch=off`. Then the **alarm drill** (round 4 P2-2), still OFF with the door shut:
   - a free tester opens checkout;
   - the founder redeems a referral code for that tester, mid-checkout;
   - the tester pays with the 90% code;
   - expect a `stacking_switch_mismatch` alert and log line from the WEBHOOK;
   - repeat with another free tester while the founder pauses the app's live webhook in the Razorpay dashboard, to
     cover verify-payment, then re-enable it (a stale redelivery after re-enable reaches only idempotent code, 2.6);
   - then resolve both alerts and correct both rows by hand (end := trial end + plan days), with a founder go per
     correction.
3. **Flip stacking:** set `ENABLE_SUBSCRIPTION_STACKING=true`, then **redeploy both writers unchanged** (the same
   payload). A deploy replaces the isolates, so no warm isolate keeps the old value. The forcing function is the
   redeploy, not a timed wait. Then:
   - (a) One purchase (90% code) by a FREE tester: the webhook logs `stacking_switch=on` and `stacking=on ...
     inserted=true`, and the row's `end = start + 30`. That proves the WEBHOOK ON path.
   - (b) The founder pauses the app's live webhook in the Razorpay dashboard, and a SECOND, DISTINCT FREE
     tester who has never paid makes one purchase. The 3(a) tester is now PRO and would get 409, and the poll's
     5-minute same-plan fallback (`razorpay_service.dart` `_pollAndActivate`, the `.eq('plan', fallbackPlan)` query; cited by symbol because B2b moved the lines) must not match the 3(a) row.
     - The client polls about 45 s, then calls verify-payment.
     - Pass: the verify-payment log shows `stacking_switch=on` and `stacking=on ... inserted=true`. That proves the
       VERIFY-PAYMENT ON path.
     - Then the webhook is re-enabled.
   - Run the reconcile queries (below): clean.
4. **4a, open the door:** set `ENABLE_TRIAL_PURCHASE=true`, then **redeploy `create-razorpay-order` unchanged**. Then
   **merge B2b** (its own founder go; the web app redeploys on the merge). **4b:** one stacked purchase (90% code) by a
   TRIAL tester through the NEW web client (it shows the paywall line and the checkout notice):
   - the order response has `stacks_after` = the trial end;
   - the paid row's `end_date` = trial end + 30 days and `start_date` = the payment instant;
   - the trial row is unchanged;
   - the poll shows the stacked end.

   Reconcile queries: clean. Then the 90% code is deactivated, every step's payment is refunded, and the tester rows
   are cancelled (not deleted; step 0 (c), (d)), each with its go.
5. **B2b** (the client). AMENDED 2026-10-22 (founder order of 2026-10-21, recorded in
   `docs/plans/oi341-piece-b2b-client.md` section 0): B2b is planned, reviewed and BUILT before this live session, and
   NOT merged. Step 4 splits: **4a** opens the door (`ENABLE_TRIAL_PURCHASE=true`, redeploy `create-razorpay-order`);
   then **B2b merges** (the web app redeploys on the merge); **4b** is the stacked trial purchase made through the NEW
   web client, so one purchase proves the door and the client together; then the code off, refunds and cancelled rows
   as above. Then `/build-apk` (founder) with the LIVE key ID in the VPS `.env` (section 0; OI-348) and one phone
   purchase. B2b must never merge before 4a. Between 4a and the merge (minutes) a trial user on the old web client gets
   the old `now + 30` estimate until the server's stored end replaces it, and no notice: accepted.

**Rollback (round 1 P1-1).**
- **Door rollback** (the normal one): unset `ENABLE_TRIAL_PURCHASE` and redeploy `create-razorpay-order`. Stacking
  stays ON: with the door shut it is harmless for free users (ON end = OFF end), and it still protects an order created
  while the door was open and paid later. Reconcile at once and at +24 h.
- **Writer rollback** (only if migration 161 / the ON path is itself faulty):
  1. FIRST unset `ENABLE_TRIAL_PURCHASE` and redeploy `create-razorpay-order`, so no door isolate still believes
     stacking is ON (round 3 P2-5).
  2. Then unset `ENABLE_SUBSCRIPTION_STACKING` and redeploy both writers. This ACCEPTS that a trial user who pays an already-open order afterwards loses trial days. The
  reconcile query at +24 h finds them, and corrections are a founder decision.

**Reconcile queries** (read-only, run by Claude after steps 3 and 4, again at +24 h after step 4 (round 4 P2-4), and
after any rollback):

```sql
-- (R1) paid rows that started inside a referral trial but end short of trial end + plan days
select p.id, p.user_id, p.plan, p.start_date, p.end_date, t.end_date as trial_end
  from subscriptions p
  join subscriptions t
    on t.user_id = p.user_id and t.plan = 'referral_trial'
   and p.start_date >= t.start_date and p.start_date < t.end_date
 where p.razorpay_payment_id is not null and p.status = 'active'
   and p.end_date < t.end_date + make_interval(days => case p.plan when 'yearly' then 365 else 30 end) - interval '1 minute';
-- (R2) unresolved payment / mismatch alerts since the flip
select id, source, severity, detected_at, context_json->>'payment_id' as payment_id, context_json->>'code' as code
  from alerts where source in ('payment_record_failed', 'stacking_switch_mismatch') and resolved_at is null
 order by detected_at desc;
```

- The founder also compares the Razorpay live Payments list for the steps 2-4 window with the rows (a captured payment
  with no row and no alert).

## 5. Not in B2a

- Two orders created before either is paid can each stack (orders set no expiry). Pre-existing, unchanged by the door
  for paid users (a paid user still gets 409); for a trial user, the second paid row stacks after the first. Stated,
  out of scope.
- `docs/operations/SECRET_INVENTORY.md` gets a corrected `RAZORPAY_KEY_SECRET` row that adds `create-razorpay-order`
  (round 3 P3-2). This is a doc fix in B2a.

- OI-359 and OI-360: pre-existing, outside the door and the flip.
- OI-350 and OI-351: the 502 loop after an auto-capture. Unchanged; a stacking failure enters it the same way an insert
  failure does today (B1 note).

## 6. Founder questions

1. **Server Razorpay keys** (step 0a): ANSWERED 2026-10-21: live; live mode with a 90% code and refunds (section 0).
2. Steps 2 and 3(b) need the app's live webhook paused for one purchase each (a dashboard action by the founder).
3. Step 2's drill needs the founder to redeem a referral code for a tester mid-checkout, twice (two drill testers), from
   one referrer account.
4. Five distinct tester accounts (section 4 step 0 (c)) and the dedicated 90% code (created by the founder, or by Claude
   with a go).

## 7. Review round 1 dispositions (v1 -> v2)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| P1-1 | P1 | Rollback that unsets stacking loses trial days for open orders | Rollback = door only; writer rollback only for a faulty 161, with stated loss + reconcile (section 4) |
| P1-2 | P1 | Step 3 proof impossible (verify-payment ON runs only when the webhook did not write) | Step 3(a) webhook proof + 3(b) webhook disabled in test mode for verify-payment |
| P1-3 | P1 | 10-minute wait is a guess, a stale OFF isolate leaves no trace | Redeploy after each secret change (forcing function) + `stacking_switch` log line (2.3) |
| P1-4 | P1 | `waitUntil` cannot meet the goal, unverified, could lose a page | Dropped; webhook alert `timeoutMs: 1000` (2.4); lock-timeout case accepted and stated |
| P1-5 | P1 | `_computeEndDate` tear-off at :957 drops stacksAfter | Pure `estimatePaidEndDate`; closure captures `_pendingStacksAfter`; test through `payment_retry_attempt` |
| P2-1 | P2 | Open question; per-device flag is not a kill switch; trial 409 shown as success | Flag dropped; `isReferralTrial` getter via `subscriptionInfoProvider.select`; trial-409 copy + `onFailure` (2.5, 2.6) |
| P2-2 | P2 | Two reads double the failure surface | One read, decision in code (2.2) |
| P2-3 | P2 | 503 collides with boot-broken + client cold-start retries | 500 `subscription_check_unavailable` |
| P2-4 | P2 | Resend may not represent automatic retries | Stated; 2.9 trigger and design given in step 0 |
| P2-5 | P2 | Reconcile is post-hoc, blind to no-row captures | R2 alert query + the founder's Payments-list comparison; run after steps 3, 4 and rollback |
| P2-6 | P2 | Tests that pass with the feature absent; private untestable functions | Banner not claimed; `estSealDate`, `estimatePaidEndDate` extracted; OFF-golden response pins no `stacks_after`; paywall negative arms |
| P3 | P3 | EST clamp drift; referral timing docs; counters; fail-open fix separate | Drift accepted and stated; ADR-0021, SoT concept, functions CLAUDE.md, client copy updated; counter comments; fail-open fix kept in this batch with its own diagnose-doc and test |

## 8. Review round 2 dispositions (v2 -> v3)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| P1-A | P1 | Web client deploys at merge, before the door opens | SPLIT: B2a server (this plan), B2b client merged after step 4 (top, section 9) |
| P1-B | P1 | A stale OFF writer is invisible for the one dangerous payment | `stacking_switch_mismatch` alarm on `notes.stacks_after` in both writers' OFF insert branch, with mutants (2.5, section 3) |
| P2-A | P2 | OFF golden cannot be byte-identical on requests | Reworded: pins responses, the order body, the read's table and filters; subprocess recording (2.2, section 3) |
| P2-B | P2 | ON 409 can report `current_plan: referral_trial` for a paid user | Body from the latest NON-trial row; test + mutant (2.2) |
| P2-C | P2 | 2.9 conditional and unreviewed | Decided and specified as 2.6 with residual risks and tests; this round-3 review covers it |
| P2-D | P2 | Test mode not established (server keys double as the webhook secret) | Step 0a + founder question 1 |
| P3 | P3 | Old builds between steps 4 and B2b; shorter dedup timeout pages more; retries in memory; web path | Stated (step 5); dedup-timeout page count bounded by Razorpay retries, accepted; web path confirmed shared in B2b |

## 9. B2b starting point (moved from v2; its own plan, branch and x2 review after B2a step 4)

> **SUPERSEDED 2026-10-22 by `docs/plans/oi341-piece-b2b-client.md` (v3, x2 converged).** Kept for history. Where
> they differ the B2b plan wins: the trial 409 KEEPS `_handleAlreadyProResponse`'s state heal (only the message and
> callback change); the copy is `PaymentCopy.trialUpgradeUnavailable` in `lib/core/copy/payment_copy.dart` (not
> `kTrialUpgradeUnavailable` under `constants/`); `kReferralTrialPlan` lives in `lib/core/constants/subscription_plans.dart`;
> the estimate is captured per ORDER ID, not in one `_pendingStacksAfter` field; and B2b is built BEFORE the live
> session but merged only after step 4a (section 4 step 5).

### 9.1 Client (`razorpay_service.dart` + `payment_retry_attempt.dart`)

- `_pendingStacksAfter` (`DateTime?`) is parsed from the 200 response's `stacks_after` (malformed parses to null).
  - It is set beside `_pendingPlan` (:135) and reset to null at the start of every `openCheckout`.
  - It is cleared in `_onUserChanged`.
- **Extract the pure function** `estimatePaidEndDate({required String plan, DateTime? stacksAfter, required DateTime
  now})` into `lib/core/services/payment_end_estimate.dart`: `max(now, stacksAfter ?? now) + 30/365` as an ISO string.
  - `_computeEndDate` becomes a thin wrapper.
  - All FOUR uses pass the stacks-after the checkout captured, including the :957 tear-off, now a closure that captures
    `_pendingStacksAfter` at checkout time.
  - It is an ESTIMATE until the server's stored end overwrites it. That overwrite is unchanged. All server paths return
    `end_date`.
- **A trial user's 409** (the door shut, for example after a rollback): when the 409 body's `current_plan ==
  'referral_trial'`, the client does NOT run `_handleAlreadyProResponse` + `onSuccess`. It shows the copy constant
  `kTrialUpgradeUnavailable` and calls `onFailure`. Any other `current_plan` keeps today's path. Both the response path
  and the catch path change.
- The checkout `'description'`: when `stacksAfter != null`, it becomes `'PRO Monthly Plan. ' + kTrialStackingNotice`,
  checked against Razorpay's description limit (255 chars) in a test.

### 9.2 Copy (Wardroom read before writing, `lib/shared/widgets/wardroom/CLAUDE.md`)

- `lib/core/constants/payment_copy.dart` (new):
  - `kTrialStackingNotice = "Your paid plan starts when your free days end."` (founder, verbatim);
  - `kTrialUpgradeUnavailable`: wording proposed in the build and checked against the Wardroom voice;
  - `kReferralTrialPlan = 'referral_trial'`.
- **Paywall line:** under the pricing cards, shown when `SubscriptionInfoData.isReferralTrial` (a new pure getter:
  `isPro && plan == kReferralTrialPlan`) is true.
  - It is read with `ref.watch(subscriptionInfoProvider.select((s) => s.isReferralTrial))`, the sanctioned read
    (`lib/CLAUDE.md`).
  - Copy only; it gates nothing (CLAUDE.md 4.4 rule 5 is about gating).
- **No client flag** (v1's configBox flag is dropped: per device, so not a rollback switch).
- The client ships AFTER the door is ON (section 4 step 5), so the line is true from the first build. After a door
  rollback the line would over-promise until the next build, and the 2.5 trial-409 copy then explains it.

### 9.3 EST seal

- Extract `estSealDate({required SubscriptionInfoData sub, required DateTime now})` as a pure top-level function, which
  the static wrapper calls: `min(expiresAt - planDays, now)`.
- **Accepted and stated:** for a stacked purchase it shows today until the trial ends, a drift of at most the trial
  length. After that it back-computes the paid start (= the trial end).
- A `referral_trial` plan back-computes 30 days, pre-existing and approximate, unchanged.

## 10. Review round 3 dispositions (v3 -> v4)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| P1-1 | P1 | Notes-based alarm never fires (payment notes come from the client) | DB-based post-insert check for an active trial row; tests with NO notes (2.5, section 3) |
| P1-2 | P1 | 3(b) needs a distinct never-paid tester; the poll fallback could match the 3(a) row | Reworded with the pass condition (section 4 step 3(b)) |
| P2-1 | P2 | Alert module hard-codes source and wording | `reportStackingMismatch` with its own source and wording (2.5) |
| P2-2 | P2 | Mismatch alert latency on the success path | `timeoutMs: 1000` from both writers; hung-alert test (2.5, section 3) |
| P2-3 | P2 | Subprocess recording infeasible | Harness transform on a committed fixture (section 3) |
| P2-4 | P2 | Wrong comment lines; event-dependent limit; refund risk | Cited :334-346, :295-302; per-event limit; refund risk stated; harmless either way (2.6) |
| P2-5 | P2 | Writer rollback leaves the door open | Door first, then writers (section 4) |
| P3 | P3 | Two-orders stacking; SECRET_INVENTORY row; checkout key mismatch, swap required | Section 5; inventory fix in B2a; step 0a strengthened |

## 11. Review round 4 dispositions (v4 -> v4.1, mechanical only)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| P2-1 | P2 | The check itself could throw or hang into the success path | One try/catch, placed after the promo, 1 s bound; throw and hang tests (2.5, section 3) |
| P2-2 | P2 | "Only a door-ON order" is false (mid-checkout redeem); no live drill | Both causes stated; neutral wording; alarm drill added to step 2 for both writers |
| P2-3 | P2 | 23505 race arms not named | Named, with mutants (section 3) |
| P2-4 | P2 | Silent alarm failures covered only by the post-step R1 | R1 + R2 again at +24 h after step 4 |
| P3 | P3 | Line cites; door switch helper; replay boundaries; check cost; dedup source | All fixed (2.5, 2.6, section 3) |

## 12. v4.1 -> v4.2 (founder answers 2026-10-21, live-sequence only)

- Server keys are live; no test secret exists. Step 0 rewritten: live mode, one dedicated 90% code (0 (c)), refunds and
  row clean-up (0 (d)); no secret swap. Steps 1-4 reworded from "test mode" to live; step 1 now proves the web app's
  checkout key matches. Order (amended 2026-10-22): B2a steps 1-3 -> 4a -> B2b merge -> 4b -> refunds -> AAB with the live key ID in `.env`
  (section 0, OI-348).
- No code, test or design change. The B-pass and hermes briefs include section 4 so this text is reviewed with the code.

## 13. B-pass and hermes dispositions (v4.2 -> v4.3, 2026-10-21)

- B-pass (2 seats): 0 P0, 0 P1, 4 P2, 7 P3; all fixed (ledger rows BP-*). Seat B's P2: only `is_active` limits a promo
  code (step 0 (c) rewritten).
- Hermes (4 seats, L1/L21, L23/L40, L22/L2 + live sequence, L29 + abuse): 0 P0, 0 P1, 6 P2, 6 P3.
  - Fixed in code: a captured payment whose amount matches no plan (or fails the webhook's cross-check) was a silent
    400; both writers now page `payment_record_failed` with code `amount_no_match` / `amount_cross_check`, response
    unchanged (diagnose c3e7a1).
  - Fixed in this plan: fresh tester accounts and a third referral redeem (step 0 (c)); clean-up by status, never delete
    (step 0 (d)); upper-case code; the door's deploy path (step 1); the third alarm cause (2.5); the deleted-account
    residual (2.6).
  - Filed: OI-366 (the door has no rate limit and honours expired or exhausted promo codes; the fix touches the founder
    digest's key list and validate-promo) and OI-367 (referral farming once the door is open: a product call before store
    launch).
  - Kept, stated: the mismatch alarm stays `critical` while the door is shut. A mid-checkout redeem really does cost the
    user trial days and needs a manual correction, so paging is right.
