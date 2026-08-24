# Hand-off — what only the founder laptop can do (2026-08-20, updated 2026-08-21)

> **Why this file exists.** The remote container that produced this batch can read and write the
> live Supabase project over MCP, so migrations, live queries and the `memory_embeddings` cleanup
> were all done there. Two things it genuinely cannot do: **deploy an Edge Function** (no Supabase
> Management API token reaches the container — see "Why not from the container" below) and **build
> an APK**. This note lists the deploys in dependency order with the exact commands, and how to
> prove each one actually took.
>
> Keep it current: delete a section once its deploy is verified, rather than leaving a stale
> instruction that reads as still-pending.

## START HERE — pulling this onto the laptop

**Nothing is unsaved.** Everything the container produced is committed and pushed:
`origin/main` is at `476bcc1` (CI run #337 green, all 7 jobs) and
`origin/claude/oi-pending-hold-weeks-1od97o` at `aad7b7f`, which is fully contained in `main`.
A pull is all that is needed.

**Check whether your local `main` is ahead BEFORE pulling.** This repo's normal workflow is
merge-locally-then-push (§4.13), so the laptop's `main` can legitimately hold commits `origin`
does not, and a blind `git pull` would turn that into a merge commit.

```bash
cd "C:/Upendra/Claude Code/Fitness App"
git fetch origin main
git rev-list --left-right --count main...origin/main
```

Read the two numbers as `<local-only> <remote-only>`:

| Output | Meaning | Do |
|---|---|---|
| `0 N` | simply behind — the expected case | `git pull origin main` fast-forwards |
| `M N` | **divergence** — you have commits that never reached GitHub | do NOT force anything; start the session and say so |
| `M 0` | ahead, nothing new upstream | nothing to pull |

Then:

```bash
git pull origin main
git log --oneline -4        # expect 476bcc1 at the top
```

**Start the session in a worktree, not in the main folder.** §4.13 is non-negotiable: the shared
main folder is integration-only (merges, pushes, `/build-apk`), because two sessions in it share
one git index and a commit from either can silently mix in the other's staged files.

```bash
sh scripts/new-worktree.sh <slug>     # copies .env for you
cd .claude/worktrees/<slug>
claude
```

`.env` is gitignored and already on the laptop; `new-worktree.sh` copies it in. Nothing else needs
restoring, re-running or re-applying.

### State of play, so a fresh session has its bearings

Landed and green on `main`: FOB-1 (week identity), FOB-5 (hold telemetry), OI-132 (the fileless
migration reconstructed + Gate 31 given a live-snapshot input), and FOB-3 (the coach's `hold`
block). `enable_hold_weeks` is still **OFF** — none of it is live for users yet, and the flip is
its own commit needing the full ×2 review and clearing all FOUR ledger rows at once.

Waiting on this machine: the two deploys in §1 and §2 below. Not next: FOB-4 — see the end of §2.

---

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

**Two deployable items today, and they are independent of each other:** §1 `rolling-context` and
§2 `ai-proxy`. Either order is fine.

Corrected 2026-08-21 — this section used to read *"2–4 ship one behaviour change together"*, on
the assumption FOB-3 and FOB-4 would land in the same batch and had to reach users in the same
window. FOB-4 did not land: it turned out to need a migration first (see the end of §2), so there
is no third or fourth deploy to sequence against.

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

## 2. `ai-proxy` — FOB-3's HOLD WEEKS manual section

FOB-3 landed 2026-08-21. The snapshot now emits a `hold` block and `captain_manual.ts` has a HOLD
WEEKS section telling the coach to read it, quote `hold.label`, and never tell a holder this is
their final week of Phase I. **That section is inert until this redeploy.**

```bash
cd "C:/Upendra/Claude Code/Fitness App"
git pull origin main
node .claude/emit_payload.js ai-proxy --auto --functions-dir ./supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy .claude/_payload_ai-proxy.json true
```

`ai-proxy` is `verify_jwt=true`, which is the last argument.

⚠️ **Watch for a 503 on the boot-verify and do not shrug it off.** `captain_manual.ts` is one long
template literal, and the section this deploy carries refers to `snapshot.hold`, `hold.label` and
friends. Those backticks are escaped in the repo (verified by parsing the extracted declaration
with node: 19831 chars, closing backtick at line 412) — but if a later edit ever adds an unescaped
one, the module stops parsing and ai-proxy 503s at boot while the OLD bundle keeps serving. That
is the failure mode that looks like nothing happened. Recorded as deploy-skill bug-class §6.8.

**ONE function, deliberately — there is no loop here any more.** This section used to open with a
`for fn in ai-proxy weekly-recap-ready weekly-report` block, above the correct single-function one.
Removed 2026-08-21 because it was the first copy-pasteable thing in the section and it is wrong to
run: `weekly-recap-ready` and `weekly-report` have no changes in this batch, so it would rewrite
two prod function configs for nothing, and it passed `verify_jwt=true` for `weekly-recap-ready`
whose documented value is `false`. (Checked rather than assumed: migration `061` has the Sunday
cron send `Authorization: Bearer <service_role_key>`, which IS a valid JWT, so the cron would most
likely still pass the gateway. "Most likely survives" is not a reason to run an unrequested prod
config change — and §4.3 wants explicit per-action authorization for each deploy anyway.)
FOB-4's commands get written when FOB-4 lands, not before.

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

## 3. APK build

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
