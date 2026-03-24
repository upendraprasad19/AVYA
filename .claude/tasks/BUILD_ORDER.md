# ICANBEFITTER — Build Order

> Manager Agent reads this file to determine what to build next.
> Status: [ ] = not started, [~] = in progress, [x] = done

## Phase 0: Project Init
- [x] Flutter scaffold, dependencies, directory structure, theme
- Agent: setup (manual)
- Deps: none

## Phase 1: Database
- [x] 21 Supabase tables + RLS + indexes
- Agent: @database-agent
- Task file: .claude/tasks/phase-1-database.md
- Deps: none

## Phase 2: Seed Data
- [x] 200+ exercises + 5,000 foods as bundled JSON → Hive on first launch
- Agent: @database-agent
- Task file: .claude/tasks/phase-2-seed-data.md
- Deps: Phase 1

## Phase 3: Auth + Onboarding + Plan Wiring
- [x] Auth + onboarding + plan generator wired → scheduled_workouts with real calendar dates → Hive workoutBox
- Agent: @auth-agent
- Task file: .claude/tasks/phase-3-auth.md
- Deps: Phase 1, Phase 2 (needs exerciseBox populated)

## Phase 4: Core Services
- [x] Calendar data provider, usage counter service, subscription service updated with 14 feature keys, wired to main.dart
- Agent: general
- Task file: .claude/tasks/phase-4-services.md
- Deps: Phase 1

## Phase 5: Screens (5x PARALLEL)
- [x] Home dashboard (calendar from Hive, weight sparkline, PR snapshot, compact stat widgets)
- [x] Train screen + active workout (6 logging types, PR detection, exercise swap from Hive, Phase 2+ gate)
- [x] Nutrition screen (AI text logs 3/10, scan meal 3mo/3day, cart auditor 1mo/3day, diet plan PDF free, saved meals)
- [x] AI Coach screen (15 msg/day trial, reasoning PRO, voice notes PRO, prediction card, Telegram toggle)
- [x] Profile screen (biometric sync free, progress photos PRO, weekly report first-free, subscription card ₹349/₹2999, logout)
- Agent: @screen-agent (×5 parallel)
- Task file: .claude/tasks/phase-5-screens.md
- Deps: Phase 3, Phase 4

## Phase 6: Backend Edge Functions
- [x] AI proxy (free + PRO), Razorpay webhook, daily snapshot, weekly recalc
- Agent: @backend-agent
- Task file: .claude/tasks/phase-6-backend.md
- Deps: Phase 1

## Phase 6B: Backend — New Features
- [x] Rolling Context Optimization (2AM cron: summarize 50 msgs → fitness_summary)
- [x] Morning Alert Generator (2AM batch → write personalized messages → 7AM push)
- [x] Beat My Coach challenge generator (HIIT finisher, 1 per 2 weeks)
- [x] Future Prediction generator (AI forecast card — once post-onboarding, monthly PRO)
- Agent: @backend-agent
- Task file: .claude/tasks/phase-6b-new-features.md
- Deps: Phase 6

## Phase 7: Monetisation
- [x] Razorpay integration (₹349/month, ₹2,999/year)
- [x] PaywallSheet with correct pricing
- [x] subscription.gate() wired to ALL PRO features with new feature keys
- [x] Usage counters: AI text logs (3/day free, 10/day PRO), scan meal (3/month free, 3/day PRO), cart auditor (1/month free, 3/day PRO)
- [x] Soft cap warnings ("2 of 3 scans used today")
- Agent: general
- Task file: .claude/tasks/phase-7-monetisation.md
- Deps: Phase 5, Phase 6

## Phase 7B: Shareable Cards
- [x] Workout Receipt PNG (free, after every workout)
- [x] Future Prediction card (once free, monthly PRO)
- [x] Beat My Coach challenge card (1 per 2 weeks, free)
- [x] All cards: ICANBEFITTER wordmark + QR code → www.icanbefitter.com
- [x] share_plus → native share sheet
- Agent: general
- Task file: .claude/tasks/phase-7b-shareable-cards.md
- Deps: Phase 5

## Phase 8: Full QA Pass
- [x] Review ALL files against CLAUDE.md (Section 6: 15 coding rules, Section 9: design system, Section 10: gate pattern, Section 14: free/PRO tiers)
- Agent: @qa-agent
- Task file: .claude/tasks/phase-8-qa.md
- Deps: Phase 7, Phase 7B

## Phase 9: Polish + Launch
- [x] Animations, skeleton loaders, error states, app icon, splash screen
- [x] UI fixes: dashboard stat widgets → one-line values, workout screen heading → left-aligned
- Agent: general
- Task file: .claude/tasks/phase-9-polish.md
- Deps: Phase 8

---

## Parallelism Notes
After Phase 1 is DONE: Phases 2, 4, 6 can run in PARALLEL (independent deps).
Phase 3 requires Phase 2 (needs exerciseBox populated for plan generation).
Phase 5 requires Phase 3 + 4. All 5 screens can run in PARALLEL.
Phase 6B requires Phase 6. Can run in PARALLEL with Phase 5.
Phase 7 + 7B require Phase 5. Can run in PARALLEL with each other.
Phase 8 requires Phase 7 + 7B. Phase 9 requires Phase 8.

## Phase 2 Targets (after ~2,000 PRO users)
- Skin in the Game Wallet (needs legal review)
- AI-Automated Upselling (plateau detection)
- Shadow Rivalries (needs user base for matching)
- WhatsApp AI Coach (₹99/month add-on)
- Adaptive workouts from biometrics
