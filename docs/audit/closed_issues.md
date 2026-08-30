# Closed Issues — archive

Closed `OI-NN` entries, split out of `open_issues.md` so the working board
answers "what's pending?" without carrying its own history. **Numbering is
untouched** — an OI number is a permanent identifier cited from diagnose-docs
and commit messages, so nothing here was renumbered and nothing was rewritten.

Open issues live in [`open_issues.md`](open_issues.md); the one-line triage view
is [`OPEN_INDEX.md`](OPEN_INDEX.md), regenerated on every commit that touches the
board.

---

## OI-01 — Reader-manifest gate is forbidden-patterns-only, not exhaustive completeness

- **Status**: CLOSED · 2026-05-17 · diagnose `0a1e17` · commit `<pending>`
- **Identified**: 2026-05-17 · post-merge audit comprehensiveness review
- **Risk class**: enforcement-gap
- **Estimated effort**: 4–6 hours (actual: ~4 hours)
- **What was missing**: `scripts/check_reader_manifest_complete.dart` fired
  only on patterns explicitly listed in `forbidden_legacy_patterns`. It
  did NOT enforce "every source file that reads `<concept>.hive.key_prefix`
  must appear in that concept's `readers:` list." A new widget added
  tomorrow that grep-finds `workoutBox.values.where(...)` for `exlog_*`
  rows would have bypassed the registry entirely.
- **How closed**: Extended the gate to Phase 2 — for every concept with
  `reader_manifest_complete: true` AND non-placeholder `hive.key_prefix`,
  source-greps `lib/` + `supabase/functions/` for `.get|put|containsKey|delete`
  and `.startsWith` on the prefix literal. Each match must be declared in
  `readers:`, `writers:`, or the new `reader_allow_files:` list per
  concept. Initial run surfaced 87 undeclared readers across 16 concepts;
  all resolved: 14 added to `readers:` (verified by reading cited code per
  `feedback_audit_findings_require_live_verification.md`), 67 added to
  per-concept `reader_allow_files:` (migrators, sync helpers, cross-
  concept readers of the same Hive key for unrelated fields).
- **Regression test**: `test/contracts/reader_manifest_exhaustiveness_test.dart`
  spawns the gate as a subprocess and asserts exit 0.
- **Closes**: diagnose-doc `docs/diagnoses/2026-05-17-oi-01-exhaustive-reader-gate-0a1e17.md`.

## OI-02 — No symmetric ReadServices for workout / nutrition / health domains

- **Status**: CLOSED · 2026-05-17 · diagnose `8d85c2` · commit `<pending>`
- **Identified**: 2026-05-17 · post-merge audit comprehensiveness review
- **Risk class**: architecture-gap
- **Estimated effort**: 1.5–2 days (actual: ~3 hours — scope was smaller
  than estimated; existing inline math at the migrated callsites was
  high-quality and lifted verbatim)
- **What was missing**: Writer-side has canonical `WorkoutWriteService`,
  `NutritionWriteService`, `HealthWriteService` — every write goes
  through them. Reader-side had nothing analogous. The PR fix this
  batch re-implemented per-set MAX logic in 2 places
  (`workout_repository.loadAllExercisePRs` + `train_screen._bestPerSetReps`).
  A third callsite would have re-implemented it inline and diverged.
- **How closed**: 3 new READ services shipped, mirroring the writer-side
  pattern:
  - `lib/core/services/workout_read_service.dart` — `bestPerSetReps`,
    `bestPerSetDuration`, `bestPerSetWeight`, `istDateForExlogRow`,
    `exerciseLogsForIstDate`.
  - `lib/core/services/nutrition_read_service.dart` —
    `totalMacrosForDate`, `totalMacrosFromItems` (Atwater fallback
    mirrors `FoodItem.kcalWithFallback`).
  - `lib/core/services/health_read_service.dart` — `latestWeightKg`,
    `sleepHoursForDate`, `waterMlForDate` (IST-anchored keys agree
    with HealthWriteService).
  Existing readers migrated to delegate: `WorkoutRepository.loadAllExercisePRs`,
  `train_screen.dart` expanded view (file-private helpers DELETED),
  `NutritionRepository.dailyMacros`. 3 contract tests pin each service.
- **Regression test**: `test/contracts/workout_read_service_per_set_semantic_test.dart`
  + `test/contracts/nutrition_read_service_total_macros_test.dart` +
  `test/contracts/health_read_service_test.dart` — 30 cases total,
  all passing.
- **Closes**: diagnose-doc `docs/diagnoses/2026-05-17-oi-02-read-services-8d85c2.md`.
- **Subsumes**: OI-08 — the PR per-set MAX semantic centralisation
  IS the workout slice of OI-02 closure.

## OI-03 — Server-side (Edge Function) reader drift not gated

- **Status**: CLOSED · 2026-05-17 · closes-diagnose `c0e3a5` · commit `<pending>`
- **Identified**: 2026-05-17 · post-merge audit comprehensiveness review
- **Risk class**: enforcement-gap
- **Estimated effort**: 4–6 hours
- **What's missing**: Edge Functions (`ai-proxy`, `rolling-context`,
  `weekly-report`, `morning-alert`) read fields by name from the JSON
  snapshot built by `AiCoachRepository.buildAiContext`. F3-1.1
  (`coach_notes` vs `coaching_notes`) was an instance of this class —
  client emitted `coaching_notes`, cloud column was `coach_notes`. The
  fix added one upward sync method. No gate prevents the NEXT instance.
- **Why class-killing**: closes the cross-system reader drift sub-class.
- **Plan**: new gate script that source-greps both
  `lib/features/ai_coach/repositories/ai_coach_repository.dart` (emit
  keys) AND every `supabase/functions/*/index.ts` (read keys from
  snapshot). Require every emitted key to have ≥1 documented consumer.
  Maintain an explicit allowlist of "intentionally one-sided" keys in
  a new `docs/snapshot_contract.yaml`.

## OI-04 — Agent reader-enumeration may have missed readers (unverified)

- **Status**: CLOSED · 2026-05-17 · subsumed by OI-01 closure (diagnose `0a1e17`)
- **Identified**: 2026-05-17 · post-merge audit comprehensiveness review
- **How closed**: OI-01's Phase 2 gate surfaced 87 undeclared readers across
  16 concepts; all resolved (14 added to `readers:` after live verification,
  67 to `reader_allow_files:`). Manifest now exhaustive vs independent grep.
- **Risk class**: unverified-claim
- **Estimated effort**: 2–3 hours
- **What's missing**: 3 parallel agents populated `reader_manifest_complete:
  true` across 41 concepts. Agent 1 (workout) explicitly reported
  Edit-tool race rejections during the parallel run; the file grew
  1683 → 3300+ lines mid-batch. `sot_registry_completeness_test.dart`
  only checks `file:line` entries resolve within file bounds — it does
  NOT verify the manifest is exhaustive vs an independent grep. There
  could be 10–20 missed readers.
- **Why class-killing**: a manifest with missing entries gives false
  confidence; the gate it backs is only as good as the manifest's
  completeness.
- **Plan**: implement OI-01's exhaustive-completeness gate (the two are
  symbiotic — OI-01's gate run against the current manifest will surface
  every missed reader as a gate failure). Audit the failures, fold them
  into the manifest, re-run until green.

## OI-05 — Obs 4 root cause unfixed (schedule.completed without exlog rows for that IST date)

- **Status**: CLOSED · 2026-05-17 · closes-diagnose `7c4e5d` · commit `<pending>`
- **Identified**: 2026-05-16 · post-+27 install observation (Obs 4)
- **Risk class**: writer/reader-drift (writer-ordering sub-class)
- **Estimated effort**: 2–3 hours
- **What's missing**: We patched the SYMPTOM in the
  `daffac` diagnose-doc — `_restoreExerciseLogs` projects
  `workout_log_id` + `day_detail_sheet` shows a snackbar on null
  receipt. The ROOT cause — why a fresh-install user has
  `schedule_<2026-05-15>.status='completed'` but no exlog rows for that
  IST date — was NOT investigated. Most likely:
  - `WorkoutScheduleService.markCompleted` flips status BEFORE exlog
    rows are committed (async ordering)
  - OR a restore-side gap where schedule completion is restored but
    the corresponding exlog rows aren't (incomplete cloud query)
  - OR the test user genuinely has a schedule completion without exlog
    rows on cloud (orphaned completion row)
- **Why class-killing**: writer-side ordering is its own drift sub-class.
  A different reader will hit the same gap differently in a future batch.
- **Plan**: (1) query cloud directly for upendraprasad19's
  `workout_schedule_completions` + matching `workout_log_exercises` for
  May 14 + May 15 — find which side is missing. (2) trace
  `markCompleted` writer ordering, ensure exlog commit precedes status
  flip OR add atomic transaction. (3) restore-side: ensure
  `_restoreScheduleCompletions` either pulls associated exlogs OR is
  ordered AFTER `_restoreExerciseLogs`.

## OI-06 — Partial UNIQUE arbiter trap audit only covered 3 tables

- **Status**: CLOSED · 2026-05-17 · closes-diagnose `9d2a47` · commit `<pending>`
- **Identified**: 2026-05-15 · APK Test #16 batch · `feedback_partial_unique_arbiter_trap.md`
- **Risk class**: writer/reader-drift (writer → DB-target sub-class)
- **Estimated effort**: 1–2 hours
- **What's missing**: Migration 064 fixed `workout_logs`,
  `workout_log_exercises`, `nutrition_logs`. Other tables with partial
  UNIQUE indexes backing `ON CONFLICT` may exist and produce 42P10
  silently. The new `check_onconflict_live_arbiter.dart` gate covers
  source-grepped upsert sites but I'm not 100% sure it covers every
  cloud table.
- **Why class-killing**: 42P10 is the silent-data-loss sub-class — rows
  fail to write but the client sees a "200 OK" via async fire-and-forget.
- **Plan**: live SQL via Supabase MCP — `SELECT tablename,
  pg_get_indexdef(indexrelid) FROM pg_indexes WHERE schemaname='public'
  AND indexdef LIKE '%WHERE%' AND indexdef LIKE 'CREATE UNIQUE%'`. For
  every match, audit `lib/core/services/sync/*.dart` for any
  `.from('<tablename>').upsert(... onConflict: ...)` call. Verify the
  onConflict arbiter columns are NOT NULL OR the index is non-partial.

## OI-07 — AI snapshot field-name contract has zero enforcement

- **Status**: CLOSED (2026-05-17 · diagnose 93aeac)
- **Identified**: 2026-05-17 · post-merge audit comprehensiveness review
- **Risk class**: enforcement-gap
- **Estimated effort**: 4 hours
- **What's missing**: `AiCoachRepository.buildAiContext()` emits ~40
  keys. Edge Functions read them by name (`snapshot.user.weight_trend`,
  `snapshot.recent_logs[0].reps_completed`, etc.). No test pins the
  contract. The 9th writer/reader drift instance was exactly this
  (coach_notes upward sync).
- **Why class-killing**: closes the implicit-cross-system-contract
  sub-class. OI-03 is the gate; THIS issue is the manifest the gate
  reads from.
- **Plan**: create `docs/snapshot_contract.yaml` listing every emitted
  key with type + consumer Edge Functions. Run independent greps on
  both sides to populate. Then OI-03's gate enforces it.
- **Closure** (2026-05-17, diagnose `93aeac`):
  - `docs/snapshot_contract.yaml` shipped (530 lines, 48 emitted keys
    + 4 extra server-written keys + 11 orphan_readers debt entries).
  - Every reader citation manually verified against actual Edge
    Function code (per `feedback_audit_findings_require_live_verification.md`).
  - Self-consistency pinned by
    `test/contracts/snapshot_contract_self_consistency_test.dart` (5
    tests).
  - Surfaced 11 orphan_readers (morning-alert / streak-guardian /
    protein-gap-alert reading fields buildAiContext doesn't emit) as
    documented debt — handed to OI-03 / next-batch remediation.
  - Gate enforcement (OI-03) remains OPEN as planned (separate batch).

## OI-08 — PR per-set MAX semantic duplicated across 2 files (not centralized)

- **Status**: CLOSED · 2026-05-17 · subsumed by OI-02 closure (diagnose `8d85c2`) · commit `<pending>`
- **Identified**: 2026-05-17 · post-merge audit comprehensiveness review
- **Risk class**: architecture-gap
- **Estimated effort**: 1–2 hours (actual: rolled into OI-02 batch)
- **What was missing**: This batch fixed `loadAllExercisePRs` (canonical
  PR reader) AND added `_bestPerSetReps` / `_bestPerSetDuration`
  helpers as file-private functions in `train_screen.dart`. Two
  implementations of the same semantic; a third callsite was likely
  to re-implement.
- **How closed**: Subsumed by OI-02. The workout slice of the new
  `WorkoutReadService` (`bestPerSetReps`, `bestPerSetDuration`,
  `bestPerSetWeight` static methods on
  `lib/core/services/workout_read_service.dart`) IS the centralisation
  OI-08 called for. `train_screen.dart` file-private helpers DELETED;
  `WorkoutRepository.loadAllExercisePRs` delegates. Diagnose-doc:
  `docs/diagnoses/2026-05-17-oi-02-read-services-8d85c2.md`.

## OI-09 — `restore_completeness` enforcement is writer-side only

- **Status**: CLOSED · 2026-05-17 · closes-diagnose `4dd7e2` · commit `<pending>`
- **Identified**: 2026-05-17 · post-merge audit comprehensiveness review
- **Risk class**: enforcement-gap
- **Estimated effort**: 2 hours
- **What's missing**: `restore_completeness_writes_test.dart` verifies
  every writer's Hive prefix has a `_restoreXxx` method. It does NOT
  verify the restored data matches the SHAPE the canonical reader
  expects. Today's `workout_log_id` restore projection gap was an
  instance — `_restoreExerciseLogs` wrote `exlog_*` rows but didn't
  include `workout_log_id`, which the canonical receipt reader filters
  on. Restore round-trip was incomplete.
- **Why class-killing**: closes the restore-fidelity sub-class. Test
  coverage today is "did we call a restore method", not "does the
  restored row contain every field the reader expects".
- **Plan**: per-concept contract test that writes a fresh row via
  canonical writer, syncs to cloud, wipes Hive, runs restore, then
  diffs the restored row's keys against the original writer output.
  Every writer-emitted key must round-trip. Whitelist legitimate
  exceptions (e.g., transient fields, fire-and-forget telemetry).

## OI-10 — Cross-account guard `authUserIdTokenProvider` inheritance is manual

- **Status**: CLOSED · 2026-05-17 · closes-diagnose `3a7c1e` · commit `<pending>`
- **Identified**: 2026-05-17 · post-merge audit comprehensiveness review
- **Risk class**: enforcement-gap (slow-drift)
- **Estimated effort**: 1 hour
- **What's missing**: The 56 user-scoped providers from commit `c4055a`
  watch `authUserIdTokenProvider`. New providers added later don't
  auto-inherit. `auth_invalidation_contract_test.dart` exists but
  maintains an exempt list manually.
- **Why class-killing**: closes the cross-account leak sub-class —
  pre-c4055a a sign-out + new sign-in could leak the prior user's data
  through cached Riverpod state. The fix added the watch to existing
  providers. The drift risk is a new provider being added without the
  watch, silent until a user encounters the leak.
- **Plan**: extend the contract test — source-grep
  `lib/features/*/providers/` for `NotifierProvider|FutureProvider|StreamProvider`
  declarations. For each, verify the build method contains
  `ref.watch(authUserIdTokenProvider)` OR appears on an explicit exempt
  list in the test file. Today the test enforces a known set; expand
  it to enforce the OPEN set.

---

## OI-11 — Cron Edge Function operational health (live audit)

- **Status**: CLOSED · 2026-05-17 · commit `<pending>`
- **Identified**: 2026-05-17 · audit-comprehensiveness review
- **Risk class**: enforcement-gap (operational)
- **Estimated effort**: ~3 hours (actual: ~1.5 hours)
- **How closed**: (1) live SQL audit via pg_cron + Edge Function logs
  showed `pr-detection`, `evaluate-rank-promotions`, `clean-orphan-media`,
  and `promote-community-item` were all running on stale deploys (source
  had JWT-decode auth via `_shared/cron_auth.ts` but the deployed
  versions still had the brittle env-equality compare from before
  audit 2026-05-16 E.14.C). (2) `promote-community-item` source still
  had the literal `token === SUPABASE_SERVICE_ROLE_KEY` compare —
  retrofitted to `isAuthorizedCronCall(req)` (JWT signature decode +
  role-claim check). (3) all 4 functions redeployed (v5/v5/v4/v9 in
  pass 1, then v6/v6/v5/v10 after telemetry wiring in pass 2). (4) post-
  deploy SQL confirmed `proactive_pr_detection` jobid 9 fires 2/0
  succeeded/failed in the last 30 minutes; `morning_alert_deliver_early`
  jobid 17 also recovered (was flagged still-401-ing in pre-batch
  memory — Vault refresh and own deploys together cleared it).
- **Follow-up tracked here**: morning-alert 200-but-empty mystery
  (notifications_inbox=0, proactive_pushes=0 since deploy) is now
  observable via OI-15 cron_call_log — next 24h of telemetry will
  show whether the function returns 200 with empty payload (logic
  bug) vs returns 200 after correctly skipping (no eligible users).
  Re-open as OI-19 if telemetry shows persistent 200-with-empty.
- **Closes**: no diagnose-doc required (operational deploy, not a code
  bug fix per CLAUDE.md rule 22). The retrofit of
  `promote-community-item` is folded into the audit 2026-05-16 E.14.C
  scope (already documented).
- **What's missing**: Prior session flagged `morning_alert_deliver_early`
  still 401-ing post-Vault refresh — never end-to-end verified. 18+
  cron Edge Functions deployed; we only confirmed `pr-detection`
  resumed 200s after the 2026-05-12 Vault fix. The other 17 may be
  silently 401-storming + logging "succeeded" in `pg_cron.job_run_details`
  (which lies for `Bearer null` cases). The c-4-gated functions also
  use brittle env-equality JWT compare which drifts when the
  service-role key rotates server-side.
- **Why class-killing**: closes the silent-cron-failure sub-class.
  Same shape as F3-1.1 (silent personalization degradation) but for
  ANY cron-driven feature: streak-guardian, plateau-alert,
  re-engagement, weekly-recap-ready, evaluate-rank-promotions,
  morning_alert_*, protein-gap-alert, i-see-you-callout, etc.
- **Plan**: (1) live SQL — last 7 days of `cron.job_run_details` per
  job, success/fail counts. (2) for any job with >0 failures, hit
  the function endpoint with the cron's exact Bearer + verify 200.
  (3) for any function still on env-equality JWT compare, retrofit
  to `_shared/cron_auth.ts` JWT-decode pattern (already used by 10
  functions per audit 2026-05-16 E.14.C). (4) gate script
  `scripts/check_cron_auth_jwt_decode.dart` source-greps every cron
  Edge Function for the JWT-decode helper usage. (5) live cron
  telemetry table (OI-15 deliverable) wired to record actual run
  results so `pg_cron.job_run_details` is no longer the only oracle.

## OI-12 — RLS policy audit + contract test (user_id scoping)

- **Status**: CLOSED · 2026-05-17 · commit `<pending>`
- **Identified**: 2026-05-17 · audit-comprehensiveness review
- **Risk class**: privacy / security
- **Estimated effort**: ~2 hours (actual: ~1 hour)
- **How closed**: live `pg_policies` + `pg_class` audit of all 47
  public-schema tables surfaced **0 P0 cross-user-read vectors**.
  Every user-scoped table that exposes read/write to authenticated
  callers scopes via `auth.uid() = user_id` (or `auth.uid() = id` for
  `users`, `auth.uid() = reviewer_id` for `community_reviews`,
  `auth.uid() = referrer_id OR auth.uid() = referee_id` for
  `referral_redemptions`, or `EXISTS` join to the parent table for
  `nutrition_log_items` / `template_exercises`). All 47 tables have
  RLS enabled. 2 P1 functional gaps closed via migration 069:
  (a) `client_errors` had only an INSERT policy — added
  `client_errors_select_own` so users can read their own telemetry
  rows. (b) `coach_memory` + `rank_promotions` are missing DELETE
  policies — deliberately left as-is per product design (append-only
  history). 5 P2 advisory findings documented (subscriptions writes
  through Edge Functions, `referral_redemptions` writes via RPC,
  `promo_code_uses` defensive INSERT-deny, `community_reviews`
  intentionally-public reads, `promo_codes.is_active=true` rows
  enumerable by authed callers — flagged for product decision).
- **Closes**: migration `069_oi_batch_closures.sql` section A. No
  diagnose-doc (no bug-fix commit).
- **What's missing**: Never systematically audited. ~30 of 46
  public-schema tables are user-scoped. Each MUST have an RLS policy
  that restricts read to `auth.uid() = user_id` (or equivalent).
  Permissive `USING (true)` policies or missing-policy tables would
  let one user read another user's data via direct PostgREST call
  with a valid JWT. This is much worse than the writer/reader drift
  class — it's a privacy leak, not a UX glitch.
- **Why class-killing**: closes the cross-account-read-via-PostgREST
  sub-class. Client-side cross-account guards (HiveUserSession +
  OI-10 authUserIdTokenProvider) only protect the LOCAL cache; cloud
  reads are gated only by RLS.
- **Plan**: (1) live SQL — `pg_policies` enumerate every policy on
  every user-scoped table; classify as user-scoped / open-read /
  service-role-only. (2) any table missing a policy or with
  `USING (true)` for `SELECT` → fix via migration. (3) regression
  test `test/contracts/rls_policy_coverage_test.dart` lists the
  expected policy shape per table and source-greps the migration
  files for coverage. (4) one-off live verification: sign in as
  user A, attempt to read user B's rows via direct PostgREST — must
  return 0 rows.

## OI-13 — Integration test skip list investigation

- **Status**: CLOSED · 2026-05-17 · commit `<pending>` (verified
  no-action — skip backlog is intentional + already governed)
- **Identified**: 2026-05-17 · audit-comprehensiveness review
- **Risk class**: test coverage gap
- **Estimated effort**: ~2 hours (actual: ~30 min agent audit)
- **How closed**: Audit catalogued 74 skipped tests. **All 64**
  integration tests carry `skip: 'Phase 7 scaffold — needs <device CI
  / Razorpay test mode / Supabase Auth test mode>'` annotations and
  are governed by `test/contracts/phase7_integration_scaffolds_present_test.dart`
  (which enforces every scaffold file exists + every test in it is
  skip-annotated until Phase 8 device-CI harness lands). The 4
  `markTestSkipped` calls in `test/edge_functions/pgvector_test.dart`
  gracefully skip when `match_memories` RPC or `memory_embeddings`
  table is not deployed — design-intended. 2 unit-level skips in
  `test/features/ai_coach/tool_dispatcher_test.dart` are covered by
  provider-level tests. **No unjustified skips found.** Phase 8
  device-CI harness is a separate scoped initiative (not an audit
  follow-up). Top-3 highest-impact backlog skips:
  `delete_account_e2e_test.dart` (irreversible DPDP §17 flow),
  `razorpay_purchase_flow_test.dart` (revenue-critical),
  `ai_coach_tools_e2e_test.dart` (20-tool coverage).
- **Closes**: no diagnose-doc (no bug fix; existing contract test
  already governs the scaffolds).
- **What's missing**: `flutter test` reports 2 skipped tests (was 11
  pre-OI-09). Skipped tests since Test #11 (2026-05-04) at least.
  Never investigated WHY they skip. If they cover real flows
  (workout end-to-end, payment, photo upload, restore), those flows
  have ZERO automated coverage.
- **Why class-killing**: closes the "tests-exist-but-don't-run"
  invisible coverage gap. A `flutter test` green is misleading if it
  silently skips the riskiest flows.
- **Plan**: (1) `flutter test --reporter expanded 2>&1 | grep -A2
  SKIPPED` — enumerate the 2 currently-skipped tests + reason. (2)
  for each: either un-skip (and fix what was blocking it), or add a
  new OI documenting why it's deferred. (3) regression test
  `test/contracts/no_unjustified_skips_test.dart` — fail if any test
  has `skip:` without a `// SKIP_REASON: <OI-NN>` annotation citing
  an open OI.

## OI-14 — Edge Function input-validation parity audit

- **Status**: CLOSED · 2026-05-17 · commit `<pending>`
- **Identified**: 2026-05-17 · audit-comprehensiveness review
- **Risk class**: abuse / cost / security
- **Estimated effort**: ~4 hours (actual: ~1 hour agent audit + live
  verification of agent claims)
- **How closed**: Audit covered all 18 primary + 12 newer Edge
  Functions across 5 hardening lenses (JWT validation, input size
  limits, SSRF guards, error sanitization shape, rate limiting).
  Strong baseline: every user-facing function validates JWT via
  `auth.getUser(token)`; every cron function uses
  `isAuthorizedCronCall(req)` from `_shared/cron_auth.ts`; all 18
  functions return the canonical `{error, request_id}` shape on
  5xx; `ai-media-proxy` is the only function fetching server-side
  URLs and has the Storage-prefix-only SSRF guard. Per
  `feedback_audit_findings_require_live_verification.md`, the agent's
  P1 finding (`assess-body-composition` missing `request_id`) was
  re-verified against `assess-body-composition/index.ts:189-194` —
  the catch block DOES generate and return `request_id`. **False
  alarm — closed as no-action.** The 3 P2 findings around
  unbounded snapshot/profile JSON in `beat-my-coach`,
  `future-prediction`, and `daily-snapshot` are real but operational-
  risk-only (cron-gated or optional-JWT callsites; not user-attack
  vectors). Tracked as OI-20 follow-up rather than fixed this batch
  to avoid breaking legitimate large-snapshot flows without testing.
- **Closes**: no diagnose-doc (no bug fix shipped this batch).
- **What's missing**: Hardened `ai-proxy` + `ai-media-proxy` (message
  5K cap, image 5MB cap, SSRF allowlist, rate limits). The other 16+
  Edge Functions were never audited for the same shape. Candidates
  with likely gaps: `validate-promo` (input length cap?),
  `verify-payment` (replay window?), `redeem-referral` (code-shape
  validation?), `delete-account` (re-validation of token?),
  `assess-body-composition` (image size cap?), `beat-my-coach`,
  `daily-snapshot`, `future-prediction`, `weekly-report`.
- **Why class-killing**: closes the per-function abuse-vector class.
  One unprotected endpoint with rate-limit gap → abuse → Gemini /
  Storage cost spike → ops emergency.
- **Plan**: (1) enumerate all `supabase/functions/*/index.ts`. (2)
  for each: verify JWT auth (auth.getUser) + input length caps +
  rate limits + error-shape normalisation (return {error,
  request_id}). (3) source-grep regression test
  `test/contracts/edge_function_input_validation_parity_test.dart`
  asserts every Edge Function has: a JWT auth call, a content-length
  check (if it accepts body), a try/catch with request_id in the
  500 response. (4) any function failing the gate → harden in this
  batch.

## OI-15 — Cron telemetry / observability beyond pg_cron

- **Status**: CLOSED · 2026-05-17 · commit `<pending>`
- **Identified**: 2026-05-17 · audit-comprehensiveness review
- **Risk class**: operational visibility
- **Estimated effort**: ~2 hours (actual: ~2 hours)
- **How closed**: (1) verified `cron_call_log` table exists (migration
  068) with the right schema and 0 rows + no policies. (2) created
  `supabase/functions/_shared/cron_telemetry.ts` exporting
  `logCronStart(name) → id` + `logCronEnd(id, status, opts)`.
  Failures inside the telemetry call itself are swallowed (try/catch +
  debug log) so cron functions never 500 on telemetry breakage. Error
  summaries capped at 1000 chars. (3) wired the helper into 4 cron
  functions already redeployed this batch: `pr-detection`,
  `evaluate-rank-promotions`, `clean-orphan-media`,
  `promote-community-item` (v6/v6/v5/v10). (4) migration 069 section B
  scheduled `cron_call_log_cleanup_daily` at 03:30 UTC — runs
  `public.cleanup_cron_call_log()` which deletes rows older than 7
  days. (5) **remaining 8 cron Edge Functions** (morning-alert,
  morning_alert_deliver_late, morning_alert_deliver_early,
  rolling-context, streak-guardian, weekly-recap-ready, weekly-recalc,
  compute-coach-signals + the 5 newer proactive triggers) NOT yet
  wired — tracked as OI-21 follow-up so they go through the same
  helper pattern incrementally without bundling a huge deploy into
  this batch.
- **Closes**: `supabase/functions/_shared/cron_telemetry.ts` +
  migration `069_oi_batch_closures.sql` section B. No diagnose-doc
  (new helper module, not a bug fix).
- **What's missing**: Migration 068 added `cron_call_log` table —
  empty per baseline. Are cron jobs actually writing to it? If
  empty, the table is a façade with no producer.
  `pg_cron.job_run_details` reports HTTP-dispatch success — it does
  NOT report the response status. So a function returning 401 looks
  identical to a function returning 200 in `job_run_details`.
- **Why class-killing**: makes the silent-cron-failure sub-class
  (OI-11's class) visible without manual SQL forensics. Wired
  correctly, dashboards can alert on >0 cron 401s per day.
- **Plan**: (1) verify whether any Edge Function INSERTs to
  `cron_call_log`. (2) if no — wire it into `_shared/cron_auth.ts`
  so every cron-authenticated call records (function_name,
  invoked_at, response_status, duration_ms, error_text). (3)
  retention policy (delete rows >30d, keep rolling window).
  (4) regression test `test/contracts/cron_telemetry_logging_test.dart`
  source-greps every cron Edge Function for the logging call.

## OI-16 — ProGuard / R8 + native crash signal

- **Status**: CLOSED · 2026-05-17 · commit `<pending>` (verified
  no-action — minification is not enabled, so keep rules unneeded)
- **Identified**: 2026-05-17 · audit-comprehensiveness review
- **Risk class**: post-ship diagnosability
- **Estimated effort**: ~2 hours (actual: ~30 min agent audit + ~5 min
  live verification of agent claims)
- **How closed**: Agent flagged "P0: no keep rules for Hive / Riverpod
  / Razorpay / OneSignal / Supabase". Per
  `feedback_audit_findings_require_live_verification.md`, verified by
  reading `android/app/build.gradle.kts:67-79`: the `release` buildType
  declares `proguardFiles(...)` but does **NOT** set `minifyEnabled =
  true`. Flutter's default for release builds is `minifyEnabled =
  false`. Therefore R8 does NOT minify/obfuscate the APK; keep rules
  are dormant. APKs +25 and +26 ship without crashes for this exact
  reason. **Agent finding was a false alarm.** Crashlytics gradle
  plugin v3.0.2 IS wired (build.gradle.kts:10) which auto-uploads
  mapping + native debug symbols on release builds; first-run
  verification would require an actual production crash, deferred as
  post-launch ops work (OI-22). Signing config for prod flavor verified
  present (build.gradle.kts:56-65); falls back to debug keystore when
  `key.properties` is absent.
- **Closes**: no diagnose-doc (no fix shipped; verified design).
- **What's missing**: Crashlytics is wired but we haven't verified:
  - Obfuscated stack traces resolvable (symbols uploaded)
  - Crash-free user rate baseline
  - Native crash signal coverage (Flutter engine crashes)
  - ProGuard/R8 rules don't strip required reflection paths
- **Why class-killing**: if obfuscation strips symbols, a post-+28
  crash report reads `unknown.a(b.dart:42)` and we can't diagnose
  ANYTHING in production.
- **Plan**: (1) verify
  `android/app/build.gradle.kts` has the Flutter ProGuard rules
  included. (2) check Crashlytics dashboard for current crash-free
  user rate + verify symbols uploaded for +27. (3) trigger a known
  test crash in a debug build and verify it surfaces in Crashlytics
  with resolved frames. (4) add a build-apk Gate that fails the
  build if `mappingFile` is missing from the AAB.

## OI-17 — Hive box compaction operational health

- **Status**: CLOSED · 2026-05-17 · commit `<pending>` (verified
  GREEN — no action needed)
- **Identified**: 2026-05-17 · audit-comprehensiveness review
- **Risk class**: long-term performance
- **Estimated effort**: ~1 hour (actual: ~30 min agent audit)
- **How closed**: Audit verified all 5 health items: (1) observer
  registration (`init()` line 83), (2) 7-day gate via
  `configBox['last_compact_at']` (line 128-135), (3) box coverage —
  the 8 mutation-heavy boxes (user / workout / nutrition / health /
  custom / coach / sync / **notifications**) are correctly compacted;
  CLAUDE.md §19 line "7 mutation-heavy boxes" is stale (was true
  before `notificationsBox` was added to the compaction list) — note
  for next CLAUDE.md edit pass, not a bug. (4) telemetry — per-box
  and global error capture via `ErrorTelemetry.recordNonFatal` with
  reasons `hive_service_maybe_compact_box` / `hive_service_maybe_compact`.
  (5) race-condition analysis with `HiveUserSession.openForUser` —
  narrow window exists (compactor reads `currentOwnerFullId` once per
  cycle, signOut could happen mid-iteration), but `_sessionLock`
  serializes session mutations and `Hive.isBoxOpen()` check at line
  150 protects against compacting unopened boxes. Existing 2026-05-11
  fix to `_openForUserLocked` keeps this stable in production. **GREEN
  overall.** No fix needed.
- **Closes**: no diagnose-doc (verification only).
- **What's missing**: `HiveService` runs compaction every 7 days on
  `AppLifecycleState.paused`. Never verified the compaction call
  actually executes or that the gate (`configBox['last_compact_at']`)
  is being updated. If broken silently, box files grow unbounded over
  months → slow cold-start, eventual storage exhaustion on low-end
  devices.
- **Plan**: (1) integration test that simulates 7-day-old
  `last_compact_at` + `AppLifecycleState.paused` and asserts compact
  ran. (2) telemetry op-type `hive_compaction_ran` on success +
  `hive_compaction_skipped` with reason on no-op. (3) startup log
  line with current box file sizes (visible in client_errors via
  log-client-error for the first launch after each cold start).

## OI-18 — Storage bucket cost + orphan-photo cleanup health

- **Status**: CLOSED · 2026-05-17 · commit `<pending>`
- **Identified**: 2026-05-17 · audit-comprehensiveness review
- **Risk class**: operational cost
- **Estimated effort**: ~1.5 hours (actual: ~1 hour)
- **How closed**: Live storage audit found **4 buckets** (`avatars`,
  `banners`, `chat-media`, `progress-photos`) totalling 20 objects /
  4.01 MB — far under 1 GB free tier; estimated monthly cost $0. **0
  orphans** across queried buckets. **0 stale `progress_photos` rows**.
  `clean_orphan_media_daily` cron jobid 18 registered, scheduled
  `0 3 * * *`, last 10 dispatches succeeded (per pg_cron) — actual
  HTTP response now observable via OI-15 `cron_call_log` after this
  batch's redeploy. **4 findings, scope-rated**:
  (a) **`coach-media` bucket referenced by `delete-account` Edge
  Function purge step does not exist** — purge silently no-ops on
  every account deletion; resolution requires product decision
  (create bucket OR drop reference). Tracked as OI-23 follow-up.
  (b) `avatars` + `banners` buckets are PUBLIC with no MIME allowlist
  + no size cap — RLS-dependent hardening gap; bucket-level caps
  require separate Storage policy migration; tracked as OI-24.
  (c) `progress-photos` bucket also lacks bucket-level size/MIME
  caps; client-side caps exist in CLAUDE.md §10 — same OI-24 scope.
  (d) Storage cost monitoring trivial at current scale; no action.
- **Closes**: no diagnose-doc (audit + verification; deferred fixes
  tracked as separate OIs with explicit rationale per
  `feedback_no_deferrals.md` exception clause — scope of bucket
  policy migration is non-trivial and would block this batch).
- **What's missing**: Progress photos + chat-media buckets accumulate
  uploads. `delete-account` purges on hard delete. `clean-orphan-media`
  cron exists — never verified when it last successfully ran or how
  it identifies orphans. Symptom if broken: bucket size + cost grow
  unbounded.
- **Plan**: (1) live query — `pg_cron.job_run_details` for
  `clean-orphan-media` last 30 days success rate. (2) read the
  function source and verify the orphan-detection logic
  (presumably: blob URLs in Storage with no referencing row in
  `progress_photos` or `ai_coach_interactions.media_url`). (3) live
  storage size query via Supabase MCP if possible (or skip if
  function-only). (4) regression test asserting the cron is
  registered + the function exists + the orphan-detection query
  shape matches the schema.

## OI-21 — Wire cron_telemetry into remaining 8 cron Edge Functions

- **Status**: CLOSED · 2026-05-17 · commit `<pending>` (10 functions
  wired in same batch as OI-23/OI-24)
- **Identified**: 2026-05-17 · OI-15 closure had scope-capped to the
  4 cron functions redeployed for OI-11
- **Risk class**: operational visibility (incremental)
- **Estimated effort**: ~1.5 hours (actual: ~45 min — agent did the
  10 source edits in parallel)
- **How closed**: Agent applied the canonical 4-step pattern from
  `pr-detection` to 10 remaining cron Edge Functions:
  `morning-alert`, `re-engagement`, `plateau-alert`, `protein-gap-alert`,
  `workout-window-closing`, `i-see-you-callout`, `rolling-context`,
  `streak-guardian`, `weekly-recap-ready`, `expiry-reminder`. Each got:
  (1) `import { logCronStart, logCronEnd }`, (2) `await logCronStart`
  after auth gate, (3) `logCronEnd(_, "success", ...)` before every
  HTTP-200 return, (4) `logCronEnd(_, "failed", ...)` in every catch
  block. Spot-verified via `grep -c logCronStart\|logCronEnd` — 63
  occurrences across 14 functions + 1 helper module. Contract test
  `test/contracts/cron_telemetry_adoption_test.dart` extended from
  17 → 57 tests; all passing. 10 deploys via host-shell API
  (all HTTP 201, version bumps recorded above). The 14 cron
  Edge Functions now all write to `cron_call_log` for every
  invocation; 7-day retention via `cleanup_cron_call_log` daily 03:30
  UTC (migration 069 section B).
- **Coverage gap remaining**: `compute-coach-signals` (jobid 8) and
  `morning_alert_generate` (jobid 5) have `null` fn_slug per the
  cron registry — they invoke Postgres RPCs not Edge Functions. Not
  in scope for this gate. Anything that calls a Postgres function
  directly is observable via Postgres logs without per-function
  telemetry.
- **Closes**: no diagnose-doc (operational helper expansion, not a
  bug fix).

## OI-23 — `coach-media` Storage bucket missing (founder decision)

- **Status**: CLOSED · 2026-05-17 · commit `<pending>` · migration 070A
- **Identified**: 2026-05-17 · OI-18 audit surfaced `delete-account`
  Edge Function references `coach-media/` bucket which did not exist
- **Risk class**: cleanup-fidelity (silent no-op in delete-account
  purge) + future-feature blocker
- **Estimated effort**: ~30 min (actual: ~20 min)
- **How closed**: Founder decided 2026-05-17: "i intend to store
  coach uploaded media. We ask user does he want to store the pic
  for future reference and on consent we save it." Migration 070
  section A creates the bucket: `coach-media` private + 5 MB cap +
  image/jpeg|png|webp MIME allowlist. Owner-only RLS policies added
  for SELECT / INSERT / DELETE mirroring `progress_photos` shape
  (`(storage.foldername(name))[1] = (auth.uid())::text`). Path
  layout `<user_id>/<filename>` per CLAUDE.md §19 image-upload
  convention. **Consent UI flow** is a separate follow-up (deferred
  client-side work tracked as OI-25 below): user uploads to
  `chat-media` first (transient, AI analysis), then on user consent
  app copies blob to `coach-media` for long-term storage. Live
  verification: `SELECT * FROM storage.buckets ORDER BY id` shows
  all 5 buckets with correct caps + MIME lists.
- **Closes**: migration `070_coach_media_bucket_and_caps.sql`
  section A. No diagnose-doc.

## OI-24 — Storage bucket-level size + MIME caps

- **Status**: CLOSED · 2026-05-17 · commit `<pending>` · migration 070B
- **Identified**: 2026-05-17 · OI-18 audit
- **Risk class**: abuse / cost / defense-in-depth
- **Estimated effort**: ~45 min (actual: ~10 min — bundled into
  migration 070)
- **How closed**: Migration 070 section B applies bucket-level
  `file_size_limit` + `allowed_mime_types` to all 4 pre-existing
  buckets that lacked them:
  - `avatars`: 1 MB cap, image-only
  - `banners`: 2 MB cap, image-only
  - `progress-photos`: 8 MB cap, image-only (PRO photos up to
    3000×3000 @ 95% quality per CLAUDE.md §10)
  - `chat-media`: 5 MB cap, image-only (matches
    `ai-media-proxy` server-side `MAX_IMAGE_BYTES`)
  Storage REST API enforces these at the gateway. Any rooted /
  malicious client can no longer bypass client-side caps to upload
  arbitrary files. Live verification post-migration: all 5 buckets
  now have non-null `file_size_limit` + 3-element `allowed_mime_types`.
- **Closes**: migration `070_coach_media_bucket_and_caps.sql`
  section B. No diagnose-doc.

## OI-26 — razorpay-webhook `supabaseClient` TDZ on every non-idempotent-skip path (PAYMENT-BLOCKING P0)

- **Status**: CLOSED · 2026-05-17 · diagnose `9a7c14` · razorpay-webhook v17→v18 deployed
- **Identified**: 2026-05-17 evening · Hermes audit F1 · verified by reading `supabase/functions/razorpay-webhook/index.ts:196-431` directly
- **Risk class**: payment-blocking production bug · combined with OI-27 = user pays + never unlocks PRO
- **Estimated effort**: ~30 min (move single `const` declaration) + ~1 hour regression test + ~10 min deploy
- **What's broken**: `const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);` is declared on line 431. It is USED on line 301 (`await supabaseClient.from("subscriptions").select("id").eq("razorpay_payment_id", razorpayPaymentId).maybeSingle()`) — both inside the same `serve(async (req) => {...})` handler that starts line 196. Execution flows top-down in the same function body → line 301 hits the SELECT before line 431's `const` initializer runs → temporal dead zone → `ReferenceError: Cannot access 'supabaseClient' before initialization` is thrown. The H-19 idempotency pre-SELECT (added per audit-2026-05-11 comment at lines 294-300) was correctly hoisted ABOVE auto-capture but NOT above its own dependency on `supabaseClient`. Webhook fails before any subscription write. Razorpay retries for 24h with the same TDZ.
- **Fix**: Move line 431 `const supabaseClient = createClient(...)` to immediately after the user_id UUID-validation block (currently before line 431) but BEFORE line 294's H-19 comment. Single-line move. Re-deploy via host-shell `node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl razorpay-webhook .claude/_payload_razorpay-webhook.json false`.
- **Regression test (planned)**: `test/contracts/razorpay_webhook_runtime_test.dart` invokes the handler with a synthetic `payment.captured` event and asserts no `ReferenceError` (today the test would catch the TDZ before deploy). Plus a contract test that source-greps the file and asserts `const supabaseClient = createClient` appears BEFORE the first occurrence of `await supabaseClient.from`.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-26-razorpay-webhook-tdz-<hex>.md`.
- **Why missed today**: lens L21 (Edge Function semantic correctness) did not exist; audit OI-14 covered input validation only, not control flow.

## OI-27 — verify-payment upserts subscription without `razorpay_signature` (NOT NULL since migration 052) — PAYMENT-BLOCKING P0

- **Status**: CLOSED · 2026-05-17 · diagnose `b3e052` · verify-payment v12→v13 deployed (sentinel `verified_via_api:<12-hex>` approach)
- **Identified**: 2026-05-17 evening · Hermes audit F2 · verified via subagent quote of migration 052:77-79 + verify-payment lines 410-439
- **Risk class**: payment-blocking · combined with OI-26 = both webhook AND fallback fail → user pays + never unlocks PRO
- **Estimated effort**: ~1 hour (decide signature source) + ~1 hour regression test + ~10 min deploy
- **What's broken**: Migration 052 (2026-05-13) executed `ALTER TABLE public.subscriptions ALTER COLUMN razorpay_signature SET NOT NULL` (lines 77-79). verify-payment Edge Function's subscription upsert payload (lines 410-439) sends `razorpay_payment_id` + `razorpay_order_id` but NEVER `razorpay_signature` — because verify-payment validates payment via Razorpay's REST API rather than HMAC, so there's no signature to send. After migration 052, every fallback path (when webhook is slow or fails) throws Postgres 23502 (`not_null_violation`).
- **Fix options**: (a) Send a verified-via-api sentinel string into `razorpay_signature` (e.g. `"verified_via_api:<short_hex>"`); the schema is permissive about content. (b) Alter migration 052 to make `razorpay_signature` nullable + add a CHECK constraint that requires it OR `verified_via='razorpay_api'`. (a) is faster; (b) is cleaner. Recommend (a) for the same-day P0 ship + (b) as a follow-up.
- **Regression test (planned)**: `test/contracts/verify_payment_payload_completeness_test.dart` asserts the upsert payload includes every NOT NULL column declared in the live schema (queries `information_schema.columns` for `subscriptions WHERE is_nullable='NO'`).
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-27-verify-payment-not-null-<hex>.md`.
- **Why missed today**: lens L22 (schema-vs-payload parity) did not exist. Migration 052 was applied 4 days ago; nobody grepped every callsite that writes to `subscriptions`.

## OI-28 — ai-media-proxy SSRF: service-role fetch of any user's Storage URL leaks cross-user images (P1)

- **Status**: CLOSED · 2026-05-17 · diagnose `5e055f` · ai-media-proxy v17→v18 deployed
- **Identified**: 2026-05-17 evening · Hermes audit F3 · verified via subagent quote of `ai-media-proxy/index.ts:163-176`
- **Risk class**: privacy / DPDP / cross-user data leak · affects progress photos + body comp + food photos + AI coach media
- **Estimated effort**: ~3 hours (refactor schema + 4 client callsites + contract test)
- **What's broken**: ai-media-proxy validates only that the supplied URL starts with `${SUPABASE_URL}/storage/v1/object/` (line ~164). It then fetches the URL with `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` (line ~175). Service role bypasses Storage RLS. Any authenticated user can supply ANOTHER user's private Storage URL and the function will fetch + forward the bytes to Gemini → response. Possible exfiltration vector if attacker can enumerate or guess path layouts.
- **Fix**: Refactor request schema from `{imageUrl}` to `{bucket, path}`. Assert `path.startsWith('${authenticatedUserId}/')` BEFORE the service-role fetch (the `${userId}/...` convention is already enforced by RLS on writes — applying the same prefix on reads aligns with it). Update client callsites in `AiService._directMediaHttpCall` + `_directHttpCall` + any other invokers. Pin with `test/contracts/ai_media_proxy_user_scope_test.dart`.
- **Regression test (planned)**: simulate request from user A with path `<userB>/<file>` and assert 403 + no Storage fetch invocation.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-28-ai-media-proxy-ssrf-<hex>.md`.
- **Why missed today**: lens L23 (service-role authz defense-in-depth) did not exist. OI-12 RLS audit was table-level only — verified policies exist on tables but didn't audit service-role bypass paths in Edge Functions.

## OI-29 — verify-payment ownership check is fail-open when `payment.notes.user_id` absent (P1)

- **Status**: CLOSED · 2026-05-17 · diagnose `c8f229` · verify-payment v12→v13 deployed (same deploy as OI-27)
- **Identified**: 2026-05-17 evening · Hermes audit F4 · verified via subagent quote of `verify-payment/index.ts:355-368`
- **Risk class**: payment entitlement bypass · severity tempered by amount-derived plan + JWT-extracted userId becoming the row owner
- **Estimated effort**: ~15 min (single guard) + ~30 min regression test + ~10 min deploy
- **What's broken**: `const notesUserId = payment.notes?.user_id; if (notesUserId && notesUserId !== userId) { return 403; }` — the `&&` short-circuit means when `notes.user_id` is absent, the rejection branch is skipped and the upsert proceeds. An attacker who learns a captured Razorpay payment_id without `notes` could claim entitlement for their own JWT.
- **Fix**: Add `if (!notesUserId) { return 400 with 'Missing user_id in payment notes'; }` before the conditional. razorpay-webhook already has this exact guard at lines 406-415 — mirror the pattern. Optional belt-and-suspenders: also reject if `notesUserId` is present but is not a UUID v4 shape (already done for `userId` at lines 418-429).
- **Regression test (planned)**: include in `test/contracts/verify_payment_payload_completeness_test.dart` — simulate payload with missing `notes.user_id` and assert 400.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-29-verify-payment-notes-fail-open-<hex>.md`.
- **Why missed today**: lens L23 (service-role authz defense-in-depth) did not exist.

## OI-30 — clean-orphan-media scans `coach-media` (consented retention bucket) instead of `chat-media` (transient) (P1)

- **Status**: CLOSED · 2026-05-17 · diagnose `c1ea30` · migration 071 + clean-orphan-media v5→v6 deployed
- **Identified**: 2026-05-17 evening · Hermes audit F5 · verified via subagent quote of migration 070 comments + `clean-orphan-media/index.ts:70`
- **Risk class**: silent data loss · paying users' explicitly-saved photos deleted by routine cron
- **Estimated effort**: ~1 hour (flip bucket + rename helper RPC + 1-line migration)
- **What's broken**: Migration 070 (2026-05-17, just shipped this morning under OI-23) documents `chat-media` = "transient bucket; 30-day cleanup via clean-orphan-media for free users" and `coach-media` = "long-term retention". clean-orphan-media line 70 does `.from('coach-media').remove([obj.path])`. This cleanup deletes from the WRONG bucket. The helper RPC `find_orphan_coach_media` similarly targets the wrong bucket.
- **Fix**: (1) Flip clean-orphan-media to `.from('chat-media').remove(...)`. (2) Migration: rename `find_orphan_coach_media` → `find_orphan_chat_media` (or add a new function and deprecate the old). (3) Document `coach-media` as cleanup-exempt long-term storage. (4) Re-deploy clean-orphan-media. (5) Audit what was ACTUALLY deleted from `coach-media` since OI-23 shipped this morning — fortunately OI-25 consent UI doesn't exist yet, so the bucket should be empty and no data loss has occurred YET, but verify with live query.
- **Regression test (planned)**: `test/contracts/clean_orphan_media_bucket_test.dart` source-greps the function and asserts `chat-media` is the only `.from(...)` target.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-30-clean-orphan-media-wrong-bucket-<hex>.md`.
- **Why missed today**: lens L41 (cross-document semantic consistency — cleanup-cron vs migration intent) did not exist. OI-18 measured Storage state, not cleanup behavior.

## OI-31 — 5 cron Edge Functions lack `isAuthorizedCronCall(req)` auth gate (P1) — DISTINCT FROM OI-21

- **Status**: CLOSED · 2026-05-17 · diagnose `c4031b` · 3 deploys (expiry-reminder v13→v14, morning-alert v24→v25, rolling-context v13→v14) · scope narrowed to active-cron via live `cron.job` query
- **Identified**: 2026-05-17 evening · Hermes audit F6 · verified via subagent grep of 5 named files + cross-reference to `_shared/cron_auth.ts`
- **Risk class**: privilege escalation · these functions create service-role clients without verifying the caller is the cron scheduler
- **Estimated effort**: ~2 hours (5 functions × ~15 min each + redeploy)
- **What's broken**: OI-21 closure earlier today wired `logCronStart` / `logCronEnd` TELEMETRY into 14 cron functions. That is DIFFERENT from the `isAuthorizedCronCall(req)` AUTH gate. Hermes subagent counted adoption: `cron_auth.ts` helper exists, but only 11 of 36 deployed Edge Functions call it. Confirmed unwired (creating service-role clients without auth gate): `compute-coach-signals`, `expiry-reminder`, `morning-alert`, `rolling-context`, `weekly-recalc`. Likely 20 more in the same shape. If any of these is deployed with `verify_jwt=false` or misconfigured, a public caller can trigger privileged batch jobs (e.g. fan out push notifications, run AI summarization on every user, recompute all weekly reports).
- **Fix**: For each of the 5 confirmed + the additional ~20 unwired: import `isAuthorizedCronCall` from `_shared/cron_auth.ts` and `await` it as the first line after CORS handling. Mirror the pattern from `clean-orphan-media`, `pr-detection`, etc. Verify each function's `supabase/config.toml` declaration sets `verify_jwt = true` OR documents WHY it must remain `false` (e.g., razorpay-webhook needs to accept unauthenticated POSTs because Razorpay calls it).
- **Regression test (planned)**: `test/contracts/cron_auth_adoption_test.dart` — sibling to `cron_telemetry_adoption_test.dart` — source-greps every cron-triggered Edge Function and asserts both the import + the `await isAuthorizedCronCall(req)` line appear.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-31-cron-auth-adoption-<hex>.md`.
- **Why missed today**: OI-15 / OI-21 charters were "cron telemetry"; auth adoption was conflated with telemetry in the tracking. Audit lens L4 needs to be split into L4a (auth) + L4b (telemetry) for the next pass.

## OI-32 — delete-account Storage purge may not be recursive (P2 — verification pending)

- **Status**: CLOSED · 2026-05-17 · diagnose `a2d0e1` · verified REAL + fixed · delete-account v2→v3 deployed
- **Identified**: 2026-05-17 evening · Hermes audit F7 · UNVERIFIED — subagent only read lines 1-150
- **Risk class**: DPDP §17 incomplete erasure · nested user-tagged paths may survive after account deletion
- **Estimated effort**: ~30 min verification + ~1 hour fix if needed
- **What's claimed**: delete-account Storage purge deletes only top-level paths `userId/file`, but nested `userId/subfolder/file` paths may survive. CLAUDE.md §16 documents the buckets purged (`progress-photos/<uid>/`, `chat-media/<uid>/`, `coach-media/<uid>/`) but does NOT specify depth handling.
- **Fix (if confirmed)**: Use Storage list with no depth limit (`storage.from(bucket).list('${uid}/', { limit: 1000 })` paginated until exhausted) → recursive remove. Or use the Storage RPC for prefix-delete if available.
- **Regression test (planned)**: `test/contracts/delete_account_storage_recursive_test.dart` — seeds nested path, runs delete-account, asserts all paths under `${uid}/` removed.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-32-delete-account-purge-depth-<hex>.md` once verified.
- **First step**: read `supabase/functions/delete-account/index.ts` lines 150+ to confirm depth handling.

## OI-33 — `check_apk_size_within_bounds.dart` exits 0 when APK missing (silent CI pass) (P2)

- **Status**: CLOSED · 2026-05-17 · diagnose `c84e33` · --release flag added; default behavior unchanged
- **Identified**: 2026-05-17 evening · Hermes audit F8 · verified by direct read at lines 44-48
- **Risk class**: gate-bypass · in clean CI or wrong order pipeline, APK size validation silently passes
- **Estimated effort**: ~30 min
- **What's broken**: lines 44-48: `if (!apkFile.existsSync()) { stdout.writeln('[Gate 13] SKIP — APK not found ... Exit 0.'); exit(0); }`. The gate is invoked from `/build-apk` (after build) so missing APK SHOULD never happen — but if someone re-orders pipeline steps or runs the gate alone, it silently green-checks.
- **Fix**: Add `--release` flag that turns missing-APK into FAIL (exit 1). Default behavior unchanged (exit 0 SKIP). `/build-apk` skill invokes with `--release`. Document in script comment.
- **Regression test (planned)**: `test/scripts/check_apk_size_strict_mode_test.dart` — runs the script in a temp dir without an APK, asserts exit 1 with `--release` flag + exit 0 without.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-33-apk-size-gate-strict-<hex>.md`.
- **Why missed today**: lens L24 (gate-strictness) did not exist. We never re-audited gate scripts asking "does this PASS when it should FAIL?"

## OI-34 — `check_migrations_applied.dart` compares snapshot file, not live Supabase (P2)

- **Status**: CLOSED · 2026-05-17 · diagnose `1c3401` · new `check_migrations_live.dart` shipped (companion to Gate 14)
- **Identified**: 2026-05-17 evening · Hermes audit F9 · verified by direct read at lines 11-13
- **Risk class**: gate-bypass · repo can believe migrations are applied while live Supabase differs
- **Estimated effort**: ~2 hours (write `check_migrations_live.dart` + wire into `/build-apk` Gate 14)
- **What's broken**: Script lines 11-13 carry TODO: `Wire this up to live Supabase MCP query (project dedsavbjuwgarrhphgnl) once MCP tooling is available at build time. Until then this is a snapshot-based comparison.` Current implementation reads `backups/applied_migrations.json` (manually maintained) — if the snapshot is stale or someone forgets to update it, the gate green-checks while migrations are actually unapplied.
- **Fix**: Write new `scripts/check_migrations_live.dart` that queries Supabase via service-role REST: `SELECT * FROM supabase_migrations.schema_migrations ORDER BY version`. Compare to `ls supabase/migrations/*.sql`. Fail if any local file lacks a row OR if live has unknown rows (drift in either direction). Requires service-role token at build time (already available via `supabase/.supabase/supabase access token.txt`). Keep `check_migrations_applied.dart` as offline fallback for environments without network.
- **Regression test (planned)**: integration test that seeds a mismatch and asserts FAIL.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-34-migrations-live-verify-<hex>.md`.
- **Why missed today**: lens L24 (gate-strictness) didn't exist. The TODO has been visible in the script since Test #13.

## OI-35 — CLAUDE.md §2 says "21 tables", §7 header says "46 tables" — intra-document drift (P2)

- **Status**: CLOSED · 2026-05-17 · diagnose `d0c352` · CLAUDE.md + AGENTS.md corrected; new `check_doc_internal_consistency.dart` Gate 18 pins drift pairs
- **Identified**: 2026-05-17 evening · Hermes audit F10 (re-attributed — drift is intra-CLAUDE.md not inter-file) · verified via grep
- **Risk class**: agent guidance drift · agents reading §2 quick-summary get stale count; §7 was bumped 2026-05-11 didn't propagate
- **Estimated effort**: ~5 min (fix) + ~1 hour (build permanent gate)
- **What's broken**: `CLAUDE.md:130` (Tech Stack §2): `| Database | Supabase Postgres (21 tables — backup + AI + community) |`. `CLAUDE.md:380` (§7 header): `## 7. DATABASE SCHEMA (46 Tables — Supabase Postgres)`. `AGENTS.md:95` also says "21 tables" (same drift; AGENTS.md mirrors CLAUDE.md §2). Drift is internal to CLAUDE.md + duplicated into AGENTS.md.
- **Fix**: Update both `CLAUDE.md:130` and `AGENTS.md:95` to "46 tables". Add permanent gate `scripts/check_doc_internal_consistency.dart` that greps known-drift pairs (table count, migration count, edge function count, rank count, plugin tools count, tier feature counts) and fails if any two surfaces disagree.
- **Regression test (planned)**: the new gate IS the regression — runs in pre-commit.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-35-claude-md-intra-drift-<hex>.md`.
- **Why missed today**: lens L25 (intra-document drift) did not exist.

## OI-36 — `NutritionProvider.deleteFoodLog` bypasses NutritionWriteService (P1)

- **Status**: CLOSED · 2026-05-17 · diagnose `d1e7e6` · client-only change (no deploy)
- **Identified**: 2026-05-17 evening · Hermes audit C1 · verified via subagent read of `nutrition_provider.dart:987-1019`
- **Risk class**: writer/reader drift class (8th instance per `feedback_writer_reader_field_drift_recurring.md`)
- **Estimated effort**: ~1 hour (mirror `restoreFoodLog` shape into a `deleteLog` method on NutritionWriteService)
- **What's broken**: `DeleteNutritionLogNotifier.delete` at lines 987-1019 directly mutates Hive: `await box.put('recent_deletes', deletes); await box.delete(logId); unawaited(SyncService.instance.syncNutritionData());`. Bypasses NutritionWriteService canonical writer. Sibling method `restoreFoodLog` at lines 1028-1034 properly routes through the service.
- **Fix**: Add `NutritionWriteService.deleteLog(logId)` method matching the existing pattern. Internally handle: mutex, Hive delete, `recent_deletes` tombstone update, fire-and-forget sync, telemetry on failure. Route `DeleteNutritionLogNotifier.delete` through it.
- **Regression test (planned)**: `test/contracts/nutrition_delete_writer_test.dart` — source-grep that `DeleteNutritionLogNotifier.delete` does not contain `box.delete` and DOES contain `NutritionWriteService.instance.deleteLog`.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-36-nutrition-delete-writer-bypass-<hex>.md`.
- **Why missed today**: writer/reader sweep in Test #16.2 E.7 covered Health domain + F11-C11-2 covered Workout schedule. Nutrition delete was visible but not scoped in.

## OI-37 — RankService writes Supabase post-promotion but reads local Hive — UI drifts (P1)

- **Status**: CLOSED · 2026-05-17 · diagnose `4a37e7` · client-only change (no deploy)
- **Identified**: 2026-05-17 evening · Hermes audit C2 · verified via subagent read of `rank_service.dart:97-129` (write) + `:142-149` (read)
- **Risk class**: writer/reader drift · UI shows old rank until next sync or app restart
- **Estimated effort**: ~1 hour
- **What's broken**: `evaluateAndPromote` upserts to `rank_promotions` (lines 98-101) + updates `user_profile` (lines 126-129) — both REMOTE writes. `getCurrentRank` reads `UserRepository.instance.getProfile()` (line 144) — LOCAL Hive read. No local profile update between the remote write and the local read. After successful promotion the user keeps seeing their old rank on Profile / Home / Rank widgets until `restoreFromCloudForUser` pulls the new `user_profile` row (could be minutes to hours).
- **Fix**: After successful remote `user_profile` update at line 129, also call `UserRepository.instance.updateProfileFields({'current_rank_code': code, 'current_rank_achieved_at': nowIso})` + `ref.invalidate(userProfileProvider)` (probably needs to be done via a callback / event since RankService isn't a Notifier). Or have RankService emit a stream that providers can listen to.
- **Regression test (planned)**: `test/contracts/rank_promotion_local_sync_test.dart` — simulate promotion, assert local Hive `user_profile.current_rank_code` matches the remote write.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-37-rank-service-local-stale-<hex>.md`.
- **Why missed today**: rank domain not in this batch's writer/reader sweep.

## OI-38 — `streakFreezeProvider.build()` writes via `commitRefill()` — Riverpod anti-pattern (P2)

- **Status**: CLOSED · 2026-05-17 · diagnose `5fe338` · refill extracted to `StreakProgressService.refillIfNewWeek()`; day_rollover invokes; build is now read-only
- **Identified**: 2026-05-17 evening · Hermes audit C3 · verified via subagent read of `home_provider.dart:258 + 291-305`
- **Risk class**: side-effect-on-read (CQRS violation, lens L26)
- **Estimated effort**: ~1.5 hours (extract to splash / day-rollover path)
- **What's broken**: `StreakFreezeNotifier.build()` calls `_refillIfNewWeek()` line 258. The method at line 291 has an idempotency guard (`if (lastRefill compareTo thisMondayStr >= 0) return;`) — so the write doesn't fire on every build, only once per IST week. BUT every Riverpod rebuild that triggers `build()` (auth change, invalidation, app refresh, hot reload) re-enters this path. Anti-pattern severity is bounded by the idempotency guard, but the pattern is still wrong — `build()` should be read-only.
- **Fix**: Extract `_refillIfNewWeek()` to: (a) splash `_runDeferredInit` post-restore hook, OR (b) `day_rollover_service.runRolloverNow()` (it already handles IST week-start awareness). Keep `streakFreezeProvider.build()` read-only. Confirm `StreakProgressService.instance.commitRefill` callsites elsewhere don't get orphaned.
- **Regression test (planned)**: `test/contracts/streak_freeze_provider_no_write_in_build_test.dart` — source-grep that the provider's build body contains no `commitRefill` reference.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-38-streak-freeze-build-write-<hex>.md`.
- **Why missed today**: lens L26 (CQRS / pure-function discipline) was in the 2026-05-11 memory but never integrated into the audit runner.

## OI-39 — `train_provider` scans Hive directly instead of via WorkoutRepository / WorkoutReadService (P2)

- **Status**: CLOSED · 2026-05-17 · diagnose `39ead9` · new `WorkoutReadService.logsForExercise` + both providers delegate
- **Identified**: 2026-05-17 evening · Hermes audit C5 · verified via subagent read of `train_provider.dart:43-124` + `:137`
- **Risk class**: writer/reader discipline · OI-02 closed read services this morning but train_provider wasn't migrated
- **Estimated effort**: ~1.5 hours
- **What's broken**: `_getLastPerformance` at line 53 iterates `for (final raw in hive.workoutBox.values)`. `exerciseHistoryProvider` at line 137 does the same. WorkoutReadService was shipped this morning under OI-02 with `bestPerSetReps` / `bestPerSetWeight` / `exerciseLogsForIstDate` methods — but train_provider was not migrated. A third callsite will re-implement inline and diverge.
- **Fix**: Migrate both providers to delegate to `WorkoutReadService.instance.*` or `WorkoutRepository.getExerciseLogsForDate`. Delete the file-private direct-Hive scans.
- **Regression test (planned)**: extend the existing `test/contracts/workout_read_service_per_set_semantic_test.dart` to assert no `hive.workoutBox.values` iteration appears in `train_provider.dart`.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-39-train-provider-direct-hive-<hex>.md`.
- **Why missed today**: OI-02 closure scoped to WorkoutRepository.loadAllExercisePRs + train_screen._bestPerSetReps + NutritionRepository.dailyMacros. train_provider wasn't included.

## OI-40 — Two paywall UI surfaces (`paywall_sheet.dart` + `paywall_sheet_phase_variant.dart`) (P2)

- **Status**: CLOSED · 2026-05-17 · diagnose `40c401` · phase variant CTA now escalates to canonical paywall (one purchase pipeline, two pitch surfaces)
- **Identified**: 2026-05-17 evening · Hermes audit C6 · verified via subagent read of both files
- **Risk class**: drift in pricing / copy / analytics / restore behavior
- **Estimated effort**: ~2 hours (decide consolidation vs documented variants)
- **What's broken**: `paywall_sheet.dart:1-50` docstring claims "This is the ONLY paywall UI in the app." But `paywall_sheet_phase_variant.dart:1-60` is a phase-specific variant. The latter doesn't appear to import `SubscriptionService`, suggesting separate integration paths. Risk: pricing/copy/analytics drift over time.
- **Fix options**: (a) Consolidate into one component with a `variant: PaywallVariant.standard | .phaseUnlock` parameter — single integration path. (b) Document both as official variants that share `SubscriptionService.startPurchase()` via a common base class. Add contract test that asserts both call the same purchase entry-point.
- **Regression test (planned)**: `test/contracts/paywall_single_purchase_path_test.dart` — both files invoke `SubscriptionService.startPurchase` and no other purchase entry point.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-40-paywall-variants-<hex>.md` once decision made.
- **Needs brainstorm**: decide consolidate vs documented-variants before fixing.

## OI-41 — Profile/Report streak source drifts from Home/Rank live calc (P2)

- **Status**: CLOSED · 2026-05-17 · diagnose `41507e` · Profile now reads `WorkoutRepository.currentStreak()` (same as Home + Rank)
- **Identified**: 2026-05-17 evening · Hermes audit C7 · verified via subagent grep `home_provider.dart:245` vs `profile_provider.dart:300`
- **Risk class**: writer/reader drift · users see different streak numbers in different places
- **Estimated effort**: ~1 hour (pin SoT + migrate Profile reader)
- **What's broken**: Home + Rank widgets call `WorkoutRepository.calculateCurrentStreak()` — walks back through `schedule_<date>` keys live. Profile + Reports read cached `current_streak_weeks` field on the user profile. The cached field can lag the live calc by hours or days depending on sync timing.
- **Fix**: Pin one canonical reader in `docs/sot_registry.yaml` (likely `WorkoutRepository.calculateCurrentStreak()` for current streak; `current_streak_weeks` cached value is fine for HISTORICAL reporting only). Migrate `profile_provider.dart:300` to call the live calc. If perf is a concern (live calc walks Hive on every Profile open), add a `currentStreakProvider` that caches with explicit invalidation on day rollover + workout completion.
- **Regression test (planned)**: `test/contracts/streak_single_source_test.dart` — assert Profile and Home both read from the same source.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-41-streak-source-drift-<hex>.md`.
- **Why missed today**: SoT registry didn't pin "Profile and Home must read the same value" for streak.

## OI-42 — Bake 5 new permanent gates for lens registry (L22 / L25 / L34 / L39 / L40)

- **Status**: CLOSED · 2026-05-17 · 5 gate scripts shipped: `check_doc_internal_consistency.dart` (Gate 18, L25) + `check_schema_payload_parity.dart` (Gate 19, L22) + `check_unawaited_has_error_sink.dart` (Gate 20, L34 advisory) + `check_restore_round_trip_coverage.dart` (Gate 21, L39) + `check_telemetry_pii_classification.dart` (Gate 22, L40 advisory). Gates 20 + 22 default to advisory mode pending cleanup OI-44.
- **Identified**: 2026-05-17 evening · Hermes verification methodology upgrade
- **Risk class**: process · prevents future regressions of the bug classes Hermes surfaced
- **Estimated effort**: ~6-8 hours (5 scripts × 1-1.5 hours each)
- **What's missing**: The new lens registry (`docs/audit/LENS_REGISTRY.md`) identifies 5 lenses that can be automated as permanent pre-commit / build gates:
  - `scripts/check_doc_internal_consistency.dart` (L25 — known-drift pairs in CLAUDE.md + AGENTS.md)
  - `scripts/check_schema_payload_parity.dart` (L22 — every NOT NULL column appears in every insert/upsert payload)
  - `scripts/check_unawaited_has_error_sink.dart` (L34 — every `unawaited(...)` has error handling)
  - `scripts/check_restore_round_trip_coverage.dart` (L39 — every `syncX` has paired `_restoreX` + round-trip test)
  - `scripts/check_telemetry_pii_classification.dart` (L40 — every `logEvent`/`recordNonFatal` payload classified)
- **Fix**: Build the 5 scripts in priority order. L22 + L25 are easiest (pure source-grep). L34 + L39 + L40 need light AST or semantic analysis (Dart `analyzer` package can help).
- **Wire into**: pre-commit hook + `/build-apk` skill (as new Gates 18-22).
- **Regression test (planned)**: each gate IS the test.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-42-new-lens-gates-<hex>.md`.

## OI-43 — First-pass run of 8 never-exercised lenses (L26 / L27 / L28 / L30 / L31 / L36 / L37 / L38)

- **Status**: CLOSED · 2026-05-17 · 8 parallel subagents scanned; findings filed as OI-44..OI-51 below. Lens registry last-run tracker updated. No P0 surfaced; multiple P1/P2 enumerated.
- **Identified**: 2026-05-17 evening · Hermes verification methodology upgrade
- **Risk class**: unknown · these lenses exist in the registry but have never been run on the codebase
- **Estimated effort**: ~1 day (8 parallel subagents + dedup + verification pass + diagnose-docs for any P0/P1 found)
- **What's missing**: After `docs/audit/LENS_REGISTRY.md` was created today, 8 lenses are documented but have zero "last-run" entries:
  - L26 CQRS / pure-function discipline
  - L27 Concurrency on shared state (refill ↔ consume races)
  - L28 Service-level invariants (3+ rest days, swap source ≠ target, etc.)
  - L30 Prompt input sanitization (`$userName` interpolation in LLM prompts)
  - L31 Cron job efficiency (skip-if-no-change predicates)
  - L36 Idempotency replay completeness (verify-payment + redeem-referral replay tests)
  - L37 Empty-state / null-shape readers (contract test coverage)
  - L38 Cross-account state leak beyond Hive (NavigatorObserver, Crashlytics user_id, OneSignal external_id, WebView cookies)
- **Fix**: Dispatch one Explore subagent per lens with the charter template from LENS_REGISTRY.md. Aggregate findings into `docs/audit/2026-05-XX/findings-by-lens.md`. Apply AUDIT_PLAYBOOK verification discipline. Each P0/P1 surfaced becomes its own OI entry.
- **Regression test (planned)**: per-finding contract tests; updates to the lens registry's last-run tracker.
- **Diagnose-doc (planned)**: one per P0/P1 finding from the lens runs.
- **Trigger**: schedule for next comprehensive audit (likely after Batch 1 P0 payment fixes ship).

---

## OI-47 — L30 prompt injection vectors: 5 unsanitized user-field interpolations (P1)

- **Status**: CLOSED · 2026-07-28 · merged `9d5e9d31` **and deployed to all 16 functions**
- **Progress 2026-07-27**: `b1bd184d` (sanitiser) + `842e813c` (15 call sites) +
  `94f0bf9e` (measured caps). Diagnose `f4a9c2`, closure
  `docs/audit/sdk-identity-prompt-safety.closure.yaml`, SoT concept
  `llm_prompt_input_sanitization`.
- **⚠ The merge was not the fix, and that gap is the lesson.** The merge landed
  2026-07-27. A day later this entry still read *"NOT merged"* (it was), and the
  **deployed** `morning-alert` bundle still contained **0** occurrences of the
  sanitizer. Control for that grep: `isNotificationEnabled`, deployed 2026-07-27,
  present in the same fetched bundle — so the grep was reading the real artifact,
  not failing to find anything. An Edge Function change is inert until redeploy;
  "committed", "merged" and "live" are three different claims and the board was
  conflating all three.
- **Deploy evidence — all 16, read back live from `dedsavbjuwgarrhphgnl`:**
  `ai-proxy` 77→78 · `morning-alert` 29→30 · `weekly-report` 24→25 ·
  `daily-snapshot` 22→23 · `ai-media-proxy` 20→21 · `streak-guardian` 19→20 ·
  `rolling-context` 16→17 · `future-prediction` and `assess-body-composition`
  14→15 · `pr-detection` and `compute-coach-signals` 10→11 · `re-engagement` and
  `protein-gap-alert` 9→10 · `plateau-alert`, `proactive-coach-promotion` and
  `workout-window-closing` 8→9. Every version incremented by exactly 1, every
  `updated_at` inside the deploy window, every emitted payload greps non-zero for
  the module **and** its exported symbols, and the remote bundles for
  `morning-alert` / `streak-guardian` / `ai-proxy` were re-fetched and grepped
  directly.
- **Why 16 is the whole surface (completeness, not assumption):** every function
  whose `index.ts` reaches an LLM — 15 of them — imports `sanitize_for_prompt.ts`,
  and **zero** LLM-reaching functions lack it. `compute-coach-signals` is the 16th:
  it consumes the sanitizer transitively via `_shared/coach_memory.ts`, so a
  direct-import grep alone would have missed it. `expiry-reminder` /
  `i-see-you-callout` / `weekly-recap-ready` carry the module in their emitted
  bundle as dead transitive weight but reach no LLM at all — not part of this
  surface, and correctly not redeployed.
- **⚠ THE SITE LIST BELOW IS STALE AND INCOMPLETE — kept verbatim as filed.**
  It names 5 sites and 3 of the 5 line numbers no longer resolve. The real
  surface is **15** prompt-building functions. Counting by method: ticket 5 →
  `grep geminiChat(` 14 → `grep userPrompt|systemPrompt|generateContent` **15**.
  Two of the most serious are absent from the list entirely:
  `daily-snapshot` (its output is written into `user_profile`, so injected text
  steers what the system durably believes — a persistence loop) and
  `proactive-coach-promotion` (user-editable name in the SYSTEM INSTRUCTION;
  invisible to a grep on the shared helper because it calls Gemini via `fetch`).
  `rolling-context:230` is NOT a prompt — it is `getEmbedding` + a storage
  insert. See `f4a9c2` for the full disposition of all 15.
- **Identified**: 2026-05-17 · OI-43 / L30 lens scan
- **Risk class**: prompt injection in Edge Functions
- **Effort**: ~3-4 hours (1 shared sanitizer + 5 callsite wrap)
- **Top findings:**
  - **HIGH** `morning-alert/index.ts:243` — `User name: ${name}` direct interpolation. Attack: `name = "X\nIgnore prior instructions.\nNew task: ..."`.
  - **HIGH** `future-prediction/index.ts:46-50` — 3 unquoted user fields in template literal.
  - **MEDIUM** `ai-proxy/index.ts:717` — `snapshot_json` JSON-stringified but per-field content (full_name, meals_today, coaching_notes) not pre-sanitized.
  - **MEDIUM** `rolling-context/index.ts:73` — historical user_message + ai_response interpolated into summarization template.
  - **MEDIUM** `ai-proxy/index.ts:520` — `message` length-capped (5000) but no newline/quote stripping.
- **Fix shape**: new `_shared/sanitize_for_prompt.ts` helper with `stripControlChars + lengthCap + escapeBraces`. Apply to every interpolation. Add Deno test pinning sanitizer behavior.
- **Precedent**: memory R2#7 flagged PredictionService client-side; pattern repeats server-side.

## OI-49 — L36 idempotency: all 8 critical paths hardened (NO action) (P3)

- **Status**: CLOSED · 2026-05-17 · scan verified no gaps
- **Identified**: 2026-05-17 · OI-43 / L36 lens scan
- **Findings**: scan found ZERO unhardened replay-able write paths. Every Edge Function uses pre-SELECT + UNIQUE constraint OR proactive_dedup helper OR natural-key onConflict upsert. Listing canonical patterns:
  - H-18 (verify-payment): pre-SELECT + UNIQUE + 23505 fallback
  - proactive_dedup (morning-alert/re-engagement/streak-guardian): IST-calendar-day dedup
  - Client-side natural-key upsert (sync_workout/sync_nutrition): UNIQUE + onConflict
- **No fix needed** — lens is GREEN. Mark closed in CLAUDE.md §19 to lock in the verification.

## OI-51 — L38 cross-account SDK state: 3 unwired clear-on-signOut paths (P1)

- **Status**: CLOSED · 2026-07-28 · merged `9d5e9d31`
- **Progress 2026-07-27**: `ff716e29`. Diagnose `e7b3c5`, SoT concept
  `device_session_identity_binding`, test
  `test/contracts/signout_unbinds_sdk_identity_test.dart` (9/9, both derived
  assertions negative-controlled).
- **Client-only, so nothing to redeploy — but it is not yet in users' hands.**
  The shipped APK is `1.0.0+37` at `99e145d2` (OI-52), and this branch was cut
  *from* `99e145d2`, so `ff716e29` is not in it. The fix reaches devices with the
  next APK build. Stated explicitly because the sibling OI-47 above was left
  half-done by exactly this kind of unstated residual step.
- **⚠ TWO CORRECTIONS to the text below, which is kept verbatim as filed.**
  1. **The severity framing is wrong.** This is NOT "user B's crashes get tagged
     as user A" — `_ensureLocalUser` overwrites both bindings when B signs in, so
     B is attributed correctly. The real exposure is the **signed-out window**:
     after A signs out the device is still `external_id = A`, so A's push
     notifications keep arriving with A's fitness data on a handset A may have
     sold or handed on. Unbounded in duration.
  2. **It lists the wrong third callback and misses the real one.** Razorpay was
     already closed by `razorpay_service._onUserChanged()` via
     `SingletonLifecycleRegistry` (2026-05-20 audit, after this was filed), and
     `SubscriptionService.onStateChanged` WAS reset — at `app.dart:90` in
     `dispose()`, i.e. widget teardown, which a sign-out-and-navigate never
     triggers. The one nobody had noticed is **`RankService.onStateChanged`**:
     installed at `app.dart:76` beside the other two and cleared **nowhere** —
     it survived sign-out AND teardown. Found by enumerating the declaration
     site (`grep -rn "static void Function()? onStateChanged" lib/` → exactly
     three) rather than trusting this list.
- **Identified**: 2026-05-17 · OI-43 / L38 lens scan
- **Risk class**: cross-account state leak via 3rd-party SDK / static callbacks
- **Effort**: ~2-3 hours
- **Findings (3 gaps in `auth_provider.signOut()`):**
  - **Crashlytics**: `setUserIdentifier(uid)` called on signIn (line 543), NEVER cleared on signOut. User B's crashes get tagged as user A.
  - **OneSignal**: `OneSignal.login(uid)` called on signIn (line 760), NEVER `OneSignal.logout()` on signOut. User B's pushes routed to user A's player_id.
  - **RazorpayService.{onSuccess, onFailure, pendingPlan}**: callbacks stored as instance state (razorpay_service.dart lines 30-32). If signOut→signUp happens mid-checkout, user A's callbacks fire under user B's session.
  - **SubscriptionService.onStateChanged**: static callback closure captures Riverpod state. No reset path. Low severity but real.
- **Already clean**: 27 of 33 services use pure singleton pattern with no user-tagged static state. HiveUserSession + Riverpod cache leak (Test #15.1 + c4055a) already closed.
- **Fix shape**: add to `auth_provider.signOut()`:
  ```dart
  await FirebaseCrashlytics.instance.setUserIdentifier('');
  await OneSignal.logout();
  RazorpayService.instance.resetSessionState();
  ```
  Pin with `test/contracts/sign_out_clears_sdk_state_test.dart` source-grep.

---

## OI-52 — Build the release APK

- **Status**: CLOSED · 2026-07-27 · APK `1.0.0+37`, commit `99e145d2`
- **Identified**: 2026-07-26
- **Closed by**: `/build-apk` from CI-green `main` @ `99e145d2` (all 6 jobs success).
  Artifact `build/app/outputs/flutter-apk/app-prod-release.apk`, 117.2 MB,
  md5 `d7b00cabeadb56579803c840cc498037`, recorded in `backups/apk_sizes.json`.
- **Gates**: Gate 13 PASS (+1.3% vs +36's 115.7 MB) · **Gate 48 PASS — release-signed,
  cert SHA-256 matches the pin (`CN=ICANBEFITTER`)**. Gate 48 is the one that matters: a
  debug-signed APK cannot install over a release-signed app, the suspected reason +32 never
  reached the founder and the device stayed on +28.
- **Notes**: versionCode required a bump first — `+36` was already shipped 2026-06-19. The bump
  commit (`2c4cbddd`) was correctly BLOCKED on its first attempt by
  `check_app_version_matches_pubspec.dart`: only `pubspec.yaml` had moved, not
  `AppConstants.appVersion`, which is what the app reports at runtime. Its CI run then failed on an
  UNRELATED transient — `esm.sh` HTTP 522 during Deno type-check (`clean-orphan-media/index.ts`
  still imports via CDN URL rather than `npm:`/`jsr:`; see `feedback_mistake_remote_dep_rot`).
  Re-ran green on `99e145d2`.
- **Unblocks**: OI-55, OI-61, OI-62, OI-63 — the APK now exists; each still needs the founder to
  install `+37` and perform its verification.

## OI-59 — Hold-week display Slices 2-6

- **Status**: CLOSED · 2026-07-25 · `d753e380` (+ fixes `342820b3`, `/dev` Flags card `066dd3f6`) ·
  shipped in a different session/thread, verified via `git log --grep=hold` + merge-body read 2026-07-27
- **Identified**: 2026-07-26 · hold mechanic Slice 1 shipped `7ca850d9`
- **Resolution differs from the original scope**: this entry originally called for un-clamp →
  strip → header → roadmap → entry card against the LOCKED mockup. The shipped implementation
  took a different, additive route instead — `holdStatusProvider` as the single flag-branch point
  (returns `.empty` when `enable_hold_weeks` is OFF) driving `hold_chip_group.dart` /
  `hold_roadmap_strip.dart` / a date-sourced hero card — while leaving `getCurrentWeekNumber` /
  `getProgramWeek` / `totalWeeks` clamped and untouched. Ship-dark tier (§4.12.4, 1 review round +
  bpass, `docs/plan-reviews/hold-display.md`); the follow-up `hold-display-fixes` batch closed 2
  more live-walkthrough defects. Flag `enable_hold_weeks` is still default OFF — the display is
  functionally live and correct, but only reachable via the `/dev` Flags card today.

## OI-70 — Tier engines classify a commit using the registry the commit itself changes

- **Status**: CLOSED · 2026-07-27 · diagnose `a7f3d1` · branch `gate-input-family`
- **Identified**: 2026-07-27 · B-pass on `a3d7b1` (pre-existing since `d947743d`, 2026-07-26)
- **Risk class**: self-protection is non-hermetic — the guard grades its own homework
- **What's wrong**: `blast_radius_from_diff.dart:121` and
  `check_plan_review_record_exists.dart:207` read `docs/blast_radius.yaml` from the **merged/working
  tree**, so the *new* registry classifies the very commit that changes it. Demonstrated: with the
  `docs/blast_radius.yaml` and `scripts/pre-push.sh` rules deleted, both resolve to `feature`, and
  the merge-to-main gate prints "PASS … (< account; no record required)".
- **Concrete exploit shape**: one commit deleting those two lines clears every review gate, and the
  deletion is what makes it clear them.
- **Real fix**: classify a merge using the registry as of `HEAD^1`, not the merged tree. Not
  attempted in `a3d7b1` — it changes how every tier decision is computed and needs its own review.
- **Why not papered over**: `a3d7b1`'s whole thesis is "a change to the reviewer must not be exempt
  from review". This is the one route by which it still can be.

## OI-71 — Keystone gate is blind to content written during conflict resolution

- **Status**: CLOSED · 2026-07-27 · diagnose `a7f3d1` · branch `gate-input-family`
- **Identified**: 2026-07-27 · adversarial review during the cron/notif-prefs merges
- **Risk class**: gate input means something different at a merge commit
- **What's wrong**: `check_plan_review_record_exists.dart:208` computes blast-radius from
  `git diff --name-only HEAD^1...HEAD^2` — the *branch's* diff, not the merge result. A file created
  or rewritten **while resolving conflicts** exists in neither parent and is therefore invisible to
  it. For a branch whose own diff is `< account`, the gate exits "no record required" while the
  merge commit itself carries higher-tier content.
- **Real fix**: union the three-dot branch diff with `git show --name-only HEAD`.
- **Related**: same family as `b7e4c2` / `c9f1d3` — checks written for the authoring-commit model
  behaving differently at a merge.

## OI-72 — A review file can satisfy the catastrophic gate without ever entering history

- **Status**: CLOSED · 2026-07-27 · diagnose `b2e6c4` · branch `gate-input-family`
- **Identified**: 2026-07-27 · while satisfying the gate legitimately for the cron merge
- **Risk class**: index/working-tree asymmetry in an enforcement gate
- **What's wrong**: `check_code_review_pass_exists.dart` hashes `git diff --cached` (the **index**)
  but reads the review file with `File(...).existsSync()` (the **working tree**). An untracked review
  file therefore satisfies the gate without changing the hash — which is genuinely useful (it is how
  a merge-diff attestation is possible at all) but means the artifact can be present at commit time
  and never committed. The same file already reads *staged* blobs elsewhere (`:129-138`) with a
  comment explaining why the working tree cannot be trusted.
- **Real fix**: read the review file from the staged blob and exclude `docs/reviews/**` from the
  gate's own hash, so the artifact is both required and recorded.

## OI-46 — L28 service-invariant gaps: 3 client-side-only rules (P1)

- **Status**: CLOSED · 2026-07-29 · branch `oi46-daily-cap-triggers`, diagnose `f4a19c`
- **Blocked on**: none
- **Verified**: 2026-07-29
- **Identified**: 2026-05-17 · OI-43 / L28 lens scan
- **Risk class**: rule bypass via new entry point
- **Effort**: ~1 day (actual: 3 new migrations + an ai-proxy restructuring, ×2 review + B-pass)
- **Findings (UI-only — new caller would bypass), kept verbatim as filed:**
  - Daily AI text log limit (50 free / 200 PRO) — only `UsageCounterService` in-memory counter; NO Postgres trigger on `ai_coach_interactions` for `channel='in_app'`. Compare to `enforce_food_text_daily_limit` precedent (migration 026).
  - Scan meal daily limit + cart auditor daily limit — same in-memory-only pattern; nutrition API batch endpoint lacks gates.
  - Onboarding fields required — only `OnboardingNotifier` route sequence enforces; no `users.*` NOT NULL constraints.
- **Already mitigated**: swapDays consecutive-rest + source≠target guards moved into `WorkoutScheduleService.swapDays()` per audit-2026-05-11 H-6 (precedent pattern).
- **Fix shape (as filed)**: add Postgres `BEFORE INSERT` triggers + 23P01 raise on cap exceeded; let Edge Function catch + return 429.
- **CORRECTED 2026-07-29** (oi-board-corrections batch) — **the first named finding above was
  WRONG, not just stale.** `channel='in_app'` does not exist as an `ai_coach_interactions`
  value anywhere in the codebase (it's an unrelated client-only coach-delivery-mode string).
  The actual 50/200 food-text cap is `channel='food_text_analysis'`, and it **already had**
  atomic trigger protection — `trg_food_text_rate_limit`, migration 026 — the exact precedent
  this entry cited as what to imitate was already applied to the feature this entry described as
  unprotected. `tool_dispatcher.dart:1225-1227` and diagnose-docs `0f8d54`/`7ad0d8` corroborate
  this predates the 2026-07-26 "Verified" stamp by months.
  **Two REAL, different gaps found in its place — both closed by this fix:**
  1. Free-tier chat (`channel='app'`, 10/day cap) was check-then-insert —
     `ai-proxy/index.ts:607` (gate check), `:942` (insert) — no trigger.
  2. Vision cap (`scan_meal`+`cart_auditor` combined, 15/day) was check-then-insert —
     `ai-proxy/index.ts:438` (cap check), `:475`/`:519` (inserts) — no trigger; worse than a
     TOCTOU, the success-path insert was wrapped in a swallowed `catch (_) {}`, so even a
     hypothetical trigger added there alone would never have actually rejected a capped request.
  **`swapDays` "already mitigated" claim was misleading, not true — reclassified, not fixed by
  this batch.** Verified `swap_service.dart:111-167` — the guards are real but 100% client-side
  Dart against local Hive state; there is **no Postgres constraint/trigger** on
  `scheduled_workouts` backing them. This entry's own risk model says client-only rules are
  exactly what's insufficient — reclassified as a 4th instance of the same gap, **accepted as a
  lower-severity residual risk** given the blast radius is a malformed workout schedule, not a
  quota/money bypass. Not part of this closure's fix scope (the plan that closed this OI scoped
  the fix to the chat/vision caps + onboarding fields only — see `docs/plan-reviews/
  oi46-daily-cap-triggers.md`); if `swapDays` needs a server-side backstop, that is a new,
  separately-filed OI, not a reopen of this one.
- **What actually shipped (2026-07-29, branch `oi46-daily-cap-triggers`)**:
  - Migration 111: `trg_chat_app_rate_limit` (channel='app', 10/day, PRO-exempt) +
    `trg_vision_analysis_rate_limit` (channel IN ('scan_meal','cart_auditor'), combined 15/day) —
    both `BEFORE INSERT` triggers on `ai_coach_interactions`, mirroring migration 026's
    `RAISE EXCEPTION ... USING ERRCODE='P0001'` shape.
  - Migration 112: `trg_onboarding_required_fields` — a state-TRANSITION gate on `user_profile`
    (fires only on the NULL→non-NULL flip of `onboarding_completed_at`, not every update),
    requiring all 9 onboarding-critical fields (`date_of_birth`, `gender`, `height_cm`,
    `current_weight_kg`, `target_weight_kg`, `primary_goal`, `fitness_experience`,
    `days_per_week`, `equipment_access`) non-null at that moment.
  - Migration 113 (unplanned finding, fixed in the same batch): migration 026's own
    `enforce_food_text_daily_limit` used a bare `date_trunc('day', now())` boundary, resetting
    the food-text cap at 05:30 IST instead of midnight IST — the exact bug class this batch was
    adding IST-correct triggers to prevent, found live in the precedent being mirrored. Fixed via
    `CREATE OR REPLACE`, cap values/gating unchanged.
  - `ai-proxy/index.ts` restructured from check-then-insert (chat) / insert-after-success behind
    a swallowed catch (vision) to an insert-first "reservation" pattern matching
    `food_text_analysis`'s own precedent: reserve a row before calling Gemini, catch the
    trigger's P0001 and return 429 without calling Gemini, UPDATE (not INSERT) the reserved row
    once Gemini succeeds.
  - **Live apply + deploy, both under explicit separate founder authorization per CLAUDE.md
    §4.3** (plan approval ≠ deploy approval): migrations 111/112/113 applied to
    `dedsavbjuwgarrhphgnl` 2026-07-29T16:03:47+05:30; `ai-proxy` redeployed as version 79 (the
    pre-batch deployed code would have thrown raw errors on chat's 11th message and silently
    discarded the vision trigger's rejection entirely — surfaced proactively, not left as a
    deploy-lag gap). Verified live via `pg_trigger` (all 4 triggers present/enabled) and
    `test/sql/oi46_daily_cap_triggers_live_verify.sql` (7/7 cases passing).
  - Process: ×2 independent context-blind plan review + a 5-lens B-pass (`docs/reviews/
    2dbdf134304e-review.md`), converged per `docs/plan-reviews/oi46-daily-cap-triggers.md`. The
    B-pass caught a second `onboarding_completed_at` writer (`restoring_screen.dart`'s OBS-3
    self-heal) that neither review round's writer enumeration had found, which this same fix
    would otherwise have put into a permanent doomed-retry loop for a narrow legacy cohort —
    fixed in the same batch.
- **Diagnose-doc**: `docs/diagnoses/2026-07-29-ai-coach-daily-caps-toctou-f4a19c.md`.

## OI-48 — L31 cron efficiency: 3 functions are O(all users), recompute-everything (P2)

- **Status**: CLOSED · 2026-08-01 · branch `re-engagement-prefilter`, commit `221567e2`, diagnose `a4e1c9`
- **Blocked on**: none
- **Verified**: 2026-08-01
- **Identified**: 2026-05-17 · OI-43 / L31 lens scan
- **Risk class**: cost scaling (billing alert at 10K users)
- **Effort**: ~1-2 days (actual: 1 migration + an Edge Function rewrite, ×2 review + B-pass + an 8-lens Hermes pass)
- **CLOSED 2026-08-01** (re-engagement-prefilter batch). `re-engagement` — the last genuinely
  open instance after this entry's own two prior corrections — now computes its Path B
  silent-user candidate set in ONE Postgres round-trip via
  `find_reengagement_silent_candidates` (migration 117, live 2026-08-01T07:05+05:30), an
  anti-join over the three activity tables, replacing the `.from("users")` scan plus the
  per-user 3-query loop. Edge Function deployed v11, boot-verified. Live `EXPLAIN` confirms
  Hash/Nested-Loop Anti Joins with index scans on all three `(user_id, date)` composites, so
  work scales with recent activity rather than total log volume.
  - **Found and fixed in passing:** `find_orphan_chat_media` — the very RPC used as the
    reference pattern — had been anon+authenticated-executable since migration 071 (never
    revoked the PUBLIC-default grant). Narrowed to service_role-only in the same migration.
    Not a live leak (RLS backstop verified), but the exact gap the new RPC was designed not to
    replicate.
  - **Filed, not folded in:** OI-78 (3 more RPCs with the same unrevoked-grant class) and
    OI-79 (P1 — un-ranged PostgREST reads truncate at db-max-rows=1000 on BOTH candidate paths;
    pre-existing, this batch strictly improves the Path B case and ships loud saturation
    detection on both, but the pagination fix spans cron functions this batch doesn't touch).
- **RE-SCOPED 2026-07-27** (gate-input-family batch). The 2026-07-26 pass flagged this entry as
  *"MATERIALLY STALE — needs re-scoping, not carrying forward"* and then carried it forward
  unchanged. Re-read all three functions rather than re-asserting the 2026-05-17 text; **one of the
  three is genuinely fixed and two are not**:
  - **evaluate-rank-promotions — NO LONGER MATCHES THE FINDING.** `e78e2c7e` (2026-07-08, OPT-E)
    replaced the per-user reads with chunked `.in("user_id", chunk)` batch pre-fetches
    (`index.ts:47-53` chunk-size comment + BATCH_SIZE, `:81` the batched `.in(`, `:136`
    — *"Reduces N*3 queries/tick to 3"*). The outer
    `.from("users")` scan at `:118` survives, so the O(all users) *shape* is intact, but
    "~5 Postgres reads × N users / 50K reads a day" is simply no longer true of this code.
  - **i-see-you-callout — STILL OPEN.** `.from("users")` at `:98` with per-user `.limit(...)`
    queries at `:202`, `:236`, `:289`.
  - **re-engagement — STILL OPEN.** `.from("users")` at `:131` with three per-user `.limit(1)`
    verification queries at `:164`, `:173`, `:182`.
- ~~**Revised scope**: two functions, not three~~ — **SUPERSEDED** by the 2026-07-29 correction
  below, which found `i-see-you-callout` was already fixed too, leaving ONE. Struck rather than
  deleted (this entry's own history of stale "still open" claims is the useful part). Kept for
  the still-true half: `evaluate-rank-promotions` is the in-repo example of the fix, not an
  instance of the bug.
- **Already efficient (pattern to copy):**
  - `clean-orphan-media` — RPC pre-filter → small working set
  - `pr-detection` — 20-min time window filter
  - `expiry-reminder` — single indexed SELECT with date range
  - `i-see-you-callout` — F45 active-user pre-filter (`ACTIVE_WINDOW_DAYS=28`) + `PAGE_SIZE=1000`
    pagination. **Moved here 2026-08-01**, executing the instruction the 2026-07-29 correction
    below gave ("Move it to the 'already efficient' list") but never actually carried out —
    caught by Hermes L31/N6 during the closing batch. Bounded per-active-user queries remain,
    which is why the *pagination* concern is filed separately as OI-79.
  - `re-engagement` — **as of 2026-08-01**, one anti-join RPC (migration 117); the entry this
    finding was ultimately about.
- **Fix shape**: add pre-filter SELECT (last_active_at, signals_computed_at, or other "interesting users today" predicate). Compare to plateau-alert/protein-gap-alert which already use coach_memory scores.
- **CORRECTED 2026-07-29** (oi-board-corrections batch) — **the 2026-07-27 re-scope pass's
  "i-see-you-callout — STILL OPEN" is ITSELF wrong, the second stale miss on this same
  function.** Verified live: `i-see-you-callout/index.ts:26-100` carries an
  `F45 (2026-06-07 audit)` active-user pre-filter (`ACTIVE_WINDOW_DAYS=28`,
  `.gte("last_active_at", activeCutoffIso)` at `:100`) plus `PAGE_SIZE=1000` pagination —
  landed over 7 weeks before this "STILL OPEN" line was written and over a month before the
  2026-07-26 pass that also missed it. **Move it to the "already efficient" list below;** only
  `re-engagement` remains a real, open instance now.
  `re-engagement`'s citation is off by one — `.from("users")` is actually at `:132`, not `:131`
  (region otherwise correct). Its Path B scan carries only an `is_deleted` filter, genuinely
  O(all non-deleted users), then a per-user 3-table (`workout_logs`/`nutrition_logs`/
  `weight_logs`) sequential-query loop at `:140-185` checking for the *absence* of recent
  activity (an anti-join, not a batchable positive-filter check).
  **"plateau-alert/protein-gap-alert already use coach_memory scores" is only half true.**
  `plateau-alert` does (`index.ts:96`, `plateau_risk_score >= 0.7`). `protein-gap-alert` does
  NOT — it pre-filters on `subscriptions.status='active'` then issues already-batched `.in()`
  queries (`index.ts:94-99,123-150`), no score involved. This is actually the **better**
  structural precedent for `re-engagement`'s fix (batched positive-filter pattern), though the
  anti-join shape of `re-engagement`'s actual check fits `clean-orphan-media`'s RPC pattern
  more directly.

## OI-128 — `retire_worktree`'s regenerable list omits test-generated output, so any worktree that ran the full suite can never retire

- **Status**: CLOSED · 2026-08-25 · branch `board-hygiene`, diagnose `f2a9c7`
- **Verified**: 2026-08-25 — closed; hit live a SECOND time on `auth-class-fixes` (merged, tracked-clean, held by this one file). Originally 2026-08-16 while retiring `open-issues-triage-976962`. The tool returned
  `KEEP [1 non-regenerable ignored file(s)]`; the file was
  `test/plan_generator/v4_diagnostic_output.md`, 920136 bytes.
- **Identified**: 2026-08-16
- **Blocked on**: none. Small and self-contained.
- **What's missing**: `scripts/retire_worktree_lib.dart` treats an ignored file as *regenerable* only
  if it matches a fixed set (`.env`, `build/`, `.dart_tool/`, ...). `v4_diagnostic_output.md` is not
  in it, so leg 3 of the four-leg predicate fails and the worktree is kept. But that file is written
  by `flutter test test/plan_generator/v4_diagnostic_test.dart` — i.e. by the FULL SUITE, which
  `pre-push` runs at >=`account` tier. It was also deliberately untracked in `3a07ada1` ("already in
  .gitignore"), so it is disposable by design.
- **Why this is worse than one missing filename**: the consequence is inverted. A worktree that did
  nothing never generates the file and retires cleanly; a worktree that pushed at >=`account` tier
  always generates it and can NEVER retire without manual intervention. **Retirement silently stops
  working for exactly the worktrees that did the most work** — the same unclosed-loop shape §4.13
  point 6 was written to close (creation had no retirement; retirement now has no path for
  suite-touched trees). Left alone, the 106-directory / 17 GB pile-up regrows.
- **Fix shape**: add it to the regenerable set, but prefer a RULE over a literal — an ignored file
  under `test/**` that a test writes is regenerable by re-running that test. A bare literal rots the
  moment a second diagnostic is added.
- ⚠ **Do NOT "fix" this by loosening leg 3 generally.** Leg 3 exists because `git status --porcelain`
  EXCLUDES ignored files and `git worktree remove` does NOT refuse on them — verified 2026-08-09,
  when a merged worktree holding an ignored `secrets/.env` was removed with exit 0 and the file was
  gone. Widening the *regenerable list* is safe; widening the *predicate* re-opens that hole.
- **Workaround until fixed**: confirm the file is regenerable (a named test writes it; a copy exists
  in primary), delete it, re-run. That is what was done for `open-issues-triage-976962`.
- **Second, smaller gap found the same day**: `retire_worktree` removes the worktree but leaves the
  BRANCH, so `new-worktree.sh <same-slug>` then fails with "branch already exists" — the slug is
  silently burned. Recovery is `git branch -d <slug>` (use `-d`, never `-D`: the safe form refuses an
  unmerged branch, which is the whole guarantee) and then re-create.
- **Blast radius estimate**: `platform` — the review/blast-radius machinery under `scripts/` is
  individually pinned in `docs/blast_radius.yaml`. Per §4.4 rule 24 a new/changed leg needs a
  mutation-proven test; the existing protective legs already carry one.

- **CLOSED 2026-08-25** (`board-hygiene` batch, diagnose `f2a9c7`). Five EXACT, root-anchored
  paths added to `regenerableIgnoredPaths` — `test/plan_generator/v4_diagnostic_output.md`
  (`.gitignore:112`), `analyze_output.txt` (:107), `flutter_test_output.txt` (:108),
  `baseline.json` (:132), `baseline-lints.json` (:133). The set was **enumerated from
  `.gitignore`**, not extrapolated from the one observed instance.
- ⚠ **This entry's own "Fix shape" was NOT followed, deliberately.** It said *"prefer a RULE over
  a literal — an ignored file under `test/**` that a test writes is regenerable"*. That is wrong
  on the merits here, and the function's own header explains why: **exact-match only, no prefix,
  no basename, no `contains`** — three successive review rounds each found a P0 in that one
  function caused by looser matching (prefix matching destroyed `.envrc` and `.envs/`;
  basename-at-any-depth destroyed `supabase/.env`, a real 518-byte credentials file). A `test/**`
  rule would make an ignored `test/fixtures/real_credentials.json` destroyable — the same class
  again. The header's instruction for the needs-a-pattern case is to KEEP the worktree instead,
  and that is what was done: `test/goldens/**/failures/` is genuinely regenerable but is a
  PATTERN, so it stays non-regenerable and is called out in the code.
  The entry's concern — *"a bare literal rots the moment a second diagnostic is added"* — is real
  but resolves the other way once failure DIRECTION is considered: a missing literal fails INERT
  (a worktree is kept that could have been retired), a too-wide glob fails DESTRUCTIVE.
- **Second gap in this entry (the branch is left behind after `worktree remove`, burning the
  slug): still OPEN**, filed separately rather than silently closed with the parent. Verified
  2026-08-25 by reading `scripts/retire_worktree.dart:275-282` — it calls `git worktree remove`
  and never touches the branch. The safe repair is `git branch -d` (never `-D`: the safe form
  refuses an unmerged branch, which is the whole guarantee), and it must delete the worktree's
  ACTUAL branch, not its slug — `post38-auth-fixes` sits on `rescue/post38-auth-inflight`, so a
  slug-keyed delete would target the wrong ref or none.
- **Regression tests**: `test/scripts/retire_worktree_lib_test.dart` — the five new paths must be
  regenerable, AND near-misses of each must still BLOCK (`…output.md.bak`,
  `archive/analyze_output.txt`, `flutter_test_output.txt.orig`, `data/baseline.json`, the bare
  `test/plan_generator/` directory, and `test/goldens/home/failures/`). Mutation: deleting the
  five entries reddens the first (34 → 33 pass / 1 fail). The near-miss test does NOT redden
  under that mutation and is not claimed to — it is a WIDENING guard and reddens on the opposite
  mutation (swapping exact match for a glob).
## OI-25 — Coach-media consent UI flow (client follow-up)

- **Status**: CLOSED
- **Blocked on**: none
- **Verified**: 2026-07-26
- **Closed**: 2026-07-30 — Unit 8 of the OI-25/44/45/46/48/50 batch
- **Identified**: 2026-05-17 · OI-23 closure spawned this follow-up
- **Risk class**: feature work
- **Estimated effort**: TBD (~3-4 hours estimate)
- **What's missing**: Founder direction was "We ask user does he
  want to store the pic for future reference and on consent we save
  it." The bucket + policies now exist (OI-23 closed) but the UI
  flow does NOT:
  - After AI analysis returns in chat (ai-media-proxy success path),
    show inline "Save this photo for future reference?" prompt.
  - On user tap → copy blob from `chat-media/<uid>/<filename>` to
    `coach-media/<uid>/<filename>` (atomic — keep source until
    target write succeeds; then optionally delete source if free
    user, retain if PRO).
  - Persist consent decision so it doesn't re-prompt for the same
    photo on a re-render.
  - Surface "Saved photos" in a profile sub-screen so users can
    review / delete their long-term collection.
- **Why class-killing**: Without this UI, the bucket sits empty +
  founder's product intent is unimplemented. The infra is now
  ready; needs Flutter work to plumb the consent + copy flow.
- **Plan**: (1) brainstorm the UX (single confirmation chip vs
  modal). (2) add `coachMediaRepository` with `saveForLater(chatMediaPath)`
  method. (3) wire into `ChatBubble.onMediaSaved` callback after
  ai-media-proxy success. (4) profile sub-screen at
  `/profile/saved-coach-photos`. (5) RLS already correct so no
  server-side work beyond ensuring `delete-account` Edge Function's
  Storage purge step lists `coach-media/<uid>/` (already does per
  CLAUDE.md §16).

**CLOSED 2026-07-30** (coach-media-consent batch, Unit 8 — diagnose
`f4a7c2`). All four missing pieces shipped, matching this plan closely with
one mechanism deviation: consent persists as two new fields
(`media_storage_path`, `media_save_state`) written in place on the same
`coach_<ms>` interaction row that already carries `media_url`, rather than
a separate coachBox key hashed on the chat-media path — same outcome (no
re-prompt on rebuild, no new metadata table), one fewer bookkeeping
mechanism, reusing this row's own established UPDATE-not-INSERT idiom.
Investigation before implementation found and fixed a genuine prerequisite
bug this feature depended on: the success-path user photo bubble never
carried `coachKey` (only the AI/error bubble did, for Retry) — without it
nothing could key the consent write back to the right row. Also folded in
the one-line doc fix the plan flagged: `supabase/functions/CLAUDE.md`'s
SSRF-allowlist bucket names were stale (said `progress-photos` +
`chat-attachments`; live code has always been `chat-media`, `coach-media`,
`progress-photos`) — fixed, plus a new test assertion pinning the real set
so this can't drift stale again unnoticed. `scripts/blast_radius_from_diff.dart`
classified the shipped diff `platform` (higher than this batch's own
`account` pre-diff estimate). Round-1 review found the media reference on
a chat photo message (mediaUrl/mediaStoragePath, and now also
mediaSaveState) has never round-tripped through cloud sync/restore, before
or after this batch — a pre-existing, not newly-introduced, gap. Practical
effect: a historical photo message degrades to caption-only text after a
restore on a second device (no image, no consent chip render at all — not
"the chip re-offers"). The photo itself is never lost (still in Storage;
an already-saved copy still lists correctly in Saved Photos, which reads
Storage directly). Out of scope for this unit (would need to extend both
the push and restore payloads in sync_coach.dart). **B-pass correction**: this
paragraph's own first draft said the gap was "flagged as a separate follow-up
task" without a durable, independently-verifiable citation — a
`mcp__ccd_session__spawn_task` chip was raised, but a chip is ephemeral
session UI state, not a git-tracked artifact, so once this OI closed there
was nothing left in the repo pointing at the gap. Filed as **OI-77** instead,
which is the actual, durable record. Full account:
`docs/diagnoses/2026-07-30-coach-media-consent-f4a7c2.md`.

---

## OI-44 — L26 CQRS violations: 3 real query-named mutators, one causing a provider self-invalidation (P2)

- **Status**: CLOSED
- **Blocked on**: none — Unit 6 landed the split, the deletion, and the gate that makes the
  shape unconstructible. See the closure block at the end of this entry.
- **Verified**: 2026-08-02
- **Identified**: 2026-05-17 · OI-43 / L26 lens scan
- **Risk class**: CQRS / pure-function discipline
- **Effort**: ~6-8 hours (10 methods × ~30-45 min each for migration + tests)
- **Findings (top 5 by blast radius):**
  - `SubscriptionService.isPro()` (sub.service.dart:233) — 28+ callsites; downgrades + invalidates on expiry check + cross-account guard during reads
  - `SubscriptionService.gate()` (sub.service.dart:306) — 15+ callsites; async `verifyFromServer()` mutation buried in callback
  - `BadgeService.checkAndUnlock()` (badge.service.dart:18) — Hive write hidden behind "check*" name
  - `RankService.getCurrentRank()` (rank.service.dart:176) — fires telemetry on read
  - `SubscriptionService.verifyFromServer()` — writes Hive subscription state from a verify-named method
- **Fix shape**: rename to verb-form (`refreshIsPro`, `evaluateAndDowngrade`, `checkAndPersistBadges`) OR move mutation into a separately-named method. Test pattern: source-grep that names starting `get*`/`is*`/`has*`/`calculate*` don't contain `box.put` / `instance.update` / `recordNonFatal` in their body.
- **Why not fixed now**: 10 methods × multi-callsite renames is a separate scoped batch.
- **CORRECTED 2026-07-29** (oi-board-corrections batch), re-verified against live code, not
  re-asserted from this entry's own 2026-05-17 text:
  1. **`RankService.getCurrentRank()` is NOT a violation** — `rank_service.dart:217`. Telemetry
     (`ErrorTelemetry.recordNonFatal`) fires ONLY in the exception catch block, never on the
     success path; zero Hive writes in any branch. Removed from the finding list.
  2. **`checkAndUnlock()`'s own name already signals its write** (doesn't match the
     `get*/is*/has*/calculate*` prefix set the fix-shape test targets) — the board's own test
     pattern would already pass this one. Kept as a real but milder finding than the other two.
  3. **`isPro()` → `subscription_service.dart:320`, `gate()` → `:420`** (both files renamed
     since this OI was filed; citations refreshed).
  4. **New finding**: `WorkoutRepository.calculateCurrentStreak()`
     (`workout_repository.dart:275`) — already `@Deprecated` since the 2026-05-11 streak CQRS
     split, **zero live callers** (grep confirms only doc-comment mentions). Fix shape is
     **delete**, not rename.
  5. **New finding, low severity**: `SupabaseService.getOrCreateReferralCode()`
     (`supabase_service.dart:103`) — genuine hidden write (falls through to a live Postgres
     upsert), but "get-or-create" is a defensible naming idiom. Optional rename.
  6. **Revised total: ~4 real items** (isPro split, gate split, calculateCurrentStreak
     deletion, optional getOrCreateReferralCode rename) — not 10 methods. A sweep across
     `nutrition_repository.dart`, `ai_coach_repository.dart`, `coach_interaction_repository.dart`,
     `water_target_service.dart`, `sync_service.dart` found no further live instances.

- **CLOSED 2026-08-02 — Unit 6.** Diagnose `a9c4e1`. Blast radius `platform`.

  **The finding that justified the work was not the naming.** Traced end to end:
  `profile_provider.dart:380` `SubscriptionInfoNotifier.build()` → `isPro()` →
  `subscription_service.dart:1048` `_downgradeLocally()` → `:1072` `onStateChanged` →
  `app.dart:47` `ref.invalidate(subscriptionInfoProvider)` — **a provider build invalidating
  itself.** Precision matters: it terminated (the second pass returns before mutating) and the
  invalidation landed a microtask after `build()` returned, so it cost one wasted rebuild rather
  than crashing. It was fixed because a build method must not mutate, not because it was on fire.

  **Fix.** `_enforceEntitlementInvariants()` (`:414`) holds the cross-account + expiry branches
  verbatim; `proStateSnapshot()` (`:367`) is a genuinely pure read; `isPro()` (`:338`) keeps its
  name and behaviour (enforce, then report) so all 32 decision callsites are byte-identical.
  Only build methods and the 8 re-entrant reads inside `verifyFromServer()` use the pure read.
  `evaluateEntitlement()` (`:481`) is called explicitly at boot (`splash_screen.dart:220`) and on
  account swap (`:56`). §4.6 kill-switch `disable_cqrs_pure_pro_read`.

  **Three of this entry's own claims were wrong** and are corrected here rather than closed over:
  - `gate()` is **10** callsites, not "15+".
  - `calculateCurrentStreak()` did **not** have "zero live callers" — `lib/` yes, but
    `test/train/streak_anchor_test.dart:42,73` called it and
    `test/contracts/streaks_writer_to_reader_test.dart:59` *source-grepped that the symbol
    exists*. That test demanded the presence of the defect; it now pins the split pair.
  - A fourth item, found while building the gate: `lib/CLAUDE.md` cited
    `check_writer_reader_drift.dart` and `check_subscription_gate.dart` as live pre-commit
    gates. **Neither has ever existed** — same class as this board's own
    `check_open_issues_reconciled.dart` note. Corrected.

  **`getOrCreateReferralCode()` → `verified_clean`, deliberately not renamed.** The hidden write
  is real (a live Postgres upsert via `_generateNewCode`), but "get-or-create" already announces
  the create, and there is exactly one callsite (`invite_friends_sheet.dart:64`). The decision is
  recorded as a reasoned entry in the gate's exemption ledger rather than in prose, so it cannot
  rot silently.

  **The gate (§4.11, shipped in an earlier commit than the refactor):**
  `scripts/check_cqrs_query_naming.dart` + `scripts/cqrs_query_naming_lib.dart`, negative-
  controlled by `test/contracts/cqrs_query_naming_gate_test.dart` against the committed fixture
  `test/fixtures/cqrs_gate/violations.dart`. It deliberately does NOT implement this entry's own
  proposed test (grep bodies for `recordNonFatal`) — that pattern is what forced the 2026-07-29
  removal of `getCurrentRank()`, so catch blocks are stripped first. It also needed a
  writer-verb layer (rule 4 routes writes through repositories, so `box.put(` is the rare shape)
  and TRANSITIVE same-file delegation resolution, without which it missed its own worked example.
  `lib/`: 135 members scanned, 2 mutate, both exempted with reasons, 0 unexempted.

  Behavioral: `test/contracts/subscription_cqrs_behavioral_test.dart` (11 tests). Groups A and B
  are a controlled pair — identical seed and hook counter, differing only in which read is
  called: pure fires 0 invalidations and leaves Hive byte-identical, decision fires ≥1 and wipes.

## OI-45 — L27 concurrency races: 4 unguarded getX→modify→setX patterns (P1)

- **Status**: CLOSED
- **Blocked on**: none — Unit 3a (`6258622b`), Unit 3b (`fa05aa88`) and Unit 3c + the
  behavioral-test gap (2026-08-01, `c8f3d1`) have all landed. See the final closure block below.
- **Verified**: 2026-08-01
- **Identified**: 2026-05-17 · OI-43 / L27 lens scan
- **Risk class**: lost-update race on shared state
- **Effort**: Unit 3b ~1-2 days (new migration + RPC + local version tracking) + Unit 3c ~0.5 day
  (needs its own conflict-resolution design, not a mechanical fix)
- **Top findings:**
  - ~~**CRITICAL**~~ **[CORRECTED 2026-07-29, usage-counter-race batch: downgraded to LOW — this rating does not hold, see the second correction block below]** `UsageCounterService.increment()` (line 74-79) — cross-device race could let users bypass daily caps. Two simultaneous scan-meal requests → only 1 counted. Pattern: `final c = read(); write(c+1)` with no atomicity. Fix: Postgres RPC with FOR UPDATE row lock (mirror `update_streak_progress`).
  - ~~**HIGH**~~ **[CLOSED 2026-07-30, progress-map-consolidation batch Unit 3a — see the third correction block below]** `UserRepository.updateProgress()` (line 75-84) — 4 writers (updateProgress, updateProfileFields, StreakProgressService.commitRefill, commitConsume) all do read-modify-write on the same `progress` map. Lost updates likely.
  - ~~**HIGH**~~ **[DOWNGRADED + CLOSED 2026-07-30, Unit 3a — no live race; see third correction block]** `BadgeService.checkAndUnlock()` — 2 writers (checkAndUnlock + checkAll). Rapid-fire achievement triggers can lose newly-unlocked badges.
  - ~~**MEDIUM**~~ **[CLOSED 2026-07-30, Unit 3a — see third correction block]** `HealthSyncService.syncToHive()` line 190-192 — TOCTOU between `existing == null` check and `put()`.
- **Already mitigated**: StreakProgressService uses migration 056 `update_streak_progress` RPC (the canonical pattern). WorkoutWriteService uses per-(date,exerciseName) `synchronized` mutex.
- **CORRECTED 2026-07-29** (oi-board-corrections batch), re-verified against live code:
  1. **`increment()` CONFIRMED exactly as described** — `usage_counter_service.dart:100-106`,
     still a raw `read; write(current+1)` with zero atomicity. CRITICAL rating stands.
     **[SUPERSEDED same day by the usage-counter-race batch correction further below — this
     pass re-confirmed the code SHAPE but never tested whether that shape actually produces a
     lost update at runtime. It doesn't. See the later correction block for the full
     verification.]**
  2. **`UserRepository.updateProgress()` race is real but 3x UNDER-counted.** Real writer set
     is **12+ callsites across 9 files** `[CORRECTED 2026-07-30, Unit 3a round-2 review, via a
     fresh grep: 15 write callsites (13 updateProgress + 2 saveProgress) across 11 files — the
     "9 files" figure was set early and never recounted as the list below grew; see item 6 of
     the third correction block below]`: `user_repository.dart` `updateProgress:133` +
     `saveProgress:89`; `streak_progress_service.dart` `commitRefill:61`, `commitConsume:126`,
     `grantFirstProFreezes:213`, `resetToFreeCapOnLapse:245`; `workout_repository.dart:247`
     (`_persistCurrentStreakDays`); plus callers in `simulation_service.dart`,
     `pro_phase_advance.dart`, `phase_progress_reconciler.dart`, `graduation_screen.dart`,
     `restoring_screen.dart`, `train_provider.dart`, `home_screen.dart`,
     `onboarding_provider.dart`. **`updateProfileFields` does NOT belong on this list** — it
     writes the separate `profile` Hive key via `ProfileWriteService.patchProfile`, which is
     already `Completer`-mutex-protected (`profile_write_service.dart:46,128`) — a genuine
     canonical pattern already in the repo, cite it alongside migration 056.
  3. **`checkAndUnlock`/`checkAll` DOWNGRADED from HIGH.** Both bodies are fully synchronous —
     no `await` between the `_box.get` read and the `_box.put` write — so there is no live
     interleaving window today under Dart's single-isolate model. Worth a defensive mutex
     anyway (a future edit could add an `await` mid-body), but it is not an active race.
  4. **"WorkoutWriteService uses a `synchronized` mutex" is WRONG.** It's a hand-rolled
     `Map<String, Completer<void>>` (`workout_write_service.dart:41,1083-1092`), not the
     `synchronized` Dart package (that package IS used elsewhere — `hive_user_session.dart` —
     which is likely the source of the mix-up).
  5. **`HealthSyncService.syncToHive()` CONFIRMED**, citation refreshed to `:148` (check at
     `:197`, put at `:199`).
- **CORRECTED 2026-07-29** (usage-counter-race batch, Unit 2 of the same 8-unit batch as the
  correction above — same day, later pass) — **finding 1's "CRITICAL rating stands" was itself
  wrong, on two independent axes, both now closed/verified:**
  1. **The same-device race does not exist — verified, not assumed.** A behavioral test firing
     two concurrent `increment()` calls via `Future.wait` (not sequentially awaited) against the
     UNMODIFIED pre-fix code still counted both — no lost update. Root cause of the non-race:
     `MigratedKey.read` is fully SYNCHRONOUS, and Hive's `Box.put()` mutates its in-memory
     keystore SYNCHRONOUSLY before its own first internal `await` (only the disk flush is
     actually async). Since `increment()`'s only `await` comes AFTER its read, and Dart is
     single-threaded/cooperative, nothing can preempt a caller between its read and its write's
     in-memory landing. This is the SAME structural-safety class already identified above for
     finding 3 (`checkAndUnlock`/`checkAll`) — it just wasn't checked for `increment()` in the
     prior pass, which re-confirmed the CODE SHAPE (`read; write(current+1)`, still true) but
     not the actual RUNTIME interleaving behavior that shape implies.
  2. **The cap-bypass concern is now server-enforced regardless.** All three features this
     service gates now have an authoritative Postgres trigger backstop on `ai_coach_interactions`
     (ai-text-log: migration 026, pre-existing; scan_meal + cart_auditor combined: migration 111,
     2026-07-29, same-day Unit 4 of this batch) — a lost or stale local counter can no longer let
     a request past the real cap, cross-device or same-device; worst case is a stale "X remaining"
     display or a request the server correctly 429s.
  **Downgraded CRITICAL → LOW (display-accuracy only, not a cap-bypass).** A per-key `Completer`
  mutex was added anyway as defense-in-depth (matching the `ProfileWriteService`/
  `WorkoutWriteService` convention for shared Hive-backed state) — not because a reproducible bug
  was found on `increment()` itself, since none was. Same fix applied to the sibling
  `MessageLimitNotifier.incrementToday()` (chat's display counter, `ai_coach_provider.dart:460`),
  found while investigating this finding — identical shape, identical structural non-race, chat's
  real cap also now server-enforced (`trg_chat_app_rate_limit`, migration 111).
  **Independent round-1 review of this correction raised a second, distinct mechanism the
  "structurally impossible" analysis above hadn't considered:** `checkAndResetCounters()`
  (`usage_counter_service.dart:209`) is a SECOND, previously-unlocked writer of the same 3 keys —
  fired on every app-resume, not just cold boot (`day_rollover_service.dart:140`) — with 4
  genuinely-yielding sequential `await` writes unlike `increment()`'s single-await-after-mutation
  shape, a plausible mechanism for a reset-vs-increment race. **Applying the exact same rigor
  demanded of finding 1 (test the actual pre-fix/unlocked code, don't reason from the mechanism
  alone):** a `Future.wait([checkAndResetCounters(), increment()])` concurrent-dispatch test was
  run against BOTH the locked and unlocked reset code — **the corrupted outcome did not reproduce
  either way, and round-2 review sharpened why: this is provably DETERMINISTIC, not merely
  "not observed."** A list literal `[a(), b()]` invokes `a()` then `b()` in that fixed order, and
  calling an async function runs synchronously to its first true suspend point, so
  `checkAndResetCounters()` (listed first)'s reset write lands in Hive's in-memory keystore
  (synchronous, inside `Box.put()`) before `increment()` (listed second) is even invoked.
  Reversing the argument order reverses the outcome (verified empirically, 20/20 runs each
  direction). The lock was added anyway, same per-key `_withLock` as `increment()`, as
  defense-in-depth against a dispatch shape this specific guarantee doesn't reach (independently
  event-loop-scheduled callers, should a future refactor add a genuine `await` before either
  read) — not because a reproducible bug was confirmed today. An earlier draft of this correction
  briefly claimed "a narrow race was real, fixed" before this verification step was run against
  the unlocked code; that claim did not survive the check and is corrected here rather than left
  standing.
  **B-pass review (the mandatory pre-merge 5-lens pass, §4.3) then found a THIRD shape that IS a
  genuine, reproducible bug — unlike every other race investigated in this correction:**
  `DayRolloverObserver` (`day_rollover_service.dart`) has no re-entrancy guard, and its staleness
  gate is written well after `checkAndResetCounters()` returns — a duplicate `resumed` lifecycle
  event before the first rollover completes dispatches a SECOND, independently-scheduled
  `checkAndResetCounters()` call, which (unlike the single-resetter case above) is NOT gated
  against observing stale state. Verified as real by reverting the fix: a synchronous
  `Future.wait([reset, increment, reset])` construction reliably lost the increment 20/20 runs.
  Closed with an outer double-checked-locking guard (`_dailyResetLockKey`) wrapping the entire
  staleness-check-and-reset body, staleness re-checked after acquiring the lock — verified closed
  20/20 runs across 3 orderings post-fix. This is the one fix in this whole investigation that is
  a confirmed-bug fix, not defense-in-depth; see
  `docs/diagnoses/2026-07-29-usage-counter-race-c9e3b1.md`'s "B-pass review" section for the full
  mechanism. Same B-pass round also closed a test-coverage gap: `MessageLimitNotifier.incrementToday()`'s
  lock had only a source-grep test, not a behavioral one — added, and honestly found to NOT
  discriminate (same non-race as `increment()` itself), so documented as invariant-pinning like
  its sibling.
  **Unplanned finding, also closed in the same batch:** the combined scan_meal+cart_auditor
  server cap (15/day, migration 111) undershot the documented PRO product promise
  (`docs/architecture/business-rules.md`: 10 scan-meals/day + 10 cart-audits/day independently =
  20 combined) — a compliant PRO user following the client's own displayed "remaining" counts
  could hit a live 429 well within their documented allowance. Founder decision: raise the server
  to match the documented promise (migration 114, 15→20), not lower the promise to match the
  server. Not a NEW bug introduced by this batch — the 15 value pre-dates it (an existing
  check-then-insert pre-check in `ai-proxy/index.ts`); migration 111 just made it, for the first
  time, an unconditionally-enforced trigger. **Applied live 2026-07-30T06:06:57+05:30** —
  verified via `pg_proc` source + the full live-Postgres behavioral test (20 rows succeed, 21st
  correctly rejected with `cap=20`). The mismatch is closed, not just designed.
  **Findings 2-4 (`UserRepository.updateProgress`, `BadgeService.checkAndUnlock`/`checkAll`,
  `HealthSyncService.syncToHive`) are UNCHANGED by this pass — still open, still Unit 3's scope.**
  This OI stays OPEN; only finding 1 (+ the newly-discovered cap-value mismatch) closes here.
- **CORRECTED 2026-07-30** (progress-map-consolidation batch, Unit 3a — findings 2-4, same
  investigate-then-verify discipline as the two corrections above):
  1. **Finding 2 (`UserRepository.updateProgress`) — SAME-DEVICE half closed; CROSS-DEVICE half
     is NOT (that's Unit 3b, not started).** A `Completer`-based mutex mirroring
     `ProfileWriteService._withLock` was built first, matching the established codebase
     convention — then tested with the same rigor as `increment()`'s own investigation: disabled,
     full suite re-run, compared. Two findings: (a) it gave NO correctness benefit for any
     concurrent `updateProgress`/`saveProgress` pairing tested via `Future.wait` (identical
     structural-safety class to `increment()` — Hive's `Box.put()` lands synchronously, list-order
     dispatch determinism); (b) it ACTIVELY BROKE 2 pre-existing tests
     (`streak_decay_reckon_permanent_ledger_test.dart`) by serializing two previously-independent
     UNAWAITED fire-and-forget writers (`StreakProgressService.commitConsume` +
     `WorkoutRepository._persistCurrentStreakDays`, both fired within one
     `reckonStreakDecayAndPersist()` flow) into a genuine queue — a real timing regression, no
     offsetting correctness gain. **The mutex was removed, not patched around.** The GENUINE,
     confirmed bug is different and simpler: `pro_phase_advance.dart` and `simulation_service.dart`
     read `progress`, awaited REAL plan-generation work (tens-hundreds of ms), then wrote the WHOLE
     map back from that pre-await snapshot — clobbering anything else that landed during the gap.
     Reproduced directly (not argued) and fixed by converting both to `updateProgress(delta)`,
     which re-reads fresh state at write time regardless of lock. Full account:
     `docs/diagnoses/2026-07-30-progress-map-stale-snapshot-d5c8a3.md`.
  2. **Finding 3 (`BadgeService`) — CONFIRMED no live race, same as the earlier pass already
     found; left unlocked, pinned with a synchronous-invariant tripwire test instead of adding
     lock machinery for a race that cannot occur today.**
  3. **Finding 4 (`HealthSyncService.syncToHive`) — CONFIRMED genuine, closed.** Called both on
     app launch and via the Settings health-sync toggle; its only real await gap sits BEFORE the
     weight read-check-write (inside `fetchLatestWeight`), not between them, so two overlapping
     calls can both pass the `existing == null` guard before either writes. Closed with a
     whole-method in-flight-`Future` dedup guard — a second concurrent caller now awaits the
     first call's result instead of independently re-running the fetch and the unguarded
     check-write. **Round-1 review found a P2 in this exact fix**: the dedup guard's `Completer`
     called `complete()` unconditionally in `finally`, so a deduped follower would see "success"
     even when the leader's sync actually threw — fixed to propagate the real outcome
     (`completeError` + `rethrow`) to every waiter. **Round-2 review then found a P1 in THAT
     fix** (exactly the risk this repo's §4.12 names — "the corrections themselves can introduce
     new defects"): in the common case (no concurrent follower ever calls `syncToHive()` while
     one is in flight), nobody ever attaches a listener to `completer.future` — Dart treats a
     `completeError()` on an unlistened `Future` as an unhandled error and reports it a SECOND
     time to the current `Zone`, which this app's `main.dart` wiring turns into a duplicate FATAL
     Crashlytics report on every ordinary (non-concurrent) sync failure. Independently reproduced
     via a `runZonedGuarded` repro script, not taken on the reviewing agent's word. Fixed by
     attaching a no-op `completer.future.catchError((_) {})` immediately, before the first
     `await` — verified (a second repro) this silences the phantom duplicate without preventing a
     real follower from observing the true outcome via its own listener on the same `Future`.
  4. **Unplanned finding, NOT closed here, spun out as Unit 3b:** `update_streak_progress`
     (migration 056, built 2026-05-11 specifically for this OI's cross-device concern) has been
     **dormant for 2.5 months** — confirmed via its own migration-096 header comment AND an
     exhaustive `.rpc(` grep across `lib/` (one hit, unrelated to progress). Both cloud-push paths
     for the `progress` map (`syncFreezes()`, `_syncUserProgress()`) are plain unversioned
     upserts with zero optimistic-lock protection today. Closing this requires: wiring the
     already-built RPC into `syncFreezes()`, a new sibling RPC for the ~10-11 fields
     `_syncUserProgress` doesn't cover, local version tracking, and bounded retry-on-mismatch —
     none of which exist in this codebase's progress-sync path today. Scoped out of Unit 3a as a
     separable, higher-risk piece (new migration + new local state vs. Unit 3a's already-shipped,
     fully local, empirically-verified fix) rather than folded in or silently dropped.
  5. **Second unplanned finding, found by round-1 review of Unit 3a's own diff, NOT closed here,
     spun out as Unit 3c:** `graduation_screen.dart`'s `_onPro()` (lines 560-670) has the SAME
     general bug class this OI is about — `currentPhase`/`nextPhase` are computed at
     lines 568/573, BEFORE the slow `await scheduleSvc.generateAndSchedule(...)` (lines 642-659),
     then the pre-await `nextPhase` is written via `updateProgress({'current_phase': nextPhase,
     ...})` at line 665. Narrower blast radius than the fixed bug — already `updateProgress`
     (delta), not a whole-map `saveProgress`, so only `current_phase`/`current_week`/
     `phase_started_at`/`plan_generated_at` are at risk, and only if an independent concurrent
     advance (e.g. `pro_phase_advance.dart`'s splash-time auto-advance) lands during the window.
     Not a mechanical copy of Unit 3a's fix: `generateAndSchedule` has already produced real
     schedule rows for `nextPhase` by the time of the stale write, so the correct resolution
     needs its own conflict-resolution design, not a delta-conversion. Full account:
     `docs/diagnoses/2026-07-30-progress-map-stale-snapshot-d5c8a3.md`'s "Round-1 review" section.
  6. **Round-2 review of Unit 3a's own diff, 3 more findings, all fixed here (no new open
     residual):** (a) the P1 named above in finding 4's own entry — a duplicate-Zone-error
     footgun in round-1's completer fix, fixed with a silencing listener. (b) A stale line
     citation (`_syncToHiveLocked` is at line 189, not 177). (c) The "12+ callsites across 9
     files" figure quoted at the top of finding 2 above was itself stale — a number set early
     and copy-pasted forward without being recounted as the enumerated writer list grew across
     three separate correction passes. Freshly re-counted via `grep -rn
     '\.updateProgress(\|\.saveProgress('` across `lib/`: **15 write callsites (13
     updateProgress + 2 saveProgress) across 11 files** (10 external callers +
     `user_repository.dart` itself, where `saveProgress`'s own body performs the actual Hive
     `put`) — this is now the correct figure, superseding "12+ / 9" everywhere it appears on
     this board. Full account of all 4 round-2 findings (a P3 test-scoping bug in
     `badge_service_synchronous_invariant_test.dart` also fixed, not board-relevant):
     `docs/diagnoses/2026-07-30-progress-map-stale-snapshot-d5c8a3.md`'s "Round-2 review" section.
  **This OI stays OPEN — findings 2-4's SAME-DEVICE / no-live-race / dedup halves are closed;
  finding 2's CROSS-DEVICE half is Unit 3b's scope, and the round-1-review-found
  `graduation_screen.dart` stale-write bug is Unit 3c's scope — neither started.**
- **CLOSED 2026-07-30** (cross-device-progress-lock batch, Unit 3b — finding 2's CROSS-DEVICE half,
  the item this OI's own text names above): the dormant `update_streak_progress` RPC (migration
  056, built 2026-05-11, never wired — see finding 4 in the prior correction block) is now wired
  into `syncFreezes()`; a new sibling RPC (migration 115, `update_user_progress_snapshot`) covers
  the 11 fields `_syncUserProgress` pushes that `update_streak_progress` doesn't. All 3 previously
  version-blind writers (`syncFreezes`, `_syncUserProgress`,
  `UserRepository.syncOnboardingToSupabase`'s onboarding-replay path via
  `pushOnboardingProgressSnapshot`) now route through version-aware writes with bounded
  retry-on-conflict. Full account: `docs/diagnoses/2026-07-30-cross-device-progress-optimistic-lock-e6b9c4.md`.
  Review pipeline converged before landing — 3 independent context-blind rounds + 3 B-pass
  dispatches + 1 11-lens Hermes pass, every single one found a real defect, severity strictly
  decreasing each round (the genuine-convergence signal per §4.12.1, not a unit too large):
  a P0 anon-executable grant on the new RPC (Postgres default-privileges bypass PUBLIC entirely —
  same class as diagnose a9d3f1); a stale pre-await Hive snapshot in both retry helpers that could
  clobber a concurrent same-device write (mirroring Unit 3a's own central bug, caught here by
  Hermes then again by round-3 review after the first fix only covered one of the two retry
  helpers); GREATEST-guards added to 3 monotonic "record" fields (`total_workouts_done`,
  `deployments_complete`, `longest_gap_days`) that were plain `COALESCE` and could silently regress
  on a stale-value retry — `longest_gap_days`'s guard is currently dormant (no live writer
  populates it yet) but closed proactively rather than left as a known gap for whenever one does.
  Migration 115 applied live against `dedsavbjuwgarrhphgnl` (2026-07-30T17:35:29+05:30), ACL
  independently re-verified post-apply via `has_function_privilege` (anon blocked, authenticated +
  service_role executable, matching the P0 fix). 21/21 live-Postgres regression cases (rollback
  transaction, run against the exact content subsequently applied), 46 wiring/contract tests, 6
  behavioral tests for the round-3-added `mergeRpcParamsPreferringNonNull` helper. Residual, NOT
  closed here: `restore-user-snapshot` Edge Function needs a redeploy for its freezes projection's
  new 5th column (`streak_progress_version`) — self-healing in the meantime (client degrades
  safely on an absent key, pinned by its own parity test), tracked as a separate follow-up
  requiring its own deploy authorization, not bundled into this merge. **OI-45 stays OPEN — only
  Unit 3c (`graduation_screen.dart`) and the Unit 3a behavioral-test-coverage gap remain.**
- **CLOSED 2026-08-01** (oi45-phase-advance-monotonic batch, Unit 3c + the Unit 3a
  behavioral-test-coverage gap — the last two items this OI's own text named above; shipped
  together because both needed the same test seam). Full account:
  `docs/diagnoses/2026-08-01-phase-advance-stale-target-c8f3d1.md`.
  1. **Unit 3c is BROADER than finding 5 described, and the description's core premise was
     wrong in the user's favour.** Finding 5 called it "narrower blast radius than the fixed
     bug — already `updateProgress` (delta)". The delta form is indeed safer for the OTHER
     fields, but the `current_phase` VALUE in that delta was still the pre-await one — so the
     residual was not unique to `graduation_screen` at all: `pro_phase_advance.dart:117` and
     `simulation_service.dart:565`, the two callsites Unit 3a "fixed", carried the identical
     stale value. All three now route through one monotonic writer
     (`pro_phase_advance.dart` `commitPhaseAdvance`) that re-reads `current_phase` at write
     time and refuses a lower-or-equal value. Verified root fact: `current_phase` had **no
     monotonic guard anywhere** — `saveProgress` guards `deployments_complete` and writes
     `current_phase` straight through (`user_repository.dart:128-135`).
  2. **A second, likelier defect finding 5 did not name:** `graduation_screen` ran
     `generateAndSchedule` entirely OUTSIDE the module-private advance mutex, so a splash pass
     and a graduation unlock could each generate the same phase — the second overwriting the
     first's `schedule_*` rows and `plan_start` under a user already looking at the plan. The
     mutex is now shared (`withPhaseAdvanceLock`) and graduation takes it around generation +
     write, never across the choice sheet.
  3. **The guard that existed never ran.** `graduation_screen`'s live-phase abort re-check sat
     inside `if (offerChoice)`, and `offerChoice` requires
     `PlanEngineFlags.adherenceGateEnabled` — ship-dark, DEFAULT OFF — so on the production
     default path it had never executed. Hoisted out. **Round-1 review then corrected the
     credit given to that hoist:** on the flag-OFF path there is no `await` between the
     `progress` read and the re-check, so it is provably unreachable today and buys nothing
     until the adherence gate flips ON. What actually closes the default-path hole is the
     shared lock plus `commitPhaseAdvance`'s write-time re-read. Recorded because the first
     draft of this closure claimed the hoist "guards every unlock".
  4. **Task #41 (the Unit-3a B-pass coverage gap) closed, and that B-pass's diagnosis
     corrected.** It attributed the gap to needing "genuinely novel test infrastructure";
     really, driving real plan generation in a test was already established
     (`repeat_content_scheduling_test.dart:154-195`) and no provider override is needed. The
     actual blocker was the auth seam — `ensureOpenedForCurrentSession()` returns null with no
     Supabase, so the function returned `false` on its second line. Those two lines moved into
     the public wrapper; the core is now `@visibleForTesting` and driven for real.
  5. **14 tests, both behavioral ones proven to discriminate by negative control** (reverting
     the guard fails the demotion test; reverting to a whole-map `saveProgress` fails the
     unrelated-field test). An early draft of the demotion test was a **false green** — a 20 ms
     delay let generation finish first, making the interposed write simply the last writer;
     replaced with a single event-loop yield plus an explicit ordering precondition so a miss
     fails loudly. Recorded because the failure mode is generic to every interposition test.
  6. **Not fixed, not applicable:** no data repair. A phase demoted by this in the past leaves
     no trace distinguishing it from a legitimate value, so the historical incidence is
     unknown rather than clean — stated as unknown.

## OI-82 — `promote-community-item` calls an RPC that does not exist on this project (P2)

- **Status**: CLOSED IN SOURCE · 2026-08-07 · branch `claude/work-session-3rqcp5` (Unit 1).
  Diagnose `d5b8c2`; test `test/contracts/promote_community_vote_tally_test.dart` (5 assertions,
  negative-controlled by reinstating the defect). **The redeploy is NOT done — see below.**
- **Blocked on**: FOUNDER, for the redeploy only. The code fix is landed; the DEPLOYED bundle still
  contains the dead call until `promote-community-item` is redeployed, which per §4.3 is a separate
  explicit authorization (plan approval ≠ deploy approval). The session that made the fix also had
  no `supabase/.supabase/` access token, so the host-shell deploy path was not available from it.
  Stated rather than omitted because conflating "committed" with "live" is precisely what OI-47 was
  caught doing.
- **Verified**: 2026-08-07 — premise RE-CONFIRMED LIVE today, not inherited: `pg_proc` across every
  schema on `dedsavbjuwgarrhphgnl` returns **zero rows** for `community_votes_summary`.
- **Identified**: 2026-08-01, while waiving RPC reads for the OI-79 gate.
- **What was wrong**: `promote-community-item/index.ts:128` and `:197` both called
  `.rpc("community_votes_summary")`. The function does not exist, so `.rpc()` returned
  `{data: null, error}` (PostgREST reports a missing function as an error object rather than
  throwing) and `candidates ?? fallbackCount(...)` fell through on every tick — the primary
  vote-summary path had never executed in production.
- **What this entry MISSED, and it is the more interesting half**: the error was also
  **unreportable**. The guard was `if (countErr && !list)`, but `fallbackCount` returns `[]` on
  failure and `![]` is `false` in JS, so the branch could not execute even when `countErr` was set.
  A dead guard wrapped a dead call and the pair source-greps as working error handling — the
  literal shape of the source-grep-false-confidence class. (That class is named after a
  `feedback_*.md` that lives only in the harness-local memory directory and is NOT in this repo —
  `memory/MEMORY.md:8` documents that trap. Stating the class in words here so the reference is
  followable from a clone, per the same lesson.)
- **Intent decided (2026-08-07, founder): DELETE the call, promote the tally.** Evidence: no
  migration in the repo has ever defined the function — the sole textual match in
  `supabase/migrations` is a PROSE COMMENT at `101_admin_dashboard_metrics_functions.sql:16` citing
  it as an example of an *existing* public function, which it is not (that comment is NOT corrected
  here — see the tier note below). So there was no unapplied migration to restore; it was speculative code whose
  helper was never written. `fallbackCount` already computed exactly what the RPC's name promises —
  same `{item_id, approves}` shape, same `APPROVAL_THRESHOLD` applied identically — so creating the
  RPC would have meant inventing unspecified ranking behaviour to replace a path that already works.
- **Fix landed**: both `.rpc()` calls, both `oi79-ok` waiver comments and both dead `countErr`
  guards deleted; `fallbackCount` renamed `countApproveVotes` and called directly; its doc comment
  rewritten (it had described itself as a fallback "if the RPC helper doesn't exist yet"). The
  waivers had to go WITH the calls: `check_unbounded_cron_reads.dart` matches waivers by line
  proximity, so an orphaned one can drift onto a neighbouring read and silently bless it. Gate now
  exits 0 with 3 waived reads repo-wide, down from 5, and none in this file.
- **Live state at close (why this closure does not overclaim)**: the entire community-promotion
  surface is dormant — 0 approve votes ever cast, 0 items approved, 0 rows in `food_database` or
  `exercise_library` with `source='community'`. Removing a path that never returned a row cannot
  change an outcome. This was a diagnosability fix, not a user-visible one.
- **Tier note — why migration 101's false-precedent comment was left alone**: that file already
  contains the literal phrase "SECURITY DEFINER" (line 33, plus the `security definer` clauses on
  the three functions it defines), and `blast_radius_content_rules_lib.dart` matches WHOLE-FILE
  content rather than the diff hunk. Editing even a comment there escalates the whole batch
  platform → **catastrophic**, pulling in a hermes pass. Measured, not assumed: staged →
  `catastrophic`, unstaged → `platform`. Tracked as ledger entry `MIG-101-COMMENT` in
  `docs/audit/oi_unit1_backlog.closure.yaml` to ride with the OI-78 unit, which must author a
  migration at that tier anyway. Recorded here because "why didn't they fix the obvious one-line
  comment" is the first question a reader will have.

## OI-79 — Un-ranged PostgREST reads silently truncate at db-max-rows (1000) in cron candidate scans (P1)

- **Status**: CLOSED (2026-08-01, Unit 9 — branch `oi79-paged-cron-reads`, commits `cda5b62c`
  → `017014f1` → `337bf6eb`)
- **Blocked on**: none
- **Verified**: 2026-08-01 (Hermes L31, Unit 5 re-engagement-prefilter) — empirically confirmed
  live, not inferred: an unbounded `GET /rest/v1/food_database?select=id` returns
  ~~`HTTP/1.1 206 Partial Content` with `Content-Range: 0-999/1431`~~.

- **CORRECTION 1 (2026-08-01, Unit 9 — the response is 200, not 206).** Re-measured live against
  `food_database`: the bare read returns **`HTTP 200 OK`**, `Content-Range: 0-999/*`, 1000 rows,
  `error === null`. A 206 requires `Prefer: count=exact`, which supabase-js does not send. This
  matters and is not pedantry — the original text implied a status code a caller could branch on.
  There is none, and the total is `*`, so the response does not even carry what you would need to
  detect the loss. The only signal is the row count, and it is ambiguous.
- **CORRECTION 2 (same pass).** The `morning-alert` pagination precedent cited at `:583-594` is a
  *different and better* pattern than the `.range()` loop this OI implied: it passes `p_offset`/
  `p_limit` into an RPC so ordering and paging both happen server-side. The `.range()` loop is at
  `:790-810`. Also: `.range()` CANNOT raise the cap (a `Range: 0-1499` still yields 1000), and no
  per-role override exists (`pg_db_role_setting` → 0 rows), so `service_role` — what every cron
  uses — is capped like everyone else.
- **Path B resolved.** This OI left "does the cap apply to RPCs?" as *very likely, not proven*. It
  is now irrelevant rather than answered: the helpers page unconditionally, so the behaviour is
  correct either way.
- **Scope found to be larger than filed.** OI-79 named 2 sites. Re-running the lens across the
  whole cron fleet found **21 reads in 4 distinct classes**, one WORSE than the under-coverage
  filed here: truncated `.in()` joins that decide who is EXCLUDED, which do not skip a user but
  *misclassify* one — e.g. `protein-gap-alert` sending "you're short on protein" to someone who hit
  their target (bites at ~250 active-PRO users), and `_shared/notification_prefs` clipping the
  preference tail so every notification toggle past ~175 users was silently ignored under its own
  ABSENT⇒SEND rule.
- **Fix**: `supabase/functions/_shared/paged_fetch.ts` (`fetchAllPages`/`fetchAllByIds`; `orderBy`
  required with no default, since a pagination loop without a stable sort key is its own bug),
  every site routed through it, plus gate `scripts/check_unbounded_cron_reads.dart`.
- **Nothing was truncating live.** 18 users; largest per-user table 565 rows. This was a latent
  correctness fix landed before growth, not an outage — stated so the closure does not overclaim.
- **Evidence**: diagnose `docs/diagnoses/2026-08-01-unbounded-cron-reads-d3f7b2.md`; ledger
  `docs/audit/2026_08_01_oi79_paged_cron_reads_closures.yaml` (41/41 terminal); behavioral proof
  end-to-end against live PostgREST (bare read 1000/`error===null` vs `fetchAllPages` 1431 = exact
  server count, no duplicates across page boundaries); 316 Deno tests; ×2 context-blind review +
  B-pass per §4.12 (`docs/plan-reviews/oi79-paged-cron-reads.md`).
- **Spawned**: OI-80 (below).
- **Identified**: 2026-08-01 · Hermes lens L31 (cron efficiency) during Unit 5's catastrophic-tier
  review.
- **What's wrong**: PostgREST caps an un-ranged response at `db-max-rows` (1000 on this project).
  **supabase-js does NOT treat a 206 as an error** — `error` is null and `data` is simply short, so
  a truncated read is indistinguishable from a small one. `re-engagement/index.ts` has no `.range(`
  or `.limit(` on either candidate path:
  - **Path A** (`.from("coach_memory").select(...).gte("dropout_risk_score", 0.5)`) — REAL,
    empirically confirmed class. At >1000 high-risk users it silently processes a truncated set.
  - **Path B** (the `find_reengagement_silent_candidates` RPC added by migration 117) — PARTIAL.
    PostgREST documents `db-max-rows` as applying to "table, view, or **stored procedure**" (same
    code path), but this could NOT be empirically proven on this project: no anon-executable
    set-returning function here can return >1000 rows (only 18 live users). Treat as very likely,
    not proven.
  - Same exposure very likely applies to the other unpaginated cron candidate scans — `i-see-you-callout`
    paginates (`PAGE_SIZE=1000`), `morning-alert` paginates (`:583-594`), but the rest were not
    audited under this lens. **Scope the fix by re-running the lens across all cron functions, not
    just the two named here.**
- **NOT introduced by Unit 5 — Unit 5 strictly improved it.** The pre-migration-117 Path B
  truncated an *unordered, unfiltered* `.from("users")` fetch at 1000 rows *before* any activity
  filtering, so it could yield ~0 genuinely-silent users; the RPC returns up to 1000
  *already-filtered* ones. Unit 5 added saturation DETECTION (a loud `console.warn` naming this OI
  when either path returns >= 1000 rows, `re-engagement/index.ts:154` and `:240`) so the condition
  is no longer silent — but detection is not a fix.
- **Fix shape**: a `.range(offset, offset + PAGE_SIZE - 1)` pagination loop over both paths, with
  in-repo precedent at `morning-alert/index.ts:583-594` (`PAGE_SIZE` + offset loop, `hasMore`
  termination on a short page). `.range()` works on `.rpc()` calls as well as table selects.
  Cross-check while doing this: `active_users_for_signals()` carries an internal `limit 5000`,
  which is UNREACHABLE through PostgREST if the cap applies to RPCs — contradicting
  `compute-coach-signals/index.ts:6-8`'s "worst-case is 5000" comment. Same class; resolve together.
- **Blast radius estimate**: `account` (Edge Function logic only, no migration, no client) —
  confirm via `scripts/blast_radius_from_diff.dart` at diff time.

## OI-50 — L37 empty/null-shape readers: 23 risky accesses across 6 files (P2)

- **Status**: CLOSED
- **Blocked on**: none — Unit 7 (2026-08-02, diagnose `d4e7c2`) landed both confirmed
  silent-wrong sites. See the final closure block below.
- **Verified**: 2026-08-02
- **Identified**: 2026-05-17 · OI-43 / L37 lens scan
- **Risk class**: runtime crash OR silent-wrong on malformed/empty Hive shapes
- **Effort**: ~1-2 days (8 contract tests + null-guard refactors)
- **Top findings (6 crashes + 17 silent-wrong):**
  - **CRASH** `train_provider.dart:72` — `sets.first` on empty List throws RangeError.
  - **CRASH** `todays_meals_card.dart:340` — `mealType[0]` indexes potentially-null string.
  - **CRASH** `workout_receipt_card.dart:450` — null deref if `box.get(k)` returns null then `val['type']` access.
  - **SILENT-WRONG** `workout_receipt_card.dart:380` — `log['sets'] ?? log['sets_detail']` both missing → empty path taken → zero reps rendered.
  - **SILENT-WRONG** `edit_workout_log_sheet.dart:938` — fallback to `sets_completed` key without existence check.
- **Already clean** (canonical pattern): `workout_read_service.dart`, `profile_provider.dart` — both use `if (X is List && X.isNotEmpty)` then `for (final s in X) if (s is Map)` guards consistently.
- **Fix shape**: per-file null-guard refactor + contract tests with `empty | malformed | missing-key | wrong-type` cases (the L37 charter pattern).
- **CORRECTED 2026-07-29** (oi-board-corrections batch) — **3 of the 5 named "CRASH" findings
  are WRONG; all already guarded.** Verified live, plus a broad `.first`/`.last`/bracket-index
  sweep across all of `lib/` found no further live instances:
  1. `train_provider.dart` `sets.first` (now at `:85`, moved from `:72`) — guarded, `if (sets
     is List && sets.isNotEmpty)` immediately precedes it at `:84`. No crash reachable.
  2. `todays_meals_card.dart:340` `mealType[0]` — **the citation doesn't exist**; that line is
     a section-divider comment (`// ── Empty slot ──...`), confirmed by direct read, not just
     stale. Both real `mealType[0]` sites — `nutrition_read_service.dart:70-72` and
     `nutrition_screen.dart:1258-1260` — are null/empty-guarded.
  3. `workout_receipt_card.dart:450` null-deref — guarded by `if (val is Map && ...)` at the
     real location, `:454-455`. No crash reachable.
  The 2 SILENT-WRONG findings are real but narrower than described: `:387` (was `:380`) — the
  `sets`/`sets_detail` fallback only produces an empty *per-set breakdown*, not "zero reps
  rendered" (aggregate reps/set-count are read from separate top-level fields); `:939`
  (was `:938`) — confirmed as described, no crash, silent `?? 0` fallback.
  **"23 risky accesses across 6 files" does not hold up.** Confirmed real: 2. A broad sweep of
  every `.first`/`.last`/bracket-index pattern in `lib/` found no further live crash-shaped
  risk. This OI (filed 2026-05-17) very likely predates or was never reconciled against
  PR-FIX-2 (2026-04-24, `lib/CLAUDE.md` common-pitfalls table), which already swept 6 instances
  of exactly this `.first`-on-empty-list bug class 3 weeks earlier.
  **`profile_provider.dart` is NOT a canonical-pattern example** — the `is List &&
  isNotEmpty`/`for (s) if (s is Map)` idiom does not appear anywhere in that file (it only
  reads scalar profile fields). The sole verified canonical example is
  `workout_read_service.dart` (`bestPerSetReps:64-83`, `bestPerSetDuration:91-112`,
  `bestPerSetWeight:118-131`, all three using the idiom).

  **CLOSED 2026-08-02 — Unit 7, diagnose `d4e7c2`.** Both remaining silent-wrong sites are
  fixed, and the fix is structural rather than two local null-guards, because the 2026-07-29
  correction — accurate on the count — still described them as independent. They are **one**
  bug: the cloud-restore writer (`sync/sync_workout.dart:733-767`) emits a different subset of
  the exlog aggregate fields than the client-side writer, and each reader hand-rolled its own
  reconciliation.

  What was actually wrong, beyond the board text:
  - `workout_receipt_card.dart` did not merely render an empty per-set breakdown. It rendered
    **0 duration** for a restored timed/cardio exercise, because a 2026-05-24 drift-fix had
    hardcoded `const int duration = 0` on the reasoning that the modern writer never emits a
    top-level `duration_seconds` — true of that writer, false of the restore writer (`:766`),
    which is the only one that produces the affected rows.
  - `edit_workout_log_sheet.dart` read only the legacy `sets_completed`, so the SETS box was
    **blank on every cloud-restored row** (restore stamps `set_number`), and its duration box
    used a per-set MAX for a value `save` writes back as a SUM — so saving a restored multi-set
    timed row **wiped the real total to 0**. That is local data loss, not just display drift.

  Fix: one shared reader — `WorkoutReadService.aggregateSetCount` /
  `hasAggregateSetCount` / `aggregateDurationSeconds` — with both surfaces delegating, a
  `hasAggregateData` flag so an absent count is distinguishable from a logged zero, and
  `exlog_no_aggregate_signal` telemetry. Behavioral coverage:
  `test/contracts/exlog_aggregate_read_behavioral_test.dart` (23 tests; 5 verified to fail
  against the pre-fix readers; 63 green across the 10 affected contract files).

  **Three review rounds corrected the scope, in the board's favour.** There were not 2
  hand-rolled aggregate readers but **7**. Round 1 found `week_selector.dart`,
  `exercise_preview_sheet.dart` and `expanded_exercises.dart`; round 2 found
  `workout_repository.dart:941` (`getExercisePRHistory` — it feeds the AI coach via
  `ai_snapshot_builder` and `pattern_detector`, so a restored user's coach reasoned over zeroed
  set history); the B-pass found `train_provider.dart:1556` (the workout-finish PR banner, whose
  hand-rolled divisor collapses to 0 on the APK Test #12.1 shape and silently suppresses a
  genuine PR). All seven now delegate. The gate that should have caught the class,
  `no_top_level_duration_seconds_reads_test.dart`, scanned only `lib/features/train/` and its
  failure message recommended the exact call that causes the bug; it was rewritten to scan
  `lib/core/services/` as well and to pick by semantic.

  The refuted count ("23 risky accesses across 6 files") is left in the heading deliberately —
  the body already corrects it, the wrong claim is useful history, and a CLOSED issue no longer
  appears in `OPEN_INDEX.md`, so nothing surfaces the stale number any more.

## OI-67 — `MEMORY.md` over its soft cap

- **Status**: CLOSED · 2026-07-29 · commit `<pending>`
- **Identified**: 2026-07-26 · consolidation pass
- **What's missing**: 20,316 bytes vs the 17,510 soft target (hard read cap 24,400). Genuinely gated
  on closing items above rather than on more compression — every surviving In-flight entry carries a
  live obligation. Closing OI-52…OI-56 removes most of it.
- **How closed**: NOT via closing OI-52…OI-56 as anticipated above — those remain OPEN (verified).
  A `/consolidate-memory` pass ran in a separate session (2026-07-29), trimming dual-tracked
  In-flight lines that already had their own OI number. Measured directly (`wc -c`), not taken from
  MEMORY.md's own retrospective entry (which claims 16,866 bytes): actual current size is
  **17,227 bytes**, under the 17,510-byte soft target by a 283-byte margin — real, but thin.

## OI-68 — Build the backlog MECHANISM (attempted 2026-07-26, withdrawn after 2 review rounds)

- **Status**: CLOSED · 2026-07-29 · diagnose `a9f2c6` · commit `<pending>`
- **Identified**: 2026-07-26
- **Risk class**: the backlog stays passive — visible only to whoever opens the file
- **What's missing**: a SessionStart digest surfacing OPEN items, a merge-to-main gate forcing an
  `open_issues:` declaration, and a format gate. All three were **built and then withdrawn** — two
  independent review rounds found 5 P1s and the unit was split per §4.12.1, shipping only the data
  half (this file + the `memory/MEMORY.md` stub), which carries no code risk.
- **How closed**: NOT the withdrawn design above (SessionStart digest + blanket merge-gate
  `open_issues:` declaration + format gate) — a narrower, different mechanism shipped instead:
  `e4bc9040` built `docs/audit/OPEN_INDEX.md` (generated, one line per open issue, fails closed on
  a missing field or an empty index) and `scripts/check_closes_oi_cited.dart` (citation required
  only on an actual OPEN→CLOSED transition, not on every merge — strictly narrower than the
  original blanket-declaration idea). Scar #3 below — "the format gate validated shape but not
  vocabulary" — reproduced live a 4th time during `build_oi_index.dart`'s own build (a
  `startsWith('OPEN')` skip silently dropped a `BLOCKED` entry); caught by the B-pass and fixed in
  `f78d721c` (diagnose `a9f2c6`) with explicit negative controls for all four words this entry
  names (PENDING, BLOCKED, REOPENED, the IN-PROGRESS typo) — `unrecognisedStatuses()` /
  `unreadableStatuses()` now classify every status line and exit 1 naming the offending entry
  rather than silently dropping it.
  **Residual, not silently dropped:** no SessionStart digest exists. Both prior attempts were
  withdrawn as buggy (2026-07-26); not re-attempted here. Distinct from OI-69 (staleness
  *detection*) — this is per-session proactive surfacing, and stays unbuilt.
- **Closes**: diagnose-doc
  `docs/diagnoses/2026-07-29-gates-silently-skip-what-they-cannot-parse-a9f2c6.md`.

- **SCARS — read before re-attempting. Three generations of the SAME bug in one component:**
  1. **v1 parser** used an exact-string match `line.trim() == '- **Status**: OPEN'`. It missed 7
     realistic shapes — worst of all this file's OWN house style, since every CLOSED entry here is
     written `- **Status**: CLOSED · <date> · <diagnose>` with a trailing qualifier
     (`grep -cE '^- \*\*Status\*\*: CLOSED ·'` → 39; one reviewer counted 40, the discrepancy was
     never settled and does not change the point). An author following the established convention
     would have been silently dropped from the digest.
  2. **v2 parser** loosened the regex to fix that — and made the colon optional and `*` a valid
     bullet, so a prose line like `- Status quo is unchanged since May` **captures "quo", locks the
     entry, and silently drops it**. Verified: 3 new drop modes, all invisible to the format gate
     shipped alongside. Requiring the colon kills two of them.
  3. **The format gate validated shape but not vocabulary**, though its own error message claimed
     otherwise — `PENDING`, `BLOCKED`, `REOPENED` and a one-character `IN-PROGRESS` typo all passed
     the gate and vanished from the digest.
- **Other findings to carry forward:**
  - The digest's cap (18) hid this very OI. Any accountability item filed against the mechanism must
    be reachable *by* the mechanism, or the tracking is theatre.
  - `open_issues:` was matched against the whole record, accepting a hit in prose or a fenced code
    block — the class `recordBranchFieldMatches` was hardened against a week earlier, reintroduced.
  - The gate reached its checks without computing blast-radius, so it could fail where the keystone
    gate passes. **0 of 70 existing records carry `open_issues:`**, so switching it to hard-fail
    without a migration would redden main immediately.
  - Promoting **this data file** to `platform` tier was self-defeating (ticking one OI to CLOSED
    would then demand a ×2 review + B-pass) and was reverted. Promoting the *enforcement scripts* is
    still right.
  - A brand-new gate on the merge path must ship `--warn-only` per §4.11 — and something must flip
    it. Live precedent for the decay: `check_skipped_discipline_budget.dart` has been `--warn-only`
    since `ae6146eb` (2026-06-18) against a documented *"24h smoke window"* — 38 days.

## OI-75 — notification_preferences has no SoT registry entry

- **Status**: CLOSED · 2026-08-07 · branch `claude/work-session-3rqcp5` (Unit 1).
  Entry appended to `docs/sot_registry.yaml` (concept `notification_preferences`, domain `profile`),
  `behavioral_test_path: test/contracts/notification_prefs_rescope_behavioral_test.dart`.
- **Blocked on**: nothing — closed.
- **Verified**: 2026-08-07 — Gate 42 (`check_sot_behavioral_test_paths.dart`) PASS at 107 concepts;
  `check_reader_manifest_complete.dart` and `check_snapshot_contract.dart` both PASS;
  `sot_registry_completeness_test.dart` ([Gate 7 mirror]) PASS. That last one earned its keep: the
  first draft of this entry cited `line_range: 205-240` for `write` in a 232-line file, and a
  `read` range of 120-145 when `read()` is at :155. Both were caught by the gate, not by review —
  worth recording because this entry's whole point is that its citations be trustworthy.
- **Identified**: 2026-07-27 · B-pass
- **What was missing**: §4.5 requires a `docs/sot_registry.yaml` entry for a new writer/reader
  contract. The arc created one (repository → compileDailySnapshot → Edge Function readers) and
  did not register it. `docs/snapshot_contract.yaml` WAS updated, so the drift gate covers the
  snapshot seam; the SoT registry entry was the missing half.
- **⚠ THIS ENTRY'S READER COUNT WAS WRONG — it said 6, the real number is 10.** Re-derived by grep
  at close time rather than copied (this entry's own citations, and `snapshot_contract.yaml`'s
  `notification_preferences` readers block, are recorded as unvalidated by OI-80). The server
  readers are **not uniform**: SIX consume `_shared/notification_prefs.ts`
  (`morning-alert:56`, `plateau-alert:44`, `pr-detection:24`, `proactive-coach-promotion:27`,
  `protein-gap-alert:46`, `re-engagement:55` — import sites), and **FOUR read
  `snapshot_json.notification_preferences` INLINE and never import the helper**
  (`weekly-recap-ready:54`, `streak-guardian:177`, `workout-window-closing:233`,
  `expiry-reminder:118`). "6" was the helper group only. Recorded because it is a live maintenance
  hazard, not a bookkeeping nit: **a change to the helper's semantics reaches only 6 of 10
  consumers**, and the ABSENT ⇒ SEND default means a divergence fails toward sending notifications
  rather than withholding them.
- **Note on §4.4 r21**: this closure also corrected root `CLAUDE.md` §4.4 r21, which still described
  Gate 42 as emitting a WARN with a `behavioral_test_required: true` backlog. The gate has been
  STRICT by default for some time and that marker is now itself a hard blocker — the stale wording
  is what led this OI's own plan to propose a bare registry entry that would have failed pre-commit.

## OI-76 — Notification count includes PRO-locked rows a free user cannot disable

- **Status**: CLOSED · 2026-08-07 · branch `claude/work-session-3rqcp5` (Unit 1).
  Diagnose `a7e3d1`; tests `test/contracts/notification_pro_key_scoping_test.dart` +
  `test/contracts/paywall_feature_label_test.dart`, both negative-controlled by execution.
- **Blocked on**: nothing — closed.
- **Verified**: 2026-08-07 — fixed and pinned. `flutter test test/contracts/ test/router/` → 2832 pass
  on Flutter 3.41.4 (the CI-pinned version) with `TZ=Asia/Kolkata`.
- **Identified**: 2026-07-27 · B-pass
- **What was wrong**: `profile_content.dart` counted all 10 registry keys, including Protein Alerts
  and Plateau Check. A free user cannot turn those off, and their server functions PRO-gate anyway,
  so the subtitle permanently read at least 2/10 "enabled" for notifications that would never fire.
- **⚠ THE "Related" LINE BELOW WAS WRONG ON ITS SECOND CLAIM — kept verbatim, corrected here.**
  It read: *"the paywall callback passes `AppConstants.featureProgressPhotos` for notification
  rows — wrong copy, and §4.4 r19 keys server-side verification off that id."*
  1. **The first half understated it.** `PaywallSheet` renders `feature` VERBATIM into its
     letterhead (`paywall_sheet.dart:367`, `'${widget.feature} is a PRO feature'`), so a free user
     tapping a locked notification row was shown the literal string
     **"progress_photos is a PRO feature"** — not merely the wrong copy, the raw identifier. It was
     the only one of ~25 `showPaywallSheet` call sites passing a snake_case constant; every other
     passes a display string.
  2. **The second half is FALSE.** §4.4 r19 does NOT key off this id. `showPaywallSheet`
     (`paywall_sheet.dart:23`) is display + telemetry only and never reaches `gate()` or
     `verifyFromServer()`; r19 keys off `gateAndVerify`'s positional first argument, a different
     call. Both appear together at `profile_content.dart:345-349`, which is the convention this fix
     restores: **id → the gate, display string → the paywall.** Acting on the claim as written
     would have produced a fix aimed at a server-side contract that does not exist — and the
     obvious "swap in a new `AppConstants.featureNotifications`" would have changed nothing, since
     `_featureSubtitle` switches on display strings and any constant still falls to the default arm.
- **Also fixed, found while fixing the above**: all three NOTIFICATIONS rows in `settings_screen.dart`
  pushed `/profile/notification-settings` with no `extra`, so the route's `?? false` default showed a
  **paying PRO user a lock** on the two PRO rows. The screen's own `initState` comment names that
  exact harm as one it fixed, but only the prefs half was ever fixed. `isPro` was already in scope at
  `settings_screen.dart:40`.
- **Load-bearing constraint the fix had to respect**: `allKeys` and `emissionMap()` are NOT narrowed.
  The server's rule is ABSENT ⇒ SEND, so scoping the emitted snapshot by tier — the intuitive
  implementation — would turn the two PRO notifications **ON** for free users. Pinned by a
  negative-controlled test rather than a comment.

## OI-83 — cloud→Hive `progress` restore merges bypass every monotonic guard, and can demote `current_phase` (P2)

- **Status**: CLOSED
- **Blocked on**: none — the scoping decision was made by the founder 2026-08-03
  (**local-max-wins**, with telemetry) and Unit A shipped both halves. Closure block at the
  end of this entry.
- **Verified**: 2026-08-03 (Unit A, diagnose `d1f6b3` — all 7 writers re-read directly)
- **Identified**: 2026-08-01 · round-1 context-blind review of the oi45-phase-advance-monotonic
  batch, while checking whether that batch's claim "`current_phase` is now monotonic" holds
  end-to-end. It does not — it holds for the ADVANCE operation only.
- **Risk class**: monotonic-field demotion via a cloud-wins restore
  (`feedback_monotonic_field_recompute_demotion.md`; siblings 3a7b9f, c8f3d1)
- **What's wrong**: `grep -rn "put('progress'" lib/` returns **7** direct writers of the whole
  `progress` map. Exactly one is `UserRepository.saveProgress`. Two of the others are cloud→Hive
  merges that copy the PostgREST row's values verbatim, cloud-wins, straight into `userBox`:
  `sync/sync_profile.dart:612-622` (`_restoreUserProgress`) and
  `auth_session_bootstrapper.dart:322-328`, both shaped
  `{...existingMap, for (final e in cloud.entries) if (e.value != null) e.key: e.value}`.
  A stale cloud row restored over a locally-advanced Hive value therefore demotes `current_phase`
  (and any other monotonic field in that map) with no guard, no telemetry, and no trace — the
  advance-side guard `c8f3d1` added sits on `commitPhaseAdvance`, which these do not go through.
  Two more (`sync_restore_completeness.dart:242,411`) write the map directly as well and want the
  same audit.
- **Why it is NOT folded into c8f3d1**: that batch's scope is the advance operation, and its own
  `restore_methods: not_applicable` is scoped-correct. This is a different operation with a
  different correct answer, and choosing it is a product/architecture call, not a mechanical fix:
  a restore that refuses to lower `current_phase` is right for a second device that is behind, and
  WRONG for a genuine account restore where the cloud row is the only truth left. Guessing between
  those would be exactly the kind of unverified premise this board exists to catch.
- **Fix shape (needs the scoping pass first)**: decide per-field whether the progress map's
  monotonic fields (`current_phase`, `deployments_complete`, `total_workouts_done`,
  `longest_gap_days`) are local-max-wins or cloud-authoritative on restore; then either route all
  4 map writers through one merge helper that applies that rule, or document why verbatim
  cloud-wins is correct and add telemetry when a restore lowers one.
- **Second-order effect, named so it is not rediscovered as a fresh incident** (B-pass F1 of the
  same batch): because these writers bypass `withPhaseAdvanceLock` entirely, one of them can bump
  `current_phase` *while* `graduation_screen._onPro` is inside the lock running
  `generateAndSchedule`. The counter then behaves correctly — `commitPhaseAdvance` declines the
  stale write — but the `schedule_*` rows and `plan_start` already written for that phase are NOT
  rolled back or reconciled against whatever the restore delivered. c8f3d1 narrowed this by
  re-checking the live phase inside the lock immediately before generating (so a bump that lands
  *before* generation no longer causes a wasted generate); the window that remains is a bump
  landing *during* generation, which is this OI's to close.
- **Blast radius estimate**: `account` (touches `lib/core/services/sync/**` +
  `auth_session_bootstrapper.dart`; no migration).

### CLOSURE — Unit A, 2026-08-03, diagnose `d1f6b3`

**Founder decision (the scoping call this entry was waiting on):** the monotonic progress fields
are **local-max-wins on restore**, with telemetry when one is refused. The alternative —
arbitrating on `updated_at` / `streak_progress_version` — is only needed if a *deliberate*
backward move must propagate across devices, and today none does: the only two writes that lower
the phase are onboarding's first write on a fresh account (nothing to demote) and the dev-panel
`resetJourney` (`simulation_service.dart:108`, debug-only). Revisit if a user-facing "restart my
journey" ever ships.

**This entry's "two more want the same audit" — audited, and they are NOT vectors.**
`sync_restore_completeness.dart:242,411`, `sync_service.dart` `_stampProgressVersion` and
`streak_freeze_clamp_migrator.dart` all read-modify-write a freshly-read map and mutate only
freeze keys / `streak_progress_version`, so they preserve whatever `current_phase` is present.
**Exactly 2 of the 7 writers were demotion vectors**, both now routed through the shared
`UserRepository.mergeCloudProgress`. Result recorded in `docs/sot_registry.yaml` so the next pass
does not re-derive it.

**The second-order half is NOT closed — it is REPORTED, and its repair is OI-85.** This closure
originally claimed it was fixed by forcing `PlanIntegrityReconciler` past its `needsHeal` gate.
Review refuted that (inert — `mergeScheduleEntry` re-applies the same predicate per row), then
refuted the follow-up (`preferSnapshot` + orphan sweep — data loss, because cloud `plan_json` is
only daily-fresh and spans every `schedule_*` key). Per §4.12.1 the smallest converged piece
ships: a `phase_advance_declined_rows_stale` event, HIGH-priority in both twin lists so the
frequency can actually be measured, and the repair filed with all three refutations.

**Also corrected:** `sync_profile.dart:592-609` justified the wholesale merge with "a fresh
restore read is always at least as new as whatever's local" — true of the server-owned
`streak_progress_version` it was written about, false of a client-advanced field. Left in place it
would have re-justified the bug for the next reader.

**Round-1 review changed three things in this closure, and each is worth carrying:**
- **`longest_gap_days` is NOT guarded**, though this entry's own fix-shape listed it. It is
  INVERTED — higher is worse, it gates a rank (`rank_service.dart:506`), it has no client writer,
  and migration 115 already GREATESTs it server-side — so local-max-wins could only ever refuse a
  server correction and pin the rank ladder shut. The guarded set is **3**, not 4.
- **A §4.6 kill-switch ships** (`disable_progress_restore_monotonic_merge`). The measured tier is
  `platform`, where `docs/blast_radius.yaml:25` makes `feature_flag` a requirement — and the
  `longest_gap_days` catch is itself the argument: a per-field judgement list can be wrong in a
  way a proven total order cannot.
- **The second-order half is REPORTED, not repaired — and its repair is now OI-85.** Three
  mechanisms were designed and each refuted, the last two by context-blind review: (1) restore
  takes `withPhaseAdvanceLock` → it is a TRY-lock, so the restore would be dropped entirely;
  (2) force past `needsHeal` → INERT, because `mergeScheduleEntry` re-applies the same
  local-has-exercises predicate per row; (3) `preferSnapshot` + deleting rows past the
  re-anchored `plan_end` → DATA LOSS, because cloud `plan_json` is pushed only by the DAILY full
  sync and can be 24h stale (the sweep would delete the WINNER's fresh rows), and the snapshot
  spans every `schedule_*` key box-wide (so it would revert an un-synced local swap). Per
  §4.12.1 the smallest converged piece ships: the demotion fix, plus a
  `phase_advance_declined_rows_stale` event that makes the condition visible for the first time.

**Not deployed, and it needs its own go:** `supabase/functions/log-client-error/index.ts` gains the
two new events in its `HIGH_PRIORITY_OP_TYPES` twin list. The code is committed and the client half
is live; until that function is deployed the server still classifies those events as LOW priority.

Tests: `test/contracts/progress_restore_monotonic_behavioral_test.dart` (23, with the pre-fix
merge inline as the negative control and the default `mergeScheduleEntry` mode as a second one) +
`test/contracts/restore_progress_uses_shared_merge_test.dart` (8 executed, routing pin,
presence-only by construction). 31 total, all green; 87 across the 7 affected suites.

## OI-84 — `graduation_screen.dart` added to the Gate 43 allow-list; split owed (P3)

- **Status**: CLOSED
- **Blocked on**: none — it was scheduled work and Unit B did it. Closure block at the end of
  this entry.
- **Verified**: 2026-08-03 (Unit B, diagnose `b4e9c7` — Gate 43 run with the allow-list entry
  DELETED: `OK — no screen exceeds 800 lines`, and `graduation_screen.dart` no longer appears
  in the `ALLOW` output at all)
- **Identified**: 2026-08-01 · Gate 43 blocked the `oi45-phase-advance-monotonic` commit
  (`c8f3d1`, Unit 3c).
- **Risk class**: god-screen / tech-debt ladder regression
- **What happened**: `lib/features/train/screens/graduation_screen.dart` was **794 lines — six
  under Gate 43's 800 ceiling** — so Unit 3c's phase-advance monotonic fix could not touch that
  file at all without tripping the gate. It is now 892 (of the +98, 77 are comment lines added at
  the direct request of the three review rounds). The file was added to the gate's transitional
  allow-list (`scripts/check_god_screen_max_lines.dart`) **on explicit founder authorization**,
  after being shown that (a) the gate has no per-run exception — no env var, no `--warn-only`, it
  exits 1 unconditionally — and (b) the allow-list is a one-way ratchet whose every prior movement
  was a *removal*. This is the first entry ever added to it.
- **Why this is tracked rather than closed**: the allow-list's own header says it "MUST shrink to
  empty when the audit ladder closes". A seventh entry with no owed-work record would quietly
  reverse that direction. This OI is that record.
- **Not a C3/C4 reopening**: `graduation_screen.dart` was never a C3 or C4 target (those were
  `active_workout`, `train`, `profile`, `ai_coach`, all closed by splitting). It was simply under
  the ceiling until this batch.
- **Fix shape (recommended, from the c8f3d1 review)**: rather than a pure part-file split, hoist
  the locked generate + `commitPhaseAdvance` + repeat-nudge block (~120 lines) out of `_onPro` and
  into the shared advance service next to `commitPhaseAdvance`, where the other three advance
  paths already live. That lands the screen at ~770 (under the ceiling honestly, not by
  exemption), leaves the screen doing UI only — choice sheet, snackbars, navigation, provider
  invalidation — and completes the "one place owns the phase advance" thesis c8f3d1 started.
  Reference layout for the alternative pure split: `lib/features/train/screens/active_workout/`.
  **Remove the allow-list entry in the same commit.**
- **Blast radius estimate**: `account` (`graduation_screen.dart` has its own file-scoped account
  rule in `docs/blast_radius.yaml`); no migration, no schema.
  MEASURED at ship time: **`platform`** — but only because the B-pass fix edited
  `docs/blast_radius.yaml` itself (`:171`, a platform-tier path). Per-file, the
  runtime code is `account` (`graduation_screen.dart`, `pro_phase_advance.dart`)
  and everything else is `feature`. The estimate was right about the CODE.

### CLOSURE — Unit B, 2026-08-03, diagnose `b4e9c7`

**909 → 552 lines. The allow-list entry is deleted and the ratchet is shrinking again** (six
entries, all original C4 targets).

Two moves, one deletion, one commit:

1. The ~120-line locked generate + `commitPhaseAdvance` block → `runGraduationPhaseAdvance` in
   `lib/shared/services/pro_phase_advance.dart`, beside the other three advance paths. Its
   `bool?` return became `GraduationAdvanceResult` — a four-case outcome enum plus
   `repeatNudgeFlagged`. The old `false` had covered TWO outcomes that already emitted
   *different* telemetry, so the type was lossier than the instrumentation next to it.
2. The ~250-line phase-2 preview UI → `lib/features/train/widgets/phase2_preview_card.dart`
   (`Phase2PreviewCard` / `Phase2BenefitsCard`). Both builders already took no `ref` and no
   `BuildContext`, so this was a move, not a refactor.
3. The `_allowList` entry deleted from `scripts/check_god_screen_max_lines.dart` in the same
   commit.

**Step 2 was NOT this item's recommended shape, and the reason is worth keeping.** The hoist
alone landed the file at ~791 — **nine lines of margin**. That is the identical condition that
*created* OI-84: the file sat six under the ceiling, so Unit 3c could not touch it at all. This
item's own "~770" estimate had gone stale, because Unit A grew the file from 892 to 909 after
the estimate was written. Founder chose the fuller split once shown the arithmetic. **A board
item's numbers age; re-measure before planning against them.**

Two second-order findings, both fixed in the same commit:

- `docs/blast_radius.yaml:207-216` justified this file's `account` rule with "contains a
  confirmed direct write to the progress map (`_onPro()`)" — **false after the hoist**. The tier
  is unchanged and still correct (the screen is the UI entry point for the PRO advance and gates
  `phases_2_to_12`), but the justification was restated. Same class as the
  `check_writer_reader_drift.dart` citation corrected in `lib/CLAUDE.md` on 2026-08-02: a rule
  whose stated reason is false reads as coverage it does not have.
- The hoist could have relocated the progress write into a path classified BELOW `account`,
  silently weakening the review gate while every other test stayed green. It did not —
  `docs/blast_radius.yaml:226` gives `pro_phase_advance.dart` its own `account` rule — but that
  is now **asserted in a test** rather than assumed, so the next move cannot regress it.

**Verification.** Six pre-existing test files source-grep `graduation_screen.dart` by path;
moving code out of it turns such assertions vacuously true, which is worse than deleting them
(`feedback_source_grep_false_confidence.md`). All six were re-pointed, and ten assertions were
then individually PROVEN to discriminate by perturbing the source and watching each fail —
files restored from copies afterwards and verified byte-identical by md5, never `git checkout`
(the Unit 7 incident). `pro_phase_advance_behavioral_test.dart` gains group D2: four behavioral
tests, one per outcome arm, against real Hive and real plan generation — coverage that could not
previously exist, because the code was a closure inside a widget callback that nothing could
call.

## OI-89 — the equipment tier is a SOFT preference: a "bodyweight" user is served gym lifts (P2)

- **Status**: CLOSED (2026-08-28, branch `oi89-bodyweight-floor`) — see "How it was closed" below.
- **Blocked on**: nothing. The product question was answered by founder 2026-08-28: the bodyweight
  tier is a HARD floor, and "no equipment needed" means nothing you have to buy.
- **Verified**: 2026-08-28 (measured across all 606 scorecard personas: equipment-violating plans
  201 → 0, violations 528 → 0, missing 0, unsafe 0). Earlier entry: 2026-08-04 (root cause re-read directly in `exercise_selector.dart` +
  `plan_engine/CLAUDE.md`; the flag default re-read in `plan_engine_flags.dart` — the source
  commentary's claim about it did NOT match the code, see below)
- **Identified**: 2026-07-19 · the workout-generator persona sweep (`PlanGenerator.generateV4`,
  18 personas × phases 1-3 = 54 plans, exported by
  `test/plan_generator/persona_matrix_export.dart` in the `persona-sweep-e2e` worktree). The
  sweep's `.xlsx` + commentary were test artifacts and have been deleted as regenerable; this
  entry is the durable record of the one finding inside them that was never filed.
- **Risk class**: plan-engine correctness / user-facing safety-of-expectation
- **What's wrong**: the **bodyweight** persona's generated plan contained **5 picks out of 28 that
  require gym equipment** — Close-Grip Bench Press (barbell + bench), Barbell Curl (×2 slots),
  Standing Calf Raise (barbell), Chin Up (pull-up bar). A genuine no-equipment user opens the app
  and is prescribed exercises they physically cannot perform.
- **Root cause (verified in code, not taken from the sweep's prose)**: `queryV4`'s cascade DROPS
  the `equipment_tier` constraint at **attempt 4** when a muscle slot's on-tier pool is too
  shallow. `lib/shared/repositories/plan_engine/CLAUDE.md:274` lists it plainly —
  `4. attempt4DropEquipment — drop equipment_tier` — and
  `lib/shared/repositories/plan_engine/exercise_selector.dart:660` calls it "the soft tier
  heuristic the cascade itself RELAXES at attempt-4". So the tier is a preference, not a floor,
  BY DESIGN. Contrast the equipment **exclusions** filter, which the same cascade deliberately
  KEEPS at attempt-4 because "an excluded item is a HARD constraint, unlike the soft tier
  heuristic att4 relaxes" (`CLAUDE.md:279`).
- **The mitigation is weaker than the sweep commentary claimed** — worth stating because it
  changes the severity. The commentary described the ⑥ equipment-exclusions feature as
  "(now flag-on)". The code says otherwise: `PlanEngineFlags.equipmentExclusionsEnabled`
  (`lib/shared/repositories/plan_engine/plan_engine_flags.dart:145-153`) reads
  `configBox['enable_equipment_exclusions']` and returns **false** when absent — ship-dark,
  DEFAULT OFF. ~~So protection today requires BOTH (a) that flag switched on AND (b) the user
  actively subtracting "barbell"/"bench"/etc. in the Customize screen.~~ **[(a) NO LONGER
  APPLIES — see the 2026-08-05 update below; and the `:145-153` line range above is stale, the
  getter is now at `plan_engine_flags.dart:169`.]** A bodyweight user who
  never opens Customize gets no protection at all. I could not observe production config from
  the repo, so the discrepancy is recorded rather than resolved — resolve it before sizing the

  > ⚠ **UPDATED 2026-08-05 — condition (a) is now SATISFIED (diagnose `e2d6b8`).** The flag was
  > flipped ON in the `deps-board-equipment` batch; the gate is now the
  > `disable_equipment_exclusions` kill-switch, default ON, so the paragraph above is accurate
  > only as a description of the world before that flip. **Condition (b) still holds and is now
  > the whole of OI-89**: a user who never opens the Customize screen sets no exclusions, so a
  > "bodyweight" user can still be served gym exercises via the SOFT equipment-TIER heuristic.
  > The flip made the item-level EXCLUSION a hard constraint; it did NOT make the tier a hard
  > constraint, and that distinction is precisely what this issue is about. Severity is unchanged
  > for the never-opened-Customize user; it drops to zero for anyone who does set exclusions.
  fix.
- **Product question (this is the real blocker)**: should each equipment tier enforce a **hard
  floor** — never surface a pick whose required equipment the tier cannot provide, falling back
  to a bodyweight substitute or a safe omission — rather than leaking a barbell lift? Today the
  answer is "only if the user manually excludes it, and only if the flag is on."
- **Fix shape (not yet attempted, and NOT to be started before the product call)**: make the
  tier a hard constraint at attempt-4 for the bodyweight tier specifically (the narrowest
  version), with the per-pattern bodyweight floor already used by attempt-5's universal pool
  providing the substitute so a slot is never empty. Needs a behavioral test asserting a
  bodyweight persona's full plan contains zero picks whose `equipment_needed` falls outside the
  tier.
- **Blast radius estimate**: ⚠ **WRONG, and corrected here rather than deleted so the estimate's
  failure mode stays visible.** This read `account` … `no migration, no schema`. The actual batch
  was **platform** and applied **three** migrations (124 `user_profile.equipment_owned`, 125 the
  cloud `exercise_library` re-seed 259 → 292 rows, 126 a single-row correction) plus changes to
  root `CLAUDE.md`, which is path-pinned platform in `docs/blast_radius.yaml`. The estimate was
  made from the SYMPTOM (a few wrong picks in one persona's plan) rather than from the fix, and the
  fix needed a vocabulary, a data restore and a schema column. Rule 14 did apply and founder gave
  explicit authorization for the three `plan_generator.dart` edits.

### How it was closed (2026-08-28)

The tier could never be the safety check: `equipment_tier` is a CURATION hint that
`docs/sot_registry.yaml` itself documented as *"over-tags tolerated"*. The fix keys on
`equipment_needed` instead, via
`effective = tierItems[tier] ∪ equipment_owned − equipment_exclusions` and
`EquipmentCapability.canPerform`.

Three of the five exercises this entry names above were NOT reachable by a tier floor at all —
Standing Calf Raise and Chin Up were tagged `bodyweight` **in the data**, so no tier-level fix
could have seen them. That is why the batch is a data restore as much as a code change: a
normalizer (`632a10b8`) had collapsed 87 authored equipment tokens into 11, and
`equipment_tier` was then derived from the collapsed values.

- Vocabulary 12 → 24 canonical tokens; `equipment_tier` re-derived for all 292 rows and its
  invariant flipped SUBSET → **EQUALITY** (the tolerated over-tag side is exactly what shipped
  Chin Up to bodyweight users); 16 rows left the bodyweight tier.
- 33 new exercises, because the corrections empty pools: `vertical_pull` reached **zero** baseline
  rows, and a first wave that took six patterns to exactly 3 rows still left **331 empty slots**
  under the live floor.
- Records: diagnose `f7b2c4` (+ `c9a7e2`, `b6f4d1`, `d3a8f5`), plan-review record
  `docs/plan-reviews/oi89-bodyweight-floor.md`, closure ledger
  `docs/audit/oi89-bodyweight-floor.closure.yaml`, B-pass
  `docs/reviews/oi89-bodyweight-floor-bpass.md`.
- ⚠ **Residual, NOT a defect and not tracked as one:** the re-derive also removed 38 rows from
  `home_dumbbells` and 16 from `basic_gym` — those tiers were propped up by the same over-tags.
  Every removal was verified correct, but their plans become more generic, and total fallback
  picks rose 1184 → 2719 as the honest price of refusing exercises users cannot do. Surfaced to
  founder; a content investment in more `home_dumbbells`-performable rows would reverse it.

## OI-91 — 138 dead `CLAUDE.md §N` citations remain in live code/test/script comments (P3)

- **Status**: CLOSED · 2026-08-07 · branch `oi91-claude-md-citations`, diagnose `b2f7a4`,
  ledger `docs/audit/oi91_claude_md_citations.closure.yaml` (5/5 terminal). All 138 swept
  (survey command now returns 0), **plus 11 wrong-but-live** that this entry recorded as
  unmeasured. Gate 26 extended to a code zone over `.dart`/`.ts`/`.js`/`.sql`/`.sh` and flipped
  to hard-fail, so the class cannot regrow.
  **Three corrections to what this entry said**, recorded rather than quietly fixed:
  1. **The mapping did not need building.** `docs/superpowers/plans/2026-05-18-claude-md-declutter-plan.md`
     Tasks 2.5–2.13 already record the destination for **all 10** dead section numbers; the
     "fix shape" below proposed reconstructing it and covered 4.
  2. **The §19 destination was wrong.** Pointing §19 at `docs/playbook/common-pitfalls.md` would
     have minted 10 fresh broken pointers — only 1 of the 5 quoted entry titles is in that file.
     `2026-05-18-claude-md-declutter-audit.md` shows the Class A/B entries were *deleted because a
     test became their record*, and in 5 cases that test is the very file carrying the citation.
  3. **Blast radius measured `catastrophic`, not `feature`.** Not the migrations — two comment
     lines in `supabase/functions/razorpay-webhook/index.ts`, which `docs/blast_radius.yaml:41`
     maps to catastrophic, and `blast_radius_from_diff.dart` has no comment-only carve-out. The
     three edited migration files carry no `security definer` text so they stay `platform`.
- **Blocked on**: nothing — closed.
- **Verified**: 2026-08-07 (count re-derived by the entry's own command → 0; gate
  negative-controlled by execution in both directions). Originally 2026-08-05 at filing time.
- **Identified**: 2026-08-05 · the B-pass on `repo-gate-pattern-sweep` (diagnose e7c3b9), which
  caught that that batch's own completeness grep had an input set of 3 directories while its
  artifacts stated the conclusion unscoped.
- **Risk class**: documentation rot / broken agent navigation
- **What's wrong**: root `CLAUDE.md`'s real `##` headings are exactly `0,1,2,2a,3,4,5,6,7`. Every
  citation of any other section number is a dead pointer. e7c3b9 swept and fixed the
  **prescriptive doc/skill zones** (`.claude/**`, `docs/naming_conventions.md`,
  `docs/audit/AUDIT_PLAYBOOK.md` + `LENS_REGISTRY.md`, `docs/playbook/**`) — 20 sites. It did
  **not** touch in-code comments, where 138 remain:

  ```
  grep -rnoE 'CLAUDE\.md.{0,3}§[0-9]+[a-z]?(\.[0-9]+)?' lib/ test/ scripts/ supabase/ integration_test/ \
    | grep -vE '§(0|1|2|2a|3|4|5|6|7)\b' | wc -l      # -> 138
  ```

  Concentrated in `§15` (the old "Source of Truth Rules", now `docs/architecture/sync.md` +
  `docs/sot_registry.yaml`), `§14`, `§11`, `§19`. Examples:
  `lib/core/constants/app_constants.dart:68` (`§14`),
  `lib/core/services/health_write_service.dart:43` (`§15`),
  `lib/core/services/nutrition_read_service.dart:16` (`§15`).
- **Why no gate catches it**: Gate 26 (`scripts/check_claude_md_citations.dart`) walks only root
  `CLAUDE.md`, `AGENTS.md`, `lib/**/CLAUDE.md` and `supabase/**/CLAUDE.md` — i.e. markdown
  contract files, never `.dart` source comments.
- **Two sub-classes, and the second is the dangerous one:**
  1. **Dead** — the cited section does not exist. Fails loudly the moment someone looks.
  2. **Wrong-but-live** — the cited section exists but is the wrong one, so it reads as correct
     and a grep-based sweep filtered on "outside §0-§7" is structurally blind to it. e7c3b9 found
     two by reading rather than grepping (`naming_conventions.md:293` cited "§6 — Coding rules"
     when §6 is MULTI-TIER COVERAGE and the rules are §4.4; `path-mappings.md:21` pointed
     "Discipline / process" at §3 = SCREENS instead of §4). **The 138 above have NOT been checked
     for this class** — that filter cannot see it, so the real number is ≥138.
- **Fix shape (AS SHIPPED — the original proposal is kept below it for the record)**: the
  authoritative old-section → new-home mapping was **already written** in
  `docs/superpowers/plans/2026-05-18-claude-md-declutter-plan.md` (Tasks 2.5–2.13), covering all
  10 numbers. Applied it; handled §19 per the per-entry classes in the sibling
  `2026-05-18-claude-md-declutter-audit.md`; read every remaining live citation for the
  wrong-but-live class (found 11); extended Gate 26 to a code zone and flipped it to hard-fail.

  *Original proposal, which under-scoped the mapping and mis-routed §19:* "build the
  old-section → new-home mapping once (§15 → `docs/architecture/sync.md`/`docs/sot_registry.yaml`,
  §11 → `docs/architecture/ai.md`, §19 → `docs/playbook/common-pitfalls.md`, §9 →
  `lib/shared/widgets/wardroom/CLAUDE.md`, …), apply it, then read every remaining live `§N`
  citation for the wrong-but-live class rather than trusting the filter. Consider extending
  Gate 26 to scan `.dart` comments so this cannot silently regrow — that is the only version of
  this fix that stays fixed." The last sentence was right and is what shipped.
- **Blast radius estimate**: was `feature`; **measured `catastrophic`** — see the Status block.
- **Root cause worth carrying forward**: the declutter **renumbered** rather than only relocated.
  Old §4 = DATA ARCHITECTURE, §5 = DIRECTORY STRUCTURE, §6 = **the coding rules 1-23**,
  §7 = **DATABASE SCHEMA**; those four numbers now hold entirely different content. So any
  pre-2026-05-18 citation of §4–§7 is suspect on sight, and no grep filtered on "outside the live
  range" can see it. That is why sub-class 2 needed reading, not grepping.

## OI-92 — `_git_lock.sh` reclaim: a failed restore destroys the lock it stole, letting two processes hold the mutex (P1)

- **Status**: CLOSED · 2026-08-05 · the automatic reclaim was DELETED, not patched a fifth time.
  The founder ratified the recommended fix below on 2026-08-05. Shipped on branch
  `discipline-tooling-hardening`: `_RECLAIM_MIN_AGE_SECONDS`, the age gate and the
  steal-verify-restore block are gone; a dead-holder lock is REFUSED with the manual `rm -rf`
  printed. The claim path (atomic `mv -T` publish) is untouched — it was never the defective part.
  The stale-lock test was INVERTED rather than deleted and asserts
  `isNot(contains('Reclaiming stale lock'))`, so re-adding a takeover path now fails a test;
  negative-controlled by execution. Diagnose `c9f4e1` (Round-4 section);
  record `docs/plan-reviews/discipline-tooling-hardening.md`.
  **Found while fixing:** the trap handlers cleaned up but did not terminate, so a Ctrl-C released
  the lock and let the wrapper carry on WITHOUT it — pre-existing for INT/TERM, fixed here with
  its own regression test (see the B-pass doc).
- **Blocked on**: nothing — closed.
- **Verified**: 2026-08-05 (round-4 review of the unshipped `discipline-tooling-hardening` branch;
  the `mv -T` failure mode reproduced by direct execution on this exact Git-Bash/MSYS2 toolchain,
  not by reasoning)
- **Identified**: 2026-08-05 · round-4 review of Unit 3a, `scripts/_git_lock.sh` (UNSHIPPED — the
  branch is not merged, so this is not a live defect on `main`; it is the reason 3a+3c did not
  ship).
- **Risk class**: check-then-act / mutual-exclusion. **Fourth occurrence of the identical shape in
  the same file** — round 1 found it in release, round 2 in claim, round 3 in the reclaim's
  decide-then-act, and this is round 4 in the reclaim's restore-then-delete.

### What's wrong

`scripts/_git_lock.sh:288-289` (unshipped branch):

```sh
mv -T "$graveyard" "$lock_path" 2>/dev/null
rm -rf "$graveyard" 2>/dev/null
```

The `rm -rf` is unconditional, but `mv -T` **fails** when the destination exists and is non-empty
— which is precisely the semantic the *claim* side of this same file depends on. Verified by
execution: with a populated `lock_path`, `mv -T graveyard lock_path` exits 1, `graveyard` survives,
and the following `rm -rf` then deletes it.

Sequence (no injected delay needed):

1. Lock holds dead holder `D`, old enough to clear the age gate.
2. Process **A** reads it, decides stale.
3. Process **B** reads the same, reclaims, publishes its own lock. B legitimately holds it.
4. **A** steals — and the file's own comment concedes `mv -T` is "a blind move keyed on the
   DESTINATION's existence, not the SOURCE's content", so A steals **B's live lock**.
5. The path is momentarily empty; **C** publishes there.
6. A's verify correctly notices it stole the wrong thing (`stolen_pid=B` ≠ `holder_pid=D`) and
   enters the restore branch.
7. `mv -T "$graveyard" "$lock_path"` **fails** — C occupies the path.
8. `rm -rf "$graveyard"` runs anyway → **B's lock is destroyed**.
9. B still believes it holds the mutex; C believes it holds the mutex. **Both proceed** — the exact
   condition the file exists to prevent.

### Why the existing comment does not cover this

The code *does* name the window ("a THIRD process claiming the momentarily-emptied path in the
exact window between this steal and its restore") but dismisses it on the wrong grounds: it argues
that process's own `git_lock_release` "would correctly detect it no longer owns `$lock_path` and
refuse to touch it". That is true and irrelevant — nothing gets *destroyed* by C, but B and C hold
the mutex **simultaneously**, which the note never addresses.

The window is also wider than the file's own standard for "realistically reproducible". The age
gate is justified by the claim that "there is no natural multi-second gap anywhere in this file's
own logic … no subprocess-spawn-class delay". But the steal→restore window contains a `sed`
subprocess plus two `echo`s, and this file's header measures a subprocess spawn at **61–89 ms** on
this stack — the same class it says made the round-2 bug reproducible without injection.

### Recommended fix — remove the reclaim, do not add a fourth layer

`flock` is **not available** on this Git-Bash/MSYS2 stack (checked), so kernel-enforced locking is
not an option. With only `mkdir` / `mv -T` / `kill -0`, an atomic "remove the stale lock AND
install mine" does not exist: a directory target makes `mv -T` fail-if-present (right for claiming,
useless for replacing), and a file target makes it replace unconditionally (right for replacing,
useless for claiming).

So delete the automatic reclaim outright — the age gate and the steal-verify-restore block, ~50
lines — and always refuse, printing the manual `rm -rf "$lock_path"` command the file already
emits. The claim path (`mv -T` publish of a fully-populated private candidate) is sound and
independently verified under 5-way contention; it is only the *reclaim* that has now failed review
four times.

Cost: a holder killed without its EXIT trap firing (SIGKILL, power loss) leaves a lock needing one
manual `rm -rf`, with the command already on screen. That is a cheap price for removing an entire
bug family, and it matches the failure direction the file already commits to for the PID-reuse
case — "wait / manual `rm -rf`, never silently proceed concurrently".

- **Blast radius estimate**: `platform` (`scripts/_git_lock.sh` is promoted to platform by the
  unshipped branch's own `docs/blast_radius.yaml` entry, alongside `safe_commit.sh` /
  `safe_push.sh`); no migration, no schema. Not live on `main`.

## OI-98 — notification preferences are push-only: a reinstall overwrites the server's copy with all-enabled (P2)

- **Status**: CLOSED (2026-08-26, batch `oi98-notification-prefs`, diagnose `e4a1b7`)
- **How it closed**: the concept MOVED out of `snapshot_json` into its own column,
  `user_preferences.notification_preferences` (migration 122). The snapshot was a DERIVED
  document — replaced wholesale, by four different writers — and this was the last piece of
  authoritative user intent living in it. Two earlier revisions tried to patch the preferences
  in place and were each blocked by independent review on a different leak from the same root
  cause: a wholesale-replaced document cannot represent *"I know these three settings and
  nothing about the other seven"*, which is exactly a reinstalled device's state.
- **The `Blocked on:` below is ANSWERED, and it resolves opposite to what this entry assumed.**
  `AndroidManifest.xml:21` sets `android:allowBackup="false"` and
  `res/xml/data_extraction_rules.xml` excludes `app_flutter` from BOTH `<cloud-backup>` and
  `<device-transfer>` — so on a real reinstall the Supabase session and Hive die TOGETHER,
  `pushSnapshotNow` returns at `sync_service.dart:936-937` for want of a session, and
  `splash_screen.dart:189` cannot poison anything before sign-in. That push is live only from
  the SECOND cold start onward.
- **⚠ The dominant failure was not the reinstall at all.** All ten server readers took the
  user's NEWEST snapshot row with no fall-through, and three cron functions
  (`rolling-context` nightly for every user, `future-prediction`, `beat-my-coach`) create a
  preference-less row when the day has none. Measured live 2026-08-26: **3 of the 5 users** who
  had ever stored a preference were being ignored outright, no reinstall involved.
- **Residual, tracked separately**: the snapshot fallback (client emission + server read) still
  exists so devices on APK +38 keep being honoured. Its retirement is **OI-141**.
- **Superseded by the fix — kept for the record:**
- **Verified**: 2026-08-07 — by grep across `lib/core/services/` and `lib/features/auth/`, while
  writing OI-75's SoT registry entry. Gate 11 (`check_sync_fanout.dart`) is what forced the
  question: it demanded a `restore_methods:` list and there was nothing truthful to put in it.
- **Identified**: 2026-08-07 · Unit 1 (branch `claude/work-session-3rqcp5`).
- **Risk class**: restore-completeness — the class `docs/architecture/sync.md` exists to prevent.
- **What's wrong**: `notification_preferences` travels UPWARD only.
  - Written into the daily snapshot at `sync_service.dart:842`
    (`'notification_preferences': NotificationPrefsRepository.emissionMap()`), pushed by
    `pushSnapshotNow` (`:870`).
  - **Nothing ever reads it back.** The only read of `snapshot_json` is `:1763-1776`, and it
    selects `fitness_summary` specifically. `grep -rn notification_preferences lib/core/services/
    lib/features/auth/` returns exactly three hits: the emission above, a key name in
    `user_config_migrator.dart:217`, and a comment in `auth_provider.dart:621`. No restore path
    writes the key back to `userBox`.
- **Why this is worse than "prefs don't restore"**: it is not a silent loss, it is an active
  overwrite. On a reinstall `userBox` is empty, so `read()` returns `{}`, so `emissionMap()` emits
  **every key with `{'enabled': true}`** (its documented default — an untouched key emits enabled).
  That map is then pushed and **replaces the server's stored preferences**. A user who had turned
  three notifications off gets all ten back on, and the record of their choice is destroyed rather
  than merely unread. The ABSENT ⇒ SEND rule makes the failure direction "send more", never "send
  less", so nobody complains about silence — they just start receiving notifications they had
  switched off.
- **⚠ Caveat, stated so this is not over-claimed**: the mechanism above is read from code. The exact
  ORDERING on a real reinstall — whether any restore repopulates `userBox` before the first
  `pushSnapshotNow`, and whether the first push happens before or after the user reaches the
  Notifications screen — was NOT traced. Confirm that before designing the fix; if some restore
  path does repopulate the box first, the impact is smaller than described (though the missing
  read-back is still a gap).
- **Fix shape (not attempted)**: give the concept a real restore leg — read
  `snapshot_json->notification_preferences` in the restore path and write it back through
  `NotificationPrefsRepository.write` before the first push. Alternatively, make the emission
  distinguish "user has never set this" from "user set it to enabled", so a fresh install cannot
  masquerade as an explicit all-enabled choice. The second is the more durable fix and is a schema
  question, not just a client one.
- **Related**: OI-75 (its registry entry records `restore_methods: []` with this as the reason);
  OI-80 (the `notification_preferences` reader citations in `snapshot_contract.yaml` are recorded
  as unvalidated).
- **Blast radius estimate**: `account` — touches the sync restore path; no migration, no schema
  change for the first fix shape.

## OI-112 — OI numbering collides across concurrent sessions; BOTH halves now gated

- **Status**: CLOSED · 2026-08-17 · diagnose `d3f1a7` · branch `cycle-time-and-board-gaps`
  · MINT-TIME half: `scripts/check_oi_numbering_unique.dart` (three-point predicate, 20 tests,
  mutation-proven on 4 legs, proven against the live 7th collision on `oi-session-coordination`).
  LANDING half: `scripts/pre-merge-commit.sh` — which had to be WRITTEN, because the claim below
  that landing was already gated was false; git invokes `pre-merge-commit`, not `pre-commit`, for
  an auto-created merge commit and that hook was never installed, so a CLEAN auto-merge ran no
  hook at all. This entry's own open decision ("pre-commit reads a possibly-stale `origin/main`;
  CI is authoritative but only after the push") is resolved by doing BOTH with different
  authority: pre-commit advisory + no fetch (a stale ref makes it MISS, never misfire), CI
  authoritative, and pre-merge-commit at the point both boards first coexist.
- **Blocked on**: nothing — closed.
- **Verified**: 2026-08-13 (a FOURTH and largest collision: six ids at once — see "Partially closed").
  The third hit a DIFFERENT session in parallel and is recorded at
  `docs/plan-reviews/claude-commit-merge-push-process-aae061.md:56-58` — "renumbered to OI-106 at
  merge time, an unrelated batch landed its own OI-105 on `main` first". Two sessions hit this
  class independently within a day, neither aware of the other. The "Measured" bullet below
  enumerates only the first two, which are the ones on THIS branch.
- **Partially closed 2026-08-13**: `scripts/build_oi_index.dart` now **fails closed on duplicate
  ids within the board** (`duplicateIds()`). What this does NOT do is warn
  at **mint time**: two sessions on two branches each picking "the next free number" still both
  validate clean in isolation, because each board is individually duplicate-free. That is the half
  OI-112's fix-shape below addresses.
  Evidence it detects: planting a second `## OI-111` made the generator exit 1 naming the id.
- ⚠ **CORRECTED 2026-08-17 — the landing half was NOT gated either, and this entry said it was.**
  The struck sentence read *"so a corrupt board can no longer render and cannot LAND — the merge
  commit regenerates the index and the gate fires"*. It could not fire. Git invokes
  **`pre-merge-commit`** — not `pre-commit` — for an automatically created merge commit, and only
  FOUR hooks were installed (`pre-commit`, `pre-push`, `commit-msg`, `prepare-commit-msg`). On a
  **clean auto-merge** — precisely the shape diagnose `b7e3d1` documents, where the two boards'
  additions sat in different regions and git combined them silently — **no hook ran at all**. Only a
  *conflicted* merge was covered, and only incidentally, because the human then runs `git commit`.
  `scripts/pre-merge-commit.sh` now exists and `setup-hooks.sh` installs it (FIVE hooks), so the
  claim is true as of this correction rather than before it. Diagnose `d3f1a7`; the identical false
  claim at `docs/diagnoses/2026-08-13-oi-id-collision-renders-silently-b7e3d1.md:56-58` was
  corrected in the same commit.
- ✅ **MINT-TIME HALF CLOSED 2026-08-17** by `scripts/check_oi_numbering_unique.dart` (+ pure
  `scripts/oi_numbering_lib.dart`), exactly the fix-shape below. It resolves this entry's own open
  decision — "pre-commit reads a possibly-stale `origin/main`; CI is authoritative but only after
  the push" — by doing **both**, with different authority: pre-commit is advisory-fast and does not
  fetch (a stale ref makes it MISS, never misfire), CI is authoritative, and `pre-merge-commit` runs
  it where both boards first coexist. THREE-point predicate, because a two-point HEAD-vs-mainline
  comparison would call every ordinary title edit a collision. Proven against the live seventh
  instance: run on unmerged branch `oi-session-coordination` it exits 1, prints both OI-128 titles
  and names the next free number. 20 tests, mutation-proven on 4 legs.
- ⚠ **Evidence undercount, corrected 2026-08-17.** The `Verified: 2026-08-13` line was never updated
  after two further instances: the `0cb4120a` renumber (2026-08-16, OI-106/107/108 → OI-125/126/127,
  detected by a human **3 days 0 h 34 m** after `0e4d97cd` pushed the collision) and the still-live
  OI-128 clash. Count as of 2026-08-17: **six** collisions, five renumber commits, three of them on
  2026-08-13 alone.
  Mutation-proven — rebuilding the check over `parseOpenIssues` (which drops CLOSED entries)
  reddens exactly the OPEN-vs-CLOSED test; neutering it reddens 4.
  Tests: `test/contracts/oi_index_test.dart` (group "OI-112 scar").
- **Identified**: 2026-08-09 · B-pass Finding 4 on `d4a8de00`
- **Risk class**: cross-session process drift — silent, and both sides validate clean
- **What's wrong**: §4.13 worktrees isolate the git INDEX; they do NOT isolate the shared
  `## OI-NN` numbering NAMESPACE in `docs/audit/open_issues.md`. Two sessions filing issues
  concurrently both pick "the next free number" against *their own* base and both are correct in
  isolation. Nothing — not the OI index generator, not Gate 40, not the merge — compares the two.
- **Measured**: 2026-08-08 mine claimed OI-96/97/98, already taken on `origin/main`; renumbered to
  99/100/101. Within hours `origin/main` advanced again (`c90fc4c0`) with its own OI-99, so mine
  moved to 100/101/102. **Two collisions, one day, same branch.** The manual renumber is a patch,
  not a fix — it goes stale the moment another session lands.
- **Why it matters beyond tidiness**: an OI number is a citation target. Diagnose-docs, closure
  YAMLs and commit messages all cite `OI-NN`. A collision silently repoints someone else's
  citation at your issue.
- **Fix shape**: `scripts/check_oi_numbering_unique.dart` — parse `## OI-(\d+)` from HEAD and from
  `origin/main`, fail when the same number carries a different title. **Open decision:** a
  pre-commit gate would read a possibly-stale local `origin/main` ref (fails safe, but weakly);
  CI is authoritative but only catches it after the push. Probably both, with CI as the real gate.
  A cheaper complement: allocate from a high, per-session-reserved block instead of "next free".
- **Blast radius estimate**: `feature` (a script plus wiring).

## OI-102 — local `test/contracts/` takes 18.6 min on every commit, and the lever is not yet known (P2)

- **Status**: CLOSED · 2026-08-11 · ADR-0018 removed the trigger: `pre-commit.sh` no longer runs
  `flutter test test/contracts/` at all, so the 18.6 min is no longer paid per commit. **The
  measurement question this was blocked on is NOT answered** — it is carried forward as OI-106
  rather than closed with it. Closing on "the symptom is gone" while the open question dies
  quietly would be the deferral §4.2 bans; the successor entry is what makes this terminal.
- **Blocked on**: nothing — closed. (Was: a clean measurement. That now blocks OI-106.)
- **Verified**: 2026-08-11 — full JSON-reporter run, `{"success":true,"type":"done","time":1114598}`.
- **Identified**: 2026-08-11.
- **Risk class**: developer-cycle-time; secondarily `--no-verify` pressure (the original I10 motive).
- **What's wrong**: `pre-commit.sh:66` runs `flutter test test/contracts/` — **477 files, 18.6 min,
  on every commit**. The I10 fast/full split (2026-05-21) sized this at ~3 min when `test/contracts/`
  held **179** files; it now holds 477, i.e. ~69% of the whole 694-file suite. The "fast path" has
  eroded into most of the suite.
- **What has ALREADY been ruled out — do not re-derive**:
  - *Optimising the slow files*: distribution is flat. Top 10 files = **8.4%**, top 25 = 15.5%,
    top 200 = 59.7%. Reaching ~5 min needs a 73% cut; no subset optimisation gets there.
  - *`flutter test` → `dart test` migration*: measured **~18%** against a ≥50% bar set in advance
    (warm marginal cost 0.83s vs 0.33s/file; fixed 9.2s vs 3.7s). 447 of 477 files import
    `flutter_test` while only 8 use `testWidgets`, so the migration is broadly *possible* — it just
    does not carry the problem. **Zero prior art in the repo**; the one untouched idea here.
  - *`--concurrency` (16 cores, default is cores/2 = 8)*: **UNPROVEN, and the obvious measurement is
    a trap.** j8-cold 191s → j16-warm 91s looks like 2.1×, but the control refutes it: j8-**warm**
    90s, j16-**warm** 170s. Runs alternate ~90s/~170s with no relationship to the flag.
  - *A "37% fixed per-file startup" figure*: **wrong** — inferred from a 6.8s minimum span, but
    spans are measured under 8-way contention and include queueing (sum-of-spans 8777s ≫ wall 1114.6s).
  - *Diff-conditional test selection*: rejected in `docs/adr/0013-blast-radius-tiered-gating.md:52-67`
    alt #3. 93 contract tests read `docs/` and 265 reference `lib/`, so the dependency graph is broad.
- **Fix shape (measurement first, no predetermined outcome)**: on a QUIET machine (no subagents —
  contamination is why the above is unproven), use **counterbalanced blocks** (`j8×3, j16×3, j16×3,
  j8×3`) or randomised order, n≥5 per arm, reporting the paired distribution. **Alternating
  j8/j16 is the single worst design here** — it is perfectly aliased with the observed period-2
  oscillation. Identify the oscillator BEFORE assigning a 1.9× swing to either arm. Also unexplained
  and probably the real lead: **CI runs 690 files in 417s while local runs 478 in 1114.6s** — ~3.9×
  slower per file locally at ~4× the parallelism.
- **Interaction**: OI-86 (concurrent `flutter test` runs corrupt each other's Hive state) is the
  named hazard for any concurrency increase; 112 contract files use Hive. It is intermittent, so
  "twice consecutively green" does NOT clear it.
- **Blast radius estimate**: `platform` (`scripts/pre-commit.sh` is `docs/blast_radius.yaml:101`).

## OI-105 — the `Supabase Integration Tests` CI job verified NOTHING: the repo had zero Actions secrets (P2)

- **Status**: CLOSED · 2026-08-30 · the job now verifies something, proven on run
  `33296974513` (HEAD `7fc359f3`, push to `main`) rather than inferred from the secrets existing.
  **Both real steps report `success`, NOT `skipped`** — which is the whole distinction this entry
  was filed on, since a skipped step rolls up to a green job just as happily. `Run Edge Function
  tests` ends `00:25 +22: All tests passed!`, and the announce step printed its positive branch:
  *"All four Supabase test secrets are configured — integration tests will run."* The `::warning::`
  has stopped firing, which the fix shape below nominated in advance as "the cheapest available
  proof".
- **Status was**: OPEN — blocked on a founder-only action. Filed 2026-08-11, secrets landed
  2026-08-12/14, closed once a run was actually read rather than assumed.
- **Blocked on**: nothing. All four secrets exist —
  `gh api repos/upendraprasad19/AVYA/actions/secrets` → `{"total_count":4,...}`:
  `SUPABASE_URL` + `SUPABASE_ANON_KEY` (2026-08-12T15:44Z), `SUPABASE_TEST_EMAIL` +
  `SUPABASE_TEST_PASSWORD` (2026-08-14T17:49Z, arriving with the four-input guard so a
  three-secret run cannot reach a live `signInWithPassword` holding an empty field).
- **Verified**: 2026-08-30 — the RAW response again, deliberately, for the reason the original
  entry gave: an empty `--jq` result and a swallowed auth error are indistinguishable at the shell
  (`feedback_green_check_input_set_width`). **Then the check was widened past "secrets exist",
  which is NOT what this entry asked for** — four present secrets plus a green job is ALSO the
  exact observable state the bug produced, so the step-level conclusions and the job log were read
  instead. **All six originally-uncovered files ran**: `webhook_test`, `redeem_referral_test`,
  `ai_proxy_test`, `pgvector_test` (`test/edge_functions/`), `auth_restore_test`,
  `sync_service_test` (`test/supabase/`) — plus three added since
  (`http_override_restored_test`, `prepare_binding_order_test`, `cleanup_target_guard_test`).
- **The one prediction that did NOT hold, recorded rather than quietly dropped**: step 2 of the fix
  shape said to *"expect the job to go RED on first real run and treat that as the point, not a
  regression"*. It is green. ⚠ This closure reads exactly ONE run and says nothing about the runs
  between 2026-08-14 and today — whether the first real run was red and triaged is a question this
  entry does not answer, and should not be read as answering.
- **Identified**: 2026-08-11 · carried out of the gate-registry/CI-speedup batch, where it was
  recorded only as a "founder-only owed" line in a memory index. Filed as a real OI once the §5
  rule change made clear that a residual living only in agent memory is not tracked at all
  (`feedback_spawn_task_chip_not_durable`, same class).
- **Risk class**: silent-inert-gate / false assurance — a green job that proves nothing, which is
  strictly worse than an absent job because it occupies the slot where real assurance would go.
- **What's wrong**: `.github/workflows/test.yml:334` defines `supabase-tests`, gated
  `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`. Its two real steps
  (`:363` Run Supabase tests, `:371` Run Edge Function tests) each carry
  `if: env.SUPABASE_URL != ''`. With no secret configured, **both steps skip and the job reports
  success.** The `ci-speedup` batch (2026-08-10) added an honest announce step at `:344-350` that
  emits `::warning title=Supabase integration tests did not run::… this job verifies NOTHING. It
  is green because there is nothing to fail, not because integration tests passed.` — so the
  condition is *disclosed*, but disclosure is not coverage, and a `::warning::` on a green run is
  read by nobody.
- **What is actually uncovered** — 6 test files, and the selection is not incidental; it is
  precisely the surface with the worst P0 history in this repo:
  `test/edge_functions/webhook_test.dart` (Razorpay — see the TDZ webhook P0 in
  `closed_issues.md:708`), `redeem_referral_test.dart`, `ai_proxy_test.dart`, `pgvector_test.dart`,
  `test/supabase/auth_restore_test.dart`, `sync_service_test.dart`.
- **Fix shape (founder action, then a verification step that is NOT optional)**:
  1. Add `SUPABASE_URL` + `SUPABASE_ANON_KEY` as repository Actions secrets. Use the **fitness-app**
     project `dedsavbjuwgarrhphgnl` (CLAUDE.md §2a — there are two Supabase projects on the account
     and the other one is a different app entirely). Anon key only; never the service-role key.
  2. **Expect the job to go RED on first real run and treat that as the point, not a regression.**
     These 6 files have never executed in CI. Budget for triage rather than assuming green.
  3. Once green, the `::warning::` at `:344-350` stops firing — that is the observable confirmation
     the job began verifying something, and it is the cheapest available proof.
- **Do NOT "fix" this by deleting the job.** That trades a disclosed gap for a silent one. The
  announce step is the current mitigation and should stay until the secrets land.
- **Blast radius estimate**: `platform` (`.github/workflows/test.yml` is `docs/blast_radius.yaml:184`)
  IF the workflow is edited; adding secrets alone touches no tracked file and has no blast radius.
## OI-115 — cleanup() can DELETE from 12 PROD tables and its guard cannot refuse the scenario it was written for (P1)

- **Status**: CLOSED (2026-08-15, `acffbd43` + `e4121c14`)
- **Resolution**: boundary re-keyed on a `const Set` of QA **uuids**
  (`assertDisposableTarget`), which does not move when the credential moves — the defect
  this entry documents. Applied at all THREE delete sites incl. the two in
  `pgvector_test.dart` that bypass `cleanup()`, AND at `ai_proxy_test.dart`'s WRITE path
  (bullet 2, "same boundary question"). Bullet 3 (LateInitializationError masking) fixed
  via `setUpSucceeded`. Mirror-tested: the guard runs BEFORE any delete, proven by moving
  it after the loop and watching only that assertion redden.
- **Blocked on**: nothing — the work is understood and scoped; it needs a design decision
  between a uuid allow-list and a runtime self-check, then implementation.
- **Verified**: 2026-08-13 — round-2 context-blind review, reproduced by direct read of
  `test/supabase/supabase_test_helper.dart:30,148,198` on branch `supabase-ci-http-mock`.
- **Identified**: 2026-08-13 (split out of diagnose 3b7e1c per §4.12.1).
- **Risk class**: production data loss. Bounded TODAY only because `qa@icanbefitter.com` does
  not exist, so sign-in fails and `cleanup()` early-returns on a null `_userId`.
- **What's wrong**: `SupabaseTestHelper.cleanup()` issues `DELETE` across 12 tables of the
  production project (`dedsavbjuwgarrhphgnl`) and CI runs it on every push to `main`. A guard
  was written (branch `supabase-ci-http-mock`, commits `29e8484e` + `a2f50316`) but it compares
  the signed-in email against `disposableTestEmail` — the SAME constant `signIn()` uses via
  `testEmail = disposableTestEmail`. **Both sides move together**, so the scenario the guard's
  own doc comment names — "repoint the constant at an account that DOES exist, because sign-in
  fails" — passes straight through. Real accounts at risk: `test2@gmail.com` … `test7@gmail.com`
  (test7 holds 133 `memory_embeddings` rows, verified by read-only SELECT).
  A pin test detects a repoint but runs in the SAME `flutter test test/supabase/` invocation as
  the file issuing the deletes, alphabetically after it — detection no earlier than the damage.
- **Also in scope, same file family**:
  - `test/edge_functions/pgvector_test.dart` deletes from `memory_embeddings` in setUp and
    tearDownAll; its guard has the same aliasing weakness and cannot fire.
  - `ai_proxy_test.dart` writes `ai_coach_interactions` and burns the signed-in user's daily
    quota — not a DELETE, same boundary question.
  - The guard's `tearDownAll` path throws `LateInitializationError` when `setUpAll` failed
    (which it does today), adding noise to the first-real-run triage OI-105 budgeted for.
- **Fix shape (not attempted)**: make the boundary independent of the sign-in identity — either
  an allow-list of QA **uuids** checked against `targetId`, or a runtime self-check inside
  `assertDisposableTarget` validating the constant's own value, so a repoint fails in the same
  call rather than in another file's test. Prefer the uuid list: an email is a mutable label, a
  uuid is the thing rows are actually keyed by.
- **Where the work is**: branch `supabase-ci-http-mock` (commits `29e8484e`, `a2f50316`) — a
  guard, its tests, and 3 mutation proofs already exist and are worth keeping; the boundary
  design is what needs redoing. Round-2 review findings are the spec.
- **Blast radius estimate**: `feature` for the helper alone; `platform` if the fix also moves the
  QA password to a secret (that requires editing `.github/workflows/test.yml`).

## OI-116 — the QA password is committed to git, and creating the account would put it on prod (P2)

- **Status**: CLOSED (2026-08-15, `e4121c14`)
- **Resolution — SUPERSEDED in part**: all four credential sites now read
  `String.fromEnvironment`; `git grep` for both literals is empty outside dated records;
  `hasCredentials` widened 2→4 inputs; `auth_helper` gained the skip-gate it never had;
  `.env.example` + `DEVICE_TESTING.md` document the keys. The entry also asked for
  `qa@icanbefitter.com` to be created — it was NOT; a different account was used instead.
- **Blocked on**: founder — creating `qa@icanbefitter.com` and adding a `SUPABASE_TEST_PASSWORD`
  Actions secret are account/settings actions an agent cannot perform.
- **Verified**: 2026-08-13 — `git grep QA_Test_2024` across the whole worktree.
- **Identified**: 2026-08-13 (split out of diagnose 3b7e1c per §4.12.1).
- **Risk class**: credential exposure. Not yet realised — the account does not exist, so the
  password currently unlocks nothing.
- **What's wrong**: `QA_Test_2024!` is a literal in `test/supabase/supabase_test_helper.dart`,
  `test/edge_functions/{ai_proxy,pgvector}_test.dart` and
  `integration_test/helpers/auth_helper.dart`, plus `supabase/seed_qa.sql`,
  `integration_test/app_test.dart` and `testing/e2e/*.md`. Creating the account with it would put
  a login on the PRODUCTION project whose password anyone with repo access can read. It is in git
  history regardless, so the account must be created with a NEW password whatever else happens.
- **What has ALREADY been done — do not re-derive** (branch `supabase-ci-http-mock`, `29e8484e` +
  `a2f50316`): all four live uses converted to `String.fromEnvironment('SUPABASE_TEST_PASSWORD')`;
  `hasCredentials` widened to three inputs with a pure `credentialsComplete()` predicate so it is
  mutation-testable; `test.yml` given the env var and quoted `--dart-define`s on both steps; the
  announce step widened to name all three missing secrets.
- **What round 2 found still wrong there**: `integration_test/helpers/auth_helper.dart` has NO
  skip-gate, so device/integration runs would attempt sign-in with an EMPTY password instead of
  skipping — fixing a security issue created a functional one. `SUPABASE_TEST_PASSWORD` is absent
  from `.env.example` and `docs/operations/DEVICE_TESTING.md`, and `scripts/run-device-tests.sh`
  passes only `--dart-define-from-file=.env`. `testing/e2e/01_auth_onboarding.md:15,93` still
  publishes the literal. The `hasCredentials` delegation test is tautological once all three
  secrets exist.
- **Fix shape**: finish the above, then founder creates the account with a NEW password and adds
  the secret. Only then can the `supabase-tests` job go green — and per OI-105 expect the first
  real run to surface genuine failures.
- **Blast radius estimate**: `platform` (`.github/workflows/test.yml`).
## OI-121 — the QA fixture account `qa@icanbefitter.com` does not exist, so `test/supabase/` cannot pass (P1)

- **Status**: CLOSED (2026-08-15, `e4121c14`)
- **Resolution — SUPERSEDED, not satisfied**: this entry is worded around CREATING
  `qa@icanbefitter.com`. That account was abandoned rather than created. The suites now
  sign in as `test6@gmail.com` via the `SUPABASE_TEST_EMAIL` / `SUPABASE_TEST_PASSWORD`
  secrets, so the stated blocker no longer exists — but nobody ever created the account
  this entry asks for, and saying "done" without that distinction would be false.
- **Blocked on**: FOUNDER — genuinely not agent-actionable. Creating an account (or setting its
  password) is a prohibited action for the agent, and it must be done against the live prod project.
- **Verified**: 2026-08-12 — queried the authoritative source, not inferred from the error:
  `select email, created_at from auth.users where email = 'qa@icanbefitter.com'` on
  `dedsavbjuwgarrhphgnl` returned **zero rows**.
- **Identified**: 2026-08-12, while fixing `a7e3c1` (the HTTP-mock bug that was hiding this one).
- **Risk class**: CI correctness. `main` is RED until this is resolved.
- **What's wrong**: `test/supabase/supabase_test_helper.dart:21-22` signs in as
  `qa@icanbefitter.com` / `QA_Test_2024!`. That user is not in `auth.users`. Both integration test
  files die in `setUpAll`, so **zero assertions in either file have ever executed**. This was
  invisible until `a7e3c1` was fixed, because the `TestWidgetsFlutterBinding` HTTP mock was
  answering every request with a fabricated 400 before any of it reached Supabase.
- **How to confirm the fix worked**: after the account exists, the live error changes from
  `AuthApiException(... invalid_credentials)` to the tests actually running. Run locally first:
  `flutter test --dart-define-from-file=.env test/supabase/auth_restore_test.dart`.
- **⚠ Read before creating it — the tests WRITE to the live prod project.**
  `supabase_test_helper.dart:116-143` deletes rows for the signed-in user across 12 tables
  (`user_profile`, `user_preferences`, `workout_logs`, `nutrition_logs`, `weight_logs`, `streaks`,
  `user_progress`, `body_measurements`, `sleep_logs`, `ai_coach_interactions`, `memory_embeddings`,
  `user_daily_snapshots`) in `setUp` **and** `tearDownAll`. That is correct for a throwaway fixture
  account and catastrophic for a real one, so the account MUST be a dedicated QA user and MUST NOT
  be an address that is ever used as a real login. It also means every green CI run mutates prod
  data for that user — acceptable for a fixture, worth stating explicitly rather than discovering.
- **Options, since this is a real decision and not just a chore**:
  1. Create the QA user in the prod project and leave the job running against prod (what the code
     assumes today).
  2. Point the job at a separate Supabase project / branch so CI never writes to prod at all.
  3. Unset the two Actions secrets, which restores the skip and a green `main` — but that returns
     the job to verifying nothing, which is precisely what OI-105 was filed about. Listed for
     completeness, not recommended.
- **Blast radius estimate**: `account` (`test/supabase/**` plus, for option 2, `.github/workflows/test.yml`).

## OI-129 — orphaned `pr-ag-handoff-gaps`: the "32 MB of UNTRACKED QA work" was a MEASUREMENT ARTEFACT; every byte was in git

- **Status**: CLOSED · 2026-08-17 · directory removed by the founder after the recoverability proof
  was re-run immediately before the delete (**526 non-build files vs 9821 blobs, 0 unmatched** — the
  blob count had moved from 9766, so the proof was redone rather than cited from earlier in the
  session). `.claude/worktrees` now holds **9 directories and `git worktree list` reports 9** — zero
  orphans, the first time those two numbers have matched since the orphan class was identified.
  **The entry is kept in full below rather than trimmed on close, because what it got WRONG is the
  reusable part** — see "REFUTED 2026-08-17".
- **Status was**: OPEN · **the blocker was purely mechanical, and it was NOT the one this was filed
  on.** Every
  file was proven recoverable from git (0 of 526 unmatched — see "REFUTED 2026-08-17"), so nothing
  is at risk and no founder judgement about what to keep is owed any more. What remains is that the
  `rm -rf` was refused by the harness safety classifier on 2026-08-17. That refusal is CORRECT for a
  recursive delete and was not worked around; it needs a human to run it or to approve it.
  **The premise this entry was filed on was wrong, twice, in the same direction, and the retraction
  is the point of the entry now** — see "REFUTED 2026-08-17".
- **Verified**: 2026-08-16 — inspected directly while auditing retirement candidates.
- **Identified**: 2026-08-16
- **Blocked on**: nothing — closed. (Was: FOUNDER, for a much smaller reason than when this was
  filed. It is no longer *"decide what is worth salvaging"* — that question is dissolved, nothing
  needs salvaging. It is now only *"run the recursive delete the classifier refused"*:
  `rm -rf .claude/worktrees/pr-ag-handoff-gaps` (~32 MB, 526 non-build files, all provably in git).
- **What's missing**: `.claude/worktrees/pr-ag-handoff-gaps` is a FULL repo checkout (`lib/`, `test/`,
  `supabase/`, `docs/`, `memory/`, `scripts/`, `telegram-bot/`, `web/` — 827 entries outside
  `build/`, 32 MB) with **no `.git`**, so `git worktree list` cannot see it and `retire_worktree`
  classifies it `ORPHAN ... manual review`. It holds content that exists NOWHERE in git:
  - `QA_FINDINGS.md` (2121 B, 65 lines) — opens with **"Critical Issue: Health Plugin
    ClassCastException"**, `MainActivity cannot be cast to b.l`, stated impact: *"Google Fit / Health
    Connect integration will NOT work"*.
  - `QA_TEST_EXECUTION.md` (1918 B) — QA report dated 2026-03-30 against `app-dev-release.apk`
    (100.3 MB) on a Pixel 5 emulator, status IN PROGRESS.
  - `memory/project_wardroom_handoff_enforcement.md`, plus 25 files under `screenshots/`.
  Both `.md` files confirmed untracked: `git log --all -- **/<name>` and `git ls-files **/<name>`
  are both empty.
- **Required action, in order**: (1) triage `QA_FINDINGS.md` — the ClassCastException may still be
  live and was never filed; if it reproduces it needs its own OI + diagnose-doc. (2) salvage anything
  worth keeping into the repo. (3) only then delete the directory.
- ⚠ **Do NOT delete this as routine worktree hygiene.** Of the three content-bearing orphans it is
  the ONLY one with unique content — `wardroom-handoff-enforcement` (100 KB) and the stray
  `.dart_tool` (1 KB) are pure build output. `retire_worktree` is right to refuse it; `--force` would
  destroy the only copy.
- **Orphan-scan cleanup 2026-08-17** (still true): the other two orphans this entry named as pure
  build output were re-checked (`find | grep -v build/ | wc -l` = **0** for both) and REMOVED;
  `.dart_tool` is now skipped by the orphan scan entirely (it is a tooling artifact, not a
  worktree). `.claude/worktrees` went 15 dirs / 4 orphans → 11 dirs / 1 orphan — this one.

### ⚠ REFUTED 2026-08-17 — everything above about unique content is wrong, and both errors share ONE cause

  Re-checked before acting on the founder's "if Health Connect works, can we delete it?". Every
  claim of unique content failed:

  1. **The three "untracked" files are TRACKED and present in main.** `git ls-files QA_FINDINGS.md`
     → returns the path; same for `QA_TEST_EXECUTION.md` and
     `memory/project_wardroom_handoff_enforcement.md`. All three are byte-identical to main's copy
     after CRLF normalization (`diff <(tr -d '\r' <orphan) <(tr -d '\r' <main)` → **0 lines** for
     each). All **25** screenshots are tracked too (`git ls-files screenshots/ | wc -l` = 25).
  2. **The "20 paths matching NO commit" is 0 of 9.** The orphan holds 246 `.dart` files under
     `lib/` vs main's 470; 9 paths exist only in the orphan. Every one's content matches a real
     historical commit once line endings are normalized — checked **exhaustively over each path's
     full history**, not sampled: `ai_coach_screen` → `b8c7a5c3`, `prelog_diff` → `853681bd`,
     `weight_sparkline` → `c0102b1e`, `hydration_section` → `ef878afb`, `my_submissions_screen` →
     `8a4e30d6`, `profile_screen` → `95ed1f72`, `active_workout_screen` → `1b27a6d2`,
     `train_screen` → `9eea0be6`, `community_review_sheet` → `f8669b54`. They are absent from main
     because they were split into subdirectories or retired (`6ed2d9a6` "split 3 god-screens",
     `7d89b76c` "split active_workout_screen", `bf2b60de` "retire hydration_section"), not because
     they hold newer work. `test/plan_engine_v3_test.dart` likewise has 3 commits in history.

  **The single root cause of BOTH: a representation mismatch that silently empties the input set.**
  The orphan's files are CRLF; git blobs are LF, and a git pathspec of `**/<name>` does not match a
  root-level file. So `git hash-object <crlf-file>` matched no blob and `git ls-files **/QA_FINDINGS.md`
  returned nothing — and in both cases an **empty result was read as a positive finding**
  ("uncommitted WIP", "untracked"). Same class as the em-dash `systemEncoding` bug found in
  `check_oi_numbering_unique.dart`'s own first live run the same day: an encoding difference makes a
  real match invisible, and nothing distinguishes "no match" from "could not compare".
  `feedback_green_check_input_set_width` names it; naming it did not prevent it. **Normalize the
  representation before concluding absence, and state which normalization was applied.**

- **Health-plugin bug: FIXED, and it was fixed the day it was reported.** `QA_FINDINGS.md` logged
  the ClassCastException at `03-30 13:55:10` and prescribed `FlutterActivity` →
  `FlutterFragmentActivity`. `android/app/src/main/kotlin/com/icanbefitter/icanbefitter/MainActivity.kt:5`
  reads `class MainActivity : FlutterFragmentActivity()` today; `6421178e` (2026-03-23) had
  `FlutterActivity`, `8a5df734` (**2026-03-30**) changed it. No OI or diagnose-doc was owed — the
  other session's triage was right. ⚠ **Source-level only**: this proves the cast cannot throw, not
  that Health Connect syncs end-to-end (that needs a device). What DID protect it: **nothing** — no
  test pinned the superclass, so a one-line revert to `FlutterActivity` would silently re-break
  health sync, and the failure is invisible (steps read 0, which looks like "no data today"). Closed
  in this same batch rather than filed as a new OI, per §4.2: `test/contracts/`
  `main_activity_flutter_fragment_activity_test.dart` pins the superclass by regex, asserts the
  negative separately (`FlutterFragmentActivity` CONTAINS `FlutterActivity`, so a naive `contains`
  check reads true on the correct file), and is mutation-proven — restoring the exact 2026-03-23
  `FlutterActivity` declaration reddens **3 of its 4** tests. The behavioral counterpart is a device
  test and belongs with the Patrol flows in `docs/operations/DEVICE_TESTING.md`.
- **Exhaustive recoverability proof (2026-08-17)** — this is what makes the delete safe, and it is
  stated so nobody has to re-derive it. Every one of the **526** non-build files
  (excluding `build/`, `node_modules/`, `.dart_tool/`) was hashed BOTH raw and CRLF-normalized and
  looked up against the full object database (`git cat-file --batch-all-objects`, 9766 blobs).
  **0 of 526 unmatched.** Not sampled — every file. Method matters here: hashing raw only is
  exactly the mistake that produced the original false finding, so both representations are checked
  and the normalization is named.
- **Resolution**: nothing to salvage. Directory removal is the only step left and is pending the
  founder action above.

## OI-132 — a migration is LIVE in prod with no file, no manifest entry and no diagnose-doc — and its absence DEFEATS Gate 31 (P1)

- **Status**: CLOSED · 2026-08-20 · diagnose `c8e5b3` · branch `claude/oi-pending-hold-weeks-1od97o`
- **Blocked on**: nothing — closed. Both halves shipped: the reconstruction AND the Gate 31 re-scope.
- **Closed by**: `supabase/migrations/121_log_table_retention.sql` (reconstruction, DO-NOT-APPLY,
  recovered verbatim from `schema_migrations.statements`), its `backups/applied_migrations.json`
  entry, the missing `c8e5b3` diagnose-doc, four `CRON_REGISTRY.md` rows, the new
  `backups/live_cron_jobs.json` snapshot, and Gate 31 re-scoped to read that snapshot as a
  second, file-independent input. Registry now covers **28 of 28** live jobs (was 24 of 28).
  Mutation-proven on five shapes — including the OI-132 scenario itself (delete the migration
  file; the gate still catches all four jobs via the snapshot). Gate 31 was PROMOTED out of the
  grandfathered set in `gate_test_ledger.yaml` as part of this.
- **Not closed by this, and deliberately so**: the snapshot proves registry-vs-snapshot parity,
  NOT snapshot-vs-live freshness. Nothing in CI can prove the latter — the repo has zero Actions
  secrets (OI-105) — so a live query there would silently skip, which is the same
  passes-because-it-never-ran failure one layer up. Regenerating the snapshot is a documented step
  on any migration that schedules or unschedules a job.
- **Verified**: 2026-08-20 — every claim below read from live `dedsavbjuwgarrhphgnl` or from the repo directly during the FOB-1/FOB-5 Hermes pass. Not inferred.

Live `supabase_migrations.schema_migrations` holds `20260815155823 / log_table_retention`. Its
stored statement is self-describing and destructive:

```
-- Destructive?: yes -- deletes ~29,044 run records and ~10,654 client_errors rows on the
--                      first pass; rows are NOT recoverable
-- Rollback strategy: inline -- reverse block in the repo file   <-- there is no repo file
-- Linked diagnose-doc: c8e5b3                                   <-- does not exist
```

Every corroborating artefact is absent:

| probe | result |
|---|---|
| `docs/diagnoses/` grep `c8e5b3` | NOT FOUND |
| repo-wide grep `c8e5b3` (md/json/yaml/sql) | no output |
| grep `jrd_retention_daily\|cleanup_client_errors` | NOT REFERENCED ANYWHERE |
| grep `retention` in `backups/applied_migrations.json` | 0 entries |

⚠ **Corrected 2026-08-20: it created FOUR cron jobs, not two.** The original filing said two,
inherited from a reviewer that had filtered on retention-shaped names; recovering the migration's
actual statements and re-querying `cron.job` shows four, **all active**:

```
jobid | jobname                       | schedule    | active
   33 | jrd_retention_daily           | 22 4 * * *  | t
   34 | client_errors_retention_daily | 25 4 * * *  | t
   35 | jrd_vacuum_daily              | 38 4 * * *  | t
   36 | client_errors_vacuum_daily    | 41 4 * * *  | t
```

`docs/operations/CRON_REGISTRY.md` lists **none of the four**. The two extra are
`VACUUM (ANALYZE)` jobs — not row-destructive, but equally unregistered and equally invisible to
Gate 31.

One thing the recovered SQL gets RIGHT, worth recording so the reconstruction does not "fix" it:
both `cleanup_*` functions are `SECURITY DEFINER` and carry
`REVOKE ALL ... FROM PUBLIC` **plus** `REVOKE ALL ... FROM anon, authenticated` and
`GRANT EXECUTE ... TO postgres` — the exact grant hygiene migration 120 got wrong (a9d3f1).

**The compounding half, which is the real finding.** Gate 31
(`scripts/check_cron_registry.dart:31`) enforces registry parity by scanning
`supabase/migrations/*.sql` for `cron.schedule(...)` calls. Because this migration has **no
file**, its two `cron.schedule` calls are invisible to the gate built to catch exactly this. The
gate reports green while two undocumented destructive jobs run daily against prod. A missing file
does not merely skip the gate — it defeats it by construction, and no amount of tightening the
scan fixes that, because the scan's input is the thing that is missing.

**Full live-vs-repo set difference** (115 live rows vs 124 `.sql` files) — live rows with no repo
file: `add_gdpr_referral_community_tables`, `028b_fix_coach_signals_formulas`,
`028c_robust_interval_extraction` (all three pre-existing and old),
`revoke_anon_authenticated_...engagement` (= 120b, deliberate and documented), and this one.

**Not caused by the FOB batch** — applied 2026-08-15, five days before branch
`claude/oi-pending-hold-weeks-1od97o` was cut. Surfaced only because the L13 lens asked for the
live-vs-manifest comparison.

**Fix shape:** author `121_log_table_retention.sql` from the live statements, add its manifest
entry and the `c8e5b3` diagnose-doc, register both cron jobs. Then the part worth arguing about:
Gate 31 needs a source of truth that is not the migration files — a live `cron.job` enumeration
against the registry would have caught this on day one, and is the same shape as the live-query
allowlist gate OI-78 has been asking for since 2026-07-31.

---

## OI-133 — 92 analytics rows are already inside the LLM's retrievable memory; the fix stops new ones and does not remove them (P1)

- **Status**: CLOSED · 2026-08-24 · `rolling-context` redeployed from the founder laptop (v18 → **v19**, `verify_jwt=false`, HTTP 201). Both items are now terminal.
- **Blocked on**: nothing. Item 2 (the DELETE) closed 2026-08-20; item 1 (the redeploy) closed 2026-08-24 — the credential blocker was environmental, and the founder laptop has the token at `supabase/.supabase/supabase access token.txt`.
- **Verified**: 2026-08-24 — deploy returned HTTP 201 with `version: 19`; live config re-read independently via the Management API (v19, `verify_jwt: false`, ACTIVE); unauthenticated POST returns 401, not 503, so the module booted. Baseline for the behavioural check recorded the same day: `memory_embeddings` = 506 rows, `content like '%{event:%'` = **0**. ⚠ The behavioural half is NOT yet observed — see "What is still owed" below.

`rolling-context` summarized `ai_coach_interactions` with no channel filter, so `app_event`
analytics rows were embedded into `memory_embeddings` as `source_type='conversation'`. Live count
at the time of writing: **92 of 598 rows (15.4%)**, with content shaped like:

```
"User: {event: phase_1_cycle_repeat_started}\nCoach: "
```

`rolling-context:269` fetched with no filter and `ai-proxy:884` concatenates retrieval output into
the **SYSTEM prompt**, so this text reaches the model as though a user had said it.

**Half-closed by commit `<this batch>`:** every one of rolling-context's reads on
`ai_coach_interactions` now carries `.neq("channel", "app_event")`, pinned by
`test/contracts/rolling_context_excludes_app_event_test.dart` (mutation-proven on five shapes,
including a NEW unfiltered read added beside the filtered ones — the shape a plain grep misses).

⚠ **The first version of this fix did not work in production, and the correction is the more
useful record.** It filtered three PostgREST chains in the TypeScript and every artifact in the
batch — the code comment, migration 120's header, the diagnose-doc, the closure YAML and this
entry — asserted "all three reads now exclude app_event". The B-pass falsified it: rolling-context
calls the RPC `get_users_with_message_count()` FIRST (`index.ts:143`) and reaches the manual
queries only if that throws. That RPC (`010_add_indexes_idempotency_rpc.sql:76-83`) has no channel
predicate, and its `where summarized = false` is a **permanent no-op** because nothing in the
codebase ever writes `summarized = true`. Two of the three filters were therefore dead code on the
live path.
Nothing was mis-deleted — the per-user FETCH filter runs whichever path selected the user — but the
threshold deciding *who gets processed* stayed as overcounted as before, and now that app_event
rows are never deleted that count grows without bound: a user whose analytics volume alone crosses
50 gets their whole history paged in nightly, then skipped.
Fixed by re-counting the RPC's candidates with the exclusion before the expensive fetch, rather
than adding a predicate to the RPC (that would be a migration apply needing its own §4.3 go).

**Two things that remain, and neither is cosmetic:**

1. **The fix is INERT until `rolling-context` is redeployed.** ⚠ Corrected 2026-08-20: the
   founder AUTHORIZED this redeploy. It is blocked on **credentials, not permission**. The §0
   host-shell path needs a Supabase Management API token and every source `deploy_via_api.js`
   accepts is absent from the remote container — `SUPABASE_ACCESS_TOKEN_FITNESS` and
   `SUPABASE_ACCESS_TOKEN` unset, `~/.supabase/fitness-app-token` absent, `supabase/.supabase/`
   gitignored so it never came with the clone.
   The MCP `deploy_edge_function` fallback was **considered and rejected, not attempted**:
   `rolling-context` deploys as **7 files** (`source/index.ts` + six siblings under `_shared/`,
   which is what makes `../_shared/...` resolve), and §0 records the legacy MCP path silently
   mangling shared-import paths. A mangled deploy of this particular function does not fail
   loudly — it breaks a nightly cron that summarizes and DELETES user conversation rows.
   **To unblock:** either export `SUPABASE_ACCESS_TOKEN_FITNESS` into the session, or run the two
   §0 commands from the founder machine. Live version at time of writing: **18**.
2. ✅ **The 92 rows are DELETED — 2026-08-20, founder-authorized, verified either side.**
   Dry-run reproduced the filing's numbers exactly before anything was removed: **92 of 598**
   rows, **2** distinct users, longest content **56** characters, **0** carrying a Coach reply,
   and — the check that mattered — a deliberately looser pattern (`content like '%{event:%'`,
   no `source_type` constraint) matched the **same 92 and nothing else**, so the strict predicate
   was not leaving a tail behind. Every matched row was the pure two-line event shape
   (`^User: \{event: [a-z0-9_]+\}\nCoach: $`); **0** carried extra prose that a human might have
   written. Deleted with that regex in the `where`, `returning id` (92 ids returned). Re-run of
   the same counts immediately after: **506 rows remain** (598 − 92), and the loose pattern now
   matches **0**. `source_type='conversation'` went 575 → 483; the other source type was
   untouched.
   Scope note, so the green is not over-read: this removes the rows from `memory_embeddings`,
   which is what retrieval reads. It does not rewrite any summary text already folded into an
   older row, and it does not touch `ai_coach_interactions` — whose 22 `app_event` rows are the
   *writer*-side residue that item 1's redeploy stops feeding forward.

**Related but NOT fixed here, filed together because they share the single root cause — five
consumers read this table and only one of them knows the channel taxonomy:** the restore path
renders `app_event` rows as the user's own chat bubbles (the replay path filters, the render path
does not), and `daily-snapshot` feeds them into the profile-fact-extraction prompt that its own
comment calls the highest-consequence injection site. Neither has a consent gate and `metadata`
is unscrubbed.

**Root-cause note worth keeping:** the FOB-5 batch DERIVED the six-channel taxonomy (measuring
116 rows across six channels to fix a 5.3x overcount) and then applied it to exactly one
consumer, leaving five others reading unfiltered. Deriving a taxonomy and not sweeping its
consumers is the writer/reader drift class arriving from the reader side.

---

**CLOSED 2026-08-24 — what actually ran, and what is still owed.**

Deployed from the founder laptop via the §0 host-shell path (`emit_payload.js --auto` →
`deploy_via_api.js ... false`), dry-run first to confirm `verify_jwt=false` before any prod call.
Payload archived at `backups/edge_function_payloads/rolling-context/v3_e78adb6.json`.

⚠ **Correction to this entry's own text:** item 1 above says `rolling-context` "deploys as
**7 files**". The actual emit produced **8** (`index.ts` + seven under `_shared/`:
`gemini.ts`, `sanitize_for_prompt.ts`, `paged_fetch.ts`, `cron_auth.ts`, `cron_telemetry.ts`,
`tools/zodToGemini.ts`, `embeddings.ts`). The count was never load-bearing — it was cited only
to argue the MCP path would mangle shared imports, which remains true — but it was wrong, and a
number stated in a closed issue gets trusted later.

**What is still owed (tracked, not deferred):** the third verification check is behavioural and
cannot be run on the deploy day. `rolling-context-nightly` (cron jobid 19) fires at
`0 21 * * *` UTC = **02:30 IST**. After the first run on/after 2026-08-25, re-run:

```sql
select count(*) from public.memory_embeddings where content like '%{event:%';
```

It must still be **0**. A non-zero count means the filter is not live despite v19 being
deployed, and this entry should be REOPENED rather than a new one filed. Closing on the two
checks that CAN be verified today, with the third named explicitly, is deliberate: leaving the
whole issue open for a scheduled cron would misreport a completed deploy as outstanding work.


## OI-144 — "I also have" collects equipment that changes nothing above the bodyweight tier (P2)

- **Status**: CLOSED (2026-08-28, same branch that introduced it) — founder chose fix 1 (capability
  authoritative at every tier). Diagnose `a9e3c7`.
- **Blocked on**: nothing.
- **How it was closed**: BOTH causes had to go, and either alone changes nothing.
  `resolveCapability` lost its `if (tier != 'bodyweight') return null;` gate, and `queryV4`'s tier
  block became `capability == null && tierLower != null` — capability SUBSUMES it rather than
  running alongside, because running both keeps the tier block binding and the widening can never
  happen. Safe only because OI-89 flipped the tier invariant to EQUALITY in the same batch, so
  `equipment_tier` carries no information `equipment_needed` lacks; the code says so at the site.
  A fail-OPEN path became reachable and was closed with it: `effectiveItems` returns every
  canonical token for an unrecognised tier, unreachable while the bodyweight gate existed, so both
  producers now resolve an unknown tier to `bodyweight`.
  Proven by `test/contracts/equipment_owned_widens_test.dart` (8 tests), mutation-proven on BOTH
  legs — reverting the consumer reddens 1, reverting the producer reddens 3. The 606-persona
  scorecard is UNCHANGED, which is the evidence that the no-owned path stayed byte-identical.
  Full suite 5054 passed, 0 failed.
- **Verified**: 2026-08-28 (measured on branch `oi89-bodyweight-floor` before merge; the picker's
  offered list computed directly, and the exclusion traced through `queryV4`)
- **Identified**: 2026-08-28 · while explaining the `home_dumbbells` quality residual from OI-89.
  Not found by the ×2 plan review or the B-pass — both read the bodyweight tier, which is where
  the feature works.
- **Risk class**: collect-but-ignore / broken promise. Same family as
  `enable_equipment_exclusions`, whose flag comment calls that shape *"a live broken promise,
  rather than an unshipped feature"* — it was flipped ON in 2026-08-05 for exactly this reason.
- **What's wrong**: OI-89's Profile picker offers a `home_dumbbells` user **13 chips** —
  `pull-up bar`, `kettlebell`, `bench`, `barbell`, … — and ticking any of them does not change
  their generated plan. `equipment_owned` widens the pool only through
  `TrainingHistoryAnalyzer.resolveCapability`, which returns `null` for every tier above
  `bodyweight` (decision 1 deliberately scoped the hard floor there), and `queryV4` still filters
  on the `equipment_tier` STRING. A pull-up-bar row is tagged `[basic_gym, full_gym]`, so it stays
  excluded no matter what the user says they own.
  The user experience is worse than a no-op: `computePlanChanged` DOES include the field, so
  saving raises the "Reschedule Workouts?" prompt, the user accepts, and the regenerated plan is
  byte-identical.
  ⚠ It is not entirely inert — `effectiveEquipmentForSnapshot` answers at every tier, so the AI
  coach does know. Only exercise SELECTION ignores it.
- **Why it matters beyond the promise**: this is the built-in remedy for OI-89's own residual.
  `home_dumbbells` `vertical_pull` slots fall to attempt-3 **100% of the time** (323/323), because
  every compound vertical pull in the library needs `cables`, `pull-up bar`, `bench` or
  `machines` — that is physics, not a content gap, and no amount of authoring fixes it. A doorway
  pull-up bar is cheap and common, so "tell us you own one" is the right answer; it just does not
  work yet.
- **Two fixes, and they promise different things**:
  1. **Make capability authoritative at EVERY tier** — `equipment_owned` widens the pool
     regardless of `equipment_tier`. Fixes the promise AND the `vertical_pull` residual for users
     who own a bar, with no new exercises. Extends decision 1 beyond what OI-89's ×2 review
     scoped, so it needs its own review round.
  2. **Show the picker only at the bodyweight tier** — honest and minimal, but discards the
     feature's value at the tier that most needs it.
- **Blast radius estimate**: `account` for fix 2 (one widget predicate);
  **`platform`** for fix 1 (it changes what `queryV4` treats as authoritative for every user).
- **NOT shipped**: the picker is on branch `oi89-bodyweight-floor`, 14 commits unpushed, no APK.
  Fixing it before the merge costs nothing; after, it is a live broken promise.
- **Related**: OI-89 (this is its residual), `enable_equipment_exclusions` in
  `plan_engine_flags.dart` (the precedent for the class),
  `docs/plan-reviews/oi89-bodyweight-floor.md`.

---

## OI-118 — CLOSED, NOT A REPO ISSUE: I read a 14-day-old orphan `/tmp` file and formatted the date out of my own evidence (P3)

- **Status**: CLOSED (`verified_clean` — there is no defect in the repo to fix)
- **Closed**: 2026-08-13, same day as filed, after THREE successive corrections.

> ⚠️ **This entry was WRONG THREE TIMES, each layer found by a different mechanism.** It is kept —
> not deleted — because a board entry describing a bug that does not exist is worse than no entry
> (the standard `docs/audit/oi-mechanism.closure.yaml` sets), and because the progression is the
> most useful thing here.
>
> | # | What I claimed | What is true | Found by |
> |---|---|---|---|
> | 1 | "`safe_commit.sh` logs to a fixed `/tmp` path" | `:43` is `mktemp` w/ `$$` fallback; `cat` to stdout at `:50`, `rm -f` at `:82`. The literal string appears **0** times in every version in its history. | the B-pass |
> | 2 | "concurrent sessions collide on that path" | Nobody collided. `/tmp/safe_commit_run.log` mtime is **2026-07-30 10:51** — an orphan abandoned 14 days before I read it. | me, following up on the B-pass |
> | 3 | "its timestamp looked recent enough to be current" | It looked recent because **my own command discarded the date**: `ls -l --time-style=+%H:%M:%S` prints time-of-day only, so `10:51:04` read as this morning. | me, re-running with `--full-time` |
>
> **The root cause is layer 3 and it is mine, not the repo's.** I chose a view that threw away the
> one field capable of refuting my conclusion, then drew the conclusion — `feedback_green_check_
> input_set_width` in its purest form, with the narrowing done by a display flag rather than a
> filter. Sibling instances that week were measurements killed by controls; this one needed no
> control, only the default `ls` output.

- **Blocked on**: nothing. Nothing to do.
- **Verified**: 2026-08-13 — `ls -l --full-time /tmp/safe_commit_run.log` → `2026-07-30 10:51:04`,
  against `date` → `2026-08-13`. And `grep -rn "safe_commit_run" scripts/` → 0 matches, so nothing
  in the repo writes it at all.
- **Why it is not merely downgraded**: every proposed fix across all three drafts (embed slug/pid;
  write inside the worktree `.git`; document a redirect convention) targets a collision that
  `mktemp` structurally prevents and that did not occur. There is no change to make.
- **What survives, and where it went**: the real hazard is reading an orphan file at a plausible
  path and assuming provenance. That is a working-practice lesson, not a backlog item, and belongs
  in the memory feedback file for the verification class — recorded there rather than left here as
  a phantom issue.
- **Terminal state**: `verified_clean`.

<!-- Original entry text retained below for the record. -->

> ⚠️ **This entry was filed with a FALSE diagnosis and corrected the same day by its own B-pass.**
> The original text claimed "`safe_commit.sh` logs to a fixed `/tmp` path". That is wrong.
> `scripts/safe_commit.sh:43` is `LOG="$(mktemp 2>/dev/null || echo "/tmp/safe_commit_$$.log")"` —
> unique per invocation, with a PID-suffixed fallback — and `:50`/`:82` `cat` it to stdout then
> `rm -f` it. The literal string `safe_commit_run.log` appears **zero** times in that script in
> **every version in its history** (`git log -p --all -- scripts/safe_commit.sh | grep -c` → 0).
> The proposed fix (embed slug/pid in the filename) would have "fixed" a collision the code already
> prevents. **The script requires no change.** Correction retained rather than deleted, because the
> filing error is the more useful record — see Risk class.

- **Status**: OPEN
- **Blocked on**: nothing. It is a practice fix, not a code fix.
- **Verified**: 2026-08-13 (corrected). The OBSERVATION was real: reading `/tmp/safe_commit_run.log`
  for my own failing run returned a **different session's** commit (`e9683418`, branch
  `progress-map-consolidation`) with a plausibly-recent mtime. The CAUSE was not. Nothing in the
  repo writes that path — `grep -rn "safe_commit_run" scripts/` → 0 matches. It exists because
  agent sessions redirect `safe_commit.sh`'s stdout there ad hoc, and several independently chose
  the same obvious name.
- **Identified**: 2026-08-13.
- **Risk class**: misattribution, and the filing error demonstrates it better than the bug does. I
  read a file at a plausible path, assumed the tool wrote it, and filed a "Verified" board entry
  naming a mechanism I never checked against the source. That is
  `feedback_mistake_unverified_done_claims` — the most recurrent class in this repo — committed
  inside a batch whose own theme is signals that misreport. The near-miss was real: I began
  diagnosing 11 test failures from another branch's output and caught it only because the branch
  name at the bottom was not mine.
- **What's actually wrong**: nothing in the tooling. The hazard is a *convention* — any agent
  redirecting to a guessable shared `/tmp` name collides with every concurrent session, and the
  resulting file carries no owner marker.
- **Fix shape**: don't redirect to a hand-picked shared path. `safe_commit.sh` already `cat`s its
  log to stdout, so capture ITS output to a session-scoped file (the harness scratchpad dir) rather
  than inventing `/tmp/<toolname>_run.log`. Worth a line in the §4.3 wrapper docs.
- **Blast-radius estimate**: `feature` (documentation/practice; no script change).


## OI-150 — mergeCloudProgress resolves current_phase and current_week/phase_started_at independently, so a not-yet-pushed phase advance reverts the week+date and cements the mismatch (P2)

- **Status**: CLOSED (`closed_in_commit`)
- **Closed**: 2026-08-30 — fix `c2534257`, merged `0ca859b9`, all 7 CI jobs green. Diagnose `321062`. Coupled the phase delta as a post-pass in `mergeCloudProgress`, anchored the login plan-regen on the guarded Hive value, gated the profile derived-target recompute on `derivedTargetInputsChanged`, and routed progress+profile writes through `SyncQueue` with `sync_reliability_v1` flipped on.
- **Blocked on**: **nothing external** — a scoped change to `UserRepository.mergeCloudProgress`
  plus its behavioral tests. Filed rather than fixed in `profile-phase-fixes` because that batch
  ships three display/restore fixes to a different concept, and this is a data-integrity change
  to a `platform`-tier monotonic-merge function whose field list two prior OI-83 review rounds
  already got wrong once.
- **Verified**: 2026-08-30 — mechanism traced end-to-end in code (below). NOT reproduced on a live
  account, and see the retention caveat.

**The asymmetry.** `UserRepository.mergeCloudProgress` (`user_repository.dart:299-381`) resolves
each cloud field independently:

- `current_phase` is in `monotonicProgressFields` (`:235-239`) → **local-max-wins** (`:368-377`).
- `current_week` and `phase_started_at` are **not** in that list → **cloud-non-null-wins
  unconditionally** (`:312-314`).

**Why that combination bites.** `commitPhaseAdvance` (`pro_phase_advance.dart:304-350`) bumps all
three together locally, then pushes fire-and-forget via `unawaited(SyncService.instance
.syncProgressNow())` (`user_repository.dart:448`) — never awaited, as coding rule 1 requires. If
that push has not landed before the next launch (app closed right after a workout, a network
blip — ordinary offline-first usage, not a QA action), the next sign-in runs
`restoreLightweightAlways` (`sync_service.dart:1243`, the NON-empty-Hive branch taken by every
returning user, `:1222-1230`) → `_restoreUserProgress` → `mergeCloudProgress` against a stale
cloud row. Result: `current_phase` stays advanced, `current_week` and `phase_started_at` revert.
The merged map is then written straight back to Hive (`sync_profile.dart:783`), so local and cloud
now AGREE on the wrong shape and nothing flags it again.

That produces exactly the state behind diagnose `c9e4b7` / `b7f1c8`'s missing-Phase-I symptom:
`current_phase=2, current_week=8, phase_started_at` still the original date.

**Silent by construction.** `reportProgressDemotionsDeclined` only fires for MONOTONIC fields that
were declined. A non-monotonic field being overwritten from cloud emits nothing — there is no
telemetry to grep for, which is why `b7f1c8`'s investigation could neither confirm nor exclude it.

⚠ **Not confirmed on either affected account, and the evidence window cannot settle it.**
`client_errors` retains from 2026-08-01 only, and zero `progress_restore_demotion_declined` /
`phase_advance_conflict_skipped` rows exist for ANY account in that window. With just 2 accounts
ever reaching phase 2 in a pre-launch app, that is an absence of population, not evidence the
mechanism does not fire. Direct Postgres manipulation during past QA remains an equally live
hypothesis for these two specific accounts.

**Proposed fix (not yet reviewed):** couple the three fields — accept cloud's `current_week` /
`phase_started_at` only when cloud's `current_phase` is also `>=` local's, so a stale cloud row
cannot half-revert a local advance. Needs its own ×2 review: the OI-83 history is that this exact
field list was wrong twice (`longest_gap_days` was included when higher is WORSE for it, caught in
round 1), and the function carries a `disable_progress_restore_monotonic_merge` kill-switch that
any change must keep honouring.

**Related:** diagnose `b7f1c8` (which surfaced this, in plan-review round 2), diagnose `c9e4b7`
(the original display symptom), OI-83 (the monotonic-merge guard this extends), diagnose `d1f6b3`.

