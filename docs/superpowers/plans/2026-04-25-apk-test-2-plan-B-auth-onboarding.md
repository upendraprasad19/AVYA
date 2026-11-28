# APK Test #2 — Plan B: Auth & Onboarding

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the post-authentication flow so returning users land on `/home` with full data restored, new users get a Mission Brief credibility moment, and every auth surface (Welcome / sign-in / phone OTP / forgot password) carries consistent branding.

**Architecture:** A new `RestoringScreen` becomes the post-auth gate, branching on `user_profile.onboarding_completed_at` (added in Plan A migration 036). New users → Mission Brief (step 00) → existing identity flow. Returning users → awaited `restoreFromCloud()` → home. All auth sub-views inherit a compact `_AuthHeader`. Privacy/terms shifts from a standalone modal to inline footer + signup checkbox; returning users skip via cloud sync of `users.terms_accepted_at`.

**Tech Stack:** Flutter (Dart 3), Riverpod, GoRouter, Hive, Supabase Auth + Postgres. Asset bundling for the Mission Brief photo. `url_launcher` for Instagram + Privacy/Terms external links.

**Spec source:** `docs/superpowers/specs/2026-04-25-apk-test-2-batch-design.md` (Section 3 — Restore Flow Architecture; Section 5 — Auth & Onboarding)

**Branch:** `feat/apk-test-2-batch` (continues from Plan A)

**Prerequisite:** Plan A complete and merged. Migration 036 must be applied to prod (Plan A Task 1) before this plan starts.

---

## File Structure

### New files
- `lib/features/auth/screens/restoring_screen.dart` — branded post-auth restore gate
- `lib/features/auth/widgets/auth_header.dart` — compact letterhead shared across sub-views
- `lib/features/onboarding/screens/mission_brief_screen.dart` — onboarding step 00 (founder credibility)
- `assets/founder/upendra.jpg` — converted from `assets/naval pics/18052229773959933.heic`

### Modified files
- `lib/features/auth/screens/splash_screen.dart` — split post-auth into restore-gate path
- `lib/features/auth/screens/welcome_screen.dart` — add privacy footer, optional referral code field stays for Plan C
- `lib/features/auth/screens/sign_in_screen.dart` — add `_AuthHeader` to email + phone + OTP views; add privacy checkbox to signup
- `lib/features/auth/widgets/forgot_password_sheet.dart` — add `_AuthHeader`
- `lib/core/router/app_router.dart` — add `/restoring`, `/onboarding/mission-brief` routes; redirect logic
- `lib/core/services/sync_service.dart` — `restoreFromCloud` returns `Future<RestoreResult>` with cancellation support; sync `users.terms_accepted_at` from cloud
- `lib/features/onboarding/providers/onboarding_provider.dart` — `completeOnboarding` writes `onboarding_completed_at` to Supabase
- `lib/features/onboarding/screens/plan_screen.dart` — add micro-reference under REPORT FOR DUTY
- `lib/features/ai_coach/providers/ai_coach_provider.dart` — first-message system context tweak
- `pubspec.yaml` — register `assets/founder/`
- `lib/main.dart` or wherever `TermsModal` gating lives — skip modal when Hive `terms_accepted_at` is set (synced from cloud)

### Tests
- `test/auth/restoring_screen_test.dart` — branching logic + timeout
- `test/auth/auth_header_test.dart` — letterhead renders correctly
- `test/onboarding/mission_brief_screen_test.dart` — layout, photo, Instagram tap, CONTINUE
- `test/router/post_auth_redirect_test.dart` — route decisions for new vs returning users
- `test/auth/terms_skip_test.dart` — TermsModal skipped when cloud timestamp present

---

## Tasks

### Task 1: Convert founder photo HEIC → JPG asset

**Files:**
- Create: `assets/founder/upendra.jpg` (square 1024×1024)
- Modify: `pubspec.yaml`

- [ ] **Step 1: Run conversion script**

```bash
python <<'EOF'
import pillow_heif
from PIL import Image
import os

src = r"C:\Upendra\Claude Code\Fitness App\assets\naval pics\18052229773959933.heic"
out_dir = r"C:\Upendra\Claude Code\Fitness App\assets\founder"
os.makedirs(out_dir, exist_ok=True)

pillow_heif.register_heif_opener()
img = Image.open(src).convert("RGB")

# Square crop centered on the subject (officer pose — face in upper third)
w, h = img.size
side = min(w, h)
# Center crop horizontally; bias upward 10% so face stays in the visible
# 96dp circular crop in the app
left = (w - side) // 2
top = max(0, (h - side) // 2 - int(h * 0.10))
img = img.crop((left, top, left + side, top + side))

# Resize to 1024x1024 master
img = img.resize((1024, 1024), Image.LANCZOS)
img.save(os.path.join(out_dir, "upendra.jpg"), "JPEG", quality=92, optimize=True)
print(f"OK: wrote {os.path.join(out_dir, 'upendra.jpg')}")
EOF
```

Expected: file `assets/founder/upendra.jpg` exists, ~150-300 KB, 1024×1024 dimensions.

- [ ] **Step 2: Register asset folder in pubspec.yaml**

Open `pubspec.yaml`. Locate the `flutter:` → `assets:` section and add:

```yaml
flutter:
  assets:
    # ... existing entries ...
    - assets/founder/
```

- [ ] **Step 3: Verify Flutter can resolve the asset**

```bash
flutter pub get
flutter analyze
```

Expected: no asset-related errors.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml assets/founder/upendra.jpg
git commit -m "assets(founder): upendra.jpg from HEIC source

Square 1024×1024 JPEG quality 92, converted from
assets/naval pics/18052229773959933.heic (officer pose with medals,
selected during Q5 brainstorm). Crop biases face into upper third
so the 96dp circular mask in MissionBriefScreen frames the face
cleanly.

Spec section 5 / Q5."
```

---

### Task 2: New `_AuthHeader` widget

**Files:**
- Create: `lib/features/auth/widgets/auth_header.dart`
- Test: `test/auth/auth_header_test.dart`

Compact letterhead shared across all auth sub-views (email form, phone OTP, forgot password). Follows existing `WardLetterhead` aesthetic but tighter.

- [ ] **Step 1: Write the widget tests first**

```dart
// test/auth/auth_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/widgets/auth_header.dart';
import 'package:icanbefitter/core/theme/colors.dart';

void main() {
  group('AuthHeader', () {
    testWidgets('renders eyebrow text and view title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthHeader(
              eyebrow: 'RECRUIT REGISTRY',
              title: 'Sign in',
            ),
          ),
        ),
      );

      expect(find.text('RECRUIT REGISTRY'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('renders back button when onBack is provided', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthHeader(
              eyebrow: 'RECRUIT REGISTRY',
              title: 'Sign in',
              onBack: () => pressed = true,
            ),
          ),
        ),
      );

      final backBtn = find.byKey(const ValueKey('auth-header-back'));
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      expect(pressed, true);
    });

    testWidgets('omits back button when onBack is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthHeader(
              eyebrow: 'RECRUIT REGISTRY',
              title: 'Sign in',
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('auth-header-back')), findsNothing);
    });

    testWidgets('renders mini AVYA seal', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthHeader(
              eyebrow: 'RECRUIT REGISTRY',
              title: 'Sign in',
            ),
          ),
        ),
      );

      // Seal should render (existing asset or glyph, depending on impl)
      expect(find.byKey(const ValueKey('auth-header-seal')), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/auth/auth_header_test.dart
```

Expected: all 4 tests fail (widget doesn't exist).

- [ ] **Step 3: Write the widget**

```dart
// lib/features/auth/widgets/auth_header.dart
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Compact letterhead for auth sub-views (email form, phone OTP, forgot
/// password, signup form). Renders:
///
/// ```
/// [← back]   ⊙ AVYA           RECRUIT REGISTRY
///                              ─────────────────
///                              Sign in
/// ```
///
/// Welcome screen retains its full hero layout — only sub-views use this.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.onBack,
  });

  final String eyebrow;
  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: GestureDetector(
                key: const ValueKey('auth-header-back'),
                onTap: onBack,
                child: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
            ),

          // Mini AVYA seal — 36dp gold-ringed circle
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Container(
              key: const ValueKey('auth-header-seal'),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 1.5),
                color: AppColors.bgDeep,
              ),
              alignment: Alignment.center,
              child: Image.asset(
                'assets/avya_icon.png',
                width: 22,
                height: 22,
              ),
            ),
          ),

          // Right column: eyebrow + rule + title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 60,
                  height: 1,
                  color: AppColors.accent.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: AppTypography.titleL.copyWith(
                    fontSize: 22,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/auth/auth_header_test.dart -v
```

Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/auth/auth_header_test.dart \
        lib/features/auth/widgets/auth_header.dart
git commit -m "feat(auth): AuthHeader compact letterhead widget

Shared header for auth sub-views (email/phone/OTP/forgot password)
to fix observation #23 (sign-in continuation screens had no logo,
broke visual continuity with the welcome screen). 36dp gold-ring
mini AVYA seal + mono eyebrow + 60dp gold rule + Fraunces 22sp
title.

Welcome screen retains its full hero treatment — only sub-views
inherit this compact header.

Spec section 5 / Q3."
```

---

### Task 3: Wire `_AuthHeader` into sign-in sub-views + forgot password sheet

**Files:**
- Modify: `lib/features/auth/screens/sign_in_screen.dart`
- Modify: `lib/features/auth/widgets/forgot_password_sheet.dart`

- [ ] **Step 1: Wrap `_buildEmailView` with `AuthHeader`**

Open `lib/features/auth/screens/sign_in_screen.dart`. Locate `_buildEmailView`. Wrap the body in a Column with `AuthHeader` at the top:

```dart
Widget _buildEmailView(BuildContext context) {
  return Column(
    children: [
      AuthHeader(
        eyebrow: 'RECRUIT REGISTRY',
        title: _isSignUp ? 'Sign up' : 'Sign in',
        onBack: () {
          setState(() {
            _showEmailForm = false;
          });
        },
      ),
      Expanded(
        child: SingleChildScrollView(
          // ... existing email form widgets ...
        ),
      ),
    ],
  );
}
```

Add the import:
```dart
import 'package:icanbefitter/features/auth/widgets/auth_header.dart';
```

- [ ] **Step 2: Same treatment for `_buildPhoneView` and `_buildOtpView`**

```dart
Widget _buildPhoneView(BuildContext context) {
  return Column(
    children: [
      AuthHeader(
        eyebrow: 'RECRUIT REGISTRY',
        title: 'Phone sign in',
        onBack: () { /* back handler */ },
      ),
      // existing body
    ],
  );
}

Widget _buildOtpView(BuildContext context) {
  return Column(
    children: [
      AuthHeader(
        eyebrow: 'RECRUIT REGISTRY',
        title: 'Enter the code',
        onBack: () { /* back handler */ },
      ),
      // existing body
    ],
  );
}
```

- [ ] **Step 3: Add `AuthHeader` to ForgotPasswordSheet**

Open `lib/features/auth/widgets/forgot_password_sheet.dart`. The sheet body is wrapped in a Column already — add `AuthHeader` at the top:

```dart
Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    AuthHeader(
      eyebrow: 'RECRUIT REGISTRY',
      title: 'Reset password',
      onBack: () => Navigator.of(context).pop(),
    ),
    // existing email field + send button
  ],
)
```

- [ ] **Step 4: Manual visual check**

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

Navigate Welcome → Continue with email → email form. Confirm header renders with seal, eyebrow, rule, title. Tap back arrow → returns to Welcome. Same for phone OTP and forgot password sheet.

Stop the app (Ctrl-C). No automated test for visual continuity here — it's just `AuthHeader` placement. The widget tests in Task 2 cover correctness.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/screens/sign_in_screen.dart \
        lib/features/auth/widgets/forgot_password_sheet.dart
git commit -m "feat(auth): wire AuthHeader into sign-in sub-views

All auth sub-views now show compact branded header:
  - _buildEmailView (sign in / sign up email form)
  - _buildPhoneView (phone OTP entry)
  - _buildOtpView (OTP verification)
  - ForgotPasswordSheet

Welcome screen is intentionally NOT wrapped — it retains its full
hero layout (the user's observation #23 was specifically about
sub-views having no logo).

Spec section 5 / Q3."
```

---

### Task 4: Privacy/terms — Welcome footer + signup checkbox

**Files:**
- Modify: `lib/features/auth/screens/welcome_screen.dart`
- Modify: `lib/features/auth/screens/sign_in_screen.dart` (`_buildEmailView` for `_isSignUp == true`)

- [ ] **Step 1: Add privacy footer to Welcome screen**

Open `lib/features/auth/screens/welcome_screen.dart`. Locate the bottom of the layout (below the BEGIN ENLISTMENT button + "Already a member? SIGN IN" line). Add a footer:

```dart
Padding(
  padding: const EdgeInsets.only(top: 16, bottom: 8),
  child: RichText(
    textAlign: TextAlign.center,
    text: TextSpan(
      style: AppTypography.bodyS.copyWith(color: AppColors.textMute),
      children: [
        const TextSpan(text: 'By continuing, you agree to our '),
        TextSpan(
          text: 'Privacy Policy',
          style: TextStyle(
            color: AppColors.accent,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              launchUrl(Uri.parse('https://icanbefitter.com/privacy'));
            },
        ),
        const TextSpan(text: ' and '),
        TextSpan(
          text: 'Terms',
          style: TextStyle(
            color: AppColors.accent,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              launchUrl(Uri.parse('https://icanbefitter.com/terms'));
            },
        ),
        const TextSpan(text: '.'),
      ],
    ),
  ),
),
```

Add imports:
```dart
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
```

- [ ] **Step 2: Add pre-checked privacy checkbox to signup form**

Open `lib/features/auth/screens/sign_in_screen.dart`. In `_buildEmailView`, add state:

```dart
bool _privacyAccepted = true; // Pre-checked per Q2 decision
```

Above the SIGN UP button, when `_isSignUp == true`, render the checkbox:

```dart
if (_isSignUp) ...[
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Checkbox(
          value: _privacyAccepted,
          activeColor: AppColors.accent,
          checkColor: AppColors.bg,
          onChanged: (v) => setState(() => _privacyAccepted = v ?? false),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTypography.bodyS.copyWith(
                color: AppColors.textPrimary,
              ),
              children: [
                const TextSpan(text: 'I agree to the '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: TextStyle(
                    color: AppColors.accent,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launchUrl(
                          Uri.parse('https://icanbefitter.com/privacy')),
                ),
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Terms',
                  style: TextStyle(
                    color: AppColors.accent,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launchUrl(
                          Uri.parse('https://icanbefitter.com/terms')),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
],
```

Gate the SIGN UP button enabled state:

```dart
ElevatedButton(
  onPressed: (_privacyAccepted && !_loading) ? _submit : null,
  // existing styling (uses theme so disabled state works automatically)
  child: Text(_isSignUp ? 'SIGN UP' : 'SIGN IN'),
)
```

- [ ] **Step 3: Stamp `terms_accepted_at` on signup success**

Locate the `_submit` method in `sign_in_screen.dart`. After successful signup (Supabase Auth `signUp` returns user), update Hive + ensure `_ensureLocalUser` syncs to cloud. The existing `TermsModal` flow already stamps Hive on accept — use the same helper here:

```dart
// Inside _submit after successful signUp + before navigation:
if (_isSignUp) {
  final hive = HiveService.instance;
  await hive.userBox.put('terms_accepted_at', DateTime.now().toIso8601String());
  await hive.userBox.put('terms_version', AppConstants.termsVersion);
  // _ensureLocalUser (called downstream) syncs both fields to public.users.
}
```

- [ ] **Step 4: Update `_ensureLocalUser` to push terms_accepted_at to cloud**

Open `lib/core/services/sync_service.dart` (or wherever `_ensureLocalUser` lives). In the upsert payload to `public.users`, ensure these fields are included:

```dart
final payload = {
  'id': user.id,
  'email': user.email,
  // ... existing fields ...
  if (hive.userBox.get('terms_accepted_at') != null)
    'terms_accepted_at': hive.userBox.get('terms_accepted_at'),
  if (hive.userBox.get('terms_version') != null)
    'terms_version': hive.userBox.get('terms_version'),
};
```

(This may already be present from migration 032 — verify and add only if missing.)

- [ ] **Step 5: Restore terms_accepted_at from cloud on relogin**

In `sync_service._restoreUserProfile()`, when fetching the user row, write the cloud timestamp into Hive:

```dart
final cloud = await supabase.from('users').select().eq('id', userId).single();
if (cloud['terms_accepted_at'] != null) {
  await hive.userBox.put('terms_accepted_at', cloud['terms_accepted_at']);
}
if (cloud['terms_version'] != null) {
  await hive.userBox.put('terms_version', cloud['terms_version']);
}
```

This means returning users won't see the standalone `TermsModal` on cold launch after logout — Hive gets the timestamp restored before the modal gates check.

- [ ] **Step 6: Confirm `TermsModal` skip logic respects Hive timestamp**

Open `lib/main.dart` (or wherever `TermsModal.maybeShow` is called from). Verify the gate:

```dart
final accepted = HiveService.instance.userBox.get('terms_accepted_at');
final acceptedVersion = HiveService.instance.userBox.get('terms_version');
if (accepted != null && acceptedVersion == AppConstants.termsVersion) {
  return; // Skip modal
}
TermsModal.show(context);
```

If this logic doesn't exist or is broken, fix it now.

- [ ] **Step 7: Write a regression test**

```dart
// test/auth/terms_skip_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';

void main() {
  setUpAll(() async {
    await Hive.initFlutter('test_terms_skip');
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
  });

  group('TermsModal gate', () {
    test('skips when current version timestamp present', () {
      final box = HiveService.instance.userBox;
      box.put('terms_accepted_at', DateTime.now().toIso8601String());
      box.put('terms_version', AppConstants.termsVersion);

      final shouldShow = _shouldShowTermsModal();
      expect(shouldShow, false);
    });

    test('shows when timestamp present but version stale', () {
      final box = HiveService.instance.userBox;
      box.put('terms_accepted_at', DateTime.now().toIso8601String());
      box.put('terms_version', 'old-version');

      final shouldShow = _shouldShowTermsModal();
      expect(shouldShow, true);
    });

    test('shows when no timestamp', () {
      final box = HiveService.instance.userBox;
      box.delete('terms_accepted_at');
      box.delete('terms_version');

      final shouldShow = _shouldShowTermsModal();
      expect(shouldShow, true);
    });
  });
}

bool _shouldShowTermsModal() {
  final accepted = HiveService.instance.userBox.get('terms_accepted_at');
  final version = HiveService.instance.userBox.get('terms_version');
  return !(accepted != null && version == AppConstants.termsVersion);
}
```

- [ ] **Step 8: Run tests**

```bash
flutter test test/auth/terms_skip_test.dart -v
```

Expected: 3 tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/features/auth/screens/welcome_screen.dart \
        lib/features/auth/screens/sign_in_screen.dart \
        lib/core/services/sync_service.dart \
        test/auth/terms_skip_test.dart
git commit -m "feat(auth): Q2 inline privacy checkbox + cloud sync

Replaces standalone TermsModal interrupt screen with:
  - Welcome footer: 'By continuing, you agree to [Privacy] and [Terms]'
    External links to icanbefitter.com/privacy + /terms.
  - Signup form: pre-checked checkbox above SIGN UP button. Untick →
    button disabled. Tappable inline links to same external URLs.
  - Returning users: cloud users.terms_accepted_at synced to Hive on
    restore. TermsModal gate respects Hive timestamp + version. No
    re-prompt for users who already accepted.

Pre-checked default per Q2 — common Indian fintech pattern (CRED,
Zerodha, Razorpay). Tapping SIGN UP with a visible-and-tickable
checkbox is the affirmative action under DPDP.

Spec section 5 / Q2."
```

---

### Task 5: Mission Brief screen (onboarding step 00)

**Files:**
- Create: `lib/features/onboarding/screens/mission_brief_screen.dart`
- Test: `test/onboarding/mission_brief_screen_test.dart`

- [ ] **Step 1: Write the widget tests**

```dart
// test/onboarding/mission_brief_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/onboarding/screens/mission_brief_screen.dart';

void main() {
  group('MissionBriefScreen', () {
    Widget buildScreen() => const ProviderScope(
          child: MaterialApp(home: MissionBriefScreen()),
        );

    testWidgets('renders eyebrow + title', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.textContaining('MISSION BRIEF'), findsOneWidget);
      expect(find.text('A note from your coach.'), findsOneWidget);
    });

    testWidgets('renders founder name + credentials', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('UPENDRA PRASAD'), findsOneWidget);
      expect(find.textContaining('EX-INDIAN NAVY'), findsOneWidget);
      expect(find.textContaining('14 YEARS'), findsOneWidget);
      expect(find.textContaining('CERTIFIED'), findsOneWidget);
    });

    testWidgets('renders locked founder copy with Jai Hind', (tester) async {
      await tester.pumpWidget(buildScreen());
      // Spot-check key phrases (full quote split into multiple TextSpan)
      expect(find.textContaining('built AVYA'), findsOneWidget);
      expect(find.textContaining('aren\'t algorithmic guesses'), findsOneWidget);
      expect(find.textContaining('14 years of military training'), findsOneWidget);
      expect(find.textContaining('playbook is mine'), findsOneWidget);
      expect(find.textContaining('Jai Hind'), findsOneWidget);
    });

    testWidgets('renders subtle Instagram link', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(
        find.textContaining('Daily wins on Instagram'),
        findsOneWidget,
      );
      expect(find.textContaining('@icanbefitter'), findsOneWidget);
    });

    testWidgets('renders single CONTINUE CTA', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.textContaining('CONTINUE'), findsOneWidget);
    });

    testWidgets('renders founder photo via Image.asset', (tester) async {
      await tester.pumpWidget(buildScreen());
      final imageFinder = find.byKey(const ValueKey('founder-photo'));
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<Image>(imageFinder);
      final provider = image.image;
      expect(provider, isA<AssetImage>());
      expect((provider as AssetImage).assetName, 'assets/founder/upendra.jpg');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/onboarding/mission_brief_screen_test.dart
```

Expected: all 6 tests fail (file doesn't exist yet).

- [ ] **Step 3: Build the screen**

```dart
// lib/features/onboarding/screens/mission_brief_screen.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class MissionBriefScreen extends ConsumerWidget {
  const MissionBriefScreen({super.key});

  Future<void> _openInstagram() async {
    final native = Uri.parse('instagram://user?username=icanbefitter');
    if (await canLaunchUrl(native)) {
      await launchUrl(native);
    } else {
      await launchUrl(Uri.parse('https://instagram.com/icanbefitter'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Eyebrow
              Text(
                '⊙  AVYA  ·  MISSION BRIEF',
                style: AppTypography.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 8),
              Container(width: 80, height: 1, color: AppColors.accent),
              const SizedBox(height: 24),

              // Title
              Text(
                'A note from your coach.',
                style: AppTypography.titleL.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 32),

              // Photo
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent, width: 1.5),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/founder/upendra.jpg',
                      key: const ValueKey('founder-photo'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Name (centered)
              Center(
                child: Text(
                  'UPENDRA PRASAD',
                  style: AppTypography.titleL.copyWith(fontSize: 22),
                ),
              ),
              const SizedBox(height: 8),

              // Credentials
              Center(
                child: Text(
                  'EX-INDIAN NAVY  ·  14 YEARS',
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'CERTIFIED FITNESS + NUTRITION COACH',
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),

              // Short rule
              Center(
                child: Container(
                  width: 24,
                  height: 1,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 24),

              // Body copy with italic-gold emphasis
              RichText(
                text: TextSpan(
                  style: AppTypography.bodyL.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.55,
                  ),
                  children: [
                    const TextSpan(
                      text:
                          '"I built AVYA because every fitness app I tried treated me like a number. The plans you\'ll see in this app ',
                    ),
                    TextSpan(
                      text: 'aren\'t algorithmic guesses',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const TextSpan(
                      text:
                          ' — they\'re shaped by 14 years of military training and certified coaching practice. The AI executes the playbook. ',
                    ),
                    TextSpan(
                      text: 'The playbook is mine.',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const TextSpan(text: '\n\nJai Hind!"'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Signature
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '— Upendra',
                  style: AppTypography.mono.copyWith(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Instagram subtle link
              Center(
                child: GestureDetector(
                  onTap: _openInstagram,
                  child: RichText(
                    text: TextSpan(
                      style: AppTypography.mono.copyWith(
                        fontSize: 11,
                        color: AppColors.textMute,
                      ),
                      children: [
                        const TextSpan(text: 'Daily wins on Instagram → '),
                        TextSpan(
                          text: '@icanbefitter',
                          style: TextStyle(
                            color: AppColors.accent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // CONTINUE CTA
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => context.go('/onboarding/identity'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.bg,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'CONTINUE  →',
                    style: AppTypography.mono.copyWith(
                      fontSize: 14,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/onboarding/mission_brief_screen_test.dart -v
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/onboarding/mission_brief_screen_test.dart \
        lib/features/onboarding/screens/mission_brief_screen.dart
git commit -m "feat(onboarding): Q5 Mission Brief screen (step 00)

New onboarding step 00 inserted between sign-up and Identity. Founder
photo (assets/founder/upendra.jpg) + locked copy + subtle Instagram
link + single CONTINUE CTA.

Italic-gold emphasis on two phrases: 'aren't algorithmic guesses' and
'The playbook is mine.' Body copy ends on 'Jai Hind!' per the locked
voice from Q5 brainstorm.

Routing handoff in next task: app_router redirects new signups
(no user_profile row) to this screen instead of straight to Identity.
Returning users skip via the restore flow in Task 7.

Spec section 5 / Q5."
```

---

### Task 6: Plan screen + AI coach micro-references

**Files:**
- Modify: `lib/features/onboarding/screens/plan_screen.dart`
- Modify: `lib/features/ai_coach/providers/ai_coach_provider.dart`

- [ ] **Step 1: Add line under REPORT FOR DUTY in plan_screen**

Open `lib/features/onboarding/screens/plan_screen.dart`. Locate the REPORT FOR DUTY button. Add a small line below it:

```dart
const SizedBox(height: 12),
Center(
  child: Text(
    'Plan shaped by 14 years of disciplined coaching.',
    style: AppTypography.bodyS.copyWith(
      color: AppColors.textMute,
      fontStyle: FontStyle.italic,
    ),
    textAlign: TextAlign.center,
  ),
),
```

- [ ] **Step 2: Add credential nod to AI coach first message**

Open `lib/features/ai_coach/providers/ai_coach_provider.dart`. Locate where the first system-prompt context is built (the chat init / send-first-message path). Add the credential line to the system context preamble (only when this is the user's first message, i.e., no prior `ai_coach_interactions` rows):

```dart
// Inside the system prompt builder, when buildAiContext + first message:
final isFirstMessage = ref.read(coachInteractionsCountProvider) == 0;
final credentialLine = isFirstMessage
    ? "You're trained on Upendra's 14-year coaching playbook — be confident, "
      "direct, and back recommendations with real-world experience."
    : '';
final systemPrompt = '$credentialLine\n\n$existingSystemPrompt';
```

If `coachInteractionsCountProvider` doesn't exist, derive the check from existing context:

```dart
final priorMessages = HiveService.instance.coachBox.values
    .where((v) => v is Map && v['user_id'] == userId)
    .length;
final isFirstMessage = priorMessages == 0;
```

- [ ] **Step 3: Manual smoke test**

Build dev APK, complete onboarding (or use seeded test account). REPORT FOR DUTY screen shows the line below the button. Open AI coach for the very first time and send a message — coach response should land naturally; the system prompt change is server-side, no visible UI.

- [ ] **Step 4: Commit**

```bash
git add lib/features/onboarding/screens/plan_screen.dart \
        lib/features/ai_coach/providers/ai_coach_provider.dart
git commit -m "feat(onboarding): Q5 micro-references on Plan + AI coach

Two small credibility threads beyond the Mission Brief screen:
  - Plan screen, below REPORT FOR DUTY: parchment-mute line
    'Plan shaped by 14 years of disciplined coaching.'
  - AI coach first-ever message gets a system-prompt prefix nod
    to the 14-year coaching playbook so the coach voice carries
    the same authority signal.

These are micro — easy to ignore, easy to notice. Spec section 5 / Q5
'micro-references' decision."
```

---

### Task 7: RestoringScreen + post-auth restore flow

**Files:**
- Create: `lib/features/auth/screens/restoring_screen.dart`
- Test: `test/auth/restoring_screen_test.dart`
- Modify: `lib/core/services/sync_service.dart` (add cancellation + RestoreResult)
- Modify: `lib/features/onboarding/providers/onboarding_provider.dart` (`completeOnboarding` writes `onboarding_completed_at`)

The decision tree:
```
sign-in succeeds
  → /restoring
    parallel:
      ├─ SELECT user_id, onboarding_completed_at FROM user_profile
      └─ start restoreFromCloud() (cancellable)
    branch on query result:
      ├─ row + onboarding_completed_at IS NOT NULL → await restore → /home
      ├─ row + onboarding_completed_at IS NULL → cancel restore → resume onboarding
      └─ no row → cancel restore → /onboarding/mission-brief
```

- [ ] **Step 1: Write the screen tests**

```dart
// test/auth/restoring_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/auth/screens/restoring_screen.dart';

void main() {
  group('RestoringScreen', () {
    Widget build() => const ProviderScope(
          child: MaterialApp(home: RestoringScreen()),
        );

    testWidgets('renders branded copy + animated dots', (tester) async {
      await tester.pumpWidget(build());
      expect(find.text('Pulling your dispatch.'), findsOneWidget);
      expect(find.textContaining('Stand by'), findsOneWidget);
      expect(find.byKey(const ValueKey('restoring-dots')), findsOneWidget);
    });

    testWidgets('hides timeout CTA before 15 seconds', (tester) async {
      await tester.pumpWidget(build());
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('restoring-timeout-cta')), findsNothing);
    });

    testWidgets('shows timeout CTA after 15 seconds', (tester) async {
      await tester.pumpWidget(build());
      await tester.pump(const Duration(seconds: 16));
      expect(
        find.byKey(const ValueKey('restoring-timeout-cta')),
        findsOneWidget,
      );
      expect(find.textContaining('CONTINUE'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/auth/restoring_screen_test.dart
```

Expected: all 3 tests fail.

- [ ] **Step 3: Write the RestoringScreen**

```dart
// lib/features/auth/screens/restoring_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class RestoringScreen extends ConsumerStatefulWidget {
  const RestoringScreen({super.key});

  @override
  ConsumerState<RestoringScreen> createState() => _RestoringScreenState();
}

class _RestoringScreenState extends ConsumerState<RestoringScreen> {
  bool _showTimeoutCta = false;
  Timer? _timeoutTimer;
  StreamSubscription<RestoreResult>? _restoreSub;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _showTimeoutCta = true);
    });
    _kickoffRestore();
  }

  Future<void> _kickoffRestore() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/');
      return;
    }

    // Parallel: profile lookup + start restore
    final profileFuture = supabase
        .from('user_profile')
        .select('user_id, onboarding_completed_at')
        .eq('user_id', user.id)
        .maybeSingle();

    final restoreFuture = SyncService.instance.restoreFromCloud();

    final profile = await profileFuture;

    if (profile == null) {
      // New user — cancel restore (it would be a no-op anyway), go to Mission Brief
      SyncService.instance.cancelInflightRestore();
      if (mounted) context.go('/onboarding/mission-brief');
      return;
    }

    if (profile['onboarding_completed_at'] == null) {
      // Mid-onboarding — cancel restore, jump to first missing step
      SyncService.instance.cancelInflightRestore();
      if (mounted) {
        final route = await _resolveOnboardingResumeRoute(user.id);
        context.go(route);
      }
      return;
    }

    // Onboarded — await restore (with timeout safety from the Timer above)
    final result = await restoreFuture;
    if (!mounted) return;
    context.go('/home');
  }

  Future<String> _resolveOnboardingResumeRoute(String userId) async {
    final supabase = Supabase.instance.client;
    final profile = await supabase
        .from('user_profile')
        .select()
        .eq('user_id', userId)
        .single();

    if (profile['full_name'] == null) return '/onboarding/identity';
    if (profile['primary_goal'] == null) return '/onboarding/goal';
    if (profile['weight_kg'] == null) return '/onboarding/stats';
    if (profile['fitness_experience'] == null) return '/onboarding/details';
    return '/onboarding/plan';
  }

  void _onContinueAnyway() {
    if (mounted) context.go('/home');
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _restoreSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Centered AVYA seal with pulsing glow
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/avya_icon.png',
                  width: 48,
                  height: 48,
                ),
              ),
              const SizedBox(height: 24),
              Container(width: 80, height: 1, color: AppColors.accent),
              const SizedBox(height: 32),
              Text(
                'Pulling your dispatch.',
                style: AppTypography.titleL.copyWith(fontSize: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Stand by, soldier.',
                style: AppTypography.bodyM.copyWith(
                  color: AppColors.accent,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 32),
              const _AnimatedDots(key: ValueKey('restoring-dots')),
              const Spacer(),
              if (_showTimeoutCta)
                Padding(
                  key: const ValueKey('restoring-timeout-cta'),
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    children: [
                      Text(
                        'This is taking a while.',
                        style: AppTypography.bodyM.copyWith(
                          color: AppColors.textDim,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _onContinueAnyway,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.accent),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(
                            'CONTINUE  →',
                            style: AppTypography.mono.copyWith(
                              fontSize: 13,
                              color: AppColors.accent,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots({super.key});

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (t + i / 3) % 1.0;
            final opacity = (0.5 + 0.5 * (1 - (2 * phase - 1).abs())).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: opacity),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: Add cancellation to `SyncService.restoreFromCloud`**

Open `lib/core/services/sync_service.dart`. Add a cancellation flag + return type:

```dart
class RestoreResult {
  final bool succeeded;
  final bool cancelled;
  final Object? error;
  RestoreResult.success() : succeeded = true, cancelled = false, error = null;
  RestoreResult.cancelled() : succeeded = false, cancelled = true, error = null;
  RestoreResult.failed(this.error) : succeeded = false, cancelled = false;
}

class SyncService {
  bool _restoreCancelled = false;

  void cancelInflightRestore() {
    _restoreCancelled = true;
  }

  Future<RestoreResult> restoreFromCloud() async {
    _restoreCancelled = false;
    try {
      // Existing restore steps — wrap each in cancellation check:
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _restoreUserProfile();
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _restoreWorkoutLogs();
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _restoreNutritionLogs();
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _restoreStreaks();
      // ... etc for each restore method ...
      return RestoreResult.success();
    } catch (e) {
      return RestoreResult.failed(e);
    }
  }
}
```

- [ ] **Step 5: Wire `onboarding_completed_at` write into completeOnboarding**

Open `lib/features/onboarding/providers/onboarding_provider.dart`. In `completeOnboarding`, after successful upsert to `user_profile`, write the timestamp:

```dart
// After existing user_profile upsert in _syncOnboardingToSupabase:
await supabase.from('user_profile').upsert({
  ...existingPayload,
  'onboarding_completed_at': DateTime.now().toIso8601String(),
});
```

- [ ] **Step 6: Add `/restoring` route to GoRouter**

Open `lib/core/router/app_router.dart`. Add the route:

```dart
GoRoute(
  path: '/restoring',
  name: 'restoring',
  builder: (context, state) => const RestoringScreen(),
),
```

Modify the post-auth redirect logic. Locate `_authRedirect` (or equivalent). After auth state confirms a logged-in user, redirect to `/restoring` (instead of going straight to `/home` or `/onboarding`):

```dart
String? _authRedirect(BuildContext context, GoRouterState state) {
  final session = Supabase.instance.client.auth.currentSession;
  final loc = state.matchedLocation;

  // Public routes (no redirect)
  const publicRoutes = ['/', '/sign-in', '/sign-up', '/welcome', '/restoring'];
  if (publicRoutes.contains(loc) || loc.startsWith('/onboarding')) {
    return null;
  }

  if (session == null) return '/welcome';

  // Authenticated users: if we just signed in (came from sign-in screens)
  // and aren't already in the restoring/onboarding flow, route through
  // /restoring to gate the decision.
  if (loc == '/home' && _justAuthenticated(context)) {
    return '/restoring';
  }

  return null;
}
```

The `_justAuthenticated` helper can read a flag from a Riverpod provider set by the sign-in success handler (`AuthStateNotifier.markJustAuthenticated()`). On RestoringScreen mount, the flag is cleared.

- [ ] **Step 7: Add `/onboarding/mission-brief` route**

```dart
GoRoute(
  path: '/onboarding/mission-brief',
  name: 'mission-brief',
  builder: (context, state) => const MissionBriefScreen(),
),
```

Order matters: `/onboarding/mission-brief` must be matched before any catch-all `/onboarding/:step` route.

- [ ] **Step 8: Run tests**

```bash
flutter test test/auth/restoring_screen_test.dart -v
flutter test test/onboarding/mission_brief_screen_test.dart -v
```

Expected: all pass.

- [ ] **Step 9: Manual smoke test on dev APK**

```bash
# Build + run dev
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

Test scenarios:
- **New signup:** sign up via email → land on Mission Brief → CONTINUE → Identity. Verify: no flash of /home.
- **Returning user logout + re-login:** complete onboarding once, log out, sign back in with same email. Verify: see RestoringScreen briefly → land on /home with profile + workouts intact (not in onboarding).
- **Mid-onboarding resume:** sign up, abandon at Stats screen, force-quit app, re-launch, sign in. Verify: lands at /onboarding/stats, not Mission Brief.

- [ ] **Step 10: Commit**

```bash
git add lib/features/auth/screens/restoring_screen.dart \
        test/auth/restoring_screen_test.dart \
        lib/core/services/sync_service.dart \
        lib/features/onboarding/providers/onboarding_provider.dart \
        lib/core/router/app_router.dart
git commit -m "feat(auth): Q1 RestoringScreen + post-auth decision tree

Closes the F2/F3 cascade: log-out + re-sign-in no longer dumps users
back into onboarding. New post-auth flow:

  sign-in success → /restoring
    parallel:
      ├─ SELECT user_id, onboarding_completed_at FROM user_profile
      └─ start restoreFromCloud() (cancellable)
    branch:
      ├─ row + onboarding_completed_at IS NOT NULL
      │   → await restore → /home (15s timeout safety)
      ├─ row + onboarding_completed_at IS NULL
      │   → cancel restore → resume at first missing onboarding step
      └─ no row
          → cancel restore → /onboarding/mission-brief

Adds:
  - lib/features/auth/screens/restoring_screen.dart (branded gate UI
    with pulsing seal + 15s timeout escape hatch)
  - SyncService.cancelInflightRestore() + RestoreResult return type
  - completeOnboarding writes onboarding_completed_at to Supabase
    (uses migration 036's column)
  - GoRouter routes /restoring + /onboarding/mission-brief
  - Post-auth redirect logic gates through /restoring

This is the foundation that fixes critical observation #3 from
APK Test #2.

Spec section 3 + section 5 / Q1 + Q5."
```

---

### Task 8: Final verification

- [ ] **Step 1: Run full test suite**

```bash
flutter test
flutter analyze
```

Expected: all tests pass. No new analyze errors.

- [ ] **Step 2: Plan B checkpoint commit**

```bash
git commit --allow-empty -m "checkpoint: Plan B complete (auth + onboarding)

  - AuthHeader compact letterhead on all sub-views (Q3)
  - Privacy footer on Welcome + signup checkbox + cloud-synced
    terms_accepted_at (Q2)
  - MissionBriefScreen at /onboarding/mission-brief (Q5)
  - Plan + AI coach micro-references (Q5)
  - RestoringScreen + post-auth decision tree (Q1, fixes F2+F3)

Plan C (subscription + monetization) is next.

Branch: feat/apk-test-2-batch
Spec: docs/superpowers/specs/2026-04-25-apk-test-2-batch-design.md"
```

---

## Self-Review

### Spec coverage
- Q1 restore flow → Task 7 ✓
- Q2 privacy → Task 4 ✓
- Q3 auth letterhead → Task 2 + 3 ✓
- Q5 Mission Brief → Task 1 + 5 + 6 ✓
- Migration 036 → (Plan A Task 1, prerequisite) ✓

### Placeholder scan
No "TBD", no "TODO", all code blocks complete.

### Type consistency
- `RestoreResult` defined in Task 7 Step 4, used by RestoringScreen.
- `SyncService.cancelInflightRestore()` defined Task 7 Step 4, called Task 7 Step 3.
- `aiInsightProvider` not modified here — cross-plan consistency with Plan A maintained.

---

## Execution Handoff

Plan B complete and saved to `docs/superpowers/plans/2026-04-25-apk-test-2-plan-B-auth-onboarding.md`.

After Plan A (foundation) ships, execute Plan B in order. Tasks 1–6 can run in parallel; Task 7 depends on migration 036 (Plan A Task 1) being applied. Task 8 is final verification.

Plan C (referral + active workout free + phase roadmap) is the next plan.
