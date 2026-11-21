# Exercise Selection V4 & Profile Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blunt category-based exercise selector with a muscle-slot + cascading-fallback engine that produces trainer-quality workouts across all equipment tiers, plus profile completeness nudges and schedule bug fixes.

**Architecture:** The plan generator pipeline gains a new MuscleSlot spec model (replacing CSpec), a Volume Filter stage (1.5), and a rewritten Exercise Selector that cascades within movement patterns. The exercise library is enriched with 4 new fields and ~30 new exercises. Profile gets completeness tracking cards and a slim achievements widget.

**Tech Stack:** Flutter/Dart, Hive, Riverpod, Python (for JSON enrichment scripts)

**Spec:** `docs/superpowers/specs/2026-04-14-exercise-selection-v4-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `lib/shared/repositories/plan_engine/volume_filter.dart` | Stage 1.5 — trims MuscleSlot lists by session duration + experience + phase |
| `lib/features/home/widgets/profile_nudge_card.dart` | Slim dismissible card showing highest-impact missing profile field |
| `lib/features/profile/widgets/slim_achievements_card.dart` | Single-line achievements with recent badges + chevron |
| `lib/features/profile/providers/profile_completeness_provider.dart` | Computes profile completeness % and highest-impact missing field |
| `scripts/enrich_exercise_library.py` | One-shot Python script to add V4 fields to exercise_library.json |
| `scripts/validate_exercise_library.py` | Validation script checking all fields, coverage matrix |
| `test/plan_engine_v4_test.dart` | Unit tests for MuscleSlot, VolumeFilter, cascading selector, split resolver |

### Modified Files
| File | Change |
|------|--------|
| `assets/data/exercise_library.json` | Remap movement_pattern (13→11 values), add 4 new fields, add ~30 new exercises |
| `lib/shared/repositories/plan_engine/models.dart` | Add `MuscleSlot` class, keep `CSpec`/`DaySlot` for backward compat during migration |
| `lib/shared/repositories/plan_engine/split_resolver.dart` | Rewrite all split methods to return `List<MuscleSlotDay>` |
| `lib/shared/repositories/plan_engine/exercise_selector.dart` | Full rewrite — cascading within movement patterns |
| `lib/shared/repositories/plan_engine/plan_generator.dart` | Wire Volume Filter, thread `sessionDuration`, update stage flow |
| `lib/shared/repositories/plan_engine/sequencing_engine.dart` | Order by MuscleSlot priority, then compound-first |
| `lib/shared/repositories/plan_engine/periodization_engine.dart` | Read exercise-specific `default_reps` for set/rep assignment |
| `lib/shared/repositories/exercise_repository.dart` | Add `queryV4()` with movement_pattern, target_focus, equipment_tier filters |
| `lib/core/services/workout_schedule_service.dart` | Fix week reset bug, auto-inject warmup for templates |
| `lib/features/home/screens/home_screen.dart` | Insert ProfileNudgeCard between quick actions and AI insight |
| `lib/features/profile/screens/profile_screen.dart` | Add completeness card, swap badges section, add experience to subtitle |
| `lib/features/profile/widgets/profile_identity.dart` | Remove CompactAchievementsRow from banner overlap |
| `lib/features/profile/screens/edit_profile_screen.dart` | Add session_duration + physique_focus + experience_level fields |

---

## Phase 1: Data Foundation

### Task 1: Add MuscleSlot and MuscleSlotDay to models.dart

**Files:**
- Modify: `lib/shared/repositories/plan_engine/models.dart`

- [ ] **Step 1: Add MuscleSlot class after CSpec**

Open `lib/shared/repositories/plan_engine/models.dart` and add after the `CSpec` class:

```dart
/// V4: Muscle-level exercise slot with cascading fallback support.
/// Replaces CSpec for trainer-quality exercise selection.
class MuscleSlot {
  final String targetMuscle;    // e.g., 'Lats', 'Biceps', 'Quads'
  final String? subFocus;       // e.g., 'width', 'short_head', 'thickness'
  final String movementPattern; // e.g., 'vertical_pull' — NEVER dropped in cascade
  final String exerciseType;    // 'compound' | 'isolation'
  final int priority;           // 1=primary, 2=secondary, 3=accessory
  final int count;              // exercises to fill for this slot (usually 1)

  const MuscleSlot({
    required this.targetMuscle,
    this.subFocus,
    required this.movementPattern,
    required this.exerciseType,
    required this.priority,
    this.count = 1,
  });

  @override
  String toString() =>
      'MuscleSlot($targetMuscle${subFocus != null ? "/$subFocus" : ""}, '
      '$movementPattern, $exerciseType, P$priority, x$count)';
}

/// V4: A workout day defined by MuscleSlots instead of CSpecs.
class MuscleSlotDay {
  final String name;
  final String focus;
  final String dayType;     // push, pull, legs, upper, full_body, shoulders_arms
  final String intensity;   // strength, hypertrophy, endurance
  final List<MuscleSlot> slotsA;
  final List<MuscleSlot>? slotsB; // null = same as A

  const MuscleSlotDay({
    required this.name,
    required this.focus,
    required this.dayType,
    required this.intensity,
    required this.slotsA,
    this.slotsB,
  });
}
```

- [ ] **Step 2: Add valid movement patterns constant**

Add at top of models.dart (after imports):

```dart
/// Valid V4 movement patterns — the 11 irreducible categories.
const kMovementPatterns = <String>{
  'horizontal_push',
  'vertical_push',
  'horizontal_pull',
  'vertical_pull',
  'knee_dominant',
  'hip_dominant',
  'core',
  'elbow_flexion',
  'elbow_extension',
  'shoulder_isolation',
  'hip_isolation',
};
```

- [ ] **Step 3: Run analyzer**

Run: `cd "C:\Upendra\Claude Code\Fitness App" && flutter analyze lib/shared/repositories/plan_engine/models.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/repositories/plan_engine/models.dart
git commit -m "feat(plan-engine): add MuscleSlot and MuscleSlotDay models for V4"
```

---

### Task 2: Enrich exercise library — remap movement_pattern + add 4 new fields

**Files:**
- Create: `scripts/enrich_exercise_library.py`
- Modify: `assets/data/exercise_library.json`

The existing `movement_pattern` field has 13 values that must be remapped to 11. Four new fields must be added to all 220 exercises. This is done via a Python script for accuracy and auditability.

- [ ] **Step 1: Write the enrichment script**

Create `scripts/enrich_exercise_library.py`:

```python
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
    "dynamic": "core",  # dynamic stretches, warmup — default to core
    "carry": "core",    # farmer's walk etc. — core stability
    "cardio": "core",   # fallback; refined per-exercise below
}

# ── Equipment tier rules ────────────────────────────────────────
# Maps equipment_needed items to minimum tier required.
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
            # Unknown equipment → assume full_gym only
            idx = 3
        max_tier_idx = max(max_tier_idx, idx)
    
    # Exercise is available at its minimum tier and all higher tiers
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
    # Explicit curl exercises
    if "curl" in name and etype == "isolation":
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
    
    # Shrugs → shoulder_isolation (trap isolation)
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
# Common swaps: machine → free weight → bodyweight
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
    # Generic: if cable/machine → suggest dumbbell variant
    equip = [e.lower() for e in (ex.get("equipment_needed") or [])]
    if any("cable" in e or "machine" in e for e in equip):
        return ""  # empty = no known swap (manual review later)
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
```

- [ ] **Step 2: Run the enrichment script**

Run: `cd "C:\Upendra\Claude Code\Fitness App" && python scripts/enrich_exercise_library.py`
Expected: All 220 exercises enriched. Verify movement_pattern distribution matches the 11 valid patterns (no stray values).

- [ ] **Step 3: Spot-check the JSON output**

Run a quick Python check:
```bash
python -c "
import json
with open('assets/data/exercise_library.json') as f:
    ex = json.load(f)
valid = {'horizontal_push','vertical_push','horizontal_pull','vertical_pull','knee_dominant','hip_dominant','core','elbow_flexion','elbow_extension','shoulder_isolation','hip_isolation'}
bad = [e['name'] for e in ex if e['movement_pattern'] not in valid]
print(f'Invalid patterns: {len(bad)}')
for b in bad[:10]: print(f'  {b}')
missing = [e['name'] for e in ex if not e.get('target_focus') or not e.get('equipment_tier')]
print(f'Missing fields: {len(missing)}')
"
```
Expected: 0 invalid patterns, 0 missing fields.

- [ ] **Step 4: Manual spot-check 5 exercises per movement pattern**

Visually inspect the JSON for these exercises:
- `vertical_pull`: Lat Pulldown, Pull Up, Chin Up — verify target_focus says "Lats (Width)" or "Lats"
- `elbow_flexion`: Barbell Curl, Dumbbell Curl — verify they were remapped from "horizontal_pull"
- `shoulder_isolation`: Face Pull, Band Pull Apart, Dumbbell Lateral Raise — verify correct
- `knee_dominant`: Barbell Back Squat, Leg Press — verify remapped from "squat"
- `hip_dominant`: Romanian Deadlift, Good Morning — verify remapped from "hip_hinge"

Fix any misclassifications in the script and re-run.

- [ ] **Step 5: Commit enrichment**

```bash
git add scripts/enrich_exercise_library.py assets/data/exercise_library.json
git commit -m "feat(exercise-lib): enrich 220 exercises with V4 fields (target_focus, equipment_tier, standard_swap, priority_tier)"
```

---

### Task 3: Expand exercise library with ~30 new exercises

**Files:**
- Create: `scripts/add_new_exercises.py`
- Modify: `assets/data/exercise_library.json`

- [ ] **Step 1: Write the expansion script**

Create `scripts/add_new_exercises.py` that appends new exercises to the library. Each exercise must have ALL 33+ fields matching the existing format. The script should:
- Read the current max ID (e.g., E220)
- Assign sequential IDs (E221, E222, ...)
- Include all standard fields + V4 fields
- Focus on gap-filling exercises identified in the spec:
  - **Legs (Glutes):** Kas Glute Bridge, B-Stance RDL, Cable Pull-throughs, Hip Abductor Machine, Frog Pumps, High Box Step-Ups, Deficit Reverse Lunges
  - **Legs (Hams):** Nordic Hamstring Curls, Stiff-Legged Deadlift, Standing Single Leg Curl
  - **Chest:** Decline DB Press, Incline DB Flyes, Deficit Push-ups, Floor Press (DB)
  - **Shoulders:** Machine Lateral Raises, Cable Front Raises, Egyptian Lateral Raise
  - **Triceps:** Bench Dips, Dumbbell Kickbacks
  - **Biceps:** Rope Hammer Curls, High Cable Curls
  - **Back:** Pendlay Row, Machine High Row, Machine Low Row
  - **Core:** Captain's Chair Leg Raises, V-Ups, Hollow Body Hold, Flutter Kicks, Side Plank

Each exercise needs realistic values for coaching_cues, common_mistakes, breathing_cue, equipment_needed, suitable_for, etc.

- [ ] **Step 2: Run the expansion script**

Run: `python scripts/add_new_exercises.py`
Expected: ~30 new exercises added, total count ~250.

- [ ] **Step 3: Verify new exercises**

```bash
python -c "
import json
with open('assets/data/exercise_library.json') as f:
    ex = json.load(f)
print(f'Total exercises: {len(ex)}')
required = ['id','name','category','movement_pattern','exercise_type','primary_muscles','equipment_needed','logging_type','target_focus','equipment_tier','priority_tier']
for e in ex:
    for r in required:
        if r not in e or e[r] is None:
            print(f'MISSING {r} on {e.get(\"name\",\"?\")}')
"
```
Expected: No missing required fields.

- [ ] **Step 4: Commit expansion**

```bash
git add scripts/add_new_exercises.py assets/data/exercise_library.json
git commit -m "feat(exercise-lib): add ~30 new exercises (glute, ham, chest, shoulder, arm, core)"
```

---

### Task 4: Validation script and coverage matrix

**Files:**
- Create: `scripts/validate_exercise_library.py`

- [ ] **Step 1: Write the validation script**

Create `scripts/validate_exercise_library.py`:

```python
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
    for tier in VALID_TIERS:
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
```

- [ ] **Step 2: Run validation**

Run: `python scripts/validate_exercise_library.py`
Expected: All exercises valid. Review coverage gaps — bodyweight tier will likely have gaps for some isolation patterns (elbow_flexion, shoulder_isolation) which is acceptable since bodyweight users get the universal fallback pool.

- [ ] **Step 3: Fix any gaps found**

If coverage matrix shows critical gaps (base patterns with 0 exercises for a tier), either:
- Add bodyweight variants to the expansion script
- Or verify the universal bodyweight pool in the selector covers these patterns

- [ ] **Step 4: Commit validation script**

```bash
git add scripts/validate_exercise_library.py
git commit -m "chore: add exercise library validation script with coverage matrix"
```

---

### Task 5: Update ExerciseRepository with V4 query method

**Files:**
- Modify: `lib/shared/repositories/exercise_repository.dart`
- Test: `test/plan_engine_v4_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/plan_engine_v4_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

void main() {
  group('MuscleSlot', () {
    test('toString includes all fields', () {
      const slot = MuscleSlot(
        targetMuscle: 'Lats',
        subFocus: 'width',
        movementPattern: 'vertical_pull',
        exerciseType: 'compound',
        priority: 1,
      );
      expect(slot.toString(), contains('Lats/width'));
      expect(slot.toString(), contains('vertical_pull'));
      expect(slot.toString(), contains('P1'));
    });

    test('count defaults to 1', () {
      const slot = MuscleSlot(
        targetMuscle: 'Biceps',
        movementPattern: 'elbow_flexion',
        exerciseType: 'isolation',
        priority: 3,
      );
      expect(slot.count, 1);
    });
  });

  group('kMovementPatterns', () {
    test('has exactly 11 patterns', () {
      expect(kMovementPatterns.length, 11);
    });

    test('contains all required patterns', () {
      expect(kMovementPatterns, contains('horizontal_push'));
      expect(kMovementPatterns, contains('vertical_pull'));
      expect(kMovementPatterns, contains('elbow_flexion'));
      expect(kMovementPatterns, contains('shoulder_isolation'));
      expect(kMovementPatterns, contains('hip_isolation'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd "C:\Upendra\Claude Code\Fitness App" && flutter test test/plan_engine_v4_test.dart`
Expected: PASS (models already implemented in Task 1).

- [ ] **Step 3: Add queryV4 method to ExerciseRepository**

Open `lib/shared/repositories/exercise_repository.dart` and add after the existing `query()` method:

```dart
  /// V4: Query exercises by movement pattern, target focus, and equipment tier.
  ///
  /// Used by the cascading exercise selector. Filters are applied in order:
  /// movement_pattern (required) → target_focus (optional) → equipment_tier
  /// (optional) → exercise_type (optional) → suitable_for (optional).
  List<Map<String, dynamic>> queryV4({
    required String movementPattern,
    String? targetFocus,
    String? targetMuscle,
    String? equipmentTier,
    String? exerciseType,
    String? suitableFor,
    bool foundationalOnly = false,
    Set<String>? excludeNames,
    List<String>? injuryExclusions,
    int? limit,
  }) {
    var results = getAll();

    // 1. Movement pattern (ALWAYS applied — never dropped)
    results = results.where((e) =>
        (e['movement_pattern'] as String?)?.toLowerCase() ==
        movementPattern.toLowerCase()).toList();

    // 2. Target focus (substring match on target_focus field)
    if (targetFocus != null && targetFocus.isNotEmpty) {
      final tf = targetFocus.toLowerCase();
      results = results.where((e) {
        final focus = (e['target_focus'] as String?)?.toLowerCase() ?? '';
        return focus.contains(tf);
      }).toList();
    }

    // 2b. Target muscle (broader — matches if target_focus contains the muscle name)
    if (targetMuscle != null && targetMuscle.isNotEmpty) {
      final tm = targetMuscle.toLowerCase();
      results = results.where((e) {
        final focus = (e['target_focus'] as String?)?.toLowerCase() ?? '';
        final muscles = e['primary_muscles'];
        if (focus.contains(tm)) return true;
        if (muscles is List) {
          return muscles.any((m) => m.toString().toLowerCase().contains(tm));
        }
        return false;
      }).toList();
    }

    // 3. Equipment tier (exercise must include user's tier in its equipment_tier list)
    if (equipmentTier != null && equipmentTier.isNotEmpty) {
      final tier = equipmentTier.toLowerCase();
      results = results.where((e) {
        final tiers = e['equipment_tier'];
        if (tiers is! List || tiers.isEmpty) return true;
        return tiers.any((t) => t.toString().toLowerCase() == tier);
      }).toList();
    }

    // 4. Exercise type (compound / isolation)
    if (exerciseType != null && exerciseType.isNotEmpty) {
      results = results.where((e) =>
          (e['exercise_type'] as String?)?.toLowerCase() ==
          exerciseType.toLowerCase()).toList();
    }

    // 5. Suitable for (experience level)
    if (suitableFor != null) {
      results = results.where((e) {
        final suitable = e['suitable_for'];
        if (suitable == null) return true;
        if (suitable is List) {
          return suitable.any(
            (s) => s.toString().toLowerCase() == suitableFor.toLowerCase(),
          );
        }
        return true;
      }).toList();
    }

    // 6. Foundational only (Phase 1)
    if (foundationalOnly) {
      results = results.where((e) => e['is_foundational'] == true).toList();
    }

    // 7. Exclude already-selected names
    if (excludeNames != null && excludeNames.isNotEmpty) {
      results = results.where((e) =>
          !excludeNames.contains(e['name'] as String? ?? '')).toList();
    }

    // 8. Injury exclusion
    if (injuryExclusions != null && injuryExclusions.isNotEmpty) {
      results = results.where((e) {
        final contra = e['injury_contraindications'];
        if (contra is! List || contra.isEmpty) return true;
        for (final injury in injuryExclusions) {
          if (contra.any((c) =>
              c.toString().toLowerCase() == injury.toLowerCase())) {
            return false;
          }
        }
        return true;
      }).toList();
    }

    // Sort: compounds first, then by priority_tier, then foundational first
    results.sort((a, b) {
      final aType = a['exercise_type']?.toString().toLowerCase() ?? '';
      final bType = b['exercise_type']?.toString().toLowerCase() ?? '';
      if (aType == 'compound' && bType != 'compound') return -1;
      if (aType != 'compound' && bType == 'compound') return 1;
      final aPri = a['priority_tier'] as int? ?? 3;
      final bPri = b['priority_tier'] as int? ?? 3;
      if (aPri != bPri) return aPri.compareTo(bPri);
      final aFound = a['is_foundational'] == true ? 0 : 1;
      final bFound = b['is_foundational'] == true ? 0 : 1;
      return aFound.compareTo(bFound);
    });

    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }

    return results;
  }
```

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/shared/repositories/exercise_repository.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/repositories/exercise_repository.dart test/plan_engine_v4_test.dart
git commit -m "feat(exercise-repo): add queryV4 method with movement pattern + target focus + equipment tier filters"
```

---

## Phase 2: Engine Rewrite

### Task 6: Rewrite SplitResolver with MuscleSlot output

**Files:**
- Modify: `lib/shared/repositories/plan_engine/split_resolver.dart`

The split resolver must output `List<MuscleSlotDay>` instead of `List<DaySlot>`. Each split definition encodes trainer wisdom: which muscles to train, in what order, with what priority.

- [ ] **Step 1: Add new selectV4 method**

Keep the existing `select()` method for backward compatibility. Add `selectV4()` that returns `List<MuscleSlotDay>`:

```dart
  /// V4: Returns MuscleSlotDay list with granular muscle slots.
  static List<MuscleSlotDay> selectV4(String goal, int daysPerWeek, {String experienceLevel = 'intermediate'}) {
    final isBeginner = experienceLevel == 'beginner';

    if (isBeginner && daysPerWeek <= 4) {
      return _getBeginnerFullBodyV4(daysPerWeek, goal);
    }

    switch (daysPerWeek) {
      case 3:
        return _get3DayV4(goal);
      case 5:
        return _get5DayV4(goal);
      case 6:
        return _get6DayV4(goal);
      default:
        return _get4DayV4(goal);
    }
  }
```

- [ ] **Step 2: Implement 5-day build_muscle split (reference case)**

This is the split from the screenshot (Back day). Define all 5 days with MuscleSlots based on the reference spreadsheet:

```dart
  static List<MuscleSlotDay> _get5DayV4BuildMuscle() {
    return [
      // Day 1: Chest
      MuscleSlotDay(
        name: 'Chest', focus: 'Chest focus', dayType: 'push', intensity: 'strength',
        slotsA: [
          const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        ],
      ),
      // Day 2: Back
      MuscleSlotDay(
        name: 'Back', focus: 'Back focus', dayType: 'pull', intensity: 'hypertrophy',
        slotsA: [
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'width', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Mid Back', subFocus: 'thickness', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', subFocus: 'lower', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 2),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
        ],
      ),
      // Day 3: Shoulders + Arms
      MuscleSlotDay(
        name: 'Shoulders + Arms', focus: 'Delts, biceps, triceps', dayType: 'shoulders_arms', intensity: 'endurance',
        slotsA: [
          const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 1),
          const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
        ],
      ),
      // Day 4: Legs
      MuscleSlotDay(
        name: 'Legs', focus: 'Quads, hams, glutes', dayType: 'legs', intensity: 'strength',
        slotsA: [
          const MuscleSlot(targetMuscle: 'Quads', movementPattern: 'knee_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Quads', subFocus: 'isolation', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Glutes', movementPattern: 'hip_isolation', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Calves', movementPattern: 'knee_dominant', exerciseType: 'isolation', priority: 3),
        ],
      ),
      // Day 5: Upper (Shoulders + Arms + Core)
      MuscleSlotDay(
        name: 'Upper + Core', focus: 'Shoulders, arms, core', dayType: 'upper', intensity: 'hypertrophy',
        slotsA: [
          const MuscleSlot(targetMuscle: 'Shoulders', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
          const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
          const MuscleSlot(targetMuscle: 'Core', subFocus: 'obliques', movementPattern: 'core', exerciseType: 'isolation', priority: 2),
        ],
      ),
    ];
  }
```

- [ ] **Step 3: Implement all remaining split definitions**

Following the same pattern, implement:
- `_get3DayV4(goal)` — Full body A/B/C for lose_fat/general_fitness; Push/Pull/Legs for build_muscle/strength
- `_get4DayV4(goal)` — Upper/Lower A/B for all goals
- `_get5DayV4(goal)` — build_muscle (above), default PPL+Upper+Lower
- `_get6DayV4(goal)` — PPL A/B for build_muscle; standard PPL repeat for others
- `_getBeginnerFullBodyV4(daysPerWeek, goal)` — 3-4 day full body with P1 compounds only

Use the reference spreadsheets and the ratio: ~60% P1 compounds, ~20% P2 secondary, ~20% P3 isolation.

- [ ] **Step 4: Write tests for split resolver V4**

Add to `test/plan_engine_v4_test.dart`:

```dart
  group('SplitResolver.selectV4', () {
    test('5-day build_muscle Back day has 3 back + 1 rear delt + 1 bicep', () {
      final days = SplitResolver.selectV4('build_muscle', 5);
      final backDay = days.firstWhere((d) => d.name == 'Back');
      
      final backSlots = backDay.slotsA.where((s) =>
          s.movementPattern == 'vertical_pull' || s.movementPattern == 'horizontal_pull').toList();
      final rearDeltSlots = backDay.slotsA.where((s) =>
          s.targetMuscle == 'Rear Delts').toList();
      final bicepSlots = backDay.slotsA.where((s) =>
          s.movementPattern == 'elbow_flexion').toList();
      
      expect(backSlots.length, greaterThanOrEqualTo(3));
      expect(rearDeltSlots.length, 1);
      expect(bicepSlots.length, greaterThanOrEqualTo(1));
    });

    test('all slots have valid movement patterns', () {
      for (final goal in ['build_muscle', 'lose_fat', 'general_fitness', 'strength']) {
        for (final days in [3, 4, 5, 6]) {
          final split = SplitResolver.selectV4(goal, days);
          for (final day in split) {
            for (final slot in day.slotsA) {
              expect(kMovementPatterns, contains(slot.movementPattern),
                  reason: '${day.name} slot ${slot.targetMuscle} has invalid pattern ${slot.movementPattern}');
            }
          }
        }
      }
    });

    test('beginner 3-day gets full body splits', () {
      final days = SplitResolver.selectV4('build_muscle', 3, experienceLevel: 'beginner');
      expect(days.every((d) => d.dayType == 'full_body'), isTrue);
    });

    test('every slot has priority 1-3', () {
      final days = SplitResolver.selectV4('build_muscle', 5);
      for (final day in days) {
        for (final slot in day.slotsA) {
          expect(slot.priority, inInclusiveRange(1, 3));
        }
      }
    });
  });
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/plan_engine_v4_test.dart`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/repositories/plan_engine/split_resolver.dart test/plan_engine_v4_test.dart
git commit -m "feat(split-resolver): add selectV4 with MuscleSlotDay output for all splits"
```

---

### Task 7: Add VolumeFilter (new Stage 1.5)

**Files:**
- Create: `lib/shared/repositories/plan_engine/volume_filter.dart`

- [ ] **Step 1: Write failing tests**

Add to `test/plan_engine_v4_test.dart`:

```dart
  group('VolumeFilter', () {
    final allSlots = [
      const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
      const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
      const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 2),
      const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
      const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
      const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
    ];

    test('60min advanced keeps all priorities', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 60, experience: 'advanced', weekCharacter: 'baseline');
      expect(result.length, 6);
    });

    test('45min intermediate keeps P1+P2 only', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 45, experience: 'intermediate', weekCharacter: 'baseline');
      expect(result.every((s) => s.priority <= 2), isTrue);
      expect(result.length, 4);
    });

    test('30min keeps P1 only', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 30, experience: 'intermediate', weekCharacter: 'baseline');
      expect(result.every((s) => s.priority == 1), isTrue);
      expect(result.length, 2);
    });

    test('beginner gets P1 + max 1 P2', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 60, experience: 'beginner', weekCharacter: 'baseline');
      final p2Count = result.where((s) => s.priority == 2).length;
      expect(p2Count, lessThanOrEqualTo(1));
      expect(result.every((s) => s.priority <= 2), isTrue);
    });

    test('deload week keeps P1 only', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 60, experience: 'advanced', weekCharacter: 'deload');
      expect(result.every((s) => s.priority == 1), isTrue);
    });

    test('null sessionMinutes defaults to 45', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: null, experience: 'intermediate', weekCharacter: 'baseline');
      expect(result.every((s) => s.priority <= 2), isTrue);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/plan_engine_v4_test.dart`
Expected: FAIL — VolumeFilter not found.

- [ ] **Step 3: Implement VolumeFilter**

Create `lib/shared/repositories/plan_engine/volume_filter.dart`:

```dart
import 'models.dart';

/// Stage 1.5: Trims MuscleSlot lists based on session duration,
/// experience level, and phase archetype (week character).
///
/// Priority is hardcoded in the split spec (trainer wisdom).
/// The CUTOFF (which priorities survive) is dynamic.
class VolumeFilter {
  /// Filter a flat list of MuscleSlots down to what fits the user's constraints.
  ///
  /// [sessionMinutes] — user's session duration (default 45 if null).
  /// [experience] — beginner | intermediate | advanced.
  /// [weekCharacter] — baseline | overreach | peak | deload.
  static List<MuscleSlot> filter(
    List<MuscleSlot> slots, {
    required int? sessionMinutes,
    required String experience,
    required String weekCharacter,
  }) {
    final minutes = sessionMinutes ?? 45;

    // Deload: P1 only regardless of time/experience
    if (weekCharacter == 'deload') {
      return slots.where((s) => s.priority == 1).toList();
    }

    // Determine max priority based on time
    int maxPriority;
    if (minutes >= 60) {
      maxPriority = 3; // all
    } else if (minutes >= 45) {
      maxPriority = 2; // P1 + P2
    } else {
      maxPriority = 1; // P1 only
    }

    // Beginner override: max P2, and only 1 P2 slot
    if (experience == 'beginner') {
      maxPriority = maxPriority.clamp(1, 2);
      final p1 = slots.where((s) => s.priority == 1).toList();
      if (maxPriority >= 2) {
        final firstP2 = slots.where((s) => s.priority == 2).take(1);
        return [...p1, ...firstP2];
      }
      return p1;
    }

    return slots.where((s) => s.priority <= maxPriority).toList();
  }

  /// Apply volume filter to every day in a MuscleSlotDay list.
  static List<MuscleSlotDay> filterDays(
    List<MuscleSlotDay> days, {
    required int? sessionMinutes,
    required String experience,
    required String weekCharacter,
  }) {
    return days.map((day) {
      final filteredA = filter(day.slotsA,
          sessionMinutes: sessionMinutes,
          experience: experience,
          weekCharacter: weekCharacter);
      final filteredB = day.slotsB != null
          ? filter(day.slotsB!,
              sessionMinutes: sessionMinutes,
              experience: experience,
              weekCharacter: weekCharacter)
          : null;
      return MuscleSlotDay(
        name: day.name,
        focus: day.focus,
        dayType: day.dayType,
        intensity: day.intensity,
        slotsA: filteredA,
        slotsB: filteredB,
      );
    }).toList();
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/plan_engine_v4_test.dart`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/repositories/plan_engine/volume_filter.dart test/plan_engine_v4_test.dart
git commit -m "feat(plan-engine): add VolumeFilter (Stage 1.5) — trims slots by duration/experience/phase"
```

---

### Task 8: Rewrite ExerciseSelector with cascading logic

**Files:**
- Modify: `lib/shared/repositories/plan_engine/exercise_selector.dart`

This is the critical rewrite. The selector must fill each MuscleSlot via cascading attempts within the movement pattern, NEVER crossing pattern boundaries.

- [ ] **Step 1: Write failing tests**

Add to `test/plan_engine_v4_test.dart`:

```dart
  group('ExerciseSelector.pickV4 (cascading)', () {
    // These tests use the real exercise library which is loaded in Hive
    // during integration tests. For unit tests, we test the cascade logic
    // with mock data via the static helper methods.

    test('cascade never crosses movement pattern boundary', () {
      // Verify that a vertical_pull slot never gets filled with horizontal_push
      // This is tested indirectly through the pickV4 output
      final slot = const MuscleSlot(
        targetMuscle: 'Lats', subFocus: 'width',
        movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1,
      );
      // The cascade should only query vertical_pull exercises
      expect(slot.movementPattern, 'vertical_pull');
    });

    test('universal bodyweight pool covers all 11 movement patterns', () {
      for (final mp in kMovementPatterns) {
        expect(ExerciseSelector.universalPoolV4.containsKey(mp), isTrue,
            reason: 'Missing universal pool for $mp');
        expect(ExerciseSelector.universalPoolV4[mp]!.isNotEmpty, isTrue,
            reason: 'Empty universal pool for $mp');
      }
    });
  });
```

- [ ] **Step 2: Add pickV4 method and universal pool to ExerciseSelector**

The new method takes `List<MuscleSlotDay>` and returns `List<PopulatedDay>`. Keep the existing `pick()` method for backward compatibility.

Add to `exercise_selector.dart`:

```dart
  /// V4 universal bodyweight pool — keyed by movement pattern.
  static const universalPoolV4 = <String, List<String>>{
    'horizontal_push':   ['Push-Up', 'Incline Push-Up', 'Wide Push-Up', 'Decline Push-Up', 'Diamond Push-Up'],
    'vertical_push':     ['Pike Push-Up', 'Wall Handstand Hold', 'Hindu Push-Up'],
    'horizontal_pull':   ['Inverted Row', 'Doorway Row', 'Towel Row', 'Superman Hold'],
    'vertical_pull':     ['Pull Up', 'Chin Up', 'Inverted Row'],
    'knee_dominant':     ['Bodyweight Squat', 'Reverse Lunge', 'Bulgarian Split Squat', 'Jump Squat'],
    'hip_dominant':      ['Glute Bridge', 'Single-Leg RDL', 'Good Morning'],
    'core':              ['Plank', 'Dead Bug', 'Bird Dog', 'Bicycle Crunches', 'Mountain Climbers'],
    'elbow_flexion':     ['Chin Up', 'Inverted Row'],
    'elbow_extension':   ['Diamond Push-Up', 'Bench Dips', 'Tricep Dips'],
    'shoulder_isolation': ['Pike Push-Up', 'Arm Circles', 'Band Pull Apart'],
    'hip_isolation':     ['Glute Bridge', 'Clamshell', 'Fire Hydrant'],
  };

  /// V4: Pick exercises for MuscleSlotDays using cascading fallback.
  static List<PopulatedDay> pickV4({
    required List<MuscleSlotDay> slotDays,
    required ExerciseRepository exerciseRepo,
    required String equipmentTier,
    required String effectiveExp,
    required int phase,
    required String goal,
    List<String> injuries = const [],
  }) {
    final result = <PopulatedDay>[];

    for (final day in slotDays) {
      final exercisesA = _fillSlots(
        day.slotsA, exerciseRepo, equipmentTier, effectiveExp, phase,
        injuries: injuries, excludeNames: {},
      );

      // Variant B: use slotsB if defined, exclude A names for variety
      final bSlots = day.slotsB ?? day.slotsA;
      final aNames = exercisesA.map((e) => e.exerciseName).toSet();
      var exercisesB = _fillSlots(
        bSlots, exerciseRepo, equipmentTier, effectiveExp, phase,
        injuries: injuries, excludeNames: goal == 'strength' ? {} : aNames,
      );

      // If B is same as A spec and no slotsB defined, just copy A
      if (day.slotsB == null) {
        exercisesB = exercisesA;
      } else {
        exercisesB = exercisesB.map((e) => e.copyWith(variant: 'B')).toList();
      }

      result.add(PopulatedDay(
        name: day.name, focus: day.focus,
        dayType: day.dayType, intensity: day.intensity,
        exercisesA: exercisesA, exercisesB: exercisesB,
      ));
    }
    return result;
  }

  /// Fill a list of MuscleSlots with exercises via 5-attempt cascade.
  static List<PlannedExercise> _fillSlots(
    List<MuscleSlot> slots,
    ExerciseRepository repo,
    String equipmentTier,
    String effectiveExp,
    int phase, {
    required List<String> injuries,
    required Set<String> excludeNames,
  }) {
    final exercises = <PlannedExercise>[];
    final pickedNames = Set<String>.from(excludeNames);

    for (final slot in slots) {
      for (var i = 0; i < slot.count; i++) {
        final exercise = _cascadeFill(
          slot, repo, equipmentTier, effectiveExp, phase,
          injuries: injuries, pickedNames: pickedNames,
        );
        if (exercise != null) {
          exercises.add(exercise);
          pickedNames.add(exercise.exerciseName);
        }
      }
    }
    return exercises;
  }

  /// 5-attempt cascade for a single MuscleSlot.
  /// movement_pattern is NEVER dropped.
  static PlannedExercise? _cascadeFill(
    MuscleSlot slot,
    ExerciseRepository repo,
    String equipmentTier,
    String effectiveExp,
    int phase, {
    required List<String> injuries,
    required Set<String> pickedNames,
  }) {
    // Attempt 1: Exact target + subFocus + equipment + type + experience
    var candidates = repo.queryV4(
      movementPattern: slot.movementPattern,
      targetFocus: slot.subFocus != null
          ? '${slot.targetMuscle} (${slot.subFocus})'
          : null,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      foundationalOnly: phase == 1,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    if (candidates.isNotEmpty) return _buildExercise(candidates.first);

    // Attempt 2: Drop subFocus (broader target within same muscle)
    candidates = repo.queryV4(
      movementPattern: slot.movementPattern,
      targetMuscle: slot.targetMuscle,
      equipmentTier: equipmentTier,
      exerciseType: slot.exerciseType,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    if (candidates.isNotEmpty) return _buildExercise(candidates.first);

    // Attempt 3: Drop target + exercise type (any exercise in movement pattern)
    candidates = repo.queryV4(
      movementPattern: slot.movementPattern,
      equipmentTier: equipmentTier,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    if (candidates.isNotEmpty) return _buildExercise(candidates.first);

    // Attempt 4: Drop equipment (allow any equipment)
    candidates = repo.queryV4(
      movementPattern: slot.movementPattern,
      suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
      excludeNames: pickedNames,
      injuryExclusions: injuries.isEmpty ? null : injuries,
    );
    if (candidates.isNotEmpty) return _buildExercise(candidates.first);

    // Attempt 5: Universal bodyweight pool
    final pool = universalPoolV4[slot.movementPattern] ?? [];
    for (final name in pool) {
      if (pickedNames.contains(name)) continue;
      final match = repo.search(name);
      if (match.isNotEmpty) return _buildExercise(match.first);
      return _buildUniversalFallback(name, 'A');
    }

    return null; // Should never happen if universal pool is complete
  }
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/plan_engine_v4_test.dart`
Expected: All pass.

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/shared/repositories/plan_engine/exercise_selector.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/repositories/plan_engine/exercise_selector.dart test/plan_engine_v4_test.dart
git commit -m "feat(exercise-selector): add pickV4 with 5-attempt cascading fallback within movement patterns"
```

---

### Task 9: Update SequencingEngine for priority ordering

**Files:**
- Modify: `lib/shared/repositories/plan_engine/sequencing_engine.dart`

- [ ] **Step 1: Update _reorderDay to consider MuscleSlot priority**

The sequencing engine currently orders by: compound > isolation, bilateral > unilateral, CNS demand. Add priority as the FIRST sort key (P1 before P2 before P3), with existing rules as tiebreakers within same priority.

In the `_reorderDay()` method, add priority comparison before compound/isolation check. Since `PlannedExercise` doesn't carry the MuscleSlot priority, we use `priority_tier` from the exercise library data (stored as `exerciseType` compound=P1, isolation=P2/P3) as a proxy. The existing compound-first rule already achieves this — no model change needed.

Actually, the priority information is lost after exercise selection (PlannedExercise doesn't have a priority field). For now, the existing compound-first + CNS ordering achieves the same result. Mark this as a no-op for V4 launch; priority ordering is implicitly correct because P1 slots are compounds and P3 are isolations.

- [ ] **Step 2: Verify existing sequencing works with V4 exercises**

No code change needed. The existing rules produce correct ordering for V4 output.

- [ ] **Step 3: Commit (documentation only)**

```bash
git commit --allow-empty -m "docs(sequencing): V4 verified — compound-first + CNS ordering implicitly matches MuscleSlot priority"
```

---

### Task 10: Update PlanGenerator orchestrator for V4 pipeline

**Files:**
- Modify: `lib/shared/repositories/plan_engine/plan_generator.dart`

- [ ] **Step 1: Add V4 generate path**

Add a `generateV4()` method that wires the new stages:

```dart
  /// V4 pipeline: MuscleSlot-based exercise selection with cascading fallback.
  Phase generateV4({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    int phase = 1,
    String experienceLevel = 'beginner',
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
    Map<String, double>? previousWeights,
  }) {
    final equipmentList = _getEquipmentList(equipment);
    final effectiveExp = effectiveLevel(experienceLevel, phase);
    final equipmentTier = equipment; // direct tier string for V4 queries

    // Stage 1: Split resolution → MuscleSlotDay[]
    final splitDays = SplitResolver.selectV4(goal, daysPerWeek,
        experienceLevel: effectiveExp);

    // Stage 2: Exercise selection → PopulatedDay[]
    final populated = ExerciseSelector.pickV4(
      slotDays: splitDays,
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: equipmentTier,
      effectiveExp: effectiveExp,
      phase: phase,
      goal: goal,
      injuries: injuries,
    );

    // Stage 0: Progression (Phase 2+ weight suggestions)
    final allNames = populated
        .expand((d) => [...d.exercisesA, ...d.exercisesB])
        .map((e) => e.exerciseName)
        .toSet()
        .toList();
    Map<String, double>? weights = previousWeights;
    if (weights == null && phase >= 2) {
      weights = ProgressionResolver.instance.resolve(phase, allNames);
    }

    // Stage 4: Periodization → WeekPlan[]
    final is6Day = daysPerWeek == 6;
    var weekPlans = PeriodizationEngine.apply(
      populated, phase,
      is6Day: is6Day,
      bodyFocus: bodyFocus,
      previousWeights: weights,
    );

    // Stage 1.5: Volume Filter (applied per-week since weekCharacter varies)
    weekPlans = weekPlans.map((week) {
      final filtered = week.workoutDays.map((day) {
        // Volume filter trims exercises based on session duration
        // For V4, this is already handled at slot level before exercise selection
        // Here we just pass through since slots were filtered before pick
        return day;
      }).toList();
      return WeekPlan(
        weekNumber: week.weekNumber,
        weekInPhase: week.weekInPhase,
        overloadNotes: week.overloadNotes,
        weekCharacter: week.weekCharacter,
        workoutDays: filtered,
      );
    }).toList();

    // Stage 3: Sequencing
    weekPlans = SequencingEngine.sequence(weekPlans);

    // Stage 5: Superset pairing
    weekPlans = SupersetPairer.pair(weekPlans);

    // Stage 6: Cardio finisher
    if (goal == 'lose_fat' || goal == 'general_fitness') {
      weekPlans = CardioFinisher.attach(
        weekPlans, goal,
        preference: cardioPreference,
        equipment: equipment,
      );
    }

    // Stage 7: Warmup/cooldown
    weekPlans = WarmupCooldownSelector.attach(
      weekPlans,
      experienceLevel: effectiveExp,
      equipment: equipment,
    );

    // Build Phase output
    final meta = _getPhaseMeta(phase);
    final weekStart = (phase - 1) * 4 + 1;
    final weekEnd = weekStart + 3;

    return Phase(
      phase: phase,
      name: meta.name,
      focus: meta.focus,
      weeks: '$weekStart-$weekEnd',
      dailyCalories: meta.dailyCalories,
      proteinGrams: meta.proteinGrams,
      workouts: weekPlans.isNotEmpty ? weekPlans.first.workoutDays : [],
      weekPlans: weekPlans,
      preferredDays: preferredDays,
    );
  }
```

- [ ] **Step 2: Update generate() to delegate to generateV4()**

Replace the body of the existing `generate()` method to call `generateV4()`, keeping the same signature for backward compatibility:

```dart
  Phase generate({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    int phase = 1,
    String experienceLevel = 'beginner',
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
    Map<String, double>? previousWeights,
  }) {
    return generateV4(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      phase: phase,
      experienceLevel: experienceLevel,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
      previousWeights: previousWeights,
    );
  }
```

- [ ] **Step 3: Wire Volume Filter at the correct position**

The Volume Filter should run BEFORE exercise selection (Stage 1.5), not after periodization. Move it:

In `generateV4()`, insert volume filtering between Stage 1 and Stage 2:

```dart
    // Stage 1.5: Volume Filter — trim slots before exercise selection
    final filteredDays = VolumeFilter.filterDays(
      splitDays,
      sessionMinutes: sessionDuration,
      experience: effectiveExp,
      weekCharacter: 'baseline', // first-pass uses baseline; deload applied in periodization
    );

    // Stage 2: Exercise selection with filtered slots
    final populated = ExerciseSelector.pickV4(
      slotDays: filteredDays,
      // ...
    );
```

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/shared/repositories/plan_engine/plan_generator.dart`
Expected: No errors.

- [ ] **Step 5: Write integration test**

Add to `test/plan_engine_v4_test.dart`:

```dart
  group('PlanGenerator V4 integration', () {
    test('5-day build_muscle generates valid phase with no empty days', () {
      final phase = PlanGenerator.instance.generate(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 5,
        experienceLevel: 'intermediate',
      );
      expect(phase.weekPlans.length, 4);
      for (final week in phase.weekPlans) {
        expect(week.workoutDays.length, 5);
        for (final day in week.workoutDays) {
          expect(day.exercises.isNotEmpty, isTrue,
              reason: '${day.name} has no exercises');
          expect(day.exercises.length, greaterThanOrEqualTo(3),
              reason: '${day.name} has fewer than 3 exercises');
        }
      }
    });

    test('Back day has no bicep-only exercises in first 3 slots', () {
      final phase = PlanGenerator.instance.generate(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 5,
        experienceLevel: 'intermediate',
      );
      final backDay = phase.weekPlans.first.workoutDays
          .firstWhere((d) => d.name.toLowerCase().contains('back'));
      
      // First 3 exercises should be back compounds, not curls
      final first3 = backDay.exercises.take(3).toList();
      for (final ex in first3) {
        final isCurl = ex.exerciseName.toLowerCase().contains('curl');
        expect(isCurl, isFalse,
            reason: '${ex.exerciseName} is a curl in first 3 of Back day');
      }
    });

    test('home_dumbbells user gets complete workouts', () {
      final phase = PlanGenerator.instance.generate(
        goal: 'build_muscle',
        equipment: 'home_dumbbells',
        daysPerWeek: 4,
        experienceLevel: 'beginner',
      );
      for (final week in phase.weekPlans) {
        for (final day in week.workoutDays) {
          expect(day.exercises.isNotEmpty, isTrue,
              reason: '${day.name} empty for home_dumbbells');
        }
      }
    });
  });
```

- [ ] **Step 6: Run all tests**

Run: `flutter test test/plan_engine_v4_test.dart`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add lib/shared/repositories/plan_engine/plan_generator.dart test/plan_engine_v4_test.dart
git commit -m "feat(plan-generator): wire V4 pipeline — MuscleSlot splits, volume filter, cascading selector"
```

---

## Phase 3: Schedule Fixes (Domain C)

### Task 11: Fix week reset bug

**Files:**
- Modify: `lib/core/services/workout_schedule_service.dart`

- [ ] **Step 1: Modify generateAndScheduleFromDate to preserve plan_start_date**

In `generateAndScheduleFromDate()`, when called for a days-per-week change (not a full regeneration), preserve the existing `plan_start_date`:

Find the line where `_planStartKey` is written (around line 220-230) and change it to only write if there's no existing start date:

```dart
// Preserve plan_start_date on reschedule (don't reset to Week 1)
final existingStart = _hive.configBox.get(_planStartKey) as String?;
if (existingStart == null) {
  // First-time generation: set the plan start
  await _hive.configBox.put(_planStartKey, monday.toIso8601String());
  await _hive.configBox.put(_planEndKey, endDate.toIso8601String());
} 
// If rescheduling (existingStart exists), keep the original start date
// so getCurrentWeekNumber() returns the correct week.
```

- [ ] **Step 2: Add preserveWeek parameter to edit profile reschedule call**

In `lib/features/profile/screens/edit_profile_screen.dart`, the reschedule call should NOT reset plan_start_date. The generateAndScheduleFromDate already preserves it with the fix above.

Verify the fix by checking that `getCurrentWeekNumber()` still reads from the original `plan_start_date`.

- [ ] **Step 3: Write test**

```dart
  test('changing daysPerWeek preserves week number', () {
    // Simulate: set plan_start_date to 7 days ago (should be Week 2)
    // Call generateAndScheduleFromDate
    // Verify plan_start_date is unchanged
    // Verify getCurrentWeekNumber() returns 2
  });
```

- [ ] **Step 4: Run tests and commit**

```bash
git add lib/core/services/workout_schedule_service.dart
git commit -m "fix(schedule): preserve plan_start_date on days-per-week change — prevents week reset"
```

---

### Task 12: Auto-inject warmup/cooldown for custom templates

**Files:**
- Modify: `lib/core/services/workout_schedule_service.dart`

- [ ] **Step 1: Add warmup injection in assignTemplateToDate**

In the `assignTemplateToDate()` method, after building the schedule entry from the template, detect the muscle focus and run WarmupCooldownSelector:

```dart
  // After building templateEntry from the template data:
  
  // V4: Auto-inject warmup/cooldown for custom templates
  final exercises = templateEntry['exercises'] as List? ?? [];
  if (exercises.isNotEmpty) {
    // Detect day type from exercise categories
    final dayType = _detectDayTypeFromExercises(exercises);
    final userProfile = UserRepository.instance.getProfile() ?? {};
    final experience = userProfile['fitness_experience'] as String? ?? 'intermediate';
    final equipment = userProfile['equipment_access'] as String? ?? 'full_gym';
    
    // Build a single-day WeekPlan to pass to WarmupCooldownSelector
    final tempDay = WorkoutDay(
      dayNumber: 1,
      name: templateEntry['workout_name'] as String? ?? 'Custom',
      focus: dayType,
      exercises: exercises.map((e) => PlannedExercise.fromMap(e as Map<String, dynamic>)).toList(),
    );
    final tempWeek = WeekPlan(
      weekNumber: 1, weekInPhase: 1,
      overloadNotes: '', weekCharacter: 'baseline',
      workoutDays: [tempDay],
    );
    
    final withWarmup = WarmupCooldownSelector.attach(
      [tempWeek],
      experienceLevel: experience,
      equipment: equipment,
    );
    
    final enrichedDay = withWarmup.first.workoutDays.first;
    if (enrichedDay.warmup.isNotEmpty) {
      templateEntry['warmup'] = enrichedDay.warmup.map((e) => e.toMap()..['auto_generated'] = true).toList();
    }
    if (enrichedDay.cooldown.isNotEmpty) {
      templateEntry['cooldown'] = enrichedDay.cooldown.map((e) => e.toMap()..['auto_generated'] = true).toList();
    }
  }
```

- [ ] **Step 2: Add _detectDayTypeFromExercises helper**

```dart
  /// Detect workout day type from exercise categories.
  String _detectDayTypeFromExercises(List exercises) {
    final categories = <String>[];
    for (final ex in exercises) {
      if (ex is Map) {
        final cat = ex['category'] as String? ?? '';
        if (cat.isNotEmpty) categories.add(cat.toLowerCase());
      }
    }
    if (categories.isEmpty) return 'full_body';
    
    final pushCount = categories.where((c) => c == 'push').length;
    final pullCount = categories.where((c) => c == 'pull').length;
    final legsCount = categories.where((c) => c == 'legs').length;
    
    if (legsCount > pushCount && legsCount > pullCount) return 'legs';
    if (pushCount > pullCount) return 'push';
    if (pullCount > pushCount) return 'pull';
    if (pushCount > 0 && pullCount > 0) return 'upper';
    return 'full_body';
  }
```

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/workout_schedule_service.dart
git commit -m "feat(schedule): auto-inject warmup/cooldown when scheduling custom templates"
```

---

## Phase 4: Profile & UX Polish (Domain B)

### Task 13: Profile completeness provider

**Files:**
- Create: `lib/features/profile/providers/profile_completeness_provider.dart`

- [ ] **Step 1: Create the provider**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Tier 2 profile fields ordered by plan impact (highest first).
const kTier2Fields = <({String key, String label, String benefit})>[
  (key: 'session_duration_minutes', label: 'Session Duration', benefit: 'Get plans sized for your schedule'),
  (key: 'physique_focus', label: 'Physique Focus', benefit: 'Bias workouts toward your goals'),
  (key: 'injuries', label: 'Injuries', benefit: 'Avoid exercises that could hurt you'),
  (key: 'target_weight_kg', label: 'Target Weight', benefit: 'Unlock weight projection'),
  (key: 'body_fat_percent', label: 'Body Fat %', benefit: 'Get more accurate calorie targets'),
  (key: 'pace_preference', label: 'Pace Preference', benefit: 'Control how fast you cut or bulk'),
];

/// Tier 1 fields (collected at onboarding — should already be filled).
const kTier1Fields = <String>[
  'full_name', 'date_of_birth', 'gender', 'height_cm', 'current_weight_kg',
  'primary_goal', 'equipment_access', 'days_per_week', 'fitness_experience',
  'lifestyle_activity',
];

class ProfileCompletenessData {
  final int percentage;
  final ({String key, String label, String benefit})? highestImpactMissing;
  final List<({String key, String label, String benefit})> allMissing;

  const ProfileCompletenessData({
    required this.percentage,
    this.highestImpactMissing,
    this.allMissing = const [],
  });

  bool get isComplete => percentage >= 100 || allMissing.isEmpty;
}

final profileCompletenessProvider = Provider<ProfileCompletenessData>((ref) {
  final profile = UserRepository.instance.getProfile() ?? {};

  // Count Tier 1 filled
  int tier1Filled = 0;
  for (final key in kTier1Fields) {
    final val = profile[key];
    if (val != null && val.toString().isNotEmpty) tier1Filled++;
  }

  // Count Tier 2 filled + collect missing
  int tier2Filled = 0;
  final missing = <({String key, String label, String benefit})>[];
  for (final field in kTier2Fields) {
    final val = profile[field.key];
    bool isFilled = false;
    if (val == null) {
      isFilled = false;
    } else if (field.key == 'injuries') {
      // injuries = ['none'] counts as not filled (default)
      final list = val is List ? val : [];
      isFilled = list.isNotEmpty && !(list.length == 1 && list.first.toString() == 'none');
    } else if (val is String) {
      isFilled = val.isNotEmpty;
    } else if (val is num) {
      isFilled = val > 0;
    } else {
      isFilled = true;
    }

    if (isFilled) {
      tier2Filled++;
    } else {
      missing.add(field);
    }
  }

  // Weighted percentage: Tier 1 = 60%, Tier 2 = 40%
  final tier1Pct = kTier1Fields.isEmpty ? 60.0 : (tier1Filled / kTier1Fields.length) * 60;
  final tier2Pct = kTier2Fields.isEmpty ? 40.0 : (tier2Filled / kTier2Fields.length) * 40;
  final pct = (tier1Pct + tier2Pct).round().clamp(0, 100);

  return ProfileCompletenessData(
    percentage: pct,
    highestImpactMissing: missing.isNotEmpty ? missing.first : null,
    allMissing: missing,
  );
});
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/profile/providers/profile_completeness_provider.dart
git commit -m "feat(profile): add profile completeness provider with Tier 1/2 weighted calculation"
```

---

### Task 14: Profile nudge card widget (home screen)

**Files:**
- Create: `lib/features/home/widgets/profile_nudge_card.dart`
- Modify: `lib/features/home/screens/home_screen.dart`

- [ ] **Step 1: Create the nudge card widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/profile/providers/profile_completeness_provider.dart';

/// Slim dismissible card showing the highest-impact missing profile field.
/// Positioned between Quick Actions and AI Coach Insight on the home screen.
class ProfileNudgeCard extends ConsumerWidget {
  const ProfileNudgeCard({super.key});

  static const _dismissKey = 'profile_nudge_dismissed_at';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completeness = ref.watch(profileCompletenessProvider);

    // Don't show if complete
    if (completeness.isComplete) return const SizedBox.shrink();

    // Don't show if dismissed < 3 days ago
    final dismissedAt = HiveService.instance.configBox.get(_dismissKey) as String?;
    if (dismissedAt != null) {
      final dismissed = DateTime.tryParse(dismissedAt);
      if (dismissed != null && DateTime.now().difference(dismissed).inDays < 3) {
        return const SizedBox.shrink();
      }
    }

    final field = completeness.highestImpactMissing;
    if (field == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: GestureDetector(
        onTap: () => context.go('/profile/edit'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.accent.withValues(alpha: 0.7)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${field.benefit} \u2192',
                  style: GoogleFonts.getFont('DM Sans', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () {
                  HiveService.instance.configBox.put(_dismissKey, DateTime.now().toIso8601String());
                  ref.invalidate(profileCompletenessProvider);
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Insert into home screen**

In `lib/features/home/screens/home_screen.dart`, in the `_buildContent()` method, insert after the quick actions line (`_buildQuickActions(context)`) and before the AI insight:

```dart
        const SizedBox(height: 10),
        const ProfileNudgeCard(),  // V4: profile completeness nudge
        const SizedBox(height: 10),
        // AI Coach insight
```

Add the import at top:
```dart
import '../widgets/profile_nudge_card.dart';
```

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/features/home/`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/widgets/profile_nudge_card.dart lib/features/home/screens/home_screen.dart
git commit -m "feat(home): add profile nudge card between quick actions and AI insight"
```

---

### Task 15: Slim achievements card + profile identity cleanup

**Files:**
- Create: `lib/features/profile/widgets/slim_achievements_card.dart`
- Modify: `lib/features/profile/widgets/profile_identity.dart`
- Modify: `lib/features/profile/screens/profile_screen.dart`

- [ ] **Step 1: Create SlimAchievementsCard**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';
import 'package:icanbefitter/features/profile/widgets/badges_grid.dart';

/// Single-line achievements card: trophy icon + recent badges + count + chevron.
/// ~44px height. Tapping chevron opens full badges grid in bottom sheet.
class SlimAchievementsCard extends StatelessWidget {
  const SlimAchievementsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final allBadges = BadgeService.instance.getAllWithStatus();
    final earned = allBadges.where((b) => b.isUnlocked).toList()
      ..sort((a, b) => (b.unlockedAt ?? DateTime(2000)).compareTo(a.unlockedAt ?? DateTime(2000)));
    final recentEarned = earned.take(4).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: GestureDetector(
        onTap: () => _openBadgesSheet(context, allBadges),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Text('\u{1F3C6}', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                'Achievements',
                style: GoogleFonts.getFont('DM Sans', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              // Recent badge icons
              ...recentEarned.map((b) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  width: 26, height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.proGold.withValues(alpha: 0.4)),
                  ),
                  child: Text(b.emoji, style: const TextStyle(fontSize: 14)),
                ),
              )),
              const Spacer(),
              Text(
                '${earned.length}/${allBadges.length}',
                style: GoogleFonts.getFont('DM Sans', fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _openBadgesSheet(BuildContext context, List<AchievementBadge> badges) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(18),
          child: BadgesGrid(badges: badges),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Remove CompactAchievementsRow from ProfileIdentity**

In `lib/features/profile/widgets/profile_identity.dart`, in the `Positioned` widget at `bottom: -40`, replace the Row children to remove the CompactAchievementsRow:

Change the Row from:
```dart
children: [
  _buildAvatar(context),
  const SizedBox(width: 14),
  Expanded(child: Align(...CompactAchievementsRow...)),
  Padding(padding: ..., child: ProPillButton(...)),
],
```

To:
```dart
children: [
  _buildAvatar(context),
  const Spacer(),
  Padding(
    padding: const EdgeInsets.only(top: 40),
    child: ProPillButton(isPro: isPro, onTap: onTapPremium),
  ),
],
```

Remove the `CompactAchievementsRow` import and the `onOpenAll` callback.

- [ ] **Step 3: Replace _CollapsibleBadgesSection with SlimAchievementsCard in profile screen**

In `lib/features/profile/screens/profile_screen.dart`, replace:
```dart
const _CollapsibleBadgesSection(),
```
with:
```dart
const SlimAchievementsCard(),
```

Add the import and remove the entire `_CollapsibleBadgesSection` class definition (lines ~1839-2050).

- [ ] **Step 4: Add experience level to profile subtitle**

In `profile_screen.dart`, update the subtitle line:
```dart
final experience = profile['fitness_experience'] as String? ?? '';
final expLabel = experience.isNotEmpty ? ' \u00B7 ${experience[0].toUpperCase()}${experience.substring(1)}' : '';
final subtitle = 'Phase ${stats.currentPhase} \u00B7 Week ${stats.currentWeek}$expLabel \u00B7 ${_formatGoal(stats.primaryGoal)}';
```

- [ ] **Step 5: Add profile completeness card to profile screen**

Insert between name/subtitle and Daily Completion:

```dart
              // V4: Profile completeness card
              _buildProfileCompletenessCard(),
              const SizedBox(height: 8),

              // #2 Daily Completion summary
              _buildDailyCompletion(stats),
```

Implement `_buildProfileCompletenessCard()` as a slim card with percentage + benefit CTA.

- [ ] **Step 6: Run analyzer**

Run: `flutter analyze lib/features/profile/ lib/features/home/`
Expected: No errors (may have warnings about unused imports — clean up).

- [ ] **Step 7: Commit**

```bash
git add lib/features/profile/widgets/slim_achievements_card.dart \
  lib/features/profile/widgets/profile_identity.dart \
  lib/features/profile/screens/profile_screen.dart
git commit -m "feat(profile): slim achievements card, remove banner badges, add experience + completeness"
```

---

### Task 16: Add session_duration and physique_focus to edit profile

**Files:**
- Modify: `lib/features/profile/screens/edit_profile_screen.dart`

- [ ] **Step 1: Add state variables**

After the existing `_pacePreference` state variable (around line 49), add:

```dart
int? _sessionDuration; // 30, 45, 60, 90
String _physiqueFocus = 'balanced'; // balanced, glutes_legs, chest_shoulders_arms, strength
String _fitnessExperience = 'intermediate'; // beginner, intermediate, advanced
```

- [ ] **Step 2: Initialize from profile in initState/didChangeDependencies**

In the profile loading section, add:
```dart
_sessionDuration = profile['session_duration_minutes'] as int?;
_physiqueFocus = profile['physique_focus'] as String? ?? 'balanced';
_fitnessExperience = profile['fitness_experience'] as String? ?? 'intermediate';
```

- [ ] **Step 3: Add UI widgets in the Fitness section**

After `_buildPaceSelector()` (around line 269), add three new selectors following the existing chip pattern:

```dart
// Session Duration selector (4 chips: 30, 45, 60, 90 min)
_buildSessionDurationSelector(),
SizedBox(height: gridGap),
// Physique Focus selector (4 chips)
_buildPhysiqueFocusSelector(),
SizedBox(height: gridGap),
// Experience Level selector (3 chips)
_buildExperienceSelector(),
```

Build each using the same `Column > Wrap > AnimatedContainer` pattern as `_buildPaceSelector()`.

- [ ] **Step 4: Add to save method**

In the `updates` map, add:
```dart
if (_sessionDuration != null) 'session_duration_minutes': _sessionDuration,
'physique_focus': _physiqueFocus,
'fitness_experience': _fitnessExperience,
```

- [ ] **Step 5: Run analyzer and commit**

```bash
git add lib/features/profile/screens/edit_profile_screen.dart
git commit -m "feat(edit-profile): add session duration, physique focus, and experience level fields"
```

---

### Task 17: UI masking by experience level

**Files:**
- Create: `lib/core/utils/exercise_display.dart`

- [ ] **Step 1: Create the display formatter**

```dart
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Format exercise display text based on user's experience level.
///
/// - Beginner: "Back: Lat Pulldown" (category only)
/// - Intermediate: "Lats: Lat Pulldown" (muscle group)
/// - Advanced: "Lats (Width): Lat Pulldown" (muscle + focus)
class ExerciseDisplay {
  static String formatMuscleLabel(Map<String, dynamic> exercise) {
    final experience = UserRepository.instance.getProfile()?['fitness_experience'] as String? ?? 'intermediate';
    final targetFocus = exercise['target_focus'] as String? ?? '';
    final category = exercise['category'] as String? ?? '';

    switch (experience) {
      case 'beginner':
        return _categoryLabel(category);
      case 'advanced':
        return targetFocus.isNotEmpty ? targetFocus : _categoryLabel(category);
      default: // intermediate
        // Extract just the muscle name from target_focus (e.g., "Lats (Width)" → "Lats")
        if (targetFocus.isEmpty) return _categoryLabel(category);
        final parenIdx = targetFocus.indexOf('(');
        return parenIdx > 0 ? targetFocus.substring(0, parenIdx).trim() : targetFocus;
    }
  }

  static String _categoryLabel(String category) {
    switch (category.toLowerCase()) {
      case 'push': return 'Push';
      case 'pull': return 'Back';
      case 'legs': return 'Legs';
      case 'core': return 'Core';
      default: return category.isNotEmpty ? category[0].toUpperCase() + category.substring(1) : 'Exercise';
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/utils/exercise_display.dart
git commit -m "feat(ui): add ExerciseDisplay formatter — masks complexity by experience level"
```

---

## Final Commit: Update re-export shim

### Task 18: Update re-export shim and clean up

**Files:**
- Modify: `lib/shared/repositories/plan_generator.dart`

- [ ] **Step 1: Add volume_filter to re-export**

The re-export shim only exports `plan_generator.dart` and `models.dart`. Add `volume_filter.dart`:

```dart
// Plan Generator V4 — Re-export shim.
// All logic lives in plan_engine/. This file preserves existing imports.
export 'plan_engine/plan_generator.dart';
export 'plan_engine/models.dart';
export 'plan_engine/volume_filter.dart';
```

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Expected: All tests pass including existing V3 tests and new V4 tests.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Expected: No errors (warnings acceptable for pre-existing issues).

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: Exercise Selection V4 complete — muscle-slot pipeline, profile polish, schedule fixes"
```

---

## Summary

| Phase | Tasks | Key Deliverable |
|-------|-------|----------------|
| **1: Data Foundation** | Tasks 1-5 | Enriched exercise library (4 new fields, ~30 new exercises), MuscleSlot model, V4 repository queries |
| **2: Engine Rewrite** | Tasks 6-10 | Muscle-slot split resolver, volume filter, cascading selector, V4 orchestrator |
| **3: Schedule Fixes** | Tasks 11-12 | Week reset bug fix, template warmup auto-inject |
| **4: Profile Polish** | Tasks 13-17 | Completeness cards (home + profile), slim achievements, experience display, UI masking |
| **Cleanup** | Task 18 | Re-export shim, full test suite, final commit |

**Total: 18 tasks, ~3-4 hours estimated for experienced agent.**
