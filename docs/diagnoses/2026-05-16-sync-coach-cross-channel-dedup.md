---
bug_id: 2026-05-16-sync-coach-cross-channel-dedup
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.5.3
status: fixed
regression_test: test/contracts/sync_coach_cross_channel_dedup_test.dart
---

## Symptom

`ai_coach_interactions` accumulated paired duplicate rows for one logical user turn. Live audit on 2026-05-16 found **8 cross-channel pairs** spanning 2026-05-11 → 2026-05-15. Each pair: same `user_id`, same `user_message`, close `created_at` (within 19s on the worst case), but DIFFERENT `channel` — one `food_text_analysis` (server-side, written by ai-proxy when user used Nutrition AI Text tab) and one `in_app_orphan` (client-side, written by `_syncCoachInteractions` when user pasted same text into AI Coach chat).

Founder's typical flow that triggered this: paste a meal description ("curd 200gms whey 1.5 scoops cashew 6") into the AI Coach chat to ask "what's this in nutrition?", then ~15-30 seconds later paste the same text into the Nutrition AI Text logger to actually log it. Both surfaces produce an `ai_coach_interactions` row, on different channels, server can't see the client-orphan path → dupe.

Analytics impact: cross-channel pairs inflated row counts ~20% during testing days. Not bug-critical for users, but contaminates "what % of chat turns hit food_text_analysis" measurements.

## Root cause

Test #12 / P2-B fix already deprecated the client orphan path by default: when Hive `coach_<ms>` entries carry a real UUID `id` (server-issued), the client skips re-upserting them. But local-only entries (where the AI Coach chat had a network error mid-turn and only the local Hive write succeeded) still hit the orphan upsert at `sync_coach.dart:91`.

The orphan upsert wrote `channel='in_app_orphan'` with a deterministic v5 UUID — that's a fresh row, NOT a merge with any server-side `app` / `food_text_analysis` row that may have landed for the same user message via a different surface.

The server-side dedup window (`ai-proxy/index.ts:222-254`) only catches intra-channel — it can't see the client's orphan write path at all. So the two writes raced past each other and both landed.

## Fix

`lib/core/services/sync/sync_coach.dart` `_syncCoachInteractions`: before the orphan upsert, SELECT for ANY row from this user with matching `user_message` within the last 5 minutes:

```dart
final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
final existing = await _supabase.client
    .from('ai_coach_interactions')
    .select('id, channel, created_at')
    .eq('user_id', userId)
    .eq('user_message', userMsg.substring(0, userMsg.length > 500 ? 500 : userMsg.length))
    .gte('created_at', cutoff.toIso8601String())
    .limit(1)
    .maybeSingle();
if (existing != null) {
  // Server already has a row for this turn — drop orphan write.
  // Stamp Hive entry with cloud id so future cold restores collapse cleanly.
  final cloudId = existing['id'] as String?;
  if (cloudId != null && cloudId.isNotEmpty) {
    final updated = Map<String, dynamic>.from(entry);
    updated['id'] = cloudId;
    await coachBox.put(key, updated);
  }
  continue;
}
```

Window choice: 5 minutes. Long enough to catch the user's "ask coach → log via Nutrition tab" double-paste (typical 15-90s gap). Short enough that an intentional repeat-log of identical meal text the next morning goes through cleanly.

Hive entry id-stamping: when we drop the orphan write, we stamp the Hive entry's `id` field with the cloud row's UUID. This makes the next cold-restore round-trip collapse cleanly via the existing `_restoreCoachInteractions` `coach_<ts>` key derivation (Test #12.8 / Bug #1 pattern). Without this stamp, restore would create a new sibling Hive key and we'd have the inverse problem on the next sync.

## Verification

- New contract test: `test/contracts/sync_coach_cross_channel_dedup_test.dart` (4 sub-tests).
  - `method SELECTs from ai_coach_interactions before orphan upsert` ✓
  - `dedup window is bounded (5 minute lookback)` ✓
  - `on dedup hit, skip orphan upsert via continue` ✓
  - `on dedup hit, Hive entry is stamped with cloud id` ✓
- All 4/4 PASS via `flutter test`.
- The 8 historical cross-channel pairs were relabeled in E.17 SQL backfill — those `model_used='pending'` rows are now `failed_legacy` (server-side rows still have `pending` if not failed, orphan rows became failed_legacy). Cross-channel pairs themselves remain as historical noise; the fix prevents new ones.

## Follow-ups

- A future hardening could deprecate the orphan path entirely (the comment at `sync_coach.dart:60-66` already gestures at this option). Reserved for a future batch — the 5-min dedup gives the server enough time to win the race in all observed cases.
- The `user_message` lookup uses `.eq('user_message', ...)` with a 500-char truncation. If a user paste is >500 chars AND the truncated prefix matches an unrelated turn, we'd false-positive skip an orphan. Acceptable: 500 chars is plenty to disambiguate (the matching is on a unique-by-user time window).

## Class lesson

Cross-surface dedup must consider all-pairs writer surfaces, not just within one surface. When N writer paths converge on one analytics table, every write site needs a SELECT-before-write gate that scopes to the table (not just the channel). Test #16.1 / Bug B added intra-channel dedup; that wasn't enough; the same audit cycle should have flagged cross-channel as the next class. Codify: every analytics table with >1 writer surface needs an "all-pairs dedup proof" item in the audit checklist.
