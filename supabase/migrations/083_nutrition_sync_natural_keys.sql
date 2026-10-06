-- Intent: User/parent-scoped natural keys for the last two same-class sync tables — add UNIQUE(user_id,name) on user_saved_meals, and add a position-stable item_index column (backfilled by insertion order) + UNIQUE(log_id,item_index) on nutrition_log_items. Closes the cross-user deterministic-id collision (Diagnose f7e3a1) where two users saving a same-named meal / logging the same food in the same meal+date collided on the PK and overwrote/stole each other's rows.
-- Destructive?: no   -- additive only: one new column + two unique indexes. NO rows lost or rewritten; item_index is backfilled from existing per-log insertion order; the 12 live (log_id,food_name) duplicate groups are PRESERVED (position-keyed, never merged). DEPLOY-ORDERING: ship WITH the matching APK — the new client OMITS id + sends item_index; an OLD client (onConflict:'id', no item_index) would 23502 on item inserts once item_index is NOT NULL, until it updates (acceptable pre-launch / single device; same posture as migration 082).
-- Rollback strategy: inline   -- reverse DDL (drop indexes, drop NOT NULL, drop item_index) commented at file end.
-- Linked diagnose-doc: f7e3a1
--
-- 083_nutrition_sync_natural_keys.sql
--
-- The two nutrition sync upserts still sent a user-INDEPENDENT deterministic id:
--   • user_saved_meals: id = _deterministicId('saved_meal_<nameHash>') (name only,
--     no user) → two users with a same-named saved meal hit the same uuid →
--     onConflict:'id' DO UPDATE overwrote one user's meal with the other's (and
--     flipped user_id).
--   • nutrition_log_items: id = _deterministicId('<nlogKey>_item_<i>') where the
--     nlog key embeds date+meal+itemsHash but NO user → two users logging the same
--     food in the same meal-type on the same date hit the same item uuid →
--     onConflict:'id' DO UPDATE stole the item (flipped its log_id to the other
--     user's parent). Same cross-user class as d4b8e2.
-- Cure: the client OMITS id (gen_random_uuid default) + upserts onConflict a
-- user/parent-scoped natural key. This migration backs those keys. Verified live
-- 2026-06-03: user_saved_meals empty (0 rows); nutrition_log_items has 0 null/empty
-- food_name (174 rows) and 12 legit (log_id,food_name) duplicate groups — which is
-- exactly why food_name is NOT used as the arbiter.

-- ── user_saved_meals: user-scoped natural identity (additive) ──
-- Both user_id + name are already NOT NULL → non-partial index, no 42P10.
create unique index if not exists uniq_user_saved_meals_user_name
  on public.user_saved_meals (user_id, name);

-- ── nutrition_log_items: position-stable, parent-scoped item identity ──
-- 1. Add the column (nullable for the backfill pass).
alter table public.nutrition_log_items
  add column if not exists item_index integer;

-- 2. Backfill existing rows: position within each log by insertion order. The
--    original sync loop inserted item 0 first, item 1 next, … so created_at ASC
--    (id as tiebreak) APPROXIMATELY reconstructs the client's i. row_number()
--    guarantees a DISTINCT index per row within each log_id (verified live: 0
--    duplicate (log_id,item_index) groups over the 174 existing rows) → step 4's
--    unique index creates cleanly even for the duplicate-food groups. NOTE: when
--    two items share a created_at, the id-tiebreak may not match emit order, so a
--    given EXISTING item could land one position off; worst case is a one-time
--    cosmetic position SWAP on first re-sync (both rows survive — never a loss),
--    and _restoreNutritionLogs now sorts items by item_index so even that is
--    invisible to every reader. New logs (post-deploy) are always exact (i = 0..n).
with ordered as (
  select id,
         (row_number() over (partition by log_id order by created_at, id) - 1) as idx
  from public.nutrition_log_items
  where item_index is null
)
update public.nutrition_log_items n
  set item_index = o.idx
  from ordered o
  where n.id = o.id;

-- 3. Lock it down so it is a reliable (non-partial, NOT NULL) onConflict arbiter.
alter table public.nutrition_log_items
  alter column item_index set not null;

-- 4. The user-scoped natural key. log_id is FK→nutrition_logs(id) (now user-scoped
--    via UNIQUE(user_id,date,meal_type)), so (log_id,item_index) is user-isolated.
--    Position-keyed → the two legit "same food twice in one meal" rows survive as
--    item_index 0 and 1; they are NEVER merged (the data-loss food_name trap).
create unique index if not exists uniq_nli_logid_itemidx
  on public.nutrition_log_items (log_id, item_index);

-- ── Rollback (inline, emergency-only) ────────────────────────────────────────
-- begin;
--   drop index if exists public.uniq_user_saved_meals_user_name;
--   drop index if exists public.uniq_nli_logid_itemidx;
--   alter table public.nutrition_log_items alter column item_index drop not null;
--   alter table public.nutrition_log_items drop column if exists item_index;
-- commit;
