# APK Test #5 Batch — Cross-Account Isolation, Plan Regen, Coach Dispatch, Letterhead Standardization

**Status:** Spec — awaiting user review.
**Date:** 2026-04-28.
**Branch (planned):** `feat/apk-test-5-batch` off main / latest hotfix tip.
**Predecessor:** Builds on APK Test #4 (in `feat/apk-test-4-batch`, partially shipped) — keeps the B1–B5 cross-account guards but tightens them, replaces U7 unified header with a different standardization model, and addresses 6 new observations from the 2026-04-28 device-install session.

---

## 1. Goals

1. **Make cross-account data leaks architecturally impossible.** Avyaansh signing into a fresh account should never see Upendra's Hive coach chats / submissions / schedule / templates / etc. — even if Hive contains stale data and the cloud restore races a guard.
2. **Plan regenerates whenever a plan-driving field changes.** Bumping experience from intermediate → advanced should produce 8-10 exercises, not 4.
3. **AI coach WRITE tools actually dispatch.** Tap a "Reshuffle week" review card and the schedule changes. The card dismisses. Hive is updated. Cloud is synced.
4. **Tab headers feel consistent without flattening identity.** Each tab keeps its own letterhead personality (welcome row on Home, Fraunces serif on others, banner+avatar on Profile) but follows a unified structural rule (eyebrow → title → gold rule → status strip) so rank/streak chip Y position is predictable across tabs.

## 2. Source observations (2026-04-28 install session)

| # | Observation | Theme |
|---|---|---|
| OBS-1 | Saved Advanced + 6 days + Full Gym + 90min → today's plan still showed 4 exercises (expected 8-10 per V4 `targetCount`). Cloud `user_profile` had the new values; the schedule rows were still from the pre-save plan. | B |
| OBS-2 | Selected 6 days/week → schedule showed only 5. Same root cause as OBS-1 (no regen) OR a second plan-generator bug. | B |
| OBS-3 | Signed in as `upendra.prasad@thinkingcode.com` (cloud row exists) — no data restored, profile had to be re-entered, custom exercises not surfaced. Cloud diagnosis: `user_profile.onboarding_completed_at = NULL` despite populated `primary_goal / fitness_experience / weight`. | A |
| OBS-4 | AI coach emitted "Review: Reshuffle week to 6 days" + "Review: Pause 1 day" cards. Tapping does nothing. Cards never dismiss. They pile up in the chat thread. | C |
| OBS-5 | Signed out as Upendra → signed in as Avyaansh → AI coach screen shows Upendra's 13 chat messages. Cloud diagnosis: `ai_coach_interactions` is correctly scoped (Avyaansh = 2 messages, Upendra = 13, separate `user_id` rows). The leak is local Hive only. | A |
| OBS-6 | U7 unified `WardTabHeader` (shipped in Test #4) feels generic — lost personalised greeting on Home, Fraunces serif titles on Nutrition / Coach / Profile, plan header on Train. User prefers the per-tab letterheads with a NEW standardization layer (not a unified header widget). | D |

---

## 3. Theme A — Cross-account data isolation

### 3.1 Goals

- The leak that allowed Avyaansh to see Upendra's chats (OBS-5) cannot recur, even if a future contributor adds a new Hive box without scoping it.
- Upendra-class accounts (cloud `onboarding_completed_at = NULL` but profile populated) self-heal on next sign-in instead of looping back to onboarding (OBS-3).
- Existing test accounts (`upendra.prasad@thinkingcode.com`, `avyaaanshfit@gmail.com`) get a clean test-prep wipe so we don't carry corrupted state into verification.

### 3.2 Four layers (a + b + c combined per Q3)

**Layer 1 — Root-cause investigation (~2h).**

Read every sign-out path + `restoreFromCloudForUser` filter + verify the prod APK actually ships `data_extraction_rules.xml` (Auto Backup exclusion). Goal: identify where the +3 APK leaked despite shipping the B1 fix.

Touch points:
- `lib/features/auth/providers/auth_provider.dart::signOut` (currently the only canonical sign-out)
- `lib/features/auth/screens/splash_screen.dart` (calls `clearAllData` directly on line 124 — secondary path, audit)
- `lib/features/auth/screens/restoring_screen.dart::_ensureOwnershipBeforeHome` (B1.4 guard — verify it actually fires)
- `lib/core/services/sync_service.dart::restoreFromCloudForUser` (verify every fetch filters by `auth.currentUser.id`, not a cached value)
- `android/app/src/main/AndroidManifest.xml` + `android/app/src/main/res/xml/data_extraction_rules.xml` (verify both shipped in `app-prod-release.apk` via `apktool` or `aapt2 dump xmltree`)

Output: a written trace doc (`docs/superpowers/notes/2026-04-28-cross-account-leak-trace.md`) describing the actual leak path. Drives Layer 2's surgical fix.

**Layer 2 — Per-user box namespacing (~6h).**

Migrate from shared boxes to `<box>_<userIdShortHash>` for every user-scoped box.

| Box | Status |
|---|---|
| `userBox` | Namespaced |
| `workoutBox` | Namespaced |
| `nutritionBox` | Namespaced |
| `healthBox` | Namespaced |
| `coachBox` | Namespaced |
| `customBox` | Namespaced |
| `notificationsBox` | Namespaced |
| `exerciseBox` | Shared (seed data, read-only) |
| `foodBox` | Shared (seed data, read-only) |
| `configBox` | Shared (app-level config) |
| `syncBox` | Shared (auth state, last-sync timestamps) |

Naming: `<box>_<first 8 hex of user.id>` — e.g. `coachBox_94368fd4`. Short enough for Windows path length limits (256 chars), still collision-resistant in practice (one app, ≤ 1 active user at a time).

Bootstrap sequence — two-phase init:
1. **Phase 1** (cold start, in `main.dart` before `runApp`): open shared boxes only (`exerciseBox`, `foodBox`, `configBox`, `syncBox`).
2. **Phase 2** (after `_ensureLocalUser` returns successfully): `HiveUserSession.openForUser(userId)` opens the 7 user-scoped boxes. Stamps `syncBox['last_authenticated_user_id'] = userId` after success.
3. **Sign-out**: `HiveUserSession.closeAll()` closes the 7 user-scoped boxes. `clearAllData()` deletes their files (not just `.clear()` — full file delete so leftover bytes can't surface).

Migration of existing local data: one-shot copy on first launch with the new APK — read shared `coachBox`, write to `coachBox_<currentUserId>`, then delete shared box. If the migration fails (unlikely — it's read+write+delete), fall back to "fresh start, cloud has everything anyway."

**Layer 3 — Defense-in-depth ownership guard (~2h).**

Every read of a user-scoped box first checks the box's namespace matches the current `auth.currentUser.id`. Mismatch → throw `HiveOwnershipException` which the global error handler catches and force-signs-out.

Implementation: `HiveService.userBox` etc. become getters that return a `_GuardedBox<T>` wrapper. The wrapper's `get` / `put` / `keys` methods call `_assertOwnership()` first.

```dart
T? _GuardedBox<T>.get(K key, {T? defaultValue}) {
  _assertOwnership();
  return _box.get(key, defaultValue: defaultValue);
}

void _assertOwnership() {
  final session = SupabaseService.instance.client.auth.currentUser?.id;
  final boxOwner = _ownerHash; // captured at openForUser
  if (session == null || boxOwner == null) {
    throw HiveOwnershipException('No active session for user-scoped box');
  }
  if (!session.startsWith(boxOwner)) {
    throw HiveOwnershipException('Box owner $_ownerHash != session ${session.substring(0,8)}');
  }
}
```

The throw path triggers force sign-out + `clearAllData()` + redirect to `/sign-in`. User sees a snackbar: "Session expired. Please sign in again."

**Layer 4 — Recovery for affected accounts (client-only, no SQL — per Q4 = b).**

`RestoringScreen._resolveOnboardingResumeRoute` already checks `onboarding_completed_at`. Update it: when `onboarding_completed_at IS NULL` AND `primary_goal IS NOT NULL` AND `fitness_experience IS NOT NULL` AND `current_weight_kg IS NOT NULL` → treat as "completed enough, restore + go home." Stamp the flag during restore so future sign-ins don't re-evaluate.

```dart
final isOnboarded = profile['onboarding_completed_at'] != null
    || (profile['primary_goal'] != null
        && profile['fitness_experience'] != null
        && profile['current_weight_kg'] != null);
```

If we route to `/home` on the populated-but-NULL case, `_completeOnboardingFromRestore` writes `onboarding_completed_at = NOW()` to cloud + Hive so the inconsistency is resolved.

### 3.3 Test-prep manual step (not code)

Before next test cycle, run:

```sql
DELETE FROM auth.users
WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com');
```

Migration 039's `ON DELETE CASCADE` cleans `public.users` + `user_profile` + `ai_coach_interactions` + every other user-scoped table. Plus uninstall + reinstall the +5 APK on device to clear Hive.

### 3.4 Out of scope for Layer A

- Server-side SQL backfill of historical `onboarding_completed_at = NULL` rows (skipped per Q4 = b — only 2 accounts affected, and we wipe them).
- Encryption-at-rest for Hive boxes (separate brainstorm if needed).
- iOS Auto Backup parity (this app is Android-first; iOS comes later).

### 3.5 Estimate

~12-14h total (2 + 6 + 2 + 2 + 2 buffer for migration edge cases).

---

## 4. Theme B — Plan regen triggers

### 4.1 Goals

- Save Advanced + 6 days + Full Gym + 90min → today's plan regenerates to 8-10 exercises within seconds.
- 6-days-vs-5-days mismatch (OBS-2) is either auto-resolved (if same root cause) or surfaced + fixed as a separate bug.

### 4.2 Surgical fix (~1.5h)

`edit_profile_screen.dart::_save` currently checks:

```dart
final planChanged = _daysPerWeek != _originalDaysPerWeek
    || _goal != _originalGoal
    || _equipment != _originalEquipment;
```

Misses `fitness_experience`, `session_duration_minutes`, `physique_focus`, `injuries` — all plan-driving per the V4 pipeline.

**Fix:**

1. Capture `_originalFitnessExperience`, `_originalSessionDuration`, `_originalPhysiqueFocus`, `_originalInjuries` in `initState` (alongside the existing 3).
2. Extend `planChanged`:

```dart
final planChanged = _daysPerWeek != _originalDaysPerWeek
    || _goal != _originalGoal
    || _equipment != _originalEquipment
    || _fitnessExperience != _originalFitnessExperience
    || _sessionDuration != _originalSessionDuration
    || _physiqueFocus != _originalPhysiqueFocus
    || !_listEquals(_injuries, _originalInjuries);
```

3. Extend the `changes` list display in the reschedule dialog with matching entries (e.g. "Experience: Intermediate → Advanced").

### 4.3 OBS-2 investigation (~1h, may roll into surgical fix)

Branches:

- **A.** Same root cause as OBS-1: user changed days_per_week in the same save where they changed experience; planChanged returned true (because days IS in the check); user tapped "Keep Current Plan" by mistake. Already fixed by 4.2 — once experience is in the trigger, the dialog fires more reliably.
- **B.** Separate bug: `WorkoutScheduleService.generateAndScheduleFromDate` doesn't honour `daysPerWeek=6` correctly. Verify by writing a test that calls it with `daysPerWeek=6` and counts schedule rows. If <6 → bug in the service or downstream V4 pipeline.
- **C.** Pre-existing schedule with completed Mon workout: regen preserves completed days but inserts only 5 new (rest of week) instead of 6. Verify by examining `WorkoutScheduleService` regen logic.

Investigation produces a 1-page diagnosis. If A → already fixed. If B or C → ship the surgical schedule-service fix as part of Theme B.

### 4.4 Out of scope for Theme B

- Restructuring the regen confirmation UX (silent auto-regen vs dialog) — separate UX brainstorm if 4.2 isn't sufficient.
- Changing `targetCount(experience, daysPerWeek)` table values — out of audit scope; current values come from V4 design.

### 4.5 Estimate

~2.5-3h.

---

## 5. Theme C — AI coach tool dispatch UX

### 5.1 Goals

- Tapping a review card for `rescheduleWeek` actually reshuffles the schedule. Tapping `pausePlan` actually inserts the rest day. Tapping cancel dismisses. Hive updates. Cloud syncs.
- Every WRITE tool (12 of 20 per CLAUDE.md §11) follows the same dispatch / confirm / dismiss pattern reliably.
- Cards auto-dismiss after dispatch — they don't pile up in the chat thread.

### 5.2 Surgical fix for `rescheduleWeek` + `pausePlan` (~3-4h)

Investigation first:

1. Read `lib/features/ai_coach/services/tool_dispatcher.dart` — find the dispatch entries for `rescheduleWeek` and `pausePlan`.
2. Trace the card render path — how does the AI coach screen render a `ToolIntent` review card? What's the tap handler? Where does it call `dispatch`?
3. If the dispatcher exists but tap doesn't reach it → wire the tap handler.
4. If dispatch fires but Hive doesn't update → fix the Hive write (likely missing `unawaited(SyncService.instance.syncWorkoutData())`).
5. If Hive updates but card stays → wire auto-dismiss (set the intent's `dispatched_at` Hive flag; card render filters out dispatched intents).
6. Add explicit "Apply" + "Dismiss" buttons on the card so the user has a clear primary action (the chevron-only pattern was unclear).

### 5.3 Audit of all 20 tools (~6-8h)

12 WRITE tools per CLAUDE.md §11 (excluding READ tools that complete server-side):

| Family | WRITE tool |
|---|---|
| Workout | `swapExercise`, `logSet`, `markWorkoutComplete`, `shortenWorkout`, `createCustomExercise`, `modifyWorkoutForInjury`, `rescheduleWeek`, `generateHotelWorkout` |
| Nutrition | `logMealByText`, `adjustCaloricTarget`, `prelog` |
| Plan | `regeneratePlanBlock`, `pausePlan`, `switchGoal`, `createCustomTemplate`, `scheduleTemplate` |

(That's 16 — `suggestMeal` from Nutrition is READ-only.)

Per tool, verify:
- Card renders with explicit Apply / Dismiss actions (not just a chevron)
- Tap → dispatch → Hive write succeeds → fire-and-forget sync → card auto-dismisses
- Failure path → error snackbar (not silent)

Output: a checklist in `docs/superpowers/notes/2026-04-28-coach-tool-audit.md`. Each tool: ✅ / fix-needed (description). Fix everything that's broken.

### 5.4 Out of scope for Theme C

- Redesigning confirmation UX from cards to bottom-sheets (deferred per Q6 = d).
- Reducing tool count (20 tools is in scope per the brilliance spec).
- Server-side tool-loop changes (no Edge Function redeploy this batch unless audit reveals a server bug).

### 5.5 Estimate

~9-12h (3-4 surgical + 6-8 audit).

---

## 6. Theme D — Tab letterhead standardization

### 6.1 Goals

- Revert U7 (the 6 commits `257a5ff` → `bfd89ae`) so each tab gets its old personality back — welcome row on Home, plan header on Train, Fraunces serif letterhead on Nutrition / Coach / Profile.
- Then add a **new** standardization layer that gives the predictable rhythm U7 was after, without flattening tab identity.

### 6.2 Revert (Step 1)

```bash
git revert --no-commit 257a5ff^..bfd89ae
git commit -m "revert U7 unified WardTabHeader (Test #4 → Test #5 redirect)"
```

Six commits to undo:
- `257a5ff` — wardroom WardTabHeader widget
- `4d94075` — home use WardTabHeader
- `5c8bcf3` — train use WardTabHeader
- `2efa0fe` — nutrition use WardTabHeader
- `f772cc7` — ai_coach use WardTabHeader
- `bfd89ae` — profile use WardTabHeader

### 6.3 Standardization layer (Step 2)

#### 6.3.1 Letterhead structure rule

Every tab's top zone follows:

```
┌─────────────────────────────────────────┐
│ [eyebrow mono caps · 10sp]              │
│ [Fraunces 28sp title]      [trailing]   │
│ ────                       (gold rule)  │
│ [status strip — streak + freeze + opt   │
│  rank chip]                             │
└─────────────────────────────────────────┘
```

Variations:
- **Home:** avatar 44dp inline on the LEFT of the eyebrow + title block. Streak chip in the trailing slot.
- **Profile:** banner 110px replaces the top zone visually. Eyebrow floats top-left on the banner at parchment 65% alpha. 80px avatar overlaps banner bottom. Name renders below the banner (acts as the Fraunces title). Gold rule below name. Status strip below.
- **Train / Nutrition / AI Coach:** standard structure — eyebrow + Fraunces title + gold rule + status strip. Trailing pill (Diet Plan / Upgrade / etc.) sits in the title row's right slot.

#### 6.3.2 Eyebrow + title content

| Tab | Eyebrow | Fraunces 28sp title | Source |
|---|---|---|---|
| 🏠 Home | `DAILY · TUE 28 APR` | `Good afternoon, <FirstName>.` | Date dynamic via `DateTime.now()`; greeting via `userGreetingProvider` (existing); name from `userFirstNameProvider` |
| 🏋️ Train | `TRAIN · WK 2 OF 4` | `<phaseName>` (e.g. `Foundation`) | Week from `WorkoutScheduleService.getCurrentWeekNumber()` + plan total weeks; phase name from current `Phase.name` |
| 🥗 Nutrition | `GALLEY · TUE 28 APR` | `Fueling the plan` | Date dynamic; title static |
| 💬 AI Coach | `THE BRIDGE · 24/7` | `Aye Captain` | Both static |
| 👤 Profile | `DOSSIER · OFFICER` (floats on banner top-left @ 65% alpha) | `<full_name>` (e.g. `Upendra Prasad`) | Eyebrow static; name from `userProfileProvider['full_name']` |

#### 6.3.3 Status strip (below gold rule on every tab)

A thin row containing chips:

| Tab | Strip content |
|---|---|
| 🏠 Home | `🔥 12 D` `❄ 2` `▮ SD2 · RECRUIT · NEXT IN 12 DAYS` |
| 🏋️ Train | `🔥 12 D` `❄ 2` |
| 🥗 Nutrition | `🔥 12 D` `❄ 2` |
| 💬 AI Coach | `🔥 12 D` `❄ 2` |
| 👤 Profile | `🔥 12 D` `❄ 2` `▮ SD2 · RECRUIT · NEXT IN 12 DAYS` |

Chip styling reuses existing `StreakBadge` + new `FreezeBadge` (small variant) + existing `RankChip` (compact pill). All three sit in a `Wrap` so they reflow on narrow screens.

#### 6.3.4 Eyebrow formula rule (for future tabs)

Every eyebrow must be `WORD · CONTEXT` (2 segments) or `WORD · CONTEXT_A · CONTEXT_B` (3 max). `WORD` is the tab's military/Wardroom letterhead noun (`DAILY` / `TRAIN` / `GALLEY` / `THE BRIDGE` / `DOSSIER`). `CONTEXT` is dynamic state — date, week, phase, or `24/7` for always-on.

No more than 3 segments. No "CAPTAIN" duplication if the title already contains the word.

#### 6.3.5 Trailing pill rule

Tabs that need a top-right action pill (Nutrition's "🍽 DIET PLAN", Coach's "↑ UPGRADE") render it in the title row's right slot — same Y as the Fraunces title. Tabs without a trailing pill leave that slot empty.

### 6.4 New / modified Wardroom primitives

- **`WardLetterhead`** — already exists. Extend to support an optional `leadingAvatar` slot for Home's pattern.
- **`WardStatusStrip`** — NEW. `Wrap` of `StreakBadge` + `FreezeBadge` + optional `RankChip`. Sits below the gold rule.
- **`FreezeBadge`** — NEW small variant of `StreakBadge` styling (parchment text, `bgRaise` background, ❄ glyph).

### 6.5 Out of scope for Theme D

- Wholesale restructure of tab body content (only the top zone changes).
- Avatar on Train / Nutrition / Coach (explicitly excluded — Home + Profile only).
- New tab eyebrow vocabulary beyond the 5 specified.
- Bottom nav avatar pattern (deferred — bottom nav stays icon-based).

### 6.6 Estimate

~8-10h (revert + new primitive + 5 tab refactors + content wiring).

---

## 7. Sequencing + risk

| Order | Theme | Why first |
|---|---|---|
| 1 | A — Cross-account isolation | Privacy bug. Ship-blocker. Other themes don't matter if data is leaking. |
| 2 | B — Plan regen triggers | Plan-correctness bug. User-trust. Once locked, everything else is verifiable. |
| 3 | C — AI coach tool dispatch | UX bug. High user-impact but data integrity not affected. |
| 4 | D — Letterhead standardization | Polish. No data risk. Easiest to revert if we hit time pressure. |

Themes A + B + C are in scope no matter what. Theme D is the lowest-stakes — if the audit in Theme C uncovers more broken tools than expected, Theme D can split into a Test #6.

### Risk register

| Risk | Theme | Mitigation |
|---|---|---|
| Per-user box namespacing breaks startup ordering on slow devices | A | Two-phase init explicit. Phase 1 boxes always available. Test on cold-start fresh install. |
| Migration of existing local data fails for some users | A | Fallback: if migration throws, fresh start (cloud has the data anyway). Log the failure to `client_errors`. |
| Plan regen audit reveals a deeper V4 pipeline bug (not just `planChanged`) | B | Investigation phase budgets 1h before fixing. If deeper issue found, scope decision: include in B or carry to Test #6. |
| Coach tool audit reveals 5+ broken tools | C | Fix the worst offenders (`rescheduleWeek`, `pausePlan`, plus any reported by user). Defer rest to Test #6 if time-blown. |
| U7 revert touches conflicting files modified after the revert window | D | Revert is `git revert --no-commit 257a5ff^..bfd89ae` — git surfaces conflicts. Resolve manually before commit. |

## 8. Total estimate

| Theme | Hours |
|---|---|
| A | 12-14 |
| B | 2.5-3 |
| C | 9-12 |
| D | 8-10 |
| **Total** | **31.5-39h** |

Comparable to Test #4 batch scope. Realistic delivery: 3-4 working days for solo execution with subagent dispatch.

## 9. Test-prep manual steps (run before APK Test #5 verification)

1. **Wipe Supabase test accounts:**
   ```sql
   DELETE FROM auth.users
   WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com');
   ```
   Cascade-deletes via migration 039's FK chain.

2. **Uninstall + reinstall** the new APK on device (clears Hive + reboots Auto Backup state).

3. **Re-onboard** both accounts fresh.

4. **Verify** the success criteria below (§10).

## 10. Success criteria

After installing the next APK and re-onboarding both test accounts:

| # | Criterion | Theme |
|---|---|---|
| C1 | Sign in as Upendra → use coach (5 messages) → sign out → sign in as Avyaansh → AI coach screen shows EMPTY thread (Avyaansh's 0 messages from cloud), NOT Upendra's 5. | A |
| C2 | Sign in as Avyaansh → check Profile → no submissions visible → sign out → sign in as Upendra → see Upendra's submissions. | A |
| C3 | (Skipped — Upendra's `onboarding_completed_at = NULL` cleared by wipe; recovery path tested by injecting a synthetic NULL row in dev DB.) | A |
| C4 | Profile → Edit Profile → bump experience Beginner → Advanced → Save → reschedule dialog shows "Experience: Beginner → Advanced" → tap Reschedule → today's plan card shows 8-10 exercises (not 4-7). | B |
| C5 | Profile → Edit Profile → bump days/week 5 → 6 → Save → reschedule dialog → tap Reschedule → calendar strip shows 6 workout days this week (not 5). | B |
| C6 | AI coach → "Mark today as rest day" → review card "Pause 1 day from <today>" appears with Apply + Dismiss buttons → tap Apply → today's calendar entry becomes "Rest" → card disappears. | C |
| C7 | AI coach → "Reshuffle my week" → review card with diff (current vs proposed) → tap Apply → schedule updates → card disappears. | C |
| C8 | Each of 5 tabs shows a letterhead with eyebrow `WORD · CONTEXT`, Fraunces 28sp title, gold rule, status strip below with streak + freeze chips (rank chip on Home + Profile only). | D |
| C9 | Home letterhead has 44dp avatar on the LEFT. Train / Nutrition / AI Coach have NO avatar. Profile has banner + 80px avatar overlap. | D |
| C10 | AI Coach title reads `Aye Captain` (not "Good afternoon, Upendra"). Eyebrow reads `THE BRIDGE · 24/7` (no "CAPTAIN" duplicate). | D |

## 11. Open questions deferred to next batch

- Whether to redesign the AI coach confirmation UX from inline cards to bottom-sheet (Q6 option c) — only if audit in 5.3 shows persistent UX issues.
- Whether to lower DOB cap below 10 with a guardian flow (deferred from Test #4 spec OQ-2).
- Whether to add eyebrow vocabulary for new tabs beyond the 5 in scope (only when a 6th tab is added).
- Whether to ship server-side SQL backfill for `onboarding_completed_at = NULL` (skipped this batch — no live affected accounts after wipe).
