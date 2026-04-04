# MCP-Orchestrated E2E Tests

Automated end-to-end tests for the ICANBEFITTER webapp using Claude Code's MCP tools.

## How it works

Each script file describes a sequence of frontend actions (via Claude Preview MCP) paired with backend verification queries (via Supabase MCP). Claude Code executes both sides and reports pass/fail for each step.

## Prerequisites

1. **Build the webapp:**
   ```bash
   flutter build web
   ```

2. **Start the dev server:**
   ```bash
   python -m http.server 8080 --directory build/web
   ```

3. **Ensure test user exists:** `qa@icanbefitter.com` / `QA_Test_2024!`

## Running Tests

Ask Claude Code to run any script:

```
Run the E2E test in testing/e2e/01_auth_onboarding.md
```

Or run all scripts in sequence:

```
Run all E2E tests in testing/e2e/ in order
```

## Scripts

| # | Script | Tests | Coverage |
|---|--------|-------|----------|
| 01 | auth_onboarding.md | 5 | Sign-in, onboarding, Supabase sync, sign-out, re-login restore |
| 02 | home_screen.md | 5 | Greeting, calendar, nutrition snapshot, weight sparkline, PRs |
| 03 | nutrition_sync.md | 5 | Food search, meal logging, weight log, water, Supabase sync |
| 04 | ai_coach.md | 6 | Free chat, response render, context, limits, prompt chips, pgvector |
| 05 | profile_edit.md | 4 | Edit weight, goal, BMR recalc, name sync |
| 06 | train_flow.md | 5 | Phase plan, week selector, exercises, template builder, PRO gate |

## Test Data Reset

Before a full test run, reset the test user's Supabase data:

```sql
-- Run via Supabase MCP (execute_sql, project dedsavbjuwgarrhphgnl)
DELETE FROM user_daily_snapshots WHERE user_id = '<USER_ID>';
DELETE FROM ai_coach_interactions WHERE user_id = '<USER_ID>';
DELETE FROM memory_embeddings WHERE user_id = '<USER_ID>';
DELETE FROM streaks WHERE user_id = '<USER_ID>';
DELETE FROM weight_logs WHERE user_id = '<USER_ID>';
DELETE FROM nutrition_logs WHERE user_id = '<USER_ID>';
DELETE FROM workout_logs WHERE user_id = '<USER_ID>';
DELETE FROM user_progress WHERE user_id = '<USER_ID>';
DELETE FROM user_profile WHERE user_id = '<USER_ID>';
DELETE FROM user_preferences WHERE user_id = '<USER_ID>';
UPDATE users SET onboarding_completed = false, full_name = null
WHERE id = '<USER_ID>';
```

Then sign out on the webapp to clear Hive (IndexedDB on web).
