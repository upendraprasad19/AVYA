-- 062_workout_logs_dedupe_and_unique.sql
-- Audit 2026-05-12 P2-E — workout_logs has 27 rows for 8 sessions (some 6×
-- copies). Same root cause as P0-A/B (`onConflict: 'id'` mismatch with the
-- natural identity). Dedup live data, add a natural-key UNIQUE, then the
-- client-side switch to natural-key onConflict prevents recurrence.
--
-- closes-diagnose: 3f8a91 (P0/P2 audit batch — same diagnose)

-- 1. One-shot dedupe. Keep the oldest row per (user_id, date, exercise_name)
--    so the canonical id (the first sync's UUID) survives. Per-set rows in
--    `workout_log_exercises` / `workout_log_sets` are FK'd to
--    `workout_log_id` which is derived from `_deterministicId('workout_<date>')`
--    — so it's NOT keyed to `workout_logs.id`. Deleting redundant
--    `workout_logs` rows does NOT cascade-delete any per-set data. Verified
--    via pg_constraint inspection 2026-05-12.
DELETE FROM public.workout_logs wl
USING (
  SELECT user_id, date, exercise_name,
         (array_agg(id ORDER BY logged_at NULLS LAST, id))[1] AS keep_id
  FROM   public.workout_logs
  WHERE  user_id IS NOT NULL
    AND  date IS NOT NULL
    AND  exercise_name IS NOT NULL
  GROUP BY user_id, date, exercise_name
  HAVING COUNT(*) > 1
) d
WHERE wl.user_id = d.user_id
  AND wl.date = d.date
  AND wl.exercise_name = d.exercise_name
  AND wl.id <> d.keep_id;

-- 2. Add natural-key UNIQUE so future inserts/upserts merge.
--    Partial index — tolerates NULLs (which the live schema allows on all
--    three columns even though the writer always sets them).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='workout_logs'
      AND indexname='uniq_workout_logs_user_date_name'
  ) THEN
    CREATE UNIQUE INDEX uniq_workout_logs_user_date_name
      ON public.workout_logs (user_id, date, exercise_name)
      WHERE user_id IS NOT NULL
        AND date IS NOT NULL
        AND exercise_name IS NOT NULL;
  END IF;
END
$$;

COMMENT ON INDEX public.uniq_workout_logs_user_date_name IS
  'Audit 2026-05-12 P2-E — natural unique for client upsert (mirrors '
  'uniq_workout_log_exercises_wlog_ex_set on the per-exercise table). '
  'Pair with onConflict: ''user_id,date,exercise_name'' in client.';
