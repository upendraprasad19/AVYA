---
review: workout-7a-phase-arc B-pass (W3.2 phase arc, ship-dark)
branch: workout-7a-phase-arc
date: 2026-07-17
reviewer: context-blind adversarial subagent (B-pass, §4.3 + §4.12 review-#2 on hardened impl)
blast_radius: platform
verdict: accepted
---

# B-pass — Batch 7-A phase arc (W3.2)

Context-blind adversarial review of the implemented diff (`git diff main`) — reader + facade +
`phaseArcEnabled` flag + `phaseArcProvider` + `PhaseArcStrip` + Train-screen wiring + the 8-test
behavioral suite — verified against the actual code + a live test run (8/8 pass) + `flutter analyze`
(clean on all 7 files).

## Verdict: ACCEPTED — no P0/P1

All 8 points CONFIRMED with file:line evidence:
1. **Round-1 fix (a) — snake_case key:** `read_service:556` reads `w['week_character']`; matches
   `WeekPlan.toMap` (`models.dart:79`) / `periodization_engine.dart:129`. Not camelCase → the strip
   populates (the behavioral test seeds + reads it back green).
2. **Round-1 fix (b) — `plan_screen.dart:195` UNCHANGED:** not in the diff; the 'mid-deload' copy is
   untouched (correctly stays accurate while the separate `enable_triggered_deload` (7-B) ships OFF).
3. **Ship-dark byte-identical:** flag absent/false → `phaseArcEnabled` false (`plan_engine_flags:163`,
   `== true`) → `phaseArcProvider` null BEFORE any wave read (`train_provider:717`) → `SizedBox.shrink`
   (`phase_arc_strip:29`). Placement after the pre-existing `SizedBox(height:10)` → OFF layout identical.
4. **Crash-safe:** `read_service:551-558` guards `raw is! Map` / `weeks is! List` / per-entry
   `(w is Map ? … : null)?.toString() ?? ''` — no `!`, no `.first`, no unguarded cast; pinned by 8 tests.
5. **Read-only / no engine coupling:** one `.get()` + `.map()`; no put/sync/generation; adds no new
   generation trigger (Train screen already hosts `currentPlanProvider`).
6. **Riverpod correct:** unconditional `ref.watch(currentPlanProvider)` then flag-gate → rebuilds on
   re-materialize; the `WorkoutScheduleService.instance`-in-provider pattern is used 30× (analyze-green).
7. **Wardroom/house rules:** `AppColors` palette only (`accent` #D4B270, rule 11) + `Colors.transparent`
   (allowed); `AppTypography.label`/`.micro` (rule 10 — the B-pass verified rule 10 at face value but the
   pre-commit **Gate 37** (`no_raw_google_fonts_test`) then caught raw `GoogleFonts.getFont('DM Sans')` in
   the widget and required the canonical `AppTypography`; switched — verified green); ConsumerWidget (no
   setState); free (no isPro). Overflow-safe (`Row` of `Expanded` + `Text(maxLines:1)`).
8. **Data supports display + SoT/tests:** `PeriodizationEngine.apply` = `List.generate(4, …)` always
   stamps exactly `[baseline, overreach, peak, deload]`, preserved through every stage into
   `Phase.weekPlans` → `waves.length == 4` aligns with `getCurrentWeekNumber().clamp(1,4)` (one node
   highlighted, correct). SoT `phase_arc_display` maps writer→4 readers with `behavioral_test_path`.

## Findings (P2/P3 — none blocking; no code fix required)
- **P2 (process):** this B-pass record must be authored before the merge (the plan-review record
  already points to it; `bpass: accepted` is substantiated here). — DONE by this file.
- **P3 (acceptable, match sibling ship-dark patterns):** `currentWeek` is date-derived → a week
  rollover without a `currentPlanProvider` invalidation can lag the highlight until the next rebuild
  (cosmetic, ship-dark); `phaseArcEnabled` is read-not-watched → a runtime flip applies on the next
  rebuild (intended flip-and-restart, matches every sibling flag); `TextOverflow.clip` center-clips a
  hypothetical renamed token (non-issue for the 4 known tokens); `screen.dart:32` import not
  alphabetized (not analyzer-flagged). All explicitly deemed acceptable.
- **Observation:** crash-safe against malformed DATA (as documented), not a closed box — matches every
  sibling reader in the file; the flag-gate + Train-screen context guarantee an open box. Not a regression.

Pure read-only display of already-stamped data; ship-dark OFF is byte-identical; both Round-1 fixes
landed; crash-safe + house-rule compliant; SoT + behavioral test present and green. No open issues.
