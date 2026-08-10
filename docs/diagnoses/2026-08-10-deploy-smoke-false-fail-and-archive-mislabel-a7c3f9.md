---
bug_id: a7c3f9
date: 2026-08-10
batch: post38-auth-fixes (slice 0 rider — two defects the v13 deploy exposed in the deploy tool itself)
status: fixed
blast_radius: feature
symptom: >
  Deploying log-client-error v13 returned HTTP 201 with a healthy ACTIVE
  function, and then printed
  "Smoke FAIL — HTTP 401 (not in tolerated set [400])" followed by rollback
  instructions. The deploy was correct; the smoke verdict was wrong. Separately,
  the same run archived its payload as v4_4df6ef2.json — naming it after a
  main-branch commit whose tree contains a FIVE-entry PRE_AUTH_OP_TYPES, while
  the archived payload contains six. The archive filename asserted a provenance
  that was false.
concept: deploy_smoke_tolerated_codes
sot_registry_entry: not_applicable — deploy tooling; no Hive or cloud writer/reader contract changes
writers: >
  .claude/deploy_via_api.js:612-706 SMOKE_TOLERATED_CODES (the table consulted
  by runSmokeStep) and .claude/deploy_via_api.js:567-598 archivePayload (writes
  backups/edge_function_payloads/<fn>/v<N>_<sha>.json). The sha it stamps comes
  from currentHeadSha(), which reads `git rev-parse HEAD` with cwd = REPO_ROOT.
readers: >
  A human reading the deploy console output (the only consumer of the smoke
  verdict — nothing gates on it), and any future rollback that navigates from an
  archive filename back to the commit it names. There is no automated reader; a
  wrong value here misleads a person, which is why it survived two prior deploys.
hive_key_prefix: "not_applicable — no Hive involvement"
hive_key_formula: "not_applicable"
sync_methods: "not_applicable — deploy-time tooling, no runtime sync path"
restore_methods: >
  not_applicable for app data. Relevant only in that the payload archive IS the
  rollback artifact — and its CONTENT was always correct; only the filename lied.
cloud_table: "not_applicable"
cloud_columns: "not_applicable"
contract_test_path: "not_applicable — see regression_test_planned for why, and what was done instead"
ist_handling: "not_applicable — no date keys or counter resets in this path"
provider_invalidations: "None — no Riverpod state involved"
telemetry_op_types: >
  None added. Worth stating explicitly because the FUNCTION being deployed is the
  telemetry sink: this fix touches the deploy tool, not log-client-error's own
  op_type surface, which is unchanged at six PRE_AUTH_OP_TYPES entries.
cross_account_guard: "not_applicable — no user-scoped data path"
forbidden_patterns_checked: >
  No raw Hive.box; no setState; no inline isPro; no secrets in the diff (the
  Supabase access token is read at runtime from the gitignored
  supabase/.supabase/ path and is not in the diff); no Container(color:+decoration:).
proposed_fix: >
  (1) SMOKE MAP — add 401 to log-client-error's tolerated set. The function is
  verify_jwt=true, so the gateway answers a headerless {smoke:true} probe with
  401 before the module ever runs. Every other auth-required function in the
  same table already lists 401 with that exact rationale
  (get-community-review-items, admin-dashboard-data, and 12 more); this entry
  was the lone outlier at [400]. The consequence was not a one-off: it made the
  smoke step fail on EVERY deploy of this function, permanently.
  (2) ARCHIVE PROVENANCE — new provenanceSha() verifies the claim before making
  it. It diffs the payload's index.ts against `git show <headSha>:supabase/
  functions/<fn>/index.ts` (CRLF-normalised, since this repo is authored on
  Windows and checked out on Linux in CI) and returns the 7-char sha only when
  they match; otherwise 'nosha' plus a warning naming the cause. Fails OPEN to
  'nosha' on any git error — an unreadable object must never crash a healthy
  deploy.
  REJECTED alternative for (2) — thread the source sha through the payload JSON
  from emit_payload.js: the payload is a bare ARRAY, so that is a contract change
  across two scripts on the path whose entire value proposition is being
  byte-identical to git. Verifying a claim the tool can already check itself is
  strictly smaller and cannot break the deploy.
  REJECTED alternative for (2) — keep stamping HEAD and document the caveat: a
  wrong sha is worse than no sha, because it actively routes a future rollback to
  source that never produced the payload. 'nosha' is honest; the archive CONTENT
  is what rollback actually consumes.
regression_test_planned: >
  Executed, not planned — and deliberately NOT as a test/contracts/ file. Two
  facts make the usual Dart contract test the wrong instrument here: CI does not
  set up node (.github/workflows/test.yml provisions deno only, lines 108/125),
  so a JS unit test would never be gated; and deploy_via_api.js runs a top-level
  async IIFE with no `require.main` guard, so it cannot be imported without
  attempting a deploy. A Dart test parsing a JS object literal to assert one
  entry contains 401 would be a source-grep presence check — the exact
  false-confidence shape feedback_source_grep_false_confidence.md warns about.
  What was done instead: both fixes were EXECUTED against the real edited file by
  extracting SMOKE_TOLERATED_CODES and provenanceSha from its source text, with
  the red path proven —
    smoke predicate(401) with the fixed table  -> true
    smoke predicate(401) with the pre-fix [400] -> FALSE  (reproduces the bug)
    provenanceSha(payload, branch sha 034e712)  -> "034e712"
    provenanceSha(payload, main sha 4df6ef2)    -> "nosha" (reproduces the 2026-08-10 mislabel)
    provenanceSha(payload, null)                -> "nosha"
  Ground truth for the smoke half was taken independently: a real headerless POST
  to the live function returns 401, and a real anon-key POST carrying
  op_type auth_send_phone_otp_failed returns 200 {"priority_lane":"pre_auth"}.
  Making this script unit-testable (a require.main guard + module.exports) is a
  real change to the execution model of the tool that had just performed a
  production deploy, and is filed as OI-105 rather than bundled into the same
  commit that fixes the defects it would test.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "no lib/ change; this is .claude/ deploy tooling, classified feature-tier by scripts/blast_radius_from_diff.dart" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "no Hive access" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no DDL" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "the v13 verification row (client_errors id c67f03ac, user_id NULL, op_type auth_send_phone_otp_failed) was inserted to prove the lane end-to-end, then DELETED — re-queried, zero rows for error_code v13_deploy_verification" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this commit; 119 was already recorded by d4a8de00" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "log-client-error v12 -> v13 deployed, status ACTIVE, verify_jwt true. Re-fetched the DEPLOYED source via get_edge_function and confirmed PRE_AUTH_OP_TYPES now has all six entries including auth_send_phone_otp_failed. This closes OI-93's fourth instance for this function." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron path touched" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: verified, evidence: "deploy token still resolved from the gitignored supabase/.supabase/ path; no secret added to or printed by the diff (the script prints only a 10-char token preview, unchanged)" }
  - { tier: 11, name: external_services, status: verified, evidence: "Supabase Management API POST /v1/projects/dedsavbjuwgarrhphgnl/functions/deploy returned 201 in 1991ms" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "full chain exercised live against v13: anon-key POST -> pre-auth lane accepted the 6th allow-list op_type -> 200 {priority_lane: pre_auth} -> row present in client_errors with user_id NULL. Under v12 that identical call returns 401, which is what makes it a discriminating test rather than a smoke check." }
impact_analysis: >
  Neither defect could affect a user, and neither could corrupt a deploy — the
  cost of both is paid entirely in trust of the tooling.
  The smoke defect is the more corrosive of the two. A verification step that
  reports FAIL on every healthy run, complete with rollback instructions,
  teaches the operator to skip reading it. That is the same failure mode as a
  telemetry sink that silently drops — the signal is present and worthless. It
  had already fired on at least the v11 and v12 deploys of this function and was
  worked around by hand each time rather than fixed.
  The archive defect is narrower but sharper: it produces a confidently wrong
  answer to "which commit produced the code that is running in production?" —
  precisely the question asked in an incident, under time pressure, when nobody
  is inclined to double-check a filename.
  Both were found only because the v13 deploy was run and its output actually
  read. Worth recording as evidence that "the tool reported success" and "the
  thing is correct" are different claims, which is the same lesson as
  feedback_git_landing_verification.md in a different subsystem.
related_bugs: >
  OI-93 (deployed Edge Function lagging the repo, undetected) — this batch closes
  its fourth instance for log-client-error by shipping v13. b6e4f2 is the
  diagnose-doc for the pre-auth lane whose redeploy exposed both defects.
recurrence: >
  New for these two specific defects, but the CLASS is well documented and this
  is at least its third appearance: a check whose green (or red) verdict is
  decided by an input set nobody examined — feedback_green_check_input_set_width.md
  ("name the input set a check consumed before citing it"). Here the smoke check's
  tolerated-code set omitted the only status the function can actually return to
  that probe, and the archive's sha came from a worktree nobody confirmed was the
  payload's source. In both cases the check ran, produced output, and was wrong
  about the thing it existed to assert.
---

# a7c3f9 — deploy tool: smoke step false-FAILs forever, archive filename claims a false provenance

Both defects were found while performing the authorised v13 redeploy of
`log-client-error` (the sixth `PRE_AUTH_OP_TYPES` entry that round-1 review added
to the repo source and that was never deployed — OI-93's fourth instance).

## What actually happened

The deploy succeeded: `HTTP 201`, `version: 13`, `status: ACTIVE`. The tool then
printed a smoke FAILURE and offered rollback instructions for a function that was
working correctly, and wrote its rollback archive under a filename naming a commit
that does not contain the archived code.

## Why the smoke step cannot ever have passed

`log-client-error` is `verify_jwt: true`. The smoke probe is a POST with **no**
`Authorization` header. Supabase's gateway rejects that at the edge with
`401 UNAUTHORIZED_NO_AUTH_HEADER` — the module never executes, so it never gets
the chance to return the `400 Missing error_code` that the tolerated set `[400]`
was written for. The entry describes a response this function is structurally
incapable of producing under smoke conditions.

The table itself shows the intended convention plainly — thirteen other
auth-required functions list `401` with comments like
`verify_jwt — unauth smoke gets a gateway 401 (expected, not a failure)`. This
one entry simply missed it.

## Why the archive sha was wrong

`archivePayload()` stamps `currentHeadSha()`, which is `git rev-parse HEAD` with
`cwd = REPO_ROOT`. But `emit_payload.js` accepts `--functions-dir`, so the payload
routinely comes from a **different worktree** than the one the process is running
in — exactly what happened here, per CLAUDE.md §4.13 (the primary worktree is
integration-only, so deploys are run from it while the source lives on a branch
worktree). Nothing connected the two, and nothing checked.

The fix does not try to discover the source worktree. It verifies the claim it is
about to make and declines to make it when it cannot be substantiated.

## The honest limit of this fix

`provenanceSha` returns `nosha` for **any** mismatch, including a legitimately
dirty working tree — a payload emitted from uncommitted edits will now be archived
as `nosha` rather than stamped with a sha that merely happens to be checked out.
That is the intended trade: the filename means "this commit contains this payload"
or it means nothing, with no third state that looks like the first.
