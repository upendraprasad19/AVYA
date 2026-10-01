# Hand-off — what only the founder laptop can do (2026-08-20, updated 2026-08-24)

> **Why this file exists.** The remote container that produced this batch can read and write the
> live Supabase project over MCP, so migrations, live queries and the `memory_embeddings` cleanup
> were all done there. Two things it genuinely cannot do: **deploy an Edge Function** (no Supabase
> Management API token reaches the container — see "Why not from the container" below) and **build
> an APK**. Both Edge Function deploys it was waiting on are now DONE (2026-08-24) — see "What is
> already done" at the end. Only the APK build is still outstanding.
>
> Keep it current: delete a section once its deploy is verified, rather than leaving a stale
> instruction that reads as still-pending.

## START HERE — pulling this onto the laptop

**Nothing is unsaved.** Everything the container produced was committed and pushed, and the
laptop pulled it on 2026-08-24 (`e78adb63`). This section is kept as the procedure for the NEXT
pull, not as an outstanding action.

⚠️ It deliberately no longer names a specific "expected" SHA. It used to assert `476bcc1`,
which went stale two merges later — a hard-coded tip in a checked-in runbook is wrong by
construction the moment anything lands. Compare against `origin/main` instead.

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
git log --oneline -4        # top commit should match origin/main
```

**Start the session in a worktree, not in the main folder.** §4.13 is non-negotiable: the shared
main folder is integration-only (merges, pushes, `/build-apk`), because two sessions in it share
one git index and a commit from either can silently mix in the other's staged files.

```bash
sh scripts/new-worktree.sh my-slug     # copies .env for you; use a REAL slug
cd .claude/worktrees/my-slug
claude
```

`.env` is gitignored and already on the laptop; `new-worktree.sh` copies it in. Nothing else needs
restoring, re-running or re-applying.

⚠️ **Run this in Git Bash, not PowerShell, and substitute a real slug.** Both halves are
load-bearing, and this block cost a session on 2026-08-24 when it was pasted verbatim:

1. This snippet used to read `<slug>`. PowerShell treats `<` as a reserved redirect operator and
   refuses at PARSE time — `The '<' operator is reserved for future use.` — before running
   anything, so the placeholder never even reached the script.
2. That parse error MASKED a second problem waiting behind it: `sh` is not on PowerShell's PATH
   on this laptop. Git ships it at `C:\Program Files\Git\bin\sh.exe`, but only
   `C:\Program Files\Git\cmd` is on PATH, so a real slug alone would have failed again with
   `'sh' is not recognized`.

From PowerShell the working form is:

```powershell
& "C:\Program Files\Git\bin\sh.exe" scripts/new-worktree.sh my-slug
```

### State of play, so a fresh session has its bearings

Landed and green on `main`: FOB-1 (week identity), FOB-5 (hold telemetry), OI-132 (the fileless
migration reconstructed + Gate 31 given a live-snapshot input), and FOB-3 (the coach's `hold`
block). `enable_hold_weeks` is still **OFF** — none of it is live for users yet, and the flip is
its own commit needing the full ×2 review and clearing all FOUR ledger rows at once.

Waiting on this machine: **nothing but the APK build.** `rolling-context` v19 and `ai-proxy` v80
both deployed and verified 2026-08-24. FOB-4 is still not deployable — it needs a migration
first (schema `public` has zero `%hold%` columns and no `workout_schedule` table, measured
2026-08-21), and that migration needs its own live-apply authorization.

---

## Why not from the container, stated once

`deploy_via_api.js` needs a Management API token. Every source it accepts is absent there:
`SUPABASE_ACCESS_TOKEN_FITNESS` and `SUPABASE_ACCESS_TOKEN` are unset, `~/.supabase/fitness-app-token`
does not exist, and `supabase/.supabase/` is gitignored so it never came with the clone.

The MCP `deploy_edge_function` fallback was **considered and rejected, not attempted**. Root
CLAUDE.md §0 records that path silently mangling nested `../_shared/...` imports, and both
functions this note covered had them (`ai-proxy` pulls 41 files, `rolling-context` 8). A mangled
deploy of `rolling-context` in particular does not fail loudly — it breaks a nightly cron that
summarizes and **deletes** user conversation rows. Kept after the fact because the reasoning
applies to the next deploy from a container, not just these two.

The `supabase` CLI on the laptop is logged into the **personal** account, not the fitness-app
account (root CLAUDE.md §2a). Do not use it for these.

---

## 1. APK build

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
- **`rolling-context` → v19** — deployed 2026-08-24 with `verify_jwt=false`. Activates the
  `.neq("channel", "app_event")` filter, so the nightly job stops selecting users by an inflated
  message count. Verified: HTTP 201, version 18→19, unauthenticated POST returns 401 (booted;
  it gates on `isAuthorizedCronCall`), live config re-read independently.
- **`ai-proxy` → v80** — deployed 2026-08-24 with **`verify_jwt=false`**. Activates FOB-3's HOLD
  WEEKS section of `captain_manual.ts`. Verified: HTTP 201, version 79→80, `verify_jwt` still
  `false`, and the module proved booted by its OWN error bodies — `{"error":"Missing authorization
  header"}` (`index.ts:184`) unauthenticated and `{"error":"Invalid or expired token"}`
  (`:191`) with an anon-key Bearer. No 503, so the `captain_manual.ts` template literal parses.
  ⚠️ This section previously told you to pass `verify_jwt=true`, which would have flipped the
  gateway on and 401'd every valid token before the module loads — silently, since the smoke step
  tolerates 401 for `ai-proxy`. Corrected and pinned by
  `test/contracts/runbook_deploy_verify_jwt_test.dart`; see diagnose `b2d8e4`
  (`docs/diagnoses/2026-08-24-runbook-verify-jwt-b2d8e4.md`).
- **`enable_hold_weeks` is still OFF** and this batch does not flip it. The flip is its own commit
  needing the full ×2 review, and it must clear all **four** pending `enable_hold_weeks` rows in
  `docs/ship_dark_pending_review.yaml` at once (hold-mechanic, hold-display, hold-display-fixes,
  claude/oi-pending-hold-weeks-1od97o). This line said "three" until 2026-08-24; a fourth row had
  been added and the count was never updated.
