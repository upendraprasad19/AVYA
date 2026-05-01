-- 039_rank_system_and_auth_fk.sql
--
-- Two changes bundled because they share a common dependency on the FK
-- chain `<table> → public.users(id) → auth.users(id)`:
--
-- (1) Bug A fix from APK Test #3 (2026-04-26): public.users had NO foreign
--     key to auth.users. Deleting an auth user (test cleanup, account
--     wipe) left an orphan public.users row that squatted the email
--     UNIQUE constraint, which blocked re-signups silently.
--
-- (2) Forever-friend rank system from APK Test #3 design spec, Obs 1:
--     rank_ladder (immutable seeded ladder), rank_promotions (per-user
--     history), denormalized current_rank_code on user_profile.
--
-- The Plan A scope of this migration ships the schema; the RankService
-- + cron logic that writes promotion rows lives in Plan B.

-- ── Part 1: Bug A fix — auth.users FK + auto-create trigger ──────────

-- Before adding the FK, clean up any existing orphans defensively. (The
-- 2026-04-26 cleanup already deleted known orphans; this guards against
-- future ones during dev/test.)
DELETE FROM public.users pu
WHERE NOT EXISTS (
  SELECT 1 FROM auth.users au WHERE au.id = pu.id
);

ALTER TABLE public.users
  ADD CONSTRAINT users_id_fk_auth
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Auto-create public.users row when an auth.users row is inserted.
-- Standard Supabase pattern. Eliminates the race where _ensureLocalUser
-- runs before the email-collision orphan can cause trouble.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, created_at)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    now()
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- ── Part 2: rank_ladder (seeded once, immutable) ─────────────────────

CREATE TABLE IF NOT EXISTS rank_ladder (
  rank_code        TEXT PRIMARY KEY,
  display_name     TEXT NOT NULL,
  short_name       TEXT NOT NULL,
  ordinal          INT  NOT NULL UNIQUE,
  min_weeks        INT  NOT NULL,
  insignia_asset   TEXT NOT NULL,
  category         TEXT NOT NULL CHECK (category IN ('sailor', 'officer')),
  is_terminal      BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO rank_ladder (rank_code, display_name, short_name, ordinal, min_weeks, insignia_asset, category, is_terminal) VALUES
  ('SD2',   'Seaman 2nd Class',           'Seaman 2nd', 0, 0,   'rank/sd2.svg',   'sailor',  FALSE),
  ('SD1',   'Seaman 1st Class',           'Seaman 1st', 1, 1,   'rank/sd1.svg',   'sailor',  FALSE),
  ('LS',    'Leading Seaman',             'Leading',    2, 4,   'rank/ls.svg',    'sailor',  FALSE),
  ('PO',    'Petty Officer',              'Petty Off.', 3, 12,  'rank/po.svg',    'sailor',  FALSE),
  ('CPO',   'Chief Petty Officer',        'Chief PO',   4, 26,  'rank/cpo.svg',   'sailor',  FALSE),
  ('MCPO',  'Master Chief Petty Officer', 'Master Ch.', 5, 52,  'rank/mcpo.svg',  'sailor',  FALSE),
  ('SubLt', 'Sub Lieutenant',             'Sub Lt',     6, 104, 'rank/sublt.svg', 'officer', FALSE),
  ('LtCdr', 'Lieutenant Commander',       'Lt Cdr',     7, 156, 'rank/ltcdr.svg', 'officer', FALSE),
  ('Cdr',   'Commander',                  'Cdr',        8, 208, 'rank/cdr.svg',   'officer', FALSE),
  ('Capt',  'Captain',                    'Captain',    9, 260, 'rank/capt.svg',  'officer', TRUE)
ON CONFLICT (rank_code) DO NOTHING;

-- ── Part 3: rank_promotions (per-user history) ───────────────────────

CREATE TABLE IF NOT EXISTS rank_promotions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rank_code        TEXT NOT NULL REFERENCES rank_ladder(rank_code),
  achieved_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  trigger_type     TEXT NOT NULL CHECK (trigger_type IN (
    'signup', 'first_sync', 'phase_complete', 'deployment_complete',
    'calendar', 'workout_count', 'combined'
  )),
  trigger_metadata JSONB,
  UNIQUE (user_id, rank_code)
);

CREATE INDEX IF NOT EXISTS idx_rank_promotions_user
  ON rank_promotions (user_id, achieved_at DESC);

ALTER TABLE rank_promotions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rank_promotions_select_own ON rank_promotions;
CREATE POLICY rank_promotions_select_own ON rank_promotions
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS rank_promotions_insert_own ON rank_promotions;
CREATE POLICY rank_promotions_insert_own ON rank_promotions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ── Part 4: Denormalized current rank on user_profile ────────────────

ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS current_rank_code        TEXT REFERENCES rank_ladder(rank_code) DEFAULT 'SD2',
  ADD COLUMN IF NOT EXISTS current_rank_achieved_at TIMESTAMPTZ DEFAULT now();
