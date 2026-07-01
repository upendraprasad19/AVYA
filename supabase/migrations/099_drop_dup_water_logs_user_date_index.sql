-- Intent: Drop the redundant duplicate UNIQUE index idx_water_logs_user_date on public.water_logs(user_id, date). The byte-identical, constraint-backed uq_water_logs_user_date remains and continues to enforce uniqueness + serve ON CONFLICT (user_id, date). Removes pure write-amplification + storage on a duplicate index.
-- Destructive?: yes   -- it is a DROP (the header convention binds DROP -> yes). No ROW data and no CONSTRAINT is lost: the surviving uq_water_logs_user_date still enforces (user_id, date) uniqueness. Fully reversible via the inline rollback below. Dry-run satisfied by 3x live rolled-back BEGIN/DROP/ON CONFLICT/ROLLBACK probes on prod (2026-07-01) + the explicit founder apply-gate.
-- Rollback strategy: inline
-- Linked diagnose-doc: n/a   -- pure infra hygiene (redundant-index removal; cf. reindex/vacuum). Traceability: docs/plan-reviews/c1-drop-dup-water-index.md + docs/plan-reviews/restore-single-call.md §7.

-- idx_water_logs_user_date was created out-of-band (no migration defines it; Dashboard/manual).
-- It is a byte-identical UNIQUE(user_id, date) btree twin of the constraint-backed
-- uq_water_logs_user_date (migration 013), which remains and enforces uniqueness + serves
-- ON CONFLICT (user_id, date). Verified live 2026-07-01 against dedsavbjuwgarrhphgnl
-- (pg_index: identical indkey '2 3', indisunique, non-partial, same opclass; pg_constraint:
--  only uq_water_logs_user_date is a conindid; idx_ backs no constraint). Both client upserts
-- (sync_nutrition.dart, sync_health.dart) use onConflict:'user_id,date' (column-based), so the
-- surviving constraint index remains a valid arbiter.
DROP INDEX IF EXISTS public.idx_water_logs_user_date;

-- Rollback (if ever needed):
-- CREATE UNIQUE INDEX idx_water_logs_user_date ON public.water_logs USING btree (user_id, date);
