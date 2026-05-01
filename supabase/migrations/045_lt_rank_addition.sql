-- Migration 045: Insert Lt rank at ordinal 7 + shift downstream ranks.
-- APK Test #6 Plan G. Mirrors lib/core/services/rank_ladder_data.dart
-- and supabase/functions/_shared/rank_engine.ts.
--
-- Idempotent: the UPDATE statements + INSERT...ON CONFLICT pattern
-- mean re-running this migration is safe.

BEGIN;

-- Step 1: shift downstream ordinals temporarily out of range
-- (10 -> 100, 9 -> 99, 8 -> 98, 7 -> 97) so the new Lt insert at ord 7
-- doesn't collide with the old LtCdr at 7. Use 90-range to dodge any
-- valid future ladder length.
UPDATE public.rank_ladder SET ordinal = 100 WHERE rank_code = 'Capt';
UPDATE public.rank_ladder SET ordinal = 99  WHERE rank_code = 'Cdr';
UPDATE public.rank_ladder SET ordinal = 98  WHERE rank_code = 'LtCdr';

-- Step 2: insert Lt at ordinal 7 (new row).
INSERT INTO public.rank_ladder (rank_code, display_name, short_name, ordinal, min_weeks, insignia_asset, category, is_terminal)
VALUES ('Lt', 'Lieutenant', 'LIEUTENANT', 7, 130, 'rank/lt.svg', 'officer', false)
ON CONFLICT (rank_code) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  short_name   = EXCLUDED.short_name,
  ordinal      = EXCLUDED.ordinal,
  min_weeks    = EXCLUDED.min_weeks,
  insignia_asset = EXCLUDED.insignia_asset,
  category     = EXCLUDED.category,
  is_terminal  = EXCLUDED.is_terminal;

-- Step 3: settle downstream ranks at their final ordinals (8, 9, 10).
UPDATE public.rank_ladder SET ordinal = 8  WHERE rank_code = 'LtCdr';
UPDATE public.rank_ladder SET ordinal = 9  WHERE rank_code = 'Cdr';
UPDATE public.rank_ladder SET ordinal = 10 WHERE rank_code = 'Capt';

-- Step 4: lock all 11 rows' short_name, min_weeks, category to spec.
UPDATE public.rank_ladder SET short_name = 'SEAMAN 2',       min_weeks = 0,   category = 'sailor'  WHERE rank_code = 'SD2';
UPDATE public.rank_ladder SET short_name = 'SEAMAN 1',       min_weeks = 1,   category = 'sailor'  WHERE rank_code = 'SD1';
UPDATE public.rank_ladder SET short_name = 'LEADING SEAMAN', min_weeks = 4,   category = 'sailor'  WHERE rank_code = 'LS';
UPDATE public.rank_ladder SET short_name = 'PETTY OFFICER',  min_weeks = 12,  category = 'sailor'  WHERE rank_code = 'PO';
UPDATE public.rank_ladder SET short_name = 'CHIEF PO',       min_weeks = 26,  category = 'sailor'  WHERE rank_code = 'CPO';
UPDATE public.rank_ladder SET short_name = 'MASTER CHIEF',   min_weeks = 52,  category = 'sailor'  WHERE rank_code = 'MCPO';
UPDATE public.rank_ladder SET short_name = 'SUB LT',         min_weeks = 104, category = 'officer' WHERE rank_code = 'SubLt';
-- Lt row already locked above via ON CONFLICT DO UPDATE.
UPDATE public.rank_ladder SET short_name = 'LT CDR',         min_weeks = 156, category = 'officer' WHERE rank_code = 'LtCdr';
UPDATE public.rank_ladder SET short_name = 'CDR',            min_weeks = 208, category = 'officer' WHERE rank_code = 'Cdr';
UPDATE public.rank_ladder SET short_name = 'CAPTAIN',        min_weeks = 260, category = 'officer', is_terminal = true WHERE rank_code = 'Capt';

-- Step 5: integrity check. All 11 codes present, ordinals 0..10 dense.
DO $$
DECLARE
  cnt int;
  ord_min int;
  ord_max int;
BEGIN
  SELECT COUNT(*), MIN(ordinal), MAX(ordinal) INTO cnt, ord_min, ord_max FROM public.rank_ladder;
  IF cnt <> 11 THEN
    RAISE EXCEPTION 'rank_ladder must have exactly 11 rows; found %', cnt;
  END IF;
  IF ord_min <> 0 OR ord_max <> 10 THEN
    RAISE EXCEPTION 'rank_ladder ordinals must span 0..10; found %..%', ord_min, ord_max;
  END IF;
END $$;

COMMIT;
