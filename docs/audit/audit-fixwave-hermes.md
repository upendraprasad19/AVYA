---
report: audit-fixwave Hermes pass (NUT-02 data-loss lens)
branch: audit-fixwave-2026-07-02
concept: nutrition_slot_merge (NUT-02, data-loss)
verdict: accepted
---

# Hermes report — NUT-02 (nutrition slot-merge data-loss)

NUT-02 (same-slot meal overwrite / data-loss) was voluntarily elevated to
Hermes-grade (data-loss on a sync/restore contract — the #1 recurring bug class).
The Hermes data-loss lens ran adversarially on the diff, then AGAIN on the fixed
code. It caught **3 P1 data-loss defects across the review passes — all fixed and
regression-tested before merge**:

1. **Orphan-on-shrink** — merged item upsert left an orphaned `nutrition_log_items`
   tail when a same-slot meal was deleted; deleted meal resurrected on restore and
   parent totals diverged from the item list. **Fix:** item tail-vacuum
   (`nutrition_log_items.delete().eq('log_id',…).gte('item_index', items.length)`).

2. **Partial-restore-loss** — per-slot-occupancy local-wins skipped restoring a
   cloud row whenever ANY local log existed for the slot, so a device with a stale
   PARTIAL local slot silently dropped the cloud items it lacked. **Fix:** a 3-way
   restore merge — skip only when the local slot is a content superset of the cloud
   row; otherwise union local+cloud and write one merged row.

3. **Duplicate-serving drop (re-Hermes)** — the union set-deduped by name|qty, so a
   genuine duplicate serving (a food logged twice) collapsed to one item (half the
   calories). **Fix:** a proper MULTISET union — keep `max(localCount, cloudCount)`
   items per signature (`nutritionSlotUnion` / `nutritionLocalSlotIsSuperset`, pure
   + unit-tested).

## Attack scenarios re-verified SAFE on the fixed code
shrink→restore (no resurrection); partial-local restore (missing cloud item
restored); unsynced-local preservation (local-wins keeps the unsynced item);
re-sync stability (converges, no growing duplication); flag-OFF clean fallback;
fiber included in restore + union totals; duplicate servings preserved.

## Residual (accepted, documented)
Two GENUINELY different foods sharing the same name+qty but different macros would
collapse to one — the same `(name, qty)` identity `_nlogKeyForRestore` already
uses; not a realistic loss for normal logging. No local re-key boot migration was
needed (the merge is at sync + restore only, flag-gated `disable_nutrition_slot_merge`,
rollback documented).

## Convergence
NUT-02 converged over 3 review passes (write-time→migration rejected; merge-at-sync
2×P1; multiset 1×P1) — each pass surfaced fewer/lesser issues. Behavioral +
structural tests in `test/contracts/nutrition_slot_merge_test.dart`; the full cloud
round-trip is the founder-gated live re-test on test7.

verdict: accepted
