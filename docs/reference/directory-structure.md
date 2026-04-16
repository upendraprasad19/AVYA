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
