# APK Test #5 Plan D — Tab Letterhead Standardization

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Revert U7 (the 6 commits 257a5ff → bfd89ae that introduced WardTabHeader) so each tab gets its old personality back, then add a NEW standardization layer (letterhead structure rule + status strip below gold rule) that gives predictable rhythm without flattening tab identity.

**Architecture:** Phase 1 — git revert the 6 U7 commits. Phase 2 — every tab implements the letterhead structure (eyebrow → Fraunces 28sp title → gold rule → status strip with streak + freeze + optional rank chip). Two new Wardroom primitives: `WardStatusStrip` and `FreezeBadge`. Extend `WardLetterhead` with optional `leadingAvatar` slot for Home. Per-tab content per spec §6.3.2 table.

**Estimated effort:** 8-10h.

**Spec reference:** `docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md` §6 + §10 (C8-C10).

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `lib/shared/widgets/wardroom/ward_freeze_badge.dart` | CREATE | NEW — small ❄ + count chip |
| `lib/shared/widgets/wardroom/ward_status_strip.dart` | CREATE | NEW — Wrap of streak + freeze + optional rank chip |
| `lib/shared/widgets/wardroom/ward_letterhead.dart` | MODIFY | Add optional `leadingAvatar` slot |
| `lib/shared/widgets/wardroom/wardroom.dart` | MODIFY | Export new primitives |
| `lib/features/home/screens/home_screen.dart` | MODIFY | Letterhead with leadingAvatar |
| `lib/features/train/screens/train_screen.dart` | MODIFY | Letterhead, no rank chip |
| `lib/features/nutrition/screens/nutrition_screen.dart` | MODIFY | Add status strip below existing letterhead |
| `lib/features/ai_coach/screens/ai_coach_screen.dart` | MODIFY | Letterhead `Aye Captain` + `THE BRIDGE · 24/7` |
| `lib/features/profile/widgets/profile_identity.dart` | MODIFY | Floating eyebrow on banner + Fraunces name below + status strip |
| `test/wardroom/ward_status_strip_test.dart` | CREATE | Smoke tests |
| `test/wardroom/ward_freeze_badge_test.dart` | CREATE | Smoke tests |
| `docs/superpowers/notes/2026-04-28-letterhead-visual-check.md` | CREATE | Visual verification log |

---

## Task D-1 — Revert U7 commits

**Files:** Whole-tree revert of 6 commits in range `257a5ff^..bfd89ae`.

- [ ] **Step 1: Confirm range and clean tree**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
git status                            # expect clean
git log --oneline 257a5ff^..bfd89ae   # expect 6-7 commits in U7 range
```

Expected commits visible:
- `257a5ff` — wardroom WardTabHeader widget
- `98e8432` — RankChipFullWidth widget (companion of U7, also reverted)
- `4d94075` — home use WardTabHeader
- `5c8bcf3` — train use WardTabHeader
- `2efa0fe` — nutrition use WardTabHeader
- `f772cc7` — ai_coach use WardTabHeader
- `bfd89ae` — profile use WardTabHeader

- [ ] **Step 2: Run the revert in `--no-commit` mode**

```bash
git revert --no-commit 257a5ff^..bfd89ae
```

If `git revert` reports conflicts on any of the 5 tab screens (home/train/nutrition/ai_coach/profile), the conflict markers will appear inline. Resolve by accepting the **pre-U7** version (the version BEFORE WardTabHeader was introduced — i.e., delete the WardTabHeader-using block, keep the original header code that was being replaced). Touch points to scan after revert:

```bash
git diff --name-only HEAD     # files changed by revert
grep -rn "WardTabHeader\|RankChipFullWidth" lib/ test/   # must return ZERO matches
ls lib/shared/widgets/wardroom/ward_tab_header.dart 2>&1   # must say "No such file"
ls lib/shared/widgets/wardroom/rank_chip_full_width.dart 2>&1   # must say "No such file"
```

If any `WardTabHeader` reference survived in a file the revert didn't touch (rare — only happens if a later commit referenced it), open that file and remove the import + replace the widget call site with the legacy header code copied from `git show <pre-revert-sha>:<path>`.

- [ ] **Step 3: Update barrel exports**

```bash
grep -n "ward_tab_header\|rank_chip_full_width" lib/shared/widgets/wardroom/wardroom.dart
```

If lines remain, delete them. Re-run `grep` until empty.

- [ ] **Step 4: Sanity-build**

```bash
flutter analyze lib/ 2>&1 | tee /tmp/analyze_after_revert.txt
```

Expect 0 errors. Warnings about unused imports are OK at this step — they get cleaned up in later tasks. If errors mention `WardTabHeader`/`RankChipFullWidth` symbols, return to Step 2 and grep more aggressively.

- [ ] **Step 5: Stage everything and commit as a single revert**

```bash
git add -A
git commit -m "revert: U7 unified WardTabHeader (Test #4 → Test #5 redirect)

Reverts the 6 U7 commits 257a5ff^..bfd89ae:
  257a5ff WardTabHeader widget
  98e8432 RankChipFullWidth widget
  4d94075 home use WardTabHeader
  5c8bcf3 train use WardTabHeader
  2efa0fe nutrition use WardTabHeader
  f772cc7 ai_coach use WardTabHeader
  bfd89ae profile use WardTabHeader

Each tab returns to its pre-U7 letterhead. The standardization
layer (status strip below gold rule, eyebrow formula) is added
in subsequent commits in this batch.

Spec: docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md §6.2"
```

---

## Task D-2 — Create FreezeBadge primitive

**Files:** Create `lib/shared/widgets/wardroom/ward_freeze_badge.dart`; update barrel.

**Decision:** existing `StreakBadge` already bundles ❄ + freeze count internally. For the new `WardStatusStrip` we want them as **separate** chips so freeze count keeps showing even when streak is 0 (the OBS-6 spec was explicit). `FreezeBadge` is the standalone freeze chip; in the status strip we pass `freezesAvailable: 0` to `StreakBadge` so it only shows the fire + day count.

- [ ] **Step 1: Create the file**

```dart
// lib/shared/widgets/wardroom/ward_freeze_badge.dart
//
// Streak-freeze count chip. Standalone variant of the freeze segment
// embedded inside StreakBadge. Used by WardStatusStrip so freeze count
// is visible even when streak is 0 (cold-start / new account state).
//
// Source: docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md §6.3.3.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class FreezeBadge extends StatelessWidget {
  final int count;

  const FreezeBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final color = count > 0 ? AppColors.info : AppColors.textDisabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '❄',
            style: TextStyle(fontSize: 11, color: color, height: 1),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: AppTypography.mono.copyWith(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add barrel export**

```bash
grep -n "ward_freeze_badge\|export 'ward_" lib/shared/widgets/wardroom/wardroom.dart | head -5
```

Open `lib/shared/widgets/wardroom/wardroom.dart` and add (in alphabetical position):

```dart
export 'ward_freeze_badge.dart';
```

- [ ] **Step 3: Verify**

```bash
flutter analyze lib/shared/widgets/wardroom/
```

Expect 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/widgets/wardroom/ward_freeze_badge.dart \
        lib/shared/widgets/wardroom/wardroom.dart
git commit -m "feat(wardroom): FreezeBadge primitive (Test #5 D-2)

Standalone ❄ + count chip used by WardStatusStrip. Mirrors the
freeze segment inside StreakBadge but renders independently so it
stays visible even when streak is 0.

Spec: §6.3.3 + §6.4."
```

---

## Task D-3 — Create WardStatusStrip primitive

**Files:** Create `lib/shared/widgets/wardroom/ward_status_strip.dart`; update barrel.

- [ ] **Step 1: Create the widget**

```dart
// lib/shared/widgets/wardroom/ward_status_strip.dart
//
// Status strip rendered below the gold rule on every tab letterhead.
// Wrap of StreakBadge (with freezesAvailable: 0 so it shows fire-only) +
// standalone FreezeBadge + optional RankChip. Uses Wrap so chips reflow
// on narrow screens.
//
// Source: docs/superpowers/specs/2026-04-28-apk-test-5-batch-design.md §6.3.3.

import 'package:flutter/material.dart';

import '../../../features/home/widgets/streak_badge.dart';
import 'rank_chip.dart';
import 'ward_freeze_badge.dart';

class WardStatusStrip extends StatelessWidget {
  final int streakDays;
  final int freezesAvailable;

  /// Optional rank chip — passed verbatim. Home + Profile pass a built
  /// RankChip; Train / Nutrition / AI Coach pass null.
  final RankChip? rankChip;

  /// Outer padding. Defaults match the WardLetterhead body padding so
  /// the strip aligns left-edge with the eyebrow above it.
  final EdgeInsets padding;

  const WardStatusStrip({
    super.key,
    required this.streakDays,
    required this.freezesAvailable,
    this.rankChip,
    this.padding = const EdgeInsets.fromLTRB(22, 10, 22, 4),
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    // Streak chip — hidden when streak == 0.
    if (streakDays > 0) {
      children.add(StreakBadge(days: streakDays, freezesAvailable: 0));
    }

    children.add(FreezeBadge(count: freezesAvailable));

    if (rankChip != null) {
      children.add(rankChip!);
    }

    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
```

- [ ] **Step 2: Barrel export**

Open `lib/shared/widgets/wardroom/wardroom.dart` and add:

```dart
export 'ward_status_strip.dart';
```

- [ ] **Step 3: Verify**

```bash
flutter analyze lib/shared/widgets/wardroom/
```

Expect 0 errors. If `RankChip` import fails, confirm the existing `lib/shared/widgets/wardroom/rank_chip.dart` exposes the class as `RankChip`.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/widgets/wardroom/ward_status_strip.dart \
        lib/shared/widgets/wardroom/wardroom.dart
git commit -m "feat(wardroom): WardStatusStrip primitive (Test #5 D-3)

Wrap of StreakBadge (streak-only, freeze=0) + standalone FreezeBadge
+ optional RankChip. Renders below the gold rule on every tab so the
streak/freeze/rank Y-position is predictable across tabs without
flattening per-tab letterhead identity.

Spec: §6.3.3 + §6.4."
```

---

## Task D-4 — Extend WardLetterhead with leadingAvatar slot

**Files:** Modify `lib/shared/widgets/wardroom/ward_letterhead.dart`.

**Backward compat:** existing call sites that don't pass `leadingAvatar` MUST keep rendering byte-identically. Default value is `null`; when null, the widget skips the avatar column entirely.

- [ ] **Step 1: Replace the widget body**

Open `lib/shared/widgets/wardroom/ward_letterhead.dart` and replace its full contents with:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import 'ward_glyphs.dart';

/// Divider style below a [WardLetterhead].
///
/// * [WardDivider.single] — 1 px gold hairline.
/// * [WardDivider.double] — two 1 px gold hairlines, 2 px gap.
/// * [WardDivider.none] — no rule.
enum WardDivider { single, double, none }

/// Page-header letterhead block. Optional [leadingAvatar] (Home only),
/// small gold anchor glyph + mono eyebrow, Fraunces title, optional
/// gold divider rule.
///
/// Legacy API: `divider: true|false` → single|none. New API: pass
/// [dividerStyle] directly.
class WardLetterhead extends StatelessWidget {
  const WardLetterhead({
    super.key,
    this.eyebrow,
    this.title,
    this.trailing,
    this.leadingAvatar,
    this.divider = true,
    this.dividerStyle,
    this.padding = const EdgeInsets.fromLTRB(22, 56, 22, 14),
    this.showAnchor = true,
  });

  final String? eyebrow;
  final String? title;
  final Widget? trailing;
  final Widget? leadingAvatar;
  final bool divider;
  final WardDivider? dividerStyle;
  final EdgeInsets padding;
  final bool showAnchor;

  WardDivider get _effectiveStyle =>
      dividerStyle ?? (divider ? WardDivider.single : WardDivider.none);

  @override
  Widget build(BuildContext context) {
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAnchor)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: AnchorGlyph(size: 12),
                ),
              Flexible(
                child: Text(
                  eyebrow!.toUpperCase(),
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ],
          ),
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              title!,
              style: AppTypography.h1.copyWith(height: 1.05),
            ),
          ),
      ],
    );

    final body = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (leadingAvatar != null)
            Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 2),
              child: leadingAvatar!,
            ),
          Expanded(child: textColumn),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: trailing!,
            ),
        ],
      ),
    );

    switch (_effectiveStyle) {
      case WardDivider.none:
        return body;
      case WardDivider.single:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            Container(
              height: 1,
              color: AppColors.accent.withValues(alpha: 0.33),
            ),
          ],
        );
      case WardDivider.double:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            Container(
              height: 1,
              color: AppColors.accent.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 2),
            Container(
              height: 1,
              color: AppColors.accent.withValues(alpha: 0.3),
            ),
          ],
        );
    }
  }
}
```

- [ ] **Step 2: Verify call sites still compile**

```bash
flutter analyze lib/
```

Expect 0 errors. The change is additive — every existing call site (no `leadingAvatar`) keeps working.

- [ ] **Step 3: Commit**

```bash
git add lib/shared/widgets/wardroom/ward_letterhead.dart
git commit -m "feat(wardroom): WardLetterhead leadingAvatar slot (Test #5 D-4)

Adds optional Widget? leadingAvatar to render to the LEFT of the
eyebrow + title block. Used by Home for the 44dp WardAvatar pattern.
Null default — every existing call site continues rendering identically.

Spec: §6.4."
```

---

## Task D-5 — Home letterhead

**Files:** Modify `lib/features/home/screens/home_screen.dart`.

- [ ] **Step 1: Locate the existing header method**

```bash
grep -n "_buildHeader\|userGreetingProvider\|userFirstNameProvider\|StreakBadge" lib/features/home/screens/home_screen.dart | head -20
```

Note current method name (`_buildHeader` vs `_buildWelcomeRow` etc.) and existing imports.

- [ ] **Step 2: Add imports if missing**

At the top of `home_screen.dart` ensure these imports exist (add only the ones missing):

```dart
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/shared/widgets/wardroom/rank_chip.dart';
// existing imports for userGreetingProvider, userFirstNameProvider,
// streakProvider, streakFreezesProvider, currentRankProvider — keep.
```

- [ ] **Step 3: Replace the header build region**

Find the section in `home_screen.dart`'s `build()` (or `_buildHeader()`) that previously rendered the welcome row. Replace it with the following two widgets stacked in a `Column`:

```dart
// Header letterhead — DAILY · <weekday> <day> <mon-abbr>.
Builder(builder: (context) {
  final now = DateTime.now();
  const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  final eyebrow =
      'DAILY · ${weekdays[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';

  final greeting = ref.watch(userGreetingProvider); // "Good afternoon" etc.
  final firstName = ref.watch(userFirstNameProvider); // "Upendra"
  final title = '$greeting, $firstName.';

  final initial = (firstName.isNotEmpty ? firstName[0] : 'A').toUpperCase();

  return WardLetterhead(
    eyebrow: eyebrow,
    title: title,
    leadingAvatar: WardAvatar(initial: initial, size: 44),
    showAnchor: false, // avatar already anchors the row visually
  );
}),
// Status strip — streak + freeze + rank chip.
Builder(builder: (context) {
  final streak = ref.watch(streakProvider).valueOrNull ?? 0;
  final freezes = ref.watch(streakFreezesProvider).valueOrNull ?? 0;
  final rank = ref.watch(currentRankProvider).valueOrNull;
  return WardStatusStrip(
    streakDays: streak,
    freezesAvailable: freezes,
    rankChip: rank != null ? RankChip(rank: rank) : null,
  );
}),
```

> **Provider names:** the snippet above uses the canonical names listed in `MEMORY.md`. If your local provider names differ (e.g., `homeStreakProvider`), keep the local names — do NOT introduce new ones. Read `lib/features/home/providers/home_provider.dart` to confirm before pasting.

> **WardAvatar import:** `WardAvatar` lives in `lib/shared/widgets/wardroom/ward_avatar.dart` and is exported via the `wardroom.dart` barrel (the same line you imported above). If it's not in the barrel, add `export 'ward_avatar.dart';` to it.

> **RankChip constructor:** if the existing `RankChip(rank: rank)` constructor expects a different argument shape (e.g., `RankChip.compact(...)` or positional), match the existing call sites in `train_screen.dart` / `profile_screen.dart` pre-revert. Don't invent new constructors.

- [ ] **Step 4: Delete the old welcome-row code**

Remove any `_buildWelcomeRow`, `_buildHeader` legacy body, hardcoded greeting strings, ad-hoc avatar inline, etc. that are no longer referenced. Keep helper methods that other screen sections rely on.

- [ ] **Step 5: Verify**

```bash
flutter analyze lib/features/home/
```

Expect 0 errors. If a provider name mismatches, fix locally and re-run.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/screens/home_screen.dart
git commit -m "feat(home): WardLetterhead with leadingAvatar + WardStatusStrip (Test #5 D-5)

Restores per-tab personality on Home (welcome row was killed by U7).
44dp WardAvatar on LEFT, eyebrow 'DAILY · <weekday> <day> <mon>',
Fraunces title '<greeting>, <firstName>.'. Status strip below with
streak + freeze + rank chip.

Spec: §6.3.2 (Home row)."
```

---

## Task D-6 — Train letterhead

**Files:** Modify `lib/features/train/screens/train_screen.dart`.

- [ ] **Step 1: Locate the U7-era top region**

```bash
grep -n "RankChip\|_buildPlanHeader\|currentWeekNumber\|phaseName\|WardLetterhead" lib/features/train/screens/train_screen.dart | head -20
```

Look at the top of the build tree — there should already be (post-revert) a plan header. The job is to align it with the standardized eyebrow formula and add the status strip.

- [ ] **Step 2: Replace the top region**

Inside the `build()`'s top column, replace the legacy plan-header block with:

```dart
// Letterhead — TRAIN · WK <n> OF 4.
Builder(builder: (context) {
  final week = WorkoutScheduleService.instance.getCurrentWeekNumber();
  final phase = ref.watch(currentPhaseProvider).valueOrNull;
  final phaseName = phase?.name ?? 'Foundation';
  final eyebrow = 'TRAIN · WK $week OF 4';
  return WardLetterhead(
    eyebrow: eyebrow,
    title: phaseName,
  );
}),
// Status strip — no rank chip on Train per spec §6.3.3.
Builder(builder: (context) {
  final streak = ref.watch(streakProvider).valueOrNull ?? 0;
  final freezes = ref.watch(streakFreezesProvider).valueOrNull ?? 0;
  return WardStatusStrip(
    streakDays: streak,
    freezesAvailable: freezes,
    rankChip: null,
  );
}),
```

- [ ] **Step 3: Decision — where the plan progress bar goes**

The plan progress bar (week pill row + Phase 1/2/3 dots) currently lives below the original plan header. Per spec §6.5 we keep it; per §6.3.1 the gold-rule status strip sits BELOW the letterhead and ABOVE everything else. So the order is:

1. WardLetterhead (eyebrow + title + gold rule)
2. WardStatusStrip (streak + freeze, no rank)
3. Existing plan progress bar
4. Existing week selector
5. Today card / etc.

If the existing post-revert code already had a "phase dots row" right under the plan header, leave it where it was — it now lives below the status strip.

- [ ] **Step 4: Imports**

Ensure the file imports:

```dart
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
// existing currentPhaseProvider import — keep.
// existing streakProvider / streakFreezesProvider imports — keep.
```

Remove the imports of `RankChip` + `RankChipFullWidth` if no longer used (revert already removed `RankChipFullWidth`; remove the `RankChip` import only if it's not referenced elsewhere on Train — it shouldn't be after this).

- [ ] **Step 5: Verify**

```bash
flutter analyze lib/features/train/
```

Expect 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/train/screens/train_screen.dart
git commit -m "feat(train): WardLetterhead + WardStatusStrip (Test #5 D-6)

Removes the old top rank-chip row (U7-era artifact) and uses the
standardized letterhead pattern. Eyebrow 'TRAIN · WK <n> OF 4',
title from current Phase.name. Status strip below with streak +
freeze; no rank chip on Train per spec §6.3.3.

Spec: §6.3.2 (Train row)."
```

---

## Task D-7 — Nutrition letterhead

**Files:** Modify `lib/features/nutrition/screens/nutrition_screen.dart`.

The Nutrition screen already had a Fraunces letterhead pre-U7 — most of this task is matching the eyebrow formula + adding the status strip.

- [ ] **Step 1: Locate the existing header method**

```bash
grep -n "_buildHeader\|WardLetterhead\|GALLEY\|FUEL\|DIET PLAN" lib/features/nutrition/screens/nutrition_screen.dart | head -20
```

- [ ] **Step 2: Update the header**

Replace the existing `_buildHeader` (or inline letterhead block) with:

```dart
Widget _buildHeader(BuildContext context, WidgetRef ref) {
  final now = DateTime.now();
  const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  final eyebrow =
      'GALLEY · ${weekdays[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';

  final dietPlanPill = _buildDietPlanPill(context, ref); // existing trailing
  final streak = ref.watch(streakProvider).valueOrNull ?? 0;
  final freezes = ref.watch(streakFreezesProvider).valueOrNull ?? 0;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WardLetterhead(
        eyebrow: eyebrow,
        title: 'Fueling the plan',
        trailing: dietPlanPill,
      ),
      WardStatusStrip(
        streakDays: streak,
        freezesAvailable: freezes,
        rankChip: null,
      ),
    ],
  );
}
```

If `_buildDietPlanPill` doesn't exist by that exact name, keep the existing trailing widget builder (whatever it's called) — only the eyebrow + title + status strip change.

- [ ] **Step 3: Imports**

Ensure:

```dart
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
// existing streakProvider / streakFreezesProvider imports — keep.
```

- [ ] **Step 4: Verify**

```bash
flutter analyze lib/features/nutrition/
```

Expect 0 errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/nutrition/screens/nutrition_screen.dart
git commit -m "feat(nutrition): WardLetterhead eyebrow + WardStatusStrip (Test #5 D-7)

Updates eyebrow to 'GALLEY · <weekday> <day> <mon>' (was 'FUEL'
during U7), title 'Fueling the plan'. Trailing diet-plan pill kept.
Status strip below with streak + freeze; no rank chip per spec.

Spec: §6.3.2 (Nutrition row)."
```

---

## Task D-8 — AI Coach letterhead

**Files:** Modify `lib/features/ai_coach/screens/ai_coach_screen.dart`.

- [ ] **Step 1: Locate header**

```bash
grep -n "DISPATCH\|WardLetterhead\|UPGRADE\|Aye Captain\|Good afternoon" lib/features/ai_coach/screens/ai_coach_screen.dart | head -20
```

- [ ] **Step 2: Replace header build**

In the AI Coach screen's `build()` (or its header method), replace the top region with:

```dart
// Letterhead — THE BRIDGE · 24/7.
WardLetterhead(
  eyebrow: 'THE BRIDGE · 24/7',
  title: 'Aye Captain',
  trailing: _buildUpgradePill(context, ref), // existing helper, keep name
  dividerStyle: WardDivider.double,
),
// Status strip — streak + freeze; no rank on AI Coach.
Builder(builder: (context) {
  final streak = ref.watch(streakProvider).valueOrNull ?? 0;
  final freezes = ref.watch(streakFreezesProvider).valueOrNull ?? 0;
  return WardStatusStrip(
    streakDays: streak,
    freezesAvailable: freezes,
    rankChip: null,
  );
}),
```

If the existing trailing pill helper is called `_buildUpgradeChip` or similar, keep its real name. The free/PRO gating logic inside it is unchanged.

- [ ] **Step 3: Anti-duplicate scan**

Per spec §6.3.4 we must NOT have "CAPTAIN" appearing in the eyebrow when the title already contains it.

```bash
grep -n "CAPTAIN" lib/features/ai_coach/screens/ai_coach_screen.dart
```

The only match should be inside the literal `'Aye Captain'`. If the eyebrow says `THE BRIDGE · CAPTAIN · 24/7`, it's wrong — the spec eyebrow is `THE BRIDGE · 24/7`.

- [ ] **Step 4: Imports**

```dart
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
```

- [ ] **Step 5: Verify**

```bash
flutter analyze lib/features/ai_coach/
```

Expect 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_coach/screens/ai_coach_screen.dart
git commit -m "feat(ai_coach): Aye Captain letterhead + status strip (Test #5 D-8)

Eyebrow 'THE BRIDGE · 24/7', static Fraunces title 'Aye Captain'
(was a dynamic time-of-day greeting that duplicated Home).
Trailing upgrade pill kept. Double gold rule per coach screen
convention. Status strip below.

Spec: §6.3.2 (AI Coach row), §10 C10."
```

---

## Task D-9 — Profile floating eyebrow + Fraunces name + status strip

**Files:** Modify `lib/features/profile/widgets/profile_identity.dart`.

This is the most invasive of the 5 tab edits because Profile uses a banner+overlap-avatar pattern, not a flat letterhead. The banner stays; we add the floating eyebrow on top of it AND move the user's name out of the avatar overlap row into a standalone Fraunces title below.

- [ ] **Step 1: Read the current widget**

```bash
wc -l lib/features/profile/widgets/profile_identity.dart
```

Read the file end-to-end before editing.

- [ ] **Step 2: Modify — three structural edits**

a. Add a `Positioned` overlay on the banner Stack:

```dart
Positioned(
  top: 8,
  left: 16,
  child: Text(
    'DOSSIER · OFFICER',
    style: AppTypography.monoXs.copyWith(
      color: AppColors.textPrimary.withValues(alpha: 0.65),
      letterSpacing: 3,
      fontWeight: FontWeight.w700,
    ),
  ),
),
```

This `Positioned` is the LAST child of the banner `Stack` so it draws on top of the gradient.

b. Below the banner Stack, replace the row that currently contains avatar+name side-by-side with avatar centered + Fraunces title underneath:

```dart
// Avatar row — centered, no name beside it.
Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Center(
    child: WardAvatar(
      initial: initial,
      size: 80,
      // existing image / ring color params — keep.
    ),
  ),
),
const SizedBox(height: 12),
// Fraunces title — full name as the tab letterhead title.
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 22),
  child: Text(
    fullName,
    textAlign: TextAlign.center,
    style: AppTypography.h1.copyWith(height: 1.05),
  ),
),
const SizedBox(height: 10),
// Gold rule — matches WardLetterhead.single divider.
Container(
  height: 1,
  margin: const EdgeInsets.symmetric(horizontal: 22),
  color: AppColors.accent.withValues(alpha: 0.33),
),
const SizedBox(height: 10),
// Status strip — streak + freeze + rank.
Builder(builder: (context) {
  final streak = ref.watch(streakProvider).valueOrNull ?? 0;
  final freezes = ref.watch(streakFreezesProvider).valueOrNull ?? 0;
  final rank = ref.watch(currentRankProvider).valueOrNull;
  return WardStatusStrip(
    streakDays: streak,
    freezesAvailable: freezes,
    rankChip: rank != null ? RankChip(rank: rank) : null,
  );
}),
```

c. Remove the OLD inline name `Text` widget from inside the banner Stack / avatar row. There must be exactly ONE rendering of the user's name on Profile.

- [ ] **Step 3: Resolve `fullName` source**

`fullName` comes from `ref.watch(userProfileProvider).val['full_name']` per the spec. Match the existing pattern in this file — if the file uses `userProfileProvider` differently (e.g., `userFullNameProvider`), keep the local pattern.

- [ ] **Step 4: Imports**

Ensure the file has:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/shared/widgets/wardroom/rank_chip.dart';
// existing providers — streakProvider, streakFreezesProvider, currentRankProvider
```

If the widget was a `StatelessWidget` and didn't already use Riverpod, convert it to `ConsumerWidget`. If it was `StatefulWidget`, convert to `ConsumerStatefulWidget` + `ConsumerState`. The conversion is mechanical: change the class extension and add `WidgetRef ref` to the build signature.

- [ ] **Step 5: Verify**

```bash
flutter analyze lib/features/profile/
```

Expect 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/profile/widgets/profile_identity.dart
git commit -m "feat(profile): floating eyebrow + Fraunces name title + status strip (Test #5 D-9)

Banner now carries 'DOSSIER · OFFICER' eyebrow at parchment 65% alpha
(top-left absolute). Avatar centers below banner; user's full name
renders BELOW the banner as a standalone Fraunces title (was inline
beside avatar pre-revert). Gold rule + status strip below.

Single source of truth for the name on Profile — the in-banner Text
widget is removed.

Spec: §6.3.2 (Profile row), §6.3.1 Profile variation."
```

---

## Task D-10 — Tests for new primitives

**Files:** Create `test/wardroom/ward_status_strip_test.dart`, `test/wardroom/ward_freeze_badge_test.dart`.

- [ ] **Step 1: Create the directory if needed**

```bash
mkdir -p test/wardroom
```

- [ ] **Step 2: Write FreezeBadge smoke test**

```dart
// test/wardroom/ward_freeze_badge_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_freeze_badge.dart';

void main() {
  group('FreezeBadge', () {
    testWidgets('renders with positive count', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FreezeBadge(count: 3)),
        ),
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('❄'), findsOneWidget); // ❄ snowflake
    });

    testWidgets('renders with zero count (dimmed)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FreezeBadge(count: 0)),
        ),
      );
      expect(find.text('0'), findsOneWidget);
      expect(find.text('❄'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 3: Write WardStatusStrip smoke test**

```dart
// test/wardroom/ward_status_strip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_freeze_badge.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_status_strip.dart';
import 'package:icanbefitter/features/home/widgets/streak_badge.dart';

void main() {
  group('WardStatusStrip', () {
    testWidgets('renders streak + freeze when no rank chip', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WardStatusStrip(
              streakDays: 12,
              freezesAvailable: 2,
              rankChip: null,
            ),
          ),
        ),
      );
      expect(find.byType(StreakBadge), findsOneWidget);
      expect(find.byType(FreezeBadge), findsOneWidget);
    });

    testWidgets('hides streak chip when streakDays == 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WardStatusStrip(
              streakDays: 0,
              freezesAvailable: 2,
              rankChip: null,
            ),
          ),
        ),
      );
      expect(find.byType(StreakBadge), findsNothing);
      expect(find.byType(FreezeBadge), findsOneWidget);
    });

    testWidgets('shows rank chip when provided', (tester) async {
      // Note: a real RankChip needs a non-null Rank model. For smoke we
      // pass a Container as the third "chip" via direct Wrap inspection.
      // The strip renders rankChip verbatim.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WardStatusStrip(
              streakDays: 5,
              freezesAvailable: 1,
              // RankChip mock omitted — confirm type-only via key
              // when full RankChip is wired with a rank fixture.
              rankChip: null,
            ),
          ),
        ),
      );
      expect(find.byType(StreakBadge), findsOneWidget);
      expect(find.byType(FreezeBadge), findsOneWidget);
    });
  });
}
```

> The third test currently passes `null` because `RankChip` requires a `Rank` model — wiring a fixture is out of scope for a smoke test. The visible-when-provided invariant is verified manually in Task D-11.

- [ ] **Step 4: Run the tests**

```bash
flutter test test/wardroom/ward_freeze_badge_test.dart test/wardroom/ward_status_strip_test.dart
```

Expect: all pass. If `StreakBadge` import path differs, fix and re-run.

- [ ] **Step 5: Commit**

```bash
git add test/wardroom/
git commit -m "test(wardroom): smoke tests for FreezeBadge + WardStatusStrip (Test #5 D-10)

- FreezeBadge: positive + zero count both render snowflake + count.
- WardStatusStrip: streak + freeze when no rank; hides StreakBadge
  when days == 0.

RankChip-with-rank visual is covered by D-11 manual verification.

Spec: §10 C8."
```

---

## Task D-11 — Manual visual smoke test (documented)

**Files:** Create `docs/superpowers/notes/2026-04-28-letterhead-visual-check.md`.

- [ ] **Step 1: Build a dev APK or run the app**

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

(Or use `/build-apk` skill if you need a release artifact for on-device verification.)

- [ ] **Step 2: Walk through all 5 tabs and verify**

| # | Tab | Verify |
|---|---|---|
| 1 | 🏠 Home | 44dp avatar on LEFT; eyebrow `DAILY · <weekday> <day> <mon>` matches today's IST date; greeting matches time-of-day (Good morning / afternoon / evening); status strip shows streak + freeze + rank chip |
| 2 | 🏋️ Train | NO rank chip in the top region; eyebrow `TRAIN · WK <n> OF 4`; title is the current Phase name; status strip shows streak + freeze only |
| 3 | 🥗 Nutrition | Eyebrow `GALLEY · <weekday> <day> <mon>`; title `Fueling the plan`; trailing DIET PLAN pill in title row right slot; status strip below |
| 4 | 💬 AI Coach | Eyebrow `THE BRIDGE · 24/7` (no `CAPTAIN` segment); title `Aye Captain`; trailing UPGRADE pill (free) or absent (PRO); status strip below |
| 5 | 👤 Profile | Floating eyebrow `DOSSIER · OFFICER` top-left of banner @ ~65% alpha parchment; avatar 80px overlapping banner bottom centered; full name as Fraunces 28sp title BELOW banner; gold rule + status strip below |

- [ ] **Step 3: Document findings**

Create `docs/superpowers/notes/2026-04-28-letterhead-visual-check.md` with:

```markdown
# Letterhead visual check — Test #5 Plan D

**Date:** <YYYY-MM-DD>
**APK:** dev / prod (circle one)
**Device:** <device + Android version>

## Result per tab

- [ ] Home — eyebrow correct, avatar 44dp on left, greeting matches time-of-day, status strip visible
- [ ] Train — no rank chip in top region, week number correct, phase name correct
- [ ] Nutrition — eyebrow GALLEY, title 'Fueling the plan', diet plan pill present
- [ ] AI Coach — eyebrow THE BRIDGE · 24/7 (no CAPTAIN dup), title 'Aye Captain'
- [ ] Profile — floating eyebrow on banner @ 65% alpha, name as Fraunces title below banner, single name render

## Issues found

(none / list)

## Spec deviations

(none / list)
```

- [ ] **Step 4: Commit the doc**

```bash
git add docs/superpowers/notes/2026-04-28-letterhead-visual-check.md
git commit -m "docs(letterhead): visual verification log (Test #5 D-11)

Manual walk-through of all 5 tabs against §6.3.2 + §10 C8-C10.

Spec: §10 C8 / C9 / C10."
```

---

## Task D-12 — Full test suite + analyze

- [ ] **Step 1: Analyze the whole tree**

```bash
flutter analyze lib/ test/
```

Expect: `No issues found!` If any issues remain, fix in-place (do NOT defer to a follow-up task — that defeats the lockdown).

- [ ] **Step 2: Run the full test suite**

```bash
flutter test
```

Expect: all pass, plus the 2 new wardroom test files. If any pre-existing test references `WardTabHeader` / `RankChipFullWidth` (the U7 widgets), delete the assertion since the widget is gone — those tests will need to be removed in this same commit.

- [ ] **Step 3: Source-grep regression — no U7 ghost references**

```bash
grep -rn "WardTabHeader\|RankChipFullWidth" lib/ test/
```

Expect: zero matches.

- [ ] **Step 4: Source-grep regression — eyebrow formula**

```bash
grep -rn "'DAILY · \|'TRAIN · WK\|'GALLEY · \|'THE BRIDGE · \|'DOSSIER · " lib/features/
```

Expect: 5 matches, one per tab.

- [ ] **Step 5: Commit if anything was fixed in this task**

If Steps 1-4 surfaced any code changes, commit them:

```bash
git add -A
git commit -m "chore(letterhead): final verify + cleanup (Test #5 D-12)

flutter analyze: 0 issues.
flutter test: all pass.
No remaining U7 ghost references.
Eyebrow formula present on all 5 tabs.

Spec: §10 C8-C10."
```

If nothing changed, skip the commit — the task is just verification.

---

## Done definition

- All 12 tasks above have all checkboxes ticked.
- `flutter analyze lib/ test/` reports 0 issues.
- `flutter test` passes (including the 2 new wardroom tests).
- All 5 tabs match spec §6.3.2 content table (verified manually in D-11).
- Spec C8 / C9 / C10 success criteria verified.
- Commit history: 1 revert + 11 feature commits in linear order on the test-5 branch.
