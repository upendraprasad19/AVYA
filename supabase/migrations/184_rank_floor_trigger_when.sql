-- Intent: Stop the floor rung (SD2) from dispatching a coach congratulation: recreate trg_dispatch_proactive_coach_promotion with WHEN (NEW.rank_code <> 'SD2').
-- Destructive?: no   -- drops and recreates one trigger binding in one transaction; no table, row, constraint or function change.
-- Rollback strategy: inline   -- re-run the CREATE TRIGGER below without the WHEN clause (the binding before this migration, migration 073).
-- Linked diagnose-doc: 8b1f3d
--
-- 184_rank_floor_trigger_when.sql
--
-- Diagnose: 2026-11-23-rank-floor-never-announced (8b1f3d), OI-348 walk.
--
-- BUG: every account is written the floor rung (SD2, ordinal 0) at sign-up
-- (rank_service.dart and the evaluate-rank-promotions cron both insert every
-- rung up to the qualified one). The AFTER INSERT trigger posted every row to
-- proactive-coach-promotion, so a brand-new account got a "Promotion Day"
-- chat message and push for the rank it was simply given. Live 2026-11-23:
-- 27 proactive_promotion chat rows, all for SD2.
--
-- FIX: the trigger fires only for rungs above the floor. The dispatch
-- function private.dispatch_proactive_coach_promotion() is NOT touched (its
-- body, privileges and search_path stay exactly as migration 107 left them);
-- only the trigger binding gains a WHEN clause. The Edge Function also skips
-- the floor itself (sink-side mirror), and the cron writes no ceremony row
-- for it. rank_promotions rows are still written (history).
--
-- The floor literal 'SD2' must equal kRankLadder.first.code
-- (lib/core/services/rank_ladder_data.dart) and kRankLadder[0].code
-- (supabase/functions/_shared/rank_engine.ts); pinned by
-- test/contracts/rank_floor_trigger_migration_test.dart. A change of the floor
-- rung needs a NEW trigger migration.
--
-- Live binding before this migration (pg_get_triggerdef, 2026-11-23):
--   CREATE TRIGGER trg_dispatch_proactive_coach_promotion AFTER INSERT ON
--   public.rank_promotions FOR EACH ROW EXECUTE FUNCTION
--   private.dispatch_proactive_coach_promotion()

BEGIN;

DROP TRIGGER IF EXISTS trg_dispatch_proactive_coach_promotion ON public.rank_promotions;

CREATE TRIGGER trg_dispatch_proactive_coach_promotion
  AFTER INSERT ON public.rank_promotions
  FOR EACH ROW
  WHEN (NEW.rank_code <> 'SD2')
  EXECUTE FUNCTION private.dispatch_proactive_coach_promotion();

COMMIT;

-- Rollback (inline; restores the migration 073 binding):
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_dispatch_proactive_coach_promotion ON public.rank_promotions;
-- CREATE TRIGGER trg_dispatch_proactive_coach_promotion
--   AFTER INSERT ON public.rank_promotions
--   FOR EACH ROW
--   EXECUTE FUNCTION private.dispatch_proactive_coach_promotion();
-- COMMIT;
