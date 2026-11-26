# Phase 8: Full QA Pass

## Agent: @qa-agent
## Deps: Phase 7 (Monetisation)

## Tasks

### 8.1 Full Codebase Review
- [ ] Review ALL files in `lib/` against CLAUDE.md coding rules
- [ ] Review ALL files in `supabase/` against CLAUDE.md security rules
- [ ] Check every screen for: loading, error, empty states
- [ ] Check every PRO feature for: subscription.gate() usage
- [ ] Check Phase 1 content: never gated

### 8.2 BLOCKER Checklist
- [ ] No inline isPro checks anywhere
- [ ] No API keys in client code
- [ ] Repository pattern enforced (no direct Hive/Supabase from widgets)
- [ ] Riverpod for all shared state
- [ ] Hive boxes registered and opened in main.dart
- [ ] No hardcoded data in any screen
- [ ] Switzer font everywhere
- [ ] Electric Cyan #00D4FF (no old green)
- [ ] Dark theme hierarchy correct
- [ ] No cross-feature imports
- [ ] Edge Functions validate JWT
- [ ] Razorpay webhook verifies HMAC
- [ ] RLS enabled on all tables

### 8.3 Design Audit
- [ ] Colors match UI.txt tokens
- [ ] Typography matches scale
- [ ] Spacing matches tokens
- [ ] Border radius matches tokens
- [ ] Component patterns match (buttons, cards, badges)

### 8.4 Data Integrity
- [ ] All screens read from Hive (not Supabase for UI)
- [ ] Writes go to Hive first
- [ ] Sync service pushes to Supabase in background
- [ ] Seed data loads correctly on first launch

## Completion Criteria
- Zero BLOCKERS remaining
- All warnings documented (non-blocking)
- Final QA report delivered to Manager Agent
