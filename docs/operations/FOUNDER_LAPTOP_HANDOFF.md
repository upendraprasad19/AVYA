# Hand-off — what only the founder laptop can do (2026-08-20)

> **Why this file exists.** The remote container that produced this batch can read and write the
> live Supabase project over MCP, so migrations, live queries and the `memory_embeddings` cleanup
> were all done there. Two things it genuinely cannot do: **deploy an Edge Function** (no Supabase
> Management API token reaches the container — see "Why not from the container" below) and **build
> an APK**. This note lists the deploys in dependency order with the exact commands, and how to
> prove each one actually took.
>
> Keep it current: delete a section once its deploy is verified, rather than leaving a stale
> instruction that reads as still-pending.

## Why not from the container, stated once

`deploy_via_api.js` needs a Management API token. Every source it accepts is absent there:
`SUPABASE_ACCESS_TOKEN_FITNESS` and `SUPABASE_ACCESS_TOKEN` are unset, `~/.supabase/fitness-app-token`
does not exist, and `supabase/.supabase/` is gitignored so it never came with the clone.

The MCP `deploy_edge_function` fallback was **considered and rejected, not attempted**. Root
CLAUDE.md §0 records that path silently mangling nested `../_shared/...` imports, and every
function below has them. A mangled deploy of `rolling-context` in particular does not fail loudly
— it breaks a nightly cron that summarizes and **deletes** user conversation rows.

The `supabase` CLI on the laptop is logged into the **personal** account, not the fitness-app
account (root CLAUDE.md §2a). Do not use it for these.

## Order matters

1 is independent. 2–4 ship one behaviour change together — the coach, the Sunday push and the
weekly report must stop telling a holder the same false week-4 story in the same window, or a
holder sees it corrected in one surface and not the others.

---

## 1. `rolling-context` — the app_event filter (OI-133 item 1)

**Live version before this deploy: 18.** The code is already on `main`; it is **inert until
redeployed**. Until then the nightly job keeps selecting users by an inflated message count.

```bash
cd "C:/Upendra/Claude Code/Fitness App"
git pull
node .claude/emit_payload.js rolling-context --auto --functions-dir ./supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl rolling-context .claude/_payload_rolling-context.json false
```

`rolling-context` is `verify_jwt=false` (cron-dispatched, gated by `_shared/cron_auth.ts`), which
is the last argument.

**Verify — three checks, not one:**

- **Version advanced.** The deploy script prints the new version; it must be **19** (or higher if
  something else deployed in between). A version that did not move means the payload was rejected.
- **It booted.** `curl -i -X POST https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/rolling-context`
  with no auth. A **503 means boot-broken** (parse/import error). The function's own 401/403 means
  the module loaded and rejected you, which is the healthy answer here.
- **It does the new thing.** After the next nightly run, `select count(*) from
  public.memory_embeddings where content like '%{event:%'` must still be **0**. It is 0 today (the
  92 historical rows were deleted 2026-08-20); a non-zero count afterwards means the filter is not
  live and the deploy did not take.

---

## 2–4. `ai-proxy`, `weekly-recap-ready`, `weekly-report` — FOB-3 + FOB-4

> **Status, 2026-08-21: FOB-3 has landed — deploy `ai-proxy`.** The snapshot now emits a `hold`
> block and `captain_manual.ts` has a HOLD WEEKS section telling the coach to read it. That
> section is **inert until this redeploy**. FOB-4 has NOT landed and its two functions
> (`weekly-recap-ready`, `weekly-report`) have nothing new to deploy yet — see the note at the
> bottom of this section for why FOB-4 turned out to need a migration first.

```bash
cd "C:/Upendra/Claude Code/Fitness App"
git pull
for fn in ai-proxy weekly-recap-ready weekly-report; do
  node .claude/emit_payload.js "$fn" --auto --functions-dir ./supabase/functions
  node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl "$fn" ".claude/_payload_$fn.json" true
done
```

`ai-proxy` and `weekly-report` are `verify_jwt=true`; `weekly-recap-ready` is cron-dispatched and
takes `false`. Run it as three separate commands rather than the loop if you want the flag right
per function — the loop above is wrong for `weekly-recap-ready` and is shown only for the shape.

**Today, only `ai-proxy` needs deploying:**

```bash
cd "C:/Upendra/Claude Code/Fitness App"
git pull
node .claude/emit_payload.js ai-proxy --auto --functions-dir ./supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy .claude/_payload_ai-proxy.json true
```

⚠️ **Watch for a 503 on the boot-verify below and do not shrug it off.** `captain_manual.ts` is one
long template literal, and the HOLD WEEKS section this deploy carries refers to `snapshot.hold`,
`hold.label` and friends. Those backticks are escaped in the repo (verified by parsing the
extracted declaration with node: 19831 chars, closing backtick at line 412) — but if a later edit
ever adds an unescaped one, the module stops parsing and ai-proxy 503s at boot while the OLD
bundle keeps serving. That is the failure mode that looks like nothing happened.

**FOB-4 is not deployable yet, and not for a scheduling reason.** Measured live 2026-08-21: schema
`public` contains ZERO columns matching `%hold%`, `user_progress` has no hold field of any
spelling, and there is no `workout_schedule` table in `public` at all — `is_hold` lives only on
local schedule rows. So `weekly-recap-ready` and `weekly-report` cannot branch on a hold whatever
is deployed to them. FOB-4 needs a **migration** and its own live-apply authorization first.

**Boot-verify caveat that has bitten this repo before (diagnose `f5d8c3`):** for a
`verify_jwt=true` function the unauthenticated smoke gets a **401 from the gateway before the
module loads**, so a broken bundle reads as healthy. Boot-verify with an anon-key Bearer, which
reaches the module:

```bash
curl -i -X POST https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/ai-proxy \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY"
```

**503 = boot-broken. The module's own 4xx = booted.**

---

## 5. APK build

Only from `main`, only via `/build-apk` (root CLAUDE.md §4.3) — a raw `flutter build apk` can hang
silently on that machine without the skill's pre-flight cleanup. `main` must be CI-green first.
If `main` is already green and pushed, `/build-apk --from-green` skips the redundant gate re-run.

---

## What is already done and needs nothing from the laptop

- **Migration 120** — applied live 2026-08-20, founder-authorized. Hold telemetry reaches the
  founder dashboard through `founder_metrics_engagement()`'s new `hold_*` columns with no EF
  redeploy, because `admin-dashboard-data` spreads that row wholesale.
- **Migration 121** — a **DO-NOT-APPLY reconstruction** of a migration that already ran on prod on
  2026-08-15. Its executable text is verified byte-identical to what ran. Do not apply it: the
  `cron.schedule` calls would survive a replay, but the `DELETE`s would run immediately rather
  than on schedule.
- **The 92 `memory_embeddings` rows** — deleted 2026-08-20 and verified either side (598 → 506,
  loose-pattern match now 0).
- **`enable_hold_weeks` is still OFF** and this batch does not flip it. The flip is its own commit
  needing the full ×2 review, and it must clear all three ledger rows at once.
