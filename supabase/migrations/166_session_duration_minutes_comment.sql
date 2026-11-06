-- Intent: Correct the column comment on public.user_profile.session_duration_minutes: migration 017 says the plan generator no longer reads it, which is false since the session set budget flip (PR #195, 2026-11-03).
-- Destructive?: no   -- comment only; no column, constraint, row or policy changes
-- Rollback strategy: inline   -- the reverse COMMENT (migration 017's text) is the commented block at the end of this file
-- Linked diagnose-doc: n/a   -- documentation hygiene; context: docs/audit/set-budget-flip.closure.yaml (SBF-MIGRATION-COMMENT)

COMMENT ON COLUMN public.user_profile.session_duration_minutes IS
  'Preferred session length in minutes (30/45/60/90), set via Edit Profile. Read by the plan generator: the session set budget sizes the sets of the budgeted exercises in each generated day to fit inside this many minutes (custom, timed and cardio rows keep their sets), and a day can run shorter (60 when unset or unreadable).';

-- Post-apply verification (read-only):
--   select col_description('public.user_profile'::regclass, a.attnum)
--   from pg_attribute a
--   where a.attrelid = 'public.user_profile'::regclass and a.attname = 'session_duration_minutes';

-- Rollback (inline, restores migration 017's text):
-- COMMENT ON COLUMN public.user_profile.session_duration_minutes IS
--   'Preferred workout duration in minutes (30/45/60). Set via Edit Profile. NOTE: post-V4 the plan generator no longer reads this; retained for user preference display and future re-use.';
