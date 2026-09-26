---
staged_against: opt-a-rls-initplan
verdict: accepted
---

# Hermes cross-lens review — opt-a-rls-initplan (migration 100)

Two deep cross-lens / adversarial passes on the catastrophic-tier RLS initplan wrap, both
context-blind, verified against live `pg_policies` / `pg_proc` / `pg_class` + the repo conventions.

## Verdict: **accepted** (behavior-preserving; process/rollback blockers fixed in-batch)

### Adversarial leak-hunt (Opus) — SAFE
Framed as "assume this leaks or locks out; find how." Conclusion: **"could not construct a leak or
a lockout."** Key evidence, all live-verified:
- `auth.uid()` is STABLE + nullary → hoisting into `(select …)` is value-identical per row (the
  Supabase-recommended rewrite). NULL/anon semantics identical (`NULL = col` → deny, both forms).
- EXISTS correlation (`nl.id = nutrition_log_items.log_id` / `wt.id = template_exercises.template_id`)
  untouched; only the leaf `auth.uid()` wrapped.
- `saved_diet_plans`: dropped SELECT policy's qual is byte-identical to the retained ALL policy's
  USING → no visibility change, no lockout. Only 2 policies existed (no hidden third).
- 0 RESTRICTIVE, 0 `auth.jwt()`/`auth.role()`, role scoping untouched by the wrap.

### Cross-lens process/deploy pass — blockers found, ALL FIXED
1. **Rollback recipe was non-functional** — it read `pg_policies`, which post-apply holds the
   WRAPPED form → regenerated a no-op. → **Replaced with 136 LITERAL reverse ALTER statements**
   (captured from pre-apply live state) + the `CREATE POLICY` restore. No live snapshot needed.
2. **Do NOT commit the migration pre-apply** — `applied_migrations_parity_test.dart` fails on a
   migration file with no manifest entry. → **Sequenced apply-first:** applied live (founder go) →
   verified → then committed the file + `applied_migrations.json` entry (version 100) together.
3. **Branch isolation** — a concurrent session's coach-completion batch is staged in the shared
   tree. → OPT-A committed via a path-restricted commit (only its own files), never a blanket add.
4. **Advisor claim** — verified 137 `auth_rls_initplan` (incl. the 8 EXISTS) + 5 `multiple_permissive`
   all clear to 0. Confirmed post-apply: advisor now returns only `unused_index` lints.
5. Gate-40 closure YAML does NOT apply (single-diagnose bug-fix, not a multi-category 20+-finding
   audit); `live_schema_columns.json` needs no regen (no column change) — both correctly omitted.

**Post-apply confirmation:** applied cleanly; behavior-preserving (A/B PASS post-apply); advisor
137→0 / 5→0. Rollback path is literal + executable if ever needed.
