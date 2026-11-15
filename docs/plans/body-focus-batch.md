# Focused plan — ⑤ body-focus bring-up (Batch 4) — OPTION 1 (+1-set emphasis)

Branch `workout-body-focus` off `b81e4fb6`. **Platform** tier (`plan_engine`). Kill-switch required.
Precedes code per §4.12 (this plan → round-2 context-blind review on the hardened plan →
`docs/plan-reviews/workout-body-focus.md` converged → implement → B-pass → land).

## Round-1 review + founder decision (scope locked)
Round-1 (context-blind) verdict **SPLIT** — VERIFIED by me against code: the originally-locked
"trade-not-add isolation-slot" mechanic is INFEASIBLE. (P1-a) `VolumeFilter.filter`
(`volume_filter.dart:52-57`) does a POSITIONAL `slots.take(target)`, never priority-sorted (priority read
only in the dead deload branch `:48-49`) → boosting `MuscleSlot.priority` is a no-op. (P2-b) split days are
hardcoded priority-ordered literals (`split_resolver.dart:553-575`) → on the focus muscle's theme day its
slots are already inside `take(N)` (nothing to promote), and on non-theme days it has no slot at all → a
position-reorder is inert. You can't give the focus muscle a meaningful dedicated slot without ADDING one
(breaks the tested `targetCount` count-per-day invariant, explicitly rejected).
**Founder decision 2026-07-13 (product fork):** ship the **+1-set emphasis** now; the dedicated focus
slot is a **future advancement** ("we will do that later"). This is a founder-ratified decomposition
(§4.12 split), NOT a deferral. So ⑤ = the translation layer feeding the EXISTING, working periodization
+1-set nudge.

## Scope (⑤ — Option 1)
Make `physique_focus` actually shape the plan by CENTRALLY translating the token → real muscle-substring
tokens and feeding `effectiveBodyFocus`, which periodization already consumes as **+1 set per matching
exercise** (`periodization_engine.dart:96-104`). NO isolation-slot allocation, NO pool-depth gate (the
+1-set adds no slots → cannot cause universalPool/(none)). Explicit focus precedes auto `weakMuscles()`.

## Ground-truth (verified b81e4fb6; ⚑ = re-verify at edit-time)
- **physique_focus dead in plan_engine** (grep 0). 4 tokens `balanced/glutes_legs/chest_shoulders_arms/
  strength` (`edit_profile_screen.dart:56,1051-1057,1616`). ⚑
- **Central seam** `plan_generator.dart:148-151` — `effectiveBodyFocus = bodyFocus.isEmpty && phase>=2 ?
  weakMuscles() : bodyFocus`; SOLE reader `PeriodizationEngine.apply` `:159`. **generateV4 ALREADY reads
  Hive here** (weakMuscles → `TrainingHistoryAnalyzer` reads Hive `:38`), so reading `physique_focus` from
  the profile at this same seam is consistent (no new Hive-coupling surface) AND degrades gracefully
  (null profile in tests → [] → no bring-up, exactly like weakMuscles returns [] with <14 logged days). ⚑
- **Periodization effect** `periodization_engine.dart:96-104`: `+1 set`, match
  `libraryMuscle.contains(focusToken)`, `break` after first (max +1/exercise). Raw `glutes_legs` matches
  no muscle → today's silent no-op. ⚑
- **Auto path** `weakMuscles()` gate `_minLoggedDaysForSignal=14` distinct days
  (`training_history_analyzer.dart:22,77`). ⚑
- **Stale comments** `edit_profile_screen.dart:76-78` AND `:1656-1660` claim physique_focus + session_duration
  drive the engine (false). ⑤ makes physique_focus TRUE; session_duration stays false (param-only). Fix both. ⚑
- **SoT** none for physique_focus→plan. New concept. **Kill-switch** ship-dark `enable_*` default-OFF
  (matches graded/session_detraining — changes prescribed volume). ⚑

## Translation table (verified correct against real primary_muscles; match = libraryMuscle.contains(token))
- `balanced` → `[]` (fall through to weakMuscles at phase≥2)
- `glutes_legs` → `['glutes','quads','hamstrings','calves']` (library uses 'Quads' not 'Quadriceps' → substring works)
- `chest_shoulders_arms` → `['chest','delt','shoulder','triceps','biceps']` (`delt` catches Deltoid+Delts;
  `shoulder` catches Shoulders+Shoulder Stabilisers that `delt` misses — keep both)
- `strength` → `[]` (not a body region; founder-consistent "may not belong")

## Design decisions
- **D1 — central seam, flag-gated for real ship-dark (round-1 P1-c + round-2 P2-a/b):** the
  `physique_focus` read lives in a NEW static `TrainingHistoryAnalyzer.physiqueFocusMuscles()` helper
  (try/catch Hive read of `HiveService.instance.userBox['profile']['physique_focus']` → the pure
  `physiqueFocusToBodyFocus(token)`; degrades to `[]` on null/corrupt/unopened-box exactly like
  `weakMuscles` `:87-92`) — this keeps the Hive read OUT of `plan_generator` (which imports no HiveService;
  it already imports TrainingHistoryAnalyzer). At `plan_generator.dart:148-151` the seam becomes: when
  `bodyFocus.isEmpty`, `focus = flagOn ? physiqueFocusMuscles() : []`; `focus.isNotEmpty ? focus : (phase>=2
  ? weakMuscles() : [])`. When the flag is OFF, `focus=[]` → the branch is the VERBATIM current logic
  (`bodyFocus.isEmpty && phase>=2 ? weakMuscles() : bodyFocus`) → byte-identical. **No fan-out** — every
  caller routes through `generate()→generateV4()→effectiveBodyFocus` (round-2 confirmed `apply` has ONE
  production callsite `:154`); nothing to thread through callers (resolves round-1 P1-b).
- **D2 — precedence:** explicit focus (non-empty translation) WINS over weakMuscles; `balanced`/`strength`/
  empty → `[]` → falls through to `weakMuscles()` (phase≥2) exactly as today.
- **D3 — mechanism = the EXISTING periodization +1-set:** no change to `periodization_engine`; it already
  +1-sets whatever `effectiveBodyFocus` tokens match. No slot allocation, no pool-depth gate.
- **D4 — kill-switch:** `enable_physique_focus_bringup`, `configBox.get(...)==true`, catch→false (ship-dark,
  mirrors graded/session_detraining). Verify on the test account, flip after (§4.6).
- **D5 — auto path byte-identical:** when flag OFF, OR focus is balanced/strength/empty, the seam behaves
  EXACTLY as today (weakMuscles +1-set path unchanged). `hypertrophy_archetype_test.dart:71-110` (calls
  `apply` directly, bypasses the seam) stays green — but therefore does NOT protect the seam; the new
  behavioral test must cover explicit-beats-weakMuscles + flag-OFF byte-identical.
- **D6 — stale comments:** correct both `edit_profile_screen.dart:76-78` + `:1656-1660` — physique_focus
  half becomes TRUE; session_duration half stays corrected-to-false (still param-only, ③ deferred).
- **Note (round-1 P2-e) — additive on FREE phase 1:** explicit focus flows at ALL phases (the phase≥2
  gate is only on the weakMuscles fallback), so a focus user's free phase-1 plan shifts by +1 set on
  matching exercises. Bounded by +1/exercise (`break`); no MRV clamp yet (W2.7 future). Acknowledge; the
  ship-dark flag governs rollout — do NOT extra-gate phase 1.
- **Note (round-1 P2-a) — chest_shoulders_arms breadth:** with +1-set-only (no slot), a broad focus adds
  +1 set to each matching push/arm exercise — proportionate to how many match on that day; acceptable +
  ship-dark. (The dedicated-slot breadth-bound is the deferred future-slot batch's concern.)

## Writer/reader contract (new SoT concept `physique_focus_bringup`)
- Writers: `plan_generator` (`_physiqueFocusToBodyFocus` + the seam profile-read + flag gate),
  `plan_engine_flags` (`physiqueFocusBringupEnabled`).
- Reader: `PeriodizationEngine.apply` (existing +1-set on the translated tokens).
- Behavioral test `test/contracts/physique_focus_bringup_test.dart`: translation table
  (glutes_legs/chest_shoulders_arms → tokens; strength/balanced → []); explicit-focus-beats-weakMuscles
  precedence; a seeded `physique_focus=glutes_legs` profile → a Glutes exercise gets +1 set (write→read
  through generateV4); flag OFF (default) → byte-identical (physique_focus ignored, weakMuscles path intact).

## Review focus areas (round-2, on this hardened Option-1 plan)
1. The seam's in-engine profile read is correct + gated; flag-OFF is VERBATIM the current logic
   (byte-identical) — verify no behavior leaks when OFF.
2. Central-source (no fan-out) genuinely covers all generation paths (the seam is the single funnel — every
   caller routes through generateV4's `effectiveBodyFocus`) — confirm no caller bypasses the seam.
3. Translation tokens match the intended real muscles and don't silently match nothing / over-match.
4. Graceful degradation: null/absent profile physique_focus in tests → [] → no bring-up (like weakMuscles).
5. Auto weakMuscles path + existing periodization/archetype tests stay green.
6. Precedence: explicit focus beats weakMuscles; balanced/strength fall through correctly.
7. Re-verify ⚑ items (seam line, periodization match, the Hive read pattern, stale-comment sites).
