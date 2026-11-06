# APK Test #7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 7 bugs surfaced in APK Test #7 on-device testing (double name, freeze duplicate, wrong rank pledge, missing Mission Brief, calorie drift, disconnected profile cards) and add a new AVYA section in Profile.

**Architecture:** All fixes are surgical — 7 files touched, no new widgets except the `readOnly` param on `MissionBriefScreen`. The AVYA profile section reuses existing `ProfileRow` + `_buildCard` primitives. The `/avya/promise` route is added outside the `/onboarding/` namespace so `_authRedirect` does not redirect onboarded users away from it.

**Tech Stack:** Flutter, GoRouter, Riverpod, Hive, url_launcher. Tests use `dart:io` source-code verification (the established pattern in `test/router/`).

---

## File Map

| File | What changes |
|---|---|
| `lib/features/home/screens/home_screen.dart` | Fix 7: remove `$firstName` from title |
| `lib/shared/widgets/wardroom/ward_status_strip.dart` | Fix 6: pass real freezes to StreakBadge, remove WardFreezeBadge |
| `lib/features/ai_coach/screens/induction_screen.dart` | Fix 5: Sub Lieutenant + 104 workouts + six months |
| `lib/features/onboarding/screens/welcome_screen.dart` | Fix 1: route to `/onboarding/mission-brief` |
| `lib/features/onboarding/screens/mission_brief_screen.dart` | Fix 1 errorBuilder; Fix 8a: `readOnly` param |
| `lib/core/router/app_router.dart` | Fix 8b: add `/avya/promise` route |
| `lib/features/profile/screens/profile_screen.dart` | Fix 4+3: consolidate REPORTS; Fix 8c: AVYA section |

---

### Task 1: Fix 7 — Remove double name from home header

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart:227`
- Test: `test/home/home_header_title_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/home/home_header_title_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/home/screens/home_screen.dart').readAsStringSync();
  });

  test('home header title must not embed firstName after greeting', () {
    expect(
      src.contains(r"'$greeting, $firstName.'"),
      isFalse,
      reason: 'greeting already contains the name — doubling it wraps to 3 lines',
    );
  });

  test('home header title ends with greeting + period only', () {
    expect(
      src.contains(r"title: '$greeting.'"),
      isTrue,
      reason: 'title should be the greeting sentence closed with a period',
    );
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```
flutter test test/home/home_header_title_test.dart
```

Expected: 1 or 2 FAILs ("greeting already contains the name").

- [ ] **Step 3: Apply the fix**

In `lib/features/home/screens/home_screen.dart` find and replace the title line (currently around line 227):

```dart
// BEFORE
title: '$greeting, $firstName.',

// AFTER
title: '$greeting.',
```

- [ ] **Step 4: Run test to confirm it passes**

```
flutter test test/home/home_header_title_test.dart
```

Expected: 2 PASSes.

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/screens/home_screen.dart test/home/home_header_title_test.dart
git commit -m "fix(home): remove duplicate firstName from greeting title"
```

---

### Task 2: Fix 6 — Streak freeze duplicate in WardStatusStrip

**Files:**
- Modify: `lib/shared/widgets/wardroom/ward_status_strip.dart`
- Test: `test/widgets/ward_status_strip_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/widgets/ward_status_strip_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/shared/widgets/wardroom/ward_status_strip.dart')
        .readAsStringSync();
  });

  test('WardFreezeBadge must not appear in WardStatusStrip', () {
    expect(
      src.contains('WardFreezeBadge'),
      isFalse,
      reason: 'StreakBadge already renders the inline freeze count — '
          'a second WardFreezeBadge produces a duplicate display',
    );
  });

  test('StreakBadge receives the real freezesAvailable value', () {
    expect(
      src.contains('freezesAvailable: freezesAvailable'),
      isTrue,
      reason: 'hardcoded 0 hid the freeze count inside the streak pill',
    );
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```
flutter test test/widgets/ward_status_strip_test.dart
```

Expected: 2 FAILs.

- [ ] **Step 3: Apply the fix**

In `lib/shared/widgets/wardroom/ward_status_strip.dart`, the `build` method's `children` list currently reads:

```dart
children: [
  StreakBadge(
    days: streakDays,
    freezesAvailable: 0,
  ),
  WardFreezeBadge(count: freezesAvailable),
  ?rankChip,
],
```

Replace with:

```dart
children: [
  StreakBadge(
    days: streakDays,
    freezesAvailable: freezesAvailable,
  ),
  ?rankChip,
],
```

Also remove the `ward_freeze_badge.dart` import at the top of the file (line 4):

```dart
// DELETE this line:
import 'ward_freeze_badge.dart';
```

- [ ] **Step 4: Run test + full suite**

```
flutter test test/widgets/ward_status_strip_test.dart
flutter analyze lib/shared/widgets/wardroom/ward_status_strip.dart
```

Expected: 2 PASSes, 0 analysis errors.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/wardroom/ward_status_strip.dart test/widgets/ward_status_strip_test.dart
git commit -m "fix(streak): remove duplicate WardFreezeBadge from WardStatusStrip"
```

---

### Task 3: Fix 5 — Induction pledge: Sub Lieutenant + 104 workouts

**Files:**
- Modify: `lib/features/ai_coach/screens/induction_screen.dart:236,248`
- Test: `test/ai_coach/induction_pledge_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ai_coach/induction_pledge_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/screens/induction_screen.dart')
        .readAsStringSync();
  });

  test('pledge must reference Sub Lieutenant, not Lieutenant Commander', () {
    expect(src.contains('Lieutenant Commander rank'), isFalse,
        reason: 'Sub Lieutenant (W104) is the first officer commission');
    expect(src.contains('Sub Lieutenant rank'), isTrue);
  });

  test('pledge must reference 104 workouts, not 200', () {
    expect(src.contains('200 workouts'), isFalse);
    expect(src.contains('104 workouts'), isTrue);
  });

  test('pledge must reference six months, not twelve', () {
    expect(src.contains('twelve months'), isFalse);
    expect(src.contains('six months'), isTrue);
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```
flutter test test/ai_coach/induction_pledge_test.dart
```

Expected: 3 FAILs.

- [ ] **Step 3: Apply the fix**

In `lib/features/ai_coach/screens/induction_screen.dart`, find and replace two spans (around lines 236 and 248):

**Change 1 — pledge headline:**
```dart
// BEFORE
'Make Lieutenant Commander rank — 200 workouts on this app — and your life '

// AFTER
'Make Sub Lieutenant rank — 104 workouts on this app — and your life '
```

**Change 2 — explanatory sentence:**
```dart
// BEFORE
'200 workouts is roughly twelve months of disciplined training. Most don\'t '

// AFTER
'104 workouts is roughly six months of disciplined training. Most don\'t '
```

- [ ] **Step 4: Run test + analyze**

```
flutter test test/ai_coach/induction_pledge_test.dart
flutter analyze lib/features/ai_coach/screens/induction_screen.dart
```

Expected: 3 PASSes, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_coach/screens/induction_screen.dart test/ai_coach/induction_pledge_test.dart
git commit -m "fix(induction): correct rank pledge to Sub Lieutenant + 104 workouts"
```

---

### Task 4: Fix 1 — Mission Brief routing in welcome screen

**Files:**
- Modify: `lib/features/onboarding/screens/welcome_screen.dart:195`
- Test: `test/router/mission_brief_routing_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/router/mission_brief_routing_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String welcomeSrc;

  setUpAll(() {
    welcomeSrc = File('lib/features/onboarding/screens/welcome_screen.dart')
        .readAsStringSync();
  });

  test('BEGIN ENLISTMENT must route to mission-brief, not identity', () {
    expect(
      welcomeSrc.contains("go('/onboarding/identity')"),
      isFalse,
      reason: 'Direct jump to identity skips RestoringScreen and Mission Brief',
    );
    expect(
      welcomeSrc.contains("go('/onboarding/mission-brief')"),
      isTrue,
      reason: 'New users must see the Mission Brief before Identity step',
    );
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```
flutter test test/router/mission_brief_routing_test.dart
```

Expected: 1 FAIL.

- [ ] **Step 3: Apply the fix**

In `lib/features/onboarding/screens/welcome_screen.dart`, around line 195, inside the `_cta` method:

```dart
// BEFORE
onTap: () => context.go('/onboarding/identity'),

// AFTER
onTap: () => context.go('/onboarding/mission-brief'),
```

- [ ] **Step 4: Run test + analyze**

```
flutter test test/router/mission_brief_routing_test.dart
flutter analyze lib/features/onboarding/screens/welcome_screen.dart
```

Expected: 1 PASS, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/onboarding/screens/welcome_screen.dart test/router/mission_brief_routing_test.dart
git commit -m "fix(onboarding): BEGIN ENLISTMENT routes to Mission Brief before Identity"
```

---

### Task 5: Fix 8a — MissionBriefScreen readOnly mode

**Files:**
- Modify: `lib/features/onboarding/screens/mission_brief_screen.dart`
- Test: `test/onboarding/mission_brief_readonly_test.dart`

Context: When a user navigates to `/avya/promise` from Profile, they should see the Mission Brief content with a back arrow but without the `CONTINUE →` button. The `readOnly` param controls both.

- [ ] **Step 1: Write the failing test**

Create `test/onboarding/mission_brief_readonly_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/onboarding/screens/mission_brief_screen.dart')
        .readAsStringSync();
  });

  test('MissionBriefScreen declares readOnly parameter', () {
    expect(src.contains('readOnly'), isTrue,
        reason: 'readOnly param needed to suppress CONTINUE when opened from Profile');
  });

  test('CONTINUE button is conditional on readOnly being false', () {
    expect(src.contains('if (!readOnly)'), isTrue,
        reason: 'CONTINUE button must be hidden when readOnly = true');
  });

  test('AppBar is conditional on readOnly', () {
    expect(src.contains('readOnly\n') || src.contains('readOnly ?'), isTrue,
        reason: 'back arrow AppBar must only appear in readOnly mode');
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```
flutter test test/onboarding/mission_brief_readonly_test.dart
```

Expected: 3 FAILs.

- [ ] **Step 3: Apply the fix**

Replace the entire `MissionBriefScreen` class declaration and build method in `lib/features/onboarding/screens/mission_brief_screen.dart`.

**Change the class declaration** (was `const MissionBriefScreen({super.key});`):

```dart
class MissionBriefScreen extends ConsumerWidget {
  const MissionBriefScreen({super.key, this.readOnly = false});

  final bool readOnly;
```

**Add conditional AppBar** — the `build` method currently returns a `Scaffold` with no `appBar`. Replace the Scaffold opening:

```dart
// BEFORE
return Scaffold(
  backgroundColor: AppColors.bg,
  body: SafeArea(

// AFTER
return Scaffold(
  backgroundColor: AppColors.bg,
  appBar: readOnly
      ? AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: AppColors.textPrimary, size: 20),
            onPressed: () => context.pop(),
          ),
        )
      : null,
  body: SafeArea(
```

**Make the CONTINUE button conditional** — currently the button is the last child in the Column. Wrap it:

```dart
// BEFORE
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

// AFTER
              if (!readOnly)
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
```

**Add errorBuilder to the founder photo** — currently `Image.asset('assets/founder/upendra.jpg', key: ..., fit: BoxFit.cover)`. Add:

```dart
// BEFORE
                    child: Image.asset(
                      'assets/founder/upendra.jpg',
                      key: const ValueKey('founder-photo'),
                      fit: BoxFit.cover,
                    ),

// AFTER
                    child: Image.asset(
                      'assets/founder/upendra.jpg',
                      key: const ValueKey('founder-photo'),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppColors.card,
                        child: const Icon(Icons.person,
                            color: AppColors.textMute, size: 40),
                      ),
                    ),
```

- [ ] **Step 4: Run test + analyze**

```
flutter test test/onboarding/mission_brief_readonly_test.dart
flutter analyze lib/features/onboarding/screens/mission_brief_screen.dart
```

Expected: 3 PASSes, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/onboarding/screens/mission_brief_screen.dart test/onboarding/mission_brief_readonly_test.dart
git commit -m "feat(mission-brief): add readOnly mode with back arrow + hide CONTINUE"
```

---

### Task 6: Fix 8b + 8c — /avya/promise route + AVYA profile section

**Files:**
- Modify: `lib/core/router/app_router.dart` (add route)
- Modify: `lib/features/profile/screens/profile_screen.dart` (add AVYA section)
- Test: `test/router/avya_promise_route_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/router/avya_promise_route_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String routerSrc;
  late String profileSrc;

  setUpAll(() {
    routerSrc = File('lib/core/router/app_router.dart').readAsStringSync();
    profileSrc =
        File('lib/features/profile/screens/profile_screen.dart').readAsStringSync();
  });

  group('/avya/promise route', () {
    test('route path is declared in app_router', () {
      expect(routerSrc.contains("path: '/avya/promise'"), isTrue);
    });

    test('route name avyaPromise is declared', () {
      expect(routerSrc.contains("name: 'avyaPromise'"), isTrue);
    });

    test('route renders MissionBriefScreen with readOnly: true', () {
      expect(
        routerSrc.contains('MissionBriefScreen(readOnly: true)'),
        isTrue,
      );
    });
  });

  group('AVYA profile section', () {
    test("AVYA section header is present", () {
      expect(profileSrc.contains("SectionHeader('AVYA')"), isTrue);
    });

    test("AVYA'S PROMISE row navigates to /avya/promise", () {
      expect(profileSrc.contains("go('/avya/promise')"), isTrue);
    });

    test('icanbefitter.com row is present', () {
      expect(profileSrc.contains('icanbefitter.com'), isTrue);
    });

    test('@icanbefitter Instagram row is present', () {
      expect(profileSrc.contains('@icanbefitter'), isTrue);
      expect(profileSrc.contains('instagram://user?username=icanbefitter'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```
flutter test test/router/avya_promise_route_test.dart
```

Expected: 7 FAILs.

- [ ] **Step 3a: Add the route in app_router.dart**

In `lib/core/router/app_router.dart`, find the existing mission-brief route (around lines 110–125):

```dart
      GoRoute(
        path: '/onboarding/mission-brief',
        name: 'missionBrief',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MissionBriefScreen(),
          ...
        ),
      ),
```

Insert the new route immediately after the closing `),` of that GoRoute:

```dart
      // ── AVYA Promise — revisit Mission Brief from Profile ──────────
      // Outside /onboarding/ namespace so _authRedirect does not bounce
      // onboarded users back to /home.
      GoRoute(
        path: '/avya/promise',
        name: 'avyaPromise',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MissionBriefScreen(readOnly: true),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      ),
```

No new import is needed — `MissionBriefScreen` is already imported at line 9 of app_router.dart.

- [ ] **Step 3b: Add the AVYA section in profile_screen.dart**

In `lib/features/profile/screens/profile_screen.dart`, find the gap between the SETTINGS card and the SUBSCRIPTION section (around lines 836–842):

```dart
              ]),
              const SizedBox(height: 12),

              // Bug #14 — Subscription moved to the bottom
              const SectionHeader('SUBSCRIPTION'),
```

Insert the AVYA section between the `SizedBox(height: 12)` and `SectionHeader('SUBSCRIPTION')`:

```dart
              ]),
              const SizedBox(height: 12),

              const SectionHeader('AVYA'),
              _buildCard([
                ProfileRow(
                  icon: Icons.shield_outlined,
                  iconColor: AppColors.accent,
                  title: "AVYA'S PROMISE",
                  subtitle: 'The mission brief — why this exists',
                  trailing: const ProfileRowChevron(),
                  showBorder: true,
                  onTap: () => context.go('/avya/promise'),
                ),
                ProfileRow(
                  icon: Icons.language_outlined,
                  title: 'icanbefitter.com',
                  subtitle: 'The full platform',
                  trailing: const ProfileRowChevron(),
                  showBorder: true,
                  onTap: () => _launchUrl('https://icanbefitter.com'),
                ),
                ProfileRow(
                  icon: Icons.camera_alt_outlined,
                  title: '@icanbefitter',
                  subtitle: 'Daily wins on Instagram',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: () async {
                    final native =
                        Uri.parse('instagram://user?username=icanbefitter');
                    if (await canLaunchUrl(native)) {
                      await launchUrl(native);
                    } else {
                      await _launchUrl('https://instagram.com/icanbefitter');
                    }
                  },
                ),
              ]),
              const SizedBox(height: 12),

              // Bug #14 — Subscription moved to the bottom
              const SectionHeader('SUBSCRIPTION'),
```

`canLaunchUrl` is from `url_launcher` which is already imported in profile_screen.dart (line 28).

- [ ] **Step 4: Run test + analyze both files**

```
flutter test test/router/avya_promise_route_test.dart
flutter analyze lib/core/router/app_router.dart lib/features/profile/screens/profile_screen.dart
```

Expected: 7 PASSes, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/profile/screens/profile_screen.dart test/router/avya_promise_route_test.dart
git commit -m "feat(profile): add AVYA section with Mission Brief + website + Instagram links"
```

---

### Task 7: Fix 4 — Consolidate REPORTS into a single card

**Files:**
- Modify: `lib/features/profile/screens/profile_screen.dart` (REPORTS section, ~lines 597–666)
- Test: `test/profile/reports_section_consolidated_test.dart`

Context: Currently three separate `_buildCard` calls (Predictions, Progress Comparison, Progress Photos) produce three floating islands. `WeeklyReportCard` stays as its own widget above the merged three-row card. This is the same single-card pattern already used by SHARE & GROW and SETTINGS.

- [ ] **Step 1: Write the failing test**

Create `test/profile/reports_section_consolidated_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/profile/screens/profile_screen.dart')
        .readAsStringSync();
  });

  test('Progress Comparison and Progress Photos share a _buildCard with Predictions', () {
    // After consolidation, the block containing 'Progress Comparison' and
    // 'Progress Photos' must NOT be preceded by a separate standalone _buildCard
    // on its own line. The simplest proxy: confirm there is no isolated
    // _buildCard wrapping only the Progress Comparison ProfileRow.
    final isolatedCompare = RegExp(
      r'_buildCard\(\s*\[\s*ProfileRow\([^)]*Progress Comparison',
      dotAll: true,
    );
    expect(
      isolatedCompare.hasMatch(src),
      isFalse,
      reason: 'Progress Comparison must share a _buildCard with other REPORTS rows',
    );
  });

  test('Predictions, Progress Comparison, and Progress Photos all appear inside one Builder block', () {
    // The merged Builder(...) block must contain all three row titles.
    final builderBlock = RegExp(
      r'Builder\(builder: \(ctx\) \{.*?Predictions.*?Progress Comparison.*?Progress Photos.*?\}\)',
      dotAll: true,
    );
    expect(
      builderBlock.hasMatch(src),
      isTrue,
      reason: 'All three REPORTS rows must be inside the same Builder(_buildCard) block',
    );
  });

  test('No SizedBox(height: 6) separates individual REPORTS items', () {
    // Proxy: WeeklyReportCard should be followed by SizedBox(height: 8) not 6.
    expect(
      src.contains('WeeklyReportCard') &&
          !src.contains('const SizedBox(height: 6),\n              Builder('),
      isTrue,
      reason: 'Height-6 gaps between individual REPORTS cards must be gone',
    );
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```
flutter test test/profile/reports_section_consolidated_test.dart
```

Expected: at least 2 FAILs.

- [ ] **Step 3: Apply the consolidation**

In `lib/features/profile/screens/profile_screen.dart`, replace the entire REPORTS section (from `const SectionHeader('REPORTS'),` through the final `const SizedBox(height: 8),` before SHARE & GROW):

**BEFORE** (lines ~597–666):
```dart
              const SectionHeader('REPORTS'),
              Builder(builder: (ctx) {
                final prediction = ref.watch(predictionProvider);
                return _buildCard([
                  ProfileRow(
                    icon: Icons.auto_awesome_outlined,
                    iconColor: AppColors.accent,
                    title: 'Predictions',
                    subtitle: _truncatedPredictionPreview(prediction),
                    trailing: const ProfileRowChevron(),
                    showBorder: false,
                    onTap: () => _showPredictionBottomSheet(ctx),
                  ),
                ]);
              }),
              const SizedBox(height: 6),
              WeeklyReportCard(
                isPro: subInfo.isPro,
                usageWeeks: usageWeeks,
                hasFirstReport: firstReportViewed,
                onViewReport: () {
                  if (!firstReportViewed) {
                    ref.read(firstReportViewedProvider.notifier).markViewed();
                  }
                  context.go('/profile/reports');
                },
                onUpgradeTap: () {
                  SubscriptionService.instance.gate(
                    AppConstants.featureWeeklyAiReport,
                    onPro: () => context.go('/profile/reports'),
                    onFree: () => showPaywallSheet(context, feature: 'Weekly AI Report'),
                  );
                },
              ),
              const SizedBox(height: 6),
              _buildCard([
                ProfileRow(
                  icon: Icons.compare_arrows_outlined,
                  title: 'Progress Comparison',
                  subtitle: 'Then vs now — starting stats and milestones',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: () => context.go('/profile/progress-comparison'),
                ),
              ]),
              const SizedBox(height: 6),
              _buildCard([
                ProfileRow(
                  icon: Icons.photo_library_outlined,
                  title: 'Progress Photos',
                  subtitle: subInfo.isPro
                      ? 'Track your transformation visually'
                      : 'PRO — visual progress timeline',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: () => SubscriptionService.instance.gate(
                    AppConstants.featureProgressPhotos,
                    onPro: () => context.go('/profile/progress-photos'),
                    onFree: () =>
                        showPaywallSheet(context, feature: 'Progress Photos'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
```

**AFTER**:
```dart
              const SectionHeader('REPORTS'),
              WeeklyReportCard(
                isPro: subInfo.isPro,
                usageWeeks: usageWeeks,
                hasFirstReport: firstReportViewed,
                onViewReport: () {
                  if (!firstReportViewed) {
                    ref.read(firstReportViewedProvider.notifier).markViewed();
                  }
                  context.go('/profile/reports');
                },
                onUpgradeTap: () {
                  SubscriptionService.instance.gate(
                    AppConstants.featureWeeklyAiReport,
                    onPro: () => context.go('/profile/reports'),
                    onFree: () => showPaywallSheet(context, feature: 'Weekly AI Report'),
                  );
                },
              ),
              const SizedBox(height: 8),
              Builder(builder: (ctx) {
                final prediction = ref.watch(predictionProvider);
                return _buildCard([
                  ProfileRow(
                    icon: Icons.auto_awesome_outlined,
                    iconColor: AppColors.accent,
                    title: 'Predictions',
                    subtitle: _truncatedPredictionPreview(prediction),
                    trailing: const ProfileRowChevron(),
                    showBorder: true,
                    onTap: () => _showPredictionBottomSheet(ctx),
                  ),
                  ProfileRow(
                    icon: Icons.compare_arrows_outlined,
                    title: 'Progress Comparison',
                    subtitle: 'Then vs now — starting stats and milestones',
                    trailing: const ProfileRowChevron(),
                    showBorder: true,
                    onTap: () => context.go('/profile/progress-comparison'),
                  ),
                  ProfileRow(
                    icon: Icons.photo_library_outlined,
                    title: 'Progress Photos',
                    subtitle: subInfo.isPro
                        ? 'Track your transformation visually'
                        : 'PRO — visual progress timeline',
                    trailing: const ProfileRowChevron(),
                    showBorder: false,
                    onTap: () => SubscriptionService.instance.gate(
                      AppConstants.featureProgressPhotos,
                      onPro: () => context.go('/profile/progress-photos'),
                      onFree: () =>
                          showPaywallSheet(context, feature: 'Progress Photos'),
                    ),
                  ),
                ]);
              }),
              const SizedBox(height: 8),
```

Key changes:
- `WeeklyReportCard` moves to the top of the section (was second).
- The three `ProfileRow` items (Predictions, Progress Comparison, Progress Photos) are merged into one `Builder(_buildCard([...]))`.
- `showBorder: false` → `showBorder: true` on the first two rows (so dividers appear between them).
- Three `SizedBox(height: 6)` inter-card gaps are gone; one `SizedBox(height: 8)` between WeeklyReportCard and the merged card.

- [ ] **Step 4: Run test + full analyze**

```
flutter test test/profile/reports_section_consolidated_test.dart
flutter analyze lib/features/profile/screens/profile_screen.dart
```

Expected: 3 PASSes, 0 analysis errors.

- [ ] **Step 5: Run the full test suite**

```
flutter test
```

Expected: all existing tests pass (863+). No regressions.

- [ ] **Step 6: Commit**

```bash
git add lib/features/profile/screens/profile_screen.dart test/profile/reports_section_consolidated_test.dart
git commit -m "fix(profile): consolidate REPORTS into single card + fix spacing"
```

---

## Post-plan checks

After all 7 tasks are committed:

- [ ] **Smoke: `flutter analyze`** — zero errors/warnings across all modified files.
- [ ] **Full test suite** — `flutter test` — all tests pass.
- [ ] **Verify Fix 2 (calorie sync) is resolved** — since Fix 1 is in place, a fresh sign-up via `welcome_screen.dart` → `mission_brief_screen.dart` → `identity_screen.dart` → ... → `plan_screen.dart` will carry complete `widget.data` to `_computeTargets`, eliminating the preview/saved discrepancy. No code needed — confirm by tracing the route.

---

## Self-review notes

**Spec coverage:** All 8 spec items covered:
- Fix 1 → Task 4 + Task 5 (errorBuilder)
- Fix 2 → documented as self-resolving, no task needed
- Fix 3 → addressed implicitly by Task 7 (removing height-6 gaps + WeeklyReportCard move)
- Fix 4 → Task 7
- Fix 5 → Task 3
- Fix 6 → Task 2
- Fix 7 → Task 1
- Fix 8a/b/c → Tasks 5, 6

**Type/name consistency check:**
- `MissionBriefScreen(readOnly: true)` used in Task 5 definition and Task 6 router — matches.
- `_buildCard`, `ProfileRow`, `ProfileRowChevron`, `SectionHeader` — all existing symbols in `profile_screen.dart`, confirmed present.
- `_launchUrl(url)` — exists at line 2134-2135 of profile_screen.dart, matches usage in Task 6.
- `canLaunchUrl` — from `url_launcher`, already imported in profile_screen.dart.
- `AppColors.accent`, `AppColors.bg`, `AppColors.textPrimary`, `AppColors.textMute`, `AppColors.card` — all defined in `colors.dart`.

**No placeholders** — every step has actual code.
