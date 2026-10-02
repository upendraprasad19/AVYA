---
bug_id: d7a1f5
date: 2026-10-01
batch: gemini3-limits-caching (Part B — limits)
status: fixed
blast_radius: platform
symptom: |
  Caught in plan review round 1, BEFORE it shipped. Migration 129's chat trigger consumes a unit for EVERY `ai_coach_interactions` insert on channel `app`. That was harmless while PRO was exempt (the trigger returned early for PRO) and free users have 5 lifetime media reads. Capping PRO chat at 20/day on that body would have made every PRO photo/video read burn a CHAT unit: ai-media-proxy writes its PRO media rows with channel `app` and a real model label (ai-media-proxy/index.ts `interactionChannel`: `free_image_analysis` for a free image, `app` otherwise), and those rows already carry their own caps (pro_image_daily / pro_video_daily). A PRO user would have hit "daily message limit" after a handful of photo questions plus chat, with the ledger saying 20 chat messages. (Free users' lifetime media rows use channel `free_image_analysis`, which the chat trigger never gated, so only the PRO rows were at risk; checked at ai-media-proxy/index.ts `interactionChannel`.)
concept: usage_quota_ledger
sot_registry_entry: usage_quota_ledger
writers:
  - { file: supabase/migrations/153_gemini3_limits_refund.sql, method_or_widget: "enforce_chat_app_daily_limit: only a NEW row with channel app AND model_used = 'pending' consumes; PRO consumes too (daily_cap variable free 7 / PRO 20)", line: 76 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "chat reservation insert (channel app, model_used 'pending') -- the ONLY 'pending' writer on channel app", line: 875 }
readers:
  - { file: supabase/functions/ai-media-proxy/index.ts, method_or_widget: "PRO media interaction rows (`interactionChannel` = app, real model label); must spend NO chat unit", line: 991 }
  - { file: supabase/functions/_shared/ai_limits.ts, method_or_widget: "FREE_CHAT_DAILY_CAP / PRO_CHAT_DAILY_CAP: the display twin of the trigger's daily_cap arms", line: 22 }
hive_key_prefix: n/a
hive_key_formula: "n/a -- server trigger change"
sync_methods: []
restore_methods: []
cloud_table: "ai_coach_interactions / usage_counters (existing columns only)"
cloud_columns:
  - channel
  - model_used
  - quota_key
  - used
contract_test_path: test/contracts/ai_message_limit_parity_test.dart
ist_handling:
  - { site: "trigger window = IST day of now()", file: supabase/migrations/153_gemini3_limits_refund.sql, helper: "date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a -- server trigger keyed on the inserted row's own user_id."
forbidden_patterns_checked:
  - { pattern: "an `IF is_pro THEN RETURN NEW` early return in the chat trigger (PRO would be uncapped again)", absent: true }
  - { pattern: "a chat trigger without the model_used = 'pending' reservation guard (PRO media rows burn chat units)", absent: true }
  - { pattern: "an inline CASE as the consume_quota limit argument (readProFreeCap / readSingleCeiling parse the `daily_cap` variable form)", absent: true }
proposed_fix: |
  Migration 153 redefines `enforce_chat_app_daily_limit`: skip unless `NEW.channel IS NOT DISTINCT FROM 'app' AND NEW.model_used IS NOT DISTINCT FROM 'pending'`; derive `daily_cap := CASE WHEN is_pro THEN 20 ELSE 7 END` (a VARIABLE, so the cap readers keep parsing it); consume for PRO too; raise `chat_app_daily_limit_reached (cap=%, pro=%)`. The vision trigger gets the same tier-aware shape (free 4 / PRO 20) on migration 132's body.
regression_test_planned: |
  test/contracts/ai_message_limit_parity_test.dart (chat free/PRO == the migration's daily_cap arms == ai_limits.ts == AppConstants; the model_used = pending guard; vision free/PRO; PRO media literals), test/contracts/cap_triggers_use_usage_counters_test.dart ("chat charges PRO too and counts only the reservation row" replaces the old PRO-exemption pin), test/contracts/founder_digest_caps_mirror_test.dart (chat/vision are tier-mixed in the digest; the refund_quota site joins the trigger sites). Live behavioural: test/sql/oi46_daily_cap_triggers_live_verify.sql (cases 1-3 and the slice-2 chat/PRO/vision blocks rewritten: PRO consumes 12 reservations while 3 media rows burn nothing) and test/sql/gemini3_limits_refund_live_verify.sql R7/R8; run by the founder after the apply go.
mutation_proof: |
  Rule 21, applied and restored as in c4e9b2. S1 chat trigger counts every app row (drops the pending predicate): 2 reds (ai_message_limit_parity "only the pending RESERVATION row spends a unit" and the cap_triggers pin). S5 chat cap back to an inline literal (`daily_cap := 7`): 1 (the parity reader returns null for the PRO/free arms). S6 PRO early return restored: 1. S9 client free cap 10: 1. B-pass additions: Q2 the guard's OR connective flipped to AND (a PRO media row would spend a chat unit): 2 reds, because both ai_message_limit_parity and cap_triggers_use_usage_counters now pin the WHOLE `channel IS DISTINCT FROM 'app' OR model_used IS DISTINCT FROM 'pending'` expression, not the clause alone. Honesty: these are source-pin tests over migration TEXT; the trigger's execution is proven only by the live SQL scripts above, not yet run.
impact_analysis: |
  Who: every PRO user (now capped at 20 chat messages/day, a founder decision made on cost grounds with no usage data yet: heaviest PRO user-day on record was 10 app-channel rows) and every free user (10 -> 7). Behaviour change at the apply moment: a free user already at 7+ chat units or 4+ vision units TODAY is over the new cap immediately; apply off-peak. Existing PRO ledger rows: none (the 129 trigger froze the PRO ledger), so PRO starts from 0 on apply. Deploy: the migration and ai-proxy are independent in order (old ai-proxy's 429 body simply lacks tier/limit; the client falls back to its own tier).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "AppConstants.freeAiMessagesPerDay 10 -> 7, new proAiMessagesPerDay 20; tier-aware 429 copy; paywall copy no longer says Unlimited (chat_limit_part_b_client_test.dart)." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "No column change; two CREATE OR REPLACE trigger functions (bindings untouched) + one new function. Live pg_get_functiondef after apply is the founder's check." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Read-only MCP query earlier this session: 5 active PRO subscribers of 38 users; no PRO chat_app ledger rows exist (frozen ledger); heaviest PRO user-day on record = 10 app-channel rows." }
  - { tier: 5, name: "Migrations applied", status: verified, evidence: "Pre-apply live read: top 152, 153 reserved (mig/153). APPLIED 2026-10-02 via MCP apply_migration after the founder's explicit go: cloud version 20261002083656 (name gemini3_limits_refund); post-apply pg_get_functiondef shows the chat trigger with the model_used IS DISTINCT FROM 'pending' guard and free 7 / PRO 20, the vision trigger free 4 / PRO 20; all 3 cap triggers still bound. Ledger entry in backups/applied_migrations.json." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "ai-proxy 429 body gains tier + limit; ai-media-proxy PRO caps 50/10 -> 10/5; deno check clean. NOT deployed." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No policy change." }
  - { tier: 12, name: "Client -> server contract", status: fixed_in_this_batch, evidence: "429 {code: RATE_LIMITED, tier, limit} parsed by CoachReplies.chatRateLimitedFromError (both map and JSON shapes, fallback for an older body)." }
recurrence: e7c4b2 (docs/diagnoses/2026-09-05-cap-triggers-count-a-pruned-log-e7c4b2.md -- cap triggers whose count source disagrees with the quota they enforce); this instance is the same class (a counted row set wider than the budget it meters), found at plan time.
related_bugs: [e7c4b2, c4e9b2]
---

# Capping PRO chat on migration 129's body would have charged every photo question as a chat message

## Accepted residue (B-pass, self-attested)

- **A softened client boundary (founder decision 2026-10-02: ship as-is).** `authenticated` holds INSERT and UPDATE on `ai_coach_interactions` (`insert_own` / `update_own`). Before Part B any client insert with `channel='app'` hit the chat trigger and was refused 42501, because the triggers are SECURITY INVOKER and `authenticated` cannot execute `consume_quota` (verified live 2026-10-02: all three trigger functions and `consume_quota` have `prosecdef=false`, `has_function_privilege('authenticated', consume_quota)=false`). A client insert of `channel='app'` with `model_used='pending'` STILL hits `consume_quota` as the user and is refused. What changed: a client insert of `channel='app'` with any other `model_used` now returns early and is stored, and a user can edit `model_used` on their own rows (including back to `'pending'`). It buys no model call and spends or refunds no quota: `refund_quota` is service_role only and takes ids `ai-proxy` minted. Consequences are confined to the user's OWN history and summaries (fake chat rows feeding their own coach memory) and to any dashboard that counts `channel='app'` rows. Closing it needs a guard on client-supplied `channel`/`model_used` plus proof that no client sync path writes `channel='app'`; not done in this batch by the founder's choice.
- **Funnel label split.** PRO media rows keep channel `app`, so any dashboard that counts `channel='app'` rows as "chat messages" over-counts PRO users by their media reads. The `usage_counters` `chat_app` key is the chat truth; the `ai_coach` feature CLAUDE.md names it.
- **Midnight edge.** A reservation made before IST midnight and refunded after it refunds the ROW's day (correct), so the user sees no unit back for the new day.
- **Paywall funnel continuity.** `paywall_shown` / `paywall_dismissed` / `paywall_upgrade_tapped` log the raw `feature` label (`paywall_sheet.dart` telemetry `feature=${widget.feature}`), so renaming the coach-limit entry from `Unlimited AI Coach` to `Higher daily AI coach limit` ENDS the old series and starts a new one at the build that carries it. This is deliberate (the old label promised "unlimited", which the product no longer offers) and a one-time split: a funnel query that must span the change filters `feature IN ('Unlimited AI Coach', 'Higher daily AI coach limit')`. All five producers and the sheet's subtitle switch are pinned to one string by `chat_limit_part_b_client_test.dart` so the series cannot split a second time by drift.
