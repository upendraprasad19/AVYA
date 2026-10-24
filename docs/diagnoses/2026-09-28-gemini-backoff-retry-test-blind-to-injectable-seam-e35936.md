---
bug_id: e35936
date: 2026-09-28
batch: single-owner-a2b (found during final full-suite verification, no unit of its own)
status: fixed
blast_radius: platform
symptom: |
  `supabase/functions/_shared/gemini_backoff_retry_test.ts`'s
  `assertSoleCallSiteHasRetries` helper — which exists specifically to pin
  `retries: 2` at each of 5 single-call-site Gemini functions
  (assess-body-composition, daily-snapshot, ai-media-proxy,
  rolling-context, weekly-report) — went permanently blind for
  `daily-snapshot` the moment unit a2a's own test-seam refactor
  (`docs/plan-reviews/single-owner-a2.md`, commit `c0e3ec54`) changed that
  function's actual Gemini call from `geminiChat({...})` to an injectable
  `geminiChatFn({...})` parameter (defaulting to the real `geminiChat`, so
  tests could inject a fake). The helper's literal source-grep
  (`source.indexOf("geminiChat({")`) does not match `geminiChatFn({` — "Fn"
  sits between "geminiChat" and "({", so the substring is absent — and the
  test failed with `daily-snapshot: no geminiChat( call found`.

  **Invisible to every targeted run in this whole batch.** a2a, a2b-1 and
  a2b-2 each ran `daily-snapshot/index_test.ts` directly (and green) many
  times; none of those runs execute
  `supabase/functions/_shared/gemini_backoff_retry_test.ts`, which lives in
  `_shared/` and is only exercised by a suite-wide `deno test
  supabase/functions/`. That command was not run once across three units
  and two B-pass rounds until this final verification pass — the exact
  "targeted run is a different input set from the suite" class
  `supabase/migrations/CLAUDE.md`'s sibling common-pitfalls table already
  documents for Flutter tests, now confirmed for Deno too.
concept: retries_2_sole_call_site_pin (existing SoT-adjacent test contract, no registry entry — presence-only Deno source-grep, per docs/sot_registry.yaml's own convention for this test file)
sot_registry_entry: not_applicable — this is a test-infrastructure regression, not a new writer/reader contract.
related_bugs:
  - This is a fresh instance of the recurring "extracting/moving code
    breaks source-grep contracts in files you never touched" class already
    documented in root CLAUDE.md's common-pitfalls table (2026-08-30,
    recurred 2026-09-16 3x) — here the moved thing is the CALL-SITE'S OWN
    NAME (via a default-parameter seam), not a file location, but the
    failure shape is identical: a literal-string test pinned to old text
    goes silently blind when the text legitimately changes for an
    unrelated, good reason.
  - OI-260 — filed by this fix's own B-pass (self-triggered, per §4.3):
    4 SIBLING files carry the identical hazard shape but are NOT currently
    broken (`weekly-report/index_test.ts:44`,
    `assess-body-composition/index_test.ts:39`,
    `ai-media-proxy/index_test.ts:430`, `rolling-context/index_test.ts:69` —
    each its own `source.indexOf("await geminiChat({")` for the OI-238
    `reportGeminiExhaustion`-wiring tests, not the retries-pinning tests
    fixed here). Not fixed in this batch: none of the 4 functions currently
    uses an injectable seam, so nothing is broken today, and each one fails
    LOUD (not silently) the moment it would matter — filed rather than
    fixed per the "not a live bug, just a latent-recurrence shape" carve-out.
writers:
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "extractCoachingNotes's geminiChatFn({...}) call (line 250)", line: 250 }
readers:
  - { file: supabase/functions/_shared/gemini_backoff_retry_test.ts, method_or_widget: "assertSoleCallSiteHasRetries", line: 261 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: supabase/functions/_shared/gemini_backoff_retry_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable
forbidden_patterns_checked:
  - "loosening the uniqueness check to `>= 1` instead of exactly 1 — rejected: the whole point of this helper is catching a SECOND call site sneaking in with no retries, and a file could legitimately contain both spellings in different unrelated code (e.g. a comment)."
  - "renaming daily-snapshot's call site back to `geminiChat(` directly, dropping the injectable seam — rejected: that seam is a2a's own deliberate testability fix (docs/plan-reviews/single-owner-a2.md), and reverting it to satisfy an unrelated test's literal-string assumption would undo real, wanted work."
proposed_fix: |
  Widen `assertSoleCallSiteHasRetries` to recognize EITHER `geminiChat({`
  OR `geminiChatFn({` as a valid call-site marker, and count total call
  sites across BOTH spellings (still must equal exactly 1) rather than
  just the bare-name spelling. The two literal substrings are mutually
  exclusive (`geminiChat({` is never a substring of `geminiChatFn({`,
  since "Fn(" sits between them), so summing both counts cannot
  double-count a single real call site.
regression_test_planned: |
  The fix IS the test file itself (`_shared/gemini_backoff_retry_test.ts`).
  Mutate it and run it (rule 21): hardcoded `seamIdx = -1` (simulating the
  pre-fix state where the seam spelling is never recognized) and re-ran —
  reddened EXACTLY the `daily-snapshot — retries: 2 passed` test (24 others
  in the same file stayed green), confirming the widening is what's load-
  bearing, not an unrelated change. Restored via `cp` from a manual backup
  (never `git checkout`) and re-confirmed 25/25 green. Also ran the full
  `deno test supabase/functions/` before and after: before, 648 passed / 3
  failed (this bug + the 2 known VPS-only AddrInUse failures in
  future-prediction/re-engagement, unrelated to this branch's diff — see
  `reference_vps_port_8000_deno_addrinuse.md`); after, 649 passed / 2
  failed (only the 2 known-unrelated VPS failures remain).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "Deno/Edge-Function test infrastructure only; no Dart/client code touched." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none clean on the fixed test file; deno test green (25/25 targeted, 649/651 suite-wide with the 2 remaining failures independently confirmed unrelated to this branch's diff via `git diff --name-only origin/main...HEAD`)." }
impact_analysis: |
  Zero production behavior change — this is a test-file-only fix. Impact is
  entirely on test COVERAGE: before this fix, a future regression that
  removed or weakened `retries: 2` at daily-snapshot's Gemini call site
  would have gone completely undetected by this test (it was asserting a
  pattern that could never match), silently reducing this function's
  resilience to a transient Gemini failure back to zero retries with no
  test failure anywhere. After this fix, that protection is restored.
---

# `assertSoleCallSiteHasRetries` blind to daily-snapshot's injectable-seam call site

## Summary

Found during final full-suite verification of the `single-owner-a2b`
branch (a2a + a2b-1 + a2b-2, preparing the merge-time plan-review record).
A full `deno test supabase/functions/` run — the first time this exact
command had been run across this branch's whole lifecycle — surfaced a
real, silent regression: `daily-snapshot`'s own retry-pinning test had been
unable to find its call site since a2a's test-seam refactor landed, and
had been failing on every full-suite run since, invisible to every
targeted per-function test invocation used throughout a2a/a2b-1/a2b-2.

## Root cause

`extractCoachingNotes` (daily-snapshot/index.ts) takes an injectable
`geminiChatFn` parameter, defaulting to the real `geminiChat`, so tests can
substitute a fake. The runtime call reads `await geminiChatFn({...})`, not
`await geminiChat({...})`. `assertSoleCallSiteHasRetries`'s literal
`source.indexOf("geminiChat({")` search does not match — "Fn(" sits
between "geminiChat" and "({" in the real source — so the helper reported
"no geminiChat( call found" and the test failed.

## Fix

Widened the helper to recognize either spelling and sum occurrences of
both (still requiring exactly one total call site). See `proposed_fix`
above for the exact mechanism and why the two spellings can't double-count
each other.

## Why this diagnose-doc exists rather than folding into a2b-2's own

This is genuinely orthogonal to a2b-2's own scope (coach-extraction
locked fields) — it is a side effect of a2a's earlier, already-landed
refactor, discovered only by this final full-suite check. Filed as its own
diagnose-doc per the recurrence-class carve-out in CLAUDE.md §4.4 rule 22
(this is the same "extracting/moving code breaks source-grep contracts"
class already on the board, just with a call-site *name* moving instead of
a file).
