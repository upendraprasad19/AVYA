---
source: CLAUDE.md §10
migrated: 2026-05-18
status: scaffold
---

# Subscription Gate Pattern — Reference

> PRO feature keys, gate() pattern, _highValueFeatures set, server verification.
> Fetch via Read when adding/modifying subscription-gated features.

## PRO Feature Keys
```
phases_2_to_12         → auto-generate new 4-week plan after Week 4
ai_coach_unlimited     → unlimited AI messages (free = 15/day for 30 days)
weekly_ai_report       → weekly nutrition report ongoing (free = first report only)
progress_photos        → full photo timeline
scan_meal_pro          → 3 scans/day (free = 3/month)
cart_auditor_pro       → 3 scans/day (free = 1/month)
ai_text_log_pro        → 10 text logs/day (free = 3/day)
morning_alert_pro      → AI-personalised morning message (free = generic push)
prediction_monthly     → fresh prediction card every month (free = once at onboarding)
adaptive_workouts      → AI workout adjustments from biometrics (Phase 2)
```

**Q6 / APK Test #2 (2026-04-25):** `active_workout_mode` was REMOVED from PRO. Active workout logging is always free for everyone — table-stakes for any fitness app, gating it killed the entry-level experience without driving conversions. The `featureActiveWorkoutMode` constant is kept as `@Deprecated` so legacy callers don't break, but `_highValueFeatures` now contains exactly 3 features: `phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`. Lock-down test in `test/subscription/high_value_features_test.dart`.

**`_highValueFeatures` exact set (server-verified via `verifyFromServer()`):**
```dart
static const Set<String> _highValueFeatures = {
  AppConstants.featurePhases2To12,
  AppConstants.featureAiCoachUnlimited,
  AppConstants.featureProgressPhotos,
};
```

## Shareable Cards (ALL FREE — growth engine)
```
workout_receipt        → PNG after every completed workout + viewable later via "View Card"
future_prediction      → AI forecast card (once free, monthly PRO)
beat_my_coach          → HIIT challenge card (1 per 2 weeks, all users)
video_share            → Remotion/Lambda video render (DEFERRED — hidden until post-launch)
```
All shareable cards include: ICANBEFITTER wordmark + QR code → www.icanbefitter.com
Packages: share_plus (native share sheet) + qr_flutter (client-side QR, zero server cost)

**Workout Receipt — View Past Cards:**
- Receipt data reconstructed on-the-fly from Hive exercise logs (`exercise_log_index_YYYY-MM-DD`)
- `WorkoutReceiptData.fromExerciseLogs(date)` — static factory, returns null if no logs
- `WorkoutReceiptSheet` — reusable bottom sheet (`lib/features/train/widgets/workout_receipt_sheet.dart`)
- Access points: Home screen completed card "View Card" button, Calendar day detail "View Workout Card" button
- Exercise logs store `volume_kg` field for exact volume reconstruction (falls back to `weight_kg × reps` for old logs)

## Correct Usage (ALWAYS use this)
```dart
await subscriptionService.gate(
  'ai_food_analysis',
  onPro: () => analyseFood(),
  onFree: () => showPaywallSheet(context, feature: 'AI Food Analysis'),
);
```

## WRONG (never do this)
```dart
if (isPro) { analyseFood(); }  // ❌ NEVER
```

## isPro() Implementation
- Reads from Hive configBox: `{isPro: bool, expiresAt: DateTime, plan: String}`
- Checks local expiry date
- **kDebugMode guard:** If `expiresAt` is null, returns `true` only in debug mode (`kDebugMode`). In release builds, null expiry = free. Prevents rooted-device Hive tampering from granting PRO.
- Refreshes from Supabase on app launch (if online)
- If expired and offline → downgrade to free immediately (no grace period)
- Downgrade = soft lock: keep all data, show paywall on PRO features, read-only on PRO content
- **Phantom PRO fix:** `localActivationAt` is force-cleared after grace period expires on network error. Prevents stale local timestamp from keeping users in PRO after subscription lapses.
- **JWT refresh:** `razorpay_service` refreshes JWT before each verify-payment retry to prevent 401 errors during polling.
- **Server-side verification:** `gate()` calls `verifyFromServer()` (5-min cache TTL) for high-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`). Other features use local check only for low latency.

## gate() High-Value Features
```dart
static const Set<String> _highValueFeatures = {
  AppConstants.featurePhases2To12,
  AppConstants.featureAiCoachUnlimited,
  AppConstants.featureProgressPhotos,  // photo writes to user-scoped Storage bucket
};
// gate() checks server for these features, local-only for others
```

**Why `progress_photos` is high-value:** It triggers Supabase Storage writes to a user-scoped bucket. Granting access via a spoofed local `isPro` flag would let a free user on a rooted device persist private photos onto infrastructure we pay for. Any feature that writes to Storage or spends cloud compute/storage on behalf of the user MUST be server-verified.
