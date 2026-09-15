---
review: audit-fixwave B-pass (self-triggered, §4.3)
branch: audit-fixwave-2026-07-02
blast_radius: platform
method: adversarial workflow — 4 context-blind review lenses over the uncommitted diff + adversarial verification of every finding
verdict: accepted
---

# B-pass — audit-fixwave (2026-07-02 audit fix batch)

Self-triggered before the `--no-ff` merge (§4.3). A `Workflow` ran 4 context-blind
review lenses (correctness/writer-reader-drift, coach-dedup-safety, gate/dead-code
ripple, Hermes NUT-02 data-loss) over the full uncommitted diff, then adversarially
verified each surfaced finding against the actual code (not the diagnose prose).

## Findings — 5 CONFIRMED, all fixed in-batch (no deferrals)

| # | Sev | Finding | Fix |
|---|-----|---------|-----|
| 1 | P1 | NUT-02 orphan-on-shrink: merged upsert left orphan `nutrition_log_items` tail when a same-slot meal was deleted → deleted meal resurrected on restore | item **tail-vacuum** (`delete().gte('item_index', N)`), mirrors template_exercises |
| 2 | P1 | NUT-02 partial-restore-loss: per-slot-occupancy local-wins dropped cloud items when the local slot was partial | **3-way restore merge** (skip iff local ⊇ cloud; else multiset-union, delete old keys, one row) |
| 3 | P2 | F1 wholesale-suppress lost a multi-exercise draft when a single-exercise `log_set` was present | exercise-NAME-aware dedup (`TypedLogCoverage`); suppress only when EVERY draft exercise is covered |
| 4 | P2 | F2 stale-drop keyed on `createdAt` hid the ✓ pill for slow confirms | key on the `intent_<id>_dispatched_at` settle marker |
| 5 | P2 | 4 new SoT concepts cited source-grep tests as `behavioral_test_path` | marked `presence_only: true` (honest classification) |

## Re-Hermes on the fixed NUT-02
A focused re-verification of the two NUT-02 fixes caught a THIRD, subtler P1 (the
union's set-dedup silently dropped a genuine duplicate serving) → fixed with a
**multiset union** (`nutritionSlotUnion`, keep max(localCount,cloudCount)), pure +
unit-tested. See `docs/audit/audit-fixwave-hermes.md`.

## Convergence
All 5 findings + the re-Hermes residual fixed with behavioral/structural
regression tests; full `flutter test` green; all pre-commit gates (SoT parity,
Gate-42 behavioral paths, Gate-40 closure, diagnose validators) green. No open
findings.

verdict: accepted
