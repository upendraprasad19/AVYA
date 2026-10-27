# APK Test #7 — Design Spec
**Date:** 2026-05-01  
**Status:** Awaiting user approval

---

## Scope

Eight targeted fixes surfaced during on-device testing of APK +6. No new features — polish, correctness, and one additive section in Profile.

---

## Fix 1 — Mission Brief routing bug

**Bug:** New users never see the Mission Brief screen. `welcome_screen.dart`'s BEGIN ENLISTMENT button calls `context.go('/onboarding/identity')` directly, bypassing `RestoringScreen` entirely. The `profile == null → /onboarding/mission-brief` decision tree in `RestoringScreen` is never reached.

**Fix:** One-line change in `welcome_screen.dart` line 195:
```
context.go('/onboarding/mission-brief')   // was: /onboarding/identity
```

The Mission Brief's own CONTINUE button already routes to `/onboarding/identity` — that stays unchanged. The GoRouter passthrough for `/onboarding/mission-brief` (unauthenticated, not-onboarded users) is already correct and requires no changes.

**Additionally:** Add an `errorBuilder` fallback to the `Image.asset('assets/founder/upendra.jpg')` in `MissionBriefScreen` so a missing asset shows a placeholder circle instead of a red error box.

---

## Fix 2 — Calorie sync (self-resolving)

**Bug:** Plan screen previewed 2093 kcal but saved profile showed 2960 kcal.

**Cause:** User entered onboarding via the broken path (Fix 1), which may have produced incomplete widget.data at plan_screen. Once Fix 1 routes correctly through Mission Brief → Identity → Goal → Stats → Details → Plan, widget.data carries the full input set and `BmrCalculator.calculateTargets` returns consistent numbers on preview and save.

**No code change required beyond Fix 1.**

---

## Fix 3 — Profile sections: continuous flat list

**Bug:** The upper profile sections (completeness, achievements, journey, body stats, targets) render as a sequence of individually-bordered WardCards with inconsistent gaps, creating a visually fragmented feel.

**Fix:** Consolidate each named group of related content into a single `_buildCard` with `ProfileRow` items separated by `line2` hairline dividers. Section headers (`SectionHeader`) remain visible above each group. Rich widgets that cannot be expressed as a `ProfileRow` (e.g. `ProfileCompletenessCard`, `SlimAchievementsCard`, `_buildBodyStats`) keep their current rendering — only the visual grouping and spacing is standardised.

Specifically:
- Standardise all inter-section `SizedBox` heights to `8` (currently a mix of 6/8/other).
- Any section whose content is already a flat `_buildCard([ProfileRow, ProfileRow, ...])` stays untouched.
- Sections that contain one standalone card surrounded by `SizedBox` gaps get their spacing tightened to `8` above and `8` below, consistent with the rest of the list.

The visual target is the same tight-list feel as SHARE & GROW and SETTINGS, applied to the full profile scroll.

---

## Fix 4 — Reports section: single grouped card

**Bug:** The REPORTS section has three separate `_buildCard` calls (Predictions, Progress Comparison, Progress Photos), each a floating island. SHARE & GROW puts all its rows in one card — REPORTS should do the same.

**Fix:** Merge the three individual `_buildCard([ProfileRow(...)])` calls into a single `_buildCard` containing all three `ProfileRow` widgets. `ProfileRow`'s existing `showBorder` divider behaviour separates them visually. `WeeklyReportCard` stays as a standalone card above the merged three-row card — it contains sparklines and rich content that do not reduce cleanly to a list row.

Result: REPORTS = `WeeklyReportCard` + one grouped `_buildCard` with three rows.

---

## Fix 5 — Induction pledge: correct rank target

**Bug:** `induction_screen.dart` line 236 hardcodes "Lieutenant Commander rank — 200 workouts", but the rank ladder was redesigned. Sub Lieutenant (ordinal 6, gate W104) is the first officer commission — the aspirational milestone Upendra should pledge to.

**Fix:** Update the pledge `TextSpan` (two changes):
1. `'Make Lieutenant Commander rank — 200 workouts'` → `'Make Sub Lieutenant rank — 104 workouts'`
2. `'200 workouts is roughly twelve months'` → `'104 workouts is roughly six months'`

All other copy ("Most don't make it past month two…") stays verbatim.

---

## Fix 6 — Streak freeze duplicate

**Bug:** `WardStatusStrip` passes `freezesAvailable: 0` (hardcoded) to `StreakBadge` AND separately renders `WardFreezeBadge(count: freezesAvailable)`. Result: streak pill shows `❄ 0` and a second badge shows `❄ 1` — two freeze displays.

**Fix:** In `ward_status_strip.dart`:
- Pass the real `freezesAvailable` value to `StreakBadge` instead of the hardcoded `0`.
- Remove the `WardFreezeBadge` line entirely.

`StreakBadge` already contains the combined `🔥 N DAYS ❄ N` pill with the divider and inline freeze count. One pill, one source of truth.

---

## Fix 7 — Double name in home header

**Bug:** Home screen title is `'$greeting, $firstName.'` where `greeting = "Good afternoon, Upendra"` (name embedded) and `firstName = "UPENDRA"`. Result: `"Good afternoon, Upendra, UPENDRA."` — name appears twice, wraps to 3 lines.

**Fix:** `home_screen.dart` line 227:
```dart
title: '$greeting.',   // was: '$greeting, $firstName.'
```

`greeting` already ends with the first name. The trailing period provides the sentence-close. No other changes needed.

---

## Fix 8 — New AVYA section in Profile

**Goal:** Let users revisit the Mission Brief from their profile, and surface the brand's web and Instagram presence.

### New section

After the existing SETTINGS section in `profile_screen.dart`, add:

```
SectionHeader('AVYA')
_buildCard([
  ProfileRow(icon: Icons.shield_outlined, title: "AVYA'S PROMISE",
             subtitle: 'The mission brief — why this exists',
             onTap: → context.go('/avya/promise')),
  ProfileRow(icon: Icons.language_outlined, title: 'icanbefitter.com',
             subtitle: 'The full platform',
             onTap: → launchUrl(Uri.parse('https://icanbefitter.com'))),
  ProfileRow(icon: Icons.camera_alt_outlined, title: '@icanbefitter',
             subtitle: 'Daily wins on Instagram',
             onTap: → launchUrl instagram://user?username=icanbefitter,
                         web fallback: https://instagram.com/icanbefitter),
])
```

### New route `/avya/promise`

`MissionBriefScreen` gets an optional `readOnly: bool = false` constructor parameter.

When `readOnly: true`:
- Scaffold gets `appBar: AppBar(backgroundColor: AppColors.bg, leading: BackButton)` — back arrow navigates `context.pop()`.
- The `CONTINUE →` button at the bottom is hidden (`if (!readOnly) ...`).
- All other content (founder photo, credentials, body copy, Instagram link) is identical.

GoRouter: add a new `/avya/promise` route pointing to `MissionBriefScreen(readOnly: true)`. This route is outside the `/onboarding/` namespace, so `_authRedirect`'s `isOnOnboarding` check does NOT redirect onboarded users away.

The existing `/onboarding/mission-brief` route keeps `readOnly: false` (default) — no change to the onboarding flow.

---

## Sections not changing

- **WardRankInsignia** (accordion pill) — stays as designed in Test #6.
- **Subscription section** — no change.
- **Auth flow** — no changes beyond the one-line Fix 1.
- **GoRouter `_authRedirect`** — no changes; existing logic already handles all cases correctly after Fix 1.

---

## File change summary

| File | Change |
|---|---|
| `lib/features/onboarding/screens/welcome_screen.dart` | Fix 1: route to `/onboarding/mission-brief` |
| `lib/features/onboarding/screens/mission_brief_screen.dart` | Fix 1: errorBuilder; Fix 8: `readOnly` param + conditional AppBar + hide CONTINUE |
| `lib/core/router/app_router.dart` | Fix 8: add `/avya/promise` route |
| `lib/features/home/screens/home_screen.dart` | Fix 7: `title: '$greeting.'` |
| `lib/shared/widgets/wardroom/ward_status_strip.dart` | Fix 6: pass real freezes to StreakBadge, remove WardFreezeBadge |
| `lib/features/ai_coach/screens/induction_screen.dart` | Fix 5: Sub Lieutenant + 104 workouts + six months |
| `lib/features/profile/screens/profile_screen.dart` | Fix 3: uniform 8dp gaps; Fix 4: merge REPORTS cards; Fix 8: AVYA section |
