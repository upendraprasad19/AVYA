---
date: 2026-09-13
status: brainstormed — awaiting founder spec review
topic: telegram-admin-bot
---

# Telegram admin bot — design spec

## 1. Problem

`@IcanbefitterBot` was reset on 2026-09-12 (59 old OpenClaw commands cleared) and is
today **push-only**: nothing consumes incoming messages, there is no command menu,
and the founder has no way to ask the bot anything on demand. The only automated
signal reaching Telegram is `founder-digest`, a once-a-day (08:00 IST) usage-only
summary — and it is not yet on `main` (see §7).

The founder wants every admin touch point available inside the bot: on-demand
reports, a browsable user list, and same-day visibility into subscriptions,
expirations, and system issues — without leaving Telegram.

## 2. Scope (locked)

- **v1 is read-only.** No command changes any state. Confirmed explicitly —
  action-taking (grant/revoke PRO, resend digest as a mutation, etc.) is out of
  scope for this batch.
- **Critical alerts push immediately**, not just inside the daily digest.
- Out of scope for this batch (see §8): closing the underlying observability gaps
  the bot's commands surface (payment-flow alerting, the Edge-Function auth-outage
  blind spot, a native-crash summary, a server-side error-rate view). The bot
  reports on top of what already exists; it does not create new detection logic
  for signals that don't exist yet.

## 3. Present state (verified 2026-09-13)

- Bot: `@IcanbefitterBot`, owned by the founder, secrets `TELEGRAM_BOT_TOKEN` +
  `FOUNDER_TELEGRAM_CHAT_ID` already in the Edge Function vault (project
  `dedsavbjuwgarrhphgnl`).
- `founder-digest` Edge Function is **deployed live** (v1) and its cron
  (`founder_digest_daily`, jobid 38, `30 2 * * *` UTC = 08:00 IST) is **active in
  prod** — but the code lives only on branch `oi153-pro-media-caps`, not merged to
  `main`. Its current content: yesterday's `usage_counters` totals per quota_key,
  users at a cap, top user-id prefixes, and that day's `alerts` rows.
- `admin-dashboard-data` Edge Function (verify_jwt=true, `ADMIN_USER_IDS` gate)
  already aggregates growth/revenue/engagement/ops metrics, a subscription-expiry
  bucket, and open alerts, for the web `/admin` dashboard. The bot reuses the same
  underlying RPCs/tables, not this function itself (different auth model — see §5).
- 5 automated checks write to `public.alerts` every 15–60 min
  (`alert_payment_flow_health`, `alert_edge_function_health`,
  `alert_client_errors_spike`, `alert_cron_silence`, `alert_cron_function_dead`).
  None currently push to Telegram; they're only visible via the daily digest or a
  Claude Code session hook.

## 4. Commands (v1 — all read-only)

| Group | Command | Content |
|---|---|---|
| Daily | `/status` | Open alerts by severity, today's signups, cron health at a glance |
| | `/revenue` | MRR, active subs by plan |
| | `/subs` | New subscriptions today/yesterday (IST), monthly vs. yearly vs. trial split |
| | `/expiring` | Users expiring in 7 / 30 days |
| Users | `/users [page]` | Paginated browse, newest signup first, ~10/page |
| | `/find <text>` | Search by partial name or email |
| | `/user <email-or-id>` | One user's subscription, plan, last active, today's usage, recent error count |
| Ops | `/alerts` | Open (unresolved) alerts, most recent first |
| | `/errors` | Yesterday's errors, grouped by source (client vs. cron/Edge Function) |
| | `/cron` | Any of the active cron jobs gone silent past its expected cadence |
| Meta | `/help` | Command list |
| | `/digest` | Re-send today's digest content on demand (reuses `founder-digest`'s read+format; no state change) |

Every handler queries the same tables/RPCs `admin-dashboard-data` already reads
(`founder_metrics_for_admin_api`, `founder_metrics_ops`, `alerts`, `subscriptions`,
`usage_counters`, `users`) directly via a service-role client — no HTTP hop through
`admin-dashboard-data` itself, since its auth model (web JWT + `ADMIN_USER_IDS`)
doesn't fit a Telegram-webhook caller.

## 5. Architecture

### 5.1 `telegram-admin-bot` (new Edge Function, webhook-triggered)

- `verify_jwt=false` — Telegram does not send a Supabase JWT (same shape as
  `razorpay-webhook`).
- **Two auth checks, both required, before any command runs:**
  1. `X-Telegram-Bot-Api-Secret-Token` header matches a new secret
     `TELEGRAM_WEBHOOK_SECRET` (set once via Telegram's `setWebhook`).
  2. `message.chat.id` equals `FOUNDER_TELEGRAM_CHAT_ID`.
  Anything failing either check returns a bare `200 OK`, no reply, and no
  identifying detail logged — the endpoint must not confirm to a stranger that it
  does anything.
- Parses `message.text`, routes on the first whitespace-separated token
  (case-insensitive, leading `/` stripped).
- Every handler wrapped in its own try/catch; a thrown error replies "something
  went wrong, try again" rather than propagating — Telegram retries a non-200
  webhook response, so this function **always** returns 200 regardless of
  internal outcome.

### 5.2 `_shared/telegram.ts` (new shared helper)

Extracted from `founder-digest`'s existing `sendMessage` implementation, which
already avoids logging the raw fetch error (that error's message embeds the bot
token). Three callers after this batch: `founder-digest`, `telegram-admin-bot`,
`alert-critical-notify`. `morning-alert`'s separate, unhardened copy is untouched
— that's a distinct, already-filed issue, not folded into this batch.

### 5.3 `alert-critical-notify` (new Edge Function, trigger-invoked)

- Cron-secret authenticated only (`isAuthorizedCronCall`, same pattern as every
  other server-triggered function in this repo) — never reachable from the public
  internet with a Telegram-shaped payload.
- Single job: given one `alerts.id`, read the row and send it through
  `_shared/telegram.ts`.
- Kept **separate** from `telegram-admin-bot` rather than a second auth branch on
  it — matches this repo's existing convention of not mixing an internet-facing
  webhook surface with a trusted-caller surface in one function (the same
  reasoning that ruled out folding the bot into `founder-digest`).

### 5.4 Critical-alert trigger

`AFTER INSERT ON public.alerts FOR EACH ROW WHEN (NEW.severity = 'critical')` →
`pg_net.http_post` to `alert-critical-notify` (async — cannot block or abort the
triggering insert). The trigger body itself is wrapped in
`BEGIN ... EXCEPTION WHEN OTHERS THEN NULL END` so a `pg_net` hiccup can never roll
back the alert write it's attached to (this repo has hit the "trigger side-effect
aborts the triggering write" class before — see `docs/diagnoses/` for the prior
incident this guards against).

### 5.5 Telegram-side setup (operational, not code)

- `setWebhook` pointing at the deployed `telegram-admin-bot` URL, with
  `secret_token` set to `TELEGRAM_WEBHOOK_SECRET`.
- `setMyCommands` to populate the "/" menu in the Telegram client — this is the
  original ask ("no commands in the menu").

## 6. Data flow

```
5 alert-writing cron checks
        │  INSERT
        ▼
   public.alerts ──severity='critical'──▶ AFTER INSERT trigger ──pg_net──▶ alert-critical-notify ──▶ _shared/telegram.ts ──▶ founder's Telegram
        │
        │  (read on demand)
        ▼
  telegram-admin-bot ◀── webhook ── founder types /command in Telegram
        │
        ▼
  _shared/telegram.ts ──▶ reply in Telegram

founder-digest (unchanged trigger: cron, daily 08:00 IST)
  + new Subscriptions section (new subs yesterday, plan split)
  + new Expiring-soon section (count only; full list via /expiring)
  ──▶ _shared/telegram.ts ──▶ founder's Telegram
```

## 7. Daily digest changes

Two new sections added to `founder-digest` (currently usage-only):

- **Subscriptions** — new subs started yesterday (IST), split monthly / yearly /
  trial.
- **Expiring soon** — count of users expiring in the next 7 / 30 days (full list
  stays on-demand via `/expiring`, not inlined into the digest).

⚠ `founder-digest` is not yet merged to `main` (§3). This batch either merges it
first or ships alongside it — a decision for the implementation plan, not this
design doc.

## 8. Deferred — logging/alerting gaps surfaced but not fixed here

Identified during this brainstorm; each needs new *detection* logic, not just a
new bot command, so each is bigger than this batch:

1. **Payment-flow alerting is effectively dormant** — the one existing check
   (`alert_payment_flow_health`) fires on "too few new subscriptions," not on
   actual Razorpay webhook/signature failures, and needs volume this app doesn't
   have yet to mean anything.
2. **A total Edge-Function auth outage is invisible** — `alert_edge_function_health`
   reads a table a 401 never writes a row to.
3. **Native crashes (Crashlytics) aren't summarized anywhere day-to-day** — they
   go straight to Firebase's own console.
4. **No server-side error-rate view** — `client_errors` covers the client well;
   there's no equivalent "which Edge Function is erroring most" breakdown.

Recommendation: file as a tracked backlog item once the founder confirms — not
filed yet (filing is a board commit; per this repo's own policy nothing gets
committed without an explicit go).

## 9. Error handling

- Webhook always returns `200`, even internally — a non-200 makes Telegram retry
  the same update.
- Unknown/rejected sender: silent 200, no reply, no content logged.
- `/user` or `/find` with no match: "not found," never a stack trace or raw error.
- Trigger → notify path: never allowed to block or abort the alert INSERT it's
  attached to (§5.4).

## 10. Testing plan

- Deno tests per command handler (mocked Supabase responses) + auth-rejection
  cases (wrong chat id, wrong/missing secret token → 200 empty, no reply sent).
- Cron-auth adoption test for `alert-critical-notify` (same shape as this repo's
  existing adoption gates).
- Live rollback-transaction test for the trigger: insert a critical alert inside
  `BEGIN ... ROLLBACK`, confirm it does not throw and does not block.
- Manual smoke, once deployed: real `/status`; a synthetic critical alert to
  confirm immediate delivery, then cleanup.

## 11. Open questions for the implementation plan (not product decisions)

- Whether this batch also merges `founder-digest` to `main` first, or ships both
  together.
- Exact column names for the new Subscriptions/`/subs` section — to be verified
  live against `information_schema.columns` at implementation time, not assumed
  here.
- Whether `/users` pagination is a text argument (`/users 2`) or a Telegram inline
  keyboard — text argument recommended for v1 (no `callback_query` handling
  needed); inline buttons are a clean v2 addition if wanted later.
