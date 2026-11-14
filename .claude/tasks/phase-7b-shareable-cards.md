# Phase 7B: Shareable Cards (Workout Receipt, Prediction, Challenge)

## Agent: general
## Deps: Phase 5 (Screens must exist — cards are triggered from workout/coach screens)

## Tasks

### 7B.1 Card Rendering Engine
- [ ] `lib/shared/widgets/shareable_card.dart` — base widget wrapper
  - Dark-mode background (#0e1219)
  - Bottom strip: ICANBEFITTER wordmark (DM Sans, w900) + app logo
  - QR code → `AppConstants.appUrl` (www.icanbefitter.com)
  - QR generated client-side via `qr_flutter` package
  - RepaintBoundary wrapping the entire card
- [ ] `lib/shared/utils/card_share_service.dart`
  - `captureAndShare(GlobalKey repaintKey)` method
  - RepaintBoundary → toImage() → PNG bytes → save to temp file
  - share_plus → native OS share sheet
  - Returns void, fire-and-forget

### 7B.2 Workout Receipt Card
- [ ] `lib/features/train/widgets/workout_receipt_card.dart`
- [ ] Triggered: after completing a workout → "Share Your Session" button
- [ ] Content:
  - Date + day name
  - Workout name (e.g., "PUSH DAY · PHASE 1")
  - Exercise list with sets × reps × weight (compact)
  - Total volume (kg), total sets, duration
  - PRs hit (highlighted in Electric Cyan)
  - Current streak badge
  - Sarcastic tagline (rotate from a list of 20+)
- [ ] Tier: FREE for all users
- [ ] Design: dark card, Electric Cyan accents, clean typography

### 7B.3 Future Prediction Card
- [ ] `lib/features/ai_coach/widgets/prediction_card.dart`
- [ ] Triggered:
  - Once after onboarding (free) — data from Future Prediction Edge Function
  - Monthly for PRO users — "Your Updated Prediction" notification
- [ ] Content:
  - "YOUR 90-DAY PREDICTION" header
  - Current stats → Predicted stats (weight, body fat %, key lifts)
  - Visual arrow/progress indicator
  - Motivational tagline from AI
  - Date generated
- [ ] Tier: once free (post-onboarding), monthly PRO (prediction_monthly gate)
- [ ] "Share My Prediction" button → share_plus

### 7B.4 Beat My Coach Challenge Card
- [ ] `lib/features/train/widgets/challenge_card.dart`
- [ ] Triggered: new challenge available notification (every 2 weeks)
- [ ] Content:
  - Challenge name (e.g., "THE DESTROYER")
  - Exercise list with rep counts
  - "Coach's Time: 18:42"
  - "CAN YOU BEAT IT?" CTA
  - Difficulty badge (Brutal / Savage / Insane)
- [ ] Tier: FREE for all users (1 per 2 weeks)
- [ ] "Challenge a Friend" button → share_plus
- [ ] After completion: show user's time vs coach's time → shareable result card

### 7B.5 Add Packages
- [ ] Add to `pubspec.yaml`:
  - `share_plus: ^10.0.0` (native share sheet)
  - `qr_flutter: ^4.1.0` (client-side QR generation)

## Completion Criteria
- Workout Receipt renders correctly with real workout data
- Future Prediction card renders with prediction JSON from Edge Function
- Beat My Coach card renders with challenge data
- All cards include ICANBEFITTER branding + QR code
- Share button opens native share sheet with PNG image
- QR code scans correctly to www.icanbefitter.com
- All cards follow design system: dark theme, Electric Cyan accent, DM Sans font
- No API calls during card rendering — all data already available locally

## Reference
- `/CLAUDE.md` Section 9 (Design System), Section 10 (Shareable Cards spec)
- `lib/core/constants/app_constants.dart` — appUrl, appName
