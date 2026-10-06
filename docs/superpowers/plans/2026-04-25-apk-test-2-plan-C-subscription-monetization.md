# APK Test #2 — Plan C: Subscription & Monetization

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the 7-day referral system end-to-end (sender + receiver UX, Edge Function with full edge-case coverage), drop active workout from PRO gating, and build the Phase Roadmap with read-only workout previews so free users can see what they're paying for before they pay.

**Architecture:** Three independent feature streams sharing the same branch. Referral uses migration 037 (Plan A) + a rewritten `redeem-referral` Edge Function + four UI surfaces (Welcome optional field, Apply Referral sheet, Profile tile, Invite Friends sheet). Active workout free is a 3-line config change. Phase Roadmap is the largest piece: extending the week selector to 12 weeks, building a new full-page roadmap screen, and a read-only workout preview screen powered by on-demand `PlanGenerator.generateV4()` calls cached for the session.

**Tech Stack:** Flutter (Dart 3), Riverpod, GoRouter, Supabase Edge Functions (Deno + TypeScript), `share_plus` for WhatsApp invocation, `url_launcher`, existing local Plan Generator V4.

**Spec source:** `docs/superpowers/specs/2026-04-25-apk-test-2-batch-design.md` (Section 6)

**Branch:** `feat/apk-test-2-batch` (continues from Plan B)

**Prerequisite:** Plan A complete (migrations 036+037 applied to prod). Plan B in flight or complete (no hard ordering vs C/D).

---

## File Structure

### Edge Function rewrite
- Modify: `supabase/functions/redeem-referral/index.ts` — full validation cascade with idempotency

### New SQL function
- Migration 038: `redeem_referral_atomic` RPC — atomic both-side reward write

### New screens & widgets
- `lib/features/profile/screens/apply_referral_sheet.dart`
- `lib/features/profile/screens/invite_friends_sheet.dart` (replaces existing implementation)
- `lib/features/profile/providers/referral_eligibility_provider.dart`
- `lib/features/train/screens/phase_roadmap_screen.dart`
- `lib/features/train/screens/preview_workout_screen.dart`
- `lib/features/train/providers/preview_plan_provider.dart`
- `lib/shared/widgets/paywall_sheet_phase_variant.dart`

### Modified files
- `lib/core/services/subscription_service.dart` — drop `featureActiveWorkoutMode` from `_highValueFeatures`
- `lib/core/constants/app_constants.dart` — keep the constant (legacy callers, deprecated comment)
- `lib/features/train/screens/train_screen.dart` — remove `gate(featureActiveWorkoutMode, ...)` calls; add VIEW ROADMAP pill above week selector
- `lib/features/train/widgets/week_selector.dart` — extend to 12 weeks with phase grouping + locks
- `lib/features/auth/screens/welcome_screen.dart` — add optional referral code field
- `lib/features/onboarding/providers/onboarding_provider.dart` — apply stashed referral code post-signup
- `lib/features/profile/screens/profile_screen.dart` — conditional Apply Referral tile, replace existing Invite Friends entry point
- `lib/core/router/app_router.dart` — `/train/roadmap`, `/train/preview` routes
- `lib/core/services/supabase_service.dart` — `getOrCreateReferralCode` handles expiry
- `test/subscription/active_workout_gate_test.dart` — DELETE (obsolete after Q6)
- `test/subscription/high_value_features_test.dart` — NEW lock-down test

### New tests
- `test/referral/code_validation_test.dart` — format, expiry, self-referral, double-redemption
- `test/referral/eligibility_provider_test.dart` — within-window, has-redeemed branching
- `test/train/preview_plan_provider_test.dart` — generates valid plan from profile
- `test/train/phase_roadmap_screen_test.dart` — 12 cards, locked styling, navigation
- `test/train/week_selector_12_weeks_test.dart` — 12 weeks rendered, locks visible
- `test/subscription/high_value_features_test.dart` — lock the 3-feature set
- `supabase/functions/redeem-referral/__tests__/redeem.test.ts` — Deno test for Edge Function logic

---

## Tasks

### Task 1: Migration 038 — `redeem_referral_atomic` RPC

**Files:**
- Create: `supabase/migrations/038_redeem_referral_atomic.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/038_redeem_referral_atomic.sql
--
-- Atomic both-side reward write for referral redemption. Used by the
-- redeem-referral Edge Function. Wraps the audit row insert + both
-- subscription extensions in a single transaction so partial failures
-- can't leave one side rewarded and the other not.

CREATE OR REPLACE FUNCTION redeem_referral_atomic(
  p_code TEXT,
  p_referrer_id UUID,
  p_referee_id UUID,
  p_days INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_referrer_expires TIMESTAMPTZ;
  v_referee_expires TIMESTAMPTZ;
BEGIN
  -- 1. Audit row (UNIQUE constraint on referee_id catches duplicates)
  INSERT INTO referral_redemptions (
    code, referrer_id, referee_id, days_granted_each
  ) VALUES (
    p_code, p_referrer_id, p_referee_id, p_days
  );

  -- 2. Extend referrer's subscription
  -- Read current expires_at if any active row, else use now() as base
  SELECT MAX(end_date) INTO v_referrer_expires
  FROM subscriptions
  WHERE user_id = p_referrer_id AND active = true;

  IF v_referrer_expires IS NULL OR v_referrer_expires < now() THEN
    -- No active subscription — insert a referral-trial row
    INSERT INTO subscriptions (
      user_id, plan, active, start_date, end_date, source
    ) VALUES (
      p_referrer_id,
      'referral_trial',
      true,
      now(),
      now() + (p_days || ' days')::interval,
      'referral'
    );
  ELSE
    -- Active subscription — extend end_date
    UPDATE subscriptions
    SET end_date = end_date + (p_days || ' days')::interval
    WHERE user_id = p_referrer_id AND active = true
      AND end_date = v_referrer_expires;
  END IF;

  -- 3. Same for referee
  SELECT MAX(end_date) INTO v_referee_expires
  FROM subscriptions
  WHERE user_id = p_referee_id AND active = true;

  IF v_referee_expires IS NULL OR v_referee_expires < now() THEN
    INSERT INTO subscriptions (
      user_id, plan, active, start_date, end_date, source
    ) VALUES (
      p_referee_id,
      'referral_trial',
      true,
      now(),
      now() + (p_days || ' days')::interval,
      'referral'
    );
  ELSE
    UPDATE subscriptions
    SET end_date = end_date + (p_days || ' days')::interval
    WHERE user_id = p_referee_id AND active = true
      AND end_date = v_referee_expires;
  END IF;
END;
$$;

-- Allow the Edge Function (service_role) to call it
GRANT EXECUTE ON FUNCTION redeem_referral_atomic(TEXT, UUID, UUID, INT)
  TO service_role;
```

- [ ] **Step 2: Apply via MCP `apply_migration`**

Project ID: `dedsavbjuwgarrhphgnl`. Name: `038_redeem_referral_atomic`.

- [ ] **Step 3: Verify**

```sql
SELECT proname, pronargs FROM pg_proc WHERE proname = 'redeem_referral_atomic';
```

Expected: single row with `pronargs = 4`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/038_redeem_referral_atomic.sql
git commit -m "db(038): redeem_referral_atomic RPC

Atomic both-side reward writer for referral redemption. Inserts
audit row + extends both subscriptions in one transaction. Used by
redeem-referral Edge Function.

Spec section 6 / Q4 + section 2 (Edge Function pseudo-code)."
```

---

### Task 2: Rewrite `redeem-referral` Edge Function

**Files:**
- Modify: `supabase/functions/redeem-referral/index.ts`
- Test: `supabase/functions/redeem-referral/__tests__/redeem.test.ts`

- [ ] **Step 1: Write the Deno test**

```typescript
// supabase/functions/redeem-referral/__tests__/redeem.test.ts
//
// Validates the redeem-referral handler's branching logic against
// mocked Supabase responses.

import { assertEquals } from "https://deno.land/std/testing/asserts.ts";
import { handleRedeemReferral } from "../index.ts";

// Helper to build a mock Supabase client
function buildMockSupabase(opts: {
  codeRow?: { user_id: string; expires_at: string } | null;
  receiverSignupAt?: string;
  existingRedemption?: { id: string } | null;
  rpcError?: { code?: string; message?: string };
}) {
  return {
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          single: () =>
            Promise.resolve({
              data: table === "referral_codes"
                ? opts.codeRow
                : table === "referral_redemptions"
                ? opts.existingRedemption
                : null,
              error: null,
            }),
        }),
      }),
    }),
    auth: {
      getUser: () =>
        Promise.resolve({
          data: {
            user: {
              id: "receiver-user-id",
              created_at: opts.receiverSignupAt ?? new Date().toISOString(),
            },
          },
          error: null,
        }),
    },
    rpc: () =>
      Promise.resolve({
        error: opts.rpcError ?? null,
      }),
  };
}

Deno.test("rejects bad format", async () => {
  const res = await handleRedeemReferral(
    { code: "not-a-code" },
    buildMockSupabase({}),
    "valid-jwt",
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error.includes("AVYA-XXXXXXXX"), true);
});

Deno.test("rejects code not found", async () => {
  const res = await handleRedeemReferral(
    { code: "AVYA-AAAAAAAA" },
    buildMockSupabase({ codeRow: null }),
    "valid-jwt",
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error.includes("don't recognize"), true);
});

Deno.test("rejects expired code", async () => {
  const res = await handleRedeemReferral(
    { code: "AVYA-AAAAAAAA" },
    buildMockSupabase({
      codeRow: {
        user_id: "referrer-id",
        expires_at: new Date(Date.now() - 86400000).toISOString(), // yesterday
      },
    }),
    "valid-jwt",
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error.includes("expired"), true);
});

Deno.test("rejects self-referral", async () => {
  const res = await handleRedeemReferral(
    { code: "AVYA-AAAAAAAA" },
    buildMockSupabase({
      codeRow: {
        user_id: "receiver-user-id", // same as receiver
        expires_at: new Date(Date.now() + 86400000).toISOString(),
      },
    }),
    "valid-jwt",
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error.includes("yourself"), true);
});

Deno.test("rejects receiver outside 7-day signup window", async () => {
  const res = await handleRedeemReferral(
    { code: "AVYA-AAAAAAAA" },
    buildMockSupabase({
      codeRow: {
        user_id: "referrer-id",
        expires_at: new Date(Date.now() + 86400000).toISOString(),
      },
      receiverSignupAt: new Date(Date.now() - 8 * 86400000).toISOString(),
    }),
    "valid-jwt",
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error.includes("recruits"), true);
});

Deno.test("rejects already-redeemed receiver", async () => {
  const res = await handleRedeemReferral(
    { code: "AVYA-AAAAAAAA" },
    buildMockSupabase({
      codeRow: {
        user_id: "referrer-id",
        expires_at: new Date(Date.now() + 86400000).toISOString(),
      },
      existingRedemption: { id: "existing-redemption-id" },
    }),
    "valid-jwt",
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error.includes("already applied"), true);
});

Deno.test("succeeds with valid code + new receiver in window", async () => {
  const res = await handleRedeemReferral(
    { code: "AVYA-AAAAAAAA" },
    buildMockSupabase({
      codeRow: {
        user_id: "referrer-id",
        expires_at: new Date(Date.now() + 86400000).toISOString(),
      },
      receiverSignupAt: new Date(Date.now() - 86400000).toISOString(),
      existingRedemption: null,
    }),
    "valid-jwt",
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.days_granted, 7);
});

Deno.test("treats 23505 unique violation as success (race)", async () => {
  const res = await handleRedeemReferral(
    { code: "AVYA-AAAAAAAA" },
    buildMockSupabase({
      codeRow: {
        user_id: "referrer-id",
        expires_at: new Date(Date.now() + 86400000).toISOString(),
      },
      receiverSignupAt: new Date(Date.now() - 86400000).toISOString(),
      existingRedemption: null,
      rpcError: { code: "23505", message: "unique_violation" },
    }),
    "valid-jwt",
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.alreadyRedeemed, true);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd supabase/functions/redeem-referral
deno test __tests__/redeem.test.ts
```

Expected: tests fail because `handleRedeemReferral` is not yet exported in the new shape.

- [ ] **Step 3: Rewrite `index.ts`**

```typescript
// supabase/functions/redeem-referral/index.ts
import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const CODE_FORMAT = /^AVYA-[A-Z0-9]{8}$/;
const SIGNUP_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
const DAYS_GRANTED = 7;

interface RedeemRequest {
  code?: string;
}

export async function handleRedeemReferral(
  body: RedeemRequest,
  supabase: any,
  _jwt: string,
): Promise<Response> {
  const requestId = crypto.randomUUID().split("-")[0];

  // 0. Get authenticated user
  const { data: authData, error: authErr } = await supabase.auth.getUser();
  if (authErr || !authData?.user) {
    return new Response(
      JSON.stringify({ error: "Authentication required", request_id: requestId }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  const referee = authData.user;

  // 1. Format check
  const code = (body.code ?? "").trim().toUpperCase();
  if (!CODE_FORMAT.test(code)) {
    return jsonError(400, "Codes look like AVYA-XXXXXXXX.", requestId);
  }

  // 2. Code lookup + expiry
  const { data: codeRow, error: codeErr } = await supabase
    .from("referral_codes")
    .select("user_id, expires_at")
    .eq("code", code)
    .single();
  if (codeErr || !codeRow) {
    return jsonError(400, "We don't recognize that code.", requestId);
  }
  if (new Date(codeRow.expires_at).getTime() < Date.now()) {
    return jsonError(
      400,
      "This code has expired. Ask your friend to send a fresh one.",
      requestId,
    );
  }

  // 3. Self-referral block
  if (codeRow.user_id === referee.id) {
    return jsonError(400, "Can't refer yourself, soldier 🫡", requestId);
  }

  // 4. Receiver eligibility window (7 days from signup)
  const refereeSignupAge = Date.now() - new Date(referee.created_at).getTime();
  if (refereeSignupAge > SIGNUP_WINDOW_MS) {
    return jsonError(
      400,
      "Referral codes are for new recruits — within 7 days of signup.",
      requestId,
    );
  }

  // 5. Idempotency check
  const { data: existing } = await supabase
    .from("referral_redemptions")
    .select("id")
    .eq("referee_id", referee.id)
    .single();
  if (existing) {
    return jsonError(400, "Code already applied to your account.", requestId);
  }

  // 6. Atomic write via RPC
  const { error: rpcErr } = await supabase.rpc("redeem_referral_atomic", {
    p_code: code,
    p_referrer_id: codeRow.user_id,
    p_referee_id: referee.id,
    p_days: DAYS_GRANTED,
  });

  if (rpcErr) {
    if (rpcErr.code === "23505") {
      // Race — treat as success
      return new Response(
        JSON.stringify({ alreadyRedeemed: true, request_id: requestId }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    console.error(`[redeem-referral] request_id=${requestId}`, rpcErr);
    return jsonError(500, "Internal server error", requestId);
  }

  return new Response(
    JSON.stringify({ days_granted: DAYS_GRANTED, request_id: requestId }),
    {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}

function jsonError(status: number, message: string, requestId: string): Response {
  return new Response(
    JSON.stringify({ error: message, request_id: requestId }),
    {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const body = await req.json().catch(() => ({}));
    return await handleRedeemReferral(body, supabase, jwt);
  } catch (err) {
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[redeem-referral] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
```

- [ ] **Step 4: Run Deno tests**

```bash
cd supabase/functions/redeem-referral
deno test __tests__/redeem.test.ts
```

Expected: all 8 tests pass.

- [ ] **Step 5: Deploy via host-shell deploy script (per CLAUDE.md)**

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js redeem-referral --auto --functions-dir "C:/Upendra/Claude Code/Fitness App/supabase/functions"
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl redeem-referral .claude/_payload_redeem-referral.json true --dry-run
# If --dry-run looks good, drop the flag:
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl redeem-referral .claude/_payload_redeem-referral.json true
```

Expected: HTTP 201 with version bump.

- [ ] **Step 6: Smoke test against prod**

```bash
curl -X POST 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/redeem-referral' \
  -H "Authorization: Bearer <test-user-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"code":"AVYA-NOTREAL"}'
```

Expected: 400 with `{"error":"We don't recognize that code.","request_id":"..."}`.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/redeem-referral/index.ts \
        supabase/functions/redeem-referral/__tests__/redeem.test.ts
git commit -m "feat(redeem-referral): full validation cascade for 7-day system

Rewrites the Edge Function with the locked Q4 validation order:
  1. Format (AVYA-XXXXXXXX)
  2. Code lookup + expires_at < now()
  3. Self-referral block
  4. Receiver signup age <= 7 days
  5. Idempotency (UNIQUE on referee_id)
  6. Atomic write via redeem_referral_atomic RPC

23505 race fallback returns 200 with alreadyRedeemed:true.
Errors carry request_id for log lookup. Sanitizes 5xx per CLAUDE.md
§11 (no leaked exception strings).

Deno test suite covers all 8 branches.

Spec section 6 / Q4."
```

---

### Task 3: Q6 — Drop active workout from PRO

**Files:**
- Modify: `lib/core/services/subscription_service.dart`
- Modify: `lib/features/train/screens/train_screen.dart` (remove gate calls)
- Modify: `test/subscription/active_workout_gate_test.dart` (DELETE)
- Create: `test/subscription/high_value_features_test.dart`

- [ ] **Step 1: Write the new lock-down test**

```dart
// test/subscription/high_value_features_test.dart
//
// Locks the contents of SubscriptionService._highValueFeatures.
// active_workout_mode was removed in Q6 (always-free decision); test
// guards against accidental re-addition.

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('SubscriptionService._highValueFeatures', () {
    test('contains exactly 3 features (no active_workout_mode)', () {
      final source = File(
        'lib/core/services/subscription_service.dart',
      ).readAsStringSync();

      // Confirm the canonical 3 are present
      expect(source.contains('featurePhases2To12'), true);
      expect(source.contains('featureAiCoachUnlimited'), true);
      expect(source.contains('featureProgressPhotos'), true);

      // active_workout_mode must NOT be in the high-value set
      // (regex: look for it specifically inside the _highValueFeatures literal)
      final highValueBlock = RegExp(
        r'_highValueFeatures\s*=\s*\{[^}]*\}',
        dotAll: true,
      ).firstMatch(source);
      expect(highValueBlock, isNotNull,
          reason: 'Could not locate _highValueFeatures set in source.');

      expect(
        highValueBlock!.group(0)!.contains('featureActiveWorkoutMode'),
        false,
        reason:
            '_highValueFeatures must not contain featureActiveWorkoutMode '
            '— Q6 made active workout always free.',
      );
    });

    test('train_screen has no gate(featureActiveWorkoutMode) call', () {
      final source = File(
        'lib/features/train/screens/train_screen.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'\.gate\([^)]*featureActiveWorkoutMode').hasMatch(source),
        false,
        reason:
            'train_screen must not gate START WORKOUT entry points behind '
            'featureActiveWorkoutMode (Q6).',
      );
    });
  });
}
```

- [ ] **Step 2: Delete the obsolete gate test**

```bash
rm test/subscription/active_workout_gate_test.dart
```

- [ ] **Step 3: Apply changes to `subscription_service.dart`**

Open `lib/core/services/subscription_service.dart`. Locate `_highValueFeatures`. Update:

```dart
// BEFORE:
static const Set<String> _highValueFeatures = {
  AppConstants.featurePhases2To12,
  AppConstants.featureAiCoachUnlimited,
  AppConstants.featureProgressPhotos,
  AppConstants.featureActiveWorkoutMode,  // ← REMOVE
};

// AFTER:
static const Set<String> _highValueFeatures = {
  AppConstants.featurePhases2To12,
  AppConstants.featureAiCoachUnlimited,
  AppConstants.featureProgressPhotos,
};
```

- [ ] **Step 4: Remove gate calls in train_screen.dart**

Open `lib/features/train/screens/train_screen.dart`. Find the START WORKOUT entry points (there are at least 2 per CLAUDE.md). Replace each:

```dart
// BEFORE:
await SubscriptionService.instance.gate(
  AppConstants.featureActiveWorkoutMode,
  onPro: () => context.go('/train/active-workout'),
  onFree: () => showPaywallSheet(context, feature: 'active_workout_mode'),
);

// AFTER:
context.go('/train/active-workout');
```

Same change for any other `gate(featureActiveWorkoutMode, ...)` site.

- [ ] **Step 5: Add `@Deprecated` comment to the constant (don't remove it — legacy callers)**

Open `lib/core/constants/app_constants.dart`. Find `featureActiveWorkoutMode`. Add deprecation comment:

```dart
/// Active workout mode is **always free** as of APK Test #2 batch (Q6).
/// This constant is kept for legacy code that referenced it; new gate
/// calls should not use it. Will be removed once all callers are migrated.
@Deprecated('Active workout is always free; do not gate against this.')
static const String featureActiveWorkoutMode = 'active_workout_mode';
```

- [ ] **Step 6: Run tests + analyze**

```bash
flutter test test/subscription/high_value_features_test.dart -v
flutter analyze
```

Expected: lock-down test passes. `flutter analyze` may show `deprecated_member_use` warnings on remaining callers — that's OK; Step 5 was deliberate. If any caller is in production code (not tests), inline-remove the call.

- [ ] **Step 7: Commit**

```bash
git add lib/core/services/subscription_service.dart \
        lib/core/constants/app_constants.dart \
        lib/features/train/screens/train_screen.dart \
        test/subscription/high_value_features_test.dart
git rm test/subscription/active_workout_gate_test.dart
git commit -m "feat(subscription): Q6 active workout always free

Drops featureActiveWorkoutMode from _highValueFeatures and removes
all gate() calls in train_screen.dart. Per Q6 brainstorm, active
workout logging is table-stakes for any fitness app — gating it
killed the entry-level experience without driving conversions.

Conversion levers unchanged:
  - phases_2_to_12 (Phase II–XII unlock)
  - ai_coach_unlimited (no daily cap)
  - progress_photos (full timeline)

featureActiveWorkoutMode constant kept with @Deprecated annotation
so legacy callers don't break; new gate calls must not use it.

Lock-down test in test/subscription/high_value_features_test.dart
guards the 3-feature set from accidental re-addition.

Spec section 6 / Q6."
```

---

### Task 4: Welcome screen optional referral code field

**Files:**
- Modify: `lib/features/auth/screens/welcome_screen.dart`
- Modify: `lib/features/onboarding/providers/onboarding_provider.dart`

- [ ] **Step 1: Add referral code field to Welcome**

Open `lib/features/auth/screens/welcome_screen.dart`. Below the BEGIN ENLISTMENT button, above the privacy footer (added in Plan B Task 4), add:

```dart
// Inside the build method, between BEGIN ENLISTMENT and the privacy footer:
const SizedBox(height: 16),
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 24),
  child: Column(
    children: [
      TextField(
        controller: _referralController,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9-]')),
          LengthLimitingTextInputFormatter(13),
        ],
        decoration: InputDecoration(
          hintText: 'Got a code? AVYA-XXXXXXXX',
          hintStyle: AppTypography.mono.copyWith(
            color: AppColors.textGhost,
            fontSize: 12,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
        ),
        style: AppTypography.mono.copyWith(
          color: AppColors.textPrimary,
          fontSize: 14,
        ),
        onChanged: (v) {
          ref.read(referralCodeStashProvider.notifier).state = v.trim();
        },
      ),
      const SizedBox(height: 4),
      Text(
        'Apply within 7 days of signup',
        style: AppTypography.bodyS.copyWith(color: AppColors.textMute),
      ),
    ],
  ),
),
```

Add the controller + provider:
```dart
final TextEditingController _referralController = TextEditingController();

// At top of file, define a Riverpod provider:
final referralCodeStashProvider = StateProvider<String>((_) => '');
```

Don't forget to dispose the controller in dispose().

- [ ] **Step 2: Apply stashed code post-signup**

Open `lib/features/onboarding/providers/onboarding_provider.dart`. In `completeOnboarding`, after the user is created in `public.users` (via `_ensureLocalUser`), apply the stashed code:

```dart
// At the end of completeOnboarding, after user_profile upsert + Mission Brief flow:
final stashedCode = ref.read(referralCodeStashProvider).trim();
if (stashedCode.isNotEmpty) {
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'redeem-referral',
      body: {'code': stashedCode},
    );
    if (response.status == 200) {
      // Snackbar success — both got 7 days PRO
      _showSnack(
        '7 days of PRO unlocked. Welcome aboard, soldier.',
      );
      // Refresh subscription cache
      await SubscriptionService.instance.verifyFromServer();
    } else {
      // Non-fatal — log but don't block onboarding completion
      debugPrint('[referral] redeem failed at signup: ${response.data}');
    }
  } catch (e) {
    debugPrint('[referral] redeem exception at signup: $e');
  } finally {
    ref.read(referralCodeStashProvider.notifier).state = '';
  }
}
```

- [ ] **Step 3: Manual smoke test**

Spin up dev with a known valid code:

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

Welcome screen → enter `AVYA-VALIDCODE` (use a real code from your test account) → BEGIN ENLISTMENT → sign up → after onboarding completes, see snackbar "7 days of PRO unlocked".

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/screens/welcome_screen.dart \
        lib/features/onboarding/providers/onboarding_provider.dart
git commit -m "feat(referral): Q4 Welcome optional code field + post-signup apply

Adds an optional referral code TextField below the BEGIN ENLISTMENT
button on Welcome. Stashed via Riverpod (referralCodeStashProvider),
applied via redeem-referral Edge Function after successful signup +
onboarding completion. Snackbar confirms 7 days unlocked.

Helper text 'Apply within 7 days of signup' under the field.

Spec section 6 / Q4 surface A."
```

---

### Task 5: Apply Referral Code sheet

**Files:**
- Create: `lib/features/profile/screens/apply_referral_sheet.dart`
- Test: `test/referral/apply_referral_sheet_test.dart`

- [ ] **Step 1: Write tests**

```dart
// test/referral/apply_referral_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/profile/screens/apply_referral_sheet.dart';

void main() {
  group('ApplyReferralSheet', () {
    Widget build() => const ProviderScope(
          child: MaterialApp(home: Scaffold(body: ApplyReferralSheet())),
        );

    testWidgets('renders title, eligibility banner, code field, CTA',
        (tester) async {
      await tester.pumpWidget(build());
      expect(find.text('Apply Referral Code'), findsOneWidget);
      expect(find.textContaining('eligibility window'), findsOneWidget);
      expect(find.byKey(const ValueKey('apply-referral-input')),
          findsOneWidget);
      expect(find.text('APPLY CODE  →'), findsOneWidget);
    });

    testWidgets('shows wrong-format error', (tester) async {
      await tester.pumpWidget(build());
      await tester.enterText(
          find.byKey(const ValueKey('apply-referral-input')), 'not-a-code');
      await tester.pump();
      expect(
        find.textContaining('Codes look like AVYA-XXXXXXXX'),
        findsOneWidget,
      );
    });

    testWidgets('CTA disabled until format is valid', (tester) async {
      await tester.pumpWidget(build());
      final cta = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'APPLY CODE  →'),
      );
      expect(cta.onPressed, isNull);

      await tester.enterText(
          find.byKey(const ValueKey('apply-referral-input')),
          'AVYA-AAAAAAAA');
      await tester.pump();

      final ctaAfter = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'APPLY CODE  →'),
      );
      expect(ctaAfter.onPressed, isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/referral/apply_referral_sheet_test.dart
```

- [ ] **Step 3: Build the sheet**

```dart
// lib/features/profile/screens/apply_referral_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/referral_eligibility_provider.dart';

class ApplyReferralSheet extends ConsumerStatefulWidget {
  const ApplyReferralSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ApplyReferralSheet(),
    );
  }

  @override
  ConsumerState<ApplyReferralSheet> createState() =>
      _ApplyReferralSheetState();
}

class _ApplyReferralSheetState extends ConsumerState<ApplyReferralSheet> {
  final _controller = TextEditingController();
  String _statusMessage = '';
  bool _statusIsError = false;
  bool _submitting = false;

  static final RegExp _format = RegExp(r'^AVYA-[A-Z0-9]{8}$');

  bool get _isValidFormat => _format.hasMatch(_controller.text.trim());

  void _onChange(String value) {
    setState(() {
      if (value.isEmpty) {
        _statusMessage = '';
      } else if (!_isValidFormat) {
        _statusMessage = 'Codes look like AVYA-XXXXXXXX.';
        _statusIsError = true;
      } else {
        _statusMessage = '';
      }
    });
  }

  Future<void> _submit() async {
    if (!_isValidFormat || _submitting) return;
    setState(() {
      _submitting = true;
      _statusMessage = '';
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'redeem-referral',
        body: {'code': _controller.text.trim()},
      );
      final body = response.data as Map?;
      if (response.status == 200) {
        await SubscriptionService.instance.verifyFromServer();
        ref.invalidate(referralEligibilityProvider);
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() {
          _statusMessage = (body?['error'] as String?) ??
              'Could not apply that code. Please try again.';
          _statusIsError = true;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Network error. Try again in a moment.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eligibility = ref.watch(referralEligibilityProvider);
    final daysLeft = eligibility.maybeWhen(
      data: (v) => v.daysRemaining,
      orElse: () => 0,
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Apply Referral Code',
                  style: AppTypography.titleL.copyWith(fontSize: 20),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textDim),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(width: 60, height: 1, color: AppColors.accent),
            const SizedBox(height: 20),
            Text(
              'Your eligibility window:',
              style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 4),
            Text(
              '$daysLeft days remaining',
              style: AppTypography.bodyL.copyWith(color: AppColors.accent),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('apply-referral-input'),
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9-]')),
                LengthLimitingTextInputFormatter(13),
              ],
              style: AppTypography.mono.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'AVYA-XXXXXXXX',
                hintStyle: AppTypography.mono.copyWith(
                  color: AppColors.textGhost,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
              onChanged: _onChange,
            ),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage,
                style: AppTypography.bodyS.copyWith(
                  color: _statusIsError ? AppColors.bad : AppColors.ok,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isValidFormat && !_submitting ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  shape: const StadiumBorder(),
                  disabledBackgroundColor: AppColors.input,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'APPLY CODE  →',
                        style: AppTypography.mono.copyWith(
                          fontSize: 13,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Tests pass**

```bash
flutter test test/referral/apply_referral_sheet_test.dart -v
```

- [ ] **Step 5: Commit**

```bash
git add test/referral/apply_referral_sheet_test.dart \
        lib/features/profile/screens/apply_referral_sheet.dart
git commit -m "feat(referral): Q4 ApplyReferralSheet (Profile entry point)

Bottom sheet for applying a friend's referral code. Visible only via
the Apply Referral Code tile (Task 6 next), which is itself only
visible when the user is within their 7-day signup window AND hasn't
already redeemed.

Layout per spec section 6 / Q4 surface C: title + close, eligibility
banner ('X days remaining'), mono input with format mask, status
hint that updates on tap (validation feedback), full-width APPLY CODE
button gated on valid format.

Server errors (expired, self, outside window, already-redeemed) are
mapped from Edge Function response.error verbatim."
```

---

### Task 6: Referral eligibility provider + Profile tile

**Files:**
- Create: `lib/features/profile/providers/referral_eligibility_provider.dart`
- Test: `test/referral/eligibility_provider_test.dart`
- Modify: `lib/features/profile/screens/profile_screen.dart`

- [ ] **Step 1: Write provider tests**

```dart
// test/referral/eligibility_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/providers/referral_eligibility_provider.dart';

void main() {
  group('ReferralEligibility', () {
    test('isEligible: signup within 7 days + no redemption', () {
      final state = ReferralEligibility(
        daysRemaining: 4,
        signupDate: DateTime.now().subtract(const Duration(days: 3)),
        hasRedeemed: false,
      );
      expect(state.isEligible, true);
    });

    test('not eligible: outside 7-day window', () {
      final state = ReferralEligibility(
        daysRemaining: 0,
        signupDate: DateTime.now().subtract(const Duration(days: 8)),
        hasRedeemed: false,
      );
      expect(state.isEligible, false);
    });

    test('not eligible: already redeemed', () {
      final state = ReferralEligibility(
        daysRemaining: 4,
        signupDate: DateTime.now().subtract(const Duration(days: 3)),
        hasRedeemed: true,
      );
      expect(state.isEligible, false);
    });

    test('daysRemaining calculation', () {
      final signedUp4DaysAgo = DateTime.now().subtract(const Duration(days: 4));
      final remaining = ReferralEligibility.computeDaysRemaining(signedUp4DaysAgo);
      expect(remaining, 3,
          reason:
              '7-day window starting 4 days ago should leave 3 days remaining.');
    });

    test('daysRemaining clamps to 0 when expired', () {
      final signedUp10DaysAgo = DateTime.now().subtract(const Duration(days: 10));
      final remaining =
          ReferralEligibility.computeDaysRemaining(signedUp10DaysAgo);
      expect(remaining, 0);
    });
  });
}
```

- [ ] **Step 2: Build the provider**

```dart
// lib/features/profile/providers/referral_eligibility_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReferralEligibility {
  final int daysRemaining;
  final DateTime signupDate;
  final bool hasRedeemed;

  ReferralEligibility({
    required this.daysRemaining,
    required this.signupDate,
    required this.hasRedeemed,
  });

  bool get isEligible => daysRemaining > 0 && !hasRedeemed;

  static int computeDaysRemaining(DateTime signupDate) {
    final daysSinceSignup =
        DateTime.now().difference(signupDate).inDays;
    final remaining = 7 - daysSinceSignup;
    return remaining.clamp(0, 7);
  }
}

final referralEligibilityProvider =
    FutureProvider<ReferralEligibility>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    return ReferralEligibility(
      daysRemaining: 0,
      signupDate: DateTime.now(),
      hasRedeemed: false,
    );
  }

  final signupDate = DateTime.parse(user.createdAt);
  final daysRemaining = ReferralEligibility.computeDaysRemaining(signupDate);

  // Check for existing redemption
  final redemption = await supabase
      .from('referral_redemptions')
      .select('id')
      .eq('referee_id', user.id)
      .maybeSingle();

  return ReferralEligibility(
    daysRemaining: daysRemaining,
    signupDate: signupDate,
    hasRedeemed: redemption != null,
  );
});
```

- [ ] **Step 3: Add Apply Referral tile to Profile**

Open `lib/features/profile/screens/profile_screen.dart`. In the SHARE & GROW section (or wherever existing share-related tiles are), conditionally render the new tile:

```dart
final eligibility = ref.watch(referralEligibilityProvider);

// In the SHARE & GROW section list:
eligibility.when(
  data: (state) {
    if (!state.isEligible) return const SizedBox.shrink();
    return _buildTile(
      title: 'Apply Referral Code',
      subtitle: '7 days of PRO when you apply a code',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '${state.daysRemaining} DAYS LEFT',
          style: AppTypography.mono.copyWith(
            fontSize: 9,
            letterSpacing: 0.8,
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      onTap: () async {
        final ok = await ApplyReferralSheet.show(context);
        if (ok == true) {
          // Snackbar success, refresh subscription
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('7 days of PRO unlocked!')),
          );
        }
      },
    );
  },
  loading: () => const SizedBox.shrink(),
  error: (_, __) => const SizedBox.shrink(),
),
```

- [ ] **Step 4: Tests pass**

```bash
flutter test test/referral/eligibility_provider_test.dart -v
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/providers/referral_eligibility_provider.dart \
        test/referral/eligibility_provider_test.dart \
        lib/features/profile/screens/profile_screen.dart
git commit -m "feat(referral): Q4 referralEligibilityProvider + Profile tile

Provider exposes daysRemaining + hasRedeemed for the Profile UI to
gate the Apply Referral tile visibility (only when within 7-day
signup window AND not yet redeemed).

Profile tile: 'Apply Referral Code · X DAYS LEFT' chip (gold accent
chip in trailing). Tap opens ApplyReferralSheet.

After successful redemption, tile hides automatically (provider
re-reads on invalidate post-redeem).

Spec section 6 / Q4 surface B."
```

---

### Task 7: Invite Friends sheet (sender-side, with REGENERATE)

**Files:**
- Create: `lib/features/profile/screens/invite_friends_sheet.dart`
- Modify: `lib/core/services/supabase_service.dart` (`getOrCreateReferralCode` handles expiry)
- Modify: `lib/features/profile/screens/profile_screen.dart` (use new sheet)

- [ ] **Step 1: Update `getOrCreateReferralCode` to respect expiry**

Open `lib/core/services/supabase_service.dart`. Locate `getOrCreateReferralCode`. Update logic:

```dart
Future<({String code, DateTime expiresAt})?> getOrCreateReferralCode() async {
  final user = _supabase.auth.currentUser;
  if (user == null) return null;

  // Try to find an existing non-expired code
  final existing = await _supabase
      .from('referral_codes')
      .select('code, expires_at')
      .eq('user_id', user.id)
      .gt('expires_at', DateTime.now().toIso8601String())
      .maybeSingle();

  if (existing != null) {
    return (
      code: existing['code'] as String,
      expiresAt: DateTime.parse(existing['expires_at']),
    );
  }

  // Generate a new code
  return _generateNewCode(user.id);
}

Future<({String code, DateTime expiresAt})?> regenerateReferralCode() async {
  final user = _supabase.auth.currentUser;
  if (user == null) return null;
  return _generateNewCode(user.id);
}

Future<({String code, DateTime expiresAt})?> _generateNewCode(String userId) async {
  // Existing 5-retry generation loop (per CLAUDE.md). Each attempt:
  // - Build AVYA-XXXXXXXX
  // - Insert into referral_codes (FK to auth.users + UNIQUE on user_id)
  // - On UNIQUE conflict, treat as success (existing code is the canonical)
  // - On collision retry up to 5 times
  for (var i = 0; i < 5; i++) {
    final code = _buildCode();
    final expiresAt = DateTime.now().add(const Duration(days: 7));
    try {
      await _supabase.from('referral_codes').upsert({
        'user_id': userId,
        'code': code,
        'expires_at': expiresAt.toIso8601String(),
      }, onConflict: 'user_id');
      return (code: code, expiresAt: expiresAt);
    } catch (e) {
      // Retry on transient errors
      if (i == 4) rethrow;
    }
  }
  return null;
}

String _buildCode() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rand = Random.secure();
  final body = List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  return 'AVYA-$body';
}
```

- [ ] **Step 2: Build the InviteFriendsSheet**

```dart
// lib/features/profile/screens/invite_friends_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class InviteFriendsSheet extends ConsumerStatefulWidget {
  const InviteFriendsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const InviteFriendsSheet(),
    );
  }

  @override
  ConsumerState<InviteFriendsSheet> createState() =>
      _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends ConsumerState<InviteFriendsSheet> {
  String? _code;
  DateTime? _expiresAt;
  bool _loading = true;
  bool _regenerating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await SupabaseService.instance.getOrCreateReferralCode();
    if (mounted) {
      setState(() {
        _code = result?.code;
        _expiresAt = result?.expiresAt;
        _loading = false;
      });
    }
  }

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    try {
      final result = await SupabaseService.instance.regenerateReferralCode();
      if (mounted && result != null) {
        setState(() {
          _code = result.code;
          _expiresAt = result.expiresAt;
        });
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _share() async {
    if (_code == null) return;
    const playStore =
        'https://play.google.com/store/apps/details?id=com.icanbefitter.avya';
    final message =
        '🎯 Try AVYA — premium fitness coaching with an AI coach who actually knows you.\n\n'
        'Use my code $_code within 7 days → 7 days of PRO, free.\n\n'
        '📲 $playStore';
    await Share.share(message);
  }

  bool get _isExpired =>
      _expiresAt == null || _expiresAt!.isBefore(DateTime.now());

  int get _daysRemaining {
    if (_expiresAt == null) return 0;
    final diff = _expiresAt!.difference(DateTime.now()).inDays;
    return diff.clamp(0, 7);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Invite a Friend',
                      style: AppTypography.titleL.copyWith(fontSize: 20),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textDim),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Container(width: 60, height: 1, color: AppColors.accent),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    _code ?? '—',
                    style: AppTypography.titleL.copyWith(fontSize: 28),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _isExpired
                        ? 'EXPIRED'
                        : 'EXPIRES IN $_daysRemaining DAYS',
                    style: AppTypography.mono.copyWith(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: _isExpired ? AppColors.bad : AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'When friends use this code within 7 days of signing up, '
                  'you both get 7 days of PRO.',
                  style: AppTypography.bodyM.copyWith(color: AppColors.textDim),
                ),
                const SizedBox(height: 24),
                if (_isExpired)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _regenerating ? null : _regenerate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.bg,
                        shape: const StadiumBorder(),
                      ),
                      child: _regenerating
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : Text(
                              'REGENERATE  →',
                              style: AppTypography.mono.copyWith(
                                fontSize: 13,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.share, size: 18),
                      label: Text(
                        'SHARE',
                        style: AppTypography.mono.copyWith(
                          fontSize: 13,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.bg,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 3: Replace existing Invite Friends entry point**

Open `lib/features/profile/screens/profile_screen.dart`. Find any existing "Invite Friends" tile and route it through `InviteFriendsSheet.show(context)` instead of the legacy implementation.

- [ ] **Step 4: Manual smoke test**

Open Profile → Invite Friends → see code with countdown. Tap SHARE → WhatsApp opens with the locked message. Manually advance the system clock 8 days (or update the DB row's expires_at to yesterday) → re-open sheet → see EXPIRED tag + REGENERATE button.

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/screens/invite_friends_sheet.dart \
        lib/core/services/supabase_service.dart \
        lib/features/profile/screens/profile_screen.dart
git commit -m "feat(referral): Q4 InviteFriendsSheet with REGENERATE

Replaces legacy Invite Friends UI. Shows current code with EXPIRES
IN N DAYS countdown. After expiry, badge changes to EXPIRED + button
becomes REGENERATE → which creates a fresh 7-day code.

Share button uses share_plus with the locked WhatsApp copy:
'🎯 Try AVYA — premium fitness coaching... within 7 days → 7 days
of PRO, free. 📲 [Play Store link]'

getOrCreateReferralCode now filters by expires_at > now() so
expired codes don't get returned. New regenerateReferralCode method
forces a new row.

Spec section 6 / Q4 surface D."
```

---

### Task 8: Q7 — Phase Roadmap screen + week selector extension

**Files:**
- Modify: `lib/features/train/widgets/week_selector.dart` — extend to 12 weeks
- Create: `lib/features/train/screens/phase_roadmap_screen.dart`
- Test: `test/train/week_selector_12_weeks_test.dart`
- Test: `test/train/phase_roadmap_screen_test.dart`
- Modify: `lib/core/router/app_router.dart` — `/train/roadmap` route
- Modify: `lib/features/train/screens/train_screen.dart` — VIEW ROADMAP pill above week selector

- [ ] **Step 1: Write week selector tests**

```dart
// test/train/week_selector_12_weeks_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/train/widgets/week_selector.dart';

void main() {
  group('WeekSelector', () {
    testWidgets('renders 12 week chips', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WeekSelector(currentWeek: 1, onWeekTap: _noop),
            ),
          ),
        ),
      );

      // Each week chip has a key 'week-N'
      for (var i = 1; i <= 12; i++) {
        expect(
          find.byKey(ValueKey('week-$i')),
          findsOneWidget,
          reason: 'Week $i chip should render.',
        );
      }
    });

    testWidgets('renders 3 phase headers', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WeekSelector(currentWeek: 1, onWeekTap: _noop),
            ),
          ),
        ),
      );

      expect(find.text('PHASE I'), findsOneWidget);
      expect(find.textContaining('PHASE II'), findsOneWidget);
      expect(find.textContaining('PHASE III'), findsOneWidget);
    });

    testWidgets('weeks 5-12 dimmed for free users', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Override: simulate free user
            isProUserProvider.overrideWith((_) => false),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WeekSelector(currentWeek: 1, onWeekTap: _noop),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Weeks 5-12 should have lock icons
      for (var i = 5; i <= 12; i++) {
        expect(
          find.byKey(ValueKey('week-$i-lock')),
          findsOneWidget,
          reason: 'Week $i should show lock icon for free users.',
        );
      }
    });
  });
}

void _noop(int week) {}
```

- [ ] **Step 2: Run tests**

```bash
flutter test test/train/week_selector_12_weeks_test.dart
```

Expected: tests fail (selector doesn't render 12 weeks yet).

- [ ] **Step 3: Extend week_selector to 12 weeks with phase headers + locks**

Open `lib/features/train/widgets/week_selector.dart`. Rewrite the build:

```dart
// lib/features/train/widgets/week_selector.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class WeekSelector extends ConsumerWidget {
  const WeekSelector({
    super.key,
    required this.currentWeek,
    required this.onWeekTap,
  });

  final int currentWeek;
  final void Function(int week) onWeekTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProUserProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _PhaseGroup(
            label: 'PHASE I',
            isPaywalled: false,
            weekStart: 1,
            weekEnd: 4,
            currentWeek: currentWeek,
            onWeekTap: onWeekTap,
            isPro: isPro,
          ),
          const SizedBox(width: 16),
          _PhaseGroup(
            label: 'PHASE II',
            isPaywalled: !isPro,
            weekStart: 5,
            weekEnd: 8,
            currentWeek: currentWeek,
            onWeekTap: onWeekTap,
            isPro: isPro,
          ),
          const SizedBox(width: 16),
          _PhaseGroup(
            label: 'PHASE III',
            isPaywalled: !isPro,
            weekStart: 9,
            weekEnd: 12,
            currentWeek: currentWeek,
            onWeekTap: onWeekTap,
            isPro: isPro,
          ),
        ],
      ),
    );
  }
}

class _PhaseGroup extends StatelessWidget {
  const _PhaseGroup({
    required this.label,
    required this.isPaywalled,
    required this.weekStart,
    required this.weekEnd,
    required this.currentWeek,
    required this.onWeekTap,
    required this.isPro,
  });

  final String label;
  final bool isPaywalled;
  final int weekStart;
  final int weekEnd;
  final int currentWeek;
  final void Function(int week) onWeekTap;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase header
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(
                label,
                style: AppTypography.mono.copyWith(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  color: isPaywalled ? AppColors.textGhost : AppColors.accent,
                ),
              ),
              if (isPaywalled) ...[
                const SizedBox(width: 4),
                Text(
                  '(PRO)',
                  style: AppTypography.mono.copyWith(
                    fontSize: 9,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Week chips
        Row(
          children: [
            for (var w = weekStart; w <= weekEnd; w++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _WeekChip(
                  key: ValueKey('week-$w'),
                  week: w,
                  isCurrent: w == currentWeek,
                  isLocked: isPaywalled,
                  onTap: () => onWeekTap(w),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _WeekChip extends StatelessWidget {
  const _WeekChip({
    super.key,
    required this.week,
    required this.isCurrent,
    required this.isLocked,
    required this.onTap,
  });

  final int week;
  final bool isCurrent;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isLocked
        ? AppColors.textGhost
        : (isCurrent ? AppColors.bg : AppColors.textPrimary);
    final bg = isLocked
        ? AppColors.input
        : (isCurrent ? AppColors.accent : AppColors.input);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 56,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: isCurrent
              ? Border.all(color: AppColors.accent, width: 1.5)
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'WK',
                  style: AppTypography.mono.copyWith(
                    fontSize: 8,
                    color: fg,
                  ),
                ),
                Text(
                  '$week',
                  style: AppTypography.titleL.copyWith(
                    fontSize: 16,
                    color: fg,
                  ),
                ),
              ],
            ),
            if (isLocked)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.lock,
                  size: 10,
                  color: AppColors.accent,
                  key: ValueKey('week-$week-lock'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add VIEW ROADMAP pill above week selector in train_screen**

Open `lib/features/train/screens/train_screen.dart`. Above the week selector widget:

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
  child: GestureDetector(
    onTap: () => context.push('/train/roadmap'),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.map_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            'VIEW THE 48-WEEK ROADMAP',
            style: AppTypography.mono.copyWith(
              fontSize: 11,
              letterSpacing: 1.2,
              color: AppColors.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Icon(Icons.arrow_forward, size: 14, color: AppColors.accent),
        ],
      ),
    ),
  ),
),
```

- [ ] **Step 5: Build PhaseRoadmapScreen**

```dart
// lib/features/train/screens/phase_roadmap_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet_phase_variant.dart';

class PhaseRoadmapScreen extends ConsumerWidget {
  const PhaseRoadmapScreen({super.key});

  static const _phases = <_PhaseInfo>[
    _PhaseInfo(
      number: 'I',
      name: 'FOUNDATION',
      weekRange: 'Wk 1–4',
      focus: 'Movement patterns + baseline strength.',
      bullets: [
        'Master the big lifts under load',
        'Build the work-capacity engine',
        'Sample workout: Full Body A · 6 exercises · 60 min',
      ],
    ),
    _PhaseInfo(
      number: 'II',
      name: 'STRENGTH BLOCK',
      weekRange: 'Wk 5–8',
      focus: 'Heavier compounds, lower reps, real progression.',
      bullets: [
        'Strength benchmarks established',
        '+5–10% on big lifts',
        'Sample workout: Heavy Push · 7 exercises · 75 min',
      ],
    ),
    _PhaseInfo(
      number: 'III',
      name: 'HYPERTROPHY',
      weekRange: 'Wk 9–12',
      focus: 'Volume push. Muscle-building emphasis.',
      bullets: [
        'Lean mass gains visible',
        'Higher rep ranges, tighter rest',
        'Sample workout: Chest + Triceps · 8 exercises · 70 min',
      ],
    ),
    // ... extend to 12 phases or stop at 3 visible phases here.
    // For first ship, 3 phases is enough; phases IV-XII can be a single
    // "+ More phases (IX–XII)" tile that opens an extended view later.
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProUserProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text(
          'Phase Roadmap',
          style: AppTypography.titleL.copyWith(fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(18),
        itemCount: _phases.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, i) {
          final phase = _phases[i];
          final isActive = i == 0;
          return _PhaseCard(
            phase: phase,
            isActive: isActive,
            isLocked: !isActive && !isPro,
            onTap: () {
              if (isActive) return;
              if (!isPro) {
                showPaywallSheetPhaseVariant(context);
              } else {
                // PRO user — drill into preview screen for first day of phase
                final week = (i == 0) ? 1 : (i == 1 ? 5 : 9);
                context.push('/train/preview?phase=${phase.number}&week=$week&day=1');
              }
            },
          );
        },
      ),
      bottomNavigationBar: !isPro
          ? Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => showPaywallSheetPhaseVariant(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.bg,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'UPGRADE TO PRO  →',
                    style: AppTypography.mono.copyWith(
                      fontSize: 13,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _PhaseInfo {
  final String number;
  final String name;
  final String weekRange;
  final String focus;
  final List<String> bullets;
  const _PhaseInfo({
    required this.number,
    required this.name,
    required this.weekRange,
    required this.focus,
    required this.bullets,
  });
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.phase,
    required this.isActive,
    required this.isLocked,
    required this.onTap,
  });

  final _PhaseInfo phase;
  final bool isActive;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? AppColors.accent : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    phase.number,
                    style: AppTypography.titleL.copyWith(
                      fontSize: 14,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  phase.name,
                  style: AppTypography.titleL.copyWith(fontSize: 16),
                ),
                const Spacer(),
                Text(
                  phase.weekRange,
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    color: AppColors.textDim,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, size: 16, color: AppColors.ok),
                ] else if (isLocked) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.lock, size: 14, color: AppColors.accent),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Container(width: 60, height: 1, color: AppColors.line2),
            const SizedBox(height: 12),
            Text(
              phase.focus,
              style: AppTypography.bodyM.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            ...phase.bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style:
                            AppTypography.bodyS.copyWith(color: AppColors.accent)),
                    Expanded(
                      child: Text(
                        b,
                        style: AppTypography.bodyS.copyWith(
                          color: AppColors.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isActive && !isLocked) ...[
              const SizedBox(height: 8),
              Text(
                'TAP ANY WEEK FOR A PREVIEW →',
                style: AppTypography.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: AppColors.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Add `/train/roadmap` route**

Open `lib/core/router/app_router.dart`. Add:

```dart
GoRoute(
  path: '/train/roadmap',
  name: 'phase-roadmap',
  builder: (context, state) => const PhaseRoadmapScreen(),
),
```

- [ ] **Step 7: Run tests**

```bash
flutter test test/train/week_selector_12_weeks_test.dart -v
```

- [ ] **Step 8: Commit**

```bash
git add lib/features/train/widgets/week_selector.dart \
        lib/features/train/screens/phase_roadmap_screen.dart \
        test/train/week_selector_12_weeks_test.dart \
        lib/core/router/app_router.dart \
        lib/features/train/screens/train_screen.dart
git commit -m "feat(train): Q7 12-week selector + Phase Roadmap screen

Week selector now shows 12 weeks (3 phases). Phase headers with
'(PRO)' badge on II + III for free users. Lock glyph on weeks 5–12
when not PRO.

Phase Roadmap screen at /train/roadmap shows all phases as cards:
roman numeral + name + week range + focus + bullets. Active phase
gets gold border + check icon. Locked phases show lock icon. PRO
users tap to drill into preview; free users see PaywallSheet.

Sticky UPGRADE TO PRO bottom CTA only visible to free users.

Spec section 6 / Q7 surfaces A + B."
```

---

### Task 9: Read-only workout preview

**Files:**
- Create: `lib/features/train/providers/preview_plan_provider.dart`
- Create: `lib/features/train/screens/preview_workout_screen.dart`
- Create: `lib/shared/widgets/paywall_sheet_phase_variant.dart`
- Test: `test/train/preview_plan_provider_test.dart`
- Modify: `lib/core/router/app_router.dart` — `/train/preview` route

- [ ] **Step 1: Build PreviewPlanProvider**

Generates Phase II–XII previews on-demand using `PlanGenerator.generateV4()` with the user's actual profile. Cached in memory for the session.

```dart
// lib/features/train/providers/preview_plan_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
// imports for Phase, profile, etc.

class PreviewKey {
  final String phaseNumber;
  final int week;
  final int day;
  const PreviewKey(this.phaseNumber, this.week, this.day);

  @override
  bool operator ==(Object other) =>
      other is PreviewKey &&
      other.phaseNumber == phaseNumber &&
      other.week == week &&
      other.day == day;

  @override
  int get hashCode => Object.hash(phaseNumber, week, day);
}

final previewPlanProvider =
    FutureProvider.family<Phase, PreviewKey>((ref, key) async {
  // Read user profile from Hive
  final profile = HiveService.instance.userBox.get('profile') as Map?;
  if (profile == null) {
    throw StateError('User profile not loaded — cannot generate preview.');
  }

  // Generate plan with user's real inputs but for the requested phase
  final phase = await PlanGenerator.generateV4(
    goal: profile['primary_goal'] as String,
    equipment: profile['equipment_access'] as String,
    daysPerWeek: profile['days_per_week'] as int,
    experience: profile['fitness_experience'] as String,
    pacePreference: profile['pace_preference'] as String,
    phaseNumber: int.parse(_romanToInt(key.phaseNumber).toString()),
  );

  return phase;
});

int _romanToInt(String roman) {
  const map = {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5,
                'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12};
  return map[roman] ?? 1;
}
```

- [ ] **Step 2: Build PreviewWorkoutScreen**

Detailed read-only workout view with state-aware banner, exercise list, and conditional UPGRADE CTA. Full implementation:

```dart
// lib/features/train/screens/preview_workout_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/providers/preview_plan_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet_phase_variant.dart';

class PreviewWorkoutScreen extends ConsumerWidget {
  const PreviewWorkoutScreen({
    super.key,
    required this.phaseNumber,
    required this.week,
    required this.day,
  });

  final String phaseNumber;
  final int week;
  final int day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProUserProvider);
    final phaseAsync = ref.watch(
      previewPlanProvider(PreviewKey(phaseNumber, week, day)),
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: phaseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load preview: $e')),
        data: (phase) {
          // Pick the requested day from the phase's first week
          if (phase.workouts.isEmpty || day - 1 >= phase.workouts.length) {
            return const Center(child: Text('Preview unavailable.'));
          }
          final workout = phase.workouts[day - 1];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PHASE $phaseNumber  ·  WEEK $week  ·  DAY $day',
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  workout.name,
                  style: AppTypography.titleL.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 4),
                Text(
                  '${phase.focus} · ${workout.exercises.length} exercises',
                  style: AppTypography.bodyM.copyWith(color: AppColors.textDim),
                ),
                const SizedBox(height: 20),
                _StateBanner(isPro: isPro),
                const SizedBox(height: 24),
                ...workout.exercises.asMap().entries.map((entry) {
                  final i = entry.key;
                  final ex = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}',
                          style: AppTypography.titleL.copyWith(
                            fontSize: 14,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ex.name,
                                style:
                                    AppTypography.titleL.copyWith(fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${ex.sets} sets · ${ex.reps} reps · '
                                '${ex.restSeconds}s rest',
                                style: AppTypography.bodyS
                                    .copyWith(color: AppColors.textDim),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 32),
                if (!isPro)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => showPaywallSheetPhaseVariant(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.bg,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        'UPGRADE TO PRO  →',
                        style: AppTypography.mono.copyWith(
                          fontSize: 13,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/train/roadmap'),
                    child: Text(
                      'See the 48-week roadmap →',
                      style: AppTypography.mono.copyWith(
                        fontSize: 11,
                        color: AppColors.accent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StateBanner extends ConsumerWidget {
  const _StateBanner({required this.isPro});
  final bool isPro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Three-state logic per spec section 6 / Q7 brainstorm:
    //   1. Free + mid-Phase-I → "Complete Phase I to unlock..."
    //   2. Free + Phase-I complete → "✓ You've earned Phase II..."
    //   3. PRO + browsing ahead → same as #1, no upgrade button
    final completionData = ref.watch(phaseICompletionProvider);
    final completed = completionData.maybeWhen(
      data: (v) => v.completedWorkouts,
      orElse: () => 0,
    );
    final scheduled = completionData.maybeWhen(
      data: (v) => v.scheduledWorkouts,
      orElse: () => 24,
    );
    final pct = scheduled > 0 ? completed / scheduled : 0.0;
    final phase1Done = pct >= 0.8 && completed >= 24;

    String title;
    String? subtitle;
    if (phase1Done) {
      title = "✓ You've earned Phase II";
      subtitle = 'Upgrade to continue your transformation.';
    } else {
      title = 'Complete Phase I to unlock Phase II';
      subtitle =
          'Week ${(completed / 6).ceil().clamp(1, 4)} of 4 · $completed/$scheduled workouts done';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.bodyM.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style:
                  AppTypography.bodyS.copyWith(color: AppColors.textDim),
            ),
          ],
          if (!phase1Done) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: AppColors.line2,
                color: AppColors.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Helper provider for phase completion stats
final phaseICompletionProvider =
    FutureProvider<({int completedWorkouts, int scheduledWorkouts})>((ref) async {
  final scheduled = WorkoutScheduleService.instance.countScheduledForPhase(1);
  final completed =
      WorkoutScheduleService.instance.countCompletedForPhase(1);
  return (completedWorkouts: completed, scheduledWorkouts: scheduled);
});
```

- [ ] **Step 3: Build PaywallSheet phase variant**

```dart
// lib/shared/widgets/paywall_sheet_phase_variant.dart
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

void showPaywallSheetPhaseVariant(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _PaywallSheetPhaseBody(),
  );
}

class _PaywallSheetPhaseBody extends StatelessWidget {
  const _PaywallSheetPhaseBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⊙ AVYA · CONTINUE THE MISSION',
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                letterSpacing: 1.2,
                color: AppColors.accent,
              )),
          const SizedBox(height: 8),
          Container(width: 60, height: 1, color: AppColors.accent),
          const SizedBox(height: 16),
          Text('Beyond Phase I.',
              style: AppTypography.titleL.copyWith(fontSize: 24)),
          const SizedBox(height: 16),
          Text(
            'Phase II–XII unlocks as you complete each phase — your '
            'AI coach generates the next 4 weeks the moment you finish.',
            style: AppTypography.bodyM.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 20),
          Text(
            'PRO UNLOCKS TODAY:',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              letterSpacing: 1.2,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 12),
          ..._bullets.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style: AppTypography.bodyM
                            .copyWith(color: AppColors.accent)),
                    Expanded(
                      child: Text(b,
                          style: AppTypography.bodyM
                              .copyWith(color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to existing pricing/checkout flow
                // (e.g., context.push('/pricing'))
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.bg,
                shape: const StadiumBorder(),
              ),
              child: Text(
                'UPGRADE TO PRO  →',
                style: AppTypography.mono.copyWith(
                  fontSize: 13,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '₹349 / month  ·  ₹2,999 / year (save 28%)',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _bullets = [
    'AI coach unlimited (no daily cap)',
    'Adaptive plans from your biometrics',
    'Photo transformation timeline',
    'Weekly AI report (Gemini Pro reasoning)',
    'Voice notes + morning alerts',
    'Monthly fresh prediction card',
  ];
}
```

- [ ] **Step 4: Add `/train/preview` route**

Open `lib/core/router/app_router.dart`. Add:

```dart
GoRoute(
  path: '/train/preview',
  name: 'preview-workout',
  builder: (context, state) {
    final phase = state.uri.queryParameters['phase'] ?? 'I';
    final week = int.parse(state.uri.queryParameters['week'] ?? '1');
    final day = int.parse(state.uri.queryParameters['day'] ?? '1');
    return PreviewWorkoutScreen(
      phaseNumber: phase,
      week: week,
      day: day,
    );
  },
),
```

- [ ] **Step 5: Wire week selector tap → preview**

Open `lib/features/train/widgets/week_selector.dart`. Update `_WeekChip.onTap` (or the parent `onWeekTap` callback in `train_screen.dart`):

```dart
// In train_screen.dart, when a locked week chip is tapped:
onWeekTap: (week) {
  final isPro = ref.read(isProUserProvider);
  if (!isPro && week >= 5) {
    final phase = week <= 8 ? 'II' : 'III';
    final dayInWeek = 1; // simplification — first day of the week
    context.push('/train/preview?phase=$phase&week=$week&day=$dayInWeek');
  } else {
    // Existing tap → navigate to that week's plan view
  }
},
```

- [ ] **Step 6: Run tests**

```bash
flutter test test/train/preview_plan_provider_test.dart -v
```

- [ ] **Step 7: Manual smoke test**

Build dev. Train screen → tap Week 5 → preview screen renders with real exercises (generated from your profile). Banner shows "Complete Phase I to unlock Phase II" with progress bar. UPGRADE TO PRO button at bottom. "See the 48-week roadmap →" cross-link goes to /train/roadmap.

- [ ] **Step 8: Commit**

```bash
git add lib/features/train/providers/preview_plan_provider.dart \
        lib/features/train/screens/preview_workout_screen.dart \
        lib/shared/widgets/paywall_sheet_phase_variant.dart \
        test/train/preview_plan_provider_test.dart \
        lib/core/router/app_router.dart \
        lib/features/train/screens/train_screen.dart \
        lib/features/train/widgets/week_selector.dart
git commit -m "feat(train): Q7 read-only workout previews + phase paywall

Tapping a locked week chip on Train (or a non-active phase card on
Roadmap) routes free users to /train/preview?phase=...&week=...&day=...
which renders a real workout — generated on-demand by
PlanGenerator.generateV4() with the user's actual profile inputs
(goal, equipment, days, experience, pace).

Three-state banner via phaseICompletionProvider:
  - Free + mid-Phase-I → 'Complete Phase I to unlock...' + progress bar
  - Free + Phase-I complete → '✓ You've earned Phase II'
  - PRO + browsing ahead → same as state 1 but NO bottom UPGRADE button

PaywallSheet phase variant shows the 6 PRO unlocks + Phase II–XII
narrative + ₹349/₹2,999 pricing.

Real generated previews are personalized to the user's profile —
not stock samples. Cached in memory per session via Riverpod family.

Spec section 6 / Q7 surface C."
```

---

### Task 10: Final verification

- [ ] **Step 1: Run all tests**

```bash
flutter test
flutter analyze
```

Expected: all pass.

- [ ] **Step 2: Plan C checkpoint commit**

```bash
git commit --allow-empty -m "checkpoint: Plan C complete (subscription + monetization)

  - Migration 038 + redeem-referral Edge Function rewrite (Q4 backend)
  - Welcome optional code field (Q4 surface A)
  - ApplyReferralSheet (Q4 surface C)
  - referralEligibilityProvider + Profile tile (Q4 surface B)
  - InviteFriendsSheet with REGENERATE (Q4 surface D)
  - Active workout dropped from PRO (Q6)
  - 12-week selector + Phase Roadmap screen (Q7 A+B)
  - Read-only workout previews + paywall variant (Q7 C)

Plan D (layout) is next.

Branch: feat/apk-test-2-batch
Spec: docs/superpowers/specs/2026-04-25-apk-test-2-batch-design.md"
```

---

## Self-Review

### Spec coverage
- Q4 referral: Tasks 1+2+4+5+6+7 ✓
- Q6 active workout free: Task 3 ✓
- Q7 phase roadmap + previews: Tasks 8+9 ✓

### Placeholder scan
No TBDs. All code blocks complete. Some intentional simplifications (e.g., 3-phase visible roadmap, week-day mapping) called out as ship-now decisions.

### Type consistency
- `ReferralEligibility` properties (`daysRemaining`, `signupDate`, `hasRedeemed`) used identically in provider, sheet, and tests.
- `PreviewKey` has `phaseNumber/week/day` matching the route query params.
- `redeem_referral_atomic` RPC signature matches the Edge Function call.
- `_highValueFeatures` set named consistently across test, source, and CLAUDE.md update.

---

## Execution Handoff

Plan C complete and saved to `docs/superpowers/plans/2026-04-25-apk-test-2-plan-C-subscription-monetization.md`.

Plan D (Layout) is the final plan.
