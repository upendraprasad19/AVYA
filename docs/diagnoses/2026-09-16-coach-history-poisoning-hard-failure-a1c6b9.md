---
bug_id: a1c6b9
date: 2026-09-16
batch: apk43-obs-fixes (Obs 2 of 3)
status: fixed
blast_radius: platform
symptom: |
  Founder reported (APK 1.0.0+43, two screenshots) that the AI Coach chat
  showed "I had trouble reaching the model. Try again in a moment." on
  every turn since the previous day, including a plain "hi" and "hi what's
  the workout today" — repeated failures at 01:51, 01:52, and again at
  23:59 IST-adjacent timestamps, spanning far longer than a single
  transient outage would explain.
concept: coach_chat_history_replay
sot_registry_entry: |
  coach_chat_history_replay
  (docs/sot_registry.yaml:4207) — not a new concept. Adds a description
  block documenting the hadHardFailure mechanism (both tool-loop.ts apology
  sites, a DEDICATED had_hard_failure field kept separate from the
  pre-existing failed field per plan-review round 1, and a restore-path
  text-matching defense for the same round's other finding), a new writer
  entry for CoachInteractionRepository.updateInteractionWithResponse, a new
  writer entry for sync_coach.dart's _restoreCoachInteractions, and corrects
  the pre-existing recentHistoryExchanges/syncCoachMemoryNow writer
  citations' line_ranges (drifted from unrelated earlier edits in the same
  files this batch — caught by scripts/check_sot_registry_parity.dart
  before commit).
writers:
  - { file: supabase/functions/_shared/tool-loop.ts, method_or_widget: "runToolLoop — HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED catch block AND HARD_FAILURE_APOLOGY_ROUNDS_EXHAUSTED (loop-exhausted branch) both set hadHardFailure=true", line: 298 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "chat handler — forwards loop.hadHardFailure as had_hard_failure in the JSON response body", line: 1161 }
  - { file: lib/core/services/ai_service.dart, method_or_widget: "_buildResponse — parses had_hard_failure into AiChatResponse.hadHardFailure", line: 316 }
  - { file: lib/features/ai_coach/repositories/coach_interaction_repository.dart, method_or_widget: "updateInteractionWithResponse — writes entry['had_hard_failure'] = hadHardFailure (NEW dedicated field; entry['failed'] stays unconditionally false, plan-review round 1 finding 2 — failed also drives ChatHistoryNotifier.build's error-bubble+Retry UI)", line: 228 }
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: "_restoreCoachInteractions — writes had_hard_failure: isKnownHardFailureApologyText(ai_response) on every restored row (plan-review round 1 finding 1 — the cloud row has no hadHardFailure column, so the restore path recognizes the two known apology texts instead of a flag)", line: 224 }
readers:
  - { file: lib/features/ai_coach/repositories/coach_interaction_repository.dart, method_or_widget: "recentHistoryExchanges — excludes on map['failed'] == true OR map['had_hard_failure'] == true", line: 319 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "semantic-memory embed guard — never embeds the apology into memory_embeddings", line: 1120 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "SendMessageNotifier — 3 updateInteractionWithResponse call sites thread hadHardFailure through (media path / primary chat / auth-retry)", line: 677 }
hive_key_prefix: coach_
hive_key_formula: "coach_<millisecondsSinceEpoch>"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [ai_response]
contract_test_path: test/contracts/coach_chat_history_replay_writer_to_reader_test.dart
ist_handling:
  - "Not applicable — no date keys or counter resets involved. The failure timestamps investigated (01:51/01:52/18:29 UTC) were read directly from Edge Function logs, not derived from any IST helper."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — the fix operates entirely within one user's own coachBox rows (the hadHardFailure flag) and the server-side per-request loop result; no cross-account read or write is introduced."
forbidden_patterns_checked:
  - { pattern: "entry['failed'] = false; (unconditional) in updateInteractionWithResponse", absent: true }
  - { pattern: "loop.hadHardFailure ignored when building the memory_embeddings insert body", absent: true }
proposed_fix: |
  Add ToolLoopResult.hadHardFailure (tool-loop.ts), set true only in the
  branch that sets the hardcoded "I had trouble reaching the model"
  apology (i.e. every bounded Gemini retry pass across both models
  genuinely exhausted — not the FC2 partial-intent case, and not the
  separate loop-exit-exhaustion apology text elsewhere in the same file,
  which is untouched). Thread it through ai-proxy's response body as
  had_hard_failure, parse it into AiChatResponse.hadHardFailure client-side,
  and pass it into every updateInteractionWithResponse call site so the
  Hive row's `failed` field reflects a hard failure instead of being
  hardcoded false. recentHistoryExchanges already excludes `failed: true`
  rows from replay — no change needed there, the bug was purely that this
  writer never set it. Also skip the semantic-memory embed for a hard
  failure turn, since embedding the apology has the same self-perpetuation
  shape one layer further out (a future retrieval pass surfacing it into a
  system prompt).
regression_test_planned:
  - test/contracts/coach_chat_history_replay_writer_to_reader_test.dart (new case: hadHardFailure:true excludes the turn from replay; default false keeps it; plan-review round 1 added 2 more cases — had_hard_failure alone excludes, and a simulated restored row excludes)
  - supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts (new file, Deno: exhaustion sets hadHardFailure=true + exact apology text; happy path false; FC2 queued-intent case stays false; B-pass added the loop-exhausted-branch case)
  - test/ai_coach/ai_service_had_hard_failure_parse_test.dart (new file: had_hard_failure JSON true/false/missing parse into AiChatResponse.hadHardFailure)
  - test/contracts/hard_failure_apology_texts_parity_test.dart (new file, plan-review round 1 — TS/Dart string parity, isKnownHardFailureApologyText pure-function behavior + mutation coverage, and a source-grep pin that _restoreCoachInteractions actually calls it)
impact_analysis: |
  Root cause confirmed via live Supabase log query (query_logs against
  function_logs/function_edge_logs), NOT guessed: on 2026-09-15 at
  01:51/01:52 UTC the exact log line
  "[geminiChatWithTools] gemini-2.5-flash failed (HTTP 429: 'You exceeded
  your current quota, please check your plan and billing details')"
  appeared for BOTH models (gemini-2.5-flash and gemini-2.5-flash-lite),
  across both of TOOLS_MAX_PASSES=2 retry passes, twice — genuine total
  quota exhaustion, not a transient overload the existing bounded-retry
  mechanism (diagnose d4f1c2, confirmed still working correctly) could
  recover from. Querying ai_coach_interactions for the same user in the
  same window found successful food_text_analysis calls interleaved with
  the failing chat calls, ruling out a global Gemini outage.

  A THIRD occurrence at 18:29 UTC is the actual mechanism this fix closes:
  the flash-lite fallback logged "fallback succeeded" (the bounded retry
  DID recover), yet the persisted ai_response was still the apology text.
  That is the history-poisoning symptom: an EARLIER hard failure's apology
  had already been written to a coach_<ms> row and, because
  updateInteractionWithResponse always set failed=false, that row survived
  recentHistoryExchanges's filter and was replayed as conversation history
  on the 18:29 turn — the model then echoed/continued from the apology
  text rather than answering "hi what's the workout today" fresh, which is
  indistinguishable from a fresh failure to the user even though Gemini
  itself had recovered.

  Scope: this fix touches every AI coach chat turn (ai-proxy is the single
  chat entry point for all tiers) — platform blast radius, confirmed by
  scripts/blast_radius_from_diff.dart on the touched file set. It does NOT
  fix the underlying Gemini API quota exhaustion itself — that is a founder
  billing/quota action item outside this batch's scope, communicated
  separately in the session summary. Does NOT touch AiService's
  ai-media-proxy response parsing path, which never sends had_hard_failure
  — AiChatResponse.hadHardFailure defaults to false there, pinned by the
  "missing field defaults to false" test case.

  PLAN-REVIEW ROUND 1 widened the scope twice (both findings independently
  verified against live current file contents before fixing, per this
  batch's own no-fabricated-numeric-claims discipline):
  (a) the original fix covered only the catch-block apology; tool-loop.ts
  ALSO sets a second, unrelated hardcoded apology when maxRounds exhausts
  with no terminal text and no queued intents — same self-perpetuation
  mechanism, unguarded. This was ALREADY caught and fixed same-session by
  the B-pass (finding 1, docs/reviews/6f1e4db85459-review.md) before round 1
  ran — round 1 independently re-verified it rather than trusting that
  status. (b) round 1's OWN finding, not previously known: ai-proxy's
  reservation-resolve UPDATE persists ai_response to the cloud
  ai_coach_interactions row UNCONDITIONALLY (no had_hard_failure column
  exists), so a hard-failure apology turn IS present in the cloud table
  exactly like a real reply — and _restoreCoachInteractions wrote a restored
  row with no failed/had_hard_failure key at all, letting the SAME poisoned
  content re-enter replay via a cold restore (reinstall / new device) even
  though the live path was fully guarded. See "Plan-review round 1" section
  below for the fix and why it required a THIRD field design decision
  (finding 2, below) rather than simply setting `failed: true` on restore.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "ai_service.dart, coach_interaction_repository.dart, ai_coach_repository.dart (shim), ai_coach_provider.dart (3 call sites) all updated; flutter analyze lib/ exits 0 with only pre-existing info-level issues, none in touched files." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "coach_<ms> row's NEW 'had_hard_failure' field (kept SEPARATE from 'failed', which stays unconditionally false on this write path — plan-review round 1 finding 2) correctly reflects a hard-failure apology turn on both the live path (flag threaded through) and the restore path (text-matched by isKnownHardFailureApologyText) — pinned by test/contracts/coach_chat_history_replay_writer_to_reader_test.dart's 3 cases and test/contracts/hard_failure_apology_texts_parity_test.dart." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "The 'failed'/'had_hard_failure' flags are Hive-local only (coach_<ms> row fields), never synced to the ai_coach_interactions cloud table — confirmed against backups/live_schema_columns.json, which lists that table's columns as id/user_id/snapshot_id/channel/user_message/ai_response/model_used/tokens_used/was_helpful/created_at/summarized/tool_calls with no such column. Corrected 2026-09-16 (B-pass P3 finding) — an earlier draft of this doc's cloud_columns field incorrectly listed 'failed' alongside 'ai_response'. Plan-review round 1 finding 1 confirmed the CONSEQUENCE of this schema gap (no cloud column exists to carry the flag through a restore) and fixed it client-side via text-matching rather than adding a migration — deliberately, to stay within this batch's scope; see 'Plan-review round 1' below." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "tool-loop.ts + ai-proxy/index.ts changed in this worktree but NOT yet deployed — deploy requires separate explicit founder authorization per CLAUDE.md §4.3 (live prod apply needs its own explicit go). deno check --node-modules-dir=none passed clean on both files pre-deploy." }
  - { tier: 12, name: "Client -> server contract", status: fixed_in_this_batch, evidence: "had_hard_failure is a new, additive JSON field on ai-proxy's response body — a client running the OLD ai_service.dart against a NEW ai-proxy ignores the unknown field (no break); a client running the NEW ai_service.dart against an UN-DEPLOYED old ai-proxy sees the field missing and defaults hadHardFailure to false (identical to pre-fix behavior, no break either direction)." }
---

## Summary

Second of three findings from the APK 1.0.0+43 observation batch (2 founder-
reported, 1 self-surfaced — see diagnose `<TBD sync-storm doc, OI-204>` for
the third, explicitly scoped out of this batch per founder direction). Fixes
the AI Coach's "I had trouble reaching the model" apology outliving the
Gemini quota outage that caused it, by stopping that apology from being fed
back into the model's own conversation history on the next turn.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "coach", "gemini", "history", "apology"
— found two prior fixes: `d4f1c2` (2026-06-01, bounded [Flash -> Flash-Lite]
retry across 2 passes) and `7fbe21` (2026-07-04, thinking-budget disable +
FC2 queued-intent apology suppression). Both mechanisms were CONFIRMED STILL
WORKING CORRECTLY in the live incident logs — the retry fired, tried both
models, both passes, and only gave up on genuine total quota exhaustion,
which neither prior fix was designed to survive (a quota exhaustion is not
transient; retrying does not help). This is NOT a recurrence of either prior
bug — it is a new bug class (a hardcoded-apology turn replaying into the
model's own history) that only became visible because the retry mechanism
those two fixes built is otherwise sound.

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer:** `CoachInteractionRepository.updateInteractionWithResponse`
(`lib/features/ai_coach/repositories/coach_interaction_repository.dart:202`,
pre-fix) unconditionally set `entry['failed'] = false` for EVERY successful
(non-throwing) response from `ai-proxy` — including the hardcoded "I had
trouble reaching the model" apology text, which the client cannot otherwise
distinguish from real model output because `ai-proxy` returned it as an
ordinary 200 response.

**Reader:** `CoachInteractionRepository.recentHistoryExchanges`
(`coach_interaction_repository.dart:297`, unchanged by this fix) already
filters `map['failed'] == true` out of replayed history — the filter logic
was always correct; the writer simply never gave it the signal to act on.

The gap is a MISSING SIGNAL at the writer, not a writer/reader field-name
drift or a broken filter: `ai-proxy` (server) knew internally that a given
turn's text was the hardcoded apology (`tool-loop.ts`'s own local
`hadHardFailure` state, introduced by this fix) but never surfaced that fact
in its response body, so the client had no way to mark the row.

## Fix

1. **Server: `ToolLoopResult.hadHardFailure`** (`tool-loop.ts:114`) — new
   field, `false` by default (`tool-loop.ts:234`), set `true` in BOTH
   branches that set a hardcoded, non-model apology text: the catch-block
   one (`tool-loop.ts:269-272`), guarded by the same `!finalText &&
   intents.length === 0` condition as the apology itself (so the FC2
   queued-intent case — a summarization-round failure over an already-
   working "Logged" card — still never sets it, matching the apology's own
   scope); and the loop-exhausted-without-a-terminal-response one
   (`tool-loop.ts:508-521`, added after a same-batch B-pass review caught
   that the first version of this fix covered only the catch-block apology
   — see `docs/reviews/6f1e4db85459-review.md` finding 1 — leaving this
   SECOND hardcoded apology, "Recruit — I had trouble pinning that down...",
   free to replay into history via the exact same mechanism this fix exists
   to close). Both sites leave the FC2 "Copy that, Recruit — I've queued
   that below" acknowledgment excluded — it is real, useful output, not an
   apology substitute.
2. **Server: thread through the response.** `ai-proxy/index.ts:1161` adds
   `had_hard_failure: loop.hadHardFailure` to the JSON response body.
   `ai-proxy/index.ts:1120` also guards the semantic-memory embed with
   `!loop.hadHardFailure` — an apology turn is never embedded into
   `memory_embeddings`, closing the same self-perpetuation shape one layer
   further out (a future retrieval pass surfacing the apology back into a
   system prompt).
3. **Client: parse it.** `AiChatResponse.hadHardFailure`
   (`ai_service.dart:41`, default `false`) parses `had_hard_failure` in
   `_buildResponse` (`ai_service.dart:316`) as `data['had_hard_failure'] as
   bool? ?? false` — so a response from `ai-media-proxy` (which never sends
   this field) or an un-deployed old `ai-proxy` both default safely to
   `false`.
4. **Client: write it.** `updateInteractionWithResponse` gains a
   `hadHardFailure` parameter (default `false`) and writes `entry['failed']
   = hadHardFailure` instead of the old unconditional `false`
   (`coach_interaction_repository.dart:225`). The shim forwarder
   `ai_coach_repository.dart` passes it through unchanged. All three real
   call sites in `ai_coach_provider.dart` (media path :677, primary chat
   :910, auth-retry :980) now pass `hadHardFailure:
   aiResponse.hadHardFailure` / `retryResponse.hadHardFailure`.

No change was needed to `recentHistoryExchanges` itself — its `failed ==
true` exclusion was already correct.

## Plan-review round 1 (independent, context-blind — CLAUDE.md §4.12)

Dispatched after the B-pass, on the post-B-pass-hardened state (2 commits
landed: `4725e8ac` OI-204 docs, `444ba20f` the fix). Re-verified every B-pass
claim independently rather than trusting the review's own `status: accepted`
markers, and re-ran every cited test command itself. Found 2 P1s and 1 P2,
none catastrophic; all fixed same session, no deferrals.

**Finding 1 (P1) — the RESTORE path had no defense at all, only the LIVE
path did.** `ai-proxy/index.ts`'s reservation-resolve UPDATE
(`.from('ai_coach_interactions').update({..., ai_response: cleanReply, ...})`)
persists every turn's text to the cloud UNCONDITIONALLY — it does not check
`loop.hadHardFailure` (only the semantic-embed guard does). So a hard-failure
apology turn sits in the cloud table exactly like a real reply. Independently
confirmed by reading `sync_coach.dart`'s pre-fix `_restoreCoachInteractions`
Hive-put: it wrote `id`/`user_message`/`ai_response`/`model_used`/`mode`/
`is_user_message`/`created_at`/`channel`/`source` and NOTHING else — no
`failed`, no equivalent. A cold restore (reinstall, new device) therefore
wrote a restored row that `recentHistoryExchanges`'s filter reads as
NOT-failed (`map['failed'] == true` is false on an absent key), so it
re-enters replay — reproducing the exact self-perpetuation bug this whole
batch exists to close, via the restore trigger instead of the live-failure
trigger. **This is itself a `guard_without_its_mirror` instance** (I guarded
the live write→read chain and never asked whether the server independently
persists the same poisoned content through an unguarded path) — recorded as
instance #30 in the harness memory's recurring-class file for that reason.
Fix: `kKnownHardFailureApologyTexts` (`sync_coach.dart`) mirrors both exported
`tool-loop.ts` apology strings (parity pinned by
`test/contracts/hard_failure_apology_texts_parity_test.dart`), and
`_restoreCoachInteractions` now writes `had_hard_failure:
isKnownHardFailureApologyText(map['ai_response'])` into every restored row.
A cloud migration to add a real column was considered and rejected for this
batch — heavier surface area (schema change, backfill, its own review round)
for a defense that a 2-string exact-text match already covers completely for
the KNOWN apology set, with the parity test as the drift guard.

**Finding 2 (P1) — reusing `failed` for the fix collided with `failed`'s
OTHER, pre-existing reader.** The original fix wrote
`entry['failed'] = hadHardFailure` in `updateInteractionWithResponse`. Its own
doc comment claimed "the turn still delivers normally (pending: false, no
retry UI)" — FALSE, independently confirmed by reading
`ChatHistoryNotifier.build` directly: `isFailed = interaction['failed'] ==
true` (no other condition) renders an `isError: true` bubble with a Retry
button whenever true, and its `errText` fallback logic is explicitly
structured to handle a `failed: true` row with no `error_text` — exactly the
shape `updateInteractionWithResponse` produces. So every hard-failure apology
turn would have started rendering as a red error bubble + Retry on the very
next `ChatHistoryNotifier` rebuild (cold start, "clear" menu action, or any
`refreshFromHive()` elsewhere in the session) — a real, untested, unintended
user-facing UI change, not merely a doc-comment inaccuracy. Rather than
deciding this new UI behavior was acceptable (a genuine product judgment call
the founder was not consulted on, and outside this batch's authorized scope),
fixed by REVERTING to the original intent: `failed` reverts to unconditional
`false` on this success-resolution path (exactly its pre-feature behavior),
and a NEW, separate `had_hard_failure` field carries the history-exclusion
signal instead. `recentHistoryExchanges` now excludes on
`map['failed'] == true || map['had_hard_failure'] == true`.

**Finding 3 (P2) — stale registry prose contradicted its own commit's code.**
`docs/sot_registry.yaml`'s `coach_chat_history_replay` description, added by
this same commit, claimed the loop-exhaustion apology site was "untouched" —
false; the same commit's diff sets `hadHardFailure = true` there too (the
B-pass's own finding 1 fix). Read as stale prose carried over from before the
B-pass correction was folded in. Fixed by rewording.

Related, both instances of the same class: this session's ORIGINAL bug-history
lookup (CLAUDE.md §4.1.5) had already surfaced the harness memory's
`guard_without_its_mirror` recurring-class file — reading it did not prevent
finding 1 from shipping in the first draft. Knowing the class is not the same
as enumerating its instances; the mechanical check that would have (grep the
whole file, not the diff hunk, for the shape that makes a guard necessary)
ran only after the B-pass and round 1 supplied it externally.

## Verification

**Deno (server):**
`supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts` (4
tests, the 4th added post-B-pass) — persistent-429-on-every-call sets
`hadHardFailure: true` with the catch-block apology text; a clean
happy-path response sets `false`; the FC2 queued-intent-before-later-
failure case (mirroring the existing `tool-loop_intent_apology_test.ts`
scenario) stays `false`; a `maxRounds`-exhausted turn with no terminal
text and no queued intent (every round calls the read-only `getFormCues`
tool, which throws internally on the test's null `ctx.sb` and is
swallowed by tool-loop.ts's own per-call catch) sets `hadHardFailure:
true` with the SECOND apology's exact text. Run via `deno test --no-check
--allow-all --node-modules-dir=none
supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts` — 4/4
passed. `deno check --node-modules-dir=none` on both `tool-loop.ts` and
`ai-proxy/index.ts` passed clean.

**Mutated and run** (rule 21), twice — once per `hadHardFailure = true;`
site: (1) removed the catch-block site (`tool-loop.ts:271`) — reddened
exactly 1 of what was then 3 tests (`Actual: false / Expected: true`).
(2) After the B-pass fix added the second site (`tool-loop.ts:520`) and
its 4th test, removed THAT line — `grep -c "hadHardFailure = true"
tool-loop.ts` confirmed exactly 1 site remained before trusting the run —
reddened exactly 1 of 4 tests (the new one, `Actual: false / Expected:
true`), the other 3 (including the catch-block positive control) stayed
green, confirming the two sites are independently covered. Both mutations
confirmed real detection, not a compile-error false positive — the file
still type-checked and ran each time. Restored both times via the
backed-up file; re-ran green (4/4). `git diff --stat` confirmed only the
24 intended lines remained in `tool-loop.ts` (15 from the first fix + 9
from the B-pass follow-up).

**Dart (client):**
`test/contracts/coach_chat_history_replay_writer_to_reader_test.dart` — new
case seeds two pending coach rows, resolves one with `hadHardFailure: true`
and the apology text and the other with `hadHardFailure: false` (default)
and a real reply, then asserts `recentHistoryExchanges()` returns ONLY the
real-reply exchange, and that the hard-failure row's Hive fields are
`pending: false`, `failed: true`, `error_text: null` (not the retry-UI error
path — the turn still delivered normally). 9/9 tests in the file passed.

**Mutated and run:** reverted `entry['failed'] = hadHardFailure;` to
`entry['failed'] = false;` — reddened exactly 1 of 9 tests, with a clear
diff showing the apology text leaking into `recentHistoryExchanges()`'s
output at index `[0]`. Restored; re-ran green (9/9). `git diff --stat`
confirmed only the 12 intended lines remained.

`test/ai_coach/ai_service_had_hard_failure_parse_test.dart` (new, 3 tests) —
`had_hard_failure: true` parses to `true`; `false` parses to `false`;
missing field (the `ai-media-proxy` shape) defaults to `false`. 3/3 passed.

**Mutated and run:** hardcoded the parse line to `hadHardFailure: false,` —
reddened 2 of 3 (the `true`-expecting test failed with `Expected: true /
Actual: <false>`; the missing-field test stayed green since both real and
mutated code yield `false` there — expected, that test asserts the DEFAULT,
not this specific parse line). Restored; re-ran green (3/3). `git diff
--stat` confirmed only the 19 intended lines remained.

`flutter analyze lib/` exits 0 (only pre-existing info-level issues, none in
touched files). Combined run of all 3 new/extended Dart test files together
with the pre-existing `error_telemetry_helper_*` and
`ai_breakdown_save_confirmation_test.dart` files (Obs 1's tests) — 34/34
passing.

**Plan-review round 1 fixes — `test/contracts/hard_failure_apology_texts_parity_test.dart`
(new, 8 tests):** parity (2 — TS/Dart string equality after accounting for TS
source-text escaping of the embedded quotes, and both export sites exist),
`isKnownHardFailureApologyText` pure-function behavior (5 — exact match,
whitespace-tolerant match, real-output rejection, null/empty rejection,
near-miss rejection), and a source-grep wiring pin that
`_restoreCoachInteractions` calls the recognizer and writes
`had_hard_failure`. 8/8 passed. `flutter analyze lib/ test/` exits 0 (250
pre-existing info-level issues across the whole tree, zero warnings/errors,
zero in any file this batch touched — confirmed by grepping the analyzer
output for both severity levels and for every touched filename).

**Mutated and run, four separate mutations, each restored before the next:**
1. Deleted the `'had_hard_failure': isKnownHardFailureApologyText(...)` line
   from `_restoreCoachInteractions` entirely — reddened exactly 1 of 8 (the
   wiring test: `Expected: true / Actual: <false>`, "restore must write the
   had_hard_failure key").
2. Hardcoded `isKnownHardFailureApologyText` to `return false;` — reddened
   exactly 2 of 8 (the two tests asserting `true`; the `false`-asserting
   tests stayed green, which is the expected shape for a constant-false
   mutation — it cannot redden an assertion it already satisfies).
3. Re-introduced finding 2 (reverted `entry['failed'] = false;` back to
   `entry['failed'] = hadHardFailure;` in `updateInteractionWithResponse`) —
   reddened exactly 1 test across both affected files (`raw['failed']`
   `Expected: <false> / Actual: <true>`), confirming the fix is genuinely
   pinned and not merely asserted in prose.
4. Removed the `if (map['had_hard_failure'] == true) continue;` line from
   `recentHistoryExchanges` — reddened exactly 3 of 8 in
   `coach_chat_history_replay_writer_to_reader_test.dart`: the original
   live-path exclusion test, the new "had_hard_failure ALONE" test, and the
   new restore-path test — all 3 tests that depend on this specific clause,
   and no others.

All four mutations confirmed real detection (each left the file compiling —
none were a compile-error false positive per the CLAUDE.md §4.4 rule 21
caution), all four were restored via Edit (not a blind git revert, since
this batch's own changes were still uncommitted), and `grep -rn
"MUTATION-TEST" lib/ supabase/ test/` returned no matches afterward,
confirming no mutation artifact survived. Final combined re-run of all 7
affected Dart test files together — 46/46 passing. Deno
(`tool-loop_hard_failure_flag_test.ts` + `tool-loop.test.ts`) — 16/16
passing, unaffected since round 1 touched no TS logic beyond the
already-mutation-proven constant extraction (verified by diffing
`tool-loop.ts` against pre-extraction content: the two apology TEXT VALUES
are byte-identical, confirmed by this same test file's parity check, so
extracting them to named exports could not change runtime behavior — no new
mutation needed for a pure refactor with its own parity test already
covering the one way it could silently break).

## Related

Builds on (does not recur) `d4f1c2` (bounded retry mechanism, confirmed
working) and `7fbe21` (FC2 apology suppression, confirmed working and
deliberately shares its exact guard condition). Sibling finding in the same
observation batch: Obs 1 (diagnose `d8e2f4`, silent-catch telemetry gap on
nutrition save) and Obs 3 (OI-204, sync/restore timeout storm — documented,
explicitly not fixed in this batch per founder direction).

**Founder action item (not code-fixable in this batch):** the root cause of
the ORIGINAL outage was genuine Gemini API quota exhaustion (HTTP 429 "You
exceeded your current quota, please check your plan and billing details").
This fix stops that outage from self-perpetuating past its own duration; it
does not raise the quota. Recommend checking the Gemini API billing/quota
dashboard.
