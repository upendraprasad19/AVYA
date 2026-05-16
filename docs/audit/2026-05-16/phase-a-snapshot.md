# Phase A · Live Cloud Snapshot — 2026-05-16

Project: `dedsavbjuwgarrhphgnl` (fitness app account `myfitnessjourney1988@gmail.com`).
Snapshot time: 2026-05-16 (live MCP query results below).

## Tables (46 — matches CLAUDE.md §7 count)

## Row counts (live `pg_stat_user_tables.n_live_tup`)

Sorted by row count desc. **14 tables with 0 rows highlighted — primary audit targets.**

| Table | Row count | Notes |
|---|---:|---|
| food_database | 1431 | V2 expansion shipped (CLAUDE.md §18) |
| client_errors | 739 | Telemetry sink — healthy volume |
| daily_quotes | 365 | Test #9 morning-quote experiment, NOT wired (CLAUDE.md §7 "Deferred") |
| workout_log_sets | 221 | |
| memory_embeddings | 137 | Semantic retrieval Phase A accumulating |
| scheduled_workouts | 112 | |
| workout_log_exercises | 72 | |
| user_daily_snapshots | 30 | |
| ai_coach_interactions | 27 | |
| template_exercises | 18 | |
| water_logs | 13 | |
| rank_ladder | 11 | Reference table — matches 11-rung ladder |
| weight_logs | 11 | |
| workout_schedule_completions | 11 | |
| nutrition_logs | 8 | |
| workout_logs | 8 | |
| nutrition_log_items | 7 | |
| user_stat_snapshots | 6 | |
| coach_memory | 4 | |
| rank_promotions | 4 | |
| streaks | 4 | |
| subscriptions | 4 | |
| user_profile | 4 | |
| user_progress | 4 | |
| users | 4 | 4 test accounts |
| workout_templates | 4 | |
| notifications_inbox | 3 | |
| promo_codes | 3 | |
| account_deletion_log | 2 | DPDP §17 hard-delete audit trail (2 deletions) |
| user_custom_exercises | 2 | |
| user_preferences | 2 | |
| daily_steps | 1 | |
| **body_measurements** | **0** | **RED FLAG — UI logs measurements; Hive has them; sync gap?** |
| **community_reviews** | **0** | RED FLAG — submissions/review feature; possibly low usage |
| **exercise_library** | **0** | EXPECTED — app reads bundled JSON, cloud table is reference only (verify intent) |
| **food_corrections** | **0** | Possibly low usage |
| **progress_photos** | **0** | PRO-only, low tester usage expected |
| **promo_code_uses** | **0** | RED FLAG — 3 promo codes exist but never redeemed? Or never written? |
| **referral_codes** | **0** | RED FLAG — founder generated codes during Test #2; should be ≥1 |
| **referral_redemptions** | **0** | EXPECTED (paired with referral_codes=0) |
| **saved_diet_plans** | **0** | RED FLAG — Hive has them; `_syncSavedDietPlan` exists; sync gap? |
| **sleep_logs** | **0** | RED FLAG — sleep tracking is core feature; Hive has them; sync gap? |
| **telegram_connections** | **0** | EXPECTED — Telegram bot is separate project (CLAUDE.md §2) |
| **user_custom_foods** | **0** | RED FLAG — Hive has them; should sync via `_syncCustomFoods` |
| **user_saved_meals** | **0** | RED FLAG — Hive has them; sync via `_syncSavedMeals`; gap? |
| **video_renders** | **0** | EXPECTED — video-share deferred (CLAUDE.md §7) |

**Initial red-flag list (subset to verify in Phase B):**
- `body_measurements` — measurement-log sync gap?
- `promo_code_uses` — redemption write missing?
- `referral_codes` — referral-code generator not syncing?
- `saved_diet_plans` — diet-plan save not syncing?
- `sleep_logs` — sleep-log sync gap?
- `user_custom_foods` — custom-food create not syncing?
- `user_saved_meals` — saved-meal create not syncing?

These look like a single class of bug: post-Test-#11 fan-out gap. They're exactly the writer-not-firing pattern that Test #11 / Test #12.8 caught in other tables. Worth flagging to Agent 4 (sync fan-out + restore completeness).

## Column metadata

Raw JSON snapshot at `docs/audit/2026-05-16/db-columns-raw.json` (97 KB).
Schema: `[{table_name, column_name, data_type, is_nullable, column_default}]` for every column in every public table.
