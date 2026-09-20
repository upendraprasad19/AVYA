# OI-162 slice 4 — `ai_coach_interactions.channel` reader enumeration (run to empty)

**Date**: 2026-09-10 · **Purpose**: discharge OI-162's `Blocked on: needs OI-153's
channel-reader enumeration`. The board records that *"three review passes each found
readers the previous one missed, so the enumeration must be run to empty before design."*

**Input set, widest form**: 402 `channel` hits across `supabase/ lib/ test/
integration_test/ scripts/` (worktrees excluded); 72 files reference
`ai_coach_interactions`. Narrowed to genuine readers below. Live half queried from
`pg_proc` / `pg_trigger` / `pg_policy` / `information_schema.views` — NOT from migrations,
because the last `CREATE OR REPLACE` wins and migration files are append-only.

## Writers (the value space)

| value | site |
|---|---|
| `app` | `ai-proxy:754`, `:1135` |
| `food_text_analysis` | `ai-proxy:324` |
| dynamic `type` | `ai-proxy:513` |
| `app_event` | `app_events_service.dart:28,63` |
| `in_app` | `proactive-coach-promotion:150` |
| `in_app_orphan` | `sync_coach.dart:152` |
| `promotion_ceremony` | `evaluate-rank-promotions:326` |
| `proactive_i_see_you` | `i-see-you-callout:120` |
| `weekly_report` | `weekly-report:639` |
| `video_paywall` / `image_paywall` | `ai-media-proxy:482`, `:554` |
| dynamic `interactionChannel` | `ai-media-proxy:765` |
| `verify_payment_attempt` | `verify-payment:252` |
| `delete_account_attempt` | `delete-account:178` — **INERT, never writes (OI-162)** |

Live: 134 rows, 0 with NULL channel.

## Readers — new-channel safety

### SAFE (allowlist / equality — a new value is excluded by construction)

| reader | predicate |
|---|---|
| `ai-media-proxy:142` | `.in("channel", ["pro_image_analysis","image_analysis"])` |
| `ai-proxy:291` | `.eq("channel","food_text_analysis")` |
| `ai-proxy:716` | `.eq("channel","app")` |
| `weekly-report:413` | `.eq("channel","promotion_ceremony")` |
| `coach_interaction_repository.dart:282` | allowlist `{app, chat, in_app_orphan}` |
| LIVE `founder_metrics_engagement()` | filters channel (migration 120) |
| LIVE trigger `enforce_chat_app_daily_limit` | `IS DISTINCT FROM 'app'` → early return |
| LIVE trigger `enforce_food_text_daily_limit` | `IS DISTINCT FROM 'food_text_analysis'` → early return |
| LIVE trigger `enforce_vision_analysis_daily_limit` | `NOT IN ('scan_meal','cart_auditor')` → early return ⚠ see defect below |

**All three cap triggers are allowlist-shaped**, so a `delete_account_attempt` insert
consumes no quota and cannot be refused by them. This is the load-bearing safety property
for slice 4 and it holds.

### UNSAFE for a new channel value — must be addressed in slice 4's batch

| # | reader | why |
|---|---|---|
| 1 | `rolling-context:181, 220, 256, 351` | `.neq("channel","app_event")` — **DENYLIST ×4**. Any new channel is treated as conversation. ⚠ The board names only `:351`; there are **four**. |
| 2 | `restore-user-snapshot:252-256` | `.select("*")`, **no channel filter** → an attempt row restores to the device as coach history |
| 3 | `daily-snapshot:61-66` | `.select("user_message, ai_response")` for the IST day, **no filter** → feeds the AI coach's context |
| 4 | LIVE `get_users_with_message_count()` | `where summarized=false group by user_id having count(*)>=min_count` — **no channel predicate**, and `summarized` is never written true, so the WHERE is a permanent no-op. Drives `rolling-context` MESSAGE_THRESHOLD=50 → summarize-and-delete → **would silently reset the delete-account counter**. This is the board's stated trap, reached by a route the board does not name. |
| 5 | LIVE `compute_coach_signals_for_user()` | `select max(created_at) … from ai_coach_interactions where user_id=…` with **no channel filter** → `v_days_silent`. An attempt row makes a user look active, suppressing re-engagement/dropout scoring. |
| 6 | `sync_coach.dart:115-140` | dedups on `user_message` across **any** channel within 5 min — low risk, narrow window, but not channel-scoped |

Readers 4 and 5 are **new** — not named on the OI-162 or OI-153 board entries.

## Defect found during the enumeration (not previously filed)

`channel` is **NULLABLE** (`information_schema` `is_nullable = YES`; 0 NULL rows today).
Two triggers guard with `IS DISTINCT FROM` (NULL-safe); `enforce_vision_analysis_daily_limit`
guards with `NOT IN ('scan_meal','cart_auditor')`. `NULL NOT IN (...)` is NULL, not TRUE, so
the early return does **not** fire and a NULL-channel insert falls through to `consume_quota`
and can raise `vision_analysis_daily_limit_reached`. Dormant only because nothing writes NULL,
which nothing enforces. Class: `guard_without_its_mirror`.

## Objects confirmed clear

- Views: only `coach_tool_invocations_v`, no channel reference
- RLS policies: 4 on the table, none reference channel
- `restore-user-snapshot` / `daily-snapshot` / `morning-alert` contain **zero** `channel`
  tokens — which is why a channel-keyed grep cannot see them. Their board citations
  (`restore-user-snapshot:254`, `daily-snapshot:61`) are **correct**, not rotted.

## Consequence for slice 4 design

Either (a) exclude `delete_account_attempt` at readers 1-5 in the same batch, or (b) record
the attempt outside `ai_coach_interactions`. Option (b) must preserve the existing
`ON DELETE CASCADE` chain (`ai_coach_interactions.user_id → users.id → auth.users.id`) —
the board is explicit that a no-FK design is a DPDP regression on the erasure endpoint.
Reader 4 alone makes option (a) require a **migration** (changing the RPC), which is a live
apply needing its own §4.3 authorization.
