# Plan Generator V4 — Diagnostic Harness Design

**Date:** 2026-04-15
**Status:** Diagnostic only. No production code changes. No fixes.
**Owner:** Upendra

## Context & bug

On-phone test (Advanced / full_gym / build_muscle / 5 days per week), the V4 generator produced only **3 exercises** on the Wed "LEGS A" day: Baithak (Hindu Squat), Reverse Lunge, Glute Bridge. Expected: 5-6 exercises including compound barbell lifts.

The user wants a diagnostic harness — **not a fix** — that generates sample plans across representative input combinations, prints a full-pipeline trace per slot, and lets us identify which stage (library taxonomy / VolumeFilter / ExerciseSelector cascade / Periodization / rendering) drops exercises.

## Goal

A deterministic, runnable Dart test that:
1. Seeds Hive from bundled `assets/data/exercise_library.json`.
2. Calls `PlanGenerator.instance.generateV4(...)` for a matrix of input combinations, including the exact bug-repro inputs.
3. Instruments every pipeline stage to emit a structured trace.
4. Writes a human-readable Markdown report we can eyeball to identify root cause.

**Non-goals** (deferred):
- Any fix to selector, volume_filter, split_resolver, library taxonomy, or universal pool.
- Wiring `sessionDuration` into the 5 orphan call sites (onboarding, edit_profile, train, graduation, auth).
- Adding `exercises` column to `scheduled_workouts` cloud table.
- Fixing profile sync failure for icanbefitter@gmail.com (Supabase row all-null despite Hive being populated).
- Fixing or hiding the "LEG DAY RELAXED" UI label (we'll locate the source, not change it).

These are logged in the Open Issues section for future brainstorms.

## Findings so far (from code reads)

### 1. 5-day build_muscle split (split_resolver.dart:686-735)

Day 4 is named **"Legs"** (not "Legs A"). Contains:
- `slotsA` (5 slots): Quads/knee_dominant/compound/P1, Hamstrings/hip_dominant/compound/P1, Quads(subFocus:isolation)/knee_dominant/isolation/P2, Glutes/hip_isolation/isolation/P2, Calves/knee_dominant/isolation/P3
- `slotsB` (5 slots): anterior/posterior emphasis swap for week-over-week alternation.

**Naming mystery:** The on-phone screenshot reads "LEGS A" and "LEG DAY RELAXED". Neither string appears in the 5-day split definition. Hypotheses to verify via trace:
- User is actually on a **6-day split** that labels A/B variants explicitly.
- UI re-labels "Legs" + week parity into "LEGS A" at render time.
- "RELAXED" is a VolumeFilter output label.

### 2. queryV4 filter semantics (exercise_repository.dart:177-295)

Clean, no obvious bugs:
- `movement_pattern` — exact case-insensitive equality (always applied).
- `target_focus` — `.contains()` substring match.
- `target_muscle` — `.contains()` across `target_focus` and `primary_muscles`.
- `equipment_tier` — single string matched against exercise's tier list via case-insensitive equality per list item.
- `suitable_for` — `.any((s) => s == suitableFor)` exact per-item match.
- `foundationalOnly` — `is_foundational == true`.
- Sort: compound → priority_tier asc → foundational first.

### 3. Three selector bugs confirmed (exercise_selector.dart:480-645)

| Bug | Evidence | Impact |
|---|---|---|
| **Attempt 1 subFocus mismatch** | Builds `targetFocus = '${targetMuscle} (${subFocus})'` → e.g. `"Quads (isolation)"`. Library uses labels like `"Quads (Overall)"`, `"Quads (Vastus Medialis)"`. The literal string `"(isolation)"` is never in any `target_focus` field. | Attempt 1 always returns 0 on any isolation slot. Falls through to Attempt 2. |
| **foundationalOnly on Attempt 1 only** | Only the very first attempt filters `is_foundational == true`; all subsequent attempts drop the flag. Combined with bug #1, Attempt 1 is effectively dead on isolation slots. | Mostly wasted attempt. Not fatal on its own. |
| **Universal pool placeholder** | `_buildUniversalFallback` emits name-only placeholders when the pool name doesn't exist in the library. | "Single Leg RDL" etc. render without full metadata — matches the 3-exercise stripped-down output on screenshot. |

### 4. plan_generator.dart wiring — correct

`equipment: "full_gym"` is passed as `equipmentTier` to `queryV4` at line 92. Not the bug.

### 5. The real mystery

Attempt 2 (drops subFocus, keeps `targetMuscle=Quads, equipmentTier=full_gym, exerciseType=compound, suitableFor=null`) should pick **Barbell Back Squat**. It doesn't — output shows Baithak (universal bodyweight pool = Attempt 5). Something fails Attempts 2-4 for full_gym + Advanced. Suspects:
- **Equipment tier string mismatch** — library stores `"full_gym"` underscore vs `"full gym"` space? Needs library audit.
- **VolumeFilter over-trim** — slots are culled before they reach the selector. Default `sessionMinutes = sessionDuration ?? 45`, and NO call site passes `sessionDuration`. Every user hits 45min default.
- **excludeNames accumulation** — earlier days may have stolen all compound Quads options by the time Day 4 runs.

## Diagnostic harness — design

### Files

- `test/plan_generator/v4_diagnostic_test.dart` — runnable via `flutter test test/plan_generator/v4_diagnostic_test.dart`.
- `test/plan_generator/v4_diagnostic_output.md` — generated artifact, committed per run for review.

### Seeding

- Initialize Hive in-memory (or temp dir), register all adapters required by `PlanGenerator`.
- Parse `assets/data/exercise_library.json` and put every entry into `exerciseBox` keyed by `id`.
- No network, no Supabase, no user data.

### Instrumentation strategy — NO production code edits

Use a **wrapper** that re-executes each `queryV4` call the selector would make, logging full filter signatures and result counts per attempt. Achieved by:
1. Calling `PlanGenerator.instance.generateV4(...)` once to get the final output.
2. Re-walking each `MuscleSlotDay` and re-calling `ExerciseRepository.instance.queryV4(...)` with the exact filter sequence from `exercise_selector._cascadeFill` (mirror the cascade in test code).
3. Comparing what the wrapper finds vs. what ended up in the final `Phase.workouts` output.

If the wrapper and the selector disagree, we've found the bug without touching production code.

### Two-layer trace

**Layer 1 — Input resolution**
```
INPUT (raw): goal, equipment, daysPerWeek, experienceLevel, sessionDuration, phase
EFFECTIVE:   effectiveExp, equipmentTier, weekCharacter
```

**Layer 2 — Per-slot cascade trace** (both slotsA and slotsB, all 4 weeks of a phase)
```
Day N "<name>" · Variant A · Week W
  PRE-VolumeFilter:  N slots [...]
  POST-VolumeFilter: M slots [...]  ← list what got dropped
  excludeNames-in:   {set accumulated from earlier days}

  Slot: <targetMuscle>/<movement_pattern>/<exerciseType>/<priority>
    Attempt 1 (full queryV4 signature): N results [names]
    Attempt 2 (signature): N results [names]
    ...
    PICK: "<name>" [LIBRARY | PLACEHOLDER]

  POST-Periodization:  N exercises
  POST-Sequencing:     N exercises
  POST-Superset:       N exercises
  FINAL RENDER:        N exercises
```

Stage counts after the cascade catch bugs in downstream stages too (e.g., if Periodization drops an exercise we couldn't detect from selector output alone).

### Library integrity pre-check

Before running any combo, dump two tables at the top of the output:

**Triplet counts:**
| movement_pattern | equipment_tier | suitable_for | is_foundational | count |
|---|---|---|---|---|
| knee_dominant | full_gym | advanced | true | ? |
| knee_dominant | full_gym | advanced | any | ? |
| hip_dominant | full_gym | advanced | any | ? |
| ... all 11 patterns × 4 tiers × 3 levels × {true, any} | | | | |

If any production-plausible triplet = 0, that's a **library taxonomy bug** we flag upfront.

**Equipment tier audit:** unique values of the `equipment_tier` field across the entire library. If the set contains both `"full_gym"` and `"full gym"` (or any variant), that's the smoking gun.

### Combo matrix

| # | Goal | Equip | Days | Exp | Phase | sessionDuration | Purpose |
|---|---|---|---|---|---|---|---|
| 1 | build_muscle | full_gym | 5 | advanced | 1 | null | **Bug-repro baseline** |
| 2 | general_fitness | bodyweight | 3 | beginner | 1 | null | Low-tier sanity |
| 3 | lose_fat | home_dumbbells | 4 | intermediate | 2 | null | Mid-tier + phase 2 |
| 4 | strength | full_gym | 5 | advanced | 3 | null | High phase |
| 5 | build_muscle | basic_gym | 6 | advanced | 1 | null | 6-day split (naming!) |
| 6 | build_muscle | full_gym | 4 | beginner | 1 | null | Advanced vs beginner isolate |
| 7 | build_muscle | full_gym | 5 | advanced | 1 | 60 | VolumeFilter toggle |
| 8 | **real-profile replay** — same as Combo 1 inputs, but with the exact Hive profile map Upendra has on-phone (re-dumped from device if needed) instead of synthetic minimum | | | | | | Production parity — eliminates "synthetic inputs don't match production" doubt |
| 9 | build_muscle | full_gym | 5 | advanced | 1 | null + `injuries=['knee']` | Injury path |
| 10 | Combo 1 × all 4 weeks (weekCharacter: baseline / overload / peak / deload) | | | | | | Phase sweep |

### What each combo proves

| Comparison | Proves |
|---|---|
| Combo 1 (baseline reproduction) | Bug reproduces in test env |
| 1 vs 7 | VolumeFilter over-trim hypothesis (sessionDuration=null vs 60) |
| 1 vs 6 | `suitable_for: advanced` filter failure (Advanced vs Beginner, same equip) |
| 1 vs 5 | 5-day vs 6-day split naming, slot count differences |
| 1 vs 2/3/4 | Equipment/goal sweep — if equipment tier string mismatch exists, it surfaces here |
| 8 (real-profile replay) | Eliminates "synthetic inputs don't match production" doubt |
| 9 (knee injury) | Confirms injury exclusion path doesn't over-exclude |
| 10 (4 weeks) | Catches weekCharacter × A/B variant interactions |

### Diagnostic heuristics (read-out rules)

- **Every slot falls to Attempt 5** across multiple combos → equipment tier normalization bug. Fix: library audit / normalize tier strings.
- **Slot count drops sharply at POST-VolumeFilter** on sessionDuration=null but not on sessionDuration=60 → VolumeFilter default of 45min is too aggressive, OR sessionDuration orphaning is the root cause.
- **Placeholder exercises appear in final render** → universal pool contains names not in the library.
- **Advanced combos fail where Beginner succeeds** on the same slot → `suitable_for` filtering issue.
- **Library triplet count = 0 for a production-plausible slot** → taxonomy/tagging gap in library data.
- **Wrapper finds N exercises but selector picked placeholder** → bug inside `_cascadeFill` itself (control flow, not filter semantics).

### Deliverables

- `test/plan_generator/v4_diagnostic_test.dart` (new)
- `test/plan_generator/v4_diagnostic_output.md` (generated artifact, committed)
- Zero production code changes

### Runtime & CI

- Runs with `flutter test`, no device, no `.env`, no Supabase.
- Expected runtime: seconds (10 combos × in-memory Hive + pure Dart).
- Not added to CI — diagnostic only, run manually when investigating.

## Open issues (deferred to separate brainstorms)

1. **sessionDuration data-model gap.** No DB column, no caller passes it. 5 orphan call sites: `onboarding_provider.dart:339`, `edit_profile_screen.dart:1595`, `train_provider.dart:469`, `graduation_screen.dart:493`, `auth_provider.dart:432`. Every user hits the `?? 45` default inside `VolumeFilter`.
2. **scheduled_workouts cloud schema.** No `exercises` column. Generator output is not inspectable from server — blocks server-side debugging of production user plans.
3. **Profile sync broken for icanbefitter@gmail.com.** Supabase row all-null despite Hive being populated. Fire-and-forget sync at `edit_profile_screen.dart:1615` (no await, no catchError). Sync payload also missing columns: `session_duration_minutes`, `lifestyle_activity`, `physique_focus`, `phone`.
4. **"LEG DAY RELAXED" UI label source.** String doesn't appear in split_resolver.dart; likely generated in VolumeFilter or a UI widget. Trace will locate it but this spec doesn't fix it.

## Approval gate

Per user's rule ("approved thrice"), implementation does NOT begin until:
1. Section-by-section design approved during brainstorm ✅
2. Full spec approved after write ← **current step**
3. Implementation plan (writing-plans skill) approved before any test file is created

---

*End of design spec.*
