---
reviewed_at: 2026-07-29T15:06:16+05:30
staged_against: 2dbdf134304e
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 2
verdict: accepted
---

# Code Review — 2dbdf134304e

## Finding 1 — P1 — writer_reader_drift
- **file:line:** lib/features/auth/screens/restoring_screen.dart:131-190 (`hasCorePlanFields`/self-heal), supabase/migrations/112_onboarding_required_fields_transition_gate.sql:19-22, docs/diagnoses/2026-07-29-ai-coach-daily-caps-toctou-f4a19c.md `writers:` field
- **claim:** Migration 112 gates the NULL→non-null transition of `user_profile.onboarding_completed_at` on 9 fields. The diagnose-doc's writer enumeration checked only one writer (`OnboardingNotifier.completeOnboarding`'s single upsert). A second, independent writer of the same transition — `restoring_screen.dart`'s OBS-3 self-heal (`_stampOnboardingCompletedAt`) — gated its stamp attempt on only 3 of the 9 fields (`hasCorePlanFields`). A `flagOnboarded=true` legacy user missing one of the other 6 fields would have this self-heal attempt the stamp on every cold start, have migration 112 correctly reject it every time (P0001 `onboarding_completed_with_missing_fields`), and never succeed — a permanent, self-perpetuating failure loop introduced by this batch's own onboarding fix.
- **verification:** `sed -n '131,190p' lib/features/auth/screens/restoring_screen.dart`; `sed -n '17,37p' supabase/migrations/112_onboarding_required_fields_transition_gate.sql`; `sed -n '85,101p' lib/core/services/sync/sync_profile.dart`.
- **suggested-fix:** Widen the self-heal's field check to match migration 112's 9 fields exactly; gate the stamp *attempt* (not the navigation) on completeness so the pre-existing `flagOnboarded=true` legacy-user routing behavior is unchanged, but the doomed-write retry loop stops.
- **status:** accepted — fixed in this batch. `hasCorePlanFields` renamed to `hasAllRequiredFields`, widened to all 9 fields; stamp attempt now wrapped in its own `if (hasAllRequiredFields)` guard inside the unchanged `if (flagOnboarded || hasAllRequiredFields)` navigation gate. Regression test added: `test/onboarding/resume_route_resolver_test.dart` ("OI-46 (2026-07-29, B-pass round) — self-heal stamp attempt is gated on ALL 9 migration-112 fields..."). 43 pre-existing tests covering this file's routing logic re-run green; `flutter analyze` clean on the touched file.

## Finding 2 — P2 — blast_radius_mismatch
- **file:line:** docs/blast_radius.yaml:23-25 (`platform` tier's `requires: [..., feature_flag]`); supabase/migrations/111_chat_vision_daily_cap_triggers.sql, 112_onboarding_required_fields_transition_gate.sql, 113_fix_food_text_trigger_ist_boundary.sql (no flag/kill-switch read anywhere in any of the three)
- **claim:** The registry's `platform` tier requires a `feature_flag` per its `requires:` list. None of the three new/modified triggers read a runtime flag — once applied, disabling a misbehaving trigger requires authoring and applying a new migration, not flipping a switch.
- **verification:** `sed -n '20,30p' docs/blast_radius.yaml`; `grep -n "RAISE EXCEPTION\|configBox\|feature_flag\|current_setting" supabase/migrations/111_chat_vision_daily_cap_triggers.sql supabase/migrations/112_onboarding_required_fields_transition_gate.sql supabase/migrations/113_fix_food_text_trigger_ist_boundary.sql` (zero flag-read hits); `grep -rln "feature_flag\|kill_switch" supabase/migrations/*.sql` across all ~113 prior migrations (zero hits anywhere in migration history, including migration 026 — the direct precedent this batch mirrors).
- **suggested-fix:** Either add a Postgres-side kill-switch (config table or GUC read) to all three trigger functions, or explicitly accept the gap as consistent with every prior trigger-adding migration in this repo's history.
- **status:** accepted as a documented exception, not fixed. Zero of ~113 prior migrations that add a trigger — including the literal migration (026) this batch was instructed to mirror — carry a runtime feature flag; all rely on `Rollback strategy: migration NNN` instead. Building batch-specific kill-switch infrastructure with no precedent elsewhere in the codebase is an architecture decision bigger than this bugfix batch should make unilaterally. Additionally, none of the three migrations are being applied live in this batch (separate explicit authorization required per CLAUDE.md §4.3) — a stronger, more deliberate gate than an in-code flag, since nothing runs at all until a human explicitly authorizes the apply. Documented in the diagnose-doc's "B-pass" section for founder visibility; flagged as a real, considered gap rather than silently dropped.

## Lens 1 (writer_reader_drift) — additional verification beyond Finding 1
- **checked:** Cross-referenced every `ai-proxy/index.ts` `.includes(...)` substring check against the exact `RAISE EXCEPTION` string each trigger raises: `chat_app_daily_limit_reached`, `vision_analysis_daily_limit_reached`, `food_text_daily_limit_reached` (pre-existing, untouched). Confirmed each `.includes()` target is an exact literal prefix of its trigger's raised message with no truncation/interpolation ahead of the match, and no cross-trigger contamination possible given each function's own early-exit channel guard.
- **why clean:** Exact string matches confirmed by direct read of both sides (migration source + ai-proxy source), not by trusting either file's own comments.

## Lens 2 (function_exception_swallow) — clean
- **checked:** Every Supabase client call touched by this diff: `visionReserved` insert, `resolveVisionPlaceholder`'s UPDATE, `chatReservation` insert, the `loopErr`-path resolution UPDATE, and the success-path resolution UPDATE. Confirmed the two bare `catch (_) {}` blocks this diff *removes* (the old scan_meal/cart_auditor post-hoc inserts) were not reintroduced anywhere else in the diff.
- **why clean:** Every one of the five calls destructures `{ data, error }` (or `{ error }`) directly off the awaited builder call — no bare `try { await ... } catch {}` wraps any of them — and every non-null `error` is logged via `console.error` before the function proceeds, matching `resolvePlaceholder`'s pre-existing shape (the round-2-review-driven fix for a prior silent-swallow finding, independently re-verified here).

## Lens 3 (blast_radius_mismatch) — additional verification beyond Finding 2
- **checked:** Confirmed via `docs/blast_radius.yaml` (not the diagnose-doc's self-declaration) that `supabase/migrations/**` and `supabase/functions/ai-proxy/**` are both registered `platform` tier. Confirmed the diagnose-doc exists, has a populated `touched_layers_checked` covering all 12 tiers with reasoned statuses. Searched the full staged diff for any live-apply or deploy call — none found, consistent with the doc's "What is NOT yet true" section.
- **why (mostly) clean:** Self-classification matches the registry's independent tier assignment; the 12-tier checklist is genuinely populated with specific evidence, not rubber-stamped. The one gap is Finding 2 (accepted exception).

## Lens 4 (secrets_in_tree) — clean
- **checked:** Full staged diff scanned for credential-shaped literals (`sk-`, `rzp_live_`, `AKIA`, `-----BEGIN`, `api_key`, `service_role`, JWT-shaped strings, `password`). Zero matches. `test/sql/oi46_daily_cap_triggers_live_verify.sql`'s synthetic fixtures use deterministic UUIDs and `.local`-TLD emails — clearly non-routable, not real PII or credentials.
- **why clean:** No credential-shaped literal anywhere in the diff.

## Lens 5 (unawaited_no_error_sink) — clean
- **checked:** No Dart `unawaited(` calls in the Edge Function diff (not applicable — TypeScript). Broadened to every `try { await ... }` touched by the diff: all `catch` blocks now perform an observable action (log + error-checked resolution write) on every code path that matters for cap correctness; the two previously-bare `catch (_) {}` blocks were deleted, not left in place.
- **why clean:** No empty/no-op catch introduced anywhere in the diff.
