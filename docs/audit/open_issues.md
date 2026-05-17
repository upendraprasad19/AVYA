# Open Issues — class-level audit follow-ups

Evergreen task board. Every gap surfaced by any audit / observation /
diagnose pass that hasn't yet been closed by a shipped commit lives here.

## How this file is used

- **Append-only at the bottom.** Never re-number a closed issue; the OI
  number is its permanent identifier (referenced from diagnose-docs +
  commit messages).
- **Status transitions:**
  - `OPEN` — identified, not started
  - `IN_PROGRESS` — being worked this session
  - `CLOSED` — shipped, with hex diagnose-doc ID + commit SHA
- **One section per issue.** Status line first so a quick scroll surfaces
  open work without reading prose.
- **Cross-reference both directions:** every diagnose-doc that closes an
  OI cites it in frontmatter `oi_closed: OI-NN`; every commit that
  closes one cites `closes-oi: OI-NN` in the message body.

## Why this file exists

5+ APK test iterations have surfaced the same recurring bug class
(writer/reader drift). Memory files capture retrospectives; diagnose-docs
capture forensics; `sot_registry.yaml` captures concept structure. None
of them answer the question "what's still open from prior audits?" This
file does. It's the queryable backlog the user explicitly asked for on
2026-05-17.

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

## Closed (chronological)

- **OI-07** (2026-05-17) — AI snapshot field-name contract manifest
  shipped. `docs/snapshot_contract.yaml` + self-consistency contract
  test. closed_diagnose_id: `93aeac`. commit_sha: pending. Gate
  enforcement (OI-03) remains OPEN as planned.
- **OI-01** (2026-05-17) — Reader-manifest gate now enforces EXHAUSTIVE
  reader completeness (Phase 2 added to
  `scripts/check_reader_manifest_complete.dart`; registry populated
  with 14 new `readers:` entries + 67 `reader_allow_files:` entries
  across 16 concepts; contract test
  `test/contracts/reader_manifest_exhaustiveness_test.dart` pins the
  gate as a subprocess). closed_diagnose_id: `0a1e17`. commit_sha:
  pending.
- **OI-02** + **OI-08** (2026-05-17) — Symmetric ReadServices shipped
  for workout / nutrition / health domains (`workout_read_service.dart`,
  `nutrition_read_service.dart`, `health_read_service.dart`). PR
  per-set MAX semantic (OI-08) centralised in
  `WorkoutReadService.bestPerSetReps` / `.bestPerSetDuration` /
  `.bestPerSetWeight`; `WorkoutRepository.loadAllExercisePRs` collapsed
  ~90 lines of inline switch math to 4 delegating calls;
  `train_screen.dart` file-private helpers DELETED;
  `NutritionRepository.dailyMacros` delegates. 3 new SoT registry
  concepts + 6 existing concept `reader_allow_files:` updates so the
  Phase 2 reader-manifest gate passes. 3 contract tests (30 cases).
  closed_diagnose_id: `8d85c2`. commit_sha: pending.

---

# Second wave (2026-05-17) — surfaces NOT covered by the writer/reader drift sweep

The OI-01 through OI-10 batch closed the writer/reader drift class
exhaustively. Founder's follow-up question on 2026-05-17 ("does our
audit cover everything — UI / backend / APIs?") surfaced 8 additional
audit surfaces never systematically swept. Added below as OI-11..OI-18
with risk ranking. Visual regression harness explicitly NOT added per
founder direction (low priority — no historical pure-visual bug has
shipped).

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

## OI-25 — Coach-media consent UI flow (client follow-up)

- **Status**: OPEN
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

---

# Hermes audit 2026-05-17 (evening) — OI-26 through OI-43

External Hermes cross-check on 2026-05-17 evening surfaced 13 REAL findings (3 P0 + 6 P1 + 4 P2) + methodology lens-registry work. Verification report: `~/.claude/plans/i-did-an-audit-glittery-meerkat.md`. Each finding becomes one OI below for tracking.

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

- **Status**: OPEN (needs verification — subagent didn't read full file)
- **Identified**: 2026-05-17 evening · Hermes audit F7 · UNVERIFIED — subagent only read lines 1-150
- **Risk class**: DPDP §17 incomplete erasure · nested user-tagged paths may survive after account deletion
- **Estimated effort**: ~30 min verification + ~1 hour fix if needed
- **What's claimed**: delete-account Storage purge deletes only top-level paths `userId/file`, but nested `userId/subfolder/file` paths may survive. CLAUDE.md §16 documents the buckets purged (`progress-photos/<uid>/`, `chat-media/<uid>/`, `coach-media/<uid>/`) but does NOT specify depth handling.
- **Fix (if confirmed)**: Use Storage list with no depth limit (`storage.from(bucket).list('${uid}/', { limit: 1000 })` paginated until exhausted) → recursive remove. Or use the Storage RPC for prefix-delete if available.
- **Regression test (planned)**: `test/contracts/delete_account_storage_recursive_test.dart` — seeds nested path, runs delete-account, asserts all paths under `${uid}/` removed.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-32-delete-account-purge-depth-<hex>.md` once verified.
- **First step**: read `supabase/functions/delete-account/index.ts` lines 150+ to confirm depth handling.

## OI-33 — `check_apk_size_within_bounds.dart` exits 0 when APK missing (silent CI pass) (P2)

- **Status**: OPEN
- **Identified**: 2026-05-17 evening · Hermes audit F8 · verified by direct read at lines 44-48
- **Risk class**: gate-bypass · in clean CI or wrong order pipeline, APK size validation silently passes
- **Estimated effort**: ~30 min
- **What's broken**: lines 44-48: `if (!apkFile.existsSync()) { stdout.writeln('[Gate 13] SKIP — APK not found ... Exit 0.'); exit(0); }`. The gate is invoked from `/build-apk` (after build) so missing APK SHOULD never happen — but if someone re-orders pipeline steps or runs the gate alone, it silently green-checks.
- **Fix**: Add `--release` flag that turns missing-APK into FAIL (exit 1). Default behavior unchanged (exit 0 SKIP). `/build-apk` skill invokes with `--release`. Document in script comment.
- **Regression test (planned)**: `test/scripts/check_apk_size_strict_mode_test.dart` — runs the script in a temp dir without an APK, asserts exit 1 with `--release` flag + exit 0 without.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-33-apk-size-gate-strict-<hex>.md`.
- **Why missed today**: lens L24 (gate-strictness) did not exist. We never re-audited gate scripts asking "does this PASS when it should FAIL?"

## OI-34 — `check_migrations_applied.dart` compares snapshot file, not live Supabase (P2)

- **Status**: OPEN (self-documented TODO in script)
- **Identified**: 2026-05-17 evening · Hermes audit F9 · verified by direct read at lines 11-13
- **Risk class**: gate-bypass · repo can believe migrations are applied while live Supabase differs
- **Estimated effort**: ~2 hours (write `check_migrations_live.dart` + wire into `/build-apk` Gate 14)
- **What's broken**: Script lines 11-13 carry TODO: `Wire this up to live Supabase MCP query (project dedsavbjuwgarrhphgnl) once MCP tooling is available at build time. Until then this is a snapshot-based comparison.` Current implementation reads `backups/applied_migrations.json` (manually maintained) — if the snapshot is stale or someone forgets to update it, the gate green-checks while migrations are actually unapplied.
- **Fix**: Write new `scripts/check_migrations_live.dart` that queries Supabase via service-role REST: `SELECT * FROM supabase_migrations.schema_migrations ORDER BY version`. Compare to `ls supabase/migrations/*.sql`. Fail if any local file lacks a row OR if live has unknown rows (drift in either direction). Requires service-role token at build time (already available via `supabase/.supabase/supabase access token.txt`). Keep `check_migrations_applied.dart` as offline fallback for environments without network.
- **Regression test (planned)**: integration test that seeds a mismatch and asserts FAIL.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-34-migrations-live-verify-<hex>.md`.
- **Why missed today**: lens L24 (gate-strictness) didn't exist. The TODO has been visible in the script since Test #13.

## OI-35 — CLAUDE.md §2 says "21 tables", §7 header says "46 tables" — intra-document drift (P2)

- **Status**: OPEN
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

- **Status**: OPEN
- **Identified**: 2026-05-17 evening · Hermes audit C3 · verified via subagent read of `home_provider.dart:258 + 291-305`
- **Risk class**: side-effect-on-read (CQRS violation, lens L26)
- **Estimated effort**: ~1.5 hours (extract to splash / day-rollover path)
- **What's broken**: `StreakFreezeNotifier.build()` calls `_refillIfNewWeek()` line 258. The method at line 291 has an idempotency guard (`if (lastRefill compareTo thisMondayStr >= 0) return;`) — so the write doesn't fire on every build, only once per IST week. BUT every Riverpod rebuild that triggers `build()` (auth change, invalidation, app refresh, hot reload) re-enters this path. Anti-pattern severity is bounded by the idempotency guard, but the pattern is still wrong — `build()` should be read-only.
- **Fix**: Extract `_refillIfNewWeek()` to: (a) splash `_runDeferredInit` post-restore hook, OR (b) `day_rollover_service.runRolloverNow()` (it already handles IST week-start awareness). Keep `streakFreezeProvider.build()` read-only. Confirm `StreakProgressService.instance.commitRefill` callsites elsewhere don't get orphaned.
- **Regression test (planned)**: `test/contracts/streak_freeze_provider_no_write_in_build_test.dart` — source-grep that the provider's build body contains no `commitRefill` reference.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-38-streak-freeze-build-write-<hex>.md`.
- **Why missed today**: lens L26 (CQRS / pure-function discipline) was in the 2026-05-11 memory but never integrated into the audit runner.

## OI-39 — `train_provider` scans Hive directly instead of via WorkoutRepository / WorkoutReadService (P2)

- **Status**: OPEN
- **Identified**: 2026-05-17 evening · Hermes audit C5 · verified via subagent read of `train_provider.dart:43-124` + `:137`
- **Risk class**: writer/reader discipline · OI-02 closed read services this morning but train_provider wasn't migrated
- **Estimated effort**: ~1.5 hours
- **What's broken**: `_getLastPerformance` at line 53 iterates `for (final raw in hive.workoutBox.values)`. `exerciseHistoryProvider` at line 137 does the same. WorkoutReadService was shipped this morning under OI-02 with `bestPerSetReps` / `bestPerSetWeight` / `exerciseLogsForIstDate` methods — but train_provider was not migrated. A third callsite will re-implement inline and diverge.
- **Fix**: Migrate both providers to delegate to `WorkoutReadService.instance.*` or `WorkoutRepository.getExerciseLogsForDate`. Delete the file-private direct-Hive scans.
- **Regression test (planned)**: extend the existing `test/contracts/workout_read_service_per_set_semantic_test.dart` to assert no `hive.workoutBox.values` iteration appears in `train_provider.dart`.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-39-train-provider-direct-hive-<hex>.md`.
- **Why missed today**: OI-02 closure scoped to WorkoutRepository.loadAllExercisePRs + train_screen._bestPerSetReps + NutritionRepository.dailyMacros. train_provider wasn't included.

## OI-40 — Two paywall UI surfaces (`paywall_sheet.dart` + `paywall_sheet_phase_variant.dart`) (P2)

- **Status**: OPEN (PARTIAL — needs decision)
- **Identified**: 2026-05-17 evening · Hermes audit C6 · verified via subagent read of both files
- **Risk class**: drift in pricing / copy / analytics / restore behavior
- **Estimated effort**: ~2 hours (decide consolidation vs documented variants)
- **What's broken**: `paywall_sheet.dart:1-50` docstring claims "This is the ONLY paywall UI in the app." But `paywall_sheet_phase_variant.dart:1-60` is a phase-specific variant. The latter doesn't appear to import `SubscriptionService`, suggesting separate integration paths. Risk: pricing/copy/analytics drift over time.
- **Fix options**: (a) Consolidate into one component with a `variant: PaywallVariant.standard | .phaseUnlock` parameter — single integration path. (b) Document both as official variants that share `SubscriptionService.startPurchase()` via a common base class. Add contract test that asserts both call the same purchase entry-point.
- **Regression test (planned)**: `test/contracts/paywall_single_purchase_path_test.dart` — both files invoke `SubscriptionService.startPurchase` and no other purchase entry point.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-40-paywall-variants-<hex>.md` once decision made.
- **Needs brainstorm**: decide consolidate vs documented-variants before fixing.

## OI-41 — Profile/Report streak source drifts from Home/Rank live calc (P2)

- **Status**: OPEN
- **Identified**: 2026-05-17 evening · Hermes audit C7 · verified via subagent grep `home_provider.dart:245` vs `profile_provider.dart:300`
- **Risk class**: writer/reader drift · users see different streak numbers in different places
- **Estimated effort**: ~1 hour (pin SoT + migrate Profile reader)
- **What's broken**: Home + Rank widgets call `WorkoutRepository.calculateCurrentStreak()` — walks back through `schedule_<date>` keys live. Profile + Reports read cached `current_streak_weeks` field on the user profile. The cached field can lag the live calc by hours or days depending on sync timing.
- **Fix**: Pin one canonical reader in `docs/sot_registry.yaml` (likely `WorkoutRepository.calculateCurrentStreak()` for current streak; `current_streak_weeks` cached value is fine for HISTORICAL reporting only). Migrate `profile_provider.dart:300` to call the live calc. If perf is a concern (live calc walks Hive on every Profile open), add a `currentStreakProvider` that caches with explicit invalidation on day rollover + workout completion.
- **Regression test (planned)**: `test/contracts/streak_single_source_test.dart` — assert Profile and Home both read from the same source.
- **Diagnose-doc (planned)**: `docs/diagnoses/2026-05-17-oi-41-streak-source-drift-<hex>.md`.
- **Why missed today**: SoT registry didn't pin "Profile and Home must read the same value" for streak.

## OI-42 — Bake 5 new permanent gates for lens registry (L22 / L25 / L34 / L39 / L40)

- **Status**: OPEN
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

- **Status**: OPEN
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
