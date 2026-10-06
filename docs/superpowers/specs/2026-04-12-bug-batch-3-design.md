# Bug Batch #3 — Design Spec

**Date:** 2026-04-12
**Status:** Draft — awaiting user review
**Bugs covered:** #20 (food log delete UX) · #21 (profile layout redesign) · #22 (PRO pill brushed metallic, gold/silver tiers) · #23 (avatar size bump) · #24 (pace picker + goal projection) · #25 (streetlight nav bar)

## Context

Six UI/UX enhancements surfaced by the user on the morning of 2026-04-12 while reviewing the app post-Bug-Batch-#2. All are independent except #21/#22/#23, which share `profile_identity.dart` and must land in a single commit.

Two of the six are pure visual enhancements (#25 streetlight, #23 avatar bump). Two are small UX fixes (#20 delete confirm, #21 profile reorder). One is a visual-design-with-behavior (#22 PRO pill). One is a significant behavioral change that touches onboarding, edit profile, the BMR calculator, storage, sync, and the Supabase schema (#24 pace picker + projection).

Per user's standing rules: no code changes, no APK builds, no implementation until this spec is reviewed AND the follow-up implementation plan is explicitly approved at least twice.

---

## Bug #20 — Food log delete confirmation + undo

### Problem

The user swiped to delete a logged food from "Today's Meals", but the swipe triggered an immediate hard delete with no confirmation. There was no way to recover the deleted log. The user's words: *"I deleted by mistake the food log. It should ask me confirmation before deleting it. And no option of bringing it back."* (Later clarified: undo IS wanted, for a short window.)

### Root cause

`lib/features/nutrition/screens/nutrition_screen.dart:234` calls `deleteFoodLog` directly from the swipe dismissible with no guard. `nutrition_provider.dart:777-786` hard-deletes from Hive (`HiveService.instance.nutritionBox.delete(logId)`) and syncs to Supabase. No confirmation dialog, no snackbar, no undo path.

### Fix

Two-stage guard:

1. **Confirmation dialog.** On swipe-to-dismiss (or pencil-icon tap → delete option), show an `AlertDialog`:
   - Title: *"Delete this meal?"*
   - Body: *"This will remove it from today's totals. You'll have 5 seconds to undo."*
   - Actions: `[Cancel]` `[Delete]` (Delete is red/destructive)
2. **Undo snackbar.** On confirm, before calling `deleteFoodLog`, stash the complete `FoodLog` map in a local variable. Then delete. Then show:
   - `SnackBar("Meal deleted", duration: Duration(seconds: 5), action: SnackBarAction(label: "Undo", onPressed: () => restoreFoodLog(stashed)))`
3. **Undo restore.** New method `nutrition_provider.restoreFoodLog(Map<String, dynamic> log)` — writes the map back into Hive at a *new* key (deterministic UUID from original `logged_at` + food name to prevent duplicates if the user somehow triggers undo twice). Fires `unawaited(syncNutritionData() + pushSnapshot())`.
4. **After snackbar expires without undo** — nothing to do. The Hive delete + sync already fired.

### Files

| File | Change |
|---|---|
| `lib/features/nutrition/screens/nutrition_screen.dart:234` | Wrap `deleteFoodLog` call in `showDialog` AlertDialog. Stash log, delete, show snackbar. |
| `lib/features/nutrition/providers/nutrition_provider.dart` | New method `restoreFoodLog(Map<String, dynamic> log)` that re-inserts at deterministic new key + syncs. |

### Why no soft-delete

Soft-delete (adding a `deleted_at` flag) would complicate every read path (all queries need `WHERE deleted_at IS NULL`), bloat Hive over time, and force sync-layer changes. The 5-second snackbar window is long enough for accidental deletes, and after that the delete is genuinely permanent — which is the simpler, auditable model.

### Verification

1. Swipe a meal → AlertDialog appears, `Cancel` dismisses without deleting.
2. Swipe → confirm → meal removed from Today's Meals list immediately. Snackbar appears with Undo.
3. Tap Undo within 5s → meal reappears in Today's Meals at the correct position (sorted by `logged_at`).
4. Swipe → confirm → let snackbar dismiss without tapping Undo → meal stays deleted, no way to recover.
5. Swipe → confirm → tap Undo → immediately swipe the same meal again → delete + undo cycle works without duplicate-key errors.

---

## Bug #21 — Profile layout redesign (Layout B with compact achievements)

### Problem

Bug #14 placed the PRO pill directly under the avatar in `ProfileIdentity`, which visually balanced the identity block but wasted the horizontal real estate to the right of the avatar. Meanwhile, the `BadgesGrid` section at `profile_screen.dart:597` occupies a full vertical section further down the page despite most users having 3-5 unlocked badges that could render much more compactly.

User feedback: *"move the pro button on right side. In the empty space between profile pic and pro new button on right, we can try to compact the achievements and show it with drop-down. We only show the recent 3-4 achievements which will fit there and rest can be in drop-down."*

### Fix (Layout B)

Reshape the `ProfileIdentity` widget so the horizontal row containing the avatar also carries:
- **Left:** 80px avatar (new size from Bug #23)
- **Middle:** compact achievements row — 3 most-recently-unlocked badges inline + chevron
- **Right:** `ProPillButton` (brushed metallic, new from Bug #22)

```
════════════ BANNER ════════════
┌──────┐                              ┌─────┐
│Avatar│  [🏆][🎯][🔥] ▼               │ PRO │
└──────┘                              └─────┘
UPEN
Phase 1 · Week 1 · Building Muscle
```

The `BadgesGrid` section at `profile_screen.dart:597` is **deleted entirely from the profile body**. The chevron (▼) in the compact row opens the full `BadgesGrid` as a bottom sheet — reusing the existing widget, not re-implementing it.

### "Recent 3 badges" definition

Sort `unlocked badges` by `unlocked_at` descending, take the first 3. Fallback if fewer than 3 unlocked: pad with locked badges from the grid's natural order (so the row always shows exactly 3 slots, with locked ones rendered at 40% opacity with a small lock overlay).

### Files

| File | Change |
|---|---|
| `lib/features/profile/widgets/profile_identity.dart` | Replace the current single-column layout (banner → avatar → PRO pill under avatar → name column) with: banner → (avatar + CompactAchievementsRow + ProPillButton in a `Row`) → name column. Delete the old under-avatar PRO pill (lines 193-195). |
| `lib/features/profile/screens/profile_screen.dart` | Delete the `BadgesGrid` section currently at line 597. Profile body becomes: identity (with inline achievements + PRO) → daily completion → body stats → journey → nutrition → prediction → reports → health sync → share & grow → settings → subscription. No separate achievements section. |
| `lib/shared/widgets/compact_achievements_row.dart` | **NEW.** Renders 3 badge icons inline (32x32 each, 6dp gap) + chevron icon on the right. On chevron tap, opens the existing `BadgesGrid` in a `showModalBottomSheet`. |

### Verification

1. Profile → identity band shows avatar (left) + 3 badge icons + chevron + gold/silver PRO pill in one horizontal row.
2. Scroll the profile body → no standalone achievements section (it's moved into the identity band).
3. Tap the chevron → bottom sheet opens with the full `BadgesGrid` (locked + unlocked, 3-column grid).
4. User with 0 unlocked badges → compact row shows 3 locked badges at 40% opacity.
5. User with 10 unlocked badges → compact row shows the 3 most recently unlocked (by `unlocked_at`).

---

## Bug #22 — Brushed metallic PRO pill (gold + silver tiers)

### Problem

The current PRO pill (added in Bug #14) is a flat 32px cyan-for-PRO / gold-for-free pill. It communicates state but lacks visual weight — it reads as "another UI element" rather than "premium affordance". User wants it to feel like a physical premium object, matching the subscription banner's gold language but more refined.

### Design decision

Two metallic tiers, one reusable widget. Gold = PRO (you made it). Silver = Free (you're on the lower tier, here's the path up). This matches universal premium-tier language (Olympics, credit cards, streaming memberships).

### PRO state — brushed gold

- **Fill:** `LinearGradient(begin: topCenter, end: bottomCenter, colors: [Color(0xFFFBBF24), Color(0xFFD97706)])` — warm amber/gold
- **Top border:** 1px `Color(0xFFFCD34D)` (light catch)
- **Bottom border:** 1px `Color(0xFF92400E)` (shadow catch)
- **Text:** `PRO` — DM Sans w900 11px, color `Color(0xFF000000)`, 0.5 letter spacing
- **Shadow:** `BoxShadow(color: Color(0x61000000), blurRadius: 8, offset: Offset(0, 2))`
- **Padding:** horizontal 14, vertical 6 → ~72dp wide × 28dp tall
- **Tap:** opens subscription detail sheet (existing behavior — reuse whatever current pill already does)

### Free state — brushed silver

- **Fill:** `LinearGradient(begin: topCenter, end: bottomCenter, colors: [Color(0xFFE5E7EB), Color(0xFF9CA3AF)])` — cool brushed steel
- **Top border:** 1px `Color(0xFFF3F4F6)` (light catch)
- **Bottom border:** 1px `Color(0xFF4B5563)` (shadow catch)
- **Text:** `GO PRO` — DM Sans w900 11px, color `Color(0xFF000000)`, 0.5 letter spacing
- **Shadow:** identical to gold (`black38 / blur 8 / offset (0, 2)`)
- **Padding:** identical to gold
- **Tap:** `showPaywallSheet(context, feature: 'PRO Upgrade')`

Both states are the **same shape, same size, same shadow, same text weight, same padding**. Only gradient + borders + label change. Side-by-side they look like two members of the same design family — instant visual tier comparison.

### New widget

`lib/shared/widgets/pro_pill_button.dart`:
```dart
class ProPillButton extends StatelessWidget {
  final bool isPro;
  final VoidCallback onTap;
  // internally switches gradient + borders + label based on isPro
}
```

### Files

| File | Change |
|---|---|
| `lib/shared/widgets/pro_pill_button.dart` | **NEW.** Widget described above. |
| `lib/features/profile/widgets/profile_identity.dart` | Import and use `ProPillButton(isPro: isPro, onTap: …)` in the Layout B right-hand slot. Delete the old pill code at lines 193-195. |

### Verification

1. Free user → Profile → top-right of identity band shows silver `GO PRO` pill. Tap → paywall sheet opens.
2. PRO user → Profile → top-right of identity band shows gold `PRO` pill. Tap → subscription detail sheet opens.
3. Both pills: same dimensions, same shadow, same border weights, same text padding.
4. Both pills visually distinguishable from cyan accent buttons elsewhere in the app (neither cyan nor flat).

---

## Bug #23 — Profile pic size bump

### Problem

Current avatar diameters feel undersized given how important identity is to the profile experience. Home: 40px (small). Profile: 62px (medium). User: *"make profile pic bigger in home and profile pages"*.

### Fix

| Surface | Current | New | Delta |
|---|---|---|---|
| `home_screen.dart:247-248` header avatar | 40×40 | **48×48** | +8px diameter (+20%) |
| `profile_identity.dart:307-308` profile avatar | 62×62 | **80×80** | +18px diameter (+29%) |

### Banner overlap recalibration

The current profile avatar overlaps the banner by `-31px` (exactly 50% of 62). To preserve the same 50%-below-banner ratio at the new 80px size, change the overlap to `-40px`. This shifts the name+phase block down by ~9dp. Verify during implementation that it doesn't collide with the new compact achievements row from Bug #21.

### Files

| File | Change |
|---|---|
| `lib/features/home/screens/home_screen.dart:247-248` | Change width/height from 40 to 48. |
| `lib/features/profile/widgets/profile_identity.dart:307-308` | Change width/height from 62 to 80. Update banner overlap offset from `-31` to `-40`. |

### Verification

1. Home header → avatar clearly larger than previous build; header strip still fits on 360dp screen without wrapping.
2. Profile identity → avatar feels like a portrait, not a thumbnail. 50% hangs below banner edge. Name + phase block sits ~9dp lower than before.
3. Layout B's compact achievements row still fits horizontally with the new 80px avatar (do NOT let this size bump break the Layout B budget).

---

## Bug #24 — Pace picker + goal projection (target calorie math)

### Problem

Current `bmr_calculator.calculateTargets()` (`lib/core/utils/bmr_calculator.dart:128-210`) takes a `goal` string and applies a **fixed** kcal delta (fat loss → minus fixed number, muscle gain → plus fixed number, maintain → zero). It reads `target_weight_kg` but only uses it as a protein-baseline nudge for fat-loss users. There is **no `timeframe_weeks` / `target_date` field** anywhere in the user profile model.

Consequences:
1. A user who wants to lose 5 kg and a user who wants to lose 25 kg receive the same daily kcal target.
2. Neither can answer "when will I reach my goal?" — the app doesn't know their pace.
3. The `target_weight_kg` input the user fills in at onboarding is effectively unused for the thing it most naturally implies: goal timeline.

User's literal words: *"How is target cals calculated? Are we anywhere taking users timeframe into account. If the user eats this much everyday, when will he reach his Target weight? ... brainstorm."*

### Direction 2 — pace picker with back-computed kcal and projection

Introduce a new `pace_preference` enum field with three values. Each maps to a weekly weight-change rate expressed as a percentage of current body weight. Back-compute daily kcal delta from that rate using the Atwater equivalent for tissue change. Show a projection date next to the kcal target so the user always sees "when".

### New profile field

- **Name:** `pace_preference`
- **Type:** enum/string — one of `slow`, `balanced`, `aggressive`
- **Default:** `balanced` (applied at migration time for existing users and at onboarding for new users who skip the picker)

### Storage

- **Hive (userBox):** `userBox.put('pace_preference', 'balanced')` — read/write via `UserRepository`
- **Supabase (user_profile table):** new column via migration `supabase/migrations/016_add_pace_preference.sql`:
  ```sql
  ALTER TABLE public.user_profile
    ADD COLUMN pace_preference text NOT NULL DEFAULT 'balanced'
    CHECK (pace_preference IN ('slow', 'balanced', 'aggressive'));
  ```
- **Sync:** `SyncService` already upserts `user_profile` on mutation; add `pace_preference` to the upsert payload.

### Pace → weekly rate mapping

| Pace | Rate (% BW/week) | Example for 80kg user | Rationale |
|---|---|---|---|
| `slow` | 0.25% | 0.2 kg/week | Minimum restriction, maximum adherence, muscle preservation |
| `balanced` | 0.50% | 0.4 kg/week | Evidence-based sweet spot for sustainable recomp |
| `aggressive` | 0.75% | 0.6 kg/week | Near upper safe limit; harder to stick with |

Hard clamp: aggressive never exceeds **1% BW/week** regardless of formula output (medical upper bound to prevent excessive muscle loss on a cut or excessive fat gain on a bulk).

### BMR calculator signature change

`BmrCalculator.calculateTargets()` takes a new required named argument `pacePreference` (enum/string). The existing fixed-delta logic is replaced with:

```
weekly_kg_delta = current_weight_kg × pace_rate
  where pace_rate = {slow: 0.0025, balanced: 0.005, aggressive: 0.0075}
  and clamped to max 0.01

daily_kcal_delta = (weekly_kg_delta × 7700) / 7
  // 7700 kcal ≈ 1 kg of body weight change (conservative Atwater)

target_kcal = TDEE + (
  goal == 'lose_fat'     ? -daily_kcal_delta :
  goal == 'build_muscle' ? +daily_kcal_delta :
                            0
)

// Clamp to physiological minimums
target_kcal = max(target_kcal, gender == 'male' ? 1500 : 1200)
```

### Projection math (new method)

`BmrCalculator.projectGoalDate({required double currentKg, required double targetKg, required String pacePreference})`:

```
weight_gap_kg = abs(current_kg - target_kg)
weekly_rate_kg = current_kg × pace_rate  // same mapping as above
weeks_to_goal = weight_gap_kg / weekly_rate_kg
projected_date = DateTime.now().add(Duration(days: (weeks_to_goal * 7).round()))
return (weeks: weeks_to_goal, date: projected_date)
```

### Edge cases

1. `target_weight_kg` within 2 kg of current → force `slow`, clamp projection floor to 4 weeks (no point picking aggressive to lose 1 kg).
2. `goal == 'maintain'` or `'general_fitness'` → no projection shown, no kcal delta applied (TDEE is the target).
3. User not onboarded yet / missing `current_weight_kg` → no projection; nutrition card shows kcal target only.
4. `weeks_to_goal > 104` (2 years) → display as ">2 years" rather than a specific date (aggressive would never produce this; only happens if user sets a very distant target with `slow` pace).
5. Existing users on migration day → default to `balanced`, which most closely matches the current fixed-delta behavior for the majority of users.

### UI changes

**Onboarding** — add pace question inline on the existing goal screen (same screen as the goal picker, added as a second section below it). Keeps onboarding flow length unchanged and groups "what do you want + how fast" as one decision.
- Section title: *"How fast do you want to get there?"*
- Three tappable cards:
  - `Slow — ~0.25% per week` · *"Minimum restriction, easiest to stick with. Best if you've struggled with plans before."*
  - `Balanced — ~0.5% per week (recommended)` · *"The evidence-based standard. Best for most users."*
  - `Aggressive — ~0.75% per week` · *"Near the upper limit. Harder to stick with, more likely to need refeeds."*
- Default selection: `Balanced`

**Edit Profile** — new row labeled "Goal pace" with the current value displayed. Tap opens the same 3-card picker as a bottom sheet. On change, re-computes kcal target immediately and invalidates nutrition providers.

**Nutrition targets card (rendered inline in `profile_screen.dart` at line ~1202 — the "MY TARGETS" row with `_targetChip` calls for TDEE / TARGET / PROTEIN; and also the equivalent targets rendering in `nutrition_screen.dart`)** — add a subtitle under the daily kcal number:
- With valid projection: *"At this pace, you'll reach 80 kg on **Jul 5** (~12 weeks)"*
- Without valid projection (maintain goal, missing target, etc.): hide the subtitle row entirely.
- Tap the row → opens a detail sheet with: current weight, target weight, current pace, projected date, explanation of the math, `[Change pace]` link that opens the pace picker.

### Files

| File | Change |
|---|---|
| `lib/core/utils/bmr_calculator.dart` | Replace fixed-delta logic with pace-based math. Add `projectGoalDate` method. |
| `supabase/migrations/016_add_pace_preference.sql` | **NEW.** Add column with default + CHECK constraint. |
| `lib/features/profile/providers/profile_provider.dart` | Read/write `pace_preference` from Hive + sync. |
| `lib/core/services/sync_service.dart` | Add `pace_preference` to `user_profile` upsert payload. |
| `lib/features/onboarding/screens/goal_screen.dart` (or new `pace_screen.dart`) | Pace picker UI at onboarding. |
| `lib/features/profile/screens/edit_profile_screen.dart` | New "Goal pace" row + bottom-sheet picker. |
| `lib/features/profile/screens/profile_screen.dart` (MY TARGETS row ~line 1202) + `lib/features/nutrition/screens/nutrition_screen.dart` (equivalent targets rendering) | Add projection subtitle + detail sheet. Both surfaces render targets inline — no separate card widget exists today. |

### Verification

1. New user onboards, picks `Balanced`, sets current 85 kg / target 80 kg / goal = lose_fat → nutrition card shows kcal target with subtitle "You'll reach 80 kg on <date ~12 weeks out>".
2. Same user switches to `Aggressive` in Edit Profile → kcal target drops by ~50% of the deficit delta, projection date moves closer by ~4-5 weeks.
3. Same user switches to `Slow` → kcal target rises, projection date moves further out.
4. User with goal = maintain → no projection subtitle, kcal target = TDEE flat.
5. User with current 80 kg / target 79 kg → pace forced to slow, projection clamped to 4+ weeks.
6. Existing user on migration day (no prior `pace_preference`) → defaults to `balanced`, kcal target matches pre-migration value within ±10% (sanity check that migration doesn't silently recompose everyone's target).
7. Supabase row inspection: `user_profile.pace_preference` is populated for all users after migration.
8. Weekly-report Edge Function + AI snapshot include `pace_preference` so AI coach can reference it in replies.

---

## Bug #25 — Streetlight nav bar

### Problem

The current bottom nav bar (`app_router.dart:257-290`) uses Flutter's default `NavigationBar` with a flat `accentTint` indicator pill behind the selected icon. Functional but visually forgettable. User screenshot shows a "streetlight from top" effect — a cone of cyan light shining down onto the selected tab from the top edge of the nav bar — which reads as distinctly premium.

### Design

Override `NavigationBar.indicatorShape` with a custom `ShapeBorder` that paints a vertical linear gradient beam:

- **Beam width:** icon width + 8dp horizontal padding (~48dp)
- **Beam height:** full nav bar height (~72dp with label)
- **Gradient:** `LinearGradient(begin: topCenter, end: bottomCenter, colors: [Color(0xE500D4FF), Color(0x0000D4FF)])` — 90% alpha cyan at top, transparent at bottom
- **Corner radius:** 0 at top (so the beam visually "emerges" from the top edge), 12 at bottom (smooth fade)
- **No pill outline** — the beam IS the indicator

### Icon + label treatment

- **Selected icon:** filled variant, tinted `AppColors.accent` (`#00D4FF`)
- **Unselected icon:** outlined variant, tinted `AppColors.textSecondary`
- **Selected label:** w700 `accent`
- **Unselected label:** w400 `textSecondary`
- **Label visibility:** unchanged — `NavigationDestinationLabelBehavior.alwaysShow`

### Accessibility

Do not rely on the beam alone to indicate selection — keep the icon color change and label weight change as redundant selection cues for users with low vision or dark-mode contrast issues.

### Files

| File | Change |
|---|---|
| `lib/core/router/app_router.dart:257-290` | Replace `indicatorColor: AppColors.accentTint` with a custom `indicatorShape` using a `CustomPainter` / custom `ShapeBorder` that draws the vertical gradient beam. |

### Performance

`CustomPaint` repaints only when the selected tab changes, not every frame. Negligible perf impact even on low-end Android.

### Verification

1. Launch app → home tab selected → vertical cyan beam visible behind the home icon, fading from bright top to transparent bottom.
2. Tap Train tab → beam animates to the Train position (should use the same transition duration as the default indicator).
3. Beam width fits the icon comfortably, doesn't overflow into adjacent tabs.
4. Selected icon is clearly tinted cyan; unselected icons are grey. Labels reflect selection state.
5. Dark theme visual check — beam should pop against the nav bar background without looking harsh.
6. 360dp screen check — beam doesn't overflow or clip on small screens.

---

## Cross-bug files matrix

| File | Touched by |
|---|---|
| `lib/features/profile/widgets/profile_identity.dart` | #21, #22, #23 — must land in the same commit |
| `lib/features/profile/screens/profile_screen.dart` | #21 (delete old `BadgesGrid` section) |
| `lib/features/home/screens/home_screen.dart` | #23 (avatar size) |
| `lib/features/nutrition/screens/nutrition_screen.dart` | #20 (delete confirm + undo) |
| `lib/features/nutrition/providers/nutrition_provider.dart` | #20 (`restoreFoodLog` method) |
| `lib/shared/widgets/pro_pill_button.dart` | #22 (NEW) |
| `lib/shared/widgets/compact_achievements_row.dart` | #21 (NEW) |
| `lib/core/utils/bmr_calculator.dart` | #24 (pace-based math + projection) |
| `lib/features/onboarding/screens/goal_screen.dart` (or new `pace_screen.dart`) | #24 (pace picker) |
| `lib/features/profile/screens/edit_profile_screen.dart` | #24 (pace row + bottom sheet) |
| `lib/features/profile/screens/profile_screen.dart` (MY TARGETS row) | #24 (projection subtitle + detail sheet) |
| `lib/features/nutrition/screens/nutrition_screen.dart` (targets rendering) | #24 (projection subtitle) |
| `lib/core/services/sync_service.dart` | #24 (`pace_preference` in `user_profile` upsert) |
| `lib/core/router/app_router.dart` | #25 (streetlight beam indicator) |
| `supabase/migrations/016_add_pace_preference.sql` | #24 (NEW) |

## Recommended implementation order

1. **#22 — `ProPillButton` widget** (standalone, reusable, no dependencies)
2. **#23 — Avatar size bumps** (small, isolated)
3. **#21 — Profile layout rebuild** (depends on #22 widget + #23 sizes being settled)
4. **#20 — Food log delete UX** (isolated to nutrition screen)
5. **#25 — Streetlight nav bar** (isolated to router)
6. **#24 — Pace picker + projection** (biggest change, touches onboarding + edit profile + BMR + nutrition card + migration + sync — do last)

## Out of scope (deferred, not in this batch)

- **Weekly recalibration from actual weigh-ins** — dynamically adjust kcal if user's 7-day weight trend diverges from projection. Needs trend data + more UX thought. Save for a future batch.
- **AI coach integration with pace preference** — have the coach reference "you're 3 weeks ahead of your pace target" in replies. Requires snapshot schema change + prompt update. Defer.
- **Pace change mid-journey semantics** — if user switches pace halfway through, does the projection reset or extend? Default assumption: extend from today using the new pace, keep the old projection date in history for comparison. Worth a follow-up conversation before implementation of #24.
- **Voice-input + media retry buttons on AI Coach failed bubbles** — out of scope for this batch (was flagged during Bug #19 in Batch #2).
- **Refactoring the subscription banner at the bottom of profile** to reuse `ProPillButton` — tempting, but out of scope to keep #22 minimal. Can be a follow-up PR.

## Rollout rules (user's standing preferences)

- Do NOT begin implementation until this spec is reviewed AND the follow-up implementation plan is explicitly approved at least twice.
- Do NOT build an APK without approval. APK build must use `--flavor prod --release`.
- Structured bug analysis format (bug → cause → fix → verification) required — this spec follows that shape.
- `plan_generator.dart` is not touched in this batch. No authorization needed for its modification.
- Hive-first for all reads/writes. Sync via fire-and-forget `unawaited(SyncService...)`.
- Subscription features must use `subscriptionService.gate()`, never inline `isPro` checks. Bug #22's `ProPillButton` takes `isPro` as an explicit parameter passed from a `gate()`-style read.
