---
bug_id: a17bc3
date: 2026-05-16
batch: APK Test #16.1 (Agent B — chat duplication)
status: in_progress
symptom: Founder's `ai_coach_interactions` table shows 6 rows for the same `user_message='curd 200gms whey 1.5 scoops cashew 6'` (3 timestamps × 2 channels). Each "Analyze with AI" tap during Gemini 502 storm produced (a) a Hive `coach_*` row, (b) a server-side placeholder row (channel=food_text_analysis, model_used=pending), and (c) a sync-time orphan row (channel=in_app_orphan). No client-side circuit breaker — user can tap retry indefinitely and each tap fans out to 3 cloud rows.
concept: ai_coach_interactions_dedup
sot_registry_entry: ai_coach_interactions_writer
writers:
  - { file: supabase/functions/ai-proxy/index.ts, method: food_text_analysis_reservation_insert, line: 208 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: saveUserMessagePending, line: 522 }
  - { file: lib/core/services/sync/sync_coach.dart, method: _syncCoachInteractions, line: 67 }
readers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: ChatHistoryNotifier.build, line: 1 }
hive_key_prefix: "coach_"
hive_key_formula: "coach_<created_at_ms>"
sync_methods: [_syncCoachInteractions]
restore_methods: [_restoreCoachInteractions]
cloud_table: ai_coach_interactions
cloud_columns: [user_id, user_message, channel, model_used, created_at]
contract_test_path: test/ai_coach/coach_writer_dedup_test.dart
ist_handling: []
provider_invalidations: [chatHistoryProvider]
telemetry_op_types:
  success: [coach_writer_dedup_hit, ai_proxy_food_text_dedup_hit, circuit_breaker_block]
  failure: []
cross_account_guard: "user-scoped Hive (coachBox) — already guarded by HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "coachBox.put.*without dedup check", absent: false }
proposed_fix: |
  4-layer defense:
  (1) Client `saveUserMessagePending` adds a 60s dedup window keyed on
      (user_message, mode). If a recent non-failed entry exists, return
      its key instead of creating a new one.
  (2) Server `ai-proxy` food_text_analysis branch SELECTs existing
      `(user_id, channel, user_message, model_used=pending)` row in
      last 60s before INSERT; UPDATEs `created_at` instead of new INSERT.
  (3) One-shot migration `068_cleanup_pending_chat_duplicates.sql`
      deletes redundant `model_used='pending'` rows older than 30 days,
      keeping earliest per `(user_id, user_message, channel)`. Verified
      live `pending` count in last 5 min = 0 (safe to clean).
  (4) Front-of-chat retry circuit breaker on `AiBreakdownNotifier`:
      after 3 consecutive 502/503/504 for the same message, block 4th
      attempt with "AI overloaded — try again in 5 minutes" inline.
      Counter is in-memory only (not Hive persisted) so app restart
      clears the block.
regression_test_planned:
  - test/ai_coach/coach_writer_dedup_test.dart
  - test/ai_coach/circuit_breaker_test.dart
  - test/contracts/cleanup_pending_migration_safety_test.dart
---
# Body

## Symptom

Cloud query for founder's account:

```
SELECT created_at, channel, model_used
FROM ai_coach_interactions
WHERE user_message='curd 200gms whey 1.5 scoops cashew 6'
ORDER BY created_at;
-- 6 rows: 3 timestamps × {food_text_analysis | in_app_orphan}
-- all model_used='pending', tokens_used=0
```

Founder tapped "Analyze with AI" 3 times during a Gemini 502 storm. The
4-attempt retry loop in `SupabaseService.retryColdStart`
(`[2000, 6000, 12000]` ms = ~20s) bounded each tap. Each tap still:

1. Wrote a Hive `coach_<ms>` row via `saveUserMessagePending` (no dedup
   check — every tap minted a fresh row).
2. `ai-proxy` `food_text_analysis` branch INSERTed a placeholder row
   `(channel='food_text_analysis', model_used='pending')` before
   calling Gemini. Gemini returned 502 — placeholder never updated.
3. Next `SyncService.syncOnAppOpen` run copied the Hive row to cloud
   as `(channel='in_app_orphan', model_used='pending')` — by design,
   since the Hive row had no UUID `id` field (placeholder row IDs
   only ever flow server→server).

3 taps × 2 distinct channel writes = 6 phantom rows.

UI surface: `ChatHistoryNotifier` renders coachBox `coach_*` keys; the
3 Hive rows show as 3 ghosted "pending" bubbles in chat scroll.

## Root cause (drift class)

Writer/reader drift at the **deduplication contract layer**. The chat
channel already has 30s server-side dedup (`ai-proxy` line 488), but:

- `food_text_analysis` branch (line 208) was added later and skipped
  the dedup pattern.
- Client `saveUserMessagePending` was never duped — assumption was
  "the user is the dedup gate." That assumption breaks during
  Gemini-storm retries.
- `_syncCoachInteractions` already skips UUID-having entries (audit
  2026-05-12 P2-B) but `coach_*` Hive keys never carry a UUID until
  the server response lands.

## Fix details

### Layer 1 — Client dedup (`saveUserMessagePending`)

Before minting a new key, scan `coachBox` for any `coach_*` entry whose
`user_message` matches AND `mode` matches AND `created_at` is within
60 seconds AND `failed != true`. If found, return existing key. Else
mint new.

Same-message-after-60s → 2 entries (intentional — user re-tries an
hour later is a legitimate new turn).

Same-message-within-60s → 1 entry (the spam case).

Failed entries are exempt from dedup so retries after explicit
"Retry" tap still work.

### Layer 2 — Server dedup (`ai-proxy` food_text_analysis)

Before the placeholder INSERT, SELECT existing
`(user_id=$1, channel='food_text_analysis', user_message=$2,
model_used='pending', created_at >= now()-60s)`. If found, UPDATE its
`created_at = now()` (refreshing the slot for the live request) and
reuse its id. Else INSERT new.

The Postgres trigger `trg_food_text_rate_limit` (migration 024) fires
on every INSERT — by collapsing the duplicate INSERT we ALSO avoid
artificially burning rate-limit slots.

### Layer 3 — Migration 068 (one-shot cleanup)

`DELETE FROM ai_coach_interactions
 WHERE model_used='pending'
   AND created_at >= now() - interval '30 days'
   AND created_at < now() - interval '5 minutes'
   AND id NOT IN (
     SELECT min(id) FROM ai_coach_interactions
     WHERE model_used='pending'
       AND created_at >= now() - interval '30 days'
     GROUP BY user_id, user_message, channel
   );`

Safety:
- Live `pending` count in last 5 min = 0 (verified via MCP execute_sql).
- 30-day upper bound prevents accidental deletion of historical
  research data.
- 5-min lower bound prevents collision with in-flight requests.
- Keeps EARLIEST `min(id)` per group, not most recent — earliest is
  the only one whose `created_at` reflects the first user intent.

Cloud delta: 18 pending rows → 8 (one per distinct group).

### Layer 4 — Circuit breaker (`AiBreakdownNotifier`)

In-memory `Map<String, int>` keyed on `text` tracks consecutive
service-error counts (502/503/504/`isServiceError`). On 3rd consecutive
fail, 4th attempt for the same text returns immediately with
"AI overloaded — try again in 5 minutes" without calling the Edge
Function. Counter is reset on:
- Any success for that text.
- `clear()` (user clears the breakdown card).
- App restart (in-memory, not Hive).

5-minute auto-reset via a `DateTime` timestamp on each counter; if
`now() - lastFailAt > 5min`, the counter resets even without a clear.

## Verification

- `test/ai_coach/coach_writer_dedup_test.dart` — write same message
  twice within 60s → 1 row; outside 60s → 2 rows.
- `test/ai_coach/circuit_breaker_test.dart` — 3 service errors for
  same text → 4th blocked client-side; success resets counter.
- `test/contracts/cleanup_pending_migration_safety_test.dart` —
  migration 068 source contains `interval '30 days'` AND
  `interval '5 minutes'` AND a `GROUP BY user_id, user_message,
  channel`.

## Risks

- **30-day bound** — historical pending rows older than 30 days are
  not touched. Acceptable: cloud query showed all 18 pending rows are
  within last 30 days. Older rows would be valuable forensics; we
  preserve them.
- **Trigger interaction** — `trg_food_text_rate_limit` counts every
  INSERT into `ai_coach_interactions`. The new server-side dedup
  bypasses one INSERT per duplicate retry — net: the user's daily
  cap counts fewer slots when they spam-retry the same message.
  This is the correct behaviour (the duplicates were not legitimate
  uses of the daily quota).
- **Layer 2 race window** — between the SELECT and UPDATE, a
  concurrent retry could SELECT the same row. Both end up UPDATEing
  the same row — idempotent. No data corruption; worst case is one
  extra UPDATE.
- **Layer 4 — 5-min auto-reset** — if Gemini is still down at the
  5-min mark, user re-attempt resets the counter and they get
  another 3 retries. Acceptable: better than permanently blocking
  the chat surface; the server-side dedup (Layer 2) still collapses
  duplicate INSERTs even if Layer 4 lets a tap through.

## SoT impact

`ai_coach_interactions_writer` SoT (see `docs/sot_registry.yaml`)
gains 2 new contract-test pins:
- coach_writer_dedup_test
- circuit_breaker_test
Plus the migration safety test.

No new writer or reader added — the existing writers are tightened.
