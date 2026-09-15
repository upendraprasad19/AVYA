---
reviewed_at: 2026-06-13T13:05:00+05:30
staged_against: community-review-fix (Unit 2, pre-merge)
blast_radius: account
reviewer: claude-sonnet-via-code-review-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — Unit 2: community-review RLS fix

Fresh context-blind Sonnet pass over the staged diff (new EF `get-community-review-items`,
migration 092, `submissions_repository` routing, `submissions_screen` telemetry, dead-sheet delete,
discipline artifacts). 2 P2 findings, both resolved before merge; 8 lens checks clean.

## Findings

### Finding 1 — P2 — stale dead-class doc references — RESOLVED
- **file:** `lib/features/profile/screens/submissions_screen.dart:17,299`
- **claim:** doc-comments still referenced `CommunityReviewSheet` (deleted this commit) — false after the diff.
- **fix:** line 17 → "a community-review bottom sheet (since removed)"; line 299 → dropped the "Mirrors
  CommunityReviewSheet._loadPendingItems" claim, replaced with the EF source of truth.
- **status:** fixed

### Finding 2 — P2 — `_vote` catch was a silent drop — RESOLVED
- **file:** `lib/features/profile/screens/submissions_screen.dart:383`
- **claim:** `_vote`'s `catch (_)` set state but never `recordNonFatal`; a failing `castCommunityVote`
  INSERT (duplicate-vote 23505, or 500) would be invisible in telemetry — violates the
  `lib/core/services/CLAUDE.md` catch-block contract. File already touched → no-deferrals applies.
- **fix:** `catch (e, st) { unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'submissions_community_vote')); ... }`.
  Contract test bumped to assert `recordNonFatal` ≥3× (both `_load` catches + `_vote`).
- **status:** fixed

## Clean lenses (verified, not assumed)
- **writer_reader_drift:** EF projections (`id,name,calories_per_100g,…` / `id,name,category,logging_type`)
  match every field the UI reads at `submissions_screen.dart:443-447`; `item['id']` present in both; no
  client reads `user_id`. `fetchAlreadyReviewedKeys`/`castCommunityVote` are own-row (RLS-safe).
- **function_exception_swallow:** `callFunction` → `Future<FunctionResponse>`; both readers propagate
  `FunctionException` to `_load`'s telemetered catch.
- **blast_radius_mismatch:** `DROP POLICY "Users can read all reviews"` matches the live name (orig
  `058_community_reviews_schema_in_source.sql`); transactional DDL; both BYPASSRLS tally readers safe.
- **secrets_in_tree:** 0 credential-shaped literals; EF reads `SUPABASE_SERVICE_ROLE_KEY` from env.
- **unawaited_no_error_sink:** both (now three) `unawaited(...)` wrap `recordNonFatal` (a telemetry sink).
- **EF auth:** pure `createClient(URL, SERVICE_ROLE)` + `getUser(token)`; no `global.headers`; `kind`
  validated (branch selector, not interpolated).

## Verdict
ACCEPTED — both P2s fixed; re-ran `flutter analyze` (clean) + the contract test (10/10) post-fix.
