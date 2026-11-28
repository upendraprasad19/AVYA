---
bug_id: e5c9d2
date: 2026-09-26
batch: single-owner-a1 (Hermes pass docs/audit/2026-09-26-hermes-single-owner-a1.md, finding L29-F3)
status: fixed
blast_radius: platform
symptom: |
  ai-proxy's chat dedup (`ai-proxy/index.ts`, "Deduplication: return cached
  response for same user+message in last 30s") served ANY recent row with a
  non-empty `ai_response` back as a 200 reply. When `runToolLoop` throws,
  the same handler closes the reserved row with
  `ai_response: "[failed] runToolLoop threw"` and
  `model_used: MODEL_USED_LOOP_THREW_SENTINEL` ("failed"), then returns 502.
  The client's `SupabaseService.retryColdStart` retries a 502 after 2 s,
  inside the 30 s window, so the retry received the internal failure marker
  as the coach's reply: the user saw "[failed] runToolLoop threw" in the
  chat. Found by reading the code (Hermes lens L29); live
  `ai_coach_interactions` holds 0 rows with `model_used = 'failed'` as of
  2026-09-26, so it has not fired yet — it needs a tool-loop crash.
concept: coach_chat_history_replay
sot_registry_entry: coach_chat_history_replay
writers:
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "runToolLoop catch — closes the reservation with ai_response '[failed] runToolLoop threw' + model_used MODEL_USED_LOOP_THREW_SENTINEL, returns 502", line: 1096 }
readers:
  - { file: supabase/functions/_shared/chat_dedup.ts, method_or_widget: "dedupDecision — process / replay_reply / replay_failure", line: 27 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "chat dedup — replay_failure returns the 502 before the reply branch", line: 758 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [user_id, channel, user_message, ai_response, model_used, created_at]
contract_test_path: supabase/functions/_shared/chat_dedup_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  - "console log '[ai-proxy] Dedup hit on a failed attempt … replaying the failure' (new); the reply-path log line is unchanged"
cross_account_guard: Not applicable — the dedup query is keyed on the JWT-derived user id, unchanged.
forbidden_patterns_checked:
  - "skipping the dedup for a failed row (re-running the message) — rejected: every run reserves a new ai_coach_interactions row and the chat cap is consumed on that insert (usage_counters ledger, migration 129) and never refunded, so the client's three automatic retries could spend three more of a free user's 10/day on one message."
  - "also skipping the dedup for the two hard-failure apology texts — rejected: those are user-facing replies by design (a1c6b9) and the original request returned them as a 200; replaying them for 30 s is the dedup doing its job, not a leak of an internal string."
proposed_fix: |
  - `_shared/chat_dedup.ts` `dedupDecision(row, loopThrewSentinel)`: no row
    or a pending reservation (`ai_response` "") → process; `model_used` is
    the loop-threw sentinel → `replay_failure`; any other non-empty reply →
    `replay_reply`. Pure, so it is testable without importing ai-proxy
    (whose module top level starts the server).
  - ai-proxy: `replay_failure` returns the same 502 ("AI temporarily
    unavailable. Please try again.", `deduplicated: true`) BEFORE the reply
    branch. The client's remaining retries hit the same dedup cheaply and
    the user sees the error, as they would have for the first failure. A
    manual resend after 30 s runs normally.
regression_test_planned:
  - supabase/functions/_shared/chat_dedup_test.ts (new, 5 tests) — no row → process; a real reply → replay_reply; the loop-threw row → replay_failure; a pending reservation → process; WIRING (comment-stripped): ai-proxy calls dedupDecision(recentDup, MODEL_USED_LOOP_THREW_SENTINEL), the failure branch precedes the reply branch, and the old truthy-ai_response check is gone.
  - "Mutations run (rule 21): see the Mutation proof section below."
impact_analysis: |
  - Only a retry or resend of a message whose first attempt crashed the tool
    loop changes: it gets the 502 error instead of a 200 whose reply is the
    internal marker. Real replies, pending reservations and the apology
    texts dedup exactly as before.
  - No quota change: a replayed failure reserves nothing.
  - Deploy: ai-proxy (already in this batch's deploy list). No migration.
related_bugs: [a1c6b9, a17bc3]
recurrence: >-
  Same class as a1c6b9 — a failed turn's text treated as a real reply — on a
  third reader of the same cloud row. a1c6b9 guarded the history-replay and
  restore readers; the dedup reader was not in its sweep. a17bc3 is the
  retry-during-failure duplicate class on the nutrition path.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "SupabaseService.retryColdStart retries 502/503/504 at 2 s / 6 s / 12 s (supabase_service.dart); AiService.chat does not set retryOn500 — so the first retry lands inside the 30 s window. No client change needed." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "ai_coach_interactions: 0 of 275 rows have model_used = 'failed' or the marker text (read-only count, 2026-09-26) — latent." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check ai-proxy — Check OK. Deploy pending founder go; live ai-proxy is still v87." }
---

# ai-proxy chat dedup replayed the internal failure marker as a reply

## Mutation proof (rule 21)
Applied by exact-string replacement (match count checked = 1), run, then
restored; every touched file hashed before and after and matched.

| Mutation | Red |
|---|---|
| Mh13 `dedupDecision` loses the sentinel check (a failed row reads as a reply) | 1 / 5 `chat_dedup_test.ts` |
| Mh14 ai-proxy's `replay_failure` branch disabled | 1 / 5 |
