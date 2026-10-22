# Exercise library + plan generator — comprehensive design

**Date:** 2026-10-21 · **Status:** Approved by the founder 2026-10-21; Batch A planned 2026-10-22 (`docs/plans/2026-10-22-library-data-repair.md`) · **Owner:** founder (decisions), Claude (build)
**Brainstorm record:** memory `project_exercise_library_comprehensive_brainstorm_inflight.md` (decisions 1–16).
**Working data (not in repo yet):** session scratchpad `tag/merged.json` (1,064 rows), `tag/RULES.md` (tagging rulebook), review page `tag/exercise_tag_review.html`.

---

## 1. Goal

Every user — beginner to advanced, any equipment from "nothing" to a well-equipped gym — gets a
scientifically sound plan built from a curated set of exercises, with an animation for almost
every exercise, and a library deep enough that a swap always has a sensible option.

**Success looks like**
- A plan day never contains an exercise the user cannot do with their equipment, or one above/below their level.
- Every movement slot a level needs is fillable for that level's assumed setup (§4.3).
- Session size follows a set budget tied to the user's minutes (§5), not a fixed exercise count.
- Custom exercises never enter a plan unless the user (or the coach, on request) puts them there.
- An animation plays for ≥ 90 % of exercises in a typical plan; the rest show the still plate or monogram.

## 2. Decisions (founder, locked)

| # | Decision | Date |
|---|---|---|
| D1 | The library is **comprehensive**: every equipment variant of a movement is kept (DB / BB / cable / machine / band / bodyweight). | 10-20 |
| D2 | Calisthenics skills, Olympic lifts, forearm/wrist isolation, extra stretches and weighted calisthenics are **kept** — as a separate **Phase 2 calisthenics track**, never mapped into normal programs. | 10-20 |
| D3 | A **core list per level** (beginner / intermediate / advanced) drives generation. Non-core rows serve swap and search only. Target the masses. | 10-20 |
| D4 | "Full gym" never assumes every machine. A **standard gym** = dumbbells, barbells, bench/rack, Smith machine, cables, leg press (+ common selectorised machines). Rare kit (sled, rings, …) is opt-in. | 10-20 |
| D5 | No-equipment users get towel / self-resistance moves for arms, shoulders and pulling, **and** a nudge to buy a resistance band and a doorway pull-up bar. | 10-21 |
| D6 | **No fallback to a lower level's list.** Intermediate and advanced users are assumed to train in a gym; their no-equipment gaps are accepted. | 10-21 |
| D7 | Incline Pike Push Up (hands on a chair) added as the beginner no-equipment vertical push. | 10-21 |
| D8 | The generator **never auto-adds custom exercises** (removal of lever L2 — Batch 0). | 10-21 |
| D9 | The Wardroom WebP animations **ship** (founder accepts the licensing risk). Keep per-file provenance so a takedown is a one-file swap. | 10-21 |
| D10 | Ship the **720 px** WebPs as-is; revisit size (480 px tested as best smaller option) only if downloads get slow. Supabase **Pro** before launch. | 10-21 |
| D11 | Founder review is minimal: finalise list (done), approve core lists (done); non-core rows accepted as drafted. | 10-20/21 |

## 3. Data model

### 3.1 Library row — new fields (added to the existing ~37)

| Field | Values | Used by |
|---|---|---|
| `core_levels` | subset of `beginner`, `intermediate`, `advanced` | generator pool (§4.1) |
| `variant_family` | snake_case family, e.g. `bench_press`, `lateral_raise` | swaps, "Not at my gym", within-level fill (§4.2) |
| `discipline` | strength, calisthenics_skill, olympic, plyometric, mobility, cardio, prehab, yoga, conditioning | exclusion of skills/olympic from normal plans |
| `gym_availability` | home, standard_gym, well_equipped_gym, specialty | setup filter + gym-extras checklist (§6) |
| `skill_track`, `skill_step`, `regression_to`, `progression_to` | ladder data | Phase 2 track only (§8) |
| `requires_coaching`, `high_impact` | bool | gating (Olympic, plyometrics) |
| `media_slug`, `media_version`, `media_source` | string / int / provenance | animation delivery (§7), D9 |

Vocabulary changes: `difficulty_level` gains `elite`; `suitable_for` gains `Calisthenics`.
`target_focus` is normalised to the slot vocabulary (`Shoulders` → `Lateral Delts`, …) so substring matching in `queryV4` finds the row. This happens in Batch B, with the equipment-aware pool. `primary_muscles` is never renamed: it feeds the frozen muscle-group map, superset pairing, titration and the scorecard. On today's pool, making the towel rows visible would let cross-phase novelty hand them to home and gym users (Batch A evidence, 2026-10-22).

### 3.2 Equipment vocabulary (`lib/core/utils/equipment_vocab.dart`)
New tokens: weight plate, dip belt, weighted vest, gymnastic rings, trap bar, landmine, stability ball, balance board, sled, grip trainer, wrist roller, yoga strap, foam roller, sandbag, yoke. The single `machines` token keeps meaning "standard selectorised machines"; well-equipped / specialty items are their own tokens so a user can say they have them.

### 3.3 Cloud + local
- `assets/data/exercise_library.json` (Hive seed) and cloud `exercise_library` table carry the same rows and columns; seed version bump forces a local re-seed. Both change in the same release (the AI coach reads the cloud copy).
- **Aliases:** a merged exercise's old name goes into the kept row's `name_aliases`, which search and the exact-name lookup read, and its id into `merged_ids`, which the seed prunes from Hive. In cloud the retired row stays with `is_active = false`.

### 3.4 Current numbers (2026-10-21)
1,064 rows (292 library + 759 from the GIF set + 13 new without art): 927 kept, 137 discarded. The 927 kept include 219 of the 292 library rows. Core lists: beginner 129, intermediate 138, advanced 99 (210 unique rows). 845 kept rows have an animation; 82 do not (40 of those are core rows).

## 4. Generator selection

### 4.1 Pool
For a slot (pattern + target muscle) the candidate pool is: rows whose `core_levels` contains the user's **effective level**, `discipline` ∉ {calisthenics_skill, olympic}, equipment the user can perform (`EquipmentCapability.canPerform`, fail-closed), no injury contraindication, minus exclusions. Existing ordering (compound-first, `priority_tier`, foundational) and variety levers (previous-phase avoid, plateau rotation, L6 demote-swap) keep working on this pool. Phase 1 stays free and foundational-only.

### 4.2 Empty slot (within the same level only — D6)
1. Non-core rows of the **same `variant_family`** whose `suitable_for` includes the level and whose equipment the user has.
2. Otherwise the slot is **dropped** and the session is shorter. Never a lower level's core pick.

### 4.3 Assumed setups
| Level | Assumed setup | Coverage (founder-approved core lists) |
|---|---|---|
| Beginner | any: none / home DB+bands / gym | every pattern covered in every setup (pike push-up closes the last gap) |
| Intermediate, Advanced | standard gym | every pattern covered; home gaps accepted (D6) |

## 5. Session size (new rule)

Today: 8 exercises/day fixed; phase 4 for the founder = 32–46 working sets/session (6 days, 90 min).
**Proposed rule** (calibrated in Batch B's plan, evidence-based):
- **Per muscle per week:** 10–20 hard sets for hypertrophy goals (Schoenfeld, Ogborn & Krieger 2017 dose-response meta-analysis), fewer for beginners.
- **Per muscle per session:** cap around 8–10 hard sets; benefit per session plateaus beyond roughly that range (Pelland et al. 2024 meta-regression, preprint).
- **Per session:** the set budget comes from the user's minutes: ≈ (minutes − warm-up − cool-down) ÷ (average set time + rest). Exercises are added until the budget is spent, not to a fixed count.
- Customs never count (D8).

## 6. Equipment UX
- **Setup question** keeps today's tiers; a short **gym-extras checklist** (6–8 items: hack squat, T-bar row, hip abduction/adduction, preacher bench, back-extension bench, landmine/trap bar, kettlebells, cable crossover) adds well-equipped items. Specialty kit appears only if ticked.
- **"Not at my gym"** on any exercise → offer the same `variant_family` members the user can do; choice **this session** or **permanently** (permanent = add the item to exclusions).
- **Nudge** (no-equipment users): one card recommending a resistance band and a doorway pull-up bar, with what each unlocks.

## 7. Animation delivery (D9, D10)
- Files: 720 px Wardroom WebPs (~400 KB each, ~365 MB total) in a **public Supabase Storage bucket**, served via CDN, name versioned (`<slug>_v<n>.webp`).
- App: at plan build, prefetch the plan's exercises **once** (Wi-Fi), keep them in an on-device cache with a size cap (LRU eviction); new phases download only new exercises; swaps fetch on first open. Web uses the browser cache with long cache headers.
- Offline / not yet downloaded → today's still plate, else monogram. A workout never waits on a download.
- Provenance column per file (D9).
- Cost: storage fits Free (1 GB); downloads ≈ 16–28 MB per user per new phase at 720 px → Free's ~10 GB/month covers a few hundred active users; Pro (250 + 250 GB) covers tens of thousands. Pro before launch (D10).

## 8. Phase 2 calisthenics track (data now, UI later)
Skill rows carry `skill_track`/`skill_step`/`regression_to`/`progression_to` (planche, front lever, back lever, handstand, HSPU, muscle-up, L-sit, pistol, nordic, one-arm push/pull, human flag, iron cross). Not used by the generator until a separate Phase 2 design.

## 9. Delivery batches

| # | Batch | Content | Notes |
|---|---|---|---|
| 0 | Stop auto-adding customs | Remove L2; one-time repair of planned days; regression test | **SHIPPED** 10-21: PR #138 `c54e63ba`, PR #141 `fcbe6840` |
| A | Library data repair | Un-shift the 136 coaching-text rows (corrects OI-149: the text is recoverable, only `pro_tip` was lost) and store cues as real lists; retire 7 duplicate rows into their twins with aliases; fix the E172/E163 "Lats" label typos; flip 19 founder-flagged start/end pictures; remove 2 wrong drawings | Fixes a live user-visible bug |
| M | Media | Upload 720 px set + provenance, `media_slug`, cache/prefetch/fallback in app; **create animations for the 40 core rows that have none** (34 plates / 6 monograms until then — Q3) | Needs Pro before launch |
| B | Schema + generator | New fields + vocab tokens, core-list pool, within-family fill, discipline exclusion, session-size budget; `target_focus` for the 6 invisible bodyweight rows (E272 E273 E276 E277 E289 E290); universal-pool and warmup/cooldown names repointed to kept rows; E261/E274 (one movement) resolved; the exercise_type `calisthenics` and sub-focus string gaps (OIs filed 2026-10-22) | Ship-dark behind a flag (§4.6); ×2 review again on flip |
| C | New rows | ~760 rows (data + animations) incl. coaching-text quality pass on core rows; remove the 66 remaining discarded library rows (incl. E075, E261), then relabel E274 `target_focus` → Mid Back | Cloud + local same release |
| D | UX | Gym-extras checklist, "Not at my gym" swap, band/pull-up-bar nudge | Wardroom copy |

Each batch: plan → two context-blind reviews → worktree → tests (mutation-proven) → B-pass → PR → founder device check.

## 10. Open questions
1. ~~§4.2 step 1~~ **LOCKED 10-21: confirmed** — same-level, same-family non-core fill, else drop. Measured: only 2 gaps with the approved core lists (beginner no-equipment vertical push, advanced hip isolation); the fill covers both.
2. ~~§5 numbers~~ **LOCKED 10-21: set budget confirmed** — 10–20 hard sets per muscle per week, ≤8–10 per muscle per workout, total sized to the minutes (90 min ≈ 27–33 working sets); exact numbers calibrated per level/goal in Batch B's plan.
3. ~~40 core rows with no animation~~ **LOCKED 10-21:** ship with what exists (34 still plates, 6 monograms); animations for these 40 are created later — a named item in Batch M (not an intention).
