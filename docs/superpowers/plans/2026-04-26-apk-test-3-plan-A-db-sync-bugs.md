# APK Test #3 — Plan A — DB + Sync Bugs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the three P0 sync bugs surfaced in APK Test #3 (orphan public.users blocking re-signups, Edit Profile sync gap, AI day-of-week hallucination) and ship Migration 039 which also seeds the rank ladder used by Plan B.

**Architecture:** Three independent fixes that share the same migration file. (1) Migration 039 adds the missing `public.users.id → auth.users(id)` FK, an auto-create trigger, and the `rank_ladder` + `rank_promotions` tables. (2) Edit Profile saves now fire `unawaited(SyncService.syncProfileNow + pushSnapshot)`. (3) `ai-proxy` injects `Today is <Day>, <Date> (IST)` into the system prompt and adds an anti-fabrication rule. Everything is feature-gated by being additive — no behavior changes for users on the existing fixed paths.

**Tech Stack:** Supabase Postgres (migration), Supabase Edge Functions (Deno + TypeScript for ai-proxy v48), Flutter (Dart 3.4+) for the Edit Profile fix, Riverpod state, Hive offline storage.

**Spec:** `docs/superpowers/specs/2026-04-26-apk-test-3-batch-design.md` (Bug A, Bug B, Bug C sections)

---

## File Structure

| File | Responsibility | New / Modified |
|---|---|---|
| `supabase/migrations/039_rank_system_and_auth_fk.sql` | Single migration for: (1) `public.users → auth.users(id)` FK with CASCADE, (2) `handle_new_auth_user` trigger that auto-creates `public.users` rows on auth signup, (3) `rank_ladder` table + 10 seed rows, (4) `rank_promotions` per-user history table, (5) `current_rank_code` + `current_rank_achieved_at` columns on `user_profile` | New |
| `lib/features/auth/providers/auth_provider.dart` (lines 320–373) | Surface 23505/23503 errors loudly via `client_errors` + debugPrint | Modified |
| `lib/features/profile/screens/edit_profile_screen.dart` (around line 1523) | Fire `unawaited(SyncService.syncProfileNow + pushSnapshot)` after save | Modified |
| `supabase/functions/ai-proxy/index.ts` | Inject IST day-of-week into system prompt; add anti-fabrication rule | Modified, deploy v48 |
| `test/sync/edit_profile_sync_test.dart` | Regex contract test: `_save` calls `syncProfileNow` + `pushSnapshot` | New |
| `test/contracts/ai_proxy_day_injection_test.dart` | Regex contract test: ai-proxy injects day-of-week | New |
| `test/contracts/auth_provider_error_surfacing_test.dart` | Regex contract test: `_ensureLocalUser` logs to `client_errors` | New |

---

## Task 1: Create Migration 039 — auth FK + auto-create trigger

**Files:**
- Create: `supabase/migrations/039_rank_system_and_auth_fk.sql`

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/039_rank_system_and_auth_fk.sql` with this exact content:

```sql
-- 039_rank_system_and_auth_fk.sql
--
-- Two changes bundled because they share a common dependency on the FK
-- chain `<table> → public.users(id) → auth.users(id)`:
--
-- (1) Bug A fix from APK Test #3 (2026-04-26): public.users had NO foreign
--     key to auth.users. Deleting an auth user (test cleanup, account
--     wipe) left an orphan public.users row that squatted the email
--     UNIQUE constraint, which blocked re-signups silently.
--
-- (2) Forever-friend rank system from APK Test #3 design spec, Obs 1:
--     rank_ladder (immutable seeded ladder), rank_promotions (per-user
--     history), denormalized current_rank_code on user_profile.
--
-- The Plan A scope of this migration ships the schema; the RankService
-- + cron logic that writes promotion rows lives in Plan B.

-- ── Part 1: Bug A fix — auth.users FK + auto-create trigger ──────────

-- Before adding the FK, clean up any existing orphans defensively. (The
-- 2026-04-26 cleanup already deleted known orphans; this guards against
-- future ones during dev/test.)
DELETE FROM public.users pu
WHERE NOT EXISTS (
  SELECT 1 FROM auth.users au WHERE au.id = pu.id
);

ALTER TABLE public.users
  ADD CONSTRAINT users_id_fk_auth
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Auto-create public.users row when an auth.users row is inserted.
-- Standard Supabase pattern. Eliminates the race where _ensureLocalUser
-- runs before the email-collision orphan can cause trouble.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, created_at)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    now()
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- ── Part 2: rank_ladder (seeded once, immutable) ─────────────────────

CREATE TABLE IF NOT EXISTS rank_ladder (
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
  ('SD2',   'Seaman 2nd Class',           'Seaman 2nd', 0, 0,   'rank/sd2.svg',   'sailor',  FALSE),
  ('SD1',   'Seaman 1st Class',           'Seaman 1st', 1, 1,   'rank/sd1.svg',   'sailor',  FALSE),
  ('LS',    'Leading Seaman',             'Leading',    2, 4,   'rank/ls.svg',    'sailor',  FALSE),
  ('PO',    'Petty Officer',              'Petty Off.', 3, 12,  'rank/po.svg',    'sailor',  FALSE),
  ('CPO',   'Chief Petty Officer',        'Chief PO',   4, 26,  'rank/cpo.svg',   'sailor',  FALSE),
  ('MCPO',  'Master Chief Petty Officer', 'Master Ch.', 5, 52,  'rank/mcpo.svg',  'sailor',  FALSE),
  ('SubLt', 'Sub Lieutenant',             'Sub Lt',     6, 104, 'rank/sublt.svg', 'officer', FALSE),
  ('LtCdr', 'Lieutenant Commander',       'Lt Cdr',     7, 156, 'rank/ltcdr.svg', 'officer', FALSE),
  ('Cdr',   'Commander',                  'Cdr',        8, 208, 'rank/cdr.svg',   'officer', FALSE),
  ('Capt',  'Captain',                    'Captain',    9, 260, 'rank/capt.svg',  'officer', TRUE)
ON CONFLICT (rank_code) DO NOTHING;

-- ── Part 3: rank_promotions (per-user history) ───────────────────────

CREATE TABLE IF NOT EXISTS rank_promotions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rank_code        TEXT NOT NULL REFERENCES rank_ladder(rank_code),
  achieved_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  trigger_type     TEXT NOT NULL CHECK (trigger_type IN (
    'signup', 'first_sync', 'phase_complete', 'deployment_complete',
    'calendar', 'workout_count', 'combined'
  )),
  trigger_metadata JSONB,
  UNIQUE (user_id, rank_code)
);

CREATE INDEX IF NOT EXISTS idx_rank_promotions_user
  ON rank_promotions (user_id, achieved_at DESC);

ALTER TABLE rank_promotions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rank_promotions_select_own ON rank_promotions;
CREATE POLICY rank_promotions_select_own ON rank_promotions
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS rank_promotions_insert_own ON rank_promotions;
CREATE POLICY rank_promotions_insert_own ON rank_promotions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ── Part 4: Denormalized current rank on user_profile ────────────────

ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS current_rank_code        TEXT REFERENCES rank_ladder(rank_code) DEFAULT 'SD2',
  ADD COLUMN IF NOT EXISTS current_rank_achieved_at TIMESTAMPTZ DEFAULT now();
```

- [ ] **Step 2: Apply migration via MCP `apply_migration` tool**

Use the Supabase MCP tool `mcp__ba7b5e8e-...__apply_migration` with:
- `project_id: "dedsavbjuwgarrhphgnl"`
- `name: "039_rank_system_and_auth_fk"`
- `query`: paste the SQL from Step 1 verbatim.

Expected: returns success without errors. (The `IF NOT EXISTS` and `ON CONFLICT` guards make it idempotent — safe to retry.)

- [ ] **Step 3: Verify schema landed correctly**

Run via `execute_sql`:
```sql
SELECT
  (SELECT count(*) FROM rank_ladder) AS ladder_rows,
  (SELECT count(*) FROM rank_promotions) AS promotions_rows,
  (SELECT count(*) FROM information_schema.table_constraints
     WHERE constraint_name = 'users_id_fk_auth') AS auth_fk_count,
  (SELECT count(*) FROM information_schema.triggers
     WHERE trigger_name = 'on_auth_user_created') AS trigger_count,
  (SELECT count(*) FROM information_schema.columns
     WHERE table_name = 'user_profile' AND column_name = 'current_rank_code') AS rank_col_count;
```
Expected: `{ladder_rows: 10, promotions_rows: 0, auth_fk_count: 1, trigger_count: 1, rank_col_count: 1}`.

- [ ] **Step 4: Backfill `current_rank_code` for existing users**

Existing users were not created via the new auto-create trigger. They need their denormalized rank seeded to `'SD2'` (the default already kicks in via `DEFAULT 'SD2'`, but rows that pre-existed before the migration may have NULL until something writes to them).

Run via `execute_sql`:
```sql
UPDATE user_profile
SET current_rank_code = 'SD2', current_rank_achieved_at = now()
WHERE current_rank_code IS NULL;
```

Expected: a small number of rows affected (depends on how many user_profile rows pre-existed). Plan B will replace `'SD2'` with the actual qualified rank for each user via the cron.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/039_rank_system_and_auth_fk.sql
git commit -m "feat(db): migration 039 — auth users FK + rank ladder schema

Bug A fix: public.users now has FK to auth.users(id) ON DELETE CASCADE,
eliminating orphan rows that blocked re-signup with the same email.
Auto-create trigger on auth.users INSERT writes the public.users row
atomically, removing the race window.

Plan B foundations: rank_ladder seeded with 10-rung Indian Navy ladder,
rank_promotions per-user history table with RLS, denormalized
current_rank_code + current_rank_achieved_at on user_profile.

Idempotent (IF NOT EXISTS / ON CONFLICT). Backfilled existing
user_profile rows to current_rank_code='SD2'."
```

---

## Task 2: Surface auth provider errors loudly

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart` (around line 370–373)
- Test: `test/contracts/auth_provider_error_surfacing_test.dart`

**Background:** The existing catch at line 370 silently swallows 23505/23503 with only a `debugPrint`. Bug A's silent failures hid for 48 hours because of this. We need errors to land in `client_errors` so they're visible across devices.

- [ ] **Step 1: Write the failing contract test**

Create `test/contracts/auth_provider_error_surfacing_test.dart`:
```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for Bug A's silent-swallow class.
///
/// _ensureLocalUser previously caught all errors with just debugPrint,
/// hiding 23505/23503 violations for 48h. This test pins the requirement
/// that errors get logged to `client_errors` so they're visible.
void main() {
  test('_ensureLocalUser logs errors to client_errors edge function', () {
    final source = File(
      'lib/features/auth/providers/auth_provider.dart',
    ).readAsStringSync();

    // Find the _ensureLocalUser method body
    final ensureStart = source.indexOf('Future<void> _ensureLocalUser(');
    expect(ensureStart, isNot(-1),
        reason: '_ensureLocalUser must exist on AuthNotifier');

    // The method should run from declaration to next top-level method.
    // Take a generous slice (4000 chars covers the whole method).
    final body = source.substring(ensureStart, ensureStart + 4000);

    // Must call log-client-error Edge Function on catch path
    expect(
      body.contains('log-client-error'),
      isTrue,
      reason:
          '_ensureLocalUser catch blocks must call the log-client-error '
          'Edge Function so silent FK / UNIQUE violations show up in '
          'client_errors. Bug A hid for 48h because of silent swallow.',
    );

    // Must check for Postgres error codes 23505/23503 explicitly so the
    // error type is preserved in the log payload.
    expect(
      body.contains('23505') || body.contains('23503'),
      isTrue,
      reason:
          'Catch path should detect 23505 (unique_violation) and '
          '23503 (foreign_key_violation) so the AI-readable error_type '
          'is correct.',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/contracts/auth_provider_error_surfacing_test.dart
```
Expected: FAIL with reason "_ensureLocalUser catch blocks must call the log-client-error Edge Function".

- [ ] **Step 3: Modify `_ensureLocalUser` to log to `log-client-error`**

In `lib/features/auth/providers/auth_provider.dart`, find the catch block at the end of the upsert section (around line 370–373):

```dart
} catch (e) {
  debugPrint('users table upsert failed: $e');
  // Non-fatal for sign-in, but AI chat may fail if row is missing.
}
```

Replace with:

```dart
} catch (e) {
  debugPrint('[_ensureLocalUser] users table upsert failed: $e');
  // Bug A defense (2026-04-26): silent-swallow let an orphan public.users
  // row block sync for 48h. Surface PostgrestException codes 23505 / 23503
  // to the cloud so future failures are auditable across devices.
  String errorType = 'users_upsert_failed';
  final eStr = e.toString();
  if (eStr.contains('23505')) errorType = 'users_unique_violation_23505';
  if (eStr.contains('23503')) errorType = 'users_fk_violation_23503';
  unawaited(_logClientError(user.id, errorType, eStr));
  // Non-fatal for sign-in flow, but AI chat / sync may fail until
  // resolved. Now visible in client_errors instead of only debugPrint.
}
```

Also add a private helper method on the same class (place it directly below `_ensureLocalUser`):

```dart
  /// Posts a single error event to the `log-client-error` Edge Function.
  /// Fire-and-forget. Catches its own errors so logging never throws.
  Future<void> _logClientError(
    String userId,
    String errorType,
    String message,
  ) async {
    try {
      await _supabase.client.functions.invoke(
        'log-client-error',
        body: {
          'user_id': userId,
          'error_type': errorType,
          'message': message.length > 1000
              ? message.substring(0, 1000)
              : message,
          'source': 'auth_provider._ensureLocalUser',
        },
      );
    } catch (_) {
      // Swallow — error logging must never break the host flow.
    }
  }
```

Make sure `import 'dart:async';` is at the top of the file (for `unawaited`).

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/contracts/auth_provider_error_surfacing_test.dart
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/contracts/auth_provider_error_surfacing_test.dart \
        lib/features/auth/providers/auth_provider.dart
git commit -m "fix(auth): surface _ensureLocalUser errors via log-client-error

Bug A silent-swallow class fix. The catch block at line 370 used to
debugPrint and continue, hiding 23505 (unique_violation) and 23503
(FK violation) for 48h. Now posts a typed error event to the
log-client-error Edge Function so future failures are auditable
across devices.

Regression test in test/contracts/auth_provider_error_surfacing_test.dart
ensures the log call survives any future refactor."
```

---

## Task 3: Edit Profile Save fires Supabase sync (Bug B)

**Files:**
- Modify: `lib/features/profile/screens/edit_profile_screen.dart` (around line 1523)
- Test: `test/sync/edit_profile_sync_test.dart`

- [ ] **Step 1: Write the failing contract test**

Create `test/sync/edit_profile_sync_test.dart`:
```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for Bug B (APK Test #3, 2026-04-26).
///
/// edit_profile_screen._save() previously only wrote to Hive via
/// updateProfile + recalculateTargets. user_profile in Supabase
/// stayed empty/stale forever, breaking AI coach context.
///
/// Fix: fire syncProfileNow + pushSnapshot fire-and-forget after save.
void main() {
  test('Edit Profile _save fires syncProfileNow + pushSnapshot', () {
    final source = File(
      'lib/features/profile/screens/edit_profile_screen.dart',
    ).readAsStringSync();

    // Find the _save method
    final saveStart = source.indexOf('Future<void> _save() async {');
    expect(saveStart, isNot(-1), reason: '_save must exist');

    // Take a generous body slice (5000 chars covers the whole method)
    final body = source.substring(saveStart, saveStart + 5000);

    expect(
      body.contains('syncProfileNow'),
      isTrue,
      reason: '_save must call SyncService.instance.syncProfileNow(userId) '
          'fire-and-forget after recalculateTargets so user_profile in '
          'Supabase reflects the change. Bug B (APK Test #3).',
    );

    expect(
      body.contains('pushSnapshot'),
      isTrue,
      reason: '_save must also call SyncService.instance.pushSnapshot() '
          'so the AI coach context refreshes after profile changes.',
    );

    // Must wrap in unawaited so save UX is not blocked by network.
    expect(
      body.contains('unawaited(SyncService.instance.syncProfileNow') ||
          body.contains('unawaited(SyncService.instance.pushSnapshot'),
      isTrue,
      reason: 'Both sync calls MUST be unawaited (fire-and-forget) — '
          'sync failures must never block the user-visible Save flow.',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/sync/edit_profile_sync_test.dart
```
Expected: FAIL with reason "_save must call SyncService.instance.syncProfileNow".

- [ ] **Step 3: Modify `_save` to fire sync after recalculateTargets**

In `lib/features/profile/screens/edit_profile_screen.dart`, find the block right after `recalculateTargets()` is called (around line 1523-1524):

```dart
      await ref.read(userProfileProvider.notifier).updateProfile(updates);
      await ref.read(userProfileProvider.notifier).recalculateTargets();

      // Refresh downstream views that cache profile-derived targets/state.
```

Insert these lines BETWEEN `recalculateTargets()` and the `// Refresh downstream views` comment:

```dart
      await ref.read(userProfileProvider.notifier).updateProfile(updates);
      await ref.read(userProfileProvider.notifier).recalculateTargets();

      // Bug B fix (APK Test #3, 2026-04-26): Edit Profile previously wrote
      // only to Hive. user_profile in Supabase stayed empty/stale forever,
      // which broke AI coach context (the snapshot reads from Hive but
      // server-side helpers like rolling-context need the cloud row).
      // Fire-and-forget so sync failures don't block the Save UX.
      final supaUserId = SupabaseService.instance.client.auth.currentUser?.id;
      if (supaUserId != null) {
        unawaited(SyncService.instance.syncProfileNow(supaUserId));
        unawaited(SyncService.instance.pushSnapshot());
      }

      // Refresh downstream views that cache profile-derived targets/state.
```

Verify the imports at the top of the file include:
- `import 'dart:async';` (for `unawaited`)
- `import 'package:icanbefitter/core/services/supabase_service.dart';`
- `import 'package:icanbefitter/core/services/sync_service.dart';`

If any are missing, add them to the import block.

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/sync/edit_profile_sync_test.dart
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/sync/edit_profile_sync_test.dart \
        lib/features/profile/screens/edit_profile_screen.dart
git commit -m "fix(sync): Edit Profile fires syncProfileNow + pushSnapshot

Bug B fix from APK Test #3 (2026-04-26). edit_profile_screen._save
used to write only to Hive. user_profile rows in Supabase stayed
empty/stale forever, breaking AI coach context for any user who
edited their profile after onboarding.

Now fires unawaited(SyncService.syncProfileNow + pushSnapshot)
fire-and-forget right after recalculateTargets, matching the
pattern documented in CLAUDE.md §15 for all mutations.

Verified end-to-end on test account 00cc3dd5- (upendra.prasad@thinkingcode.com)."
```

---

## Task 4: ai-proxy injects IST day-of-week + anti-fabrication rule (Bug C)

**Files:**
- Modify: `supabase/functions/ai-proxy/index.ts`
- Test: `test/contracts/ai_proxy_day_injection_test.dart`

**Background:** ai-proxy v47 has zero matches for `day_of_week | weekday | toLocaleDateString`. Gemini hallucinated "today, Monday" on a Sunday. Fix injects IST day/date and tells Gemini not to invent statistics.

- [ ] **Step 1: Write the failing contract test**

Create `test/contracts/ai_proxy_day_injection_test.dart`:
```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for Bug C (APK Test #3, 2026-04-26).
///
/// ai-proxy/index.ts had no day-of-week injection in the system prompt,
/// so Gemini guessed (called Sunday "Monday" + invented "100% skip" stat).
void main() {
  test('ai-proxy injects IST day-of-week into system prompt', () {
    final source = File(
      'supabase/functions/ai-proxy/index.ts',
    ).readAsStringSync();

    // Day-of-week injection
    expect(
      source.contains('Asia/Kolkata') &&
          (source.contains('weekday') || source.contains('day_of_week')),
      isTrue,
      reason: 'ai-proxy must compute current weekday in Asia/Kolkata '
          'timezone and inject it into the system prompt. Bug C.',
    );

    // Anti-fabrication rule must be present
    expect(
      source.contains('NEVER cite percentages') ||
          source.contains('never cite percentages') ||
          source.contains('do not invent statistics') ||
          source.contains('Do NOT invent statistics'),
      isTrue,
      reason: 'ai-proxy system prompt must include an anti-fabrication '
          'rule warning Gemini not to cite percentages/trends without '
          'data support. Bug C ("100% skip Monday workouts" hallucination).',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/contracts/ai_proxy_day_injection_test.dart
```
Expected: FAIL with both reasons.

- [ ] **Step 3: Find the system prompt assembly point in ai-proxy**

Read `supabase/functions/ai-proxy/index.ts` and locate the section that builds `systemPrompt` for the chat channel. Look for either:
- A variable named `systemPrompt` being assigned a multi-line string
- Or a function call like `buildSystemPrompt(...)` that returns the prompt

Note the line range so the next step can be applied precisely.

- [ ] **Step 4: Inject the day-of-week prefix and anti-fabrication rule**

At the top of the chat-handler block (immediately before `systemPrompt` is finalized for the Gemini call), insert:

```typescript
// Bug C fix (APK Test #3, 2026-04-26): inject the current IST day of
// week so Gemini stops hallucinating "today, Monday" on a Sunday.
// ai-proxy v47 had zero day-injection — model guessed.
const istNow = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
const todayName = istNow.toLocaleDateString("en-US", {
  weekday: "long",
  timeZone: "Asia/Kolkata",
});
const todayIso = istNow.toISOString().split("T")[0];

const dayInjection = `Today is ${todayName}, ${todayIso} (IST). When the user asks about "today", use this exact date and weekday.\n\n`;

const antiFabricationRule = `
IMPORTANT — Anti-fabrication rule:
Do NOT invent statistics. NEVER cite percentages, averages, frequencies,
or trends about the user's missed workouts, skipped days, attendance
patterns, or behavior unless the snapshot's "recent_logs",
"coach_notices", "nutrition_trend_7d", or "meals_today" actually contains
data supporting that claim. If asked about behavior with insufficient
data, say so honestly: "I don't have enough data on your Monday pattern
yet" — never make up a number.
`;

systemPrompt = dayInjection + systemPrompt + "\n\n" + antiFabricationRule;
```

(Adjust the variable assignment to match the existing prompt-building style. The key invariants: `Asia/Kolkata` is referenced, `weekday: "long"` is used, and the anti-fabrication string is appended.)

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/contracts/ai_proxy_day_injection_test.dart
```
Expected: PASS.

- [ ] **Step 6: Deploy ai-proxy v48**

Use the host-shell deploy flow (see CLAUDE.md §0 / MEMORY.md "Deploy workflow"):

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js ai-proxy --auto --functions-dir "C:/Upendra/Claude Code/Fitness App/supabase/functions"
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy ".claude/_payload_ai-proxy.json" false --dry-run
```

Inspect the dry-run output. If clean, drop `--dry-run` and run again to actually deploy. Expect HTTP 201 with version bumped to 48 (or higher if previous redeploys happened).

- [ ] **Step 7: Live verify the fix**

Use `mcp__ba7b5e8e-...__execute_sql` to insert a chat row from the test user and check the response, OR have the human tester send "What's my workout today?" via the app on the next test session.

Quick programmatic verification:
```bash
curl -X POST 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/ai-proxy' \
  -H "Authorization: Bearer <test-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"message":"What day is it?","channel":"chat","mode":"chat","snapshot":"{}"}'
```
Expected: response references the actual IST weekday.

- [ ] **Step 8: Commit**

```bash
git add test/contracts/ai_proxy_day_injection_test.dart \
        supabase/functions/ai-proxy/index.ts
git commit -m "fix(ai-proxy): inject IST day-of-week + anti-fabrication rule

Bug C fix from APK Test #3 (2026-04-26). ai-proxy v47 had no
day-of-week injection. Gemini hallucinated 'today, Monday' on
Sunday 2026-04-26 + invented '100% skip Monday workouts' stat
(user has 0 workout_logs).

System prompt now prepends 'Today is <Day>, <YYYY-MM-DD> (IST)'
and appends an explicit anti-fabrication rule forbidding
percentages/trends about user behavior without data support.

Deployed as ai-proxy v48 via host-shell pipeline."
```

---

## Task 5: Verify the migration on a fresh Supabase test signup

**Files:** None (verification-only).

This task validates the trigger works end-to-end before Plans B/C/D rely on it.

- [ ] **Step 1: Sign up a throwaway test user via Supabase Auth**

Use the Supabase dashboard at https://supabase.com/dashboard/project/dedsavbjuwgarrhphgnl/auth/users → "Add user" → email `apk3-trigger-test@example.com`, password `TestPlanA-2026`, auto-confirm.

- [ ] **Step 2: Verify the trigger created the public.users row automatically**

Run:
```sql
SELECT
  au.id, au.email, au.created_at AS auth_created,
  pu.id IS NOT NULL AS has_public_row,
  pu.created_at AS public_created
FROM auth.users au
LEFT JOIN public.users pu ON pu.id = au.id
WHERE au.email = 'apk3-trigger-test@example.com';
```

Expected: one row, `has_public_row = true`, `public_created` within ~1 second of `auth_created`.

- [ ] **Step 3: Verify CASCADE delete works**

Delete the throwaway from `auth.users` (via dashboard or SQL). Then check:
```sql
SELECT count(*) AS leftover_rows
FROM public.users
WHERE email = 'apk3-trigger-test@example.com';
```

Expected: `leftover_rows = 0`. If non-zero, the FK + CASCADE didn't take — re-check Migration 039 Part 1.

- [ ] **Step 4: Verify orphan check is clean**

```sql
SELECT count(*) AS orphans
FROM public.users pu
LEFT JOIN auth.users au ON au.id = pu.id
WHERE au.id IS NULL;
```

Expected: `orphans = 0`.

- [ ] **Step 5: Document verification result**

This task has no commit; it's a confidence checkpoint. If all four checks pass, proceed to Plan B. If any fail, stop and re-investigate.

---

## Self-Review

**Spec coverage:**
- Bug A schema fix → Task 1 (Migration 039 Part 1) ✓
- Bug A error surfacing → Task 2 ✓
- Bug B Edit Profile sync → Task 3 ✓
- Bug C day-of-week + anti-fab → Task 4 ✓
- rank_ladder + rank_promotions + denorm columns (Plan B prerequisite) → Task 1 (Parts 2–4) ✓
- Live verification → Task 5 ✓

**Placeholder scan:** None. Every step has concrete code or commands.

**Type consistency:** `current_rank_code` referenced in Task 1 matches `user_profile` column declaration. Migration trigger function `handle_new_auth_user` matches the trigger reference name. Edge Function name `log-client-error` referenced in Task 2 is an existing function (verified via grep `log-client-error`).

**Cross-plan dependency:** Plan B Task 1 will read `rank_ladder` and write `rank_promotions` — both ship in Plan A. Plan B blocked on Plan A landing.
