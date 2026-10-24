# APK Test #3 — Bug Batch + Forever-Friend + Nutrition Redesign

**Date:** 2026-04-26
**Branch (suggested):** `feat/apk-test-3-batch`
**Predecessor:** `feat/apk-test-2-batch` (commit `52eb035`, not yet merged to main)

---

## Context

Third APK test round on user device (`upendra.prasad@thinkingcode.com`, auth id `00cc3dd5-...`). Surfaced **3 P0 bugs** that broke sync entirely for re-signups, plus **3 design observations** that move the product from "12-week plan" to "forever fitness companion."

The brainstorm covered eleven Q-series decisions (Q1–Q8.1) over a single session on 2026-04-26. All locks are documented in `~/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/project_apk_test_3_brainstorm_inflight.md`.

The single sentence that captures this batch:

> **"Your AI coach is here for life. The first 12 weeks are Deployment 01: Foundation. Each completed deployment earns rank. Whether you're cutting for a wedding, recovering from injury, or just maintaining — the coach adapts to whatever season you're in. Deployments evolve. Your rank stays. Your coach never leaves."**

Out of scope (filed as deferred):
- **F18** — W12 Debrief flow (force AI coach interview at end of Deployment 01 → Deployment 02 generation). No live user will hit it for ≥12 weeks; designing now would be premature.
- **F19** — Adaptive seasons UI (explicit "switch to cut for wedding" / "I'm injured" / "post-pregnancy" affordance). Today the AI coach can adapt via tool calls; first-class UI affordance can wait.

---

## Decisions Locked (from brainstorm)

| ID | Question | Choice |
|---|---|---|
| Q1 | Long-term story | A+C+D hybrid (Endless Deployments + Lifelong adaptive coach + Lifetime rank) |
| Q2 | Promotion cadence | C compounding (fast early, slow late) |
| Q3 | Rank set | E Indian Navy (9 rungs) |
| Q4 | UI surfacing | A (Train) + B (Profile) + minimal Home line below streak |
| Q5 | Roadmap layout | A vertical timeline in modal at `/train/roadmap` |
| Q6 scope | What ships now | Rank ladder + Train layout + Profile Service Record + Home line + Roadmap modal + phase exercise count fix. **Defer** W12 Debrief, adaptive seasons UI. |
| Q6.1 | Streak semantic for rank gates | β workout-day-streak, lower thresholds (7 / 16 / 60 / 100) |
| Q6.2 | Diet plan protein deficit | A anchor-protein-per-meal |
| Q6.3 | AI meal awareness | A — add `meals_today` + `nutrition_trend_7d` to snapshot |
| Q7 | Nutrition page IA | A → β single CTA + bottom sheet (Strong/Hevy pattern) |
| Q8 | Page layout | Approve as drawn, with Q8.1 amendment |
| Q8.1 | Urine treatment | A — combine HYDRATION + URINE into one card with two rows |

---

## Issue Inventory

### 🔴 Critical Bugs (sync / correctness)

#### **Bug A — Orphaned `public.users` row blocks all server writes for re-signups**

**Root cause.** `public.users.id` has no foreign key to `auth.users(id)`. When an `auth.users` row is deleted (account wipe, dev cleanup, Supabase admin delete), the `public.users` row is left orphaned. `public.users.email` is `UNIQUE`. The next signup with the same email creates a new `auth.users` row but the `_ensureLocalUser` upsert into `public.users` fails with **23505 (unique_violation)** because the orphan still owns the email. All FK-bound writes (`user_profile`, `ai_coach_interactions`, `user_custom_exercises`, `workout_logs`, `nutrition_logs`) then fail with **23503 (foreign_key_violation)** because their `user_id` FK references `public.users(id)` which never got created. Every error is silently swallowed by `unawaited()` fire-and-forget.

**User impact (verified 2026-04-26).** Account `upendra.prasad@thinkingcode.com` (`00cc3dd5-...`) signed up on 2026-04-24, used the app for 48 hours, and produced **0 rows** in `public.users`, `user_profile`, `ai_coach_interactions`, `user_custom_exercises`, `workout_logs`, `nutrition_logs`. Two orphan rows blocked the email: `1574f7c6-...` (this email) + `015507ef-...` (`thinking-code.com` typo email).

**Mitigated.** Orphans deleted via SQL on 2026-04-26. Sync verified afterward: 3 of 4 tables resumed writing (`public.users`, `ai_coach_interactions`, `user_custom_exercises`). `user_profile` still empty, but that's Bug B not Bug A.

**Permanent fix.**
1. **Migration 039** — `ALTER TABLE public.users ADD CONSTRAINT users_id_fk_auth FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;` so orphans cascade-delete with the auth row.
2. **Trigger** on `auth.users` INSERT that auto-creates `public.users` row from `id + email + raw_user_meta_data->>'full_name'`. Standard Supabase pattern. Eliminates the race entirely.
3. **Error surfacing** in `_ensureLocalUser` — log 23505/23503 to `client_errors` and `debugPrint`. No more silent swallow.

#### **Bug B — Edit Profile saves to Hive but never syncs `user_profile` to Supabase**

**Root cause.** Path:
```
edit_profile_screen._save()
  → userProfileProvider.notifier.updateProfile(updates)
    → UserRepository.updateProfileFields(fields)
      → saveProfile()    ← HIVE ONLY
```
`UserRepository` exposes two other methods that DO write to Supabase (`updateSupabaseProfileField` at line 240, `syncOnboardingToSupabase` at line 261), but `_save` calls neither. Snackbar says "Saved", but `user_profile` row in Postgres stays empty / stale forever.

**User impact (verified).** Account `00cc3dd5-...` tapped Edit Profile → Save on 2026-04-26 after the Bug A cleanup. `public.users` row appeared (proving the FK fix worked) but `user_profile` row remained absent.

**Fix.** After `recalculateTargets()` in `_save`:
```dart
final userId = supabase.auth.currentUser?.id;
if (userId != null) {
  unawaited(SyncService.instance.syncProfileNow(userId));
  unawaited(SyncService.instance.pushSnapshot());
}
```

**Sync gap audit (broader than just Edit Profile).** Verify and add fire-and-forget upserts to:
| Surface | Today | After fix |
|---|---|---|
| Edit Profile → Save | Hive only ❌ | `syncProfileNow` + `pushSnapshot` |
| Workout complete | Already syncs ✅ | + `RankService.evaluateAndPromote` (NEW from Obs 1) |
| Plan generated / phase advance | Hive only ❓ | `syncProgressNow` + `RankService.evaluate` |
| Streak roll | Hive only ❓ | `syncStreaks` (verify exists) |
| Deployment 01 complete (W12 + Phase III done) | Doesn't exist | New event → `rank_promotion` row + AI celebration |

#### **Bug C — AI hallucinates day-of-week + invents stats**

**Root cause.** `supabase/functions/ai-proxy/index.ts` has zero matches for `day_of_week | dayOfWeek | weekday | toLocaleDateString | getDay()`. The system prompt does not inject the current date or day-of-week. Gemini guesses.

**User impact (verified).** Sunday 2026-04-26 11:31 IST. User asked "What's my workout today?" AI responded "Upendra, you don't have a workout planned for today, **Monday**. I've noticed you skip **Monday** workouts **100%** of the time." User has 0 `workout_logs` rows in DB; the "100% skip" stat is pure invention.

**Fix (server-side, ai-proxy/index.ts).**

```ts
const istNow = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
const todayName = istNow.toLocaleDateString('en-US', {
  weekday: 'long',
  timeZone: 'Asia/Kolkata',
});
const todayIso = istNow.toISOString().split('T')[0];

systemPrompt =
  `Today is ${todayName}, ${todayIso} (IST). Use this for any "today" reference.\n\n` +
  systemPrompt;
```

Plus an anti-fabrication rule appended to the system prompt:
> **NEVER cite percentages, averages, or trends about skipped workouts, missed days, attendance patterns, or behavior frequency unless the snapshot's `recent_logs`, `coach_notices`, or `nutrition_trend_7d` actually contains data supporting that claim. If asked about behavior with insufficient data, say so honestly: "I don't have enough data on your Monday pattern yet."**

Deploy as `ai-proxy v48`.

---

### 🟦 Forever-Friend Story (Obs 1)

#### **Brand promise**

A+C+D hybrid:
- **A — Endless Deployments**: 12-week chapters with a Debrief at the end and AI-generated next deployment.
- **C — Lifelong adaptive coach**: coach changes with life seasons (cut for wedding, recovery from injury, postpartum, etc.).
- **D — Lifetime rank**: visible from Day 1, going years out, never resets.

#### **Indian Navy 9-rung rank ladder (LOCKED)**

| # | Week | Rank Code | Display name | Insignia | Trigger gate (BOTH must satisfy) |
|---|---|---|---|---|---|
| 0 | W0 | `SD2` | Seaman 2nd Class | Plain anchor | Signup + onboarding done |
| 1 | W1 | `SD1` | Seaman 1st Class | Single chevron + anchor | streak ≥ 7 workouts AND 1 week of scheduled workouts logged |
| 2 | W4 | `LS` | Leading Seaman | Anchor + chevron | streak ≥ 16 workouts AND Phase I done (4 weeks all logged) |
| 3 | W12 | `PO` | Petty Officer | Crossed anchors | streak ≥ 60 workouts AND Phase III done (Deployment 01 complete) |
| 4 | W26 | `CPO` | Chief Petty Officer | Crossed anchors + crown | streak ≥ 100 workouts AND Deployment 02 complete |
| 5 | W52 | `MCPO` | Master Chief Petty Officer | Crown + star + anchors | 1-Year active streak (no >14-day gap — calendar-based) |
| 6 | W104 | `SubLt` | Sub Lieutenant | Single gold stripe (officer commission) | 100 total workouts logged |
| 7 | W156 | `LtCdr` | Lieutenant Commander | 2.5 gold stripes | 200 total workouts |
| 8 | W208 | `Cdr` | Commander | 3 gold stripes | 300 total workouts |
| 9 | W260+ | `Capt` | Captain | 4 gold stripes + crown | 500 total workouts AND 3 deployments completed |

**Streak math context (verified from code, do NOT re-derive in implementation).** `WorkoutRepository.calculateCurrentStreak()` walks back through `schedule_<date>` keys. Rest days `type='rest'`/`type='off'` are INVISIBLE — they don't break, they don't increment. Only `status=='completed'` increments. Missed scheduled workout consumes a streak freeze if available, else streak ends. Today's incomplete workout doesn't penalize.

**RankService MUST call `calculateCurrentStreak()` fresh on every evaluation.** `current_streak_days` is NOT in `_syncUserProgress` projection; only `current_streak_weeks` (week-level) syncs. Don't trust any cached number.

#### **UI surfacing (LOCKED)**

**Train tab — top to bottom:**
1. NEW: Compact rank chip — `⚓ SEAMAN 2ND CLASS · NEXT IN 12 DAYS`. Single mono row.
2. Today's Workout card (existing).
3. NEW position: `DEPLOYMENT 01 — FOUNDATION (Week 1 of 12)` header + `[ ⚓ ROADMAP — WK 1/12 → ]` pill. **Above** This Week (was below).
4. This Week calendar (existing).

**Profile tab — new section above bio stats:**
- `SERVICE RECORD` letterhead.
- Full ladder rendered as a vertical list. Earned ranks show insignia + earned date. Locked ranks show grayed insignia + the gate text ("100 workouts to unlock Sub Lieutenant").
- Lifetime stats row: `Deployments completed` (count of `rank_promotions` rows with `trigger_type='deployment_complete'`) / `Service days` (calendar days since signup, from `auth.users.created_at`) / `Total volume lifted (kg)` (sum of `volume_kg` across all exercise logs).

**Home tab — minimal one-line addition:**
- Below the streak counter, a single mono row: `⚓ SEAMAN 2ND CLASS · NEXT IN 12 DAYS`.
- No spacing changes; slots into the existing block.

**Roadmap modal at `/train/roadmap`:**
- Full-screen route, vertical scroll.
- Header: `DEPLOYMENT 01 · FOUNDATION  WK 1/12  0% complete`.
- Vertical timeline:
  - W1 marker — current position (`← you are here`).
  - Phase I — Foundation (W1–4) with `Push/Pull/Legs · 6 ex/day` description.
  - Promotion markers at W2, W4 with rank chevrons.
  - Phase II — Strength (W5–8) **PRO 🔒** for free users.
  - Phase III — Precision (W9–12) **PRO 🔒** for free users.
  - W12 promotion marker → `PETTY OFFICER · DEBRIEF + DEPLOYMENT 02`.
  - **Year 1 divider** band.
  - W26 (CPO), W52 (MCPO 1-Year Service Pin) markers.
  - **Year 2 divider** band.
  - W104 (Sub Lieutenant — Officer Commission) — visual category change to gold stripe.
  - **Years 3-5 divider** band.
  - W156 (LtCdr), W208 (Cdr), W260 (Captain) markers — Captain shown faintly at the far edge so user senses the years.
- Tap any rank marker → small detail sheet showing rank insignia, gate description, your progress toward it.

#### **Storage (Migration 039 — combined with Bug A schema fix)**

```sql
-- Migration 039: forever-friend rank system + auth FK fix

-- Part 1 — Bug A schema fix
ALTER TABLE public.users
  ADD CONSTRAINT users_id_fk_auth
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', '')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- Part 2 — Rank ladder (seeded once, immutable)
CREATE TABLE rank_ladder (
  rank_code        TEXT PRIMARY KEY,
  display_name     TEXT NOT NULL,
  short_name       TEXT NOT NULL,
  ordinal          INT  NOT NULL UNIQUE,
  min_weeks        INT  NOT NULL,
  insignia_asset   TEXT NOT NULL,
  category         TEXT NOT NULL CHECK (category IN ('sailor', 'officer')),
  is_terminal      BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO rank_ladder (rank_code, display_name, short_name, ordinal, min_weeks, insignia_asset, category, is_terminal) VALUES
  ('SD2',   'Seaman 2nd Class',          'Seaman 2nd', 0, 0,   'rank/sd2.svg',   'sailor',  FALSE),
  ('SD1',   'Seaman 1st Class',          'Seaman 1st', 1, 1,   'rank/sd1.svg',   'sailor',  FALSE),
  ('LS',    'Leading Seaman',            'Leading',    2, 4,   'rank/ls.svg',    'sailor',  FALSE),
  ('PO',    'Petty Officer',             'Petty Off.', 3, 12,  'rank/po.svg',    'sailor',  FALSE),
  ('CPO',   'Chief Petty Officer',       'Chief PO',   4, 26,  'rank/cpo.svg',   'sailor',  FALSE),
  ('MCPO',  'Master Chief Petty Officer','Master Ch.', 5, 52,  'rank/mcpo.svg',  'sailor',  FALSE),
  ('SubLt', 'Sub Lieutenant',            'Sub Lt',     6, 104, 'rank/sublt.svg', 'officer', FALSE),
  ('LtCdr', 'Lieutenant Commander',      'Lt Cdr',     7, 156, 'rank/ltcdr.svg', 'officer', FALSE),
  ('Cdr',   'Commander',                 'Cdr',        8, 208, 'rank/cdr.svg',   'officer', FALSE),
  ('Capt',  'Captain',                   'Captain',    9, 260, 'rank/capt.svg',  'officer', TRUE);

-- Part 3 — Per-user promotion history
CREATE TABLE rank_promotions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rank_code        TEXT NOT NULL REFERENCES rank_ladder(rank_code),
  achieved_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  trigger_type     TEXT NOT NULL CHECK (trigger_type IN ('signup','first_sync','phase_complete','deployment_complete','calendar','workout_count','combined')),
  trigger_metadata JSONB,
  UNIQUE (user_id, rank_code)
);

CREATE INDEX idx_rank_promotions_user ON rank_promotions (user_id, achieved_at DESC);

-- RLS — same pattern as the rest of the app
ALTER TABLE rank_promotions ENABLE ROW LEVEL SECURITY;
CREATE POLICY rank_promotions_select_own ON rank_promotions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY rank_promotions_insert_own ON rank_promotions FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Part 4 — Denormalized current rank on user_profile (for fast reads)
ALTER TABLE user_profile
  ADD COLUMN current_rank_code        TEXT REFERENCES rank_ladder(rank_code) DEFAULT 'SD2',
  ADD COLUMN current_rank_achieved_at TIMESTAMPTZ DEFAULT now();

-- Part 5 — Trigger that pushes rank promotion → push notification queue
-- (placeholder — push delivery already handled elsewhere via OneSignal;
-- this trigger just writes a notifications-inbox row that the app reads)
```

#### **`RankService` (client-side service)**

New file: `lib/core/services/rank_service.dart`.

```dart
class RankService {
  static final instance = RankService._();
  RankService._();

  /// Idempotent: evaluates the user's current state, computes the highest
  /// rank they qualify for, and writes a rank_promotions row + denormalized
  /// user_profile.current_rank_code for any rank they newly qualify for.
  ///
  /// Fire-and-forget. Catches its own errors. Safe to call after every
  /// workout complete, on splash, and after onboarding completion.
  Future<void> evaluateAndPromote() async { ... }

  /// Returns the user's current rank info for UI consumption.
  /// Reads from user_profile.current_rank_code (denormalized).
  RankInfo getCurrentRank();

  /// Returns the next rank the user is working toward + days/workouts to go.
  RankInfo? getNextRank();

  /// Returns the full ladder with earned/locked status. For Profile Service
  /// Record rendering.
  List<LadderEntry> getLadder();
}
```

#### **Server-side cron `evaluate-rank-promotions`**

New Edge Function. Runs nightly via pg_cron. Iterates all users; for each, recomputes their rank ceiling from Postgres data (workout_logs counts, signup date, completed deployments via user_progress); if the cloud rank lags behind what they qualify for (e.g., user installed but never opened app, missing client-side firings), upserts a rank_promotions row.

Path: `supabase/functions/evaluate-rank-promotions/index.ts`.
`verify_jwt: false` (cron-only, like `streak-guardian`).

#### **Linkage table — where rank flows**

| System | Reads rank? | Use |
|---|---|---|
| Plan generator V4 | NO | Plan = exp + days + goal + phase. Rank decorative. |
| Detected experience | INDIRECT | PO+ promotion bumps `detected_experience` from beginner→intermediate (only if user self-reported beginner). |
| AI coach context | YES | `coach_memory.current_rank` + `weeks_until_next_rank` in snapshot. Coach uses for greeting + nudge copy. |
| Workout receipt | YES | Footer: `⚓ Petty Officer · Deployment 01 W3` identity. Identity travels with the share. |
| Home / Train / Profile UI | YES | Read denormalized `user_profile.current_rank_code` for fast reads. |
| Profile Service Record | YES | Reads `rank_promotions` history for badge wall. |
| Push notifications | YES | `rank_promotions` INSERT enqueues "⚓ Promoted to Leading Seaman" push + AI coach celebration message. |

#### **Phase exercise count fix**

User flagged: Today card on Train shows "8 EX" while 12-week roadmap preview shows different counts (6/7/8) per phase. Likely because:
- Today card reads actual scheduled plan exercise count (computed at plan generation, derived from user's `VolumeFilter.targetCount(experience, daysPerWeek)`).
- Roadmap PREVIEW for Phase II/III uses `previewPlanProvider` calling `PlanGenerator.generateV4()` with potentially different inputs.

**Fix:** ensure roadmap preview uses the SAME `experience + days_per_week` as the user's actual onboarding values (read from `user_profile`). Audit `previewPlanProvider` — it should never substitute defaults when reading those two fields. Verify with a unit test.

---

### 🟢 Diet Plan Protein Anchor (Obs 2)

**Root cause.** `lib/features/nutrition/screens/diet_plan_screen.dart`'s plan generator picks foods balanced by category but has no per-meal protein anchor constraint. Indian-first DB (93 foods) skews carb-heavy. Result: 138g target → 94g delivered (32% deficit).

**Fix — anchor-protein-per-meal rule.** Each meal slot has a required anchor:

| Meal slot | Anchor protein options | Selection rule |
|---|---|---|
| Breakfast | Egg, Whey Protein, Greek Yogurt, Paneer, Sprouts, Tofu | Pick one, target ≥ 20g protein |
| Lunch | Chicken, Mutton, Fish, Paneer, Dal, Rajma, Tofu | Pick one, target ≥ 30g protein |
| Dinner | Same as lunch | Pick one, target ≥ 30g protein |
| Snacks | Whey shake, mixed nuts, sprouts, Greek yogurt (optional anchor) | If used, target ≥ 15g protein |

Algorithm:
1. For each slot, pick anchor first (filtered by `diet_preference` veg/vegan/non-veg).
2. Add 1–2 carb staples to hit calorie band.
3. Add 1 fat source if calorie band still has room.
4. Verify total protein for the day ≥ 95% of target. If not, swap lowest-protein-density item for higher alternative in same calorie band.

Files to modify:
- `lib/features/nutrition/screens/diet_plan_screen.dart` (or wherever `_generatePlan()` lives)
- Possibly extract the algorithm into `lib/features/nutrition/services/diet_plan_generator.dart` for testability.
- Add unit test validating ≥ 95% protein adherence across 4 archetypes (low-cal cut, balanced maintain, surplus build, vegan high-protein).

---

### 🟪 Nutrition Page Redesign (Obs 3)

#### **New page architecture (top → bottom)**

```
┌──────────────────────────────────────────────────┐
│  ⚓ FUELING THE PLAN              [DIET PLAN] ▶  │  Existing header
├──────────────────────────────────────────────────┤
│  TODAY'S SUMMARY                                  │  Existing, kept compact
│  [calorie ring]  PROTEIN 0/138g  CARBS 0/408g    │
│                  FAT 0/81g       FIBER 0/30g     │
│                  WATER 1.7/3.0L                  │
│  On track to hit 80kg by Aug 26 (~19 wks)         │
├──────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────┐  │
│  │           + LOG FOOD                       │  │  NEW gold-accent CTA
│  └────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────┤
│  HYDRATION & STATUS                  1.7 / 3.0 L │  Q8.1=A combined card
│  [● ● ● ● ● ● ● ○]   [+ 250ML]  [+ 500ML]       │  Water row
│  ─────────────────────────────────────────       │
│  URINE STATUS · WELL HYDRATED       [change ▾]   │  Status pill row
│  Keep it up — pee should stay pale yellow.       │  Tip line
│  [color picker — expanded inline when tapped]    │  8-color picker
├──────────────────────────────────────────────────┤
│  TODAY'S MEALS                                    │  Existing TodaysMealsCard
│  ┌─ BREAKFAST ─────────────────────┐              │  4 meal-slot rows
│  │ Oats, Milk · 307 kcal · P 13g  ✏ │             │
│  ├─ LUNCH (empty — tap to log) ────┤              │
│  ├─ DINNER (empty) ─────────────────┤             │
│  └─ SNACKS ──────────────────────-─┘              │
├──────────────────────────────────────────────────┤
│  INSIGHTS & TRENDS              view all →       │
│  [7-day weekly chart strip]                       │  Existing WeeklyChartCard
│  [pattern chips — "Low protein 3 days"]           │  + coach_notices summary
├──────────────────────────────────────────────────┤
│  YOUR FOODS                       + ADD CUSTOM   │  NEW (mirror Train YOUR
│  [horizontal chip strip]                         │  EXERCISES from APK Test
│  • Anjali's Special Dal     [ DRAFT ]           │  #1 D6)
│  • Mom's Chicken Curry      [ PENDING ]         │
│  • My Protein Smoothie      [ APPROVED ✓ ]      │
└──────────────────────────────────────────────────┘
```

Net: ~1500 dp scroll → ~700 dp.

#### **Removed sections (consolidated into bottom sheet)**

| Section today (line in `nutrition_screen.dart`) | New location |
|---|---|
| AI Breakdown card (~202) | Sheet → AI mode (last result rendered in mode body) |
| Food Logger section (~541) | Sheet → AI mode (textfield + ANALYSE & LOG) |
| Scan Meal section (~548, 823 LoC) | Sheet → SCAN mode |
| Cart Auditor section (~628, 332 LoC) | Sheet → CART mode |
| Barcode trigger (~633) | Sheet → BARCODE mode |
| Saved Meals section (~251, 228 LoC) | Sheet → SEARCH mode → "Saved" filter chip |

#### **Bottom sheet — `+ LOG FOOD` tap**

```
┌─────────────────────────────────────────────┐
│ LOG FOOD                                ✕   │  Header
├─────────────────────────────────────────────┤
│ ✨ AI · 📷 SCAN · 🛒 CART · 🔢 BAR · 🔍 SEARCH│  Segmented tabs (WardChip)
├─────────────────────────────────────────────┤
│ [active mode renders here ~70% screen]       │
│                                              │
│ AI default. SEARCH has sub-filter chips:    │
│ All | Saved Meals | Recent.                  │
│                                              │
│ Each mode has its own save action; sheet     │
│ dismisses on success; page refreshes.        │
└─────────────────────────────────────────────┘
```

- New file: `lib/features/nutrition/widgets/log_food_sheet.dart`.
- Hosts the 5 mode widgets (AI / Scan / Cart / Barcode / Search). Each mode is a refactor of an existing widget — minimal new code, mostly relocation.
- Default tab = AI (most-used path).
- SEARCH mode includes `[All] [Saved Meals] [Recent]` sub-filter chips at top.

#### **Hydration & Urine combined card**

New widget: `lib/features/nutrition/widgets/hydration_card.dart` (replaces `hydration_section.dart`).

- Two-row card.
- Row 1: water progress + 8-cell glass grid + quick-add buttons.
- Row 2: urine status pill ("WELL HYDRATED") + `[change ▾]` tap → expands 8-color picker inline. One-line tip below.
- Both rows share a single card surface (`WardCard`) for visual unity.

#### **YOUR FOODS section**

New widget: `lib/features/nutrition/widgets/your_foods_section.dart`.

Mirrors the structure of `_buildYourExercisesSection` from APK Test #1 D6 (Train screen):
- Section header: `YOUR FOODS` mono eyebrow + `+ ADD CUSTOM` pill on the right.
- Body: horizontally-scrollable `WardChip` row, one chip per custom food.
- Status pills:
  - `submitted_to_library = false` → `DRAFT` (textMute)
  - `submitted_to_library = true AND approved_for_library = false` → `PENDING` (warn)
  - `approved_for_library = true` → `APPROVED ✓` (ok)
- Tap chip → existing `CustomFoodSheet` opens (edit / submit / delete).
- Empty state: `"No custom foods yet"` + the `+ ADD CUSTOM` pill.

---

### 🟫 AI Snapshot Expansion (Q6.3)

#### **Add `meals_today` to AI snapshot**

In `AiCoachRepository.buildAiContext()`:

```dart
'meals_today': _getMealsToday(),  // NEW
```

New method `_getMealsToday()`:
- Reads `nutritionBox` `nlog_*` rows where `date == today`.
- Groups by `meal_type` (breakfast/lunch/dinner/snacks).
- Returns:
```dart
[
  {
    'slot': 'breakfast',
    'items': [{'name': 'Oats', 'kcal': 152, 'protein_g': 5, 'carbs_g': 27, 'fat_g': 3}],
    'total_kcal': 307,
    'total_protein_g': 13,
  },
  // ... up to 4 slots
]
```
- Token cost ~300–500 bytes typical.

#### **Add `nutrition_trend_7d` to AI snapshot**

```dart
'nutrition_trend_7d': _getNutritionTrend7d(),  // NEW
```

New method `_getNutritionTrend7d()`:
- Iterates last 7 days of `nutritionBox` rows.
- Returns:
```dart
[
  {'date': '2026-04-26', 'calories': 0,    'protein_g': 0,   'carbs_g': 0,   'fat_g': 0,   'fiber_g': 0},
  {'date': '2026-04-25', 'calories': 1820, 'protein_g': 92,  'carbs_g': 220, 'fat_g': 65, 'fiber_g': 24},
  // ...
]
```
- Token cost ~200 bytes.

#### **Update `AiService._compactContext` trim order**

Add both new keys to the same priority lane as `step_history_7d` (drop early under pressure):

```
step_history_7d → meals_today → nutrition_trend_7d → weight_trend → ...
```

---

## Files to Modify

### Migrations & backend
- **NEW** `supabase/migrations/039_rank_system_and_auth_fk.sql` (Bug A + Obs 1 storage)
- **NEW** `supabase/functions/evaluate-rank-promotions/index.ts` (cron Edge Function)
- **MODIFY** `supabase/functions/ai-proxy/index.ts` (Bug C: day-of-week injection + anti-fabrication rule). Deploy as v48.

### Sync
- **MODIFY** `lib/features/profile/screens/edit_profile_screen.dart:1423-1542` (Bug B: fire `syncProfileNow` + `pushSnapshot`)
- **MODIFY** `lib/core/services/sync_service.dart` — verify `syncProgressNow` exists; if not, add. Audit other sync gaps from Bug B's broader audit.

### Forever-Friend (Obs 1)
- **NEW** `lib/core/services/rank_service.dart` (`evaluateAndPromote`, `getCurrentRank`, `getNextRank`, `getLadder`)
- **NEW** `lib/shared/widgets/wardroom/rank_chip.dart` (compact rank chip primitive — reused on Home + Train + Profile)
- **NEW** `lib/shared/widgets/wardroom/rank_insignia.dart` (renders the SVG insignia for any `rank_code`)
- **NEW** `lib/features/profile/widgets/service_record_section.dart` (Profile Service Record card)
- **NEW** `lib/features/train/screens/roadmap_screen.dart` (full-screen `/train/roadmap` route, vertical timeline)
- **MODIFY** `lib/features/train/screens/train_screen.dart` (insert rank chip + reorder Roadmap pill above This Week)
- **MODIFY** `lib/features/home/screens/home_screen.dart` (insert rank line below streak counter)
- **MODIFY** `lib/features/profile/screens/profile_screen.dart` (insert SERVICE RECORD section above bio stats)
- **MODIFY** `lib/core/router/app_router.dart` (add `/train/roadmap` route)
- **MODIFY** `lib/features/train/providers/train_provider.dart` (`previewPlanProvider`: ensure same VolumeFilter inputs as actual plan — Phase exercise count fix)
- **MODIFY** `lib/features/train/providers/train_provider.dart` (`completeWorkout`: fire `RankService.evaluateAndPromote()`)

### AI
- **MODIFY** `lib/features/ai_coach/repositories/ai_coach_repository.dart:40-90` (add `meals_today` + `nutrition_trend_7d` to snapshot, also `current_rank` from coach_memory)
- **MODIFY** `lib/core/services/ai_service.dart` `_compactContext` (trim order)

### Nutrition (Obs 2 + Obs 3)
- **NEW** `lib/features/nutrition/services/diet_plan_generator.dart` (extract anchor-protein-per-meal algorithm; testable)
- **MODIFY** `lib/features/nutrition/screens/diet_plan_screen.dart` (use new generator)
- **MODIFY** `lib/features/nutrition/screens/nutrition_screen.dart` (full body rewrite per Obs 3 layout — drop the 5 logging sections, add CTA, reorder)
- **NEW** `lib/features/nutrition/widgets/log_food_sheet.dart` (the `+ LOG FOOD` bottom sheet hosting 5 modes)
- **NEW** `lib/features/nutrition/widgets/hydration_card.dart` (Q8.1=A combined Hydration + Urine card; replaces `hydration_section.dart`)
- **NEW** `lib/features/nutrition/widgets/your_foods_section.dart` (mirror of Train YOUR EXERCISES)
- **REFACTOR** `lib/features/nutrition/widgets/{ai_breakdown_card,food_logger_section,scan_meal_section,cart_auditor_section,barcode_scan_sheet,saved_meals_section}.dart` → repurpose as bottom-sheet mode widgets, drop them from `nutrition_screen.dart` body

---

## Reused Code (do not reinvent)

| Existing utility | Location | Why |
|---|---|---|
| `WardChip` | `lib/shared/widgets/wardroom/ward_chip.dart` | Both segmented tabs in LOG FOOD sheet AND status pills in YOUR FOODS use it |
| `WardCard` | `lib/shared/widgets/wardroom/ward_card.dart` | Hydration card surface |
| `WardLetterhead` | `lib/shared/widgets/wardroom/ward_letterhead.dart` | Section eyebrows (SERVICE RECORD, YOUR FOODS, etc.) |
| `WardSealBadge` (4 variants) | `lib/shared/widgets/wardroom/ward_seal_badge.dart` | May extend with `WardSealVariant.rank` for Service Record |
| `BmrCalculator.calculateTargets` | `lib/core/utils/bmr_calculator.dart` | Macro targets (already used) |
| `WorkoutRepository.calculateCurrentStreak` | existing | Workout streak math for rank gates |
| `SubscriptionService.isPro()` | existing | Roadmap modal locks Phase II/III for free users |
| `_buildYourExercisesSection` pattern | `lib/features/train/screens/train_screen.dart` | YOUR FOODS mirrors this exactly |
| `CustomFoodSheet` | `lib/features/nutrition/widgets/custom_food_sheet.dart` | Tap-to-edit from YOUR FOODS chip |
| `TodaysMealsCard` | existing | Reused; only its position in the page changes |
| `WeeklyChartCard` | existing | Reused for INSIGHTS & TRENDS section |
| `ai-proxy` Edge Function | existing | Modified in place for Bug C; deploy as v48 |

---

## Verification Plan

Run on prod APK via `/build-apk` skill (per CLAUDE.md). On-device verification:

### Bug fixes
1. **Bug A.** Sign up with a brand-new email, immediately do onboarding, log a workout, send AI chat, create a custom food. Within 30s confirm: (a) `public.users` row exists, (b) `user_profile` row exists, (c) `ai_coach_interactions` row exists, (d) `user_custom_foods` row exists. Then delete the auth user via Supabase dashboard. Confirm `public.users` row CASCADE-deletes (no orphan).
2. **Bug B.** With the test account, Profile → Edit Profile → change name → Save. Within 5s confirm `user_profile.full_name` matches in Supabase.
3. **Bug C.** Send AI message "What's my workout today?" on a Sunday. Response must include "Sunday" not "Monday". With 0 workout_logs, response must NOT cite percentages or "100% skip" stats.

### Forever-friend
4. **Rank ladder.** Brand-new account → confirm Home shows `⚓ SEAMAN 2ND CLASS · NEXT IN ~12 DAYS`. Confirm Profile → SERVICE RECORD shows ladder with SD2 earned, all others locked. Tap any locked rank → detail sheet opens.
5. **Train layout.** Confirm rank chip is at top, Today's Workout below it, then `DEPLOYMENT 01 — FOUNDATION (Week 1 of 12)` header + ROADMAP pill, then THIS WEEK calendar. Roadmap pill is ABOVE THIS WEEK (was below pre-batch).
6. **Roadmap modal.** Tap ROADMAP pill → `/train/roadmap` opens. Vertical scroll. W1 marker highlighted. Year 1 / Year 2 / Years 3-5 dividers visible. Captain marker faintly visible at far edge. Tap a rank marker → detail sheet shows insignia + gate + your progress.
7. **Phase exercise count.** Today card and Roadmap modal show the SAME exercise count for the user's experience+days. No 6/7/8 mismatch.
8. **Rank promotion fires.** Complete first scheduled workout → after 7 successful workouts, confirm SD1 promotion fires → push notification + AI coach celebration message + `rank_promotions` row in Supabase + Profile Service Record updates.

### Diet plan
9. **Protein adherence.** Open Diet Plan. With target 138g protein, sum the generated plan's protein. Should be ≥ 95% of target (≥ 131g). Anchor protein visible in each meal slot (egg/whey/paneer in breakfast, chicken/dal/paneer in lunch+dinner).

### Nutrition page redesign
10. **Layout.** First paint shows: header → summary → `+ LOG FOOD` CTA → Hydration combined card → Today's Meals → Insights → YOUR FOODS. Total scroll ≤ 800 dp on a 360×640 viewport.
11. **+ LOG FOOD sheet.** Tap CTA → bottom sheet opens. AI tab default. All 5 modes work end-to-end. Sheet dismisses on save; page refreshes.
12. **Hydration card.** Water + urine in one card. Tap `[change ▾]` → 8-color picker expands inline. Tip line updates on selection.
13. **YOUR FOODS.** Section visible with status pills. Empty state for new users. Tap chip → `CustomFoodSheet` opens.

### AI snapshot
14. **`meals_today`.** Log breakfast (oats + milk). Send AI message "what did I eat today?". AI should reference oats and milk by name (not just totals). Confirm `meals_today` is in the snapshot via debug log.
15. **`nutrition_trend_7d`.** After 7 days of logs, ask "how has my protein been this week?". AI references the 7-day trend.

### Regression sweep
- All existing nutrition mutations still fire `syncNutritionData + pushSnapshot`.
- Existing `MySubmissionsScreen` still shows custom foods correctly (now they reach Supabase via Bug A fix).
- AI coach context size stays under 9.5KB per `_compactContext` trim.
- Rank chip on Home doesn't break the streak counter layout.
- Roadmap modal renders for free + PRO users (Phase II/III locked-state for free).

---

## Follow-ups (NOT in this batch)

**F18 — W12 Debrief flow.** End-of-Deployment AI coach interview that drafts Deployment 02. Will need design + ai-proxy tool extension. Estimated 3 days. Triggers: when `rank_promotions` for `PO` (Petty Officer) is about to fire AND user is at Phase III Week 4.

**F19 — Adaptive seasons UI.** Explicit user-initiated "switch goal" affordance (e.g., "Cut for wedding (8 weeks)" → AI coach tool generates a custom 8-week deployment overriding the current). Requires UI for season picker, ai-proxy tool extension. Estimated 4 days.

**F20 — Rank insignia SVG asset pack.** The migration 039 seeds `insignia_asset` paths like `rank/sd2.svg`...`rank/capt.svg`. The actual SVG files do NOT yet exist in `assets/`. **In this batch, ship with text-fallback `WardSealBadge` rendering** — show the rank short_name (e.g. `SEAMAN 2ND`, `LEADING`, `PETTY OFF.`, `CAPTAIN`) inside a gold-ringed seal. The seed paths in the migration are forward-looking; `RankInsignia` widget reads them but falls back to text rendering when the asset is missing. Final SVG pack delivered separately by an asset designer; UI swaps in automatically once `assets/rank/*.svg` files appear in `pubspec.yaml`. **Do NOT block the batch on asset delivery.**

---

## Rollout

1. Branch: `feat/apk-test-3-batch` off `feat/apk-test-2-batch` (latest unmerged tip — current tip `52eb035`).
2. Recommended commit order to keep review manageable:
   - `feat(db): migration 039 — auth users FK + rank ladder + rank promotions` — Bug A + Obs 1 storage
   - `fix(sync): Edit Profile fires syncProfileNow + pushSnapshot` — Bug B
   - `fix(ai-proxy): inject IST day-of-week + anti-fabrication rule` — Bug C, deploy v48
   - `feat(ai): expand snapshot with meals_today + nutrition_trend_7d` — Q6.3
   - `feat(rank): RankService client + evaluate-rank-promotions cron` — Obs 1 service layer
   - `feat(rank): rank chip primitive + Train/Home/Profile surfaces` — Obs 1 UI
   - `feat(train): roadmap modal at /train/roadmap` — Obs 1 vertical timeline
   - `fix(train): reconcile roadmap preview VolumeFilter inputs` — phase exercise count fix
   - `fix(nutrition): diet plan anchor-protein-per-meal algorithm` — Obs 2
   - `feat(nutrition): + LOG FOOD bottom sheet with 5 modes` — Obs 3 sheet
   - `feat(nutrition): combined Hydration + Urine card` — Obs 3 hydration
   - `feat(nutrition): YOUR FOODS section with status pills` — Obs 3 custom foods
   - `feat(nutrition): page reorder per redesign` — Obs 3 page rewrite
3. After all merges, single `/build-apk` run, then APK test round 4.
