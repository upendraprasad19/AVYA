-- Intent: Add update_user_progress_snapshot RPC — optimistic-lock writer for the 11
--   non-freeze user_progress fields (current_phase, current_week, phase_started_at,
--   plan_generated_at, total_workouts_done, current_streak_weeks,
--   detected_experience_level, deployments_complete, current_streak_days,
--   last_workout_date, longest_gap_days) that SyncService._syncUserProgress pushes
--   today via a raw, version-blind upsert. Shares the existing
--   streak_progress_version column (migration 056) as ONE whole-row optimistic
--   counter rather than adding a second version column, since user_progress is
--   one row per user. Also hardens update_streak_progress's fresh-insert branch
--   (found in passing while writing this RPC's own insert branch, same file
--   family, same migration — not deferred): a bare INSERT with no ON CONFLICT
--   guard means two concurrent first-ever syncs for a brand-new account (no
--   user_progress row yet) can 23505 unique-violation instead of the caller
--   getting a clean NULL-retry signal. Both RPCs' insert branches now use
--   INSERT ... ON CONFLICT (user_id) DO NOTHING + a FOUND check: the losing
--   caller backs off and returns NULL (re-read + retry), matching the existing
--   version-mismatch UX instead of throwing. ALSO fixes a second, more severe
--   pre-existing bug found by live-testing THIS migration in a rollback
--   transaction before shipping it (per supabase/migrations/CLAUDE.md's own
--   "live INSERT-in-a-rollback-transaction is the only reliable test" rule):
--   update_streak_progress's p_freezes_last_refill is typed TEXT but the
--   target column streak_freezes_last_refill is `date` — every call reaching
--   the INSERT or UPDATE branch 42804'd ("column is of type date but
--   expression is of type text"). 100% latent since this RPC has never had a
--   caller until this same batch; would have broken on literally the first
--   real call (this batch's own syncFreezes wiring) had live-testing not
--   caught it. Fixed with an explicit ::date cast at both assignment sites.
-- Destructive?: no   -- new function + a CREATE OR REPLACE on an existing function's
--   insert-branch only; no data change, no column change
-- Rollback strategy: inline   -- reverse = DROP FUNCTION update_user_progress_snapshot
--   + CREATE OR REPLACE update_streak_progress back to migration 096's body; both
--   blocks at end of file
-- Linked diagnose-doc: e6b9c4
-- ============================================================
-- Unit 3b (OI-45 cross-device half) — cross-device optimistic
-- locking for user_progress (branch: cross-device-progress-lock,
-- 2026-07-30)
-- ============================================================

-- ── 1. New sibling RPC for the 11 non-freeze progress fields ──────────────
--
-- Nullable params + COALESCE-based partial update mirror _syncUserProgress's
-- existing conditional-push semantic (`if (p['x'] != null) 'x': p['x']`) — a
-- field the caller doesn't have locally yet must NOT overwrite a populated
-- cloud value with NULL. On version mismatch: the caller re-fetches the fresh
-- version and re-sends the SAME local field values once (not a field-level
-- merge — these fields are client-authoritative per their own doc comments in
-- sync_profile.dart, cloud is a passive mirror for cron/report consumption),
-- matching this codebase's fire-and-forget-self-heals-on-next-write
-- philosophy rather than a new queue.
CREATE OR REPLACE FUNCTION public.update_user_progress_snapshot(
  p_user_id uuid,
  p_expected_version bigint,
  p_current_phase integer,
  p_current_week integer,
  p_phase_started_at timestamptz,
  p_plan_generated_at timestamptz,
  p_total_workouts_done integer,
  p_current_streak_weeks integer,
  p_detected_experience_level text,
  p_deployments_complete integer,
  p_current_streak_days integer,
  p_last_workout_date date,
  p_longest_gap_days integer
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_current_version BIGINT;
  v_new_version BIGINT;
BEGIN
  -- Security (mirrors update_streak_progress / mig 090): an authenticated
  -- caller may only write its OWN progress. service_role / cron
  -- (auth.uid() IS NULL) pass through.
  --
  -- Hermes C4 (2026-07-30): p_user_id IS NULL is an explicit, separate
  -- rejection. PL/pgSQL `IF <x> <> NULL` evaluates to NULL, which IF
  -- treats as false — so `p_user_id <> auth.uid()` silently passed
  -- through a NULL p_user_id before this fix, and the only thing stopping
  -- the write was user_progress.user_id's NOT NULL constraint downstream
  -- (defense-by-accident, not by this guard). No shipped caller sends
  -- NULL today; this closes the RPC's own contract for any future/direct
  -- PostgREST caller (the function is authenticated-executable by design).
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id must not be null';
  END IF;
  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'cross-account progress write blocked (caller % != target %)',
      auth.uid(), p_user_id;
  END IF;

  SELECT streak_progress_version INTO v_current_version
    FROM public.user_progress
    WHERE user_id = p_user_id
    FOR UPDATE;

  IF NOT FOUND THEN
    -- Hermes C4 (2026-07-30): explicit NULL rejection — `p_expected_version
    -- <> 0` was NULL (falsy) when the param itself was NULL, letting a
    -- NULL-version caller fall through into a phantom fresh-insert
    -- regardless of what it actually expected. No shipped caller sends
    -- NULL (all coerce to `?? 0`); closes the RPC's own contract.
    IF p_expected_version IS NULL OR p_expected_version <> 0 THEN
      RETURN NULL;
    END IF;

    -- Unit 3b round-1-review P2 fix (2026-07-30): current_phase/current_week/
    -- total_workouts_done/current_streak_weeks now COALESCE to the SAME schema
    -- DEFAULTs those columns carry (confirmed live via information_schema:
    -- 1/1/0/0 respectively, all nullable) instead of inserting a bare NULL
    -- param on an all-null fresh insert. Not reachable from any writer
    -- shipped in Unit 3b's first pass (both real callers always populate all
    -- 4), but the P1 fix (routing UserRepository.syncOnboardingToSupabase's
    -- onboarding-replay path through this RPC) makes it newly reachable:
    -- that replay deliberately sends p_current_week=NULL to preserve the
    -- program-week projection on an UPDATE (matches the RPC's COALESCE-to-
    -- existing-column semantics there) — but on a FRESH INSERT there is no
    -- existing column to preserve, so an un-COALESCE'd NULL would have
    -- landed a genuinely wrong NULL instead of the intended default 1.
    INSERT INTO public.user_progress (
      user_id, current_phase, current_week, phase_started_at,
      plan_generated_at, total_workouts_done, current_streak_weeks,
      detected_experience_level, deployments_complete, current_streak_days,
      last_workout_date, longest_gap_days, streak_progress_version, updated_at
    ) VALUES (
      p_user_id, COALESCE(p_current_phase, 1), COALESCE(p_current_week, 1),
      p_phase_started_at, p_plan_generated_at,
      COALESCE(p_total_workouts_done, 0), COALESCE(p_current_streak_weeks, 0),
      p_detected_experience_level, COALESCE(p_deployments_complete, 0),
      COALESCE(p_current_streak_days, 0), p_last_workout_date,
      COALESCE(p_longest_gap_days, 0), 1, now()
    )
    ON CONFLICT (user_id) DO NOTHING;

    IF NOT FOUND THEN
      -- Lost the fresh-insert race to a concurrent caller (e.g. syncFreezes'
      -- own fresh-insert branch, or another device) — let the winner's row
      -- stand, caller re-reads + retries against the real version.
      RETURN NULL;
    END IF;
    RETURN 1;
  END IF;

  -- Hermes C4 (2026-07-30): explicit NULL rejection, same reasoning as the
  -- fresh-insert branch above — `v_current_version <> p_expected_version`
  -- was NULL (falsy) on a NULL p_expected_version, so a NULL-version
  -- caller passed this guard and reached the UPDATE below, whose WHERE
  -- clause then matched zero rows (`= NULL` never matches) while the
  -- function still RETURNed v_new_version as if it had written — a
  -- false-success shape.
  IF p_expected_version IS NULL OR v_current_version <> p_expected_version THEN
    RETURN NULL;
  END IF;

  v_new_version := v_current_version + 1;
  UPDATE public.user_progress
    SET current_phase = COALESCE(p_current_phase, current_phase),
        current_week = COALESCE(p_current_week, current_week),
        phase_started_at = COALESCE(p_phase_started_at, phase_started_at),
        plan_generated_at = COALESCE(p_plan_generated_at, plan_generated_at),
        -- Hermes C3 (2026-07-30): GREATEST, not bare COALESCE — this is a
        -- registered monotonic field (docs/sot_registry.yaml,
        -- feedback_monotonic_field_recompute_demotion.md, diagnose 3a7b9f).
        -- COALESCE alone accepts ANY non-null resend, including one lower
        -- than what's already stored — reachable both by weekly-recalc's
        -- EF writer (supabase/functions/weekly-recalc/index.ts:333-339, a
        -- 4th writer of this column that never touches
        -- streak_progress_version, so the version lock can't see it) and
        -- by this RPC's own retry helper resending a stale local count
        -- after losing a version race. GREATEST closes both regardless of
        -- which writer races, without requiring either to know about the
        -- other.
        total_workouts_done =
          GREATEST(COALESCE(p_total_workouts_done, total_workouts_done), total_workouts_done),
        current_streak_weeks = COALESCE(p_current_streak_weeks, current_streak_weeks),
        detected_experience_level =
          COALESCE(p_detected_experience_level, detected_experience_level),
        -- B-pass round-2 (2026-07-30): GREATEST, not bare COALESCE — same
        -- reasoning as total_workouts_done 4 lines above. deployments_complete
        -- is a registered lifetime-monotonic field (lib/core/services/CLAUDE.md
        -- pitfalls table; docs/sot_registry.yaml phase_progress_current_phase
        -- concept) read by evaluate-rank-promotions (server rank gate) and
        -- rank_service.dart (client rank gate) — a plain COALESCE accepts any
        -- non-null resend including a lower one, reachable by the exact same
        -- retry-helper-resends-stale-local-value vector total_workouts_done's
        -- own fix comment names.
        deployments_complete =
          GREATEST(COALESCE(p_deployments_complete, deployments_complete), deployments_complete),
        current_streak_days = COALESCE(p_current_streak_days, current_streak_days),
        last_workout_date = COALESCE(p_last_workout_date, last_workout_date),
        -- Final B-pass (2026-07-30, docs/reviews/8d5a2f558995-review.md Finding 1):
        -- GREATEST, not bare COALESCE — same reasoning as total_workouts_done and
        -- deployments_complete above. longest_gap_days is a lifetime high-water-mark
        -- (the longest gap ever recorded between workouts), read by rank_service.dart
        -- and evaluate-rank-promotions for disqualification gating — the same
        -- "record" shape as its two siblings. Currently inert (no client writer
        -- populates progress['longest_gap_days'] in Hive today, confirmed by grep —
        -- p_longest_gap_days is always NULL in practice), but fixed now rather than
        -- left inconsistent: the RPC parameter and column already exist, and a
        -- future writer populating this field would silently inherit the same
        -- demotion bug total_workouts_done and deployments_complete already had.
        longest_gap_days =
          GREATEST(COALESCE(p_longest_gap_days, longest_gap_days), longest_gap_days),
        streak_progress_version = v_new_version,
        updated_at = now()
    WHERE user_id = p_user_id
      AND streak_progress_version = p_expected_version;
  RETURN v_new_version;
END;
$function$;

-- Unit 3b round-1-review P0 fix (2026-07-30): REVOKE ... FROM PUBLIC alone is a
-- no-op here. Live pg_default_acl on this project shows the postgres role has a
-- default-privileges entry that grants EXECUTE on every NEW public-schema
-- function DIRECTLY to anon/authenticated/service_role (objtype='f' row:
-- {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres})
-- — bypassing PUBLIC entirely, so PUBLIC never held the grant this REVOKE was
-- trying to remove. Confirmed live in a rollback transaction: the original
-- REVOKE-FROM-PUBLIC-only block left anon_can_exec = true. update_streak_progress's
-- OWN live ACL ({postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres},
-- no anon entry) proves the working pattern is an EXPLICIT REVOKE ... FROM anon,
-- not a PUBLIC-only revoke — matching migration 090's targeted revoke for that
-- function. Re-verified live post-fix: anon_can_exec=false, authenticated/
-- service_role unchanged=true.
REVOKE EXECUTE ON FUNCTION public.update_user_progress_snapshot(
  uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer,
  text, integer, integer, date, integer
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_progress_snapshot(
  uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer,
  text, integer, integer, date, integer
) TO authenticated, service_role;

COMMENT ON FUNCTION public.update_user_progress_snapshot IS
  'Unit 3b (OI-45 cross-device half, e6b9c4) — optimistic-lock writer for the '
  '11 non-freeze user_progress fields. Returns the new version on success, '
  'NULL on version mismatch or lost fresh-insert race (caller re-reads + '
  'retries once, then drops).';

-- ── 2. Harden update_streak_progress's fresh-insert branch (found in ──────
--     passing; same file family, same migration, not deferred).
--     Signature UNCHANGED from migration 096, so mig 090's auth.uid() guard
--     and mig 091's REVOKE-from-PUBLIC + GRANT-to-authenticated/service_role
--     ACLs are preserved via CREATE OR REPLACE (Postgres does not reset
--     grants on a same-signature replace).
--     ALSO fixes a second, more severe latent bug found by live-testing this
--     migration's own INSERT branch (not theoretical — reproduced in a
--     rollback transaction before this fix): p_freezes_last_refill is typed
--     TEXT but the target column streak_freezes_last_refill is `date`
--     (migration 048). Postgres does not implicitly cast a bound TEXT
--     variable to `date` in an INSERT/UPDATE assignment context (unlike an
--     unknown-type string literal) — every call that reached either the
--     INSERT or UPDATE branch would 42804 "column is of type date but
--     expression is of type text". Since this RPC has never had a caller
--     until this same batch, the bug was 100% latent — it would have fired
--     on literally the first real call (this batch's own syncFreezes wiring)
--     had live-testing not caught it first. Fixed with an explicit
--     `::date` cast at both assignment sites — the client already sends a
--     plain YYYY-MM-DD string (StreakProgressService's thisMondayStr), which
--     casts cleanly.
CREATE OR REPLACE FUNCTION public.update_streak_progress(
  p_user_id uuid,
  p_expected_version bigint,
  p_freezes_available integer,
  p_freeze_used_dates text[],
  p_freezes_last_refill text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_current_version BIGINT;
  v_new_version BIGINT;
BEGIN
  -- Hermes C4 (2026-07-30): same NULL-guard hardening as the sibling RPC
  -- above — see its comment for the full reasoning.
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id must not be null';
  END IF;
  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'cross-account streak write blocked (caller % != target %)',
      auth.uid(), p_user_id;
  END IF;

  SELECT streak_progress_version INTO v_current_version
    FROM public.user_progress
    WHERE user_id = p_user_id
    FOR UPDATE;

  IF NOT FOUND THEN
    -- Hermes C4: same explicit NULL rejection as the sibling RPC.
    IF p_expected_version IS NULL OR p_expected_version <> 0 THEN
      RETURN NULL;
    END IF;
    INSERT INTO public.user_progress (
      user_id,
      streak_freezes_available,
      streak_freezes_used_dates,
      streak_freezes_last_refill,
      streak_progress_version
    ) VALUES (
      p_user_id,
      -- Hermes C4 / L22 F1 (2026-07-30): COALESCE to the same live schema
      -- defaults (streak_freezes_available NOT NULL DEFAULT 1,
      -- streak_freezes_used_dates NOT NULL DEFAULT ARRAY[]::text[]) the
      -- sibling RPC's fresh-insert branch already applies to its own
      -- nullable params, for the same reason: a NULL here 23502s against
      -- the NOT NULL constraint. No shipped caller sends NULL for these
      -- today; closes the gap for any future one.
      COALESCE(p_freezes_available, 1),
      COALESCE(p_freeze_used_dates, ARRAY[]::text[]),
      p_freezes_last_refill::date,
      1
    )
    ON CONFLICT (user_id) DO NOTHING;

    IF NOT FOUND THEN
      -- Unit 3b (e6b9c4): lost the fresh-insert race (e.g. to the new
      -- update_user_progress_snapshot RPC's own fresh-insert branch, or
      -- another device) — back off, caller re-reads + retries.
      RETURN NULL;
    END IF;
    RETURN 1;
  END IF;

  -- Hermes C4: same explicit NULL rejection as the sibling RPC.
  IF p_expected_version IS NULL OR v_current_version <> p_expected_version THEN
    RETURN NULL;
  END IF;

  v_new_version := v_current_version + 1;
  UPDATE public.user_progress
    -- Hermes C4 / L22 F1 (2026-07-30): freezes_available/used_dates now
    -- COALESCE to the existing column, matching the sibling RPC's
    -- UPDATE-branch pattern for every other nullable param (unreachable
    -- from shipped callers today, but a real 23502 gap in the RPC's own
    -- contract otherwise).
    --
    -- last_refill is the live-reachable one (Hermes L1-1): the OLD raw
    -- upsert this RPC replaces OMITTED the key entirely when local
    -- last_refill was null (conditional-inclusion upsert semantics),
    -- which preserves the cloud value. An RPC has no such thing as "omit
    -- this param" — every declared parameter is always passed — so a
    -- caller with no local last_refill (e.g. right after
    -- streak_freeze_clamp_migrator.dart deliberately removes the key,
    -- sync_service.dart:626-side re-sync) now sent an explicit NULL,
    -- which this un-COALESCE'd raw assignment wrote straight over a real
    -- cloud value. Live-confirmed reachable: 14 of 17 live user_progress
    -- rows currently hold a non-null streak_freezes_last_refill.
    SET streak_freezes_available = COALESCE(p_freezes_available, streak_freezes_available),
        streak_freezes_used_dates = COALESCE(p_freeze_used_dates, streak_freezes_used_dates),
        streak_freezes_last_refill =
          COALESCE(p_freezes_last_refill::date, streak_freezes_last_refill),
        streak_progress_version = v_new_version
    WHERE user_id = p_user_id
      AND streak_progress_version = p_expected_version;
  RETURN v_new_version;
END;
$function$;

-- ── Rollback (inline) ──────────────────────────────────────
-- B-pass finding (2026-07-30): both halves now have an actual, copy-pasteable
-- statement — the streak-side rollback was previously prose-only ("re-apply
-- migration 096's body"), which cost an incident responder a detour to go
-- read that file under time pressure.
--
-- DROP FUNCTION public.update_user_progress_snapshot(
--   uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer,
--   text, integer, integer, date, integer
-- );
--
-- Re-apply migration 096's update_streak_progress body verbatim (restores the
-- plain, non-ON-CONFLICT insert branch and the un-cast p_freezes_last_refill —
-- i.e. un-does BOTH of this migration's fixes to that function, not just one).
-- Signature unchanged either way, so mig 090's auth.uid() guard + mig 091's
-- ACLs survive regardless:
--
-- CREATE OR REPLACE FUNCTION public.update_streak_progress(
--   p_user_id uuid,
--   p_expected_version bigint,
--   p_freezes_available integer,
--   p_freeze_used_dates text[],
--   p_freezes_last_refill text)
--  RETURNS bigint
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO 'public'
-- AS $function$
-- DECLARE
--   v_current_version BIGINT;
--   v_new_version BIGINT;
-- BEGIN
--   IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
--     RAISE EXCEPTION 'cross-account streak write blocked (caller % != target %)',
--       auth.uid(), p_user_id;
--   END IF;
--
--   SELECT streak_progress_version INTO v_current_version
--     FROM public.user_progress
--     WHERE user_id = p_user_id
--     FOR UPDATE;
--
--   IF NOT FOUND THEN
--     IF p_expected_version <> 0 THEN
--       RETURN NULL;
--     END IF;
--     INSERT INTO public.user_progress (
--       user_id,
--       streak_freezes_available,
--       streak_freezes_used_dates,
--       streak_freezes_last_refill,
--       streak_progress_version
--     ) VALUES (
--       p_user_id,
--       p_freezes_available,
--       p_freeze_used_dates,
--       p_freezes_last_refill,
--       1
--     );
--     RETURN 1;
--   END IF;
--
--   IF v_current_version <> p_expected_version THEN
--     RETURN NULL;
--   END IF;
--
--   v_new_version := v_current_version + 1;
--   UPDATE public.user_progress
--     SET streak_freezes_available = p_freezes_available,
--         streak_freezes_used_dates = p_freeze_used_dates,
--         streak_freezes_last_refill = p_freezes_last_refill,
--         streak_progress_version = v_new_version
--     WHERE user_id = p_user_id
--       AND streak_progress_version = p_expected_version;
--   RETURN v_new_version;
-- END;
-- $function$;
