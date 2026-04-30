# APK Test #4 Hotfix Plan D — UX Large (U7, U9)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two large UX redesigns — unified tab headers across all 5 tabs (U7) + welcome screen premium/military redesign Direction B (U9). Plus versionCode bump 1.0.0+2 → 1.0.0+3 as last task.

**Architecture:** U7 introduces a new `WardTabHeader` widget shared across all 5 tab screens; rank chip pulls into a separate row below the header for consistent Y-position across tabs. U9 is targeted edits to `sign_in_screen.dart` welcome view per Direction B specifics from the spec.

**Spec reference:** `docs/superpowers/specs/2026-04-28-apk-test-4-hotfix-batch-design.md` §3 U7/U9.

**Estimated effort:** 10-14h.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `lib/shared/widgets/wardroom/ward_tab_header.dart` | CREATE | New unified tab header widget |
| `lib/shared/widgets/wardroom/wardroom.dart` | MODIFY | Export WardTabHeader from barrel |
| `lib/features/home/screens/home_screen.dart` | MODIFY | Use WardTabHeader (eyebrow: DAILY BRIEF) |
| `lib/features/train/screens/train_screen.dart` | MODIFY | Use WardTabHeader (eyebrow: TRAIN) |
| `lib/features/nutrition/screens/nutrition_screen.dart` | MODIFY | Use WardTabHeader (eyebrow: FUEL) |
| `lib/features/ai_coach/screens/ai_coach_screen.dart` | MODIFY | Use WardTabHeader (eyebrow: DISPATCH) |
| `lib/features/profile/screens/profile_screen.dart` | MODIFY | Use WardTabHeader (eyebrow: DOSSIER) |
| `lib/features/auth/screens/sign_in_screen.dart` | MODIFY | Welcome view redesign per Direction B |
| `pubspec.yaml` | MODIFY | versionCode bump |

---

## Task D-1 — Create WardTabHeader widget

**Files:** Create `lib/shared/widgets/wardroom/ward_tab_header.dart`

- [ ] **Step 1: Look at existing patterns**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
ls lib/shared/widgets/wardroom/ | head -20
grep -n "class Ward" lib/shared/widgets/wardroom/wardroom.dart | head -10
```

- [ ] **Step 2: Create the widget**

```dart
// lib/shared/widgets/wardroom/ward_tab_header.dart
//
// Unified header used by all 5 tab screens (Daily/Workout/Nutrition/Coach/Profile).
// Provides identical structure + Y-position for the rank chip across tabs so
// the user perceives stability when navigating tabs.
//
// Structure (56dp tall):
//   [avatar 32dp] [TAB EYEBROW (mono caps gold)]  [Spacer]  [streak chip] [freeze chip]
//
// Source: APK Test #4 hotfix spec §3 U7.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class WardTabHeader extends StatelessWidget {
  /// Tab-specific eyebrow text. Captain voice, mono caps.
  /// e.g., "DAILY BRIEF", "TRAIN", "FUEL", "DISPATCH", "DOSSIER".
  final String eyebrow;

  /// First letter of user's name for the avatar circle. Defaults to "A".
  final String avatarInitial;

  /// Current streak in days. 0 hides the streak chip.
  final int streakDays;

  /// Available freezes. -1 hides the chip; 0+ shows.
  final int freezesAvailable;

  /// Optional avatar tap handler (e.g., to navigate to Profile).
  final VoidCallback? onAvatarTap;

  const WardTabHeader({
    super.key,
    required this.eyebrow,
    this.avatarInitial = 'A',
    this.streakDays = 0,
    this.freezesAvailable = -1,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          GestureDetector(
            onTap: onAvatarTap,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                avatarInitial.isEmpty ? 'A' : avatarInitial[0].toUpperCase(),
                style: AppTypography.mono.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Eyebrow text
          Expanded(
            child: Text(
              eyebrow,
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
          // Streak + freeze chips
          if (streakDays > 0) _StreakChip(days: streakDays),
          if (streakDays > 0 && freezesAvailable >= 0) const SizedBox(width: 6),
          if (freezesAvailable >= 0) _FreezeChip(count: freezesAvailable),
        ],
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int days;
  const _StreakChip({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            '$days DAYS',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _FreezeChip extends StatelessWidget {
  final int count;
  const _FreezeChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('❄', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Add to wardroom barrel**

Edit `lib/shared/widgets/wardroom/wardroom.dart`:

```dart
// Add the export (alphabetical order):
export 'ward_tab_header.dart';
```

- [ ] **Step 4: Verify**

```bash
flutter analyze lib/shared/widgets/wardroom/ward_tab_header.dart \
                lib/shared/widgets/wardroom/wardroom.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/wardroom/ward_tab_header.dart \
        lib/shared/widgets/wardroom/wardroom.dart
git commit -m "feat(wardroom): WardTabHeader widget — unified tab header (U7 prep)

56dp header row with [avatar] [tab eyebrow] [streak] [freeze]. Used by
all 5 tab screens to ensure rank chip below appears at identical Y
position across tabs (eliminates visual jump on tab switch).

Tab-specific eyebrows (Captain voice):
- DAILY BRIEF / TRAIN / FUEL / DISPATCH / DOSSIER

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task D-2 to D-6 — Apply WardTabHeader to all 5 tabs

For each tab screen, replace the existing per-screen header with `WardTabHeader` + the rank chip below.

### Pattern (apply per screen)

In each screen's `build()` method, find the top-of-screen header section and replace with:

```dart
import 'package:icanbefitter/shared/widgets/wardroom/ward_tab_header.dart';
import 'package:icanbefitter/features/profile/widgets/rank_chip.dart';  // existing

// Inside Column or whatever scaffold:
WardTabHeader(
  eyebrow: 'TAB_EYEBROW_HERE',  // see per-tab table below
  avatarInitial: _getUserFirstLetter(),
  streakDays: _streakDays(ref),  // read from existing provider
  freezesAvailable: _freezesAvailable(ref),  // read from existing provider
  onAvatarTap: () => context.go('/profile'),
),
const SizedBox(height: 8),
const RankChipFullWidth(),  // see Task D-7
const SizedBox(height: 12),
// ... existing tab content ...
```

### Per-tab eyebrow assignments

| Task | File | Eyebrow |
|---|---|---|
| D-2 | `lib/features/home/screens/home_screen.dart` | `'DAILY BRIEF'` |
| D-3 | `lib/features/train/screens/train_screen.dart` | `'TRAIN'` |
| D-4 | `lib/features/nutrition/screens/nutrition_screen.dart` | `'FUEL'` |
| D-5 | `lib/features/ai_coach/screens/ai_coach_screen.dart` | `'DISPATCH'` |
| D-6 | `lib/features/profile/screens/profile_screen.dart` | `'DOSSIER'` |

### Per-screen steps

For each tab task (D-2 through D-6):

- [ ] **Step 1: Identify the existing header to replace**

Read the top of the screen's build method. Note any tab-specific header content (e.g., Daily's "WELCOME BACK" greeting, Coach's "13 msgs left today" pill, Profile's "STRENGTH · BEGINNER" eyebrow).

- [ ] **Step 2: Decide which existing content to PRESERVE**

The unified header replaces the avatar + greeting + streak/freeze. PRESERVE any tab-specific content that's NOT just identity/streak — e.g., Coach's "messages remaining" should move to a sub-row below the rank chip, not be deleted.

- [ ] **Step 3: Apply the replacement**

Replace the existing header widget tree with the pattern above. Adapt the streak/freeze provider reads to whatever each screen already uses.

- [ ] **Step 4: Visual smoke check (manual)**

Run app, navigate to the tab. Confirm:
- Header shows: avatar + tab eyebrow + streak + freeze
- Below header: rank chip full-width
- Tab-specific content renders below
- No layout overflow / clipping
- Rank chip appears at SAME Y position when navigating to other tabs (the goal of U7)

- [ ] **Step 5: Commit**

```bash
git add lib/features/<tab>/screens/<tab>_screen.dart
git commit -m "feat(<tab>): use WardTabHeader (U7 — eyebrow: <EYEBROW>)

Tab now uses unified header pattern. Rank chip Y-position now identical
across all tabs that use this header.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

(Repeat for each of the 5 tabs as separate commits.)

---

## Task D-7 — RankChipFullWidth widget (or use existing)

**Files:** Possibly create `lib/features/profile/widgets/rank_chip_full_width.dart`, or extend an existing rank chip widget

- [ ] **Step 1: Check what exists**

```bash
grep -rn "class RankChip\|class RankPill\|class WardRankChip" lib/features/profile/ lib/shared/widgets/ | head -10
```

If a rank chip widget exists, evaluate whether it can render full-width with the same content used in image 2 (the Daily screen). If yes, USE IT. If it's compact-only, EXTEND or CREATE a full-width variant.

- [ ] **Step 2: Implement (if needed)**

Create `lib/features/profile/widgets/rank_chip_full_width.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Full-width rank chip rendered below the WardTabHeader on every tab.
/// Tap takes user to Profile → RANK card (which is now at the top of Profile).
class RankChipFullWidth extends ConsumerWidget {
  const RankChipFullWidth({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = RankService.instance.getCurrentRank();
    final daysToNext = RankService.instance.daysUntilNextRank();
    final next = RankService.instance.getNextRank();

    final summary = next == null
        ? 'TOP RANK ACHIEVED'
        : '${current.displayName.toUpperCase()} · NEXT IN $daysToNext DAYS';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Insignia circle
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.textDim, width: 1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              summary,
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/profile/widgets/rank_chip_full_width.dart
git commit -m "feat(profile): RankChipFullWidth widget for unified tab placement (U7)

Full-width rank chip rendered below WardTabHeader on every tab.
Reads from RankService.daysUntilNextRank() (extracted in B4).
Tappable — navigates to Profile.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task D-8 — Welcome screen redesign Direction B (U9)

**Files:** `lib/features/auth/screens/sign_in_screen.dart`

This is a multi-edit task. Apply ALL edits below, then test.

- [ ] **Step 1: Unify all 3 auth buttons to dark+gold-outline**

Find the 3 auth buttons (CONTINUE WITH GOOGLE, CONTINUE WITH PHONE, CONTINUE WITH EMAIL). Currently the Google button is white-filled. Change all 3 to identical dark+gold-outline style:

```dart
// All 3 buttons share this style:
Container(
  width: double.infinity,
  height: 52,
  decoration: BoxDecoration(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(100),
    border: Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 1.4),
  ),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      // Brand icon with accent color
      Icon(brandIcon, color: AppColors.accent, size: 18),
      const SizedBox(width: 12),
      Text(
        buttonLabel,
        style: AppTypography.mono.copyWith(
          fontSize: 13,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w800,
          color: AppColors.accent,
        ),
      ),
    ],
  ),
)
```

- [ ] **Step 2: Replace "CONTINUE WITH" → "ENLIST VIA"**

Find labels:
- "CONTINUE WITH GOOGLE" → "ENLIST VIA GOOGLE"
- "CONTINUE WITH PHONE" → "ENLIST VIA PHONE"
- "CONTINUE WITH EMAIL" → "ENLIST VIA EMAIL"

- [ ] **Step 3: Replace "Forgot password?" → "Reset access"**

Find the gold link below the auth buttons. Change:
- Text: "Forgot password?" → "RESET ACCESS"
- Style: small caps mono, letter-spacing 1.2

- [ ] **Step 4: Replace "OR" divider**

Find the divider between phone and email buttons. Change "OR" to a thin gold rule:

```dart
Row(
  children: [
    Expanded(child: Container(height: 1, color: AppColors.accent.withValues(alpha: 0.2))),
    const SizedBox(width: 12),
    Text(
      'AUX',
      style: AppTypography.mono.copyWith(
        fontSize: 9,
        letterSpacing: 2.0,
        color: AppColors.textMute,
      ),
    ),
    const SizedBox(width: 12),
    Expanded(child: Container(height: 1, color: AppColors.accent.withValues(alpha: 0.2))),
  ],
),
```

- [ ] **Step 5: Replace "AI-POWERED FITNESS & NUTRITION / BUILT FOR INDIAN LIFESTYLES"**

Find the subtitle block below the AVYA logo. Replace with:

```dart
Text(
  'FITNESS · NUTRITION · DISCIPLINE',
  textAlign: TextAlign.center,
  style: AppTypography.mono.copyWith(
    fontSize: 10,
    letterSpacing: 2.0,
    color: AppColors.accent,
  ),
),
const SizedBox(height: 6),
Text(
  'BUILT FOR INDIAN LIFESTYLES',
  textAlign: TextAlign.center,
  style: AppTypography.mono.copyWith(
    fontSize: 9,
    letterSpacing: 1.8,
    color: AppColors.textDim,
  ),
),
```

- [ ] **Step 6: Add Captain-voice manifesto line**

After the logo + subtitle block, add:

```dart
const SizedBox(height: 18),
Text(
  'Discipline. Honest data.\nTwelve months. We change the man.',
  textAlign: TextAlign.center,
  style: AppTypography.body.copyWith(
    fontSize: 13,
    height: 1.5,
    fontStyle: FontStyle.italic,
    color: AppColors.textDim,
  ),
),
```

- [ ] **Step 7: Replace "JOIN 18,866+ INDIANS..." footer**

Find the footer text. Replace:

```dart
Text(
  'ENLISTED · 18,866 SAILORS ACTIVE',
  textAlign: TextAlign.center,
  style: AppTypography.mono.copyWith(
    fontSize: 9,
    letterSpacing: 1.6,
    color: AppColors.textDim,
  ),
),
```

- [ ] **Step 8: Add mil-stamp footer**

At the very bottom of the SafeArea content:

```dart
const SizedBox(height: 12),
Text(
  'AVYA · v1.0.0+3 · ISSUED 2026',
  textAlign: TextAlign.center,
  style: AppTypography.mono.copyWith(
    fontSize: 8,
    letterSpacing: 1.4,
    color: AppColors.textMute,
  ),
),
```

(Note: versionCode `+3` matches the bump in Task D-9. If you build before D-9, use `+2` here.)

- [ ] **Step 9: Add "REGISTRATION OPEN · 2026" arc**

Below the AVYA wordmark:

```dart
const SizedBox(height: 4),
Text(
  '· REGISTRATION OPEN · 2026 ·',
  textAlign: TextAlign.center,
  style: AppTypography.mono.copyWith(
    fontSize: 8,
    letterSpacing: 1.6,
    color: AppColors.accent.withValues(alpha: 0.6),
  ),
),
```

- [ ] **Step 10: Tighten vertical spacing**

Throughout the welcome view, reduce SizedBox heights by ~20%:
- `SizedBox(height: 32)` → `24`
- `SizedBox(height: 24)` → `18`
- `SizedBox(height: 16)` → `12`

(Don't reduce below 8 unless original was tiny.)

- [ ] **Step 11: Visual smoke check**

Run app, navigate to welcome screen. Confirm:
- All 3 auth buttons identical style (dark + gold border, no white)
- Manifesto line visible below subtitle
- Mil-stamp footer at bottom
- Tighter overall spacing
- "ENLIST VIA" replaces "CONTINUE WITH"
- "AUX" replaces "OR" with thin gold rules
- "RESET ACCESS" replaces "Forgot password?"
- Premium/military feel achieved (subjective check)

- [ ] **Step 12: Commit**

```bash
git add lib/features/auth/screens/sign_in_screen.dart
git commit -m "feat(auth): welcome screen Direction B redesign (U9)

Premium/military redesign per spec §3 U9:
- All 3 auth buttons unified dark+gold-outline (no more white Google)
- 'CONTINUE WITH' → 'ENLIST VIA' (Captain voice)
- 'Forgot password?' → 'RESET ACCESS' (mono caps)
- 'OR' divider → 'AUX' with thin gold rules
- 'AI-POWERED FITNESS & NUTRITION' → 'FITNESS · NUTRITION · DISCIPLINE'
- Manifesto line: 'Discipline. Honest data. Twelve months. We change the man.'
- 'JOIN 18,866+ INDIANS' → 'ENLISTED · 18,866 SAILORS ACTIVE'
- Mil-stamp footer: 'AVYA · v1.0.0+3 · ISSUED 2026'
- Vertical spacing tightened ~20%

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task D-9 — versionCode bump 1.0.0+2 → 1.0.0+3

**Files:** `pubspec.yaml`

- [ ] **Step 1: Edit**

```yaml
# BEFORE (line 19):
version: 1.0.0+2

# AFTER:
version: 1.0.0+3
```

- [ ] **Step 2: Commit**

```bash
git add pubspec.yaml
git commit -m "chore(android): bump versionCode 1.0.0+2 → 1.0.0+3 for hotfix batch ship

Forces clean install on user's device — same versionCode would risk
Android update collision (per Test #4 install issue).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-review

- [ ] **Spec coverage:** U7 (unified headers) → D-1 through D-7. U9 (welcome redesign) → D-8. versionCode bump → D-9. ✅
- [ ] **Risk:** Plan D is the largest. D-2 through D-6 each touch a different tab screen — tab-by-tab visual smoke check is critical.
- [ ] **Placeholder scan:** D-2 through D-6 use a per-tab pattern that's repeated (not "similar to Task X"). ✅

## Out of scope for Plan D

- Bug fixes → Plans A/B
- U6/U8/U10 → Plan C
- "Welcome back, [name]" greeting on Daily — DROPPED per design decision (i): purity over identity. Identity is conveyed by the avatar + name first-letter.
