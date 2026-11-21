# Batch 11-B/11-C — Cross-Phase Variety (W3.4) + Curated Injury-Substitute Preference (①.1d)

## ⏳ IMPLEMENTATION STATUS (2026-07-18) — 11-C production code DONE + COMPILING (byte-identical, flag OFF)
**Shipping 11-C (①.1d) FIRST. §4.12 ×2 review COMPLETE + CONVERGED (Round-1 ×2 + Round-2; records above).**
DONE (compiles clean, `flutter analyze` 0 issues):
- `lib/shared/repositories/plan_engine/injury_substitutes.dart` — the curated map + `preferredFor` (List, lowercased, deduped).
- `plan_engine_flags.dart` — `injurySubstitutePreferenceEnabled` / `enable_injury_substitute_pref` (ship-dark OFF).
- `exercise_selector.dart` — `_selectCandidate` helper (map-order sort, exact-lowercased match, fallthrough) + 4 `_cascadeFill` return sites + `applyInjurySubstitutePreference` threaded through `_cascadeFill`/`_fillSlots`/`pickV4`/`buildPinnedDays`(+`fresh()`).
- `plan_generator.dart` — `generateV4` resolves the flag → passes to BOTH pickV4 + buildPinnedDays calls.
REMAINING for 11-C (all specified below + in the folds):
1. **Tracer mirror** — `test/plan_generator/v4_diagnostic/cascade_tracer.dart`: add `bool applyInjurySubstitutePreference=false` to `trace()` + mirror `_selectCandidate` at its 4 pick sites (~:119,148,173,196; it already receives `injuries`; import the Hive-free `InjurySubstitutes`). `query_v4_mirror.dart` UNCHANGED. Do NOT modify `generator_matrix.dart`'s trace call (baseline unmoved).
2. **Behavioral test** — `test/contracts/injury_substitute_preference_behavioral_test.dart` (reuse `repeat_phase_pinned_selection_behavioral_test.dart` harness): shoulder-injured horizontal_push slot → ON picks the curated sub (Machine Chest Press), OFF picks candidates.first (assert ON-specific, per Round-2 P2); sub-absent fallthrough; chosen sub never contraindicated; flag toggles via `cfg.put/delete('enable_injury_substitute_pref')`.
3. **SoT** `injury_safe_substitute_preference` (+ behavioral_test_path + the L6-phase≥2 note + "6 of 9 tokens" note) + nested `plan_engine/CLAUDE.md` cascade-section paragraph.
4. flutter analyze + targeted tests → self-B-pass (≥platform) → plan-review record `docs/plan-reviews/workout-variety-injurysub-11bc.md` → commit → merge --no-ff → push → CI.
Then **11-B (W3.4 variety)** on its own branch off post-11-C main (design below), then **Batch 12**.



Worktree `workout-variety-injurysub-11bc` off main `1d93b677` (11-A shipped). Blast radius: **platform** (plan_engine). Both ship-dark, default OFF. Focused plan drafted by a Plan subagent + ground-truth verified against code; **awaiting §4.12 ×2 context-blind review before implementation.**

## SPLIT DECISION (adopted): TWO units, **①.1d (11-C) FIRST**, then W3.4 (11-B)
- **11-C injury-sub = engine-local** (a const map `injury_substitutes.dart` + a candidate re-rank at the 4 `_cascadeFill` return sites; NO service-layer change, NO Hive read). Smaller, ships first, establishes the combined `_selectCandidate` seam + the `cascade_tracer` signature.
- **11-B variety = bigger** (a new non-G5 previous-phase reader on `WorkoutScheduleReadService`, an `avoidNames` param threaded pickV4→_fillSlots→_cascadeFill + both advance callers, AND a new multi-phase 0-fallback sweep). Increments on a green post-11-C main.
- Rationale: §4.12 "ship the smallest converged piece"; keeps each ×2 review focused; isolates the variety multi-phase-sweep risk from the trivially-safe injury-sub. NOT a deferral — explicit decomposition of an already-split batch.

## The shared seam (both units)
Both are a **candidate re-rank on the OUTPUT of `queryV4`**, applied at the four `return _buildExercise(candidates.first)` sites in `_cascadeFill` (`exercise_selector.dart:993,1006,1017,1030`). Neither changes `queryV4` filtering/sort → **`query_v4_mirror.dart` UNCHANGED**; only `cascade_tracer.dart` (the `_cascadeFill` mirror) changes. Neither changes which cascade attempt fires → the "0 attempt3/universalPool/none" target is preserved by construction. Attempt-5 universal pool stays verbatim.

Combined selector at each attempt-1-4 site:
```
_selectCandidate(candidates, {avoidNames, injuries, applyInjurySub}):
  pool = candidates
  if applyInjurySub:
    prefs = InjurySubstitutes.preferredFor(injuries)   // [] if no injuries
    subs = candidates.where(name in prefs)
    if subs.isNotEmpty: pool = subs                     // ①.1d precedence (outer)
  return _preferNovel(pool, avoidNames)                 // W3.4 tiebreak (inner)
_preferNovel(cands, avoid): avoid.isEmpty ? cands.first : (firstNotIn(avoid) ?? cands.first)
```
Precedence "prefer-injury-sub-then-variety": injury-sub selects the pool, variety breaks ties within it.

## 11-C (①.1d) design
- **Map:** new Hive-free `lib/shared/repositories/plan_engine/injury_substitutes.dart` — `Map<String,List<String>>` keyed on InjuryVocab canonical tokens (shoulder/knee/lower_back/…) → ordered preferred safe substitute NAMES. `preferredFor(List<String> injuries)` → union, deduped, lowercased.
- **Insertion:** the `_selectCandidate` re-rank (with `applyInjurySub` only; `avoidNames` empty until 11-B). Re-ranks the POST-injury-filter, pattern-locked candidate list → **structurally cannot surface a contraindicated exercise** (safety). PREFERENCE (safe fallthrough if no curated sub in the candidate set).
- **Flag:** `injurySubstitutePreferenceEnabled` / `enable_injury_substitute_pref` (ship-dark OFF), resolved ONCE in `generateV4` → `applyInjurySubstitutePreference` bool threaded down (mirrors `applyInjuryUniversalFilter` at `plan_generator.dart:162/174`). `_cascadeFill` never reads Hive → tracer mirrors with a plain bool. OFF → `_selectCandidate` reduces to `candidates.first` → byte-identical.
- **⚠ KEY RISK (verify against `assets/data/exercise_library.json` before finalizing the map):** the re-rank can only surface a curated sub that shares the SLOT's `movement_pattern` AND is in the tier pool. Each `injury→sub` pair MUST be library-tag-verified or it silently no-ops. This is the single highest-risk correctness checkpoint (and why ①.1d was originally Wave-3 content work).
- **Test:** `test/contracts/injury_substitute_preference_behavioral_test.dart` (reuse the `repeat_phase_pinned_selection_behavioral_test` harness: seed library into exerciseBox, drive real generateV4). Cases: ON → injured slot picks curated sub; OFF → candidates.first (byte-identical); sub absent → fallthrough; chosen sub never contraindicated.
- **cascade_tracer.dart:** add `bool applyInjurySubstitutePreference=false` to `trace`; replace the 4 attempt picks with mirrored `_selectCandidate`; import InjurySubstitutes; attempt-5 unchanged; defaults keep 5 call sites byte-identical.
- **SoT:** `injury_safe_substitute_preference` concept + behavioral_test_path.

## 11-B (W3.4) design (after 11-C lands)
- **Previous-phase names reader:** ADD `WorkoutScheduleReadService.previousPhaseNamesByDay()` — reuses `namesOf`/`collect` over `getWeek(1)`/`getWeek(2)` (`:684-700`) WITHOUT the G5 `last_phase_profile` gate (avoiding a stale name is safe even if frames changed). Returns `Map<int,({List<String> a,List<String> b})>`. Called at the two advance sites (`autoGenerateNextPhaseIfNeeded:478-488`, `graduation_screen._onPro:634-644`) ONLY when variety flag ON AND `pins==null` (variety ⟂ repeat-content, mutually exclusive).
- **Thread:** `generateV4`(`plan_generator.dart:74`) → `pickV4`(`exercise_selector.dart:512`, index the `:546` loop so day i → avoidA=prev[i].a for slotsA `:548`, avoidB=prev[i].b for slotsB `:559`) → `_fillSlots`(`:934`, `Set<String> avoidNames=const{}`) → `_cascadeFill`(`:967`). `_preferNovel` inner. A-fill avoids prev.a, B-fill avoids prev.b (composes with existing intra-phase B hard-exclude of A `:561`).
- **Flag:** `crossPhaseVarietyEnabled`/`enable_cross_phase_variety` — read at the SERVICE layer to gate the previousPhase read; OFF → not invoked, `previousPhaseByDay:null` → inert.
- **Multi-phase 0-fallback sweep (Round-4c gap):** extend `generator_matrix.dart`/a sibling with a 2-phase driver (phase N names → phase N+1 with avoidNames across `personaMatrix()`), assert `fallbacks==0 && missing==0` in N+1 — the cross-phase exclusion single-phase sweeps never exercise.
- **Test:** `test/contracts/cross_phase_variety_behavioral_test.dart` — OFF byte-identical; avoid-when-sibling; keep-when-no-sibling; no (none); A/B avoid correctness.
- **SoT:** `cross_phase_variety` concept (+ getWeek read-ordering + mutual-exclusion note).

## Ground-truth corrections the Plan agent flagged (VERIFY EACH before implementing)
1. A/B threading target is **`pickV4`** (exercise_selector.dart), not `generateV4` directly (generateV4 calls pickV4 at `plan_generator.dart:166`).
2. **Coding rule 14** ("never modify plan_generator.dart without explicit instruction") is triggered — the batch mandate is that instruction (precedent: batches 3-10 extended generateV4); note in the plan-review record.
3. Previous-phase reader **already exists** (W2.5 repeatPinsFrom/getWeek) → 11-B needs only a non-G5 variant + threading.
4. `queryV4` unchanged → **QueryV4Mirror needs no update**; only cascade_tracer.dart.
5. ①.1d bounded to same-movement_pattern in-tier curated subs — map MUST be library-verified.

## ①.1d FEASIBILITY — VERIFIED against assets/data/exercise_library.json (258 rows)
Injury token counts: shoulder 33, knee 30, hip 26, lower_back 24, wrist 15, elbow 12, ankle 13, neck 1, hamstring 2. `movement_pattern` is an ARRAY. queryV4 ALREADY drops contraindicated rows → the curated map re-ranks the SAFE same-pattern remainder (so it can NEVER surface a contraindicated exercise; value is highest where the safe pool is THIN). Verified safe-remainder subs (all library-present, same-pattern, NOT tagged for the injury; `*`=foundational):
- **shoulder** · horizontal_push (8 contra / 18 safe): Machine Chest Press*, Dumbbell Bench Press*, Push Up* · vertical_push (10/2 — THIN): Kettlebell Goblet Press, Front Raise* · shoulder_isolation (4/4): Face Pull*, Band Pull Apart* · vertical_pull (4/6): Lat Pulldown*, Chin Up* · elbow_extension (3/6): Tricep Pushdown (Cable)*
- **knee** · knee_dominant (27/10): Leg Press*, Leg Curl (Lying)*, Wall Sit* · hip_isolation (2/9): Glute Bridge*
- **lower_back** · hip_dominant (12/9): Hip Thrust*, Romanian Deadlift* · horizontal_pull (3/12): Chest Supported Row*, Seal Row
- **wrist** · horizontal_push (6/20): Machine Chest Press* · elbow_flexion (3/10): Cable Curl* · vertical_push (2/10): Landmine Press
- **elbow** · elbow_extension (5/4): Tricep Pushdown (Cable)* · elbow_flexion (4/9): Cable Curl*
- **hip** · knee_dominant (18/19): Leg Press*, Leg Extension* · hip_isolation (3/8): Glute Bridge*
Curated map = these verified safe subs (prefer foundational + machine/DB variants = joint-friendlier). ①.1d confirmed OPTIONAL POLISH (safe cascade refill already ships) but real + safe. The behavioral test seeds the real library so a wrong/missing map entry is caught (would no-op, never harm).

## HARDENED — Round-1 ×2 folds (both context-blind reviewers converged; NO P0; safety+inertness independently confirmed)
Binding implementation directives for 11-C:
1. **Honor map order (P1).** `_selectCandidate`: after `subs = candidates.where(isCuratedSub)`, SORT `subs` by `prefs.indexOf(name.toLowerCase())` (stable, map-order-first) BEFORE `_preferNovel`. So the curated list order IS the preference (Machine Chest Press before Push Up etc.). Map lists are authored foundational/joint-friendlier-first.
2. **Exact + lowercased BOTH sides (P1).** `preferredFor` returns a `Set<String>` of lowercased EXACT names; the candidate check is `prefs.contains((c['name'] as String? ?? '').toLowerCase())` — NEVER substring (the "Push Up"⊂"Pike Push Up" bug class, house precedent `_isContraindicated` lowercases both sides). A missed lowercase = permanent silent no-op → pinned by the behavioral test asserting the SPECIFIC curated name.
3. **Drop Romanian Deadlift + variants from lower_back (P1).** RDL/Single-Leg-RDL/Trap-Bar have EMPTY `injury_contraindications` but share Stiff-Legged-Deadlift's lumbar-loading mechanics (which IS tagged) — an under-tagging gap, not vetted safety. lower_back·hip_dominant curated = **Hip Thrust** only; lower_back·horizontal_pull = Chest Supported Row / Seal Row (independently safe: supported = spine unloaded).
4. **Frozen-baseline text correction (P1).** The D3 baseline gate is `scorecard_gate_test.dart` → `generator_matrix.dart` `personaMatrix()` (~21 INJURED personas, :238-253) → `CascadeTracer.trace`. 11-C does NOT modify `generator_matrix.dart`'s trace call, so its mirror param defaults `false` there → injured personas keep the pre-11-C pick → `baseline_scorecard.json` unmoved. (NOT "because no injuries.") If a FUTURE batch wires the flag through that trace call, re-run `generate_baseline.dart`.
5. **Thread through buildPinnedDays (P2).** Add `bool applyInjurySubstitutePreference=false` to `buildPinnedDays` signature (`exercise_selector.dart:653-664`) AND its internal `fresh()` closure's `pickV4` call (`:716-726`), mirroring EVERY `applyInjuryUniversalFilter` appearance (incl. `:662`,`:724`) + the `generateV4` call site (`plan_generator.dart:162-163`). Else a repeat-content fresh-fill silently skips the preference when the flag is ON.
6. **Doc nits (P2).** `CascadeTracer.trace` has 7 call sites (v4_diagnostic_test:121,145 · markdown_writer:109 · sample_plans_report:52 · injury_safe_omission_test:41,60 · generator_matrix:175) — all byte-identical via defaulted param. Curated map covers 6 of 9 InjuryVocab tokens (ankle/neck/hamstring → no subs → safe fallthrough; state in SoT).
7. **CONVERGENCE:** Round-1 surfaced only bounded refinements (no redesign, no P0) → the unit is right-sized. Fold + one Round-2 verification pass on this hardened plan (§4.12: catch defects the corrections introduce), then implement.

## ROUND-2 folds (verdict CONVERGED, implementation-ready — §4.12 ×2 satisfied: Round-1 ×2 + Round-2)
1. **P1 (compile-blocking) — `preferredFor` returns `List<String>`, NOT `Set<String>`.** Fold 1's `prefs.indexOf(...)` needs an ordered list; `Set` has no `.indexOf`. Order-preserving + deduped `List<String>` (a "seen" guard while unioning multiple injuries). `.contains()` on a List is still EXACT-match (Fold 2's safety guarantee intact). `_selectCandidate` sorts `subs` by `prefs.indexOf(name.toLowerCase())` (all subs are in prefs → index always ≥0).
2. **P2 — multi-injury union order:** iterate `injuries` in caller order, append each injury's curated list, skip already-added (deterministic).
3. **P2 — behavioral test asserts the ON-specific curated pick, NOT a hardcoded OFF winner** (verified: shoulder·horizontal_push real slot — Dumbbell Bench Press is queryV4-first, Machine Chest Press is the curated pick → ON≠OFF observable; but ties have no tertiary sort key, so don't pin the OFF exact winner — assert ON picks the curated name + OFF≠that-when-not-already-first, or OFF==candidates.first).
4. **P2 (note, no code) — L6 `_applyHistoryAdjustments` (`exercise_selector.dart:782-827`, phase≥2 only) can re-swap a curated pick if it's in the user's `demoted` set** — NOT a safety issue (L6's replacement is still `injuryExclusions`-filtered) and arguably correct (explicit user demote beats app suggestion). The phase-1 test harness has L2/L6 gated off (`:570`). Note in SoT so it's not mistaken for a regression.
CONVERGED — no third round.

## Ceremony (per unit): ship-dark flag (OFF, byte-identical proven) + behavioral test (Gate 42) + self-initiated /code-review B-pass BEFORE --no-ff merge (§4.3 ≥platform) + ×2 context-blind plan-review record (`docs/plan-reviews/<branch>.md`) + SoT + retrospective. No diagnose-doc (feature). Worktree-per-session (§4.13).
