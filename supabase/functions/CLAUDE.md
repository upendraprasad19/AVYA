---
scope: edge_functions
parent: ../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Edge Functions — Local Rules

> This file is auto-loaded by Claude Code when working under `supabase/functions/`.
> Root CLAUDE.md (../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`supabase/functions/` holds every Deno Edge Function deployed to the
**fitness-app project (`dedsavbjuwgarrhphgnl`)**. They serve three roles:

1. **AI proxies** — the CLIENT-FACING AI calls, so API keys never live
   client-side. Exactly three: `ai-proxy`, `ai-media-proxy`, `weekly-report`.
   The food/scan/cart AI are `type` values on `ai-proxy`, not functions of their
   own — see the routing table in the AI Architecture section.
   NOT the full set of LLM callers: `rolling-context` (cron) and two client-invoked
   non-proxy functions call Gemini too — **6 in total**; the AI Architecture section
   has the list (derive it by grep, never by hand).
2. **Payment / subscription** — `verify-payment`, `razorpay-webhook`,
   `validate-promo`, `validate-referral`, `delete-account` (DPDP §17).
   `consume-day-swap` (day-swapper + sync-load batch) is quota-shaped like these
   but not payment — see the dedicated paragraph below.
3. **Cron-dispatched jobs** — FUNCTION slugs (three of these were previously
   listed under their pg_cron JOB name, which is a different string; the
   job → function mapping lives in `docs/operations/CRON_REGISTRY.md`):
   `morning-alert`, `evening-alert`, `pr-detection`, `streak-guardian`
   (job `streak-guardian-daily`), `rolling-context` (job
   `rolling-context-nightly`), `weekly-recap-ready`, `evaluate-rank-promotions`,
   `plateau-alert`, `protein-gap-alert`, `re-engagement`,
   `workout-window-closing`, `i-see-you-callout`, `clean-orphan-media`,
   `expiry-reminder`, `promote-community-item` (job
   `promote_community_item_daily`), `proactive-coach-promotion`,
   `founder-digest` (job `founder_digest_daily`, 08:00 IST — the founder's
   Telegram digest of yesterday's `usage_counters` + `alerts`; READ-ONLY, the
   one aggregate reader of the ledger, OI-153 2026-09-12).
4. **Trigger/webhook-dispatched, not cron:** `alert-critical-notify` — invoked ONLY by the
   `private.dispatch_critical_alert_notify()` trigger (migrations 133/134) via `pg_net.http_post` on a
   critical `alerts` INSERT; cron-secret authenticated via `_shared/cron_auth.ts`; telemetry in
   `cron_call_log` under `function_name = 'alert-critical-notify'`. `telegram-admin-bot` — founder's
   read-only admin console (`verify_jwt=false`, internet-facing; auth = Telegram webhook secret
   header + one allowlisted chat id, both checked in-handler). Reuses `_shared/founder_digest_content.ts`.
   Spec: `docs/superpowers/specs/2026-09-13-telegram-admin-bot-design.md`.

Shared helpers live under `_shared/`:

- `_shared/ist_date.ts` — IST date helpers (mirror of `lib/core/utils/ist_date.dart`).
- `_shared/cron_auth.ts` — service-role-key gate for every cron-dispatched function.
- `_shared/cron_telemetry.ts` — adoption-gated telemetry helper (test
  `cron_telemetry_adoption_test.dart` enforces every cron-dispatched function uses it).
- `_shared/tools/` — AI coach tool implementations (`logSet`, `logMealByText`,
  `logPR`, etc.). Imported via `from "../_shared/tools/..."` (parent dir — NOT `./_shared/`).

## Deploy protocol

Two deploy paths exist; both must produce **byte-identical output to git**.

### Preferred: host-shell deploy (any function with nested `_shared/tools/` or payload >100KB)

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js <fn> --auto --functions-dir <worktree>/supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl <fn> .claude/_payload_<fn>.json <verify_jwt>
```

- **Token:** `<primary repo>/.supabase/supabase access token.txt` WORKS and is what `.claude/token_path.js` resolves (from any worktree). `supabase/.supabase/supabase access token.txt` on the VPS holds a REVOKED token (HTTP 401, verified 2026-10-02): do not use it there (Windows clone unverified). Both gitignored.
- **Byte-identical:** no MCP path-mangling. First used Phase C.5 → `ai-proxy` v43.
- **Path scheme:** all `_shared/` imports MUST use `from "../_shared/..."` (parent dir).
  The legacy MCP `deploy_edge_function` tool silently mangled `./_shared/` imports.

### Legacy: MCP `deploy_edge_function`

Still works for small **single-file** functions. Do NOT use for `ai-proxy`
(nested `_shared/tools/`) or anything >100KB. The `supabase` CLI is logged into
the **wrong account** (Upendra's personal, not the fitness app) — never use it.

After every deploy, run a smoke test via the `/edge-function-deploy-rollback`
skill (HTTP 200 + expected response shape) and record the resulting version in
the diagnose-doc + project retrospective.

**Boot-verification caveat (diagnose f5d8c3):** for a `verify_jwt=true` function the unauthenticated
smoke gets a **401 from the GATEWAY before the module loads** — it does NOT confirm boot. Boot-verify
with an anon-key Bearer: `curl -X POST <url> -H "Authorization: Bearer <SUPABASE_ANON_KEY>"` → **503 =
boot-broken**, the module's own 4xx = booted (deploy-skill bug-class 6.5). Removed `{ encode }` imports from
`deno.land/std@>=0.210/encoding/(hex|base64)` boot-fail on the NEXT redeploy — gate
`scripts/check_std_encoding_import_rot.dart` blocks it (bug-class 6.6).

## `consume-day-swap` (day-swapper + sync-load batch)

The ONE call site of quota key `day_swap`. Input `{ week_start: "YYYY-MM-DD" }` (an IST Monday); output `{ allowed, used, limit }` or `{ error, request_id }`. `verify_jwt: true`, authenticates via `supabase.auth.getUser(token)` (CLAUDE.md §4.4 rule 9), then calls `consume_quota` (migration 130, EXECUTE revoked from PUBLIC) with `p_quota_key='day_swap'`, `p_window_start=<IST Monday 00:00 +05:30>`, `p_limit` 1 (free) / 3 (PRO), re-derived server-side from the caller's subscription row (`isProUser`), never from the request body.

**No `users.subscription_status` / `subscription_expires_at` (OI-202, migration 152).** Those mirror columns, `trg_subscription_update_user`, `update_user_subscription_status()` and `extend_subscription()` are dropped; PRO is `fetchProUserIds` / `isProUser` and any per-user expiry question is `fetchLatestActiveEndByUser` + the pure reducers, all in `_shared/subscription.ts`. A failed read returns `null` (NOT an empty map — that would print "nobody is expiring"). Deploy order when the columns are dropped: Edge Functions FIRST (razorpay-webhook 500s when its `users.update` fails). Scan: `test/contracts/subscription_columns_dropped_test.dart`.

`index.ts` is a thin `serve()` shell; every pure piece (`validateWeekStart`, `windowStartIso`,
`mapQuotaResult`, quota-key/limit constants) lives in `logic.ts` with `logic_test.ts` — the pattern for any
new EF whose validation/mapping is worth testing directly. `_shared/day_swap_routing.ts` picks the ONE
Captain-Manual block by `(isPro, capabilities)`; full routing contract and `client_capabilities.ts` parsing
rules are in `lib/features/ai_coach/CLAUDE.md` `coach_swap_workout_days`. A capability-gated tool needs
BOTH checks: the OFFER-time filter (`allTools(isPro, capabilities)` in `registry.ts`) AND the EXECUTION-time
re-check in `tool-loop.ts` (`capability_blocked` / `capability_required`) — the model can emit a
functionCall BY NAME for a tool it was never offered.

## AI Architecture (canonical)

> This table covers the CLIENT-FACING AI proxies only, NOT every function that calls an LLM (see the list
> below; it sets prompt-sanitiser and redeploy scope). `food-text-analysis`, `food-scan-analysis` and
> `cart-auditor` are NOT Edge Functions — they are `type` values POSTed to `ai-proxy`.

**Every function that calls an LLM (6).** Derived by grepping
`geminiChat|generateContent` across `supabase/functions/*/index.ts` — regenerate it that way
rather than editing by hand, because a hand-maintained list is what was wrong here twice:

- **Client-facing proxies (3, detailed in the table below):** `ai-proxy`, `ai-media-proxy`,
  `weekly-report`.
- **Client-invoked, not proxies, but they DO call Gemini (2):**
  `assess-body-composition`, `daily-snapshot`. Both are
  `verify_jwt=true` and carry no cron-auth gate — they are not cron jobs.
- **Cron-dispatched and call Gemini (1):** `rolling-context`.

`weekly-recap-ready` is NOT among the 6 — it sends the "recap ready" push and calls no model. (History of
the former 15-function list and the `cron-ai-removal` batch:
`docs/superpowers/specs/2026-09-16-proactive-cron-ai-removal-design.md`.)

| Function | Model | Tier | Notes |
|---|---|---|---|
| `ai-proxy` | Gemini 3.1 Flash Lite (`MODEL_FLASH` chat/food/prediction, `MODEL_FLASH_LITE` vision types — one slug today) | Chat: free 7/day forever (no trial), PRO 20/day (not unlimited); numbers in `_shared/ai_limits.ts` | Single chat entry, and the ONLY host of the food/scan/cart AI. Inserts placeholder row BEFORE Gemini call (rate-limit trigger SoT). 60s client dedup + placeholder dedup + 3-strike circuit breaker. Per-`type` routing table below. |
| `ai-media-proxy` | Gemini 3.1 Flash Lite (`MODEL_FLASH_LITE`, Vision) | **5 free LIFETIME image analyses, then PRO** · video PRO-only · **PRO: 10 images / 5 videos per IST day** (`pro_media_daily_caps` row below). Free gate = `usedSoFar >= FREE_IMAGE_ANALYSIS_LIMIT` in the serve handler (cite by SYMBOL), metered on `usage_counters` (`free_image_analysis`, `'epoch'`). | SSRF allowlist (`ALLOWED_BUCKETS`): `chat-media`, `coach-media`, `progress-photos` only + user-scope assertion on path (OI-28), evaluated over the URL as `fetch` will REQUEST it (`parseStorageUrl` uses `new URL()`; `..` / `%2e%2e` cannot pass). The cap key follows Storage's content-type, not the client's `media_type`; `checkFreeImageQuota` runs pre-fetch AND post-fetch. Pins: `ai-media-proxy/index_test.ts`. Provenance: `docs/architecture/functions-detail.md`. |
| `weekly-report` | Gemini 3.1 Flash Lite (`MODEL_PRO`, `thinking: "on"`) | **1 free LIFETIME report, then PRO** | The Weekly Report deep-dive; the thinking-on Gemini function (not `weekly-recap-ready`, which calls no model). Free gate: `if (!hasPro && !isFirstReport) return 403`; metered on `usage_counters` (quota_key `weekly_report_free`, `'epoch'` window). |

### `ai-proxy` request types (NOT separate Edge Functions)

Source of truth: `supabase/functions/ai-proxy/index.ts:14-16` (the function's own header).
Client call sites are all `SupabaseService.callFunction(AppConstants.aiProxyFunction, …)`.

| `type` | Model | Cap | Client call site |
|---|---|---|---|
| `food_text_analysis` | `gemini-3.1-flash-lite`, JSON mode | 10/day free · 200/day PRO — enforced atomically by the `trg_food_text_rate_limit` Postgres trigger (live definition migration 129; read the cap from the HIGHEST-numbered migration defining the function), which raises `food_text_daily_limit_reached` (SQLSTATE P0001) → 429 | `lib/features/nutrition/providers/nutrition_provider.dart` |
| `scan_meal` | `gemini-3.1-flash-lite` (vision), JSON mode | **COMBINED with `cart_auditor` (free 4/day, PRO 20/day since migration 153)** — one shared budget, not two independent caps (OI-46; 15→20 by migration 114). Enforced atomically by `trg_vision_analysis_rate_limit` (live definition migration 129, quota_key `vision_analysis`), which raises `vision_analysis_daily_limit_reached` (SQLSTATE P0001) → 429. | `nutrition_provider.dart` |
| `cart_auditor` | `gemini-3.1-flash-lite` (vision), JSON mode | **COMBINED with `scan_meal` (free 4/day, PRO 20/day)** — same shared budget as above, same trigger. | `nutrition_provider.dart:1445` |

`prediction` (`gemini-3.1-flash-lite`, JSON mode) — 3/day per user on `usage_counters` quota_key `prediction_daily`, consumed by `_shared/prediction_handler.ts` BEFORE Gemini (fail-closed on a ledger error, 429 at the cap, non-retried 500 on Gemini failure); server-owned system prompt — the request's `context.system_prompt` is ignored. Kill switch: secret `DISABLE_PREDICTION_QUOTA=true` skips the ledger only (read per call; name/rule in `_shared/prediction_quota_switch.ts`, also read by the founder digest). Client: `AiService.predict`; automatic refreshes get one attempt per IST day (`PredictionAttemptGate`); only a 429 with `code: RATE_LIMITED` reads as the daily limit. Request-size limits for every `type` are validated once by `_shared/ai_proxy_input_limits.ts`.

Chat (`type` omitted or `"chat"`, `channel='app'` in `ai_coach_interactions`) is free 7/day forever ·
PRO 20/day — enforced atomically by `trg_chat_app_rate_limit` (live definition migration 153: counts ONLY the `model_used='pending'` reservation row, so PRO media rows on channel `app` spend no chat unit; created by 111, usage_counters since 129), which raises
`chat_app_daily_limit_reached` (SQLSTATE P0001) → 429. All three triggers (food_text, chat, vision)
use the insert-first "reservation" pattern: the row is inserted (or updated) BEFORE calling Gemini,
so a capped request never pays for a model call it can't keep — Edge Function catches the trigger's
error message substring and maps it to a 429 without ever reaching `geminiChat()`.

Note `scan_meal` — the `type` is NOT `food-scan-analysis`; the old table named a slug that
never existed on either side of the wire.

Every AI proxy enforces input limits server-side: **message ≤ 5K chars**,
**snapshot ≤ 10K chars** (CLAUDE.md §4.4 rule 18). Every catch block returns
`{error: "Internal server error", request_id: <8-char hex>}` and logs
`console.error("[fn-name] request_id=X", err)` — never `JSON.stringify(err)`
into the response body (CLAUDE.md §4.4 rule 17).

## Single-source-of-truth contracts

| Concept | Writer | Reader |
|---|---|---|
| `ai_proxy_placeholder_resolution` | `ai-proxy/index.ts` inserts placeholder row → calls Gemini → updates row | client-side dedup checks placeholder before issuing new request. |
| `food_text_analysis_daily_cap` | `trg_food_text_rate_limit` trigger (live def migration 129) on `ai_coach_interactions`, quota_key `food_text` | `ai-proxy` renders the 429 from `FOOD_TEXT_FREE_DAILY_CAP`/`FOOD_TEXT_PRO_DAILY_CAP` (pinned by `food_text_analysis_daily_cap_writer_to_reader_test.dart`). |
| `chat_app_daily_cap` | `trg_chat_app_rate_limit` trigger (live def migration 129, PRO-aware), channel='app', quota_key `chat_app` | `ai-proxy` catches `chat_app_daily_limit_reached` → 429; client maps to "Daily message limit reached". |
| `vision_analysis_daily_cap` | `trg_vision_analysis_rate_limit` trigger (live def migration 153: free 4 / PRO 20), quota_key `vision_analysis`, channels `scan_meal`+`cart_auditor` — one shared budget | `ai-proxy` catches `vision_analysis_daily_limit_reached` → 429. |
| `weekly_report_free_gate` | `consume_quota('weekly_report_free', 'epoch')` in `weekly-report/index.ts`, `!hasPro`, AFTER the `ai_coach_interactions` insert | the function's advisory `usage_counters` read → `isFirstReport` → 403. **TWO writes, both required.** Read uses **`.maybeSingle()`, never `.single()`** (absent row = `used = 0` = GRANT; only a populated `error` fails closed). Pins: `weekly_report_lifetime_meter_test.dart`, `weekly_report_pro_gate_writer_to_reader_test.dart`. |
| `media_free_image_lifetime_gate` | `consume_quota('free_image_analysis', 'epoch')` in `ai-media-proxy/index.ts`, AFTER the interaction insert | advisory read `readFreeImageQuota` → 5-lifetime gate. **TWO writes, both required**; `.maybeSingle()`; fails CLOSED (`gate_reason: "quota_unavailable"`). `checkFreeImageQuota` is called from TWO sites (pre-fetch and post-fetch mirror) — removing the mirror lets a free user bypass the cap by labelling images "video". Pins: `media_free_image_lifetime_gate_writer_to_reader_test.dart`, `pro_media_daily_caps_writer_to_reader_test.dart`. |
| `pro_media_daily_caps` | ONE atomic `consume_quota(proQuotaKey, istDayStartIso(), proCap)` in `ai-media-proxy/index.ts`, `isPro`, AFTER `fetchImageAsBase64` and BEFORE `geminiChat` — `pro_image_daily` (10) / `pro_video_daily` (5; was 50/10 until Part B, 2026-10-01) by content-type-reconciled `isVideo` | RPC `-1` → HTTP 200 `gated: true`, `gate_reason: pro_image_daily_limit_reached` / `pro_video_daily_limit_reached`, `COACH_REPLIES.proImageDailyCapReached(proCap)` / `proVideoDailyCapReached(proCap)`, `resets_at` = next IST midnight; RPC error → `pro_quota_unavailable`, subscriptions-read error → `tier_unavailable`, both fail CLOSED. Consume-FIRST here, consume-AFTER for the free meter (deliberate). Pin: `pro_media_daily_caps_writer_to_reader_test.dart`. |
| `chat_media_signed_url` | `ai-media-proxy` issues short-TTL signed URL after SSRF allowlist check | `WardroomChatBubble` photo renderer. |
| `day_swap_allowance` (server half) | `consume-day-swap/index.ts` — one atomic `consume_quota('day_swap', <IST Monday window>, limit)`, called AFTER the phone's optimistic +1 (see `lib/core/services/CLAUDE.md`) | `DaySwapAllowance._consume` background reply; `mapQuotaResult` (`logic.ts`) → `{allowed, used, limit}`. |
| `delete_account_rate_limit` | `consume_quota('delete_account', <hourly bucket>)` at the TOP of `delete-account/index.ts`, 429 on `-1` | none (hard gate). Fails OPEN on a `consume_quota` error (DPDP §17 erasure must not be blocked) — the OPPOSITE of `verify_payment_rate_limit`. Pin: `delete_account_rate_limit_writer_to_reader_test.dart`. |
| `verify_payment_rate_limit` | `consume_quota('verify_payment', <10-minute bucket>)` at the TOP of `verify-payment/index.ts`, 429 on `-1` | none (hard gate). Fails CLOSED on a `consume_quota` error (background confirmation only). Pin: `verify_payment_rate_limit_writer_to_reader_test.dart`. |
| `log_client_error_payload` | client `ErrorTelemetry.recordNonFatal` POSTs to `log-client-error` Edge Function (rate-limit 100→2000/window, `next_window_at` signal, HIGH_PRIORITY_OP_TYPES bypass) | `client_errors` Postgres table + audit queries. APK Test #16.1 / D silent-drop fix. |
| `gemini_failure_alert` | `_shared/gemini_failure_alert.ts` `reportGeminiExhaustion(client, source, lastError, endpoint?)` on total Gemini exhaustion: `ai-proxy` (food_text_analysis, scan_meal, cart_auditor, prediction via `prediction_handler.ts`), `tool-loop.ts` hard-failure catch (chat), and `weekly-report` / `ai-media-proxy` / `assess-body-composition` / `daily-snapshot` / `rolling-context`. Inserts into `public.alerts` (trigger migration 133 → founder Telegram). `source` = `ai_proxy_gemini_exhausted` for live user-invoked sites (30-min dedup spans the app); cron `rolling-context` uses its OWN `rolling_context_gemini_exhausted`. Kill-switch `DISABLE_GEMINI_FAILURE_ALERT`. Server-side wiring has no mechanical gate (client side: `check_gemini_retry_and_telemetry_coverage.dart`). Modules that `serve(...)` at module scope are covered by source-grep tests; `daily-snapshot` has behavioral tests. Provenance: `docs/architecture/functions-detail.md`. | `alerts` table → Telegram, founder-only. |
| Cron auth gate | `_shared/cron_auth.ts` (service-role-key + JWT decode fallback) | every cron-dispatched function. Adoption gated by `cron_auth_adoption_test.dart`. |
| Cron telemetry | `_shared/cron_telemetry.ts` | every cron-dispatched function. Adoption gated by `cron_telemetry_adoption_test.dart`. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| **A `_shared/` change breaks a test in a function folder you never opened** | CI runs `deno test --no-check --allow-all supabase/functions/` over the WHOLE tree, not per-function. Before pushing any `_shared/` change run that exact command locally with `--node-modules-dir=none` (~21 s / 739 tests measured). | PR #47, `bd6e5b1f` (`telegram-admin-bot/index_test.ts` fake lacked `.in()`) |
| **Deploying from a feature branch that is behind `main` rolls back main's live code** | A deploy uploads the WHOLE bundle from the local tree. Before any non-`main` deploy: `git fetch origin main` then `git diff --name-only HEAD...origin/main -- supabase/functions`; non-empty and touching the function or an imported `_shared` file ⇒ merge `origin/main`, `deno check`, then deploy. | 2026-09-28 near-miss (merge `19b42747`) |
| API key in client | ALL AI calls through Edge Functions. Never expose API keys client-side. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Promo code enumeration | `validate-promo` requires JWT auth. Never expose promo discount_pct to unauthenticated callers. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Edge Function leaks stack trace | Every catch block MUST return `{error: "Internal server error", request_id: <8-char hex>}` and log `console.error("[fn-name] request_id=X", err)` server-side. Never `JSON.stringify(err)` into the response body. Validation errors (400s) are the only exception — they ARE user-actionable and safe to return verbatim. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| food_text_analysis 429 when user is below daily cap | Trigger `trg_food_text_rate_limit` (live def migration 129) enforces 10/day free / 200/day PRO atomically; read the cap from the HIGHEST-numbered migration defining it. Insert-first: `ai-proxy` inserts a placeholder BEFORE Gemini; on `food_text_daily_limit_reached` (P0001) return 429. Do NOT re-add a check-then-insert pre-check. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Cron jobs send `Authorization: Bearer null` → 401 every tick | Vault `service_role_key` must be populated; resolve via `private.morning_alert_get_service_key()`, never hardcode the anon JWT. pg_cron reports "succeeded" for `net.http_post()` regardless of HTTP status. Closed 2026-05-12. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| `pr-detection` cron loops 401 despite the Vault fix | The in-function gate compares `token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")`; the Vault JWT drifted from the env key. Founder-only fix: re-copy the service_role JWT into Vault. Affects every C-4-gated cron function. Diagnose 5a65bd. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| `client.functions.invoke()` 409 inside try is dead code | `supabase_flutter ^2.12.0` THROWS `FunctionException` on any non-2xx. `if (resp.status == 409)` inside `try` never executes. Detect via `catch (e) { if (e is FunctionException && e.status == 409) ... }`. APK Test #12.5 root cause. | `feedback_function_exception_class.md` |
| Used `supabase` CLI to set a secret | CLI is logged into Upendra's personal account, NOT the fitness app account. Use MCP tools or the Supabase Dashboard logged in as `myfitnessjourney1988@gmail.com`. Root CLAUDE.md §2a. | Root CLAUDE.md §2a |
| **Local `deno check` / `deno test` silently rewrites the tracked `node_modules/`** | Always pass **`--node-modules-dir=none`** (`deno check --node-modules-dir=none supabase/functions/<fn>/index.ts`; `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/<fn>/`). Recovery: `rm -f node_modules/pg && rm -rf node_modules/.deno && git checkout -- node_modules/`. Keep module scope side-effect-free (`if (import.meta.main) serve(handler)`); a module reading `SUPABASE_URL` at import needs `Deno.env.set(...)` BEFORE a dynamic `await import("./index.ts")`. | OI-153 (2026-09-12) |
| **A Telegram fetch error's `.message` carries the bot token** | Never log/store `err` or `err.message` from a Telegram fetch; surface `err.name` only (`founder-digest`'s `telegramErrorSummary`). `morning-alert`'s sender lacks this guard (filed as an OI). | OI-153 (2026-09-12) |

## Tests pinning the rules here

- `test/contracts/`: `ai_proxy_placeholder_resolution_test`, `ai_proxy_day_injection_test`, `ai_media_proxy_{ssrf_allowlist,user_scope,status_code_classification,telemetry}_test`, `media_free_image_lifetime_gate_writer_to_reader_test`, `pro_media_daily_caps_writer_to_reader_test`, `coach_replies_test` (server-client copy mirror), `delete_account_rate_limit_writer_to_reader_test`, `verify_payment_rate_limit_writer_to_reader_test`, `cron_auth_adoption_test`, `cron_telemetry_adoption_test`, `food_text_analysis_daily_cap_test`, `vision_analysis_daily_cap_test` (pins the `COMBINED with` / `20/day COMBINED` wording of the `scan_meal`/`cart_auditor` rows above), `edge_function_{safety,503_retry,cold_start_retry_behavioral,storage_race_retry}_test`, `error_telemetry_payload_contract_test`, `chat_media_signed_url_test`.
- Deno: `supabase/functions/ai-media-proxy/index_test.ts` (user-scope guard over the RESOLVED URL, behavioural).

## See also

- `supabase/migrations/CLAUDE.md` — migration header convention + backups manifest pairing.
- `docs/architecture/functions-detail.md` — moved-out history, provenance and correction notes for this file.
- `docs/architecture/ai.md` — model matrix + tool dispatcher + semantic retrieval.
- `docs/architecture/payment.md` — Razorpay flow + DPDP delete-account.
- `.claude/skills/edge-function-deploy-rollback/SKILL.md` — emit-payload → byte-identical-deploy → smoke flow.
- Root CLAUDE.md §0 (deploy commands) + §2a (account identity) + §4.4 (rules 16-19).
