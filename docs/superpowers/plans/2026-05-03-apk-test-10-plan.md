# APK Test #10 — UX redesign batch (post-Test-#9 observations)

**Branch:** `feat/apk-test-10-batch` off main (post Test #9 merge `c0102a9`)
**Date:** 2026-05-03
**Estimated scope:** 5 observations · ~12–18h · 1 batch APK
**Migrations:** 0
**Edge function deploys:** 0
**Mockups locked:**
- [docs/mockups/2026-05-03-home-header-and-stats-v1.html](../../mockups/2026-05-03-home-header-and-stats-v1.html) — obs 1 + 4
- [docs/mockups/2026-05-03-rank-ladder-nutrition-coach-v1.html](../../mockups/2026-05-03-rank-ladder-nutrition-coach-v1.html) — obs 2 + 3 + 5

## Scope summary

| Obs | Surface | Changes | Files (primary) |
|---|---|---|---|
| 1 | Home header | 3 rows → 2 rows · greeting+name stack inside avatar height · streak pill inline | `home_screen.dart` |
| 2 | Rank ladder | New `/profile/rank-ladder` full-screen + rewrite `_humanGateText` (covers all 11 ranks, surfaces hidden gate halves) + rename sheet link `VIEW FULL ROADMAP` → `VIEW LIFETIME LADDER` (route swap) | `rank_service_record_sheet.dart` · `rank_service.dart` · `app_router.dart` · NEW `rank_ladder_screen.dart` |
| 3 | Nutrition header | 3 rows → 2 rows · drop linear `WardBar` · streak pill collapses onto title row | `nutrition_screen.dart` |
| 4 | Today macro tiles | 3 separate tiles → 1 merged block with hairline-divided rows + `◇ ◆ ▲` bullet glyphs | `today_workout_card.dart` |
| 5 | AI coach compass | New compass-glyph button left of input · tap opens segregated tools bottom sheet (4 families · 15 prefill commands) | `ai_coach_screen.dart` · NEW `compass_tools_sheet.dart` |

---

## OBS 1 · Home header — 3 rows → 2 rows

### Files touched

- `lib/features/home/screens/home_screen.dart` (lines ~205–304)

### Changes

Replace the 3-row header inside the `Builder` block at [home_screen.dart:205](../../../lib/features/home/screens/home_screen.dart):

**Before** (current):
- Row 1: `AnchorGlyph` + dense eyebrow `DAILY · TUE 3 MAY · WK 1 · PHASE 1`
- Row 2: `WardAvatar(44)` + `Good morning, Avyaansh.` (h1)
- Row 3: streak pill right-aligned (`WardStatusStrip` wrapping `StreakBadge`)
- Single 1px `accent`-33 hairline rule

**After** (proposed):
- Row 1: unchanged (anchor + dense eyebrow)
- Row 2: single horizontal `Row` with three children:
  - `WardAvatar(44)` (unchanged primitive)
  - `Expanded` containing a `SizedBox(height: 44)` with a `Column(mainAxisAlignment: center)`:
    - Top text: greeting WITHOUT name — use `userGreetingProvider`'s prefix only, uppercased
      (`'GOOD EVENING,'` etc.). Style: `AppTypography.mono` 10sp w700, `accent` color, +1.6 letter-spacing.
    - Bottom text: name from `userFirstNameProvider`, uppercase + ` 👋` inline.
      Style: `AppTypography.h1` reduced to 22sp Fraunces w900 (NOT default 26sp — must fit alongside pill).
      `maxLines: 1`, `TextOverflow.ellipsis`.
  - `WardStatusStrip(streakDays, freezesAvailable)` (unchanged primitive — moves from row 3 to inline)
- Drop the standalone row-3 padding block (`header-streak-row`).
- Single rule unchanged.

### Provider work

`userGreetingProvider` currently returns `'Good morning, Avyaansh'` (full string with name). Rather than re-parsing, **add a new `userTimeOfDayProvider`** that returns just `'GOOD MORNING' | 'GOOD AFTERNOON' | 'GOOD EVENING'` based on hour. Keep the existing `userGreetingProvider` for any other consumers (don't break it).

```dart
class UserTimeOfDayNotifier extends Notifier<String> {
  @override
  String build() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }
}
final userTimeOfDayProvider =
    NotifierProvider<UserTimeOfDayNotifier, String>(UserTimeOfDayNotifier.new);
```

### Tests

- `test/home/home_header_layout_test.dart` (NEW) — golden test: render `_buildHeader` at 360 dp, assert greeting + name + pill all visible on a single row, total header height drops by ≥ 30 dp vs baseline.
- `test/home/home_header_provider_test.dart` (NEW) — `userTimeOfDayProvider` returns correct string for hours 0–23 boundaries (00:00 → MORNING, 12:00 → AFTERNOON, 17:00 → EVENING).

### Risks

- Long names (e.g., `ABHISHEK SHARMA`) may overflow at 22sp inside the constrained middle column. Guard with `maxLines: 1 + ellipsis`. If clipping looks bad, drop name to first-name-only (`profile['full_name']?.split(' ').first` — already exposed via `userFirstNameProvider`).

---

## OBS 2 · Lifetime ladder full-screen + officer-track copy fix

### Files touched

- `lib/features/profile/widgets/rank_service_record_sheet.dart` (line 122 — link label + route)
- `lib/core/services/rank_service.dart` (lines 234–249 — `_humanGateText` rewrite)
- `lib/core/router/app_router.dart` (NEW route)
- `lib/features/profile/screens/rank_ladder_screen.dart` (NEW)

### Changes

#### 2a. Rewrite `_humanGateText`

Surface BOTH gate halves when both apply. Replaces the early-return pattern that hides `deploymentsCompleteAtLeast` on PO/CPO and the entire `completionRateMinimum` half on MCPO + officer track.

```dart
String _humanGateText(RankLadderEntry entry) {
  final gate = kRankGates[entry.code]!;
  if (entry.code == 'SD2') return 'Earned at induction';

  final parts = <String>[];

  // Sailor-track — streak primary.
  if (gate.streakAtLeast != null) {
    parts.add('${gate.streakAtLeast}-workout streak');
  }

  // Calendar gate — convert to years for officer track readability.
  final weeks = entry.minWeeks;
  if (weeks > 0) {
    if (entry.category == 'officer' && weeks >= 104) {
      // 104 → 2 years, 130 → 2.5 years, 156 → 3 years etc.
      final years = (weeks / 52);
      final yearLabel = years == years.toInt()
          ? '${years.toInt()} years'
          : years.toStringAsFixed(1).replaceAll('.0', '') + ' years';
      parts.add('$yearLabel of service');
    } else {
      parts.add('$weeks ${weeks == 1 ? "week" : "weeks"} of service');
    }
  }

  if (gate.deploymentsCompleteAtLeast != null) {
    parts.add('${gate.deploymentsCompleteAtLeast} deployments complete');
  }

  if (gate.maxGapDays != null) {
    parts.add('no >${gate.maxGapDays}-day gap');
  }

  if (gate.completionRateMinimum != null && gate.completionRateWindowWeeks != null) {
    final pct = (gate.completionRateMinimum! * 100).round();
    final win = gate.completionRateWindowWeeks!;
    final winLabel = win >= 52
        ? (win == 52 ? '52 weeks' : win == 104 ? '2 years' : '$win weeks')
        : '$win weeks';
    parts.add('$pct% completion (rolling $winLabel)');
  }

  return parts.join(' · ');
}
```

This propagates to **all 3 surfaces** automatically (single source):
1. `rank_service_record_sheet.dart` upcoming-row (line 300)
2. `service_record_section.dart` profile widget (line 257)
3. New `rank_ladder_screen.dart` (this batch)

#### 2b. Rename + reroute the sheet's footer link

In [`rank_service_record_sheet.dart:113-131`](../../../lib/features/profile/widgets/rank_service_record_sheet.dart):

```dart
// before:
context.go('/train/roadmap');
// label: 'VIEW FULL ROADMAP →'

// after:
context.go('/profile/rank-ladder');
// label: 'VIEW LIFETIME LADDER →'
```

The `/train/roadmap` link is NOT lost — it stays accessible from the Train tab's existing entry. Two surfaces, two destinations.

#### 2c. New full-screen `RankLadderScreen`

Path: `lib/features/profile/screens/rank_ladder_screen.dart`

```dart
class RankLadderScreen extends ConsumerWidget {
  const RankLadderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankService = RankService.instance;
    final ladder = rankService.getLadder();
    final current = rankService.getCurrentRank();
    final currentIdx = ladder.indexWhere((e) => e.entry.code == current.entry.code);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Lifetime ladder',
            style: AppTypography.titleL.copyWith(fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView.builder(
        itemCount: ladder.length + 1, // +1 for summary tile
        itemBuilder: (ctx, i) {
          if (i == ladder.length) return _buildSummaryTile(context);
          final view = ladder[i];
          final state = i < currentIdx
              ? _RankRowState.passed
              : i == currentIdx
                  ? _RankRowState.current
                  : _RankRowState.future;
          return _RankRow(view: view, state: state);
        },
      ),
    );
  }
  // _RankRow + _buildSummaryTile per mockup
}
```

3-state styling per locked spec:
- PASSED: insignia 100% opacity · dim `PASSED` chip · gateText replaced by `'Earned · ${MMM yyyy}'` from `promotion_history_provider`
- CURRENT: gold 2px ring on insignia · `accent`-10 row bg · 3px gold left-border · gold-fill `CURRENT` chip · gateText hidden
- FUTURE: insignia 35% opacity · small lock glyph overlay · gateText visible per the new `_humanGateText`

Bottom summary tile: 3 columns (DEPLOYMENTS · SERVICE · VOLUME). Data sources:
- DEPLOYMENTS = `progress['total_workouts_done']` from `UserRepository.instance.getProgress()`
- SERVICE = `(now - signupAt).inDays` (signupAt from `phase_started_at` IST or `auth.users.created_at`)
- VOLUME = `WorkoutRepository.instance.totalLifetimeVolumeKg()` (NEW method — sum `volume_kg` across all `exlog_*` rows)

#### 2d. Router registration

In `app_router.dart`, add:
```dart
GoRoute(
  path: '/profile/rank-ladder',
  builder: (_, __) => const RankLadderScreen(),
),
```

### Tests

- `test/profile/rank_ladder_gate_text_test.dart` (NEW) — `_humanGateText` returns expected string for each of 11 ranks. Pin the locked copy table.
- `test/profile/rank_ladder_screen_test.dart` (NEW) — render screen at 360 dp, find one CURRENT chip, N–1 FUTURE rows visible (or PASSED for completed test fixture), summary tile at bottom.
- `test/profile/rank_service_sheet_link_test.dart` (NEW) — assert footer link label is `VIEW LIFETIME LADDER →` and tapping it pushes `/profile/rank-ladder`.

### Risks

- `WorkoutRepository.totalLifetimeVolumeKg()` is a new method. Iterate `workoutBox.toMap()` filtering for `exlog_*` keys, sum `volume_kg`. Fall back to `weight_kg × reps_completed` for legacy rows missing `volume_kg`.
- For 3-state styling, we need promotion dates for PASSED rows. `promotion_history_provider` returns `AsyncValue<List<PromotionRecord>>`. Show `Earned` without date during loading, hydrate on data.
- Lt is at ordinal 7 in `kRankLadder` — make sure the screen renders 11 rows, not the 10 in user's old reference screenshot.

---

## OBS 3 · Nutrition header — drop linear bar, pull pill up

### Files touched

- `lib/features/nutrition/screens/nutrition_screen.dart` (lines ~66–158)

### Changes

In the `Builder` block at [nutrition_screen.dart:69](../../../lib/features/nutrition/screens/nutrition_screen.dart):

**Remove:**
- Row 3: the `WardBar` with `trailingLabel: '$consumedKcal / $targetKcal KCAL'` (lines 122–149)
- Local computations for `consumedKcal`, `targetKcal`, `pct` if no longer used after removal

**Modify row 2** (the title row, currently lines 113–120):
- Wrap the existing `Text('Fueling the plan', ...)` in a `Row` with the streak pill `WardStatusStrip` on the right.
- `Expanded(child: title)` to let title take available width.
- `WardStatusStrip(streakDays: ref.watch(streakProvider), freezesAvailable: ref.watch(streakFreezeProvider))` wrapped in the existing `GestureDetector(onTap: () => StreakExplainerSheet.show(...))`.

**Keep unchanged:**
- Row 1 (eyebrow + DIET PLAN chip)
- Single 1px `accent`-33 hairline rule

### Tests

- `test/nutrition/nutrition_header_layout_test.dart` (NEW) — render header at 360 dp, assert linear `WardBar` is NOT present, streak pill IS visible on the same row as the title.

### Risks

- Title `'Fueling the plan'` at h1 32sp + streak pill ~85 dp + padding 22 each side: at 360 dp screen, content area is 316 dp. Fraunces 32sp 16-char title is ~210 dp. Plus 8 dp gap + 85 dp pill = 303 dp. Tight but fits. If overflow appears on certain devices, drop title to `AppTypography.h1.copyWith(fontSize: 28)` for this surface.

---

## OBS 4 · Today macros — 3 tiles → 1 merged block

### Files touched

- `lib/features/home/widgets/today_workout_card.dart` (lines ~84–104, `_MacroColumn` widget)

### Changes

Replace `_MacroColumn` to render a single `Container` with `border` + `radius` instead of 3 separate tiles separated by `SizedBox(height: 6)` gaps.

```dart
class _MacroColumn extends StatelessWidget {
  // ... existing fields ...

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.cardS),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _MacroRow(
            bullet: '◇',
            label: 'FUEL',
            value: '$caloriesCurrent/$caloriesTarget',
            fillPct: (caloriesCurrent / caloriesTarget).clamp(0.0, 1.0),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line2),
          _MacroRow(
            bullet: '◆',
            label: 'PROTEIN',
            value: '$proteinCurrent/${proteinTarget}g',
            fillPct: (proteinCurrent / proteinTarget).clamp(0.0, 1.0),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line2),
          _MacroRow(
            bullet: '▲',
            label: 'STEPS',
            value: '$stepsCurrent/${TodayWorkoutCard._abbreviateK(stepsTarget)}',
            fillPct: (stepsCurrent / stepsTarget).clamp(0.0, 1.0),
          ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String bullet;
  final String label;
  final String value;
  final double fillPct;
  const _MacroRow({required this.bullet, required this.label, required this.value, required this.fillPct});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(bullet, style: TextStyle(color: AppColors.accent, fontSize: 12, height: 1)),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: AppTypography.monoXs.copyWith(fontSize: 8, letterSpacing: 1.2, color: AppColors.textDim, fontWeight: FontWeight.w700))),
              Text(value, style: AppTypography.titleS.copyWith(fontSize: 13, color: AppColors.textPrimary, height: 1)),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fillPct,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

### Tests

- `test/home/today_macro_block_test.dart` (NEW) — assert 1 single `Container` with border, find 3 `_MacroRow` instances inside, find 2 `Divider` instances between them, no separate `Container` per tile.

### Risks

- The existing `_MacroTile` widget will become dead code after this change — delete it. Grep for any other usages first (should be none).
- Bullet glyphs ◇ ◆ ▲ render correctly on Android system fonts. Sanity-check on a real device — fall back to `Icons.diamond_outlined` etc. if any one renders as tofu.

---

## OBS 5 · AI coach compass + segregated tools sheet

### Files touched

- `lib/features/ai_coach/screens/ai_coach_screen.dart` (line ~1100, `_buildInputBar` modification)
- `lib/features/ai_coach/widgets/compass_tools_sheet.dart` (NEW)

### Changes

#### 5a. Add compass button to composer

In `_buildInputBar` at [ai_coach_screen.dart:1112](../../../lib/features/ai_coach/screens/ai_coach_screen.dart), modify the bubble's `padding` to `EdgeInsets.fromLTRB(6, 0, 6, 0)` (was `14, 0, 6, 0`) and add a compass button as the FIRST child of the inner `Row`:

```dart
child: Row(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    if (!_isRecording)
      IconButton(
        icon: const Icon(Icons.explore_outlined,
            color: AppColors.accent, size: 20),
        onPressed: isSending
            ? null
            : () => CompassToolsSheet.show(
                context,
                onSelect: (prefill) {
                  _messageController.text = prefill;
                  _messageController.selection = TextSelection.collapsed(
                      offset: prefill.length);
                  _inputFocusNode.requestFocus();
                },
              ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    Expanded(
      child: _isRecording ? _buildRecordingBody() : TextField(/* unchanged */),
    ),
    // ... existing paperclip + mic/send ...
  ],
),
```

`Icons.explore_outlined` is the Flutter Material compass-rose icon — 8-point compass, fits the naval theme.

#### 5b. New `CompassToolsSheet` widget

```dart
// lib/features/ai_coach/widgets/compass_tools_sheet.dart
class CompassToolsSheet extends StatelessWidget {
  final ValueChanged<String> onSelect;
  const CompassToolsSheet({super.key, required this.onSelect});

  static Future<void> show(BuildContext context, {required ValueChanged<String> onSelect}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => CompassToolsSheet(onSelect: onSelect),
    );
  }

  static const _families = <_Family>[
    _Family('DRILL · WORKOUT', [
      _Cmd('/LOG', 'Log workout', 'Log my workout: '),
      _Cmd('/SWAP', 'Swap exercise', 'Swap [exercise] for '),
      _Cmd('/SHORTEN', 'Shorten today', 'Cut today\'s workout to 30 min'),
      _Cmd('/HOTEL', 'Travel workout', 'I\'m travelling — give me a hotel-room workout'),
      _Cmd('/INJURY', 'Modify for injury', 'Modify my plan — my [body part] hurts'),
    ]),
    _Family('GALLEY · NUTRITION', [
      _Cmd('/LOG MEAL', 'Log a meal', 'Log meal: '),
      _Cmd('/SUGGEST', 'Meal idea', 'Suggest a 600 kcal high-protein meal'),
      _Cmd('/TARGET', 'Adjust calorie target', 'Adjust my calorie target to '),
    ]),
    _Family('ORDERS · PLAN', [
      _Cmd('/SHUFFLE', 'Regenerate plan', 'Regenerate this week\'s plan'),
      _Cmd('/SCHEDULE', 'Reschedule day', 'Reschedule [day] to '),
      _Cmd('/PAUSE', 'Pause plan', 'Pause my plan for '),
      _Cmd('/SWITCH', 'Change goal', 'Switch my goal to '),
    ]),
    _Family('INTEL · PROGRESS', [
      _Cmd('/PROGRESS', 'Progress summary', 'Show my progress this month'),
      _Cmd('/HISTORY', 'Exercise history', 'Show my [exercise] history'),
      _Cmd('/PR', 'Log a PR', 'Log a PR: '),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.85,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(/* per mockup spec */),
      ),
    );
  }
}

class _Family {
  final String label;
  final List<_Cmd> commands;
  const _Family(this.label, this.commands);
}
class _Cmd {
  final String slash;
  final String desc;
  final String prefill;
  const _Cmd(this.slash, this.desc, this.prefill);
}
```

Tap behavior: `onSelect(cmd.prefill)` + `Navigator.of(ctx).pop()`. Ai coach screen receives the prefill, sets input text, focuses input, places cursor at end. No auto-fire.

### Tests

- `test/ai_coach/compass_tools_sheet_test.dart` (NEW) — render sheet, find 4 family labels, find 15 command rows total, tap one and verify `onSelect` callback fires with correct prefill string.

### Risks

- The existing `_buildInputBar` is complex (recording state, slide-to-cancel, animations). Adding the compass button must NOT touch any of those code paths — additive only.
- Sheet content scrolls when keyboard opens. `DraggableScrollableSheet` with `initialChildSize: 0.65` should keep it bounded. Verify on a 360×640 device.

---

## Test plan (overall)

```bash
# Per-obs unit + widget tests
flutter test test/home/home_header_layout_test.dart
flutter test test/home/home_header_provider_test.dart
flutter test test/profile/rank_ladder_gate_text_test.dart
flutter test test/profile/rank_ladder_screen_test.dart
flutter test test/profile/rank_service_sheet_link_test.dart
flutter test test/nutrition/nutrition_header_layout_test.dart
flutter test test/home/today_macro_block_test.dart
flutter test test/ai_coach/compass_tools_sheet_test.dart

# Full suite — must pass before APK build
flutter test
```

Expected: 893 → ≥ 901 pass after this batch. Pre-existing 4 fails remain, no new red.

---

## Manual QA checklist (post-APK install)

- [ ] Home header: greeting + name + streak pill all visible on one row at 360 dp, no truncation for sub-15-char names
- [ ] Home header: tap streak pill → `StreakExplainerSheet` opens (regression check)
- [ ] Today macros: visually one block, hairlines between rows, ◇ ◆ ▲ glyphs render
- [ ] Profile rank chip → service record sheet → footer says `VIEW LIFETIME LADDER →` → tap opens new full-screen
- [ ] Lifetime ladder: 11 ranks in order, current rank has gold left-border + CURRENT chip, future ranks 35% opacity + lock glyph
- [ ] Bottom summary tile shows non-zero values for an account with completed workouts
- [ ] Nutrition header: NO linear bar, streak pill on title row
- [ ] AI coach: compass button visible left of input, tap → sheet opens with 4 family sections, 15 commands
- [ ] Tap a command → input prefilled with the starter phrase, sheet closes, keyboard appears

---

## Rollout

1. Branch `feat/apk-test-10-batch` off main.
2. Implement obs 1 → 4 → 3 (cheapest first, sanity-check the visual flow).
3. Implement obs 2 (largest — new screen + service rewrite).
4. Implement obs 5 (new sheet widget).
5. Run full test suite. Resolve any non-pre-existing failures.
6. `/build-apk` → install on device → run manual QA checklist.
7. Merge to main `--no-ff` with batch commit message.
8. Write retrospective memory `project_apk_test_10_batch.md` covering decisions made + any tweaks that surfaced during implementation.

---

## Out of scope (deferred)

- Time-aware eyebrow variant text decisions (`WELCOME BACK,` vs `GOOD MORNING,`) — locked the time-aware path; user reaction during APK QA can iterate on phrasing without code change.
- AI-coach compass alt UI (4-family chip strip vs single sheet) — user locked the sheet pattern; chip strip not built.
- Promotion-celebration changes — Test #6 already shipped this; no changes needed.
- Migration / Edge function work — none required for this batch.
