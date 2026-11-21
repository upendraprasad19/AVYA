# APK +27 install verification — Upendra fresh sign-in

**Captured before uninstall:** 2026-05-16 (Asia/Calcutta)
**user_id:** `d7a67a37-0b05-4f0a-b13c-388bff3cb59b`
**email:** `upendraprasad19@gmail.com`

## Pre-install cloud baseline

| Surface | Count | Notes |
|---|---:|---|
| `coach_memory.coach_notes` | **NULL** | ⚠️ The F3-1.1 bug exactly. After ~5 min of AI coach use on +27, this should become non-NULL. |
| `coach_memory.coach_notes` length | 0 | |
| `ai_coach_interactions` total rows | 21 | 8 with real Gemini responses · 8 failed_legacy (E.17 backfill) · 5 other |
| `memory_embeddings` (semantic retrieval) | 127 | Pre-existing — should restore on first launch |
| `workout_logs` | 8 | Should restore via `_restoreWorkoutLogs` |
| `workout_log_exercises` | 72 | Should restore via `_restoreExerciseLogs` (now keyed via canonical `WorkoutWriteService.exlogKey`) |
| `workout_log_sets` | 221 | Should restore via per-set fetch |
| `nutrition_logs` | 8 | |
| `weight_logs` | 10 | |
| `water_logs` | 12 | |
| `scheduled_workouts` | 28 | |
| `workout_templates` | 4 | |
| `streak_weeks` | 3 | |
| `custom_exercises` | 2 | Should appear in Swap sheet (Test #16 / Bug 5e35aaf fix) |
| `saved_diet_plans` | 0 | If user saves one post-install, will sync via `_syncSavedDietPlan` (E.10 path verified) |
| `referral_codes` | 0 | New restore method `_restoreReferralCodes` (E.10) will activate next time founder generates a code |
| `rank_promotions` | 1 | Should restore on first launch |
| `client_errors` last 1h | 0 | Clean baseline |
| `client_errors` for Upendra 24h | 0 | Clean baseline |
| `cron_call_log` rows | 0 | Migration 068 table empty (per-cron logging is a follow-up batch deliverable; the table exists but the cron Edge Functions don't INSERT to it yet) |

## What to look for after sign-in

### CRITICAL — F3-1.1 verification (AI coach memory roundtrip)
1. After fresh install + sign-in, open AI Coach.
2. Send 3-5 messages over ~5-10 min ("how's my progress this week?" / "what should I eat today?" / etc.).
3. Wait ~2 min after the last message (gives `daily-snapshot` cron or the chat success path time to populate Hive `coaching_notes`, then the next mutation fires `syncCoachMemoryNow` which now projects to `coach_memory.coach_notes`).
4. I'll re-query the same baseline — `coach_notes` should now be non-NULL with a non-zero length. **That validates F3-1.1.**

### Restore-completeness (should all "just work")
- Open Home → workouts count should match 8 (existing workouts visible)
- Open Train → 4 templates visible · 28 scheduled workouts on calendar
- Open Profile → streak shows 3 weeks
- Search "Single Leg Front" in Swap sheet → "Single Leg Front Lever" custom exercise should appear (Test #16 5e35aaf fix)
- AI Coach scrolling history → 21 historical conversations + semantic retrieval pulling from 127 embeddings

### Things that USED to break, should now work
- After ~5 min, no fresh `client_errors` rows for Upendra (the audit closed the 401-storm class)
- Schedule edits (swap exercise / mark completed) → AI coach immediately reflects new state (F11-C11-2 fix)
- Photo upload in AI Coach as free user → shows paywall sheet (F8.1 fix) — only if currently free
- Sign-up checkbox + login as Upendra → check `users.terms_accepted_at` becomes non-NULL within seconds (F3-1.2 DPDP fix)

## Post-install verification query (rerun later)

```sql
SELECT
  (SELECT coach_notes IS NOT NULL FROM coach_memory WHERE user_id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b') AS coach_notes_now_populated,
  (SELECT length(coach_notes) FROM coach_memory WHERE user_id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b') AS coach_notes_len_now,
  (SELECT terms_accepted_at FROM users WHERE id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b') AS terms_accepted_at,
  (SELECT COUNT(*) FROM client_errors WHERE user_id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b' AND created_at > '2026-05-16') AS fresh_errors_today;
```

Run when convenient. If `coach_notes_now_populated = true` → audit's headline fix validated live.
