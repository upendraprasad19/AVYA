---
reviewed_at: 2026-07-17T23:30:00+05:30
staged_against: b7d05691feda
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 6
verdict: accepted
---

# Code Review (B-pass) — ⑧ UNIT 2-cap (repeat-phase pinned-selection) — staging b7d05691feda

Fresh Sonnet reviewer, context-blind, ran the 5 standard lenses + 7 plan-engine-specific
adversarial questions against the staged diff, cross-tracing `exercise_selector.dart`,
`plan_generator.dart`, `exercise_repository.dart`, `periodization_engine.dart`,
`split_resolver.dart`, `models.dart`, and one empirical engine run. **Net: caught one real P1
the ×2 plan-review missed. All 6 findings accepted + fixed in-batch (§4.2 no-deferrals).**

## Finding 1 — P1 — exercisesB collapse (CONFIRMED, empirically) — FIXED
- **claim:** `buildPinnedDays` set `exercisesB: exercises` (== exercisesA) unconditionally. But
  `pickV4` only collapses B→A when `slotsB == null`; the 4-day build_muscle split (the one the
  tests use) has a distinct `slotsB` on all days. `PeriodizationEngine` reads `exercisesB` for
  weeks 2 & 4 (`useB = !is6Day && weekIdx∈{1,3}`), so a "repeat" would DUPLICATE weeks 1/3 into
  weeks 2/4. All 7 original tests read only `Phase.workouts` (week 1) → structurally blind to it.
  The reviewer confirmed by generating a plan and diffing week1 vs week2 (0% overlap fresh; 100%
  collapsed).
- **disposition:** ACCEPTED. Root-fixed: `pinnedExercisesByDay` value is now a per-day record
  `({List<String> a, List<String> b})`; `buildPinnedDays` pins A into exercisesA (weeks 1/3) and B
  into exercisesB (weeks 2/4); a B-absent day derives a fresh B-variant when `slotsB != null`
  (never `B = A`), else `B = A` (mirrors pickV4's genuine `slotsB==null` branch). Tests (2)/(3)/(8)
  now assert week-2 (variant-B) sets — the collapse is a hard-fail. `generateV4`/`generate` param
  type updated; SoT + plan_engine CLAUDE.md updated.

## Finding 2 — P1 — equipment-TIER omission risks a stale cross-tier pin — FIXED (contract)
- **claim:** `buildPinnedDays` never checks the pinned exercise's `equipment_tier` against the
  CURRENT profile tier; the "att4 relaxes tier" defense only holds within ONE generation, not for a
  selection imported from a prior, possibly different-tier phase (e.g. full_gym→bodyweight leaves a
  barbell pin reachable). The SoT/plan-review only committed UNIT 2-int to gating goal+daysPerWeek,
  not tier.
- **disposition:** ACCEPTED as a CONTRACT clarification (not a 2-cap code change — the capability
  is correctly tier-agnostic; att4-relaxed same-tier picks must survive a faithful repeat). The
  cross-tier guarantee is the CALLER's: UNIT 2-int now gates the repeat on the prior phase's
  equipment-TIER being UNCHANGED (alongside goal + daysPerWeek). Documented on the `buildPinnedDays`
  docstring, the SoT entry, and the plan-review record; carried to UNIT 2-int's task.

## Finding 3 — P2 — test (1) "null byte-identical" was tautological — FIXED
- **claim:** the `gen()` helper's `pins` defaulted null, so `gen()` ≡ `gen(pins: null)` — the test
  compared a function to itself.
- **disposition:** ACCEPTED. Test (1) is now FACADE PARITY: `generate()` (which forwards the new
  `pinnedExercisesByDay` + `equipmentExclusions`) == direct `generateV4()` — a real regression guard
  for the facade additions — plus a "null pin is a valid populated plan" sanity check.

## Finding 4 — P2 — tests (2)/(7) couldn't distinguish live-dispatch from dead-fallthrough — FIXED
- **claim:** pinning the cascade's OWN output is indistinguishable from ignoring pins and re-running
  the cascade.
- **disposition:** ACCEPTED. New test (3) pins two SYNTHETIC non-organic names `(a:[X], b:[Y])` and
  asserts X in weeks 1/3, Y in weeks 2/4 — a dead dispatch provably diverges. Tests (4)/(5)/(6) also
  pin non-organic names (contraindicated / off-tier-only / nonexistent / custom-only). Live dispatch
  is now proven.

## Finding 5 — P2 — MF-1 "never a (none) day" overclaim — FIXED
- **claim:** the fresh-fill `pickV4([frame]).first.exercisesA` can still be empty in the documented
  all-pool-contraindicated edge (unchanged latent behavior of plain pickV4).
- **disposition:** ACCEPTED. Docstring + SoT softened to "degrades to at worst the SAME safe
  slot-omission a fresh generation would produce, never a bespoke `(none)`." No functional change.

## Finding 6 — P2 — `getCustomExercises()` rescanned per missed pin — FIXED
- **claim:** the custom fallback scanned the full customBox once per library-missing name.
- **disposition:** ACCEPTED. Hoisted to a lazy `customsCache` — scanned at most once per
  `buildPinnedDays` call, only if some name misses the library.

## Standard lenses — clean
writer_reader_drift (no new persisted field — pure in-memory `Phase`), function_exception_swallow
(no `functions.invoke`), blast_radius_mismatch (platform, correctly tiered; ship-dark via
null-default + behavioral test), secrets_in_tree (none), unawaited_no_error_sink (no async
fire-and-forget) — all confirmed clean by the reviewer's greps.

## Post-fix verification
`flutter analyze` clean (3 files); 8/8 behavioral (incl. the new week-2 / A-B-distinct / facade-parity
cases); 176/176 plan_engine regression green. **Verdict: accepted.**
