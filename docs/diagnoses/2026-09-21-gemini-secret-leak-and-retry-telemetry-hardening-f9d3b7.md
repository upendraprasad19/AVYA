---
bug_id: f9d3b7
date: 2026-09-21
batch: observation-batch-and-digest-redesign (self-triggered Hermes pass, catastrophic tier)
status: fixed
blast_radius: platform
symptom: |
  Three independent defects in the shared Gemini call path, all found by
  the self-triggered Hermes pass before merge:

  (1) L40 F1 — Deno's `fetch` rejects a network-level failure with a
  TypeError whose `.message` embeds the FULL request URL. The Gemini
  request URL carries `GEMINI_API_KEY` as a `?key=...` query param. Three
  separate catch/error-handling sites in `gemini.ts` stringified that raw
  exception (`String(err)`) directly into `lastError.message` / `reason`,
  which flows into `reportGeminiExhaustion` -> `public.alerts` -> the
  founder's Telegram digest (`gemini_failure_alert.ts`'s `context_json` and
  `summary`) — none of which are secret-safe destinations. Same bug shape
  this repo's own CLAUDE.md already documents for a Telegram bot token
  leaking through `_shared/telegram.ts`'s fetch errors, applied here to a
  different secret.

  (2) L21 F3 — `rolling-context`'s `summarizeMessages` (its one Gemini call
  site) sits inside a per-USER loop with `retries: 2` and no other retry on
  the path. Worst case: (2+1 passes) x 2 models (Flash, Flash-Lite fallback)
  = 6 Gemini calls per user, all against the SAME shared project quota
  `ai-proxy`'s live user-facing chat also depends on — heaviest exactly when
  Gemini is already degraded (every pass failing is what triggers the next
  one), amplified across every active user in one nightly cron run.

  (3) L34 #4 — `tool-loop.ts`'s hard-failure catch fires
  `reportGeminiExhaustion` unconditionally, with no way for the founder
  reading the resulting Telegram alert to tell "user got NOTHING" apart
  from "user's real action (e.g. logSet) already succeeded in an earlier
  round; only the SUMMARIZATION reply failed" (the exact case FC2's own
  queued-intent apology-suppression already distinguishes for the
  user-facing text, but the alert stayed blind to it).
concept: gemini_secret_redaction / rolling_context_retry_budget / gemini_exhaustion_alert_context
sot_registry_entry: not_applicable
writers:
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: redactSecrets, line: 55 }
  - { file: supabase/functions/rolling-context/index.ts, method_or_widget: summarizeMessages, line: 83 }
  - { file: supabase/functions/_shared/tool-loop.ts, method_or_widget: "runToolLoop (hard-failure catch)", line: 283 }
readers:
  - { file: supabase/functions/_shared/gemini_failure_alert.ts, method_or_widget: reportGeminiExhaustion, line: 32 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: alerts
cloud_columns: [alerts.summary, alerts.context_json]
contract_test_path: supabase/functions/_shared/gemini_backoff_retry_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [public.alerts source=ai_proxy_gemini_exhausted]
cross_account_guard: "Not applicable — no cross-user data path; this is a secret-exposure guard (GEMINI_API_KEY into an admin-only alert channel), not an inter-user isolation concern."
forbidden_patterns_checked:
  - "redacting only the ONE confirmed leak site instead of the whole class — fixed at every message-construction point in gemini.ts that touches an exception or upstream response body, so a fetch/URL implementation detail changing later can't reopen this silently"
  - "dropping rolling-context's retries to 0 outright — this path has NO OTHER retry mechanism (a failed nightly summary is just silently not generated for that user), so a genuine transient blip would lose legitimate summaries; halved instead of zeroed"
  - "suppressing the exhaustion alert entirely when a write intent was already queued — the underlying Gemini failure is equally real either way; only the alert's CONTEXT changes, never whether it fires"
proposed_fix: |
  (1) New exported `redactSecrets(input: string): string` in gemini.ts:
  strips the literal GEMINI_API_KEY value wherever it appears, plus a
  generic `[?&]key=<value>` query-param regex as belt-and-suspenders for a
  differently-encoded or rotated key. Wired into all 5 message-construction
  sites across `_callOnce`/`_callOnceWithTools`/`geminiChatWithTools`'s
  exhaustion-error message that touch an exception or upstream response
  body — not just the one confirmed leak.
  (2) rolling-context: `retries: 2` -> `retries: 1` at summarizeMessages'
  sole geminiChat() call site (worst case per user: 6 -> 4 Gemini calls).
  (3) tool-loop.ts: compute `hadQueuedIntent = intents.length > 0` BEFORE
  both the alert call and the FC2 apology guard (previously only the guard
  read this), and pass it through a new optional `extra` parameter on
  `reportGeminiExhaustion` that merges into `context_json` — additive only,
  never changes whether the alert fires or its severity.
regression_test_planned:
  - supabase/functions/_shared/gemini_backoff_retry_test.ts (new: 3 pure redactSecrets unit tests + 2 behavioral end-to-end leak tests through geminiChat/geminiChatWithTools; corrected 1 pre-existing stale assertion + widened 1 stale scan window, both broken by this same batch's own edits; AMENDED same day by a B-pass — see AMENDMENT below — with 3 more: 2 redact-before-truncate ordering tests + 1 console.warn defense-in-depth test)
  - supabase/functions/_shared/tool-loop_gemini_exhaustion_alert_test.ts (new: hadQueuedIntent:true when a tool call already queued an intent before the failure, hadQueuedIntent:false mirror case)
impact_analysis: |
  All three fixes are corrective within code that either shipped earlier in
  this same batch (tool-loop's reportGeminiExhaustion wiring, itself new
  this batch — see docs/diagnoses/2026-09-21-ai-failure-telemetry-gap-oi226-f7a2c9.md)
  or is a pre-existing shared module (gemini.ts, rolling-context) not
  otherwise touched by this batch. redactSecrets is purely additive to the
  message string (strips one substring/pattern, changes nothing else about
  control flow, retry decisions, or return shapes) — every existing caller
  of geminiChat/geminiChatWithTools is unaffected except for the CONTENT of
  a failure message they already treated as opaque diagnostic text. The
  retries reduction changes only rolling-context's OWN worst-case latency
  and call volume under a genuine outage; its happy path (one call
  succeeds) is unaffected.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "No lib/ changes — entirely server-side (Edge Functions)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none passes with 0 errors on every one of the 6 Gemini-calling functions (ai-proxy, ai-media-proxy, weekly-report, assess-body-composition, daily-snapshot, rolling-context) plus founder-digest and telegram-admin-bot. NOT yet deployed — live deploy remains a separate, founder-authorized action not requested this session." }
mutation_proven:
  mutated: "Reverted redactSecrets to `return input;` (a no-op)."
  result: "Ran deno test on gemini_backoff_retry_test.ts (--node-modules-dir=auto, matching CI): RED — exactly 4 of 22 tests failed (the 2 pure unit tests exercising the query-param/literal-key forms, and the 2 behavioral end-to-end tests through geminiChat/geminiChatWithTools), each failure printing the actual leaked key/value in its assertion message. All 18 unrelated tests (including the 5 retries: N source-pins) stayed green. Reverted; re-ran: GREEN, 22/22. Per this project's own documented pitfall, `--node-modules-dir=auto` materialized node_modules/.deno and replaced the tracked node_modules/pg with a symlink on the FIRST run of this cycle — ran the documented recovery (rm -f node_modules/pg && rm -rf node_modules/.deno && git checkout -- node_modules/) immediately after, confirmed via git status."
  confirmed_applied: "Read the file (Edit/python tool's own before/after) to confirm the mutation matched intent both times; re-ran the full suite after each restore to confirm no other assertion was silently affected."
mutation_proven_hadQueuedIntent:
  mutated: "Set `const hadQueuedIntent = false;` unconditionally in tool-loop.ts, discarding the `intents.length > 0` computation."
  result: "Ran deno test on tool-loop_gemini_exhaustion_alert_test.ts (--node-modules-dir=auto): RED — exactly 1 of 4 tests failed (the new 'tags it hadQueuedIntent:true' test), asserting `false` where `true` was expected. The 3 other tests (total exhaustion with nothing queued, and the happy path) stayed green, confirming the mutation's effect was isolated to the one case it should be. Reverted; re-ran: GREEN, 4/4. Ran the node_modules recovery again after this cycle too."
  confirmed_applied: "Read the file (Edit/sed tool's own before/after) to confirm the mutation matched intent."
mutation_proven_rolling_context_retries:
  mutated: "Not applicable in the redden-a-test sense for the RUNTIME behavior (retries:1 vs retries:2 both compile and both pass the happy-path tests identically — the difference is only observable under a genuine multi-attempt failure, which the shared backoff test already covers generically for OTHER callers). Instead: the pre-existing SOURCE-PIN test (`rolling-context — retries: 2 passed`) reddened IMMEDIATELY on making this exact code change, before any deliberate mutation was needed — proof the test suite was already watching this literal value and caught the change on contact."
  result: "Corrected the test to assert `retries: 1` (renamed to explain why); in the same run discovered the test's own 1000-char scan window no longer reached the argument at all (this fix's own explanatory comment pushed the call-to-argument distance from a previously-measured 763 chars to 1489), which would have made the corrected assertion permanently unable to pass — widened the window to 1800 with a comment recording the new measured distance. Re-ran: GREEN."
  confirmed_applied: "Read the test failure output directly (distance measured via a Python one-liner against the real file, not estimated)."
mutation_proven_redact_before_slice:
  mutated: "Reverted BOTH ordering fixes back to slice-then-redact (_callOnce's HTTP-not-ok branch AND _callOnceWithTools's HTTP-not-ok branch) — the exact pre-fix shape Reviewer A (B-pass) found."
  result: "Ran deno test --node-modules-dir=none on gemini_backoff_retry_test.ts: RED — exactly 2 of 25 failed (the 2 new straddling-key tests added by this amendment), each printing the actual leaked 10-char key fragment (`test-key-n`) in its assertion message. All 23 other tests, including the two pre-existing 'never leaks the FULL key' tests, stayed green — confirming those tests structurally cannot see a PARTIAL-key leak from this ordering bug, which is exactly why Reviewer A's finding survived the original mutation-proof round. Restored; re-ran: GREEN, 25/25."
  confirmed_applied: "Read the actual failure output (the leaked fragment printed verbatim in the assertion message), not just the pass/fail count."
mutation_proven_console_warn_defense_in_depth:
  mutated: "Three-way test, matching Reviewer B's own mutation exactly: (a) revert ONLY the inner redactSecrets call inside _callOnceWithTools's catch block, keeping the new console.warn-site redaction; (b) restore (a), then ALSO revert the new console.warn-site redaction, removing both layers."
  result: "(a) 25/25 GREEN — the new console.warn defense-in-depth redaction independently catches the leak even with the inner layer gone; captured console.warn output showed [REDACTED] in place of the key. (b) with BOTH layers gone: 24/25 — RED, and the ONLY failing test was the new 'per-attempt console.warn never leaks... (defense-in-depth)' test; the PRE-EXISTING 'geminiChatWithTools: a persistent fetch throw never leaks GEMINI_API_KEY into the thrown exhaustion Error's message' test stayed GREEN throughout, with the raw key visibly present in the captured console.warn output — reproducing Reviewer B's exact finding that every pre-existing test is blind to this specific log-line leak because it inspects only the FINAL exhaustion message, which geminiChatWithTools re-redacts independently of the per-attempt log line. Restored both; re-ran: GREEN, 25/25."
  confirmed_applied: "Read the actual console.warn output captured by the test in both mutated states, not just the pass/fail counts."
---

## Summary

Three defects in the shared Gemini call path, found by the same
self-triggered Hermes pass covering this catastrophic-tier batch: a secret
(`GEMINI_API_KEY`) could leak into a founder-facing Telegram alert through
an unredacted fetch error; one cron function's retry budget amplified Gemini
call volume across every active user in a single nightly run; and the
coach's Gemini-exhaustion alert couldn't distinguish "user got nothing" from
"user's real action already succeeded, only the reply failed."

## Root cause

`gemini.ts` stringified raw exceptions directly into failure messages meant
for founder-facing diagnostics, without accounting for the fact that Deno's
`fetch` embeds the full request URL — including this project's own
query-param API key convention — in a network-level TypeError.
`rolling-context` inherited a retry count tuned for a single-call context
(`f7a2c9`) without accounting for its own per-user loop multiplying that
count by every active user. `tool-loop.ts`'s alert call predates the
FC2 queued-intent distinction and was never updated to carry it.

## Fix

See `proposed_fix` in the frontmatter above — `redactSecrets` wired at every
message-construction site touching an exception or response body;
`rolling-context`'s retries halved from 2 to 1; `hadQueuedIntent` computed
once and threaded through both the alert's `context_json` and the
pre-existing FC2 guard.

## Verification

- See the three `mutation_proven*` sections above — each fix was verified
  against a real reversion, with the resulting test failures inspected
  (not just counted) to confirm they redden for the right reason and stay
  isolated to the intended assertions.
- `deno check --node-modules-dir=none` clean on all 6 Gemini-calling
  functions plus founder-digest and telegram-admin-bot.
- The documented `node_modules/pg` auto-mode corruption was hit twice
  during this verification cycle (once per test file requiring
  `tools/types.ts`'s zod import) and recovered both times per the
  established procedure, confirmed clean via `git status` after each.

## Files changed

- Modified: `supabase/functions/_shared/gemini.ts`
- Modified: `supabase/functions/_shared/gemini_failure_alert.ts`
- Modified: `supabase/functions/_shared/tool-loop.ts`
- Modified: `supabase/functions/rolling-context/index.ts`
- Modified: `supabase/functions/_shared/gemini_backoff_retry_test.ts`
- Modified: `supabase/functions/_shared/tool-loop_gemini_exhaustion_alert_test.ts`
- Created: this diagnose-doc.

## AMENDMENT (2026-09-21) — B-pass round on the full batch, 2 findings

A self-triggered B-pass on the FULL 69-file staged batch (required before
the `--no-ff` merge per CLAUDE.md §4.3, catastrophic tier) ran two fresh
context-blind reviewers, specifically instructed to give this file's fixes
their closest attention since no independent review had touched them yet.
Two findings, both real:

**Finding (Reviewer A, P2, secrets_in_tree)** — the two `!response.ok`
branches (`_callOnce` and `_callOnceWithTools`) sliced the raw response
body to 200 chars BEFORE calling `redactSecrets`, backwards from the two
catch/transport-error branches (which redact-then-slice). If the raw key
ever appeared in an HTTP error response body and straddled the 200-char
truncation boundary, the truncated fragment would no longer match the
full-key literal `redactSecrets` looks for, leaking that fragment
un-redacted. **Fixed**: both branches now redact the FULL response text
before truncating, matching the pattern already used in the file's two
catch blocks. Proven with 2 new tests constructing a body where the key
straddles exactly that boundary — see `mutation_proven_redact_before_slice`
above.

**Finding (Reviewer B, P1, guard_without_its_mirror)** — `geminiChatWithTools`'s
per-attempt `console.warn` (one log line per failed attempt, up to 4 times
per request) had NO redaction of its own — its only protection was
`_callOnceWithTools`'s inner `redactSecrets` call, one layer away. Reviewer
B proved by mutation that reverting that inner call left the raw key
leaking into this log line on every retriable failure while **all 22
pre-existing tests stayed green**, because every one of them inspects only
the FINAL thrown/alerted message — which stays clean because
`geminiChatWithTools` separately re-redacts `lastReason` when building
THAT message. This is exactly the completeness gap this file's own fix was
written to close ("applied at every point... not just the one confirmed
leak"), missed for the one sink no existing test could see. **Fixed**:
added a second, independent `redactSecrets` call at the `console.warn`
site itself — defense-in-depth, so this log line no longer depends on the
inner call staying correct. Proven with a new test that captures
`console.warn` output directly and, via the three-way mutation in
`mutation_proven_console_warn_defense_in_depth` above, reproduces
Reviewer B's exact finding: with both layers removed, this new test is the
ONLY one of 25 that reddens.

Neither finding indicated the batch's core secret-redaction fix was
wrong in principle — both were genuine gaps in its completeness, found by
the first independent adversarial pass this specific code received.
