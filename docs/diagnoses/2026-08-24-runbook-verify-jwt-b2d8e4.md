---
bug_id: b2d8e4
date: 2026-08-24
batch: handoff-deploys
status: fixed
blast_radius: feature
symptom: >
  The operator runbook docs/operations/FOUNDER_LAPTOP_HANDOFF.md instructed the founder to
  redeploy ai-proxy with verify_jwt=true. Live config is false, and deliberately so. Running the
  documented line would have flipped the Supabase gateway JWT check ON for the app's single most
  critical Edge Function, causing every valid user token to be rejected with 401 BEFORE the module
  loads — an outage of the AI coach and all food AI (food_text_analysis, scan meal, cart auditor)
  for every user. No user ever hit this: the wrong value was caught by reading live config during
  session prep and was never executed.
concept: >
  Documentation-as-executable-input drift. A runbook command is not prose — it is an input to a
  prod control plane, and it had drifted from the live state it addresses with nothing pinning the
  two together. The failure would also have been SILENT: deploy_via_api.js tolerates HTTP 401 for
  ai-proxy in its post-deploy smoke step, so the deploy prints "Smoke OK" over a dead function.
  This is the bad-news-vs-no-news class — a 401 meant "healthy module rejected you" before the
  change and would have meant "gateway killed everything" after it, with no way to tell them apart
  from the smoke output alone.
sot_registry_entry: >
  None added. The source of truth for a function's verify_jwt is the Supabase Management API (live
  config), not any in-repo file, so there is no writer/reader pair in lib/ or supabase/ to register.
  The new contract test carries a snapshot of that live truth instead, and documents how to
  regenerate it.
writers:
  - { file: .claude/deploy_via_api.js, method: metadata literal sent in the multipart deploy body, line: 817 }
  - { file: .claude/deploy_via_api.js, method: verifyJwt argument coercion (anything not the literal string false becomes true), line: 337 }
readers:
  - { file: supabase/functions/ai-proxy/index.ts, method: header comment recording WHY the gateway check must stay off, line: 26 }
  - { file: supabase/functions/ai-proxy/index.ts, method: self-authentication path that replaces the gateway check, line: 183 }
  - { file: .claude/deploy_via_api.js, method: SMOKE_TOLERATED_CODES entry that would have masked the outage, line: 669 }
  - { file: .claude/deploy_via_api.js, method: interactive confirm box printing verify_jwt (the only pre-existing guard), line: 853 }
hive_key_prefix: not_applicable — no Hive box, key or adapter is involved; this is an Edge Function gateway config and a docs defect.
hive_key_formula: not_applicable — see hive_key_prefix.
sync_methods: not_applicable — nothing in the Hive-to-Supabase sync fan-out reads or writes verify_jwt.
restore_methods: not_applicable — verify_jwt is server-side control-plane config and is never part of a user snapshot or restore.
cloud_table: none — verify_jwt lives in Supabase Edge Function config, reachable via the Management API, not in a Postgres table.
cloud_columns: none — see cloud_table.
contract_test_path: test/contracts/runbook_deploy_verify_jwt_test.dart
ist_handling: not_applicable — no date key, counter reset or cloud date column is touched by this fix.
provider_invalidations: none — no Riverpod provider reads Edge Function gateway config.
telemetry_op_types: >
  None added. Deliberate, and worth stating rather than leaving implied: the useful signal here is
  not a client op_type but the deploy-time verification itself, which is now pinned by the contract
  test. A telemetry event fired from the client could not have distinguished a gateway 401 from the
  module's own 401 — that is precisely the ambiguity that made this failure mode silent.
cross_account_guard: >
  not_applicable — no user-scoped data path is touched. Noted for completeness: had the flip been
  executed it would have denied ALL accounts equally rather than leaking across them, so this is an
  availability defect, not an isolation one.
forbidden_patterns_checked: >
  Checked and clean. No Container with both color and decoration, no inline isPro check, no
  client-side API key, no raw flutter build, no bare dart in a hook path. The repo-specific pattern
  that DID apply is the one this bug is an instance of: a doc asserting a live-state value with no
  mechanical link to that state.
proposed_fix: >
  Three parts, all landed in this batch. (1) Correct the runbook's ai-proxy command from true to
  false and state inline why the value is load-bearing, citing ai-proxy/index.ts:26-27. (2) Add
  test/contracts/runbook_deploy_verify_jwt_test.dart, which parses every runnable deploy_via_api.js
  invocation out of the operator runbooks and asserts its verify_jwt argument matches a snapshot of
  live config, failing closed on any slug the snapshot has never heard of. (3) Delete the two
  runbook sections whose deploys are now verified, per that file's own instruction to remove a
  section once its deploy has taken.
regression_test_planned: >
  Written and proven both directions before the fix landed. Against the unfixed runbook the suite
  reported 6 passing and 1 failing, the failure naming the exact file and defect —
  'docs/operations/FOUNDER_LAPTOP_HANDOFF.md: deploys "ai-proxy" with verify_jwt=true but live
  config is false'. After the correction all 7 pass. A fixture group asserts the validator itself
  still catches a wrong value, accepts a right one, rejects an unknown slug and ignores the
  non-runnable <verify_jwt> template placeholder — that group exists because deleting the consumed
  runbook sections empties the live scan's input set, and an empty scan would otherwise pass
  vacuously forever.
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "No lib/ file changed. flutter test on the new contract test passes 7/7." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No box, adapter or key is involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL; verify_jwt is not a Postgres object." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "memory_embeddings baseline captured live for the OI-133 behavioural check: 506 rows total, 0 matching the event pattern." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration applied; backups/applied_migrations.json untouched." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "rolling-context 18 to 19 and ai-proxy 79 to 80, both HTTP 201 with verify_jwt false; live config re-read independently via the Management API after both deploys." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "cron.job jobid 19 rolling-context-nightly is active on 0 21 * * * UTC, which is 02:30 IST — the schedule the deferred behavioural check depends on." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched; gateway auth sits above RLS." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "Management API token resolved from supabase/.supabase and both deploys authenticated; no secret value printed, only the sbp_ prefix the tool already logs." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Razorpay, OneSignal and Firebase are untouched." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "ai-proxy returns its OWN error bodies — Missing authorization header at index.ts:184 unauthenticated, and Invalid or expired token at :191 with an anon-key Bearer — proving the gateway passes requests through to the module and the module booted." }
impact_analysis: >
  Severity if executed: P0 outage, all users, immediate. ai-proxy is the single entry point for AI
  coach chat and the only host of food_text_analysis, scan meal and cart auditor. Probability it
  would have been executed: high — it was the copy-pasteable command in the runbook written for
  exactly this session, and the founder had already been told to run it. Detectability once
  executed: poor, which is the worst property here. The deploy script would have printed Smoke OK
  because SMOKE_TOLERATED_CODES lists 401 for ai-proxy, and the operator's next signal would have
  been user reports. Actual impact: zero. The value was checked against live config before any prod
  call, and both deploys ran with verify_jwt false. Corroboration that false is correct: across the
  whole repo, runnable ai-proxy invocations read false eleven times and true exactly once — the
  line this batch removed.
---

# `verify_jwt=true` in the ai-proxy runbook would have 401'd every valid token

## What happened

`docs/operations/FOUNDER_LAPTOP_HANDOFF.md` was written by a Claude Code **web** session that
could not deploy Edge Functions — no Supabase Management API token reaches that container. It
handed the two pending deploys to the founder laptop with exact commands. The `ai-proxy` command
passed `true` as the trailing `verify_jwt` argument.

Live config for `ai-proxy` is `verify_jwt: false`, and the reason is recorded in the function's own
header at `supabase/functions/ai-proxy/index.ts:26-27`:

> of the Supabase middleware bug that 401's valid JWTs. We validate the bearer token ourselves via
> `auth.getUser(token)`.

So the gateway check is off **on purpose**, and the module does the work instead at `:183-191` —
missing header gives 401, bad token gives 401. Passing `true` would have re-enabled the exact
middleware that bug report describes.

## Why it would not have looked like a failure

`.claude/deploy_via_api.js:337` coerces the argument with `verifyJwt = verifyJwtArg !== 'false'`
and ships it as live metadata at `:817`. There is no comparison against current config and no
warning on a change — the only guard is the human-read confirmation box at `:853`, which is
skipped entirely under `--yes`.

Then the post-deploy smoke step would have lied. `:669` reads:

```js
'ai-proxy': [400, 401],          // missing user_id → 400 is healthy
```

That toleration is correct *while* `verify_jwt` is `false`, because an unauthenticated POST reaches
the module and the module answers. Flip the gateway on and the identical 401 now comes from the
gateway with the module never loading — same status code, opposite meaning, and the script prints
`Smoke OK — function reachable; deployment confirmed.`

## How it was caught

Not by a gate — there wasn't one. It was caught by reading live config during session prep and
noticing it contradicted the runbook. Four independent sources then agreed on `false`:

1. Management API: `ai-proxy` v79 `verify_jwt: false`.
2. `ai-proxy/index.ts:26-27` explaining why.
3. `deploy_via_api.js:669`'s toleration comment, which only makes sense if the module is reachable.
4. Repo history: eleven runnable `ai-proxy` invocations pass `false`; one passes `true`.

## The near-identical bug one line above

The same runbook section already carried a correction dated 2026-08-21. It had opened with a
`for fn in ai-proxy weekly-recap-ready weekly-report` loop, removed because it "passed
`verify_jwt=true` for `weekly-recap-ready` whose documented value is `false`".

The author caught that instance and did not check the single-function command directly beneath it.
That is the recurring shape — fixing the instance rather than the class — and it is why the fix
here is a test over *every* runnable invocation in the runbooks rather than an edit to one line.

## Fix

- Runbook corrected to `false`, with the reasoning and the `:853` confirm-box check inline.
- `test/contracts/runbook_deploy_verify_jwt_test.dart` pins every runnable invocation in
  `docs/operations/**` and `.claude/skills/**` against a snapshot of live config. Unknown slugs
  fail rather than skip.
- Historical records — diagnose-docs, audit files, `docs/superpowers/plans/**` — are deliberately
  **out of scope**. They record what was run at the time; rewriting them to match today's config
  would falsify history, the same reasoning CLAUDE.md §7 applies to the closure ledgers. One such
  file does carry a stale value (`weekly-report ... false`, live is `true`), left untouched by
  design.

## Verification

Both deploys ran with the corrected value and were verified from an independent source rather than
from the deploy tool's own output:

| Function | Before | After | verify_jwt | Boot proof |
|---|---|---|---|---|
| `rolling-context` | 18 | **19** | `false` | unauth POST returns 401, not 503 (gates on `isAuthorizedCronCall`) |
| `ai-proxy` | 79 | **80** | `false` | module's own bodies: `Missing authorization header` (`:184`), `Invalid or expired token` (`:191`) |

The `ai-proxy` boot proof is the load-bearing one. Because the response bodies match the module's
source verbatim, they establish two things at once: the gateway passed the request through (so
`verify_jwt` really is `false`), and `captain_manual.ts` parsed (so the long template literal
carrying the new HOLD WEEKS section did not break the bundle — deploy-skill bug-class §6.8).

## Still owed

OI-133's third check is behavioural and could not run on deploy day. `rolling-context-nightly`
fires at 02:30 IST; after the first run on or after 2026-08-25,
`select count(*) from public.memory_embeddings where content like '%{event:%'` must still be `0`
(baseline that day: 506 rows total, 0 matching). Non-zero means the filter is not live despite v19,
and OI-133 should be reopened rather than a new issue filed.

## Related

- OI-133 — closed by this batch's `rolling-context` deploy.
- `docs/operations/FOUNDER_LAPTOP_HANDOFF.md` — corrected and trimmed to the APK build only.
