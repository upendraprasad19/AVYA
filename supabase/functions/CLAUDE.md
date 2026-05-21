---
scope: edge_functions
parent: ../../CLAUDE.md
created: 2026-05-18
status: scaffold
---

# Edge Functions — Local Rules

> This file is auto-loaded by Claude Code when working under `supabase/functions/`.
> Root CLAUDE.md (../../CLAUDE.md) contains process invariants and a pointer index.

<!-- MIGRATION IN PROGRESS — content from CLAUDE.md will be moved here in Milestone 2 -->

## Single-source-of-truth contracts

(populated in Milestone 2)

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| API key in client | ALL AI calls through Edge Functions. Never expose API keys client-side. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Promo code enumeration | `validate-promo` requires JWT auth. Never expose promo discount_pct to unauthenticated callers. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Edge Function leaks stack trace | Every catch block MUST return `{error: "Internal server error", request_id: <8-char hex>}` and log `console.error("[fn-name] request_id=X", err)` server-side. Never `JSON.stringify(err)` into the response body. Validation errors (400s) are the only exception — they ARE user-actionable and safe to return verbatim. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| food_text_analysis 429 when user is below daily cap | Trigger `trg_food_text_rate_limit` on `ai_coach_interactions` (migration 024, 2026-04-18) enforces the 50/day free / 200/day PRO cap atomically. Insert-first pattern — `ai-proxy` inserts a placeholder row BEFORE calling Gemini. If trigger raises `food_text_daily_limit_reached` (SQLSTATE P0001), return 429. Do NOT re-add a separate check-then-insert pre-check; the trigger is the single source of truth. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Cron jobs send `Authorization: Bearer null` → 401 every tick | Closed by user action 2026-05-12 (audit P0 Vault fix). Cause: `private.morning_alert_get_service_key()` reads `vault.decrypted_secrets WHERE name='service_role_key'`; the Vault row had never been populated, so the function returned `NULL` and every cron job sent `Bearer null` → Edge Function gateway 401. 12 cron jobs affected (0 successful invocations across thousands of attempts). pg_cron reports "succeeded" for `net.http_post()` dispatches regardless of HTTP response — symptom invisible from `cron.job_run_details`. Fix: Dashboard → Settings → Vault → add secret named exactly `service_role_key` with the project's service_role JWT. **Don't add new cron jobs that hardcode the anon JWT** — always resolve via `private.morning_alert_get_service_key()` (migration 061 P1-D retrofitted `rolling-context-nightly` + `streak-guardian-daily` to this pattern). Server-side cron execution telemetry is still a gap — `client_errors` doesn't capture these failures (audit 2026-05-12 M2 follow-up). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| `pr-detection` cron loops 401 every 15 min despite audit P1-D fix | Closed (operational fix flagged to founder) in APK Test #16 (2026-05-15). Audit 2026-05-11 C-4 / 2026-05-12 P1-D `private.morning_alert_get_service_key()` retrofit was applied correctly to every cron entry — the `cron.job.command` for `pr-detection` (jobid 9) USES `Bearer ' \|\| private.morning_alert_get_service_key()`. The Vault row IS populated (219-char real JWT). **Actual root cause:** the in-function gate at `supabase/functions/pr-detection/index.ts:56` compares `token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")`. Between 2026-05-11 and 2026-05-15 the Vault-stored JWT and the env-injected `SUPABASE_SERVICE_ROLE_KEY` drifted (likely Supabase platform-side rotation or someone re-saved Vault). Equality check fails → 401. **Operational fix (founder-only):** Dashboard → Settings → API → copy current service_role JWT → Dashboard → Settings → Vault → edit row `service_role_key` → paste → save. **Class fix deferred:** replace the brittle env-equality check in `_shared/cron_auth.ts` with a JWT signature+role decode. Migration 065 ships a sanity-audit DO block that warns on hardcoded JWTs or `app.settings.service_role_key` (which returns NULL on this project — flagged jobid 7 `promote_community_item_daily` as separate deferred bug). Same shape affects every C-4-gated function (re-engagement, plateau-alert, protein-gap-alert, workout-window-closing, streak-guardian, evaluate-rank-promotions, i-see-you-callout, clean-orphan-media, expiry-reminder, weekly-recap-ready) — all latent on the same drift. closes-diagnose: 5a65bd. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

(populated in Milestone 6)
