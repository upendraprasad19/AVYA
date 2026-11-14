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
final tap on Plan screen ("I COMMIT →") calls
`OnboardingNotifier.completeOnboarding()` which writes the consolidated
profile map to `userBox['profile']`, stamps `onboarding_completed_at`,
generates the plan, records the commitment and fires the initial sync fan-out.
There is no screen after it: the Muster question and the separate Induction
screen were retired on 2026-11-14 (onboarding-fuse-commit).

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
| `onboarding_single_commit` (2026-11-14) | `completeOnboarding` ends with `finalizeLocalCommit()`: `InductionService.recordCommitment` (only when `!hasCommitted`, so a retry never overwrites a pledge) + `completeInduction`, THEN `setOnboarded()`. The session is opened at the TOP of the method (before the cloud guard), and `state.answers` is captured BEFORE that open, because opening the session re-emits `authUserIdTokenProvider` and rebuilds this notifier with empty answers. The profile map carries `id` (the session owner) and `physique_focus: 'balanced'`. | `postSessionRedirect` (`isOnboarded` now means profile + plan + commitment are durable); `ai_snapshot_builder.dart` (`committed_to_lt_cdr`); `AuthNotifier.shouldClearForProfileId` (a profile with no `id` reads as another account's). The `already_onboarded` early return stamps nothing. Tests `onboarding_single_commit_test.dart`, `onboarding_hive_session_open_before_write_test.dart` C1. |
| `muster_to_profile_bridge` | **Live writer retired 2026-11-14** (Muster screen, `recordMusterAnswer`, `_bridgeToProfile` deleted). New users get `physique_focus: 'balanced'` from `completeOnboarding`; `backfillMusterToProfileIfNeeded` still migrates old accounts' stored muster answers once. | profile screen / Edit Profile (`physique_focus`); `ai_snapshot_builder.dart` reads the profile fields directly — see `lib/features/ai_coach/CLAUDE.md`. |
| `referral_redemption` (new users) | The code comes from the Welcome-screen stash OR the email sign-up field, which `AuthNotifier.signUpWithEmail` stores in auth user metadata `referral_code` (diagnose `c7b4d2`). | `completeOnboarding` → `resolveReferralCode(stash, userMetadata)` (stash wins) → `redeem-referral` in `_syncOnboardingAndPostActions`, AFTER the users upsert. The sign-in screen does NOT redeem. |
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
Mission Brief (/onboarding/mission-brief) → founder photo + founder-locked
                                            note ("Welcome aboard, Recruit." →
                                            "AVYA is the structure of military
                                            training…" → "No one is coming to
                                            save you" closer; shortened
                                            2026-11-01 — the injury story and
                                            "Fourteen years" paragraphs are
                                            gone). The
                                            Instagram CTA was REMOVED (founder
                                            call — acquisition friction on the
                                            trust-building first screen).
                                            CONTINUE → Identity            (step 00)
   ↓
Identity      (/onboarding/identity)   → full_name, date_of_birth, sex     (01 · 05)
   ↓
Goal          (/onboarding/goal)       → primary_goal: Build / Cut / Maintain
                                         only (3 cards, 2026-11-01)         (02 · 05)
   ↓
Stats         (/onboarding/stats)      → current_weight_kg, target_weight_kg,
                                         height_cm, body_fat_pct,
                                         activity_level                    (03 · 05)
   ↓
Details       (/onboarding/details)    → fitness_experience, pace_preference,
                                         days_per_week, equipment_access,
                                         injuries                          (04 · 05)
   ↓
Plan          (/onboarding/plan)       → pledge card + "I COMMIT →" — commits via
                                         OnboardingNotifier.completeOnboarding()
                                         (profile, plan, commitment)       (05 · 05)
   ↓
Home          (/home)                   (/coach/muster and /coach/induction
                                         are redirects to /home since
                                         2026-11-14)
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
- **Goal screen = 3 cards (2026-11-01, founder call).** Build (`build_muscle`), Cut (`lose_fat`), Maintain (`general_fitness`). `recompose` / `strength` stay in `FitnessGoals` (restore, legacy chat onboarding, AI coach switch-goal) and in `plan_screen._mapGoal`; the goal-token gate (`scripts/check_goal_token_exhaustiveness.dart`, logic in `goal_token_exhaustiveness_lib.dart`) takes them via the narrow `kLegacyReachableOnlyGoalTokens` allowlist (a stale entry that IS card-reachable fails). A legacy `recomp`/`strength` route extra falls back to Build (`GoalScreen.initState`); the `?? 'recomp'` fallbacks in `plan_screen` / `app_router` are now `'build_muscle'`.
- **Target weight is validated against the goal** (`target_weight_check.dart`, pure): Cut strictly below current, Build strictly above, Maintain ±3.0 kg inclusive, in integer tenths (float trap 78.3−75.3). Blank/NaN → `missing`; `recomp`/`strength`/unknown goals have no rule. `StatsScreen._onCalibrate` validates the RAW parsed value after the weight/height guard and before the body-fat snackbar, and shows a dismissable popup (focus returns to TARGET). The target seed (`seedTargetWeight`) reseeds when the stored target was seeded for a different goal: both Stats exits write `seeded_for_goal`; BACK writes an explicit `target_weight_kg: null` when the field is blank (an absent key would let the `...widget.initial` spread resurrect a stale value).
- **Sex moved from Stats to Identity.** Stats no longer shows the 3-pill sex selector.
- **Age dropped entirely.** `date_of_birth` (captured on Identity via date picker, min age
  13) is the canonical field. `plan_screen` computes `age` on the fly for `BmrCalculator`;
  `age` is never stored to Hive or Supabase.
- **`injuries` is now COLLECTED at onboarding** (Ship 3 / U5, 2026-07-12 — injury-safety
  batch): the Details screen has an injuries chip row (multi-select, pre-selected "No injuries"
  like its other rows so CONTINUE always works). `details_screen` seeds `_injuries` from the
  incoming route extras in `initState` (so the plan→details "ADJUST PLAN" round-trip preserves
  a real selection) and writes `'injuries'` into the outgoing extras; `plan_screen._onReportForDuty`
  reads `widget.data['injuries']` for `setAnswer('injuries', …)` — it was previously HARD-CODED to
  `['none']` (plan_screen ~:531), so an injured user's generated plan was never injury-filtered
  because the data was never captured. The chip vocabulary is the shared `InjuryVocab.chipTokens`
  (== `{none} ∪ canonicalTokens`) + `InjuryVocab.toggleChip`, identical to Edit-Profile — SoT
  `injury_vocabulary_contract`. Founder-accepted tradeoff (Option B): a silent-injured user who
  leaves the default isn't later nagged by the completeness nudge.
- **Fields still defaulted by the stepped flow** (user can edit via Profile → Edit Profile):
  - `lifestyle_activity` — inferred from `activity_level` (1:1 mapping).
  - `diet_preference` — defaults to `'veg'` (Indian-first default).
  - `start_date` — hardcoded to `'this_monday'`.
  - `city` — optional, not collected during onboarding.
  These **are persisted** to Hive by `completeOnboarding` (pre-2026-04-24 bug: they
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
  plan calibration doesn't happen until the commit tap on step 05 (now "I COMMIT"). Renamed to `CONTINUE →`;
  behavior unchanged.
- **Details screen is now ALL chip rows** (APK-test-2-batch / Q8, supersedes APK-test-1-batch
  fade-row layout; Ship 3 / U5 added the 5th row). Sections render as horizontal chip rows:
  Experience (3 chips: Beginner / Intermediate / Advanced), Pace (3 chips: Steady / Balanced /
  Aggressive), Days/Week (4 chips: 3 / 4 / 5 / 6), Equipment (**dropdown** since 2026-11-01: Bodyweight / Dumbbells /
  Basic Gym / Full Gym, **Basic Gym preselected in onboarding only** via `kOnboardingDefaultEquipment`
  — the shared `kDefaultEquipmentAccess` stays `bodyweight`, diagnose d3a8f5, and the seed is written
  as a typed local + ternary because `equipment_access_default_test.dart` bans the
  `['equipment_access'] ?? '<literal>'` shape across `lib/`), and **Injuries** (a collapsed "No
  injuries" row that expands in place to the multi-select `Wrap`: No injuries + the 9 canonical tokens
  from `InjuryVocab.chipTokens`; a pre-existing real selection opens expanded). The collapsed screen is
  436 dp of content (measured with real DM Sans) so it fits 360×640 without scrolling. Selected chip = gold-fill + black
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
| A returning user re-runs onboarding and overwrites a real profile | `completeOnboarding()` now refuses at its ENTRY (before the Hive stamp, so the sync fan-out it triggers is prevented too) when cloud `user_profile.onboarding_completed_at` is already set — `error: 'already_onboarded'`, returns null. Decision is the pure, mutation-proven `OnboardingNotifier.shouldRefuseOnboardingOverwrite`. **FAILS OPEN** on any error or when signed out: a false negative costs a returning user one wrong screen, a false positive would block every genuine new signup — never invert this. Added because THREE routing bugs (1bfeed, a3f6d9, c2e9f4) have put a fully-onboarded user in front of onboarding and only luck (the founder not tapping through) prevented the loss. Kill-switch `disable_onboarding_overwrite_guard`. | `docs/diagnoses/2026-08-10-resolve-destination-failed-read-means-new-user-c2e9f4.md` |
| Stepped onboarding bounces back to Welcome on every tap | `GoRouter._authRedirect`'s `isOnOnboarding` check MUST use `location.startsWith('/onboarding')`, not `location == '/onboarding'`. Sub-routes (`/goal`, `/stats`, `/plan`) would otherwise be redirected back to Welcome on every navigation. Fixed in commit `17faa86`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md, a local build: CLAUDE.md §4.1.5) |

## Tests pinning the rules here

- `test/contracts/onboarding_completed_at_writer_to_reader_test.dart`
- `test/contracts/auth_session_bootstrapper_test.dart` — pure-logic destination table.
- `test/contracts/onboarding_single_commit_test.dart` — the commitment tail's
  order (stamps before the onboarded flag), retry keeps a pledge, the sync uid,
  the profile-id clear decision, the captured answers, the retired routes.
- `test/contracts/muster_bridge_backfill_test.dart` (the muster bridge's
  behavioural test was deleted with `recordMusterAnswer` on 2026-11-14; the
  backfill for old accounts is what remains)
- `test/contracts/full_name_backfill_test.dart`
- `test/contracts/plan_screen_targets_match_completeOnboarding_test.dart`
- `test/contracts/onboarding_injuries_chip_wiring_test.dart` — Ship 3: plan_screen reads the
  collected injuries (no re-hardcode to `['none']`), details writes + seeds them.
- `test/contracts/injury_chip_vocab_contract_test.dart` — Ship 3: the shared chip vocab
  (`InjuryVocab.chipTokens` == `{none} ∪ canonicalTokens`) + `toggleChip` invariants.

## See also

- `lib/features/auth/CLAUDE.md` — post-auth `RestoringScreen` decision tree.
- `lib/features/profile/CLAUDE.md` — Edit Profile reuses the same field map.
- `lib/shared/repositories/plan_engine/CLAUDE.md` — Plan tap triggers initial plan generation.
- `docs/architecture/sync.md` — onboarding sync fan-out + restore-completeness.
