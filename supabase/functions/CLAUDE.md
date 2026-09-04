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
   ⚠️ These three are NOT the full set of functions that call an LLM. Nine of the
   cron jobs in role 3 below call Gemini too, as do three client-invoked
   non-proxy functions — **15 in total**. The AI Architecture section carries the
   complete list; derive it by grep, never by hand.
2. **Payment / subscription** — `verify-payment`, `razorpay-webhook`,
   `validate-promo`, `validate-referral`, `delete-account` (DPDP §17).
3. **Cron-dispatched jobs** — FUNCTION slugs (three of these were previously
   listed under their pg_cron JOB name, which is a different string; the
   job → function mapping lives in `docs/operations/CRON_REGISTRY.md`):
   `morning-alert`, `evening-alert`, `pr-detection`, `streak-guardian`
   (job `streak-guardian-daily`), `rolling-context` (job
   `rolling-context-nightly`), `weekly-recap-ready`, `evaluate-rank-promotions`,
   `plateau-alert`, `protein-gap-alert`, `re-engagement`,
   `workout-window-closing`, `i-see-you-callout`, `clean-orphan-media`,
   `expiry-reminder`, `promote-community-item` (job
   `promote_community_item_daily`), `proactive-coach-promotion`.

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

- **Token:** auto-resolved from `supabase/.supabase/supabase access token.txt` (gitignored).
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

**Boot-verification caveat (2026-06-08, diagnose f5d8c3):** for a `verify_jwt=true`
function (verify-payment, ai-media-proxy, weekly-report…) the unauthenticated smoke
gets a **401 from the GATEWAY before the module loads** — it does NOT confirm the
module booted, so a parse/import error reads as "healthy". Boot-verify with an
anon-key Bearer (reaches the module): `curl -X POST <url> -H "Authorization: Bearer
<SUPABASE_ANON_KEY>"` → **503 = boot-broken**, the module's own 4xx = booted. See
`/edge-function-deploy-rollback` bug-class 6.5. **Latent dep-rot (diagnose d4c8e1):**
an import of the REMOVED `{ encode }` from `deno.land/std@≥0.210/encoding/(hex|base64)`
boot-fails only on the NEXT redeploy of each affected function (the old bundle keeps
serving) — gate `scripts/check_std_encoding_import_rot.dart` blocks it (deploy-skill bug-class 6.6).

## AI Architecture (canonical)

> ⚠️ **This table covers the CLIENT-FACING AI proxies only. It is NOT the list of functions
> that call an LLM.** Twelve cron-dispatched functions also call Gemini (they are listed
> below). Read the full list before making any "does this function touch a model?" decision —
> that judgement sets prompt-sanitiser scope and redeploy scope, and this table alone will
> under-count it by a factor of five.
>
> Also: `food-text-analysis`, `food-scan-analysis` and `cart-auditor` are **NOT** Edge
> Functions — they are `type` values POSTed to `ai-proxy`. The table claimed they were
> separate functions until 2026-07-28.

**Every function that calls an LLM (15).** Derived by grepping
`geminiChat|generateContent` across `supabase/functions/*/index.ts` — regenerate it that way
rather than editing by hand, because a hand-maintained list is what was wrong here twice:

- **Client-facing proxies (3, detailed in the table below):** `ai-proxy`, `ai-media-proxy`,
  `weekly-report`.
- **Client-invoked, not proxies, but they DO call Gemini (3):**
  `assess-body-composition`, `daily-snapshot`, `future-prediction`. All three are
  `verify_jwt=true` and carry no cron-auth gate — they are not cron jobs.
- **Cron-dispatched and call Gemini (9):** `morning-alert`, `plateau-alert`, `pr-detection`,
  `proactive-coach-promotion`, `protein-gap-alert`, `re-engagement`, `rolling-context`,
  `streak-guardian`, `workout-window-closing`.

These 15 are exactly the set the OI-47 prompt-sanitiser had to cover. `weekly-recap-ready` is
NOT among them — it sends the "recap ready" push and calls no model.

| Function | Model | Tier | Notes |
|---|---|---|---|
| `ai-proxy` | Gemini 2.5 Flash (`MODEL_FLASH`) + Gemini 2.5 Flash Lite (`MODEL_FLASH_LITE`) for the vision types | Free 10/day forever (no trial), PRO unlimited | Single chat entry, and the ONLY host of the food/scan/cart AI. Inserts placeholder row BEFORE Gemini call (rate-limit trigger SoT). 60s client dedup + placeholder dedup + 3-strike circuit breaker (APK Test #16.1 / Theme B). Per-`type` routing table below. |
| `ai-media-proxy` | Gemini 2.5 Flash **Lite** (Vision) — `MODEL_FLASH_LITE`, self-labelled at `ai-media-proxy/index.ts:119` | PRO only | Photo/video chat. SSRF allowlist (`ALLOWED_BUCKETS`, `ai-media-proxy/index.ts:170-174`, verified live 2026-07-30): `chat-media`, `coach-media`, `progress-photos` Storage buckets only + user-scope assertion on path (OI-28). Corrected in the coach-media-consent batch — this row previously said `progress-photos` + `chat-attachments`, a bucket name (`chat-attachments`) that has never existed in this codebase and was stale from before `coach-media` (migration 070) was added to the allowlist. |
| `weekly-report` | Gemini 2.5 Pro (`MODEL_PRO`) — deepest reasoning | PRO only | The Weekly Report deep-dive. **This is the Gemini 2.5 Pro function** — not `weekly-recap-ready`, which only sends the "recap ready" push and calls no model at all. |

### `ai-proxy` request types (NOT separate Edge Functions)

Source of truth: `supabase/functions/ai-proxy/index.ts:14-16` (the function's own header).
Client call sites are all `SupabaseService.callFunction(AppConstants.aiProxyFunction, …)`.

| `type` | Model | Cap | Client call site |
|---|---|---|---|
| `food_text_analysis` | `gemini-2.5-flash`, JSON mode | 10/day free · 200/day PRO — enforced atomically by the `trg_food_text_rate_limit` Postgres trigger (live definition migration 127; created by 026, IST boundary fixed by 113, free arm lowered 50→10 by 127 per b8f4c2), which raises `food_text_daily_limit_reached` (SQLSTATE P0001) → 429 | `lib/features/nutrition/providers/nutrition_provider.dart:733` |
| `scan_meal` | `gemini-2.5-flash-lite` (vision), JSON mode | **20/day COMBINED with `cart_auditor`** — one shared budget, not two independent caps (corrected 2026-07-29, OI-46; raised 15→20 same day, usage-counter-race batch, to match the documented PRO product promise of 10+10 independent — see `docs/architecture/business-rules.md`). Enforced atomically by `trg_vision_analysis_rate_limit` (migration 111, cap raised via migration 114's `CREATE OR REPLACE`), which raises `vision_analysis_daily_limit_reached` (SQLSTATE P0001) → 429. | `nutrition_provider.dart:1356` |
| `cart_auditor` | `gemini-2.5-flash-lite` (vision), JSON mode | **20/day COMBINED with `scan_meal`** — same shared budget as above, same trigger. | `nutrition_provider.dart:1445` |

Chat (`type` omitted or `"chat"`, `channel='app'` in `ai_coach_interactions`) is free 10/day forever ·
PRO unlimited — enforced atomically by `trg_chat_app_rate_limit` (migration 111), which raises
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
| `food_text_analysis_daily_cap` | `trg_food_text_rate_limit` Postgres trigger (live definition migration 127) on `ai_coach_interactions` | `ai-proxy` renders the 429 body from `FOOD_TEXT_FREE_DAILY_CAP`/`FOOD_TEXT_PRO_DAILY_CAP` (pinned to the trigger by `food_text_analysis_daily_cap_writer_to_reader_test.dart`); client maps 429 → "limit reached". |
| `chat_app_daily_cap` | `trg_chat_app_rate_limit` Postgres trigger (migration 111, PRO-aware) on `ai_coach_interactions`, channel='app' | `ai-proxy/index.ts` catches `chat_app_daily_limit_reached` → 429; client maps to "Daily message limit reached". |
| `vision_analysis_daily_cap` | `trg_vision_analysis_rate_limit` Postgres trigger (migration 111, cap raised 15→20 by migration 114) on `ai_coach_interactions`, channel IN ('scan_meal','cart_auditor') — one shared 20/day budget | `ai-proxy/index.ts` catches `vision_analysis_daily_limit_reached` → 429; client maps to "Daily vision analysis limit reached". |
| `chat_media_signed_url` | `ai-media-proxy` issues short-TTL signed URL after SSRF allowlist check | `WardroomChatBubble` photo renderer. |
| `log_client_error_payload` | client `ErrorTelemetry.recordNonFatal` POSTs to `log-client-error` Edge Function (rate-limit 100→2000/window, `next_window_at` signal, HIGH_PRIORITY_OP_TYPES bypass) | `client_errors` Postgres table + audit queries. APK Test #16.1 / D silent-drop fix. |
| Cron auth gate | `_shared/cron_auth.ts` (service-role-key + JWT decode fallback) | every cron-dispatched function. Adoption gated by `cron_auth_adoption_test.dart`. |
| Cron telemetry | `_shared/cron_telemetry.ts` | every cron-dispatched function. Adoption gated by `cron_telemetry_adoption_test.dart`. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| API key in client | ALL AI calls through Edge Functions. Never expose API keys client-side. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Promo code enumeration | `validate-promo` requires JWT auth. Never expose promo discount_pct to unauthenticated callers. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Edge Function leaks stack trace | Every catch block MUST return `{error: "Internal server error", request_id: <8-char hex>}` and log `console.error("[fn-name] request_id=X", err)` server-side. Never `JSON.stringify(err)` into the response body. Validation errors (400s) are the only exception — they ARE user-actionable and safe to return verbatim. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| food_text_analysis 429 when user is below daily cap | Trigger `trg_food_text_rate_limit` on `ai_coach_interactions` (live definition migration 127, 2026-09-04; created by 026) enforces the 10/day free / 200/day PRO cap atomically. ⚠ The free arm was 50/day until b8f4c2 while the client and business-rules both said 10 — read the cap from the HIGHEST-numbered migration defining the function, never from 026. Insert-first pattern — `ai-proxy` inserts a placeholder row BEFORE calling Gemini. If trigger raises `food_text_daily_limit_reached` (SQLSTATE P0001), return 429. Do NOT re-add a separate check-then-insert pre-check; the trigger is the single source of truth. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Cron jobs send `Authorization: Bearer null` → 401 every tick | Closed by user action 2026-05-12 (audit P0 Vault fix). Cause: `private.morning_alert_get_service_key()` reads `vault.decrypted_secrets WHERE name='service_role_key'`; the Vault row had never been populated, so the function returned `NULL` and every cron job sent `Bearer null` → Edge Function gateway 401. 12 cron jobs affected (0 successful invocations across thousands of attempts). pg_cron reports "succeeded" for `net.http_post()` dispatches regardless of HTTP response — symptom invisible from `cron.job_run_details`. Fix: Dashboard → Settings → Vault → add secret named exactly `service_role_key` with the project's service_role JWT. **Don't add new cron jobs that hardcode the anon JWT** — always resolve via `private.morning_alert_get_service_key()` (migration 061 P1-D retrofitted `rolling-context-nightly` + `streak-guardian-daily` to this pattern). Server-side cron execution telemetry is still a gap — `client_errors` doesn't capture these failures (audit 2026-05-12 M2 follow-up). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| `pr-detection` cron loops 401 every 15 min despite audit P1-D fix | Closed (operational fix flagged to founder) in APK Test #16 (2026-05-15). Audit 2026-05-11 C-4 / 2026-05-12 P1-D `private.morning_alert_get_service_key()` retrofit was applied correctly to every cron entry — the `cron.job.command` for `pr-detection` (jobid 9) USES `Bearer ' \|\| private.morning_alert_get_service_key()`. The Vault row IS populated (219-char real JWT). **Actual root cause:** the in-function gate at `supabase/functions/pr-detection/index.ts:56` compares `token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")`. Between 2026-05-11 and 2026-05-15 the Vault-stored JWT and the env-injected `SUPABASE_SERVICE_ROLE_KEY` drifted (likely Supabase platform-side rotation or someone re-saved Vault). Equality check fails → 401. **Operational fix (founder-only):** Dashboard → Settings → API → copy current service_role JWT → Dashboard → Settings → Vault → edit row `service_role_key` → paste → save. **Class fix deferred:** replace the brittle env-equality check in `_shared/cron_auth.ts` with a JWT signature+role decode. Migration 065 ships a sanity-audit DO block that warns on hardcoded JWTs or `app.settings.service_role_key` (which returns NULL on this project — flagged jobid 7 `promote_community_item_daily` as separate deferred bug). Same shape affects every C-4-gated function (re-engagement, plateau-alert, protein-gap-alert, workout-window-closing, streak-guardian, evaluate-rank-promotions, i-see-you-callout, clean-orphan-media, expiry-reminder, weekly-recap-ready) — all latent on the same drift. closes-diagnose: 5a65bd. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| `client.functions.invoke()` 409 inside try is dead code | `supabase_flutter ^2.12.0` THROWS `FunctionException` on any non-2xx. `if (resp.status == 409)` inside `try` never executes. Detect via `catch (e) { if (e is FunctionException && e.status == 409) ... }`. APK Test #12.5 root cause. | `feedback_function_exception_class.md` |
| Used `supabase` CLI to set a secret | CLI is logged into Upendra's personal account, NOT the fitness app account. Use MCP tools or the Supabase Dashboard logged in as `myfitnessjourney1988@gmail.com`. Root CLAUDE.md §2a. | Root CLAUDE.md §2a |

## Tests pinning the rules here

- `test/contracts/ai_proxy_placeholder_resolution_test.dart`
- `test/contracts/ai_proxy_day_injection_test.dart`
- `test/contracts/ai_media_proxy_ssrf_allowlist_test.dart`
- `test/contracts/ai_media_proxy_user_scope_test.dart`
- `test/contracts/ai_media_proxy_status_code_classification_test.dart`
- `test/contracts/ai_media_proxy_telemetry_test.dart`
- `test/contracts/cron_auth_adoption_test.dart`
- `test/contracts/cron_telemetry_adoption_test.dart`
- `test/contracts/food_text_analysis_daily_cap_test.dart`
- `test/contracts/edge_function_safety_test.dart`
- `test/contracts/edge_function_503_retry_test.dart`
- `test/contracts/edge_function_cold_start_retry_behavioral_test.dart`
- `test/contracts/edge_function_storage_race_retry_test.dart`
- `test/contracts/error_telemetry_payload_contract_test.dart`
- `test/contracts/chat_media_signed_url_test.dart`

## See also

- `supabase/migrations/CLAUDE.md` — migration header convention + backups manifest pairing.
- `docs/architecture/ai.md` — model matrix + tool dispatcher + semantic retrieval.
- `docs/architecture/payment.md` — Razorpay flow + DPDP delete-account.
- `.claude/skills/edge-function-deploy-rollback/SKILL.md` — emit-payload → byte-identical-deploy → smoke flow.
- Root CLAUDE.md §0 (deploy commands) + §2a (account identity) + §4.4 (rules 16-19).
