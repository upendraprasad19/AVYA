# Batch 1 (rest) — Injuries / Safety (focused implementation plan)

**Parent:** `~/.claude/plans/ok-lock-1a-and-atomic-balloon.md` (item ① + WU-1 + the Batch-0
universal-pool finding). **Branch/worktree:** `injuries-safety`. **Tier: platform** (touches
`lib/shared/repositories/plan_engine/**` — exercise_selector + warmup_cooldown). Requires:
regression_test + behavioral_test + code_review_b_pass + **feature_flag** (kill-switch) + a
`docs/plan-reviews/injuries-safety.md` converged record before merge.

**Theme:** make the injury-safety promise REAL end-to-end. Today it is theater: the UI collects
`back` but the library uses `lower_back` (0 exclusions), and even when injuries ARE excluded the
universal-pool fallback re-introduces contraindicated moves. This is the recurring writer/reader
drift class — every change below NAMES its writer + reader.

## Ground-truth (verified across the overhaul's 5 review rounds + Batch-0 harness)
- Live injury match: `exercise_repository.dart:290` (queryV4, exact lowercase equality of the
  user's injury token vs each exercise's `injury_contraindications` token).
- UI chips: `edit_profile_screen.dart:1207` = `{none,knee,back,shoulder,hip,wrist,ankle}`; saved
  `'injuries': _injuries` (~:1612). Library tokens (canonical): `lower_back`(26), `knee`(30),
  `shoulder`, `wrist`, `elbow`(12), `hip`, `ankle`, `neck`(1), `hamstring`(2).
- Onboarding never collects injuries — `plan_screen.dart:525` hardcodes `['none']`.
- **Batch-0 finding (NEW):** the cascade attempt-5 universal pool (`exercise_selector.dart`
  const `universalPoolV4` lines **495-507** + the fill at ~:828-836 via `repo.search(name)` /
  `_buildUniversalFallback`) is hardcoded and NOT injury-filtered → 2 unsafe plans in the matrix
  (e.g. "Pike Push Up" for a shoulder injury — it's in both vertical_push + shoulder_isolation
  pools). Attempts 1-4 (selector :782/:798/:810/:820) DO injury-filter via
  `queryV4(injuryExclusions:)`; only the pool fill bypasses it. (The injury filter at selector
  :464-478 is the LEGACY V3 `_selectForSpecs` path — not the live V4 pool fill.)
- Warmup/cooldown (`warmup_cooldown.dart`) are hardcoded per-dayType name lists, NOT injury-filtered.

## Units (each: writer → reader named; behavioral test; smallest-converged-first order)

### U1 — Injury vocabulary fix (writer/reader drift) [account-ish, but bundled]
- **Writer:** `edit_profile_screen.dart:1207` chip options. Rename stored `back`→`lower_back`;
  add `elbow`, `neck`, `hamstring`. Display labels human ("Lower Back", "Elbow", "Neck",
  "Hamstring"); STORED values = library tokens. ⚠ GT-review: TWO save points in this flow —
  `:1612` AND `:1682` (`injuries: _injuries`) — U1 touches both.
- **Reader:** `exercise_repository.dart:290` (queryV4 exact-match, reached live via
  generateV4→pickV4→_fillSlots→_cascadeFill→queryV4). No reader change — the fix aligns the
  writer's vocabulary to what the reader already matches.
- **Test:** `test/contracts/` — assert the chip-token set ⊆ the library `injury_contraindications`
  token set (pins the vocabulary so it can't drift again); behavioral: a `lower_back` plan excludes
  the **24** lower_back-contraindicated exercises (⚠ GT-review corrected: 24, NOT 26 — 26 is `hip`).
- Migration-safe: existing profiles storing `back` (local Hive + synced cloud `injuries` text[]) —
  reuse the `body_fat_default_healer.dart` boot-healer pattern (idempotent, kill-switched, wired in
  `auth_provider._ensureLocalUser` after the cross-account guard, clears cloud-then-local) for a
  `back`→`lower_back` normalizer. Read-side alias at :290 is the fallback. DECIDE in design review
  (leaning boot normalizer, per GT-review's confirmed reusable pattern).

### U2 — Universal-pool injury filter (the Batch-0 safety hole) [platform, HIGHEST safety value]
- **Writer/site:** `exercise_selector.dart` attempt-5 universal-pool fill. When picking from the
  hardcoded pool, SKIP any exercise whose library `injury_contraindications` ∩ user injuries ≠ ∅
  (look up the library record by name — the pool is names). If the pool empties for the pattern,
  leave the slot to the existing (none)/placeholder path rather than prescribe a contraindicated move.
- **Reader:** the generated plan (safety). **Measured by the Batch-0 gate: unsafe 2 → 0.**
- **Test:** behavioral — injury persona whose slot falls to the universal pool gets 0 contraindicated
  picks; + re-run `dart run test/plan_generator/generate_baseline.dart` → unsafe_plan_count 0, then
  the gate's no-regression holds.
- Kill-switch `configBox['disable_injury_universal_filter']`.

### U3 — Warmup/cooldown injury filter (WU-1) [platform]
- **Writer/site:** `warmup_cooldown.dart` `_dynamicWarmup` (:15-40) + `_cooldownStretches` (:43-50).
  ⚠ GT-review: `attach()` (:53-113) does NOT currently accept an `injuries` param → U3 needs a
  SIGNATURE change (add injuries) + thread it from `generateV4`'s WarmupCooldownSelector.attach
  call. Add a curated move→injury-token map + filter/substitute the offending move (uses the SAME
  normalized vocab as U1). Warmup IS per-dayType (verified) so a push-day warmup is shoulder-prep →
  a shoulder-injured user needs the swap. (Design review to decide: substitute vs simply DROP the
  offending move — avoid asserting a medical "this is safe" claim; see design-review finding.)
- **Test:** behavioral — shoulder injury → 0 shoulder-loading warmup/cooldown moves.
- Kill-switch shared with U2 (`disable_injury_universal_filter` or a sibling).

### U4 — Thread injuries to the write paths that drop them [account]
- **Writers (each reads `profile['injuries']` filtered `!= 'none'`, passes to the service that
  already ACCEPTS injuries):** `onboarding_provider.dart:453`, `train_provider.dart:466`,
  `edit_profile_screen.dart:1795`, `graduation_screen.dart:588`, `auth_session_bootstrapper.dart:379`.
  (Coach regen/hotel injury threading: DECIDE in review whether to include — cheap, but re-touches
  the just-merged coach files; leaning include for a complete injury-safe promise. Also
  `simulation_service.dart:161` is a 6th caller that drops injuries — dev-only sim harness; thread
  for parity or note as intentionally-out-of-scope, per GT-review.)
- **Reader:** `PlanGenerator.generateV4(injuries:)` → the cascade. Normalize (strip literal `none`).
- **Test:** behavioral — a knee-injury profile → onboarding/train/edit-profile generated plan has 0
  knee-contraindicated exercises across all 4 weeks (per write path).

### U5 — Onboarding injuries collection + read-side + nudge [account]
- **Writer:** new injuries chip row on `details_screen.dart` (reuse edit-profile's multi-select
  widget), pre-selected "None". **Read-side fix:** `plan_screen.dart:525` must read the chip's
  selection from the onboarding extras, NOT hardcode `['none']`.
- **Nudge:** `profile_completeness_provider.dart:55-65` currently treats any non-empty list
  (incl. silent `['none']`) as filled — can't tell "explicitly none" from "never asked". With U5
  onboarding now ASKS, so `['none']` is a real answer; but a blow-through user still has `['none']`.
  DECIDE in review: add an `injuries_answered` marker OR accept pre-selected-None as answered.
- **Test:** onboarding→profile round-trip; nudge no longer flags a user who explicitly chose None.

## Sequencing (smallest-converged-first, each its own commit; one branch)
U1 (vocab) → U2 (universal-pool, the safety hole) → U3 (warmup) → U4 (threading) → U5 (onboarding).
Re-run the Batch-0 gate after U2/U3 (safety must improve, no regression). One kill-switch family.

## ⚑ HARDENED after ×2 review (2026-07-12) — SPLIT + 6 resolutions (SUPERSEDES the units above)

The ground-truth + design ×2 review found 6 material issues → §4.12 SPLIT. This section is the
converged design. Three ships on this branch (each own commit; Ship 1 is the first to implement).

### SHIP 1 — "injuries actually filter safely" (U1 + U2 + U4 — inseparable) [platform]
The user-facing safety win; U2 is inert without U1+U4 (verified: injuries never reach the cascade
today due to the vocab bug + threading gap).

- **Shared helper `InjuryVocab` (new, `lib/shared/repositories/plan_engine/` or core):**
  `canonicalTokens` (the 9: ankle/elbow/hamstring/hip/knee/lower_back/neck/shoulder/wrist) +
  `normalize(List<String>) → List<String>` that maps `back`→`lower_back`, lowercases, trims,
  splits free-text on spaces/commas to canonical tokens, drops `none`/unmappable. **Read-side
  alias, NOT a boot normalizer** (review #5: normalizer is restore-fragile + incomplete; alias
  covers local+restored+muster uniformly, no cloud migration).
- **U1 vocab (writers→reader):** `edit_profile_screen.dart:1207` chips → rename `back`→`lower_back`,
  add elbow/neck/hamstring (both save points :1612 + :1682). Apply `InjuryVocab.normalize` at the
  chip SELECTED-STATE reader too (else a legacy stored `back` renders de-selected + is dropped on
  save — review #5). **PLUS the missed writer (review #2):** `muster_screen.dart:96` +
  `induction_service.dart:93/:170` write free-text injuries → normalize before they land in
  `profile['injuries']` (or route unmappable free-text to a coach-only field, never the engine's
  injuries). Reader unchanged: `exercise_repository.dart:290`. Behavioral test: `lower_back` plan
  excludes the **24** lower_back-contra exercises; muster "lower back" → `lower_back` → excluded.
- **U2 universal-pool filter + GATE SEMANTICS (review #1, the blocker):** in
  `exercise_selector.dart` attempt-5 fill (~:828-836), skip a pool pick whose library record's
  `injury_contraindications` ∩ user injuries ≠ ∅ (use the `contra is List && isNotEmpty` guard,
  injury-check the ACTUAL `repo.search(name).first` record, dedup via pickedNames — review #9).
  **Resolve the (none)-collapse (review #1):** (a) add a curated per-pattern ALWAYS-SAFE fallback
  where one genuinely exists (e.g. core→Plank/Dead Bug are contra-free); (b) for pattern×injury
  pairs where NONE exists (vertical_push for shoulder/wrist), emit a NEW distinct source
  `safelyOmitted` (NOT `(none)`); (c) **update the Batch-0 harness in lockstep** —
  `cascade_tracer.dart:191-221` mirror must injury-filter its pool too, and
  `scorecard_gate_test.dart:70` must treat `safelyOmitted` as PASS (a safe intentional omission)
  while a real `(none)` stays a HARD failure. Also add a real per-day minimum-safe floor to
  `pickV4._fillSlots` (a null cascade currently silently drops the slot). Kill-switch
  `configBox['disable_injury_universal_filter']`, default filter-ON (the pure-Dart harness
  hardcodes ON — can't read configBox; state it). Measured: Batch-0 unsafe 2→0, missing stays 0
  (with `safelyOmitted` excluded from the missing tally).
- **U4 thread ALL generation entry points (review #3, no deferral):** onboarding_provider:453,
  train_provider:466, edit_profile:1795, graduation_screen:588, auth_session_bootstrapper:379,
  **coach regen (`regenerate_plan_planner.dart`) + hotel (`hotel_workout_planner.dart`)** — all
  read `profile['injuries']` → `InjuryVocab.normalize` → pass `injuries:` (the service methods +
  generate() already accept it). splash_screen:253-268 ALREADY threads (leave). sim_service:161
  (dev-only) threaded for parity. Terminal state for every path — no "decide later." Behavioral
  test per representative path: knee profile → 0 knee-contra exercises across 4 weeks.

### SHIP 2 — U3 warmup/cooldown injury safety (drop-not-substitute) [platform]
- `warmup_cooldown.dart` `attach()` gains an `injuries` param (signature change, threaded from the
  generateV4 call). **DROP the offending move** (shorter warmup) rather than substitute — a
  negative "don't load the injury" claim, not a positive medical "this swap is safe" claim
  (review #6, same concern that deferred R9). Hand-authored move→injury-token map (warmup moves
  aren't all library records). Own kill-switch + own behavioral test (shoulder → 0 shoulder-loading
  warmup moves). ⚠ The Batch-0 gate CANNOT prove U3 (warmup isn't in the scorecard's allExercises)
  — the behavioral test is the only proof (corrects the earlier "gate proves U3" claim).

### SHIP 3 — U5 onboarding injuries collection [account]
- Onboarding Details injuries chip — **explicit choice, NO pre-selected None** (review #7:
  pre-selected None silences the completeness nudge for the injured-but-silent user). A mandatory
  "No injuries" tap so `['none']` genuinely means "answered none" → the existing nudge logic
  (`profile_completeness_provider.dart:55-65`) stays correct with ZERO new state (no
  `injuries_answered` marker). Read-side fix `plan_screen.dart:525` reads the chip, not hardcoded
  `['none']`. `_buildInjuriesChips` is a private screen method → extract-or-duplicate, not import.

## Discipline
- [x] Own worktree (injuries-safety), own focused plan (this doc).
- [x] ×2 context-blind review of THIS plan BEFORE code (§4.12) — ground-truth + design; 6 material
  issues → SPLIT + hardened above. Record → `docs/plan-reviews/injuries-safety.md` (to write with
  the Ship-1 merge, verdict converged after this hardening).
- [ ] SHIP 1 first (U1+U2+U4). Kill-switch (§4.6); behavioral tests per unit; diagnose-docs for the
  vocab-drift bug + the universal-pool safety bug; Batch-0 gate re-run (unsafe 2→0) proves U2.
- [ ] Self-B-pass before each merge (§4.3). Commit/merge/push autonomously (auto mode). Ships 2+3 follow.
