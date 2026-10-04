---
bug_id: f1a70c
date: 2026-06-07
batch: psych-skill-and-audit-2026-06-07 (audit remediation — Batch 3, F1)
status: fixed
blast_radius: account
symptom: >
  The client declared the free AI-coach cap as 15 messages/day and ran a
  client-only 30-day trial, while the server (ai-proxy) enforces 10/day FOREVER
  with no trial (OQ-1). Two user-facing failures: (1) a free user saw the
  counter allow 5 more, sent message 11, and got a server 429; (2) any free user
  >30 days post-install had the AI-coach composer DISABLED ("Daily limit reached
  — Go PRO") even with 0 messages used today, locked out by a trial the real
  product does not have.
concept: ai_free_message_limit
sot_registry_entry: "server FREE_DAILY_LIMIT is authoritative — pinned client==server by test/contracts/ai_message_limit_parity_test.dart"
writers:
  - "{ file: supabase/functions/ai-proxy/index.ts, method: FREE_DAILY_LIMIT, line: 63 } — server cap = 10, OQ-1 (authoritative)"
readers:
  - "{ file: lib/core/constants/app_constants.dart, method: freeAiMessagesPerDay, line: 70 } — client cap, now 10"
  - "{ file: lib/features/ai_coach/screens/ai_coach/screen.dart, method: _sendMessage, line: 259 } — free-tier send gate (per-day count only, no trial)"
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: ai_coach_interactions
cloud_columns: "channel (server counts channel='app' rows per IST day for the cap)"
contract_test_path: test/contracts/ai_message_limit_parity_test.dart
ist_handling: "server counts the daily cap per IST day (istDateStr in ai-proxy); client count resets per IST day"
provider_invalidations: messageLimitProvider (the daily message count drives the gate)
telemetry_op_types: n/a
cross_account_guard: user-scoped (subscription + message count are per-user)
forbidden_patterns_checked: >
  no freeAiTrialDays constant, no trialInfoProvider / TrialInfoData /
  TRIAL_EXPIRED anywhere in lib/ — asserted by ai_message_limit_parity_test.dart.
proposed_fix: >
  Set client freeAiMessagesPerDay 15→10 to match the server; remove the entire
  client-only trial subsystem (TrialInfoData / TrialInfoNotifier / trialInfoProvider
  + every consumer's trial branch); the free send-gate is now the per-day count
  only. Pin client==server with a comment-stripped parity test. Update
  business-rules.md + supabase/functions/CLAUDE.md to "10/day forever, no trial".
regression_test_planned: test/contracts/ai_message_limit_parity_test.dart (parity + trial-removed) — GREEN
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: cap 15→10; trial subsystem removed across 9 files; isLimitReached + _sendMessage gate on the per-day count only; flutter analyze clean; grep shows 0 dangling trial refs; parity test green }"
  - "{ layer: edge_function, status: verified, evidence: ai-proxy/index.ts:63 already FREE_DAILY_LIMIT=10, no trial path (OQ-1) — server unchanged, no deploy }"
  - "{ layer: client_to_server_contract, status: fixed_in_this_batch, evidence: client cap now equals the server's; parity test prevents re-drift }"
  - "{ layer: postgres_data, status: not_applicable, evidence: no schema/data change; ai_trial_start Hive key simply stops being written/read (left in migrator array, harmless) }"
impact_analysis: >
  P1 free-tier lockout: every free user >30 days post-install was blocked from the
  AI coach by a fictional trial. Plus messages 11–15 were accepted client-side then
  429'd. Fix removes the trial and aligns the cap to the server's 10/day-forever.
  3 device integration tests that pinned the buggy trial-paywall behaviour were
  converted to assert the new contract (free user under cap sends, no paywall).
closes-diagnose: f1a70c
---

# F1 — AI free-tier 15/10 cap drift + 30-day-trial lockout

## What happened
`AppConstants.freeAiMessagesPerDay = 15` + `freeAiTrialDays = 30` (client) vs
`ai-proxy/index.ts FREE_DAILY_LIMIT = 10`, OQ-1 "10/day forever, no trial" (server).
The client `TrialInfoNotifier` started a 30-day `ai_trial_start` clock and, once
"expired", the composer gate `isLimitReached = !isPro && (count >= 15 || trialInfo.isTrialExpired)`
disabled the input for free users **regardless of today's message count** — a lockout
the server never imposes. The `TRIAL_EXPIRED` error branch mapped a code the server
never sends.

## Fix
- `freeAiMessagesPerDay 15 → 10` (+ comment); deleted `freeAiTrialDays`.
- Removed the trial subsystem: `TrialInfoData`/`TrialInfoNotifier`/`trialInfoProvider`
  + every consumer (input_bar param + gate, screen send-gate + reads, compact_header,
  subscription_section chip, app.dart + day_rollover invalidations, bootstrapper
  `ai_trial_start` write, razorpay_service invalidation). The free send-gate is now
  `messageCount >= freeAiMessagesPerDay` only.
- RATE_LIMITED copy interpolates the constant (no hardcoded "15/day"); dead
  TRIAL_EXPIRED branch deleted.
- `business-rules.md` + `supabase/functions/CLAUDE.md` → "10/day forever, no trial".
- `test/contracts/ai_message_limit_parity_test.dart` pins client==server (comment-stripped)
  + asserts the trial stays removed.

## Recurrence
First instance for the AI-limit contract. The parity test (server-as-SoT) makes
re-drift a CI failure. See also `feedback_source_grep_strip_comments_first`.
