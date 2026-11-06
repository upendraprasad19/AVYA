---
bug_id: c7d4f1
date: 2026-06-13
batch: community-review-fix
status: fixed
blast_radius: account
symptom: >
  Profile -> Submissions -> COMMUNITY REVIEW always shows "No items to review
  right now", for EVERY user, even when other users have submitted unapproved
  custom foods/exercises. The community-vote -> auto-promotion pipeline
  (>=10 approve votes -> global library) is therefore inert: nobody can vote
  because nobody can see anyone else's pending submissions.
concept: edge_function_cross_user_read_rls_context
sot_registry_entry: community_review_queue
writers: >
  supabase/functions/get-community-review-items/index.ts (NEW) — a scoped
  service-role function (BYPASSRLS) that authenticates the caller via
  getUser(token) and returns up to 20 submitted-but-not-approved rows from OTHER
  users, narrow column projection, submitter user_id stripped (anonymized).
readers: >
  lib/shared/repositories/submissions_repository.dart fetchPendingFoodReviews /
  fetchPendingExerciseReviews (now route through callFunction), consumed by
  lib/features/profile/screens/submissions_screen.dart _CommunityReviewBody._load.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (Edge Function + cloud-only review queue)
sync_methods: []
restore_methods: []
cloud_table: user_custom_foods, user_custom_exercises, community_reviews
cloud_columns: >
  user_custom_foods(user_id, submitted_to_db, approved, calories_per_100g,
  protein_per_100g, carbs_per_100g, fat_per_100g, name);
  user_custom_exercises(user_id, submitted_to_library, approved_for_library,
  category, logging_type, name); community_reviews(reviewer_id, item_type,
  item_id, vote)
contract_test_path: test/contracts/community_review_rls_context_c7d4f1_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - submissions_community_review_load
    - submissions_my_load
cross_account_guard: true
forbidden_patterns_checked:
  - "client reads user_custom_foods / user_custom_exercises cross-user via .from().neq('user_id', me) — blocked by own-only SELECT RLS (auth.uid()=user_id) -> 0 rows -> empty queue. REPLACED with a scoped service-role Edge Function."
  - "community_reviews SELECT = world-read (USING true) de-anonymizes the vote graph (any authenticated user can read every reviewer_id/item_id/vote). TIGHTENED to own-only (auth.uid()=reviewer_id) in migration 092 — breaks no reader (both tally consumers BYPASSRLS)."
  - "submissions_screen _load catch (_) set _error WITHOUT ErrorTelemetry.recordNonFatal — a server-silent drop once the read can fail (EF non-2xx). FIXED: both _load catches telemeter."
  - "relaxing user_custom_* RLS to world-read to make the queue work — REJECTED: would expose every user's entire custom catalog incl. private un-submitted rows. The EF returns only submitted&&!approved rows."
proposed_fix: >
  Add a service-role Edge Function get-community-review-items (verify_jwt=true):
  pure createClient(URL, SERVICE_ROLE) + getUser(token) (mirror redeem-referral
  d2b9e6 / delete-account e8a1c3); per-kind read of submitted-but-not-approved
  rows from OTHER users (.neq('user_id', callerId)), narrow projection WITHOUT
  user_id (anonymized), limit 20. Route fetchPendingFoodReviews /
  fetchPendingExerciseReviews through SupabaseService.callFunction (response.data
  as Map?). Migration 092 tightens community_reviews SELECT world-read -> own-only
  (closes the vote-graph de-anonymization; both tally consumers BYPASSRLS so
  voting/auto-promotion unaffected). Delete the dead, RLS-broken, rule-#4-violating
  community_review_sheet.dart. Add ErrorTelemetry.recordNonFatal to both
  submissions_screen _load catches (close the silent-drop the new failure mode opens).
regression_test_planned: >
  test/contracts/community_review_rls_context_c7d4f1_test.dart (source-grep,
  comment-stripped): EF built with a pure service-role client + getUser(token),
  selects WITHOUT user_id (anonymized) on both tables; repository routes both
  readers through callFunction('get-community-review-items') and no longer does a
  direct cross-user .from('user_custom_foods'/'user_custom_exercises'); migration
  092 tightens community_reviews SELECT to auth.uid()=reviewer_id; the dead
  community_review_sheet.dart is gone; submissions_screen telemeters both _load
  catches. Plus a live smoke after deploy (4 pending exercises return for a real
  user via the EF; temp-food-insert proves the food path).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "submissions_repository routes both readers through callFunction (response.data as Map?); submissions_screen imports error_telemetry + dart:async and telemeters BOTH _load catches; flutter analyze clean on both changed files (ran in 11.0s, No issues found)" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live counts at plan time: pending_foods=0, pending_exercises=4, distinct_exercise_submitters=2, null_reviewer_rows=0 — so the in-app smoke shows 4 exercises (0 foods is correct, not a regression)" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "get-community-review-items written (pure service-role + getUser(token), _shared/error.ts helpers, anonymized projection, verify_jwt=true); host-shell deploy + live smoke pending the founder deploy authorization (§4.3 classifier-gated)" }
  - { tier: 8, layer: rls_policies, status: verified, evidence: "live pg_policies: user_custom_foods_select_own + user_custom_exercises_select_own = auth.uid()=user_id (own-only) -> cross-user client read blocked (the bug); community_reviews SELECT was world-read (USING true), tightened to own-only by 092. BOTH vote-tally readers BYPASSRLS: trg_auto_approve_community -> auto_approve_community_item() prosecdef=true (SECURITY DEFINER), and promote-community-item via service-role client. No SECURITY INVOKER reader of community_reviews." }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "pre-fix the cross-user read returns 0 under authenticated RLS (empty queue for all). The EF's exact service-role query returns the 4 live pending exercises that the client cannot see — proven via execute_sql; full end-to-end in-app proof pending the founder smoke." }
impact_analysis: >
  Account-tier (new Edge Function + RLS migration + cross-user data path). The
  community-review queue has been inert since inception: the readers need OTHER
  users' pending submissions, but own-only SELECT RLS on user_custom_foods /
  user_custom_exercises returns 0 rows under the caller's authenticated context.
  Same CLASS as d2b9e6 (referral) — a feature needs a cross-user read that
  own-only RLS blocks — but a different mechanism: there was no Edge Function at
  all (the client read Supabase directly), so the fix INTRODUCES a scoped
  service-role EF rather than correcting an existing one's client. The secondary
  community_reviews world-read tighten closes a vote-graph de-anonymization in the
  same feature; verified reader-safe because both tally consumers BYPASSRLS (the
  SECURITY DEFINER trigger + the service-role cron). Deleted-user rows
  (reviewer_id NULL via migration 049) become invisible on the authenticated path
  post-tighten but are still counted by both tallies (0 such rows live). Plan
  independently reviewed TWICE (context-blind, per CLAUDE.md §4.12) before code;
  review #1 caught a P0 client accessor (callFunction returns FunctionResponse,
  not a Map) and review #2 caught a P1 telemetry silent-drop in _load — both folded
  in before a line was written.
  related: d2b9e6 (referral cross-user read RLS-context, same class); e8a1c3
  (delete-account EF-auth family); observability silent-drop class (the _load catch).
---

# Community review queue is always empty — cross-user read blocked by own-only RLS (c7d4f1)

## What happened
Profile → Submissions → COMMUNITY REVIEW shows "No items to review right now" for
every user. The two readers (`submissions_repository.fetchPendingFoodReviews` /
`fetchPendingExerciseReviews`, consumed by `submissions_screen._CommunityReviewBody`)
query OTHER users' submitted-but-not-approved rows with `.neq('user_id', me)`. Both
`user_custom_foods` and `user_custom_exercises` enforce own-only SELECT RLS
(`auth.uid() = user_id`), so the cross-user read returns **0 rows** under the caller's
`authenticated` context. The community-vote → auto-promotion pipeline is inert.

## Root cause
```dart
// submissions_repository.dart (before) — runs as `authenticated`, own-only RLS
await client.from('user_custom_foods')
    .select('id, name, ..., user_id')
    .eq('submitted_to_db', true).eq('approved', false)
    .neq('user_id', currentUserId)   // <-- cross-user read; RLS returns 0 rows
    .limit(20);
```
You cannot relax the table RLS to world-read — that exposes every user's entire custom
catalog (incl. private, un-submitted rows). The cross-user read must move to a scoped
service-role context that returns ONLY `submitted && !approved` rows from other users.

## Fix
- **New EF** `get-community-review-items` (verify_jwt=true): pure service-role client
  (BYPASSRLS) + `getUser(token)`; per-kind read of submitted-not-approved rows from other
  users (`.neq('user_id', callerId)`), narrow projection **without** `user_id` (anonymized),
  limit 20. Mirrors the redeem-referral (d2b9e6) auth pattern.
- **Client**: both readers route through `SupabaseService.callFunction` (`response.data as Map?`).
- **Migration 092**: `community_reviews` SELECT world-read → own-only (closes vote-graph
  de-anonymization; both BYPASSRLS tally consumers unaffected; INSERT/UPDATE untouched).
- **Telemetry**: both `submissions_screen._load` catches now `recordNonFatal` (the EF can fail
  non-2xx; the old `catch (_)` would have been a server-silent drop).
- **Delete** the dead, RLS-broken, rule-#4-violating `community_review_sheet.dart`.

## Verification
- `test/contracts/community_review_rls_context_c7d4f1_test.dart` (source-grep, comment-stripped).
- Live smoke (after deploy): the EF returns the 4 live pending exercises for a real user;
  temp `user_custom_foods` insert proves the food path; then cleaned up.

## See also
- supabase/functions/get-community-review-items/index.ts
- supabase/migrations/092_community_reviews_select_own_only.sql
- docs/diagnoses/2026-06-13-referral-rls-context-d2b9e6.md (same cross-user-read RLS class)
- docs/superpowers/plans/2026-06-13-unit2-community-review-rls.md (plan + 2 review rounds)
