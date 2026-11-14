---
bug_id: 8b1f33
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 11 / Theme C)
status: shipped
symptom: |
  Founder ranked up SD2 → LT recently and the AVYA coach said
  nothing about it. The pre-existing coach surface is reactive —
  responds only to user messages. No proactive-message
  infrastructure existed: no event queue, no Edge Function watching
  `rank_promotions`, no notification path.

  Theme B (commit 7) wired the existing PromotionCelebrationScreen
  to a client-side Hive flag — surfaces a modal next time the user
  opens the home tab. But the AVYA coach itself stayed silent. The
  user's expectation per the brand model is that AVYA is the
  coach — should congratulate them by name when they hit a
  milestone, in the AI Coach chat surface itself, and notify them
  via push if the app is closed.
concept: proactive_coach_promotion
sot_registry_entry: rank_promotion_log
writers:
  - { file: supabase/migrations/073_proactive_coach_promotion_trigger.sql, method_or_widget: trg_dispatch_proactive_coach_promotion — fires AFTER INSERT on rank_promotions → pg_net.http_post → /functions/v1/proactive-coach-promotion. Service-role key from Vault per canonical cron-auth pattern. Errors swallowed (rank record is source of truth; dispatch is additive). Telemetry to client_errors., line: 1 }
  - { file: supabase/functions/proactive-coach-promotion/index.ts, method_or_widget: Edge Function — pulls user_profile + user_progress, composes Gemini 2.5 Flash congrats (80-120 words, AVYA brand voice), inserts coach_interactions row (role=assistant, channel=in_app, metadata.kind=proactive_promotion), POSTs OneSignal push with deep_link=/ai-coach., line: 1 }
readers:
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: existing coach_interactions reader — surfaces the new proactive message as just another assistant turn in chat history. No client change needed., line: 1 }
hive_key_prefix: "n/a — server-side wiring"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: rank_promotions
cloud_columns: [user_id, rank_code, achieved_at, created_at]
contract_test_path: test/contracts/proactive_coach_promotion_test.dart
ist_handling:
  - { file: supabase/migrations/073_proactive_coach_promotion_trigger.sql, line: 60, source: "passes NEW.achieved_at OR NEW.created_at as TIMESTAMPTZ to the Edge Function — no date-key math at this layer" }
provider_invalidations: []
telemetry_op_types:
  success: [proactive_coach_promotion_dispatched]
  failure: [proactive_coach_promotion_dispatch_failed, proactive_coach_promotion_failed]
cross_account_guard: trigger uses NEW.user_id from the rank_promotions row — row-level isolation guarantees the dispatch targets the correct user. Edge Function uses service-role client with explicit eq('user_id', user_id) on every read. No cross-account leak surface.
forbidden_patterns_checked:
  - "Hardcoding service_role_key in DDL — must come from Vault."
  - "Letting trigger errors propagate to the INSERT transaction — rank record cannot be lost because the celebration failed."
  - "Calling Gemini 2.5 Pro (expensive) for 80-120 word congrats — flash is the right tier."
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "no client change needed — coach_interactions reader already surfaces assistant role messages in chat order" }
  - { tier: 3, name: postgres_schema, status: fixed_in_this_batch, evidence: "migration 073 creates private.dispatch_proactive_coach_promotion + AFTER INSERT trigger" }
  - { tier: 5, name: migrations_applied, status: pending_pre_merge, evidence: "migration file committed; apply_migration via Supabase MCP + backups/applied_migrations.json update happens as final pre-merge step" }
  - { tier: 6, name: edge_function_code, status: fixed_in_this_batch, evidence: "supabase/functions/proactive-coach-promotion/index.ts written" }
  - { tier: 6, name: edge_function_deploy, status: pending_pre_merge, evidence: "deploy via host-shell flow (node .claude/emit_payload.js + deploy_via_api.js) happens as final pre-merge step alongside migration apply" }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "Vault has service_role_key (Audit 2026-05-12). ONESIGNAL_APP_ID + ONESIGNAL_REST_API_KEY + GEMINI_API_KEY confirmed set per CLAUDE.md §2a." }
  - { tier: 11, name: external_services, status: fixed_in_this_batch, evidence: "OneSignal push payload validated; Gemini 2.5 Flash REST endpoint correct" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/proactive_coach_promotion_test.dart — 14 assertions covering migration shape (function in private schema + SECURITY DEFINER + Vault resolve + pg_net + AFTER INSERT + exception-swallow + telemetry) and Edge Function shape (service-role client + coach_interactions role/channel/metadata + OneSignal push + deep_link + telemetry + Gemini-Flash model + brand voice)" }
impact_analysis:
  callers_audited:
    - public.rank_promotions INSERT path (RankService.evaluateAndPromote — the only writer)
    - Edge Function caller surface (trigger only — no other intended callers)
  callers_updated_in_this_batch:
    - supabase/migrations/073_proactive_coach_promotion_trigger.sql (new)
    - supabase/functions/proactive-coach-promotion/index.ts (new)
  callers_unchanged:
    - Client app — coach_interactions reader already handles assistant-role messages; new metadata.kind value is forward-compatible.
proposed_fix: |
  Three-layer server-side pipeline:

  1. Migration 073 — Postgres trigger on rank_promotions INSERT:
     - private.dispatch_proactive_coach_promotion() SECURITY DEFINER
       function.
     - Resolves service_role_key from Vault via existing
       private.morning_alert_get_service_key() helper.
     - pg_net.http_post to ${SUPABASE_URL}/functions/v1/proactive-coach-promotion
       with payload {user_id, rank_code, achieved_at, trigger_source}.
     - Exception handler swallows errors — never block the parent
       INSERT.
     - Telemetry on every path (dispatched / dispatch_failed) to
       client_errors.

  2. Edge Function `proactive-coach-promotion`:
     - verify_jwt=false (trigger is the only legitimate caller; bears
       service_role_key as Bearer).
     - Pulls user_profile (full_name, primary_goal) + user_progress
       (current_streak_weeks, total_workouts_done) via service-role
       client.
     - Composes AVYA congrats via Gemini 2.5 Flash with hardcoded
       system prompt enforcing brand voice (military lexicon sparingly,
       NO emojis, 80-120 words, single paragraph, addresses by first
       name, references specific milestone + primary_goal).
     - INSERTS into coach_interactions with role=assistant,
       channel=in_app, metadata={kind:'proactive_promotion', rank_code,
       source:'proactive-coach-promotion'}.
     - Sends OneSignal push targeting external_user_id=user_id with
       headings="🎖️ Promotion Day", body=truncated congrats,
       data.deep_link=/ai-coach.
     - Success / failure telemetry to client_errors.

  3. No client change needed — existing AiCoachRepository reader
     surfaces the new assistant message as part of chat history.
     Optional future enhancement: a "new proactive message" badge on
     the coach tab nav. Not in scope this batch — message-in-chat +
     OneSignal push is sufficient surface per the founder's stated
     need.
regression_test_planned:
  - test/contracts/proactive_coach_promotion_test.dart — 14 assertions covering migration (private schema + SECURITY DEFINER + Vault resolve + pg_net + AFTER INSERT + exception-swallow + dispatch telemetry) and Edge Function (service-role client + coach_interactions role/channel/metadata + OneSignal endpoint + deep_link to /ai-coach + dispatched/failed telemetry + gemini-2.5-flash model + brand-voice prompt enforcement).
related_bugs:
  - 9aa2c1  # Theme B — wires PromotionCelebrationScreen modal (client-side complement to this server-side push)
deploy_steps:
  - Step 1 (pre-merge, founder runs): Apply migration via Supabase MCP `apply_migration` — name=073_proactive_coach_promotion_trigger, query=contents of supabase/migrations/073_proactive_coach_promotion_trigger.sql.
  - Step 2 (pre-merge, founder runs): Update backups/applied_migrations.json with the new entry per feedback_migration_apply_record_pair.md. Commit the JSON update in the same git commit as the apply.
  - Step 3 (pre-merge, founder runs): Deploy Edge Function via host-shell flow per CLAUDE.md §0 — `node .claude/emit_payload.js proactive-coach-promotion --auto --functions-dir <worktree>/supabase/functions` then `node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl proactive-coach-promotion .claude/_payload_proactive-coach-promotion.json false`. verify_jwt=false (the trigger holds the service-role bearer).
  - Step 4 (post-deploy verify): `mcp__ba7b5e8e__get_edge_function` for proactive-coach-promotion returns the new version code. Query client_errors for proactive_coach_promotion_dispatched after a test rank insert.
---
# Body

## Why server-side (vs client-after-write)

Client-side stamp (Theme B) is the right shape for the in-app modal
celebration: it surfaces the moment the user next opens the home tab
on the device where the promotion was evaluated. But for the COACH
surface specifically:

- A user can rank up while the app is closed (e.g. background sync
  on splash → workout-complete → RankService → rank changed).
  Client-after-write means the coach gets the proactive message only
  on the user's next manual open.
- Multi-device: device A's RankService writes rank_promotions. Device
  B's coach surface should also reflect the milestone next time the
  user opens AVYA on B.

Server-side via Postgres trigger + Edge Function + OneSignal push
solves both: the dispatch is decoupled from device state, the AI
message is one cloud record consumed by every device's existing
coach reader, and the push notification lands even if the app is
closed.

## Why trigger errors must be swallowed

The rank_promotions INSERT is the source of truth for the user's
rank. If the dispatch fails (network blip, Vault not seeded,
Edge Function cold-start timeout, OneSignal outage), we ABSOLUTELY
must not lose the rank record by rolling back the parent transaction.
The dispatch is additive — a celebration moment, not a record.

EXCEPTION WHEN OTHERS captures the failure into client_errors with
op_type=proactive_coach_promotion_dispatch_failed. A future operational
review of stuck dispatches catches them via SQL; the user has the
rank record either way.

## Why Gemini 2.5 Flash (not Pro)

Per the model matrix in docs/architecture/ai.md:
- 2.5 Pro: weekly report (PRO-only, deepest reasoning, 1K-2K words).
- 2.5 Flash: text analysis class — short structured outputs (80-120
  words is well within the Flash sweet spot).
- 2.5 Flash Lite: scan meal + cart auditor (image input).

Congrats messages are ~100 words of natural language with specific
data points. Flash is the right tier — fast (<5s typical), cheap,
and avoids Pro's quota gating. The congrats doesn't need Pro's
deep reasoning.

## Deploy steps (run as the final pre-merge gate)

The migration apply + Edge Function deploy are infra changes that
modify production. They run AFTER all 12 code commits land but
BEFORE the merge-to-main, per the founder's explicit option 1
sequencing. The deploy_steps section above lists the exact MCP /
host-shell commands.

After deploy, smoke test:
1. Force a rank promotion (e.g. via supabase test INSERT on
   rank_promotions for the founder).
2. Within 30 seconds — query client_errors for op_type
   proactive_coach_promotion_dispatched (success path).
3. Within 60 seconds — open AI Coach in the app, confirm the new
   assistant message at the top of chat.
4. Confirm OneSignal push landed on phone with deep_link to
   /ai-coach.

## Future enhancement (NOT a deferred bug)

"New proactive message" badge / gold dot on Coach tab nav — would
require a small client-side StateProvider reading coach_interactions
for unread proactive messages. Tracked as a discrete UX enhancement
in batch retrospective; not implemented this batch because (a) the
founder didn't ask for it explicitly, (b) the OneSignal push is the
authoritative "new message" surface for the same scenario, (c) the
badge work is independent of the server-side plumbing this commit
ships.
