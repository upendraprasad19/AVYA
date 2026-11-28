---
branch: workout-equipment-filter
scope: ⑥ slice B1 — equipment item-level exclusion filter (pure-exclusion, ship-dark, platform)
blast_radius: platform
reviewer: context-blind adversarial B-pass (self-initiated, §4.3)
verdict: accepted
---

# B-pass — ⑥ slice B1 equipment item-level exclusion filter

Context-blind adversarial review of the staged diff (16 files, platform tier). Every load-bearing claim
verified against the actual code + the live library asset; the reviewer RAN the tests + `flutter analyze`.
**No P0/P1 defects.**

## Verified-clean
- **Ship-dark no-op is BYTE-IDENTICAL (the key claim) — confirmed empirically.** The behavioral test passes:
  flag-OFF+exclusions and flag-ON+empty both `== baseline` via `jsonEncode(Phase.toMap())` (deep serialization
  incl. `equipment_needed`). Determinism holds (no `Random` in the pick path; progression/`DateTime.now` are
  phase≥2-only; the no-op test is phase 1). Every new guard is `if (exclusions.isNotEmpty)`.
- **Doubly-inert:** no `lib/` caller passes `equipmentExclusions:` yet (the profile-read is slice C), so
  flipping the flag ON alone does nothing until C wires it — a safe rollout.
- **queryV4 drop** placed BEFORE the no-tier `return true` short-circuit; predicate is crash-safe
  (`EquipmentVocab.fromProfile`, no `as List`) + normalizing; `exclusions` is a REQUIRED param; all 5 call
  sites pass it (compile-enforced).
- **att4 keeps exclusions; att5 skip** mirrors the U2 injury skip (order-invariant). The floor never empties a
  slot — the scorecard gate passes **7/7**, incl. the HARD `missing==0` over the 9 exclusion personas.
- **L2/L6** threaded + guarded; **floorSanitizedExclusions** strips none/bodyweight so the floor is never
  excludable; **mirror + cascade_tracer** carry the same drop; baseline regen is a clean append (non-exclusion
  rows byte-identical — the display re-normalization is slice-A's committed library catching up in the
  renderer, NOT a B1 selection change).
- **Flag-ON real user:** exclude-cables → no cables pick; exclude-everything → valid bodyweight plan, zero
  excluded tokens; community bare-String row excluded without crashing (e9d1c7 class).
- **Process:** `feat` → no diagnose-doc required; SoT `equipment_exclusion_filter` + `behavioral_test_path`
  present; `flutter analyze` on all changed files: No issues.

## P2 (nits) — all 3 actionable ones FIXED in this batch (§4.2 no-deferrals)
- **P2-1 att5 floor SPOF** (vertical_pull + elbow_flexion survive only via Inverted Row; the "≥1 bodyweight per
  pattern" guarantee is a pool-data property, not floor-sanitize) → **added a guard test** pinning "every
  universalPoolV4 pattern retains a bodyweight survivor" (red-flags a retag/removal).
- **P2-2 stale line numbers** (SoT/CLAUDE.md cited :268/:272/:90) → **corrected** to the actual :282/:288/:291/:92.
- **P2-3 phase≥2 no-op not behaviorally pinned** → the L2/L6 inertness uses the same `.isNotEmpty` guard
  (trivially guard-covered + B-pass-confirmed); a phase≥2 byte-identical harness needs the full history/customBox
  stack for no added coverage of the guard — **documented in the test** rather than over-built.
- P2-4 (att5 placeholder branch) — bodyweight-by-design (placeholders are never excluded); no change.
- P2-5 (baseline display re-normalization) — benign slice-A catch-up; no change.

## Verdict: accepted
The pure-exclusion design is correct: the no-op is empirically byte-identical, the filter reaches all four pick
paths crash-safely, the att5 floor holds (scorecard 7/7 + a new guard test), the mirror mirrors prod, and the
ship-dark posture is doubly-inert. No P0/P1.
