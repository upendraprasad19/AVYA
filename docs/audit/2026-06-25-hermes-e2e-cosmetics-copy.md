---
hermes_pass_id: 2026-06-25-hermes-e2e-cosmetics-copy
ran_at: 2026-06-25T22:35:00+05:30
batch_scope: 66143a4 (Unit C) + touched fields (full_name writers, carb-target readers)
lens_set: [field_drift_completeness, unicode_i18n, ui_render_safety, state_side_effects]
agents_dispatched: 4
findings_total: 3
findings_by_severity: { P0: 0, P1: 1, P2: 1, false_alarm: 1 }
verdict: accepted
---

# Hermes pass — fix-e2e-cosmetics-copy (Unit C completeness)

Triggered because the single Sonnet B-pass on a cosmetic+copy account-tier batch
found a real writer-drift miss (edit_profile) — the founder asked for a deep pass
to check whether the field sweeps were COMPLETE. Four fresh context-blind Opus
lenses on `66143a4` + the touched fields.

## Summary
- 1 P1, 1 P2, 1 false_alarm. 0 ship-blockers. All resolved in the fix-forward recovery.
- The deep pass paid off twice: it found a P1 the B-pass entirely missed AND refuted a
  B-pass false-alarm (saving a pointless "fix").

## Findings by lens

### L-field-drift-completeness — P1 (REAL) + P2 (REAL)
- **P1 — `user_repository.ensureComputedTargets:217` carb singular-only write-back.** The
  all-four "already has targets" gate checks `carb_grams` only; a restored profile (plural
  `carbs_grams`) fails it → recompute → `updateProfileFields(toMap())` overwrites the canonical
  targets. Same OBS-11 class, write-back severity; the Unit B sweep (`nutrition_provider` +
  `home_provider`) missed this third reader. Dead code today (no caller) → latent. **Fixed**
  (dual-name gate + `toMap` emits plural).
- **P2 — `edit_profile_screen.dart:1595` raw `full_name`.** 2nd writer of the SoT; OBS-13 fix
  covered only onboarding. **Fixed** (titleCaseName).
- Enumerated all 8 `full_name` writers + all carb readers; the rest are clean
  (propagate-stored / external-OAuth / plural-correct / a false-positive `_stepLabel` switch).

### L-unicode-i18n — false_alarm (REFUTED)
- The B-pass "surrogate-pair corruption" hypothesis is FALSE. Empirically: Dart `String[0]`
  returns one UTF-16 code unit; `'\uD83D'.toUpperCase()` is a no-op; `substring(1)` returns the
  low surrogate; concat re-joins losslessly. `'ß'.toUpperCase()=='ß'` (no SS expansion). No
  corruption stored to Hive/cloud. P3 cosmetic-only: a leading-punct word stays lowercase
  (`.bob`) — negligible, `_nameAllowed` guards onboarding input. **No hardening.**

### L-ui-render-safety — CLEAN
- `flush_card` BoxDecoration cannot trip the uniform-border assert in ANY position
  (`first/middle/last/only`): radius non-null ⟹ uniform `Border.all`; non-uniform `Border` ⟹
  null radius. `today_workout_card` Spacer→SizedBox is strictly safer (no unbounded/zero-width).
  `journey_timeline` + `subscription_section` copy null-safe + within the prior width envelope.
  (`_FlushPos.only` has no live call site — dead-but-correct, untested.)

### L-state-side-effects — CLEAN
- `full_name` is read for display only (no casing-as-key/dedup/lookup/equality). `titleCaseName`
  idempotent. The `auth_session_bootstrapper` self-heal comparison stays safe under title-casing
  (cannot newly equal the lowercase email prefix). Greeting providers `ref.watch` the auth token
  and re-read on the onboarding nav. No new fire-and-forget / silent catch.

## Action items
- [x] Fix P1 (`user_repository` + `bmr_calculator.toMap`).
- [x] Fix P2 (`edit_profile`).
- [x] No surrogate fix (refuted).
- [x] Tooling: `blast_radius_from_diff` positional-ref guard (root cause of the tier miss).
- [x] Tests: carb dual-name (+2), full_name 2nd-writer (+2), blast-radius guard (new).
