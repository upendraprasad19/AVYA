# Plan — Unit 2: Community Review fix (cross-user read blocked by own-only RLS)

> Founder-directed split (2026-06-13): Unit 1 (Referral P0) shipped. This is Unit 2.
> Per CLAUDE.md §4.12: this plan is independently reviewed TWICE (context-blind) before any code.
> Blast-radius = **account** (new Edge Function + RLS migration + cross-user data path) → self-initiated
> B-pass before the `--no-ff` merge.

## Symptom
The Profile → Submissions → **COMMUNITY REVIEW** tab always shows "No items to review right now",
for every user, even when other users have submitted unapproved custom foods/exercises. The
community-review → auto-promotion (`promote-community-item`, ≥10 approve votes → global library)
pipeline is therefore inert: nobody can ever vote.

## Root cause (live-verified)
The COMMUNITY REVIEW tab needs to read **other users'** pending submissions. The two readers query
`user_custom_foods` / `user_custom_exercises` directly from the client with `.neq('user_id', me)`:

- `lib/shared/repositories/submissions_repository.dart:53-64` `fetchPendingFoodReviews`
- `lib/shared/repositories/submissions_repository.dart:70-80` `fetchPendingExerciseReviews`
  (called by `lib/features/profile/screens/submissions_screen.dart:328-329` `_CommunityReviewBody._load`)

But both tables enforce **own-only** SELECT RLS — live `pg_policies`:
- `user_custom_foods_select_own` → `USING (auth.uid() = user_id)`
- `user_custom_exercises_select_own` → `USING (auth.uid() = user_id)`

So the cross-user read returns **0 rows** under the caller's `authenticated` context → empty queue.
You cannot simply relax these to world-read: that would expose every user's *entire* custom-food/
exercise catalog (incl. un-submitted private rows), a far larger privacy hole. The correct fix is a
**scoped service-role Edge Function** that returns ONLY submitted-not-approved rows from OTHER users,
column-projected and submitter-anonymized.

This is the same *class* as d2b9e6 (referral, Unit 1): a feature needs a cross-user read that own-only
RLS blocks. d2b9e6's mechanism was JWT-in-`global.headers` inside an existing EF; here there is no EF
at all — the client reads direct. Shared lesson: **cross-user read need + own-only RLS → scoped
service-role EF, never relax the table RLS.**

## Secondary finding (same feature, in-scope per no-deferrals)
`community_reviews` SELECT is **world-read** (`"Users can read all reviews"` qual=`true`). This
de-anonymizes the vote graph (any authenticated user can read every `(reviewer_id, item_id, vote)`
row → who-reviewed-what). The only authenticated readers filter to their own rows:
- `submissions_repository.dart:86-95` `fetchAlreadyReviewedKeys` → `.eq('reviewer_id', me)`
- (the dead `community_review_sheet.dart:63-66` → same `.eq('reviewer_id', me)`)

There are **two** vote-tally consumers, BOTH BYPASSRLS (verified live), so neither breaks under the tighten:
- **Real-time:** AFTER-INSERT trigger `trg_auto_approve_community` → `auto_approve_community_item()` —
  confirmed `prosecdef=true` (SECURITY DEFINER, `SET search_path='public'`). Its `SELECT count(*) FROM
  community_reviews WHERE item_type=… AND item_id=… AND vote='approve'` runs as the function owner → RLS
  does not apply. (≥10 approve → flips `approved`/`approved_for_library`.)
- **Batch + push:** `promote-community-item` cron via a service-role client (`index.ts:94`).

So tightening SELECT to own-only (`auth.uid() = reviewer_id`) **breaks no reader**. INSERT
(`with_check auth.uid()=reviewer_id`) + UPDATE (own-only) policies are left untouched → voting keeps
working. **Deleted-user consequence:** migration 049 sets `community_reviews.reviewer_id = NULL` on
account delete; post-tighten those rows match no `auth.uid()` → invisible on the authenticated path
(but still counted by both BYPASSRLS tallies). Live `null_reviewer_rows = 0` today → latent, not active;
documented in the diagnose-doc tier-8.

## Dead code (remove, latent reintroduction trap)
`lib/shared/widgets/community_review_sheet.dart` (class `CommunityReviewSheet`) is a standalone bottom
sheet that (a) is **never instantiated** anywhere (0 hits in `lib/` outside its own file, 0 in `test/`),
(b) violates CLAUDE.md rule #4 (widget calls Supabase directly), and (c) contains the *same* RLS-broken
cross-user query + the world-read `community_reviews` assumption. A future wire-up would reintroduce the
bug. **Delete it.** (Pre-deletion: re-grep for any `import '.../community_review_sheet.dart'` — expected 0.)

## The fix

### 1. New Edge Function `supabase/functions/get-community-review-items/index.ts` (verify_jwt = true)
Mirror the Unit 1 / e8a1c3 auth contract (CLAUDE.md rule #9, gate `check_edge_function_auth_pattern.dart`):
build ONE service-role client (NO `global.headers` → BYPASSRLS) and authenticate the caller with
`getUser(token)` on it.

```ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientError, corsHeaders, ok, serverError } from "../_shared/error.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PAGE_LIMIT = 20;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return clientError("Method not allowed", 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return clientError("Missing authorization header", 401);
  const token = authHeader.slice("Bearer ".length);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY); // no global headers → BYPASSRLS
  const { data: { user }, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !user) return clientError("Unauthorized", 401);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_) { /* empty body tolerated */ }
  const kind = body?.kind;
  if (kind !== "food" && kind !== "exercise") {
    return clientError("kind must be 'food' or 'exercise'", 400);
  }

  try {
    if (kind === "food") {
      const { data, error } = await admin
        .from("user_custom_foods")
        .select("id, name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g")
        .eq("submitted_to_db", true)
        .eq("approved", false)
        .neq("user_id", user.id)        // filter on a non-projected column (PostgREST allows this)
        .limit(PAGE_LIMIT);
      if (error) throw error;
      return ok({ items: data ?? [] });
    }
    const { data, error } = await admin
      .from("user_custom_exercises")
      .select("id, name, category, logging_type")
      .eq("submitted_to_library", true)
      .eq("approved_for_library", false)
      .neq("user_id", user.id)
      .limit(PAGE_LIMIT);
    if (error) throw error;
    return ok({ items: data ?? [] });
  } catch (err) {
    return serverError("get-community-review-items", err);
  }
});
```

- **Anonymized:** `user_id` is NOT in either `select(...)` (the UI at `submissions_screen.dart:436-475`
  renders only `name` + `kind` + macros/category — never the submitter). The `.neq('user_id', …)`
  filters on the row, independent of projection.
- Deploy host-shell (CLAUDE.md §0): `node .claude/emit_payload.js get-community-review-items --auto
  --functions-dir <repo>/supabase/functions` → `node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl
  get-community-review-items .claude/_payload_get-community-review-items.json true` (trailing `true` =
  verify_jwt; matches `deploy_via_api.js` positional `<project> <fn> <payload> [verify_jwt]`).
- Add `get-community-review-items: [401]` to `SMOKE_TOLERATED_CODES` in `.claude/deploy_via_api.js` so the
  post-deploy unauthenticated smoke (which a verify_jwt EF answers 401) reads OK instead of a WARN.

### 2. Client routing (`submissions_repository.dart`, same commit as deploy)
Replace the two direct `.from(...)` cross-user queries with `callFunction` (fresh-token route, gate
`check_authed_invoke_fresh_token.dart`). **`callFunction` returns `Future<FunctionResponse>`** (verified:
`supabase_service.dart:231`, a `retryColdStart` over `client.functions.invoke`) — extract via
`response.data`, NOT `response[...]`; the Unit-1 caller `referral_repository.dart:94` is the reference:

```dart
Future<List<Map<String, dynamic>>> fetchPendingFoodReviews(String currentUserId) async {
  final response = await SupabaseService.instance
      .callFunction('get-community-review-items', body: {'kind': 'food'});
  final body = response.data as Map?;                  // FunctionResponse.data (decoded JSON), not response[...]
  final items = (body?['items'] as List?) ?? const [];
  return List<Map<String, dynamic>>.from(items);
}
// fetchPendingExerciseReviews identical with body {'kind': 'exercise'}
```
`currentUserId` param retained for signature stability (the caller identity is now derived server-side
from the JWT — authoritative; the client-supplied id is ignored). `_load` + `fetchAlreadyReviewedKeys` +
`castCommunityVote` are **unchanged** (own-row reads/writes still pass RLS).

**Error-path behavior delta + telemetry fix (R2 / review #2 P1):** today the RLS-blocked direct query
returns `[]` (silent empty). `callFunction` THROWS `FunctionException` on non-2xx (stale-token 401, 500;
502/503/504 retry first). The two repo methods deliberately carry **no internal try/catch** — they
propagate to `_CommunityReviewBody._load`'s `catch` (`submissions_screen.dart:355`). BUT that catch is
currently `catch (_)` and sets `_error` WITHOUT `ErrorTelemetry.recordNonFatal` — and the screen does not
import `ErrorTelemetry` at all (verified). Routing a real EF failure through it would be a **server-silent
drop** (`feedback_observability_silent_drop.md` class), violating the `lib/core/services/CLAUDE.md`
catch-block contract (the very pattern `referral_repository.redeem` follows). **Fix in the same commit:**
add `import 'dart:async';` + `import '../../../core/services/error_telemetry.dart';` to
`submissions_screen.dart` and upgrade BOTH `_load` catches —
`_CommunityReviewBody._load` (line ~355) AND the symmetric pre-existing `_MySubmissionsBody._load`
(line 187, in-scope per no-deferrals while in the file) — to
`catch (e, st) { unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: '<submissions_community_review_load | submissions_my_load>')); setState(() => _error = …); }`.
Net UX: a retry error-state card instead of a silent empty queue (strictly better); net observability: the
failure now reaches `client_errors`.

### 3. Migration `092_community_reviews_select_own_only.sql`
```sql
DROP POLICY IF EXISTS "Users can read all reviews" ON public.community_reviews;
CREATE POLICY "Users can read own reviews"
  ON public.community_reviews FOR SELECT
  USING (auth.uid() = reviewer_id);
```
Pair with `backups/applied_migrations.json` (+ `backups/live_schema_columns.json` is unaffected — no
column change). INSERT/UPDATE policies untouched.

### 4. Delete `lib/shared/widgets/community_review_sheet.dart` (dead).

## Discipline artifacts (per §4.5 / rules 21-22)
- **Diagnose-doc** `docs/diagnoses/2026-06-13-community-review-rls-context-<id>.md`, `blast_radius: account`,
  `related_bugs: [d2b9e6]`, `touched_layers_checked` covering: client code, EF code-vs-deploy (tier 6),
  RLS policies (tier 8 — MUST name BOTH BYPASSRLS tally readers `trg_auto_approve_community`/SECURITY
  DEFINER + `promote-community-item`/service-role, AND the deleted-user NULL-reviewer invisibility
  consequence), Postgres data (tier 4 — live pending: 0 foods / 4 exercises / 2 submitters / 0 null
  reviewers), client→server contract (tier 12 — note `sync_community.dart` is the verified-unaffected
  own-row consumer of the same two tables: it upserts/restores the caller's OWN rows under own-only RLS,
  never cross-user, never reads `community_reviews`).
- **Pre-flight (review #2 P2):** spot-check `backups/live_schema_columns.json` already lists the EF's
  referenced columns (`user_custom_foods`: name/calories_per_100g/protein_per_100g/carbs_per_100g/
  fat_per_100g/submitted_to_db/approved/user_id; `user_custom_exercises`: name/category/logging_type/
  submitted_to_library/approved_for_library/user_id) — no migration adds columns, so the snapshot needs
  no regen, but `check_schema_column_refs.dart` will scan the new EF against it.
- **Behavioral contract test** `test/contracts/community_review_rls_context_<id>_test.dart` (comment-stripped
  source-grep): EF uses pure service-role client (no `global.headers` Authorization) + `getUser(token)` +
  selects WITHOUT `user_id` (anonymize) on BOTH tables; repository routes the two readers through
  `callFunction('get-community-review-items')` and NO longer does a direct `.from('user_custom_foods')` /
  `.from('user_custom_exercises')` cross-user read; migration 092 tightens `community_reviews` SELECT to
  `auth.uid() = reviewer_id`; `community_review_sheet.dart` is deleted (File-not-exists pin); and
  `submissions_screen.dart` imports `error_telemetry` + calls `recordNonFatal` ≥2× (R2 — both `_load`
  catches telemeter).
- **SoT registry** `docs/sot_registry.yaml`: add/extend a `community_review_queue` concept
  (writer = EF `get-community-review-items`; readers = `submissions_repository` → `submissions_screen`;
  + `behavioral_test_path`).
- **Self-evolution** debugging skill new bug-class: "cross-user read need vs own-only RLS → scoped
  service-role EF (never relax table RLS); anonymize the projection." Cite d2b9e6 as the sibling.

## Live smoke (founder drives any real-token step — I never mint tokens)
1. `GET /functions/v1/get-community-review-items` version after deploy (tier 6: deployed).
2. anon/no-token POST → expect **401** (verify_jwt working; per deploy-rollback §6.7 a 401 here is the
   EXPECTED pass, not a failure).
3. SQL-as-service_role (`execute_sql`) the EXACT two EF queries → confirm they return the pending cross-user
   rows the client cannot see under own-only RLS, AND prove finding A (`.neq` on a non-projected `user_id`
   returns rows, no error). Live today: **exercises return 4 rows (2 submitters); foods return 0.** So the
   **food** path has no live data — INSERT a temp `user_custom_foods` submission under a test user
   (`submitted_to_db=true, approved=false`), confirm the EF query returns it, then DELETE it (capture id
   first) → verify 0 residual.
4. **Founder one-tap in-app confirm:** test2 → Profile → Submissions → COMMUNITY REVIEW. Expect the **4
   pending exercises** to appear (0 foods is correct — none exist live, not a regression); approve/reject
   writes a `community_reviews` row. (For a fuller check the founder may submit a custom food first.)

## Sequence
1. EF + client + migration 092 (apply live) + delete dead sheet — coherent feature commit.
2. `flutter analyze --no-fatal-infos` + targeted tests green.
3. Deploy EF → smoke (steps 1-3) → record migration in ledger.
4. Diagnose-doc + behavioral test + SoT + self-evolution (commit).
5. B-pass (account tier) → resolve findings.
6. `flutter test` (targeted) + gates green → merge `--no-ff` → `main` → push → CI green.
7. Founder in-app confirm (smoke step 4). (APK not built — founder's call.)

## Open questions — RESOLVED by review #1 (context-blind, all re-verified by me against code + live DB)
- A: `.neq('user_id', …)` on a column absent from `select(...)` — PostgREST emits the filter as
  `user_id=neq.<x>` independent of projection; valid. Marked **must-verify-at-runtime** → smoke step 3.
- B: `callFunction` returns `Future<FunctionResponse>` (NOT a Map). Plan corrected to `response.data as Map?`
  (the `referral_repository.dart:94` pattern). **Was P0; fixed above.**
- C: No consumer besides `submissions_screen.dart:328-329` `_load` (0 in lib/ + test/). ✓
- D: Two tally readers — `trg_auto_approve_community` (SECURITY DEFINER, prosecdef verified) +
  `promote-community-item` (service-role). BOTH BYPASSRLS. No SECURITY INVOKER reader, no view, no
  `community_votes_summary` RPC. Tighten is safe. ✓
- E: delete-account NULLs `reviewer_id` (mig 049) → post-tighten those rows invisible to authenticated
  readers (0 live; both tallies still count them). Documented in the secondary-finding + diagnose-doc.

Review #1 verdict: PLAN-NEEDS-HARDENING — 1 P0 (B) + 2 P1 (doc coverage of tally readers + deleted-user)
+ P2s (smoke framing, deploy-smoke WARN). All folded in above. Architecture (scoped service-role EF +
own-only SELECT tighten + delete dead sheet) confirmed sound and reader-safe.
