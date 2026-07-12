---
review: injuries-safety Ship 1 B-pass (U1 vocab + U2 universal-pool + U4 threading)
branch: injuries-safety
date: 2026-07-12
reviewer: context-blind adversarial subagent (B-pass, §4.3)
blast_radius: platform
verdict: accepted
diagnose: a1f6c3
---

# B-pass — injuries-safety Ship 1 (a1f6c3)

Context-blind adversarial review of the implemented diff (`git diff main -- lib
test`), verified against the actual code (not the diagnose prose) + a live test
run. Ground truth established: all named tests pass, `flutter analyze` clean on
the 5 changed engine files, and the baseline diff proves the fix is real (the two
`full_gym|4d|advanced|p1|inj:shoulder(+knee)` personas went `safety:0 /
"Pike Push Up contraindicated for shoulder"` → `safety:100 / violations:[]`).

## Verdict: ACCEPTED — no P0/P1 issues

Eight areas verified CONFIRMED-OK:
1. **`InjuryVocab.normalize` correctness** — no non-injury word maps to a token
   (unmapped fragments dropped); `\band\b` won't mis-split "hand"; vocab↔library
   equality pinned by the contract test.
2. **Central normalize covers ALL paths** — `pickV4` has exactly one caller
   (`generateV4`, which normalizes at the top); every generation route funnels
   through `generateV4`. No cascade bypass.
3. **7 threaded entry points + missed-path sweep** — all 7 confirmed threading a
   valid local `injuries` var; `splash`/`preview`/`sim` already wired (not
   double-counted); `redoWeek4` copies rows (no regeneration → no filter needed);
   no missed user-facing path.
4. **U2 filter correctness** — `_isContraindicated` exactly mirrors the queryV4
   match; safe-omission (`return null`) handled gracefully by `_fillSlots` (no
   crash, bounded loop); placeholder branch skips only when injured.
5. **Kill-switch fail-safe** — returns `true` on Hive absence; threaded to
   `pickV4` for BOTH slotsA/slotsB; coach + hotel read the same central flag.
6. **Harness fidelity** — tracer mirrors production attempt-5;
   `safelyOmitted` correctly PASS (excluded from missing/fallback/balance/realism).
7. **No regression to uninjured users** — `normalize([])`/`normalize(['none'])`
   → `[]`; behavior byte-identical to pre-fix for the 99% with no injuries.
8. **Field-drift / null-safety** — no new SoT gap.

## Two P2 (non-blocking) findings — FIXED IN THIS BATCH (not deferred, §4.2)

- **P2-a (`as List?` vs the batch's `is List` pattern):** the 5 new threading
  callsites read `(profile['injuries'] as List?)`, which `_CastError`s on a
  legacy non-null non-List (pre-migration-033) value. FIXED: added the crash-safe
  shared helper `InjuryVocab.fromProfile(raw)` (List/null/legacy-String → safe
  `List<String>`) and routed all 5 sites through it.
- **P2-b (harness exact-vs-substring enrichment nuance + untested production
  return-null):** `ExerciseRepository.search` is a pure SUBSTRING match with no
  exact-name priority, so a pool name like "Push Up" resolves `.first` to a
  superstring ("Pike Push Up") — the omit decision could inspect a different
  record than the scorecard's exact-name enrichment, and (latently) attempt-5
  could build the wrong pool exercise. FIXED: both production `_cascadeFill` and
  the tracer now resolve the EXACT-name record (falling back to `.first`), so the
  injury check + built exercise are the intended pool move and enrichment/
  decision agree by construction. Added `injury_safe_omission_production_test.dart`
  covering the real `pickV4 → _cascadeFill` return-null path (the behavioral test
  previously only exercised the partial-skip case). Matrix counts unchanged
  (fallback 1154, missing 0) — no baseline shift.

Post-fix: all injury tests green (vocab contract, 4 behavioral, 2 tracer
safe-omission, 3 production safe-omission), scorecard gate green (unsafe 0),
`flutter analyze` clean. No open issues.
