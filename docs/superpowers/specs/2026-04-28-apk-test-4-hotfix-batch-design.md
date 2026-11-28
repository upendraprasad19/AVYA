# APK Test #4 Hotfix + UX Batch — Design Spec

**Date:** 2026-04-28
**Author:** Upendra (with Claude as design partner)
**Status:** Draft, pending user review
**Branch (proposed):** continue on `feat/apk-test-4-batch` (already pushed to origin)
**Trigger:** On-device install of Test #4 surfaced 9 distinct issues — 5 bugs (1 P0 cross-account leak, 4 P1) + 4 UX redesigns. User chose scoping option **C** (ship everything in one batch).

---

## 1. Summary

After installing the rebuilt Test #4 APK (`+2` versionCode), 9 issues surfaced. This spec defines the fixes for all of them in a single follow-up batch, shipping as additional commits on `feat/apk-test-4-batch`.

**Total scope:** ~22-28h across 4 implementation plans (A/B/C/D below).

The single biggest fire is **#1 cross-account Hive leak** — user signed out from one account and signed in to another, but sees the prior account's data throughout the app. This is a production-blocker.

Everything else is fixable in parallel with disciplined testing.

---

## 2. The 9 items

### Bugs (5)

| # | Symptom | Severity |
|---|---|---|
| **B1** | Cross-account Hive leak — user signs out + signs in as different account, sees prior account's data | P0 |
| **B2** | Streak freeze auto-consumed on first launch for new account | P1 |
| **B3** | Coach "ran out of steps" answer to "what's my workout today?" | P1 |
| **B4** | Profile RANK card shows "-13 days" (negative countdown); chip header shows correct positive number | P1 |
| **B5** | RestoringScreen "Pulling dispatch" silently fails / times out | P1 (related to B1) |

### UX redesigns (4)

| # | Item | Severity |
|---|---|---|
| **U6** | Profile RANK card move ABOVE Profile Completion (from current "above Daily Goals" position) | P2 |
| **U7** | Unified tab headers across all 5 tabs — eyebrow per tab + rank chip at same Y position | P2 |
| **U8** | Referral code: remove from welcome screen; add to signup form + Profile | P2 |
| **U9** | Welcome screen premium/military redesign (Direction B — reduce + regiment) | P2 |
| **U10** | DOB picker — lower min-age cap from 13 to 10 (no guardian flow) | P2 |

---

## 3. Detailed problem analysis + fix per item

### B1 — Cross-account Hive leak (system-wide)

**Symptom:** User signs out from account A → signs in as account B. Edit Profile correctly shows account B's email (read from `Supabase.auth.currentUser.email` directly). All other surfaces show account A's data — workouts, plan, coach memory, rank, streak, etc.

**Root cause analysis (3 likely contributors):**

1. **`clearAllData()` only covers 8 of 11 boxes.** `notificationsBox` (added later in PR AG) was never added to the clear list. Same for any future-added boxes.

2. **`_ensureLocalUser` cross-account guard misses the "existing == null" path.** After proper sign-out, `userBox['profile']` is null. Cross-account check (`existingId != user.id`) never fires because `existing == null`. So if signOut SOMEHOW failed mid-way and OTHER boxes still have data, the guard never catches it.

3. **No "last authenticated user id" anchor.** Hive has no record of which account it belongs to. Any future signOut bug that fails to clear leaves stale data with no detection mechanism.

**Fix surface:**

A) **Add `notificationsBox` to `clearAllData()`** (`lib/shared/repositories/user_repository.dart:200-210`). Trivial.

B) **Add `last_authenticated_user_id` to `syncBox`.** Stamp it on every successful sign-in. On every `_ensureLocalUser` call, compare `last_authenticated_user_id` vs `currentUser.id` — if mismatch, **always** call `clearAllData()` regardless of whether `existing == null`. This catches silent signOut failures.

C) **Strengthen `_ensureLocalUser`** to write `last_authenticated_user_id` AFTER successful sign-in completes.

D) **Strengthen `signOut()` ordering:** if `clearAllData()` throws, the entire signOut should fail loudly (snackbar to user) instead of silently leaving Hive in a partial state. Currently the code at `auth_provider.dart:293` awaits `clearAllData` but if it throws, the catch upstream might swallow.

**Files modified:**
- `lib/shared/repositories/user_repository.dart` — add notificationsBox to clearAllData
- `lib/features/auth/providers/auth_provider.dart` — strengthen _ensureLocalUser cross-account check
- `lib/core/services/hive_service.dart` — expose `lastAuthenticatedUserIdKey` constant (in syncBox)

**Tests:**
- New unit test `test/auth/cross_account_isolation_test.dart`:
  - Stamp `last_authenticated_user_id = 'A'` in syncBox; populate userBox with profile
  - Call `_ensureLocalUser(user_id='B')` — assert ALL boxes cleared (incl notificationsBox)
  - Assert `last_authenticated_user_id = 'B'` after
- Source-grep test `test/contracts/clear_all_data_box_coverage_test.dart`:
  - Read `lib/core/services/hive_service.dart` for all `*Box` getters
  - Read `clearAllData()` body
  - Assert every Box (except `exerciseBox`/`foodBox` seed data) is cleared

### B5 — RestoringScreen "Pulling dispatch" silently fails

**Symptom:** When upendra signed in (to a phone with avyaansh's Hive), "Pulling dispatch" UI showed but data didn't restore. User landed on /home with avyaansh's data still visible.

**Root cause analysis (related to B1):**

`RestoringScreen` runs `restoreFromCloudForUser()` in parallel with the `user_profile` lookup. The lookup tells RestoringScreen whether to await restore or cancel it.

If `user_profile` lookup hits an error (network, RLS, etc.), the screen MAY route to /home prematurely with whatever Hive currently contains. Per CLAUDE.md §13a: "row + onboarding_completed_at IS NOT NULL → await restore → /home (15s timeout safety)."

If restore times out at 15s or throws silently, user lands on /home with stale Hive.

**Fix surface:**

A) **RestoringScreen MUST not navigate to /home if Hive's `last_authenticated_user_id` doesn't match the current session user.id.** Add this guard before the navigate. If mismatch → call `clearAllData()`, then await restore, then navigate.

B) **Surface restore failures as toast on /home.** "Restore incomplete — pull-to-refresh on Home" or similar. Don't silently fall through.

C) **Increase the timeout from 15s to 30s** for slow networks, OR show a "still working..." indicator after 10s.

**Files modified:**
- `lib/features/auth/screens/restoring_screen.dart`

### B2 — Streak freeze auto-consumed for new account

**Symptom:** User creates new account today, completes onboarding. On first opening of any streak-displaying screen, sees "0 freezes" or "1 freeze used" — but they've never opened a workout yet.

**Root cause:** `WorkoutRepository.calculateCurrentStreak()` (lines 113-188) walks backward 365 days from today. For each day with a `schedule_<date>` row, if `status != 'completed'` AND `i > 0` (not today) AND a freeze is available → **automatically consume freeze**.

The plan generator creates schedule rows for the user's plan period — including today's "this Monday." If user onboarded Tuesday Apr 28 and plan starts Mon Apr 27, schedule has Apr 27 = pending. calculateCurrentStreak walks back, hits Apr 27, calls it a "missed scheduled day," consumes the freeze.

But the user **literally couldn't have done that workout** — they didn't have the app yet.

**Fix:**

In `calculateCurrentStreak()`, before the loop, determine an "earliest valid date" anchor:
```dart
final progress = UserRepository.instance.getProgress() ?? {};
final profile = UserRepository.instance.getProfile() ?? {};

// Earliest of: onboarding_completed_at, plan_start_date, first_workout_date
final anchorDate = _earliestUserAnchor();
```

In the walk-back loop, **break early when `date.isBefore(anchorDate)`** instead of consuming a freeze. The user can't be penalized for days that pre-dated their account.

**Files modified:**
- `lib/features/train/repositories/workout_repository.dart` — `calculateCurrentStreak()` + new helper `_earliestUserAnchor()`

**Tests:**
- New test: seed Hive with `onboarding_completed_at = today`, `schedule_<yesterday> = pending`, run `calculateCurrentStreak()` — assert streak = 0, NO freeze consumed (was 1, still 1).
- Existing streak tests must continue passing.

### B3 — Coach "ran out of steps" / Manual §8 routing too aggressive

**Symptom:** User asks "what's my workout today?" Coach replies "I started working on that but ran out of steps — try again with a more specific request."

**Root cause:** `runToolLoop` hits its 3-round budget. Captain Manual §8 instructs: *"a specific date, year, month, or temporal phrase ('last year', 'March', 'two months ago', 'when did I') → call getExerciseHistory or getPRTimeline. Do NOT infer from snapshot."*

Gemini probably parses *"today"* as a temporal phrase and calls `getExerciseHistory` repeatedly looking for a "today" workout — instead of just reading `snapshot.today_workout`.

**Fix surface:**

A) **Captain Manual §8 — refine routing rule** to differentiate PAST temporal queries from PRESENT/TODAY queries:

```
TOOL ROUTING:

PAST temporal queries — these CALL tools:
- "last year", "in March 2025", "two months ago", "when did I", "show my history"
- → Call getExerciseHistory or getPRTimeline. Do NOT infer from snapshot.

PRESENT/TODAY queries — these READ FROM SNAPSHOT, do NOT call tools:
- "today", "right now", "this week", "current", "what's my workout"
- → Read snapshot.today_workout, snapshot.current_plan_summary,
  snapshot.week_lookahead, etc. directly. NEVER call a tool for "today" data.
```

B) **Tool-loop max-round fallback** (`supabase/functions/_shared/tool-loop.ts`): when 3 rounds exhausted, instead of returning whatever raw text the model emitted (which may say "I ran out of steps"), inject a Captain-voice fallback that summarizes what's available in snapshot. Example:

```
"Recruit — I had trouble pinning that down via tools. Reading the
manifest directly: today is [today_workout.type], [N] exercises, ~[Y]
min. Try again or be more specific."
```

**Files modified:**
- `supabase/functions/_shared/captain_manual.ts` (Manual §8 update)
- `supabase/functions/_shared/tool-loop.ts` (max-rounds fallback)
- Re-deploy ai-proxy

### B4 — Profile RANK shows "-13 days"

**Symptom:** Profile screen RANK card collapsed summary shows "Next: Seaman 1st Class in -13 days" (negative). Daily/Workout chip header shows "NEXT IN 13 DAYS" (positive). Two code paths computing the same ETA inconsistently.

**Root cause:** Probably `_calculateNextRankEta` in `service_record_section.dart` (or the helper it uses) does `now - target.add(N.days)` instead of `target.add(N.days) - now`. Sign reversed.

**Fix:**

Find the negative-ETA computation in `service_record_section.dart` (or `RankService.getNextRank()` if helper is shared) and reverse the operands. Use **the same code path** as the chip header to ensure consistency — likely `RankService.daysUntilNextRank()` if it exists. If it doesn't, extract a single helper and use it in both surfaces.

**Files modified:**
- `lib/features/profile/widgets/service_record_section.dart`
- Possibly `lib/core/services/rank_service.dart` (if extracting helper)

**Tests:**
- Snapshot test on `_buildCurrentRankSummary` — assert the rendered string never contains "-" before a number

---

### U6 — Profile RANK card position move

**Current order on Profile (post-OBS-5):**
1. ProfileIdentity (name + avatar + "STRENGTH · BEGINNER")
2. ProfileCompletenessCard (87%)
3. ServiceRecordSection (RANK card — moved here in OBS-5)
4. Daily Goals
5. Badges
6. Phase Progress
7. Body Stats

**New order:**
1. ProfileIdentity (header)
2. **ServiceRecordSection (RANK card — moved up)**
3. ProfileCompletenessCard
4. Daily Goals
5. ...

**Files modified:**
- `lib/features/profile/screens/profile_screen.dart` — reorder children

### U7 — Unified tab headers (5 screens)

**Pattern:**

```
┌─────────────────────────────────────────────┐
│ [avatar 32dp] [TAB EYEBROW — mono]  🔥8 ❄0 │  56dp
├─────────────────────────────────────────────┤
│ ⭕ SEAMAN 2ND CLASS · NEXT IN 13 DAYS       │  36dp
├─────────────────────────────────────────────┤
│ Tab-specific content...                     │
```

**Eyebrows per tab (Captain voice):**

| Tab | Eyebrow | Replaces |
|---|---|---|
| Daily | `DAILY BRIEF` | "WELCOME BACK, [NAME]" greeting (dropped per design decision i) |
| Workout | `TRAIN` | (no current header — net new) |
| Nutrition | `FUEL` | (current state TBD — likely some existing header) |
| Coach | `DISPATCH` | "Good morning, [name]" greeting |
| Profile | `DOSSIER` | (current state — STRENGTH · BEGINNER eyebrow stays) |

**New widget:** `lib/shared/widgets/wardroom/ward_tab_header.dart`

```dart
class WardTabHeader extends StatelessWidget {
  final String eyebrow;        // "DAILY BRIEF", "TRAIN", "FUEL", etc.
  final String? userInitial;   // "A" for avatar
  final int streakDays;
  final int freezesAvailable;
  final VoidCallback? onAvatarTap;

  // Renders: [avatar] [eyebrow text] [Spacer] [streak chip] [freeze chip]
}
```

**Used in:**
- `lib/features/home/screens/home_screen.dart`
- `lib/features/train/screens/train_screen.dart`
- `lib/features/nutrition/screens/nutrition_screen.dart`
- `lib/features/ai_coach/screens/ai_coach_screen.dart`
- `lib/features/profile/screens/profile_screen.dart`

Plus a separate `WardRankPill` widget if it doesn't already exist — full-width rank chip displayed below the header on every tab.

**Files modified:**
- 5 tab screens
- 2 new shared widgets

**Risk:** Cross-cutting refactor. If the existing tab headers have specific concerns (e.g., Coach has "13 msgs left today" pill, Daily has time-of-day greeting), need to PRESERVE those — they go into the header row alongside or below the streak/freeze chips.

### U8 — Referral code positioning

**Current state:** Referral code field appears on welcome/sign-in screen for ALL users (signin + signup paths).

**New state:**

| Surface | Show referral input? |
|---|---|
| Welcome / sign-in landing | ❌ Removed |
| Email/phone signup form (sign-up mode only) | ✅ Optional field "Have a referral code? Apply for +7 days PRO" |
| Profile → Invite Friends sheet | ✅ "Apply referral code" entry (already exists per memory; may need UI flesh-out) |

**Files modified:**
- `lib/features/auth/screens/sign_in_screen.dart` — remove referral field from welcome view
- Same file or separate signup view — add referral field to signup form path
- `lib/features/profile/widgets/invite_friends_sheet.dart` (or equivalent) — confirm or add code-entry UI

### U10 — DOB picker min-age cap lower (13 → 10)

**Symptom:** User couldn't enter their son's DOB (2019, 7 yrs old) in the onboarding date picker because `lastDate: DateTime(now.year - 13)` enforces min age 13.

**User decision:** Option (c) from prior triage — lower the cap to **10** (not 13, not 8) without introducing a guardian-managed account flow. Trade-off accepted: less COPPA-aligned but simpler.

**Fix:**

`lib/features/onboarding/screens/identity_screen.dart` line 74:
```dart
// BEFORE:
final max = DateTime(now.year - 13, now.month, now.day);
// AFTER:
final max = DateTime(now.year - 10, now.month, now.day);
```

Plus update the comment / docstring at the top of the file (line 14) from "min age 13" → "min age 10".

**Note for future product review:** lowering to 10 without guardian flow may create CCPA / Indian DPDP compliance questions for users 10-12. Track for legal review post-Test #4. Not in this batch's scope.

**Files modified:**
- `lib/features/onboarding/screens/identity_screen.dart` — single-line + docstring

**Tests:**
- Manual: open DOB picker → confirm year picker shows back to current year minus 10 (e.g., today 2026 → up to 2016)
- Existing onboarding tests should still pass (the cap change doesn't break the picker contract)

---

### U9 — Welcome screen premium/military redesign (Direction B)

Direction B = "Reduce + regiment" (~6-8h):

**Changes:**
1. **Unify all 3 auth buttons** to dark+gold-outline style with brand-color icons (no white Google button)
2. **Tighten vertical spacing** — military forms compact, not airy
3. **Promote ONE primary auth method** (Email or Google) as hero — others demoted to compact icon-only buttons in a row
4. **Replace "CONTINUE WITH"** verb → "ENLIST VIA" / "REPORT IN" (Captain voice)
5. **Replace "Forgot password?"** → "Reset access" small caps mono
6. **Replace "OR"** divider → thin gold rule with mono "—  AUX  —" or no text
7. **Replace footer "JOIN 18,866+ INDIANS..."** → "ENLISTED · 18,866 SAILORS ACTIVE"
8. **Replace "AI-POWERED FITNESS & NUTRITION"** → "FITNESS · NUTRITION · DISCIPLINE" (3 pillars)
9. **Add tiny footer stamp** — "AVYA · v1.0.0+2 · ISSUED 2026" mono dim
10. **Add Captain-voice manifesto line** below the AVYA logo: *"Discipline. Honest data. Twelve months. We change the man."*
11. **Add serial-number arc** under the AVYA wordmark: `· REGISTRATION OPEN · 2026 ·`

**Files modified:**
- `lib/features/auth/screens/sign_in_screen.dart` (welcome view portion)
- May need new tiny widgets: `_MilStampFooter`, `_SerialArc`, etc.

---

## 4. Implementation plan grouping (4 plans)

To keep diffs reviewable and isolate risk:

### Plan A — Critical bug fixes (highest priority, ~6-8h)
- B1 cross-account leak (notificationsBox + last_authenticated_user_id + strengthen guards)
- B5 RestoringScreen guard (depends on B1's last_authenticated_user_id)
- Migration: none (Hive-only)
- Tests: cross_account_isolation_test, clear_all_data_box_coverage_test, restoring_screen_guard_test

### Plan B — Coach + minor bug fixes (~4-5h)
- B2 streak freeze anchor
- B3 Manual §8 routing + tool-loop fallback (re-deploy ai-proxy v59)
- B4 RANK card "-13 days" sign fix

### Plan C — UX small (~3-5h)
- U6 Profile RANK reposition (above Profile Completion)
- U8 Referral code surfaces (remove from welcome, add to signup form + Profile)
- U10 DOB picker min-age 13 → 10 (single-line fix + docstring)

### Plan D — UX large (~10-14h)
- U7 Unified tab headers (5 screens + 2 new widgets)
- U9 Welcome redesign B

---

## 5. Risk + mitigation

| Risk | Likelihood | Mitigation |
|---|---|---|
| B1 fix breaks an existing in-app sign-in flow (e.g., Google OAuth) | Medium | Test all 3 sign-in entry points (Email / Phone / Google) after fix |
| B2 anchor logic excludes legitimate streak days for established users | Low | Anchor is the EARLIEST of (onboarding_completed_at, first_workout_date). For established users, anchor is far in the past, no false skip |
| B3 Manual §8 change makes coach worse for past queries | Low | Tool routing for past queries unchanged — only adds a "present/today → snapshot" carve-out |
| U7 tab header refactor breaks existing tab content | High | Implement screen-by-screen with manual visual smoke check after each |
| U9 welcome redesign breaks signup flow | Medium | Preserve all auth-action onTap handlers; only style changes |
| ai-proxy redeploy mid-batch breaks live coach | Medium | Deploy after Plan B complete; re-deploy is idempotent and rollback is `git revert` |

---

## 6. Out of scope (NOT in this batch)

- Plan generator past-Monday issue (root cause of B2 timing). Workaround in calculateCurrentStreak suffices for now; plan-generator audit comes in a later batch.
- Captain v3 conversational improvements (e.g., response variety, multi-turn coherence)
- Snapshot coverage gaps from prior review (progress photos, swap history)
- New tools (getWeakPoints, compareWeeks, projectWeightETA, oneOffEquipmentOverride) — Manual §8 still notes these are deferred
- "Relaxed" workout label UX explanation (F from prior triage — user chose option d, defer)
- Community items pending-approval UX (G from prior triage)
- Guardian-managed accounts for users < 10 (U10 only lowers cap to 10; under-10 not addressed)

---

## 7. Success criteria

After all 4 plans ship:

1. **B1 must pass:** Sign in as account A → log workout → sign out → sign in as account B (different user) → see EMPTY workout list, NOT account A's workouts. Repeat for nutrition, coach memory, rank, streak. Run on a phone that previously had account A installed (no uninstall required).
2. **B2 must pass:** Create new account today → land on /home → streak chip shows "0 days" with "1 freeze available," NOT "0 freezes."
3. **B3 must pass:** Ask coach "what's my workout today?" → coach answers in Captain voice with the actual workout type + exercises (read from snapshot, no tool call).
4. **B4 must pass:** Profile RANK card collapsed summary shows "Next: [rank] in 13 days" (positive); chip header in Daily/Workout shows same positive number.
5. **U6 must pass:** Open Profile → RANK card is above Profile Completion (was below).
6. **U7 must pass:** Tab between Daily / Workout / Nutrition / Coach / Profile — rank chip appears at IDENTICAL Y position. No flicker. Eyebrows match the spec (DAILY BRIEF / TRAIN / FUEL / DISPATCH / DOSSIER).
7. **U8 must pass:** Welcome screen has NO referral field. Tap signup mode → field appears. Tap Profile → Invite Friends → "Apply referral code" entry visible.
8. **U9 must pass:** Welcome screen reads premium/military per Direction B. All 3 auth buttons unified style. Captain-voice manifesto present.

---

## 8. Sequencing

```
Plan A (B1, B5)  →  Plan B (B2, B3, B4)  →  Plan C (U6, U8)  →  Plan D (U7, U9)
[~6-8h]              [~4-5h]                  [~3-4h]              [~10-14h]
                                                                       ↓
                                                            Bump versionCode → +3
                                                            Rebuild APK
                                                            User on-device verify
                                                            PR to main
```

**Why this order:**
- A first — B1 is P0 production blocker
- B before C/D — bug fixes complete before UX changes minimize merge complexity
- D last — biggest scope, most likely to find unexpected work

---

## 9. Notes for writing-plans

When writing the implementation plan:
- Use TDD where helpful (B1 cross-account isolation, B2 streak anchor — both have clear test expectations)
- For U7 unified tab headers, plan should be screen-by-screen with explicit visual smoke check after each
- For U9 welcome redesign, plan should specify each copy change verbatim so executing agent has no interpretation ambiguity
- Bump versionCode 1.0.0+2 → 1.0.0+3 as last commit before APK build
- All commits authorized per user OQ-equivalent (user said "ship everything" with explicit fix authorization)

---

*End of design spec.*
