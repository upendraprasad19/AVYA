---
bug_id: f4a19c
date: 2026-07-29
batch: oi46-daily-cap-triggers
status: fixed
blast_radius: platform
symptom: >
  OI-46 (audit finding, re-verified 2026-07-29) named a `channel='in_app'`
  gap that does not exist as a live value. The real gaps, found during
  re-verification: (1) chat's free-tier 10/day cap
  (`ai-proxy/index.ts`, channel='app') was check-then-insert — a SELECT
  count() pre-check followed by an unconditional INSERT at the very end of
  the handler with no re-check at insert time, so two concurrent requests
  near the cap boundary could both pass. (2) the vision cap (scan_meal +
  cart_auditor, combined 15/day) was worse: the interaction row was
  INSERTed AFTER Gemini succeeded, wrapped in a silently-swallowed
  `catch (_) {}` — so even a capped user's request would complete
  successfully with the row-insert failure discarded, meaning the cap was
  not enforced at all once the pre-check SELECT was raced. (3) the 9
  onboarding-critical `user_profile` fields (date_of_birth, gender,
  height_cm, current_weight_kg, target_weight_kg, primary_goal,
  fitness_experience, days_per_week, equipment_access) were only enforced
  by `OnboardingNotifier`'s client-side route sequence, with no Postgres
  backstop — a corrupted local Hive state or a future client bug could sync
  `onboarding_completed_at` non-null with one of the 9 fields still null.
  A fourth, unplanned finding surfaced while mirroring the precedent
  trigger (migration 026) for the two new ones: `enforce_food_text_daily_limit`
  itself uses a bare `date_trunc('day', now())` boundary, which truncates in
  the DB session's default timezone (UTC on this project) and resets the
  50/200-per-day food_text_analysis cap at 05:30 IST instead of midnight IST
  — the exact H-4 bug class already fixed once on the client side of this
  same file (`istDayStartIso()`), reproduced server-side, live, in
  production, in the file this batch was directly mirroring.
concept: ai_coach_daily_cap_enforcement
sot_registry_entry: >
  chat_app_daily_cap and vision_analysis_daily_cap follow the existing
  food_text_analysis_daily_cap precedent — documented as rows in
  supabase/functions/CLAUDE.md's SoT contracts table (not as top-level
  docs/sot_registry.yaml concepts; that heavier Hive+cloud schema is not
  used for Edge-Function-only, no-Hive concepts, matching how
  food_text_analysis_daily_cap itself is scoped). onboarding_required_fields
  is folded as prose into the PRE-EXISTING docs/sot_registry.yaml
  `onboarding_completed_at` concept (not a new top-level concept — the
  trigger adds a write-time constraint to that concept's existing writer,
  it does not introduce a new writer/reader pair).
writers: >
  supabase/functions/ai-proxy/index.ts — chat reservation insert at line 692
  (chatReservation), UPDATE-not-INSERT resolution via resolveVisionPlaceholder-
  style error-checked UPDATEs (loopErr-path + success-path) at the end of the
  tool loop; vision reservation insert at line 460 (visionReserved),
  resolveVisionPlaceholder UPDATE (with `.error` logging, round-2 review fix)
  called from every exit path (success, Gemini-failure, invalid-JSON) in both
  scan_meal and cart_auditor. Trigger
  functions: supabase/migrations/111_chat_vision_daily_cap_triggers.sql
  enforce_chat_app_daily_limit (line 13) + trg_chat_app_rate_limit trigger
  (line 62), enforce_vision_analysis_daily_limit (line 67) +
  trg_vision_analysis_rate_limit trigger (line 99);
  supabase/migrations/112_onboarding_required_fields_transition_gate.sql
  enforce_onboarding_required_fields (line 17) + trg_onboarding_required_fields
  trigger (line 41); supabase/migrations/113_fix_food_text_trigger_ist_boundary.sql
  CREATE OR REPLACE FUNCTION enforce_food_text_daily_limit (line 18, IST-boundary
  fix only, cap values and channel gating unchanged from migration 026).
  Client sync writer for the onboarding fields:
  lib/core/services/sync/sync_profile.dart's conditional-field-inclusion
  upsert (SyncService._hasValue guards) — verified this is a SINGLE upsert
  call, so a legitimate onboarding-completion sync always carries all 9
  fields alongside onboarding_completed_at in the same request; a later
  partial-upsert on an already-completed row simply omits unchanged
  columns, which the trigger's OLD.onboarding_completed_at IS NOT NULL
  short-circuit correctly ignores. A SECOND writer, found by the B-pass
  round (not by the earlier ×2 review — see "B-pass" section below):
  lib/features/auth/screens/restoring_screen.dart's OBS-3 self-heal
  (`_stampOnboardingCompletedAt`, line ~490) also transitions
  onboarding_completed_at NULL -> non-NULL, gated on `flagOnboarded ||
  hasAllRequiredFields` (renamed from `hasCorePlanFields`, widened from 3
  fields to the full 9 this batch). The stamp ATTEMPT is now separately
  gated on `hasAllRequiredFields` so a flagOnboarded=true legacy user with
  an incomplete profile still navigates home (no behavior change) but the
  app stops retrying a write migration 112 would reject every time.
readers: >
  Free-tier + PRO users hitting the AI Coach chat, scan-meal, and
  cart-auditor features (client caller:
  lib/features/nutrition/providers/nutrition_provider.dart:733/1356/1445,
  and the chat screen's message-send path); onboarding completion readers —
  every place that gates on `onboarding_completed_at` non-null
  (lib/features/onboarding/providers/onboarding_provider.dart,
  lib/features/auth/screens/restoring_screen.dart,
  lib/core/services/auth_session_bootstrapper.dart) now get a guarantee
  the 9 fields were non-null at the moment that flag was set server-side,
  not just client-side.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: ai_coach_interactions, user_profile
cloud_columns: >
  ai_coach_interactions.channel, ai_coach_interactions.user_id,
  ai_coach_interactions.created_at (trigger read columns);
  user_profile.onboarding_completed_at, user_profile.date_of_birth,
  user_profile.gender, user_profile.height_cm,
  user_profile.current_weight_kg, user_profile.target_weight_kg,
  user_profile.primary_goal, user_profile.fitness_experience,
  user_profile.days_per_week, user_profile.equipment_access
contract_test_path: test/contracts/chat_app_daily_cap_test.dart, test/contracts/vision_analysis_daily_cap_test.dart, test/contracts/onboarding_required_fields_test.dart, test/onboarding/resume_route_resolver_test.dart
ist_handling: >
  Both new triggers (migration 111) use
  `date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'`
  — the idiom already established in migrations 093/101 — NOT migration
  026's bare `date_trunc('day', now())`, which was found live-buggy during
  this batch and fixed separately in migration 113 (CREATE OR REPLACE on
  the same function, cap values/gating byte-identical to migration 026).
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  check-then-insert / check-then-write races on a shared cap counter; a
  swallowed `catch (_) {}` around a row-insert that is the ONLY enforcement
  point for a cost-relevant cap; a blanket NOT NULL on a table populated
  incrementally (would have broken legitimate partial onboarding writes);
  copying a known-buggy day-boundary expression into new code while fixing
  a sibling of the same bug in the same batch.
proposed_fix: >
  Two new Postgres triggers (migration 111) mirroring migration 026's
  BEFORE INSERT + RAISE EXCEPTION ... USING ERRCODE='P0001' shape, with the
  corrected Asia/Kolkata day boundary: trg_chat_app_rate_limit (channel='app',
  10/day, PRO-exempt via a subscriptions EXISTS check) and
  trg_vision_analysis_rate_limit (channel IN ('scan_meal','cart_auditor'),
  combined 15/day, no PRO exemption — matches the existing client-side
  cap's own scope). ai-proxy/index.ts restructured from check-then-insert /
  insert-after-success to the same insert-first "reservation" pattern
  food_text_analysis already used: reserve a row BEFORE calling Gemini,
  catch the trigger's P0001 and return 429 without ever calling Gemini,
  UPDATE (not INSERT) the reserved row with the real response once Gemini
  succeeds. A third trigger (migration 112),
  enforce_onboarding_required_fields, is a state-TRANSITION gate (fires
  only on the NULL -> non-NULL transition of onboarding_completed_at, not
  on every subsequent update) requiring the 9 onboarding-critical fields
  non-null at that moment. A fourth migration (113) fixes migration 026's
  own day-boundary bug via CREATE OR REPLACE, found while mirroring its
  shape for the two new triggers.
regression_test_planned: >
  Source-grep contract tests (presence-only, per
  feedback_source_grep_false_confidence.md):
  test/contracts/chat_app_daily_cap_test.dart,
  test/contracts/vision_analysis_daily_cap_test.dart,
  test/contracts/onboarding_required_fields_test.dart — all 3 new + the
  pre-existing food_text_analysis_daily_cap_test.dart run green locally
  (11/11 tests passed, verified this batch). Behavioral proof (the actual
  live-Postgres trigger behavior — 11th/16th row rejection, PRO exemption,
  onboarding transition-vs-post-completion semantics, and migration 113's
  deployed function source) lives in
  test/sql/oi46_daily_cap_triggers_live_verify.sql, run via the existing
  generic `scripts/check_onconflict_live_arbiter.dart --sql
  test/sql/oi46_daily_cap_triggers_live_verify.sql` harness (no new script
  needed — it is already fully SQL-file-parameterized). **RUN LIVE
  2026-07-29, after migrations 111/112/113 were applied per explicit
  founder authorization: all 7 cases (chat 11th-row rejection, PRO
  exemption 11-rows-ok, vision combined 16th-row rejection, onboarding
  gate rejects missing field, onboarding gate allows the complete row,
  onboarding gate ignores post-completion edits, food_text IST-boundary
  fix confirmed) returned `status='ok'`.** The file's first draft used
  invalid explicit `SAVEPOINT`/`ROLLBACK TO SAVEPOINT` statements (PL/pgSQL
  does not support them inside a function/DO body — only implicit
  per-BEGIN-block savepoints via nested `BEGIN ... EXCEPTION WHEN ... END`);
  this was caught by the live run itself (`42601: syntax error at or near
  "TO"`) and fixed by rewriting the harness with nested BEGIN/EXCEPTION
  blocks only, re-run green. behavioral_test_required: true is now
  satisfied for all 3 new SoT registry entries.
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "ai-proxy/index.ts restructured to insert-first reservation for chat + vision (lines 460, 692 and surrounding blocks) — a Deno Edge Function, not covered by flutter analyze. B-pass round found a second onboarding_completed_at writer (lib/features/auth/screens/restoring_screen.dart's OBS-3 self-heal) that migration 112 would have put into a permanent doomed-retry loop for a narrow legacy cohort; fixed by widening its field check to match migration 112 exactly and gating the stamp attempt on completeness (line ~140-190). `flutter analyze` clean on the touched file + full-repo `--no-fatal-infos` run (0 errors/warnings); 43 pre-existing tests covering this file's routing logic re-run green; 1 new regression test added (test/onboarding/resume_route_resolver_test.dart)." }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive read/write in this batch" }
  - { tier: 3_postgres_schema, status: fixed_in_this_batch, evidence: "3 new migration files add 2 new trigger functions + 2 new triggers on ai_coach_interactions, 1 new trigger function + trigger on user_profile, and a CREATE OR REPLACE fix to an existing trigger function. Applied live — see tier 5." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no existing row data touched by any of the 4 migrations; all are function/trigger DDL only" }
  - { tier: 5_migrations_applied, status: fixed_in_this_batch, evidence: "Applied live to dedsavbjuwgarrhphgnl 2026-07-29T16:03:47+05:30 via mcp__supabase__apply_migration, per explicit founder authorization (AskUserQuestion: 'Apply now, then commit'). Verified via a live pg_trigger query confirming all 4 triggers (trg_chat_app_rate_limit, trg_vision_analysis_rate_limit, trg_onboarding_required_fields, food_text's existing trigger re-pointed at the CREATE OR REPLACE'd function) present and enabled. backups/applied_migrations.json updated in the same batch (entries for 111/112/113, applier: claude-via-mcp, diagnose: f4a19c)." }
  - { tier: 6_edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "ai-proxy/index.ts source restructured AND deployed live as version 79 via the host-shell deploy flow (emit_payload.js + deploy_via_api.js --yes), per explicit founder authorization (AskUserQuestion: 'Deploy ai-proxy now'). Boot-verified via an unauthenticated smoke test returning the function's own in-code 401 (verify_jwt=false, so this 401 originates from the function's own auth-header check, confirming the module booted successfully with the new code)." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron-dispatched function touched" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS policy change; ai_coach_interactions and user_profile RLS unchanged" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage bucket or object touched" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service (Razorpay/OneSignal/Firebase) touched" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "test/sql/oi46_daily_cap_triggers_live_verify.sql traces the full chat + vision + onboarding flows end-to-end via live-Postgres INSERT/UPDATE sequences in a rollback transaction; run live 2026-07-29 after migration apply — all 7 cases passed (status='ok'). See regression_test_planned for detail." }
impact_analysis: >
  Positive: closes a genuine TOCTOU on the chat cap and a genuine
  enforcement-defeating swallowed-error bug on the vision cap (both cost-
  relevant — each bypassed request is a paid Gemini call); adds a
  previously-absent server-side backstop for onboarding data completeness;
  fixes a live day-boundary bug in a pre-existing trigger discovered as a
  direct byproduct of correctly mirroring its shape. **All three triggers
  are now live** (migrations 111/112/113 applied 2026-07-29T16:03:47+05:30,
  ai-proxy deployed as version 79 the same day, both per explicit founder
  authorization) — the vulnerability window described in the original plan
  is closed, not merely prepared. Verified end-to-end via
  test/sql/oi46_daily_cap_triggers_live_verify.sql (7/7 cases passing
  live).

  Two additional residuals, surfaced by round-1 independent review and
  accepted as out-of-scope for this batch rather than silently dropped:
  (1) the new triggers' cap check (`SELECT count(*) ...` then insert) runs
  under ordinary READ COMMITTED with no `FOR UPDATE`/advisory lock/unique-
  constraint-backed counter, so two genuinely simultaneous inserts from the
  SAME user (e.g. a double-tap across two devices) can each pass the check
  before either commits, landing at one row over cap — this mirrors the
  PRE-EXISTING food_text_analysis trigger's identical design (migration
  024/026) verbatim, is self-inflicted only (cannot affect another user's
  cap), and closing it would mean redesigning the already-accepted
  precedent this batch was explicitly told to mirror, not a regression
  introduced here. (2) the chat reservation does not get the same pending-
  row dedup-reuse treatment food_text_analysis has (lines ~238-287) — a
  rapid same-message double-tap while the first request is still in-flight
  creates two reservations instead of reusing one, burning two cap slots.
  This is unchanged from pre-fix behavior (the old code's completed-row-only
  dedup had the identical gap, just with the insert timing moved) so it is
  not a new regression; fixing it would require porting food_text's
  pending-row-reuse dedup to chat, which is a separable enhancement, not
  required to close OI-46's actual named gaps.
---

# AI Coach daily-cap enforcement had two live TOCTOU/swallowed-error gaps, and a third gap had no server backstop at all

## What OI-46 actually named vs. what's real

OI-46's original text described a `channel='in_app'` gap. That value does not exist
anywhere in `ai_coach_interactions` — the live channel values are `app` (chat),
`food_text_analysis`, `scan_meal`, `cart_auditor`, and a small number of system-internal
ones. Re-verifying the board against live code (2026-07-29) found the actual gaps were
elsewhere entirely, and one of them (vision) was structurally worse than a simple TOCTOU.

## Gap 1 — chat: check-then-insert with no re-check at insert time

`ai-proxy/index.ts`'s chat handler ran a `SELECT count(*) ... WHERE channel='app' AND
created_at >= istDayStartIso()` against the free-tier cap of 10, then — much later in the
same handler, after the full tool loop had run — unconditionally `INSERT`ed the interaction
row with no cap re-check at insert time. Two requests arriving within the same race window
could both observe `count=9`, both pass, and both insert, landing the user at 11+ messages
for the day. The insert was also the ONLY point at which the row's terminal state was
recorded — a Gemini-side failure between the check and the insert left no artifact at all.

## Gap 2 — vision: the enforcement point itself was silently discarded

`scan_meal` and `cart_auditor` shared a combined 15/day pre-check SELECT, structurally the
same race as chat. But their success-path insert was:

```ts
try {
  await supabaseClient.from("ai_coach_interactions").insert({...});
} catch (_) {}
return new Response(JSON.stringify(parsed), { status: 200, ... });
```

Even with a hypothetical trigger added directly on this insert with no other change, a
capped user's request would still complete successfully: the trigger's P0001 exception
would be thrown, caught by the empty `catch (_) {}`, and discarded — the 200 response with
the real Gemini output would still be returned. This is not merely racy; the historical
enforcement point could never have worked once raced past the initial SELECT. Mirroring
migration 026's trigger onto this insert point alone, without also restructuring the insert
timing, would have shipped a trigger that never actually rejects a live request.

## Gap 3 — onboarding: client-only enforcement, no Postgres backstop

`OnboardingNotifier`'s route sequence collects the 9 required fields before ever setting
`onboarding_completed_at`, but nothing on the Postgres side enforced that ordering. A
corrupted local Hive state, or a future client-side onboarding-flow bug, could sync
`onboarding_completed_at` non-null while one of the 9 fields was still null, with the server
accepting it silently.

## Unplanned finding: migration 026 has the exact bug it was chosen to protect against

Migration 111's two new triggers were built to mirror migration 026
(`enforce_food_text_daily_limit`)'s shape — same insert-first reservation discipline, same
`RAISE EXCEPTION ... USING ERRCODE='P0001'` pattern. Reading migration 026 in full to copy
it correctly surfaced that its day-boundary expression is `date_trunc('day', now())` with no
timezone qualifier — this truncates in the database session's default timezone (UTC on this
project; no migration sets a non-UTC session timezone), so the 50/200-per-day
food_text_analysis cap actually resets at 05:30 IST, not midnight IST. This is the identical
H-4 bug class already fixed once on the CLIENT side of this same `ai-proxy/index.ts` file
(`istDayStartIso()`, replacing a `setUTCHours(0,0,0,0)` UTC-midnight bug) — reproduced
server-side, live, in production, in the exact file being used as this batch's own
precedent. Fixed via a fourth migration (113), `CREATE OR REPLACE FUNCTION` with the
corrected `Asia/Kolkata`-qualified boundary; cap values and channel gating are otherwise
byte-identical to migration 026.

## The fix

All four migrations use the insert-first "reservation" pattern already proven by
`food_text_analysis`: reserve a row (or, for onboarding, gate the state transition) BEFORE
the expensive/consequential operation, let the trigger raise P0001 if over cap or missing a
required field, and only proceed on a clean reservation. `ai-proxy/index.ts` was restructured
for both chat and vision to insert the reservation row before calling Gemini and UPDATE
(not INSERT) it afterward — closing gap 2 structurally, not just adding a trigger on top of
an already-broken enforcement point. The onboarding trigger is a state-transition gate (only
fires on the NULL -> non-NULL flip of `onboarding_completed_at`), not a blanket NOT NULL,
because `user_profile` is populated incrementally and `sync_profile.dart`'s conditional-
field-inclusion upsert pattern legitimately sends partial payloads on every subsequent sync
of an already-completed profile — confirmed by reading the writer before finalizing the
trigger design, per the standing writer/reader-before-fix discipline.

## Round-1 review: vision's "structural" fix didn't cover every exit path, and a malformed request could still orphan a reservation

Independent review of the first draft found two real bugs in the vision restructuring. First,
`resolveVisionPlaceholder`-equivalent resolution only ran on the success path — the `!content`
(Gemini failure) and invalid-JSON `catch` branches in both `scan_meal` and `cart_auditor`
returned without ever touching the reserved row, leaving it stuck at `model_used: 'pending'`
forever while still counting toward the day's 15-cap. This is the identical "stuck pending row"
bug class `food_text_analysis`'s own `resolvePlaceholder` helper exists specifically to close
(see its comment: "8 stuck pending placeholder rows across 2026-05-11→15"); the vision
restructuring hadn't carried that discipline over. Fixed by extracting a shared
`resolveVisionPlaceholder` helper called from all three exit branches in both handlers.

Second, the pre-reservation image validation only rejected wrong-typed or oversized images, not
a missing/null/empty one — since neither handler runs without a truthy `body.image`
(`if (type === "scan_meal" && body.image)`), a malformed request would still insert a
reservation that nothing would ever resolve, burning a cap slot and orphaning a row on a request
that should have 400'd immediately. Fixed by rejecting `imgB64.length === 0` (and tightening the
null/undefined branch) before the reservation insert.

Two new regression tests pin both fixes in `test/contracts/vision_analysis_daily_cap_test.dart`.

## Round-2 review: the round-1 fix closed the functional gap but dropped the diagnostic half

A second, independent reviewer verified round-1's two fixes were complete and correct (traced
every exit path by hand), then found that `resolveVisionPlaceholder` — and the two analogous
inline UPDATE resolutions on the chat path — used a bare `try/catch` around the resolution
UPDATE. supabase-js query builders resolve with `{data, error}` on a PostgREST-level failure
(RLS denial, constraint violation, 5xx) rather than rejecting a promise
(`feedback_postgrest_builder_no_catch.md`), so a bare `catch` never observes that failure class
— a resolution UPDATE could fail completely silently, with no log line, immediately after this
same batch's diagnose-doc cited "stuck pending rows, discovered only because failures were
logged" as the exact motivating precedent. Fixed by destructuring `{ error }` from all three
resolution UPDATEs (vision's `resolveVisionPlaceholder`, chat's `loopErr`-path resolution,
chat's success-path resolution) and logging on failure, matching `resolvePlaceholder`'s existing
shape exactly.

The same round also caught two migration comments (111, 113) that cited
`ai-proxy/index.ts:604-606, istDayStartIso()` as still-live evidence for the IST-boundary fix's
rationale — but this same diff's chat/vision restructuring deletes `istDayStartIso()` and the
check-then-insert pre-checks that called it. Once these migrations are applied, that comment
would be baked into the deployed function definition describing code that no longer exists in
the file it's part of. Reworded to past tense, naming what the fix used to be rather than
pointing at now-removed lines. It also caught two stale line-number citations in this doc's own
`writers:` field (chat reservation cited at 667, actually 692; vision at 448, actually 460) —
both corrected.

## B-pass: a second onboarding writer the ×2 review never enumerated, and an accepted registry-tier exception

The 5-lens B-pass found the most consequential issue in the whole batch: the ×2 review's writer
analysis for the onboarding trigger checked exactly one writer
(`OnboardingNotifier.completeOnboarding`'s single upsert) and concluded the transition gate was
safe. `lib/features/auth/screens/restoring_screen.dart` has a second, independent writer of the
same NULL -> non-NULL transition — the OBS-3 self-heal, which fires when a returning user's local
Hive profile looks complete but the cloud `onboarding_completed_at` was never stamped. Pre-fix,
this self-heal's own completeness check (`hasCorePlanFields`) only verified 3 of the 9 fields
migration 112 now gates. A `flagOnboarded=true` legacy user missing one of the other 6 would have
this self-heal attempt the stamp on every single cold start, have migration 112 correctly reject
it every time, and never succeed — a permanent, silent, self-perpetuating failure loop for that
cohort, introduced by this batch's own fix for a *different* bug. Fixed by widening the check to
all 9 fields (renamed `hasAllRequiredFields`) and, since the `flagOnboarded` legacy signal alone
should still route the user home without a navigation regression, gating only the stamp *attempt*
— not the navigation — on completeness. Regression test added:
`test/onboarding/resume_route_resolver_test.dart`.

This is the second time in this batch that widening a writer/reader search surfaced a real,
non-obvious defect (`sync_profile.dart`'s conditional upsert being the first, pre-migration-112
design check) — both times because the actual writer set was larger than the first pass assumed.

The B-pass also flagged that `docs/blast_radius.yaml`'s `platform` tier lists `feature_flag` as a
requirement, and none of the three new/modified triggers have one — an incident-response concern
(disabling a misbehaving trigger post-deploy means authoring a new migration, not flipping a
runtime flag). Checked against precedent: zero of this repo's ~113 prior migrations that add a
trigger — including migration 026, the direct precedent this batch was told to mirror — carry a
runtime feature flag; every one relies on `Rollback strategy: migration NNN` instead. Given (a)
this pattern is consistent with every sibling migration in the codebase's history, not a new gap
this batch introduces, and (b) the migrations are not being applied live in this batch regardless
(a stronger, more deliberate gate than an in-code flag — nothing runs until a human explicitly
authorizes the apply), this is accepted as a documented exception to the registry's generic
`platform`-tier requirement rather than built as new, batch-specific infrastructure with no
precedent elsewhere in the repo. If a future incident makes Postgres-side kill-switches for
AI-coach triggers a recurring need, that is a `docs/naming_conventions.md`-worthy pattern decision
for the founder to make deliberately, once, and apply consistently — not something to invent
unilaterally inside a single bugfix batch.

## Live apply + deploy (2026-07-29, post-B-pass)

Landing this branch's diff alone would not have closed the vulnerability window — per CLAUDE.md
§4.3, plan approval is not deploy approval, and a live migration apply / Edge Function deploy
each require their own separate, explicit authorization. Both were requested and given
explicitly this session, via `AskUserQuestion`, and executed:

1. **Migrations 111/112/113 applied** to `dedsavbjuwgarrhphgnl` at 2026-07-29T16:03:47+05:30 via
   `mcp__supabase__apply_migration`, after `backups/applied_migrations.json`'s parity test
   (`test/contracts/applied_migrations_parity_test.dart`) surfaced that this repo's manifest
   schema has no "authored but not applied" state — every one of its 114 pre-existing entries
   carries a real `applied_at` timestamp, meaning the established convention is author+apply in
   the same commit, not stage-then-apply-later. Founder chose "Apply now, then commit."
   Verified live via `pg_trigger` (all 4 triggers present + enabled) and the full behavioral SQL
   test (7/7 passing).
2. **`ai-proxy` redeployed as version 79.** The currently-live (pre-batch) function code did not
   handle the new triggers' P0001 errors gracefully: chat's old bare INSERT would have thrown a
   raw uncaught error on the 11th message, and vision's old swallowed `catch (_) {}` would have
   silently discarded the trigger's rejection entirely — meaning the vision cap trigger, alone,
   would have been live in Postgres but functionally unenforced in production until the Edge
   Function caught up. Surfaced proactively and confirmed via `AskUserQuestion` rather than left
   as a silent gap or deployed unilaterally; founder chose "Deploy ai-proxy now." Boot-verified
   via an unauthenticated smoke test.

Both authorizations and their outcomes are recorded in `backups/applied_migrations.json` (entries
for 111/112/113) and this doc's `touched_layers_checked` tiers 5/6 above. The vulnerability
window OI-46 named is closed as of this commit, not merely prepared.
