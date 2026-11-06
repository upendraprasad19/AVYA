# Plan — payment hardening (OI-350, OI-351, OI-359, OI-360, OI-366 + promo_codes public read)

**Version 2.2 (2026-10-24), after review round 3** (a confirmation round on 2.1: 0 P0, 2 P1, 2 P2,
3 P3, all on commit mechanics and proof completeness, none on the design; section 11). **Split under
§4.12.1:** U4 (the `promo_codes` migration) moves to its OWN branch and worktree,
`promo-codes-server-only`, and ships FIRST: it has no code dependency on U0-U3, it closes the live
exposure, and alone it avoids the Gate 14 interplay (section 3 U4). This branch keeps U0-U3.

**Version 2.1 (2026-10-24), after review rounds 1 and 2.** Round 1: four context-blind seats
(A verify-payment, B webhook, C order/promo, D cross-cutting; 0 P0, 6 P1). Round 2 on version 2: three
seats (writers; order/promo/migration; process/deploy; 0 P0, 2 P1, 11 P2). Every finding was re-verified
by the coordinator against code or live state before folding in; one round-2 finding (the tuning-entry
location) was REJECTED as stale (section 9).

- **Branch / worktree:** `payment-hardening`, fast-forwarded to `origin/main` 3af16319 (no payment file
  changed since 2cd1d0b8; the skill-tuning gate did).
- **Tier:** L (payment, Edge Functions, a migration). Blast radius **catastrophic**
  (`verify-payment/**`, `razorpay-webhook/**`, `create-razorpay-order/**` in `docs/blast_radius.yaml`).
  Record `docs/plan-reviews/payment-hardening.md` (the gate keys on the branch name) with
  `review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`,
  `hermes: accepted`; each of `bpass_review:` / `hermes_report:` cites ONE path whose file carries a
  literal `verdict: accepted` line.
- **Execution mode (decided at batch start, §4.12.7): INLINE, sequential, one worktree.** The units
  share both writers, the shared harness, `payment.md`, the functions CLAUDE.md SoT table,
  `sot_registry.yaml` and `blast_radius.yaml`, and about fifteen Dart contracts read these files.
  Parallelism is used for review rounds only.

## Founder decisions

Taken 2026-10-24 ("go"): order limit 30 per hour per user, 429, fail closed on a counter error; a promo
is honoured at order time only while active, unexpired (IST end of the `valid_until` day) and not
exhausted; the payment writers keep their tolerant read; the `validate-promo` throttle is in scope.

**Ratified by the founder 2026-10-24** (answers to the four questions; the promo-check limit of 20/hour was superseded 2026-10-25: 7 per UTC-hour bucket, plan `2026-10-25-promo-check-limit-7.md`): F-1 every call at 20/hour;
F-2 the no-switch exception for U0/U1 approved; F-3 U4 added; the Telegram bot is deferred (OI-278: the
bot is disabled), so no out-of-repo reader of `promo_codes` exists. **F-4 (round 2; RATIFIED by the
founder 2026-10-24: "Default ON, kill switch"):** the U2 and U3 switches are KILL switches that default ON (new path live at
deploy), which is not §4.6 step 1's "default new path behind a gate"; precedent `DISABLE_WRITE_CLAIM_RULE`
(coach-log-truth). This is not ship-dark (§4.12.4), so the full ×2 review + B-pass + hermes apply (they
do); no `docs/ship_dark_pending_review.yaml` entry. The catastrophic tier's `feature_flag` requirement
(`docs/blast_radius.yaml:20-27`) is met by U2/U3's switches and waived for U0/U1 by F-2;
`rollback_documented` is section 6.

Original wording of the questions:
- **F-1 (D-U3-2):** count EVERY `validate-promo` call at 20 per hour (one atomic call) instead of only
  misses at 10 per hour (needs a read before the lookup plus a consume after it). The bound is PER
  ACCOUNT, and accounts are free, so neither shape is an enumeration bound on its own; U4 is what closes
  the listing.
- **F-2 (§4.6 exception):** U1 (ownership before capture) and U0 (log text) ship WITHOUT a kill switch.
  A switch on U1 would restore the vulnerable ordering, and own-payment behaviour is unchanged (tests);
  U0 changes log text only. U2 and U3 DO get kill switches (§4.6 default). Rollback for U0/U1 is the
  prepared forward-deploy of the previous payload (section 6).
- **F-3 (new scope, U4):** revoke client access to `promo_codes` (live finding below), a migration whose
  live apply needs its own go. The one fact only the founder could supply (whether the Telegram bot, a
  separate OpenClaw project, reads `promo_codes` with the anon key) is ANSWERED: the bot is deferred and
  disabled (OI-278), so no out-of-repo reader is known (the founder's statement, not verified from the repo).

## 0. Ground truth (2026-10-24)

1. **Live code equals `main`** for the payment functions (GET
   `/v1/projects/dedsavbjuwgarrhphgnl/functions/<slug>/body`, decode the eszip's embedded
   `sourcesContent`, compare byte-for-byte with the local import closure):
   `verify-payment` v30, `razorpay-webhook` v34, `create-razorpay-order` v18 — every file IDENTICAL.
   `validate-promo` v21 differs ONLY in the std import (`std@0.177.0` live vs `std@0.224.0` main,
   ec01b469; logic identical). `founder-digest` v14 differs only by the additive `readProState` in
   `_shared/subscription.ts` (unused by the digest). No deploy here rolls back live-only code.
   Live `verify_jwt` flags (MCP `list_edge_functions`): `verify-payment` true, `validate-promo` true,
   `create-razorpay-order` false, `razorpay-webhook` false, `founder-digest` false,
   `telegram-admin-bot` false.
2. **`consume_quota` has no key allowlist** (migration 128; 130 only revokes PUBLIC EXECUTE and grants
   `service_role`, which both functions' clients use). New keys need no migration.
3. **`promo_codes.valid_until` is `date NOT NULL`** (`20260330_create_promo_codes.sql:7`).
4. **NEW, live (read-only SQL + one count-only API call):** `anon` and `authenticated` each hold all
   eight table privileges on `public.promo_codes` (DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER,
   TRUNCATE, UPDATE; grantor `postgres`; no PUBLIC entry; no column grants; corrected 2026-10-24 by the U4
   B-pass F7, which found the earlier "SELECT, INSERT and UPDATE" here); RLS is on; the ONE policy is
   `"Anyone can read active promo codes"` (SELECT, roles `public`, `using (is_active = true)`, created by
   `20260330_create_promo_codes.sql:25-32` "needed for client validation"). A request with only the
   public anon key (`GET /rest/v1/promo_codes?select=code&limit=0`, `Prefer: count=exact`) answered
   `206`, `content-range: */3`: all three active codes and their `discount_pct` are listable without
   signing in. INSERT/UPDATE have no policy, so RLS denies them. No reader in `lib/` or `web/`; the only
   readers are the four payment Edge Functions, all service-role (RLS bypassed). `promo_code_uses` is
   clean (own-rows SELECT; client INSERT `with check false`).
5. **The 2026-10-23 webhook traffic** was deploy smoke only (function_edge_logs: 400s and 401s at the
   four deploy hours; the OI-341 live record says no real payment ran). No live evidence either way on
   OI-351's frequency (section 1).
6. **Bug history (§4.1.5)**: `c8f229` (verify-payment notes guard; pinned by
   `verify_payment_notes_user_id_required_test.dart`, which this batch keeps and extends); `7ad0d5` H-19
   (pre-SELECT before capture; OI-351 is the not-yet-recorded case it does not reach); `f2c8d5`
   (windowed limits were inert: prove each new limit writes live); `c3e7a1` (amount_no_match pages: the
   writers must stay tolerant); `d4c8e1` (std-encoding import rot broke a redeploy) and `f5d8c3`
   (module-load SyntaxError masked by the gateway 401): boot-verify every deploy. `7ad054` fixed
   `promo_code_uses` policies but never looked at `promo_codes`. Not recurrence: OI-351, OI-360, OI-366
   and the promo listing have no prior diagnose under their concepts.

## 1. Corrections to the OI texts (recorded on the board in this batch)

- **OI-350 = OI-359**: one defect (capture and status echo before the ownership check). One fix, two
  closure rows.
- **OI-366 is partly wrong**: `validate-promo` DOES reject inactive (`:100`), expired (`:111-123`) and
  exhausted (`:126-140`). The gap: `create-razorpay-order` (`:215-231`) only logs expired/exhausted and
  honours the discount. Its "unthrottled oracle" is real, but moot while U4's listing is open.
- **OI-351 runs on the normal flow, not only after a failed insert** (seat B, re-verified):
  `create-razorpay-order:253` sets `payment_capture: 1`, so Razorpay auto-captures; a
  `payment.authorized` delivery that arrives after Razorpay's own capture has its manual capture
  refused and answers 502 today, while the separate `payment.captured` event records the row. How often
  is not evidenced (no real payment since the live keys). On the 24 h claim: if Razorpay keeps the
  original `created_at` on retries, retries past 300 s are already rejected with 400 at `:365`, so only
  retries inside 300 s benefit; if it re-stamps them, the fix removes a 24 h loop. The first real payment
  settles both (section 6 live checks).
- **OI-360 wording**: in `verify-payment` the stored signature is a sentinel
  (`verified_via_api:<12 chars>`, `:544`); what leaks there is the user id, order id and payment id in
  `details`. The webhook's `:716` carries the real HMAC header.

## 2. Writers and readers (file:line on `origin/main` 2cd1d0b8)

| Item | Writer | Readers / consumers |
|---|---|---|
| OI-350/359 | `verify-payment/index.ts`: GET `:370-397`, capture `:404-437`, echo `:439-451`, 400 `:459-470`, 403 `:471-482` | client `razorpay_service.dart:911-915` (`status==200 && verified==true`) and `:1011-1019` (retry; non-200 → null); `verify_payment_notes_user_id_required_test.dart` |
| OI-360 | `verify-payment/index.ts` `:683-686`, `:421-423`, `:161`, `:522`, `:579`; `razorpay-webhook/index.ts` `:716`, `:503`, `:517`, `:461-463`, `:482`, `:243`, `:566`, `:141`, `:189`, `:206`, `:535`; `create-razorpay-order/index.ts:272-277` | function logs (platform retention, dashboard readers) |
| OI-351 | `razorpay-webhook/index.ts:426-491` (non-OK `:459-474`, throw `:481-490`); inserts `:648` (ON) / `:688` (OFF) | Razorpay retry scheduler; H-19 pre-SELECT `:399`; second pre-SELECT `:622`; replay window `:365`; `payment_alert.ts:94` dedup |
| OI-366 | `create-razorpay-order/index.ts` auth `:117-126`, guard `:148-178`, promo `:196-233`, order `:243-281`; `validate-promo/index.ts` env `:21-23`, lookup `:83-97`, rules `:99-140` | `razorpay_service.dart:157-278` (non-409 non-2xx → `_extractServerError(details)` `:488-494`, shown verbatim); `paywall_sheet.dart:216-247` (200 `{valid, reason, discount_pct}`; ANY non-2xx → "Network error. Try again."); `_shared/founder_digest_content.ts` `DIGEST_KEYS :87-129` (read by `founder-digest` and `telegram-admin-bot/index.ts:20`) |
| promo read | `20260330_create_promo_codes.sql:25-32` policy + the default Supabase table grants | anyone holding the anon key (PostgREST); no app reader |

## 3. Units, in implementation order (one `fix(...)` commit each, section 5)

### U0 — `_shared/payment_log_safe.ts` (pure, no imports, no I/O)

- `pgErrorCode(err)`: `err.code` only if it is a string matching `^[A-Za-z0-9_]{1,16}$` (PGRST116,
  23503 pass; `""`, a 10 KB string, an object do not) → else `"no_code"`. Never `details`/`hint`/`message`.
- `errorName(err)`: `err.name` for an Error, else `typeof err` (`null` → `"null"`).
- `razorpayErrorSummary(status, bodyText)`: `status` (integer, else `"?"`) plus the parsed
  `error.code` and `error.reason` ONLY when each is a string (each sliced to 40 and passed through
  `boundedText`); a non-JSON body, `"null"`, an array, a string `error` → status only.
- `notesShape(notes)`: for a plain object, which of the KNOWN keys (`user_id`, `plan`, `promo_code`,
  `stacks_after`, `source`, `billing_cycle`) are present plus a count of other keys; arrays (Razorpay
  sends `notes: []` when empty), null and strings → their type. Never values, never unknown key names.
- `boundedText(v, n = 40)`: `JSON.stringify(String(v).slice(0, n))` — quotes and escapes newlines, so a
  client-supplied string cannot forge a log line or grow it.
- Tests `_shared/payment_log_safe_test.ts`: each helper against hostile fixtures (23503 with a fake
  signature in `details`; non-string and nested `code`; empty `code`; a 10 KB body; notes as `[]`,
  `null`, a string, an object with a secret-shaped value and an unknown key; a value with `\n`).
- Naming: append `payment_log_safe` to `docs/naming_conventions.md`. Blast radius
  `supabase/functions/_shared/payment_log_safe*.ts` → catastrophic (the `payment_alert*.ts` precedent,
  `blast_radius.yaml:86`).

### U1 — verify-payment: ownership before any side effect (OI-350, OI-359)

Move the two guards (`:453-482`, text, order and messages unchanged: absent → 400 "Missing user_id in
payment notes", mismatch → 403 "Payment does not belong to this user") to directly after `let payment =
await razorpayResponse.json();` (`:397`), before the capture block and the status echo. After the move
nothing before the guards touches anything not the caller's (rate limit = own counter; pre-check `:341`
is `.eq("user_id", userId)`; the GET is a read).

| Caller's payment | Before | After |
|---|---|---|
| own, captured / authorized / created / failed | as today | unchanged (same requests, same body) |
| GET non-OK, or a `null` body | 502 / 500 | unchanged |
| a non-null primitive body (unreachable from Razorpay) | 200 `Payment status is 'undefined'` | 400 (no `notes`) |
| another user's, any status | capture fired if authorized; status echoed 200; 403 only once captured | 403, no capture, no status |
| no `notes.user_id`, captured | 400 | 400 |
| no `notes.user_id`, not captured | status echo 200 (capture first if authorized) | 400, no capture |

The last row changes only for payments not made through this app's order path (the app always sets
`notes.user_id`, `create-razorpay-order:254-255`); no reader relies on it (seats A, D).

Tests (`verify-payment/index_test.ts`; the harness's `paymentServer` hard-codes a captured payment, so
these use `Scenario.intercept`, which runs first and whose requests are recorded):
1. another user's AUTHORIZED payment → 403 and `server.to("/v1/payments/", "POST")` is empty;
2. another user's `created` payment → 403, body lacks `Payment status is`;
3. no `notes.user_id` + authorized → 400, no capture POST;
4. own authorized → capture → 200 (request sequence as today).
Mutations: **M1** guards back below the capture → tests 1 and 3 red; **M1b** guards between the
capture and the echo → red too. Measured 2026-10-24: M1 reddens 4 Deno tests (both 403 and both 400 cases)
and the Dart pin; M1b reddens 3 (the AUTHORIZED 403 and both 400 cases) and the Dart pin, NOT test 2 as
first predicted: with the guards ahead of the echo a created payment is already refused 403.
Dart pin: extend `verify_payment_notes_user_id_required_test.dart` (comments stripped): both guards
precede the first `/capture` AND precede `payment.status !== "captured"`; the three existing pins stay.
Live proof: none possible on demand; the diagnose-doc says "proven by the Deno tests".

### U2 — razorpay-webhook: already-captured recovery (OI-351), behind a kill switch

- Kill switch `DISABLE_WEBHOOK_CAPTURE_RECOVERY`, exactly `"true"` (via the existing exported
  `isEnvExactlyTrue`, `_shared/subscription_stacking.ts:42`), read once per request inside the handler:
  set → today's status, body, requests and side effects (the U0 log text and the hoisted `credentials`
  apply in both states; no test pins the old log text).
- Hoist `credentials` above the capture `try` (`:442`). Keep the capture `try`/`catch` shape; on a
  non-OK capture or a throw set `captureRefused = true` and record `razorpayErrorSummary` /
  `errorName` (no early return when the switch is unset). AFTER the `try`/`catch`, if `captureRefused`:
  `rereadIsCaptured(paymentId, expectedAmount, credentials)` — a NEW never-throwing helper bounded at
  1500 ms by `Promise.race` against a timer plus an `AbortController` (the `payment_alert.ts:65-73`
  `bounded` pattern: the test fake ignores `init.signal`, `postgrest_fake_fetch.ts:94-121`, so a bare
  `AbortSignal.timeout` would be untestable), that GETs `/v1/payments/<id>` and answers true only when
  the body is a plain object with `id === paymentId`, a number `amount === paymentEntity.amount`,
  `captured === true` and `status === "captured"`. The `resp.json()` read is INSIDE the raced promise
  (a hang after the headers must not escape the bound). (Budget: the capture POST is unbounded today; 1.5 s
  on top keeps a recovered request within reach of Razorpay's 5 s clock in the normal case; a timed-out
  request is retried by Razorpay and then meets H-19 or recovers.) True → `console.warn` "capture refused, payment already captured;
  continuing payment_id=<id>" and fall through to the notes/plan/insert path unchanged (the signed event
  stays the source of amount, notes and plan, exactly as on the `payment.captured` path). False →
  `console.error` with the summary and today's 502 "Capture failed, will retry".
- The GET is a `fetch` to Razorpay, not a supabase call, so
  `razorpay_webhook_supabase_client_decl_order_test.dart` (first `await supabaseClient.from(`) holds;
  the 23505 regex and `let alreadyProcessed` pinned by
  `razorpay_webhook_promo_double_burn_guard_test.dart` are not reflowed.
- Replay end states (3 deliveries each; seat B): captured event → insert once, then H-19 skips;
  authorized + capture OK → H-19 skips; authorized + capture OK + insert fails → today 502 then 400
  past 300 s, after U2 retry 1 recovers and inserts once (promo once; replays 2-3 skip), a persistent
  insert failure answers 500 each time (ON path: `payment_record_failed` critical once then warn);
  authorized whose GET says authorized / 5xx / throws → 502 as today.
- Harness: add an authorized `captured: false` event builder to `_shared/payment_writer_harness.ts`
  (today `webhookRequest` builds only captured events, `:269-278`, and the test's local `eventRequest`
  forces `captured = true`, `index_test.ts:365`). Additive; verify-payment shares the file.
- Tests (`razorpay-webhook/index_test.ts`): (1) authorized, no row, capture 400, GET captured → row
  inserted, 200; (2) capture 400, GET authorized → 502; (3) capture 400, GET 500 → 502; (4) capture
  throws, GET captured → 200; (5) GET captured but amount differs → 502; (6) happy path (capture OK) →
  no GET; (7) three replays after a recovery → H-19 skips, no capture, no GET; (8) recovery on the
  stacking-ON path → exactly one RPC call, promo only if `inserted`; (9) recovery + 23505 race → no
  promo; (10) switch `"true"` → a TRUE golden: origin fixture handler vs new handler on the same
  authorized `captured:false` event with capture 400 — status, body and request list equal (the frozen
  fixture holds the same capture block, `razorpay_webhook_origin_main.ts.txt:387-441`); (11) GET hangs
  (never-resolving intercept) → 502 within about 2 s; (12-15) one negative per clause: id differs;
  `captured:false` with `status:"captured"`; `captured:true` with `status:"authorized"`; body `null`,
  an array, or a string `amount`.
  **M3**: remove the recovery call → test 1 red. **M3b**: drop the `Promise.race` → test 11 times out.
  **M3c-h**, one per clause (compound-boolean connective rule): plain-object check → body `null`/array
  test; `id` → id-differs test; number type → string-`amount` test; amount equality → test 5;
  `captured === true` → `captured:false, status:"captured"` test; `status === "captured"` →
  `captured:true, status:"authorized"` test.

### U0 log sites (OI-360) — all three functions

- `verify-payment`: `:683-686` → `[verify-payment] subscription insert failed (non-23505)
  request_id= payment_id= user_id= plan= amount_paise= code=<pgErrorCode>` (the fields of the `:609-611`
  reconcile line under its OWN prefix, so the runbook's `stacking read failed` grep stays ON-path only;
  money is captured and no row exists on this OFF-path branch, so the ids must stay; documented in
  payment.md); `:421-423` → `razorpayErrorSummary`; `:161` → `errorName` + `pgErrorCode`; `:522` (raw
  `body.plan`) → `boundedText`; `:579` (`preSelectError.message`) → `pgErrorCode`; `:113` and `:491`
  (promo code read from notes) → `boundedText`.
- `razorpay-webhook`: `:716` → `[razorpay-webhook] subscription insert failed (non-23505)
  payment_id= user_id= plan= amount_paise= code=` (no `request_id`: this path's 500 body carries none to
  correlate with); `:503` → `notesShape`; `:517` → value type and
  length; `:461-463` → `razorpayErrorSummary` (warn when recovered, see U2); `:482` → `errorName`;
  `:243` → `errorName` + `pgErrorCode` (presence-only: postgrest-js returns errors, so the catch is
  reachable only by a throw); `:566` (`notes.plan`), `:141`, `:189`, `:206`, `:535` (promo code read
  from notes) → `boundedText`.
- `create-razorpay-order:272-277` → `razorpayErrorSummary`.
- Unchanged, with reason: every outer catch-all (`verify-payment:771`, `razorpay-webhook:782`,
  `create-razorpay-order:303`, `validate-promo:156`) — reachable throws carry no row data or notes
  (seats A, B, D: `req.json()` SyntaxError, fetch TypeError with the URL only, null dereference);
  `razorpay-webhook:657-659` is the intended reconcile line (pinned by its tests).
- **R-6 folded in**: both `redeemPromo` twins (`verify-payment:149-159`, `razorpay-webhook` `:231`/
  `:234`) now check the RETURNED errors of `increment_promo_used_count` and the `promo_code_uses`
  insert and log a label naming which call failed plus `pgErrorCode` (U3 makes `used_count`
  load-bearing for exhaustion). Log only: `redeemPromo` returns void and nothing reads a result, so no
  response, row or count changes (a repeat-user `promo_code_uses` 23505 now produces a log line).
  Tests per twin: `increment_promo_used_count` answers 500 with a code (the fake's `rpcs` handler returns
  a `Response`); the `promo_code_uses` POST fails (intercept); each asserts response, row and
  `promoIncrements` equal to the golden plus exactly one labelled code-only log line. **M2b**: remove
  the check → red.
- Log tests: the harness's `captureConsole` prints an Error as `.message` only and objects via
  `JSON.stringify` (`payment_writer_harness.ts:102-103`), so a leak test can pass against the leaky
  code. Each log test therefore carries a **positive control**: the same scenario against the frozen
  origin fixture handler must SHOW the secret in `all`. If the control cannot see it (an Error-shaped
  PostgrestError), extend `captureConsole` with an opt-in `Deno.inspect` formatter first. One fixture
  per changed site that a test can reach (`verify-payment` `:683`, `:421`, `:522`, `:579`;
  `razorpay-webhook` `:716`, `:503`, `:517`, `:461`, `:566`); webhook `:482` is covered by the
  `errorName` unit test only (the fake's `"throw"` raises a fixed `TypeError`, `postgrest_fake_fetch.ts:121`,
  and `captureConsole` prints an Error's `.message`, so no positive control can show a secret there).
  Harness limits: `webhookRequest` always injects `user_id` (a missing-id test overrides it with `""`);
  `verifyRequest` cannot send `plan` (the `:522` test builds its Request by hand). The scenarios run with stacking
  OFF where the site is on the OFF branch, and the 23503 intercept's `message` must not contain
  "duplicate key". **M2**: restore one whole-object log in each writer → red.

### U3 — order limit, strict promo at order time, validate-promo throttle (OI-366), behind a kill switch

- **Kill switch** `DISABLE_ORDER_ABUSE_GUARDS`, exactly `"true"` (`isEnvExactlyTrue`), read once per
  request inside each handler; set → every U3 rule off in BOTH functions (the counter AND the strict
  promo rule; stated coupling: restoring purchases during a counter outage also reopens expired codes).
  Each handler logs `order_abuse_guards=<on|off>` once per request (the `write_claim_rule=<bool>`
  precedent) so a flip is visible; a row in `docs/operations/SECRET_INVENTORY.md` (if a warm isolate
  logs the old value after a flip, redeploy, as the `DISABLE_WRITE_CLAIM_RULE` row says).
- **create-razorpay-order**: after the JWT check and BEFORE the guard read, `consume_quota` with
  `p_quota_key: ORDER_QUOTA_KEY, p_window_start: bucketStart, p_limit: ORDER_QUOTA_LIMIT` in that literal
  order; `const ORDER_QUOTA_KEY = "create_order";` and `const ORDER_QUOTA_LIMIT = 30;` declared IN this
  `index.ts`; `bucketStart` initialised from a `bucketStartMs` expression (1-hour UTC epoch floor, the
  `delete-account/index.ts:168-170` precedent; `founder_digest_caps_mirror_test.dart` parses exactly this
  in `_resolveStrings`/`_resolveInts`/`_resolveKind` (~54-108) and `_efSites` (~120-192), over every
  non-`_test.ts` file under `supabase/functions`, so `validate-promo/index.ts` too).
  `-1` → 429 `{error: "Too many payment attempts. Try again in a few minutes.", error_code: "rate_limited", retry_after_seconds}` + `Retry-After`;
  RPC error → 429 `{error: "Could not start payment right now. Try again shortly.", error_code: "rate_limit_unavailable", request_id}` (fail closed).
  Accepted and stated: a 409 already-PRO, a 400 bad plan and a bad JSON body each spend a unit; and
  `SupabaseService.callFunction` retries a 502/503/504 up to 3 times (`supabase_service.dart:418-435`),
  so one tap during a Razorpay outage can spend 4 units (about 8 taps lock a buyer out for the hour).
  Bucket-edge doubling (up to 60 in about 2 minutes) has the `verify_payment` shape; accepted.
- **Promo rule**: new `_shared/promo_rules.ts` `promoUsableAt(promo, now)` → `"ok" | "inactive" |
  "expired" | "exhausted"`, evaluated in that order (inactive, expired, exhausted, matching
  `validate-promo:100/:111/:126`); `is_active === true` only (the column is nullable,
  `20260330_create_promo_codes.sql:8-10`); `valid_until` normalised by `String(v).slice(0, 10)` (live is
  `"YYYY-MM-DD"`, the test fixture is `"2099-01-01T00:00:00Z"`) and REQUIRED to match
  `^\d{4}-\d{2}-\d{2}$` — anything else (`"infinity"`, `"abc"`, `""`, `null`) → `"expired"` (a bare
  string compare would sort letters after digits and fail OPEN); then expired when
  `istDateStr(now) > thatDate`; exhausted when `max_uses != null && Number(used_count ?? 0) >=
  Number(max_uses)` (loose `!=` so a missing `max_uses` reads as unlimited, never as `NaN`). **Promo read error** (`create-razorpay-order:197-201` destructures only `data`
  today): read `error`; an error → 500 `{error: "Could not check the promo code. Try again.",
  error_code: "promo_check_unavailable", request_id}` and NO order (the guard-read precedent
  `:156-167`), so an outage is never reported as a dead code; `maybeSingle` with no row and no error is
  the "unknown" case. In the order: a supplied code that is unknown or not `"ok"` → 400
  `{error: "This promo code can no longer be used. Reopen the upgrade screen to pay without it.", error_code: "promo_invalid"}`
  and NO Razorpay order (behaviour change: today an inactive or unknown code silently gives a
  full-price order; the paywall sends a code only after `validate-promo` said valid, `paywall_sheet.dart:319`,
  and has already closed, `:311`, so reopening starts clean). The writers keep their tolerant
  `derivePlanFromAmount` (`verify-payment:106-118`, `razorpay-webhook:135-146`): strict-at-order cannot
  strand money (seat C). Exhaustion race (two concurrent orders) accepted, bounded by the limit.
- **validate-promo**: refactor to `export async function handler` + `if (import.meta.main)
  serve(handler)`, moving `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` reads (`:21-23`) into the
  handler; keep `std@0.224.0`. After the JWT check: `consume_quota` with local `PROMO_QUOTA_KEY =
  "promo_validate"`, 1-hour bucket, `PROMO_QUOTA_LIMIT = 20` (F-1). Over the limit → HTTP 200
  `{valid: false, reason: "Too many attempts. Try again in an hour."}` (2026-10-25, hermes H3: shipped as
  "Try again in N minutes.", N = the minutes left in the UTC hour); RPC error → HTTP 200
  `{valid: false, reason: "Couldn't check the code right now. Try again shortly."}` (200 because the
  paywall maps every non-2xx to "Network error"; installed builds read it). Expiry → `promoUsableAt`;
  the lookup becomes `.maybeSingle()` with `error` read: an error → the same 200 "Couldn't check the
  code right now" reason (the old `.single()` folded errors into "Invalid promo code", `:89`; kept only
  on the switch path). Switch `"true"` → the OLD code path verbatim (UTC `setHours` expiry, `.single()`,
  no counter).
- **Digest**: add `{ key: "create_order", label: "create-razorpay-order", kind: "subday" }` and
  `{ key: "promo_validate", label: "validate-promo", kind: "subday" }` (no `cap`, no quote in a label;
  `founder-digest/index_test.ts:546` checks duplicates).
- **Tests**:
  - `create-razorpay-order/index_test.ts`: `run()` gains `fallbackRpc` (count 1 by default) with a
    per-test override (-1, error); without it every existing scenario would answer 429
    (`postgrest_fake_fetch.ts:40,143`). The existing door goldens compare status, body, order body and
    guard filters (not the request list), so no normaliser is needed; their origin fixture is the
    FROZEN pre-B2a copy (it differs from today's `index.ts` by 110 lines), kept as the baseline. New:
    31st call → 429, no Razorpay request (**M5**: drop the `-1` branch → red); RPC error → 429, no
    order; expired yesterday-IST → 400 `promo_invalid`, no order; `valid_until` = today checked at
    23:59 IST → honoured and at 00:01 IST the next day → refused (**M6**: compare in UTC → one red);
    exhausted / inactive / unknown → 400; both `valid_until` formats; switch `"true"` → the old
    tolerant behaviour (status, body, order body equal the frozen fixture's for each golden scenario).
  - NEW `validate-promo/index_test.ts` + frozen fixture `_shared/fixtures/validate_promo_origin_main.ts.txt`
    (today's file): switch `"true"` → equal to the fixture on every scenario; 21st call → 200
    `valid:false` with the rate reason and NO `promo_codes` read (**M7**: drop the consume → red); RPC
    error → the distinct reason; IST boundary pair; the four existing answers unchanged; importing the
    module reads no env, fetches nothing and binds no server (the `create-razorpay-order/index_test.ts:303-335` test shape).
  - `_shared/promo_rules_test.ts`: the rule table incl. IST boundaries, both date formats,
    `"infinity"`, `"abc"`, `""`, `null`, `is_active` null, `used_count` null with `max_uses` 0 and 5.
  - promo read error: `create-razorpay-order` with an intercepted 500 on `/rest/v1/promo_codes` → 500
    `promo_check_unavailable`, no Razorpay order; `validate-promo` the same → 200 with the distinct reason.
  - No new test file spells the literal `consume_quota` or `usage_counters` (the census tests scan
    `_test.ts` too): tests route through `fallbackRpc` and, if they name the RPC, use a concatenated
    `CONSUME_QUOTA_RPC` constant (the `prediction_handler` test precedent).
  - `usage_quota_ledger_writer_to_reader_test.dart:250-271`: add `create-razorpay-order/index.ts` and
    `validate-promo/index.ts` to `allowed`, with the reason (an HTTP attempt, no INSERT for a trigger
    to hang off).

### U4 — revoke client access to `promo_codes` (new; F-3) — OWN BRANCH `promo-codes-server-only`, ships first

**Branch mechanics (round 3):** Gate 14 (`scripts/check_migrations_applied.dart:43-50,119-125`) lists the
WORKING TREE of `supabase/migrations/` and fails any `.sql` there with no ledger entry, so the migration
file must not sit in that directory before its live apply. Sequence on the U4 branch: reserve the number
with `sh scripts/mint_migration.sh <slug>` (reserves `mig/N`, writes no file); draft the migration under
`docs/plans/promo-codes-server-only/NNN_<slug>.sql.draft` with its tests and diagnose-doc E; full gate
loop; B-pass on that staged draft; founder go; the rehearsal; the live apply; then `git mv` the draft to
`supabase/migrations/NNN_<slug>.sql`, add the ledger entry (hash from `migration_ledger_hash.dart`), and
commit; PR; CI; merge. **Slug and wording:** the slug must not contain `rls` and the file (comments
included) must not contain the phrase "security definer" — `docs/blast_radius.yaml:88` (`*rls*.sql`) and
`blast_radius_content_rules_lib.dart:38` would otherwise make it catastrophic; slug
`promo_codes_server_only_access`. Tier then: platform (record needs `review_rounds: 2` +
`bpass: accepted`; this unit was reviewed in rounds 2 and 3). Its own plan-review record
`docs/plan-reviews/promo-codes-server-only.md` cites this plan.

- Migration: number and four-tag stub from `sh scripts/mint_migration.sh --stub <slug>`; header
  `Destructive?: yes` (it DROPs a policy; no data is lost), `Rollback strategy: inline` (commented
  reverse block at file end), `Linked diagnose-doc:` diagnose E. Body:
  `DROP POLICY IF EXISTS "Anyone can read active promo codes" ON public.promo_codes;` and
  `REVOKE ALL ON TABLE public.promo_codes FROM PUBLIC, anon, authenticated;` RLS stays enabled;
  `service_role` untouched. The file is immutable once applied.
- Pre-apply live read, recorded in the diagnose-doc and used for the rollback block: table ACL
  (`aclexplode(relacl)` from `pg_class`) AND column ACLs (`aclexplode(attacl)` from `pg_attribute`) for
  every grantee and grantor (`information_schema.role_table_grants` omits column grants, the migration-160
  lesson in `supabase/migrations/CLAUDE.md`), plus `pg_policies` for the table. Rollback block =
  re-create the policy verbatim (`FOR SELECT USING (is_active = true)`, default `TO public`) and re-grant
  exactly the captured ACL; it re-opens the listing, which is the original defect.
- Dry-run (`Destructive?: yes`, `supabase/migrations/CLAUDE.md:64`: a dry-run + founder sign-off):
  `test/sql/promo_codes_server_only_rehearsal.sql`, the live verify's DO block with the two migration
  statements run first inside it, as ONE aborting statement with no explicit BEGIN (U4 B-pass F8: a
  `BEGIN; ...; ROLLBACK;` script never reaches its ROLLBACK because the checks always RAISE, and the aborted
  session could keep DROP POLICY's ACCESS EXCLUSIVE lock). Expected: 16 `ok`; then the live verify still
  reads its pre-apply `ok=10 fail=6`, and `pg_locks` shows no lock on `promo_codes`. The contract test pins
  the rehearsal equal to the verify plus exactly the migration.
- Post-apply live verify (`test/sql/promo_codes_no_client_access_live_verify.sql`, the
  `referral_pay_on_conversion_live_verify.sql` group-Q shape): under `SET LOCAL ROLE anon` and then
  `authenticated`, `SELECT count(*) FROM public.promo_codes` raises 42501; `has_any_column_privilege`
  false for both roles; no `pg_policies` row for the table; `has_function_privilege` false for both roles
  on `public.increment_promo_used_count(text)` EXECUTE (closed by migrations 090:38 and 091:20-21; proven
  live here, not inferred); `pg_publication_tables` has no row for `promo_codes`; POSITIVE checks that
  `has_table_privilege('service_role', 'public.promo_codes', 'SELECT,UPDATE')` and the same for
  `postgres` stay true (REVOKE FROM PUBLIC cannot touch `service_role`'s explicit default grant, migration
  120:155-163, but this proves it). Added by the U4 B-pass (F3-F5): the 42501 must be the TABLE's
  ("permission denied for table promo_codes", not a refused role switch); `has_table_privilege` false for
  every privilege (membership routes too); no client-callable definer function names the table; and
  `service_role` really reads every row under RLS (BYPASSRLS), 16 cases in all. Each expected-42501 statement sits in its own `DO … EXCEPTION WHEN
  insufficient_privilege` block, so the rehearsal transaction is not aborted by the first one. The
  pre-apply ACL read lists each entry's GRANTOR: a `REVOKE` run as `postgres` removes only grants
  `postgres` made, so a grant by another grantor (e.g. `supabase_admin`) needs its own `REVOKE … GRANTED BY`
  or is reported to the founder before the apply. Then the count-only anon
  API request answers 401/403 instead of `*/3`, and a signed-in `validate-promo` call still answers
  (the Edge Functions keep reading through the service role).
- Writer/reader proof that nothing in the app reads it: `grep -rn promo_codes lib/ web/` empty;
  `supabase/functions` readers are the four payment functions only, all `SUPABASE_SERVICE_ROLE_KEY`.
- Tests: `test/contracts/promo_codes_server_only_writer_to_reader_test.dart` pins the migration's DROP + REVOKE
  (source) and that no file under `lib/`/`web/` names `promo_codes`; a live verify SQL
  `test/sql/promo_codes_no_client_access_live_verify.sql` (read-only, the
  `referral_pay_on_conversion_live_verify.sql` shape). Mutation: drop the REVOKE line → the pin reds.
- `backups/applied_migrations.json` updated in the SAME commit as the migration (§4.5; Gate 14 and
  `check_migration_ledger_paired.dart`), its hash from `dart run scripts/migration_ledger_hash.dart <NNN>`
  (Gate 39 verifies it); `backups/live_schema_columns.json` unchanged (no column change). OI minted with
  `scripts/mint_oi.sh`. Registry: `promo_codes_server_only` carries `presence_only: true` with the reason
  "the access rule lives in the catalog; behaviour is proven by the live-verify SQL", not a
  `behavioral_test_path:` claim.
- **Apply BEFORE the merge** (section 5): the migration file is reviewed by the B-pass and hermes on the
  branch; then the founder's go; then the rehearsal; then the apply; then commit 5; then the PR.

## 4. Docs, registry and board (same batch)

- `docs/architecture/payment.md`: rule 2 (tolerant only in the writers; strict at order time), new
  rule 11 (ownership before capture; webhook recovery and its switch; log safety; order and validate
  limits and their switch; `promo_codes` server-only).
- `supabase/functions/CLAUDE.md`: SoT rows `create_order_rate_limit`, `promo_validate_rate_limit`,
  `promo_usable_rule`, `webhook_already_captured_recovery`; pitfall row "a payment-path log carries a
  whole error, notes or upstream body"; then re-record `backups/context_artifact_sizes.json` (the file
  is already 34,818 bytes against 33,616 recorded).
- `docs/sot_registry.yaml`: those four plus `verify_payment_owner_before_capture`,
  `payment_log_safety` (and `promo_codes_server_only` on the U4 branch) — each row lands in the SAME commit as its diagnose-doc
  and test (`check_sot_registry_citations.dart` hard-fails a post-2026-08-01 diagnose-doc whose
  `sot_registry_entry:` names an unregistered concept; Gate 42 needs every `behavioral_test_path:` on
  disk at commit time). Refresh the `line_range` entries the moved code shifts (`sot_registry.yaml`
  around lines 8299, 8303, 13592, 13600, 16420-16502).
- `docs/blast_radius.yaml`: `_shared/payment_log_safe*.ts`, `_shared/promo_rules*.ts` → catastrophic;
  `validate-promo/**` stays account (its row exists, `:392`).
- `docs/naming_conventions.md`: `create_order`, `promo_validate`, `payment_log_safe`,
  `DISABLE_ORDER_ABUSE_GUARDS`, `DISABLE_WEBHOOK_CAPTURE_RECOVERY`.
- `docs/operations/SECRET_INVENTORY.md`: rows for both kill switches.
- Diagnose-docs (rule 22, FULL template, `touched_layers_checked` per §6): A owner-before-capture
  (OI-350/359), B log safety (OI-360, incl. R-6), C webhook recovery (OI-351), D order/promo limits
  (OI-366), E promo_codes public read (new OI).
- `docs/audit/payment-hardening.closure.yaml` (§4.2; five items: OI-350, OI-359, OI-360, OI-351,
  OI-366; the U4 OI is closed by its own branch's diagnose-doc and record, not a ledger — it is a single
  item, below §4.2's ≥4 threshold): created last, after the final code SHAs exist (no rebase after it; the merge is
  a merge commit, never a squash), once every row is terminal; rows are `closed_in_commit` for the
  code with `notes: live verification pending (deploy is founder-gated)`; the ledger's own commit is
  never cited as a row's `commit:`.
- OI board: the section 1 corrections; rows stay OPEN until each live check passes, then move to
  `closed_issues.md` in a post-deploy docs PR. **No `closes-oi:` trailer in this branch**
  (`check_closes_oi_performed.dart` requires the cited OI to be CLOSED at the merge). New OIs: the
  promo listing (U4) and the removal of both kill switches after their live checks (OI-374 precedent).
- Skill self-evolution (§5.1): `.claude/skills/debugging/bug-classes.md` entry "side effect before the
  authorization check on a service-role path" if none exists. Each `docs/reviews/*.md` added (the
  B-pass) carries its own `## Tuning entry` section (dated bullet first); the archive
  `.claude/skills/code-review/tuning-history.md` is FROZEN (`check_skill_tuning_history.dart` on
  `origin/main` 3af16319).

## 5. Commits and gates

Commits (each `fix(...)` carries exactly one `closes-diagnose:` — the gate reads the first match — and
contains its code, its tests, its diagnose-doc AND its registry rows; no `closes-oi:` anywhere):
1. `fix(verify-payment)`: U1 — diagnose A + `verify_payment_owner_before_capture`.
2. `fix(payments)`: U0 + all log sites + R-6 — diagnose B + `payment_log_safety`.
3. `fix(razorpay-webhook)`: U2 — diagnose C + `webhook_already_captured_recovery`.
4. `fix(payments)`: U3 — diagnose D + `create_order_rate_limit`, `promo_validate_rate_limit`,
   `promo_usable_rule`.
   (U4 is NOT on this branch: section 3 U4, its own branch, shipped first.)
5. `docs(...)`: payment.md, the functions CLAUDE.md rows, naming, blast radius, inventory, OI board,
   context budget re-record, skill entry; then the closure ledger (after final SHAs; five items here,
   the U4 OI is closed by its own branch's ledger).
6. `docs(review)`: the hermes report (line-anchored `verdict: accepted`).
7. `docs(plan-review)`: `docs/plan-reviews/payment-hardening.md` with `branch: payment-hardening`
   frontmatter and the fields above.
**Per-commit B-pass (round 3, verified):** `scripts/check_code_review_pass_exists.dart` requires, for
EVERY commit whose staged diff reaches catastrophic, a `docs/reviews/<hash of that staged diff>-review.md`
staged IN that commit with `verdict: accepted` (the hash excludes `docs/reviews/**`; precedent
`6bfbd402` carried `64b21cb79f3c-review.md`). Commits 1-4 each touch a catastrophic path, so each runs
`/code-review` on its own staged diff and ships its own review file (each with its `## Tuning entry`,
`check_skill_tuning_history.dart`). The record's `bpass_review:` cites ONE of them (the U3 commit's,
the largest); all four carry `verdict: accepted`.
Gates before the review rounds that follow code (§4.12.8): `flutter analyze lib/`; `deno check
--node-modules-dir=none` on every touched function; `deno test --no-check --allow-all
--node-modules-dir=none supabase/functions/` (whole tree); `TZ=Asia/Kolkata flutter test
--exclude-tags golden` (full; the VPS quirk); the pre-commit loop; mutations M1, M1b, M2, M2b, M3,
M3b-f, M5, M6, M7 and the U4 pin, each proven applied (`grep -c`) and restored (`cmp`). Then
`/code-review` (B-pass) and `/hermes-pass`, PR, CI, and `sh scripts/safe_pr_merge.sh`.

## 6. Live steps — each its own founder go, ONE at a time

**Rollback preparation, before ANY deploy** (skill §6.13: the pre-deploy snapshot writes 0 files, and a
git-SHA `--rollback` without `--dry-run` silently sets `verify_jwt=true`; the tool defaults to `true`
whenever the flag is omitted, `deploy_via_api.js:355`): for each function run
`node .claude/deploy_via_api.js --rollback <fn> <rollback SHA> --dry-run` (git-SHA mode takes NO
project ref; `--rollback <project_ref> <fn>` is the legacy snapshot mode, which finds nothing here). It
writes `.claude/_payload_<fn>_rollback_<sha>.json` (`deploy_via_api.js:823-824`, gitignored) and stops
at `:934-935`, before any POST and before `archivePayload` (`:949`). Copy it to the session scratchpad;
the durable artifact is the SHA. Rollback = a FORWARD deploy of that payload with the `verify_jwt`
argument stated explicitly. **Rollback SHAs, each verified byte-equal to the LIVE bundle's embedded
sources on 2026-10-24** (newest commit whose whole local import closure equals live): `verify-payment`,
`razorpay-webhook`, `create-razorpay-order` → `6bfbd402`; `validate-promo` → `4c5bd085` (the
pre-ec01b469 `std@0.177.0` file); `founder-digest`, `telegram-admin-bot` → `ca2f6f46` (live
`telegram-admin-bot` predates `6bfbd402`'s 3-line comment in its `index.ts`, so `ca2f6f46` — not HEAD — is
the byte-equal SHA; checked against the live bundle, not against HEAD). A SHA stays
"last good" only if nothing else deploys these functions first; re-run the check right before.

**U4 is not in this table**: it is applied before the merge (section 5).

| # | Step (after the merge, from this worktree fast-forwarded to `main`) | verify_jwt | Proof |
|---|---|---|---|
| 1 | `founder-digest` | false | boot (anon Bearer → the module's answer, not 503); next morning's digest lists the two keys, no "unlisted keys" line |
| 2 | `telegram-admin-bot` | false | an unsigned POST → 200 with an EMPTY body (it answers every unauthorized request that way, `index.ts:106-168`; a 5xx/503 = boot-broken). No `/digest` probe: it would message the founder (the bot is deferred) |
| 3 | `verify-payment` | true | anon Bearer → module 401 (booted); a signed-in call with a well-formed unknown `pay_` id → the module's 502 (boot only; U1's ordering is proven by tests) |
| 4 | `validate-promo` | true | the tool prints "Smoke FAIL 401" (the function is not in `SMOKE_TOLERATED_CODES`, `deploy_via_api.js:691-770`): expected; this deploy also moves std 0.177 → 0.224, so the signed-in check IS its boot proof: `NOPE` → 200 `valid:false` "Invalid promo code", twice within one UTC hour; `usage_counters` row `promo_validate` with `used = 2`; log `order_abuse_guards=on` |
| 5 | `create-razorpay-order` | false | signed-in `{plan:"bogus"}` → 400 (409 for a PRO/trial tester), twice within one UTC hour; `create_order` row `used = 2` |
| 6 | `razorpay-webhook` | false | POST with no signature header → 400 "Missing x-razorpay-signature header"; a wrong signature → 401 |

`alert-critical-notify` imports only `istClock` from the digest module: bytes change, behaviour does
not; NOT redeployed. A signed-in smoke needs a real tester JWT (skill §6.5/§6.7), from the founder or a
test account's password sign-in.
**Where deploys run:** from this worktree after a fast-forward to the merged `main`, never from the
integration-only primary. Every deploy writes `backups/edge_function_payloads/*` and
`.claude/_payload_*.json`, and `archivePayload` PRUNES tracked archives (`deploy_via_api.js:629-633`)
(OI-405): nothing of that is committed in this batch (OI-405's policy is the founder's open choice).
After the last deploy: `git checkout -- backups/edge_function_payloads`, delete the new untracked
archive files and `.claude/_payload_*.json` in this worktree, confirm `git status --porcelain` is empty,
so retirement passes.
**At the first real payment after the deploys:** read the webhook logs for the recovery line and count
`payment.authorized` "Webhook too old" rejections (settles section 1's two open questions); OI-348 gets
the row.

## 7. Residual risks (stated)

- `verify-payment`'s own capture can still 502 when the webhook or Razorpay captured first; the client
  retries at 60 s / 5 m / 15 m and the retry sees `captured`. Not a loop.
- The 403 tells a caller a payment id exists and is someone else's; ids are not guessable.
- Promo exhaustion race; per-account bounds only (accounts are free).
- OI-367 (referral farming), OI-339/340 (refunds, disputes) are not in this batch.

## 8. Questions for the confirmation round (round 3, on version 2.1)

- Does any round-2 fold-in introduce a new defect (the `Promise.race` bound, the promo-read error
  paths, the date-format guard, the REVOKE FROM PUBLIC, the commit map with registry rows per commit,
  the apply-before-merge order, the per-function rollback SHAs)?
- Is every round-2 resolution in section 10 actually present in sections 0-6?
- (Round 2 answered: U4's REVOKE is complete in the repo — no view, publication, definer RPC or grant
  names `promo_codes`; `increment_promo_used_count` EXECUTE is closed by 090/091 and is checked live.)

## 9. Round-1 resolution (every finding verified by the coordinator before folding in)

| Seat/finding | Sev | Resolution |
|---|---|---|
| C1, D1 consume_quota census allowlist | P1 | U3 tests bullet; verified `usage_quota_ledger_writer_to_reader_test.dart:250-271` |
| C2, D7 order tests need `fallbackRpc`; no normaliser; frozen fixtures | P1 | U3 tests; verified `run()` has no `fallbackRpc`; fixtures differ from today by 110-161 lines |
| C3, D6 validate-promo OFF path undefined, env at module scope | P1 | U3 validate-promo bullet + fixture + import test |
| C4 promo_codes client-readable | P1 | verified LIVE (section 0.4) → U4 |
| D2 rollback sets verify_jwt=true; snapshot writes 0 files | P1 | section 6; verified skill §6.13 and `deploy_via_api.js:355` |
| A1, B5 log tests blind to Error-shaped objects | P2 | positive control + optional `Deno.inspect` formatter; verified `harness:102-103` |
| A2 `:683` must keep the ids | P2 | reconcile-shaped line |
| A3, B5 harness cannot express the scenarios | P2 | `Scenario.intercept`; authorized builder added to the harness |
| A4 status echo ordering pinned only in Deno | P2 | Dart pin extended |
| B1 recovery runs on the normal flow | P2 | section 1 corrected; U2 gated by a kill switch |
| B2 300 s window bounds the loop | P2 | section 1, both branches; live check at first payment |
| B3 recovery must match id and amount | P2 | `rereadIsCaptured` conditions |
| B4 GET inside the try; no timeout; credentials scope | P2 | flag after try/catch; 2 s timeout; hoisted credentials |
| C5 digest mirror shape | P2 | exact literal shape in U3 |
| C6 valid_until formats, malformed input | P2 | `slice(0,10)`; malformed → expired |
| C7 units burned by 409/400 and client retries | P2 | stated as accepted |
| C11 per-account bound | P2 | F-1 text |
| D3 telegram-admin-bot imports the digest | P2 | deploy step 3; verified `telegram-admin-bot/index.ts:20` |
| D4 kill switch needs inventory row and a visible log line | P2 | U3 switch bullet |
| D5 §4.6 for U2 | P2 | U2 gated; F-2 lists the U0/U1 exception for ratification |
| D8 commit/trailer/record mechanics | P2 | section 5 + section 4 (no `closes-oi:`) |
| D9 smokes weaker than claimed | P2 | section 6 (400 or 409, `used = 2`, token source, boot-only noted) |
| D10 deploy residue (OI-405) | P2 | section 6 "where deploys run" |
| A5-A7, B3 helper input shapes | P3 | U0 helper spec |
| A8, B7, D12 missed log sites | P3 | U0 log sites list |
| A9 sentinel signature wording | P3 | section 1 |
| A10/A11, B8, B9, C8-C10, C12, D11, D13 | P3 | folded (switch coupling, distinct RPC-error text, webhook smoke statuses, pins named, context budget re-record, `isEnvExactlyTrue` reused) |
| R-6 `redeemPromo` ignores returned errors | — | folded into U0 log sites |

## 10. Round-2 resolution (on version 2; every finding re-verified by the coordinator)

| Seat/finding | Sev | Resolution |
|---|---|---|
| S3 P1-1 new concepts cited before they are registered | P1 | section 5: registry rows ride in each fix commit; verified `sot_citation_lib.dart:19` cutoff 2026-08-01 |
| S3 P1-2 U4 apply-vs-merge contradiction; `Destructive?: yes` dry-run; ledger hash tool | P1 | U4 + section 5: apply before the merge; rehearsal; `migration_ledger_hash.dart`; verified `supabase/migrations/CLAUDE.md:46,64,77,123` |
| S2 P2-1 malformed date fails OPEN under a string compare | P2 | U3: `^\d{4}-\d{2}-\d{2}$` required, else expired; tests |
| S2 P2-2 promo read error reported as a dead code | P2 | U3: `promo_check_unavailable` 500 / distinct 200 reason; verified `create-razorpay-order:197-201` |
| S2 P2-3 U4 verify blind to PUBLIC and column ACLs | P2 | U4: REVOKE FROM PUBLIC too; `relacl` + `attacl`; `SET LOCAL ROLE` 42501 checks |
| S1 P2-1 2 s bound untestable on the fake | P2 | U2: `Promise.race` bound (1500 ms), hang test, M3b; verified `postgrest_fake_fetch.ts:121`, `payment_alert.ts:65-73` |
| S1 P2-2 re-read clauses not each killable | P2 | U2 tests 12-15, M3c-f |
| S1 P2-3 no positive control possible at webhook `:482` | P2 | `errorName` unit test only; verified the fixed `TypeError` |
| S1 P2-4 R-6 had no test | P2 | U0 R-6 tests + M2b |
| S3 P2-1 telegram-admin-bot smoke expectation | P2 | section 6 step 2; verified `index.ts:106-168` |
| S3 P2-2 one rollback SHA is not the live bytes for three functions | P2 | per-function SHAs verified byte-equal to live (section 6) |
| S3 P2-3 tuning entry must go in the frozen archive | P2 | **REJECTED (stale)**: the reviewer read the pre-3af16319 gate; on `origin/main` the entry lives INSIDE the review file and the archive is frozen (`check_skill_tuning_history.dart:4-6,141`); section 5 commit 7 names the review files |
| S3 P2-4 F-2 framing: default-ON switches also deviate from §4.6 step 1 | P2 | F-4 added for founder confirmation; "verbatim" softened |
| S1/S2/S3 P3s (OFF-path log prefix, webhook request_id, `:113`/`:491`, test 10 golden, primitive body, `presence_only`, line ranges, `validate-promo` smoke noise, residue restore, same-hour bucket, `--exclude-tags golden`, ledger after final SHAs, nullable columns, mirror-test citation, increment ACL + publication checks) | P3 | folded where listed above |

## 11. Round-3 resolution (confirmation round on version 2.1; every finding re-verified)

| Finding | Sev | Resolution |
|---|---|---|
| R3-1 an uncommitted migration file fails Gate 14 on every commit | P1 | verified `check_migrations_applied.dart:43-50,119-125` (working-tree `listSync`); U4 split to its own branch, drafted outside `supabase/migrations/` until the apply |
| R3-2 every catastrophic commit needs its own staged review file | P1 | verified `check_code_review_pass_exists.dart:5-12,113-141`; section 5 per-commit B-pass |
| R3-3 no positive check that `service_role`/`postgres` keep access; 42501 aborts the rehearsal | P2 | U4 verify: positive checks; `DO … EXCEPTION` blocks; grantor listed (verified migration 120:153-164 on default grants) |
| R3-4 the migration can silently become catastrophic | P2 | U4: slug `promo_codes_server_only_access`, no "security definer" text |
| R3-5 clause/mutant mapping; body read outside the race | P3 | U2: M3c-h mapped one-to-one; `resp.json()` inside the race |
| R3-6 `ca2f6f46` is not HEAD for telegram-admin-bot | P3 | section 6 note (live predates `6bfbd402`; byte-equal to the live bundle) |
| R3-7 `max_uses` missing reads NaN | P3 | U3: loose `!= null` |

Convergence: round 3 surfaced no design defect; its P1s were gate mechanics, answered by the split and
the per-commit review. The plan is CONVERGED at 2.2 for implementation.
