---
branch: workout-body-focus
batch: 4-⑤
scope: ⑤ body-focus bring-up, Option 1 (physique_focus translation → existing +1-set nudge)
blast_radius: platform
reviewer: context-blind adversarial B-pass (self-initiated, §4.3)
verdict: accepted
verdict_note: initial verdict changes-needed (1 P2 test-coverage gap + 1 P3 doc cite); both fixed + re-verified → accepted
---

# B-pass — ⑤ body-focus bring-up (Option 1)

Context-blind adversarial review of the staged diff. **Zero code defects** — the reviewer independently
traced the ship-dark guarantee, checked the translation table against all 258 library rows, and verified
graceful degradation. One test-coverage gap (P2) + one doc cite (P3), both fixed.

## Verified-clean (no code defect)

- **Flag-OFF byte-identical — VERIFIED (ship-dark guarantee).** All three cases traced: bodyFocus
  non-empty → unchanged; empty+phase≥2 → weakMuscles(); empty+phase<2 → stays empty — identical to the
  pre-⑤ seam. The ~20 existing generateV4 tests (flag default OFF) stay green.
- **Precedence + all-phases — VERIFIED.** Flag ON: non-empty physiqueFocusMuscles() wins over weakMuscles
  and applies at ALL phases; balanced/strength/empty → [] → weakMuscles only at phase≥2. Phase-1 explicit
  focus bounded to +1/exercise by the periodization `break`.
- **Helper + graceful degradation — VERIFIED.** `physiqueFocusMuscles()`: `is! Map` guard + `?.trim()` +
  try/catch → [] on null/non-Map/missing-field/non-String/unopened-box, never throwing into the generator.
  `HiveService.instance.userBox` confirmed the correct profile accessor (matches body_fat_default_healer,
  stat_snapshot_service).
- **Translation table — VERIFIED against all 258 rows.** glutes_legs + chest_shoulders_arms match the
  intended muscles, no over-match; `delt`+`shoulder` dual tokens both load-bearing (shoulder catches
  Shoulders/Shoulder Stabilisers that delt misses). All 4 written physique_focus tokens handled.
- **+1-set unchanged — VERIFIED.** `periodization_engine.dart` not in the diff; the archetype "+1 set"
  test untouched. Seam is a genuine single funnel (apply has ONE production callsite).
- **Stale comments accurate; flag getter mirrors the ship-dark graded pattern.**

## Findings + resolution

### P2 — generateV4 seam glue behaviorally unpinned (rule-21) — FIXED
The test pinned the three components (pure translation, apply-direct +1-set, helper Hive-read) but NO test
invoked the generateV4 seam, so the flag-gate + precedence wiring had no regression coverage — reverting
the seam edit would have passed every test (the exact false-confidence gap rule-21 targets; also
under-delivered the plan's binding P2-c).
**Fix (better than a flaky exerciseBox-seeded generateV4 boot):** extracted the inline seam into the
behavior-tested `TrainingHistoryAnalyzer.resolveBodyFocus({explicitBodyFocus, phase})` (behavior-identical
— same flag-gate + precedence, verified byte-identical-OFF); the `plan_generator` seam is now a one-liner
calling it. Added 4 glue tests: flag-ON+physique_focus → physique tokens (fails if the seam stops calling
the helper); flag-OFF → byte-identical []; balanced → []; explicit-param passthrough. Re-verified: +24
tests green, analyze clean, SoT parity PASS.

### P3 — doc line cite drift (:148-159 → the seam) — FIXED
`sot_registry.yaml` + `plan_engine/CLAUDE.md` cited `plan_generator.dart:148-159`; corrected to `:148-155`
(the resolveBodyFocus call site) and updated to name `resolveBodyFocus` as the glue.

## Verdict: accepted
Zero code defects at review; the test-coverage gap closed by extracting + directly pinning the seam glue
(`resolveBodyFocus`), the ship-dark flag-OFF byte-identical guarantee now behaviorally tested. Re-verified
green (24 tests, analyze clean, SoT completeness/parity/behavioral PASS). The dedicated isolation slot is
founder-deferred to next release (out of scope).
