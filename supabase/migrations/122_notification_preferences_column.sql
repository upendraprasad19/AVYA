-- Intent: Give `notification_preferences` a real home — a nullable jsonb column on user_preferences — so a user's notification toggles stop riding inside the wholesale-replaced user_daily_snapshots.snapshot_json blob, where they were push-only and destroyed on every reinstall (OI-98 / diagnose e4a1b7).
-- Destructive?: no   -- pure ADD COLUMN, nullable, no default, no backfill, no data touched
-- Rollback strategy: inline   -- reverse block at the end of this file; DDL only and fully reversible (the column is empty at apply time)
-- Linked diagnose-doc: e4a1b7

-- ─────────────────────────────────────────────────────────────────────
-- WHY A COLUMN AND NOT A SNAPSHOT KEY
--
-- `snapshot_json` is a DERIVED read model: rebuilt wholesale from Hive on
-- every write (ai_snapshot_builder.dart renders 7 boxes into ~9.5 KB) and
-- REPLACED, not merged, by `daily-snapshot`'s upsert on
-- (user_id, snapshot_date). That is correct for regenerable data, which is
-- every other key it carries.
--
-- Notification preferences are the opposite: user intent, derivable from
-- nothing, and the only copy that exists. Two consequences followed, both
-- verified live on 2026-08-26:
--   1. A reinstalled device reports all ten toggles as enabled (its empty Hive
--      box and "everything on" are the same value) and that REPLACES the
--      server's stored copy.
--   2. All ten server readers take the user's NEWEST snapshot row with no
--      fall-through, and four Edge Functions write that row — three of which
--      create a preference-less row when the day has none. 3 of the 5 users
--      who ever stored a preference were in that state.
--
-- `user_preferences` is one row per user, written by PARTIAL-COLUMN upsert
-- (each writer names only the columns it owns, and unnamed columns survive —
-- verified empirically: daily-snapshot wrote coaching_notes three days after
-- insert and left created_at / updated_at / preferred_language /
-- motivational_style at their insert values). So there is no newest-row-wins,
-- no wholesale replace, and no shadowing.
--
-- ⚠ NULLABLE WITH NO DEFAULT, DELIBERATELY.
-- NULL means "this user has no record", which MUST stay distinguishable from
-- `{}` ("record exists, nothing set") and from a populated map. Collapsing
-- "no record" into "everything enabled" is the precise root of OI-98; a
-- DEFAULT '{}'::jsonb here would re-create it in the new home on day one.
--
-- ⚠ NO BACKFILL, and that is a finding rather than an omission.
-- Live at apply time: 126 snapshot rows across 18 users, 14 rows carrying
-- notification_preferences across 5 users, and ZERO rows with any key set to
-- `false`. No user's real "off" survives anywhere in the cloud, so there is no
-- earlier truth to recover. Back-filling the all-enabled blobs would only
-- write the bug's own output into the new column and make it authoritative.
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.user_preferences
  ADD COLUMN IF NOT EXISTS notification_preferences jsonb;

COMMENT ON COLUMN public.user_preferences.notification_preferences IS
  'Per-user notification toggles, shape {key: {enabled: bool, ...}}. Client is THE writer '
  '(NotificationPrefsRepository -> _syncUserPreferences, partial upsert, omitted entirely when '
  'the device has no local record). Server readers apply ABSENT => SEND: NULL, a missing key, or '
  'a non-boolean `enabled` all mean send; only a literal false silences. NULL is "no record" and '
  'is deliberately distinct from {} — see OI-98 / diagnose e4a1b7.';

-- ─────────────────────────────────────────────────────────────────────
-- ROLLBACK (inline). Safe at any point: the column is additive and nothing
-- read it before this migration. Dropping it returns every reader to the
-- snapshot fallback, which is still in place until +39 adoption retires it.
--
--   ALTER TABLE public.user_preferences DROP COLUMN IF EXISTS notification_preferences;
--
-- ⚠ After adoption retires the snapshot fallback, this rollback becomes a
-- DATA-LOSS operation: at that point the column is the only home for the
-- concept. Re-check before running it then.
-- ─────────────────────────────────────────────────────────────────────
