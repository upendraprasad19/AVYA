-- Intent: Heal user_profile.current_rank_code + current_rank_achieved_at to highest-ever rank from rank_promotions. Pre-fix the client + server unconditionally overwrote current_rank_code with the currently-qualifying rank (computed from live state), demoting users whose streak dropped below a sailor-track gate. Paired with client (rank_service.dart) + Edge Function (evaluate-rank-promotions) only-promote guards landing in the same batch.
-- Destructive?: no   -- UPDATE only. rank_promotions rows untouched (already permanent via UNIQUE (user_id, rank_code)).
-- Rollback strategy: not applicable   -- forward heal; the demoted values were already incorrect, restoring them is the desired terminal state.
-- Linked diagnose-doc: 2026-05-27-rank-demotion-on-state-recompute-3a7b9f

-- For each user, find the highest-ordinal entry in rank_promotions and use
-- its rank_code + achieved_at to set the user_profile denormalization.
-- WHERE clause only touches users currently BELOW their peak rank — users
-- already at peak (or above, defensive) are no-ops.

WITH rank_ordinals(rank_code, ordinal) AS (
  VALUES
    ('SD2', 0), ('SD1', 1), ('LS', 2), ('PO', 3), ('CPO', 4),
    ('MCPO', 5), ('SubLt', 6), ('Lt', 7), ('LtCdr', 8), ('Cdr', 9), ('Capt', 10)
),
peak_per_user AS (
  SELECT DISTINCT ON (rp.user_id)
    rp.user_id,
    rp.rank_code      AS peak_code,
    rp.achieved_at    AS peak_achieved_at,
    ro.ordinal        AS peak_ordinal
  FROM rank_promotions rp
  JOIN rank_ordinals ro ON ro.rank_code = rp.rank_code
  ORDER BY rp.user_id, ro.ordinal DESC, rp.achieved_at DESC
)
UPDATE user_profile up
SET
  current_rank_code        = ppu.peak_code,
  current_rank_achieved_at = ppu.peak_achieved_at
FROM peak_per_user ppu
WHERE up.user_id = ppu.user_id
  AND (
    up.current_rank_code IS NULL
    OR up.current_rank_code NOT IN (SELECT rank_code FROM rank_ordinals)
    OR COALESCE(
         (SELECT ordinal FROM rank_ordinals WHERE rank_code = up.current_rank_code),
         -1
       ) < ppu.peak_ordinal
  );
