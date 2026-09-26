# Plan-review record — c1-drop-dup-water-index

branch: c1-drop-dup-water-index
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/c1-drop-dup-water-index-bpass.md

## Change

Drop the redundant duplicate UNIQUE index `idx_water_logs_user_date` on `water_logs(user_id, date)` (migration `099`). The byte-identical, constraint-backed `uq_water_logs_user_date` remains and keeps enforcing uniqueness + serving `ON CONFLICT (user_id, date)`. Also corrects a pre-existing SoT drift folded in per §4.2 no-deferrals: `docs/sot_registry.yaml` water_logs `cloud.columns` `amount_ml` → `total_ml` (live + both client writers use `total_ml`; `amount_ml` never existed).

Blast-radius = **platform** (`docs/blast_radius.yaml`: `supabase/migrations/**` = platform; the branch is NOT one of the `*rls*` / `*pseudonymize*` / `*security_definer*` / `*subscriptions_rls*` catastrophic migration globs). Platform ⇒ B-pass required, **no Hermes**.

## Ground truth (verified live 2026-07-01 against `dedsavbjuwgarrhphgnl`)

- `water_logs` has two byte-identical UNIQUE(user_id,date) btree indexes: `uq_water_logs_user_date` (the `conindid` of constraint `uq_water_logs_user_date`, migration 013 — **KEEP**) and `idx_water_logs_user_date` (bare, backs no constraint, created out-of-band — **DROP**).
- Both key columns NOT NULL; non-partial → the surviving index is a valid `ON CONFLICT` arbiter (no 42P10).
- Zero repo references to `idx_water_logs_user_date` by name (lib/test/docs/scripts/supabase/backups). Client upserts use `onConflict: 'user_id,date'` (column-based) at `sync_nutrition.dart:301` + `sync_health.dart:274`.
- 71 rows / 88 kB → a plain (non-CONCURRENT) `DROP INDEX` lock is sub-second.

## Review rounds

- **R1** (1 context-blind adversarial reviewer): SAFE — verified claims A–H live, incl. a rolled-back `ON CONFLICT` probe (no 42P10).
- **R2** (3 diverse lenses — correctness/arbiter, reader/dependency, process/convention — + synthesis): **CONVERGED, no blocking.** The correctness + dependency lenses each re-proved the drop via their own independent live rolled-back probes. Process lens raised two refinements, both folded: `Destructive?` → `yes` (convention binds DROP→yes), and the `amount_ml`→`total_ml` SoT drift. Synthesis `destructive_recommendation: yes`. The synthesis's "already shipped on 86bb7bd" claim was **corrected by direct ground-truth**: `86bb7bd` has no 099 / no DROP INDEX, and the dup index is still live — the C3 record scoped C1 as *apply-gated*, so C1 ships now as its own platform mini-batch and this R1+R2 is its review of record.
- **B-pass** (implementation diff vs live): **accepted** — see `bpass_review`.

## Apply (gated separately — §4.3)

`apply_migration` is a separate live-prod authorization (plan approval ≠ apply approval). The `Destructive?: yes` dry-run requirement is satisfied by the 3× live rolled-back `BEGIN/DROP/ON CONFLICT/ROLLBACK` probes on the exact prod state (a stronger check than a separate DB branch) + the explicit founder apply-gate. Post-apply: re-query `pg_indexes` (dup gone, `uq_` remains) and confirm an `ON CONFLICT (user_id,date)` upsert still resolves. The `099` file + `backups/applied_migrations.json` entry are committed **after** the apply (the parity test requires the manifest entry, which truthfully records the apply).
