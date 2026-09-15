# APK Test #2 Batch — Design Spec

**Date:** 2026-04-25
**Source:** APK testing session 2026-04-25 by founder (account: `upendra.prasad@thinkingcode.com`)
**Branch (suggested):** `feat/apk-test-2-batch`
**Migrations:** 036 (`user_profile.onboarding_completed_at`), 037 (`referral_codes.expires_at` + `referral_redemptions` audit table)

---

## Context

Yesterday's APK Test #1 batch (`feat/apk-test-1-batch`, commit `ebed6eb`) shipped 14 fixes across bugs, onboarding, and UX. APK testing this morning surfaced 23 fresh observations + 4 carry-overs from items that didn't land cleanly. This spec consolidates the 27 items into a single coherent batch.

The batch breaks into:

1. **Critical bug fixes (F1–F17)** — clear root causes located via parallel investigation; no design decisions needed.
2. **Onboarding & auth restructure (Q1, Q2, Q3, Q5)** — restore flow, privacy integration, signup/signin visual continuity, founder credibility (Mission Brief).
3. **Subscription & monetization (Q4, Q6, Q7)** — referral system with 7-day theme, active workout free for all, phase roadmap with read-only previews.
4. **Layout fixes (Q8, Q9, Q10, Q11)** — Details chip rows, Today card two-column with macro tile redesign, chip-based shareable receipt with category-tagged quotes, Train empty states eliminated.

**Out of scope (filed as deferred follow-ups F18–F22):**
- Install Referrer API auto-fill of referral code
- In-app deep-link password reset (carry-over from APK Test #1)
- Goal-personalized phase names on roadmap (`build_muscle` users see Strength Block, `lose_fat` users see Cutting Phase, etc.)
- `future-prediction` Edge Function structured-response wiring
- Full Welcome screen redesign

---

## Decisions Locked (from brainstorm)

| Decision | Choice |
|---|---|
| Restore flow on relogin | Refined Option C — gate on `user_profile.onboarding_completed_at`, branded RestoringScreen with awaited `restoreFromCloud()`, 15s timeout safety net |
| Onboarding signal column | Migration 036 adds explicit `onboarding_completed_at TIMESTAMPTZ`; backfilled from existing rows where `primary_goal IS NOT NULL` |
| Privacy/terms placement | Pre-checked checkbox on signup form, footer text on Welcome, external website links to `https://icanbefitter.com/privacy` + `/terms` |
| Auth screen visual continuity | Compact letterhead (mini AVYA seal + RECRUIT REGISTRY eyebrow + gold rule) on all auth sub-views (email form, phone OTP, forgot password, signup form) |
| Founder credibility placement | New onboarding step 00 "Mission Brief" after sign-up, before Identity. New users only. |
| Founder photo | `assets/naval pics/18052229773959933.heic` (officer pose, medals visible) — converted to JPG for asset bundling |
| Founder copy | Locked verbatim: *"I built AVYA because every fitness app I tried treated me like a number. The plans you'll see in this app aren't algorithmic guesses — they're shaped by 14 years of military training and certified coaching practice. The AI executes the playbook. The playbook is mine. Jai Hind!"* |
| Mission Brief CTAs | Single primary `CONTINUE →`. Subtle inline link "Daily wins on Instagram → @icanbefitter" (handle gold + underlined, opens `instagram://user?username=icanbefitter` with web fallback). |
| Founder micro-references | Plan screen sub-line under "REPORT FOR DUTY": *"Plan shaped by 14 years of disciplined coaching."* AI coach first-message includes one credential nod (e.g., *"Trained on Upendra's 14-year coaching playbook."*) |
| Referral reward | 7 days PRO each side (symmetric) |
| Referral code lifetime | **7 days from generation.** Sender regenerates after expiry. |
| Referral receiver eligibility | Within 7 days of receiver's signup |
| Referral entry points | Welcome screen (optional field) + Profile → "Apply Referral Code" tile (only visible during receiver's 7-day window) |
| Referral cap | None for now |
| Referral install flow | Phase 1: Play Store link + manual code entry. Install Referrer API deferred (F18). |
| Active workout PRO gating | **Removed.** `active_workout_mode` no longer in PRO list — always free for everyone. |
| Train week selector range | 12 weeks visible (3 phases). Weeks 5–12 dim/locked for free users. |
| Phase Roadmap screen | New `/train/roadmap`. 12 phase cards, scrollable, with Roman numeral, name, focus, weeks, "what you'll achieve" bullets. Cross-linked to/from week selector. |
| Read-only workout preview | Real generated plans (local Dart, zero API cost) using user's actual profile. Three-state banner: mid-Phase-I / Phase-I-complete / PRO-browsing-ahead. UPGRADE TO PRO bottom CTA shown only to free users. |
| Details screen layout | All 4 sections become chip rows. Experience + Pace inline 3-chips. Days/Week inline 4-chips. Equipment 2×2 grid. |
| Details chip styling | Selected = gold-fill + black w700 text. Unselected = transparent + textGhost border + textDim text + opacity 0.55. Description below each row updates on selection. |
| Today card layout | Two-column 60/40 ratio. Title `maxLines: 2`. Eyebrow stays inside left column (unchanged). |
| Today card macro tile | 2-line structure: eyebrow + inline number on row 1 (eyebrow left, value right-aligned, `kg` lowercase, format `1820/2983`), bar on row 2. |
| Today card completed state | DONE chip + VIEW CARD button paired in left column (anchored to workout, never crosses into macro column). Best-lift on its own line below. |
| Shareable receipt format | Bracketed chip per set, 1px border, wrap when full. logging_type-aware content (`10 kg × 10 reps`, `60 secs`, `+10 kg × 8 reps`, etc.). |
| Shareable receipt quote | Context-aware — quote pool tagged by category (push/pull/legs/core/full_body/general). Filter to match workout type at render time. Fallback to `general` if no match. |
| Train empty states | **Eliminate empty cards.** Replace with single-line hint text below section header. Gold-accent tappable "+ CREATE" inline word as discoverability path. |

---

## 1. Critical Bug Fixes (F-series)

### F1. Custom exercise sync silently failing — Dart syntax error

**Root cause:** `lib/core/services/sync_service.dart:1564` contains invalid Dart map-literal syntax:
```dart
'default_duration_secs': ?defaultDur,  // ← '?' is not a valid map value operator
```
This throws at runtime when `_projectCustomExercise` builds the upsert payload. The `kDebugMode` trace fires (logging exercise name + id), then the function throws, caught by the outer try/catch as a silent error. Hive write succeeds locally, but Supabase never gets the row. Cascade: B3 + B4 + obs #1 (custom exercise not in YOUR EXERCISES list, not in MY SUBMISSIONS).

**Fix:**
```dart
// Replace line 1564 with:
if (defaultDur != null) 'default_duration_secs': defaultDur,
```

This uses the conditional spread pattern in a map literal — valid Dart 3 syntax.

**Verification:** Create a custom exercise with logging_type=timed, set default_duration_secs=60, save with "Share with community" ticked. Within 5s, row appears in Supabase `user_custom_exercises`. YOUR EXERCISES chip row in Train shows it (PENDING badge). Profile → Submissions → MY SUBMISSIONS shows it.

---

### F2. Logout → re-signin forces onboarding restart

**Root cause:** `splash_screen._navigateNext()` (line 100) fires synchronously before `unawaited(checkAndSync())` (line 163) completes. Router (`app_router.dart:399`) checks `configBox['onboarding_completed']`, which was cleared by `clearAllData()` during logout. Even though `restoreFromCloud()` is in-flight, navigation has already happened — user sent to `/onboarding`.

The cross-account Hive guard (CLAUDE.md §19 row "Cross-account Hive leak on fresh sign-up") wipes Hive correctly when local profile.id ≠ session user.id; the bug is the absence of an await on restore before navigation.

**Fix:** Migration 036 adds explicit `user_profile.onboarding_completed_at TIMESTAMPTZ`. `splash_screen` is restructured into post-auth restore flow (see Section 3 — Q1 architecture).

---

### F3. "Account not synced with server" in AI coach

**Root cause:** Cascades from F2. When user lands in AI coach with empty Hive (restore not yet complete), `pushSnapshot()` sends an incomplete context → Edge Function returns 404/User-not-found → `ai_coach_provider.dart:587-588` maps to that error string.

**Fix:** Solving F2 (await restore before navigation) eliminates this cascade. By the time user opens AI coach, Hive has full profile + workouts + nutrition.

---

### F4. Prediction card shows YAML-style key:value (B2-redux)

**Root cause:** Yesterday's `_sanitisePredictionText` parse guard only triggers when raw text starts with `{` or `[`. Gemini interpreted "no JSON, no code fences" as "use a different structured shape" and returned flat YAML-style:
```
outcome_3_months: weight_kg:77.5. body.
```
The early-return at `ai_coach_provider.dart:695` passes this through unmodified.

**Fix:** Extend `_sanitisePredictionText` to detect `key: value` patterns even without `{`/`[` prefix:

```dart
static String? _sanitisePredictionText(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Existing JSON / code-fence path unchanged...
  if (trimmed.startsWith('{') || trimmed.startsWith('[') || trimmed.startsWith('```')) {
    // ... existing JSON parse logic
  }

  // NEW: detect YAML-ish flat key:value shape
  // Heuristic: contains 2+ "key: " patterns AND no sentence-ending punctuation
  // before the first ":".
  final keyValuePattern = RegExp(r'^[a-z_]+\s*:', multiLine: true);
  final matches = keyValuePattern.allMatches(trimmed).toList();
  if (matches.length >= 2) {
    // Likely structured output. Extract the most prose-y line.
    final lines = trimmed.split('\n');
    String? bestLine;
    for (final line in lines) {
      final colonIdx = line.indexOf(':');
      if (colonIdx == -1) continue;
      final value = line.substring(colonIdx + 1).trim();
      // Pick the longest value that looks like prose (>20 chars, has spaces)
      if (value.length > 20 && value.contains(' ')) {
        if (bestLine == null || value.length > bestLine.length) {
          bestLine = value;
        }
      }
    }
    if (bestLine != null) {
      _writeBackToHive(bestLine); // existing helper
      return bestLine;
    }
    // Fallback: strip the keys, leave just the values joined
    final cleaned = lines
        .map((l) {
          final i = l.indexOf(':');
          return i == -1 ? l : l.substring(i + 1).trim();
        })
        .where((l) => l.isNotEmpty)
        .join(' · ');
    if (cleaned.isNotEmpty) {
      _writeBackToHive(cleaned);
      return cleaned;
    }
  }

  return raw;
}
```

**Also harden the prompts** (`prediction_service.dart` + `onboarding_provider.dart`):
> Add to system prompt: *"Reply in plain English sentences only. DO NOT use any structured format. DO NOT prefix lines with labels like 'outcome:', 'weight_kg:', or any colon-separated keys. Just write 2-3 sentences of prose."*

The triple defense (prompt → JSON guard → key:value guard) makes the prediction card robust to any structured output Gemini might emit.

---

### F5. Stale "Legs B scheduled" insight after plan regenerate

**Root cause:** `home_provider.aiInsightProvider` (computes from `WorkoutScheduleService.getScheduleForDate(now)`) is **never invalidated** in plan-regen or workout-complete paths. Only day rollover invalidates it. Locations:
- `edit_profile_screen.dart:1643-1645` — invalidates `currentPlanProvider`, `todayWorkoutProvider`, `calendarWeekProvider` after `generateAndScheduleFromDate`. Missing `aiInsightProvider`.
- `train_provider.completeWorkout` — invalidates same set + `streakProvider` + `allExercisePRsProvider`. Missing `aiInsightProvider`.

**Fix:** Add `ref.invalidate(aiInsightProvider);` to:
1. `edit_profile_screen._save` (regen path)
2. `train_provider.completeWorkout`
3. `WorkoutScheduleService.generateAndScheduleFromDate` callers (any direct Hive write to `schedule_*` keys)

Add a regression test: `test/providers/ai_insight_invalidation_test.dart` mocks Hive schedule changes + verifies `aiInsightProvider.build()` re-runs after invalidate.

---

### F6. V4 plan generator volume regresses 8 → 4 on days/week change

**Root cause:** `lib/features/profile/screens/edit_profile_screen.dart:1621` reads `profile['detected_experience_level']` — a key that is never written. Onboarding writes the key as `'fitness_experience'` (line 54, 140). Result: experience defaults to 'beginner' on edit-profile regen, `VolumeFilter.targetCount(beginner, 5) = 4` instead of advanced's 8.

**Fix:** Change line 1621:
```dart
// Before:
final experience = (profile['detected_experience_level'] as String?) ?? 'beginner';
// After:
final experience = (profile['fitness_experience'] as String?) ?? 'intermediate';
```

Default fallback also bumped from `'beginner'` to `'intermediate'` since onboarding pre-selects Intermediate as the default anyway.

**Verification:** `test/plan_generator/edit_profile_regen_test.dart` asserts that an Advanced + 5-day profile regenerated from edit-profile produces 8 exercises/day on every day.

---

### F7. Logging type lost through swap

**Root cause:** `lib/core/services/workout_schedule_service.dart:965-967`:
```dart
final newType = (replacement['logging_type'] as String?)
    ?? (original['logging_type'] as String?)
    ?? 'weight_reps';
```
When `replacement` (a custom exercise or library entry without explicit `logging_type`) is used, the fallback to `'weight_reps'` overrides the original's correct type. User reports: swap from Handstand Hold (timed) to Handstand Pushup → target rendered with KG/REPS columns instead of timed.

**Fix:** Resolve `logging_type` from the canonical source before falling back:
```dart
String? resolveLoggingType(Map<String, dynamic> exercise) {
  // 1. Explicit field on the exercise
  final direct = exercise['logging_type'] as String?;
  if (direct != null && direct.isNotEmpty) return direct;

  // 2. Look up in exerciseBox (library) by name
  final name = exercise['name'] as String?;
  if (name != null) {
    final box = HiveService.instance.exerciseBox;
    for (final value in box.values) {
      if (value is Map && value['name'] == name) {
        final t = value['logging_type'] as String?;
        if (t != null && t.isNotEmpty) return t;
      }
    }
    // 3. Look up in customBox by name
    final customBox = HiveService.instance.customBox;
    for (final value in customBox.values) {
      if (value is Map && value['name'] == name) {
        final t = value['logging_type'] as String?;
        if (t != null && t.isNotEmpty) return t;
      }
    }
  }

  return null;
}

// In swapExerciseInDay:
final newType = resolveLoggingType(replacement)
    ?? (original['logging_type'] as String?)
    ?? 'weight_reps';
```

Also a separate audit: confirm `Jump Rope`, `Handstand Hold`, and similar timed exercises have `logging_type: timed` in `assets/data/exercise_library.json`. If missing, regenerate seed migration. Same for `default_sets` defaults on cardio/timed entries (should be 3-4, not 2). This handles obs #11 (Jump Rope shown as weight_reps) at the data level.

---

### F8. Adding 3rd set wipes entered weight

**Root cause:** `active_workout_screen.dart:1147-1206` `_ExerciseCardState` stores `TextEditingController` lists. `didUpdateWidget()` (line 1200-1201) detects the new sets count (2→3) and calls `_disposeControllers() + _initControllers()` — full rebuild. New controllers are then re-populated from provider state, but the just-typed value for set 2 hasn't been saved to provider yet (TextField onChanged is debounced or saves on focus loss).

**Fix:** Append controllers when adding a set instead of full rebuild:
```dart
@override
void didUpdateWidget(covariant _ExerciseCard oldWidget) {
  super.didUpdateWidget(oldWidget);
  final oldCount = oldWidget.exercise.sets;
  final newCount = widget.exercise.sets;

  if (newCount > oldCount) {
    // Append new empty controllers
    for (var i = oldCount; i < newCount; i++) {
      _kgControllers.add(TextEditingController());
      _repsControllers.add(TextEditingController());
    }
  } else if (newCount < oldCount) {
    // Remove trailing controllers (shrink)
    for (var i = oldCount - 1; i >= newCount; i--) {
      _kgControllers.removeAt(i).dispose();
      _repsControllers.removeAt(i).dispose();
    }
  }
  // Don't touch indices [0..min(oldCount, newCount)] — preserve existing values
}
```

**Verification:** Integration test in `integration_test/flows/add_set_preserves_weight_test.dart` enters values in sets 1-2, adds set 3, asserts sets 1-2 values are unchanged.

---

### F9. "WK 17" wrong on home header

**Root cause:** `home_screen.dart:388-389` uses calendar-year math:
```dart
final week = ((now.difference(DateTime(now.year, 1, 1)).inDays) / 7).floor() + 1;
```
This computes ISO-ish week-of-year. For 2026-04-25, that's week 17. Should be plan-relative (week 1 of Phase 1 if user just started).

**Fix:** Replace with `WorkoutScheduleService.getCurrentWeekNumber()` (already exists, used elsewhere correctly).

---

### F10. View Card button overflow on completed Today card

**Root cause:** `today_workout_card.dart:329-380` uses `Row(MainAxisSize.min)` with no `Expanded`/`Flexible` constraints. DONE chip + VIEW CARD button + best-lift summary all flow off the right edge.

**Fix:** Solved by Q9 (Section 4 — Today card layout). The DONE chip + VIEW CARD button are paired in the left column (60/40 ratio); best-lift is on its own line below.

---

### F11. AI food analysis broken

**Root cause hypothesis** (needs APK-log + Supabase row count to confirm): rate-limit trigger `trg_food_text_rate_limit` is firing prematurely. Likely cause: stale subscription cache after restore (user is PRO but client-side cache shows free, hits 50/day cap), OR stale `ai_coach_interactions` rows from a prior session of the same account.

**Fix steps:**
1. Add `kDebugMode` log to `nutrition_provider.analyseFoodText()` capturing the exact 4xx response body from `ai-proxy`.
2. After F2 (restore flow fix), subscription cache is freshly populated post-restore — most likely resolves this automatically.
3. If issue persists after F2: add explicit subscription cache refresh on first food-analysis call after sign-in (`SubscriptionService.invalidateCache()` then `verifyFromServer()`).
4. As defense-in-depth, expose the trigger error to the client with a request_id for support: server logs `[ai-proxy] request_id=X food_text_rate_limit user=Y count=N/cap=M`, client-side toast says "Daily food analysis limit reached. Try again tomorrow." (instead of generic "AI not working" which is misleading).

---

### F12. Custom exercise not in YOUR EXERCISES chip row
Cascade fix — F1 resolves this. The `ValueListenableBuilder<Box>` already renders new exercises live; the bug was that the Hive write itself sometimes failed silently if the chained sync threw early in a way that polluted state. Net of F1: write succeeds, Listenable fires, chip appears.

### F13. Login screen logo continuity (obs #23)
Solved by Q3 (compact letterhead on all auth sub-views).

### F14. Privacy accept screen jarring (obs #19)
Solved by Q2 (inline checkbox, footer text, returning users skip via cloud `users.terms_accepted_at` check).

### F15. Jump Rope shown as weight_reps (obs #11)
Solved by F7's data audit (verify `Jump Rope` entry in exercise library has `logging_type: timed`).

### F16. Default 2 sets on Jump Rope (obs #11)
Same data audit as F15 — verify `default_sets` for cardio/timed entries is 3 or 4 (not 2). Regenerate seed migration if needed.

### F17. DONE pill ambiguity (obs #15)
Solved by Q9 (DONE chip paired with VIEW CARD button in the left column — never floats over macros).

---

## 2. Migrations & Schema

### Migration 036 — `user_profile.onboarding_completed_at`

```sql
-- supabase/migrations/036_onboarding_completed_at.sql

ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;

-- Backfill existing rows where onboarding has clearly completed
-- (primary_goal is required during onboarding step 02 and never null afterward)
UPDATE user_profile
  SET onboarding_completed_at = COALESCE(updated_at, created_at, now())
  WHERE primary_goal IS NOT NULL
    AND onboarding_completed_at IS NULL;

-- Index for the restore-flow query
CREATE INDEX IF NOT EXISTS idx_user_profile_onboarding_completed
  ON user_profile (user_id, onboarding_completed_at);
```

### Migration 037 — `referral_codes.expires_at` + `referral_redemptions`

```sql
-- supabase/migrations/037_referral_redemptions.sql

-- Code expiry on existing referral_codes table (added by migration 035)
ALTER TABLE referral_codes
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ
    NOT NULL DEFAULT (now() + interval '7 days');

-- Backfill existing rows (any pre-2026-04-25 codes get a fresh 7-day window
-- starting now, since they were generated under the "permanent" assumption
-- and we don't want to expire them retroactively)
UPDATE referral_codes
  SET expires_at = now() + interval '7 days'
  WHERE expires_at <= now();

-- Audit table: who redeemed whose code, with both-side reward tracking
CREATE TABLE IF NOT EXISTS referral_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL,
  referrer_id UUID NOT NULL REFERENCES auth.users(id),
  referee_id UUID NOT NULL REFERENCES auth.users(id),
  redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  days_granted_each INT NOT NULL DEFAULT 7,
  CONSTRAINT no_self_referral CHECK (referrer_id != referee_id),
  CONSTRAINT unique_referee_redemption UNIQUE (referee_id)  -- one code per receiver, ever
);

CREATE INDEX idx_referral_redemptions_referrer ON referral_redemptions (referrer_id);
CREATE INDEX idx_referral_redemptions_redeemed_at ON referral_redemptions (redeemed_at);

ALTER TABLE referral_redemptions ENABLE ROW LEVEL SECURITY;

-- Both referrer and referee can read their own redemption rows
CREATE POLICY "Users can read own redemptions" ON referral_redemptions
  FOR SELECT USING (auth.uid() = referrer_id OR auth.uid() = referee_id);

-- INSERT only via Edge Function (service role bypasses RLS)
-- No client-side INSERT policy — referee can't self-create
```

### Edge Function update — `redeem-referral`

```typescript
// supabase/functions/redeem-referral/index.ts
// Pseudo-code for the validation order:

const { code } = await req.json();
const { user: referee } = await getAuthenticatedUser(req);

// 1. Format check
if (!/^AVYA-[A-Z0-9]{8}$/.test(code)) {
  return jsonError(400, "Codes look like AVYA-XXXXXXXX.");
}

// 2. Code lookup + expiry
const { data: codeRow } = await supabase
  .from('referral_codes')
  .select('user_id, expires_at')
  .eq('code', code)
  .single();
if (!codeRow) {
  return jsonError(400, "We don't recognize that code.");
}
if (new Date(codeRow.expires_at) < new Date()) {
  return jsonError(400, "This code has expired. Ask your friend to send a fresh one.");
}

// 3. Self-referral block
if (codeRow.user_id === referee.id) {
  return jsonError(400, "Can't refer yourself, soldier 🫡");
}

// 4. Receiver eligibility window (7 days from signup)
const refereeSignupAge = Date.now() - new Date(referee.created_at).getTime();
if (refereeSignupAge > 7 * 24 * 60 * 60 * 1000) {
  return jsonError(400, "Referral codes are for new recruits — within 7 days of signup.");
}

// 5. Idempotency check (UNIQUE constraint on referee_id catches it, but check first for clean error)
const { data: existing } = await supabase
  .from('referral_redemptions')
  .select('id')
  .eq('referee_id', referee.id)
  .single();
if (existing) {
  return jsonError(400, "Code already applied to your account.");
}

// 6. Atomic write: redemption row + extend both subscriptions by 7 days
const { error: insertErr } = await supabase.rpc('redeem_referral_atomic', {
  p_code: code,
  p_referrer_id: codeRow.user_id,
  p_referee_id: referee.id,
  p_days: 7,
});

if (insertErr) {
  // 23505 unique violation = race condition; treat as success
  if (insertErr.code === '23505') {
    return jsonOk({ alreadyRedeemed: true });
  }
  return jsonError(500, "Internal server error", { request_id });
}

return jsonOk({ days_granted: 7 });
```

The `redeem_referral_atomic` SQL function (defined as part of migration 037) writes the audit row + upserts both subscriptions in a single transaction.

---

## 3. Restore Flow Architecture (Q1)

### The decision tree

```
sign-in succeeds (Supabase auth)
   ↓
RestoringScreen mounts (replaces splash post-auth)
   ↓
parallel:
  ├─ SELECT user_id, onboarding_completed_at FROM user_profile
  │   WHERE user_id = session.user.id
  └─ start restoreFromCloud() (cancellable)
   ↓
branch on query result:
  │
  ├─ row exists AND onboarding_completed_at IS NOT NULL
  │   → await restoreFromCloud() with 15s hard cap
  │   → on complete: navigate to /home
  │   → on timeout: show "Taking longer than usual — you can continue" CTA → /home
  │
  ├─ row exists AND onboarding_completed_at IS NULL
  │   → cancel restoreFromCloud()
  │   → read partial fields from user_profile
  │   → navigate to onboarding at first missing-field step
  │       (Identity if name missing → Goal if goal missing → Stats → Details → Plan)
  │
  └─ row doesn't exist (genuine new user OR signup just happened)
      → cancel restoreFromCloud()
      → navigate to /onboarding/mission-brief (Q5 step 00)
```

### File changes

- **NEW** `lib/features/auth/screens/restoring_screen.dart` — Wardroom letterhead, gold seal, "Pulling your dispatch back from HQ…" copy + animated progress dots, 15s timeout safety button.
- **MODIFY** `lib/features/auth/screens/splash_screen.dart` — split post-auth path off; existing splash logic stays for cold-start non-authed flow.
- **MODIFY** `lib/core/router/app_router.dart` — add `/restoring` route; on auth-state change post-signin, redirect to `/restoring` first instead of `/home` or `/onboarding`.
- **MODIFY** `lib/core/services/sync_service.dart` — `restoreFromCloud()` returns a `Future<RestoreResult>` that the RestoringScreen can await. Adds cancellation support (e.g., when query reveals new user).
- **MODIFY** `lib/features/auth/providers/auth_state_provider.dart` — emit `RestoreReady` state after RestoringScreen completes.

### Restoring screen UI

```
┌────────────────────────────────────────┐
│                                         │
│              ⊙ AVYA                     │  ← centered seal, 80dp,
│           ─────────────                 │     gold ring, glow pulse
│                                         │
│         Pulling your dispatch.          │  ← Fraunces 22sp w800
│                                         │
│       Stand by, soldier.                │  ← italic-gold sub
│                                         │
│       ●  ●  ●                           │  ← 3 dots, animated
│                                         │
│                                         │
│       ┌──────────────────────────────┐  │
│       │  This is taking a while.     │  │  ← only visible after 15s
│       │  CONTINUE  →                 │  │     soft escape hatch
│       └──────────────────────────────┘  │
│                                         │
└────────────────────────────────────────┘
```

The 15s timeout button appears with a fade-in. Tapping it navigates to `/home` and lets restore continue in the background — providers will refresh as data arrives.

### Photos restore note

`progress_photos` are intentionally cloud-primary (no Hive mirror — too large). On first open of the photo gallery after restore, `ProgressPhotoRepository.list()` queries Supabase directly. This works correctly today; the only reason photos appear "missing" right now is because user is stuck on onboarding (F2 cascade). Solving F2 fixes this without separate work.

---

## 4. Layout Specs

### Q8. Details screen — chip rows

```
┌──────────────────────────────────────────┐
│ ← BACK                              04·05│
│                                          │
│  Calibrate your training.               │  ← Fraunces 28sp w800
│                                          │
│  EXPERIENCE                              │  ← mono eyebrow 10sp gold
│  ┌────────┐┌──────────────┐┌──────────┐ │
│  │Beginner││⦿ Intermediate│ Advanced  │ │  ← chip row
│  └────────┘└──────────────┘└──────────┘ │
│  6–24 months consistent training         │  ← description, textDim
│                                          │
│  PACE                                    │
│  ┌──────┐┌──────────┐┌────────────┐    │
│  │Steady││⦿ Balanced│ Aggressive  │    │
│  └──────┘└──────────┘└────────────┘    │
│  Standard transformation rate            │
│                                          │
│  DAYS / WEEK                             │
│  ┌───┐┌────┐┌───┐┌───┐                  │
│  │ 3 ││⦿ 4 ││ 5 ││ 6 │                  │
│  └───┘└────┘└───┘└───┘                  │
│  4 days  ·  most sustainable             │
│                                          │
│  EQUIPMENT                               │
│  ┌────────────┐ ┌────────────┐          │
│  │ Bodyweight │ │ Dumbbells  │          │  ← 2×2 grid
│  └────────────┘ └────────────┘          │
│  ┌────────────┐ ┌────────────┐          │
│  │⦿ Basic Gym │ │  Full Gym  │          │
│  └────────────┘ └────────────┘          │
│  Standard gym setup                      │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │      CONTINUE  →                  │   │
│  └──────────────────────────────────┘   │
└──────────────────────────────────────────┘
```

**Chip styling:**
- **Selected:** gold-fill (`AppColors.accent`) bg + black w700 text + 1px accent border
- **Unselected:** transparent bg + 1px `textGhost` border + `textDim` text + opacity 0.55
- Cross-fade on tap: 150ms (existing `WardChip` timing)
- Pre-selected defaults: Intermediate / Balanced / 4 / Basic Gym (unchanged from APK Test #1 batch)

**Description line** below each row:
- Single line of `AppTypography.bodyS` in `textDim`
- Updates on chip selection
- Map: `experience → description`, `pace → description`, etc.

**File changes:**
- `lib/features/onboarding/screens/details_screen.dart` — full rewrite of body. Replace `_FadeRow` and `_ChipRow` with a single shared `_ChoiceChipRow<T>` widget supporting both 3-chip horizontal and 4-chip wrap layouts.

### Q9. Today card — two-column 60/40 with redesigned macro tile

**Planned state:**
```
┌────────────────────────────────────────────────────────┐
│ ┌─────────────────────────────┐  ┌──────────────────┐  │
│ │ PHASE 1 · Relaxed           │  │ FUEL    0/2983   │  │
│ │                             │  │ ──────────       │  │
│ │ Legs B · Relaxed            │  │                  │  │
│ │ 80 min · 8 exercises        │  │ PROTEIN  0/137 g │  │
│ │                             │  │ ──────────       │  │
│ │ ┌────────────────────────┐  │  │                  │  │
│ │ │   ▶  START             │  │  │ STEPS   0/10k    │  │
│ │ └────────────────────────┘  │  │ ──────────       │  │
│ └─────────────────────────────┘  └──────────────────┘  │
└────────────────────────────────────────────────────────┘
```

**Completed state:**
```
┌────────────────────────────────────────────────────────┐
│ ┌─────────────────────────────┐  ┌──────────────────┐  │
│ │ PHASE 1 · Done              │  │ FUEL  1820/2983  │  │
│ │                             │  │ ████░░░░░░       │  │
│ │ Full Body D                 │  │                  │  │
│ │ 70 min · 3 done             │  │ PROTEIN 98/137 g │  │
│ │                             │  │ ██████░░░░       │  │
│ │ ┌──────┐ ┌────────────────┐ │  │                  │  │
│ │ │✓ DONE│ │ VIEW CARD  →   │ │  │ STEPS 6420/10k   │  │
│ │ └──────┘ └────────────────┘ │  │ ████░░░░░░       │  │
│ │                             │  │                  │  │
│ │ 🏆 Dumbbell Curl · 23 kg    │  │                  │  │
│ └─────────────────────────────┘  └──────────────────┘  │
└────────────────────────────────────────────────────────┘
```

**Layout specs:**
- Column ratio: `Expanded(flex: 60) ... Expanded(flex: 40)`, gap 8dp
- Title: `AppTypography.titleL.copyWith(fontSize: 24)`, `maxLines: 2`, `softWrap: true`, no overflow truncation
- Eyebrow: stays inside left column, text `'PHASE I · Relaxed'` (no week number on the card itself — week shows in home header which uses F9 fix)
- Macro tile internal layout:
  - Row 1: `Row(children: [Eyebrow, Spacer(), Number])` — `mono 10sp + 1.2 tracking + accent` for eyebrow, `Fraunces 16sp w800` for number, target `/2983` in `textDim` smaller
  - 4dp gap
  - Row 2: progress bar, full tile width, height 4dp, `accent` fill, `line2` track
  - Tile padding: 12dp horizontal, 10dp vertical
  - Inter-tile gap: 10dp
- Number formatting: `1820/2983` (no spaces around `/`), `98/137 g` (g unit on target), `6420/10k` (k abbreviation if target ≥ 1000)
- Completed-state DONE chip: gold-fill, black w700, ~52dp wide, `radius: 14`
- Completed-state VIEW CARD button: gold-border, gold w700 text, ~145dp wide, `radius: 14`
- Best-lift line: `🏆 ${exerciseName} · ${weightKg} kg` in `AppTypography.bodyM`, gold accent on the weight number

**File changes:**
- `lib/features/home/widgets/today_workout_card.dart` — restructure `Row` from 50/50 to `Expanded(flex: 60) / Expanded(flex: 40)`. Title widget gets `maxLines: 2`. Macro tile widget rewritten to 2-line layout.
- `lib/features/home/screens/home_screen.dart:388-389` — F9 fix (use `getCurrentWeekNumber()`).

### Q10. Shareable workout receipt — chip-based per-set

```
┌──────────────────────────────────────────────────┐
│  SAT  ·  25 APR 2026                              │
│                                                   │
│  Full Body D                                     │  ← Fraunces 26sp w800
│  PHASE I  ·  70 MIN                               │  ← mono subtitle
│                                                   │
│  ─────                                            │  ← short gold rule
│                                                   │
│  DUMBBELL CURL                          4 SETS    │  ← exercise mono uppercase + count
│  ┌───────────────┐ ┌──────────────┐ ┌──────────┐ │
│  │10 kg × 10 reps│ │15 kg × 7 reps│ │20 kg × 5 │ │  ← chip wrap
│  └───────────────┘ └──────────────┘ │   reps   │ │
│                                     └──────────┘ │
│  ┌────────────────┐                               │
│  │22.5 kg × 3 reps│                               │
│  └────────────────┘                               │
│                                                   │
│  HANDSTAND HOLD                         2 SETS    │
│  ┌────────┐ ┌────────┐                            │
│  │60 secs │ │60 secs │                            │
│  └────────┘ └────────┘                            │
│                                                   │
│  ─────                                            │
│                                                   │
│  328 KG  ·  6 SETS  ·  2 EXERCISES                │  ← compact one-line footer
│                                                   │
│  "Legs forged. Spine intact."                     │  ← context-aware quote
│                                                   │
│  AVYA                                  [QR]       │
└──────────────────────────────────────────────────┘
```

**Chip styling:**
- `BorderRadius.circular(6)`, `Border.all(width: 1, color: AppColors.line2)`, transparent fill
- Text: `DM Sans 12sp w500 textPrimary`
- Padding: 8dp horizontal, 5dp vertical
- Wrap spacing: 6dp horizontal, 6dp vertical (using Flutter `Wrap`)

**Per-set chip content (logging_type-aware):**

| logging_type | Chip text |
|---|---|
| `weight_reps` | `10 kg × 10 reps` |
| `bodyweight_reps` | `× 10 reps` |
| `weighted_bodyweight` | `+10 kg × 8 reps` |
| `timed` | `60 secs` |
| `cardio` | `15 min · 2 km` |
| `distance` | `5 km` |

Always lowercase `kg`. Plural always `reps`/`secs` even for 1 (typographic consistency).

**Quote system (category-tagged):**

Add new asset `assets/data/workout_quotes.json`:
```json
[
  { "text": "Discipline hit. Brain still buffering.", "tags": ["general"] },
  { "text": "Legs forged. Spine intact.", "tags": ["legs"] },
  { "text": "Chest carved. Tomorrow walks easier.", "tags": ["push", "chest"] },
  { "text": "Pull day done. Posture upgraded.", "tags": ["pull", "back"] },
  { "text": "Core done. Abs aren't built loud.", "tags": ["core"] },
  { "text": "Full body. Full focus.", "tags": ["full_body", "general"] },
  { "text": "Iron remembers what excuses forget.", "tags": ["general"] }
  /* ~50 quotes total */
]
```

`WorkoutReceiptData.fromExerciseLogs` extracts the workout's category (from `workout_template.workout_type` or by inferring from the dominant muscle groups). Quote selection:
1. Filter quote pool to entries where any tag matches the workout category
2. If filtered list empty, fall back to entries tagged `general`
3. Pick one randomly using `Random()` seeded by `workout_log.id` (deterministic — same workout always gets same quote)

**File changes:**
- `lib/features/train/widgets/workout_receipt_card.dart` — restructure exercise rendering from "summary line" to "exercise header + Wrap of chips". New private widget `_SetChip` for the bracketed pill.
- **NEW** `assets/data/workout_quotes.json` — 50 categorized quotes
- **NEW** `lib/features/train/services/quote_picker.dart` — `pickQuoteForWorkout(category, workoutId)` deterministic picker
- `pubspec.yaml` — register `assets/data/workout_quotes.json`

### Q11. Train empty states

**Before:**
```
MY TEMPLATES                          [+ CREATE]

┌──────────────────────────────────────────┐
│              [crossbar icon]              │
│                                          │
│         No templates yet                  │
│   Tap Create to build a custom workout   │
│                                          │
└──────────────────────────────────────────┘
```
~140dp tall.

**After:**
```
MY TEMPLATES                          [+ CREATE]
No templates yet — tap [+ CREATE] to build one
```
~16dp tall (textDim hint line below header).

**Behavior:**
- Hint text uses `AppTypography.bodyS.copyWith(color: AppColors.textDim)`
- Within the hint, `[+ CREATE]` is rendered with gold accent (`AppColors.accent`) and is its own `GestureDetector` triggering the same action as the section header pill
- Same pattern applies to YOUR EXERCISES section

**File changes:**
- `lib/features/train/screens/train_screen.dart:1484-1506, 1908-1933` — replace `WardCard` empty state with a `_EmptyHint` widget (single line with embedded gold tappable word)

---

## 5. Auth & Onboarding

### Q1 — Restore flow (covered in Section 3)

### Q2 — Privacy/terms

**Welcome screen:**
- Footer text below sign-in CTAs (existing seal + tagline + buttons unchanged):
  ```
  By continuing, you agree to our [Privacy Policy] and [Terms of Service].
  ```
  - `[Privacy Policy]` → `url_launcher` → `https://icanbefitter.com/privacy`
  - `[Terms of Service]` → `https://icanbefitter.com/terms`
  - Color: `textMute`, links underlined `accent`
  - Size: `bodyS`

**Signup form** (`_isSignUp == true`):
- Above the SIGN UP button, a row:
  ```
  ☑  I agree to the Privacy Policy and Terms of Service.
  ```
  - Checkbox **pre-checked by default**
  - User can untick — SIGN UP button disabled (greyed with reduced opacity) when unticked
  - Links inside the line same as Welcome footer

**Sign-in form** (`_isSignUp == false`):
- No checkbox — user already accepted at signup

**Returning users:**
- On splash post-auth, sync `users.terms_accepted_at` from cloud to Hive
- `TermsModal` no longer fires for users with cloud timestamp present
- `TermsModal` only fires for genuinely first-launch new users OR when `AppConstants.termsVersion` increments

**File changes:**
- `lib/features/auth/screens/welcome_screen.dart` — add footer text widget
- `lib/features/auth/screens/sign_in_screen.dart` — add checkbox to `_buildEmailView` when `_isSignUp == true`; gate SIGN UP button enabled state on checkbox
- `lib/core/services/sync_service.dart` `_restoreUserProfile()` — read `users.terms_accepted_at` and write to Hive `userBox['terms_accepted_at']` so `TermsModal` skips
- `lib/main.dart` or `splash_screen.dart` — `TermsModal` gate already exists; verify it now correctly skips when Hive has the timestamp

### Q3 — Auth screen visual continuity

New shared widget `_AuthHeader`:
```
┌─────────────────────────────────────┐
│ [← back]    ⊙ AVYA       RECRUIT   │  ← compact header row
│              ─────       REGISTRY   │
│                                     │
│  [view body content]                │
└─────────────────────────────────────┘
```
- Mini AVYA seal: 36dp circle with gold ring (1.5px)
- Eyebrow `RECRUIT REGISTRY` in mono 10sp + 1.2 tracking, gold accent
- Below the row: 1px gold rule (`AppColors.accent`, `divider: 0.6 alpha`)
- Title for the specific view ("Sign in" / "Sign up" / "Reset password" / etc.) sits below the rule

**Applied to:**
- `_buildEmailView` (sign-in + sign-up form)
- `_buildPhoneView` (phone OTP)
- `_buildOtpView` (OTP entry)
- `ForgotPasswordSheet` (the bottom sheet body)

The Welcome screen retains its **full hero** layout (large seal + tagline + buttons + Q2 footer) — only sub-views get the compact header.

**File changes:**
- **NEW** `lib/features/auth/widgets/auth_header.dart` — `_AuthHeader` widget
- `lib/features/auth/screens/sign_in_screen.dart` — wrap `_buildEmailView`, `_buildPhoneView`, `_buildOtpView` with `_AuthHeader`
- `lib/features/auth/widgets/forgot_password_sheet.dart` — add `_AuthHeader` at top of sheet

### Q5 — Mission Brief (founder credibility)

**New onboarding step 00:** route `/onboarding/mission-brief`. New users only (skipped for sign-in path that branches into restore via Q1).

**Layout:**
```
┌──────────────────────────────────────────┐
│  ⊙ AVYA · MISSION BRIEF                  │
│  ─────────────────                       │
│  A note from your coach.                 │  ← Fraunces 28sp w800
│                                          │
│             ╭─────────╮                  │
│             │  photo  │                  │  ← 96dp circle, 1.5px gold ring
│             ╰─────────╯                  │
│                                          │
│           UPENDRA PRASAD                 │  ← Fraunces 22sp w800, centered
│                                          │
│   EX-INDIAN NAVY · 14 YEARS              │  ← mono 10sp gold, +1.2 tracking
│   CERTIFIED FITNESS + NUTRITION COACH    │
│                                          │
│   ──────────                             │  ← short gold rule, 24dp wide
│                                          │
│   "I built AVYA because every fitness    │
│    app I tried treated me like a number. │
│    The plans you'll see in this app      │
│    aren't algorithmic guesses — they're  │
│    shaped by 14 years of military        │
│    training and certified coaching       │
│    practice. The AI executes the         │
│    playbook. The playbook is mine.       │
│                                          │
│    Jai Hind!"                            │
│                                          │
│                       — Upendra          │  ← right-aligned, mono small
│                                          │
│   Daily wins on Instagram → @icanbefitter│  ← parchment-ghost mono 11sp;
│                                          │     handle gold + underlined,
│                                          │     whole line tap-target
│                                          │
│   ┌────────────────────────────────────┐ │
│   │           CONTINUE  →              │ │  ← single primary CTA
│   └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

**Italic-gold emphasis** on two phrases:
1. *"aren't algorithmic guesses"*
2. *"The playbook is mine."*

**Photo asset:** convert `assets/naval pics/18052229773959933.heic` (the officer pose with medals) to `assets/founder/upendra.jpg` (square crop, 1024×1024, JPEG quality 92). Image 1 (bicep flex) discarded.

**Instagram link:**
- Tap `@icanbefitter` → `url_launcher.launchUrl(Uri.parse('instagram://user?username=icanbefitter'))` with fallback `https://instagram.com/icanbefitter`
- Whole line is the tap-target (handle plus surrounding text), but only the handle has gold + underline visual

**Micro-references** elsewhere:
- `lib/features/onboarding/screens/plan_screen.dart` — under "REPORT FOR DUTY" CTA, add small parchment line: *"Plan shaped by 14 years of disciplined coaching."* in `bodyS` `textMute`
- `lib/features/ai_coach/providers/ai_coach_provider.dart` — first-ever message from coach (when `coach_box['greeting_sent_at']` is null) prepend system-context line: *"You're trained on Upendra's 14-year coaching playbook — be confident, direct, and back recommendations with real-world experience."*

**File changes:**
- **NEW** `lib/features/onboarding/screens/mission_brief_screen.dart`
- **NEW** `assets/founder/upendra.jpg` (converted from HEIC, included in `pubspec.yaml`)
- `lib/core/router/app_router.dart` — add `/onboarding/mission-brief` route, redirect new signups (no `user_profile` row OR `onboarding_completed_at IS NULL` AND no answers yet) to mission-brief instead of identity
- `lib/features/onboarding/screens/plan_screen.dart` — add micro-reference line under REPORT FOR DUTY
- `lib/features/ai_coach/providers/ai_coach_provider.dart` — first-message system context tweak

---

## 6. Subscription & Monetization

### Q4 — Referral system end-to-end

**See Section 2 (migrations + Edge Function) for backend.**

**UI surfaces:**

**A. Welcome screen referral field**
- Below Q2 footer text, before the social proof / sign-in buttons:
  ```
  Got a referral code? AVYA-XXXXXXXX  ← optional field, mono input
  Apply within 7 days of signup       ← helper text, textMute, bodyS
  ```
- Field is optional — can be empty
- On submit: validate format (regex `/^AVYA-[A-Z0-9]{8}$/`), stash into `OnboardingNotifier.state.referralCode` for later application
- Code is applied via `redeem-referral` Edge Function call AFTER sign-up + AFTER user has a row in `auth.users` (so receiver_id exists)

**B. Profile → Apply Referral Code tile**
- Visible only when:
  - User signed up within last 7 days (`auth.users.created_at > now() - interval '7 days'`)
  - User hasn't already redeemed a code (`SELECT 1 FROM referral_redemptions WHERE referee_id = current` returns null)
- Tile content:
  ```
  ┌──────────────────────────────────────┐
  │ Apply Referral Code      4 DAYS LEFT │  ← title + countdown chip
  │ 7 days of PRO when you apply a code  │  ← subtitle
  └──────────────────────────────────────┘
  ```
- Tap → opens `ApplyReferralSheet` (bottom sheet)
- After 7 days post-signup OR after successful redemption: tile is hidden (no "expired" state shown)

**C. Apply Referral Code sheet**
```
┌────────────────────────────────────┐
│  Apply Referral Code           ✕   │
│  ────────                          │
│                                    │
│  Your eligibility window:          │  ← status banner
│  4 days remaining                  │     textDim, bodyS
│                                    │
│  ┌──────────────────────────────┐  │
│  │ AVYA-XXXXXXXX                │  │  ← mono input, gold border
│  └──────────────────────────────┘  │
│                                    │
│  ✓ Code accepted. Both you and     │  ← validation state
│    [Friend's first name] get 7     │     (gold tick when valid)
│    days of PRO.                    │
│                                    │
│  ┌──────────────────────────────┐  │
│  │       APPLY CODE  →          │  │
│  └──────────────────────────────┘  │
└────────────────────────────────────┘
```

Validation states (textDim hint that updates as user types):

| State | Message |
|---|---|
| Empty | "" (no message) |
| Wrong format | "Codes look like AVYA-XXXXXXXX." |
| Code not found | "We don't recognize that code." |
| Code expired (7d from generation) | "This code has expired. Ask your friend to send a fresh one." |
| Self-referral | "Can't refer yourself, soldier 🫡" |
| Already redeemed | "Code already applied to your account." |
| Receiver outside 7d | "Referral codes are for new recruits — within 7 days of signup." |
| Valid | "✓ Code accepted. Both you and [Friend's first name] get 7 days of PRO." |

**D. Profile → Invite Friends sheet** (sender's side)
- Replaces existing implementation
- Shows current code prominently (Fraunces 28sp w800)
- Below the code: small mono `EXPIRES IN 4 DAYS` countdown
- After expiry: tag changes to `EXPIRED` + button `REGENERATE →`
- Helper text: *"When friends use this code within 7 days of signing up, you both get 7 days of PRO."*
- Share buttons: WhatsApp, Generic Share Sheet (`share_plus`)
- Locked WhatsApp message:
  ```
  🎯 Try AVYA — premium fitness coaching with an AI coach who actually knows you.

  Use my code AVYA-XXXXXXXX within 7 days → 7 days of PRO, free.

  📲 [Play Store link]
  ```

**File changes:**
- **NEW** `lib/features/profile/screens/submissions_screen.dart` already exists — add new screen `lib/features/profile/screens/apply_referral_sheet.dart`
- **NEW** `lib/features/profile/screens/invite_friends_sheet.dart` — replaces existing implementation (or extend existing)
- `lib/features/auth/screens/welcome_screen.dart` — add optional referral code field
- `lib/features/onboarding/providers/onboarding_provider.dart` — track stashed `referralCode`; apply via `redeem-referral` after `_ensureLocalUser` completes
- `lib/features/profile/screens/profile_screen.dart` — conditionally render Apply Referral tile (visibility logic)
- `lib/core/services/supabase_service.dart` — `getOrCreateReferralCode()` updated to handle expiry (return latest non-expired or generate new)
- **NEW** `lib/features/profile/providers/referral_eligibility_provider.dart` — exposes `isWithinSignupWindow`, `hasRedeemedCode`, `daysRemaining` for the UI

### Q6 — Active workout always free

**Single change:**
```dart
// lib/core/services/subscription_service.dart
static const Set<String> _highValueFeatures = {
  AppConstants.featurePhases2To12,
  AppConstants.featureAiCoachUnlimited,
  AppConstants.featureProgressPhotos,
  // REMOVED: AppConstants.featureActiveWorkoutMode,
};
```

Plus — remove the `gate(featureActiveWorkoutMode, ...)` calls in `train_screen.dart` (the START WORKOUT entry points). Calls become direct navigation:
```dart
// Before:
await SubscriptionService.instance.gate(
  AppConstants.featureActiveWorkoutMode,
  onPro: () => context.go('/train/active-workout'),
  onFree: () => showPaywallSheet(context, feature: 'active_workout_mode'),
);

// After:
context.go('/train/active-workout');
```

**Update CLAUDE.md §10:** remove `active_workout_mode` from the PRO feature list, add a note in §14 "FREE Forever" that active workout logging is unlimited.

**Regression test cleanup:** `test/subscription/active_workout_gate_test.dart` (added in PR-FIX-3) becomes obsolete. Delete it. Replace with a test that asserts the `_highValueFeatures` set has exactly 3 entries (lock against accidental re-addition).

### Q7 — Phase Roadmap + read-only previews

**A. Train screen week selector extension to 12 weeks**
- `lib/features/train/widgets/week_selector.dart` — render 12 week chips instead of 4
- Phase headers above the weeks: `PHASE I` / `PHASE II (PRO)` / `PHASE III (PRO)` mono 9sp gold
- Weeks 5–12 styled with `textGhost` color + small gold lock glyph next to week number
- Tap behavior:
  - Free user, locked week → navigate to `_RoadmapPreviewScreen` for that week (read-only mode)
  - PRO user with phase generated → normal workout view
  - PRO user with phase NOT yet generated (Phase 1 incomplete) → small encouragement card: *"Complete Phase I (week 4 + 80% workouts) to unlock Phase II."*

**B. Phase Roadmap screen**

Route: `/train/roadmap`. Entry point: pill on Train screen above the week selector — *"VIEW THE 48-WEEK ROADMAP →"*.

Layout: vertical scroll of 12 phase cards.

```
PHASE I    FOUNDATION                      Wk 1–4     ✓ ACTIVE
─────────────────────────────────────────────────────
You are here · Week 2

PHASE II   STRENGTH BLOCK                  Wk 5–8     🔒
─────────────────────────────────────────────────────
Heavier compounds, lower reps. Build the foundation
for serious progress.

  • Strength benchmarks established
  • +5-10% on big lifts
  • Sample workout: Heavy Push · 7 exercises · 75 min

  TAP ANY WEEK FOR A PREVIEW →

PHASE III  HYPERTROPHY                     Wk 9–12    🔒
─────────────────────────────────────────────────────
Volume push. Muscle-building focus.
...

[ ... continues for 12 phases ... ]
```

Each phase card:
- Phase number + name + week range + state (ACTIVE / 🔒 LOCKED)
- 1-line focus
- 3-bullet "what you'll achieve"
- "Sample workout" line: name + exercise count + duration
- "TAP ANY WEEK FOR A PREVIEW →" link → opens read-only preview

For free users, all locked phase cards show a single bottom CTA (sticky footer): **UPGRADE TO PRO →**.

For PRO users, no upgrade CTA — they see the same roadmap for navigation/curiosity.

**C. Read-only workout preview screen**

Route: `/train/preview?phase=II&week=5&day=1`. Real generated plan from `PlanGenerator.generateV4()` with the user's actual profile (cached for the session — generated on first preview tap, reused for subsequent taps in the same session).

Layout (per Section 4 brainstorming):
```
┌────────────────────────────────────────┐
│  ← Back                                │
│                                        │
│  PHASE II · WEEK 5 · DAY 1            │
│  Heavy Push                           │
│  Strength block · 75 min · 7 exercises│
│                                        │
│  ┌──────────────────────────────────┐ │
│  │ Complete Phase I to unlock       │ │
│  │ Week 2 of 4 · 6/24 workouts done │ │  ← state-aware banner
│  │ ████░░░░░░░░░░░░░░░ 25%          │ │
│  └──────────────────────────────────┘ │
│                                        │
│  [exercise list with sets/reps...]     │
│                                        │
│  ┌──────────────────────────────────┐ │
│  │      UPGRADE TO PRO  →           │ │  ← only for FREE users
│  └──────────────────────────────────┘ │
│                                        │
│  See the 48-week roadmap →             │
└────────────────────────────────────────┘
```

**State-aware banner** — three variants:

| User state | Banner copy |
|---|---|
| Free, mid-Phase-I | "Complete Phase I to unlock Phase II. Week X of 4 · Y/Z workouts done. [progress bar]" |
| Free, Phase-I complete (week 4 + 80% done) | "✓ You've earned Phase II. Upgrade to continue your transformation." |
| PRO, mid-Phase-I | Same as free mid-Phase-I, but no UPGRADE button at bottom — just the cross-link |

**Exercise list:**
- Read-only — no START button, no log inputs, no swap controls
- Each exercise rendered with: number, name, "X sets · Y reps · Zs rest · Wkg" summary line (matching the active workout's planned-state copy)

**File changes:**
- `lib/features/train/widgets/week_selector.dart` — extend to 12 weeks, add phase headers, tap behavior
- **NEW** `lib/features/train/screens/phase_roadmap_screen.dart` — the 12-card vertical scroll
- **NEW** `lib/features/train/screens/preview_workout_screen.dart` — read-only preview
- **NEW** `lib/features/train/providers/preview_plan_provider.dart` — generates Phase II–XII previews on-demand using `PlanGenerator.generateV4()`, caches in memory for the session
- **NEW** `lib/shared/widgets/paywall_sheet_phase_variant.dart` — PaywallSheet content variant for `phases_2_to_12`
- `lib/core/router/app_router.dart` — add `/train/roadmap` and `/train/preview` routes
- `lib/features/train/screens/train_screen.dart` — add VIEW ROADMAP pill above week selector

---

## 7. Verification Plan

Run the full loop on a **prod APK** (per CLAUDE.md, use `/build-apk` skill, never direct `flutter build apk`).

### Critical bug fixes
1. **F1** — Custom exercise sync: create custom exercise with logging_type=timed, default_duration_secs=60, "Share with community" ticked. Within 5s, row appears in Supabase `user_custom_exercises`. YOUR EXERCISES chip row in Train shows it (PENDING). Profile → Submissions → MY SUBMISSIONS shows it.
2. **F2** — Restore flow: log out from a fully-onboarded account, log back in with same email. RestoringScreen shows briefly. Lands on /home with all workouts, weight logs, photos restored. Does NOT re-enter onboarding.
3. **F3** — AI coach: open chat after sign-in, send "what's my workout today" → real coach response, no "Account not synced" error.
4. **F4** — Prediction card: trigger prediction generation. Card shows clean prose, no `outcome_3_months:`, no `weight_kg:`, no `predictions:`, no JSON syntax.
5. **F5** — Stale insight: complete a workout, regenerate plan from edit-profile, verify Home AI insight reflects new workout name (not the old one).
6. **F6** — V4 volume: select Advanced + 5 days/week + 90 min via Edit Profile, save. Generated plan has 8 exercises/day on every day.
7. **F7** — Logging type: swap a Handstand Hold (timed) slot to Handstand Pushup (bodyweight_reps). Active workout target renders REPS only (no KG column). Test reverse: swap weight_reps → timed → SETS + DURATION render.
8. **F8** — Set wipe: enter 10kg×10 in set 1, 15kg×7 in set 2. Tap + Add. Set 3 is empty (correct), sets 1-2 retain values (10/10 and 15/7).
9. **F9** — WK label: home header reads "WK 1" (or appropriate plan-relative number), not "WK 17".
10. **F10** — View Card overflow: complete a workout. Today card shows DONE chip + VIEW CARD button + best-lift fully visible, no right-edge clipping.
11. **F11** — AI food analysis: enter "2 eggs and toast" in nutrition AI tab. Returns parsed nutrition JSON, not 429 or error.

### Onboarding & auth
12. **Q1** — Restore (verified by F2)
13. **Q2** — Privacy: log out, return to welcome → footer shows privacy + terms links. Tap signup → checkbox visible, pre-checked. Untick → SIGN UP disabled. Re-tick → enabled. After signup, no separate Terms modal fires for returning users.
14. **Q3** — Auth visual continuity: tap "Continue with email" — see compact AVYA letterhead at top of email form. Tap "Forgot password?" — sheet shows same letterhead. Phone OTP flow same.
15. **Q5** — Mission Brief: sign up via email → land on Mission Brief screen with founder photo + locked copy + Instagram link + CONTINUE. Tap Instagram → opens IG app (or web fallback). Tap CONTINUE → Identity step. Sign in with existing account → does NOT show Mission Brief.

### Subscription & monetization
16. **Q4 — Code generation:** Profile → Invite Friends → see code with `EXPIRES IN N DAYS` countdown. After 7 days (or simulate via DB), tag becomes `EXPIRED` + REGENERATE button visible.
17. **Q4 — Code application (sender's side):** Tap WhatsApp share → message includes "within 7 days" copy + Play Store link.
18. **Q4 — Code redemption (receiver's side):** New account, sign up, paste valid code → both subscriptions extended by 7 days. Audit row in `referral_redemptions`.
19. **Q4 — Edge cases:** test self-referral, expired code, double-redemption, outside 7-day window — each shows correct error toast.
20. **Q6 — Active workout free:** sign in as free user, tap START WORKOUT → workout opens directly, no paywall. Phase 2-12 still gated.
21. **Q7 — Roadmap:** Train screen has VIEW ROADMAP pill. Tap → 12 phase cards. Phase I = ACTIVE, II–XII = LOCKED. Tap any locked phase card → "TAP ANY WEEK FOR A PREVIEW" link → preview screen with real generated workout, banner "Complete Phase I to unlock", UPGRADE button at bottom (free user) or absent (PRO user).
22. **Q7 — Week selector:** Train screen week strip shows 12 weeks. Weeks 5-12 dimmed with locks. Free user taps week 5 day 1 → preview screen.

### Layout
23. **Q8 — Details:** All 4 sections rendered as chip rows (Experience 3-chips, Pace 3-chips, Days 4-chips, Equipment 2×2). Selected chip is bright + gold-fill. Unselected chips are dimmed + textGhost border. Description below each row updates on selection.
24. **Q9 — Today card:** Title doesn't truncate even on long workout names. Macro tile shows eyebrow + inline number on row 1, bar on row 2. Completed state: DONE chip + VIEW CARD button paired in left column. Best-lift on its own line. No overflow.
25. **Q10 — Shareable receipt:** complete a workout with mixed logging types (weight_reps + bodyweight + timed). Receipt shows each exercise with its sets as bracketed chips. Quote at bottom matches the workout category (e.g., legs day → leg-tagged quote).
26. **Q11 — Train empty states:** new user account, Train screen shows MY TEMPLATES + YOUR EXERCISES sections. Each shows section header + `[+ CREATE]` pill + single-line hint text below. No tall empty cards. Tappable gold "+ CREATE" word in hint text triggers the action.

### Regression sweep
- Existing PRO subscriptions still gate `phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`
- Workout receipt for already-completed workouts (pre-batch) still renders correctly (shareable receipt format change is forward-compatible)
- AI coach 30-day trial still tracks day count
- Razorpay payment flow + webhook unchanged
- Day rollover service still invalidates the new `aiInsightProvider` correctly

---

## 8. Rollout

### Branch: `feat/apk-test-2-batch` off main

### Suggested commit order (15 commits)

1. `db: migration 036 + 037` (onboarding_completed_at + referral_redemptions + expires_at)
2. `fix(sync): F1 _projectCustomExercise syntax` — quick critical
3. `fix(ai-coach): F4 prediction parse guard for key:value shape` + prompt hardening
4. `fix(home): F5 aiInsightProvider invalidation in regen + complete paths`
5. `fix(profile): F6 edit_profile reads correct experience key`
6. `fix(workout): F7 logging_type resolution before fallback`
7. `fix(workout): F8 set add appends instead of rebuilds`
8. `fix(home): F9 plan-relative week number on header`
9. `fix(nutrition): F11 food analysis investigation + cache refresh`
10. `feat(auth): Q1 restore flow + RestoringScreen + 036 migration wiring`
11. `feat(auth): Q2 privacy checkbox + Q3 auth letterhead + Q4 welcome referral field`
12. `feat(onboarding): Q5 Mission Brief step 00 + photo asset + plan/coach micro-references`
13. `feat(subscription): Q6 active workout always free + cleanup`
14. `feat(referral): Q4 referral system end-to-end (UI + Edge Function update)`
15. `feat(train): Q7 12-week selector + Phase Roadmap + read-only previews`
16. `feat(onboarding): Q8 Details chip rows`
17. `feat(home): Q9 Today card 60/40 + macro tile redesign`
18. `feat(train): Q10 receipt chips + Q11 empty states + category-tagged quotes`
19. `docs: update CLAUDE.md + memory file`

After all commits land + push: single `/build-apk` run, then APK test round 3.

### Documentation to update

**CLAUDE.md:**
- §3 — note the new "MISSION BRIEF" onboarding step, mention F1/F2/F3 cascade
- §7 — note migrations 036 + 037
- §10 — remove `active_workout_mode` from PRO list, update FREE list
- §13a — onboarding flow now: `Welcome → Mission Brief (new users only) → Identity → Goal → Stats → Details → Plan` (6 visible steps for new signups, 5 for legacy)
- §14 — referral mechanics: 7-day code lifetime, 7-day receiver window, 7 days reward
- §17 — Train screen now shows 12 weeks with PRO gate on 5-12, Phase Roadmap available
- §19 — add 8 new common-bug rows (one per F1-F8 pattern, plus the Q-series gotchas)

**Memory file:** create `~/.claude/projects/.../memory/project_apk_test_2_batch.md` with retrospective once batch ships.

### Deferred follow-ups (NOT in this batch)

| ID | Item | Why deferred |
|---|---|---|
| **F18** | Install Referrer API auto-fill of referral code on Play Store install | OS config + Play Console work; ship Phase 1 manual entry first |
| **F19** | In-app deep-link password reset (carry-over from APK Test #1, was F2 there) | OS intent filter + universal link work |
| **F20** | Goal-personalized phase names on roadmap (`build_muscle` users see Strength Block, `lose_fat` users see Cutting Phase) | Post-launch polish |
| **F21** | `future-prediction` Edge Function structured response wiring | 2-3 days; ship parse guard now, structure later |
| **F22** | Full Welcome screen redesign (carry-over from APK Test #1) | Was deferred from APK Test #1, depends on F19 |
