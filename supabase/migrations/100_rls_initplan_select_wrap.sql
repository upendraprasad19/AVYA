-- Intent: OPT-A — wrap auth.uid() → (select auth.uid()) in all 137 RLS policies that reference it (initplan perf) + consolidate the saved_diet_plans duplicate SELECT (multiple_permissive_policies). Clears 137 auth_rls_initplan + 5 multiple_permissive advisories. Behavior-preserving (0 jwt/role/restrictive/asymmetric policies).
-- Destructive?: yes   -- DROPs one redundant policy (saved_diet_plans "Users see own diet plan"); the ALL policy on that table still covers SELECT, so no access is lost. Catastrophic-tier (touches every RLS policy) → dry-run + founder sign-off before prod apply.
-- Rollback strategy: inline   -- reverse DDL block at end of file (re-create the dropped SELECT + un-wrap recipe)
-- Linked diagnose-doc: e6b1a4
-- ============================================================
-- OPT-A — RLS initplan wrap (branch: opt-a-rls-initplan, 2026-07-07)
--
-- WHY: each flagged policy calls auth.uid() which Postgres re-evaluates PER ROW.
-- Wrapping as (select auth.uid()) makes the planner treat it as an initplan —
-- evaluated ONCE per query. Supabase-recommended; behavior-identical. Biggest
-- query-CPU win at scale; touches the last privacy fence, so catastrophic-tier.
--
-- SHAPE: 137 policies reference auth.uid() → 136 are ALTERed (wrapped) + 1 (the
-- redundant saved_diet_plans SELECT) is DROPped = 137 affected. The 136 ALTERs
-- break down as 128 simple + 8 correlated-EXISTS (the 129th simple policy is the
-- dropped saved_diet_plans SELECT).
-- GENERATION: the 136 ALTER POLICY statements below were emitted directly from
-- live pg_policies via a blind textual auth.uid() → (select auth.uid())
-- substitution (per-cmd clause structure: USING for SELECT/DELETE, WITH CHECK
-- for INSERT, both for UPDATE/ALL) — zero hand-transcription. Live ground truth
-- (2026-07-07): 137 policies reference auth.uid(); 129 simple + 8 correlated
-- EXISTS (nutrition_log_items ×4, template_exercises ×4); 0 already-wrapped,
-- 0 auth.jwt()/auth.role() refs, 0 RESTRICTIVE, 0 asymmetric USING-vs-WITH-CHECK.
-- The saved_diet_plans SELECT ("Users see own diet plan") is EXCLUDED from the
-- ALTER set and DROPped in the consolidation step (its ALL sibling covers SELECT),
-- so there is no DROP-before-ALTER "policy not found" ordering hazard.
--
-- SAFETY GATE (run before prod apply, per the plan): per-policy A/B rollback-txn
-- leak check (user A vs user B) — see test/sql/rls_initplan_ab_verify.sql — plus
-- the perf advisor re-run (expect auth_rls_initplan 137 → ~0, multiple_permissive
-- 5 → 0). Live apply requires its own explicit founder go (§4.3).
-- ============================================================

BEGIN;

-- ── 136 initplan wraps (auth.uid() → (select auth.uid())) ──────────────────
ALTER POLICY "ai_coach_interactions_delete_own" ON public.ai_coach_interactions USING (((select auth.uid()) = user_id));
ALTER POLICY "ai_coach_interactions_insert_own" ON public.ai_coach_interactions WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "ai_coach_interactions_select_own" ON public.ai_coach_interactions USING (((select auth.uid()) = user_id));
ALTER POLICY "ai_coach_interactions_update_own" ON public.ai_coach_interactions USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "body_measurements_delete_own" ON public.body_measurements USING (((select auth.uid()) = user_id));
ALTER POLICY "body_measurements_insert_own" ON public.body_measurements WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "body_measurements_select_own" ON public.body_measurements USING (((select auth.uid()) = user_id));
ALTER POLICY "body_measurements_update_own" ON public.body_measurements USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "client_errors_insert_own" ON public.client_errors WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "client_errors_select_own" ON public.client_errors USING (((select auth.uid()) = user_id));
ALTER POLICY "users_insert_own_coach_memory" ON public.coach_memory WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "users_read_own_coach_memory" ON public.coach_memory USING (((select auth.uid()) = user_id));
ALTER POLICY "users_update_own_coach_memory" ON public.coach_memory USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "Users can insert own review" ON public.community_reviews WITH CHECK (((select auth.uid()) = reviewer_id));
ALTER POLICY "Users can read own reviews" ON public.community_reviews USING (((select auth.uid()) = reviewer_id));
ALTER POLICY "Users can update own review" ON public.community_reviews USING (((select auth.uid()) = reviewer_id)) WITH CHECK (((select auth.uid()) = reviewer_id));
ALTER POLICY "daily_steps_delete_own" ON public.daily_steps USING (((select auth.uid()) = user_id));
ALTER POLICY "daily_steps_insert_own" ON public.daily_steps WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "daily_steps_select_own" ON public.daily_steps USING (((select auth.uid()) = user_id));
ALTER POLICY "daily_steps_update_own" ON public.daily_steps USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "food_corrections_delete_own" ON public.food_corrections USING (((select auth.uid()) = user_id));
ALTER POLICY "food_corrections_insert_own" ON public.food_corrections WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "food_corrections_select_own" ON public.food_corrections USING (((select auth.uid()) = user_id));
ALTER POLICY "food_corrections_update_own" ON public.food_corrections USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "memory_embeddings_own" ON public.memory_embeddings USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "Users insert own notifications" ON public.notifications_inbox WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "Users see own notifications" ON public.notifications_inbox USING (((select auth.uid()) = user_id));
ALTER POLICY "Users update own notifications" ON public.notifications_inbox USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "nutrition_log_items_delete_own" ON public.nutrition_log_items USING ((EXISTS ( SELECT 1
   FROM nutrition_logs nl
  WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = (select auth.uid()))))));
ALTER POLICY "nutrition_log_items_insert_own" ON public.nutrition_log_items WITH CHECK ((EXISTS ( SELECT 1
   FROM nutrition_logs nl
  WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = (select auth.uid()))))));
ALTER POLICY "nutrition_log_items_select_own" ON public.nutrition_log_items USING ((EXISTS ( SELECT 1
   FROM nutrition_logs nl
  WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = (select auth.uid()))))));
ALTER POLICY "nutrition_log_items_update_own" ON public.nutrition_log_items USING ((EXISTS ( SELECT 1
   FROM nutrition_logs nl
  WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = (select auth.uid())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM nutrition_logs nl
  WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = (select auth.uid()))))));
ALTER POLICY "nutrition_logs_delete_own" ON public.nutrition_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "nutrition_logs_insert_own" ON public.nutrition_logs WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "nutrition_logs_select_own" ON public.nutrition_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "nutrition_logs_update_own" ON public.nutrition_logs USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "progress_photos_delete_own" ON public.progress_photos USING (((select auth.uid()) = user_id));
ALTER POLICY "progress_photos_insert_own" ON public.progress_photos WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "progress_photos_select_own" ON public.progress_photos USING (((select auth.uid()) = user_id));
ALTER POLICY "progress_photos_update_own" ON public.progress_photos USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "Users can see own promo uses" ON public.promo_code_uses USING (((select auth.uid()) = user_id));
ALTER POLICY "rank_promotions_insert_own" ON public.rank_promotions WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "rank_promotions_select_own" ON public.rank_promotions USING (((select auth.uid()) = user_id));
ALTER POLICY "Users can insert own referral code" ON public.referral_codes WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "Users can read own referral code" ON public.referral_codes USING (((select auth.uid()) = user_id));
ALTER POLICY "Users can read own redemptions" ON public.referral_redemptions USING ((((select auth.uid()) = referrer_id) OR ((select auth.uid()) = referee_id)));
ALTER POLICY "Users upsert own diet plan" ON public.saved_diet_plans USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "scheduled_workouts_delete_own" ON public.scheduled_workouts USING (((select auth.uid()) = user_id));
ALTER POLICY "scheduled_workouts_insert_own" ON public.scheduled_workouts WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "scheduled_workouts_select_own" ON public.scheduled_workouts USING (((select auth.uid()) = user_id));
ALTER POLICY "scheduled_workouts_update_own" ON public.scheduled_workouts USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "sleep_logs_delete_own" ON public.sleep_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "sleep_logs_insert_own" ON public.sleep_logs WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "sleep_logs_select_own" ON public.sleep_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "sleep_logs_update_own" ON public.sleep_logs USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "streaks_delete_own" ON public.streaks USING (((select auth.uid()) = user_id));
ALTER POLICY "streaks_insert_own" ON public.streaks WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "streaks_select_own" ON public.streaks USING (((select auth.uid()) = user_id));
ALTER POLICY "streaks_update_own" ON public.streaks USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "subscriptions_select_own" ON public.subscriptions USING (((select auth.uid()) = user_id));
ALTER POLICY "telegram_connections_delete_own" ON public.telegram_connections USING (((select auth.uid()) = user_id));
ALTER POLICY "telegram_connections_insert_own" ON public.telegram_connections WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "telegram_connections_select_own" ON public.telegram_connections USING (((select auth.uid()) = user_id));
ALTER POLICY "telegram_connections_update_own" ON public.telegram_connections USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "template_exercises_delete_own" ON public.template_exercises USING ((EXISTS ( SELECT 1
   FROM workout_templates wt
  WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = (select auth.uid()))))));
ALTER POLICY "template_exercises_insert_own" ON public.template_exercises WITH CHECK ((EXISTS ( SELECT 1
   FROM workout_templates wt
  WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = (select auth.uid()))))));
ALTER POLICY "template_exercises_select_own" ON public.template_exercises USING ((EXISTS ( SELECT 1
   FROM workout_templates wt
  WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = (select auth.uid()))))));
ALTER POLICY "template_exercises_update_own" ON public.template_exercises USING ((EXISTS ( SELECT 1
   FROM workout_templates wt
  WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = (select auth.uid())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM workout_templates wt
  WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = (select auth.uid()))))));
ALTER POLICY "user_custom_exercises_delete_own" ON public.user_custom_exercises USING (((select auth.uid()) = user_id));
ALTER POLICY "user_custom_exercises_insert_own" ON public.user_custom_exercises WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_custom_exercises_select_own" ON public.user_custom_exercises USING (((select auth.uid()) = user_id));
ALTER POLICY "user_custom_exercises_update_own" ON public.user_custom_exercises USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_custom_foods_delete_own" ON public.user_custom_foods USING (((select auth.uid()) = user_id));
ALTER POLICY "user_custom_foods_insert_own" ON public.user_custom_foods WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_custom_foods_select_own" ON public.user_custom_foods USING (((select auth.uid()) = user_id));
ALTER POLICY "user_custom_foods_update_own" ON public.user_custom_foods USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_daily_snapshots_delete_own" ON public.user_daily_snapshots USING (((select auth.uid()) = user_id));
ALTER POLICY "user_daily_snapshots_insert_own" ON public.user_daily_snapshots WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_daily_snapshots_select_own" ON public.user_daily_snapshots USING (((select auth.uid()) = user_id));
ALTER POLICY "user_daily_snapshots_update_own" ON public.user_daily_snapshots USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_preferences_delete_own" ON public.user_preferences USING (((select auth.uid()) = user_id));
ALTER POLICY "user_preferences_insert_own" ON public.user_preferences WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_preferences_select_own" ON public.user_preferences USING (((select auth.uid()) = user_id));
ALTER POLICY "user_preferences_update_own" ON public.user_preferences USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_profile_delete_own" ON public.user_profile USING (((select auth.uid()) = user_id));
ALTER POLICY "user_profile_insert_own" ON public.user_profile WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_profile_select_own" ON public.user_profile USING (((select auth.uid()) = user_id));
ALTER POLICY "user_profile_update_own" ON public.user_profile USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_progress_delete_own" ON public.user_progress USING (((select auth.uid()) = user_id));
ALTER POLICY "user_progress_insert_own" ON public.user_progress WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_progress_select_own" ON public.user_progress USING (((select auth.uid()) = user_id));
ALTER POLICY "user_progress_update_own" ON public.user_progress USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_saved_meals_delete_own" ON public.user_saved_meals USING (((select auth.uid()) = user_id));
ALTER POLICY "user_saved_meals_insert_own" ON public.user_saved_meals WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "user_saved_meals_select_own" ON public.user_saved_meals USING (((select auth.uid()) = user_id));
ALTER POLICY "user_saved_meals_update_own" ON public.user_saved_meals USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "uss_self_delete" ON public.user_stat_snapshots USING (((select auth.uid()) = user_id));
ALTER POLICY "uss_self_insert" ON public.user_stat_snapshots WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "uss_self_read" ON public.user_stat_snapshots USING (((select auth.uid()) = user_id));
ALTER POLICY "uss_self_update" ON public.user_stat_snapshots USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "users_delete_own" ON public.users USING (((select auth.uid()) = id));
ALTER POLICY "users_insert_own" ON public.users WITH CHECK (((select auth.uid()) = id));
ALTER POLICY "users_select_own" ON public.users USING (((select auth.uid()) = id));
ALTER POLICY "users_update_own" ON public.users USING (((select auth.uid()) = id)) WITH CHECK (((select auth.uid()) = id));
ALTER POLICY "video_renders_delete_own" ON public.video_renders USING (((select auth.uid()) = user_id));
ALTER POLICY "video_renders_insert_own" ON public.video_renders WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "video_renders_select_own" ON public.video_renders USING (((select auth.uid()) = user_id));
ALTER POLICY "video_renders_update_own" ON public.video_renders USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "water_logs_delete_own" ON public.water_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "water_logs_insert_own" ON public.water_logs WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "water_logs_select_own" ON public.water_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "water_logs_update_own" ON public.water_logs USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "weight_logs_delete_own" ON public.weight_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "weight_logs_insert_own" ON public.weight_logs WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "weight_logs_select_own" ON public.weight_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "weight_logs_update_own" ON public.weight_logs USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "wle_delete_own" ON public.workout_log_exercises USING (((select auth.uid()) = user_id));
ALTER POLICY "wle_insert_own" ON public.workout_log_exercises WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "wle_select_own" ON public.workout_log_exercises USING (((select auth.uid()) = user_id));
ALTER POLICY "wle_update_own" ON public.workout_log_exercises USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "workout_log_sets_delete_own" ON public.workout_log_sets USING (((select auth.uid()) = user_id));
ALTER POLICY "workout_log_sets_insert_own" ON public.workout_log_sets WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "workout_log_sets_select_own" ON public.workout_log_sets USING (((select auth.uid()) = user_id));
ALTER POLICY "workout_log_sets_update_own" ON public.workout_log_sets USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "workout_logs_delete_own" ON public.workout_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "workout_logs_insert_own" ON public.workout_logs WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "workout_logs_select_own" ON public.workout_logs USING (((select auth.uid()) = user_id));
ALTER POLICY "workout_logs_update_own" ON public.workout_logs USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "wsc_delete_own" ON public.workout_schedule_completions USING (((select auth.uid()) = user_id));
ALTER POLICY "wsc_insert_own" ON public.workout_schedule_completions WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "wsc_select_own" ON public.workout_schedule_completions USING (((select auth.uid()) = user_id));
ALTER POLICY "wsc_update_own" ON public.workout_schedule_completions USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "workout_templates_delete_own" ON public.workout_templates USING (((select auth.uid()) = user_id));
ALTER POLICY "workout_templates_insert_own" ON public.workout_templates WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "workout_templates_select_own" ON public.workout_templates USING (((select auth.uid()) = user_id));
ALTER POLICY "workout_templates_update_own" ON public.workout_templates USING (((select auth.uid()) = user_id)) WITH CHECK (((select auth.uid()) = user_id));

-- ── saved_diet_plans multiple_permissive consolidation ─────────────────────
-- The ALL policy "Users upsert own diet plan" (altered above) already gates
-- SELECT via its USING clause, so the dedicated SELECT policy is redundant and
-- is the sole source of the 5 multiple_permissive_policies warnings. Dropping
-- it preserves all 4 verbs (INSERT/UPDATE/DELETE/SELECT) via the ALL policy.
DROP POLICY "Users see own diet plan" ON public.saved_diet_plans;

COMMIT;

-- ── Rollback (inline) — LITERAL reverse DDL (no live snapshot needed) ───────
-- To revert: run block (1) then (2) below (uncommented). These are the exact
-- pre-migration policy definitions (bare auth.uid()), captured 2026-07-07 from
-- live pg_policies BEFORE apply — deterministic, does NOT depend on post-apply
-- state (unlike a "regenerate from pg_policies" recipe, which after apply would
-- read the already-wrapped form and un-wrap nothing).
--
-- (1) Re-create the dropped redundant SELECT policy:
-- CREATE POLICY "Users see own diet plan" ON public.saved_diet_plans
--   FOR SELECT TO public USING (auth.uid() = user_id);
--
-- (2) Un-wrap all 136 policies (restore bare auth.uid()):
-- ALTER POLICY "ai_coach_interactions_delete_own" ON public.ai_coach_interactions USING ((auth.uid() = user_id));
-- ALTER POLICY "ai_coach_interactions_insert_own" ON public.ai_coach_interactions WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "ai_coach_interactions_select_own" ON public.ai_coach_interactions USING ((auth.uid() = user_id));
-- ALTER POLICY "ai_coach_interactions_update_own" ON public.ai_coach_interactions USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "body_measurements_delete_own" ON public.body_measurements USING ((auth.uid() = user_id));
-- ALTER POLICY "body_measurements_insert_own" ON public.body_measurements WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "body_measurements_select_own" ON public.body_measurements USING ((auth.uid() = user_id));
-- ALTER POLICY "body_measurements_update_own" ON public.body_measurements USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "client_errors_insert_own" ON public.client_errors WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "client_errors_select_own" ON public.client_errors USING ((auth.uid() = user_id));
-- ALTER POLICY "users_insert_own_coach_memory" ON public.coach_memory WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "users_read_own_coach_memory" ON public.coach_memory USING ((auth.uid() = user_id));
-- ALTER POLICY "users_update_own_coach_memory" ON public.coach_memory USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "Users can insert own review" ON public.community_reviews WITH CHECK ((auth.uid() = reviewer_id));
-- ALTER POLICY "Users can read own reviews" ON public.community_reviews USING ((auth.uid() = reviewer_id));
-- ALTER POLICY "Users can update own review" ON public.community_reviews USING ((auth.uid() = reviewer_id)) WITH CHECK ((auth.uid() = reviewer_id));
-- ALTER POLICY "daily_steps_delete_own" ON public.daily_steps USING ((auth.uid() = user_id));
-- ALTER POLICY "daily_steps_insert_own" ON public.daily_steps WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "daily_steps_select_own" ON public.daily_steps USING ((auth.uid() = user_id));
-- ALTER POLICY "daily_steps_update_own" ON public.daily_steps USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "food_corrections_delete_own" ON public.food_corrections USING ((auth.uid() = user_id));
-- ALTER POLICY "food_corrections_insert_own" ON public.food_corrections WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "food_corrections_select_own" ON public.food_corrections USING ((auth.uid() = user_id));
-- ALTER POLICY "food_corrections_update_own" ON public.food_corrections USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "memory_embeddings_own" ON public.memory_embeddings USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "Users insert own notifications" ON public.notifications_inbox WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "Users see own notifications" ON public.notifications_inbox USING ((auth.uid() = user_id));
-- ALTER POLICY "Users update own notifications" ON public.notifications_inbox USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "nutrition_log_items_delete_own" ON public.nutrition_log_items USING ((EXISTS ( SELECT 1 FROM nutrition_logs nl WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = auth.uid())))));
-- ALTER POLICY "nutrition_log_items_insert_own" ON public.nutrition_log_items WITH CHECK ((EXISTS ( SELECT 1 FROM nutrition_logs nl WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = auth.uid())))));
-- ALTER POLICY "nutrition_log_items_select_own" ON public.nutrition_log_items USING ((EXISTS ( SELECT 1 FROM nutrition_logs nl WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = auth.uid())))));
-- ALTER POLICY "nutrition_log_items_update_own" ON public.nutrition_log_items USING ((EXISTS ( SELECT 1 FROM nutrition_logs nl WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1 FROM nutrition_logs nl WHERE ((nl.id = nutrition_log_items.log_id) AND (nl.user_id = auth.uid())))));
-- ALTER POLICY "nutrition_logs_delete_own" ON public.nutrition_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "nutrition_logs_insert_own" ON public.nutrition_logs WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "nutrition_logs_select_own" ON public.nutrition_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "nutrition_logs_update_own" ON public.nutrition_logs USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "progress_photos_delete_own" ON public.progress_photos USING ((auth.uid() = user_id));
-- ALTER POLICY "progress_photos_insert_own" ON public.progress_photos WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "progress_photos_select_own" ON public.progress_photos USING ((auth.uid() = user_id));
-- ALTER POLICY "progress_photos_update_own" ON public.progress_photos USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "Users can see own promo uses" ON public.promo_code_uses USING ((auth.uid() = user_id));
-- ALTER POLICY "rank_promotions_insert_own" ON public.rank_promotions WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "rank_promotions_select_own" ON public.rank_promotions USING ((auth.uid() = user_id));
-- ALTER POLICY "Users can insert own referral code" ON public.referral_codes WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "Users can read own referral code" ON public.referral_codes USING ((auth.uid() = user_id));
-- ALTER POLICY "Users can read own redemptions" ON public.referral_redemptions USING (((auth.uid() = referrer_id) OR (auth.uid() = referee_id)));
-- ALTER POLICY "Users upsert own diet plan" ON public.saved_diet_plans USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "scheduled_workouts_delete_own" ON public.scheduled_workouts USING ((auth.uid() = user_id));
-- ALTER POLICY "scheduled_workouts_insert_own" ON public.scheduled_workouts WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "scheduled_workouts_select_own" ON public.scheduled_workouts USING ((auth.uid() = user_id));
-- ALTER POLICY "scheduled_workouts_update_own" ON public.scheduled_workouts USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "sleep_logs_delete_own" ON public.sleep_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "sleep_logs_insert_own" ON public.sleep_logs WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "sleep_logs_select_own" ON public.sleep_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "sleep_logs_update_own" ON public.sleep_logs USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "streaks_delete_own" ON public.streaks USING ((auth.uid() = user_id));
-- ALTER POLICY "streaks_insert_own" ON public.streaks WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "streaks_select_own" ON public.streaks USING ((auth.uid() = user_id));
-- ALTER POLICY "streaks_update_own" ON public.streaks USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "subscriptions_select_own" ON public.subscriptions USING ((auth.uid() = user_id));
-- ALTER POLICY "telegram_connections_delete_own" ON public.telegram_connections USING ((auth.uid() = user_id));
-- ALTER POLICY "telegram_connections_insert_own" ON public.telegram_connections WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "telegram_connections_select_own" ON public.telegram_connections USING ((auth.uid() = user_id));
-- ALTER POLICY "telegram_connections_update_own" ON public.telegram_connections USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "template_exercises_delete_own" ON public.template_exercises USING ((EXISTS ( SELECT 1 FROM workout_templates wt WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = auth.uid())))));
-- ALTER POLICY "template_exercises_insert_own" ON public.template_exercises WITH CHECK ((EXISTS ( SELECT 1 FROM workout_templates wt WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = auth.uid())))));
-- ALTER POLICY "template_exercises_select_own" ON public.template_exercises USING ((EXISTS ( SELECT 1 FROM workout_templates wt WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = auth.uid())))));
-- ALTER POLICY "template_exercises_update_own" ON public.template_exercises USING ((EXISTS ( SELECT 1 FROM workout_templates wt WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1 FROM workout_templates wt WHERE ((wt.id = template_exercises.template_id) AND (wt.user_id = auth.uid())))));
-- ALTER POLICY "user_custom_exercises_delete_own" ON public.user_custom_exercises USING ((auth.uid() = user_id));
-- ALTER POLICY "user_custom_exercises_insert_own" ON public.user_custom_exercises WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_custom_exercises_select_own" ON public.user_custom_exercises USING ((auth.uid() = user_id));
-- ALTER POLICY "user_custom_exercises_update_own" ON public.user_custom_exercises USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_custom_foods_delete_own" ON public.user_custom_foods USING ((auth.uid() = user_id));
-- ALTER POLICY "user_custom_foods_insert_own" ON public.user_custom_foods WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_custom_foods_select_own" ON public.user_custom_foods USING ((auth.uid() = user_id));
-- ALTER POLICY "user_custom_foods_update_own" ON public.user_custom_foods USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_daily_snapshots_delete_own" ON public.user_daily_snapshots USING ((auth.uid() = user_id));
-- ALTER POLICY "user_daily_snapshots_insert_own" ON public.user_daily_snapshots WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_daily_snapshots_select_own" ON public.user_daily_snapshots USING ((auth.uid() = user_id));
-- ALTER POLICY "user_daily_snapshots_update_own" ON public.user_daily_snapshots USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_preferences_delete_own" ON public.user_preferences USING ((auth.uid() = user_id));
-- ALTER POLICY "user_preferences_insert_own" ON public.user_preferences WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_preferences_select_own" ON public.user_preferences USING ((auth.uid() = user_id));
-- ALTER POLICY "user_preferences_update_own" ON public.user_preferences USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_profile_delete_own" ON public.user_profile USING ((auth.uid() = user_id));
-- ALTER POLICY "user_profile_insert_own" ON public.user_profile WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_profile_select_own" ON public.user_profile USING ((auth.uid() = user_id));
-- ALTER POLICY "user_profile_update_own" ON public.user_profile USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_progress_delete_own" ON public.user_progress USING ((auth.uid() = user_id));
-- ALTER POLICY "user_progress_insert_own" ON public.user_progress WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_progress_select_own" ON public.user_progress USING ((auth.uid() = user_id));
-- ALTER POLICY "user_progress_update_own" ON public.user_progress USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_saved_meals_delete_own" ON public.user_saved_meals USING ((auth.uid() = user_id));
-- ALTER POLICY "user_saved_meals_insert_own" ON public.user_saved_meals WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "user_saved_meals_select_own" ON public.user_saved_meals USING ((auth.uid() = user_id));
-- ALTER POLICY "user_saved_meals_update_own" ON public.user_saved_meals USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "uss_self_delete" ON public.user_stat_snapshots USING ((auth.uid() = user_id));
-- ALTER POLICY "uss_self_insert" ON public.user_stat_snapshots WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "uss_self_read" ON public.user_stat_snapshots USING ((auth.uid() = user_id));
-- ALTER POLICY "uss_self_update" ON public.user_stat_snapshots USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "users_delete_own" ON public.users USING ((auth.uid() = id));
-- ALTER POLICY "users_insert_own" ON public.users WITH CHECK ((auth.uid() = id));
-- ALTER POLICY "users_select_own" ON public.users USING ((auth.uid() = id));
-- ALTER POLICY "users_update_own" ON public.users USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));
-- ALTER POLICY "video_renders_delete_own" ON public.video_renders USING ((auth.uid() = user_id));
-- ALTER POLICY "video_renders_insert_own" ON public.video_renders WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "video_renders_select_own" ON public.video_renders USING ((auth.uid() = user_id));
-- ALTER POLICY "video_renders_update_own" ON public.video_renders USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "water_logs_delete_own" ON public.water_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "water_logs_insert_own" ON public.water_logs WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "water_logs_select_own" ON public.water_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "water_logs_update_own" ON public.water_logs USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "weight_logs_delete_own" ON public.weight_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "weight_logs_insert_own" ON public.weight_logs WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "weight_logs_select_own" ON public.weight_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "weight_logs_update_own" ON public.weight_logs USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "wle_delete_own" ON public.workout_log_exercises USING ((auth.uid() = user_id));
-- ALTER POLICY "wle_insert_own" ON public.workout_log_exercises WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "wle_select_own" ON public.workout_log_exercises USING ((auth.uid() = user_id));
-- ALTER POLICY "wle_update_own" ON public.workout_log_exercises USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "workout_log_sets_delete_own" ON public.workout_log_sets USING ((auth.uid() = user_id));
-- ALTER POLICY "workout_log_sets_insert_own" ON public.workout_log_sets WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "workout_log_sets_select_own" ON public.workout_log_sets USING ((auth.uid() = user_id));
-- ALTER POLICY "workout_log_sets_update_own" ON public.workout_log_sets USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "workout_logs_delete_own" ON public.workout_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "workout_logs_insert_own" ON public.workout_logs WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "workout_logs_select_own" ON public.workout_logs USING ((auth.uid() = user_id));
-- ALTER POLICY "workout_logs_update_own" ON public.workout_logs USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "wsc_delete_own" ON public.workout_schedule_completions USING ((auth.uid() = user_id));
-- ALTER POLICY "wsc_insert_own" ON public.workout_schedule_completions WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "wsc_select_own" ON public.workout_schedule_completions USING ((auth.uid() = user_id));
-- ALTER POLICY "wsc_update_own" ON public.workout_schedule_completions USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "workout_templates_delete_own" ON public.workout_templates USING ((auth.uid() = user_id));
-- ALTER POLICY "workout_templates_insert_own" ON public.workout_templates WITH CHECK ((auth.uid() = user_id));
-- ALTER POLICY "workout_templates_select_own" ON public.workout_templates USING ((auth.uid() = user_id));
-- ALTER POLICY "workout_templates_update_own" ON public.workout_templates USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
