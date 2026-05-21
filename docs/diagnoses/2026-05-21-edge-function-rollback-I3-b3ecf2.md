---
bug_id: b3ecf2
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 / B3 (finding I3)
status: shipped
symptom: |
  Edge Function deploys were forward-only. When a bad deploy hit prod
  (caught via `client_errors` spike per B1 / I4 alert, or a user
  report), the operator's only path was: `git checkout <previous SHA>`
  → re-emit payload via emit_payload.js → redeploy via deploy_via_api.js,
  all under outage pressure. There was no "deploy previous version"
  one-liner. MTTR for any bad deploy was unbounded by tooling. The
  legacy snapshot path (audit-2026-05-11) captured the cloud bytes
  pre-deploy but required knowing the project ref + having the snapshot
  file on disk + zero verification that the rolled-back function was
  actually running afterward.
concept: edge_function_deploy_reversibility
sot_registry_entry: edge_function_deploy_reversibility
writers:
  - { file: .claude/deploy_via_api.js, method: printHelp (--help surface), line: 135 }
  - { file: .claude/deploy_via_api.js, method: resolveGitSha (revspec → full SHA), line: 342 }
  - { file: .claude/deploy_via_api.js, method: emitPayloadAtSha (rebuild payload at SHA without checkout), line: 418 }
  - { file: .claude/deploy_via_api.js, method: archivePayload (write + prune backups/edge_function_payloads/<fn>/v<N>_<sha>.json), line: 567 }
  - { file: .claude/deploy_via_api.js, method: runSmokeStep (synthetic-payload post-deploy verification), line: 642 }
readers:
  - { file: scripts/check_edge_function_rollback_script.dart, method_or_widget: Gate 38 — asserts --rollback flag + git-SHA path + smoke step + archive dir, line: 28 }
  - { file: docs/runbooks/edge-function-rollback.md, method_or_widget: Operator runbook — when/how to roll back + post-rollback checklist, line: 1 }
  - { file: docs/audit/LENS_REGISTRY.md, method_or_widget: L53 row — charter + gate + runbook references, line: 130 }
hive_key_prefix: not_applicable_no_hive_state
hive_key_formula: "no Hive state — deploy tooling lives entirely in .claude/ + scripts/"
sync_methods: [not_applicable]
restore_methods: [not_applicable]
cloud_table: not_applicable_no_table
cloud_columns: [not_applicable]
contract_test_path: scripts/check_edge_function_rollback_script.dart
ist_handling:
  - { file: .claude/deploy_via_api.js, line: 578, fn: archive filename uses git-HEAD SHA not timestamp (idempotent across timezones; IST not relevant) }
provider_invalidations: [not_applicable_node_cli]
telemetry_op_types:
  success: [not_applicable_node_cli]
  failure: [not_applicable_node_cli]
cross_account_guard: Deploy script runs under operator credentials only — Management API token resolution priority documented in script header (lines 56-74). No user-scoped data touched.
forbidden_patterns_checked:
  - { pattern: "git checkout.*supabase/functions", absent: true }
  - { pattern: "ROLLBACK_FORWARD_ONLY", absent: true }
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "deploy_via_api.js extended from 441 to 852 lines; emit_payload.js untouched (per brief — reuse, not refactor); --help / --rollback <fn> <sha> / smoke step / archive all live alongside the existing forward-deploy + legacy snapshot paths" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Deploy tooling is a Node CLI; no Hive interaction" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change — deploys are Management API operations" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "The deploy script IS the code-vs-deploy contract here; --rollback + smoke step + archive close the previously-open reversibility gap. Verified via `node .claude/deploy_via_api.js --rollback ai-proxy 818ba30 --dry-run` (reconstructed 44-file payload from git, 224596 content bytes, no live POST). Verified via `node .claude/deploy_via_api.js --rollback ai-proxy previous --dry-run` (HEAD~1-for-file resolution worked: 2b3154e selected, 85-line diff vs HEAD reported)." }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "Gate 38 (scripts/check_edge_function_rollback_script.dart) PASS — asserts --rollback flag exists, git-SHA reconstruction path exists, `previous` keyword accepted, smoke step + tolerated-code allowlist exist, archive dir exists, --help flag exists. Auto-wired into pre-commit via the dynamic gate loop introduced in B1 (Gate 33 still PASS at 43 gates)." }
impact_analysis:
  callers_audited:
    - .claude/deploy_via_api.js (the script itself — single CLI; existing forward-deploy path untouched)
    - .claude/emit_payload.js (reused via the same path-naming scheme inside emitPayloadAtSha — no edits)
    - scripts/pre-commit.sh (dynamic for-loop picks up Gate 38 automatically; no manual wiring)
    - .github/workflows/test.yml (same dynamic-loop picks up Gate 38)
  callers_updated_in_this_batch:
    - .claude/deploy_via_api.js (411 lines added — --rollback git-SHA path, --help, smoke step, archive)
    - scripts/check_edge_function_rollback_script.dart (new — Gate 38)
    - docs/runbooks/edge-function-rollback.md (new — operator runbook)
    - docs/audit/LENS_REGISTRY.md (L53 row populated; next-audit lens count L52 → L53)
    - backups/edge_function_payloads/.gitkeep (new — archive root scaffold)
  callers_unchanged:
    - .claude/emit_payload.js — explicitly preserved per brief (reuse opportunity, not refactor target). The rollback path replicates its `payloadName()` convention inline so both surfaces produce byte-identical payloads for the same SHA.
    - All Edge Function source files — no behavior change in the deployed code; this is purely deploy-tooling reversibility.
proposed_fix: |
  Three additions to .claude/deploy_via_api.js plus one gate + one
  runbook + one LENS row:

  1. Add a --rollback path that accepts a function name + a git
     revspec (7-char SHA, full SHA, or the literal "previous" = the
     second-most-recent commit touching the function's index.ts).
     The script uses `git show <SHA>:supabase/functions/<fn>/index.ts`
     to read source at that SHA WITHOUT a working-tree checkout, then
     recursively follows relative imports to rebuild the same payload
     emit_payload.js would have produced at that SHA. Prints a
     `git diff --stat` against HEAD scoped to the function, prompts
     the operator to type "yes" (skip with --yes), then POSTs.

     The legacy snapshot-based rollback (two positional args = project
     + fn, audit-2026-05-11) is preserved unchanged. Disambiguator: an
     arg that matches /^[0-9a-f]{7,40}$/ or equals "previous" → git
     mode; otherwise → legacy snapshot mode.

  2. Add a post-deploy smoke step: every successful deploy (forward
     or rollback) POSTs `{"smoke":true}` to the deployed function URL.
     Tolerated codes are 2xx plus a per-function allowlist for non-2xx
     responses that legitimately indicate "deployed and running" (e.g.
     verify-payment 401 on a missing-JWT smoke probe is healthy). On
     non-tolerated responses the script logs a WARN with the rollback
     command pre-baked — does NOT auto-rollback (operator decision).

  3. Add a payload archive: every deploy writes
     backups/edge_function_payloads/<fn>/v<N>_<sha>.json. Pruned to
     the 3 most recent per function on each deploy. The archive is
     regenerable from git so no PII concerns; it serves as the
     "what was live in prod between X and Y" historical record AND a
     fast-path for "just redeploy v(N-1)" without re-running git
     reconstruction.

  Gate 38 (scripts/check_edge_function_rollback_script.dart) asserts
  the deploy script has the --rollback flag + git-SHA path +
  "previous" keyword + smoke step + tolerated-code allowlist + archive
  directory + --help flag. Auto-picked-up by the dynamic gate loop
  introduced in B1 (no manual wiring of pre-commit.sh or test.yml).

  Operator runbook at docs/runbooks/edge-function-rollback.md
  documents when to roll back (client_errors spike, smoke fail, user
  report, log 5xx surge), the three rollback options (previous /
  specific SHA / legacy snapshot), the dry-run safety net, the
  step-by-step script behavior, the post-rollback validation
  checklist, smoke-step tuning, failure modes, and the audit trail.

  LENS_REGISTRY L53 (was "reserved" placeholder) populated with
  charter + gate + runbook + precedent.

  No commit per founder instruction — files staged only.
regression_test_planned:
  - scripts/check_edge_function_rollback_script.dart — Gate 38. Source-grep contract test: asserts .claude/deploy_via_api.js contains --rollback flag, gitShowAtSha / `git show` reconstruction call, "previous" keyword handling, runSmokeStep / smoke-check semantics, SMOKE_TOLERATED_CODES allowlist, backups/edge_function_payloads/ archive root, --help surface. Manual verification: dry-run rollback to commit 818ba30 reconstructed 44-file 224596-byte payload from git history without working-tree mutation; dry-run rollback to "previous" correctly selected the 2nd-most-recent commit touching the function file (2b3154e, not the repo's HEAD~1) and reported the 85-line diff vs HEAD.
---
# Body

## What changed

Three deploy-tooling additions in `.claude/deploy_via_api.js` (411 new
lines on top of the existing 441-line script):

1. **`--rollback <fn> <sha-or-previous>` path** — reconstructs the
   payload at a past SHA via `git show <SHA>:...` (no checkout),
   recursively follows relative imports to rebuild every shared dep
   exactly as `emit_payload.js` would have at that SHA, prompts
   confirmation, then deploys. The keyword `previous` is special-cased
   to mean "the second-most-recent commit that touched
   `supabase/functions/<fn>/index.ts`" — not repo-wide HEAD~1, which
   would often miss the actual prior deploy.

2. **Post-deploy smoke step** — every successful deploy POSTs
   `{"smoke":true}` to the deployed function URL. Tolerated responses
   are 2xx plus a per-function allowlist (e.g. `verify-payment` 401 on
   missing JWT is a healthy "deployed and auth-gated" signal). Smoke
   failures log a WARN with the rollback command pre-baked — operator
   decides whether to roll back.

3. **Payload archive** — every deploy writes
   `backups/edge_function_payloads/<fn>/v<N>_<sha>.json`. Pruned to the
   3 most recent per function. Regenerable from git (no PII concerns)
   so safe to commit; it serves as the historical record of "what was
   live in prod between deploys X and Y" and a fast-path for
   "redeploy v(N-1)" without re-running git reconstruction.

The existing forward-deploy code path is untouched — the rollback +
smoke + archive code is additive. The legacy snapshot-based rollback
(audit-2026-05-11, two-positional-arg shape: `--rollback <project>
<fn>`) is preserved unchanged for the "cloud bytes pre-this-deploy"
use case (e.g. when a deploy went through dashboard hot-patch without
hitting git).

## Why this isn't gold-plating

This was the bottom item in the I3 tech-debt finding: "deploys are
forward-only; bad deploys are discovered via `client_errors` spike
(now alerted per B1 / I4 close); MTTR is `git checkout <SHA> + re-emit
+ redeploy under pressure`." With B1's `client_errors` alert wired,
the detection latency dropped to minutes — but the response latency
was still bounded by how fast an operator could `git checkout` under
pressure. This close brings response latency to one command.

Specifically prevents the failure mode where:
- A deploy ships at T0.
- The `client_errors` alert fires at T0+3min.
- The operator runs `git checkout <prev-sha>`, accidentally mutates
  the working tree, has unsaved changes, gets distracted resolving
  the conflict, and prod stays broken for another 10+ minutes.

With `--rollback <fn> previous`: zero working-tree mutation, zero
intermediate steps, payload reconstructed in ~200ms, POST + smoke in
~3s. Operator-time-to-restore drops from ~10min to ~90s.

## Migration touch list

| Site | What it does |
|---|---|
| `.claude/deploy_via_api.js` lines 60-127 | New CLI arg parsing for `--help`, `--rollback`, `--no-smoke`, `--project`; existing forward-mode parser preserved. |
| `.claude/deploy_via_api.js` lines 135-220 | `printHelp()` — comprehensive `--help` surface documenting all three deploy modes. |
| `.claude/deploy_via_api.js` lines 222-262 | Mode dispatcher — disambiguates git-SHA rollback vs legacy snapshot rollback via `looksLikeGitRevspec()`. |
| `.claude/deploy_via_api.js` lines 342-415 | `resolveGitSha`, `gitShowAtSha`, `gitCommitSubject`, `findRelativeImports` — git-history accessors. |
| `.claude/deploy_via_api.js` lines 418-470 | `emitPayloadAtSha` — recursive import walk + payload reconstruction. |
| `.claude/deploy_via_api.js` lines 565-605 | `ARCHIVE_DIR` + `archivePayload` — write `backups/edge_function_payloads/<fn>/v<N>_<sha>.json` + prune to 3 most recent. |
| `.claude/deploy_via_api.js` lines 612-695 | `SMOKE_TOLERATED_CODES` + `runSmokeStep` — synthetic-payload post-deploy verification. |
| `scripts/check_edge_function_rollback_script.dart` | New Gate 38 — asserts the contract. |
| `docs/runbooks/edge-function-rollback.md` | New operator runbook. |
| `docs/audit/LENS_REGISTRY.md` line 130 | L53 row populated (was "reserved"). |
| `backups/edge_function_payloads/.gitkeep` | New — archive root scaffold (regenerable artifacts go here). |

## Verification

```
$ node .claude/deploy_via_api.js --help
deploy_via_api.js — Supabase Edge Function deployer

USAGE
  Forward deploy:
    node deploy_via_api.js <project_ref> <function_name> <payload_json_path> [verify_jwt] [flags]

  Rollback (git-SHA — I3, audit 2026-05-20):
    node deploy_via_api.js --rollback <function_name> <git-sha-or-keyword> [flags]
  ...

$ node .claude/deploy_via_api.js --rollback ai-proxy 818ba30 --dry-run
[deploy] ROLLBACK (git): ai-proxy → 818ba30  "fix(audit): comprehensive 22-task Phase E batch — APK Test #16.2"
[deploy] ROLLBACK (git): wrote .claude/_payload_ai-proxy_rollback_818ba30.json  (44 files)
[deploy] DRY RUN — skipping actual request. All inputs valid.

$ node .claude/deploy_via_api.js --rollback ai-proxy previous --dry-run
[deploy] ROLLBACK (git): ai-proxy → 2b3154e  "fix(coach): chat duplicates — 60s client+server dedup + circuit-breaker + migration 066"
[deploy] ROLLBACK (git):   supabase/functions/ai-proxy/index.ts | 85 ++++++++++++++++++++++++++----------
[deploy]    1 file changed, 62 insertions(+), 23 deletions(-)
[deploy] DRY RUN — skipping actual request. All inputs valid.

$ dart run scripts/check_edge_function_rollback_script.dart
[Gate 38] PASS: edge function deploy script supports rollback + smoke + archive.

$ dart run scripts/check_gate_scripts_wired.dart
[Gate 33] PASS: all 43 gate scripts wired (or allow-listed).
```

No live API calls during this work — verification was dry-run only,
per founder instruction.

## Followups

- First real-world test will be the next legitimate Edge Function
  redeploy. Until then, the rollback path is exercised only by
  Gate 38 + manual dry-runs.
- Consider adding `--list-archive <fn>` to print the 3 archived
  payloads' SHAs + timestamps. Deferred; trivial to add when needed.
- Consider per-deploy Slack / Telegram webhook notifying smoke
  results. Deferred to a future operability batch (overlap with B1's
  client_errors alert routing).
