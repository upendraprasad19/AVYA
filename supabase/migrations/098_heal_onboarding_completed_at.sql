-- Intent: Heal user_profile.onboarding_completed_at for already-onboarded users whose column is NULL (diagnose c4d8a2). Sets it to users.created_at where users.onboarding_completed = true AND onboarding_completed_at IS NULL. Repairs rows (e.g. test7) stranded by the pre-fix missing-durable-writer bug — on a new device those users would otherwise be forced to re-onboard. Forward-only; touches only NULL rows.
-- Destructive?: no   -- backfills a NULL column only; no existing non-null value is overwritten
-- Rollback strategy: inline   -- reverse block at end of file (NOT advised — the backfilled value is correct)
-- Linked diagnose-doc: c4d8a2
-- ============================================================
-- Unit D heal — onboarding_completed_at durable backfill
-- (branch: opt-quick-wins, 2026-06-28)
-- ============================================================

UPDATE public.user_profile AS up
SET onboarding_completed_at = u.created_at
FROM public.users AS u
WHERE up.user_id = u.id
  AND u.onboarding_completed = true
  AND up.onboarding_completed_at IS NULL;

-- ── Rollback (inline) ──────────────────────────────────────
-- NOT advised (the backfilled value is correct). To reverse the heal:
-- UPDATE public.user_profile up SET onboarding_completed_at = NULL
--   FROM public.users u
--   WHERE up.user_id = u.id AND u.onboarding_completed = true
--     AND up.onboarding_completed_at = u.created_at;
