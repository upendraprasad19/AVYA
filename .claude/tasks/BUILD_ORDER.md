# ICANBEFITTER — Build Order

> Manager Agent reads this file to determine what to build next.
> Status: [ ] = not started, [~] = in progress, [x] = done

## Phase 0: Project Init
- [x] Flutter scaffold, dependencies, directory structure, theme
- Agent: setup (manual)
- Deps: none

## Phase 1: Database
- [ ] 21 Supabase tables + RLS + indexes
- Agent: @database-agent
- Task file: .claude/tasks/phase-1-database.md
- Deps: Phase 0

## Phase 2: Seed Data
- [ ] 200+ exercises + 5,000 foods as bundled JSON
- Agent: @database-agent
- Task file: .claude/tasks/phase-2-seed-data.md
- Deps: Phase 1

## Phase 3: Auth + Onboarding
- [ ] Supabase Auth + onboarding chat + plan generation
- Agent: @auth-agent
- Task file: .claude/tasks/phase-3-auth.md
- Deps: Phase 1

## Phase 4: Core Services
- [ ] Repositories, providers, Hive service, sync service, subscription service
- Agent: general
- Task file: .claude/tasks/phase-4-services.md
- Deps: Phase 1

## Phase 5: Screens (PARALLEL)
- [ ] Home dashboard
- [ ] Train screen + active workout
- [ ] Nutrition screen + diet plan
- [ ] AI Coach screen
- [ ] Profile screen + reports
- Agent: @screen-agent (×5 parallel)
- Task file: .claude/tasks/phase-5-screens.md
- Deps: Phase 3, Phase 4

## Phase 6: Backend Edge Functions
- [ ] AI proxy (free + PRO), Razorpay webhook, daily snapshot, weekly recalc
- Agent: @backend-agent
- Task file: .claude/tasks/phase-6-backend.md
- Deps: Phase 1

## Phase 7: Monetisation
- [ ] Razorpay integration, subscription service, PaywallSheet, feature gates
- Agent: general
- Task file: .claude/tasks/phase-7-monetisation.md
- Deps: Phase 5, Phase 6

## Phase 8: Full QA Pass
- [ ] Review ALL files against CLAUDE.md
- Agent: @qa-agent
- Task file: .claude/tasks/phase-8-qa.md
- Deps: Phase 7

## Phase 9: Polish + Launch
- [ ] Animations, skeleton loaders, error states, app icon, splash screen
- Agent: general
- Task file: .claude/tasks/phase-9-polish.md
- Deps: Phase 8

---

## Parallelism Notes
After Phase 1 is DONE: Phases 2, 3, 4, 6 can run in PARALLEL (independent deps).
Phase 5 requires 3 + 4 but all 5 screens can run in PARALLEL.
Phase 7 requires 5 + 6. Phase 8 requires 7. Phase 9 requires 8.
