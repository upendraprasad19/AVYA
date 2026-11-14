---
bug_id: c9e2a5
date: 2026-09-21
batch: observation-batch-and-digest-redesign (A2a)
status: fixed
blast_radius: platform
symptom: |
  Founder observation #2: AI Coach chat rendered a raw JSON-shaped Gemini
  reply (e.g. `{"summary": "..."}`) instead of natural language. A SECOND,
  related symptom in the same report — after force-closing and reopening the
  app, the SAME raw-shaped text kept reappearing on relaunch — turned out to
  be a distinct gap in the RESTORE path, not just the live-send path.
  AMENDMENT (2026-09-21, same-batch self-triggered Hermes pass, lens L1):
  the fix below introduced its OWN false positive — a plain-prose chat reply
  shaped like a macro breakdown ("Protein: 45g\nCarbs: 30g\n...") matches the
  same key:value heuristic step 2 uses to catch a YAML-style Gemini reply for
  the prediction card, and got wrongly stripped down to a fragment in chat.
  See the amendment section below.
concept: coach_chat_reply_sanitization
sot_registry_entry: not_applicable
writers:
  - { file: supabase/functions/_shared/tool-loop.ts, method_or_widget: "runToolLoop (finalText = resp.text)", line: 306 }
readers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: detectAndStripJsonShapedReply, line: 1185 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "SendMessageNotifier.sendWithMedia", line: 698 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "SendMessageNotifier.send (primary)", line: 948 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "SendMessageNotifier.send (auth-retry)", line: 1025 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "ChatHistoryNotifier.build (success render)", line: 317 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "ChatHistoryNotifier.build (isFailed fallback render)", line: 285 }
hive_key_prefix: coach_
hive_key_formula: "coach_<ms> (unrelated to this fix — the Hive-PERSISTED ai_response value is left untouched; only the RENDERED bubble text is cleaned)"
sync_methods: []
restore_methods: [_restoreCoachInteractions]
cloud_table: ai_coach_interactions
cloud_columns: [ai_response]
contract_test_path: test/contracts/coach_chat_reply_sanitization_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [ai-proxy console.warn "JSON-shaped chat reply detected" (informational, no client-facing effect)]
cross_account_guard: Not applicable — no cross-user data path touched.
forbidden_patterns_checked:
  - "reusing PredictionNotifier._sanitisePredictionText directly for chat (it writes back to the global prediction_text Hive key — a data-corruption hazard for the unrelated Profile-tab prediction card)"
proposed_fix: |
  Extract a PURE detectAndStripJsonShapedReply(String? raw) -> String? from
  PredictionNotifier._sanitisePredictionText, stripped of its
  _writeBackToHive side effect. PredictionNotifier keeps a thin wrapper
  (pure-fn call + write-back only when the result differs from the input,
  preserving the exact original write-back semantics). Wire the pure
  function into SIX render sites: SendMessageNotifier.sendWithMedia,
  .send's primary success AND its auth-retry success (both call sites carry
  identical risk — an unfixed retry path would reintroduce the bug on that
  path alone), and ChatHistoryNotifier.build()'s two AI-bubble render
  branches (success, and the isFailed->aiResponse fallback) — the latter is
  what the RESTORE half of the founder's report actually needed; a
  live-send-only fix would have kept reproducing on every relaunch.
  Server-side belt-and-braces: extractLogActions (ai-proxy/index.ts) gets a
  cheap heuristic (starts with { or [, parses as JSON) that logs a
  console.warn so a recurrence is visible in function logs without waiting
  for a user report.
regression_test_planned:
  - test/contracts/coach_chat_reply_sanitization_test.dart
impact_analysis: |
  Additive extraction: the original `_sanitisePredictionText` logic is
  preserved byte-for-byte inside the new pure function (verified by the
  pre-existing test/ai_coach/prediction_sanitiser_test.dart — all 9 cases
  still pass unmodified). Six new call sites each wrap an existing render
  with `detectAndStripJsonShapedReply(x) ?? x` — a pure, side-effect-free
  transform with a safe null-coalescing fallback to the original value, so a
  crash-free plain-prose reply is byte-identical to before. The Hive-
  persisted ai_response value is NEVER modified by any of the 6 chat-path
  sites (only PredictionNotifier's own wrapper still writes back, unchanged,
  to its own unrelated key) — confirmed by a source-grep negative assertion
  that SendMessageNotifier never calls _writeBackToHive.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/features/ai_coach/ — 5 pre-existing infos, 0 new issues. flutter test test/contracts/coach_chat_reply_sanitization_test.dart — 14/14 passed. flutter test test/ai_coach/prediction_sanitiser_test.dart — 9/9 passed (no regression to the extracted-from method)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none supabase/functions/ai-proxy/index.ts passes with 0 errors. NOT yet deployed — the live ai-proxy deploy remains a separate, founder-authorized action not requested this session." }
mutation_proven:
  mutated: "Reverted ChatHistoryNotifier.build()'s success-branch render from `detectAndStripJsonShapedReply(aiResponse) ?? aiResponse` back to raw `aiResponse`, confirmed applied by reading the file."
  result: "Ran flutter test test/contracts/coach_chat_reply_sanitization_test.dart: RED — 2 of 14 failed: the behavioral restore-path test (asserted raw JSON text instead of cleaned prose) AND the position-scoped source-grep test for build() (found 1 call site instead of the expected 2). A first version of the source-grep test used a whole-file occurrence COUNT (>=5) instead of per-site checks and stayed GREEN through this exact mutation — the total still included the function's own definition, the unrelated _sanitisePredictionText wrapper's call, and the untouched isFailed-fallback call in the same method, papering over the one removed. Rewrote it to slice the source between named method anchors and count per-method, which correctly reddened. Reverted the mutation; re-ran: GREEN, 14/14 passed."
  confirmed_applied: "Read the file (Edit tool's own before/after) to confirm the code matched the intended mutation both times."
mutation_proven_amendment:
  mutated: "Reverted the `send()` primary call site's `allowYamlHeuristic: false` argument (removed it, falling back to the default `true`), confirmed by reading the file."
  result: "Ran flutter test test/contracts/coach_chat_reply_sanitization_test.dart: RED — exactly 1 of 22 failed, the new per-call-site source-pin test for that container, with the exact expected diagnostic message. Re-added the argument; re-ran: GREEN, 22/22 passed. A first attempt at writing this test used a wide `source.substring(0, classEnd)` range that also swept in the function's own (later, forward-referenced) declaration, over-counting by 1 — rewritten as 3 narrowly-scoped per-container counts of the `allowYamlHeuristic: false` string (which cannot appear inside the function's own declaration), matching this file's own pre-existing per-site-pin idiom rather than a blind whole-file total."
  confirmed_applied: "Read the file (Edit tool's own before/after) to confirm the code matched the intended mutation both times."
---

## Summary

AI Coach chat rendered a raw, JSON-shaped Gemini reply instead of natural
language — both immediately after sending, and again on every subsequent app
launch (the restore path re-rendering the same unclean value from Hive).

## Root cause

`ChatHistoryNotifier.build()` and every success branch of `SendMessageNotifier`
rendered `aiResponse.reply` / a restored `ai_response` value directly, with no
guard. A near-identical detection/cleanup heuristic already existed
(`PredictionNotifier._sanitisePredictionText`) but was scoped to the
Profile-tab prediction card and impure — every branch also wrote the cleaned
value back to a single global `prediction_text` Hive key, making direct reuse
for chat a data-corruption hazard rather than a fix.

## Fix

Extracted the detection/cleanup logic into a pure, Hive-free
`detectAndStripJsonShapedReply`. `PredictionNotifier` keeps its own thin
wrapper (pure call + conditional write-back, byte-identical behavior to
before). Wired the pure function into all 6 places a Gemini/restored reply
becomes chat-bubble text: `sendWithMedia`, `send`'s primary AND auth-retry
paths, and `ChatHistoryNotifier.build()`'s success and isFailed-fallback
branches — the last two are the restore path and are what the founder's
"reopen the app" symptom actually needed fixed. Added a cheap server-side
heuristic (`extractLogActions`) that logs a warning when this shape recurs.

## Verification

- New unit tests on the pure function (JSON object, nested `predictions[]`,
  malformed-JSON artefact-stripping fallback, YAML-style key:value, plain
  prose passthrough by identity, null/empty).
- New behavioral tests seed `coachBox` with a JSON-shaped `ai_response` and
  read the real `chatHistoryProvider` via a `ProviderContainer` — proving the
  RESTORE path specifically renders cleaned text, not just the live-send path.
- New source-grep tests pin every one of the 6 sites individually (not a
  whole-file count — see the mutation-proof note above for why a raw count
  is the wrong shape here) and assert `SendMessageNotifier` never touches
  `prediction_text`/`_writeBackToHive`.
- Mutation proof: reverted one of the 6 sites — both the behavioral test and
  (after fixing the count-based test's blind spot) the source-grep test
  caught it; reverted, 14/14 green again.
- Re-ran the pre-existing `prediction_sanitiser_test.dart` (9/9 passed) to
  confirm the extraction didn't change `PredictionNotifier`'s behavior.
- `deno check --node-modules-dir=none` on `ai-proxy/index.ts` — 0 errors.

## Files changed

- Modified: `lib/features/ai_coach/providers/ai_coach_provider.dart`
- Modified: `supabase/functions/ai-proxy/index.ts`
- Created: `test/contracts/coach_chat_reply_sanitization_test.dart`
- Created: this diagnose-doc.

## Amendment (2026-09-21) — Hermes pass lens L1: the fix's own false positive

### Root cause

`detectAndStripJsonShapedReply`'s step 2 (YAML-style `key: value` detection)
was written for the Profile-tab prediction card, where a Gemini reply really
is a flat `key: value` block. Wiring the SAME function unconditionally into
chat (the fix above) meant a plain-prose chat reply shaped like a macro
breakdown — `Protein: 45g\nCarbs: 30g\nFat: 20g` — also matches the
`^[a-z_][a-z_0-9]*\s*:` pattern per line and got stripped down to a
fragment, mangling a completely legitimate answer. The heuristic that fixes
one Gemini output shape broke another.

### Fix

Added an `allowYamlHeuristic` parameter (default `true`, preserving the
prediction card's existing behavior byte-for-byte). All 5 chat-path call
sites (`sendWithMedia`; `send`'s primary and auth-retry success renders;
`ChatHistoryNotifier.build`'s success and isFailed-fallback renders) now pass
`allowYamlHeuristic: false` explicitly, so chat only ever strips step 1
(JSON object / code-fence) and never touches step 2. `PredictionNotifier
._sanitisePredictionText`'s own call site is unchanged (bare call, default
`true`) — its 9 pre-existing tests keep passing unmodified.

### Verification

- `test/contracts/coach_chat_reply_sanitization_test.dart` extended to 22
  tests: a new "allowYamlHeuristic: false (chat mode)" group (4 tests,
  including the exact macro-breakdown reproduction case and a
  default-preserves-old-behavior confirmation) plus 4 new per-container
  source-pin tests (one per call-site container, plus a negative check that
  the prediction card's own call site does NOT pass `allowYamlHeuristic` at
  all).
- Mutation proof: see `mutation_proven_amendment` above.
- `flutter analyze lib/features/ai_coach/providers/ai_coach_provider.dart`:
  clean, no issues (file has no `part`/`part of` directives, so a per-file
  analyze is reliable here).
