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
ai_coach_unlimited     → dedicated coaching + higher daily limit (free = 7/day forever, no trial; PRO = 20/day). Gate id is internal and NOT renamed (rule 19).
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
- Downgrade = soft lock: keep all data, show paywall on PRO features, read-only on PRO content. Exception, stated not decided: Progress photos are LOCKED, not read-only, for a lapsed user (entry is blocked at the hub row and by the screen's own gate; the hub row already did this before 2026-10-05; a screen that is ALREADY OPEN when the subscription lapses keeps showing and deleting photos until the next Add tap, because only entry and Add run the gate), so the only in-app way to remove a lapsed user's progress photos is Delete Account (DPDP §17). Founder decision 2026-10-06 (row C7): a lapsed user MAY view and delete old photos and may not upload new ones. The database half (migration 154) is INSERT-only and so already allows view and delete; the app half (hub row, screen entry) still locks them until unit B2 (OI-314).
- **Phantom PRO fix:** `localActivationAt` is force-cleared after grace period expires on network error. Prevents stale local timestamp from keeping users in PRO after subscription lapses.
- **Grace window is DERIVED (OI-182):** `kPaymentGraceWindow` in `lib/core/constants/payment_timing.dart` = last verify retry (15 m) + `kActivationPhasesBudget` (225 s) + one bounded retry attempt (60 s) + 2 m margin ≈ 21 m 45 s; every network call in the activation flow is wrapped in `boundedAttempt`. A retry that verifies runs write-PRO-state → clear grace → refresh → clear `localActivationAt` in that order (`payment_retry_attempt.dart`). Retries are in-memory timers: best-effort under suspend / app kill.
- **No `users.subscription_*` mirror (OI-202, migration 152):** entitlement is derived from `public.subscriptions` only (`status='active' AND end_date > now()`); server-side expiry windows use `fetchLatestActiveEndByUser` (`_shared/subscription.ts`). razorpay-webhook and verify-payment write the `subscriptions` row and nothing else.
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

**Why `progress_photos` is high-value:** It triggers Supabase Storage writes to a user-scoped bucket. Granting access via a spoofed local `isPro` flag would let a free user on a rooted device persist private photos onto infrastructure we pay for. Any feature that writes to Storage or spends cloud compute/storage on behalf of the user MUST be server-verified. (Since the progress-photo PRO INSERT rule, migration 154, the database refuses the INSERT as well, see below, so a spoofed flag no longer persists a photo; the client gate remains so a refused user is stopped before the picker and the upload.)

**A PRO-only screen gates ITSELF (2026-10-05, R1-04 of the Photos-hub batch).** A gate on the door (a row, a button) is bypassed by any way in that does not go through it: on web, `#/profile/progress-photos` edited into an app that is already open (a fresh load goes through `/restoring` and lands on Home, so only a warm tab reaches it). `ProgressPhotosScreen` therefore runs `gateAndVerify(featureProgressPhotos)` on entry (`_enter`) and again on its Storage-writing action (`_onAddPhoto`, which waits on the server for up to 10 s when the 5-minute verify cache is stale, shows the busy spinner and ignores a second tap meanwhile), and shows a locked card (`ProLockedOverlay`) to a user the gate refuses; a refused user who upgrades gets the gate re-run (`ref.listen` on `subscriptionInfoProvider`). The door's gate stays: it gives a free user the paywall without opening the screen. Client gates stop honest users and typed addresses; the enforcement a determined client cannot skip is a server rule (RLS or a BEFORE INSERT check, modelled on the AI-coach daily-cap trigger), which `progress_photos` has since migration 154 (`progress_photos_pro_insert_rls_rule`, row C5 of `docs/plans/progress-screen-pro-gate.md`): the Storage INSERT policy `progress_photos_insert_own` on the `progress-photos` bucket and a BEFORE INSERT trigger on `public.progress_photos` both require an active, unexpired `public.subscriptions` row (`status = 'active' AND end_date > now()`, the predicate `verify-subscription` reads). INSERT only: the SELECT and DELETE policies are untouched, so a lapsed user can still view and delete what they have (founder decision 6, 2026-10-06; this is the DATABASE only: the app still locks a lapsed user out at the hub row and at the screen entry, and the client half of decision 6 is unit B2, OI-314; an `INSERT ... ON CONFLICT` by a lapsed user is refused too, so an existing row is edited with a plain UPDATE). Because `capture` uploads first, the refusal a client is expected to see is the Storage refusal (`StorageException.statusCode == '403'`, taken from the response body; the HTTP status itself can be 400 or 403 depending on the Storage version; expected, not yet verified against the live Storage API); the trigger's PostgREST `P0001` `progress_photo_pro_required` is the second line of defence. Named residuals the rule does not close: the 5/day cap is client-side only, a signed upload URL minted while PRO stays usable until it expires, an object whose row insert then fails is an orphan, and a user who has JUST paid is refused until the `subscriptions` row exists (seconds, up to about 20 minutes in the worst realistic case: the client stops believing PRO at about 21 m 45 s, `kPaymentGraceWindow` in `lib/core/constants/payment_timing.dart`; the row can arrive later still if only Razorpay's own webhook retries deliver it, and the refusal is permanent if the webhook and every retry fail); the out-of-repo Telegram bot was not checked for progress-photo inserts.
