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


## OI-170 — `day_of_week` round-trips through the cloud as 1..7 where every reader expects 0..6, shifting every `D<n>` badge (P1)

- **Status**: CLOSED (2026-09-08, `regen-wave-alignment`) — diagnose `c4e8b2`
- **Blocked on**: none
- ⚠ **CLOSED BY BEING FOLDED IN, reversing this entry's own "not folded into the OI-166 batch" reasoning below.** Both stated reasons were wrong in the same direction. (1) The repair needs NO already-corrupt-cloud fixture: deriving from `scheduled_date` makes the transmitted value **unread**, so there is nothing to fixture. (2) "Different layer" did not hold either — the LOCAL half of the identical off-by-one was already being fixed in that batch, so filing this separately would have shipped one off-by-one fixed on one side and live on the other, which is precisely the writer/reader drift class the batch attacks. The `platform` tier note below is the one part that survived: folding it in DID raise the batch from `account` to `platform`, which pulled in a `feature_flag` requirement the batch initially missed and a B-pass caught
- **Shipped**: restore derives `dayOfWeekFromDate(scheduled_date)` (self-healing, no migration); push sends the stored value with the derivation only as fallback; canon given ONE definition in `lib/core/utils/date_utils.dart:50`. Kill-switch `disable_day_of_week_derive` (opt-OUT — the fix is live by default; default-OFF would have preserved the known-broken path). 13 assertions in `test/contracts/day_of_week_canon_writer_to_reader_test.dart`, mutation-proven on 3 legs (4/4/1 red)
- **Verified**: 2026-09-07 — canon is 0..6: `tool_dispatcher.dart:695` writes `destDate.weekday - 1` with the explicit comment `// 0=Mon..6=Sun`, `workout_schedule_read_service.dart:415` writes `d.weekday - 1`, and both readers assume it (`train_provider.dart:619` `(row['day_of_week'] as int?) ?? 0`; `:816` and `:622` compute `dayNumber = (week-1)*7 + day_of_week + 1`). Two writers emit 1..7: `sync/sync_workout.dart:1620` (`'day_of_week': parsedDate?.weekday ?? entry['day_of_week']`) and `hotel_workout_planner.dart:183` (`'day_of_week': d.weekday`). Cloud column is a bare `int`, no CHECK, no comment (`supabase/migrations/002_create_fitness_tables.sql:104`); **no Edge Function reads it** (`grep -rn "day_of_week" supabase/functions/` → 0, positive control `scheduled_workouts` → 5 files)
- **Identified**: 2026-09-07 · surfaced by round 4 of the OI-166 plan review (P1-4), while verifying a *different* claim about `hotel_workout_planner.dart`. Three earlier rounds and two versions of the regen inventory had read the same files and missed it
- **The mechanism, end to end**: the local write is correct (0..6) → the **push** at `:1620` discards it and re-derives 1..7 from the row's own date (`parsedDate` comes from `:1595`, so it is effectively never null and the `??` fallback never fires) → the **restore** at `:1977` writes `if (map['day_of_week'] != null) 'day_of_week': map['day_of_week']` **after** the `existingMap` spread, so the cloud's 1..7 OVERWRITES a correct local 0..6 → readers add 1 → every day number is one too high
- **User-visible symptom**: after any cloud round-trip (reinstall, new device, and the background restore that runs on most cold starts for returning users), Monday of week 1 renders **`D2`** and Sunday of week 1 renders **`D8`** inside a seven-day week. Rendered at `week_rows.dart:54` (`'D${day.dayNumber}'`), `day_card.dart:54` and `expandable_day_card.dart:196`. `preview_plan_provider.dart:117` also *matches* on `dayNumber`, so a shifted value silently falls through to its positional-index fallback at `:122`
- ⚠ **The PUSH is the wrong side, not the restore.** There is no server-side contract to honour — no constraint, no comment, no EF reader — so the app is the only consumer and 0..6 is its canon. The `??` ordering is also backwards: it prefers a re-derivation over the stored canonical value
- **Proposed repair, not yet reviewed**: (1) the restore DERIVES `day_of_week` from `scheduled_date` (`parsed.weekday - 1`) instead of trusting the transmitted value — it is a pure function of the date, so it never needed to round-trip, and deriving it **self-heals every already-corrupted cloud row with no migration**; (2) the push sends `entry['day_of_week']` rather than re-deriving. (1) alone is sufficient; (2) is correctness hygiene
- **Blast radius**: `sync/**` is `platform` (`docs/blast_radius.yaml:63`), which is why this is not folded into the `account`-tier OI-166 batch
- **The local half of the same off-by-one IS fixed in the OI-166 batch** — `hotel_workout_planner.dart:183` — because that file is a schedule-row implementation matched by that batch's new `check_single_schedule_row_builder.dart` gate. This issue owns only the cloud round-trip

## OI-171 — the deload lift writes the `current_plan` blob AFTER the fan-outs that would push it, so the lifted week 4 can sit un-pushed until an unrelated write (P2)

- **Status**: CLOSED (2026-09-08, `regen-wave-alignment`) — diagnose `b6d1f4`
- **Blocked on**: none
- **Shipped**: `unawaited(SyncService.instance.pushWorkoutPlanForSyncDomain())` immediately after the blob write — the narrow plan push, kept UNAWAITED exactly as the warning below demands, so cold-launch home navigation is not blocked. ⚠ It first shipped with **zero** regression coverage, self-disclosed in its own diagnose-doc as acceptable "fixture cost" — which is a §4.2 deferral wearing a confession. A B-pass caught it by DELETING the line and watching 60 tests across four suites stay green. Now pinned by a 3-assertion ordering group in `test/contracts/deload_eval_behavioral_test.dart` (`indexOf(push) > indexOf(blobWrite)`), mutation-proven 2 legs: MOVING the push above the blob write reddens exactly the ordering assertion (1), deleting it reddens 3
- **Verified**: 2026-09-07 — `_liftWeekFour` writes rows via `upsertScheduled` (`deload_evaluator.dart:207-223`), each of which fires `unawaited(SyncService.instance.syncWorkoutData())` (`workout_write_service.dart:566`); it then writes the blob at `deload_evaluator.dart:264` and fires only `unawaited(SyncService.instance.pushSnapshot())` at `:273`. `pushSnapshot` does **not** reach `_syncWorkoutPlan` — the only two call sites of that method are `weeklyFullSync()` (`sync_service.dart:1143` → `:1169`) and `pushWorkoutPlanForSyncDomain()` (`sync_workout.dart:2053-2057`, invoked from `sync_domains/workouts_sync_domain.dart:55`). `_syncWorkoutPlan` (`sync_workout.dart:1024-1057`) is what builds `plan_json` from the blob (`:1045-1056`)
- **Identified**: 2026-09-07 · round 5 of the OI-166 plan review (P2-9) flagged `deload_evaluator.dart:264` as the one blob writer not paired with `syncWorkoutData()`. ⚠ **Its stated conclusion — that the lifted blob "never reaches `plan_json`" — is WRONG and was corrected on verification**: the row writes' own fan-out does reach it. The real defect is narrower and is an ORDERING one
- **The actual gap**: the row fan-outs fire **before** the blob is written, so the `plan_json` they push carries the PRE-lift blob. Nothing after `:264` pushes the post-lift blob. It therefore reaches the cloud only on the next unrelated `syncWorkoutData()` (any later workout write) or the weekly `weeklyFullSync()`
- **Who is exposed**: a user whose week 4 deload is lifted and who then logs nothing before reinstalling or moving device. On restore, `_restoreWorkoutPlan` applies the stale blob and the phase-arc strip shows `deload` for a week whose rows say `working` — the rows-vs-blob disagreement Unit B shipped 2026-09-06 to eliminate, arriving through the sync layer instead of the writer
- ⚠ **Do NOT "fix" this by appending `syncWorkoutData()` at `:273`.** The comment at `:269-272` is deliberate: *"Durability — UNAWAITED (offline-first) … Awaiting here would block cold-launch home navigation (`runRolloverNow` is awaited before `context.go`)"*. The lift runs on the cold-launch rollover path. The fix must preserve that non-blocking property — most likely `unawaited(SyncService.instance.pushWorkoutPlanForSyncDomain())` after the blob write, which is the narrow push rather than the whole domain
- **Blast radius**: `lib/core/services/**` → `account` (`docs/blast_radius.yaml:326`); the fix did not touch `sync/**`. The BATCH that shipped it is `platform`, but for OI-170's sake, not this one's
- ~~**Not folded into the OI-166 batch**~~ — **superseded 2026-09-08: it WAS folded in.** The bullet read *"it is a defect in the deload lift's own durability sequencing, not in either regeneration path"*. That is still an accurate description of the defect and a poor reason to file it separately: it was one line, it was discovered while verifying an OI-166 review finding, and the batch was already re-testing the deload lift's dual write. §4.2 makes the same point structurally — a bug surfaced by a batch is fixed by that batch

## OI-226 — ai-proxy chat/tool-calling Gemini exhaustion paths have no reportGeminiExhaustion alert wiring

- **Status**: CLOSED (2026-09-21, `observation-batch-and-digest-redesign`, A5) — diagnose `f7a2c9`
- **Blocked on**: none
- **Shipped**: BOTH gaps this OI named. (1) `geminiChatWithTools` (`gemini.ts`) now attaches
  `{status, geminiMessage}` onto its total-exhaustion throw via `Object.assign` (the pre-existing
  thrown Error carried no structured field `reportGeminiExhaustion` could consume); `tool-loop.ts`'s
  `runToolLoop` hard-failure catch (`:300`) now calls `reportGeminiExhaustion` with the same
  `source="ai_proxy_gemini_exhausted"` the 3 nutrition sites use and `endpoint="chat"`. (2) The
  `prediction` handler's own single-shot `geminiChat()` call (`ai-proxy/index.ts`, originally cited
  below as `:692`, drifted to `:722` by this same batch's own A2b `retries: 2` insertions earlier in
  the file) never destructured `lastError` at all — now does, and its `!content` branch calls
  `reportGeminiExhaustion` with `endpoint="prediction"`. ai-proxy now has 5 total call sites (was 3).
  ⚠ **An earlier pass at this fix closed only (1) and nearly reported this OI closed while (2) was
  still open** — caught by re-reading this entry's own full body (specifically the "at least two
  more … call sites" sentence below) before writing the closure claim, not by any tooling. Mechanical
  gate `scripts/check_gemini_retry_and_telemetry_coverage.dart` covers client-side telemetry +
  `geminiChat` retries going forward; this server-side `reportGeminiExhaustion` wiring itself has no
  mechanical gate (scope decision, 5 call sites judged too small a surface to warrant one — see the
  diagnose-doc).
- **Verified**: 2026-09-21 — `grep -c "reportGeminiExhaustion(" supabase/functions/ai-proxy/index.ts`
  → 4 (3 pre-existing + `prediction`); `tool-loop.ts` has exactly 1 more. `deno check
  --node-modules-dir=none` clean on `gemini.ts`, `tool-loop.ts`, `ai-proxy/index.ts`. Both new sites
  mutation-proven (deleted each `reportGeminiExhaustion` call independently, confirmed exactly its
  own test reddened, reverted, confirmed green) — see the diagnose-doc's `mutation_proven` field for
  exact pass/fail counts.
- **Identified**: 2026-09-20 · filed via mint_oi.sh from branch `claude/food-logging-observations-126ab3`

The `food-logging-observations` batch (Tasks 9-10, commits `72a4aa7d`/`c84eb796`) wired
`reportGeminiExhaustion` at exactly the three `ai-proxy` call sites its own plan named —
`food_text_analysis` (`:443`), `scan_meal` (`:603`), `cart_auditor` (`:646`) — because that
plan was scoped to the nutrition/food-logging observations, not to ai-proxy as a whole.
Round-2 plan review (2026-09-20) correctly noted that ai-proxy has at least two more
`geminiChat`/`geminiChatWithTools` call sites with no equivalent wiring: the plain chat
path (`index.ts:692`, destructures `{ content, modelUsed, tokensUsed }` — no `lastError`)
and the 3-round tool-calling path (around `:1009`, `geminiChatWithTools`). A terminal Gemini
failure on either path currently degrades silently to the client with zero founder
visibility, the exact gap Task 9/10 closed for the nutrition endpoints.

**This is accepted as an explicit plan-scope boundary, not a defect in the delivered
work** — the plan's Task 10 brief names the three call sites verbatim in its Files section,
and extending coverage to the chat/tool-calling paths is a separate unit of work (the
`geminiChatWithTools` path has a materially different retry/round shape than the
single-shot `geminiChat` calls Task 9 instrumented). Filed here per §4.2 so the gap has a
tracked terminal state rather than living only in a round-2 review nobody re-reads.

**Fix direction (as filed — see Shipped above for what actually landed):** wire
`reportGeminiExhaustion` (or a `lastError`-carrying equivalent) at `index.ts:692` and inside
`geminiChatWithTools`'s exhaustion path, using the same `endpoint` discriminator pattern
(`"chat"` / `"chat_tool_call"`) Task 10 established for the three existing sites. (Shipped used
`endpoint="chat"` for the tool-calling path and added `endpoint="prediction"` for the
previously-unnamed-by-fix-direction second site.)

## OI-243 — Discipline v3 Phase 3: gates, memory-write-guard, hooks-check

- **Status**: CLOSED (2026-09-23, same session that filed it) — the title-only stub this OI
  was filed as ("Discipline v3 Phase 3: gates, memory-write-guard, hooks-check") describes
  exactly the work this very batch ships: `check_hive_first_pattern.dart` +
  `check_edge_function_scope.dart` (the two new report-mode AST gates), `memory_write_guard_hook.dart`
  + `memory_write_guard_lib.dart` (the memory write-guard), and the `check_hooks_installed.dart`
  (Gate 32 / OI-104) freshness-check fix. Confirmed via `git log -S "OI-243"` that the stub was
  introduced in this same session's own commit `aca0237a`, carried in from uncommitted
  pre-compaction state swept in by a broad `git add -A` — it was never a separately-scoped ask,
  it was this batch documenting itself mid-flight before the work was finished.
- **Blocked on**: none
- **Verified**: 2026-09-23 — re-read this session's own diff and file list against the stub's
  three named areas (gates / memory-write-guard / hooks-check); all three are present, tested,
  and mutation-proven (see `docs/audit/gate_test_ledger.yaml` entries for
  `check_hive_first_pattern.dart` and `check_edge_function_scope.dart`, and the memory
  write-guard's own test files).
- **Identified**: 2026-09-23 · filed via mint_oi.sh from branch `claude/supabase-outage-check-e79200`

## OI-230 — AI coach snapshot rank-promotion math is self-contradictory: _getNextRankFromLadder / _getEtaNextPromotion

- **Status**: CLOSED (2026-09-22, `oi-batching-strategy-e5e359`, Batch A) — diagnose `a8f3e2`
- **Blocked on**: none
- **Original filing** (ported verbatim from `claude/food-logging-observations-126ab3`, adopted here per root CLAUDE.md §7's OI allocator row):
  - **Verified**: 2026-09-21 — read both functions live this session, confirmed
    the mechanism below by tracing the code (the original founder-observed
    contradictory screenshot text itself was not preserved in writing from the
    earlier investigation and is not re-quoted here — the mechanism below is
    independently derived from the current source, not from that screenshot)
  - **Identified**: originally from founder APK screenshots (Phase 1, this
    session, exact date/wording not preserved) · filed 2026-09-21 via
    mint_oi.sh from branch `claude/food-logging-observations-126ab3`

Founder observed self-contradictory rank/promotion info in an AI coach reply
(exact wording not preserved in writing). Re-deriving the mechanism directly
from `lib/features/ai_coach/services/ai_snapshot_builder.dart` finds a
concrete, precisely-locatable defect that would produce exactly this shape
of contradiction:

`_getNextRankFromLadder()` (`:1400-1459`) computes a `remaining` map keyed by
whichever of `workouts` / `streak_days` / `weeks` / `deployments` the next
rank's gate actually requires (`kRankGates[next.code]`), and picks a
`binding_constraint` — the requirement with the MAX remaining value (`:1430,
1442-1445`). So `binding_constraint` can legitimately be `'weeks'`,
`'streak_days'`, or `'deployments'` — NOT `'workouts'` — whenever the user
has already satisfied the workout count but not the other gate(s).

`_getEtaNextPromotion()` (`:1585-1619`) calls `_getNextRankFromLadder()` and
then reads **only** `remaining['workouts']` (`:1590`) to decide the ETA.
If `remainingWorkouts == 0`, it unconditionally returns `{days: 0, date:
<today>}` for BOTH `at_current_cadence` and `at_plan_cadence` (`:1592-1597`)
— i.e. "promotion happens today" — **regardless of whether
`remaining['streak_days']`, `remaining['weeks']`, or
`remaining['deployments']` are still nonzero.** Even in the non-zero branch
(`:1604-1607`), the day/week cadence math is computed purely from
`remainingWorkouts` and never references the other three keys at all.

**Net effect:** any user whose binding constraint is weeks/streak/deployments
rather than workouts gets a snapshot where `next_rank.binding_constraint`
correctly names the real bottleneck (e.g. `"weeks"`, with
`next_rank.remaining.weeks: 3`), while `eta_next_promotion` simultaneously
claims `{days: 0, date: today}` — because it only ever looked at
`remaining.workouts`, which happened to already be 0. The Captain, fed both
fields in the same snapshot, has no way to reconcile "3 weeks still needed"
against "promotion today" — because the snapshot itself contains both, and
they disagree.

**Fix direction (as filed):** `_getEtaNextPromotion()` must compute ETA from
the ACTUAL `binding_constraint` `_getNextRankFromLadder()` selected, not
hardcode `workouts`. For a `weeks`-bound or `streak_days`-bound promotion,
the "0 days" short-circuit is simply wrong — a weeks-gate can only be
satisfied by calendar time passing, and a streak-gate needs the streak
itself extended, neither of which `remainingWorkouts == 0` says anything
about. Needs a per-constraint-type ETA formula, or at minimum an honest
"cannot estimate" response when the binding constraint isn't workouts,
rather than a false "today."

**Shipped:** `_getEtaNextPromotion()` rewritten to branch on the real
`binding_constraint`: `weeks` gets a deterministic calendar-based answer
(cadence-independent); `streak_days`/`deployments` return an honest "cannot
estimate" (`{days: null, date: null}`) rather than a fabricated date, since
neither is reliably forecastable from a cadence figure; a rank whose real
gate is `completionRateMinimum` (officer/MCPO track — not modeled in
`remaining` at all) also gets the honest-unknown shape regardless of what
`binding_constraint` naively resolves to, avoiding a confidently-wrong
number. Additionally found and fixed in the same function:
`remaining['streak_days']`/`remaining['deployments']` never computed a real
`current` value (hardcoded 0), so `remaining['streak_days']` always showed
the FULL requirement no matter the user's actual streak — fixed for streak
(`WorkoutRepository.instance.currentStreak()`, a cheap sync local read);
deployments intentionally left as-is, matching `RankService.getNextRank()`'s
own documented tradeoff (`rank_service.dart:439-444` — an accurate count
needs a network call). The completion-rate-gate modeling gap is filed
separately as OI-240 (not fixed here — a materially different, larger unit
of work: a new requirement type + an adherence-dependent ETA semantic).
**Regression tests**: `test/ai_coach/snapshot_keys_test.dart`
(`eta_next_promotion` + `next_rank` groups, 4 new/rewritten cases),
mutation-proven (5 tests reddened against the pre-fix code, 0 false
positives across the other 43 tests in the file).
**Closes**: diagnose-doc `docs/diagnoses/2026-09-22-rank-eta-binding-constraint-blind-a8f3e2.md`.

## OI-232 — AI coach chat scrolls to top on every switch between in-app chat and Telegram channel

- **Status**: CLOSED (2026-09-22, `oi-batching-strategy-e5e359`, Batch A) — diagnose `c1b9d4`
- **Blocked on**: none
- **Original filing** (ported verbatim from `claude/food-logging-observations-126ab3`, adopted here per root CLAUDE.md §7's OI allocator row):
  - **Verified**: 2026-09-21 — founder reported live; mechanism re-derived from
    source this session (not yet fixed or regression-tested)
  - **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/food-logging-observations-126ab3`

Founder: switching to Telegram then back to in-app chat scrolls the chat to
the top (oldest message), requiring a manual re-scroll down every time.

**Mechanism**, traced in `lib/features/ai_coach/screens/ai_coach/screen.dart`:
`channel == 'in_app' ? _buildChatArea(messages, isSending) :
_buildTelegramView(telegramConnected)` (`:447-449`) means the chat's
scrollable widget tree is entirely REMOVED from the tree when switching to
Telegram and rebuilt fresh when switching back — Flutter does not preserve a
`ScrollController`'s offset across that kind of unmount/remount (no
`PageStorageKey`/keep-alive is used here).

The one thing that WOULD re-scroll it to the bottom on remount,
`_jumpToBottom()` (`:275-281`, jumps to `maxScrollExtent`, guarded by
`_scrollController.hasClients`), is only ever invoked from ONE call site
(`:423-426`):
```
if (!_initialScrollDone && messages.isNotEmpty) {
  _initialScrollDone = true;
  _jumpToBottom();
}
```
`_initialScrollDone` (`:159`, declared once per `_AiCoachScreenState`) is a
**one-shot flag for the screen's entire lifetime** — it was added
specifically to fix first-paint landing position (comment at `:416-422`,
`closes-diagnose: 2026-05-10-coach-scroll-init`, APK Test #15 / Bug E) and
was never intended to fire more than once. Because `_AiCoachScreenState`
itself is NOT recreated when `channel` changes (only the conditional child
widget swaps), `_initialScrollDone` is already `true` well before the first
channel switch — so the guard's condition never re-fires, `_jumpToBottom()`
never runs again, and the freshly-remounted chat ListView is left at
whatever its own default initial position is (the top).

**Fix direction (as filed):** re-scroll to bottom on every remount of the
chat area, not just the screen's first paint — e.g. call `_jumpToBottom()`
whenever `channel` transitions TO `'in_app'`, or give the chat
`ListView`/`CustomScrollView` a `PageStorageKey`/`AutomaticKeepAliveClientMixin`.
The existing one-shot `_initialScrollDone` guard should stay for its
original first-paint purpose.

**Shipped:** implemented exactly the recommended `ref.listen(channelProvider,
...)` trigger — fires `_jumpToBottom()` only on the transition INTO
`'in_app'` (`previous != 'in_app' && next == 'in_app'`), added alongside the
existing `ref.listen` calls in `build()`, without touching the pre-existing
one-shot `_initialScrollDone` gate.
**Regression test**: `test/ai_coach/initial_scroll_to_bottom_test.dart` (new
case, source-grep — matches this file's own established convention for this
exact screen), mutation-proven (reverting the fix reddens exactly this one
new test, the pre-existing 4 stay green).
**Closes**: diagnose-doc `docs/diagnoses/2026-09-22-coach-scroll-channel-switch-c1b9d4.md`.

## OI-238 — 5 Gemini-calling Edge Functions have no server-side reportGeminiExhaustion telemetry (weekly-report, ai-media-proxy, assess-body-composition, daily-snapshot, rolling-context)

- **Status**: CLOSED (2026-09-22, `oi-batching-strategy` Batch C) — diagnose `b6e3a8`
- **Blocked on**: none
- **Shipped**: all 5 named call sites. Each function's `geminiChat()` call now destructures
  `lastError` and its total-exhaustion branch calls `reportGeminiExhaustion`. Dedup source split
  by traffic shape rather than reused uniformly: the 4 LIVE user-invoked sites
  (`weekly-report` `:573`, `ai-media-proxy` `:941`, `assess-body-composition` `:178`,
  `daily-snapshot`'s `extractCoachingNotes` `:167`) share the SAME `"ai_proxy_gemini_exhausted"`
  source ai-proxy/tool-loop.ts already use, each with a distinct `endpoint` tag; `rolling-context`'s
  `summarizeMessages` (`:127`) — the sole cron-dispatched site among the 5, looping over every user
  with >50 stored messages in one nightly run — deliberately gets its OWN source
  (`"rolling_context_gemini_exhausted"`) so a bad-run failure burst can't suppress a same-day
  live-traffic alert. `rolling-context/index.ts`'s `summarizeMessages` also gained a new
  `supabase: SupabaseClient` parameter (it previously received none), threaded through from the
  per-user loop's own `supabaseClient` at its call site. Same `DISABLE_GEMINI_FAILURE_ALERT`
  kill-switch covers all 10 call sites now (5 from OI-226, 5 from this fix). No mechanical gate for
  server-side wiring — same scope decision OI-226 already made, unchanged by this fix (10 call
  sites across 6 functions still judged too small a surface).
- **Verified**: 2026-09-22 — `grep -n "geminiChat\|reportGeminiExhaustion" supabase/functions/{weekly-report,ai-media-proxy,assess-body-composition,daily-snapshot,rolling-context}/index.ts`
  confirmed all 5 destructure `lastError` and call `reportGeminiExhaustion` exactly once each.
  `deno check --node-modules-dir=none` clean on all 5 `index.ts` files. `deno test --no-check
  --allow-all --node-modules-dir=none` across all 5 functions: 44/44 passed. Each of the 5
  new/extended wiring sites mutation-proven independently (deleted each `reportGeminiExhaustion`
  call block in turn, confirmed exactly its own test reddened while every other test in that
  file's suite stayed green, reverted, confirmed green again) — see the diagnose-doc's
  `mutation_proven` field for exact pass/fail counts per site.
- **Identified**: 2026-09-22 · filed via mint_oi.sh from branch `claude/strange-merkle-c2d0b9`

Found by the self-triggered Hermes pass on `observation-batch-and-digest-redesign`
(`docs/diagnoses/2026-09-21-ai-failure-telemetry-gap-oi226-f7a2c9.md`'s own fix wired
`reportGeminiExhaustion` into `ai-proxy`'s 4 internal `type` handlers plus `tool-loop.ts`'s
chat/tool-calling path — 5 call sites total, all inside ONE function, `ai-proxy`). This was a
DIFFERENT, wider gap: per `supabase/functions/CLAUDE.md`'s own AI Architecture section, 6
functions call Gemini in total, and the other 5 — `weekly-report`, `ai-media-proxy`,
`assess-body-composition`, `daily-snapshot`, `rolling-context` — each called `geminiChat`
directly with NO server-side exhaustion alert of any kind. A total Gemini failure in any of these
5 was invisible to the founder until a user complained (or, for `rolling-context`, silently
produced zero nightly summaries with no page at all). Explicitly out of scope for OI-226 — that
OI's own filed text named only ai-proxy's two previously-uncovered call sites, not this wider
surface; scope-creeping that batch to cover 5 more functions was rejected in favour of tracking
it here.

**Fix direction (as filed):** wire `reportGeminiExhaustion` (or a function-appropriate variant —
some of these are user-invoked, not cron, so the `endpoint`/dedup semantics may need adjustment)
into each of the 5 call sites' failure path, matching the pattern `ai-proxy`/`tool-loop.ts`
already establish. Shipped exactly this — the dedup-source split (shared for the 4 live sites,
separate for the one cron site) IS the "adjustment" the filed text anticipated.

**Closes**: diagnose-doc `docs/diagnoses/2026-09-22-gemini-exhaustion-telemetry-oi238-b6e3a8.md`.

## OI-104 — `check_hooks_installed.dart` detects hook PRESENCE, not staleness; installed hooks were 12 days behind their sources (P2)

- **Status**: CLOSED (2026-09-23, discipline-v3-phase3 batch) — commit `aca0237a` cited
  `closes-oi: OI-104` in its own trailer while this entry stayed marked "ADDRESSED, not CLOSED,"
  a self-contradiction only caught later by `check_closes_oi_performed.dart` (a gate that landed
  on `main` from a separate concurrent session while this branch was in flight). Since that
  commit is already merged and immutable, closing here for real rather than leaving the citation
  dangling. On the merits: the entry's own title names the defect as "detects PRESENCE, not
  staleness" — that is fixed (`check_hooks_installed.dart` / Gate 32 now does full-content
  comparison, not header-line-anchor matching), and the recurrence this entry documents (a hook
  script edit going silently inert) cannot happen again. The one open question the "ADDRESSED"
  note raised — escalating the check from WARN to a hard FAIL — was evaluated and INTENTIONALLY
  REJECTED, not deferred: `setup-hooks.sh` installs into the git dir COMMON to every worktree
  (§4.13), so hard-failing would block every worktree's next commit the instant any hook script
  changes anywhere, until someone re-runs the installer once from anywhere — a worse failure mode
  than the false-negative this OI was filed to fix. WARN is the correct terminal state for this
  architecture, not a placeholder for future hardening.
- **Blocked on**: none.
- **Verified**: 2026-09-23 — re-read `scripts/check_hooks_installed.dart`'s current
  full-content-comparison logic and `test/scripts/check_hooks_installed_e2e_test.dart`'s
  BODY-only-edit-detection test (mutation-proven: reverting to the old anchor-only logic reddens
  it).
- **Identified**: 2026-08-11 · ×2 plan review of `safe-push-verifier`. Recurred 2026-08-20.
- **Risk class**: silent-inert-gate — the highest-consequence shape, because everything downstream
  looks green.
- **What was wrong**: `scripts/setup-hooks.sh:45` installs by `cp`, not symlink, so `.git/hooks/*`
  drifts from `scripts/*.sh` the moment either changes, and the old `check_hooks_installed.dart`
  check only looked for the STRING `flutter analyze` anywhere in the installed file — any file
  containing that string passed, so an edit to a hook script was inert until someone remembered to
  re-run the installer, and the gate that existed to catch that said green throughout both the
  2026-08-11 and 2026-08-20 recurrences.
- **Closes**: `aca0237a` (fix), this closure entry (board reconciliation).

## OI-254 — alert_client_errors_spike cnt metric still counts benign event-coded _null breadcrumbs the users/server_events arms now exclude

- **Status**: CLOSED (2026-09-27, `ops-alerting-b2a2b` batch) — the client-side rename this
  entry's own "Fix shape" called for landed as Fix 2 of that batch
  (`subscription_refresh_query_returned_null` → `subscription_refresh_no_active_row`,
  `lib/core/services/subscription_service.dart:906`), and the "Audit the other ~24 call-sites"
  instruction below was also carried out: every op_type string in `lib/` matching migration 087's
  failure-shaped reinclusion regex `(fail|error|crash|fallback|unknown|exception|timeout|denied|
  _null)` was swept (`grep -rnoE "['\"][a-zA-Z0-9_]*['\"]" lib/` piped through the regex, plus a
  manual review of every hit), turning up 6 other matches — `restoring_destination_unknown`,
  `restoring_continue_still_unknown`, `sync_completed_at_fallback`,
  `guarded_box_auto_open_fallback`, `sync_skipped_null_natural_key`,
  `restore_users_row_null_via_singlecall` — each spot-verified to carry an explicit, pre-existing
  code comment establishing it as a deliberate rare-event-surfacing signal, not an accidental
  benign-state `_null` naming collision like this OI's own case. Zero further renames needed.
  Per the entry's own reasoning, once the client-side name no longer matches the regex, "the
  regex correctly stops matching" — no SQL change to migration 147's `cnt` metric was made or is
  needed, so the SQL-side asymmetry this entry originally reported is closed by removing its one
  cause, not by widening the SQL guard (which would have undone 087/f0b9d3's own P0 fix, per
  this entry's "Why not fixed in 147 directly" reasoning below).
- **Blocked on**: none.
- **Verified**: 2026-09-27 — `test/contracts/oi254_subscription_refresh_op_type_rename_test.dart`
  (5 tests, green) pins the rename and that the new name does not match the regex; live volume
  this removes from `cnt`'s matched set (28 occurrences/36 days) reconfirmed against migration
  147's own diagnose-doc (`d2c9f4`) impact_analysis.
- **Identified**: 2026-09-27 · filed via mint_oi.sh from branch `ops-alerting-b2a2a`
- **Problem**: migration 147 (diagnose `d2c9f4`) added an `error_code NOT IN
  ('event','info')` guard to the NEW `users` and `server_events` breadth arms,
  citing the routine `event`-coded `subscription_refresh_query_returned_null`
  breadcrumb (`lib/core/services/subscription_service.dart:911-912`) as the
  reason. The PRIMARY `cnt` metric — the one the threshold (40/100/200)
  actually gates on, and the metric this whole migration exists to fix — has
  no equivalent guard, because it inherits the outer breadcrumb-reinclusion
  regex `(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)`
  from migration 087 (diagnose `f0b9d3`), which matches this breadcrumb's
  `_null` suffix even though its `error_code='event'`. Found by the
  self-triggered B-pass (`docs/reviews/46c9b9ff3bde-review.md`, Finding 1),
  verified live: this exact breadcrumb fires 28 times over 36 days (41 total
  across every event/info-coded op_type matching the same regex); currently
  NON-MATERIAL (`max(cnt)` over the same window is 24, well under the 40
  floor).
- **Why not fixed in 147 directly**: two of three SQL-only fixes were
  evaluated and rejected. (a) Adding the same `error_code NOT IN` guard to
  `cnt` would UNDO 087/f0b9d3's own P0 fix — that guard exists specifically
  to catch genuine failures the client mislabels `error_code='event'`, and
  narrowing `cnt` back to exception-shaped-only reopens that exact blind
  spot. (b) A literal/name-based exclusion for just this one op_type is the
  "transient denylist" f0b9d3's own diagnose doc already evaluated and
  rejected, because the SAME client-side mislabeling pattern recurs across
  ~25 call-sites under different op_type strings — patching one name here
  is whack-a-mole, not a fix. The actual root cause is CLIENT-SIDE: the
  `_null` suffix on an op_type is supposed to signal "a query that should
  have returned data returned null unexpectedly" (a bug), but this call site
  uses `_null` for an EXPECTED, benign state transition ("no active
  subscription row" is a normal outcome, not a bug) — a pure-SQL cron
  migration cannot distinguish "benign business _null" from "buggy _null" by
  regex alone.
- **Fix shape**: rename this call site's `op_type` on the client (e.g. to
  something that does not match the failure-reinclusion regex, or introduce
  a distinct "expected state transition" telemetry category the regex
  explicitly excludes) — this is a `lib/` change, naturally in scope for
  B2a-2b (client telemetry, the next unit in this same batch) since that
  unit already touches `ErrorTelemetry`/offline-signature semantics on the
  client side. Audit the other ~24 call-sites f0b9d3 already identified for
  the same class while there. Once fixed client-side, no SQL change is
  needed here at all — the regex correctly stops matching.
- **Class**: a shared classification regex (the breadcrumb-reinclusion
  pattern) applied asymmetrically across three derived metrics computed from
  the SAME filtered rowset, where narrowing the metric is worse than leaving
  the asymmetry, and the real fix lives one layer up (client) from where the
  finding surfaced (SQL migration).
- **Source**: B-pass finding 1, `docs/reviews/46c9b9ff3bde-review.md`; diagnose
  `d2c9f4` (147); diagnose `f0b9d3` (087, the original rejected-denylist
  precedent this finding extends).
- **Closes**: `docs/diagnoses/2026-09-27-sync-telemetry-dual-write-oi254-offline-signature-f7b2c9.md`
  (fix), this closure entry (board reconciliation).

## OI-255 — Migration numbering has no collision-proof allocator -- two branches both minted 145 AND 146

- **Status**: CLOSED (2026-09-28, `gate14-migration-collision` batch) — implemented this entry's
  own fix-shape option (b): Gate 14 (`scripts/check_migrations_applied.dart`) now hard-fails on
  two `.sql` files sharing an exact bare numeric prefix, naming both, via a new
  `scripts/migration_collision_lib.dart`. The two ALREADY-APPLIED collisions this entry documents
  (145 and 146) are grandfathered by name in the check — permanently, since both pairs are
  immutable once applied — with an explicit comment forbidding future additions to that list.
  Option (a), a `mint_oi.sh`-style migration-number allocator (reserving a ref before drafting a
  new migration file), was considered and explicitly NOT implemented — founder chose option (b)
  alone for now as sufficient practical prevention at a fraction of the engineering cost; it
  remains a legitimate future enhancement, not a deferral of this entry's own ask (the ask was "a
  fix shape (a) and/or (b)", and (b) alone satisfies it). The underlying historical fact this
  entry documents — that migrations 145 and 146 were each independently claimed twice — is
  permanently true and cannot be undone; this closure is about the PREVENTION mechanism, not about
  retroactively resolving four already-live, immutable files.
- **Blocked on**: none.
- **Verified**: 2026-09-28 — `test/scripts/migration_collision_lib_test.dart` (7 tests) +
  `test/scripts/check_migrations_applied_collision_e2e_test.dart` (3 tests spawning the real gate
  binary against a throwaway repo), all green. Mutation-proven: neutering the detection reddened
  4/10 tests, neutering the grandfather exclusion reddened 2/10 — both mutations confirmed applied
  and compiling, both reddened for the correct assertion-failure reason (not a compile error or a
  swallowed exception). The real 145/146 quadruple was reproduced in the e2e suite and confirmed
  to still pass Gate 14 (must not start failing every future commit); a NEW, non-grandfathered
  collision (two files both prefixed "148") was reproduced and confirmed to fail it, naming both
  files, closing the exact blind spot this entry's own "Impact" section named
  (`appliedMigrations.any((a) => a.startsWith(prefix) || ...)` satisfying both colliding files'
  ledger check independently).
- **Identified**: 2026-09-27 · filed via mint_oi.sh from branch `template-stable-identity`
- **Problem, Root cause, Impact**: see this entry's own body, preserved verbatim below — none of it
  changed by this closure; only the fix-shape section is superseded by "Fix implemented" below.

Symptom: `supabase/migrations/` now holds FOUR files across two colliding number prefixes, not one
as first filed (corrected during the merge to `main` — the merge conflict in
`backups/applied_migrations.json` exposed a second collision at 145 that a single-number
investigation had missed): `145_alert_sql_job_failures.sql` / `146_alert_cron_job_silent.sql`
(main, OI-178/ops-alerting-b2a batch, applied live 2026-09-26/27) and
`145_workout_templates_stable_delete.sql` / `146_workout_templates_delete_trigger_insert_path.sql`
(this branch, OI-252, applied live 2026-09-27T06:44:46+05:30 and 2026-09-27T10:22:49+05:30). All
four have their own `"migration"` entry in `backups/applied_migrations.json` (main's two, then this
branch's two, in that chronological order after the merge). Found when pulling `origin/main` into
the primary worktree immediately before merging `template-stable-identity` — the two branches
diverged from `main` before either side's migrations existed on the other, and each independently
picked "145" then "146" as the next free number at draft time, in the same order, coincidentally.

Root cause: migration numbers are chosen by hand from whatever `ls supabase/migrations/` shows the
drafting branch at draft time — there is no reservation mechanism analogous to `mint_oi.sh`'s
`refs/heads/oi/N` compare-and-swap for OI numbers (§7 pointer table, OI allocator row). Two
branches developing in parallel off diverging `main` states have no way to see each other's
in-flight migration numbers.

Impact, checked rather than assumed: **no functional collision** — all four migrations touch
entirely disjoint database objects (a `workout_templates` trigger function + soft-delete column vs.
two new pg_cron alert jobs + their functions), all four applied successfully and independently.
**Gate 14 (`scripts/check_migrations_applied.dart`) does not detect the ambiguity**: its
"unapplied" check matches by bare numeric prefix via `appliedMigrations.any((a) =>
a.startsWith(prefix) || ...)` (`check_migrations_applied.dart:97-101`), so both files under each
colliding number independently satisfy the same ledger entry and the gate reports PASS for all
four. The break is the implicit "one number names exactly one migration" invariant relied on for
human navigability, `docs/naming_conventions.md`-style citation, and any future tooling that
assumes strict 1:1 sequential numbering.

Historical note (fix implemented 2026-09-28, superseding the paragraph below): **all four files
remain immutable once applied** (same principle
`docs/diagnoses/2026-09-21-hermes-pass-migration-138-139-fixes-h1a2b3.md` and this file's own
common-pitfalls table state for migration 138/139) — renaming any of them post-apply would
misrepresent what actually ran and would invalidate cross-references already pushed on both
branches (diagnose-docs, commit messages, `backups/applied_migrations.json` `"migration"` values,
OI-board prose). Fix shape (as originally filed, not designed): (a) a migration-number allocator
mirroring `mint_oi.sh` — reserve a ref before drafting a new migration file so a second branch
drafting in parallel sees the reservation on its next fetch — and/or (b) widen Gate 14 to hard-fail
on two `.sql` files sharing an EXACT bare numeric prefix (distinct from today's loose "is this
number present in the ledger at all" check), so a future collision is caught at commit/push time
instead of only by a human noticing during a `git pull` before a merge. **Fix implemented:** option
(b), via `scripts/migration_collision_lib.dart` — see Status above.
- **Class**: a manual, unreserved numbering scheme with no cross-branch visibility, structurally
  identical to the class `mint_oi.sh` was built to close for OI numbers — but for migration
  numbers, which (unlike OI numbers) become permanently immutable the moment they are applied
  live, so a collision here can never be un-collided, only prevented from a third recurrence.
- **Source**: filed via `mint_oi.sh` from `template-stable-identity`, 2026-09-27; closed via
  `docs/diagnoses/2026-09-28-gate14-migration-number-collision-detection-d5f1b8.md`.
- **Closes**: `docs/diagnoses/2026-09-28-gate14-migration-number-collision-detection-d5f1b8.md`
  (fix), this closure entry (board reconciliation).

## OI-258 — backups/applied_migrations.json missing entries for live-applied migrations 147 and two colliding 145/146 numbers across diverged main branches

- **Status**: CLOSED (2026-09-28, board reconciliation — no new code) — both findings this entry
  documents are already resolved on `main`, as a side effect of subsequent, unrelated work landing
  after this entry was filed; nothing was left to fix.
  1. **The "missing 147 entry" finding was never true on `main`.** It was true only on the
     divergent branch (`single-owner-a2b`) this entry was filed from, which had branched before
     commit `984d9c51` (`fix(alerts): rewrite alert_client_errors_spike...`) landed — and that
     commit added the migration-147 ledger entry in the SAME commit that applied it, per §4.5, as
     it should. When `single-owner-a2b` was later merged into `main` (`8ff6c1f1`), the two
     histories reconciled and the ledger came out complete. No standalone hygiene commit was ever
     required.
  2. **The 145/146 collision bookkeeping is also already complete**, but via the sibling entry
     **OI-255** (filed the same day, closed 2026-09-28) rather than via this entry's own suggested
     fix. OI-255 hard-codes the two colliding, already-applied migration numbers into Gate 14's
     permanent grandfather list (`scripts/migration_collision_lib.dart:26`,
     `grandfatheredMigrationCollisionPrefixes = {'145', '146'}`), which both documents the
     collision durably and makes a FUTURE recurrence of this class fail the commit by naming both
     files. **This entry's own suggested resolution — "document the collision inline in each of
     the four files' headers" — was correctly NOT done.** `supabase/migrations/CLAUDE.md:72-96`
     is explicit that an applied migration is immutable including its comments (a comment edit
     changes the file's hash while the ledger still records the old one, silently falsifying the
     audit trail — this happened once already, migration 127). The immutability rule's own
     prescribed alternative — "the correction goes in the diagnose-doc, and — if it is a durable
     trap — a row in root CLAUDE.md §4.9" — is exactly the shape OI-255's grandfather list takes.
- **Blocked on**: none.
- **Verified**: 2026-09-28 — `backups/applied_migrations.json` on `main` (HEAD `e75d630d` at
  verification time) holds complete entries for migration 145 (both slugs
  `alert_sql_job_failures` / `workout_templates_stable_delete`), 146 (both slugs
  `alert_cron_job_silent` / `workout_templates_delete_trigger_insert_path`), 147
  (`alert_client_errors_spike_breadth`), and 148. `sha256sum` recomputed against the actual files
  on disk for all five 145/146/147 files and compared byte-for-byte against the ledger's `hash`
  field — all five match exactly, confirming no file was edited to "fix" this (which would have
  been the wrong fix per the immutability rule above). `dart run scripts/check_migrations_applied.dart`
  (Gate 14) passes clean: `[Gate 14] PASS — all local migrations appear in the applied snapshot
  (156 applied)`, with the collision check (`findMigrationPrefixCollisions`) reporting no
  new, non-grandfathered collisions.
- **Identified**: 2026-09-27 · filed via mint_oi.sh from branch `single-owner-a2b`, discovered
  while investigating `test/contracts/applied_migrations_parity_test.dart`'s failure ahead of
  migration 148's own ledger entry. Original Problem/Root cause/Impact preserved verbatim below —
  none of it changed by this closure; only the "Fix, when picked up" section is superseded by
  "Status" above.
- **Note**: this entry's own "Consider whether `mint_oi.sh`'s allocator pattern... should be
  extended to migration numbers too" bullet is picked up independently by **OI-263**
  ("Migration-number allocator: reserve migration numbers server-side (mint_oi.sh pattern)"),
  filed 2026-09-28 from a separate concurrent branch (`day-swapper-sync-load`, not yet merged to
  `main` at the time of this closure) — not opened or actioned by this closure, noted only for
  cross-reference.

**Two independent findings, both real, both live on `dedsavbjuwgarrhphgnl`:**

1. **Migration 147 (`147_alert_client_errors_spike_breadth.sql`, commit `984d9c51`, diagnose `d2c9f4`,
   batch `ops-alerting-b2a2a`) was applied live (cloud `list_migrations` shows version
   `20260927094123`, name `alert_client_errors_spike_breadth`) but `backups/applied_migrations.json`
   has NO `"migration": "147"` entry** — violates CLAUDE.md §4.5 ("Migration apply paired with
   `backups/applied_migrations.json` update in same commit"). Confirmed via
   `python3 -c "... '147' in versions"` → `False` against the file on `main` (HEAD `00ae3e46` /
   `d8832af8` on `origin/main`). This branch (`single-owner-a2b`) does not even have the 147 file
   in its own tree yet (branched before it landed), so it cannot be fixed from here without pulling
   unrelated work into an unrelated feature branch — needs its own small commit directly against
   `main`'s current tip, in a fresh worktree, never in the shared primary worktree per §4.13.

2. **`main` and `origin/main` used migration numbers `145` and `146` for TWO DIFFERENT PAIRS of
   migrations, and BOTH pairs are already live-applied to the SAME prod database:**
   - This branch's lineage: `145_alert_sql_job_failures.sql` / `146_alert_cron_job_silent.sql`
     (ledger entries present, `cloud_version` `20260926183009` / `20260926183056`).
   - `origin/main`'s lineage (12 commits ahead of local `main` at discovery time, presumably a
     different concurrent session's branch, since `avya-c4` showed `busy` in `ListAgents` at the
     time): `145_workout_templates_stable_delete.sql` /
     `146_workout_templates_delete_trigger_insert_path.sql`, confirmed live via `list_migrations`
     (`cloud_version` `20260927011446` / `20260927045029` — LATER than this branch's 145/146, so
     they landed on cloud AFTER this branch's own 145/146 were already applied).
   Both pairs are immutable (already applied — supabase/migrations/CLAUDE.md forbids editing an
   applied migration file, and a rename is the same class of risk even though it wouldn't change
   the file's hash). This is the exact "migration numbering coordination risk" already flagged as
   a residual/hypothetical risk in `docs/diagnoses/2026-09-27-coach-extraction-locked-fields-writer-drift-a2b2f1.md`'s
   own numbering-risk section for migration 148 — it just materialized for real at 145/146 instead,
   from a totally different pair of branches, before 148 was even drafted. The earlier mitigation
   (`ls`-checking each branch's HIGHEST migration number before picking one) is insufficient: both
   branches' highest number matched (147) at check time, which hid that two MIDDLE numbers (145,
   146) had already silently diverged and both gone live. A number-uniqueness check needs to diff
   the actual FILE SET per number across branches, not just compare the max.
   No schema-object collision is expected (the two migrations touch entirely disjoint tables/
   functions — `workout_templates` vs `alerts`/`cron.job`), so this is a bookkeeping/numbering
   problem, not a data-corruption one. Nothing needs reverting.

**Third finding, ALREADY FIXED (single-owner-a2b-2's own commit, same investigation):**
`backups/live_schema_columns.json` (Gate: `scripts/check_schema_column_refs.dart`) was ALSO
stale — `workout_templates` gained a `deleted_at` column via the 145/146 collision pair above,
but the snapshot file was never regenerated for it (same "regen in the same commit" rule the
147-ledger gap violated, different file). Found by diffing a full live
`information_schema.columns` dump against the snapshot file table-by-table (not just the two
columns THIS batch's migration 148 added) — a `check_schema_column_refs.dart` run would have
failed on the very next commit touching `workout_templates` regardless of who made it. Fixed
inline in this batch's commit (adding `deleted_at` to the snapshot's `workout_templates` array)
since it's a pure-additive, zero-risk JSON edit directly unblocking this batch's own gate — unlike
the ledger/migration-file findings above, which need their own standalone commit.

- **Class**: board staleness — the underlying problems resolved as a byproduct of unrelated merges
  before anyone re-read the board entry against current state.
- **Source**: filed via `mint_oi.sh` from `single-owner-a2b`, 2026-09-27.
- **Closes**: this closure entry (board reconciliation; no diagnose-doc — no code changed).

## OI-63 — Restore C2: 137-policy RLS initplan

- **Status**: CLOSED · 2026-09-26 · verified_clean, no code change · branch `ci-green-batch-a`
- **Verified**: 2026-09-26 — LIVE: 144 public policies, 137 mention `auth.uid()`, **0** still unwrapped (case-insensitive strip of `( SELECT auth.uid() AS uid)`); 0 `auth.jwt()`/`auth.role()`/`current_setting` hits; performance advisor has no `auth_rls_initplan`/`multiple_permissive` lints. Done by migration 100 (2026-07-07, before this OI was filed) + 141 (readiness_daily).
  PRIOR (kept verbatim): 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`,
  2026-07-27). This issue's own substance has NOT been re-checked since filing.
- **Identified**: 2026-07-26 · restore-perf C3 shipped
- **Blocked on**: none — it was sequenced after OI-52, which closed 2026-07-27. Pickable now.

## OI-66 — Prove or remove the CI gradle cache

- **Status**: CLOSED · 2026-09-26 · proven win, keep the cache · branch `ci-green-batch-a`
- **Blocked on**: none
- **Verified**: 2026-09-26 — CI run on `fafec56a`: 'Cache hit … Cache restored successfully' (setup-java gradle key), Build Check (APK) 02:59:14→03:02:39Z = 3m25s; 3m52s/3m37s/3m50s on the 3 prior runs, vs the 7m41s uncached baseline.
  PRIOR (kept verbatim): never
- **Identified**: 2026-07-26 · ci-speed batch `904e6961`
- **Risk class**: unverified optimisation
- **What's missing**: The cache is **3.4 GB**; restore-and-extract cost may exceed the Gradle work it
  saves. First run only populated it, so its value is still unmeasured. Compare a warm-cache run's
  `Build Check (APK)` duration against the 7m41s/7m47s uncached baseline. **If it is not a clear win,
  take it back out** — an unmeasured optimisation is tech debt.

## OI-153 — PRO media caps read a `channel` value nothing writes (P1)

- **Status**: CLOSED (2026-09-13, `oi153-pro-media-caps`) — diagnose `a9d4e7`
- **Blocked on**: none
- **Verified**: 2026-09-13 — source (`67ba6ba4`, `f15fad75` + the review-remediation commit),
  4 context-blind plan rounds, a 2-agent B-pass (6 findings, 0 false alarms, all fixed), 13 + 15
  mutations restored byte-identically; LIVE: `ai-media-proxy` **v24** deployed 2026-09-13
  02:17Z (verify_jwt=true unchanged) from the branch bytes that the merge carries to `main`
  unchanged — decoded multipart `/body` SHA-256 of `index.ts` (`48549aa1…`) and
  `_shared/coach_replies.ts` (`0fea2a5a…`) equal the git blobs; anon-Bearer probe → the module's
  own 401; a real-user-token smoke (QA account, `{}` body, session revoked after) → the module's
  own 400 `Missing 'message'`, never 401. `founder-digest` v1 deployed the same morning
  (verify_jwt=false), first digest delivered 02:00Z. THEN, after the Hermes E-pass
  (`docs/audit/2026-09-13-hermes-oi153-pro-media-caps.md`, catastrophic tier — migration 131's
  COMMENT carries "SECURITY DEFINER"): `ai-media-proxy` **v25** (~06:39Z; the L23 P0 path
  traversal through the OI-28 guard, diagnose `c7e2a4`, plus the served-MIME cap key and the
  non-numeric RPC refusal; real-user traversal probes → 403) and `founder-digest` **v2** (~06:47Z;
  exact alert count, line-boundary truncation, parallel bounded reads, unlisted keys surfaced,
  the reached-yesterday label; manual re-run 200 with a `cron_call_log` row). Both byte-identical
  to the committed blobs by decoded `/body`. THEN, after a B-pass on this same apply commit found
  2 more real defects in `ai-media-proxy` (BP-1: a vestigial raw-string SSRF pre-check, strictly
  MORE restrictive than `parseStorageUrl`, deleted; BP-2: the served-MIME paywall reconciliation
  only ran one direction — the mirror extracted as `checkFreeImageQuota`, called pre- AND
  post-fetch): `ai-media-proxy` **v26** (~13:04Z; anon/real-user/traversal probes unchanged, byte-
  identical). Separately, `founder-digest` **v3** (~13:08Z; the alerts `.limit()` literal fixed for
  `check_unbounded_cron_reads.dart`; `unlistedTotals` made mode-aware — a lifetime key now reports
  movers, never a summed cumulative counter) — delivered live (200, reachable only post-send) but
  this ONE run's own `cron_call_log` row was lost to a live PostgREST 504 on the start-insert, a
  fresh recurrence of OI-194 during the batch's own verification. Both v26/v3 byte-identical to the
  committed blobs by decoded `/body`. Ledger: `docs/audit/oi153-pro-media-caps.closure.yaml`.
- **CLOSED BY** the OI-153 batch (plan `docs/audit/oi153-plan.md`, record
  `docs/plan-reviews/oi153-pro-media-caps.md` whose `bpass_review:` is the one pointer to the
  review). What changed, per defect in this entry:
  - **CODE-1/CODE-3 (the dormant 50/day image cap, fail-open)**: the channel-counting gate and
    `countProImageAnalysesToday` are DELETED. PRO callers now hit ONE atomic
    `consume_quota(pro_image_daily | pro_video_daily, istDayStartIso(), 50 | 10)` placed after the
    Storage fetch (a rejected upload never spends a unit) and before the Gemini call (the spend is
    bounded under concurrency — an advisory read is not). `-1` → HTTP 200 `gated: true` with a
    rank-free Bridge reply naming the midnight-IST reset; every installed APK renders it as an
    ordinary coach bubble. A ledger error fails CLOSED (`pro_quota_unavailable`), as does the
    `subscriptions` read error that the old code DISCARDED (`tier_unavailable` — it used to route a
    paying user down the free path). Founder decisions 2026-09-12: 50 images / 10 videos per IST
    day, in-app reply not the paywall, midnight-IST reset.
  - **CODE-2 (PRO video uncapped)**: the same guard — `if (isPro)`, image and video alike; the key
    AND the cap are selected by `isVideo`, association pinned by two regexes and a
    literal-independent guard assertion (B-pass finding 5).
  - **CODE-4 / the enumeration this entry demanded**: the `pro_image_analysis` /
    `image_analysis` channel literals are gone from the repo (the "dead reader" test greps for
    them); `founder_metrics_engagement()` (migration 120) never needed a change because nothing
    writes those channels — the enumeration ran to empty in the plan's ground truth (0 rows, ever).
  - **The last of the ten**: the ledger census (`usage_quota_ledger_writer_to_reader_test.dart`)
    reads ZERO legacy quota readers; `usage_counter_source_lib.dart`'s ai-media-proxy entry is 0.
  - **The founder digest** (Unit D, `founder-digest` cron EF, migration 131 in the apply commit):
    one Telegram message at 08:00 IST with yesterday's ledger per key, users at a ceiling, top id
    prefixes, and the day's alerts — three states per section, never zeros for a failed read. The
    OI-183 trigger asymmetry closes in the same apply commit (migration 132).
- **Filed from this batch, not fixed here**: OI-196 (morning-alert's sender can log the bot
  token), OI-192 (orphan-sync dedupe never matches a photo turn), OI-193 (Gate 31 blind to a
  commented `cron.unschedule`), OI-194 (`compute_admin_metrics_daily` silent-skip class),
  OI-195 (Gate 42 never checks a cited test path exists).
- **Was** (retained for provenance):
- **Verified (at filing)**: 2026-09-03 — source + live prod
- **What**: tech-debt audit 2026-09-02 findings CODE-1, CODE-2, CODE-3, CODE-4 (Slice B). The PRO
  50/day image cap counts `channel IN ('pro_image_analysis','image_analysis')`
  (`ai-media-proxy/index.ts:98`) but the only insert writes `'free_image_analysis'` or `'app'`
  (`:663-666`). `pro_image_analysis` appears **once** in the repo — that read. Live prod
  `ai_coach_interactions` holds **0** rows on either counted channel, so the cap has never fired.
  CODE-2: PRO+video matches neither `:433` (`isVideo && !isPro`) nor `:504` (`!isVideo && isPro`) —
  the most expensive request type is uncapped.
- **Why it is not a one-line fix**: stamping `pro_image_analysis` drops those rows out of two
  allowlists outside `supabase/functions/` — `coach_interaction_repository.dart:282`
  (`_coachChatChannels`, filters the coach's replayed history) and
  `migrations/120_...sql:125` (`founder_metrics_engagement()`, live). Three review passes each
  found readers the previous one missed, so **the enumeration must be run to empty before design**.
  Changing the read to count `'app'` is REJECTED — `'app'` is shared with ai-proxy text chat.
- **Also**: CODE-1/CODE-2 share one ternary at `:663-665`; `"image_analysis"` is a second dead
  channel with no disposition; updating `founder_metrics_engagement()` needs a migration that may
  collide with the in-flight backend-CPU-starvation batch (migration 120).
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §11 Slice B.

### ✅ CLOSED 2026-09-08 by OI-162 slice 3b — the FREE-IMAGE LIFETIME QUOTA resets itself

A third instance of the counter-in-a-summarized-table class, split out of OI-162 because its storage
semantics are the OPPOSITE of a windowed rate limit and it belongs with this entry's channel work.

- **The defect**: `ai-media-proxy/index.ts:62-76` `countFreeImageAnalyses` enforces
  `FREE_IMAGE_ANALYSIS_LIMIT = 5` (`:16`, checked `:466`) by counting **lifetime** rows —
  `.eq("user_id").eq("channel","free_image_analysis")` with **no `created_at` bound** (its own
  docstring says "lifetime"). Those rows are non-`app_event`, so `rolling-context:329-351` selects
  them and `:463-472` deletes all but the newest 10 once `:364` passes `MESSAGE_THRESHOLD = 50`.
  **A lifetime quota has no window to survive deletion on — the 5-image free cap resets toward
  unlimited.** Verified: no guard blocks it.
- ⚠ **Second, independent defect in the same function**: `if (error) return 0` with a docstring
  arguing *"fail-open is safer … because 0 < 5"* — which is precisely when the gate does NOT fire.
  (Audit finding CODE-3.) Both must be fixed together.
- ⚠ **A client-side TWIN exists and is easy to miss**:
  `lib/features/ai_coach/repositories/ai_coach_repository.dart:279-292`
  `getFreeImageAnalysisCount()` reads the same `channel='free_image_analysis'`. Currently **uncalled**
  (`grep -rn getFreeImageAnalysisCount lib/ test/` → 1 hit, its own definition), which makes it cheap
  to fix now and easy to forget later — textbook writer/reader drift (§4.1).
- **LATENT, not live** (verified 2026-09-03): **zero** `free_image_analysis` rows exist, and no user
  is near the 50-row prune threshold (max non-`app_event` = 25). The mechanism is real; nobody has
  hit it. So the "migrate existing consumed quota" question is currently moot — there is nothing to
  migrate.
- **Why NOT in the OI-162 table**: a lifetime quota must never be pruned, while a windowed rate limit
  must be. Fusing them forced a retention exclusion that would have retained a `user_id` forever
  after a DPDP erasure. They are different concepts that share a word.
- **CLOSED 2026-09-08 by slice 3b.** The gate now does an ADVISORY `.maybeSingle()` read of
  `usage_counters` (quota_key `free_image_analysis`, `'epoch'` window) and `consume_quota` is the
  authoritative writer, running AFTER the conversation-log insert and gated on it having succeeded.
  Both defects above are closed together, as this entry required: the fail-OPEN `if (error) return 0`
  now fails CLOSED and returns its own `gate_reason: "quota_unavailable"` rather than the paywall's
  (telling a user who spent nothing that they spent 5 would be a lie). The client twin
  `getFreeImageAnalysisCount()` was DELETED, not repointed — zero production callers.
  Pinned by `test/contracts/media_free_image_lifetime_gate_writer_to_reader_test.dart` (10 assertions,
  mutation-proven on 6 legs) + the ratcheted allowlist in `scripts/usage_counter_source_lib.dart`
  (2 → 1). No migration: `quota_key` is unconstrained `text`.
- ⚠ **Two corrections to this entry, recorded rather than silently fixed.** Its
  `ai-media-proxy/index.ts:62-76` citation was stale by the time it was closed — the function sat at
  `:67-82`; the entry was written 2026-09-03 and the file shifted under it. And its
  `grep -rn getFreeImageAnalysisCount lib/ test/ → 1 hit` was scoped to `lib/` in practice: there
  were **2**, the second being a `stillLegacy` map entry in
  `usage_quota_ledger_writer_to_reader_test.dart` that asserted this very file still read the old
  table. Deleting the method broke it. Found by plan-review round 1, before landing.
- ⚠ **Still LATENT at closure, verified live 2026-09-08:** `select count(*) from
  ai_coach_interactions where channel = 'free_image_analysis'` → **0**, across 0 distinct users. So
  the cutover regrant ("everyone starts at used=0") affected nobody. Re-measure rather than citing
  this; the mechanism was real and would have bitten the first user to spend one.

### ✅ CLOSED 2026-09-06 by OI-162 slice 3a — the WEEKLY-REPORT first-free gate

**Was:** "ALSO 2026-09-03 — the WEEKLY-REPORT first-free gate is a lifetime count and resets the
same way."

**Fixed in OI-162 slice 3a.** The gate now reads `usage_counters` (quota_key
`weekly_report_free`, `'epoch'` lifetime sentinel) via an advisory fail-closed read, and
`consume_quota()` writes it gated on `!hasPro`. `rolling-context` cannot touch that table, so the
one free Gemini 2.5 Pro report can no longer regenerate. The `ai_coach_interactions` insert stays
verbatim — it is the sole persisted copy of the report and the row a reinstall restores — but it
no longer feeds the gate. Pinned by `weekly_report_lifetime_meter_test.dart` (9 assertions, 9
mutations) and the repointed `weekly_report_pro_gate_writer_to_reader_test.dart`.

⚠ The free-IMAGE lifetime quota below is NOT closed by this — that is slice 3b.

⚠ **Found in code shipped to prod hours earlier the same day** (`a0e20576`, diagnose `e4d1b7`).
That fix closed the gate's FAIL-OPEN half (a failed count granted a free Gemini 2.5 **Pro** report).
It did not touch — and the diagnose-doc never asked about — what DELETES the rows the gate counts.

- `weekly-report/index.ts:93-98`: `.select("id", { count: "exact", head: true })
  .eq("user_id", …).eq("channel", "weekly_report")` — **no `created_at` bound**, i.e. a LIFETIME
  count, feeding `isFirstReport` at `:113` and the PRO gate at `:116`.
- `weekly_report` is non-`app_event`, so `rolling-context:329-351` summarizes and `:463-472` deletes
  it once the user passes `MESSAGE_THRESHOLD = 50`. Count returns to 0 ⇒ `isFirstReport` true ⇒
  **another free Gemini 2.5 Pro report**, repeatedly.
- Same class as the free-image lifetime quota above; same remedy (a quota ledger that is not pruned).
- **How it was found, worth recording:** a plan reviewer proposed replacing a VOCABULARY-based gate
  matcher (`rate.?limit|attempt|throttle` near the table) with a STRUCTURAL one — `count: "exact"`
  in the same statement as an `.eq/.in("channel")` filter. Run over `supabase/functions/` it returns
  **exactly 5 sites, zero false positives**, and this was site 5. The vocabulary matcher missed it
  and two others, while firing on two `rate_limit` mentions that were COMMENTS. **Match on what the
  code DOES, not on what its prose calls itself.**

### ⚠ STALE 2026-09-06 — the nightly summarizer RESETS two paid-tier daily caps

**Superseded by OI-162 slice 2 (`c7b95fe5`, migration 129), not by any work under this OI.**
Live-verified with `pg_get_functiondef`: all three cap triggers
(`enforce_chat_app_daily_limit`, `enforce_vision_analysis_daily_limit`,
`enforce_food_text_daily_limit`) now read `usage_counters` EXCLUSIVELY — zero
`ai_coach_interactions` references in any trigger body. This subsection's premise, that those
caps are resettable because the summarizer prunes the rows they count, is structurally
impossible now.

⚠ Its **"THREE DEFECTS MOVED HERE 2026-09-04"** sub-list below stays OPEN — those are separate
items, mostly slice-3b scoped, and item 3 (CI cannot drive cron-gated SQL) is unaddressed.

*Original text retained below for provenance.*


Found while checking a different question; nobody had looked. Same root as the entry above
(a counter whose rows `rolling-context` deletes) but a DIFFERENT mechanism — these caps are
enforced by **Postgres triggers**, not Edge Function code, so an EF-only search misses them.

- `rolling-context/index.ts:27-28` — `MESSAGE_THRESHOLD = 50`, `KEEP_RECENT = 10`; `:369-370`
  summarizes everything except the newest 10 and `:463-472` DELETES it, for any user with >= 50
  non-`app_event` rows.
- The three daily caps count an **IST-day window** over `ai_coach_interactions` (live
  `pg_get_functiondef`): `enforce_chat_app_daily_limit` >= **10**,
  `enforce_food_text_daily_limit` >= **50** free / 200 PRO, `enforce_vision_analysis_daily_limit`
  >= **20**.
- **Where the cap exceeds KEEP_RECENT, the cap is resettable.** A free user who reaches the 50/day
  food-text cap has 50 rows today; the 02:30 IST cron keeps the newest 10 and deletes 40, the
  trigger recounts 10, and **40 more analyses unlock**. Same shape for vision (20/day).
- ✅ **chat (10/day) is SAFE — by coincidence, not design.** The cap blocks the 11th row, so a user
  can hold at most 10 rows for the day, and KEEP_RECENT is also 10, so today's rows are exactly the
  ones kept. ⚠ **That safety evaporates if either constant is changed independently** — they are in
  different files with no comment linking them.
- **LATENT** (verified 2026-09-03): max non-`app_event` rows for any user is **25**, below the 50
  threshold, so this has not fired. Both caps are paid-tier boundaries, so it is a revenue issue
  once usage grows.
- **Design note for whoever takes this**: this is a **quota ledger**, not a rate limiter. It also
  needs `countProImageAnalysesToday` (`:88-99`, IST-day) resolved at the same time — that is CODE-1
  above, the dead `pro_image_analysis` read, so the two are one piece of work.
- **THREE DEFECTS MOVED HERE from the OI-162 review, 2026-09-04** — they were surfaced by review
  round 1 of the usage-counter redesign and, until this edit, lived ONLY in
  `docs/plan-reviews/oi162-round1-findings.md`. A known bug parked in a review-notes file nobody
  has a reason to open is a §4.2 deferral in substance, whatever it is called. They are recorded
  here because this OI already owns `ai-media-proxy` + `weekly-report` quota territory:
  1. **Consumption moves from success-time to request-time** if a counter is naively swapped to an
     increment call. Today the free-image row is written at `ai-media-proxy:669`, AFTER Gemini
     returns; the 502 path returns at `:645` writing nothing. An increment at the pre-flight gate
     means **a free user whose Gemini call fails permanently loses one of five lifetime analyses**,
     and a weekly-report failure burns their single free Gemini 2.5 Pro report — with no report.
     Needs either a read-only pre-flight (`peek`) plus consume-at-the-existing-write-point, or an
     explicit release-on-failure path with every failure path enumerated.
  2. **`ai-media-proxy:687` is a SECOND call to the same counter** — a display re-count after the
     insert, commented at `:680-682` as "re-count AFTER insert so the displayed remaining is
     accurate". Under an increment-based counter it burns a second unit on every success, turning
     the 5-image cap into 2. Any fix must make `:687` read the value the single consume returned,
     not re-query.
  3. **The `rolling-context` prune interaction is not testable in CI.** `rolling-context:117-125` is
     cron-only (`isAuthorizedCronCall`), and CI carries no `CRON_SECRET` — so "the summarizer runs
     and the quota survives", the assertion that most directly pins this whole bug class, has no
     automated home. Either drive the SQL directly in a Deno test under `supabase/functions/`
     (CI's `deno-edge-functions` job runs), or record it as a manual live check in the diagnose-doc.
     Do NOT ship a test that silently skips and reads as green.

## OI-155 — six gates are wired to no runner, and Gate 33 cannot detect it (P1)

- **Status**: CLOSED (2026-09-19, `gate-integrity`) — diagnose `b3e7a1`
- **Blocked on**: none
- **Verified**: 2026-09-19 — Gate 33's `_allowList` is now `Map<String, List<GateRunner>>` (`file(path)` / `loop(preCommit|ci)` / `manual(OI-NNN)`), each runner machine-checked on every commit by `scripts/gate_scripts_wired_lib.dart` (22 pure tests + 5 lib mutations = 9 reds; two real-gate mutations — a `manual` target changed to OI-9999 and one pointed at a CLOSED OI — both FAIL exit 1; coordinator re-ran both legs by hand on the integrated branch). The six: `snapshot_contract` → runs in BOTH loops (skip lines deleted; passes today); `unawaited_has_error_sink` → `loop(ci)` (advisory; pre-commit's `>/dev/null` loop has no reader); `migrations_live` → `manual(OI-223)` — cannot pass by construction (125/139 never registered live, 75 founder raw-SQL applies; RETIRE recommended, founder's call). **Founder chose retire, same batch, same commit as this row's last edit: `check_migrations_live.dart` deleted, its allowlist entry with it — the five remaining runners above are current, `migrations_live` is no longer among them (96 `check_*`, not 97).** `onconflict_live_arbiter` + `two_user_cross_account` → `manual(OI-165)` (403); `test_runtime_budget` → `manual(OI-101)`. A `manual` runner must name an OPEN/IN_PROGRESS OI on the merged boards, so closing OI-223/165/101 turns Gate 33 red until that gate gets a real runner. Wiring inference now requires an INVOCATION (`run scripts/<gate>` on a non-comment line), not a mention; a stale allowlist key is a violation. Counts re-derived: 97 `check_*`, pre-commit loop 84 (13 case-skipped), 86 of 97 + 1 on a merge; test.yml skip 13 → 11.
- **What**: audit findings INFRA-2, INFRA-11 (Slice D). `check_gate_scripts_wired.dart` allow-lists
  gates with a free-text reason such as *"runs in /build-apk skill Gate 14b"*. For six of them
  `.claude/commands/build-apk.md` contains **0** occurrences (control: `check_apk_size_within_bounds`
  → 1), while their only occurrences in `pre-commit.sh:327-341` and `test.yml:236-249` are **skip
  entries**. They execute nowhere. Two are security-relevant
  (`check_two_user_cross_account`, `check_onconflict_live_arbiter`).
- **The audit said five; it is six** — `check_test_runtime_budget.dart` (`pre-commit.sh:338`,
  `test.yml:248`, 0 in `build-apk.md`) has the identical shape. Re-derive with `comm` rather than
  copying a number.
- **INFRA-11 is the mechanism, not a duplicate**: the allowlist reason is prose nobody parses. Fixing
  the six entries without machine-checking the allowlist leaves the class open.
- **Landing hazard**: a hard-fail INFRA-11 landing before INFRA-2 blocks every commit repo-wide.
  Land together, or warn-only first (§4.11 point 2). `check_test_runtime_budget` may need an explicit
  `runner: manual` state since it can name no runner file.
- **Un-dormanting these surfaces pre-existing violations** their allowlist already names
  ("1 unapplied migration", "3 schema-arbiter conflicts", "1 missing test"). ⚠ The
  snapshot-contract one is **stale** — that gate now passes ("57 keys checked").
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §11 Slice D.

## OI-162 — the delete-account rate limit is INERT in production; its counter has never written a row (P1)

- **Status**: CLOSED (2026-09-12, `oi162-slice4-windowed-counters`) — diagnose `f2c8d5`
- **Blocked on**: none
- **Verified**: 2026-09-12 — LIVE, post-deploy: `delete-account` v9 and `verify-payment` v18 read back
  byte-identical to `main` `f95cae45` (SHA-256 of the decoded `index.ts` via the Management API,
  `Accept: multipart/form-data`); `has_function_privilege(anon|authenticated, consume_quota)` = false
  (migration 130 intact); anon-Bearer boot probes reached both modules (their own sanitized 401).
- **CLOSED BY slice 4 of 4** (`0c13a144` + `ed4d5f05`, merge `f95cae45`, catastrophic — B-pass
  `docs/reviews/3cd1891ee7eb-review.md`, Hermes `docs/audit/2026-09-11-hermes-oi162-slice4-windowed-counters.md`,
  record `docs/plan-reviews/oi162-slice4-windowed-counters.md`). Each claim above, in order:
  - **The title defect**: `delete-account` now enforces 5/hour via `consume_quota('delete_account',
    <UTC hourly bucket>, 5)` at the top of the handler; `-1` → 429 + true `Retry-After`. The malformed
    attempt insert is GONE, not corrected. `verify-payment` (instance B) enforces 20/10min the same way,
    reads `{ error }` and now fails CLOSED by design; the un-awaited `.then()` and the inline `20`/`600`
    are gone (named constants).
  - **The TRAP** (a new channel value falling into rolling-context's denylist): avoided by construction —
    NO attempt row is written to `ai_coach_interactions` any more; both `*_attempt` channel literals
    are removed repo-wide and `test/contracts/usage_quota_ledger_writer_to_reader_test.dart` pins that
    neither file touches that table in code. The channel enumeration this entry was blocked on was
    still run to empty (`docs/audit/oi162-slice4-channel-enumeration.md`), which is what dissolved the
    OI-153 blocker: slice 4 mints no channel, so OI-153's reader work is independent of it.
  - **DPDP**: `usage_counters.user_id` is `REFERENCES users(id) ON DELETE CASCADE` (migration 128), so
    the attempt counters still erase with the user — the no-FK regression this entry warned about did
    not happen.
  - **Hardening the fix exposed** (diagnose `f2c8d5` part C): `consume_quota` is SECURITY INVOKER with
    no `p_user_id` ownership check and was EXECUTE-granted to PUBLIC/anon/authenticated (direct grants,
    not PUBLIC-inherited); migration 130 revoked all three, live-verified 42501 for `authenticated`.
    The raw table grants under the RLS-zero-policy default-deny are a separate, pre-existing gap → OI-184.
  - **Paired gate finding INFRA-14** (`check_schema_column_refs.dart` validates only the first line of a
    multi-line insert map — how the phantom columns shipped undetected): NOT touched by slice 4; carried
    as its own entry, **OI-185**, so this closure drops nothing.
  - **Not runtime-exercised yet**: `usage_counters` holds 0 rows for `delete_account`/`verify_payment`
    as of closing — the chain is source-, SQL- (`test/sql/oi162_slice4_quota_boundary_and_acl_live_verify.sql`,
    27/27 in a rolled-back txn) and deploy-verified. The first real attempt writes the row.
  - **Cost of landing**: the pre-push full suite refused the first merge on the slice-1 ledger census
    (2 assertions this slice deliberately falsified and had not repointed) — third slice that file has
    caught; repointed in `ed4d5f05`, mutation-proven.
- **PROGRESS 2026-09-06 (does NOT close this)**: slice 3a moved the `weekly-report` first-free
  lifetime gate onto the ledger — the first EDGE FUNCTION reader to migrate, where slices 1-2 were
  database-side only. It proves the EF-side pattern this issue's own fix will use: an advisory
  fail-closed `.maybeSingle()` read, `consume_quota` written AFTER the durable row and gated on
  tier, and `-1` treated as a successful refusal rather than an error. Six readers → five.
- **PROGRESS 2026-09-05 (does NOT close this)**: the `usage_counters` ledger this issue's fix will
  use is now live AND proven in production with three real readers — migration 129 (`c7b95fe5`)
  moved the chat / vision / food_text cap triggers onto `consume_quota()`. That is slice 2 of 4;
  this issue is slice 4's target and is untouched. What it de-risks: the ledger's atomicity, its
  RLS-with-no-policy guard and its retention are no longer theoretical. ⚠ The trap noted below is
  UNCHANGED and still applies — the fix here still introduces a new channel value, and
  `delete_account_attempt` rows must not become quota state.
- **Security impact**: `7ad009` (2026-05-11) added a rate limit to the delete-account
  confirmation-token check because *"a malicious actor knowing a target's 8-char user_id prefix could
  repeatedly POST attempts."* **That limit has never functioned.** `attemptCount` is structurally
  always 0, so `delete-account/index.ts:159`'s `>= RATE_LIMIT_MAX` can never fire and the
  token-guessing path on the DPDP §17 erasure endpoint is unthrottled.
- **Why the counter always fails** — the insert at `:176-182` is malformed two independent ways:
  1. `prompt_snippet` (`:179`) and `response_snippet` (`:180`) **do not exist** on
     `ai_coach_interactions`. Live snapshot: `[id, user_id, snapshot_id, channel, user_message,
     ai_response, model_used, tokens_used, was_helpful, created_at, summarized, tool_calls]`.
     Repo-wide `prompt_snippet` appears **once** — that line. ⇒ 400 / PGRST204.
  2. `user_message text NOT NULL` (`005_create_ai_tables.sql:32`) is never sent ⇒ 23502.
  **Prod confirms**: the `ai_coach_interactions` channel census lists `in_app_orphan` 57, `app_event`
  30, `food_text_analysis` 25, `app` 8, `in_app` 5, `promotion_ceremony` 5 — `delete_account_attempt`
  is absent at a granularity that shows 5-row channels.
- ⚠ **The obvious fix is a TRAP — do not just correct the columns and ship.** Making the insert
  succeed introduces a NEW channel value, and `rolling-context/index.ts:351` filters by
  `.neq("channel","app_event")` — a **denylist**, deliberately (`:347-350`), so any new channel is
  treated as conversation. Its own header (`:332-344`) records the Hermes P1-E/P1-F incident of
  2026-08-20: such rows *"were being embedded into memory_embeddings as source_type='conversation' —
  92 of 598 rows"* and reached ai-proxy's **SYSTEM prompt**, and the delete at `:466-472` then
  **removed them** — which here would silently reset the very counter the limit reads.
  ⇒ Either add `.neq("channel","delete_account_attempt")` to rolling-context's predicates in the same
  batch (also re-check `restore-user-snapshot:254`, `daily-snapshot:61`, `sync_coach.dart:121`), or
  record the attempt somewhere that is not `ai_coach_interactions`.
- **Paired gate finding (INFRA-14) — why this shipped undetected**:
  `scripts/check_schema_column_refs.dart` validates insert-map keys *"single-line + **first line** of
  multi-line maps"* (its own SCOPE/LIMITS, `:32-34`). `.insert({` puts every key from line 2 onward,
  so most of every multi-line insert map is unchecked; it runs clean today
  (`840 references validated; 0 drift`) while missing both phantom columns. Its header states this
  class *"was invisible BY CONSTRUCTION. Measured: 53% of recent fix-regressions were this
  cloud-contract class"* — it closed the single-line half only.
  ⚠ **A naive balanced-brace extension produces false positives**: a prototype measured 12
  violations of which **10** were keys of nested JSONB value objects (`ai-proxy:1081-1088`
  `metadata: { date, channel, model, is_pro }`, `rolling-context:394-397`, `daily-snapshot:222`,
  `proactive-coach-promotion:154-157`). The fix needs **brace-depth-1-only** key validation, and
  should also add ES6 **shorthand** keys (`.insert({ user_id, embedding, content })` currently
  contributes zero checked refs). ⚠ It can never catch defect #2 — the snapshot stores column
  **names only**, no nullability — so a Deno test asserting `error === null` is the acceptance
  evidence for the NOT NULL half.
- **Provenance**: tech-debt audit 2026-09-02 finding CODE-7, root cause rewritten by Slice A review
  round 1, hazard found by round 2. Split out of Slice A because its blocker is OI-153's enumeration.
- **RESCOPED 2026-09-03 to the WINDOWED counters only** (`delete_account` 5/60min,
  `verify_payment` 20/10min). The free-image LIFETIME quota — a third instance found during this
  plan review — **folded into OI-153**, because a lifetime quota must never be pruned while a
  windowed limit must be, and fusing them forced a retention exclusion that would have retained a
  `user_id` forever after a DPDP erasure.
- ⚠ **verify-payment is instance B and its root cause is NOT deletion** (corrected in review round 2):
  it counts only `>= now()-10min` and `rolling-context` is nightly, so the overlap is narrow. Its
  real defects are the **un-awaited** fire-and-forget `.then()` (`verify-payment/index.ts:258`) and
  inline magic numbers (`>= 20` at `:230`, `600`) instead of named constants.
- ⚠ **DPDP, settled by live query**: `ai_coach_interactions.user_id` is already
  `REFERENCES users(id) ON DELETE CASCADE`, and `users.id` is `REFERENCES auth.users(id) ON DELETE
  CASCADE`. So today's attempt rows ALREADY erase with the user. Any new table must preserve that —
  a no-FK design would be a REGRESSION on the erasure endpoint, not a neutral choice.
- **Related**: OI-153, `docs/audit/2026-09-02/slice-a-plan.md`, `docs/audit/oi162-plan.md`,
  diagnose `7ad009`.

## OI-176 — the OI-collision gate answers `PASS (vacuous)` for a branch with no commits, which is the exact state in which numbers are minted (P2)

- **Status**: CLOSED · 2026-09-12 · diagnose f3a9c1 · branch oi-allocator — working-tree arm in check_oi_numbering_unique.dart (dispatch on `git diff --quiet HEAD -- <boards>` before HEAD's shape); allocator in scripts/mint_oi.sh
- **Blocked on**: none
- **Verified**: 2026-09-08 — observed live, not reasoned about. On branch `regen-wave-alignment` with **zero commits** and a real three-way collision sitting in the index, `dart run scripts/check_oi_numbering_unique.dart` printed: *"PASS (vacuous): merge commit (HEAD^1 vs HEAD^2) — the … side minted no OI number that the merge-base lacked, so no cross-branch collision is expressible. 163 entries … were read and compared; **this is a checked answer, not a skipped one**."* Meanwhile `git show main:docs/audit/open_issues.md` and the staged board each carried `## OI-167`, `## OI-168`, `## OI-169` under completely different titles
- **Identified**: 2026-09-08 · B-pass finding 1 on the OI-166 Unit 1 batch (`docs/reviews/df96a61cf598-bpass.md`). The collision was found BY HAND; the gate that exists for it was green throughout
- **The mechanism**: a session works in a fresh worktree per §4.13 and mints OI numbers into the working tree BEFORE its first commit. In that state `HEAD` is whatever commit the branch was cut from — routinely a **merge commit** on `main`. The gate detects that shape and compares `HEAD^1` vs `HEAD^2`, which are two ancestors of the branch point, so it is answering a real question about the wrong pair of trees. The staged board is never compared against mainline
- ⚠ **Why this is worse than a skip**: the gate distinguishes SKIPPED from PASS deliberately (its own first live run reported PASS against an empty mainline board, which is why that wording exists) — and then emits `PASS` plus *"this is a checked answer, not a skipped one"* for a comparison that structurally cannot see the branch's own additions. A reader doing the right thing, trusting a gate that says it checked, is misled
- **Why the other two invocation points do not cover it**: `pre-merge-commit` runs when both boards first coexist, which is AFTER the numbers are already committed and pushed — the repair there is a renumber commit, which is exactly the five-renumber-commit history CLAUDE.md §7 records. CI is per-push, same timing. Only the pre-commit invocation is early enough to catch the mint as it happens, and that is the one going vacuous
- **Proposed repair, not yet reviewed**: when the working tree or index has board changes, compare the **staged/working board** against `origin/main` (or the merge-base's mainline board) rather than dispatching on HEAD's shape. Keep the fail-open posture and keep saying SKIPPED when it genuinely cannot answer — the bug is not the fail-open, it is calling an unanswerable comparison a PASS
- **Blast radius**: `scripts/**` here is `platform` (the review/blast-radius machinery is individually pinned) — needs its own gate test + `mutation_proven` ledger entry per rule 24
- **Class**: `feedback_green_check_input_set_width` — the gate is correct; its input set was empty of the change under test

## OI-168 — nothing fires §4.9's "grep the test tree before you land" rule, so it is re-learned by breaking main (P2)

- **Status**: CLOSED · 2026-09-26 · superseded by OI-220's sweep arm · branch `ci-green-batch-a`
- **Blocked on**: nothing technical — needs the gate written, mutation-proven, ledger entry
- **Verified**: 2026-09-26 — `scripts/contract_sweep.dart:99` runs `git grep -l -F <basename> -- test/` for every changed non-doc file and runs the hits at pre-push, for EVERY tier. That is this rule, mechanised. The remaining hard-fail flip is owned by OI-220.
  PRIOR (kept verbatim): 2026-09-07 — the pre-push full suite on `493d230b` failed 3 assertions in **files the batch never opened**: `test/contracts/usage_quota_ledger_writer_to_reader_test.dart` (×2) and `test/scripts/usage_counter_source_lib_test.dart` (×1). None was a code defect; all three were contracts the change deliberately falsified. Cost: one full push cycle (~20 min) plus a red local `main`
- **Identified**: 2026-09-07 · during OI-162 slice 3a
- **Symptom**: you change a production file, run the tests you wrote, they pass, and the full suite then fails in test files you never opened — because source-grep contracts pin code by LOCATION and CONTENT, so relocating or repairing something breaks assertions in files the diff does not touch. A targeted run structurally cannot see them.

- **Root cause is NOT ignorance of the rule — it is that the rule has no trigger.** CLAUDE.md §4.9 already carries this class **twice** ("Extracting or moving code breaks source-grep contracts in files you never touched"; "Repairing a broken ENFORCEMENT breaks every test that was silently relying on it not enforcing"), and the second row's closing sentence, written during slice 2, reads verbatim: *"**Expect this again in slices 3-4** — six more quota readers move onto the same ledger."* That row was loaded into context at session start. The grep it prescribes was not run. **Prediction accuracy was perfect; delivery was zero.** This is §4.13 point 6's own law — *everything with a gate holds, everything on intention decays* — applied to a prose row that names its own future failure.

- **Proposed gate** (`scripts/check_test_grep_coverage.dart`, pre-commit, WARN-first per §4.11):
  for each staged non-test path P, `grep -rln "<basename or symbol>" test/` and print every hit.
  v1 is a **reporter, not a blocker** — it prints "these N test files reference what you changed;
  run them" and exits 0. That alone closes the gap, because the failure mode is not knowing, not
  refusing.
- **Why not a blocker on day one**: it cannot know which tests were actually run, so a hard fail
  would either need a test-run ledger (real work) or would block every commit. §4.11 says the gate
  ships first and flips later; this is the WARN half.
- **Sharpest form if it graduates**: pair it with the pre-push tier so a `feature`-tier push that
  skips the full suite gets the reporter's list run explicitly.

- **Recommendation**: write the WARN reporter. Two commands' worth of logic, and it would have caught this exact batch.

## OI-172 — killing a backgrounded `safe_push` does NOT kill the push; it keeps running and can land (P1)

- **Status**: CLOSED
- **Blocked on**: nothing — option 2 shipped 2026-09-10
- **Verified**: 2026-09-10 — option 2 shipped. `safe_push.sh` writes a terminal record and `scripts/push_result_lib.dart` reads it; all three outcomes confirmed end-to-end against a real remote (LANDED exit 0, FAILED exit 1, UNVERIFIED exit 2 with an empty `remote_sha`), plus a mid-flight `STARTED` record carrying a live pid. 51 assertions across three files, mutation-proven on 15 legs. Original 2026-09-07 finding: a backgrounded `safe_push.sh` was reported by the harness as `status: killed`; its process (PID 86281) was **still alive**, still holding `.git/.safe_git_op.lock` (`holder` file: `pid=86281 op=safe_push`), and it subsequently completed the full suite and **landed the push** — `[safe_push] OK -- origin/main now at 493d230b… (matches local)`
- **Identified**: 2026-09-07
- **Symptom**: the harness's kill terminates the *wrapper* it spawned, not the shell script's own process tree. A reader who trusts "killed" concludes the push did not happen. If they then start a second push, two pushes race one lock; if they conclude the remote is unchanged, they are asserting something they did not check.

- **What saved it this time**: the lock. A second `safe_push` would have found `.safe_git_op.lock` held by a LIVE pid and refused. So the failure mode is not corruption — it is a **false belief about production state**, which is the same class as `feedback_git_landing_verification.md`'s "git said OK but it didn't land", inverted: here the tool said FAILED and it did land.
- ⚠ **This already has a documented sibling**: that memory file records "a killed push landed anyway and reddened main". The new information is the MECHANISM — the pid survives the harness's kill, and the lock's `holder` file is the way to find out.

- **Options**:
  1. Document only: after any killed/interrupted git operation, read `.git/.safe_git_op.lock/holder` and `kill -0` the pid before concluding anything. (This is what worked.)
  2. Have `safe_push.sh` write a terminal result file (`.claude/.last_push_result`) with `LANDED|FAILED|UNVERIFIED` + the sha, so a caller has a machine-readable answer that survives losing the stdout.
  3. Trap `SIGTERM`/`SIGINT` in the wrapper so a kill releases the lock and records `INTERRUPTED` — ⚠ but NOT so it aborts the push mid-flight, which would be worse.

- **Recommendation**: option 2. It also fixes the adjacent hazard that made this expensive — `safe_push.sh` prints its verdict to stdout, and a caller who appends `; echo $?` gets the ECHO's exit code, not the script's (CLAUDE.md §4.9 documents that footgun; it fired again this session and made a FAILED push read as exit 0). A result file cannot be destroyed by shell composition.

- **RESOLUTION (2026-09-10)**: option 2 shipped, with **two deliberate deviations from the text above**, both recorded because the board is the thing future-me will read:
  1. **The path is `$(git rev-parse --absolute-git-dir)/.safe_push_result`, NOT `.claude/.last_push_result`.** The option as written would have been the **fourth** instance of "a tool wrote a gitignored file into a worktree and made it permanently unretirable" (`docs/diagnoses/INDEX.md:45`, diagnose `b4d7e9`, OI-128) — `retire_worktree_lib.dart` treats any unlisted gitignored path as PRECIOUS, so it would also have owed that list TWO entries (the file and its `.tmp` mirror). Inside `.git` it is invisible to `git status --ignored` and cannot trip the predicate at all. `--absolute-git-dir` rather than `--git-dir` because the latter is **relative** in the primary worktree. Per-worktree, matching `_git_lock.sh`'s own key, so the existing lock already serialises writes — `--git-common-dir` would be one shared path with no such serialisation, since the lock is keyed on `--git-dir` and two linked worktrees can push concurrently.
  2. **The reader is CODE, not prose** — `scripts/push_result_lib.dart`, pure parse + classify. Plan review round 3 caught that a prose contract's test had to invent its own reader, making it circular: it could only prove a stand-in agreed with prose by the same author. Same pure-lib/own-test split as `ci_reconcile_state_lib.dart`.
- **The record also answers the in-flight question, which a terminal-only file could not.** A `STARTED` record carrying the pid is written before the push, so the 2026-09-07 scenario — process still running, no verdict yet — reads as `cat` + one `kill -0`. An earlier draft of this fix claimed it would have replaced a whole `ps` forensics pass; that was wrong for this incident's timeline and the design was widened rather than the claim kept.
- **Found while fixing it, and fixed in the same batch**: `safe_push.sh:75`'s own guard was inert. Plain `git rev-parse <unresolvable>` prints the NAME to **stdout** and exits 128, so `LOCAL_SHA` became the literal branch string, the `-z` check never fired, and the script pushed a bogus refspec instead of printing "could not resolve local ref". Now `--verify --quiet`, which prints nothing on failure and resolves real branches and tags identically. Surfaced by the new abort test, not by reading.
- **Residues, neither fixed, both now visible**: a `kill -9` still leaves no record (the same limit `_git_lock.sh`'s trap has — which is exactly why an absent record must read UNVERIFIED, never FAILED); and a **tag** passed where a branch is expected still gets a wrong `FAILED`, because `probe_remote_sha()` hardcodes `refs/heads/$BRANCH`. The record carries `verified_ref` so a reader can SEE the probe used the wrong namespace, but the verdict is still wrong. Zero call sites pass `--tags` today. Option 3 (trapping SIGTERM) remains **rejected**, as the entry itself argued.
- Diagnose `docs/diagnoses/2026-09-10-safe-push-outcome-not-recorded-a7f3c1.md`; plan review `docs/plan-reviews/oi172-push-result-file.md` (3 rounds).

## OI-178 — pg_cron SQL jobs are structurally invisible to the alerting stack: `cron_call_log` is written only by Edge Functions (P1)

- **Status**: CLOSED (2026-09-27, `ops-alerting-b2a`) — diagnose `b4c8e2` + `f7a3d2`
- **Blocked on**: none
- **Resolution**: two new pg_cron alerts, applied live — `alert_sql_job_failures` (migration 145, jobid 46, hourly) reads `cron.job_run_details` for `status='failed'` rows; `alert_cron_job_silent` (migration 146, jobid 47, hourly) reads `cron.job` + `cron.job_run_details` for jobs stopped being launched or switched off. Together they cover both aggravations this entry named: `return_message = "1 row"` hiding retention volume is now filed separately as [[OI-251]] (not this entry's scope — that is disk-observability, not run-visibility), and the kill-switch-with-no-run-row gap is closed by 146's INACTIVE (warn) arm. Residual gaps this fix does NOT close, filed separately: self/correlated silence and the `cron.log_run` dependency ([[OI-250]]). Design converged after 4 rounds (145) / 3 rounds (146) of independent plan review plus an accepted B-pass (`docs/plan-reviews/ops-alerting-b2a.md`).
- **Verified**: 2026-09-10 — `cron_call_log` holds **1,080 rows across 16 distinct `function_name`s**, and **0 rows** for any of `jrd_retention_daily`, `client_errors_retention_daily`, `jrd_vacuum_daily`, `client_errors_vacuum_daily`. All four are live and `active=true` in `cron.job` (jobids 33–36).
- **Identified**: 2026-08-16 · Hermes L31-F2, same pass as [[OI-177]].
- **The mechanism**: pg_cron records every run in `cron.job_run_details`. This project's alerting reads `public.cron_call_log`, which is written **only** by `_shared/cron_telemetry.ts` — i.e. only by Edge Functions. A cron job whose command is pure SQL therefore emits nothing any alert reads, no matter how it fails. `alerts/_thresholds.yaml` has no retention/vacuum/disk entry at all.
- ⚠ **Two aggravations that make manual inspection useless as a fallback**:
  - `return_message` is `"1 row"` for BOTH retention jobs (verified live) — that is the wrapping SELECT's row count, not the DELETE's. **Reading it cannot distinguish 29,029 rows deleted from 0 deleted.**
  - the documented kill switch (`UPDATE cron.job SET active = false`) writes **no run row at all**, and Gate 31 reads migration files rather than live `cron.job.active` ([[OI-177]]), so a job left switched off is noticed by nothing, anywhere.
- ⚠ **The migration's own header rejects "a human remembering to run it" as a mitigation, and then adopts exactly that.** Worth reading before designing the fix: the gap is not an oversight, it is a mitigation that was argued against and then relied on.
- **Blast radius**: `supabase/migrations/**` — content-classified; a `SECURITY DEFINER` body forces **catastrophic**, so classify the written file, never the planned path (§4.9).
- **Class**: `feedback_observability_silent_drop` + `feedback_bad_news_vs_no_news` — a failing job and a job that never ran are the same observation here: nothing.

## OI-181 — nothing catches a MISSING plan-review record at merge time; both prechecks miss the plain absent case (P1)

- **Status**: CLOSED (2026-09-19, `gate-integrity`) — diagnose `b7e2d4`
- **Blocked on**: none
- **Verified**: 2026-09-19 — `scripts/safe_merge.sh:235-` classifies the three-dot `refs/heads/main...refs/heads/$BRANCH` range with the real classifier and WARNS (advisory; `NO plan-review record` / `unwinding this merge`) when the tier is ≥ account and `git show $BRANCH:docs/plan-reviews/<slug>.md` is empty — the keystone gate's own predicate (`check_plan_review_record_exists.dart:617-620`) mirrored BEFORE the merge; one `NOTE:` when the classifier yields no tier for a non-empty path list; every other failure path silent; the gate's version-bump exemption deliberately NOT mirrored (OI-222). `test/scripts/safe_merge_test.dart` 12 → 15; 3 mutations = 4 reds (block deleted 1, case arm widened 2, three-dot → two-dot 1; the last re-run by hand by the coordinator). Third instance closed (2026-08-30, `dcb94a93` 2026-09-10, `0768a0ce` 2026-09-19).
- **Verified (pre-fix, kept)**: 2026-09-10 — live, by causing it. Branch `hipri-parity` (blast-radius `account`, `supabase/functions/**`) was merged as `dcb94a93` with no `docs/plan-reviews/hipri-parity.md`. Neither merge-time guard fired. The warning arrived from `git_safety_hook.dart` at PUSH time — after the merge — and CI's keystone gate reads the record from the tree AT the merge commit, so no later commit can repair that commit's evaluation.
- **The two-sided gap, and why "there are two prechecks" reads like coverage**:
  - `scripts/safe_merge.sh` warns when a record CLAIMS `bpass: accepted` while its `bpass_review:` file lacks `verdict: accepted`. It says nothing when the record is **absent entirely** — its whole predicate starts by reading a file that is not there, and every failure path falls through silently BY DESIGN (advisory, must never wedge the only path onto main).
  - `scripts/git_safety_hook.dart` DOES detect the missing record — and runs on `git push`. By then the merge commit exists and is immutable for this purpose.
  So the case that is easiest to hit (forgot the record entirely) is the one case checked only after it is too late to fix cheaply. CLAUDE.md §7 already documents the push-time timing as a known limitation of that hook; what is NOT documented is that `safe_merge.sh` does not cover the absent case either.
- ⚠ **Cost, measured not estimated**: a red `main`. The repair for a merged-without-record branch is a `git reset --hard` unwind, which §7 records costing a full cycle on 2026-08-30 — the same shape, six weeks apart.
- **Proposed repair**: extend `safe_merge.sh`'s existing precheck with the absent-record case — it already computes `recordSlug(branch)` and already reads `git show "$BRANCH:<path>"`, so this is a `git cat-file -e` on a path it has in hand. Keep it ADVISORY for the same reason the rest of that script is: a hygiene guard must never be the thing that blocks landing work. An advisory warning BEFORE the merge is worth more than a hard block after it.
- ⚠ **Do not "fix" this by making the hook block the push** — that is the wrong end. The push-time check is already correct and already fires; the problem is that merge time has no equivalent.
- **Blast radius**: `scripts/**` is individually pinned `platform`; needs its own test (`test/scripts/safe_merge_test.dart` already exists and its fixture commits the record ON THE BRANCH deliberately — extend it with an absent-record leg) plus mutation proof.
- **Class**: `feedback_gates_unsatisfiable_at_merge` + `feedback_green_check_input_set_width` — two guards whose union looks total and whose intersection with "record absent, before the merge" is empty.

## OI-183 — `enforce_vision_analysis_daily_limit`'s channel guard is NULL-unsafe, unlike its two siblings (P3, dormant)

- **Status**: CLOSED (2026-09-13, `oi153-pro-media-caps`, migration 132) — OI-153 Unit F
- **Blocked on**: none
- **Verified**: 2026-09-13 — LIVE: `pg_get_functiondef` shows the guard as
  `IF NEW.channel IS NULL OR NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN`
  (migration 132 applied 07:28:48 IST, cloud version `20260913015848`);
  `test/sql/oi153_pro_media_caps_live_verify.sql` Part B ran green inside a
  rolled-back transaction — a NULL-channel insert leaves the `vision_analysis`
  ledger row untouched while a `scan_meal` control consumes one unit — and
  the DISCRIMINATION run (migration 129's body restored in the same rolled-back
  transaction) turned that probe RED, so the probe measures 132 and not
  nothing. SOURCE: `cap_triggers_use_usage_counters_test.dart` "every channel
  guard is NULL-safe" pins the `IS NULL OR` arm on the vision trigger and
  `IS DISTINCT FROM` on the two siblings; mutation M12 (the arm removed from
  132) reddens exactly that test, 1/11.
- **CLOSED BY**: migration 132 (`132_vision_trigger_null_channel_guard.sql`)
  — migration 129's vision body verbatim with the one guard line made
  NULL-safe. Shipped as OI-153 Unit F on the founder's 2026-09-12 apply-go,
  in the same apply commit as migration 131. Still dormant at closure (0
  NULL-channel rows), which is the point: the sibling asymmetry was the
  shape a future writer copies.
- **Was** (retained for provenance):
- **Verified (at filing)**: 2026-09-11 — read the live trigger body directly; confirmed
  `ai_coach_interactions.channel` is nullable (`information_schema.columns`)
  and holds 0 NULL rows today (live count query)
- **What**: `enforce_vision_analysis_daily_limit`
  (`supabase/migrations/129_cap_triggers_use_usage_counters.sql:149`) guards
  its early-return with `IF NEW.channel NOT IN ('scan_meal', 'cart_auditor')
  THEN RETURN NEW; END IF;`. Its two siblings in the same migration use the
  NULL-safe form instead: `IF NEW.channel IS DISTINCT FROM 'app' THEN` (chat,
  line 99) and `IF NEW.channel IS DISTINCT FROM 'food_text_analysis' THEN`
  (food_text, line 183). In Postgres, `NULL NOT IN (...)` evaluates to NULL,
  and PL/pgSQL treats a NULL `IF` condition as false (the branch is NOT
  taken) — so a row with `channel IS NULL` does not take the early return and
  falls through to `consume_quota('vision_analysis', ...)`, unlike the other
  two triggers, which correctly early-return for any non-matching value
  including NULL.
- **Consequence**: dormant today (0 NULL-channel rows exist, and nothing in
  `lib/` or any Edge Function writes a NULL channel deliberately), but any
  future write path that omits `channel` would silently consume a vision-
  analysis quota unit for a row that was never a vision request, and could
  eventually raise `vision_analysis_daily_limit_reached` for an unrelated
  insert.
- **Surfaced by**: `docs/audit/oi162-slice4-channel-enumeration.md:66-73`
  (OI-162 slice 4's own channel census), which correctly identified and
  labelled the class (`guard_without_its_mirror`) and correctly assessed it
  as dormant and out of scope — but never minted an OI for it, unlike the
  sibling out-of-scope discovery from the same review round (OI-182), which
  was filed properly. Caught by slice 4's own B-pass review (Finding 2 —
  the file is hash-named and was renamed three times as the batch grew;
  `docs/plan-reviews/oi162-slice4-windowed-counters.md`'s `bpass_review:`
  field is the stable pointer to it), which is the correct
  outcome but should not have been necessary — a dormant defect found during
  a batch's own investigation should not depend on a later reviewer
  re-reading prose to be rediscovered.
- **Proposed repair**: `IF NEW.channel IS DISTINCT FROM 'scan_meal' AND
  NEW.channel IS DISTINCT FROM 'cart_auditor' THEN RETURN NEW; END IF;` (or
  equivalent NULL-safe rewrite) via `CREATE OR REPLACE FUNCTION`, same shape
  as migration 129's own two correct siblings. Mechanically trivial; treat
  as its own reviewed unit since it touches a live cap trigger, not a
  drive-by edit.
- **Blast radius**: `supabase/migrations/**` — platform tier (live Postgres
  trigger function).
- **Related**: OI-162 (parent), OI-182 (sibling out-of-scope finding from the
  same review round, filed correctly the first time).

## OI-189 — Edit-Profile regen now stops at `plan_end`, so orphan rows past it keep OLD-GOAL workouts after a goal change (Q7 from the OI-166 review, dropped by the Unit 2 re-plan) (P2)

- **Status**: CLOSED (2026-09-13, `oi189-plan-end-bound`) — diagnose `b9e4d1`
- **Blocked on**: none — founder decided 2026-09-12: option (b), widened to a sweep on BOTH regen paths (D2: user-placed rows past `plan_end` are swept too); the restore residual stays on OI-174 (D1)
- **Verified**: 2026-09-13 — closed by `oi189-plan-end-bound`: `test/contracts/oi189_plan_end_bound_behavioral_test.dart` 27/27 (12 behavioural through the real plan()→cache()→execute() path + 9 source pins incl. B-pass B-1's sim push pin + 6 unit tests on the extracted phaseNote()/phaseDayLabel()), 22 mutation legs each reddened; both prod censuses (plan_json + scheduled_workouts, 10 users, 369 rows each) → 0 rows past `plan_end`
- **Identified**: 2026-09-06 as **Q7** in OI-166's plan review (round 3), parked on the OI-166 entry *"because an open question inside a document under rewrite has no owner"* — and then lost anyway: the Unit 2 re-plan (v4→v10), nine review rounds and the B-pass contain **zero** mentions of it (`grep -c 'Q7\|orphan rows\|refresh regression'` over the plan, diagnose `d7f3b2`, the record and rounds 5-9 → 0). Filed as its own number 2026-09-12 by the post-ship audit.
- **Mechanism (verified)**: writer B (`WorkoutScheduleReadService.generateAndScheduleFromDate`, called from `edit_profile_screen.dart:2029` via `workout_schedule_service.dart:118`) has ALWAYS deleted only `today..planEnd` (`workout_schedule_read_service.dart:362`, unchanged since before Unit 2). Before Unit 2 its WRITE loop laid out 4 weeks from the regen date regardless of `plan_end` (`for (int week = 0; week < 4; week++)` at old `:435`) — which is exactly how OI-174's orphan rows past `plan_end` were CREATED, and which also meant a goal change REWROTE any orphans that already existed. Unit 2 bounded the write loop at the stored `plan_end` (`:489 … date.isAfter(effectivePlanEnd) → skip`). Net effect: B no longer manufactures orphans (good), but orphans manufactured earlier are now neither deleted nor rewritten by an Edit-Profile regen, so after a goal change they keep the OLD goal's workouts. They stay user-visible for as long as OI-174 says orphans live (`isPhaseExpiredFrom` keeps the phase looking un-expired while any row exists on-or-after today).
- **Scope, so it is not over-read**: writer C (`RegeneratePlanPlanner.plan`, the coach's `switchGoal` / `regeneratePlanBlock`) is NOT bounded at `plan_end` — it still writes its requested `weeks` from today (no `plan_end` reference in `regenerate_plan_planner.dart`), so the coach's switch-goal refreshes the same rows it always did. C therefore also still CREATES orphans past `plan_end`; that half belongs to OI-174, not here.
- **Options** (carried verbatim from the round-3 question, plus what Unit 2 changed about them):
  1. **(a) Accept until OI-174's prune** — leaves stale forward workouts after an explicit goal change for the lifetime of the orphans. Cheapest; contradicts what the user asked for.
  2. **(b) Extend B's DELETE range past `plan_end` to cover existing forward rows** — i.e. OI-174's prune scoped to the rows this one regen is replacing. The delete loop at `:362` is the single site; the write loop stays bounded. "Rows this regen is replacing" is a smaller claim than a global prune. **Lean: (b)**, unchanged from round 3.
  3. A THIRD option Unit 2 makes available: since B now stamps `plan_end`-bounded rows and C does not, unify the two under OI-190's de-duplication and decide the horizon ONCE there. Only worth it if OI-190 is picked up first; otherwise (b) stands alone.
- **Regression test owed with the fix**: seed orphan rows dated `plan_end+1..plan_end+7` carrying goal X, run an Edit-Profile regen with goal Y, assert the rows are (b) deleted or (a) explicitly still X and documented as such — the behavioural file for Unit 2 (`oi166_unit2_regen_content_cycling_behavioral_test.dart`) seeds the same Hive boxes and is the natural home.
- **Blast radius**: `lib/core/services/**` default → `account` (`docs/blast_radius.yaml:326`); no schema, no EF.
- **Related**: OI-166 (parent, still OPEN on OI-175), OI-174 (the orphans' existence + prune design — this is the *content* of those rows, that is their *lifetime*), OI-175, OI-190.
- **CLOSED 2026-09-13 by `oi189-plan-end-bound` (diagnose `b9e4d1`)**: (1) writer C (`RegeneratePlanPlanner.plan()`) now bounds every day at the stored `plan_end` by the same literal-date comparison B uses, and reports `totalWeeks` (bounded) / `requestedWeeks` / `phaseEndsOn` / `clearsPastPhaseEnd`; (2) one shared sweep `WorkoutScheduleReadService.sweepNonCompletedRowsPastPlanEnd` runs on B and on both coach commit sites — removes non-completed `schedule_*` rows of any type and `displaced_*` shadows past `plan_end`, keeps completed history, no-op unless BOTH window keys are stored; (3) every writer that sweeps or MOVES the window pushes `plan_json` immediately (B, both coach commits incl. the "nothing to write" branch, `redoWeek4`, and A only at its two phase-advance sites via `pushPlanWindow: true` — the reinstall/repair callers must NOT push, they would replace the cloud copy); `pushWorkoutPlanForSyncDomain` gained the `pausedForSimulation` guard. Five context-blind review rounds (plan v5) + a two-reviewer B-pass (`docs/reviews/oi189-plan-end-bound-bpass.md`) that fixed 3 more findings in-batch: the sweep now also honours `completed` on `displaced_*` shadows (not just `schedule_*` rows), the dev year-sim harness's end-of-run flush now pushes `plan_json` too (it never did — every in-loop push had been no-op'd by the very `pausedForSimulation` guard this unit added), and `_phaseNote`/`_dayLabel` were extracted from both diff-preview widgets into a shared `phase_note.dart` with 6 new unit tests (the two widgets' private copies had zero coverage). Residuals: OI-174 (cloud `scheduled_workouts` never pruned; restore writers unbounded; offline-advance revert window; a NEW fourth residual from the B-pass — a future-dated completed row keeps `isPhaseExpiredFrom` false), OI-190 (coach-card copy for the bounded case: EF `previewSummary` + `_executedMessage`).

## OI-195 — Gate 42 accepts any non-empty `behavioral_test_path:` / `presence_only:` text and never checks the cited file EXISTS (P3, gate gap, zero live violations)

- **Status**: CLOSED (2026-09-19, `gate-integrity`) — diagnose `c7d2e4`
- **Blocked on**: none
- **Verified**: 2026-09-19 — every `behavioral_test_path(_*)` value (comment-stripped; sibling `_cqrs` key at registry `:826` included) and every repo-shaped path inside `presence_only` prose / `presence_only_reason` blocks (block scalar, blank lines kept, or plain) is resolved on disk via ONE helper (`_missingOnDisk`, `FileSystemEntity.typeSync` — a DIRECTORY citation is valid; `File.existsSync` would have flagged `test/sql/` as missing, caught at integration). Real registry: `138 behavioral_test_path value(s) + 4 presence_only prose citation(s) resolved on disk`, 0 missing; positive control with 2 injected fakes → exit 1 naming exactly those two. `test/scripts/sot_behavioral_test_paths_gate_test.dart` 10 tests; 5 mutations = 12 reds; ledger promoted out of the grandfathered set. The tally now counts every `presence_only: true` line: **17 (10 also cite a behavioral path; 7 presence-only)** — the "7" the gate printed before, and the "6" CLAUDE.md rule 21 carried, both counted only the presence-only-WITHOUT-behavioral subset, which is the under-report OI-161 documents as its third instance.
- **Verified (pre-fix, kept)**: 2026-09-13 — `grep -n "existsSync\|File(" scripts/check_sot_behavioral_test_paths.dart` → only `docs/sot_registry.yaml` itself is opened; a census of the registry's 134 distinct `behavioral_test_path:` values found **0 missing** today (`test -e` over each), so this is a gap, not a live breach
- **What**: rule 21 says every SoT concept MUST have a `behavioral_test_path:` (or `presence_only: true` with a justification). Gate 42 enforces the FIELD is present and non-empty; it never resolves the value. A concept can cite a test that was never written — or, the case the OI-153 B-pass caught (its finding 2), a `presence_only:` justification can cite a live-verify SQL file that did not exist yet — and the gate is green. `check_sot_registry_parity.dart` DOES resolve writer/reader `file:` citations, so the asymmetry is within one registry: the writer/reader half is checked, the test half is not.
- **Why it is cheap and worth doing**: the fix is the same `existsSync` the parity gate already runs; the `presence_only:` prose is free text and should be scanned for repo-shaped paths (`test/…`, `docs/…`) the same way `check_sot_registry_citations.dart` scans diagnose-docs for identifier-shaped citations.
- **Blast radius**: `scripts/**` pinned platform (gate script); rule 24 applies (mutation-proven test + ledger entry).
- **Related**: OI-153 (found by its B-pass), OI-180 (the same registry's other silently-skipped field), `feedback_mistake_unverified_done_claims` (a path is a claim).

## OI-198 — pr-detection cron: repeated Gateway Timeout on paged_fetch (4x in 24h, 2026-09-13/14)

- **Status**: CLOSED · 2026-09-26 · no recurrence · branch `ci-green-batch-a`
- **Blocked on**: none
- **Verified**: 2026-09-26 — LIVE: 812 success / 0 non-success pr-detection rows in retained `cron_call_log` (earliest retained row 2026-09-14; the failures were 09-13). Closed on that evidence. The CAUSE (disk-IO starvation era, or migration 141's hourly-cadence change) is a HYPOTHESIS, not a finding. Note the 12-day-deep retention is itself a symptom of the failing `db_maintenance_nightly` job (filed separately 2026-09-26).
  PRIOR (kept verbatim): 2026-09-14, live query against `public.cron_call_log`
- **Identified**: 2026-09-14 · filed via mint_oi.sh from branch `telegram-admin-bot`
- **How found**: telegram-admin-bot's `/status` smoke test (Task 13, Step 5) reported
  "Cron failures (24h): 4" — unexpected against the naive assumption of a quiet cron
  schedule. Independently verified by re-running `founder_metrics_ops()`'s live SQL
  (`select count(*) from public.cron_call_log where started_at >= now() - interval '24
  hours' and (status = 'failed' or (status = 'started' and started_at < now() - interval
  '1 hour')))`) — matched the bot's reported 4 exactly, plus the underlying rows.
- **Evidence**: all 4 failing rows are `function_name = 'pr-detection'`, `status =
  'failed'`, `http_status = 500`, error `paged_fetch[pr-detection prs]: page 0 (rows
  0-999) failed: Gateway Timeout`, at 2026-09-13 19:30/20:45/21:30/23:45 UTC
  (request_ids `8c2ec592`, `052a49ab`, `b4ca04c1`, `7e2ce940`).
- **Scope note**: pre-existing production reliability issue, unrelated to the
  telegram-admin-bot batch's own code — `pr-detection` and its `_shared/paged_fetch.ts`
  usage are untouched by this branch. Out of scope to fix here; filed so it isn't lost.
  The consistent shape (page 0, rows 0-999, every failure) suggests the first page's
  query itself is timing out rather than an intermittent network blip — worth checking
  the `prs`-source query plan / row count before assuming it's transient.

## OI-204 — Full-rescan sync architecture (_syncExerciseLogs/_syncNutritionLogs) times out at 45s under growing history

- **Status**: CLOSED · 2026-09-19 · Both halves shipped in the
  `oi204-delta-sync` batch: exercise-log fingerprint-skip (`a44dafb5`, Task 2)
  and nutrition-log fingerprint-skip (Task 3, this commit — closes-diagnose
  `d3f8a6`). Extends the proven H1b Part A pattern
  (`sync_scheduled_payload_hash_index`) to both `_syncExerciseLogs` and
  `_syncNutritionLogs`: a sync-owned fingerprint index lets an unchanged
  key/slot skip its idempotent re-upsert instead of re-walking the entire
  historical log every coalesced pass. See
  `docs/diagnoses/2026-09-19-full-rescan-sync-timeout-d3f8a6.md` for the
  full root cause + fix + verification detail on both domains.
- **Blocked on**: none
- **Verified**: 2026-09-16, `client_errors` telemetry for user `d7a67a37` (founder's
  device) + live read of `lib/core/services/sync/sync_workout.dart:185-308` and
  the `_syncNutritionLogs` sibling in `sync_nutrition.dart`
- **Identified**: 2026-09-16 · filed via mint_oi.sh from branch `apk43-obs-fixes`
- **How found**: investigating APK +43 founder observations 1 (snack save fails)
  and 2 (AI coach stuck apologising). Neither symptom's own root cause is this
  bug, but `client_errors` showed a 25+ hour sustained pathology overlapping
  both windows: since 2026-09-14 ~23:06 IST, **424** `restore_op_done` events,
  **34×** 45s `TimeoutException` on `sync_exercise_logs`, **22×** on the
  generic `sync_service_restore_op_timeout` wrapper, **11×** on
  `sync_nutrition_logs`, plus one DNS failure and one Supabase PGRST002
  "schema cache… Service Unavailable" blip. Still ongoing as of the last query
  (2026-09-16 00:11 IST).
- **Root cause**: `syncWorkoutData()`/`syncNutritionData()` are the COALESCED,
  per-write fire-and-forget sync entries (`lib/core/services/CLAUDE.md`'s
  `SyncCoalescer` — fired after every `WorkoutWriteService.logExercise` /
  `NutritionWriteService.logMeal`). `_syncExerciseLogs` (`sync_workout.dart:185`)
  and `_syncNutritionLogs` iterate **every** Hive key with the domain prefix
  (`exlog_*` / `nlog_*`) — the ENTIRE historical log, not just what changed
  since the last sync — and `await`s an individual `.upsert()` network call
  per row, sequentially, inside the loop (`sync_workout.dart:287-308` for the
  summary row alone; per-set rows add more). No "unchanged since last sync"
  skip exists anywhere in this path. As the founder's historical log count
  grows, each coalesced pass takes proportionally longer; `restore_op_done`
  telemetry shows individual passes at 14-40s even on success, and `_safeRestoreOp`'s
  45s `restoreOpTimeout` ceiling (`sync_service.dart:2204`, added 2026-08-07 for
  a DIFFERENT class — an unbounded wedge, diagnose b7e4c1) now gets tripped
  routinely rather than only on a genuine network wedge.
- **Consequence**: every workout set or meal logged fires another full
  historical re-sync in the background; on this account it now frequently
  exceeds 45s and aborts (silently, from the user's perspective — `_safeRestoreOp`
  swallows the timeout and reports only to telemetry). Plausible (unconfirmed)
  contributor to APK +43 observation 1 (snack save) via device resource
  contention during the save window, though the actual observation-1 root
  cause was traced to a separate telemetry gap (see the `apk43-obs-fixes`
  branch's diagnose-docs for observations 1 and 2, shipped in this same batch).
- **Fix shape (not decided)**: real fix is incremental/delta sync — track a
  per-row "last synced" marker (timestamp, dirty-flag, or hash) so
  `_syncExerciseLogs`/`_syncNutritionLogs` only push rows that changed since
  their last successful sync, collapsing each coalesced pass from O(total
  historical rows) to O(rows changed). This is a platform-blast-radius change
  to `sync_fanout_workout_domain`/`sync_fanout_nutrition_domain` — a
  SoT-registered, contract-tested concept (`test/contracts/sync_fanout_contract_test.dart`,
  `docs/architecture/sync.md`) in the codebase's most heavily-guarded
  subsystem (writer/reader drift is the single most recurrent bug class here).
  Needs its own §4.11 gate-before-refactor + §4.12 ×2 plan review, not a
  same-batch patch.
- **Scope note**: founder explicitly scoped this out of the apk43-obs-fixes
  batch (2026-09-16) — document + file now, design + implement as its own
  dedicated follow-up.

## OI-206 — retire_worktree.dart's regenerable-ignored-paths allowlist is missing deno.lock

- **Status**: CLOSED · 2026-09-26 · already fixed in `8bf79dde` (2026-09-18) · branch `ci-green-batch-a`
- **Blocked on**: none
- **Verified**: 2026-09-26 — `'deno.lock'` is at `scripts/retire_worktree_lib.dart:255`; `8bf79dde` is an ancestor of `main`; `test/scripts/gitignore_classification_test.dart` pins every literal `.gitignore` entry into exactly one list. The board was never updated.
  PRIOR (kept verbatim): 2026-09-16, live read of `scripts/retire_worktree_lib.dart:236-303`
  (`regenerableIgnoredPaths`) — no `deno.lock` entry anywhere in the list —
  plus `.gitignore:140` (`deno.lock` is gitignored, 0 tracked files by that
  name per `git ls-files`) and a live check of the primary worktree, where
  `deno.lock` exists untracked (16,625 bytes, last written 2026-07-27),
  produced as a side effect of running Deno tooling and never committed.
- **How found**: while closing out plan-review round 2 on the apk43-obs-fixes
  batch, which added `deno check --node-modules-dir=none` runs against
  `tool-loop.ts` and `ai-proxy/index.ts` per CLAUDE.md's Deno mandate — each
  run leaves a fresh `deno.lock` in the worktree root.
- **Root cause**: the allowlist is exact-match-only by design (its own header
  comment records three prior review rounds each finding a P0 from looser
  matching), so it only protects paths someone has explicitly enumerated.
  `deno.lock` was never added — most likely because Deno itself was not
  installed on this machine until 2026-09-12 (CLAUDE.md's git-hooks section,
  Deno 2.9.6 via winget), so before that date no worktree could produce the
  file at all and the gap was latent rather than live.
- **Consequence**: CLAUDE.md now directs running `deno check
  --node-modules-dir=none supabase/functions/<fn>/index.ts` (and `deno test`)
  on every touched Edge Function before the commit. Both commands write
  `deno.lock` into the worktree root as a side effect. Any worktree that
  follows that mandate and then merges cleanly will report `KEEP` from
  `retire_worktree.dart` forever afterward — leg 3 (no non-regenerable
  ignored files) fails on a file that is, in fact, fully regenerable
  (`deno check`/`deno test` recreate it byte-for-byte from
  `supabase/functions/**`'s import graph). Same bug-class this exact file has
  already fixed twice before, for `.claude/.batch_close_state` (diagnose
  `b4d7e9`, OI-128's shape) and the `.claude/.ci_reconcile_pending.jsonl`
  pair — a tool that writes a new gitignored file into the worktree owes this
  list an entry, and the 2026-09-12 Deno adoption shipped without one.
- **Fix shape (not decided)**: add `'deno.lock'` as one more exact-match entry
  to `regenerableIgnoredPaths` (`scripts/retire_worktree_lib.dart:236`), with
  a comment citing this OI, plus a case in
  `test/scripts/retire_worktree_lib_test.dart` asserting
  `isRegenerableIgnored('deno.lock')`. Filed only, not implemented, per
  founder instruction (documentation-only batch).
- **Identified**: 2026-09-16 · filed via mint_oi.sh from branch `deno-lock-retire-fix`

## OI-209 — check_sot_registry_parity.dart's line_range parser is blind to bare (non-dash) entries -- 15 stale citations invisible, 14 predating cron-ai-removal in unrelated subsystems

- **Status**: CLOSED · 2026-09-26 · DUPLICATE of OI-180 (same line_range regex); its violation census moved onto OI-180 · branch `ci-green-batch-a`
- **Blocked on**: none
- **Verified**: 2026-09-26 — read side by side with OI-180; the survivor carries this entry's content (see its 2026-09-26 UPDATE).
  PRIOR (kept verbatim): 2026-09-16, B-pass on the cron-ai-removal batch
  (`docs/reviews/247d945d1ba0-review.md` Finding 4) plus independent
  re-verification. `scripts/check_sot_registry_parity.dart`'s block-form
  parser (`blockRegex`) requires a dash-separated `line_range: N-M` —
  `grep -cE "^\s*line_range:\s*[0-9]+\s*$" docs/sot_registry.yaml` finds
  **30** bare-number entries the gate has never checked at all. Widening
  the regex to accept a bare `line_range: N` as a 1-line range (the same
  convention the file's own `ist_sites` inline-map parser already applies
  for `line: N`) surfaces **15** stale-line-range errors, spanning
  `lib/core/services/phase_progress_reconciler.dart`,
  `lib/core/services/sync_service.dart` (x2),
  `supabase/functions/streak-guardian/index.ts`,
  `lib/features/auth/screens/sign_in_screen.dart` (x3),
  `lib/core/services/supabase_service.dart` (x4),
  `lib/features/profile/services/notification_inbox_service.dart` (x2),
  `lib/core/services/day_rollover_service.dart` — confirmed via
  `git diff main...cron-ai-removal -- docs/sot_registry.yaml` that NONE of
  these 15 registry entries were touched by this batch's diff, i.e. all 15
  predate this branch. The one entry this batch's own review actually
  named (`streak-guardian/index.ts`, `line_range: 214`, method
  `streakDays`) was corrected directly in the same batch
  (`docs/sot_registry.yaml`, now `264`, matching
  `grep -n "const streakDays" supabase/functions/streak-guardian/index.ts`
  → line 264) — trivial, verified, no gate-behavior change required. The
  other 14 are unrelated to cron-ai-removal (auth, sync, notification
  inbox, day rollover) and were deliberately NOT fixed in that batch —
  see Scope note.
- **Scope note**: `check_sot_registry_parity.dart` runs UNCONDITIONALLY in
  the pre-commit gate loop (`scripts/pre-commit.sh:324`, `for GATE in
  scripts/check_*.dart`, not in the case-skip allowlist), on every commit
  in the whole repo, with no arguments (hard-fail mode, not
  `--warn-only`). Widening the parser without first fixing all 15 exposed
  violations would fail pre-commit for every future commit until they
  are all cleared — a repo-wide blocking-gate regression wildly out of
  proportion to a "remove Gemini calls from cron functions" batch, and
  touching 5 subsystems that batch never opened a single file in. Reverted
  the parser widening from the worktree rather than commit it half-done
  (`git checkout -- scripts/check_sot_registry_parity.dart`); filed here
  instead per precedent OI-207 (same shape: a review found stale
  `sot_registry.yaml` citations predating the batch that found them, filed
  separately rather than folded in).
- **Suggested fix**: (1) widen the parser per the diff already drafted and
  reverted (accept a bare `line_range: N` as `N-N`); (2) fix the 14
  newly-exposed pre-existing stale citations, most likely across several
  small, unrelated commits grouped by subsystem rather than one giant
  diff; (3) land the parser widening only once (2) is clean, so the gate
  never goes red for a pre-existing reason.
- **Identified**: 2026-09-16 · filed via mint_oi.sh from branch `cron-ai-removal`,
  during the self-triggered `/code-review` B-pass required before merge
  (CLAUDE.md §4.3).

## OI-223 — check_migrations_live cannot pass by construction: 125/139 local migrations never registered live (75 founder raw-SQL applies) -- retire in favour of Gate 14 or redesign the matcher

- **Status**: CLOSED (2026-09-19, `gate-integrity`) — retired (no diagnose-doc: a deletion, not a `fix`/`bug`/`regression` commit)
- **Blocked on**: none
- **Verified**: 2026-09-19 — founder chose RETIRE. Six sites done: `scripts/check_migrations_live.dart` deleted; `docs/audit/gate_test_ledger.yaml` entry removed; `check_gate_scripts_wired.dart`'s `_allowList` entry removed (Gate 33 PASS on the real tree, 96 `check_*`, down from 97); the two case-skip lines removed from `pre-commit.sh` and `test.yml`; `test/contracts/phase_c_oi_closures_test.dart`'s OI-34 group INVERTED (asserts the file no longer exists, not deleted, so a reintroduction with no ledger/allowlist entry is caught — 58/58 green); `docs/runbooks/restore-drill.md` step 5 repointed at Gate 14 (`check_migrations_applied.dart`) + a manual cross-check note. Original verification kept below.
- **Verified (pre-retirement, kept)**: 2026-09-19 — exact run from the primary with the PAT: exit 1, `local migrations: 139, live migrations: 130`, `FAIL — 125 local migration(s) NOT applied live`; 14/139 prefix matches
- **Identified**: 2026-09-19 · filed via mint_oi.sh from branch `worktree-agent-a57ce47ba764ba91c` (gate-integrity batch, OI-155 unit)

`scripts/check_migrations_live.dart` compares every local `supabase/migrations/*.sql`
numeric prefix (139 distinct prefixes over 142 files; `all_*` skipped) against the live
versions the Management API lists at `/v1/projects/<id>/database/migrations` (`:58`). Its own header
(`:27-32`) admits the local→live matcher is a prefix HEURISTIC. It cannot pass by
construction: `backups/applied_migrations.json` records **75 `applier: founder`** raw-SQL
applies (25 `claude`), and a raw-SQL apply never registers a version in Supabase's
migrations table, so those files are "unapplied" to this gate forever. Only 14 of 139
prefixes match a live version.

Where it runs today: NOWHERE automated. Case-skipped in `scripts/pre-commit.sh:333` and
`.github/workflows/test.yml:243`; its allowlist prose in `check_gate_scripts_wired.dart`
claimed "runs in /build-apk skill Gate 14b" — `grep -ic 14b .claude/commands/build-apk.md`
→ 0, and build-apk's "first failure stops the build" would have stopped every full-gate
build had it been wired. Its ONLY documented runner is by hand
(`docs/runbooks/restore-drill.md:63`), where it fails. The OI-155 fix (gate-integrity
batch) replaces that prose with a machine-checked `GateRunner.manual('OI-223', …)` entry:
Gate 33 now re-verifies on every commit that THIS OI is still OPEN/IN_PROGRESS — closing
it without giving the gate a real runner (or deleting the gate) turns Gate 33 red.

**Recommendation: RETIRE.** Gate 14 (`scripts/check_migrations_applied.dart`) +
`backups/applied_migrations.json` already own "applied live", and the live matcher
contradicts the project's own raw-SQL apply history. **Retire checklist (six sites, all
in one commit):** delete `scripts/check_migrations_live.dart`; its
`docs/audit/gate_test_ledger.yaml` entry (`:391`); its `_allowList` entry in
`scripts/check_gate_scripts_wired.dart` (the stale-key mirror there FAILS if the file
goes and the entry stays); its case-skip lines `scripts/pre-commit.sh:333` +
`.github/workflows/test.yml:243`; the exists-assertion at
`test/contracts/phase_c_oi_closures_test.dart:81-85` (OI-34's "exists" pin — repoint it
to the retirement, do not just delete the group); and the by-hand invocation at
`docs/runbooks/restore-drill.md:63`. **Redesign alternative:** match by file CONTENT
hash against `backups/applied_migrations.json` (the ledger Gate 14 already validates)
instead of by live version prefix — then the gate would be a ledger-vs-disk check, which
Gate 14 already is, which is the argument for retiring.

## OI-224 — alert_cron_function_dead threshold unreachable, cron_call_log pruned at 7 days

- **Status**: CLOSED · 2026-09-26 · DUPLICATE of OI-179 (same predicate, same prune interaction) · branch `ci-green-batch-a`
- **Blocked on**: none
- **Verified**: 2026-09-26 — read side by side with OI-179; the survivor carries this entry's content (see its 2026-09-26 UPDATE).
  PRIOR (kept verbatim): 2026-09-20 — live on dedsavbjuwgarrhphgnl: `cron_call_log` `min(started_at)` 7.04 days back, alert has fired 0 times ever, `cleanup_cron_call_log()` body unchanged (still 7-day / global-newest-success)
- **Identified**: 2026-08-16 (Hermes pass, `debugging-stuck-issue-89b2e9`) — re-verified + filed 2026-09-20 via mint_oi.sh from branch `oi224-alert-cron-threshold`

`alert_cron_function_dead` (migration 110, `supabase/migrations/110_cron_silence_per_function_and_cleanup_null_guard.sql:112`)
fires on `days_silent >= 8`, where `days_silent` is computed from `MAX(started_at)`
over `public.cron_call_log` filtered to `status = 'success'` (`:107`). But
`cleanup_cron_call_log()` (`:30-47`, run daily as `cron_call_log_cleanup_daily`,
jobid 23, 03:30 UTC) prunes that same table to `started_at < now() - interval
'7 days'` (`:37`), sparing only the single newest success row and the single
newest row of any status — GLOBALLY, not per function.

The ceiling this creates: `days_silent` for ANY function can never exceed roughly
7 days plus the gap between two consecutive cleanup runs (~24h), because the row
that would prove a longer silence is deleted before the alert's next tick. The
`>= 8` threshold sits just past that ceiling — unreachable by construction, not
by bad luck. Verified LIVE, twice, six weeks apart (2026-08-16 and 2026-09-20):
`min(started_at)` in `cron_call_log` reached back 7.21 days on the first check
and 7.04 days on the second; `select count(*) from public.alerts where source =
'alert_cron_function_dead'` returns 0 both times. The alert has never fired once
since it was created (migration 110).

Consequence: the ONE alert designed to catch a single dead cron function (as
opposed to `alert_cron_silence`, which only catches a total fleet outage) cannot
ever fire. A function that silently stops succeeding — the exact scenario
`alert_cron_function_dead`'s own doc comment describes, "boot failure, a module
that fails to load writes NO cron_call_log row at all, and pg_cron still
reports success" — gets no alert, ever, regardless of how many days pass.

Two independent fixes, either sufficient alone:
- Lower the threshold below the achievable ceiling (`>= 6` would clear it with
  margin; `>= 8` needs either a longer cleanup retention or a per-function
  spare in `cleanup_cron_call_log` rather than one global newest-row).
- Make `cleanup_cron_call_log` spare the newest SUCCESS row PER FUNCTION_NAME,
  not one global newest-success row — this also closes a second latent gap:
  a function that has never once succeeded recently while others have keeps
  ZERO rows after cleanup regardless of the threshold, because the single
  global newest-success spare belongs to whichever function ran most recently.

Found by a Hermes pass (L1-F3) on `claude/debugging-stuck-issue-89b2e9`, a
branch whose own migration work (log-table retention) was independently
reconstructed and shipped to main as `121_log_table_retention.sql`
(OI-132/c8e5b3) before this branch was ever merged — this finding is the one
piece of that pass's output that did NOT get carried forward with the
reconstruction, and does not appear to have been independently found since.
The branch itself is being retired as superseded; this is the one live defect
worth keeping.

**Recommendation**: small, self-contained migration. Pick the threshold fix
(simplest, lowest blast-radius) unless the per-function-silent-forever gap
above is also worth closing in the same pass — if so, do the per-function
spare instead, since it fixes both.

## OI-234 — alert_edge_function_health never fires — 401s write no cron_call_log row, so its err_rate guard structurally never matches an auth outage

- **Status**: CLOSED · 2026-09-26 · DUPLICATE of OI-197 item 2 (EF auth-outage alert never fires) · branch `ci-green-batch-a`
- **Blocked on**: none
- **Verified**: 2026-09-26 — read side by side with OI-197; the survivor carries this entry's content (see its 2026-09-26 UPDATE).
  PRIOR (kept verbatim): never
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/next-aab-decision-d1227b`

## OI-235 — proactive_plateau_alert (~116s avg) and i-see-you-daily (~93s avg) run unusually long once daily — likely per-user loop instead of set-based query, needs Edge Function code review

- **Status**: CLOSED · 2026-09-26 · misattributed · branch `ci-green-batch-a`
- **Blocked on**: none
- **Verified**: 2026-09-26 — LIVE `cron.job_run_details`: both jobs run 0.1–1.3 s every day EXCEPT the two 2026-09-21 'job startup timeout' failures (1488 s / 1853 s, the e8b4a1 DB-starvation incident); 0 runs > 5 s otherwise. The ~116 s / ~93 s averages were one outlier each. Also: this metric times the pg_net DISPATCH, not the Edge Function runtime, so it never measured a per-user loop either way.
  PRIOR (kept verbatim): 2026-09-22, re-confirmed live by a B-pass review of the disk-io-audit-cleanup work (diagnose e8b4a1) (`select avg/min/max(extract(epoch from (end_time-start_time))) from cron.job_run_details join cron.job ... where jobname in (...)`) — both averages reproduced exactly (93.1s, 116.0s over 16 runs each). Distribution is genuinely bimodal, not uniformly slow: min=0.1s, max=1488.1s (~24.8min) for i-see-you-daily and max=1853.8s (~30.9min) for proactive_plateau_alert — most runs are fast and one outlier per job pulls the average up. Sharpens the likely cause: a conditional expensive path (e.g. a per-user loop that only fires under some condition) rather than a uniformly slow query.
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/next-aab-decision-d1227b`

## OI-242 — realtime_pro_gate_behavioral_test.dart flakes on full-suite CI run with a Box-not-found HiveError, passes clean in isolation

- **Status**: CLOSED · 2026-09-26 · fixed, diagnose `b3f8e5` · branch `ci-green-batch-a`
- **Blocked on**: nothing — closed.
- **Verified**: 2026-09-26 — ROOT CAUSE is NOT a cross-file state leak (the
  hypothesis below is refuted). `isPro()` starts `_downgradeLocally()` unawaited
  (`subscription_service.dart:480-483`); the test waited with `pumpEventQueue()`,
  a turn-bounded proxy racing an I/O-bounded chain. On a loaded runner the proxy
  won, the assertion read pre-downgrade state, and tearDown closed Hive under the
  still-running chain (the trailing Box-not-found). Reproduced DETERMINISTICALLY
  in-process: 2000 unawaited puts queued before `isPro()` ⇒ old wait RED 5/5,
  new `ProDowngradeWaiter` (`test/helpers/pro_downgrade_waiter.dart`, waits on
  `onDowngrade` :1213) green 3/3. Same fix applied to the expiry-banner and
  paused-guard files. Test: `test/contracts/pro_downgrade_waiter_behavioral_test.dart`.
  PRIOR (kept verbatim): 2026-09-22 — reproduced the CI failure signature exactly via
  GitHub Actions logs; ruled out as unrelated to the PR that surfaced it by
  running the file alone locally (9/9 green) and by confirming the same
  failure independently hit an unrelated merge's CI run too.
- **Identified**: 2026-09-22 · filed via mint_oi.sh from branch `claude/oi-batching-strategy-e5e359`

Found while checking CI on PR #37 (Batch B, a docs-only investigation commit
touching only `docs/audit/open_issues.md`/`OPEN_INDEX.md` — no Dart/Hive code
whatsoever). The "Unit Tests" job failed on
`test/contracts/realtime_pro_gate_behavioral_test.dart`'s "e4a7c9 — the
teardown half (an attached channel never re-enters the gate) THE SECOND BUG:
a downgrade fires onDowngrade" case:

```
Expected: true
  Actual: <false>
an expiry downgrade must release PRO-owned resources

[MigratedKey.delete] userBox expiresAt threw: HiveError: Box not found. Did you forget to call Hive.openBox()?
...
HiveError: Box not found. Did you forget to call Hive.openBox()?
  package:hive/src/hive_impl.dart 186:7           HiveImpl._getBoxInternal
  package:hive/src/hive_impl.dart 197:33          HiveImpl.box
  .../guarded_box.dart 341:20                     wrapUserScopedBox
  .../hive_service.dart 235:7                     HiveService.userBoxGuarded
  .../hive_service.dart 226:22                    HiveService.userBox
  .../user_repository.dart 159:23                 UserRepository.getProgress
  .../streak_progress_service.dart 246:46         StreakProgressService.resetToFreeCapOnLapse
  .../subscription_service.dart 1225:38           SubscriptionService._downgradeLocally
```

**This is genuinely NOT related to PR #37's diff** — a docs-only merge
cannot affect this code path. Checking `main`'s own recent CI history
(`gh run list --branch main`) confirms it's flapping independently of any
single PR: the merge-to-main run for PR #34 (`024d7a82`) also FAILED, the
merge-to-main run for PR #36 (`e7733cb8`, in between) PASSED, and this
PR #37 run failed again on the exact same test. **Confirmed NOT
reproducible in isolation**: `flutter test
test/contracts/realtime_pro_gate_behavioral_test.dart --exclude-tags golden`
run alone, locally, against current `main` — all 9 tests pass, INCLUDING the
exact case that failed on CI. Re-running the failed CI job (`gh run rerun
--failed`) is the practical workaround used so far and it clears the check,
consistent with order/state-leak-dependent flakiness rather than a
deterministic regression.

**Hypothesis, not yet confirmed:** some earlier test file in the full
`test/` suite run leaves global/static state (a Hive box left open, or a
singleton — `SubscriptionService`/`HiveService`/`UserRepository` are all
involved in the failure's call chain) that this test's `setUp`/`tearDown`
assumes is clean. This is the SAME general class CLAUDE.md's own
common-pitfalls table already documents for GoogleFonts/`path_provider`
box-lifecycle races and for concurrent-session Hive temp-dir contention —
but this instance reproduces WITHIN a single suite run on an isolated CI
runner (no concurrent session possible there), so it is a distinct,
narrower case: ordering/state-leak between test FILES in one process, not
cross-process contention.

**Recommendation**: (1) Bisect by running larger and larger prefixes of the
full `test/` suite (or binary-search which OTHER file, run immediately
before this one in suite order, causes the box to be left in the state that
trips `userBoxGuarded`) to find the actual leaking test. (2) Once found, fix
via proper `tearDown`/`tearDownAll` box closure in the leaking file, or make
this test's own `setUp` more defensive (re-open/re-verify the box it needs
rather than assuming a clean slate). (3) Short-term mitigation already in
use: `gh run rerun --failed` clears it reliably when it fires — acceptable
for now given it does not block any specific PR's own correctness, but
should not become a standing habit given CLAUDE.md rule 20's ban on treating
CI flakiness as permanently acceptable.


## OI-135 — 60 of 125 migration-ledger hashes do not match their files, and nothing recomputes them (P2)

- **Status**: CLOSED (2026-09-29, `migration-ledger-integrity`): Gate 39 now VERIFIES every ledger hash. A hash is valid iff it equals the sha256 of the file under its LF **or** CRLF form, so the 56 entries hashed on a Windows CRLF working copy stay byte-for-byte as recorded (no re-stamp — they are as-applied records). The 5 genuine drifts (057, 069, 070, 108, 123) are grandfathered BY NAME with a PINNED sha (`grandfatheredLedgerHashDrift`), so a further edit still fails and a pin that starts matching fails as stale. Founder call on the 5 was taken as the recommended default (pin, do not re-stamp) and flagged for veto at merge. Limits stated in `supabase/migrations/CLAUDE.md`: catches a forgotten re-stamp, not a deliberate edit + re-stamp. Tests: `migration_ledger_hash_lib_test.dart`, `check_applied_migrations_ledger_e2e_test.dart`; 9 mutations run (`gate_test_ledger.yaml`).
- **Blocked on**: nothing technical. The fix shape is settled (below); what it needs is a decision on whether to backfill the 60 or grandfather them by name.
- **Verified**: 2026-09-26 — RECOMPUTED by the coordinator: 147 hashable ledger entries, **61** mismatches, of which **56** equal sha256 of the file with LF→CRLF (hashed on a Windows CRLF working copy — content-identical) and only **5** are genuine content drift: 057, 069, 070, 108, 123.
  PRIOR (kept verbatim): 2026-08-20 — measured, not estimated. Recomputed sha256 for every entry in `backups/applied_migrations.json` against its `supabase/migrations/*.sql` file: **125 entries → 64 match, 60 mismatch, 1 non-hash sentinel (120b, deliberate)**.

`backups/applied_migrations.json` records a `hash` per applied migration. Its documented purpose
is drift auditing — "recompute hashes on drift", per `applied_migrations_parity_test.dart:36`.
**Nothing recomputes them.** `check_applied_migrations_ledger.dart` requires the `hash` KEY to be
present (`_requiredKeys`) and never looks at its value; no other gate reads it. So the field has
been decorative since it was introduced, and has silently drifted on 48% of entries.

**Found by the round-2 review of `claude/oi-pending-hold-weeks-1od97o`**, which correctly flagged
migration 120's hash as stale — I had updated it in one commit and then edited the file again in
the next, invalidating it. That instance is fixed. The finding only became interesting when the
count was checked: 120 was not special, it was the 61st.

**Why it drifts by construction:** the hash tracks the FILE, and migration files legitimately get
edited after they are applied — corrected comments, added rollback blocks, clarified headers. Every
such edit invalidates a hand-maintained hash, and nothing notices. A hash maintained by memory
across a repo this size will always converge on wrong.

**Fix shape:**
1. A gate that recomputes sha256 for every ledger entry naming a real file and fails on mismatch.
   It must skip entries with no file by design (120b's `unverifiable:no-artifact` sentinel) and
   entries hand-applied outside the migration system (119).
2. The 60 existing mismatches get **enumerated by name** as `grandfathered:` in that script — a
   terminal exemption, exactly the precedent `check_gate_test_ledger.dart` set for its 84
   pre-2026-08-10 gates, and explicitly NOT a deferral. Membership by name, not by date.
3. Mutation-prove it per rule 24 and add its `gate_test_ledger.yaml` entry.

**Deliberately NOT bundled into the batch that found it.** Adding a hard-failing gate with 60
pre-existing violations to a merge-blocking step would be a ship-stop for a hygiene problem — the
same error class as the 2026-07-25/26 required-status-checks incident. The one instance that batch
caused is fixed in it; the class is filed here.

---

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** The decision shrinks from 'grandfather ~60' to: hash LF-normalised content, re-stamp the 56 (provably content-identical), and a FOUNDER call on the 5 genuine drifts (grandfather by name or re-stamp after review). A raw-byte gate would disagree between the Windows laptop and Linux CI — normalise first. Pairs with OI-137 (hash shape) and OI-163 (header gate).

## OI-137 — the migration-ledger gate checks that `hash:` EXISTS, never that it is a hash; a literal `%s` passed it (P2)

- **Status**: CLOSED (2026-09-29, `migration-ledger-integrity`): step 1 (shape) and step 2 (value) both shipped with OI-135. `hash` must be `sha256:<64 hex>` or an `unverifiable:<reason>` sentinel; a sentinel is legal only when the migration has no `.sql` of its own (`120b`, `123b`), and a sentinel beside an existing file fails so it cannot become the new escape hatch. A literal `sha256:%s` now fails (pinned by both the lib test and the gate e2e).
- **Blocked on**: nothing technical. Same grandfather-or-backfill decision as OI-135 — 60 of 126 entries already carry hashes that match no artifact, so a strict flip is a ship-stop until they are recomputed or enumerated by name.
- **Verified**: 2026-08-20 — reproduced, not inferred. The entry for migration `121` was written with `"hash": "sha256:%s"` — an unsubstituted Python format placeholder. `dart run scripts/check_applied_migrations_ledger.dart` reported PASS. Caught by the B-pass on the same commit, and corrected there to `sha256:ac8c01a26e32…`.

`scripts/check_applied_migrations_ledger.dart:26` is the whole story:

```dart
const _requiredKeys = ['migration', 'applied_at', 'hash', 'applier'];
```

The gate asserts every entry HAS the four keys. It never looks at what is in them. So
`sha256:%s`, `sha256:`, `TODO`, or the empty-ish `sha256:x` all satisfy it identically, and the
field that exists to attest replay fidelity attests nothing.

**Why this one is worth a number rather than a quiet fix.** It is the third instance in two days
of the same shape — a gate green because it checks the presence of a thing rather than the thing
(OI-132: Gate 31's input could not see a fileless migration; OI-136: Gate 40 "validates" YAML it
never parses). And it landed *inside the commit whose own note explains why a meaningless hash on
this entry must not happen*, which is as close to a controlled demonstration as this class gets:
the author knew the failure mode, wrote it down, and still shipped an instance of it past the gate
in the same file.

**Fix shape:** two cheap checks, one strict and one advisory.
1. Shape: `hash:` must match `^sha256:[0-9a-f]{64}$` OR a documented sentinel string (the `120b`
   entry deliberately carries one, because a fileless entry has nothing to hash — see its note).
   That alone would have caught `%s`, and costs nothing.
2. Value: where a `.sql` file exists for the migration, recompute its sha256 and compare. That is
   the OI-135 half and is the one that needs the grandfather decision first, because it reddens 60
   pre-existing entries on day one.

Step 1 is separable and blocks nothing — it is the part worth doing on its own.

**Related:** OI-135 (60 of 126 ledger hashes match nothing, and nothing recomputes them — this is
its mint-time sibling: 135 is about drift, 137 is about a value that was never a hash at all),
OI-136, OI-132.

## OI-263 — Migration-number allocator: reserve migration numbers server-side (mint_oi.sh pattern) and refuse a number already applied live

- **Status**: CLOSED (2026-09-29, `migration-ledger-integrity`) for what shipped: `scripts/mint_migration.sh` (server-side `mig/N` compare-and-swap, copy of `mint_oi.sh`'s core with a parity test), `scripts/check_migration_number_reserved.dart` (every added `NNN_*.sql` needs a reservation; same-number collision with a different file on origin/main fails), `vercel.json` skips `mig/*`, blast pins, docs. **The apply-time "refuse a number already applied live" half of the chosen fix shape was CUT** by founder decision after three plan-review rounds each found new defects in it, and is **OI-272** (with the round-3 evidence). Honest scope of what shipped: a reservation proves the author looked at the allocator, NOT that the branch owns N; two branches can still share one reservation and only Gate 14 catches it at merge; live names are 69/145 unprefixed so `--live` cannot see those. The planning also fixed `check_migration_ledger_paired.dart`, which read `041_chunks/041_00_alter.sql` as migration 041 and never matched a letter-suffix file (it had no test).
- **Blocked on**: none
- **Verified**: 2026-09-28 — live list_migrations held 148 while the tree did not
- **Identified**: 2026-09-28 · filed via mint_oi.sh from branch `day-swapper-sync-load`; founder asked for it

Symptom, measured 2026-09-28: the day-swapper-sync-load migration was renumbered 145 → 147 → 148
as other batches landed on `main`, then had to become **149 at apply time**, because live
`list_migrations` already held `20260927224028 / 148_coach_extraction_locked_fields`. That branch
(`single-owner-a2b`) had applied 148 to prod before merging to `main`, so no file in this
worktree's tree and nothing on `origin/main` showed 148 as taken. Nothing allocates a migration
number today: the next number is read off `ls supabase/migrations/` by whoever writes the file.
OI-258 is the ledger-side symptom of the same gap (145/146 collided across diverged `main`s).

- **Class**: a green check is only as wide as its input set
  (`feedback_green_check_input_set_width` #60). "Is N free?" has THREE sources — the local tree,
  `origin/main`, and the live database — and both collisions so far came from the one nobody
  checked.
- **Industry norm, for the record**: timestamp-prefixed filenames (Rails, Supabase's own
  `supabase migration new`) make a git collision near-impossible with no coordination; sequential
  numbering (Django, Alembic, Flyway) relies on a merge-time "two heads" detector. Neither covers a
  migration applied LIVE from an unmerged branch, which is the case that bit here.
- **Fix shape (founder chose this 2026-09-28)**: `scripts/mint_migration.sh`, reusing
  `mint_oi.sh`'s compare-and-swap ref reservation (`refs/heads/mig/N`), so two sessions cannot
  claim one number; the mint also refuses N when live `list_migrations` (or
  `backups/applied_migrations.json` on `origin/main`) already carries it. Plus a pre-apply check:
  before any `apply_migration`, compare the file's number against live `list_migrations` and refuse
  a taken number. Keeps the 3-digit scheme (tooling such as `latestMigrationDefining` parses it);
  switching to timestamps was offered and not chosen. Needs its own tests, mutation-proven per
  rule 24 if it becomes a `check_*` gate.
- **Source**: day-swapper-sync-load Task 34 apply.

## OI-138 — `retire_worktree` removes the worktree but leaves the BRANCH, silently burning the slug

- **Status**: CLOSED (2026-09-29, `branch-lifecycle-cleanup`) — `retire_worktree.dart` now deletes the worktree's own local branch after a successful removal; diagnose `4c3fc4`
- **Verified**: 2026-08-25 — read `scripts/retire_worktree.dart:275-282` directly: it calls
  `git worktree remove <path>`, reports RETIRED on exit 0, and never references the branch.
- **Identified**: 2026-08-16, as a "second, smaller gap" inside OI-128. **Split out 2026-08-25**
  when OI-128 closed, rather than being closed with its parent — the parent's fix (the
  regenerable list) does not touch this at all, so closing both on one commit would have recorded
  a fix that was never written.
- **Blocked on**: none. Small, but see the trap below — it is not a one-liner.
- **What's missing**: after a successful `git worktree remove`, delete the branch with
  `git branch -d`. Use `-d`, NEVER `-D`: the safe form refuses an unmerged branch, and that
  refusal is the entire guarantee. The four-leg predicate has already proven the branch merged by
  the time we get here, so `-d` is expected to succeed; if it does not, that is new information
  and the branch must be KEPT and reported, not force-deleted.
- ⚠ **THE TRAP: the worktree slug is NOT the branch name.** Verified live 2026-08-25 —
  `git worktree list` shows `.claude/worktrees/post38-auth-fixes` sitting on branch
  `rescue/post38-auth-inflight`, and three other `rescue/*` branches are in the same shape. A
  delete keyed on the directory slug would either fail to find a ref or, worse, match an
  unrelated branch that happens to share the name. The loop already has the real branch in scope
  (`classifyWorktree` is called with `merged.contains(branch)`), so the fix must use THAT value,
  not `name`.
- **Symptom when it bites**: `sh scripts/new-worktree.sh <same-slug>` fails with "branch already
  exists". The slug is burned and the operator has to `git branch -d <slug>` by hand — which is
  exactly the state OI-128's own workaround note describes.
- **Regression test shape**: extend `test/scripts/retire_worktree_e2e_test.dart` (it already
  builds real linked worktrees). Two cases, and the second is the one that matters: (1) retiring a
  merged worktree deletes its branch and the slug is immediately reusable; (2) a worktree whose
  BRANCH NAME DIFFERS FROM ITS SLUG deletes the branch, not the slug-named ref — construct it the
  way `rescue/*` did, with `git worktree add -b rescue/<x> .claude/worktrees/<x>`.
- **Blast radius estimate**: `platform` — `scripts/retire_worktree*.dart` is NOT individually pinned — CORRECTED 2026-09-29: this entry
  claimed it was pinned above the `scripts/** → feature` catch-all in `docs/blast_radius.yaml`, but `grep retire_worktree docs/blast_radius.yaml` returns nothing (OI-139 records the same fact), and the classifier returns `feature` for the tool + its test alone; this batch is `platform` only because its diff also touches CLAUDE.md. Adds a DESTRUCTIVE
  operation (branch deletion) to a tool that currently only removes directories, so it needs the
  mutation-proven treatment its siblings already carry.
- **Related**: OI-128 (parent, CLOSED 2026-08-25 — the regenerable-list half), §4.13 point 6.

**Closed 2026-09-29 (`branch-lifecycle-cleanup`, `closes-oi: OI-138`).** Shipped: after `git worktree remove`
succeeds the tool runs `git merge-base --is-ancestor` then `git branch -d --` on `w.branch` (never the
folder slug, never `-D`); `main`/`develop` and `rescue/*` `oi/*` `dependabot/*` are never deleted; a
refusal prints `KEPT-BRANCH` with git's first line and no force-delete advice. Also fixed in passing:
the merged set used `%(refname:short)`, which prints `heads/T` when a tag `T` exists, silently keeping
that worktree forever. Tests: `test/scripts/retire_worktree_e2e_test.dart` (10 new, each on its own repo,
incl. the folder-slug-differs case this entry called the trap, and the remote-deleted-upstream matrix) +
`retire_worktree_lib_test.dart`. The ancestry re-check closes a race and is pinned by a hook-driven e2e test that makes the race deterministic (mutation: 1 red). Remote
branches are out of scope here: GitHub's `delete_branch_on_merge` covers PR merges; any other route is OI-273.

## OI-182 — the payment grace window closes before the last verify-payment retry fires (P2)

- **Status**: CLOSED · 2026-09-29 · fixed on branch `oi-182-202-subscription-state` — `kPaymentGraceWindow` is now DERIVED from the retry schedule and the per-call bounds (`lib/core/constants/payment_timing.dart`, ≈21m45s, was a bare 10-minute literal) and every activation-flow network call is bounded; the retry success path now clears the grace and writes PRO state in a tested order. Diagnose `f2a6d1` (`docs/diagnoses/2026-09-29-payment-grace-window-shorter-than-last-retry-f2a6d1.md`). Client-only: reaches users with the next founder-initiated APK build. Stated residue: the retries are in-memory timers (best-effort under suspend / app kill).
- **Blocked on**: none
- **Verified**: 2026-09-11 — read both constants directly, no live query needed
- **What**: `SubscriptionService._paymentGraceWindow` is **10 minutes**
  (`lib/core/services/subscription_service.dart:162`). `RazorpayService`'s
  verification-retry schedule is **`[60s, 5m, 15m]`**
  (`lib/core/services/razorpay_service.dart:734-738`). The grace window closes
  **5 minutes before the final retry even fires**.
- **Consequence**: if a `verifyFromServer()` check lands in that 10–15 minute gap
  while the webhook is also delayed, `isPaymentInFlight` already reads `false` and
  the code runs `_downgradeLocally()` (`subscription_service.dart:1087-1089`) for a
  user who genuinely paid. Requires the webhook AND the first two retries to all be
  late — rare, but the two constants disagreeing is a plain authoring gap, not a
  designed tradeoff; nothing suggests 10 minutes was chosen deliberately against a
  15-minute retry tail.
- **Surfaced by**: OI-162 slice 4's review round 2, while checking whether
  switching `verify-payment`'s rate limit to fail-closed removes user-visible
  safety margin. It does, marginally — one of the four attempts that could still
  land inside the grace window is now refused if the 20/10min cap is exhausted.
  That interaction is real but secondary; the mismatch itself pre-exists slice 4
  and is unrelated to its scope (an EF-side rate-limit fix has no coupling to a
  client-side Dart timing constant), so it is filed separately rather than folded
  in. Per CLAUDE.md §4.2 this is a genuinely different bug, not a re-wrapped
  deferral of slice 4's own scope.
- **Proposed repair**: widen `_paymentGraceWindow` to comfortably exceed 15
  minutes (e.g. 20) so it never closes before the retry schedule completes.
  Mechanically trivial — one constant — but touches the subscription-downgrade
  path, so treat it as its own reviewed unit rather than a drive-by edit.
- **Blast radius**: `lib/core/services/subscription_service.dart` — account tier
  (payment/subscription path).
- **Related**: OI-162 (slice 4 plan, `docs/audit/oi162-slice4-plan.md`).

## OI-202 — users.subscription_status never reconciles to free after expiry

- **Status**: CLOSED · 2026-09-30 · diagnose `c7e3b9` · migration 152 (cloud version 20260930065332)
- **Blocked on**: none
- **Closure**: chose fix shape (b) — derive and drop. Every reader now derives from `public.subscriptions` (`fetchLatestActiveEndByUser` + `fetchProUserIds`/`isProUser`): founder digest, `telegram-admin-bot` `/expiring` + `/user`, `admin-dashboard-data`, `expiry-reminder`, `bot.py` `is_pro`, and `private.founder_metrics()` (pro_expired = any subscriptions row and no live active one; free = never subscribed). The webhook and verify-payment stopped writing the mirror (deployed webhook v27 / verify-payment v23, merged to `main` as 93e61579 with CI green BEFORE the apply, per Hermes L35 F1). Migration 152 dropped both columns, `trg_subscription_update_user`, `update_user_subscription_status()` and `extend_subscription(uuid,integer)`. Live after apply: 0 columns / 0 trigger / both functions absent / no function body names either column; `founder_metrics()` 38 / pro_active 5 / pro_expired 2 / free 31 (dry-run predicted exactly this). The 8 pre-drop mirror rows are in `backups/subscription_mirror_columns_snapshot_2026-09-29.json`. Pinned by `test/contracts/migration_152_drop_subscription_mirror_test.dart` (13, 10 mutations reddened), `test/contracts/subscription_columns_dropped_test.dart` and `supabase/functions/_shared/subscription_test.ts`.
- **Verified**: 2026-09-15, founder spot-check of `public.users` via the Supabase
  table editor — `test6@gmail.com` (`subscription_status='pro'`,
  `subscription_expires_at` 2026-07-03) and `test3@gmail.com` (same,
  `subscription_expires_at` 2026-06-22), both over 2 months past their own
  listed expiry, still read `'pro'`. Cross-checked against the already-shipped
  fix at the consumption layer: `supabase/functions/_shared/subscription.ts`'s
  docstring (added 2026-07-26) documents the identical symptom in production
  ("Live it claimed 6 PRO users, all 6 lapsed. `morning-alert` read it and sent
  Gemini-generated PRO-tier copy to churned users") and names the root cause —
  three writers (the `update_user_subscription_status` trigger,
  `razorpay-webhook/index.ts:604`, `verify-payment/index.ts:629`) set the column
  to `'pro'`; NONE unset it, no cron/trigger reconciles it. Confirmed every real
  consumer has since been migrated off this column: the client
  (`subscription_service.dart` → `verify-subscription/index.ts:66-73` queries
  `subscriptions` directly with `status='active'` + a live `end_date > now()`
  compare; zero references to `subscription_status` anywhere under `lib/`),
  `morning-alert`/`weekly-recap-ready` (via `_shared/subscription.ts`'s
  `fetchProUserIds`/`isProUser`, same predicate), and `telegram-admin-bot`'s
  `/user` command (`index.ts:404-436` — selects `subscription_expires_at` from
  `users` but never displays it; the printed "plan: X (ends Y)" line is
  re-derived from a fresh `subscriptions` query, per its own inline comment at
  `:413-417`).
- **Scope note**: not a live bug — nothing that gates an actual decision reads
  this column today (verified above). Purely misleading for anyone — founder,
  future session, ad-hoc dashboard — manually inspecting `public.users`
  directly, exactly as happened here. The column drifts further from reality
  forever under the current architecture, since no writer ever resets it on
  expiry.
- **Fix shape (not decided)**: either (a) add a reconciliation job/trigger that
  flips `subscription_status` back to `'free'` and nulls
  `subscription_expires_at` once the backing `subscriptions.end_date` lapses
  (keeps the column trustworthy for ad-hoc queries), or (b) drop both columns
  outright since no code path reads them for a decision — would need a
  dependency sweep first (the 3 writers above, plus `telegram-admin-bot`'s
  unused `subscription_expires_at` select at `:406`) and its own migration.
- **Identified**: 2026-09-15 · filed via mint_oi.sh from branch `oi-stale-subscription-status`

## OI-245 — Restored PRO photo-coach turns are replayed to Gemini as text (sync_coach hardcodes mode quick)

- **Status**: CLOSED · 2026-09-29 · fixed by `6e3975ae` (branch `oi-245-246-restore-fixes`, merged via PR #50) — a restored photo/video coach row now gets its real media mode back, so the context builder's `mode == 'media'` filter sees it. Diagnose `a2c9e5` (`docs/diagnoses/2026-09-28-coach-restored-media-mode-a2c9e5.md`). Client-only fix: it reaches users with the next APK build.
- **Blocked on**: none
- **Verified**: 2026-09-29 — fix commit read on `main`; diagnose-doc `a2c9e5` exists. (Filed 2026-09-26 — code read: `lib/core/services/sync/sync_coach.dart:261` restores every row with `mode: 'quick'`; the history filter at `coach_interaction_repository.dart:362` excludes only `mode == 'media'`; PRO photo rows are channel `app`. So a restored photo turn loses its media marker and is replayed into Gemini context as a plain-text turn.
- **Identified**: 2026-09-26 · filed via mint_oi.sh from branch `ci-green-batch-a` (backlog triage)

Writer: `sync_coach.dart:261` (restore). Reader: `coach_interaction_repository.dart:362` (context builder). Classic writer/reader field drift — fix is to restore the row's real mode, with a writer→reader test.

## OI-246 — Deleted exercise logs reappear after a cloud restore (deleteLog removes the Hive key only)

- **Status**: CLOSED · 2026-09-29 · fixed by `6e3975ae` (branch `oi-245-246-restore-fixes`, merged via PR #50) — a deleted exercise log is now tombstoned in the cloud instead of only removed from Hive (`PendingExlogDeletes` queue + drain, restore skips queued keys). Server side is live: migrations 150 + 151 applied, `weekly-recalc` v25 and `pr-detection` v17 deployed with the `deleted_at` filter (`88fef854`). Diagnose `e1c8b4` (`docs/diagnoses/2026-09-28-exlog-tombstone-resurrection-e1c8b4.md`). The client half reaches users with the next APK build. Read-side residue is filed separately as OI-269 (4 other `workout_log_exercises` readers that still skip the `deleted_at` filter).
- **Blocked on**: none
- **Verified**: 2026-09-29 — fix commit and deploy record read on `main`. (Filed 2026-09-26 — code read: `deleteLog` removes the Hive `exlog_` key only (no tombstone, no cloud delete), and restore re-puts every cloud row whose key is absent locally (`lib/core/services/sync/sync_workout.dart:916`). A user-deleted log therefore comes back on the next restore.
- **Identified**: 2026-09-26 · filed via mint_oi.sh from branch `ci-green-batch-a` (backlog triage)

Needs a tombstone or cloud-side delete; restore-completeness class (docs/architecture/sync.md).
