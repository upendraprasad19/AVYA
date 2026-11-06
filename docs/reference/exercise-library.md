---
source: CLAUDE.md §17
migrated: 2026-05-18
status: scaffold
---

# Exercise Library Reference

914 exercises seeded in bundled JSON (`assets/data/exercise_library.json`): the 285 original rows (`E###`) and the 629 rows Batch C1 added (`G####` and `N##`, `source` "exercise-gif-set", written by `scripts/add_library_batch_c_v15.js` from `scripts/data/library_batch_c_source.json`; 79 more converted rows are held with an owner, OI-437). The category counts below are the original 250-row scaffold and are no longer exact. Categories:
- Push (~35), Pull (~35), Legs (~40), Core (~25)
- Cardio (~20), Flexibility (~30), Calisthenics (~10)
- Indian Traditional (5): Dand, Baithak, Surya Namaskar, Malkhamb, Hindu Warrior Flow

Every exercise has: coaching_cues, common_mistakes, breathing_cue, warmup_protocol, pro_tip, MET_value, logging_type, difficulty, suitable_for, regression/progression links, image URLs.

## Media fields (introduced in library v16, 137 old rows added in v17; optional)
Three optional keys on the 754 rows that have a Wardroom animation: the 617 new rows that have one (the other 12 new rows have none) and, since the OI-443 release, 137 old `E` rows (see `docs/operations/EXERCISE_MEDIA.md`). A row carries **all three or none**; absent, never `null`; always the last three keys, in this order. Since Batch M2a (OI-440) the app reads them through `resolveMedia`.
| Field | Type | Purpose |
|-------|------|---------|
| `media_slug` | string | `<4-digit gif number>-<kebab(name)>`, for example `0103-barbell-standing-ab-rollout`. Two rows with one gif number share one slug. |
| `media_version` | int | Positive; 1 for every file in M1. A changed file is a new version (Batch M1c, OI-441). |
| `media_source` | string | The constant `wardroom`. |
The Storage object is `<media_slug>_v<media_version>.webp` in the **private** bucket `exercise-media`. The keys are written by the importer's media stage from `scripts/data/library_media_v16.json`; never edit them in the JSON by hand.

## V4 Fields (on every exercise)
| Field | Type | Purpose |
|-------|------|---------|
| `movement_pattern` | string | One of 11 pipeline patterns (+ cardio/warmup/cooldown/flexibility for non-pipeline) |
| `target_focus` | string | Granular muscle target (e.g., "Lats (Width)", "Biceps (Short Head)") |
| `equipment_tier` | string[] | Subset of: bodyweight, home_dumbbells, basic_gym, full_gym |
| `rep_range` | string | Exercise-specific rep prescription (e.g., "5-8", "8-12", "12-15") |
| `priority_tier` | int | 1 (primary compound), 2 (secondary), 3 (accessory isolation) |
| `primary_muscles` | string[] | The muscles the exercise trains, **ORDER MATTERS** (OI-454): in the 6-day build_muscle split the session set budget treats an exercise whose FIRST listed muscle is Quads (and which does not also list Hamstrings) as a quad exercise that does not credit Glutes, so put the main mover first. `quads_floor_6day_behavioral_test.dart` pins the known exceptions (rows listing Quads and Glutes with another muscle first, and the quad-first hip hinge Trap Bar Deadlift) and fails on a new one, so a library batch decides it on purpose. |
