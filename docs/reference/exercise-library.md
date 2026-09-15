---
source: CLAUDE.md §17
migrated: 2026-05-18
status: scaffold
---

# Exercise Library Reference

250 exercises seeded in bundled JSON. Categories:
- Push (~35), Pull (~35), Legs (~40), Core (~25)
- Cardio (~20), Flexibility (~30), Calisthenics (~10)
- Indian Traditional (5): Dand, Baithak, Surya Namaskar, Malkhamb, Hindu Warrior Flow

Every exercise has: coaching_cues, common_mistakes, breathing_cue, warmup_protocol, pro_tip, MET_value, logging_type, difficulty, suitable_for, regression/progression links, image URLs.

## V4 Fields (on every exercise)
| Field | Type | Purpose |
|-------|------|---------|
| `movement_pattern` | string | One of 11 pipeline patterns (+ cardio/warmup/cooldown/flexibility for non-pipeline) |
| `target_focus` | string | Granular muscle target (e.g., "Lats (Width)", "Biceps (Short Head)") |
| `equipment_tier` | string[] | Subset of: bodyweight, home_dumbbells, basic_gym, full_gym |
| `rep_range` | string | Exercise-specific rep prescription (e.g., "5-8", "8-12", "12-15") |
| `priority_tier` | int | 1 (primary compound), 2 (secondary), 3 (accessory isolation) |
