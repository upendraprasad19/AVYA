---
scope: onboarding
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Onboarding — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/onboarding/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/features/onboarding/` owns the stepped onboarding funnel (6 screens) +
the legacy chat fallback (`/onboarding/chat`, retained for rollback). The
final tap on Plan screen calls `OnboardingNotifier.completeOnboarding()` which
writes the consolidated profile map to `userBox['profile']`, stamps
`onboarding_completed_at`, and fires the initial sync fan-out.

Screens: `welcome_screen.dart`, `mission_brief_screen.dart`, `identity_screen.dart`,
`goal_screen.dart`, `stats_screen.dart`, `details_screen.dart`, `plan_screen.dart`,
`onboarding_chat_screen.dart` (legacy).

State is passed between screens via `GoRouter` `state.extra` (a
`Map<String, dynamic>`) — **no premature provider commits**. The notifier
runs once, on the final tap. Each screen spreads `...widget.initial` into
its outgoing extras so every field captured upstream survives to Plan.

## Single-source-of-truth contracts

| Concept | Writer | Reader |
|---|---|---|
| `onboarding_completed_at` | `OnboardingNotifier.completeOnboarding` stamps both Hive `userBox['profile']['onboarding_completed_at']` AND fires sync to `user_profile.onboarding_completed_at` cloud column | `restoring_screen.dart` post-auth classification via `AuthSessionBootstrapper.resolveDestination`. NULL + populated Hive profile → Plan A self-heal. |
| `user_full_name` | `identity_screen.dart` input → `OnboardingNotifier.completeOnboarding` → `users.full_name` cloud column (NOT user_profile) + `userBox['profile']['full_name']` | profile header, every screen that greets the user by name. |
| `muster_to_profile_bridge` | Q3..Q5 muster-style answers → profile fields. APK Test #15.4 / B2 dropped Q1+Q2, made Q5 single-select. Migration 063 + bridge + backfill. | profile screen. |
| Plan-screen preview targets | `plan_screen._computeTargets` calls canonical `BmrCalculator.calculateTargets` with every real input (weight, height, DOB-derived age, sex, activity_level, goal, pace_preference, target_weight_kg, body_fat_pct). Returns `targets.dailyCalories` + `targets.proteinGrams` verbatim. | What `completeOnboarding` writes to the profile — **no drift** between preview and saved profile (APK Test #1 fix). |
| Body-fat calc input (Unit 4, c3f2d8) | BOTH `_computeTargets` (preview) AND `completeOnboarding` (commit) route body-fat through the SINGLE shared `BmrCalculator.bodyFatForCalc(bf, disabled:)` selector → Katch-McArdle when provided, Mifflin when null/disabled. Parity by construction (no per-site ternary). Kill-switch `disable_bodyfat_calc`. A skip SAVES null (never a fabricated 18.0/0.0). | `profile_provider.recalculateTargets` consumes `body_fat_percent` via Katch on every profile edit; `body_stats.dart` displays it (null → "—"). SoT concept `onboarding_bodyfat_calc_input`; heal in `lib/core/services/CLAUDE.md` (BodyFatDefaultHealer). |

## Stepped flow (default since PR Y–AB, expanded over PR AI 2026-04-20, APK Test #1 2026-04-24, APK Test #2 2026-04-25)

**Current default flow for NEW users (6 screens — Mission Brief inserted between sign-up and Identity in APK Test #2):**

```
Welcome       (/onboarding)            → sets no state, just CTA           (unnumbered)
   ↓ [BEGIN ENLISTMENT]
[sign-up via email/Google/phone]
   ↓
[/restoring]                            → branded gate; awaits user_profile lookup
                                          + restoreFromCloud() in parallel
   ↓ (no row in user_profile → new user)
Mission Brief (/onboarding/mission-brief) → founder photo + locked copy +
                                            subtle Instagram link;
                                            CONTINUE → Identity            (step 00)
   ↓
Identity      (/onboarding/identity)   → full_name, date_of_birth, sex     (01 · 05)
   ↓
Goal          (/onboarding/goal)       → primary_goal                      (02 · 05)
   ↓
Stats         (/onboarding/stats)      → current_weight_kg, target_weight_kg,
                                         height_cm, body_fat_pct,
                                         activity_level                    (03 · 05)
   ↓
Details       (/onboarding/details)    → fitness_experience, pace_preference,
                                         days_per_week, equipment_access   (04 · 05)
   ↓
Plan          (/onboarding/plan)       → "REPORT FOR DUTY" — commits via
                                         OnboardingNotifier.completeOnboarding()
                                                                            (05 · 05)
```

**Flow for RETURNING users (post-logout sign-in):**

```
[sign-in via email/Google/phone]
   ↓
[/restoring]                            → SELECT user_id, onboarding_completed_at
                                          FROM user_profile + restoreFromCloud()
   ↓
   ├─ row + onboarding_completed_at IS NOT NULL
   │   → await full restore → /home (15s timeout safety)
   │
   ├─ row + onboarding_completed_at IS NULL  (mid-onboarding abandonment)
   │   → cancel restore → resume at first missing step
   │       (Identity if name null → Goal if goal null → Stats → Details → Plan)
   │
   └─ no row (new user just signed up)
       → /onboarding/mission-brief
```

**RestoringScreen** (`lib/features/auth/screens/restoring_screen.dart`) is the post-auth gate added in APK Test #2 (Q1). It shows a branded "Pulling your dispatch. Stand by, soldier." screen with a pulsing AVYA seal + 3-dot animation. After 15 seconds without completion, a CONTINUE button lets the user escape to home (restore continues in background).

`SyncService.restoreFromCloud()` returns `RestoreResult { succeeded, cancelled, error }` and supports `cancelInflightRestore()` so the RestoringScreen can abandon when the user is determined to be new (no `user_profile` row).

- **State passing:** `GoRouter` `state.extra` (a `Map<String, dynamic>`) between screens —
  **no premature provider commits.** The notifier only runs once, on the final tap. Each
  screen spreads the incoming extras (`...widget.initial`) into its outgoing extras so
  every field captured upstream survives to Plan.
- **Sex moved from Stats to Identity.** Stats no longer shows the 3-pill sex selector.
- **Age dropped entirely.** `date_of_birth` (captured on Identity via date picker, min age
  13) is the canonical field. `plan_screen` computes `age` on the fly for `BmrCalculator`;
  `age` is never stored to Hive or Supabase.
- **Fields still defaulted by the stepped flow** (user can edit via Profile → Edit Profile):
  - `lifestyle_activity` — inferred from `activity_level` (1:1 mapping).
  - `diet_preference` — defaults to `'veg'` (Indian-first default).
  - `injuries` — defaults to `['none']` (matches `edit_profile_screen` convention).
  - `start_date` — hardcoded to `'this_monday'`.
  - `city` — optional, not collected during onboarding.
  These four **are now persisted** to Hive by `completeOnboarding` (pre-2026-04-24 bug: they
  were set via `setAnswer` in plan_screen but never copied into the final profile map → home
  completeness nudge falsely flagged "Injuries" for every new user).
- **Legacy chat fallback:** the pre-PR-Y chat-based flow is still reachable at
  `/onboarding/chat` (`onboarding_chat_screen.dart`). Retained for rollback only.
- **Auth redirect gotcha:** `GoRouter._authRedirect` uses
  `location.startsWith('/onboarding')` (NOT `location == '/onboarding'`), so taps on
  `/onboarding/identity` / `/goal` / `/stats` / `/details` / `/plan` aren't bounced back to
  Welcome. This was the nav bug fixed in commit `17faa86`.
- **Inference fallback:** `plan_screen._onReportForDuty` keeps the old switch-expression
  inference rules as fallback for fields missing from `widget.data` (legacy chat users,
  deep-links, corrupted route extras). Fallback must never become the default path. The
  DOB path falls back to `DateTime(now.year - age, ...)` when `date_of_birth` is missing
  and `age` happens to be present — only legacy chat users hit this.
- **Plan-screen preview uses canonical `BmrCalculator.calculateTargets`** (APK-test-1-batch,
  2026-04-24). `_computeTargets` in `plan_screen.dart` passes every real input from
  `widget.data` (weight, height, DOB-derived age, sex, activity_level, goal, pace_preference,
  target_weight_kg, body_fat_pct) and returns `targets.dailyCalories` + `targets.proteinGrams`
  verbatim. Weight delta is `target - current` rounded, with `HOLD` when abs(diff) < 0.5. The
  preview numbers now exactly match what `completeOnboarding` will write to the profile — no
  "plan screen shows X, saved profile gets Y" drift. Pre-2026-04-24 this used a reduced
  goal-only formula (`weight × 32 + 250` for build_muscle, `weight × 2` for protein) that
  ignored half the inputs.
- **Body fat is optional, and now ACTUALLY feeds the calc** (APK-test-1-batch; Unit 4
  c3f2d8 2026-06-14). `stats_screen.dart` controller seeds to `''`, label `BODY FAT % · OPT`,
  em-dash ghost when empty. **When PROVIDED**, body-fat now flows into the SAVED calc
  (Katch-McArdle, lean-mass based) via the shared `BmrCalculator.bodyFatForCalc` selector —
  pre-Unit-4 both the preview and the commit silently dropped it (always Mifflin). **When
  BLANK**, `stats_screen` forwards `null` (was a fabricated `?? 18.0`) and `completeOnboarding`
  parses with `_parseDoubleOrNull` → SAVES `null` (was 18.0, briefly 0.0): Mifflin-St Jeor +
  `body_stats` shows "—". The fabricated 18.0 was invisible at onboarding (its own calc ignored
  body-fat) but `profile_provider.recalculateTargets` consumed it via Katch on the FIRST profile
  edit → a made-up 18% recompute. `BodyFatDefaultHealer` (boot) clears legacy fabricated 18.0
  rows. The skip snackbar still reads "Skipping body fat — using weight + height. Scan later
  from Profile to refine." Kill-switches: `disable_bodyfat_calc` (calc), `disable_bodyfat_heal`
  (heal).
- **Details step CTA is `CONTINUE →`, not `CALIBRATE PLAN →`** (APK-test-1-batch). Pre-2026-
  04-24 the Stats → Details navigation button was labelled "CALIBRATE PLAN", misleading since
  plan calibration doesn't happen until REPORT FOR DUTY on step 05. Renamed to `CONTINUE →`;
  behavior unchanged.
- **Details screen is now ALL chip rows** (APK-test-2-batch / Q8, supersedes APK-test-1-batch
  fade-row layout). All 4 sections render as horizontal chip rows: Experience (3 chips:
  Beginner / Intermediate / Advanced), Pace (3 chips: Steady / Balanced / Aggressive),
  Days/Week (4 chips: 3 / 4 / 5 / 6), Equipment (2×2 grid: Bodyweight / Dumbbells / Basic Gym
  / Full Gym — labels too long for single row at 360 dp). Selected chip = gold-fill + black
  w700 + opacity 1.0. Unselected = transparent + textGhost border + textDim text + opacity
  0.55. Cross-fades 150 ms on tap. Description line below each row updates on selection.
  Defaults pre-selected (Intermediate / Balanced / 4 / Basic Gym) so CONTINUE always works.
  The previous APK-test-1 `_FadeRow`/`_ChipRow` widgets
  live in `details_screen.dart` (not Wardroom primitives) — if reused elsewhere, promote to
  `lib/shared/widgets/wardroom/`.
- **Identity screen name field auto-focuses with inline validation** (APK-test-1-batch).
  `autofocus: true` pops the keyboard immediately, `textCapitalization.words` title-cases as
  you type, `_nameError` state + `_nameAllowed` regex (letters/spaces/`.-'`) enforce min 2 /
  max 40 chars on CONTINUE tap. Error clears automatically when the user resumes typing.
  DOB still uses a snackbar for missing-field feedback (no inline error surface on the date
  tile).

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Stepped onboarding bounces back to Welcome on every tap | `GoRouter._authRedirect`'s `isOnOnboarding` check MUST use `location.startsWith('/onboarding')`, not `location == '/onboarding'`. Sub-routes (`/goal`, `/stats`, `/plan`) would otherwise be redirected back to Welcome on every navigation. Fixed in commit `17faa86`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

- `test/contracts/onboarding_completed_at_writer_to_reader_test.dart`
- `test/contracts/auth_session_bootstrapper_test.dart` — pure-logic destination table.
- `test/contracts/muster_to_profile_bridge_test.dart`
- `test/contracts/full_name_backfill_test.dart`
- `test/contracts/plan_screen_targets_match_completeOnboarding_test.dart`

## See also

- `lib/features/auth/CLAUDE.md` — post-auth `RestoringScreen` decision tree.
- `lib/features/profile/CLAUDE.md` — Edit Profile reuses the same field map.
- `lib/shared/repositories/plan_engine/CLAUDE.md` — Plan tap triggers initial plan generation.
- `docs/architecture/sync.md` — onboarding sync fan-out + restore-completeness.
