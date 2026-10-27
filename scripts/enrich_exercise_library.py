#!/usr/bin/env python3
"""
Enrich exercise_library.json with V4 fields:
- Remap movement_pattern from 13 values to 11 V4 values
- Add target_focus (granular muscle target)
- Add equipment_tier (which tiers can do this)
- Add standard_swap (named equipment alternative)
- Add priority_tier (1=primary, 2=secondary, 3=accessory)
"""
import json
import sys
from pathlib import Path

LIBRARY_PATH = Path(__file__).parent.parent / "assets" / "data" / "exercise_library.json"

# ── Movement pattern remapping ──────────────────────────────────
MOVEMENT_REMAP = {
    "horizontal_push": "horizontal_push",
    "vertical_push": "vertical_push",
    "horizontal_pull": "horizontal_pull",
    "vertical_pull": "vertical_pull",
    "squat": "knee_dominant",
    "lunge": "knee_dominant",
    "hip_hinge": "hip_dominant",
    "isometric": "core",
    "rotation": "core",
    "static": "core",
    "dynamic": "core",
    "carry": "core",
    "cardio": "core",
}

# ── Equipment tier rules ────────────────────────────────────────
EQUIP_TO_TIER = {
    "none": "bodyweight",
    "bodyweight": "bodyweight",
    "resistance band": "home_dumbbells",
    "dumbbells": "home_dumbbells",
    "dumbbell": "home_dumbbells",
    "kettlebell": "home_dumbbells",
    "bench": "home_dumbbells",
    "pull-up bar": "home_dumbbells",
    "barbell": "basic_gym",
    "ez bar": "basic_gym",
    "cable machine": "basic_gym",
    "rope": "basic_gym",
    "incline bench": "basic_gym",
}

TIER_ORDER = ["bodyweight", "home_dumbbells", "basic_gym", "full_gym"]

def tier_index(t):
    return TIER_ORDER.index(t) if t in TIER_ORDER else 3

def compute_equipment_tier(equip_list):
    """Return list of tiers that can perform this exercise (from min required up to full_gym)."""
    if not equip_list:
        return ["bodyweight", "home_dumbbells", "basic_gym", "full_gym"]

    max_tier_idx = 0
    for item in equip_list:
        item_lower = item.lower().strip()
        if item_lower in EQUIP_TO_TIER:
            idx = tier_index(EQUIP_TO_TIER[item_lower])
        else:
            idx = 3
        max_tier_idx = max(max_tier_idx, idx)

    return TIER_ORDER[max_tier_idx:]

# ── Target focus rules ──────────────────────────────────────────
def compute_target_focus(ex):
    """Derive granular target_focus from primary_muscles + exercise_type + name."""
    muscles = [m.lower() for m in (ex.get("primary_muscles") or [])]
    name = ex.get("name", "").lower()
    category = ex.get("category", "").lower()
    etype = ex.get("exercise_type", "").lower()

    if not muscles:
        return "General"

    m0 = muscles[0]

    # Back exercises
    if "lat" in m0:
        if any(w in name for w in ["pulldown", "pull-up", "pull up", "chin"]):
            return "Lats (Width)"
        if any(w in name for w in ["row", "pullover"]):
            return "Lats (Thickness)"
        return "Lats"
    if "rhomboid" in m0 or "mid back" in m0:
        return "Mid Back (Thickness)"
    if "trap" in m0:
        if "upper" in m0 or "shrug" in name:
            return "Upper Traps"
        return "Traps"
    if "rear delt" in m0 or "posterior" in m0:
        return "Rear Delts"

    # Chest exercises
    if "chest" in m0 or "pec" in m0:
        if "upper" in m0 or "clavicular" in m0 or "incline" in name:
            return "Upper Chest"
        if "lower" in m0 or "costal" in m0 or "decline" in name:
            return "Lower Chest"
        return "Mid Chest"

    # Shoulder exercises
    if "delt" in m0 or "shoulder" in m0:
        if "front" in m0 or "anterior" in m0:
            return "Front Delts"
        if "side" in m0 or "lateral" in m0:
            return "Lateral Delts"
        if "rear" in m0 or "posterior" in m0:
            return "Rear Delts"
        return "Shoulders"

    # Arms
    if "bicep" in m0:
        if "brachialis" in m0:
            return "Brachialis"
        if "long head" in m0:
            return "Biceps (Long Head)"
        if "short head" in m0:
            return "Biceps (Short Head)"
        return "Biceps"
    if "tricep" in m0:
        if "long head" in m0:
            return "Triceps (Long Head)"
        if "lateral" in m0:
            return "Triceps (Lateral Head)"
        return "Triceps"
    if "forearm" in m0:
        return "Forearms"

    # Legs
    if "quad" in m0:
        return "Quads"
    if "hamstring" in m0:
        return "Hamstrings"
    if "glute" in m0:
        return "Glutes"
    if "calf" in m0 or "calve" in m0 or "gastrocnemius" in m0 or "soleus" in m0:
        return "Calves"
    if "hip" in m0 or "adduct" in m0 or "abduct" in m0:
        return "Hip"

    # Core
    if "ab" in m0 or "rectus" in m0 or "oblique" in m0 or "core" in m0 or "transverse" in m0:
        return "Core"

    # Lower back
    if "lower back" in m0 or "erector" in m0:
        return "Lower Back"

    return muscles[0]  # fallback to raw primary_muscle

# ── Priority tier rules ─────────────────────────────────────────
def compute_priority_tier(ex):
    """1=primary compound, 2=secondary compound or key isolation, 3=accessory isolation."""
    etype = ex.get("exercise_type", "").lower()
    is_foundational = ex.get("is_foundational", False)
    cns = ex.get("cns_demand", 1)

    if etype == "compound" and (is_foundational or cns >= 4):
        return 1
    if etype == "compound":
        return 2
    if etype == "calisthenics":
        return 1 if is_foundational else 2
    # Isolation
    if is_foundational:
        return 2
    return 3

# ── Movement pattern refinement ─────────────────────────────────
def refine_movement_pattern(ex, base_pattern):
    """Override movement_pattern for specific exercise types based on primary_muscles."""
    muscles = [m.lower() for m in (ex.get("primary_muscles") or [])]
    name = ex.get("name", "").lower()
    category = ex.get("category", "").lower()
    etype = ex.get("exercise_type", "").lower()

    # Bicep isolations → elbow_flexion
    if category == "pull" and etype == "isolation":
        if any("bicep" in m for m in muscles):
            return "elbow_flexion"
    # Guard: leg curls (Nordic, Lying, Reverse Nordic) stay as their base pattern
    LEG_CURL_NAMES = ["nordic curl", "leg curl", "reverse nordic curl"]
    if "curl" in name and etype == "isolation" and not any(lc in name for lc in LEG_CURL_NAMES):
        return "elbow_flexion"

    # Tricep isolations → elbow_extension
    if category == "push" and etype == "isolation":
        if any("tricep" in m for m in muscles):
            return "elbow_extension"
    if any(w in name for w in ["pushdown", "extension", "skullcrusher", "kickback"]) and etype == "isolation":
        if any("tricep" in m for m in muscles):
            return "elbow_extension"

    # Lateral/rear delt isolations → shoulder_isolation
    if etype == "isolation" and any(w in name for w in ["lateral raise", "face pull", "reverse fly", "reverse pec", "rear delt"]):
        return "shoulder_isolation"
    if etype == "isolation" and any("delt" in m and ("lateral" in m or "rear" in m or "side" in m or "posterior" in m) for m in muscles):
        return "shoulder_isolation"

    # Glute isolation → hip_isolation
    if etype == "isolation" and any("glute" in m for m in muscles):
        return "hip_isolation"
    if any(w in name for w in ["kickback", "abduct", "clamshell", "frog pump"]) and "glute" in " ".join(muscles):
        return "hip_isolation"

    # Shrugs → shoulder_isolation
    if "shrug" in name:
        return "shoulder_isolation"

    # Wrist curls → elbow_flexion (forearm)
    if "wrist" in name and "curl" in name:
        return "elbow_flexion"

    # Face Pull is compound but shoulder_isolation pattern
    if "face pull" in name:
        return "shoulder_isolation"

    # Band Pull Apart → shoulder_isolation
    if "band pull apart" in name:
        return "shoulder_isolation"

    return base_pattern

# ── Standard swap rules ─────────────────────────────────────────
STANDARD_SWAPS = {
    "Barbell Bench Press": "Dumbbell Bench Press",
    "Dumbbell Bench Press": "Push-Up",
    "Incline Dumbbell Press": "Incline Push-Up",
    "Lat Pulldown": "Pull Up",
    "Pull Up": "Inverted Row",
    "Barbell Bent Over Row": "Dumbbell Row",
    "Seated Cable Row": "Chest Supported Row",
    "Dumbbell Row": "Inverted Row",
    "Barbell Back Squat": "Goblet Squat",
    "Leg Press": "Bulgarian Split Squat",
    "Hack Squat": "Leg Press",
    "Romanian Deadlift": "Dumbbell Romanian Deadlift",
    "Deadlift": "Trap Bar Deadlift",
    "Barbell Shoulder Press": "Dumbbell Shoulder Press",
    "Cable Lateral Raise": "Dumbbell Lateral Raise",
    "Barbell Curl": "Dumbbell Curl",
    "Cable Curl": "Dumbbell Curl",
    "Cable Tricep Pushdown": "Overhead Dumbbell Extension",
    "Face Pull": "Band Pull Apart",
    "Cable Crunch": "Plank",
    "Hyperextension": "Good Morning",
    "Leg Extension": "Bodyweight Squat",
    "Lying Leg Curl": "Glute Bridge",
    "Standing Calf Raise": "Bodyweight Calf Raise",
}

def compute_standard_swap(ex):
    name = ex.get("name", "")
    if name in STANDARD_SWAPS:
        return STANDARD_SWAPS[name]
    equip = [e.lower() for e in (ex.get("equipment_needed") or [])]
    if any("cable" in e or "machine" in e for e in equip):
        return ""
    return ""

# ── Main enrichment ─────────────────────────────────────────────
def enrich():
    with open(LIBRARY_PATH, "r", encoding="utf-8") as f:
        exercises = json.load(f)

    stats = {"remapped": 0, "target_focus_set": 0, "equipment_tier_set": 0}

    for ex in exercises:
        # 1. Remap movement_pattern
        old_mp = ex.get("movement_pattern", "")
        base_mp = MOVEMENT_REMAP.get(old_mp, "core")
        new_mp = refine_movement_pattern(ex, base_mp)
        if new_mp != old_mp:
            stats["remapped"] += 1
        ex["movement_pattern"] = new_mp

        # 2. Add target_focus
        ex["target_focus"] = compute_target_focus(ex)
        stats["target_focus_set"] += 1

        # 3. Add equipment_tier
        ex["equipment_tier"] = compute_equipment_tier(ex.get("equipment_needed", []))
        stats["equipment_tier_set"] += 1

        # 4. Add standard_swap
        ex["standard_swap"] = compute_standard_swap(ex)

        # 5. Add priority_tier
        ex["priority_tier"] = compute_priority_tier(ex)

    with open(LIBRARY_PATH, "w", encoding="utf-8") as f:
        json.dump(exercises, f, indent=2, ensure_ascii=False)

    print(f"Enriched {len(exercises)} exercises")
    print(f"  movement_pattern remapped: {stats['remapped']}")
    print(f"  target_focus set: {stats['target_focus_set']}")
    print(f"  equipment_tier set: {stats['equipment_tier_set']}")

    # Print distribution
    from collections import Counter
    mp_dist = Counter(e["movement_pattern"] for e in exercises)
    print("\nMovement pattern distribution:")
    for k, v in sorted(mp_dist.items()):
        print(f"  {k}: {v}")

    pt_dist = Counter(e["priority_tier"] for e in exercises)
    print(f"\nPriority tier distribution: {dict(sorted(pt_dist.items()))}")

    tf_dist = Counter(e["target_focus"] for e in exercises)
    print(f"\nTarget focus distribution (top 20):")
    for k, v in tf_dist.most_common(20):
        print(f"  {k}: {v}")

if __name__ == "__main__":
    enrich()
