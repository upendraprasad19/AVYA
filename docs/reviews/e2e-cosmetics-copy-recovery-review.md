---
reviewed_at: 2026-06-25T22:40:00+05:30
staged_against: 66143a4 (Unit C shipped) + the 2026-06-25 completeness recovery
blast_radius: account
reviewer: claude-sonnet-bpass + 4-lens-opus-hermes
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, unicode_i18n, ui_render_safety, state_side_effects]
findings_count: 3
verdict: accepted
---

# Code review — fix-e2e-cosmetics-copy (Unit C) + completeness recovery

Consolidated from a fresh context-blind Sonnet B-pass (5 lenses) + a 4-lens Opus
Hermes pass on `66143a4` and the fields it touched. All findings resolved in the
fix-forward recovery commit.

## Finding 1 — P1 — writer_reader_drift (OBS-11 sibling, Unit B miss) — ACCEPTED → FIXED
- **file:line:** `lib/shared/repositories/user_repository.dart:217` (`ensureComputedTargets` gate) → `:265` write-back; sink `lib/core/utils/bmr_calculator.dart:314` `toMap`.
- **claim:** the all-four "already has computed targets" check reads `profile['carb_grams']` SINGULAR only. A restored profile carries only the plural cloud `carbs_grams` → the check false-negatives → recompute branch calls `updateProfileFields(targets.toMap())`, **writing drifted targets back over the canonical** (a write-back — worse than OBS-11's read-time drift). Dead code today (no `lib/` caller) so latent, but exactly the OBS-11 class.
- **verification:** `sed -n '215,219p;265p' lib/shared/repositories/user_repository.dart`; `sed -n '309,316p' lib/core/utils/bmr_calculator.dart` (toMap had no plural).
- **fix:** `(profile['carb_grams'] ?? profile['carbs_grams']) != null` at :217; `toMap` now emits BOTH spellings. Pinned: `nutrition_target_carb_dualname_test.dart` (+2).

## Finding 2 — P2 — writer_reader_drift (OBS-13 sibling, Unit C miss) — ACCEPTED → FIXED
- **file:line:** `lib/features/profile/screens/edit_profile_screen.dart:1595`.
- **claim:** the Edit Profile save writes `'full_name': name` RAW — the 2nd writer of the `user_full_name` SoT. On web (`textCapitalization.words` inert) a lowercase edit re-saves un-title-cased casing, re-greeting "Recruit test"; the H-3 self-heal then propagates the raw value to cloud `users.full_name`. Only the onboarding writer was fixed in `66143a4`.
- **verification:** `grep -n "full_name" lib/features/profile/screens/edit_profile_screen.dart` (only :1595, no `titleCaseName`).
- **fix:** `'full_name': titleCaseName(name)` + import. Pinned: `title_case_name_test.dart` (+2, both writers).

## Finding 3 — (was P2) — titleCaseName surrogate-pair corruption — REFUTED (FALSE_ALARM)
- The B-pass hypothesised `titleCaseName` corrupts emoji/non-BMP leading chars (UTF-16 `String[0]`/`substring`). The Hermes Unicode lens EMPIRICALLY refuted it: Dart `'\u{1F600}aa'[0]` → lone high surrogate, `.toUpperCase()` no-op, `substring(1)` → low surrogate, concat re-joins LOSSLESSLY. Also `'ß'.toUpperCase()=='ß'` (no SS blow-up). No corruption, no hardening. (Onboarding's `_nameAllowed` regex rejects emoji at input anyway.)

## Clean (verified by the render-safety + state lenses)
- All 4 UI fixes provably correct: `flush_card` border/radius across `first/middle/last/only`
  cannot trip the uniform-border assert; `today_workout_card` Spacer→SizedBox has no
  unbounded/zero-width/overflow risk; `journey_timeline` + `subscription_section` copy null-safe.
- No casing-as-key/dedup/lookup use of `full_name`; `titleCaseName` is idempotent; self-heal
  comparison stays safe; greeting providers refresh; no new `unawaited`/silent-catch; no secrets.

## Verdict
**accepted** — 2 real findings fixed (1 P1, 1 P2), 1 false-alarm refuted, UI clean. Plus the
`blast_radius_from_diff` positional-ref guard (the tooling cause of the original tier miss).
