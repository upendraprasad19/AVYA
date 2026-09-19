---
bug_id: e2a1f7
date: 2026-06-07
batch: psych-skill-and-audit-2026-06-07 (audit remediation — Batch 5, honest-surface integrity)
status: fixed
blast_radius: account
symptom: >
  Three user-facing surfaces showed fabricated or misleading content under an
  honesty-led brand. F10: the home AI-insight card rendered a CONST "QUICK WINS"
  macro rail beneath a live-AI "AI COACH · INSIGHTS" eyebrow + green dot, so a
  fixed reference list read as a per-user AI-derived "quick win". F21: the sign-in
  welcome showed "ENLISTED · 18,866 SAILORS ACTIVE" — a fabricated head-count for a
  pre-public-launch app with no such user base. F26: the today-workout card showed
  a static "~340 kcal" chip for EVERY workout (a fixed fake) and defaulted the day
  label to "PUSH DAY", mislabelling any workout whose name lacked a known keyword.
concept: honest_surface_integrity
sot_registry_entry: "n/a — render-only honesty fixes; no new writer/reader contract (psychology-pass ethical line: never fabricate progress / social-proof; ADR-0012 derive-only)"
writers:
  - "{ file: lib/features/home/widgets/ai_insight_card.dart, line: 84 } — F10 static cheat-sheet rail, relabelled honestly"
  - "{ file: lib/features/auth/screens/sign_in_screen.dart, line: 322 } — F21 belonging-cue Text, was a fabricated count"
  - "{ file: lib/features/train/widgets/today_workout_card.dart, line: 23 } — F26 dayType default + removed fake kcal chip"
readers:
  - "{ file: lib/features/home/widgets/ai_insight_card.dart, line: 45 } — renders the computed insight body the user sees"
  - "{ file: lib/features/train/widgets/today_workout_card.dart, line: 43 } — renders 'TODAY · dayType'"
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: n/a
cloud_columns: n/a
contract_test_path: test/contracts/audit_2026_06_07_batch5_regression_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: n/a
forbidden_patterns_checked: >
  fabricated head-count ("18,866"), static fake kcal ("340"), and the misleading
  "QUICK WINS" label are now asserted-absent by the Batch 5 regression guard
  (comments stripped); the honest replacements ("FOUNDING COHORT", "PROTEIN CHEAT
  SHEET", "TRAINING DAY") are asserted-present.
proposed_fix: >
  F10: relabel the static rail "QUICK WINS" to "PROTEIN CHEAT SHEET" (the macro
  values 3 eggs=18g etc. are accurate; only the AI-personalised IMPLICATION was
  false) + doc-comment the rail as a fixed, non-AI reference. F21: replace the
  invented count with "FOUNDING COHORT · ENLISTMENT OPEN" — true for an early-stage
  app, conferring honest belonging + honest scarcity without a fake number. F26:
  drop the static "~340 kcal" chip entirely + change the default dayType from
  "PUSH DAY" to the neutral "TRAINING DAY" (keyword overrides kept).
regression_test_planned: test/contracts/audit_2026_06_07_batch5_regression_test.dart group 'Honest surface — no fabricated/misleading UI (F10, F21, F26)' — GREEN (3 tests)
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: 3 surfaces relabelled/de-faked; analyze clean; regression guard green (3 tests) }"
  - "{ layer: client_server_contract, status: verified, evidence: no data contract touched — render-only strings; no writer/reader drift }"
impact_analysis: >
  An integrity-led brand (the "honest data" manifesto sits two lines above the F21
  cue) cannot show a single fabricated number without poisoning the whole halo
  (psychology-pass: a faked count breaks trust everywhere). F10/F26 likewise made
  the app look like it personalised / measured when it did not. All three are now
  honest; the regression guard prevents re-introduction.
closes-diagnose: e2a1f7
---

# Honest-surface integrity (F10 / F21 / F26)

Three render-only surfaces masqueraded as personalised, measured, or socially
proven when they were none of those things.

## Fixes
- **F10 — AI-insight "QUICK WINS" rail.** Relabelled the const macro rail to
  **"PROTEIN CHEAT SHEET"** and doc-commented it as a FIXED, non-AI reference. The
  card's *body* ("Xg of protein left") is genuinely computed; only the static
  rail's label implied per-user AI derivation.
- **F21 — fabricated sign-in head-count.** `"ENLISTED · 18,866 SAILORS ACTIVE"`
  → **"FOUNDING COHORT · ENLISTMENT OPEN"** — honest belonging + honest scarcity
  for a pre-launch app, no invented number.
- **F26 — today-workout fake kcal + PUSH-DAY default.** Removed the static
  `~340 kcal` chip (shown identically for every workout); default `dayType`
  `PUSH DAY` → **`TRAINING DAY`** (keyword overrides retained).

## Guard
`test/contracts/audit_2026_06_07_batch5_regression_test.dart` asserts the
fabricated strings are absent and the honest replacements present (comments
stripped).
