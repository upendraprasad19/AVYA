# Ship 2 — U3 warmup/cooldown injury filter (WU-1)

Branch `warmup-injury-filter`, off main WITH Ship 1 (so `InjuryVocab` is available).
Ship 2 of the workout-generator injury batch. Blast radius **platform**
(`lib/shared/repositories/plan_engine/warmup_cooldown.dart`).

## Problem (WU-1, from the master plan + the Ship-1 review)

Ship 1 injury-filtered the MAIN exercise cascade (attempts 1-4 + the U2 universal
pool). But `WarmupCooldownSelector.attach` (`warmup_cooldown.dart:53`) builds
warmup/cooldown from HARDCODED per-dayType name-lists (`_dynamicWarmup` :15-40,
`_cooldownStretches` :43-50, `_bodyweightCardio`/`_gymCardio` :9-12) — NOT the
library cascade. So injuries never touch them: a shoulder-injured user's push-day
warmup still contains "Push Up" / "Band Pull Apart", and their cooldown still
contains "Cross-body Shoulder Stretch" / "Overhead Stretch".

The warmup IS per-workout-day (dayType-keyed: push/pull/legs/upper/full_body/
shoulders_arms, beginner vs advanced tiers) — which is exactly why the push-day
warmup is shoulder-prep and needs the filter.

## Design — DROP-not-substitute (review-mandated)

The Ship-1 design review flagged U3 as exercise-science content with correctness
risk (same class as the deferred R9). Resolution: **DROP** a contraindicated
warmup/cooldown move (shorter warmup) rather than substitute — a negative "don't
load the injured area" claim, NOT a positive "this swap is safe" medical claim.

1. **Hand-authored move→injury-token map** (`_moveInjuries`) over the ~26 fixed
   warmup/cooldown/cardio moves. Uses the SAME canonical vocabulary as the main
   filter (`InjuryVocab.canonicalTokens`). CONSERVATIVE: tag a move with an
   injury only when it clearly loads/stresses that area. Proposed (for review):

   | Move | Injury tokens it loads |
   |---|---|
   | Arm Circles | *(none — low-load mobility; library tags it contra-free — Ship 1's safe fallback)* |
   | Torso Twists | lower_back |
   | Wall Push Up | shoulder, wrist |
   | Push Up | shoulder, wrist, elbow |
   | Band Pull Apart | *(none — light rear-delt activation; library contra-free)* |
   | Wrist Rotations | wrist |
   | Neck Rotations | neck |
   | Dead Hang | shoulder, wrist, elbow |
   | High Knees | knee, hip, ankle |
   | Leg Swings | hip, hamstring |
   | Hip Circles | hip |
   | Baithak (Hindu Squat) | knee, hip |
   | Jumping Jacks | knee, ankle, shoulder |
   | Spot Jogging | knee, ankle |
   | Jump Rope | knee, ankle, wrist |
   | Cycling (Stationary) | *(none — low-impact; safe for most)* |
   | Running (Treadmill) | knee, ankle, hip |
   | Slow Walking | *(none)* |
   | Chest Doorway Stretch | shoulder |
   | Cross-body Shoulder Stretch | shoulder |
   | Overhead Stretch | shoulder |
   | Standing Toe Touch | lower_back, hamstring |
   | Side Bend Stretch | lower_back |
   | Standing Quad Stretch | knee |
   | Deep Breathing | *(none)* |
   | High Knees / Leg Swings … | *(as above)* |

   Open question for review: is `Arm Circles`/`Band Pull Apart` truly safe for a
   shoulder injury? Ship 1 treated Arm Circles as the injury-safe shoulder_isolation
   fallback (library `injury_contraindications` empty), so this map must AGREE with
   the library where the move IS a library exercise, to stay self-consistent.

2. **`attach()` signature change:** add `List<String> injuries = const []`
   (default empty → verbatim old behavior for the no-injury 99%). Inside, DROP a
   dynamic-warmup / cooldown / cardio move whose `_moveInjuries` ∩ injuries ≠ ∅.
   Guard against emptying the warmup entirely — a minimum floor of the cardio +
   at least the contra-free moves (Deep Breathing / Slow Walking always survive
   as universally-safe anchors, so cooldown never empties).

3. **Thread `injuries`:** `generateV4` already computes `normalizedInjuries`
   (Ship 1) and calls `WarmupCooldownSelector.attach(...)` — pass it. VERIFY the
   attach() call site in plan_generator.dart + any OTHER attach() callers (custom
   templates auto-inject warmup per the plan-engine CLAUDE.md "Warmup/Cooldown
   now also auto-injects for custom templates").

4. **Kill-switch** `configBox['disable_warmup_injury_filter']` (default filter ON),
   read via a `PlanEngineFlags` accessor (mirrors Ship 1's
   `injuryUniversalFilterEnabled`), threaded as a bool param to `attach()`.

## Verification (⚠ Batch-0 gate CANNOT prove U3)

The Batch-0 scorecard scores only the MAIN exercises (`plan.allExercises`), NOT
warmup/cooldown. So the scorecard gate will NOT move for U3 — the BEHAVIORAL
TEST is the sole proof (corrects any "gate proves U3" assumption):
- `test/contracts/warmup_injury_filter_behavioral_test.dart` (Hive + real
  library, via PlanGenerator.generate): a shoulder-injured plan's warmup AND
  cooldown contain ZERO shoulder-loading moves (Push Up, Wall Push Up, Dead
  Hang, Chest Doorway/Cross-body/Overhead stretches); a knee-injured plan's
  warmup excludes High Knees/Baithak/Jump Rope; an uninjured plan is byte-
  identical to pre-fix (no move dropped); kill-switch OFF → moves reappear
  (non-vacuity).

## Discipline
- [x] Own worktree (warmup-injury-filter), own focused plan (this doc).
- [ ] ×2 context-blind review of THIS plan BEFORE code (§4.12) — ground-truth
  (attach() call sites, move inventory completeness, InjuryVocab availability,
  library self-consistency of the map) + design (the move→injury map correctness,
  drop-not-substitute, floor-never-empties, kill-switch). Record →
  `docs/plan-reviews/warmup-injury-filter.md` (converged; bpass accepted ≥platform).
- [ ] Diagnose-doc (warmup injury bypass); behavioral test (the sole proof);
  kill-switch; self B-pass before merge; commit/merge/push autonomously.

## ⚑ HARDENED after ×2 review (2026-07-12) — verdict: harden-then-implement (NOT split)

Both context-blind reviewers (ground-truth + design) converged. I verified the library
values against `assets/data/exercise_library.json` myself. Resolutions:

1. **Map-vs-library premise was FALSE — INVERT it (P1, both reviewers).** The library
   WARMUP/cooldown rows are UNDER-tagged (`Wall Push Up`/`Dead Hang`/`Chest Doorway
   Stretch`/`Cross-body`/`Overhead Stretch`/`High Knees`/… all `injury_contraindications:
   []`, yet they clearly load those areas). So the hand-map does NOT "agree with the
   library" — it deliberately **supersedes** the under-tagged library warmup rows (more
   conservative). Delete the false "must agree" claim.
2. **Main-selectable moves use the LIBRARY tags for consistency (resolves the Push Up
   contradiction).** `Push Up` (E005, `horizontal_push`, `["wrist"]`), `Band Pull Apart`
   (E093, `shoulder_isolation`, `[]`), `Baithak` (E077, `knee_dominant`, `["hip","knee"]`)
   are pickable by the MAIN cascade. The warmup map for these MUST equal their library tags
   (Push Up→wrist only, NOT shoulder) so a shoulder-injured user isn't given Push Up as a
   working set but denied it in warmup. Warmup-ONLY moves (not main-selectable) get the
   conservative hand tags.
3. **SURFACED Ship-1 gap (P2, NOT silently inherited):** the library under-tags MAIN moves
   too — `Push Up` is not `shoulder`-tagged, so Ship-1's main filter gives push-ups to a
   shoulder-injured user; `Spot Jogging`/`Running` aren't knee-tagged. **This is the founder
   decision below** — it changes the shipped main plan, so it is NOT decided unilaterally here.
4. **Guarantee a concrete non-empty warmup FLOOR (P1).** The old "floor of the cardio" was
   self-contradictory (a knee-injured bodyweight user's only cardio, Spot Jogging/Jumping
   Jacks, both drop; Cycling is gym-only). Fix: after filtering, if the dynamic warmup is
   empty inject a known-safe anchor (`Deep Breathing`); if all cardio drops, fall back to
   `Slow Walking` (or `Cycling` when gym). The warmup can never be emptier than {safe cardio
   fallback + 0..N dynamic}. (Worked worst case: knee+hip/legs/bodyweight → cardio→Slow
   Walking, dynamic all drop → warmup = [Slow Walking]. Non-empty. ✓)
5. **Thread `template_service.dart:164` (P1 — was "verify", too weak).** It reads
   `fitness_experience`/`equipment_access` from `profileMap` but NOT injuries → custom-
   template warmup is currently UNFILTERED. Add `InjuryVocab.normalize(InjuryVocab.fromProfile(
   profileMap['injuries']))` and pass it. (Coach regen + hotel need nothing — they route
   through `generateV4`, verified; only these 2 lib call-sites of `attach` exist.)
6. **Close the Arm Circles / Band Pull Apart open question (P1 — §4.2 bans an open medical
   question in a converged plan).** BOTH stay UNTAGGED — justified on LOAD, not library-
   deference: controlled low-load end-range mobility (Arm Circles) + scapular-retraction
   posterior-cuff activation (Band Pull Apart) are standard shoulder REHAB, not loading. The
   `Jumping Jacks: shoulder` tag is for BALLISTIC overhead impact (different) — internal
   consistency preserved by the load rationale.
7. **P2 conservative under-tags folded in:** `Wall Push Up` +`elbow`; `Baithak` +`ankle`
   (toe-rise); `Standing Quad Stretch` +`ankle` (single-leg balance).
8. **Kill-switch design nit (P2):** `attach()` reads `PlanEngineFlags.warmupInjuryFilterEnabled`
   itself (default-ON) so the template_service caller inherits it without a 2nd read.
9. **Extended behavioral test (P1):** add (a) worst-case multi-injury NON-EMPTY-FLOOR
   (knee+hip/legs), (b) knee-bodyweight cardio-drop→Slow-Walking-fallback, (c) irrelevant-
   injury-unchanged (wrist → legs warmup identical), plus a drift-guard test asserting every
   name in the dynamic/cooldown/cardio lists has a `_moveInjuries` entry (catches the dead
   `durationMap` entries `Ankle Rotations`/`Butt Kicks` if ever emitted).

**Verdict: CONVERGED (post-hardening) — implementable once the founder decision below is set.**
Plan-review record `docs/plan-reviews/warmup-injury-filter.md` to be written at merge.

## ⚑ FOUNDER DECISION NEEDED — library injury-tag aggressiveness (affects the SHIPPED main plan)

The ×2 review surfaced that `exercise_library.json`'s `injury_contraindications` is
**under-tagged** — not just for warmup moves, but for MAIN exercises (e.g. `Push Up` is
tagged `["wrist"]`, NOT `shoulder`). Consequence, live today after Ship 1: a **shoulder-
injured user is still given push-ups as a working set** in their main plan. Options:

- **(A) Recommended — bounded now + scoped follow-up.** Ship U3 as the conservative warmup/
  cooldown filter (warmup-only moves; main-selectable moves defer to their library tags so
  main+warmup stay consistent). Then a SEPARATE, deliberate batch does an exercise-science
  audit of the whole library's `injury_contraindications` (all 258 exercises) to fix the
  main-plan under-tagging (Push Up→shoulder, etc.) — a content project with its own review.
- **(B) Fold the main-move enrichment into U3 now.** Enrich the main-selectable moves'
  library tags in this batch too (Push Up→+shoulder+elbow, jogging→+knee…). Bigger blast
  radius (changes the shipped main plan for injured users), needs its own careful audit —
  the reviewers cautioned against silently expanding scope here.

I recommend **(A)** — it ships the warmup safety win cleanly and treats the deeper library
data-quality gap as the deliberate content project it is, rather than rushing a 258-exercise
re-tag inside a warmup batch. Which direction (or a variant)?

## Out of scope (separate batches, NOT deferred here)
- WU-2 (equipment consistency for warmup/cardio gym options) → Batch 5 (⑥ equipment).
- WU-3 (F1/F3 rewrite/copy must preserve warmup/cooldown) → Batches 7/8 (assertion).
