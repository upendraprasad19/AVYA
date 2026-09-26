# Directory Structure

> Extracted from CLAUDE.md §5 to keep the master reference lean.
> The actual file tree is the source of truth — this doc is a quick orientation.

```
lib/
  main.dart
  app.dart                              # MaterialApp + theme + GoRouter
  core/
    theme/
      app_theme.dart                    # Dark ThemeData with all tokens
      colors.dart                       # AppColors static class
      typography.dart                   # AppTypography text styles
      spacing.dart                      # AppSpacing + AppRadius constants
    router/
      app_router.dart                   # GoRouter config + auth redirect
    constants/
      app_constants.dart                # API URLs, feature keys, limits
    services/
      supabase_service.dart             # Supabase client singleton
      ai_service.dart                   # OpenRouter fallback chain
      subscription_service.dart         # isPro(), gate(), openUpgrade()
      sync_service.dart                 # Daily snapshot, weekly full sync
      hive_service.dart                 # Box init, adapter registration
      seed_service.dart                 # First-launch: parse bundled JSON → Hive
      day_rollover_service.dart         # Bug #13 — runRolloverNow() called from splash
    utils/
      bmr_calculator.dart               # Mifflin-St Jeor formula
      date_utils.dart
      exercise_display.dart             # Experience-level-aware exercise label formatter (V4)
  features/
    auth/
      screens/sign_in_screen.dart
      screens/splash_screen.dart        # Bug #13 — calls runRolloverNow before /home
      providers/auth_provider.dart
    onboarding/
      screens/onboarding_chat_screen.dart
      providers/onboarding_provider.dart
    home/
      screens/home_screen.dart          # No prediction card (moved to profile in Bug #14)
      widgets/
        profile_nudge_card.dart         # Dismissible profile completeness nudge card
      providers/home_provider.dart      # streakWarningEligibilityProvider (Bug #12)
    train/
      screens/train_screen.dart         # Collapsible warmup/cooldown (Bug #15)
      screens/active_workout_screen.dart # One-exercise-focus (Bug #15)
      screens/template_builder_screen.dart
      widgets/
        workout_receipt_card.dart          # WorkoutReceiptData (source of truth: fromExerciseLogs)
        workout_receipt_sheet.dart         # Reusable receipt bottom sheet
        edit_workout_log_sheet.dart        # SINGLE edit surface for completed workouts
        create_custom_exercise_sheet.dart  # Custom exercise creator
      providers/train_provider.dart
      repositories/workout_repository.dart # getRecentWorkoutCompletionHours (Bug #12)
    nutrition/
      screens/nutrition_screen.dart
      screens/diet_plan_screen.dart
      widgets/
      providers/nutrition_provider.dart
      repositories/nutrition_repository.dart
    ai_coach/
      screens/ai_coach_screen.dart      # Retry button on failed messages (Bug #19)
      widgets/
        chat_bubble.dart                # Error/retry rendering (Bug #19)
        prediction_card.dart            # Now consumed by profile (Bug #14)
      providers/ai_coach_provider.dart  # Two-write persistence (Bug #19)
      repositories/ai_coach_repository.dart # saveUserMessagePending + update (Bug #19)
    profile/
      screens/profile_screen.dart       # Premium pill + new section order (Bug #14)
      screens/edit_profile_screen.dart
      screens/reports_screen.dart
      widgets/
        profile_completeness_card.dart  # Progress bar + missing fields on profile screen
        profile_identity.dart           # Premium pill button (Bug #14)
        slim_achievements_card.dart     # Single-line achievements with badges + chevron
      providers/
        profile_completeness_provider.dart  # Tier 1/2 weighted completeness calculation
        profile_provider.dart
  shared/
    widgets/
      paywall_sheet.dart                # Single reusable paywall UI
      pro_badge.dart                    # Champion Gold badge
      streak_warning_banner.dart        # Smart eligibility (Bug #12)
      loading_skeleton.dart
      hydration_color_card.dart
    repositories/
      user_repository.dart
      exercise_repository.dart
      food_repository.dart
      plan_generator.dart               # Hard floor 5 + retry chain (Bug #17). NEVER modify without explicit approval.
      plan_engine/                      # V4 modular pipeline
        models.dart                     # MuscleSlot, MuscleSlotDay
        split_resolver.dart             # Stage 1: muscle-level day splits (8-10 P1-P5 slots/day)
        volume_filter.dart              # Stage 1.5: slots.take(targetCount(exp, daysPerWeek))
        exercise_selector.dart          # Stage 2: 5-attempt cascade within movement patterns
        sequencing_engine.dart          # Stage 3: CNS ordering
        periodization_engine.dart       # Stage 4: DUP + exercise-specific rep_range
        superset_engine.dart            # Stage 5: pairing
        cardio_finisher.dart            # Stage 6: cardio append
        warmup_cooldown_selector.dart   # Stage 7: warmup/cooldown injection

assets/
  data/
    exercise_library.json               # 250 exercises with V4 fields (movement_pattern, target_focus, equipment_tier, rep_range, priority_tier). Timed entries have default_duration_secs (Bug #16)
    food_database.json                  # 5,000 Indian-first foods, bundled in APK
  fonts/
    # DM Sans font loaded via google_fonts package (runtime download)

scripts/
  enrich_exercise_library.py           # One-shot: add V4 fields to exercise library
  add_new_exercises.py                 # Add ~30 new exercises for gap coverage
  add_rep_ranges.py                    # Add exercise-specific rep ranges
  validate_exercise_library.py         # Coverage matrix validation

supabase/
  migrations/                           # SQL migration files
    015_morning_alert_cron.sql          # Bug #18 — pg_cron schedules for morning-alert
  functions/                            # Edge Functions (TypeScript)
    ai-proxy/index.ts                   # Free: 3-tier fallback. PRO: direct Cerebras 120B
    ai-proxy-pro/index.ts               # Direct Cerebras 120B
    ai-media-proxy/index.ts             # Vision (PRO only)
    morning-alert/index.ts              # Bug #18 — 8s timeout, PRO-light fallback, structured logging
    razorpay-webhook/index.ts           # HMAC verify → write subscriptions (idempotent)
    verify-payment/index.ts             # Client-side polling fallback
    daily-snapshot/index.ts             # Nightly cron
    weekly-recalc/index.ts              # Experience level recalculation
    weekly-report/index.ts              # PRO weekly nutrition report
    future-prediction/index.ts          # Prediction card AI generation
    rolling-context/index.ts            # AI coach context refresh

.claude/
  commands/                              # Slash-command skills (auto-discovered)
    add-edge-function.md                 # Scaffold Supabase Edge Function
    add-migration.md                     # Create SQL migration file
    add-repository.md                    # Create Hive-first repository
    build-apk.md                         # Automated APK build pipeline (pre-flight, clean, build, verify)
    build.md                             # Autonomous multi-phase build pipeline
    design-review.md                     # Widget design system audit
    gate-feature.md                      # Wire PRO subscription gate
    pre-commit-check.md                  # QA checklist before commit
    scaffold-screen.md                   # Generate feature folder + screen template
    seed-data.md                         # Generate exercise/food seed data
  agents/                                # Subagent role definitions
    auth-agent.md                        # Auth + onboarding scope
    backend-agent.md                     # Edge Functions scope
    database-agent.md                    # Supabase DB scope
    manager-agent.md                     # Pipeline orchestrator
    qa-agent.md                          # QA + testing scope
    screen-agent.md                      # Flutter screen scope
  tasks/                                 # Build pipeline phase files
    BUILD_ORDER.md                       # Phase dependency graph
```

---

## Quick orientation (relocated from CLAUDE.md §5 by the 2026-05-18 declutter)

> See `docs/naming_conventions.md` for naming rules + reserved domain glossary. **Read this before introducing new feature names.**

```
lib/
  core/{theme, router, constants, services, utils, copy}/   # singletons, GoRouter, theme tokens, BMR
      utils/exercise_display.dart    # Experience-aware exercise labels
      copy/wardroom_copy.dart        # Single source for literal Wardroom handoff strings
                                     #   (eyebrows, CTA labels, onboarding copy, notifications)
  features/{auth, onboarding, home, train, nutrition, ai_coach, profile}/
    each: screens/, widgets/, providers/, repositories/, models/
      onboarding/screens/
        welcome_screen.dart          # Stepped flow entry — / onboarding (NEW default)
        goal_screen.dart             # /onboarding/goal (NEW)
        stats_screen.dart            # /onboarding/stats (NEW)
        plan_screen.dart             # /onboarding/plan — "REPORT FOR DUTY" CTA (NEW)
        onboarding_chat_screen.dart  # LEGACY — now only at /onboarding/chat for rollback
      profile/screens/
        settings_screen.dart         # Wardroom refresh (PR AC)
        notifications_screen.dart    # Wardroom notifications inbox (PR AF)
      profile/providers/profile_completeness_provider.dart  # Tier 1/2 weighted calculation
      profile/widgets/profile_completeness_card.dart  # Progress bar + missing fields
      profile/widgets/slim_achievements_card.dart     # Single-line badges row
      profile/screens/submissions_screen.dart         # Tabbed MY SUBMISSIONS / COMMUNITY
                                                      #   REVIEW. Canonical route:
                                                      #   /profile/submissions (S1, APK
                                                      #   test #1 batch 2026-04-24).
      profile/screens/my_submissions_screen.dart      # LEGACY — kept only so old
                                                      #   deep-links to /profile/my-
                                                      #   submissions keep working. Do
                                                      #   not add new entry points;
                                                      #   route new callers at
                                                      #   /profile/submissions instead.
  shared/
    widgets/    paywall_sheet, pro_badge, streak_warning_banner, loading_skeleton
      wardroom/   # 36 exports (up from 28) — see "Wardroom primitives" in §9.
                  # Barrel: wardroom.dart. New since PR R (2026-04-18..20):
                  #   ward_seal_badge.dart            — WardSealBadge + WardSealVariant
                  #   ward_dispatch_header.dart       — WardDispatchHeader (double gold rule eyebrow)
                  #   ward_insight_quote.dart         — WardInsightQuote + InsightSegment
                  #   ward_glass_grid.dart            — WardGlassGrid (8-cell hydration)
                  #   ward_achievement_strip.dart     — WardAchievementStrip (earned/locked circles)
                  #   ward_phase_dots.dart            — WardPhaseDots (12-phase row)
                  #   ward_phase_block.dart           — WardPhaseBlock (roman numeral + START chip)
                  #   ward_stat_tile.dart             — WardStatTile (mono label + Fraunces numeric)
                  #   ward_radio_row.dart             — WardRadioRow (gold left-border)
                  #   ward_toggle.dart                — WardToggle (pill, 150ms crossfade)
                  #   ward_unit_toggle.dart           — WardUnitToggle (KG/LBS pill)
                  #   ward_session_row.dart           — WardSessionRow + WardSessionTable
                  #   ward_category_sidebar.dart      — WardCategorySidebar (rotated mono label)
    repositories/  user, exercise, food, plan_generator (NEVER modify without approval)
      plan_generator.dart (re-export shim)
      plan_engine/             # V4 modular pipeline
        models.dart            # MuscleSlot, MuscleSlotDay, CSpec (legacy)
        split_resolver.dart    # Trainer-wisdom splits → MuscleSlotDay[]
        volume_filter.dart     # Stage 1.5: slots.take(targetCount(exp, daysPerWeek))
        exercise_selector.dart # 5-attempt cascading fallback
        plan_generator.dart    # Pipeline orchestrator (generateV4)
        periodization_engine.dart # DUP + exercise-specific rep_range
        sequencing_engine.dart # CNS ordering
        superset_engine.dart   # Pairing
        cardio_finisher.dart   # Cardio append
        warmup_cooldown_selector.dart # Warmup/cooldown inject

assets/data/{exercise_library, food_database}.json    # bundled, seeded into Hive on first launch
supabase/{migrations, functions}/                     # SQL + Edge Functions (TS)
```

## Single-source-of-truth files

**Don't fork these:**

- `lib/features/train/widgets/workout_receipt_card.dart` — `WorkoutReceiptData.fromExerciseLogs()` (the only receipt builder)
- `lib/features/train/widgets/edit_workout_log_sheet.dart` — the only completed-workout edit surface (4 entry points route through it)
- `lib/core/services/day_rollover_service.dart` — `runRolloverNow()` (canonical "today" provider invalidation list)
- `lib/core/services/subscription_service.dart` — `isPro()` + `gate()` (never read `configBox.get('isPro')` directly)
- `lib/core/services/ai_service.dart` — `_compactContext()` (the only snapshot trimmer)
- `lib/shared/repositories/plan_generator.dart` — workout plan generation (CLAUDE rule #14: untouchable without explicit approval)
- `lib/shared/repositories/plan_engine/volume_filter.dart` — Stage 1.5 target-count trimming (`targetCount(experience, daysPerWeek)`)
- `lib/core/utils/exercise_display.dart` — Experience-level exercise label formatting
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart V4 pipeline tracer. Run this when plan generator output looks wrong; emits `test/plan_generator/v4_diagnostic_output.md`. Mirrors `exercise_repository.queryV4` + `exercise_selector._cascadeFill`; any change to either production file requires an equivalent update to the mirror.
- `lib/features/nutrition/providers/diet_plan_provider.dart` — ONE reader of `configBox['saved_diet_plan']`. Returns `Map<String, PlannedSlot>` keyed by slot (breakfast/lunch/dinner/snack). Consumed by `TodaysMealsCard` to render "FROM YOUR DIET PLAN" hints on empty slots. `diet_plan_screen._savePlan` invalidates this provider after writing the plan (PR AH.5).
- `lib/features/profile/providers/weekly_report_data_provider.dart` — ONE source for Weekly Report 4-up sparklines. Reads last-7-days series from `healthBox` (weight, forward-filled), `nutritionBox` (calories + protein, zero-filled), `workoutBox` (0/1 per day). Consumed only by `WeeklyReportCard` (PR AH.8). Invalidate after any mutation if you want real-time refresh; the card is not watched elsewhere.
- `docs/sot_registry.yaml` — canonical machine-readable registry of every single-source-of-truth concept (writers + readers + regression tests + class constraints). Cross-referenced by every fix involving a writer/reader contract. Keep in sync when this bullet list, the Source-of-Truth Rules, the Hive field-name contract, the Sync fan-out contract, or the Restore-completeness sync sub-section change.
- `lib/core/services/sync_service.dart` — `SyncService` singleton. Split into 8 part files under `lib/core/services/sync/` via Dart `part`/`part of` + extensions (refactor `refactor/sync-service-part-split`, 2026-05-13). Root file (~1339 lines) keeps: class declaration, singleton, instance fields, static helpers (`_deterministicId`, `_looksLikeUuid`, `_nlogKeyForRestore`, `_customEntityId`, `_hasValue`, `_hasNumber`, `_currentPlatform`, `_currentClientVersion`), cross-domain orchestrators (`checkAndSync`, `pushSnapshot`, `weeklyFullSync`, `restoreFromCloud*`, `pullRecentCrossChannelLogs`), and **infrastructure helpers heavily called by every domain part file** (`_reportSyncFailure`, `_safeRestoreOp`, `_ensureSessionOpen`, `_setTimestamp`, `_getTimestamp`, `_executeUserProfileUpsert`, `drainTelemetryQueue`, `initQueue`, etc.) — these must stay on the class body because Dart extensions cannot dispatch to methods defined on other extensions of the same type. Domain part files: `sync_workout.dart` (~1574), `sync_nutrition.dart` (~428), `sync_health.dart` (~400), `sync_profile.dart` (~349), `sync_community.dart` (~492), `sync_coach.dart` (~217), `sync_restore_completeness.dart` (~284), `sync_realtime.dart` (~121). Public API surface pinned by `test/contracts/sync_service_public_api_snapshot_test.dart`. Fan-out + restore-completeness contracts pinned by `sync_fanout_contract_test.dart` + `restore_completeness_writes_test.dart` (both broadened to scan root + all part files via `test/contracts/_sync_service_source.dart` helper).
