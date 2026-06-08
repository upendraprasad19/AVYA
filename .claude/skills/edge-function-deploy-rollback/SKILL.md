---
name: edge-function-deploy-rollback
description: Apply this skill when deploying, redeploying, or rolling back a Supabase Edge Function on the fitness-app project. Enforces emit-payload → byte-identical-deploy → smoke flow + SHA-pinned rollback path. Self-evolving — append learnings.
type: process
priority: medium
self-evolving: true
---

# Edge Function Deploy + Rollback Skill — ICANBEFITTER

> Project-local skill. Codifies the host-shell deploy flow established Phase C.5 (ai-proxy v43) and adopted as standard since. Replaces the legacy `mcp__ba7b5e8e__deploy_edge_function` tool for any function with nested `_shared/` imports or payload >100KB.

---

## 0. When to invoke

Trigger phrases / contexts:
- "deploy ai-proxy", "redeploy <fn>", "ship the new <fn>"
- "ai-proxy version", "what version of <fn> is live?"
- "rollback <fn>", "revert <fn> to v<N>"
- Any Edge Function code change merging to main that hasn't yet shipped
- Cron-failure debugging where the Edge Function code on disk diverges from production

Do NOT invoke for: pure SQL migrations (those go through Supabase MCP `apply_migration`); client-only fixes; documentation-only edits.

---

## 1. Pre-flight checks (5 minutes)

### 1.1 Confirm project ID
ALWAYS verify `project_id = dedsavbjuwgarrhphgnl` BEFORE any deploy. There are two projects on the account — the OTHER one (`krcrkntuwutvnmdnkfqf`) is the blog/website. Deploying to the wrong project corrupts a different app. Per CLAUDE.md §2a.

### 1.2 Check git tree is clean
```bash
git status
```
The deploy ships whatever is in `supabase/functions/<fn>/` on disk. Uncommitted local changes WILL ship if you proceed. If unsure: `git stash` or commit first.

### 1.3 Confirm token presence
```bash
ls -l "supabase/.supabase/supabase access token.txt"
```
Generated 2026-04-20 against fitness-app account (org `hwwukmntixflgbxkwavm`). Gitignored. If missing, regenerate via Supabase dashboard logged in as `myfitnessjourney1988@gmail.com` (NOT the personal account).

### 1.4 Check secrets required by the function
Every Edge Function reads from Vault via `Deno.env.get()`. If you're deploying a NEW function or one that references a NEW secret:
```sql
SELECT name FROM vault.decrypted_secrets WHERE name LIKE '%<your-pattern>%';
```
Missing secrets → 500 at runtime, no clue in deploy logs.

---

## 2. Standard deploy (existing function, byte-identical from git)

```bash
cd "C:/Upendra/Claude Code/Fitness App"

# Step 1 — emit the payload from disk
node .claude/emit_payload.js <fn> --auto --functions-dir "$PWD/supabase/functions"

# Step 2 — deploy via REST
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl <fn> .claude/_payload_<fn>.json <verify_jwt>
```

Where:
- `<fn>` = function slug (e.g. `ai-proxy`, `morning-alert`, `verify-payment`)
- `<verify_jwt>` = `true` (most functions — requires Supabase auth on caller) or `false` (cron-triggered functions with their own auth)

### 2.1 Path convention (NON-NEGOTIABLE)

ALL shared imports MUST use parent-dir relative paths:

```typescript
// CORRECT
import { fooHelper } from "../_shared/foo.ts";

// WRONG — the old MCP path silently mangled this
import { fooHelper } from "./_shared/foo.ts";
```

Per CLAUDE.md §0. Pre-deploy: run `grep -rn 'from "./\\_shared' supabase/functions/<fn>/` and verify empty.

### 2.2 Verify deploy succeeded

```bash
# 1) Check version bumped
# 2) Smoke test
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl <fn> --smoke
```

The `--smoke` flag (NEW in B5) invokes the function with `{ smoke: true }` payload and asserts a 200 response. Fails fast if Vault secret missing or import path broken.

If smoke fails:
1. Read deploy logs via MCP `get_logs` (service: `edge-function`).
2. If `Module not found` → check parent-dir path convention.
3. If 500 with no clue → likely missing Vault secret.
4. If 403 → `verify_jwt` mismatch for the caller pattern.

---

## 3. Rollback (revert to prior version)

### 3.1 Find prior version

```bash
git log --all --oneline -- supabase/functions/<fn>/index.ts | head -10
```

Pick the SHA you want to roll back to. Production version on disk is whatever shipped last; rollback re-emits the payload from that prior SHA.

### 3.2 Execute rollback

```bash
node .claude/deploy_via_api.js --rollback <fn> <sha>
```

The script (B3 deliverable from audit 2026-05-20):
1. Checks out `supabase/functions/<fn>/` from `<sha>` into a temp dir
2. Emits payload from that snapshot
3. Deploys + runs smoke
4. Restores your working tree on completion (does NOT touch HEAD)

The deployed payload is also archived under `backups/edge_function_payloads/<fn>/<sha>.json` (last 3 retained per function).

### 3.3 Communicate rollback

Rollback is a production-state change. Document immediately:
1. Diagnose-doc at `docs/diagnoses/<date>-<fn>-rollback-<bug-id>.md` per CLAUDE.md rule 22.
2. Update `applied_migrations.json` if the function depends on a not-yet-applied migration (rare, but verify).
3. If the rollback was due to a runtime bug, the forward-fix MUST land + redeploy before the next batch closes. No "rollback and forget".

---

## 4. New function (first deploy)

```bash
# Create function directory + index.ts under supabase/functions/<new-fn>/
# Header comment block REQUIRED per Doc4 audit (2026-05-20):
#   /**
#    * <fn> — <one-line purpose>
#    *
#    * Triggers: <pg_cron job N | client RPC | webhook URL>
#    * Vault secrets: <SECRET_NAME>, <SECRET_NAME>
#    * Owner: <founder>
#    * Created: <YYYY-MM-DD>
#    */

# Add to docs/operations/CRON_REGISTRY.md if cron-triggered
# Add to import_map.json if new external dependency

# Then standard deploy:
node .claude/emit_payload.js <new-fn> --auto --functions-dir "$PWD/supabase/functions"
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl <new-fn> .claude/_payload_<new-fn>.json <verify_jwt>
```

Per CLAUDE.md naming conventions (§4.7) — function slug uses kebab-case; matches the directory name; reserved-domain prefix where applicable (`ai-`, `morning-`, `cron-`, `webhook-`).

---

## 5. Cron-triggered functions

Cron Edge Functions MUST use `_shared/cron_telemetry.ts` (adoption gate test exists). Pattern:

```typescript
import { withCronTelemetry } from "../_shared/cron_telemetry.ts";

Deno.serve(withCronTelemetry("my-fn", async (req) => {
  // your handler
  return new Response(JSON.stringify({ ok: true }), {
    headers: { "Content-Type": "application/json" },
  });
}));
```

The wrapper:
- Verifies the cron auth header (uses `CRON_SHARED_SECRET` Vault key)
- Emits `cron_call_log` row with status / duration / error
- Returns 401 cleanly on auth mismatch (cron jobs retry)

Skipping this wrapper = silent cron failure (precedent: morning-alert 401 series, Tests #12.9 / #15.4 / #16.1).

---

## 6. Bug classes (self-evolving)

### 6.1 Mangled path — `Module not found` after deploy
**Telltale:** Function returns 500 / cron logs show `Cannot find module './_shared/foo'`
**Root cause:** Used `./` instead of `../` for shared imports. The legacy MCP tool tolerated this; the host-shell flow doesn't.
**Fix:** `grep -rn 'from "./\\_shared' supabase/functions/<fn>/` → fix imports → redeploy.
**Prior:** Phase C.5 (ai-proxy v43 cutover).

### 6.2 Cron 401 after deploy — silent loop
**Telltale:** `cron.job_run_details` shows non-2xx for the function for hours.
**Root cause:** `CRON_SHARED_SECRET` Vault entry not refreshed OR `_shared/cron_telemetry.ts` wrapper missing.
**Fix:** Refresh Vault secret OR wrap handler. Audit Test #15.4 / 16.1 prior incidents.

### 6.3 Wrong account deploy
**Telltale:** Deploy command authenticates against `Upendra-Prasad's Project` not fitness-app.
**Root cause:** `supabase` CLI logged in as personal account; user invoked it instead of the host-shell flow.
**Fix:** ALWAYS use `node .claude/deploy_via_api.js` (auto-resolves the fitness-app token); NEVER `supabase functions deploy`.
**Prior:** CLAUDE.md §2a documents the dual-account split.

### 6.4 Payload too large / nested files dropped
**Telltale:** Function deploys but new files under `_shared/tools/` aren't present at runtime.
**Root cause:** Used MCP `deploy_edge_function` for a function with nested `_shared/tools/` — the MCP tool flattens paths.
**Fix:** Use host-shell `emit_payload.js` (preserves nested structure exactly).
**Prior:** AI coach tools bundle work (Phase 7).

### 6.5 `verify_jwt=true` smoke is GATEWAY-MASKED — a 401 does NOT confirm the module booted
**Telltale:** Deploy smoke returns 401 for a `verify_jwt=true` function (verify-payment, ai-media-proxy, weekly-report …) and you read "reachable = healthy" — but every AUTHENTICATED call 500s.
**Root cause:** For `verify_jwt=true` the Supabase gateway validates the JWT and rejects an UNAUTHENTICATED smoke with 401 **before the function module loads**. A module that fails to BOOT (parse / import error) is therefore invisible to the unauth smoke — the 401 is the gateway, not the function.
**Fix:** Boot-verify with an ANON-key Bearer (passes the gateway → reaches the module): `ANON=$(grep -oE "SUPABASE_ANON_KEY=[^[:space:]]+" .env | cut -d= -f2); curl -X POST <url> -H "Authorization: Bearer $ANON" -d '{}'`. A **503 BOOT_ERROR = broken**; the module's OWN 4xx (e.g. `{"error":"Invalid or expired token"}`) = booted. The unauth `--smoke` only proves the gateway is up.
**Prior:** 2026-06-08 — verify-payment v14 shipped with a duplicate `const existingSub` (module-load SyntaxError); the unauth smoke 401'd (gateway) so it read "healthy". Caught by the Hermes E-pass, not the deploy. Diagnose f5d8c3.

### 6.6 std encoding dead-export / latent dep-rot — boot fails only on the NEXT deploy
**Telltale:** A function that's served fine for weeks returns 503 BOOT_ERROR the first time you redeploy it — and your diff didn't touch imports.
**Root cause:** A prior commit bumped a `deno.land/std@X/encoding/(hex|base64).ts` import past 0.210 while keeping `{ encode }` (REMOVED at std 0.210) — a dead export. The function kept serving its pre-bump bundle, so the broken import stayed latent until the redeploy re-fetched it. (Same class as a `deno.land/x` URL 404'ing upstream — `feedback_mistake_remote_dep_rot.md`.)
**Fix:** `git log -S "<import>"` finds the bump commit; a code rollback does NOT help (the bad import predates your edit). Revert to a std version that still exports it (≤0.208) OR use `encodeHex`/`encodeBase64`. Gate `scripts/check_std_encoding_import_rot.dart` blocks `{ encode | decode }` from std≥0.210/encoding. Deploy per-function (not "all N blind") so the blast is one function at a time.
**Prior:** 2026-06-08 — razorpay-webhook (the live payment webhook) went DOWN on redeploy. Diagnose d4c8e1.

---

## 7. Verification gates

After every deploy:
1. `scripts/check_edge_function_smoke_step.dart` — assert deploy script includes smoke step
2. `scripts/check_edge_function_rollback_script.dart` (Gate 38) — assert `--rollback` flag present in deploy_via_api.js
3. `scripts/check_cron_registry.dart` (Gate 31) — assert cron-triggered functions registered

If a deploy script change adds a new function, all 3 gates must pass before merge.

---

## 8. Documentation requirements

Every deploy commit message must reference:
- The function slug + version (e.g. `feat(ai-proxy): bump to v66 — placeholder resolution`)
- If it's a rollback: `revert(ai-proxy): rollback to v65 — closes-diagnose <id>`
- Vault secrets added/changed (list explicitly)

If deploy is part of a multi-fn batch (e.g. test #15.4 fixed pr-detection + morning-alert + 2 others together), one diagnose-doc per function with their own `bug-id`.

---

## 9. Anti-patterns

- ❌ Using `supabase functions deploy` CLI (wrong account)
- ❌ Using `./` for shared imports (path mangle)
- ❌ Deploying without git status clean (uncommitted state ships)
- ❌ Skipping `--smoke` flag after deploy
- ❌ Cron function without `_shared/cron_telemetry.ts` wrapper
- ❌ Rollback without diagnose-doc
- ❌ Adding a Vault secret in dashboard but not documenting in CLAUDE.md §2a credential table

---

## Self-evolution

Append a new bug-class section under §6 the SAME commit that introduces the fix. Cite: bug ID + trigger phrase + regression test path. New skills under `.claude/skills/<related>/SKILL.md` when 3+ batches share a non-deploy pattern.

Last evolved: B5 D1 of tech-debt audit 2026-05-20 (initial creation; codifies host-shell flow shipped Phase C.5).
