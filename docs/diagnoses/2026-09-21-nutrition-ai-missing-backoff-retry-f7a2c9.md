---
bug_id: f7a2c9
date: 2026-09-21
batch: observation-batch-and-digest-redesign (A2b)
status: fixed
blast_radius: platform
symptom: |
  Investigation finding (gate check under A5, expanded across two plan-review
  rounds): 9 production `geminiChat(...)` call sites had no `retries` argument
  (default 0), so a single transient empty-candidate/429/5xx response failed
  the whole request outright — food_text_analysis, scan_meal, cart_auditor and
  the `prediction` handler in ai-proxy/index.ts, plus assess-body-composition,
  daily-snapshot, ai-media-proxy, rolling-context, and weekly-report. The
  coach's own tool-loop path (`geminiChatWithTools`) already has bounded
  backoff-retry since diagnose d4f1c2 (2026-06-01); none of these 9 single-shot
  callers did.
concept: nutrition_ai_gemini_resilience
sot_registry_entry: >
  not_applicable — this is Edge Function upstream-call (Gemini) resilience,
  not a Hive/cloud writer/reader SoT concept. Same framing as d4f1c2's
  ai_coach_tool_loop_gemini_resilience, which is also absent from
  docs/sot_registry.yaml. The AI call sites themselves are charted under
  docs/architecture/ai.md.
recurrence: >
  Sibling of d4f1c2 (2026-06-01) — same missing-backoff-retry class, different
  call sites: d4f1c2 fixed the coach tool-loop's geminiChatWithTools; this
  fixes the plain geminiChat() single-shot helper's 9 production callers,
  which never got the equivalent. food_parser.ts's logMealByText tool call
  (retries: 2, already in place) is the one geminiChat() caller that had
  already been given this treatment, and served as the fix's reference
  pattern.
related_bugs:
  - d4f1c2
writers:
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "food_text_analysis handler", line: 416 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "scan_meal handler", line: 612 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "cart_auditor handler", line: 655 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "prediction handler", line: 716 }
  - { file: supabase/functions/assess-body-composition/index.ts, method_or_widget: "serve handler", line: 158 }
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "coach-personality extraction", line: 146 }
  - { file: supabase/functions/ai-media-proxy/index.ts, method_or_widget: "serve handler", line: 921 }
  - { file: supabase/functions/rolling-context/index.ts, method_or_widget: "summarizeConversation", line: 83 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: "Captain Brief generation", line: 548 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "food_text_analysis / scan_meal / cart_auditor response consumers", line: 733 }
  - { file: lib/core/services/ai_service.dart, method_or_widget: "prediction response consumer", line: 393 }
hive_key_prefix: not_applicable
hive_key_formula: "not_applicable (no Hive key involved — server-side Edge Function resilience)"
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
cross_account_guard: >
  Not applicable — the retry is per-request and stateless; no cross-account
  state is read or written by any of the 9 call sites' retry configuration.
forbidden_patterns_checked:
  - "Applying retries:2 to weekly-report's 40s-timeout Gemini 2.5 Pro call without checking wall-clock impact — verified geminiChat's retryDeadlineMs (20s) is checked BETWEEN passes, not within one, so it does not multiply with the 40s per-attempt timeoutMs; confirmed safe in plan review round 2 before applying."
  - "A whole-file `includes('retries: 2')` count that can't tell 'present at the right call site' from 'present somewhere in the file' — the exact feedback_green_check_input_set_width class. Used bounded-window, anchor-scoped source pins per site instead (see regression_test_planned)."
proposed_fix: |
  Passed `retries: 2` at all 9 real call sites (re-derived from source via
  `grep -rn "geminiChat(" supabase/functions` rather than trusted from the
  spec's own prose, which said "7" in its title/fix paragraph while its own
  enumerated list — and the live source — total 9; the spec's count was
  stale from before its two review-round expansions were folded into the
  headline number). Mirrors food_parser.ts:114's existing pattern for the
  coach's own logMealByText tool. Confirmed geminiChat's retriable-empty-
  candidate classification (the "empty text in candidate" branch, gemini.ts
  ~line 314-320) is inside the SAME retried loop as 429/5xx — no separate
  classification work needed, this is the identical shared helper d4f1c2
  already hardened for geminiChatWithTools's own retry logic.
regression_test_planned:
  - supabase/functions/_shared/gemini_backoff_retry_test.ts
impact_analysis: |
  Additive and conservative, matching d4f1c2's own precedent: the happy path
  is unchanged (a successful first call never enters the retry loop), and
  retries only fire on the retriable bucket (429/5xx/empty-candidate) that
  geminiChat's shared loop already classifies — a non-retriable 4xx or a
  25s-timeout AbortError still fails immediately, exactly as before. Platform
  blast radius: 9 call sites span all 3 client-facing AI proxies
  (ai-proxy ×4, ai-media-proxy) plus 3 other client-invoked or cron-dispatched
  Gemini callers (assess-body-composition, daily-snapshot, rolling-context)
  and the weekly report. weekly-report was sanity-checked specifically since
  it is a rare, expensive Gemini 2.5 Pro call with a 40s per-attempt timeout:
  geminiChat's retryDeadlineMs (20s wall-clock, checked BETWEEN passes) means
  a failing first pass at 40s+ already exceeds the deadline, so retries:2
  adds only a small, bounded amount of additional worst-case latency on the
  failure path — not a multiplicative 2-3x of the base timeout.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "This fix touches only Edge Function (Deno) source under supabase/functions/ — no lib/ files changed." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none passes with 0 errors on all 6 touched functions (ai-proxy, assess-body-composition, daily-snapshot, ai-media-proxy, rolling-context, weekly-report). deno test --allow-env --allow-read --node-modules-dir=none supabase/functions/_shared/gemini_backoff_retry_test.ts — 16/16 passed (5 pre-existing geminiChatWithTools cases + 2 new geminiChat behavioral cases + 9 new per-call-site source pins). NOT yet deployed — the live redeploy of these 6 functions remains a separate, founder-authorized action not requested this session." }
mutation_proven:
  mutated: "Removed retries: 2 (and its comment) from the food_text_analysis call site only (ai-proxy/index.ts), confirmed applied by reading the file before running."
  result: "Ran deno test on gemini_backoff_retry_test.ts: RED on exactly 1 of 16 — 'ai-proxy food_text_analysis — retries: 2 passed' (AssertionError: retries: 2 not found at this call site). All other 15 tests, including the other 3 ai-proxy per-site pins (scan_meal, cart_auditor, prediction), stayed green — confirming the bounded-window per-site assertions are actually scoped to their own call site and not silently passing off a shared/aggregate signal. Reverted the mutation; re-ran: 16/16 green. Re-verified node_modules/ untouched (git status --porcelain node_modules/ empty) and ai-proxy/index.ts still type-checks clean after the revert."
  confirmed_applied: "Read the file both before removing (to capture the exact block) and after reverting to confirm the restored text matched the original."
---

## Summary

9 production `geminiChat(...)` call sites across 6 Edge Functions had no
`retries` argument (default 0), so a single transient empty-candidate, 429,
or 5xx response from Gemini failed the whole request — a food log, a scan, a
cart audit, a prediction, an assess-body-composition scan, a daily-snapshot
personality extraction, a media-chat reply, a rolling-context summary, or a
weekly report — with no recovery, even though the SAME shared `geminiChat`
helper already supports bounded retry via its `retries` option.

## Root cause

The coach's tool-calling path (`geminiChatWithTools`) got bounded backoff-retry
in diagnose d4f1c2 (2026-06-01). The plain single-shot `geminiChat()` helper
gained the same `retries` option at the same time (it's the one place both
paths share retry-classification logic), but only `food_parser.ts`'s
`logMealByText` tool call was ever updated to actually pass `retries: 2`. The
other 9 real call sites were never revisited — an incomplete rollout, not a
design gap.

## Fix

Passed `retries: 2` at all 9 sites, verified by re-deriving the call-site list
from a live `grep -rn "geminiChat(" supabase/functions` rather than trusting
the design spec's own count (its title and fix paragraph said "7" while its
own itemized list, and the live source, total 9 — a stale headline number
left over from before two review-round scope expansions were folded in).
`weekly-report`'s site was sanity-checked specifically for wall-clock safety
given its 40s per-attempt timeout and Gemini 2.5 Pro cost — confirmed safe,
see impact_analysis.

## Verification

- `deno check --node-modules-dir=none` on all 6 touched functions — 0 errors.
- Extended `gemini_backoff_retry_test.ts` with 2 new behavioral cases proving
  the shared `geminiChat` retry mechanism actually recovers an empty-candidate
  response when `retries: 2` is passed, and does NOT when it's the pre-fix
  default (0) — plus 9 bounded-window, anchor-scoped source pins, one per real
  call site, so a gap at any single site fails its own named test rather than
  being masked by an aggregate/whole-file check.
- Mutation proof: removing `retries: 2` from one site (food_text_analysis)
  reddened exactly that site's own test and none of the other 15 — confirming
  the per-site scoping is real.

## Files changed

- Modified: `supabase/functions/ai-proxy/index.ts` (4 sites)
- Modified: `supabase/functions/assess-body-composition/index.ts`
- Modified: `supabase/functions/daily-snapshot/index.ts`
- Modified: `supabase/functions/ai-media-proxy/index.ts`
- Modified: `supabase/functions/rolling-context/index.ts`
- Modified: `supabase/functions/weekly-report/index.ts`
- Modified: `supabase/functions/_shared/gemini_backoff_retry_test.ts`
- Created: this diagnose-doc.
