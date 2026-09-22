---
bug_id: f7a2c9
date: 2026-09-21
batch: observation-batch-and-digest-redesign (A5)
status: fixed
blast_radius: platform
symptom: |
  OI-226 (open_issues.md:5059): "ai-proxy chat/tool-calling Gemini exhaustion
  paths have no reportGeminiExhaustion alert wiring." The OI's own text names
  TWO distinct gaps on the server — re-verified against the live source
  before this doc was written, not assumed from the OI's prose alone: (a) the
  `prediction` handler's own direct geminiChat() call (ai-proxy/index.ts,
  originally cited as index.ts:692 in the OI, drifted to :722 by this same
  batch's own A2b retries:2 insertions above it — re-verified by grep, not by
  the OI's stale citation) destructured `{content, modelUsed, tokensUsed}`
  with NO `lastError`, so it could not call reportGeminiExhaustion at all; (b)
  the coach's tool-calling path (runToolLoop's hard-failure catch in
  tool-loop.ts) never called it either. Both were still open at the start of
  this fix — an earlier pass had fixed only (b) and nearly closed this OI
  while (a) remained live; caught by re-reading the OI's own full text
  against a fresh grep before writing this doc's closure claim.

  Separately, an exhaustive human+subagent sweep of every AI/network catch
  block under lib/features/ai_coach/ and lib/features/nutrition/ (108 catch
  blocks reviewed) found 2 real, live CLIENT gaps with ZERO telemetry: (1)
  SendMessageNotifier.sendWithMedia's catch only logged on its generic
  fallback branch — the other 6 user-facing error branches (no-internet,
  image-too-large, storage-upload-incomplete, message-too-long, PRO-required,
  Gemini-502/503/504) showed a distinct chat bubble with no ErrorTelemetry
  call at all; (2) CartAuditorNotifier.analyseCart had NO telemetry on either
  failure path (a non-200/null-data ai-proxy response, or a thrown exception)
  — its structural sibling ScanMealNotifier.scanImage had already been fixed
  for the thrown-exception case, but analyseCart never was. Both confirmed
  live via client_errors returning ZERO rows for a fully-reproduced incident
  window.
concept: ai_failure_telemetry_coverage
sot_registry_entry: >
  not_applicable — this is client-side error-observability (ErrorTelemetry)
  and server-side incident-alerting (reportGeminiExhaustion → public.alerts),
  not a Hive/cloud writer/reader SoT concept. Same framing as the sibling A2b
  fix (f7a2c9, nutrition_ai_gemini_resilience) and its own precedent d4f1c2 —
  neither is in docs/sot_registry.yaml. The pre-existing 3-nutrition-endpoint
  wiring is documented as a prose table row (not a docs/sot_registry.yaml
  entry) in supabase/functions/CLAUDE.md under "gemini_failure_alert",
  updated by this fix to remove its own "tracked as OI-226" pointer now that
  the gap it named is closed.
recurrence: >
  Sibling of this same batch's A2b fix (bug_id f7a2c9 is intentionally reused
  across both diagnose-docs — evidenced by, and kept consistent with, the
  source comments already written at every A5 call site before this doc was
  drafted; see docs/diagnoses/2026-09-21-nutrition-ai-missing-backoff-retry-f7a2c9.md
  for the sibling fix). A2b fixed the RETRY side of Gemini-call resilience
  (9 geminiChat() sites had no backoff); this fixes the OBSERVABILITY side —
  what happens when a call still fails after every retry/pass is exhausted.
  Also an instance of feedback_observability_silent_drop.md (a failure path
  with no distinguishable signal reads as "working" until an incident makes
  it obvious) and feedback_bad_news_vs_no_news.md (a silently-absent
  ErrorTelemetry call collapses "real failure" into "no signal", identical to
  a null-vs-empty-array collapse on an external boundary).
related_bugs: []
writers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "SendMessageNotifier.sendWithMedia catch — unconditional log before branch chain", line: 748 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "CartAuditorNotifier.analyseCart non-200 branch", line: 1533 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "CartAuditorNotifier.analyseCart catch block", line: 1542 }
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "geminiChatWithTools total-exhaustion throw — now attaches {status, geminiMessage}", line: 552 }
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "CallOnceResult failure union — new status field", line: 591 }
  - { file: supabase/functions/_shared/tool-loop.ts, method_or_widget: "runToolLoop hard-failure catch — new reportGeminiExhaustion call", line: 300 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "prediction handler — geminiChat() now destructures lastError", line: 722 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "prediction handler !content branch — new reportGeminiExhaustion call", line: 738 }
readers:
  - { file: lib/core/services/error_telemetry.dart, method_or_widget: "recordNonFatal (client_errors sink)", line: 231 }
  - { file: lib/core/services/error_telemetry.dart, method_or_widget: "logEvent (client_errors sink)", line: 328 }
  - { file: supabase/functions/_shared/gemini_failure_alert.ts, method_or_widget: "reportGeminiExhaustion — inserts into public.alerts with 30-min dedup keyed on source", line: 32 }
hive_key_prefix: not_applicable
hive_key_formula: "not_applicable (no Hive key involved — client telemetry + server alerting only)"
sync_methods: []
restore_methods: []
cloud_table: public.alerts
cloud_columns: []
contract_test_path: |
  test/contracts/ai_media_proxy_telemetry_test.dart
  test/contracts/ai_breakdown_notifier_cart_auditor_telemetry_test.dart
  supabase/functions/_shared/tool-loop_gemini_exhaustion_alert_test.ts
  supabase/functions/_shared/gemini_backoff_retry_test.ts
  test/scripts/gemini_retry_coverage_lib_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - ai_coach_send_with_media_failed
    - cart_auditor_notifier_non_200_response
    - cart_auditor_notifier_analyse_cart
    - ai_proxy_gemini_exhausted
cross_account_guard: >
  Not applicable — every new telemetry/alert call is per-request and
  stateless; no cross-account state is read or written.
forbidden_patterns_checked:
  - "A whole-file `.contains()` source-grep that can't tell 'the call exists somewhere' from 'the call fires unconditionally at the right point' — used bounded, position-scoped indexOf comparisons (telemetryCall < firstBranch / < errorState) instead, mirroring ai_media_proxy_telemetry_test.dart's own established convention."
  - "Discovered live while mutation-proving THIS diagnose-doc's own regression test: commenting out (rather than deleting) the ai_coach_send_with_media_failed call left the exact searched substring intact inside the comment text, so the position-scoped source-grep test stayed GREEN against neutered code — the literal feedback_green_check_input_set_width class, caught only because the mutation was actually run and re-checked rather than assumed. Corrected by deleting the call text outright for the mutation; reverted afterward. Documented here so a future mutation-proof on a source-grep test doesn't repeat it: comment-based neutering does not remove a substring match."
  - "A gate design that assumes 'the first catch after a method's opening anchor is the one that matters' — false against both send() (telemetry is its 2nd of 3 catches) and analyse() (2nd of 2, after a deliberately-silent inner catch) — see docs/audit/gate_test_ledger.yaml's check_gemini_retry_and_telemetry_coverage.dart entry for the full account."
proposed_fix: |
  Client (2 real gaps, both confirmed live and fixed): added an unconditional
  ErrorTelemetry.logEvent call at the top of sendWithMedia's catch (mirrors
  the sibling send() method's own pre-existing unconditional-log-at-top
  pattern, so every branch below it — not just the generic fallback — now
  leaves a client_errors breadcrumb); added ErrorTelemetry.logEvent to
  CartAuditorNotifier.analyseCart's non-200 branch and
  ErrorTelemetry.recordNonFatal to its catch block, mirroring the equivalent
  fix already shipped on its structural sibling ScanMealNotifier.scanImage's
  catch block (scanImage's own non-200 branch fix, round-2 plan review
  2026-09-20, had NO regression test at all until this batch — backfilled
  as part of building this fix's own test file, closing a real,
  previously-untested gap in already-shipped code).

  Server (OI-226 itself, BOTH of its named gaps): geminiChatWithTools's
  total-exhaustion throw in gemini.ts now attaches structured {status,
  geminiMessage} onto the thrown Error via Object.assign (previously a
  hand-composed .message string only, with no field reportGeminiExhaustion's
  {status, message} shape could consume without re-parsing prose) — confirmed
  no other caller of geminiChatWithTools depends on the exact shape of the
  thrown Error's .message string before making this change (grepped all call
  sites: the only production consumer of the thrown error's shape is
  tool-loop.ts's own catch, added in this same fix). tool-loop.ts's
  hard-failure catch now calls reportGeminiExhaustion with
  source="ai_proxy_gemini_exhausted" (the SAME dedup source as the 3
  nutrition endpoints, so a 30-minute window spans chat + nutrition together)
  and endpoint="chat" (keeps it distinguishable in the alert
  summary/context_json).

  Separately — and initially missed by an earlier pass over this same fix,
  caught only by re-reading OI-226's own filed text in full rather than
  trusting a partial recollection of it — the `prediction` handler in
  ai-proxy/index.ts is a direct, single-shot geminiChat() call that never
  goes through runToolLoop at all, and its destructure omitted `lastError`
  entirely (`{content, modelUsed, tokensUsed}`, no error field), so it
  structurally could not call reportGeminiExhaustion regardless of the
  tool-loop.ts fix above. Added `lastError` to the destructure and a
  reportGeminiExhaustion call (same source, endpoint="prediction") inside the
  existing `if (!content)` branch, mirroring the 3 nutrition sites' own
  established pattern exactly.

  reportGeminiExhaustion never throws by its own documented contract, so none
  of the 5 total call sites (3 pre-existing + this fix's 2 new ones — chat via
  tool-loop.ts, prediction via ai-proxy/index.ts) can introduce a new failure
  mode in the failure paths they instrument.

  Mechanical gate: scripts/check_gemini_retry_and_telemetry_coverage.dart
  (part b) now hard-fails pre-commit if any of the 5 registered AI/network
  entry points ever loses its telemetry again — see the gate's own ledger
  entry for its design history and mutation proof.

  Deliberately NOT folded into this diff: an exhaustive sweep also found 6
  untelemetered business-validation exceptions in tool_dispatcher.dart. These
  are a genuinely different bug class (validation-rejection paths, not
  AI/network-call failure paths) and were flagged as a separate follow-up
  session (spawn_task task_f581ec43) rather than bundled here — bundling
  would have buried OI-226's actual scope (Gemini-exhaustion alerting) inside
  an unrelated dispatcher-validation cleanup.
regression_test_planned:
  - test/contracts/ai_media_proxy_telemetry_test.dart
  - test/contracts/ai_breakdown_notifier_cart_auditor_telemetry_test.dart
  - supabase/functions/_shared/tool-loop_gemini_exhaustion_alert_test.ts
  - supabase/functions/_shared/gemini_backoff_retry_test.ts
  - scripts/check_gemini_retry_and_telemetry_coverage.dart
  - test/scripts/gemini_retry_coverage_lib_test.dart
impact_analysis: |
  Additive and observability-only on every path: no user-facing behavior
  changes on success OR failure — the chat bubble / error state the user sees
  is byte-identical before and after this fix. The only new effect is that a
  terminal failure now ALSO writes a breadcrumb (client_errors) or fires a
  deduped alert (public.alerts, 30-min window, existing
  trg_dispatch_critical_alert_notify paging path — no new Telegram wiring).
  Platform blast radius: touches the coach's primary chat entry point
  (sendWithMedia) and the cart-auditor nutrition AI, plus the shared
  gemini.ts/tool-loop.ts helpers every coach chat message and tool call
  passes through. Reviewed for double-paging risk: a sufficiently broad
  Gemini outage could now cross BOTH client_errors' alert_client_errors_spike
  threshold AND gemini_failure_alert's own 30-min dedup, paging the founder
  twice under two unrelated-looking source labels with no cross-reference —
  flagged as a stated, conscious tradeoff (spec's own review round 2 note),
  not a defect; unlikely at current ~32-user scale and addressed by Part B4
  of this same batch's founder-digest work.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze clean on both touched files. flutter test test/contracts/ai_media_proxy_telemetry_test.dart (4/4) + test/contracts/ai_breakdown_notifier_cart_auditor_telemetry_test.dart (3/3) green. Mutation-proven live in this diagnose-doc's own verification pass (see mutation_proven below), not merely asserted." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none clean on gemini.ts, tool-loop.ts and ai-proxy/index.ts. deno test --allow-env --allow-read --node-modules-dir=none on tool-loop_gemini_exhaustion_alert_test.ts (2/2) and the extended gemini_backoff_retry_test.ts (17/17, including the new prediction-handler OI-226 pin). Mutation-proven live for both new sites (see below). NOT yet deployed — this requires a live redeploy of ai-proxy, gemini.ts and tool-loop.ts that remains a separate, founder-authorized action not requested this session." }
mutation_proven:
  mutated: >
    Four separate mutations, each run and reverted independently in this
    diagnose-doc's own verification pass (not carried over from an earlier,
    unverified claim): (1) client — first attempted by commenting out the
    sendWithMedia ErrorTelemetry.logEvent call, which left the searched
    substring intact inside the comment and stayed falsely GREEN (see
    forbidden_patterns_checked); corrected by deleting the call text outright.
    (2) client — deleted CartAuditorNotifier's catch-block
    ErrorTelemetry.recordNonFatal call, then separately deleted its non-200
    branch ErrorTelemetry.logEvent call (two independent runs). (3) server,
    tool-calling half of OI-226 — deleted the reportGeminiExhaustion call
    block from tool-loop.ts's hard-failure catch. (4) server, prediction half
    of OI-226 — deleted the reportGeminiExhaustion call from ai-proxy's
    prediction handler's !content branch (destructure of lastError left in
    place for this run).
  result: >
    (1) flutter test test/contracts/ai_media_proxy_telemetry_test.dart:
    3 passed / 1 failed — the exact new "logged BEFORE any branch check"
    assertion (Expected: true, Actual: false); the 3 pre-existing tests in
    the file were unaffected. (2a) flutter test
    test/contracts/ai_breakdown_notifier_cart_auditor_telemetry_test.dart:
    2 passed / 1 failed — the fault-injection test's capturedReason assertion
    (Expected: 'cart_auditor_notifier_analyse_cart', Actual: null); the 2
    source-pin tests (including scanImage's sibling pin) were unaffected.
    (2b) same file, non-200 mutation: 2 passed / 1 failed — the non-200
    branch's own position assertion (Expected: true, Actual: false); the
    fault-injection test and scanImage's sibling pin were both unaffected.
    (3) deno test tool-loop_gemini_exhaustion_alert_test.ts: 1 passed /
    1 failed — the total-exhaustion test's `assertEquals(client.inserted.length, 1)`
    (Actual: 0); the happy-path mirror test stayed green in both the
    pre-mutation and post-mutation runs, confirming it alone would NOT have
    caught this regression — the total-exhaustion test is the one doing the
    protective work. (4) deno test gemini_backoff_retry_test.ts (17 tests,
    the whole shared-Gemini-helper file): 16 passed / 1 failed — exactly the
    new "reportGeminiExhaustion wired on !content (OI-226)" test (Expected
    truthy, got the report-call-missing assertion failure); all 4 retry-pin
    tests for the other Edge Functions, and the prediction handler's own
    retries:2 pin, were unaffected. All four sites reverted; re-ran each
    affected file green (4/4, 3/3, 2/2, 17/17 respectively); deno check clean
    on gemini.ts, tool-loop.ts and ai-proxy/index.ts after all reverts.
  confirmed_applied: >
    Read each file's exact current text via grep before mutating (not from
    memory/summary — line numbers were re-verified live against the working
    tree before this doc was written, and re-verified AGAIN after discovering
    mid-verification that OI-226 named a second, still-open gap the doc had
    not yet covered), applied the mutation via Edit, ran the affected test
    file, then reverted via Edit and re-ran to confirm the exact original
    text was restored and the suite was fully green again. grep -c sanity
    checks after all reverts: reportGeminiExhaustion appears exactly 3× in
    tool-loop.ts (import + doc comment + call, no duplication); exactly 4× in
    ai-proxy/index.ts (3 pre-existing + this fix's 1 new call); exactly 1× as
    ai_coach_send_with_media_failed in ai_coach_provider.dart.
---

## Summary

OI-226 named TWO server-side gaps: the coach's chat/tool-calling path
(`runToolLoop`) and the `prediction` handler's own direct `geminiChat()`
call, neither of which had `reportGeminiExhaustion` alert wiring, even though
the 3 nutrition endpoints already had it. Both are fixed here — the second
was found still open partway through this fix's own verification pass, by
re-reading OI-226's filed text in full rather than trusting a partial
recollection of it. An exhaustive sweep of every AI/network catch block in
the app also found 2 real, live client-side telemetry gaps — one on the
coach's own photo/media chat path, one on the cart-auditor nutrition AI —
both confirmed via `client_errors` returning zero rows for a fully-reproduced
incident window.

## Root cause

Client: `sendWithMedia`'s catch block only called `ErrorTelemetry` on its
generic fallback branch; the other 6 user-visible error branches were added
over time without the same unconditional top-of-catch logging its sibling
`send()` method already has. `CartAuditorNotifier.analyseCart` never got
either telemetry call its structural sibling `ScanMealNotifier.scanImage`
has — an incomplete rollout of that same fix, not a design gap.

Server: `reportGeminiExhaustion` was wired into the 3 nutrition `ai-proxy`
endpoints (food-logging-observations batch, 2026-09-20) but that batch's plan
was explicitly scoped to those 3 sites only. Two call sites were left behind
and tracked as OI-226 rather than silently left absent: `runToolLoop`'s
hard-failure catch (required an additive change to `geminiChatWithTools`'s
thrown Error, attaching `{status, geminiMessage}`, since the pre-existing
thrown Error carried no structured field `reportGeminiExhaustion` could
consume) and the `prediction` handler's own single-shot `geminiChat()` call,
which never even destructured `lastError` from its response.

## Fix

See `proposed_fix` above. Also shipped: a mechanical gate
(`scripts/check_gemini_retry_and_telemetry_coverage.dart`) so neither class of
gap (missing `geminiChat` retries, missing AI-entry-point telemetry) can
silently regress — see its own `docs/audit/gate_test_ledger.yaml` entry for
its design history (two false-positive designs found and fixed before
shipping) and mutation proof.

## Verification

- `flutter analyze` clean on both touched Dart files.
- `deno check --node-modules-dir=none` clean on all three touched Deno files
  (gemini.ts, tool-loop.ts, ai-proxy/index.ts).
- All 5 regression test files green (client ×2, Deno ×2, gate lib ×1 — 19
  tests in the gate lib file after the A2d comment-stripping correction
  below (was 17), 17 in the extended gemini_backoff_retry file).
- Mutation proof run live for all 4 real fix sites in this verification pass
  (not inherited from an earlier unverified claim) — see `mutation_proven`
  above for exact pass/fail counts at each site.
- One process finding surfaced BY the mutation-proof step itself: a
  comment-based neuter of the `sendWithMedia` call left its searched
  substring intact inside the comment, so the position-scoped test stayed
  green against effectively-neutered code until the mutation was corrected to
  actually delete the text. Recorded under `forbidden_patterns_checked` so a
  future mutation-proof on a source-grep-style test doesn't repeat it.
- A2d addendum (self-triggered B-pass review on this batch's full staged
  diff, same day, before merge): the exact same comment-blindness class
  found above in a test's mutation was ALSO present in the GATE this fix
  shipped — `check_gemini_retry_and_telemetry_coverage.dart`'s two
  `.contains()` checks ran against raw, comment-inclusive extracted text.
  Fixed with a `stripComments()` helper applied to the extracted
  block/catch-body only; 2 new regression tests added; mutation-proof
  (reverting to the raw checks) reddened exactly those 2, nothing else.
  Full evidence: `docs/audit/gate_test_ledger.yaml`'s
  `check_gemini_retry_and_telemetry_coverage.dart` entry.

## Files changed

- Modified: `lib/features/ai_coach/providers/ai_coach_provider.dart`
- Modified: `lib/features/nutrition/providers/nutrition_provider.dart`
- Modified: `test/contracts/ai_media_proxy_telemetry_test.dart`
- Created: `test/contracts/ai_breakdown_notifier_cart_auditor_telemetry_test.dart`
- Modified: `supabase/functions/_shared/gemini.ts`
- Modified: `supabase/functions/_shared/tool-loop.ts`
- Modified: `supabase/functions/ai-proxy/index.ts` (prediction handler — the
  OTHER half of OI-226)
- Modified: `supabase/functions/_shared/gemini_backoff_retry_test.ts` (new
  OI-226 pin + `assert` import)
- Modified: `scripts/gemini_retry_coverage_lib.dart` (A2d — `stripComments()`
  correction)
- Modified: `test/scripts/gemini_retry_coverage_lib_test.dart` (A2d — 2 new
  comment-defeat regression tests)
- Modified: `docs/audit/gate_test_ledger.yaml` (A2d evidence addendum)
- Created: `supabase/functions/_shared/tool-loop_gemini_exhaustion_alert_test.ts`
- Created: `scripts/gemini_retry_coverage_lib.dart`
- Created: `scripts/check_gemini_retry_and_telemetry_coverage.dart`
- Created: `test/scripts/gemini_retry_coverage_lib_test.dart`
- Updated: `docs/audit/gate_test_ledger.yaml` (new gate's mutation-proof entry)
- Updated: `supabase/functions/CLAUDE.md` (gemini_failure_alert row — OI-226 closed)
- Created: this diagnose-doc.
