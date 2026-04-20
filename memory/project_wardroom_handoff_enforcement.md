# Wardroom Handoff Enforcement — Sweep Summary

**Date:** 2026-04-20
**Branch:** feat/wardroom-handoff-enforcement
**Commits:** 17 (16 PRs R–AF + 1 post-PR nav fix)
**Merge commit:** e3d5aaf (merged into main)

## Scope

Enforced the canonical Wardroom design handoff (`Knowledgebase/Avya App redesign/design_handoff_wardroom/`) onto 14 screens:
- 5 main tabs: Daily (Home), Train, Active Workout, Nutrition, AI Coach
- 4 new stepped onboarding screens: Welcome, Goal, Stats, Plan
- 4 utility screens: Settings, Edit Profile, Weekly Reports, Notifications Inbox
- 1 Profile screen: banner height bump + identity widget

## What Shipped

- **13 new Wardroom primitives** added to `lib/shared/widgets/wardroom/` (total now 28, up from 15)
- **`lib/core/copy/wardroom_copy.dart`** — single source for all literal handoff strings
- **`colors.dart`** reconciled to JSX source of truth (not README, which rounds for print)
- **Stepped onboarding** replaces chat-based flow; legacy chat still at `/onboarding/chat`
- **`_authRedirect` fix**: `startsWith('/onboarding')` so sub-routes don't bounce back
- **`WardBar.trailingLabel`** slot added for gold "25%" trailing numeral
- **`WardLetterhead.dividerStyle`** — new `WardDivider` enum (none / single / double) with legacy `divider: bool` kept for backward-compat

## What's Deferred (PR AG)

- Nutrition meal-slot cards (structural only — Galley redo landed, content cards pending)
- Coach "Today's Insight" + Suggested Actions + Patterns sections
- Profile Journey card + Body Stats + Achievements + Subscription Seal
- Stepped-onboarding field coverage: `fitness_experience`, `days_per_week`, `equipment_access`, `lifestyle_activity`, `pace_preference`, `diet_preference`, `injuries`, target weight
- Notifications inbox real-data wiring (OneSignal + Hive box reader — currently sample data)

## APK

Built from worktree before merge. Path:
`.claude/worktrees/wardroom-handoff-enforcement/build/app/outputs/flutter-apk/app-prod-release.apk`

On-device smoke test: Welcome → Goal → Stats → Plan navigation confirmed working after the auth-redirect fix.
