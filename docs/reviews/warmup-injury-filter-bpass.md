---
review: warmup-injury-filter U3 B-pass (Ship 2)
branch: warmup-injury-filter
date: 2026-07-12
reviewer: context-blind adversarial subagent (B-pass, §4.3)
blast_radius: platform
verdict: accepted
diagnose: d3f8a1
---

# B-pass — U3 warmup/cooldown injury filter (d3f8a1)

Context-blind adversarial review of the implemented diff (`git diff main -- lib
test`), verified against the actual code, the exercise library JSON, `flutter
analyze` (clean on all 5 changed files), and a live test run
(`warmup_injury_filter_behavioral_test.dart` → 7/7 green).

## Verdict: ACCEPTED — no blocking items

1. **`_moveInjuries` vs library — correct.** The 3 main-cascade-selectable moves
   match their library `injury_contraindications` EXACTLY (Push Up→{wrist}, Band
   Pull Apart→{}, Baithak→{hip,knee}); verified these are the only 3 main-
   selectable warmup moves, so no other move can re-introduce a main-vs-warmup
   contradiction. The implementation correctly did NOT add the plan's proposed
   `ankle` to Baithak (which would have broken library-consistency) — the plan's
   own item-7 tension resolved the right way. Warmup-only conservative tags are
   defensible.
2. **Floor guarantee — unbreakable.** `cardioLead` falls back to Slow Walking
   ({} tag); cooldown unconditionally prepends Slow Walking outside the filtered
   loop. No (dayType × injury × equipment) combo can empty warmup or cooldown;
   the 7-injury bodyweight-legs worst case is asserted per-day and passes.
3. **Threading — complete.** Exactly 2 lib callers (generateV4 passes
   normalizedInjuries; template_service reads profile injuries crash-safe); coach
   hotel + regen inherit via generateV4→attach. No 3rd caller; no `warmup:` built
   outside attach. Profile key `'injuries'` consistent with the writers.
4. **Kill-switch — fail-safe.** Read internally by attach (both callers inherit);
   default-ON on Hive absence / exception. Non-vacuity proven by the OFF test.
5. **Uninjured regression — byte-identical.** `filterOn=false` takes every
   original branch; the Deep Breathing anchor is gated behind `filterOn &&
   safeDynamic.isEmpty` so it never fires; the Slow Walking cooldown prepend was
   pre-existing.
6. **Tests — non-vacuous.** Baseline proves the uninjured plan contains the
   shoulder+knee moves; the drop/kill-switch tests would fail if the filter were
   removed; the drift-guard covers every emittable move.
7. **Null-safety / analyze / visibility — clean.** `@visibleForTesting` exposes
   only two immutable `Set<String>` getters; `fromProfile` handles List/String/
   null without throwing.

## Two non-blocking P2s

- **P2 (a) — deliberate, documented:** `Cycling {}` (low-impact) and `Arm Circles
  {}` (kept `{}` for consistency with Ship 1's safe shoulder fallback) are
  exercise-science judgment calls, already justified in the code comments. No
  change.
- **P2 (b) — FIXED in-batch:** the drift-guard's `allFixedMoves` is hand-assembled
  from the current lists, so a future NEW emittable LIST category (vs a new entry
  in an existing list) would be invisible to the guard. Added a ⚠ doc-comment on
  `allFixedMoves` telling maintainers to extend it in that case.

The founder-directed carve-out (the library's MAIN-move under-tagging — Push Up
not shoulder-tagged — is a separate audit batch, not expanded here) is correct.
