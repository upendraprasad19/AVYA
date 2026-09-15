# Edge Function Rollback Runbook

> Tech-debt audit 2026-05-20 finding I3 — Edge Function deploys were
> forward-only. Rolling back required `git checkout <SHA>` → re-emit
> payload → redeploy under pressure. This runbook closes that gap.
>
> **Lens precedent:** L53 (Edge Function deploy reversibility).
> **Diagnose-doc:** `docs/diagnoses/2026-05-21-edge-function-rollback-I3-*.md`.
> **Gate:** `scripts/check_edge_function_rollback_script.dart` (Gate 38).

## When to roll back

| Signal | Where it surfaces | Decision |
|---|---|---|
| `client_errors` table spikes after a deploy | B1 / I4 alert on `supabase/alerts/client_errors.yaml` | Roll back the **most recently deployed** function. |
| Post-deploy smoke step printed `[deploy] Smoke FAIL` | Deploy stdout (the deployer prints the rollback command verbatim) | Roll back if the failure is not a known transient (e.g. cold-start 504 on first POST). |
| User-reported breakage within ~10 min of a deploy | Founder dashboard / Telegram | Roll back, then diagnose at leisure. |
| Edge Function logs show 5xx rate > baseline | `mcp__ba7b5e8e__get_logs` | Roll back if rate exceeds 2x baseline for >2 min. |

**Default policy:** roll back first, diagnose second. The script is
designed so rollback is one command. MTTR from "I see the alert" to
"prod is restored" should be under 90 seconds.

## How to roll back

### Option A — Roll back one commit

This is the right call ~90% of the time: the most recent deploy is the
one that broke things, and the prior commit was known-good.

```
node .claude/deploy_via_api.js --rollback <fn-name> previous
```

`previous` resolves to the second-most-recent commit that touched
`supabase/functions/<fn-name>/index.ts` (not the second-most-recent
commit in the repo overall — that would often miss the actual prior
deploy).

### Option B — Roll back to a specific SHA

Use this when you know exactly which commit was good:

```
node .claude/deploy_via_api.js --rollback <fn-name> <7-char-or-full-sha>
```

The script reads the source at that SHA via `git show <SHA>:supabase/functions/<fn>/index.ts`
(no `git checkout` — your working tree stays untouched). It recursively
follows relative imports to reconstruct the full payload, exactly as
`emit_payload.js` would have at that SHA.

### Option C — Roll back to the cloud snapshot (legacy)

Every deploy captures the pre-deploy cloud state under
`.claude/_snapshots/<fn>_<ISO-ts>.json`. To redeploy that snapshot:

```
node .claude/deploy_via_api.js --rollback dedsavbjuwgarrhphgnl <fn-name>
```

The two-positional shape (project + fn, no SHA) triggers the legacy
snapshot path. Use this if:
- The breaking change was deployed without going through git (e.g.
  hot-patched via dashboard editor), so no SHA is meaningful.
- You explicitly want the bytes that were live just before this deploy,
  not what was in git at that time.

### Dry-run any rollback first (when uncertain)

```
node .claude/deploy_via_api.js --rollback <fn-name> <sha> --dry-run
```

Builds the payload, prints the diff vs HEAD, but does **not** POST.
Use this to sanity-check the SHA before pulling the trigger.

## What the script does step by step

1. Resolves the SHA (handles `previous` keyword → HEAD~1 for the
   function's file history).
2. Prints the target commit subject + a `git diff --stat` against HEAD
   scoped to `supabase/functions/<fn>/`.
3. Writes the reconstructed payload to
   `.claude/_payload_<fn>_rollback_<short-sha>.json`.
4. Prompts the operator to type `yes` (skip with `--yes` for CI).
5. Archives the payload to `backups/edge_function_payloads/<fn>/v<N>_<sha>.json`
   (pruned to the 3 most recent per function).
6. POSTs to `https://api.supabase.com/v1/projects/<ref>/functions/deploy?slug=<fn>`.
7. Runs the post-deploy smoke step: `POST` to the deployed function URL
   with body `{"smoke":true}`, asserts the response is in the tolerated
   code set (2xx, plus 401 for auth-required functions like
   `verify-payment` — see `SMOKE_TOLERATED_CODES` in `deploy_via_api.js`).

## Post-rollback validation checklist

After the script reports HTTP 201 + smoke OK:

- [ ] Run a real end-user flow against the rolled-back function (chat
      message → ai-proxy; payment verify → verify-payment; etc.).
- [ ] Check `client_errors` table for the next 5 minutes — the rate
      should return to baseline.
- [ ] Open `mcp__ba7b5e8e__get_logs` for the function, filter for the
      window since rollback, confirm no 5xx burst.
- [ ] Notify in `#oncall` (or equivalent) that the rollback shipped,
      with the SHA + reason.
- [ ] Open a follow-up ticket / branch for the actual fix (the
      rolled-back code remains in `main`; rollback only changes what's
      live in prod).

## What rollback does NOT do

- Does not revert the git commit. If you rolled back `fed9e2c`, the
  next forward deploy will still ship `fed9e2c` unless you also revert
  the commit (`git revert <sha>` on a new branch). Rollback is a
  cloud-state-only operation.
- Does not roll back Postgres migrations. Migrations are separate;
  use `supabase/migrations/<NNN>_revert_*.sql` for those (see
  `supabase/migrations/CLAUDE.md`).
- Does not roll back Vault secrets. If a deploy bumped
  `service_role_key` or a third-party key, that change persists; check
  `docs/operations/SECRET_INVENTORY.md` for the canonical rotation
  procedure.

## Smoke-step tuning

If a function's legitimate `{smoke:true}` response is NOT in the
allow-list, the smoke step will warn (NOT fail the deploy). The
operator decides whether the warning is real.

To add a new tolerated code, edit `SMOKE_TOLERATED_CODES` in
`.claude/deploy_via_api.js` and add a contract entry justifying the
toleration (e.g. "this function 400s on missing user_id, which is the
correct behavior for a smoke probe with no body").

To skip the smoke step entirely (only when you have a deeply broken
function-side handler that throws on any unexpected body and you've
verified it via another channel), pass `--no-smoke`. Discouraged.

## Failure modes + escapes

| Symptom | Likely cause | Escape |
|---|---|---|
| `ROLLBACK ERROR: could not resolve revspec` | SHA doesn't exist (typo or unfetched) | `git fetch && git log -- supabase/functions/<fn>/` to find the right SHA. |
| `dep <path> missing at SHA` warning | A shared dep was added AFTER the rollback target | Acceptable IF the missing dep wasn't imported at that SHA. Otherwise pick a later SHA. |
| Smoke check timeout | Function cold-starting | Re-run smoke manually: `curl -X POST https://<ref>.supabase.co/functions/v1/<fn> -d '{"smoke":true}'`. |
| HTTP 401 on the Management API POST | Token expired or wrong account | See `docs/operations/SECRET_INVENTORY.md` for rotation; default token at `supabase/.supabase/supabase access token.txt`. |
| Archive prune deleted something you wanted | The archive is the LAST 3 deploys; older ones are git-regenerable | Re-emit from git: `git show <old-sha>:supabase/functions/<fn>/index.ts`. |

## Audit trail

Every rollback leaves:
- The reconstructed payload at `.claude/_payload_<fn>_rollback_<sha>.json`
  (gitignored — not committed).
- An archived payload at `backups/edge_function_payloads/<fn>/v<N>_<sha>.json`
  (committed; serves as the historical record).
- A snapshot of the cloud-pre-rollback state (if applicable) at
  `.claude/_snapshots/<fn>_<ts>.json` (gitignored).

The archive is the canonical "what was live in prod between dates X and
Y" record. Don't manually delete it.
