-- rls_initplan_ab_verify.sql — OPT-A (diagnose e6b1a4) per-policy A/B leak check.
--
-- PURPOSE: prove migration 100's initplan rewrite is behavior-PRESERVING — a user
-- reads/writes ONLY their own rows, never another's — across the shapes that could
-- regress if the rewrite were wrong:
--   (a) plain auth.uid()=user_id (weight_logs),
--   (b) correlated EXISTS (nutrition_log_items → nutrition_logs),
--   (c) OR-shape (referral_redemptions: referrer_id OR referee_id — BOTH arms),
--   (d) consolidated saved_diet_plans (ALL policy must still let A READ its own row
--       AND block B's write — proves the DROP lost no access).
--
-- DESIGN: everything runs inside a ROLLBACK transaction (zero pollution). We SEED
-- both users' rows as the OWNER (RLS bypassed, so all NOT-NULL/FK constraints are
-- satisfiable), then SET ROLE authenticated + impersonate each user via
-- request.jwt.claims (what auth.uid() reads) to run the RLS-gated assertions.
-- RAISEs on any leak/lockout; always ROLLBACKs. Pure SQL (no psql \set) so it runs
-- via the SQL editor / execute_sql. Run AFTER applying migration 100 to confirm the
-- live filtering is unchanged; can also be run BEFORE apply for an identical baseline.
--
-- Uses two REAL, distinct public.users.id (FK-valid): A=upendra, B=sumitt.

BEGIN;

-- ── Seed as owner (RLS bypassed) ────────────────────────────────────────────
-- A = d7a67a37-0b05-4f0a-b13c-388bff3cb59b   B = e0128c03-d648-4f30-b3db-4fc6c02d13c4
INSERT INTO public.weight_logs (user_id, date, weight_kg)
  VALUES ('d7a67a37-0b05-4f0a-b13c-388bff3cb59b','2020-01-01', 70),
         ('e0128c03-d648-4f30-b3db-4fc6c02d13c4','2020-01-01', 80);

WITH la AS (
  INSERT INTO public.nutrition_logs (user_id, date, meal_type, total_calories)
    VALUES ('d7a67a37-0b05-4f0a-b13c-388bff3cb59b','2020-01-01','breakfast',100) RETURNING id),
     lb AS (
  INSERT INTO public.nutrition_logs (user_id, date, meal_type, total_calories)
    VALUES ('e0128c03-d648-4f30-b3db-4fc6c02d13c4','2020-01-01','breakfast',200) RETURNING id)
INSERT INTO public.nutrition_log_items (log_id, item_index, food_name, calories)
  SELECT id, 0, 'A_item', 100 FROM la
  UNION ALL
  SELECT id, 0, 'B_item', 200 FROM lb;

INSERT INTO public.saved_diet_plans (user_id, plan_json)
  VALUES ('d7a67a37-0b05-4f0a-b13c-388bff3cb59b','{"owner":"A"}'::jsonb),
         ('e0128c03-d648-4f30-b3db-4fc6c02d13c4','{"owner":"B"}'::jsonb);

-- referral_redemptions: one row A→B exercises BOTH OR arms (A=referrer, B=referee).
INSERT INTO public.referral_redemptions (referrer_id, referee_id)
  VALUES ('d7a67a37-0b05-4f0a-b13c-388bff3cb59b','e0128c03-d648-4f30-b3db-4fc6c02d13c4');

-- ── Assert under RLS as each user ───────────────────────────────────────────
SET LOCAL role authenticated;

-- As A: sees own, not B's; OR-shape referrer arm; own diet plan readable.
SET LOCAL request.jwt.claims = '{"sub":"d7a67a37-0b05-4f0a-b13c-388bff3cb59b"}';
DO $$
DECLARE n_own int; n_other int; n_ref int; n_plan int;
BEGIN
  SELECT count(*) INTO n_own   FROM public.weight_logs WHERE weight_kg = 70;
  SELECT count(*) INTO n_other FROM public.weight_logs WHERE weight_kg = 80;
  IF n_own <> 1 OR n_other <> 0 THEN RAISE EXCEPTION '(a) weight_logs: A own=% other=% want 1/0', n_own, n_other; END IF;

  SELECT count(*) INTO n_own   FROM public.nutrition_log_items WHERE food_name = 'A_item';
  SELECT count(*) INTO n_other FROM public.nutrition_log_items WHERE food_name = 'B_item';
  IF n_own <> 1 OR n_other <> 0 THEN RAISE EXCEPTION '(b) EXISTS nutrition_log_items: A own=% other=% want 1/0', n_own, n_other; END IF;

  -- (c) OR-shape referrer arm: A is the referrer → must see the row.
  SELECT count(*) INTO n_ref FROM public.referral_redemptions
    WHERE referrer_id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b';
  IF n_ref <> 1 THEN RAISE EXCEPTION '(c) referral OR referrer-arm: A sees=% want 1', n_ref; END IF;

  -- (d) positive: A can STILL read its own diet plan after the SELECT-policy drop.
  SELECT count(*) INTO n_plan FROM public.saved_diet_plans
    WHERE user_id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b';
  IF n_plan <> 1 THEN RAISE EXCEPTION '(d) saved_diet_plans: A cannot read own plan (=%) — consolidation lost read access', n_plan; END IF;
END $$;

-- As B: OR-shape referee arm (B=referee → sees the same row); cannot see/UPDATE A's plan.
SET LOCAL request.jwt.claims = '{"sub":"e0128c03-d648-4f30-b3db-4fc6c02d13c4"}';
DO $$
DECLARE n_ref int; b_sees_a int; b_upd_a int;
BEGIN
  SELECT count(*) INTO n_ref FROM public.referral_redemptions
    WHERE referee_id = 'e0128c03-d648-4f30-b3db-4fc6c02d13c4';
  IF n_ref <> 1 THEN RAISE EXCEPTION '(c) referral OR referee-arm: B sees=% want 1', n_ref; END IF;

  SELECT count(*) INTO b_sees_a FROM public.saved_diet_plans
    WHERE user_id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b';
  IF b_sees_a <> 0 THEN RAISE EXCEPTION '(d) LEAK: B sees As diet plan (=%)', b_sees_a; END IF;

  UPDATE public.saved_diet_plans SET plan_json = '{"hacked":1}'::jsonb
    WHERE user_id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b';
  GET DIAGNOSTICS b_upd_a = ROW_COUNT;
  IF b_upd_a <> 0 THEN RAISE EXCEPTION '(d) LEAK: B updated As diet plan (% rows) — write RLS lost in consolidation', b_upd_a; END IF;
END $$;

RESET ROLE;
SELECT 'rls_initplan_ab_verify: PASS — no leak/lockout across plain / EXISTS / OR-arms / consolidated shapes' AS result;

ROLLBACK;
