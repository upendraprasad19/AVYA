---
bug_id: b6e3a8
date: 2026-09-22
batch: oi-batching-strategy (Batch C)
status: fixed
blast_radius: platform
symptom: |
  OI-238 (open_issues.md, filed 2026-09-22 from the Hermes pass on
  `observation-batch-and-digest-redesign`): OI-226's own fix
  (`docs/diagnoses/2026-09-21-ai-failure-telemetry-gap-oi226-f7a2c9.md`) wired
  `reportGeminiExhaustion` into `ai-proxy`'s 4 internal `type` handlers plus
  `tool-loop.ts`'s chat/tool-calling path — 5 call sites, all inside ONE
  function (`ai-proxy`). Per `supabase/functions/CLAUDE.md`'s own AI
  Architecture section, 6 Edge Functions call Gemini directly in total; the
  other 5 — `weekly-report`, `ai-media-proxy`, `assess-body-composition`,
  `daily-snapshot`, `rolling-context` — each called `geminiChat()` with no
  server-side exhaustion alert of any kind. A total Gemini failure on any of
  these 5 was invisible to the founder until a user complained (or, for
  `rolling-context`, silently produced zero nightly conversation summaries
  with no page at all).

  Re-verified live before writing this doc, not assumed from the OI's filed
  text: `grep -n "geminiChat\|reportGeminiExhaustion" supabase/functions/{weekly-report,ai-media-proxy,assess-body-composition,daily-snapshot,rolling-context}/index.ts`
  confirmed all 5 called `geminiChat` and none referenced
  `reportGeminiExhaustion`, and none of the 5 destructured `lastError` from
  `GeminiResult` — the OI's claim had not drifted since filing.
concept: ai_failure_telemetry_coverage
sot_registry_entry: >
  not_applicable — same framing as the sibling OI-226 fix (f7a2c9): this is
  server-side incident-alerting (reportGeminiExhaustion → public.alerts), not
  a Hive/cloud writer/reader SoT concept. The pre-existing wiring is
  documented as a prose table row (not a docs/sot_registry.yaml entry) in
  supabase/functions/CLAUDE.md under "gemini_failure_alert", extended by this
  fix to cover the 5 new call sites and close OI-238's pointer.
recurrence: >
  Direct sibling of OI-226/f7a2c9 — same underlying gap (a geminiChat() call
  site with no reportGeminiExhaustion wiring), on a DIFFERENT surface (5
  other Gemini-calling Edge Functions instead of ai-proxy's own internal
  handlers). Also an instance of feedback_observability_silent_drop.md (a
  failure path with no distinguishable signal reads as "working" until an
  incident makes it obvious) and feedback_bad_news_vs_no_news.md — a silently
  absent alert collapses "Gemini is really down" into "no signal", the same
  null-vs-empty-array collapse class on a different boundary.
related_bugs:
  - f7a2c9
writers:
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: "serve handler — geminiChat() call now destructures lastError", line: 549 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: "serve handler !aiContent branch — new reportGeminiExhaustion call", line: 573 }
  - { file: supabase/functions/ai-media-proxy/index.ts, method_or_widget: "handleRequest — geminiChat() call now destructures lastError", line: 922 }
  - { file: supabase/functions/ai-media-proxy/index.ts, method_or_widget: "handleRequest !rawReply branch — new reportGeminiExhaustion call", line: 941 }
  - { file: supabase/functions/assess-body-composition/index.ts, method_or_widget: "serve handler — geminiChat() call now destructures lastError", line: 159 }
  - { file: supabase/functions/assess-body-composition/index.ts, method_or_widget: "serve handler !rawText branch — new reportGeminiExhaustion call", line: 178 }
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "extractCoachingNotes — geminiChat() call now destructures lastError", line: 148 }
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "extractCoachingNotes !rawText branch — new reportGeminiExhaustion call", line: 167 }
  - { file: supabase/functions/rolling-context/index.ts, method_or_widget: "summarizeMessages — geminiChat() call now destructures lastError", line: 85 }
  - { file: supabase/functions/rolling-context/index.ts, method_or_widget: "summarizeMessages !content branch — new reportGeminiExhaustion call, own dedup source", line: 127 }
readers:
  - { file: supabase/functions/_shared/gemini_failure_alert.ts, method_or_widget: "reportGeminiExhaustion — inserts into public.alerts with 30-min dedup keyed on source", line: 32 }
hive_key_prefix: not_applicable
hive_key_formula: "not_applicable (no Hive key involved — server-side alerting only)"
sync_methods: []
restore_methods: []
cloud_table: public.alerts
cloud_columns: []
contract_test_path: |
  supabase/functions/weekly-report/index_test.ts
  supabase/functions/ai-media-proxy/index_test.ts
  supabase/functions/assess-body-composition/index_test.ts
  supabase/functions/daily-snapshot/index_test.ts
  supabase/functions/rolling-context/index_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - ai_proxy_gemini_exhausted
    - rolling_context_gemini_exhausted
cross_account_guard: >
  Not applicable — every new reportGeminiExhaustion call is per-request (or,
  for rolling-context, per-user within its own nightly loop) and stateless;
  no cross-account state is read or written.
forbidden_patterns_checked:
  - "A whole-file `.contains()` source-grep that can't tell 'the call exists
    somewhere' from 'the call fires in the right branch' — every new test
    is POSITION-SCOPED (bounded to the specific !content/!rawText/!aiContent
    branch's block) and comment-stripped before any `.includes()` check,
    exactly matching gemini_retry_coverage_lib.dart's stripComments()
    discipline and the sibling f7a2c9 fix's own documented trap (a
    commented-out, not deleted, call left a naive substring check falsely
    green)."
  - "Assumed a shared dedup source was automatically correct for every new
    call site without checking the fan-out shape of the caller. rolling-context
    is a CRON job that loops over every user with >50 messages in one nightly
    run; sharing ai-proxy's live-traffic dedup source would let a burst of
    per-user failures during one bad run suppress a genuine same-day
    live-traffic alert to severity 'warn' for the rest of that source's
    30-minute window. Given its own dedup source
    (rolling_context_gemini_exhausted) instead — verified by a dedicated test
    asserting the shared source string is ABSENT from its call, not just that
    its own source is present."
  - "ai-media-proxy's index_test.ts already exports/tests handleRequest, which
    made it tempting to assume a full behavioral test (stubbed fetch +
    fake Supabase client, mirroring tool-loop_gemini_exhaustion_alert_test.ts)
    was free there. Checked first: every existing handleRequest test in that
    file stops at the auth boundary, because auth is a REAL
    `createClient(...).auth.getUser(token)` call with no injectable seam —
    driving a request past it to reach the geminiChat branch is not reachable
    with the file's existing test infrastructure. Used the same source-grep
    approach as the other 4 sites instead of building a new, larger auth-mocking
    seam whose own correctness would need separate scrutiny."
proposed_fix: |
  Wired `reportGeminiExhaustion` into all 5 remaining Gemini-calling Edge
  Functions' total-exhaustion path, mirroring the pattern OI-226/f7a2c9
  established for ai-proxy:

  - `weekly-report/index.ts`: the report-generation `geminiChat()` call now
    destructures `lastError`; the pre-existing `!aiContent` branch (already
    returning a 502) now also calls `reportGeminiExhaustion` before
    returning.
  - `ai-media-proxy/index.ts`: same shape on `handleRequest`'s `!rawReply`
    branch.
  - `assess-body-composition/index.ts`: same shape on the `!rawText` branch.
  - `daily-snapshot/index.ts`: `extractCoachingNotes` (already takes a
    `supabase` client parameter) now also destructures `lastError` and calls
    `reportGeminiExhaustion` from its own `!rawText` branch, using that same
    parameter (not a module-level client — there isn't one at this scope).
  - `rolling-context/index.ts`: `summarizeMessages` previously received no
    Supabase client at all (its return value was just `string | null`). Added
    a `supabase: SupabaseClient` parameter, threaded through from the
    per-user loop's own `supabaseClient` at the call site, and wired
    `reportGeminiExhaustion` into its `!content` branch.

  Dedup-source design decision (per the OI's own fix-direction note that
  "the endpoint/dedup semantics may need adjustment"): the 4 LIVE,
  user-invoked call sites (weekly-report, ai-media-proxy,
  assess-body-composition, daily-snapshot) reuse the SAME
  `"ai_proxy_gemini_exhausted"` dedup source ai-proxy/tool-loop.ts already
  use — they share the identical GEMINI_API_KEY/quota with live chat
  traffic, and `reportGeminiExhaustion`'s own `classify()` advice ("check
  Gemini quota/billing") is a project-wide concern, not a per-function one; a
  real outage should page the founder ONCE across the whole app, not once per
  surface. `rolling-context` — the ONE cron-dispatched site among the 5,
  running nightly inside a per-user loop over every user with >50 stored
  messages — gets its OWN dedup source
  (`"rolling_context_gemini_exhausted"`), because a bad nightly run could
  fail dozens of users back-to-back in minutes; sharing the live-traffic
  source would let that burst suppress a genuine same-day ai-proxy alert to
  severity "warn" for the rest of the shared source's 30-minute dedup window
  while users are actively hitting errors during the day. Each of the 5 new
  call sites carries a distinct `endpoint` tag (`"weekly_report"`,
  `"ai_media_proxy"`, `"assess_body_composition"`,
  `"daily_snapshot_extraction"`, `"rolling_context_summarize"`) so alerts
  stay distinguishable in `summary`/`context_json` regardless of which
  source they share.

  `reportGeminiExhaustion` never throws by its own documented contract, so
  none of these 5 new call sites can introduce a new failure mode on the
  paths they instrument.

  Deliberately NOT shipped in this batch: a mechanical gate extending
  `check_gemini_retry_and_telemetry_coverage.dart` to cover server-side
  reportGeminiExhaustion wiring. OI-226's own closure already documented this
  as an explicit scope decision ("5 call sites judged too small a surface to
  warrant one") and this fix does not change that calculus — it is now 10
  server-side call sites across 6 functions, still small enough that a
  regression would be caught by the next Hermes/audit pass, and inventing a
  registry-based gate for this specific shape is a separable unit of
  engineering this OI's own filed text did not ask for.
regression_test_planned:
  - supabase/functions/weekly-report/index_test.ts
  - supabase/functions/ai-media-proxy/index_test.ts
  - supabase/functions/assess-body-composition/index_test.ts
  - supabase/functions/daily-snapshot/index_test.ts
  - supabase/functions/rolling-context/index_test.ts
impact_analysis: |
  Additive and observability-only: no user-facing behavior changes on
  success OR failure for any of the 5 functions — every existing error
  response (502 / null return) is byte-identical before and after this fix.
  The only new effect is that a terminal Gemini failure on any of these 5
  surfaces now ALSO fires a deduped alert into `public.alerts` (existing
  `trg_dispatch_critical_alert_notify` paging path, migration 133 — no new
  Telegram wiring). Platform blast radius: touches 5 Edge Functions spanning
  the weekly report, photo/video chat, PRO body-composition assessment, the
  per-mutation coaching-notes extraction, and the nightly rolling-context
  summarization cron — none of which share a request path with each other or
  with ai-proxy, so this fix cannot regress any of those functions' existing
  behavior on the happy path. Double-paging risk (same tradeoff the sibling
  f7a2c9 fix flagged for ai-proxy, now wider): a sufficiently broad Gemini
  outage could page the founder via BOTH the shared
  `ai_proxy_gemini_exhausted` source and the separate
  `rolling_context_gemini_exhausted` source in the same incident window —
  accepted as a stated, conscious tradeoff (that is exactly why
  rolling-context was deliberately NOT folded into the shared source; the
  alternative, sharing it, has the WORSE failure mode of masking live-traffic
  signal during the day) — unlikely to matter at current ~32-user scale.
  Edge Functions NOT redeployed by this batch — a live redeploy of all 5
  functions remains a separate, founder-authorized action not requested this
  session.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "No lib/ files touched — this fix is entirely server-side (supabase/functions/)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none clean on all 5 touched index.ts files. deno test --no-check --allow-all --node-modules-dir=none across all 5 functions' index_test.ts: 44/44 passed (3 weekly-report, 24 ai-media-proxy [21 pre-existing + 3 new], 3 assess-body-composition, 8 daily-snapshot [5 pre-existing + 3 new], 6 rolling-context). Each of the 5 new/extended wiring assertions mutation-proven live in this diagnose-doc's own verification pass — see mutation_proven below. NOT yet deployed — a live redeploy of all 5 functions remains a separate, founder-authorized action not requested this session." }
mutation_proven:
  mutated: >
    Five separate mutations, each run and reverted independently in this
    diagnose-doc's own verification pass: deleted the `reportGeminiExhaustion(...)`
    call block from each of the 5 new/extended call sites in turn —
    weekly-report's `!aiContent` branch, ai-media-proxy's `!rawReply` branch,
    assess-body-composition's `!rawText` branch, daily-snapshot's `!rawText`
    branch (inside `extractCoachingNotes`), and rolling-context's `!content`
    branch (inside `summarizeMessages`).
  result: >
    (1) weekly-report: deno test index_test.ts — 2 passed / 1 failed (the
    "reports Gemini exhaustion on the !aiContent branch" assertion; the
    import + lastError-destructure tests were unaffected). (2) ai-media-proxy:
    deno test index_test.ts (24 tests, the whole file) — 23 passed / 1 failed
    (exactly the new "!rawReply branch" assertion; all 21 pre-existing
    Storage-guard/quota tests stayed green). (3) assess-body-composition:
    2 passed / 1 failed (the "!rawText branch" assertion). (4) daily-snapshot:
    deno test index_test.ts (8 tests, the whole file) — 7 passed / 1 failed
    (exactly the new OI-238 branch assertion; the 5 pre-existing merge-safe
    tests stayed green). (5) rolling-context: deno test index_test.ts (6
    tests) — 5 passed / 1 failed (the "reports Gemini exhaustion on the
    !content branch" assertion; the supabase-parameter, call-site-wiring,
    lastError-destructure, and happy-path-return tests all stayed green).
    All five reverted; re-ran each affected file green (3/3, 24/24, 3/3,
    8/8, 6/6 respectively) and `deno check --node-modules-dir=none` clean on
    all 5 index.ts files after every revert.
  confirmed_applied: >
    Read each file's exact current text via grep/Read before mutating (not
    from memory), applied each mutation via Edit, ran the affected file's
    test suite, confirmed the exact expected assertion (and only that one)
    failed, then reverted via Edit and re-ran to confirm the original text
    was restored and the suite was fully green again. Post-revert sanity:
    `grep -n "reportGeminiExhaustion(" supabase/functions/{weekly-report,ai-media-proxy,assess-body-composition,daily-snapshot,rolling-context}/index.ts`
    shows exactly one call per file, at its original line, matching the
    writers table above.
---

## Summary

OI-238 named a wider sibling gap to OI-226: 5 other Gemini-calling Edge
Functions (`weekly-report`, `ai-media-proxy`, `assess-body-composition`,
`daily-snapshot`, `rolling-context`) had no `reportGeminiExhaustion` wiring
at all on their `geminiChat()` total-exhaustion path — none even
destructured `lastError` from `GeminiResult`. All 5 are fixed here, following
the pattern OI-226/f7a2c9 established, with one deliberate design deviation:
`rolling-context` (the sole cron-dispatched site among the 5) uses its own
dedup source rather than sharing the live-traffic one, to avoid a nightly
per-user failure burst suppressing a same-day live alert.

## Root cause

Each of these 5 functions predates the `gemini_failure_alert.ts` module
(`food-logging-observations` batch, 2026-09-20) and was never retrofitted —
that batch scoped itself to 3 `ai-proxy` nutrition endpoints, OI-226/f7a2c9
extended coverage to `ai-proxy`'s remaining 2 internal call sites, and this
OI explicitly tracked the remaining 5-function gap rather than
scope-creeping either of those batches.

## Fix

See `proposed_fix` above.

## Verification

- `deno check --node-modules-dir=none` clean on all 5 touched `index.ts`
  files.
- All 5 functions' `index_test.ts` green: 44/44 tests total (21 pre-existing
  ai-media-proxy + 5 pre-existing daily-snapshot tests unaffected; 18 new
  OI-238 tests added/extended).
- Mutation proof run live for all 5 new/extended wiring sites in this
  verification pass — see `mutation_proven` above for exact pass/fail counts
  at each site.
- Source-grep test rationale documented per site in
  `forbidden_patterns_checked` — every new test is position-scoped to the
  specific failure branch and comment-stripped before any substring check,
  matching the sibling f7a2c9 fix's own documented discipline.

## Files changed

- Modified: `supabase/functions/weekly-report/index.ts`
- Created: `supabase/functions/weekly-report/index_test.ts`
- Modified: `supabase/functions/ai-media-proxy/index.ts`
- Modified: `supabase/functions/ai-media-proxy/index_test.ts`
- Modified: `supabase/functions/assess-body-composition/index.ts`
- Created: `supabase/functions/assess-body-composition/index_test.ts`
- Modified: `supabase/functions/daily-snapshot/index.ts`
- Modified: `supabase/functions/daily-snapshot/index_test.ts`
- Modified: `supabase/functions/rolling-context/index.ts`
- Created: `supabase/functions/rolling-context/index_test.ts`
- Modified: `supabase/functions/CLAUDE.md` (gemini_failure_alert row — OI-238 closed)
- Modified: `docs/audit/open_issues.md` (OI-238 removed, moved to closed)
- Modified: `docs/audit/closed_issues.md` (OI-238 closed entry added)
- Created: this diagnose-doc.
