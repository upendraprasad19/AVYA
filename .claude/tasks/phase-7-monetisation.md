# Phase 7: Monetisation

## Agent: general
## Deps: Phase 5 (Screens), Phase 6 (Backend)

## Tasks

### 7.1 Razorpay Integration
- [ ] Add Razorpay checkout flow to upgrade screen
- [ ] WebView opens Razorpay payment page
- [ ] On success: poll Supabase for subscription confirmation
- [ ] Update Hive configBox: {isPro: true, expiresAt, plan}
- [ ] Annual plan selected by default

### 7.2 Subscription Service Wiring
- [ ] `isPro()` reads Hive cache, checks expiry
- [ ] Refresh from Supabase on app launch
- [ ] If expired offline → downgrade immediately (no grace period)
- [ ] Soft lock: keep data, show paywall on PRO actions

### 7.3 PaywallSheet Polish
- [ ] Compelling copy per feature
- [ ] Price display: ₹249/month or ₹2,499/year (save X%)
- [ ] Annual pre-selected
- [ ] Smooth bottom sheet animation

### 7.4 Feature Gates (wire into all screens)
- [ ] Train: `phases_2_to_12`, `active_workout_mode`, `pro_tips`
- [ ] Nutrition: `ai_food_analysis`, `adjustable_portions`, `scan_meal`, `diet_plan_pdf`
- [ ] AI Coach: `ai_coach_unlimited`, `reasoning_tab`
- [ ] Profile: `weekly_ai_report`, `progress_photos`
- [ ] All using `subscriptionService.gate()` — no inline isPro

### 7.5 PRO Locked Card Pattern
- [ ] Blur content + dark overlay + gold lock badge + cyan CTA
- [ ] Consistent across all PRO-gated sections

## Completion Criteria
- User can upgrade to PRO via Razorpay
- All PRO features gated correctly
- PaywallSheet appears with correct copy per feature
- Subscription status persists in Hive
- Downgrade works correctly (soft lock)
- Phase 1 remains free under all conditions
