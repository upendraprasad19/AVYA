#!/usr/bin/env python3
"""Validate exercise_library.json for V4 completeness and coverage."""
import json, sys
from pathlib import Path
from collections import Counter, defaultdict

LIBRARY_PATH = Path(__file__).parent.parent / "assets" / "data" / "exercise_library.json"

VALID_PATTERNS = {
    "horizontal_push", "vertical_push", "horizontal_pull", "vertical_pull",
    "knee_dominant", "hip_dominant", "core",
    "elbow_flexion", "elbow_extension", "shoulder_isolation", "hip_isolation",
}
VALID_TIERS = {"bodyweight", "home_dumbbells", "basic_gym", "full_gym"}
VALID_PRIORITIES = {1, 2, 3}

def validate():
    with open(LIBRARY_PATH, "r", encoding="utf-8") as f:
        exercises = json.load(f)

    errors = []

    # Field presence + validity
    for ex in exercises:
        name = ex.get("name", "UNNAMED")

        if not ex.get("movement_pattern"):
            errors.append(f"{name}: missing movement_pattern")
        elif ex["movement_pattern"] not in VALID_PATTERNS:
            errors.append(f"{name}: invalid movement_pattern '{ex['movement_pattern']}'")

        if not ex.get("target_focus"):
            errors.append(f"{name}: missing target_focus")

        tiers = ex.get("equipment_tier", [])
        if not tiers:
            errors.append(f"{name}: missing equipment_tier")
        elif not all(t in VALID_TIERS for t in tiers):
            errors.append(f"{name}: invalid equipment_tier {tiers}")

        pt = ex.get("priority_tier")
        if pt not in VALID_PRIORITIES:
            errors.append(f"{name}: invalid priority_tier {pt}")

    # Coverage matrix: equipment_tier x movement_pattern
    print("=== COVERAGE MATRIX (equipment_tier x movement_pattern) ===")
    coverage = defaultdict(lambda: defaultdict(int))
    for ex in exercises:
        mp = ex.get("movement_pattern", "")
        for tier in ex.get("equipment_tier", []):
            coverage[tier][mp] += 1

    gaps = []
    for tier in sorted(VALID_TIERS):
        for mp in sorted(VALID_PATTERNS):
            count = coverage[tier][mp]
            flag = " <-- GAP!" if count < 3 else ""
            print(f"  {tier:15s} x {mp:20s}: {count}{flag}")
            if count < 3:
                gaps.append((tier, mp, count))

    if errors:
        print(f"\n=== {len(errors)} ERRORS ===")
        for e in errors:
            print(f"  {e}")
    else:
        print(f"\n=== ALL {len(exercises)} EXERCISES VALID ===")

    if gaps:
        print(f"\n=== {len(gaps)} COVERAGE GAPS (< 3 exercises) ===")
        for tier, mp, count in gaps:
            print(f"  {tier} x {mp}: only {count}")
    else:
        print("\n=== ALL COVERAGE >= 3 ===")

    return len(errors) == 0

if __name__ == "__main__":
    ok = validate()
    sys.exit(0 if ok else 1)
