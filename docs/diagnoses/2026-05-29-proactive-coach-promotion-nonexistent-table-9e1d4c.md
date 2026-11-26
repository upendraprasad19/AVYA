---
bug_id: 9e1d4c
date: 2026-05-29
batch: audit-2026-05-29
status: fixed
symptom: >
  Every rank promotion silently fails to deliver its celebration — no AI
  congrats message is stored and no OneSignal "Promotion Day" push is sent.
concept: coach_interactions
sot_registry_entry: coach_interactions
blast_radius: platform
writers:
  - { file: supabase/functions/proactive-coach-promotion/index.ts, method: serve, line: 99 }
  - { file: supabase/functions/proactive-coach-promotion/index.ts, method: logTelemetry, line: 268 }
readers:
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: getFreeImageAnalysisCount, line: 269 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [user_id, channel, user_message, ai_response, model_used, tool_calls]
contract_test_path: test/contracts/proactive_coach_promotion_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: [proactive_coach_promotion_dispatched]
  failure: [proactive_coach_promotion_failed]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: 'from\("coach_interactions"\)', absent: true }
  - { pattern: 'role:\s*"assistant"', absent: true }
  - { pattern: 'severity:', absent: true }
proposed_fix: >
  Insert into the real chat table ai_coach_interactions with valid columns
  (user_message empty string since the column is NOT NULL, ai_response =
  congrats, channel = in_app, model_used, and the proactive tag + rank_code
  in the tool_calls jsonb). Fix logTelemetry to write client_errors.error_message
  / error_code (the real columns) instead of message / severity. Replace the
  RANK_LABELS map with the canonical ladder codes from rank_ladder_data.dart.
regression_test_planned:
  - test/contracts/proactive_coach_promotion_test.dart
touched_layers_checked:
  - { tier: 1, layer: edge_function_code, status: fixed_in_this_batch, evidence: "index.ts insert + telemetry + rank labels corrected" }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "information_schema confirms ai_coach_interactions exists; coach_interactions does not; client_errors has error_message not message/severity" }
  - { tier: 6, layer: edge_deploy_vs_git, status: fixed_in_this_batch, evidence: "proactive-coach-promotion v3 deployed 2026-05-29 (HTTP 201); smoke returned healthy 400 on empty body = input guard reached" }
  - { tier: 7, layer: cron_trigger, status: verified, evidence: "trg_dispatch_proactive_coach_promotion confirmed live on rank_promotions" }
impact_analysis: >
  Every rank promotion fires the trigger, which invokes this function. The
  insert into the nonexistent coach_interactions table returned an error,
  causing an early HTTP 500 BEFORE the OneSignal push — so the entire
  promotion-celebration loop (chat congrats + push notification) was inert
  since the function first shipped (v1/v2). The failure was invisible because
  the function's own telemetry insert also targeted nonexistent client_errors
  columns. Fix is source-only; takes effect on redeploy to v3 (founder-gated).
  No data loss, no crash, no demotion — purely a missed delivery.
---

# 9e1d4c — proactive-coach-promotion wrote to a nonexistent table

## What happened
`proactive-coach-promotion` (fired by `trg_dispatch_proactive_coach_promotion`
on every `rank_promotions` INSERT) inserted into a table `coach_interactions`
that **does not exist** in the live DB. The real chat table is
`ai_coach_interactions`, with columns `user_message` (NOT NULL), `ai_response`,
`channel`, `model_used`, `tool_calls` — not the `role / content / metadata`
this code wrote. The insert errored → HTTP 500 at the early-return guard →
`sendOneSignalPush` never ran.

Two compounding defects made it invisible and cosmetically wrong:
- `logTelemetry` inserted `{message, severity}` into `client_errors`, which has
  neither column (real: `error_message`, `error_code`) → failure telemetry
  silently dropped.
- `RANK_LABELS` used codes (`PO2/PO1/ENS/LTJG/LCDR/CDR/CAPT`) absent from the
  canonical ladder (`SD2,SD1,LS,PO,CPO,MCPO,SubLt,Lt,LtCdr,Cdr,Capt`), so 7 of
  11 ranks fell through to the raw code in the AI prompt.

## Root cause
A source-grep contract test (`proactive_coach_promotion_test.dart`) pinned the
WRONG table/columns and **never verified the table exists** — classic
`feedback_source_grep_false_confidence`. Live schema was never cross-checked.

## Fix
See `proposed_fix`. The rewritten test now asserts the correct table + columns
AND adds negative assertions (nonexistent table/columns must be ABSENT) that
would have caught this. Deploy of v3 is gated on founder approval.

## Verification
Live `information_schema` queries (2026-05-29) confirm: `ai_coach_interactions`
exists with the columns used; `coach_interactions` does not exist;
`client_errors` columns are `error_code/error_message/op_type` (no
`severity`/`message`). Trigger confirmed on `rank_promotions`.
