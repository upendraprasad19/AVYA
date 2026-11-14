-- Migration 055: add WITH CHECK to 35 UPDATE / ALL policies (H-29)
--
-- closes-finding: H-29 (audit 2026-05-11)
--
-- Background:
-- Postgres RLS policies with `cmd=UPDATE` (or `cmd=ALL`) require BOTH a
-- USING expression (which rows can be selected for update) AND a WITH
-- CHECK expression (which rows the result of update must satisfy).
-- When WITH CHECK is omitted, it defaults to TRUE — meaning a user can
-- UPDATE their own row's user_id to point at someone else's UUID,
-- effectively "transferring" the row to another user. Combined with
-- referential integrity, this can poison cross-user data.
--
-- Audit (run 2026-05-11 via MCP): 35 policies missing WITH CHECK on
-- public.* tables. All 35 share the pattern `USING (auth.uid() = <fk_col>)`
-- with no WITH CHECK. Two also use an EXISTS subquery (nutrition_log_items
-- + template_exercises) — same fix shape: mirror the USING expr into
-- WITH CHECK.
--
-- Fix: ALTER each policy with `WITH CHECK (<same as USING>)`. Postgres 15+
-- supports `ALTER POLICY ... WITH CHECK (...)`.
--
-- ICANBEFITTER advisor count (H-29) said "12 tables". Actual prod state is
-- 35 policies. Audit doc updated to reflect reality.

BEGIN;

-- ──────────────────────────────────────────────────────────────────────
-- Standard pattern: WITH CHECK = same as USING (auth.uid() = user_id)
-- ──────────────────────────────────────────────────────────────────────

ALTER POLICY ai_coach_interactions_update_own
  ON public.ai_coach_interactions
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY body_measurements_update_own
  ON public.body_measurements
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY users_update_own_coach_memory
  ON public.coach_memory
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY "Users can update own review"
  ON public.community_reviews
  WITH CHECK (auth.uid() = reviewer_id);

ALTER POLICY daily_steps_update_own
  ON public.daily_steps
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY food_corrections_update_own
  ON public.food_corrections
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY memory_embeddings_own
  ON public.memory_embeddings
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY "Users update own notifications"
  ON public.notifications_inbox
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY nutrition_logs_update_own
  ON public.nutrition_logs
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY progress_photos_update_own
  ON public.progress_photos
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY "Users upsert own diet plan"
  ON public.saved_diet_plans
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY scheduled_workouts_update_own
  ON public.scheduled_workouts
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY sleep_logs_update_own
  ON public.sleep_logs
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY streaks_update_own
  ON public.streaks
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY telegram_connections_update_own
  ON public.telegram_connections
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY user_custom_exercises_update_own
  ON public.user_custom_exercises
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY user_custom_foods_update_own
  ON public.user_custom_foods
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY user_daily_snapshots_update_own
  ON public.user_daily_snapshots
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY user_preferences_update_own
  ON public.user_preferences
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY user_profile_update_own
  ON public.user_profile
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY user_progress_update_own
  ON public.user_progress
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY user_saved_meals_update_own
  ON public.user_saved_meals
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY uss_self_update
  ON public.user_stat_snapshots
  WITH CHECK (auth.uid() = user_id);

-- users table: column is `id`, not `user_id`
ALTER POLICY users_update_own
  ON public.users
  WITH CHECK (auth.uid() = id);

ALTER POLICY video_renders_update_own
  ON public.video_renders
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY water_logs_update_own
  ON public.water_logs
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY weight_logs_update_own
  ON public.weight_logs
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY wle_update_own
  ON public.workout_log_exercises
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY workout_log_sets_update_own
  ON public.workout_log_sets
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY workout_logs_update_own
  ON public.workout_logs
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY wsc_update_own
  ON public.workout_schedule_completions
  WITH CHECK (auth.uid() = user_id);

ALTER POLICY workout_templates_update_own
  ON public.workout_templates
  WITH CHECK (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────────────────
-- EXISTS-subquery pattern: parent ownership check, same shape
-- ──────────────────────────────────────────────────────────────────────

ALTER POLICY nutrition_log_items_update_own
  ON public.nutrition_log_items
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.nutrition_logs nl
      WHERE nl.id = nutrition_log_items.log_id
        AND nl.user_id = auth.uid()
    )
  );

ALTER POLICY template_exercises_update_own
  ON public.template_exercises
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.workout_templates wt
      WHERE wt.id = template_exercises.template_id
        AND wt.user_id = auth.uid()
    )
  );

COMMIT;
