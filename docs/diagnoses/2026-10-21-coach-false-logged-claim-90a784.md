---
bug_id: 90a784
date: 2026-10-21
batch: coach-log-truth (OI-368, OI-369; both stay OPEN until the post-deploy measurement)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: platform
symptom: >-
  Founder's A12 web walk 2026-10-21 (app.icanbefitter.com, ai_coach_interactions read-only): at 13:19:59 "log bench
  press" got "Roger. Logged. I need the specifics…" with nothing proposed or written (OI-368); at 13:21:37 "Log this
  workout for today: bench press 3 sets of 8 at 60 kg" got "Roger. Bench Press, 3 sets of 8, 60 kg. Logged. Carry on."
  while a logSet card was still waiting for APPLY, and the founder tapped DISMISS, so nothing was written (OI-369). The
  coach says something is logged before anything is saved.
concept: coach_write_claim_wording — what the coach is taught about saving, and a log-only label of what it said.
sot_registry_entry: coach_write_claim_wording
writers:
  - { file: supabase/functions/_shared/tool-loop.ts, method_or_widget: "runToolLoop: the queued functionResponse (status queued_for_user_confirmation) never said 'not saved'", line: 608 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "ICBF_LOG_INSTRUCTIONS headed 'FITNESS DATA LOGGING — INSTANT:' (origin/main :975-995), now icbfLogInstructions(ruleOn) from _shared/write_claim_prompt.ts", line: 1025 }
  - { file: supabase/functions/ai-media-proxy/index.ts, method_or_widget: "the same 'INSTANT' header in its own prompt (origin/main :728-745), now mediaIcbfLogInstructions(ruleOn)", line: 738 }
  - { file: supabase/functions/_shared/day_swap_routing.ts, method_or_widget: "PRO_CAPABLE_BLOCK example 'Confirm below and it's done.'", line: 49 }
  - { file: supabase/functions/_shared/tools/nutrition/logMealByText.ts, method_or_widget: "description claimed a 5-second auto-confirm card (the typed meal card waits for APPLY)", line: 27 }
  - { file: supabase/functions/_shared/tools/plan/scheduleTemplate.ts, method_or_widget: "description example 'Saved! Want me to schedule…'", line: 23 }
readers:
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "the reply; ai_coach_interactions.ai_response update (replayed as history and by the 30 s dedup)", line: 1282 }
  - { file: lib/features/ai_coach/widgets/log_confirm_card.dart, method_or_widget: "LogConfirmCard countdown: a legacy water/weight/food/sleep/measurement tag saves 5 s after it renders", line: 37 }
  - { file: lib/features/ai_coach/widgets/tool_confirm_card.dart, method_or_widget: "ToolConfirmCard: a typed intent waits for APPLY (trivial and reviewable)", line: 15 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [ai_response, tool_calls]
contract_test_path: supabase/functions/_shared/write_claim_prompt_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["console.log '[write-claim-detect]' + JSON {fn, interaction_id, rule_on, token, safe_marker, negation, unsafe_claims, queued_lines, typed_log, typed_other, legacy_workout, legacy_auto, replay, user_question} — never reply text, never the user id; ai-proxy size log gains write_claim_rule=<bool>"]
  failure: ["console.warn '[write-claim-detect] skipped' (a fixed string; the error object is never logged)"]
cross_account_guard: "n/a: prompt text and a log label; the detector line carries the interaction row id, never the user id."
forbidden_patterns_checked:
  - "rewriting the reply server-side (L3) — REJECTED by the founder 2026-10-21 after round 2 (10 P1s): the server cannot know which cards are on the user's screen; 14 of 28 realistic replies came out wrong. The app, which knows the cards, is the place for a guard if the measurement finds one is needed."
  - "editing CAPTAIN_MANUAL — REJECTED: weekly-report imports it too; the rule lives in _shared/write_claim_prompt.ts and is appended by the two proxies only."
  - "the rule inside the snapshot fence — REJECTED: the media rule is authored text, appended before the fenced snapshot."
  - "a kill switch that changes bytes when off — REJECTED: the OFF prompt, declarations and functionResponse are byte-identical to origin/main (golden recorded independently at 37c7498e)."
proposed_fix: >-
  L1: the queued functionResponse gains note "NOT saved yet. The user must tap APPLY on the card. Do not say it is
  logged, saved or done; say it is queued." L2: the ICBF blocks of both proxies move to _shared/write_claim_prompt.ts
  with a header saying nothing is saved when the coach replies, the founder-approved queued lines are taught in
  WRITE_CLAIM_RULE (a media variant with no tool lines), the logMealByText and scheduleTemplate descriptions stop
  claiming a save, and the day-swap example says "Tap APPLY below to swap them." A log-only detector labels every reply
  that claims a save or carries a prescribed line. Kill switch DISABLE_WRITE_CLAIM_RULE (exactly "true"), read once per
  request. OI-368/369 close only on the post-deploy measurement (plan §5.7).
regression_test_planned:
  - "supabase/functions/_shared/write_claim_prompt_test.ts: golden OFF bytes (both ICBF blocks + the day-swap block, sha256-recorded at 37c7498e); ON carries every approved line; the media variant names no tool and none of the tool lines; prompt-size delta pinned (2189 UTF-16 units); description swap (OFF = same array); kill-switch reader."
  - "supabase/functions/_shared/tool-loop_write_claim_note_test.ts: through runToolLoop with the fake Gemini: note on (true and undefined), absent (false); meal and template declarations."
  - "supabase/functions/_shared/write_claim_detector_test.ts: the three real transcripts, every prescribed line, 35 authored replies, word boundaries, untyped inputs, privacy and never-throw of the log helper; after the B-pass, every claim sentence read (unsafe_claims), wrapped/double-spaced lines, a curly-apostrophe negation, a throwing ctx thunk."
  - "test/contracts/coach_write_claim_wiring_test.dart: wiring pins over comment-stripped handler source; test/contracts/body_measurement_sites_parity_test.dart repointed to the shared module with exactly 2 matches."
mutation_proof: >-
  21 mutations by a scripted harness (scratchpad coach/run.py: exact-one-match replace, the named Deno or Dart test,
  restore in a finally, byte-compared). Per-mutation results in docs/audit/coach-log-truth.closure.yaml. Self-attested.
golden_capture: >-
  deno run --allow-run --allow-write capture_golden.ts 37c7498ed31400d3d4257e90e73b180091e0e060
  supabase/functions/_shared/testdata/icbf_blocks_pre_write_claim.json — the script reads ai-proxy/index.ts,
  ai-media-proxy/index.ts and _shared/day_swap_routing.ts with `git show <sha>:<path>`, slices each literal and
  evaluates it, independent of the new builders; its source is quoted in the closure ledger.
impact_analysis: >-
  Prompt text only, plus one functionResponse field and one log line. The ai-proxy prompt grows by 2189 UTF-16 units
  with the rule on. No reply is rewritten. Deploy of ai-proxy and ai-media-proxy needs the founder's go; the live check
  (plan §5) runs from local Claude Code on the founder's computer.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "no client behaviour change; tool_confirm_card.dart comment and body_measurement_sites.dart comment corrected; the parity pin repointed" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "the three 2026-10-21 ai_coach_interactions rows read read-only (plan §0)" }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "live ai-proxy / ai-media-proxy are origin/main; this change is NOT deployed (founder's go, plan §5.0)" }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "DISABLE_WRITE_CLAIM_RULE is new and unset (rule ON); SECRET_INVENTORY row added" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the reply/actions/intents response shape is unchanged; the functionResponse note is internal to the loop" }
recurrence: "New class: no prior record of the coach claiming a write it did not make. 7fbe21 (FC2, tool-loop.ts) is the precedent wording and is already true ('I've queued that below … tap APPLY'). Searched INDEX for logged/claim/queued/fabricat; the anti-fabrication records (CAPTAIN_MANUAL §8) cover invented data, not write claims."
related_bugs:
  - 7fbe21
---

# The coach said "Logged" before anything was saved

## What was wrong

Every prompt piece the model read either said nothing about when a save happens or said it was instant: the ICBF block
was headed "FITNESS DATA LOGGING — INSTANT:", the meal tool claimed a 5-second auto-confirm card that no longer exists
for typed meals, the template tool's example said "Saved!", the day-swap example said "Confirm below and it's done.",
and the queued functionResponse only said `queued_for_user_confirmation`. The model narrated the save as done.

## Fix

Teach what is true, verbatim with the founder-approved lines, and label every reply so the post-deploy measurement can
count false claims. The reply is never rewritten. See `docs/plans/coach-log-truth.md` (rev 13).

## Not closed here

OI-368 and OI-369 stay OPEN until the measurement of plan §5.7. If a false claim remains, the next piece is a
client-side guard. Removal of the kill switch: OI-374. FC2's hard-coded "Recruit": OI-375.
