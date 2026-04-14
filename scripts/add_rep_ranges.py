#!/usr/bin/env python3
"""
add_rep_ranges.py — Assigns rep_range to every exercise in exercise_library.json.

Rules (most-specific wins — evaluated top to bottom):
  1.  logging_type == 'timed'                   → "30-60"   (seconds)
  2.  logging_type == 'cardio'                  → "20-30"   (min/duration)
  3.  movement_pattern / category → cardio      → "20-30"
  4.  movement_pattern in warmup/cooldown/flexibility
      OR category in warmup/cooldown/flexibility → "10-15"
  5.  exercise_type in flexibility/dynamic_stretch/static_stretch/recovery → "10-15"
  6.  movement_pattern == 'core'                → "12-20"
  7.  exercise_type == 'isolation'              → "12-15"
     Name overrides inside isolation:
       - contains Curl / Extension / Raise / Fly → "12-15" (same, confirmed)
  8.  Compound + strength-tier (priority_tier==1):
       - name contains Deadlift + compound       → "5-8"
       - name contains Squat + compound          → "5-8"
       - name contains Barbell … Press (compound)→ "5-8"
       - name contains Close Grip Bench Press    → "5-8"
       - name contains Snatch / Clean / Jerk     → "5-8"
  9.  Compound Press (dumbbell / machine) + compound → "8-12"
  10. Any remaining compound                    → "8-12"
  11. Calisthenics (bodyweight strength moves)  → "8-12"
  12. Fallback                                  → "8-12"

The field is inserted after priority_tier (preserving all other field order).
"""

import json
import re
import sys
from pathlib import Path

LIBRARY_PATH = Path(__file__).parent.parent / "assets" / "data" / "exercise_library.json"


def assign_rep_range(ex: dict) -> str:
    name: str = ex.get("name", "")
    logging_type: str = ex.get("logging_type", "")
    movement_pattern: str = ex.get("movement_pattern", "")
    exercise_type: str = ex.get("exercise_type", "")
    category: str = ex.get("category", "")
    priority_tier: int = ex.get("priority_tier", 2)
    equipment: list = ex.get("equipment_needed", [])

    # ── Rule 1: timed ──────────────────────────────────────────────
    if logging_type == "timed":
        return "30-60"

    # ── Rule 2 & 3: cardio ─────────────────────────────────────────
    if logging_type == "cardio":
        return "20-30"
    if movement_pattern == "cardio" or category == "Cardio" or category == "cardio":
        return "20-30"

    # ── Rule 4: warmup / cooldown / flexibility (movement / category) ─
    MOBILITY_PATTERNS = {"warmup", "cooldown", "flexibility"}
    MOBILITY_CATS = {"warmup", "cooldown", "flexibility", "Warmup", "Cooldown", "Flexibility"}
    if movement_pattern in MOBILITY_PATTERNS or category in MOBILITY_CATS:
        return "10-15"

    # ── Rule 5: flexibility exercise_types ─────────────────────────
    FLEX_TYPES = {"flexibility", "dynamic_stretch", "static_stretch", "recovery", "activation"}
    if exercise_type in FLEX_TYPES:
        return "10-15"

    # ── Rule 6: core movement pattern ──────────────────────────────
    if movement_pattern == "core":
        return "12-20"

    # ── Rule 7: isolation ──────────────────────────────────────────
    if exercise_type == "isolation":
        return "12-15"

    # ── Rules 8-10: compound / calisthenics ────────────────────────
    name_upper = name.upper()

    is_compound = exercise_type in ("compound",)
    is_calisthenics = exercise_type == "calisthenics"
    has_barbell = any("Barbell" in eq or "barbell" in eq for eq in equipment)

    def name_contains(*terms):
        return any(t.upper() in name_upper for t in terms)

    if is_compound:
        # ── Rule 8: heavy compound → "5-8" ─────────────────────────
        # Deadlifts (all variants are heavy hip-dominant compounds)
        if name_contains("Deadlift"):
            return "5-8"

        # Squat variants — only barbell-loaded squats get 5-8
        # (Goblet, Hack Machine, Bulgarian with DBs → 8-12)
        if name_contains("Squat") and has_barbell:
            return "5-8"

        # Barbell bench / incline / decline bench press
        if name_contains("Barbell") and name_contains("Press"):
            return "5-8"

        # Close Grip Bench Press (tricep strength compound)
        if "CLOSE GRIP BENCH" in name_upper or "CLOSE-GRIP BENCH" in name_upper:
            return "5-8"

        # Olympic lifts (Clean, Snatch, Jerk)
        if name_contains("Snatch", "Clean", "Jerk", "Power Clean"):
            return "5-8"

        # Barbell Row, T-Bar Row (heavy compound pulls, priority 1)
        if name_contains("Barbell Bent Over Row", "T-Bar Row") or (
            name_contains("Row") and has_barbell and priority_tier == 1
        ):
            return "5-8"

        # ── Rule 9 & 10: all other compounds → "8-12" ──────────────
        return "8-12"

    # ── Calisthenics: bodyweight strength moves ─────────────────────
    if is_calisthenics:
        # Pure timed ones already caught by Rule 1 above.
        # Skill-holds that somehow slipped through get 8-12 for reps.
        return "8-12"

    # ── Fallback ────────────────────────────────────────────────────
    return "8-12"


def insert_after_priority_tier(exercise: dict, rep_range: str) -> dict:
    """Return a new ordered dict with rep_range inserted after priority_tier."""
    result = {}
    for key, value in exercise.items():
        result[key] = value
        if key == "priority_tier":
            result["rep_range"] = rep_range
    # Guard: if priority_tier wasn't present, append at end
    if "rep_range" not in result:
        result["rep_range"] = rep_range
    return result


def main():
    print(f"Reading: {LIBRARY_PATH}")
    with open(LIBRARY_PATH, encoding="utf-8") as f:
        raw = f.read()

    data = json.loads(raw)
    is_list = isinstance(data, list)
    exercises = data if is_list else data.get("exercises", [])

    # Skip if already patched (re-entrant safety)
    already_patched = sum(1 for e in exercises if "rep_range" in e)
    if already_patched == len(exercises):
        print(f"All {len(exercises)} exercises already have rep_range — nothing to do.")
        return

    updated = []
    stats: dict[str, int] = {}
    for ex in exercises:
        rr = assign_rep_range(ex)
        stats[rr] = stats.get(rr, 0) + 1
        updated.append(insert_after_priority_tier(ex, rr))

    # Write back
    if is_list:
        out_data = updated
    else:
        out_data = {**data, "exercises": updated}

    with open(LIBRARY_PATH, "w", encoding="utf-8") as f:
        json.dump(out_data, f, ensure_ascii=False, indent=2)

    print(f"\nDone — {len(updated)} exercises updated.")
    print("\nrep_range distribution:")
    for rr, count in sorted(stats.items(), key=lambda x: -x[1]):
        print(f"  {rr:>8}  →  {count} exercises")


if __name__ == "__main__":
    main()
