---
reviewed_at: 2026-06-03T03:30:00+05:30
staged_against: b8d5c2 (saved-meal key writer/restore drift fix, folded into apk-obs-2026-06-02)
blast_radius: feature
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [data_loss_on_merge, idempotency, writer_change_side_effects, gate_completeness, boot_ordering]
findings_count: 5
verdict: accepted
---

# Code Review (B-pass) — saved-meal key migrator (b8d5c2)

A fresh context-blind Sonnet reviewer was given the live facts and asked to break
the re-key/delete migrator. It found 5 findings; 4 fixed in-batch, 1 surfaced.

## F3 — P1 — `String.hashCode` is Dart-VM-unstable + 32-bit — FIXED (the important one)
- **claim:** `savedMealKey` used `name.toLowerCase().trim().hashCode` — but the codebase's OWN `NlogKeyMigrator` H-17 note documents that `String.hashCode` is unstable across Dart VM/SDK versions (it caused a real v6→v7 migration bump) and is only 32-bit. An SDK upgrade could change the hash → new key → reintroduce the very duplicates this fix removes; and a 32-bit space risks a saved-meal hash-collision.
- **disposition:** **FIXED** — `savedMealKey` now uses **full UUID v5** over the name (deterministic across SDK versions + 122-bit → collision-free, closing F6 by construction). The restore now CALLS `savedMealKey` (single source — no writer/restore drift to maintain). Pinned by `saved_meal_key_canonical_test.dart` (asserts a full-uuid shape, not hashCode/ms).

## F6 — P0 (class) / negligible (prob) — distinct-meal hash-collision merges + deletes one — FIXED by F3
- **claim:** with a 32-bit key, two distinct meal names that hash-collide would group + one gets deleted.
- **disposition:** **FIXED** — full v5 UUID (122-bit) makes a distinct-name collision impossible in practice; the migrator only ever groups truly same-name rows. No same-name guard needed (would be dead code).

## F1 — P2 — delete-before-put risks total loss if `put` throws — FIXED
- **claim:** the migrator deleted legacy keys, THEN wrote the merged row; a throwing/interrupted `box.put` would leave the group's keys deleted and nothing written.
- **disposition:** **FIXED** — reordered to **put-first, then delete**. Idempotent: an interrupted put-then-delete re-enters the group next boot (old keys still present) and reproduces the result. (Sibling `NlogKeyMigrator` has the same delete-before-put ordering → surfaced as a follow-up; not folded — it's the pre-existing proven path.)

## F4 — P2 — same-name re-save silently reset `times_used` to 0 — FIXED
- **claim:** re-saving an existing meal name overwrote the row with `times_used: 0`, zeroing a re-log count.
- **disposition:** **FIXED** — `saveMealPreset` now reads the prior row and preserves `times_used` (re-save UPDATES, never resets the count).

## F5 — P3 — gate stripped `//` but not `/* */` comments — FIXED
- **claim:** the gate (and its mirror test) didn't strip block comments → a future `/* saved_meal_$x */` could false-trip / false-pass (pre-existing class per `feedback_source_grep_strip_comments_first.md`).
- **disposition:** **FIXED** — `check_saved_meal_key_canonical.dart` + the contract test now strip BOTH block and line comments (block comments blanked but newlines kept so line numbers hold). (Sibling nlog/exlog gates have the same gap → follow-up.)

## Lenses clean
- writer_change_side_effects (callers): `nutrition_provider` delegators don't store the returned key; `relogSavedMeal` reads `id` from the Hive map which the migrator updates to the new key. No caller breaks.
- idempotency: flag-write failure → next boot re-runs but all groups are canonical singletons → safe no-op.
- boot_ordering: runs after `openForUser` (boxes open), before `/home` reads `savedMealsProvider`; wrapped in try/catch (non-fatal).

## Verdict: accepted
F3+F6 fixed via UUID v5; F1 via put-before-delete; F4 via times_used preservation; F5 via block-comment stripping. Two pre-existing siblings surfaced as follow-ups (NlogKeyMigrator delete-ordering; nlog/exlog gate comment-stripping).
