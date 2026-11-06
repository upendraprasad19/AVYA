# Phase 9: Polish + Launch Prep

## Agent: general
## Deps: Phase 8 (QA Pass)

## Tasks

### 9.1 Animations & Micro-interactions
- [ ] Animated progress rings (calories, macros, water)
- [ ] Skeleton loaders on all data-dependent sections
- [ ] Smooth page transitions
- [ ] PR celebration animation (trophy/confetti on new PR)
- [ ] Streak counter pulse on increment

### 9.2 App Identity
- [ ] App icon (dark bg + Electric Cyan accent)
- [ ] Splash screen (app name + tagline)
- [ ] App name in manifest: "ICANBEFITTER"

### 9.3 Error Handling Polish
- [ ] Friendly error messages (not technical jargon)
- [ ] Retry buttons on all error states
- [ ] Network connectivity indicator
- [ ] Graceful offline mode messaging

### 9.4 Performance
- [ ] Image caching for exercise library images
- [ ] Lazy loading for food database search
- [ ] Efficient Hive queries (don't load full box when filtering)

### 9.5 Configuration
- [ ] `.env.example` with all required env vars
- [ ] `pubspec.yaml` assets registered
- [ ] Android manifest permissions (internet, health)
- [ ] ProGuard rules for Razorpay (Android)

### 9.6 Pre-Launch Checklist
- [ ] `flutter analyze` — zero errors
- [ ] `flutter test` — all pass (if tests exist)
- [ ] `flutter build apk` — builds successfully
- [ ] App launches on Android emulator without crashes
- [ ] Auth flow works end-to-end
- [ ] Onboarding generates plan
- [ ] Workout can be logged
- [ ] Food can be logged
- [ ] AI Coach responds (with Edge Function)

## Completion Criteria
- App builds and runs without errors
- All screens polished with animations and proper states
- Ready for internal testing / beta release
