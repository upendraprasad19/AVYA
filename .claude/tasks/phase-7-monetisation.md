# Phase 7: Monetisation

## Agent: general
## Deps: Phase 5 (Screens), Phase 6 (Backend)

## Tasks

### 7.1 Razorpay Integration
- [ ] Add Razorpay checkout flow to upgrade screen
- [ ] WebView opens Razorpay payment page
- [ ] Pricing: ₹349/month OR ₹2,999/year (annual pre-selected)
- [ ] Annual discount display: "Save 28%"
- [ ] On success: poll Supabase for subscription confirmation
- [ ] Update Hive configBox: {isPro: true, expiresAt, plan}

### 7.2 Subscription Service Wiring
- [ ] `isPro()` reads Hive configBox cache, checks local expiry
- [ ] Refresh from Supabase on app launch (if online)
- [ ] If expired and offline → downgrade immediately (no grace period)
- [ ] Soft lock: keep all data, show paywall on PRO features, read-only on PRO content

### 7.3 PaywallSheet Polish
- [ ] `lib/shared/widgets/paywall_sheet.dart` — single reusable paywall UI
- [ ] Compelling copy per feature (passed as parameter)
- [ ] Price display: ₹349/month or ₹2,999/year (save 28%)
- [ ] Annual plan pre-selected
- [ ] "Start Free Trial" for features with trial (AI Coach)
- [ ] Smooth bottom sheet animation

### 7.4 Feature Gates (ALL PRO features)
All gated via `subscriptionService.gate()` using keys from `AppConstants`:

**Train Screen:**
- `phases_2_to_12` — unlock Phase 2+ plan generation

**Nutrition Screen:**
- `scan_meal_pro` — beyond 3 scans/month free
- `cart_auditor_pro` — beyond 1 scan/month free
- `ai_text_log_pro` — beyond 3 text logs/day free

**AI Coach Screen:**
- `ai_coach_unlimited` — beyond 30-day trial / 15 msg/day
- `reasoning_tab` — deep coaching tab
- `voice_notes` — push-to-talk voice input
- `prediction_monthly` — monthly prediction refresh

**Profile Screen:**
- `weekly_ai_report` — ongoing weekly reports (first free)
- `progress_photos` — photo timeline
- `morning_alert_pro` — AI-personalised morning messages

### 7.5 Usage Counter System
- [ ] `lib/core/services/usage_counter_service.dart`
- [ ] Track daily/monthly usage in Hive configBox:
  - `ai_text_log_count_today: int` (resets daily)
  - `scan_meal_count_month: int` (resets monthly)
  - `cart_auditor_count_month: int` (resets monthly)
  - `scan_meal_count_today: int` (PRO daily tracking)
  - `cart_auditor_count_today: int` (PRO daily tracking)
  - `last_counter_reset_date: DateTime`
- [ ] Reset logic: check date on app launch and before each increment
- [ ] Methods: `canUse(feature) → bool`, `increment(feature)`, `remaining(feature) → int`

### 7.6 Soft Cap Warnings
- [ ] When PRO user hits 2/3 daily scans: show toast "2 of 3 scans used today"
- [ ] When free user approaches limit: show "1 AI text log remaining today"
- [ ] When free user hits limit: show PaywallSheet with upgrade CTA
- [ ] When counter resets (new day/month): clear UI warnings

### 7.7 PRO Locked Card Pattern
- [ ] Blur content + dark overlay + gold lock badge + cyan CTA
- [ ] Consistent across all PRO-gated sections
- [ ] Pattern: `ProLockedOverlay` widget wrapping the content

### 7.8 Phase 1 Graduation Ceremony
- [ ] When user completes Week 4 of Phase 1:
  - Full-screen celebration with stats, streak, PRs
  - Reveal Phase 2 structure (blur exercise names, show day names)
  - "Continue Your Journey" → PaywallSheet for phases_2_to_12
  - This is the #1 conversion moment — polish this screen heavily

## Completion Criteria
- User can upgrade to PRO via Razorpay (₹349/month, ₹2,999/year)
- All PRO features gated correctly via subscription.gate()
- PaywallSheet appears with correct copy per feature
- Usage counters track and reset correctly (daily + monthly)
- Soft cap warnings display at correct thresholds
- Subscription status persists in Hive configBox
- Downgrade works correctly (soft lock, keep data)
- Phase 1 remains free under ALL conditions
- Phase 1 graduation screen triggers correctly at Week 4 completion

## Reference
- `/CLAUDE.md` Sections 10, 14, 16
- `lib/core/constants/app_constants.dart` — pricing, feature keys, all limits
