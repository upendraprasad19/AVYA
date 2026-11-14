---
bug_id: 125b81
date: 2026-09-26
batch: single-owner-a1 (single-owner remediation, audit docs/audit/2026-09-26-single-owner-audit-pass2.md P0 #5)
status: fixed
blast_radius: platform
symptom: |
  ai-proxy's `type: "prediction"` branch (`ai-proxy/index.ts:700-757` before
  this fix) had three defects, each verified by reading the code on
  2026-09-26:
    1. Unmetered. No quota, no tier check. Every call was a Gemini Flash call,
       so any signed-in user could loop it without limit — the one ai-proxy
       path with no cap at all.
    2. Unbounded input. The branch ran BEFORE the chat branch's length checks
       (`message` ≤5000, `snapshot_json` ≤10000 at `:757-762`) and repeated
       none of them, so an arbitrarily long `message` went straight into the
       prompt (CLAUDE.md §4.4 rule 18).
    3. Caller-controlled SYSTEM prompt. It used
       `context.system_prompt` from the request body when present
       (`:716-720`), so a caller could replace the endpoint's system prompt
       wholesale. The in-code comment recorded that a derived gate had flagged
       this and left the "should it be settable at all" question open.
  Both legitimate callers (`prediction_service.dart:52-55`,
  `onboarding_provider.dart:797-800`) send the server's own default text, so
  the field has never had a legitimate use.
concept: usage_quota_ledger (new key prediction_daily) + ai_proxy_input_limits
sot_registry_entry: usage_quota_ledger
writers:
  - { file: supabase/functions/_shared/prediction_handler.ts, method_or_widget: "consumePredictionQuota — the ONE consume_quota call for predictions (key prediction_daily, IST-day window, cap 3)", line: 68 }
  - { file: supabase/functions/_shared/ai_proxy_input_limits.ts, method_or_widget: "validateAiProxyInput — the ONE owner of message/text/snapshot size limits", line: 37 }
readers:
  - { file: supabase/functions/_shared/prediction_handler.ts, method_or_widget: "handlePrediction — consume before Gemini; -1 → 429, ledger error → 500 (fail closed), Gemini empty → report + 500; DISABLE_PREDICTION_QUOTA skips the consume only", line: 95 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "serve handler — validateAiProxyInput(body) before the first type branch; prediction branch delegates to handlePrediction", line: 294 }
  - { file: lib/core/services/ai_service.dart, method_or_widget: "AiService.predict — now sends only {message, type}", line: 388 }
  - { file: lib/core/services/prediction_service.dart, method_or_widget: "PredictionAttemptGate — writes/reads Hive prediction_auto_attempt_day (one automatic attempt per IST day; Hermes)", line: 31 }
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: "unmeteredQuotaKeys / buildDigestText — prediction_daily reads UNMETERED while DISABLE_PREDICTION_QUOTA is on (Hermes)", line: 242 }
  - { file: lib/core/services/prediction_service.dart, method_or_widget: "PredictionService.safeToWriteForTest + _regenerate's ownerAtStart guard — refuses to write if the signed-in account changed mid-flight (B-pass round 2)", line: 166 }
  - { file: lib/core/services/ai_service.dart, method_or_widget: "AiService._sanitizedLength — _compactContext's size() budget matches the server's post-sanitizeJsonForPrompt measurement (B-pass round 2)", line: 177 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: usage_counters
cloud_columns: [user_id, quota_key, window_start, used, updated_at]
contract_test_path: supabase/functions/_shared/prediction_handler_test.ts
ist_handling:
  - "Window is istDayStartIso() — the IST calendar day, same as the three cap triggers and ai-media-proxy's PRO caps (CLAUDE.md §4.5)."
provider_invalidations: []
telemetry_op_types:
  - "reportGeminiExhaustion(source ai_proxy_gemini_exhausted, endpoint prediction) — unchanged, now injected into the handler (OI-226)"
cross_account_guard: Not applicable — the quota row is keyed on the JWT-derived user id inside the Edge Function; no client-side account state is read or written.
forbidden_patterns_checked:
  - "refunding the unit on Gemini failure — rejected for this path: a refund keyed on 'no content' also refunds request-induced failures (review round 2, F2), and it is unnecessary here because the failure status is a non-retried 500. Refunds for the tight free vision caps are designed separately (batch a3)."
  - "returning 502 on Gemini failure (the previous status) — rejected: SupabaseService.retryColdStart auto-retries 502/503/504 three times, and each retry would consume a unit, so one outage would spend the whole daily cap in one tap."
  - "keeping context.system_prompt behind sanitizeBlock — rejected: it has no legitimate sender, and a sanitised caller-authored SYSTEM prompt is still caller-authored."
  - "a bare quota_key 'prediction' — rejected: collides with the 'prediction card' glossary term (naming_conventions.md); key is prediction_daily."
proposed_fix: |
  - `_shared/prediction_handler.ts`: server-owned `PREDICTION_SYSTEM_PROMPT`
    (the old default, verbatim); `consumePredictionQuota` (consume_quota,
    key `prediction_daily`, IST-day window, cap 3) called BEFORE Gemini;
    ledger error or non-number → 500 fail-closed; `-1` → 429
    `RATE_LIMITED`; Gemini empty → reportGeminiExhaustion + 500.
  - `_shared/ai_proxy_input_limits.ts`: one validator for message / text /
    snapshot sizes, called before the first `type` branch; the per-branch
    length checks are removed (same error strings).
  - ai-proxy's prediction branch is a thin delegation; `context` is no
    longer destructured at all.
  - Client: `AiService.predict(message)` sends only the message; both
    callers drop the dead `system_prompt` map.
  - Digest: `DIGEST_KEYS` gains `prediction_daily` (daily, cap 3); the caps
    mirror now scans every non-test module in the functions tree,
    recursively (B-pass Finding 5: the first widening listed `_shared/`
    non-recursively and could not see `_shared/tools/`).
  - B-pass c5d659f52986 remediation:
    - Finding 1 — `functions.invoke` THROWS on non-2xx, so `predict()`'s
      status check never saw the 429 and its generic catch dropped the
      status. `predict()` now catches `FunctionException` and keeps the status
      and server text (`AiService.predictionFailure`);
      `regeneratePrediction()` returns `PredictionRefreshOutcome`
      (success / dailyLimitReached / failed; the cap is no longer sent to
      telemetry as a fault); the Profile refresh says "Daily prediction limit
      reached. Try again tomorrow." instead of "try again later"; a PRO
      goal-change regenerate that does not land marks the prediction stale,
      as the FREE branch already did.
    - Finding 2 — the prompt test now attempts the attack (a hostile
      `context.system_prompt` and two siblings) and the ai-proxy call's first
      argument is pinned to exactly `{ message }`.
    - Finding 4 — kill switch `DISABLE_PREDICTION_QUOTA=true` (Edge Function
      secret, read per call, no redeploy) skips the ledger only; the prompt
      stays server-owned.
  - Hermes pass (docs/audit/2026-09-26-hermes-single-owner-a1.md) remediation:
    - L1-F1 — a PRO prediction marked stale by the goal-change path showed
      "Refresh prediction (PRO)" while UPDATE stayed disabled for up to 30
      days. `PredictionService.refreshEnabled` enables it whenever the text
      is stale; the notifier uses it.
    - L1-F3 / L29-F4 / L21 — the 30-day auto-refresh fires on every provider
      rebuild and the goal-change regenerate on every goal save, so automatic
      calls alone could spend all 3 units. `PredictionAttemptGate`: automatic
      callers share one attempt per IST day (Hive `prediction_auto_attempt_day`,
      user-scoped, written BEFORE the request), and a request made while one
      runs joins it. Manual taps are limited only by the server.
    - L37-F3 — `outcomeForError` read every 429 as the daily cap. It now
      requires the handler's `code: RATE_LIMITED`, carried on the new
      `AiServiceException.code`; any other 429 is a fault (telemetry, generic
      message).
    - L37-F2 — the snapshot cap measured `JSON.stringify`, but the prompt
      receives `sanitizeJsonForPrompt`, which turns each raw U+2028/U+2029/
      U+0085 into six characters (9,998 → ~60,000). It now measures the
      sanitised text; identical for every snapshot without those characters.
    - L1-F2 — with the kill switch on, the digest printed
      "Prediction (3/day): none". The switch's name and rule moved to
      `_shared/prediction_quota_switch.ts` (no imports, so the digest does not
      bundle Gemini) and the digest prints UNMETERED for that key.
    - L21-F1 / L29-F5 — unused `asPrincipalMessage` import removed; stale
      migration/cap citations in ai-proxy comments corrected against live
      `pg_get_functiondef` (129 / 132 / 129, vision cap 20).
  - B-pass round 2 (0d1abba92408, over the Hermes remediation delta):
    - F1 P1 — `PredictionService` was never registered with
      `SingletonLifecycleRegistry`, unlike its 10+ siblings. On a
      same-device account switch mid-flight, the new gate's join
      semantics let the NEW account's own tap join the OLD account's
      stale future, and — independent of joining — `_regenerate`'s
      `MigratedKey.write` calls resolve the CURRENT userBox at write
      time, so a prediction generated for the OLD profile could land in
      the NEW account's box. `_regenerate` now captures
      `HiveUserSession.currentOwnerFullId` before `predict()` and refuses
      to write if it changed; `PredictionService` registers with
      `SingletonLifecycleRegistry` and clears the gate's in-flight future
      on account change.
    - F2 P2 — the client's `_compactContext` snapshot budget measured
      plain `json.encode(...)` length while the server (this same
      batch's L37-F2 fix) measures the length after
      `sanitizeJsonForPrompt`. A snapshot near the client's 9500-char
      ceiling carrying ~100+ rare separator characters could pass the
      client and be rejected server-side. The client now measures the
      same sanitised length.
regression_test_planned:
  - supabase/functions/_shared/prediction_handler_test.ts (new, 11 tests, fakes) — -1 → 429 with Gemini NOT called; ledger error and non-number → 500 with Gemini NOT called; missing message → 400 with nothing consumed; system prompt is the server's, including against a hostile context.system_prompt; exhaustion → report BEFORE a 500; consume-then-Gemini order; kill switch ON → no consume, server prompt kept; kill switch read from the env on every call; consumePredictionQuota's exact RPC args.
  - test/services/prediction_refresh_outcome_test.dart (new, 6 tests) — a thrown 429 / 500 / status-0 keeps its status and server text; 429 → dailyLimitReached, everything else → failed; end to end.
  - test/contracts/prediction_refresh_outcome_wiring_test.dart (new, 4 tests, comment-stripped presence) — predict() catches FunctionException into predictionFailure; the Profile daily-limit branch; the PRO goal-change stale mark; the coach auto-refresh invalidates only on success.
  - supabase/functions/_shared/ai_proxy_input_limits_test.ts (new, 7 tests) — each limit at N and N+1 with the old strings; the prediction shape is bounded; WIRING: the validator precedes the first `if (type ===`, and the prediction branch delegates with exactly `{ message }` and reads no system_prompt.
  - supabase/functions/_shared/gemini_backoff_retry_test.ts — the two prediction pins repointed to the handler (retries: 2; lastError destructured and reported before a 500; ai-proxy injects reportGeminiExhaustion with endpoint "prediction"); plus a new assertion that the handler never returns 502.
  - test/contracts/founder_digest_caps_mirror_test.dart — mirror widened to every non-test module, recursively; pinned cap prediction_daily = 3.
  - test/contracts/usage_quota_ledger_writer_to_reader_test.dart — prediction_handler.ts allowlisted as a direct caller, with its reason.
  - test/services/prediction_attempt_gate_test.dart — now 15 tests: the original 10 (Hermes), plus B-pass round 2's `safeToWriteForTest` (4: same owner safe, changed owner unsafe, signed-out mid-flight unsafe, no-session-throughout safe) and the join-avoidance test (`clearInFlightForAccountChange` makes the next call start fresh against the REAL `PredictionAttemptGate` class, not a fake).
  - test/services/prediction_refresh_outcome_test.dart — now 9 tests: 429 needs RATE_LIMITED; a gateway 429 (no code, string body) → failed; the code is read from Map and JSON-string bodies.
  - test/contracts/prediction_refresh_outcome_wiring_test.dart — now 9 pins: the Hermes 7, plus B-pass round 2's `_regenerate` guard-placement pin (owner captured before `predict()`, guard between `predict()` and the first write) and the `SingletonLifecycleRegistry.register`/callback-body pin.
  - test/contracts/prediction_service_singleton_lifecycle_test.dart (new, 2 tests, B-pass round 2) — touching `PredictionService.instance` really registers it (via the real `SingletonLifecycleRegistry.registeredNames()`, not a source grep); a real `HiveUserSession.openForUser` account-switch cycle invokes the callback without throwing.
  - test/ai_coach/compact_context_sanitized_length_test.dart (new, 4 tests, B-pass round 2) — sanitised length equals plain length for ASCII; each separator character adds 5; a snapshot under the plain ceiling but over the sanitised one is trimmed (margins verified with a probe script); the same snapshot without separators is not trimmed (control).
  - supabase/functions/_shared/ai_proxy_input_limits_test.ts — now 8 tests: a U+2028 snapshot under the stringify length is refused.
  - supabase/functions/_shared/founder_digest_content_test.ts + founder-digest/index_test.ts — UNMETERED rendered instead of "none" (with a switch-off control); unmeteredQuotaKeys; gatherDigestInput reads the env.
  - "Mutations run (rule 21): see the Mutation proof section below."
impact_analysis: |
  - Every user: predictions are capped at 3 attempts per IST day. The two
    callers are onboarding (once) and regenerate / the PRO 30-day refresh;
    neither approaches 3 in normal use. A 4th attempt gets 429: both
    callers keep the previous prediction, the Profile refresh says the daily
    limit was reached, and a PRO goal-change regenerate marks it stale.
  - Kill switch: `DISABLE_PREDICTION_QUOTA=true` stops metering without a
    redeploy if the ledger misbehaves; unset is the default. While it is on,
    the founder digest says so instead of reporting "none".
  - Automatic refreshes (PRO 30-day, PRO goal change) get one attempt per IST
    day between them; a skipped goal-change regenerate marks the prediction
    stale, and a stale PRO prediction's UPDATE button is enabled.
  - A prediction whose network request outlives a same-device account
    switch is discarded rather than written into the new account's Hive
    box; the switch also clears the automatic-refresh gate so the new
    account starts fresh instead of joining the old one's stale request.
  - The client's own snapshot trim budget matches the server's, so a
    snapshot carrying enough rare separator characters is trimmed
    client-side instead of being rejected by the server with no local
    feedback.
  - A Gemini failure now costs one of the 3 attempts and is not retried by
    the client (was 502, auto-retried). The EF still retries Gemini itself
    (retries: 2).
  - Old app versions still send context.system_prompt; the server ignores
    it. No client behaviour depends on it.
  - Requests over the size limits get the same 400 strings as before; the
    only newly-refused requests are over-long prediction messages (the real
    ones are ~700 chars).
  - Deploy: ai-proxy, founder-digest, telegram-admin-bot. No migration.
  - Tier: this doc's own files classify `platform` (ai-proxy/**, _shared/**,
    lib/core/**, CLAUDE.md); the batch commit is `catastrophic` through the
    delete-account half (40054f), not through this fix (B-pass Finding 6).
related_bugs: [f7a2c9, e7b3c5, e7c4b2]
recurrence: >-
  Same class as the OI-162 ledger slices (e7c4b2 and siblings): a Gemini path
  whose spend had no durable owner. And the system-prompt half was flagged
  during OI-47 (e7b3c5) and recorded as an open product question in the code
  comment rather than closed; this closes it.
touched_layers_checked:
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "New user-scoped key prediction_auto_attempt_day (IST YYYY-MM-DD) via MigratedKey, listed in UserConfigMigrator.userScopedKeys (migrated_key_contracts_test green) and the naming table; a new key never lived in configBox, so no _flagKey bump." }
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "AiService.predict now message-only and keeps a FunctionException's status; PredictionService returns PredictionRefreshOutcome; Profile, edit-profile and the coach auto-refresh updated; flutter analyze lib/ — no errors or warnings." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "usage_counters has no prediction_daily rows today (new key); consume_quota creates them on first use." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check ai-proxy, founder-digest, telegram-admin-bot — Check OK. Deploy pending founder go + a fresh Management API token; ai-proxy is diffed against deployed v87 first." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "consume_quota is SECURITY INVOKER with EXECUTE for service_role only (migration 130); ai-proxy calls it with its service-role client." }
  - { tier: 12, name: "Client → server contract", status: fixed_in_this_batch, evidence: "predict() sends {message,type}; the server returns the unchanged 200 shape {reply, model_used, tokens_used, actions}, 429 RATE_LIMITED at the cap, 500 otherwise." }
---

# ai-proxy prediction: unmetered, unbounded, caller-controlled system prompt

## Mutation proof (rule 21)
Each mutation applied by exact-string replacement with the match count checked
(= 1) before running, then reverted; runner script in the session scratchpad.
Counts are failed / total of the files named.

| Mutation | Red |
|---|---|
| M1 consume removed (`deps.consume()` → a constant `{ used: 1 }`) | 5 / 8 `prediction_handler_test.ts` |
| M2 fail-open on ledger error (`if (error \|\| typeof used !== "number")` → `if (false)`) | 2 / 8 |
| M3 system prompt derived from the request (`String(message)`) | 1 / 8 |
| M4 Gemini-empty returns 502 | 2 / 33 (`prediction_handler_test.ts` + `gemini_backoff_retry_test.ts`) |
| M5 validator result ignored (the `if (limitViolation) return …` line deleted) | 1 / 7 `ai_proxy_input_limits_test.ts` |
| M5b validator call left only inside a comment | 1 / 7 |
| M9 `prediction_daily` removed from DIGEST_KEYS | 2 / 6 `founder_digest_caps_mirror_test.dart` |

⚠ **M5 and M5b reddened NOTHING against the first version of the wiring test.**
It checked only that the text `validateAiProxyInput(body)` appeared before the
first branch: it neither required the result to be acted on (M5) nor stripped
comments (M5b, where the mutation left the call's text in a comment). Both are
the rule-21 "zero-red is not coverage" trap. The test now strips comments and
requires both the call and the `return` on a violation before the first
`if (type ===`; the counts above are from the strengthened version.

The M1–M4 counts were measured when `prediction_handler_test.ts` held 8 tests;
the B-pass additions below took it to 11.

### B-pass c5d659f52986 remediation (run 2026-09-26, same runner; the worktree
diff was hashed before and after and matched byte-for-byte)

| Mutation | Red |
|---|---|
| Mb1 the reviewer's regression: handler falls back to `input.context?.system_prompt`, ai-proxy passes `context: body.context` (0 / 15 red against the first version of the tests) | 3 / 18 (`prediction_handler_test.ts` + `ai_proxy_input_limits_test.ts`) |
| Mb2 kill switch read once at module load | 1 / 11 |
| Mb3 kill switch ignored (consume always runs) | 2 / 11 |
| Mb4 `predict()`'s `on FunctionException` clause removed | 1 / 10 (`prediction_refresh_outcome_test.dart` + `_wiring_test.dart`) |
| Mb5 `predictionFailure` drops `statusCode` | 4 / 6 |
| Mb6 `outcomeForError` never matches 429 | 2 / 6 |
| Mb7 Profile's daily-limit branch disabled | 1 / 4 |
| Mb8 PRO goal-change stale mark removed | 1 / 4 |
| Mb11 probe `consume_quota` caller added in `_shared/tools/` | 1 / 1 — the mirror fails at site discovery, naming the probe file |
| Mb12 Mb11's probe with the scan reverted to non-recursive `_shared/` | 0 / 6 — the control: the old scan never saw it |

### Hermes remediation (run 2026-09-26, `hermes_mutations.py` in the session
scratchpad; every touched file hashed before and after and matched)

| Mutation | Red |
|---|---|
| Mh1 automatic attempts never skipped | 1 / 10 `prediction_attempt_gate_test.dart` |
| Mh2 automatic day recorded after the request | 1 / 10 |
| Mh3 no in-flight join | 1 / 10 |
| Mh4 in-flight never cleared | 4 / 10 |
| Mh5 `refreshEnabled` loses the stale arm | 1 / 10 |
| Mh6 `outcomeForError` ignores the code | 2 / 9 `prediction_refresh_outcome_test.dart` |
| Mh7 `predictionFailure` drops the code | 3 / 9 |
| Mh8 coach auto-refresh not `automatic` | 1 / 7 `prediction_refresh_outcome_wiring_test.dart` |
| Mh9 goal-change regenerate not `automatic` | 1 / 7 |
| Mh10 notifier passes `isStale: false` | 1 / 7 |
| Mh12 snapshot measured before sanitising | 1 / 8 `ai_proxy_input_limits_test.ts` |
| Mh15 digest renders an unmetered key as a count | 1 / 17 `founder_digest_content_test.ts` |
| Mh16 `gatherDigestInput` never reads the switch | 1 / 52 `founder-digest/index_test.ts` |

⚠ **Mh10 reddened NOTHING against the first version of its pin** (0 / 7). The
pin matched `isStale: isStale` lazily from the `refreshEnabled(` call onward,
and the same text appears again in the `PredictionData(...)` below it, so a
call passing `isStale: false` still matched. The pin now reads the call's own
argument list; the count above is from that version.

### B-pass round 2 remediation (run 2026-09-26, over the Hermes delta;
every touched file backed up and restored byte-for-byte)

| Mutation | Red |
|---|---|
| Mb13 `safeToWriteForTest` returns `true` unconditionally | 2 / 15 `prediction_attempt_gate_test.dart` |
| Mb14 `PredictionService`'s `SingletonLifecycleRegistry.register` call commented out | 3 / 11 (`prediction_service_singleton_lifecycle_test.dart` + `prediction_refresh_outcome_wiring_test.dart`) |
| Mb15 `clearInFlightForAccountChange` made a no-op | 1 / 15 `prediction_attempt_gate_test.dart` |
| Mb16 `_compactContext`'s `size()` reverted to plain `json.encode(...).length` | 1 / 4 `compact_context_sanitized_length_test.dart` |

`compact_context_sanitized_length_test.dart`'s own fixture numbers (plain
8790, sanitised 10040) were computed with a throwaway probe script before
being written into the test, not estimated — round 1 of writing this test
picked numbers with too little margin (200 separator characters, expected
result exceeded 9500 by only ~700 short) and the assertion caught its own
fixture being wrong before any mutation was run. The test file's first draft
also embedded a raw U+2028 character directly in a comment (twice, once in
the fixture and once in the comment WARNING about doing exactly that) —
found by hex-dumping the file, not by reading it — and was rewritten to
build every separator character from `String.fromCharCode`/bare hex, never
a literal escape in source, matching `sanitize_for_prompt.ts`'s own
documented discipline for this file class.

**SoT registry follow-through (Mb14's fix):** `PredictionService` is the
8th singleton registered with `SingletonLifecycleRegistry` (was 7 at the
2026-05-20 A7 audit). Updated: `docs/sot_registry.yaml`'s
`singleton_lifecycle_registry` concept — new `writers:` entry, and its two
current-state "seven singletons" prose lines bumped to "eight" (the
audit-historical "seven core services … A7, score 14" sentence describing
the ORIGINAL 2026-05-20 finding was left as-is, since that count is a
historical fact about the audit, not the registry's current membership).
`test/contracts/singleton_lifecycle_registry_test.dart`'s hardcoded `wired`
list gained `['lib/core/services/prediction_service.dart',
'PredictionService']`, and its two "7 wired singletons" header comments
were bumped to "8"; the file's `SingletonLifecycleRegistry.count`
assertions (lines ~62, ~114) are scoped to isolated/reset test blocks with
fake callbacks, not the real global registry total, so they needed no
change. Full suite re-run after: 49/49 green across every prediction- and
singleton-lifecycle-related test file (see Mb13-Mb16 above).
