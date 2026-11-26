# Batch 11-B — Cross-Phase Variety (W3.4), HARDENED plan

Worktree `workout-variety-11b` off main `0fa2b56c` (11-A + 11-C shipped). Blast radius **platform**.
Ship-dark `enable_cross_phase_variety` (default OFF → byte-identical). Last piece of Batch 11.
§4.12 ×2 review: Round-1 ×2 CONVERGED (no P0; spec-hardening folds below); Round-2 pending on THIS hardened plan.

## Feature
When generating a NEW phase, the cascade AVOIDS repeating the previous phase's pick for a slot
WHEN a same-`movement_pattern` sibling exists (motivation; Baz-Valle 2019). BOUNDED: never forces a
wrong pattern, never empties a slot, deterministic (no churn). It EXTENDS 11-C's `_selectCandidate`:
injury-sub selects the pool (outer), variety breaks ties within it (inner "prefer-injury-sub-then-variety").

## Design (extends the SHIPPED _selectCandidate — DO NOT transcribe the abbreviated 11-C pseudocode)
The shipped `_selectCandidate(candidates, {injuries, applyInjurySubstitutePreference})`:
OFF→`candidates.first`; else injury-sub pool filter → **sort subs by prefs.indexOf** → `subs.first`.
11-B adds `Set<String> avoidNames = const {}` and makes the FINAL return `_preferNovel(pool, avoidNames)`
where `pool` is the (already injury-sub-filtered + **map-order-sorted**) list, OR the full `candidates`
when injury-sub didn't narrow. **KEEP 11-C's sort** — `_preferNovel` walks the sorted pool:
```
_preferNovel(pool, avoidNames):
  if avoidNames.isEmpty return pool.first          // OFF path → verbatim (byte-identical)
  for c in pool: if !avoidNames.contains((c['name'] as String? ?? '').toLowerCase()) return c
  return pool.first                                 // only last-phase picks remain → keep (bounded)
```
So `_selectCandidate` OFF/OFF (both flags off, avoidNames empty) → `candidates.first` (byte-identical).

## Round-1 FOLDS (binding)
1. **Extract shared row-parsers (P1).** `namesOf`/`collect` are PRIVATE closures nested in
   `WorkoutScheduleReadService.repeatPinsFrom` — NOT reusable as-is. Extract to STATIC helpers
   (e.g. `_exerciseNamesOfRow(row)` + `_collectWorkoutRowsByDayIndex(week)`) on the service; call
   from BOTH `repeatPinsFrom` AND the new `previousPhaseNamesByDay` (one parser — #1 drift class).
   `previousPhaseNamesByDay()` = the same getWeek(1)/getWeek(2) + collect, WITHOUT the G5
   `last_phase_profile` gate → `Map<int,({List<String> a, List<String> b})>`.
2. **`avoidNames` is SOFT — feeds `_selectCandidate` ONLY (P1).** ⚠ NEVER add avoidNames to
   `pickedNames`/`excludeNames` or `queryV4`'s `excludeNames:` — those are HARD candidate-shrinking
   filters; conflating would let an avoided name hard-empty a thin same-pattern pool (e.g.
   shoulder·vertical_push = 2 safe) → an unwanted fallback → violates the 0-fallback invariant.
   avoidNames is threaded as its OWN param generateV4→pickV4→_fillSlots→_cascadeFill→_selectCandidate.
3. **Tracer mirror gets avoidNames + _preferNovel (P1).** Add `Set<String> avoidNames = const {}` to
   `cascade_tracer.dart` `trace()` + mirror `_preferNovel` inside `_selectCandidateName` (1:1 with
   production, keep the sort). `query_v4_mirror.dart` UNCHANGED. The multi-phase sweep MUST drive
   `trace(avoidNames: prevPhaseNames)` or it passes trivially (false coverage).
4. **exact + lowercased avoidNames (P2).** `_preferNovel` matches `avoidNames.contains(name.toLowerCase())`;
   `previousPhaseNamesByDay` returns LOWERCASED names (house `_isContraindicated` precedent).
5. **Indexed pickV4 loop (P2).** `pickV4`'s per-day `for (final day in slotDays)` → `for (var i=0; …)`
   so day `i` resolves `avoidA = previousPhaseByDay?[i]?.a`, `avoidB = previousPhaseByDay?[i]?.b`
   (A-fill avoids prev.a, B-fill avoids prev.b — composes with the existing intra-phase B hard-exclude
   of A names). `buildPinnedDays` already uses an indexed loop — same pattern.
6. **L6 note (P2).** `_applyHistoryAdjustments` (phase≥2) may re-swap a novel pick toward a demoted
   exercise — safe (still injury-filtered), documented (like 11-C's L6 note), not a regression.
7. **Edge cases (P2, note in SoT).** (a) daysPerWeek/split-shape change across advance → day-index
   misalignment is a HARMLESS no-op by construction (_preferNovel only re-ranks the already-filtered
   non-empty candidates; a stale avoid-name matching nothing → falls to .first). (b) repeatContent
   requested but G5-rejected (`pins==null` via mismatch) → variety fires on the fallback-fresh
   generation — acceptable.

## ROUND-2 folds (verdict CONVERGED — §4.12 ×2 satisfied: Round-1 ×2 + Round-2)
- **buildPinnedDays UNCHANGED (simplification).** Variety is mutually-exclusive with `pins` (pins==null
  gate), so ONLY generateV4's `pickV4` branch threads `previousPhaseByDay`; buildPinnedDays' internal
  `fresh()` pickV4 call omits it → avoidNames empty → inert. Do NOT add the param to buildPinnedDays.
- **P2 — attempt-5 (universal pool) is NOT variety-eligible.** attempt-5's pool-walk never calls
  `_selectCandidate`, so thinnest-pool slots that fall through get no variety (stays exactly as safe as
  today — not a defect). SoT + CLAUDE.md note this scope limit (like the L6 caveat).
- **P2 — behavioral SET-DIFFERS test pins a DEEP-POOL persona:** `equipment:'full_gym',
  experienceLevel:'advanced'` (advanced → suitableFor:null, broadest pool) so avoiding last-phase's
  picks genuinely pulls in novel siblings → the SET changes (a shallow/beginner persona has pool-depth-1
  slots where _preferNovel is a guaranteed no-op).
- **P2 — lowercasing split:** the shared `_exerciseNamesOfRow` keeps ORIGINAL case (repeatPinsFrom's
  `getByExactName` needs it); `previousPhaseNamesByDay` applies its OWN `.toLowerCase()` on top.

## Threading + flag
- `generateV4` gains `Map<int,({List<String> a, List<String> b})>? previousPhaseByDay` (default null).
  When null → avoidNames empty everywhere → inert.
- FLAG read at the SERVICE layer (precedent: `WorkoutScheduleReadService.adherenceGateEnabled` read at
  its own service): the two advance callers (`autoGenerateNextPhaseIfNeeded`, `graduation_screen._onPro`)
  call `previousPhaseNamesByDay()` ONLY when `crossPhaseVarietyEnabled` AND `pins == null`, and pass
  the result into `generateAndSchedule → generateV4`. OFF → not called → `previousPhaseByDay: null`.
  Read BEFORE `generateAndSchedule` overwrites plan_start (both sites already read pins there).
- `enable_cross_phase_variety` / `crossPhaseVarietyEnabled` in `plan_engine_flags.dart` (ship-dark OFF).

## Tests
- **Behavioral** `test/contracts/cross_phase_variety_behavioral_test.dart` (reuse the library-seed
  harness): generate phase N (capture per-day A/B names); generate phase N+1 passing
  `previousPhaseByDay = <phase-N names>`. ON → the phase-N+1 name SET DIFFERS from phase N (variety
  pulled in novel siblings — queryV4 is deterministic so OFF would reproduce phase N); OFF/param-null →
  phase N+1 SET == phase N (byte-identical); every day non-empty (no `(none)`); combined
  injurySub+variety persona → variety never escapes the curated pool (precedence preserved).
- **Multi-phase 0-fallback sweep** (Round-4c gap): extend `generator_matrix.dart` (or a sibling) with a
  2-phase driver — phase N names → phase N+1 via `CascadeTracer.trace(avoidNames: …)` across
  `personaMatrix()`, assert `fallbacks==0 && missing==0` in N+1. ADDITIVE (a new assertion) — do NOT
  modify the flag-OFF single-phase baseline sweep (frozen D3 baseline stays put).

## SoT `cross_phase_variety`
writers: `previousPhaseNamesByDay` + the extracted parsers + the `avoidNames`/`_preferNovel` thread +
generateV4 previousPhaseByDay. reader: `_cascadeFill._selectCandidate` (`_preferNovel`). behavioral_test_path:
`test/contracts/cross_phase_variety_behavioral_test.dart`. kill-switch `enable_cross_phase_variety`.
Notes: getWeek read-ordering; mutual-exclusion with `repeat_phase_pinned_selection` (pins==null); L6;
daysPerWeek-change no-op; avoidNames is soft (never queryV4).

## Ceremony: ship-dark flag (OFF byte-identical) + behavioral test + multi-phase sweep + self /code-review
B-pass BEFORE merge (§4.3 ≥platform) + this ×2 plan-review record + SoT. No diagnose-doc (feature).
⚠ Re-grep EVERY exercise_selector.dart line before editing — 11-C shifted them (_cascadeFill ~:1003,
_selectCandidate ~:982, _fillSlots ~:942, pickV4 ~:513/loop:550).
