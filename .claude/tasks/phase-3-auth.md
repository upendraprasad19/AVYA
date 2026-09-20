# Phase 3: Auth + Onboarding

## Agent: @auth-agent
## Deps: Phase 1 (Database tables must exist)

## Tasks

### 3.1 Sign In Screen
- [ ] `lib/features/auth/screens/sign_in_screen.dart`
- [ ] Email input + "Sign In" button
- [ ] Google OAuth button
- [ ] Phone OTP option
- [ ] Dark theme, Switzer font, Electric Cyan accent
- [ ] Loading and error states

### 3.2 Auth Provider
- [ ] `lib/features/auth/providers/auth_provider.dart`
- [ ] Riverpod provider with Supabase Auth methods
- [ ] signInWithEmail, signInWithGoogle, signInWithPhone
- [ ] signUp, signOut
- [ ] Listen to auth state changes

### 3.3 Onboarding Chat Screen
- [ ] `lib/features/onboarding/screens/onboarding_chat_screen.dart`
- [ ] Conversational flow collecting 10 data points (see auth-agent.md)
- [ ] Chat-style UI with bot messages and user inputs
- [ ] Appropriate input types (text, number, dropdown, date picker)
- [ ] Progress indicator (step X of 10)

### 3.4 Onboarding Provider
- [ ] `lib/features/onboarding/providers/onboarding_provider.dart`
- [ ] Collect all 10 fields
- [ ] On complete: write user_profile to Hive + Supabase
- [ ] Run plan_generator locally → save plan to Hive workoutBox
- [ ] Set ai_chat_started_at = now
- [ ] Mark onboarding_completed = true
- [ ] Navigate to home

### 3.5 Router Auth Guard
- [ ] Update `lib/core/router/app_router.dart`
- [ ] Redirect logic: no session → sign-in, not onboarded → onboarding, else → home

## Completion Criteria
- User can sign in with email
- New user sees onboarding chat
- Onboarding collects all 10 fields
- Plan generated locally after onboarding
- User arrives at home screen after onboarding
- Auth guard redirects correctly on app launch

## Logic Reference
- `Knowledgebase/brainstorm data _PROJECT/app/onboarding/chat.jsx` — FLOW array pattern
- `Knowledgebase/brainstorm data _PROJECT/app/auth/sign-in.jsx` — sign-in patterns
