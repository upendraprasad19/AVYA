# APK Test #4 Hotfix Plan C — UX Small (U6, U8, U10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three surgical UX changes — Profile RANK reposition (U6), referral code surfacing (U8), DOB cap 13→10 (U10).

**Spec reference:** `docs/superpowers/specs/2026-04-28-apk-test-4-hotfix-batch-design.md` §3 U6/U8/U10.

**Estimated effort:** 3-5h.

---

## Task C-1 — Profile RANK card move above ProfileCompletenessCard (U6)

**Files:** `lib/features/profile/screens/profile_screen.dart`

- [ ] **Step 1: Find the current widget order**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
grep -nB1 "ProfileIdentity\|ProfileCompletenessCard\|ServiceRecordSection\|_buildDailyCompletion" lib/features/profile/screens/profile_screen.dart | head -25
```

Note the current line numbers. Per OBS-5 close-out, current order is:
1. ProfileCompletenessCard (line ~536)
2. ServiceRecordSection (line ~537)
3. Daily completion / Goals row

User wants ServiceRecordSection BEFORE ProfileCompletenessCard.

- [ ] **Step 2: Reorder**

Edit `lib/features/profile/screens/profile_screen.dart` — find the section where these widgets are listed as Column children (or ListView children). Move `const ServiceRecordSection()` to render BEFORE `ProfileCompletenessCard`.

```dart
// BEFORE (sequential):
ProfileIdentity(...),
const ProfileCompletenessCard(),
const ServiceRecordSection(),
_buildDailyCompletion(),
// ...

// AFTER:
ProfileIdentity(...),
const ServiceRecordSection(),
const ProfileCompletenessCard(),
_buildDailyCompletion(),
// ...
```

- [ ] **Step 3: Verify**

```bash
flutter analyze lib/features/profile/screens/profile_screen.dart
flutter test test/profile/ test/  # full suite
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/profile/screens/profile_screen.dart
git commit -m "feat(profile): RANK card above Profile Completion (U6)

User observation from Test #4 install: 'image 4: in profile screen, lets
use the blank space indicated to mention the rank with drop down. saves
space. and also move the rank to above profile completion block.'

Reorders Profile screen children. ServiceRecordSection (RANK card) now
renders BEFORE ProfileCompletenessCard. The collapsed-by-default
behavior from OBS-5 fills the previously-blank space at the top of the
Profile content stack.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task C-2 — Referral code: remove from welcome, add to signup form + Profile (U8)

**Files:** `lib/features/auth/screens/sign_in_screen.dart`, `lib/features/profile/widgets/invite_friends_sheet.dart` (or equivalent)

- [ ] **Step 1: Find the referral field on welcome screen**

```bash
grep -n "referral\|REFERRAL CODE\|AVYA-XXXX" lib/features/auth/screens/sign_in_screen.dart | head -10
```

- [ ] **Step 2: Identify sign-in vs signup mode separation**

Read `sign_in_screen.dart` for any `_isSignUp` flag or similar that toggles between sign-in and sign-up views. Per CLAUDE.md APK Test #2 / Q3 design, the screen has separate "welcome view" and "email view" with sign-up checkbox in the email view.

```bash
grep -n "_isSignUp\|_isSignup\|signupMode\|signUpMode\|_emailMode" lib/features/auth/screens/sign_in_screen.dart | head -15
```

- [ ] **Step 3: Remove referral field from welcome / sign-in views**

Find and DELETE the referral code input + label + footer text "JOIN 18,866+ INDIANS..." or similar that surrounds it. The widget tree on welcome should end at "Forgot password?" link without the referral input.

Add a comment to mark the deletion:

```dart
// U8 fix (Test #4 hotfix): referral code input REMOVED from welcome
// landing view. Referral entry now lives only in:
//   (a) sign-up form (when _isSignUp == true) — see _buildEmailView
//   (b) Profile → Invite Friends sheet
//
// Welcome screen had it visible to all (signin + signup) which was
// confusing UX — sign-in users have no business entering a referral.
```

- [ ] **Step 4: Add referral field to signup form path**

Find the signup-mode branch in the email view. Add the referral field there:

```dart
if (_isSignUp) ...[
  const SizedBox(height: 16),
  Text(
    'REFERRAL CODE (OPTIONAL)',
    style: AppTypography.mono.copyWith(
      fontSize: 10,
      letterSpacing: 1.4,
      color: AppColors.textDim,
    ),
  ),
  const SizedBox(height: 6),
  TextField(
    controller: _referralController,
    decoration: _inputDecoration(hint: 'AVYA-XXXX1234'),
    style: const TextStyle(color: Colors.white),
    textCapitalization: TextCapitalization.characters,
  ),
  const SizedBox(height: 4),
  Text(
    'Have a referral code? Apply for +7 days PRO.',
    style: AppTypography.body.copyWith(
      fontSize: 12,
      color: AppColors.textDim,
    ),
  ),
],
```

(Adapt `_referralController` to the existing controller name if there's already one. The signup submit handler needs to pass this value to the existing referral redemption flow.)

- [ ] **Step 5: Add / confirm referral entry in Profile → Invite Friends**

```bash
grep -rn "InviteFriendsSheet\|invite_friends\|getOrCreateReferralCode\|redeemReferralCode" lib/features/profile/ | head -10
```

The Invite Friends sheet (if it exists) should have an "Apply someone else's code" entry. Add if missing:

In `lib/features/profile/widgets/invite_friends_sheet.dart` (create if doesn't exist):

```dart
// Inside the sheet's Column:
const SizedBox(height: 16),
const Divider(),
const SizedBox(height: 16),
Text(
  'GOT A REFERRAL CODE?',
  style: AppTypography.mono.copyWith(/* ... */),
),
TextField(
  controller: _applyController,
  decoration: _inputDecoration(hint: 'AVYA-XXXX1234'),
),
WardButton(
  label: 'APPLY CODE',
  onPressed: _onApplyCode,
),
```

The `_onApplyCode` handler calls the existing `redeem-referral` Edge Function pattern (per CLAUDE.md memory).

- [ ] **Step 6: Verify**

```bash
flutter analyze lib/features/auth/screens/sign_in_screen.dart \
                lib/features/profile/widgets/invite_friends_sheet.dart
flutter test test/  # full suite
```

- [ ] **Step 7: Commit**

```bash
git add lib/features/auth/screens/sign_in_screen.dart \
        lib/features/profile/widgets/invite_friends_sheet.dart \
        lib/features/profile/screens/profile_screen.dart
git commit -m "feat(auth+profile): referral code surfacing (U8)

User observation from Test #4 install: 'referral code doesnt make sense
in this screen. why is it here? if a user is signing up using a referral
code, then when he is in signup screen (not signin), he should get code
option. else he can go and apply code from profile screen right?'

Three changes:
1. Welcome / sign-in view: referral field REMOVED. Sign-in users have
   no business entering one.
2. Sign-up form (when _isSignUp == true): referral field ADDED with
   helper text 'Have a referral code? Apply for +7 days PRO.'
3. Profile → Invite Friends sheet: 'Apply someone else's code' entry
   ADDED (uses existing redeem-referral Edge Function).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task C-3 — DOB picker min-age cap 13 → 10 (U10)

**Files:** `lib/features/onboarding/screens/identity_screen.dart`

- [ ] **Step 1: Read current cap**

```bash
grep -nC1 "year - 13\|min age 13" lib/features/onboarding/screens/identity_screen.dart
```

Expected: line 14 (docstring) + line 74 (DateTime calc).

- [ ] **Step 2: Apply edits**

Edit `lib/features/onboarding/screens/identity_screen.dart`:

```dart
// Line 14 (docstring):
// BEFORE:
///   * `date_of_birth` — date picker, required, min age 13

// AFTER:
///   * `date_of_birth` — date picker, required, min age 10
```

```dart
// Line 74 (cap calculation):
// BEFORE:
final max = DateTime(now.year - 13, now.month, now.day);

// AFTER:
final max = DateTime(now.year - 10, now.month, now.day);
```

- [ ] **Step 3: Verify**

```bash
flutter analyze lib/features/onboarding/screens/identity_screen.dart
flutter test test/onboarding/ test/  # full suite — onboarding tests should still pass
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/onboarding/screens/identity_screen.dart
git commit -m "feat(onboarding): DOB min-age cap 13 → 10 (U10)

User observation: 'why is date range bound by years? i tried inserting
date of my son as 2019. i was unable.' Min-age was 13 — son (7) couldn't
enroll. User chose option (c): lower cap to 10 without guardian flow.

Trade-off accepted: less COPPA-aligned but simpler. Track for legal
review post-Test #4. Guardian-managed accounts for under-10 users
remain out of scope for this batch.

Single-line + docstring change. lastDate = DateTime(now.year - 10,
now.month, now.day).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-review

- [ ] **Spec coverage:** U6 (RANK reposition) → C-1; U8 (referral) → C-2; U10 (DOB cap) → C-3. ✅
- [ ] **Placeholder scan:** No TBD/TODO. ✅
- [ ] **Risk:** C-2 has the most surface (3 locations). C-1 + C-3 are surgical.

## Out of scope for Plan C

- Bug fixes → Plans A/B
- U7 + U9 → Plan D
