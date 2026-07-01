# C1 B-pass — drop duplicate `water_logs` unique index

branch: c1-drop-dup-water-index
date: 2026-07-01
scope: `supabase/migrations/099_drop_dup_water_logs_user_date_index.sql` + `docs/sot_registry.yaml` (water_logs cloud.columns `amount_ml`→`total_ml`)
reviewer: context-blind adversarial B-pass on the implementation diff, re-verified against live prod `dedsavbjuwgarrhphgnl`
verdict: accepted

## What was verified (evidence)

1. **DROP targets the REDUNDANT index, not the constraint one.** Live `pg_index`/`pg_constraint`: `idx_water_logs_user_date` (indkey `2 3`, unique, non-partial, `backs_constraint=null`) is the bare duplicate the SQL drops; `uq_water_logs_user_date` (same shape, `conindid` of constraint `UNIQUE (user_id, date)`) survives.
2. **SQL correct** — `DROP INDEX IF EXISTS public.idx_water_logs_user_date;` schema-qualified, idempotent, no typo.
3. **Live rolled-back probe** — `BEGIN; DROP INDEX …; INSERT … ON CONFLICT (user_id,date) DO UPDATE; ROLLBACK` → uq_ index + constraint still present, idx_ gone, conflict path resolved (no 42P10).
4. **Inline rollback DDL** byte-identical to live `pg_get_indexdef` of the dropped index.
5. **4-line header** correct order/casing: `Intent` / `Destructive?: yes` / `Rollback strategy: inline` / `Linked diagnose-doc: n/a` (valid — pure infra hygiene per migrations/CLAUDE.md).
6. **SoT edit scoped** to the water_logs cloud.columns block only; live `information_schema` confirms `total_ml` exists and no `amount_ml`. No YAML break introduced.
7. **File hygiene** — 099 next-free, UTF-8/no CRLF, only two paths changed.

## Non-blocking (out of scope, not defects in this diff)

- `integration_test/helpers/test_data_helper.dart:216` writes a Hive map key `'amount_ml'` (local fixture, not the cloud column) — unrelated to this cloud-column registry fix.
- `sot_registry.yaml` has a pre-existing non-`safe_load` parse quirk at line 371 (identical in HEAD; not gated; not introduced by C1).

## Preceding plan review

R1 (context-blind, adversarial) = SAFE; R2 (3 diverse lenses + synthesis) = CONVERGED — each independently proved the drop safe via its own live rolled-back ON CONFLICT probe. See `docs/plan-reviews/c1-drop-dup-water-index.md`.
