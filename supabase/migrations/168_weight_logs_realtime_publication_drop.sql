-- Intent: Remove public.weight_logs from the supabase_realtime publication (added by 079): the client no longer subscribes (batch realtime-weight-off, PR #214), so the server decoded its WAL for no subscriber.
-- Destructive?: no   -- publication membership only; no table, row or policy changes. Realtime delivery of weight_logs stops (no client consumes it).
-- Rollback strategy: inline   -- see the commented reverse DDL at the end of the file
-- Linked diagnose-doc: e4a7c9

-- Idempotent: only drops when the table is currently a member.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'weight_logs'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.weight_logs;
  END IF;
END
$$;

-- ROLLBACK (re-adds the table; run only if a Realtime consumer is reintroduced):
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.weight_logs;
