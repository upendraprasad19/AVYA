-- Intent: Give profile fields that AI coach-chat extraction also writes (diet_preference, lifestyle_activity, injuries) a per-field lock so a manual Edit-Profile / onboarding-injuries edit can't be silently overwritten by the next daily-snapshot extraction pass.
-- Destructive?: no   -- ADD COLUMN with default + a backfill UPDATE (see below — touches every existing row's NEW column only, no prior data is read or lost) + CREATE FUNCTION + grants
-- Rollback strategy: inline   -- reverse block at end of file
-- Linked diagnose-doc: a2b2f1 (docs/diagnoses/2026-09-27-coach-extraction-locked-fields-writer-drift-a2b2f1.md)

-- ─────────────────────────────────────────────────────────────────────
-- WHY THIS EXISTS
--
-- a2b-2 (single-owner remediation batch) extends daily-snapshot's Gemini
-- extraction (`mergeCoachingNotes` / `mergeCoachMemoryFields`,
-- supabase/functions/daily-snapshot/index.ts) so it can also propose
-- `diet_preference`, `lifestyle_activity` and `injuries` into `user_profile`
-- from conversational signal ("I'm actually vegetarian now", "I hurt my
-- knee"). Those same three fields are ALSO writable directly by the user via
-- Profile -> Edit Profile (lib/features/profile/screens/edit_profile_screen.dart)
-- and, for injuries, during onboarding (lib/features/onboarding/screens/
-- details_screen.dart). Two independent writers to the same column with no
-- ordering guarantee is exactly the writer/reader-drift class this repo's
-- root CLAUDE.md flags as the default suspect (OI-256 filed during design
-- for the more general per-field conflict-resolution gap; this migration
-- ships the narrower, field-specific lock the founder chose instead of
-- blocking on OI-256's full resolution).
--
-- THE CHOSEN SHAPE: an explicit lock list, not last-write-wins timestamps.
-- Once a user has EXPLICITLY set one of these three fields through a
-- first-party UI (Edit Profile save, or onboarding injuries when the user
-- picked something other than the "no injuries" default), that field is
-- locked forever against AI-coach overwrite. The AI can still SUGGEST a
-- change (surfaced via coach_memory.locked_field_conflicts, migration 148's
-- second change below) but the row itself does not move until the user
-- edits it again through the UI. This is deliberately conservative: a false
-- "locked" (the user's own Edit Profile save locks a field they didn't
-- actually care about) costs nothing but a missed auto-update; a false
-- "unlocked" would let the AI silently override an explicit human choice,
-- which is the actual bug this migration exists to prevent.
--
-- WHY AN ADDITIVE-UNION RPC AND NOT A PLAIN COLUMN UPSERT
-- Same shape as migration 123's merge_notification_preferences (see that
-- file's header for the general argument): `user_profile` UPDATE writes come
-- from multiple call sites (Edit Profile save, the onboarding
-- injuries-lock trigger, and potentially a future call site), and a plain
-- `.update({coach_extraction_locked_fields: [...]})` from one call site would
-- silently un-lock a field a DIFFERENT call site had already locked, because
-- an UPDATE overwrites the whole array rather than merging into it.
-- lock_coach_extraction_fields(p_fields) is UNION-only — it can add a field
-- to the locked set, never remove one. There is deliberately no unlock RPC:
-- unlocking is not a feature this batch's ground truth or plan review
-- identified a need for, and adding one un-asked-for would be scope
-- creep this repo's process explicitly warns against.
--
-- WHY THE VALUE ALLOWLIST INSIDE THE FUNCTION, NOT A CHECK CONSTRAINT
-- Postgres has no clean way to CHECK "every element of a text[] is drawn
-- from a fixed set" without a second lookup table or a function-based
-- constraint that duplicates this same list. Filtering p_fields to the
-- three known lockable columns INSIDE the function keeps the allowlist in
-- one place and makes a garbage/typo'd field name from a future client bug
-- a silent no-op rather than a column full of junk. The allowlist filter
-- also implicitly bounds the stored array's size: since only the 3 known
-- names can ever survive the WHERE f = ANY(v_allowed) filter,
-- array_agg(DISTINCT f) can never produce more than 3 elements regardless
-- of how large or repetitive the caller's p_fields argument is.
--
-- SECURITY INVOKER, NOT DEFINER — identical reasoning to migration 123: the
-- caller's own `user_profile_update_own` RLS policy applies
-- ((select auth.uid()) = user_id, migration 100), and the row being touched
-- is the CALLER'S OWN row (keyed on auth.uid(), never a caller-supplied id),
-- so SECURITY INVOKER cannot let a user touch another user's lock list.
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS coach_extraction_locked_fields text[] NOT NULL DEFAULT '{}';

-- P0 backfill (round-1 review finding) — WITHOUT this, every EXISTING row
-- reads as unlocked the instant this column exists, so the very next nightly
-- extraction run would silently overwrite any pre-existing user's genuine,
-- deliberately-set diet_preference/lifestyle_activity/injuries — exactly the
-- bug this whole feature exists to prevent, guaranteed to fire on day one
-- for anyone with a real (non-default) value. Every row that exists AT
-- MIGRATION-APPLY TIME predates this feature and gets ALL THREE fields
-- locked, full stop — deliberately MORE conservative than trying to detect
-- "is this value still the hardcoded default" (a locked field on an
-- existing user costs one fewer auto-fill opportunity, never a correctness
-- risk). Only accounts created AFTER this migration start unlocked
-- (the column's own DEFAULT '{}' above covers that case).
UPDATE public.user_profile
SET coach_extraction_locked_fields = ARRAY['diet_preference', 'lifestyle_activity', 'injuries'];

COMMENT ON COLUMN public.user_profile.coach_extraction_locked_fields IS
  'Additive-only set of profile field names (subset of diet_preference / '
  'lifestyle_activity / injuries) the user has explicitly set via a '
  'first-party UI. daily-snapshot''s coach-extraction merge (mergeCoachingNotes) '
  'skips any field present here and instead records a conflict marker on '
  'coach_memory.locked_field_conflicts. Written ONLY via '
  'lock_coach_extraction_fields(); never write this column directly from a '
  'plain UPDATE/upsert, which would silently un-lock fields another call '
  'site had already locked.';

CREATE OR REPLACE FUNCTION public.lock_coach_extraction_fields(p_fields text[])
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_allowed text[] := ARRAY['diet_preference', 'lifestyle_activity', 'injuries'];
  v_filtered text[];
BEGIN
  IF p_fields IS NULL OR array_length(p_fields, 1) IS NULL THEN
    RETURN;
  END IF;

  -- Allowlist filter: only known-lockable field names survive. A garbage or
  -- future-typo'd name is silently dropped rather than stored.
  SELECT array_agg(DISTINCT f) INTO v_filtered
  FROM unnest(p_fields) AS f
  WHERE f = ANY(v_allowed);

  IF v_filtered IS NULL OR array_length(v_filtered, 1) IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.user_profile
  SET coach_extraction_locked_fields = (
        SELECT array_agg(DISTINCT x)
        FROM unnest(coach_extraction_locked_fields || v_filtered) AS x
      )
  WHERE user_id = (SELECT auth.uid());

  -- Raise loudly on zero rows affected rather than silently no-op-ing or
  -- masking it with a fallback INSERT. Every legitimate call site (Edit
  -- Profile save, syncOnboardingToSupabase — both operate on a user whose
  -- user_profile row was already created) runs AFTER the row exists, so a
  -- missing row here is itself a bug (called too early, or a race) that
  -- should surface immediately in Postgres logs, not be quietly absorbed.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lock_coach_extraction_fields: no user_profile row for %', (SELECT auth.uid());
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.lock_coach_extraction_fields(text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.lock_coach_extraction_fields(text[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.lock_coach_extraction_fields(text[]) TO authenticated;

COMMENT ON FUNCTION public.lock_coach_extraction_fields(text[]) IS
  'Additive-only (UNION, never removes) write of locked field names into '
  'user_profile.coach_extraction_locked_fields, scoped to the calling user via '
  'SECURITY INVOKER + auth.uid(). Values outside the diet_preference / '
  'lifestyle_activity / injuries allowlist are silently dropped. See OI-256, '
  'single-owner-a2b-2 batch.';

-- ─────────────────────────────────────────────────────────────────────
-- SECOND CHANGE, same migration: coach_memory.locked_field_conflicts.
--
-- Ground-truth finding during a2b-2 implementation (not caught by 5 rounds
-- of plan review): the plan's original Design §5 proposed writing the
-- "extraction wanted to change a locked field" conflict marker into
-- user_preferences.coaching_notes. That column has ZERO readers anywhere in
-- ai-proxy / _shared / rolling-context / weekly-report — writing there would
-- have shipped a suggest-mechanism that could never reach the AI or the
-- user, silently defeating the very P1 fix ("the suggest half of the
-- approved decision was silently dropped") this batch exists to close.
--
-- coach_memory IS reachable: daily-snapshot's response returns the row
-- (`coach_memory: memory` in the handler), sync_service.dart mirrors it into
-- Hive coachBox['coach_memory'], and ai_snapshot_builder.dart's
-- _getCoachMemoryForContext() returns CoachMemory.readFromBox(...).toJson()
-- WHOLESALE into the AI's snapshot context (subject to private_mode, which
-- this migration's writer must also respect). Any field added to the
-- CoachMemory schema is therefore live in the AI's prompt without further
-- plumbing. upsertCoachMemory() (supabase/functions/_shared/coach_memory.ts)
-- does a targeted-column upsert (ON CONFLICT DO UPDATE SET <only the passed
-- columns>), so adding this column does not disturb the OTHER, independent
-- coach_memory.coach_notes writer (ai_coach_repository.dart's upward sync).
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.coach_memory
  ADD COLUMN IF NOT EXISTS locked_field_conflicts jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.coach_memory.locked_field_conflicts IS
  'Structured markers: {"<field>": {"attempted_value": ..., "at": "<iso8601>"}} '
  'written by daily-snapshot''s mergeCoachingNotes when Gemini extraction wanted '
  'to change a field the user has locked via lock_coach_extraction_fields(). '
  'Reaches the AI prompt via ai_snapshot_builder._getCoachMemoryForContext() '
  '(whole-object toJson() pass-through) so the model can phrase around the '
  'conflict instead of silently repeating a suggestion the user already '
  'declined by editing the field directly. Written by the daily-snapshot '
  'service-role client (bypasses RLS by design, same as every other '
  'coach_memory column); never client-writable.';

-- ─────────────────────────────────────────────────────────────────────
-- ROLLBACK (inline).
--
--   DROP FUNCTION IF EXISTS public.lock_coach_extraction_fields(text[]);
--   ALTER TABLE public.user_profile DROP COLUMN IF EXISTS coach_extraction_locked_fields;
--   ALTER TABLE public.coach_memory DROP COLUMN IF EXISTS locked_field_conflicts;
--
-- ⚠ Dropping coach_extraction_locked_fields without reverting the client's
-- lock-RPC call sites (edit_profile_screen.dart, user_repository.dart) and
-- the daily-snapshot guard (index.ts) leaves those call sites erroring
-- against a missing column/function. Revert those call sites FIRST, in the
-- same rollback batch.
-- ─────────────────────────────────────────────────────────────────────
