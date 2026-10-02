# Resilient Client — Phase 1 Implementation Plan (revision 3, post plan-review round 2 — Unit C split out)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execution mode (CLAUDE.md §4.12.7, decided at batch START, never switched): INLINE in this worktree.** Reason: Tasks 2 and 4 both edit `sync_service.dart` / `sync_state_provider.dart`; parallel units would collide on shared files.

**Goal:** Make the client survive a Supabase API outage (521/504/PGRST002) without hanging the splash or losing a failed push forever — while putting *less* load on Supabase, not more. **Pull-on-resume (a backgrounded device refreshing itself) is NOT in this plan:** two review rounds kept finding design-level defects in it (CLAUDE.md §4.12.1), so it is split out as Phase 1b — see the Round-2 log and `docs/superpowers/plans/2026-10-01-resilient-client-phase1b-resume-pull-DRAFT.md`.

**Architecture:** Four small units, no migration, no Edge Function change. (A) a hard ceiling on the post-auth routing read so the existing "local evidence → home" shortcut can run — and a late answer is never thrown away for a user with no local data. (B) a reachability-gated, capped retry controller that re-runs the existing fingerprint-skipped push sweep (`weeklyFullSync`) after an outage-shaped PUSH failure, plus: the daily-sweep stamp is only written by a clean sweep. (D) a "sync paused" banner state fed by (B). (E) stop writing one `client_errors` row per *successful* restore/sync op (57% of that table; closes OI-151), which (B)'s retry sweeps would otherwise multiply. (The units keep their letters; **Unit C = pull-on-resume is Phase 1b**.)

**Tech Stack:** Flutter/Dart, Riverpod 3, Hive, supabase_flutter. Tests: `flutter_test` + `fake_async` + the real-`SyncService`-against-a-local-stub harness (`test/helpers/sync_stub_server.dart`, `test/sync/sync_domain_skip_harness.dart`).

**Spec:** In-flight design notes `memory/project_resilient_client_outage_inflight.md` (brainstorm 2026-10-01) + the Design Decisions below. Phase 1b (pull-on-resume) and Phase 2 (delta sync, `updated_at`/`deleted_at` tombstones on every synced table, conditional push, water-as-entries, cold-start cursor) are OUT of this plan and filed on the OI board — Task 8.

## Global Constraints

- Hive-first for ALL reads/writes; never block the UI on Supabase (§4.4 r1).
- §4.6 feature-flag protocol: every new behaviour ships with a `configBox['disable_*']` kill-switch, read DEFENSIVELY (`try { ... } catch (_) { return false; }`), default = fix ACTIVE. Kill-switches added: `disable_resolve_destination_timeout`, `disable_sync_retry_sweep`, `disable_restore_op_done_filter`. (These default to ACTIVE — a permanent operator kill-switch, the repo precedent of `disable_bg_restore` / `disable_plan_integrity_reconciler` / `disable_sync_banner_grace` — not §4.6's "new path hidden until rolled"; the diagnose doc says so.)
- IST throughout for date keys: `istDateStr` from `lib/core/utils/ist_date.dart`.
- Never call `Hive.box` / `Supabase` directly from a widget (§4.4 r4). The banner reads a Riverpod provider only.
- **`flutter analyze lib/` on the WHOLE tree after every edit** — `sync_service.dart` has `part` files; a per-file analyze is a different, narrower input set (CLAUDE.md §4.9 `part`-file row). ~40 s.
- Members of `SyncService` that are `static` must be qualified (`SyncService.applyRestoreCeiling`) when used from the part-file `extension` (unqualified static lookup fails inside an extension).
- **ONE commit for the whole batch**, via `sh scripts/safe_commit.sh "$(cat <scratchpad>/msg.txt)"` (one positional argument, no flags, no `/tmp`). Reason: `commit-msg` requires `docs/diagnoses/*-e5b2a9.md` to exist and validate at every `fix(`-subject commit carrying `closes-diagnose: e5b2a9`, so a per-task commit would need the diagnose doc first; the units share files and have no independent user value (§4.3 consolidation rule). **The founder has NOT said "commit"; do not commit or push until they do.**
- No APK build. No live apply / deploy: no migration, no Edge Function.
- **Run tests with `TZ=Asia/Kolkata`** (CLAUDE.md §0; pre-push runs `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden`). The Bash tool's default 120 s timeout is too short for `pre-commit.sh` (97–640 s) and the full suite (~7 min) — run those with `run_in_background`, never append `&`, never pipe, and verify a commit/push with `git log -1` + `git status` + `git ls-remote` (§4.9).
- **Every new test is MUTATED once before it is believed** (§4.4 r21): break the fix so the file STILL COMPILES, confirm the test goes red *for the right reason* (read the failure text — a compile error is not a proof), restore, confirm green, `git diff <file>` shows nothing afterwards (a `git checkout --` restore eats earlier uncommitted fixes in the same file — restore by reverse-editing, not checkout). Record "what was mutated, how many tests reddened" in the diagnose doc.
- A mutation that reddens ZERO tests means "covered elsewhere" or "absorbed by a catch that returns the asserted value" — find out which (r21, 2026-09-06 clause).
- Telemetry: NO new per-success `logEvent` anywhere in this plan (that is the load Unit E removes).
- Branch: `claude/resilient-client-phase1` (cut from `origin/main` @ `e53998a0`). Plan-review record = `docs/plan-reviews/claude-resilient-client-phase1.md` (`recordSlug()`: `/` → `-`).
- **Gate 43 (blocking at pre-commit): `lib/**/screens/*_screen.dart` ≤ 800 lines** (`scripts/check_god_screen_max_lines.dart:29`). `restoring_screen.dart` is **exactly 800 today** — every edit to it must be net ≤ 0 lines; check `wc -l` + the gate after Task 1. Never raise the cap.
- **No `/*` character sequence in ANY inserted comment, not even a `///` doc line** (e.g. a path like `/rest/v1/*`). Several contract tests strip comments with the NAIVE regex `/\*[\s\S]*?\*/` (`auth_session_bootstrapper_test.dart:165-171,391-398`); a stray `/*` pairs with the next real `*/` and erases hundreds of lines from the stripped view. Check after every task: `git diff -U0 -- '*.dart' | grep -n '^+.*/\*'` prints nothing.
- **Each new `import` lands in the task that creates AND uses the symbol** (an unused import is a warning → fails the push, and an import of a not-yet-created file is a compile error).
- **SoT registry `line_range`s drift when lines are inserted above them** (`docs/sot_registry.yaml`, gate `scripts/check_sot_registry_parity.dart`). Rules read from the script (round-2 R2d): a BLOCK entry's cited symbol must appear inside `[start,end]` with NO tolerance (the ±5-line window applies only to inline `{ file, line, fn }` maps); `endLine > lineCount` is a hard error unless `9999`, so **for a NEW small file use `line_range: 1-9999`**, never a "wide ±40"; `compileDailySnapshot` (`:10600`, 1052-1110) moves ~+25 lines with Task 2 and keeps a 5-line margin — re-run the gate, do not assume; entries that drift: on `sync_service.dart` `:10899` (`restoreOpTimeout`, a 1-line range `2507-2507` — ANY inserted import/field above it breaks it), `:10910` (`applyRestoreCeiling`), `:10920` (`restoreFailureReason`), `:10935` (`_safeRestoreOp`), `:12377` (`_onUserChanged`); on `auth_session_bootstrapper.dart` `:4874` (`resolveDestination`, 150-208 — Task 1 shifts it). The parity gate is therefore **expected RED after Tasks 1, 2 and 5** and is repointed ONCE in Task 6 after all edits are in; it must be green at Task 7. **Do NOT write `hive_key_prefix:` / `key_prefix:` in the new concept blocks** (any non-empty value, even `n/a`, makes Gate 9 demand `test/contracts/<concept>_writer_to_reader_test.dart`); copy `restore_completeness` (`sot_registry.yaml:2677`), which has none.
- **Merge strategy:** `gh pr merge <N> --merge` ONLY — never `--squash` / `--rebase`, never edit the merge subject. `scripts/check_plan_review_record_exists.dart` (CI, push to `main` only) needs a two-parent `Merge pull request #N from <owner>/<branch>` commit; a single-parent landing at ≥account is judged a DIRECT landing and reddens `main`.
- Diagnose id: **`e5b2a9`** (verified unused: `grep -c e5b2a9 docs/diagnoses/INDEX.md` → 0).
- Test fixtures use the REAL error strings seen in `client_errors` during the outage (queried 2026-10-01): `ClientException with SocketException: Failed host lookup: '…supabase.co'`, `PostgrestException(message: error code: 521\n, code: 521, details: <none>, hint: null)`, `PostgrestException(message: Could not query the database for the schema cache. Retrying., code: PGRST002, …)`, `TimeoutException after 0:00:45.000000: Future not completed`, `ClientException: Load failed, uri=…`.

## Round-1 review log (4 context-blind reviewers; every finding verified against code before acting)

| # | Finding | Disposition |
|---|---|---|
| R1 | Resume pull includes `_restoreNutritionLogs` → a meal deleted locally is re-added from the cloud (delete is local-only, `NutritionWriteService.deleteLog`; cloud keeps it). `_restoreScheduledWorkouts` is an unbounded timestamp-overlay that can wipe an unpushed swap. | **Both dropped from the pull** (D10/D11). Meals logged on another device appear at the next cold start; schedule edits likewise. Nutrition-delete resurrection is an EXISTING cold-start bug → own OI (Task 8). |
| R2 | `SyncError.isTransient` is true for `UnknownError`/`AuthError` and its `'401'`/`'403'` substring match hits UUIDs → infinite retry loop. | Outage-shaped, status-aware predicate (`isOutageShapedFailure`), push-opType allowlist, `String` errors ignored, attempt cap (D12). |
| R3 | `weeklyFullSync` stamps `last_full_sync` even when every op failed, so a relaunch skips the sweep. | Stamp only when no retryable failure occurred (D13). Single-flight join added. |
| R4 | `restoreCompletedTick` is also the streak-decay safety gate (`workout_repository.dart:244-247`) and Train's `invalidateOnRetry` resets `selectedWeekProvider`. | Bump only when `tick > 0` AND a Hive window signature changed (D7). Side effects documented. |
| R5 | The 8 s ceiling would discard a late answer for a no-evidence user. | `resolveBounded`: with evidence → unknown→home; without → keep awaiting the ORIGINAL read (D14). |
| R6 | New public `SyncService` methods break `sync_service_public_api_snapshot_test`. | Added to `expectedPublicApi` in the task that adds each method (2 and 3). |
| R7 | Task 4 wiring test was vacuous; `composeSyncState` branches were dead in production; new `ref.onDispose` before the existing one would break the first-occurrence pin. | One-line live branch in `_stateFor`; slice-scoped wiring test; listener removal added INSIDE the existing `onDispose` after its last line. |
| R8 | The writers swallow their own errors (`_reportSyncFailure`, no rethrow) so a pull `catch` never fired. | Pull measures failure with `_syncFailureSeq` (incremented at the funnel top) before/after each op. |
| R9 | `fix(` commits need the diagnose doc present; the literal `\n` commit example was wrong. | One commit; message via `"$(cat msg.txt)"`. |
| R10 | D2 text wrong (profile/progress/preferences/coach pushes are not skip-indexed); stale citations; `OI-151` not referenced; `bug-classes.md:474` telltale. | Corrected below / Tasks 5-6. (An earlier draft also claimed `readRestoringScreenSource` does not exist — WRONG: `test/helpers/read_screen_source.dart:114` defines it and `restoring_screen.dart` has `part` files; Task 1's wiring test uses it.) |
| R11 | **`restoring_screen.dart` is exactly 800 lines; Gate 43 caps screens at 800** and blocks at pre-commit. The draft Task 1 added a field + a try/finally + a multi-line call (net growth). | Task 1 redesigned: all logic in `AuthSessionBootstrapper` (`resolveDestinationBounded`, `resolveDestinationBoundedOnce`, `ExclusiveRun`); the screen edit is net-ZERO lines; `onStillWaiting` dropped (the existing 15 s hint / 30 s CTA already cover the wait). `wc -l` + Gate 43 are exit checks. |
| R12 | A `/*` inside a `///` doc line (`/rest/v1/*`) breaks every naive comment-stripper test. | Comment reworded; Global Constraint + per-task grep check added. |
| R13 | SoT registry `line_range`s for `sync_service.dart` go stale. | Task 6 repoints; parity gate is an exit check of Tasks 2/3/5/7. |
| R14 | Public-API snapshot goes red between Task 2 (`probeBackendReachable`) and Task 3; imports of not-yet-created files; `failReadsTo`/`requests` state leaks across tests in one file (the harness server object is shared). | Snapshot entry moved to Task 2; imports added per task; behavioral test `setUp` clears `requests`, `failReadsTo`, `getResponders`. |

> R1, R4, R8 and R14 above concern the resume pull (Unit C); their dispositions now live in the Phase 1b draft.

## Round-2 review log (4 context-blind reviewers on revision 2; every finding verified against code before acting)

| # | Finding (reviewer) | Disposition |
|---|---|---|
| R2-1 | **P0.** `PostgrestException` is not in scope in the sync library (`sync_service.dart:5` is `show FunctionResponse`; a `part of` file cannot import) → `sync_resilience.dart` does not compile. (R2a) | Task 2 Step 4 item 2 widens the `show` clause; the false "resolves through the existing import" claim is deleted. Verified against the file. |
| R2-2 | `postgrest` 2.9.1 `_executeWithRetry` retries every GET/HEAD answered 503/520 three more times (1 s/2 s/4 s) — 503 is the REAL PGRST002 outage shape. So "one tiny request per probe" was false (4), and a stub that answers 503 makes a "one failing request" test fail. (R2a) | Probe query opts out with `.retry(enabled: false)`; the "one request" wording is qualified. The pull stub lesson (`failReadsTo` must answer 500/504, not 503) is recorded in the Phase 1b draft. |
| R2-3 | A wiring test greps a literal the plan's own code line-breaks (`retryableFailureSeq ==\n retryableFailuresBefore`) → red on the correct code. (R2a) | `RegExp(r'…\s*==\s*…')`; mutation 8 reworded. |
| R2-4 | Task 1 strands `test/onboarding/resume_route_resolver_test.dart:107-115` (source-greps `resolveDestination(`) and `test/contracts/local_onboarding_evidence_behavioral_test.dart:409` (`resolveDestination(userId)`); neither directory is in the gate loop, so they would first fail at pre-push/CI. (R2a) | Both named + repointed in Task 1 Step 5; `test/onboarding/` added to the Task 7 gate loop. |
| R2-5 | Task 3's tests: two fail against the plan's own controller (cooldown starts at construction, tests then call at the same instant), one is vacuous (kill-switch test is `skipped` by the cooldown whatever the switch does), an unused import fails the push, a wiring literal is line-broken. (R2a) | Unit C is split out (R2-6); every one of these is recorded in the Phase 1b draft so the rewrite starts from them. |
| R2-6 | **Unit C design defects** (R2b, each verified against code): (a) `DayRolloverObserver._checkAndRollover` → `reckonStreakDecayAndPersist` runs on STALE local data BEFORE any pull can land (pre-existing hazard; starting the pull after it does not help); (b) `_restoreExerciseLogs` is local-wins `get(logId)==null`, so an exercise log the user deleted whose tombstone is still queued in `PendingExlogDeletes` (exactly the outage case) is RESURRECTED by the pull; (c) the per-set fetch failure is swallowed (`sync_workout.dart:891-901`) → an exlog row is written WITHOUT `sets` and local-wins never heals it; (d) `restoreCompletedTick` is bumped only at `heal_after_restore.dart:74`, so a device whose background restore never completed never refreshes the UI after a pull; (e) partial-pull refresh, water, typed-field predicate. | **§4.12.1: two review rounds in a row found design-level defects in this unit → it is too large. SPLIT.** Units A, B, D, E ship in this batch; Unit C becomes Phase 1b with its own plan + two review rounds, seeded by the draft file (which carries R2-5 and this row). Filed on the OI board (Task 8). |
| R2-7 | `weeklyFullSync` JOINING an in-flight sweep lets the retry report "swept after recovery" about a sweep that started BEFORE the server came back. (R2b P1-3, R2a nit) | Serialised queue: each caller awaits the previous tail, reads the failure baseline AFTER the wait. D13 updated. |
| R2-8 | A banner "Retry" tapped repeatedly = N probes+sweeps; a hung sweep wedges `_running` forever. (R2b P2) | `kSyncRetryManualCooldown` (10 s) and `kSyncRetrySweepCeiling` (5 min) + two tests + two mutations. A "launch-sweep attempt gate" is NOT added: `checkAndSync` is called only from `splash_screen.dart:203`, once per launch, so an unstamped sweep re-runs at most once per launch. |
| R2-10 | **Stranded-contracts lens (R2c, scratch-copy simulation: the plan's Tasks 1/2/4/5 applied, 220 test files that load the edited files + 32 that scan `lib/` run, ~25 gates run):** independently reproduced R2-1 (compile error), R2-3 (line-broken literal), R2-4 (both stranded greps; suggested the whitespace-tolerant regex `AuthSessionBootstrapper.instances*.s*resolveDestination` — equivalent to the repoint in Task 1 Step 5). Measured the registry set that goes stale: `:4874`, `:10899`, `:10910`, `:10920`, `:10935` (`:12377` `_onUserChanged` and `compileDailySnapshot` `:10600` 1052-1110 stay inside their range — the latter by only 5 lines). Everything else green; Gate 43 passes with ZERO slack (800/800). | Already folded (R2-1/3/4); the margin note added to the Global Constraints registry bullet. Verified-safe list is the evidence that the retained units strand nothing else. |
| R2-9 | **Process lens (R2d, scripts read, every item verified):** tuning-history entry belongs in `.claude/skills/code-review/tuning-history.md` (not `SKILL.md`); the plan-review record needs `branch:` + `bpass_review:` and Steps 4/5 must swap; merge must be `--merge`; the closure ledger needs `commit:` per `closed_in_commit`; OI-151 is MOVED to `closed_issues.md`; `mint_oi.sh` already appends the `## OI-N` stub; Task 7 Step 1 told the executor to commit before the founder said so and ran a hand-picked test subset (§4.12.8); the diagnose doc needs 25 keys and a resolvable `sot_registry_entry`; registry `line_range` traps. | Tasks 6/7/8 and the Global Constraints rewritten. |

## B-pass fold (self-triggered `/code-review` on the implemented diff, 2026-10-01 — supersedes the code blocks in Tasks 2 and 4 where they differ)

The code embedded in Tasks 2 and 4 below is the design as reviewed in rounds 1-2. The B-pass (10 findings, no P0/P1, every one verified by mutation or by running the code in a scratch copy) changed the implementation as follows. The REPO files are the source of truth; where a block below disagrees, the repo wins.

| # | B-pass finding | What changed |
|---|---|---|
| F1 | The "next launch's unstamped sweep" recovery claim was false: `last_full_sync` is never cleared, only not advanced, so a reload or the 6-run cap left a failed row unsent until tomorrow's launch. | Durable syncBox flag `sync_sweep_owed`: set by `_reportSyncFailure` when the controller ACCEPTS a failure, cleared only by a clean `weeklyFullSync`, honoured by `checkAndSync` through the pure `shouldRunFullSweep` (interval / no stamp / owed). |
| F2 | The `weeklyFullSync` serialisation (raw tail future + `Completer`) was covered only by a source-grep; four mutations left every test green. | Extracted to `lib/core/services/serial_slot.dart` (`SerialSlot` / `SerialTicket`, newest-tail rule, idempotent release) and tested under fakeAsync (`test/contracts/serial_slot_test.dart`). |
| F3 | The probe had no test, while the docs and registry cited one. | `lib/core/services/backend_probe.dart` (`probeBackendWithClient`) + `test/sync/probe_backend_reachable_test.dart` against the stub server: ONE request, answered-"no" = reachable, 5xx/PGRST002/socket = not. `sync_resilience.dart` keeps the session guard and the 8 s ceiling. |
| F4 | The arming predicate was a name-prefix rule that disagreed with what the sweep re-sends (armed-but-not-swept: `sync_custom_items`, `sync_freezes`, ...; the `sync_community_items` READ). | `kNotSweptOpTypes` + a FORCING-FUNCTION test that enumerates every `opType:` literal in `lib/` against an expected push / not-push table. |
| F5 | The classifier scanned Postgres' echo of the user's own row (`details`) and missed real outage codes. | `_classifiableText` cuts at `, details:`; status regex gains `\b`; widened to TLS/handshake, `net::ERR_`, `53xxx`, `08xxx`, `40001`, `40P01`. |
| F6 | More survivors: connectivity kick `&&`, catch-path attempt count, kill-switch key literals, `_onPausedChanged`, the browser outage strings. | `shouldKickRetryOnConnectivity` is pure and tested; key literals pinned; per-alternative classifier tables; mutation re-proofs recorded in the diagnose doc. |
| F7 | The kill-switch did not restore the old `weeklyFullSync` (the queue was unconditional). | With `disable_sync_retry_sweep` on, `weeklyFullSync` takes no ticket (old path verbatim); stated in the diagnose limits. |
| F8 | The tier hangs on one file: `blast_radius.yaml` classifies only `sync/**` as platform; `sync_service.dart`, `sync_retry_controller.dart`, `sync_queue.dart` compute `account`. | Pre-existing glob gap — an OI (policy call), not a code change in this batch. |
| F9 | Staged docs asserted OI-board state that did not exist yet, an `OI-N` placeholder, a stale telemetry-test reason string, and a 2.82 wording gap (the SDK also retries a GET that THROWS). | OIs minted + placeholders substituted in the same commit; reason string and wording fixed; OI-151's 2 s threshold is recorded as proposed-in-plan, ratified by approving the batch. |
| F10 | A banner tap fanned an un-throttled forced drain into `SyncQueue` (7 forced passes dead-letter an op); the copy could wrap on a 360 dp phone; manual/connectivity probes while paused have no cap. | `retryPausedSync` returns inside the controller cooldown and drains only a non-empty queue; copy "Sync paused — your data is safe", one line, ellipsis; the probe rate is bounded by the 10 s cooldown (no unbounded loop) — accepted, stated in the limits. |

### Unit A extension — evidence-first routing (founder decision 2026-10-01, after the B-pass)

Founder: "if the data for a user is available on the phone, why should we wait repeatedly for 8 seconds? I opened the app, swiped it away, came back, and it started syncing again." A swipe-away is a full cold start; `RestoringScreen._kickoffRestore` awaited the cloud routing read before ANY branch ran, even for a device that already holds everything needed to route.

**Design (verified against the code before building).** With local evidence EVERY branch of `_kickoffRestore` ends in `_goHome` (StartMissionBrief is overridden by the evidence, DestinationUnknown goes home on it, ResumeOnboarding self-heals and goes home, GoHome goes home), so the read cannot change where the user lands. `resolveBounded(evidenceFirst: true)` therefore checks evidence FIRST and returns `GoHome()` immediately; the original read is handed to `_settleLateAnswer`, which applies `applyLateAnswer` when it answers: the Plan A `onboarding_completed_at` stamp for ResumeOnboarding (only with all 9 migration-112 fields, OI-46) and the c2e9f4 override signal for StartMissionBrief — only while `sessionOwnedBy` (Supabase uid AND the open Hive owner) still names the user, with an error sink. `GoHome()`, not `DestinationUnknown`, is returned so the screen's Unknown branch does not log a new per-launch event (Unit E's whole point is less telemetry). No evidence falls through to the pre-existing policy untouched (c2e9f4: a read that did not answer is never StartMissionBrief; a fresh device keeps awaiting the original read). Kill-switch `disable_evidence_first_routing` (the old path, verbatim); `disable_resolve_destination_timeout` and `disable_local_onboarded_evidence` also turn it off. `restoring_screen.dart`: the Plan A stamp body moved to `AuthSessionBootstrapper.stampOnboardingCompletedAt` and the screen's `_stampOnboardingCompletedAt` delegates (net -6 lines; ONE stamp writer; the two source-greps that anchor on the method name are untouched).

**Limits (stated, not hidden).** Saves only the routing-read wait (well under a second on a healthy network; up to the 8 s ceiling on a bad one). Does NOT touch the 3 s splash floor or the cold-start full-history restore (`since='2020-01-01'`, re-run on every swipe-away; a cold-start cooldown is only safe once resume-pull / Phase 1b exists — recorded on the Phase 2 OI). A device whose only evidence is the onboarding flag (no `primary_goal` in the local profile) still awaits the restore in `_goHome`.

**Process.** One fresh self-triggered context-blind review round on the changed files, every finding folded; if it keeps finding new material design issues the extension is split back out (§4.12.1). Tests: `test/contracts/evidence_first_routing_test.dart` (behavioural policy + handler + mirrors, wiring); one existing wiring slice repointed (stricter, not looser): `restoring_destination_timeout_test.dart`.

**Review fold (done, 2026-10-01).** Three context-blind reviewers ran in parallel (routing equivalence + kill-switch matrix; background settle safety; tests/docs/gates): **22 findings, 0 P0, 0 P1, 10 P2, 12 P3, no design-level defect — no split.** Everything was folded: `read.ignore()` on the handed-over read; the background chain extracted into the static `settleLateAnswer` (error sink, no ceiling); `liveSessionOwnedBy` with injectable live readers; `stampOnboardingCompletedAt` self-guarded at entry AND before its push, keeping an existing real stamp (HEAD overwrote it); `ensureTermsConsentFallback` refreshes the token first (it now runs at t~0); per-arm / ordering source-slice pins in place of whole-source `contains`; behavioural tests for the kill-switch getter, the stamp value / push / guards, and the settle chain; two OR-chain source-greps tightened (assertions ADDED, never loosened); wording corrected ("serves empty" was wrong — the raw box getter throws; the Gate 43 cap does not FORCE the logic into the bootstrapper, it is there by choice). Per-finding dispositions: `docs/reviews/resilient-client-phase1-bpass.md`, section "Evidence-first extension".

## Design Decisions (and what they correct)

| # | Decision | Why |
|---|---|---|
| D1 | Pushes are **not** batched. | On current `main` every history push already goes through `SyncSkipIndex.pushIfChanged` (`sync/sync_skip_index.dart`) — only rows whose fingerprint changed since the last CONFIRMED push are sent; a failed push is not recorded as sent, so the next sweep re-sends it. |
| D2 | The retry re-runs `weeklyFullSync()` (`sync_service.dart:1270`). No new push logic. | It fans out every domain through the skip index, so a retry sends only what is still unsent. **Not skip-indexed** (re-sent on EVERY sweep): `_syncUserProfile`, `_syncUserProgress`, `_syncUserPreferences`, `_syncCoachInteractions`, plus the sequential `_syncWorkoutTemplates` — a retry sweep therefore costs ≥ ~6 unconditional requests. The 30 s → 2 m → 10 m backoff, the reachability probe and the 6-attempt cap are what bound that. |
| D3–D11 | **Resume-pull decisions — moved with Unit C to the Phase 1b draft** (window, water, cooldown, `_safeRestoreOp` avoidance, tick bump, recovery, shared failure state, meals/schedule exclusion). | Not part of this plan; numbering kept so existing cross-references to D12–D14 stay valid. |
| D12 | Retry predicate = **outage-shaped** failures only, on **push** opTypes only. Cap = 6 failed runs, then `paused` clears and the cycle restarts only on the next failure. | See R2. Real shapes: socket/DNS, `ClientException: Load failed`, 5xx / Cloudflare 52x (`code: 521`), 408/429, `PGRST000-003` (HTTP 503 with a JSON body — carries NO status code in `PostgrestException.toString()`), `57014`/`53300`, `TimeoutException`. 4xx (400/401/403/404/409/422) and PG `23xxx`/`42703` are NOT retried; unknown shapes are NOT retried (avoids an infinite loop). Push opTypes = `upsert_*`, `sync_*` (except `sync_fitness_summary`, a READ), `restore_sync_*` (a push op that hit the 45 s ceiling), `weekly_full_sync`. `restore_*`, `realtime_*`, `push_snapshot`, `check_and_sync*`, onboarding and `*_recovered`/`*_orphaned` ops never arm a retry. A `String` error is a telemetry-queue REPLAY of an old failure and is ignored. |
| D13 | `weeklyFullSync` writes `last_full_sync` only if `SyncRetryController.retryableFailureSeq` did not move during the sweep, and runs AFTER any in-flight sweep (serialised queue, baseline read after the wait) instead of overlapping or joining. | Without it a failed sweep is stamped "done" and the next launch skips the 1-day sweep (the failure has no other persisted trace — covers the app-kill case without a persisted flag). A deterministic failure (schema/validation) never moves the counter, so it cannot force a re-sweep every launch. |
| D14 | Routing ceiling 8 s: `resolveBounded` → with local evidence the existing `DestinationUnknown`→home branch runs; with NO local evidence (fresh device — nothing to fall back to) it keeps awaiting the original read. The CONTINUE retry is bounded too and guarded against stacking (`ExclusiveRun`). All of it lives in `AuthSessionBootstrapper` so the 800-line-capped screen edit stays small (planned net-zero, ended net -6 with the stamp delegation; R11). | A user with no Hive data cannot be routed anywhere useful; the late answer must still reach the router. |

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/core/services/auth_session_bootstrapper.dart` | Modify | `boundDestination`, `resolveBounded`, `resolveDestinationBounded`, `resolveDestinationBoundedOnce`, kill-switch getter, top-level `ExclusiveRun` |
| `lib/features/auth/screens/restoring_screen.dart` | Modify | Planned net-zero lines (head file at the 800-line Gate 43 cap): two calls swapped for the bounded variants; the evidence-first extension then moved the stamp body out (final: net -6, 794 lines) |
| `lib/core/services/sync_retry_controller.dart` | **Create** | Outage predicates, capped backoff controller (manual cooldown, sweep ceiling), `paused`, `retryableFailureSeq` |
| `lib/core/services/restore_telemetry_policy.dart` | **Create** | `shouldLogRestoreOpDone` |
| `lib/core/services/serial_slot.dart` | **Create** (B-pass F2) | `SerialSlot` / `SerialTicket` — the `weeklyFullSync` serialisation primitive |
| `lib/core/services/backend_probe.dart` | **Create** (B-pass F3) | `probeBackendWithClient` — the ONE-request reachability probe |
| `test/contracts/serial_slot_test.dart`, `test/sync/probe_backend_reachable_test.dart` | **Create** (B-pass F2/F3) | behavioural tests for the two primitives |
| `test/contracts/evidence_first_routing_test.dart` | **Create** (Unit A extension) | evidence-first policy, late-answer handler, session guard, kill-switches, wiring |
| `lib/core/services/sync/sync_resilience.dart` | **Create** | `part of` extension: `probeBackendReachable` |
| `lib/core/services/sync_service.dart` | Modify | line-5 `show` widened, part/imports, `_weeklyFullSyncRunning`, bind + reset controllers, `_reportSyncFailure` hook, `weeklyFullSync` serialise + stamp-on-clean, `_safeRestoreOp` filter |
| `lib/shared/providers/sync_state_provider.dart` | Modify | `SyncPaused`, paused-first `_stateFor`, listener, connectivity kick, `retryPausedSync` |
| `lib/shared/widgets/sync_banner.dart` | Modify | Render `SyncPaused` |
| `test/contracts/sync_service_public_api_snapshot_test.dart` | Modify | add `probeBackendReachable` |
| `test/onboarding/resume_route_resolver_test.dart`, `test/contracts/local_onboarding_evidence_behavioral_test.dart` | Modify | repoint the two source-greps Task 1 strands (R2-4) |
| `test/contracts/restoring_destination_timeout_test.dart` | **Create** | Task 1 |
| `test/contracts/sync_retry_controller_test.dart` | **Create** | Task 2 |
| `test/contracts/sync_paused_state_test.dart` | **Create** | Task 4 |
| `test/contracts/restore_op_done_filter_test.dart` | **Create** | Task 5 |
| `docs/sot_registry.yaml`, `docs/diagnoses/2026-10-01-supabase-api-outage-client-resilience-e5b2a9.md`, nested `CLAUDE.md`s, `docs/architecture/sync.md`, `.claude/skills/debugging/{bug-classes.md,SKILL.md}`, `docs/audit/{open_issues.md,closed_issues.md,resilient-client-phase1.closure.yaml}`, `docs/plan-reviews/claude-resilient-client-phase1.md`, `docs/reviews/<id>-bpass.md`, `.claude/skills/code-review/tuning-history.md`, this plan + the Phase 1b draft | Modify/Create | Tasks 6 + 7 + 8 |

**Moved out with Unit C (Phase 1b draft):** `resume_pull_controller.dart`, `pullRecentWindow`, `day_rollover_service.dart` hook, `failReadsTo` stub helper, the two pull test files.
---

### Task 1: Bound the post-auth routing read (Unit A)

**Symptom:** during the 2026-10-01 05:50–06:30 UTC outage the splash showed "Getting you ready…" for ~15 min.
**Writer/reader:** `AuthSessionBootstrapper.resolveDestination` (`auth_session_bootstrapper.dart:175`) is the writer of the routing decision; `RestoringScreen._kickoffRestore` (`restoring_screen.dart:110-116`) is the reader and `await`s it with no ceiling. Its retry at `restoring_screen.dart:623-624` is the same shape. The "already onboarded locally → go home" branch (`:156-160`) only runs after that `await` returns.
**Recurrence check (§4.1.5):** same *class* as `c2e9f4` (a read that did not answer must not look like "new user") and `d7b1f8` (auth reads piling up on a starved backend, 10–36 s each). Neither added a ceiling.
**Hard constraint (round-1b, verified):** `restoring_screen.dart` is **exactly 800 lines** and Gate 43 (`scripts/check_god_screen_max_lines.dart:29`, blocking at pre-commit) caps `lib/**/screens/*_screen.dart` at 800. The screen edit is therefore **net-zero lines** — two 2-line statements are replaced by two 2-line statements — and ALL logic (ceiling, local-evidence policy, in-flight guard, kill-switch read) lives in `auth_session_bootstrapper.dart`. Do not raise `_maxLines`.

**Files:**
- Modify: `lib/core/services/auth_session_bootstrapper.dart` (class members inserted after `resolvePlanRegenStart`, before `/// Per-user mutex.`; one top-level class appended at the end of the file)
- Modify: `lib/features/auth/screens/restoring_screen.dart` (`_kickoffRestore` ~:110-111; `_onContinueAnyway` ~:623-624) — **net 0 lines**
- Test: `test/contracts/restoring_destination_timeout_test.dart` (create)
- Modify (stranded source-greps, R2-4): `test/onboarding/resume_route_resolver_test.dart:107-115`, `test/contracts/local_onboarding_evidence_behavioral_test.dart:409`

**Interfaces:**
- Produces on `AuthSessionBootstrapper`: `kDestinationReadLimit` (8 s), `kDestinationTimeoutReason` (`'read_ceiling'`), `kDisableDestinationTimeoutKey`, `static bool get destinationTimeoutDisabled`, `static boundDestination(read, {limit, disabled})`, `static resolveBounded(read, {required hasLocalEvidence, limit, disabled})`, instance `resolveDestinationBounded(String userId, Future<bool> Function() hasLocalEvidence)`, instance `resolveDestinationBoundedOnce(String userId)`; top-level `class ExclusiveRun { Future<T> run<T>(Future<T> Function() start, {required T whenBusy}) }`.
- Consumes: `DestinationUnknown(String reason)` (`:76-80`), `HiveService.instance.configBox`, `RestoringScreen._hasLocalOnboardedEvidence` (`:267`, never throws).

- [ ] **Step 1: Write the failing test**

Create `test/contracts/restoring_destination_timeout_test.dart`:

```dart
// test/contracts/restoring_destination_timeout_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit A). The post-auth routing read must
// have a hard ceiling so a hung backend (521/504, 10-36s per request) cannot
// hold RestoringScreen before its local-evidence branch can run — WITHOUT
// discarding a late answer for a user who has no local data to fall back on.
//
// Behavioral (fakeAsync) for the static helpers + ExclusiveRun; comment-stripped
// source-grep for the wiring (presence only — the behavioral half is the helper
// tests). `restoring_screen.dart` is a LIBRARY (head + part files), so the wiring
// reads it through readRestoringScreenSource().

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';

import '../helpers/read_screen_source.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

typedef _Dest = PostSignInDestination;

void main() {
  group('boundDestination', () {
    test('a read that never answers becomes DestinationUnknown(read_ceiling) at the limit',
        () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.boundDestination(Completer<_Dest>().future)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 7));
        expect(got, isNull, reason: 'must still be waiting before the limit');
        async.elapse(const Duration(seconds: 2));
        expect(got, isA<DestinationUnknown>());
        expect((got! as DestinationUnknown).reason,
            AuthSessionBootstrapper.kDestinationTimeoutReason);
      });
    });

    test('a prompt GoHome passes through untouched', () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.boundDestination(
                Future<_Dest>.value(const GoHome()))
            .then((v) => got = v);
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
      });
    });

    test('MIRROR: an ANSWERED StartMissionBrief inside the limit is not rewritten',
        () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.boundDestination(Future<_Dest>.delayed(
                const Duration(seconds: 7), () => const StartMissionBrief()))
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 8));
        expect(got, isA<StartMissionBrief>(),
            reason: 'a real "new user" answer must never become unknown');
      });
    });

    test('a timeout is NEVER StartMissionBrief (the c2e9f4 invariant)', () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.boundDestination(Completer<_Dest>().future)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 10));
        expect(got, isNotNull, reason: 'the ceiling must have fired');
        expect(got, isNot(isA<StartMissionBrief>()));
      });
    });

    test('custom limit is honoured; disabled never times out', () {
      fakeAsync((async) {
        _Dest? a;
        _Dest? b;
        AuthSessionBootstrapper.boundDestination(Completer<_Dest>().future,
                limit: const Duration(seconds: 2))
            .then((v) => a = v);
        AuthSessionBootstrapper.boundDestination(Completer<_Dest>().future,
                disabled: true)
            .then((v) => b = v);
        async.elapse(const Duration(minutes: 5));
        expect(a, isA<DestinationUnknown>());
        expect(b, isNull);
      });
    });

    test('constants: 8 s ceiling and the documented kill-switch key', () {
      expect(AuthSessionBootstrapper.kDestinationReadLimit,
          const Duration(seconds: 8));
      expect(AuthSessionBootstrapper.kDisableDestinationTimeoutKey,
          'disable_resolve_destination_timeout');
    });
  });

  group('resolveBounded (the policy RestoringScreen runs)', () {
    test('timeout + local evidence → unknown at 8s so the existing branch goes home',
        () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(Completer<_Dest>().future,
                hasLocalEvidence: () async => true)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 7));
        expect(got, isNull);
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(got, isA<DestinationUnknown>());
      });
    });

    test('timeout + NO local evidence → keeps waiting; the LATE answer is used, not discarded',
        () {
      fakeAsync((async) {
        final c = Completer<_Dest>();
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(c.future,
                hasLocalEvidence: () async => false)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 9));
        async.flushMicrotasks();
        expect(got, isNull, reason: 'nothing to fall back to: must keep waiting');
        async.elapse(const Duration(minutes: 2));
        expect(got, isNull);
        c.complete(const GoHome());
        async.flushMicrotasks();
        expect(got, isA<GoHome>(),
            reason: 'the original read answered late — its answer must route');
      });
    });

    test('an evidence check that THROWS counts as no evidence (keeps waiting)', () {
      fakeAsync((async) {
        final c = Completer<_Dest>();
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(c.future,
                hasLocalEvidence: () async => throw StateError('box closed'))
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 9));
        async.flushMicrotasks();
        expect(got, isNull);
        c.complete(const GoHome());
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
      });
    });

    test('a prompt answer never consults local evidence', () {
      fakeAsync((async) {
        var consulted = 0;
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(
                Future<_Dest>.value(const GoHome()),
                hasLocalEvidence: () async {
                  consulted++;
                  return true;
                })
            .then((v) => got = v);
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
        expect(consulted, 0);
      });
    });

    test('MIRROR: a StartMissionBrief answered at 7s is returned as-is', () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(
                Future<_Dest>.delayed(
                    const Duration(seconds: 7), () => const StartMissionBrief()),
                hasLocalEvidence: () async => true)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 8));
        async.flushMicrotasks();
        expect(got, isA<StartMissionBrief>());
      });
    });

    test('disabled → the raw read is awaited and evidence is never consulted', () {
      fakeAsync((async) {
        var consulted = 0;
        final c = Completer<_Dest>();
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(c.future,
                disabled: true,
                hasLocalEvidence: () async {
                  consulted++;
                  return true;
                })
            .then((v) => got = v);
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(got, isNull);
        c.complete(const GoHome());
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
        expect(consulted, 0);
      });
    });
  });

  group('ExclusiveRun (the CONTINUE-retry stacking guard)', () {
    test('a second call while one is running gets whenBusy and does NOT start', () {
      fakeAsync((async) {
        final r = ExclusiveRun();
        final gate = Completer<int>();
        var started = 0;
        int? first;
        int? second;
        r.run<int>(() {
          started++;
          return gate.future;
        }, whenBusy: -1).then((v) => first = v);
        r.run<int>(() {
          started++;
          return gate.future;
        }, whenBusy: -1).then((v) => second = v);
        async.flushMicrotasks();
        expect(started, 1);
        expect(second, -1);
        gate.complete(7);
        async.flushMicrotasks();
        expect(first, 7);
      });
    });

    test('MIRROR: once the first finishes, the next call runs', () async {
      final r = ExclusiveRun();
      expect(await r.run<int>(() async => 1, whenBusy: -1), 1);
      expect(await r.run<int>(() async => 2, whenBusy: -1), 2);
    });

    test('a start that THROWS still releases the slot', () async {
      final r = ExclusiveRun();
      await expectLater(
          r.run<int>(() async => throw StateError('x'), whenBusy: -1),
          throwsStateError);
      expect(await r.run<int>(() async => 5, whenBusy: -1), 5);
    });
  });

  group('wiring (presence — comment-stripped)', () {
    final screen = _strip(readRestoringScreenSource());
    final boot = _strip(
        File('lib/core/services/auth_session_bootstrapper.dart').readAsStringSync());

    test('no bare resolveDestination( call remains in the restoring screen', () {
      expect(RegExp(r'\.resolveDestination\(').hasMatch(screen), isFalse,
          reason: 'every routing read in the screen must be bounded');
    });

    test('_kickoffRestore routes through resolveDestinationBounded with the local-evidence check',
        () {
      expect(
          screen.contains(
              'resolveDestinationBounded(user.id, _hasLocalOnboardedEvidence)'),
          isTrue);
    });

    test('the CONTINUE retry routes through the guarded, bounded variant', () {
      expect(screen.contains('resolveDestinationBoundedOnce(userId)'), isTrue);
    });

    test('the bootstrapper wrappers apply the kill-switch and the guard', () {
      final i = boot.indexOf('resolveDestinationBounded(');
      expect(i, greaterThan(-1));
      final w = boot.substring(i, i + 700);
      expect(w.contains('resolveBounded('), isTrue);
      expect(w.contains('destinationTimeoutDisabled'), isTrue);
      expect(w.contains('_continueRetry.run<'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/restoring_destination_timeout_test.dart`
Expected: FAIL to compile — `boundDestination` / `resolveBounded` / `ExclusiveRun` / constants undefined.

- [ ] **Step 3: Implement the helpers**

In `lib/core/services/auth_session_bootstrapper.dart`, directly after the closing brace of `resolvePlanRegenStart` (the method ending `return DateTime.tryParse(hiveIso) ?? now;\n  }`), before `/// Per-user mutex.` (**no `/*` character sequence anywhere in these comments** — see Global Constraints):

```dart
  /// Hard ceiling on how long the post-auth routing read may hold the splash.
  ///
  /// closes-diagnose e5b2a9 — during the 2026-10-01 Supabase API outage the auth
  /// endpoint and the REST endpoints answered 504/521 for ~25 minutes and each
  /// hung request held a connection 10-36 s (same shape as d7b1f8).
  /// [resolveDestination] (token refresh + SELECT + hard-refresh retry +
  /// SELECT) had NO ceiling, so `RestoringScreen._kickoffRestore`'s
  /// `await destinationFuture` never reached its local-evidence branch and the
  /// user sat on "Getting you ready…" until they found the 30 s CONTINUE button.
  static const Duration kDestinationReadLimit = Duration(seconds: 8);

  /// `DestinationUnknown.reason` stamped by the ceiling. Distinct from every
  /// reason [resolveDestination] itself produces, so [resolveBounded] can tell
  /// "the ceiling fired" from "the read answered unknown".
  static const String kDestinationTimeoutReason = 'read_ceiling';

  /// §4.6 kill-switch: `configBox[...] == true` restores the unbounded await.
  static const String kDisableDestinationTimeoutKey =
      'disable_resolve_destination_timeout';

  /// Defensive read — a missing/unopened configBox means the fix stays ACTIVE.
  static bool get destinationTimeoutDisabled {
    try {
      return HiveService.instance.configBox
              .get(kDisableDestinationTimeoutKey) ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// Bounds [read] so an unanswered routing read becomes
  /// [DestinationUnknown]([kDestinationTimeoutReason]) — NEVER
  /// [StartMissionBrief]. "The read did not answer" is its own state (c2e9f4).
  ///
  /// The abandoned read keeps running inside [resolveDestination]'s per-user
  /// lock. A second [resolveDestination] call therefore queues behind it, which
  /// is why the CONTINUE retry is bounded (and guarded) too.
  static Future<PostSignInDestination> boundDestination(
    Future<PostSignInDestination> read, {
    Duration limit = kDestinationReadLimit,
    bool disabled = false,
  }) {
    if (disabled) return read;
    return read.timeout(
      limit,
      onTimeout: () => const DestinationUnknown(kDestinationTimeoutReason),
    );
  }

  /// The routing policy `RestoringScreen._kickoffRestore` runs.
  ///
  ///  * answered within [limit] → that answer, untouched;
  ///  * ceiling fired AND the device holds local evidence of onboarding → the
  ///    ceiling's [DestinationUnknown] (the screen's existing unknown branch
  ///    then goes home on that evidence);
  ///  * ceiling fired and there is NO local evidence (fresh device / reinstall —
  ///    nothing to fall back to) → keep awaiting the ORIGINAL [read], so a late
  ///    answer still routes instead of being thrown away.
  static Future<PostSignInDestination> resolveBounded(
    Future<PostSignInDestination> read, {
    required Future<bool> Function() hasLocalEvidence,
    Duration limit = kDestinationReadLimit,
    bool disabled = false,
  }) async {
    final bounded =
        await boundDestination(read, limit: limit, disabled: disabled);
    final ceilingFired = bounded is DestinationUnknown &&
        bounded.reason == kDestinationTimeoutReason;
    if (!ceilingFired) return bounded;
    var evidence = false;
    try {
      evidence = await hasLocalEvidence();
    } catch (_) {
      evidence = false;
    }
    if (evidence) return bounded;
    return read;
  }

  /// [resolveDestination] + [resolveBounded] + the kill-switch, for the screen.
  Future<PostSignInDestination> resolveDestinationBounded(
    String userId,
    Future<bool> Function() hasLocalEvidence,
  ) =>
      resolveBounded(
        resolveDestination(userId),
        hasLocalEvidence: hasLocalEvidence,
        disabled: destinationTimeoutDisabled,
      );

  /// The CONTINUE button's retry: bounded, and a second tap while one is in
  /// flight gets an "unknown" (the screen's existing "tap again" branch) instead
  /// of queueing another abandoned read behind the per-user lock.
  final ExclusiveRun _continueRetry = ExclusiveRun();

  Future<PostSignInDestination> resolveDestinationBoundedOnce(String userId) =>
      _continueRetry.run<PostSignInDestination>(
        () => boundDestination(
          resolveDestination(userId),
          disabled: destinationTimeoutDisabled,
        ),
        whenBusy: const DestinationUnknown('retry_in_flight'),
      );

```

Append at the END of the same file:

```dart
/// Runs one async job at a time: a call made while another is in flight returns
/// [whenBusy] without starting, and the slot is released even if the job throws.
class ExclusiveRun {
  bool _busy = false;

  Future<T> run<T>(Future<T> Function() start, {required T whenBusy}) async {
    if (_busy) return whenBusy;
    _busy = true;
    try {
      return await start();
    } finally {
      _busy = false;
    }
  }
}
```

- [ ] **Step 4: Wire the two call sites (NET ZERO LINES)**

In `lib/features/auth/screens/restoring_screen.dart` replace

```dart
    final destinationFuture =
        AuthSessionBootstrapper.instance.resolveDestination(user.id);
```
with
```dart
    final destinationFuture = AuthSessionBootstrapper.instance
        .resolveDestinationBounded(user.id, _hasLocalOnboardedEvidence);
```
and replace
```dart
        final retry =
            await AuthSessionBootstrapper.instance.resolveDestination(userId);
```
with
```dart
        final retry = await AuthSessionBootstrapper.instance
            .resolveDestinationBoundedOnce(userId);
```

- [ ] **Step 5: Repoint the two stranded source-greps, then run the test + neighbours + the 800-line gate + whole-tree analyze**

Task 1's edit removes the literals two existing tests grep for (verified, R2a P1-6). REPOINT both — the assertion still holds, the call was renamed — never loosen:
- `test/onboarding/resume_route_resolver_test.dart:107-115` ('mid-onboarding branch invokes the bootstrapper'): it accepts `AuthSessionBootstrapper.instance.resolveDestination`, `AuthSessionBootstrapper().resolveDestination` or `.resolveDestination(` — none survives (the screen now reads `AuthSessionBootstrapper.instance
        .resolveDestinationBounded(` / `…BoundedOnce(`). Replace the whole `restoringSrc.contains(…) || … || …` expression with `RegExp(r'.resolveDestination(Bounded|BoundedOnce)?(').hasMatch(restoringSrc)`, keep the `reason:`.
- `test/contracts/local_onboarding_evidence_behavioral_test.dart:409`: `continueBody.contains('resolveDestination(userId)')` → `continueBody.contains('resolveDestinationBoundedOnce(userId)')` (same `reason:` — "it must actually re-ask, not guess").

Run: `TZ=Asia/Kolkata flutter test test/contracts/restoring_destination_timeout_test.dart test/onboarding/resume_route_resolver_test.dart test/contracts/restoring_screen_timeout_test.dart test/contracts/auth_session_bootstrapper_test.dart test/contracts/local_onboarding_evidence_behavioral_test.dart test/contracts/background_restore_test.dart`
Expected: PASS (the neighbours pin the 15 s/30 s thresholds, `classifyDestination`, the evidence predicate, `_goHome`; `auth_session_bootstrapper_test.dart` strips comments with a NAIVE block-comment regex — which is why no inserted comment may contain `/*`). If a neighbour source-greps a slice that this edit shifted, REPOINT it (the assertion still holds, it moved) — never loosen.
Run: `wc -l lib/features/auth/screens/restoring_screen.dart` → must print **800 or less**, then `dart run scripts/check_god_screen_max_lines.dart` → exit 0.
Run: `git diff -U0 -- lib/core/services/auth_session_bootstrapper.dart | grep -n '^+.*/\*'` → must print nothing.
Run: `flutter analyze lib/` → `No issues found!` (warnings fail the push; infos tolerated).

- [ ] **Step 6: Mutation proof (record the counts)**

1. `boundDestination`: replace the `read.timeout(...)` return with `return read;` → expect RED: "never answers", "custom limit", "never StartMissionBrief" (`isNotNull`), the ceiling test in `resolveBounded`. Record N.
2. `resolveBounded`: change the final `return read;` to `return bounded;` → "NO local evidence … LATE answer" and "evidence check THROWS" RED. Record.
3. `resolveBounded`: delete `if (evidence) return bounded;` → "timeout + local evidence" RED. Record.
4. `ExclusiveRun`: delete `if (_busy) return whenBusy;` → "second call … does NOT start" RED; separately delete the `finally { _busy = false; }` release → "MIRROR: once the first finishes" and "THROWS still releases" RED. Record.
5. `restoring_screen.dart`: revert ONE wrapped call to the bare `.resolveDestination(` → "no bare resolveDestination( call remains" RED. Record.
Restore each by reverse-editing; re-run → green; `git diff` of both files shows only the intended change and `wc -l` of the screen is still ≤ 800.

---

### Task 2: Reachability-gated, capped retry of the push sweep (Unit B)

**Symptom:** a weight logged on web during the outage never reached the cloud (no 2026-10-01 `weight_logs` row) and nothing retried it until the next write or launch. `SyncStateNotifier`'s connectivity trigger (`sync_state_provider.dart:164`) cannot fire in a backend-only outage — the device is online — and `SyncQueue` carries only 3 profile op types.
**Writer/reader:** writer of the failure signal = every domain push's catch → `SyncService._reportSyncFailure` (`sync_service.dart:2657`, single funnel; `SyncSkipIndex.pushIfChanged` reports through it `sync_skip_index.dart:231-232`; `_safeRestoreOp` reports push-op ceilings as `restore_sync_*`). The reader that must act on it does not exist. Second defect, same area: `weeklyFullSync` stamps `last_full_sync` (`:1310`) unconditionally, so even a launch after a fully-failed sweep skips the sweep for a day.
**Recurrence check:** `b7c2a9` / `d2e8f4` (SyncQueue auto-drain never wired) — same class, "a retry mechanism with no trigger for the failure that actually occurs". Different mechanism.

**Files:**
- Create: `lib/core/services/sync_retry_controller.dart`
- Create: `lib/core/services/sync/sync_resilience.dart` (`probeBackendReachable`)
- Modify: `lib/core/services/sync_service.dart` (**including line 5: `show FunctionResponse` → `show FunctionResponse, PostgrestException`** — a `part of` file cannot add its own import, and `sync_resilience.dart` names `PostgrestException` in an `is` test; without this `flutter analyze lib/` fails with `type_test_with_undefined_name`. Round-2 R2a P0-1, verified: line 5 today is `import 'package:supabase_flutter/supabase_flutter.dart' show FunctionResponse;`)
- Modify: `test/contracts/sync_service_public_api_snapshot_test.dart` (add `'probeBackendReachable'` — a new public member of the part-file extension; the exact-set snapshot goes red the moment Task 2 adds it)
- Test: `test/contracts/sync_retry_controller_test.dart` (create)

**Interfaces:**
- Produces: `kSyncRetrySchedule` (`[30 s, 2 m, 10 m]`), `kSyncRetryMaxAttempts` (6), `kSyncRetryManualCooldown` (10 s — a banner tap spammed N times is ONE probe+sweep), `kSyncRetrySweepCeiling` (5 min — a hung sweep cannot wedge `_running` forever), `syncRetryDelay`, `httpStatusOfError(Object) → int?`, `isOutageShapedFailure(Object)`, `isPushFailureOpType(String)`, `isSyncRetryDisabled(Object?)`, `class SyncRetryController` — ctor `({required probe, required sweep, schedule, maxAttempts, jitter, isDisabled})`; `static instance`; `bind({probe, sweep})`; `ValueNotifier<bool> paused`; `int get retryableFailureSeq`; `void noteFailure(Object error, {required String opType})`; `Future<void> retryNow()`; `void reset()`. `SyncService.probeBackendReachable()` → `Future<bool>`.
- Consumes: `weeklyFullSync()`.

- [ ] **Step 1: Write the failing test**

Create `test/contracts/sync_retry_controller_test.dart`:

```dart
// test/contracts/sync_retry_controller_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit B). An OUTAGE-SHAPED PUSH failure
// schedules a reachability-gated re-sweep on 30s → 2m → 10m (capped at 6 failed
// runs); anything else never does; recovery clears `paused` and resets the
// backoff; an account switch drops everything including an in-flight run.

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_retry_controller.dart';

// Real shapes from client_errors, 2026-10-01 outage.
final Object _cf521 = Exception(
    'PostgrestException(message: error code: 521\n, code: 521, details: <none>, hint: null)');
final Object _pgrst002 = Exception(
    'PostgrestException(message: Could not query the database for the schema cache. Retrying., code: PGRST002, details: null, hint: null)');
final Object _dns = Exception(
    "ClientException with SocketException: Failed host lookup: 'dedsavbjuwgarrhphgnl.supabase.co' (OS Error: No address associated with hostname, errno = 7)");
final Object _webLoadFailed = Exception(
    'ClientException: Load failed, uri=https://dedsavbjuwgarrhphgnl.supabase.co/rest/v1/workout_logs?on_conflict=user_id');
final Object _ceiling45 =
    TimeoutException('Future not completed', const Duration(seconds: 45));
// A deterministic failure: the same payload can never succeed.
final Object _dup23505 =
    Exception('PostgrestException(message: duplicate key, code: 23505, details: x, hint: null)');

class _Harness {
  int probes = 0;
  int sweeps = 0;
  bool reachable = true;
  bool disabled = false;
  Completer<bool>? probeGate;
  Completer<void>? sweepGate;
  void Function()? duringSweep;
  late final SyncRetryController c;

  _Harness({int maxAttempts = kSyncRetryMaxAttempts}) {
    c = SyncRetryController(
      probe: () async {
        probes++;
        final g = probeGate;
        if (g != null) return g.future;
        return reachable;
      },
      sweep: () async {
        sweeps++;
        duringSweep?.call();
        final g = sweepGate;
        if (g != null) await g.future;
      },
      jitter: (d) => d, // deterministic
      maxAttempts: maxAttempts,
      isDisabled: () => disabled,
    );
  }

  void fail([String op = 'upsert_weight_log', Object? e]) =>
      c.noteFailure(e ?? _cf521, opType: op);
}

void main() {
  group('outage predicate', () {
    test('httpStatusOfError reads the status from the real shapes, never a UUID or a PG code',
        () {
      expect(httpStatusOfError(_cf521), 521);
      expect(httpStatusOfError(Exception('FunctionException(status: 503, details: x)')), 503);
      expect(httpStatusOfError(_dup23505), isNull, reason: '5-digit PG code is not an HTTP status');
      expect(httpStatusOfError(Exception('id 5f0a13b2-401a-4bcc-8403-dddddddddddd failed')),
          isNull);
    });

    test('outage shapes ARE retryable', () {
      for (final e in [
        _cf521,
        _pgrst002,
        _dns,
        _webLoadFailed,
        _ceiling45,
        const SocketException('Failed host lookup'),
        Exception('PostgrestException(message: x, code: 504)'),
        Exception('PostgrestException(message: x, code: 429)'),
        Exception('PostgrestException(message: canceling statement, code: 57014)'),
      ]) {
        expect(isOutageShapedFailure(e), isTrue, reason: '$e');
      }
    });

    test('MIRROR: answered-and-rejected / unknown shapes are NOT retryable', () {
      for (final e in [
        _dup23505,
        Exception('PostgrestException(message: x, code: 400)'),
        Exception('PostgrestException(message: JWT expired, code: 401)'),
        Exception('PostgrestException(message: x, code: 403)'),
        Exception('PostgrestException(message: x, code: 404)'),
        Exception('PostgrestException(message: x, code: 409)'),
        Exception('column foo does not exist 42703'),
        StateError('bad state'),
        Exception('id 5f0a13b2-401a-4bcc-8403-dddddddddddd failed'),
      ]) {
        expect(isOutageShapedFailure(e), isFalse, reason: '$e');
      }
    });

    test('push op types are allowlisted; reads/restores/bookkeeping are not', () {
      for (final op in [
        'upsert_weight_log',
        'upsert_workout_log',
        'sync_workout_plan',
        'sync_custom_items',
        'restore_sync_weight', // a PUSH op that hit the 45s ceiling in weeklyFullSync
        'weekly_full_sync',
      ]) {
        expect(isPushFailureOpType(op), isTrue, reason: op);
      }
      for (final op in [
        'sync_fitness_summary', // a READ
        'restore_workout_logs',
        'restore_weight_logs',
        'realtime_handler_weight_logs',
        'push_snapshot',
        'check_and_sync',
        'onboarding_sync',
        'scheduled_workout_fk_recovered',
        'scheduled_workout_template_orphaned',
        'restore_from_cloud_for_user',
      ]) {
        expect(isPushFailureOpType(op), isFalse, reason: op);
      }
    });

    test('delay schedule is 30s, 2m, 10m and caps at the last entry', () {
      expect(syncRetryDelay(0), const Duration(seconds: 30));
      expect(syncRetryDelay(1), const Duration(minutes: 2));
      expect(syncRetryDelay(2), const Duration(minutes: 10));
      expect(syncRetryDelay(9), const Duration(minutes: 10));
      expect(syncRetryDelay(-3), const Duration(seconds: 30));
    });

    test('kill-switch predicate: only literal true disables', () {
      expect(isSyncRetryDisabled(true), isTrue);
      expect(isSyncRetryDisabled(false), isFalse);
      expect(isSyncRetryDisabled(null), isFalse);
      expect(isSyncRetryDisabled('true'), isFalse);
    });
  });

  group('noteFailure filtering', () {
    test('only an outage-shaped PUSH failure is accepted (and counted)', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail('upsert_weight_log', _cf521);
        expect(h.c.retryableFailureSeq, 1);
        h.fail('restore_weight_logs', _cf521); // wrong opType
        h.fail('upsert_weight_log', _dup23505); // wrong shape
        h.c.noteFailure('PostgrestException(code: 521)', // a telemetry-queue REPLAY
            opType: 'upsert_weight_log');
        expect(h.c.retryableFailureSeq, 1);
      });
    });

    test('kill-switch on → inert: nothing counted, nothing paused', () {
      fakeAsync((async) {
        final h = _Harness()..disabled = true;
        h.fail();
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();
        expect(h.c.paused.value, isFalse);
        expect(h.c.retryableFailureSeq, 0);
        expect(h.probes, 0);
      });
    });

    test('a non-retryable failure never schedules anything', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail('upsert_weight_log', _dup23505);
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();
        expect(h.c.paused.value, isFalse);
        expect(h.probes, 0);
        expect(h.sweeps, 0);
      });
    });
  });

  group('controller', () {
    test('a failure pauses and sweeps after 30s, not before', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        expect(h.c.paused.value, isTrue);
        async.elapse(const Duration(seconds: 29));
        expect(h.sweeps, 0, reason: 'must wait the full 30s');
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(h.probes, 1);
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isFalse, reason: 'clean sweep clears paused');
      });
    });

    test('an unreachable probe does NOT sweep and backs off to 2 minutes', () {
      fakeAsync((async) {
        final h = _Harness()..reachable = false;
        h.fail();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.probes, 1);
        expect(h.sweeps, 0, reason: 'no sweep while the server is unreachable');
        expect(h.c.paused.value, isTrue);

        async.elapse(const Duration(minutes: 1, seconds: 50)); // t=141s < 150s
        async.flushMicrotasks();
        expect(h.probes, 1, reason: 'second attempt waits the 2m step');

        h.reachable = true;
        async.elapse(const Duration(seconds: 15)); // t=156s
        async.flushMicrotasks();
        expect(h.probes, 2);
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isFalse);
      });
    });

    test('a burst of failures yields ONE sweep (single timer)', () {
      fakeAsync((async) {
        final h = _Harness();
        for (var i = 0; i < 25; i++) {
          h.fail();
        }
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(h.sweeps, 1);
      });
    });

    test('a failure DURING the sweep keeps paused and re-arms at the next step', () {
      fakeAsync((async) {
        final h = _Harness();
        h.duringSweep = () => h.fail();
        h.fail();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isTrue, reason: 'sweep itself failed again');

        h.duringSweep = null;
        // The 2m step was armed at t≈30s → fires at t≈150s. Now t=31s:
        // +110s → t=141s still waiting; +15s → t=156s fires.
        async.elapse(const Duration(minutes: 1, seconds: 50));
        async.flushMicrotasks();
        expect(h.sweeps, 1, reason: 'next attempt is the 2m step, not 30s');
        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();
        expect(h.sweeps, 2);
        expect(h.c.paused.value, isFalse);
      });
    });

    test('MIRROR: recovery resets the backoff — the next outage waits 30s again', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.c.paused.value, isFalse);

        h.fail();
        async.elapse(const Duration(seconds: 29));
        expect(h.sweeps, 1, reason: 'second outage must not inherit a longer wait');
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(h.sweeps, 2);
      });
    });

    test('the cap: after 6 failed runs it stops and clears paused (no endless loop)', () {
      fakeAsync((async) {
        final h = _Harness()..reachable = false;
        h.fail();
        async.elapse(const Duration(hours: 3));
        async.flushMicrotasks();
        expect(h.probes, 6, reason: '30s,2m,10m,10m,10m,10m then give up');
        expect(h.c.paused.value, isFalse,
            reason: 'the banner must not claim "retrying" forever');
        // A later failure starts a FRESH cycle from the 30s step.
        h.reachable = true;
        h.fail();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.sweeps, 1);
      });
    });

    test('retryNow() sweeps immediately and cancels the pending timer', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        h.c.retryNow();
        async.flushMicrotasks();
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isFalse);
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(h.sweeps, 1, reason: 'the cancelled timer must not double-fire');
      });
    });

    test('retryNow() against an unreachable server does NOT advance the backoff', () {
      fakeAsync((async) {
        final h = _Harness()..reachable = false;
        h.fail();
        h.c.retryNow();
        async.flushMicrotasks();
        expect(h.probes, 1);
        expect(h.sweeps, 0);
        // A manual tap must re-arm the SAME 30s step, not escalate to 2m.
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.probes, 2);
      });
    });

    test('retryNow() spam: taps inside the 10s cooldown are ONE probe+sweep', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        h.c.retryNow();
        async.flushMicrotasks();
        expect(h.probes, 1);
        h.fail(); // a second failure re-pauses (a 30s timer is armed)
        h.c.retryNow(); // inside the cooldown → ignored
        h.c.retryNow();
        async.flushMicrotasks();
        expect(h.probes, 1, reason: 'a tap inside the cooldown must not probe');
        async.elapse(kSyncRetryManualCooldown + const Duration(seconds: 1));
        h.c.retryNow(); // after the cooldown → runs
        async.flushMicrotasks();
        expect(h.probes, 2);
      });
    });

    test('a sweep that never completes is abandoned at the ceiling; the cycle continues', () {
      fakeAsync((async) {
        final h = _Harness()..sweepGate = Completer<void>();
        h.fail();
        async.elapse(const Duration(seconds: 31)); // the run starts and parks in the sweep
        async.flushMicrotasks();
        expect(h.sweeps, 1);
        async.elapse(kSyncRetrySweepCeiling + const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(h.c.paused.value, isTrue,
            reason: 'a hung sweep is a FAILED run — never reported as recovery');
        h.sweepGate = null;
        async.elapse(const Duration(minutes: 3)); // the re-armed 2m step (attempt 1)
        async.flushMicrotasks();
        expect(h.sweeps, 2, reason: '_running must have been released');
        expect(h.c.paused.value, isFalse);
      });
    });

    test('reset() cancels a pending sweep and clears paused (account switch)', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        h.c.reset();
        expect(h.c.paused.value, isFalse);
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(h.probes, 0);
        expect(h.sweeps, 0);
      });
    });

    test('reset() while a run is IN FLIGHT: the old run is a no-op and the new owner still gets retried',
        () {
      fakeAsync((async) {
        final gate = Completer<bool>();
        final h = _Harness()..probeGate = gate;
        h.fail();
        async.elapse(const Duration(seconds: 31)); // run 1 parked on the probe
        expect(h.probes, 1);

        h.c.reset(); // account switch mid-probe
        h.probeGate = null;
        h.fail(); // the NEW owner's first failure — must not be swallowed
        expect(h.c.paused.value, isTrue);

        gate.complete(true); // the OLD run wakes up
        async.flushMicrotasks();
        expect(h.sweeps, 0, reason: 'a stale run must not sweep under the new owner');
        expect(h.c.paused.value, isTrue, reason: 'nor clear the new owner\'s flag');

        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isFalse);
      });
    });
  });

  group('wiring (presence — comment-stripped; behavior is covered above)', () {
    String strip(String s) => s
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final svc =
        strip(File('lib/core/services/sync_service.dart').readAsStringSync());

    test('_reportSyncFailure counts and forwards every failure before anything else', () {
      final i = svc.indexOf('Future<void> _reportSyncFailure(');
      expect(i, greaterThan(-1));
      final body = svc.substring(i, i + 1200);
      expect(
          body.contains('SyncRetryController.instance.noteFailure(error, opType: opType)'),
          isTrue);
    });

    test('the controller sweeps with weeklyFullSync and probes with probeBackendReachable', () {
      expect(svc.contains('probe: probeBackendReachable'), isTrue);
      expect(svc.contains('sweep: weeklyFullSync'), isTrue);
    });

    test('_onUserChanged resets the controller', () {
      final i = svc.indexOf('void _onUserChanged()');
      final j = svc.indexOf('final HiveService _hive', i);
      expect(svc.substring(i, j).contains('SyncRetryController.instance.reset()'), isTrue);
    });

    test('weeklyFullSync SERIALISES behind an in-flight sweep and stamps ONLY on a clean one', () {
      final m = RegExp(r'Future<void>\s+weeklyFullSync\(\)\s*async\s*\{')
          .firstMatch(svc);
      expect(m, isNotNull);
      final next = svc.indexOf(RegExp(r'\n  Future<'), m!.end);
      final body = svc.substring(m.start, next);
      expect(body.contains('_weeklyFullSyncRunning'), isTrue, reason: 'serialisation slot');
      // The code breaks this comparison across two lines — match whitespace-tolerantly
      // (round-2 R2a P1-4: a literal-string match was -1 against the plan's own code).
      final guard = RegExp(r'retryableFailureSeq\s*==\s*retryableFailuresBefore')
          .firstMatch(body);
      final stamp = body.indexOf('_setTimestamp(_lastFullSyncKey)');
      expect(guard, isNotNull);
      expect(stamp, greaterThan(guard!.start),
          reason: 'the stamp sits BEHIND the clean-sweep guard');
      // The baseline must be read AFTER waiting for the previous sweep, or the
      // previous sweep's failures would be charged to this one.
      final wait = body.indexOf('await prior');
      final baseline = body.indexOf('final retryableFailuresBefore');
      expect(wait, greaterThan(-1), reason: 'waits for the previous sweep');
      expect(baseline, greaterThan(wait),
          reason: 'baseline taken after the wait');
      expect(body.contains('finally'), isTrue, reason: 'the slot must always be released');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/sync_retry_controller_test.dart`
Expected: FAIL to compile — `sync_retry_controller.dart` does not exist.

- [ ] **Step 3: Implement the controller**

Create `lib/core/services/sync_retry_controller.dart`:

```dart
/// Re-runs the changed-rows-only push sweep after an OUTAGE-SHAPED push failure.
///
/// closes-diagnose e5b2a9. Every domain push already goes through
/// `SyncSkipIndex.pushIfChanged`, which records a row as sent only after a
/// CONFIRMED push — so re-running the sweep sends exactly what is still unsent.
/// What was missing is the TRIGGER: a failed push only retried on the next write
/// or the next app launch, and the connectivity trigger in `SyncStateNotifier`
/// cannot fire when only the backend is down (the device is online).
///
/// Gate: a retry first PROBES that the backend answers (one tiny request), so a
/// still-down server costs one probe per backoff step, not a full sweep. A cap
/// of [kSyncRetryMaxAttempts] failed runs ends the cycle (the next failure
/// starts a fresh one), so a permanently-broken path cannot loop.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'hive_service.dart';

/// Wait before retry attempt N (0-indexed). Capped at the last entry.
const List<Duration> kSyncRetrySchedule = [
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
];

/// Failed runs before the cycle ends: 30 s, 2 m, 10 m, 10 m, 10 m, 10 m.
const int kSyncRetryMaxAttempts = 6;

/// A banner "Retry" tapped repeatedly is ONE probe+sweep, not N.
const Duration kSyncRetryManualCooldown = Duration(seconds: 10);

/// A sweep that has not returned by now is abandoned as a FAILED run, so a
/// hung request can never wedge the controller in `_running` forever.
const Duration kSyncRetrySweepCeiling = Duration(minutes: 5);

Duration syncRetryDelay(int attempt,
        {List<Duration> schedule = kSyncRetrySchedule}) =>
    schedule[attempt.clamp(0, schedule.length - 1)];

// A 3-digit HTTP status as it appears in the real error text:
//   `PostgrestException(message: error code: 521\n, code: 521, ...)`
//   `FunctionException(status: 503, ...)`.
// `(?!\d)` keeps 5-digit Postgres codes (23505, 57014) and UUID fragments from
// matching; the leading `code`/`status` word keeps a UUID's "401" from matching.
final RegExp _httpStatusRe =
    RegExp(r'(?:status(?:code)?|code)\W{0,4}(\d{3})(?!\d)', caseSensitive: false);

/// The HTTP status carried in [error]'s text, if any.
int? httpStatusOfError(Object error) {
  final m = _httpStatusRe.firstMatch(error.toString());
  return m == null ? null : int.tryParse(m.group(1)!);
}

// Outage shapes that carry NO HTTP status in the text: socket/DNS/fetch failures
// (all platforms), PostgREST's JSON-bodied 503s (PGRST000-003 — "Could not query
// the database for the schema cache"), and PG overload codes.
final RegExp _outageTextRe = RegExp(
  r'(socketexception|failed host lookup|connection (refused|reset|closed|abort|terminated)|network is unreachable|software caused connection abort|failed to fetch|load failed|xmlhttprequest error|timeoutexception|timed out|pgrst00[0-3]|code: ?(?:57014|57p0[123]|53300)\b)',
  caseSensitive: false,
);

/// A failure that means "the backend or the network did not answer", i.e. one a
/// later retry can plausibly fix. 4xx (400/401/403/404/409/422) and PG `23xxx` /
/// `42703` are the server ANSWERING "no" — retrying the same payload cannot
/// succeed. Unknown shapes are NOT retried (an unclassified error must not be
/// able to loop).
bool isOutageShapedFailure(Object error) {
  if (error is TimeoutException) return true;
  final status = httpStatusOfError(error);
  if (status != null) return status >= 500 || status == 408 || status == 429;
  return _outageTextRe.hasMatch(error.toString());
}

/// `_reportSyncFailure` also receives restore, realtime, onboarding and
/// bookkeeping failures. Only a PUSH failure can be fixed by re-running the push
/// sweep. `restore_sync_*` is a push op wrapped by `_safeRestoreOp` in
/// `weeklyFullSync` that hit its 45 s ceiling; `sync_fitness_summary` is a READ.
bool isPushFailureOpType(String opType) =>
    opType == 'weekly_full_sync' ||
    opType.startsWith('upsert_') ||
    opType.startsWith('restore_sync_') ||
    (opType.startsWith('sync_') && opType != 'sync_fitness_summary');

/// §4.6 kill-switch predicate: only a literal `true` disables.
bool isSyncRetryDisabled(Object? raw) => raw == true;

class SyncRetryController {
  SyncRetryController({
    required Future<bool> Function() probe,
    required Future<void> Function() sweep,
    this.schedule = kSyncRetrySchedule,
    this.maxAttempts = kSyncRetryMaxAttempts,
    Duration Function(Duration)? jitter,
    bool Function()? isDisabled,
  })  : _probe = probe,
        _sweep = sweep,
        _jitter = jitter ?? _defaultJitter,
        _isDisabled = isDisabled ?? _configDisabled;

  /// The app-wide instance. Callbacks are bound by `SyncService`
  /// (`bind`) so this file never imports the service (no cycle).
  static final SyncRetryController instance = SyncRetryController(
    probe: () async => false,
    sweep: () async {},
  );

  static final Random _rng = Random();

  /// ±20% so every device that failed in the same outage does not re-probe in
  /// the same second when the backend returns (d7b1f8 saw ~15 requests released
  /// within 400 ms).
  static Duration _defaultJitter(Duration d) => Duration(
      milliseconds:
          (d.inMilliseconds * (0.8 + _rng.nextDouble() * 0.4)).round());

  static bool _configDisabled() {
    try {
      return isSyncRetryDisabled(
          HiveService.instance.configBox.get('disable_sync_retry_sweep'));
    } catch (_) {
      return false;
    }
  }

  Future<bool> Function() _probe;
  Future<void> Function() _sweep;
  final List<Duration> schedule;
  final int maxAttempts;
  final Duration Function(Duration) _jitter;
  final bool Function() _isDisabled;

  /// True from the first accepted failure until a sweep completes cleanly (or
  /// the cap ends the cycle). Drives the "sync paused" banner.
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);

  int _retryableFailureSeq = 0;

  /// Monotonic count of ACCEPTED failures. `weeklyFullSync` compares it before
  /// and after a sweep to decide whether the sweep was clean enough to stamp
  /// `last_full_sync`.
  int get retryableFailureSeq => _retryableFailureSeq;

  Timer? _timer;
  bool _running = false;
  bool _manualCooling = false;
  int _attempt = 0;
  int _failuresThisRun = 0;

  /// Bumped by `_fire` and by `reset`. A run whose captured value no longer
  /// matches is stale (account switch) and must touch nothing.
  int _gen = 0;

  void bind({
    required Future<bool> Function() probe,
    required Future<void> Function() sweep,
  }) {
    _probe = probe;
    _sweep = sweep;
  }

  /// Called from the single failure funnel (`SyncService._reportSyncFailure`).
  void noteFailure(Object error, {required String opType}) {
    if (_isDisabled()) return;
    // A String is a telemetry-queue REPLAY of an OLD failure, not a live one.
    if (error is String) return;
    if (!isPushFailureOpType(opType)) return;
    if (!isOutageShapedFailure(error)) return;
    _retryableFailureSeq++;
    if (_running) {
      _failuresThisRun++;
      return;
    }
    if (!paused.value) paused.value = true;
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_timer != null) return;
    _timer = Timer(
      _jitter(syncRetryDelay(_attempt, schedule: schedule)),
      () => unawaited(_fire()),
    );
  }

  /// "Retry" tap on the banner: run now instead of waiting for the timer.
  /// Taps inside [kSyncRetryManualCooldown] of the previous one are ignored,
  /// so a frustrated user cannot turn the banner into a request cannon.
  Future<void> retryNow() async {
    if (_manualCooling) return;
    _manualCooling = true;
    Timer(kSyncRetryManualCooldown, () => _manualCooling = false);
    _timer?.cancel();
    _timer = null;
    await _fire(manual: true);
  }

  void _afterFailedRun() {
    if (_attempt >= maxAttempts) {
      // End of the cycle: stop claiming "retrying". The data is still unsent;
      // the next failure, the next launch's sweep (unstamped) or the next
      // write's fan-out picks it up.
      _attempt = 0;
      paused.value = false;
      return;
    }
    _scheduleNext();
  }

  Future<void> _fire({bool manual = false}) async {
    _timer = null;
    if (_running) return;
    _running = true;
    _failuresThisRun = 0;
    final gen = ++_gen;
    try {
      final reachable = await _probe();
      if (gen != _gen) return;
      if (!reachable) {
        if (!manual) _attempt++; // a manual tap must not escalate the backoff
        _afterFailedRun();
        return;
      }
      await _sweep().timeout(kSyncRetrySweepCeiling);
      if (gen != _gen) return;
      if (_failuresThisRun == 0) {
        _attempt = 0;
        paused.value = false;
      } else {
        _attempt++;
        _afterFailedRun();
      }
    } catch (_) {
      if (gen == _gen) {
        _attempt++;
        _afterFailedRun();
      }
    } finally {
      if (gen == _gen) _running = false;
    }
  }

  /// Account switch: drop everything. Bumping [_gen] makes an in-flight run's
  /// tail a no-op, and clearing [_running] here lets the NEW owner's first
  /// failure schedule normally instead of being swallowed as "a run is active".
  void reset() {
    _gen++;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _attempt = 0;
    _failuresThisRun = 0;
    _manualCooling = false;
    paused.value = false;
  }
}
```

- [ ] **Step 4: Add the probe + wire the controller into `SyncService`**

Create `lib/core/services/sync/sync_resilience.dart`:

```dart
part of '../sync_service.dart';

/// closes-diagnose e5b2a9 — outage-resilience entry point for
/// `SyncRetryController` (the reachability probe).
extension SyncServiceResilience on SyncService {
  /// One tiny RLS-safe request: does the backend ANSWER at all? A server that
  /// answers "no" (401/RLS/PGRST) is reachable; a 5xx / Cloudflare 52x /
  /// PGRST00x / socket / the 8 s ceiling is not. Runs only while a failure is
  /// pending, so steady-state cost is zero. ONE request per probe: the SDK
  /// otherwise retries a GET that returns 503/520 three more times (1 s, 2 s,
  /// 4 s — `postgrest` `_executeWithRetry`) and 503 is the real PGRST002
  /// outage shape, so the probe query opts out with `.retry(enabled: false)`.
  Future<bool> probeBackendReachable() async {
    try {
      return await _probeBackend()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeBackend() async {
    try {
      // A stale token 401s the probe; a 401 still counts as "answered", but
      // refreshing first keeps the probe honest (CLAUDE.md §4.4 rule 9).
      await _supabase.ensureFreshToken();
      final uid = _supabase.currentUser?.id;
      if (uid == null) return false;
      final q = _supabase.client
          .from('users')
          .select('id')
          .eq('id', uid)
          .limit(1)
          .retry(enabled: false);
      // PostgREST builders are thenables — flatten before awaiting.
      await Future<dynamic>.value(q);
      return true;
    } catch (e) {
      // Only a PostgREST error that is NOT outage-shaped means the server
      // answered. Anything else (socket, timeout, unknown) = unreachable.
      return e is PostgrestException && !isOutageShapedFailure(e);
    }
  }
}
```

In `lib/core/services/sync_service.dart`:

1. After `part 'sync/sync_realtime.dart';` add `part 'sync/sync_resilience.dart';`.
2. Line 5: change `show FunctionResponse` to `show FunctionResponse, PostgrestException` (the part file's `is PostgrestException` needs it). After `import 'package:icanbefitter/core/services/sync_queue.dart';` add ONLY this task's import (Task 5 adds its own with the file it creates — an import of a not-yet-created file is a compile error and an unused one fails the push):
```dart
import 'package:icanbefitter/core/services/sync_retry_controller.dart';
```
3. Next to the coalescer fields (`SyncCoalescer _workoutCoalescer = …`), add:
```dart
  /// closes-diagnose e5b2a9 — the tail of the `weeklyFullSync` queue, so a
  /// retry sweep and a launch sweep run ONE AFTER THE OTHER instead of
  /// overlapping. Serialised, not joined: a retry that joined an older
  /// in-flight sweep would report "swept after recovery" about a sweep that
  /// started BEFORE the server came back.
  Future<void>? _weeklyFullSyncRunning;
```
4. In `_registerLifecycle()`, after `SingletonLifecycleRegistry.register('SyncService', _onUserChanged);`:
```dart
    // closes-diagnose e5b2a9 — bind the retry controller. The sweep is
    // `weeklyFullSync`: every domain through SyncSkipIndex, so it re-sends only
    // rows still unsent (plus ~6 unconditional requests, D2).
    SyncRetryController.instance.bind(
      probe: probeBackendReachable,
      sweep: weeklyFullSync,
    );
```
5. At the END of `_onUserChanged()` (after `_snapshotCoalescer = SyncCoalescer();`):
```dart
    // closes-diagnose e5b2a9 — a pending retry / paused flag / queued sweep
    // belongs to the PREVIOUS owner.
    SyncRetryController.instance.reset();
    _weeklyFullSyncRunning = null;
```
6. At the very top of `_reportSyncFailure`'s body — immediately before the existing `// Crashlytics ONLY here (diagnose …` comment:
```dart
    // closes-diagnose e5b2a9 — single funnel for every push AND restore
    // failure. Tell the retry controller, which accepts only outage-shaped
    // PUSH failures.
    try {
      SyncRetryController.instance.noteFailure(error, opType: opType);
    } catch (_) {}
```
7. In `weeklyFullSync()` — **keep the signature line and the existing `try {` unchanged** (`sync_template_before_schedule_order_test.dart:63` extracts the body by that regex). Three insertions:
   a. Immediately after the method's opening `{`, before `try {`:
```dart
    // closes-diagnose e5b2a9 — run AFTER any in-flight sweep (a retry sweep and
    // a launch sweep must not overlap, and neither may inherit the other's
    // failures). Each caller queues behind the previous tail; the slot is
    // released in `finally`. The baseline is read AFTER the wait.
    final prior = _weeklyFullSyncRunning;
    final done = Completer<void>();
    final doneFuture = done.future;
    _weeklyFullSyncRunning = doneFuture;
    if (prior != null) {
      try {
        await prior;
      } catch (_) {}
    }
    final retryableFailuresBefore =
        SyncRetryController.instance.retryableFailureSeq;
```
   b. Replace `await _setTimestamp(_lastFullSyncKey);` with:
```dart
      // closes-diagnose e5b2a9 — stamp the 1-day sweep as done ONLY if no
      // outage-shaped push failure occurred during it. Pre-fix a sweep in which
      // every op failed was stamped "done" and the next launch skipped it.
      // (A deterministic failure never moves the counter, so it cannot force a
      // re-sweep on every launch.)
      if (SyncRetryController.instance.retryableFailureSeq ==
          retryableFailuresBefore) {
        await _setTimestamp(_lastFullSyncKey);
      }
```
   c. Append a `finally` after the existing `catch (e, st) { … }` block (no re-indent of the body):
```dart
    finally {
      if (identical(_weeklyFullSyncRunning, doneFuture)) {
        _weeklyFullSyncRunning = null;
      }
      done.complete();
    }
```

- [ ] **Step 5: Run + whole-tree analyze + neighbours**

Add `'probeBackendReachable', // e5b2a9 retry-controller probe` to `expectedPublicApi` in `test/contracts/sync_service_public_api_snapshot_test.dart` (the exact-set snapshot also scans every `part of` file under `lib/core/services/sync/`).
Run: `flutter test test/contracts/sync_retry_controller_test.dart test/contracts/sync_template_before_schedule_order_test.dart test/contracts/sync_queue_auto_drain_test.dart test/contracts/sync_service_public_api_snapshot_test.dart test/sync/sync_telemetry_test.dart`
Expected: PASS. (`sync_telemetry_test.dart` source-counts the H-42 recordNonFatal/`_reportSyncFailure` pairs across ALL sync part files via `loadSyncServiceSource()` — the new hook lines must not disturb it; ~47 tests load that concatenated source, so the new part file is in their input set.)
Run: `flutter analyze lib/` → `No issues found!` (the new `part` file must compile into the library; `PostgrestException` resolves ONLY because Step 4 item 2 widened the `show` clause — the existing import was `show FunctionResponse`).
Run: `dart run scripts/check_sot_registry_parity.dart` → **expected RED here** for the `sync_service.dart` entries listed in Global Constraints (inserted lines shift them). Do NOT repoint now — repoint ONCE in Task 6 after every task's edits are in (a mid-batch repoint goes stale again). The gate must be green before Task 7.
Run: `git diff -U0 -- '*.dart' | grep -n '^+.*/\*'` → nothing.

- [ ] **Step 6: Mutation proof (each mutation must still COMPILE; read the failure text)**

1. `_fire`: delete the `return;` after `_afterFailedRun()` in the `!reachable` branch → expect "unreachable probe does NOT sweep" RED.
2. `noteFailure`: delete the `isOutageShapedFailure` line → "non-retryable never schedules" + the counter test RED.
3. `noteFailure`: delete the `error is String` line → the filtering test RED.
4. `reset()`: delete `_gen++;` → the "IN FLIGHT" test RED (old run sweeps).
5. `_fire`: remove the `if (!manual)` guard (always `_attempt++`) → "retryNow … does NOT advance" RED.
6. `_afterFailedRun`: delete the cap `if` block → "the cap" RED (probes ≫ 6).
7. `isPushFailureOpType`: drop the `!= 'sync_fitness_summary'` clause → allowlist test RED.
8. `sync_service.dart`: change the comparison `retryableFailureSeq == retryableFailuresBefore` (it spans two lines — edit the second line to `true`) so the stamp is unconditional → wiring test RED; delete the `noteFailure` hook line → wiring RED; move `final retryableFailuresBefore` ABOVE the `await prior` block → the wait-before-baseline assertion RED.
9. `retryNow`: delete the `if (_manualCooling) return;` line → "retryNow() spam" RED.
10. `_fire`: delete `.timeout(kSyncRetrySweepCeiling)` → "a sweep that never completes" RED (the run never ends; `paused` stays true and `sweeps` stays 1).
Record red counts per mutation; restore by reverse-edit; re-run green.

---

### Task 3: (moved out — Unit C, pull-on-resume, is Phase 1b)

Intentionally empty so Task 4–8 numbers (cited across the plan, the diagnose doc and the closure ledger) stay stable. The full former Task 3 text, with every round-2 finding attached, is `docs/superpowers/plans/2026-10-01-resilient-client-phase1b-resume-pull-DRAFT.md` (**NOT converged — do not execute**; it needs its own plan + two review rounds, CLAUDE.md §4.12.1).

---

### Task 4: "Sync paused" banner state (Unit D)

**Symptom:** a failed push is invisible; the user cannot tell their data has not synced.
**Writer/reader:** writer = `SyncRetryController.paused` (Task 2); reader = `SyncStateNotifier._stateFor` (`sync_state_provider.dart:144`) → `SyncBanner` (`shared/widgets/sync_banner.dart:24-31`). Existing structural pins to keep green (`test/contracts/sync_queue_auto_drain_test.dart`, all slice-based): `_stateFor` 600-char slice must contain `_bannerGraceDisabled`, `syncBannerDisplayCount(`, `return const SyncIdle();`, `SyncQueued(rawCount)`; the FIRST `ref.onDispose(` 400-char slice must contain `_displayTimer?.cancel()`; the first `_drainTimer =` must precede `_displayTimer =`; the `_connectivitySub =` 400-char slice must not contain `force: true`; the `retryNow` 500-char slice must contain `_forceRetryDisabled`, `drain(force: true)`, `SyncQueue.instance.drain()`. **Every edit below is placed so those windows only gain text AFTER their last pinned token.**

**Files:**
- Modify: `lib/shared/providers/sync_state_provider.dart`, `lib/shared/widgets/sync_banner.dart`
- Test: `test/contracts/sync_paused_state_test.dart` (create)

**Interfaces:**
- Produces: `class SyncPaused extends SyncState`; `SyncStateNotifier.retryPausedSync()`.
- Consumes: `SyncRetryController.instance.paused`, `.retryNow()`.

- [ ] **Step 1: Write the failing test**

Create `test/contracts/sync_paused_state_test.dart`:

```dart
// test/contracts/sync_paused_state_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit D). While the backend is paused the
// banner says so; the existing queue-based states are unchanged.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/providers/sync_state_provider.dart';
import 'package:icanbefitter/shared/widgets/sync_banner.dart';

class _Fixed extends SyncStateNotifier {
  _Fixed(this._s);
  final SyncState _s;
  @override
  SyncState build() => _s; // no connectivity/timer side effects in a unit test
}

void main() {
  group('SyncBanner', () {
    Future<void> pump(WidgetTester t, SyncState s) async {
      await t.pumpWidget(ProviderScope(
        overrides: [syncStateProvider.overrideWith(() => _Fixed(s))],
        child: const MaterialApp(home: Scaffold(body: SyncBanner())),
      ));
    }

    testWidgets('SyncPaused renders the reassuring copy', (t) async {
      await pump(t, const SyncPaused());
      expect(find.textContaining('Sync paused'), findsOneWidget);
      expect(find.textContaining('data is safe'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('SyncIdle renders nothing', (t) async {
      await pump(t, const SyncIdle());
      expect(find.textContaining('Sync paused'), findsNothing);
      expect(find.textContaining('waiting to sync'), findsNothing);
    });

    testWidgets('MIRROR: SyncQueued still renders its own copy, not the paused one', (t) async {
      await pump(t, const SyncQueued(2));
      expect(find.text('2 changes waiting to sync'), findsOneWidget);
      expect(find.textContaining('Sync paused'), findsNothing);
    });
  });

  group('wiring (presence — slice-scoped, comment-stripped)', () {
    String strip(String s) => s
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final src = strip(
        File('lib/shared/providers/sync_state_provider.dart').readAsStringSync());

    test('_stateFor checks the paused flag FIRST and returns SyncPaused', () {
      final i = src.indexOf('SyncState _stateFor(');
      expect(i, greaterThan(-1));
      final body = src.substring(i, i + 600);
      final paused = body.indexOf('SyncRetryController.instance.paused.value');
      final empty = body.indexOf('if (rawCount == 0)');
      expect(paused, greaterThan(-1), reason: 'inside _stateFor, not elsewhere in the file');
      expect(body.contains('SyncPaused()'), isTrue);
      expect(paused, lessThan(empty), reason: 'paused must outrank the queue states');
    });

    test('build() listens to the paused notifier and removes the listener in the EXISTING onDispose', () {
      expect(src.contains('paused.addListener('), isTrue);
      final d = src.indexOf('ref.onDispose(');
      final tail = src.substring(d, src.indexOf('return _stateFor(', d));
      expect(tail.contains('paused.removeListener('), isTrue,
          reason: 'the removal must live in the first onDispose block');
    });

    test('a connectivity restore kicks the retry controller only while paused', () {
      final c = src.indexOf('_connectivitySub =');
      final body = src.substring(c, c + 700);
      expect(body.contains('SyncRetryController.instance.retryNow()'), isTrue);
      expect(body.contains('paused.value'), isTrue);
    });

    test('the banner tap kicks the controller through the notifier', () {
      expect(src.contains('Future<void> retryPausedSync()'), isTrue);
      final b = strip(File('lib/shared/widgets/sync_banner.dart').readAsStringSync());
      expect(b.contains('retryPausedSync()'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails** — `flutter test test/contracts/sync_paused_state_test.dart` → FAIL to compile (`SyncPaused` undefined).

- [ ] **Step 3: Implement the state**

In `lib/shared/providers/sync_state_provider.dart`:

1. Add `import '../../core/services/sync_retry_controller.dart';` after `import '../../core/services/sync_queue.dart';`.
2. After `class SyncQueued extends SyncState { … }`:
```dart
/// The backend stopped answering (outage-shaped push failure) and a retry is
/// pending — closes-diagnose e5b2a9. Distinct from [SyncQueued]: that is "N ops
/// are waiting"; this is "the server is not reachable right now".
class SyncPaused extends SyncState {
  const SyncPaused();
}
```
3. In `_stateFor`, add ONE line as the first statement (the existing four lines stay verbatim after it):
```dart
    if (SyncRetryController.instance.paused.value) return const SyncPaused();
```
4. In `build()`, inside the connectivity listener, AFTER the existing `if (shouldDrainOnConnectivityChange(results)) { … }` block (still inside the listener callback):
```dart
      // e5b2a9 — connectivity came back while pushes are paused: retry now
      // instead of waiting out a 10-minute backoff step (offline case).
      if (shouldDrainOnConnectivityChange(results) &&
          SyncRetryController.instance.paused.value) {
        unawaited(SyncRetryController.instance.retryNow());
      }
```
5. In `build()`, AFTER the display-aging timer block and BEFORE `ref.onDispose(() {`:
```dart
    // closes-diagnose e5b2a9 — surface the retry controller's paused flag.
    SyncRetryController.instance.paused.addListener(_onPausedChanged);
```
and inside the EXISTING `ref.onDispose(() { … })` block, as its LAST statement (after `_displayTimer = null;`):
```dart
      SyncRetryController.instance.paused.removeListener(_onPausedChanged);
```
and add the member next to `_onCount`:
```dart
  void _onPausedChanged() {
    state = _stateFor(SyncQueue.instance.pendingCountSync);
  }
```
6. AFTER `retryNow()` (new LAST member — `retryNow`'s pinned slice is unaffected):
```dart
  /// Banner tap while paused: kick the push retry controller AND the queue drain.
  Future<void> retryPausedSync() async {
    unawaited(SyncRetryController.instance.retryNow());
    await retryNow();
  }
```

- [ ] **Step 4: Render it**

In `lib/shared/widgets/sync_banner.dart` change the `switch` to
```dart
    return switch (state) {
      SyncIdle() => const SizedBox.shrink(),
      SyncQueued(:final pendingCount) => _QueuedBanner(count: pendingCount),
      SyncPaused() => const _PausedBanner(),
    };
```
and append (same structure/colors as `_QueuedBanner`):
```dart
class _PausedBanner extends ConsumerWidget {
  const _PausedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.accentTint,
      child: InkWell(
        onTap: () => ref.read(syncStateProvider.notifier).retryPausedSync(),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sync paused — your data is safe. Retrying…',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
              Text(
                'Retry',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```
(Copy rule from the file header — no "restart the app". Reassurance + action, no jargon.)

- [ ] **Step 5: Run + analyze + neighbours**

Run: `flutter test test/contracts/sync_paused_state_test.dart test/contracts/sync_queue_auto_drain_test.dart` → PASS. `flutter analyze lib/` → no warnings (a new `SyncState` subtype makes any other exhaustive `switch` on it a COMPILE error — analyze lists them; only `sync_banner.dart` consumes it).

- [ ] **Step 6: Mutation proof**

1. Delete the paused-first line in `_stateFor` → "checks the paused flag FIRST" RED.
2. Move that line BELOW `if (rawCount == 0)` → same test RED (ordering leg).
3. Move the `removeListener` out of the first `onDispose` → wiring RED.
4. Delete the connectivity kick → wiring RED.
5. Change `_PausedBanner`'s copy → "reassuring copy" RED. (Deleting the `SyncPaused()` switch arm is a COMPILE error — not a valid proof.)

---

### Task 5: Stop logging every successful restore/sync op (Unit E — closes OI-151)

**Symptom (measured live 2026-10-01):** `client_errors` holds 7,047 rows; **5,479 (78%) are `event` rows and 4,043 (57%) are `restore_op_done`** — one INSERT per successful `_safeRestoreOp` (`sync_service.dart:2567`). `pg_stat_statements` ranks `INSERT INTO client_errors` #2 by total time. Task 2 would multiply it: `weeklyFullSync` runs ~20 `_safeRestoreOp`s per retry sweep. **OI-151** (`docs/audit/open_issues.md:2530`, OPEN, "a PRE-LAUNCH tuning decision… wants a call on what breadcrumb granularity is worth paying for") is exactly this: this unit IS that call (log only ops ≥ 2 s).
**Writer/reader:** writer = `_safeRestoreOp` success branch (`sync_service.dart:2565-2570`); readers = the slow-op diagnosis in `docs/diagnoses/2026-05-19-restoring-screen-slow-no-telemetry-4f8e2d.md`, the pin `test/contracts/streak_freeze_refill_telemetry_test.dart:90`, the debugging-skill telltale `.claude/skills/debugging/bug-classes.md:474`, and the founder digest / admin-bot `client_errors_7d` count (will step down ~57% — expected, say so in the diagnose doc). The diagnostic value is the SLOW op, not the fast ones.
**Recurrence check:** bug-class 2.13 (telemetry flood).

**Files:**
- Create: `lib/core/services/restore_telemetry_policy.dart`
- Modify: `lib/core/services/sync_service.dart` (`_safeRestoreOp` success branch; kill-switch getter)
- Modify: `docs/audit/open_issues.md` + `docs/audit/closed_issues.md` (OI-151 is MOVED, not flagged in place)
- Test: `test/contracts/restore_op_done_filter_test.dart` (create)

**Interfaces:**
- Produces: `kRestoreOpDoneSlowThreshold` (2 s), `shouldLogRestoreOpDone(Duration elapsed, {required bool alwaysLog})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/restore_op_done_filter_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit E), closes-oi OI-151. A fast
// successful restore/sync op must not write a client_errors row; a SLOW one
// still does (that is the signal restore_op_done exists for); the kill-switch
// restores log-everything.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/restore_telemetry_policy.dart';

void main() {
  test('fast ops are not logged', () {
    expect(
        shouldLogRestoreOpDone(const Duration(milliseconds: 111), alwaysLog: false),
        isFalse);
  });
  test('boundary: 1999 ms not logged, 2000 ms logged', () {
    expect(
        shouldLogRestoreOpDone(const Duration(milliseconds: 1999), alwaysLog: false),
        isFalse);
    expect(
        shouldLogRestoreOpDone(const Duration(milliseconds: 2000), alwaysLog: false),
        isTrue);
  });
  test('MIRROR: a slow op is always logged', () {
    expect(shouldLogRestoreOpDone(const Duration(seconds: 11), alwaysLog: false),
        isTrue);
  });
  test('kill-switch (alwaysLog) logs even a 1 ms op', () {
    expect(shouldLogRestoreOpDone(const Duration(milliseconds: 1), alwaysLog: true),
        isTrue);
  });

  test('wiring: _safeRestoreOp consults the policy before logging restore_op_done', () {
    final src = File('lib/core/services/sync_service.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final i = src.indexOf("'restore_op_done'");
    expect(i, greaterThan(-1), reason: 'the event itself must still exist');
    final lead = src.substring((i - 260).clamp(0, src.length), i);
    expect(lead.contains('shouldLogRestoreOpDone('), isTrue);
    expect(lead.contains('_restoreOpDoneFilterDisabled'), isTrue);
  });
}
```

- [ ] **Step 2: Run it** → FAIL to compile (`restore_telemetry_policy.dart` missing).

- [ ] **Step 3: Implement**

Create `lib/core/services/restore_telemetry_policy.dart`:

```dart
/// closes-diagnose e5b2a9 / closes-oi OI-151 — which successful restore/sync ops
/// earn a `client_errors` row.
///
/// `restore_op_done` was written for EVERY successful op, so 57% of
/// `client_errors` (4,043 of 7,047 rows, 2026-10-01) was "this worked in 80 ms".
/// The row exists to answer "which op is the long pole" (4f8e2d), which only
/// slow ops can. `restore_started` / `restore_completed` bookends are unchanged
/// and still bracket every restore; failures are unchanged.
library;

const Duration kRestoreOpDoneSlowThreshold = Duration(seconds: 2);

bool shouldLogRestoreOpDone(Duration elapsed, {required bool alwaysLog}) =>
    alwaysLog || elapsed >= kRestoreOpDoneSlowThreshold;
```

In `sync_service.dart` add `import 'package:icanbefitter/core/services/restore_telemetry_policy.dart';` (this task creates and uses it), then replace the success branch in `_safeRestoreOp`
```dart
      sw.stop();
      unawaited(ErrorTelemetry.logEvent(
        'restore_op_done',
        message: 'op=$label ms=${sw.elapsedMilliseconds}',
      ));
```
with
```dart
      sw.stop();
      // closes-diagnose e5b2a9 — only SLOW ops earn a row (kill-switch
      // `disable_restore_op_done_filter` restores log-everything).
      if (shouldLogRestoreOpDone(sw.elapsed,
          alwaysLog: _restoreOpDoneFilterDisabled)) {
        unawaited(ErrorTelemetry.logEvent(
          'restore_op_done',
          message: 'op=$label ms=${sw.elapsedMilliseconds}',
        ));
      }
```
and next to `_restoreOpTimeoutEnabled` add:
```dart
  bool get _restoreOpDoneFilterDisabled {
    try {
      return _hive.configBox.get('disable_restore_op_done_filter') == true;
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 4: Repoint the neighbour pin (do not loosen)**

Run `flutter test test/contracts/streak_freeze_refill_telemetry_test.dart test/contracts/restore_op_timeout_behavioral_test.dart`. `streak_freeze_refill_telemetry_test.dart:90-94` greps `'restore_op_done'` + the `{op, ms}` message shape — both unchanged, so it should stay green. If it asserts UNCONDITIONAL emission, repoint it to "emits `restore_op_done` {op, ms} for ops the policy accepts" — the assertion still holds, it moved.

- [ ] **Step 5: Close OI-151 on the board (MOVE it)** — the board has no `Closed:` field (`open_issues.md:22-25`: status vocabulary `OPEN` / `IN_PROGRESS` / `CLOSED — shipped, with hex diagnose id + commit SHA`). Closed entries live in `docs/audit/closed_issues.md` (shape: `closed_issues.md:5237-5245`, OI-245). In the SAME commit as the code: cut the whole `## OI-151` section out of `open_issues.md`, append it to `closed_issues.md` with `- **Status**: CLOSED · <date> · diagnose `e5b2a9` · branch `claude/resilient-client-phase1` (SHA after merge) — log only ops ≥ 2 s; kill-switch `disable_restore_op_done_filter``. Leaving it in `open_issues.md` as CLOSED breaks the board convention (§5: 0 CLOSED entries on the open board), and copying instead of moving trips `check_oi_numbering_unique.dart` Check A (one OI on both boards). Pre-commit regenerates `OPEN_INDEX.md` itself (`pre-commit.sh:202-209`). The commit trailer `closes-oi: OI-151` is enforced by `scripts/check_closes_oi_cited.dart` at commit-msg.

- [ ] **Step 6: Run + analyze + mutation proof**

`flutter test test/contracts/restore_op_done_filter_test.dart` PASS; `flutter analyze lib/` clean; `dart run scripts/check_sot_registry_parity.dart` is expected RED for the shifted `sync_service.dart` entries — repointed ONCE in Task 6; `/*` grep clean. Mutations: (1) `>=` → `>` → boundary RED; (2) drop `alwaysLog ||` → kill-switch RED; (3) delete the `if` wrapper in `_safeRestoreOp` → wiring RED.

---

### Task 6: Registry, diagnose doc, nested docs, skills (rule 21/22 + §5)

**Files:**
- Modify: `docs/sot_registry.yaml` (2 new concepts + repointed ranges), `lib/core/services/CLAUDE.md`, `lib/features/auth/CLAUDE.md`, `docs/architecture/sync.md`, `.claude/skills/debugging/bug-classes.md`, `.claude/skills/debugging/SKILL.md`
- Create: `docs/diagnoses/2026-10-01-supabase-api-outage-client-resilience-e5b2a9.md`

- [ ] **Step 1: Read the validator first** (`feedback_check_validators_before_drafting`): `sed -n 1,160p scripts/validate_diagnose_doc_lib.dart`, then copy `docs/diagnoses/2026-08-13-auth-refresh-no-inflight-join-d7b1f8.md` as the template. The frontmatter MUST carry ALL of (R2d, read from `validate_diagnose_doc_lib.dart:8-25`): `bug_id, date, batch, status, symptom, concept, sot_registry_entry, writers, readers, hive_key_prefix, hive_key_formula, sync_methods, restore_methods, cloud_table, cloud_columns, contract_test_path, ist_handling, provider_invalidations, telemetry_op_types, cross_account_guard, forbidden_patterns_checked, proposed_fix, regression_test_planned, touched_layers_checked, impact_analysis`, plus `blast_radius: platform` (docs dated ≥ 2026-05-28). Traps: (a) **no `TBD`/`TODO`/`tbd`/`todo` substring anywhere in the frontmatter** (including inside a word); (b) every `{ file:, line: }` in `writers`/`readers`/`ist_handling` must resolve to an existing file with `line ≤` its line count; (c) `touched_layers_checked` needs ≥ 1 entry with `status: verified` or `fixed_in_this_batch` (Tier 1 client `fixed_in_this_batch`; Tier 11 external = the Supabase API outage `verified`, evidence = the `edge_logs` 521/522/504 + `client_errors` composition; Tier 4 data `verified` — `client_errors` 7,047 rows / 4,043 `restore_op_done`; Tier 7 cron `not_applicable`); (d) **`sot_registry_entry: restoring_destination_read_timeout, sync_failure_retry_sweep`** — bare identifier names that must exist in `sot_registry.yaml` (docs dated ≥ 2026-08-01: prose or a dangling name is a HARD violation of `check_sot_registry_citations.dart`), so Step 3's entries land in the same commit; (e) **OMIT `tier:`** — it is not validated; only the literal `s_fix` is read (by batch telemetry) and this batch is not an S-fix. Body: the four units (A, B, D, E), writers/readers named in Tasks 1–5, the **mutation log** (what was mutated, red counts, from each task's mutation step), `related_bugs: [d7b1f8, c2e9f4, b7c2a9, d2e8f4, 4a3b08, 4f8e2d]` + the `recurrence:` text from §4.1.5. State plainly: D1 (no batching), the Unit C split (§4.12.1, Phase 1b, OI-N), the expected ~57% drop in `client_errors_7d`, the kill-switch note (permanent operator switches default ACTIVE — repo precedent `disable_bg_restore`, so a reviewer does not read it as a §4.6 miss), the review-round dispositions tables, and that Android users need a new APK for any of it. `contract_test_path` = the four new test files.
- [ ] **Step 2: Validate** — `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-10-01-supabase-api-outage-client-resilience-e5b2a9.md` → exit 0 (never `sh scripts/_dart_bin.sh …` — sourced-only, exits 64).
- [ ] **Step 3: SoT registry** — FIRST repoint the existing entries this batch shifted: run `dart run scripts/check_sot_registry_parity.dart`, then for EVERY failing `line_range` (known: `sync_service.dart` `:10899` / `:10910` / `:10920` / `:10935` / `:12377` and `auth_session_bootstrapper.dart` `:4874` — see Global Constraints; the gate lists the rest) `grep -n` the cited symbol's NEW line and rewrite the range around it. Rules (R2d, from the script): a BLOCK entry has NO ±5 tolerance (the symbol must be inside `[start,end]`); `endLine > lineCount` is a hard error, so a range may be widened (±40) only on a file long enough — **for the NEW small files use `1-9999`**. Re-run until green. THEN read the neighbouring `restore_completeness` entry (`docs/sot_registry.yaml:2677` onwards) and add two concepts in the same shape (`concept`, `domain: cross_domain`, `behavioral_test_path`, `description`, `writers:` / `readers:` with `file` + `line_range` + `method` + `semantic` + `notes`, `regression_test`, `class_constraints`). **Do NOT write `hive_key_prefix:` / `key_prefix:` in either block** (any non-empty value, even `n/a`, makes Gate 9 demand `test/contracts/<concept>_writer_to_reader_test.dart`; `restore_completeness` has none):
  - `restoring_destination_read_timeout` — writer `auth_session_bootstrapper.dart` `boundDestination` / `resolveBounded`; reader `restoring_screen.dart` `_kickoffRestore` + `_onContinueAnyway`; `behavioral_test_path: test/contracts/restoring_destination_timeout_test.dart`. `class_constraints`: a timeout is never `StartMissionBrief`; the no-evidence path keeps awaiting the original read.
  - `sync_failure_retry_sweep` — writer `sync_service.dart` `_reportSyncFailure` (signal) + `sync_retry_controller.dart` `SyncRetryController`; reader `sync_state_provider.dart` `_stateFor` + `weeklyFullSync` (stamp-on-clean); `behavioral_test_path: test/contracts/sync_retry_controller_test.dart`. `class_constraints`: outage-shaped + push-opType only; capped; the probe is ONE request (`.retry(enabled: false)`).
- [ ] **Step 4: Run the registry gates** — `dart run scripts/check_sot_behavioral_test_paths.dart` and `dart run scripts/check_sot_registry_parity.dart` and `dart run scripts/check_sot_registry_citations.dart` → PASS (Gate 42 resolves every cited path on disk; the three new test files exist from Tasks 1/2).
- [ ] **Step 5: Nested docs** —
  - `lib/core/services/CLAUDE.md`: SoT-table rows for the two concepts + Common-pitfalls rows: *"`_safeRestoreOp` logged one `client_errors` row per success — never use it in a high-frequency path; Unit E now logs only ops ≥ 2 s."*, *"`weeklyFullSync` stamps `last_full_sync` only on a clean sweep and runs serialised behind an in-flight one; the push retry controller accepts only outage-shaped PUSH failures — never widen it to `SyncError.isTransient` (UnknownError is transient → infinite loop)."*, and *"the supabase SDK retries a GET answered 503/520 three more times (1/2/4 s) — a probe or any request that must be ONE request opts out with `.retry(enabled: false)`."* (The budget: this file is 18,922 B against a 18,002 B baseline; the SOFT band crosses at 20,702 B and is silent locally — keep the three rows terse; `dart run scripts/check_context_artifact_budget.dart` before commit, `--record` only if the drift is intended.)
  - `lib/features/auth/CLAUDE.md`: pitfall row *"An awaited routing read with no ceiling hangs the splash on a 504/521 backend — `resolveBounded` (8 s) → `DestinationUnknown('read_ceiling')`; with local evidence → home, without → keep awaiting the ORIGINAL read; never `StartMissionBrief`."* and fix the `15s hint / 30s CTA` description lines (`:59-60`, `:85`) to mention the 8 s ceiling that now precedes them.
  - `docs/architecture/sync.md`: a short "Outage resilience (Phase 1)" section inserted BEFORE `### Restore Pagination` (`:396` — re-grep; the restore-conflict-policy section it follows runs `:367-395`, not `:367-377`) covering the retry sweep + cap + serialised queue, stamp-on-clean, the probe, and a pointer to Phase 1b / Phase 2. ALSO update the existing `#### SyncBanner display policy (2026-09-17)` section (`:58-75`): the banner's single `_stateFor` funnel now has a `SyncPaused` branch that outranks the queue states.
- [ ] **Step 6: Skill self-evolution (§5.1)** — `.claude/skills/debugging/bug-classes.md`: add (a) *"a retry mechanism with no trigger for the failure mode that actually occurs (connectivity trigger vs a backend-only outage)"*, citing `e5b2a9` + `test/contracts/sync_retry_controller_test.dart`; (b) *"awaiting an unbounded network read before a local-evidence fallback"*; (c) *"an SDK-level automatic retry (supabase `postgrest` 503/520 → 3 retries) multiplies a 'one tiny request' probe by 4 — and a test stub that answers 503 hits it"*; and update the telltale text at `:475` (the heading `### 2.43` is `:474`) to note `restore_op_done` is now logged only for ops ≥ 2 s (so "~90 restore_op_done in 27 s" no longer appears — look at `restore_started`/`restore_completed` counts instead). **ALSO** add one ROW per new class to the §2 index table in `.claude/skills/debugging/SKILL.md` (it requires one row each; `SKILL.md:94` gives the max-id command — ids are non-monotonic with 9 duplicates; the highest today is 2.79, so these are 2.80–2.82).
- [ ] **Step 7:** Skill edits ship in the SAME commit as the fix (§5.1).

---

### Task 7: Review, B-pass, merge gates (process — §4.12 / §4.3)

- [ ] **Step 1: Full gate loop BEFORE any reviewer dispatch (§4.12.8 — never a hand-picked subset), WITHOUT committing.** `flutter analyze lib/` clean. Then the FULL suite once: `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden` (what pre-push runs at ≥ platform; `run_in_background`, ~7 min). It is not optional here: tests outside `test/contracts/` and `test/sync/` name touched members (`test/safety/restore_after_session_open_test.dart:57-60` source-greps `_safeRestoreOp(`; `test/supabase/sync_service_test.dart:42-46` names `_safeRestoreOp` and `weeklyFullSync`; `test/onboarding/resume_route_resolver_test.dart` is Task 1's stranded grep). Fix whatever moved by REPOINTING, never loosening. Then the pre-commit loop: **`git add` the explicit file list (never `-A`), run `sh scripts/pre-commit.sh` directly — DO NOT run `git commit`** (the founder has not said "commit"). Also by name: `wc -l lib/features/auth/screens/restoring_screen.dart` ≤ 800 + `dart run scripts/check_god_screen_max_lines.dart`; `dart run scripts/check_sot_registry_parity.dart`; `dart run scripts/check_sync_hash_skip_atomicity.dart` (G1); `dart run scripts/check_sync_no_now_fallback.dart` (G2); `dart run scripts/check_context_artifact_budget.dart`; `git diff -U0 -- '*.dart' | grep -n '^+.*/\*'` → nothing. Unstage afterwards if the founder's go has not come.
- [ ] **Step 2: Classify** — write the staged-diff file list to the scratchpad and run `dart run scripts/blast_radius_from_diff.dart -` with the BARE `-` stdin form (never positional). **Computed in round 2 (R2d): `platform`** — only `lib/core/services/sync/sync_resilience.dart` is platform (`lib/core/services/sync/**`); the other `lib/core` files and `lib/features/auth/**` are account. Demands `review_rounds ≥ 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted` + a committed `bpass_review` file. Hermes is NOT required (catastrophic only). Re-run on the real staged list; if it says `catastrophic`, add a Hermes pass.
- [ ] **Step 3: Plan review** — **Round 1 DONE** (4 Sonnet context-blind reviewers; Round-1 log). **Round 2 DONE** on revision 2 (4 Sonnet reviewers: claims-vs-code, behavioral, compile+ground-truth with a scratch Flutter project, process/gates); findings and dispositions in the Round-2 log. Round 2 found design-level defects only in Unit C, which is split out (§4.12.1); the retained units A, B, D, E received one P0 (compile) and a set of mechanical/process findings, all folded in this revision. The record below states `review_rounds: 2`.
- [ ] **Step 4: Self-triggered B-pass FIRST, then the record** (the record cannot name a B-pass file that does not exist yet). Run the `code-review` skill on the staged diff BEFORE merging (§4.3; never wait to be asked). It writes `docs/reviews/<id>-bpass.md` — that file needs line-anchored `reviewed_at: YYYY-MM-DD…` and `verdict: accepted` lines. The same commit appends a dated entry to **`.claude/skills/code-review/tuning-history.md`** under `## 7. Tuning history` (NOT `SKILL.md` — `scripts/check_skill_tuning_history.dart:24` reads the tuning file and blocks otherwise): header `- **YYYY-MM-DD** — blast-radius platform …`, the date equal to the review file's `reviewed_at:`, the entry text containing the review file's basename stem (`skill_tuning_lib.dart:71-80,145-175`); precedent commit `82e15c5a`.
- [ ] **Step 5: Plan-review record** — `docs/plan-reviews/claude-resilient-client-phase1.md` (filename = `recordSlug()` of the branch: `/` → `-`), literal `---` fence, ALL of (R2d, `check_plan_review_record_exists.dart:788-867`):
  ```
  ---
  branch: claude/resilient-client-phase1
  plan: docs/superpowers/plans/2026-10-01-resilient-client-phase1.md
  review_rounds: 2
  ground_truth_verified: true
  verdict: converged
  bpass: accepted
  bpass_review: docs/reviews/<id>-bpass.md
  ---
  ```
  `branch:` must equal the RAW branch name; `bpass_review:` must name a file committed in the merge. The gate runs ONLY on a push to `main` (a PR or local run prints "PASS: not landing on main") — so a missing field reddens `main` AFTER the merge; check the record against this list by hand. The plan file itself is untracked today — `git add` it (78 plans are tracked) together with the Phase 1b draft.
- [ ] **Step 6: Stop at the founder** — report: tests green, review rounds, B-pass findings fixed, and ask for "commit". Commit message (scratchpad file, then `"$(cat msg.txt)"`): subject `fix(sync): survive a Supabase API outage — bounded splash, capped push retry, paused banner`; body carries `closes-diagnose: e5b2a9` and `closes-oi: OI-151` and cites each test path (rule 21). Commit via `sh scripts/safe_commit.sh` with `run_in_background` (pre-commit measured 97–640 s); verify `git log -1 --format=%s` + `git status`. Merge is `gh pr create` then **`gh pr merge <N> --merge` ONLY** (never `--squash`/`--rebase`, do not override the subject — a single-parent landing at ≥ account fails the keystone gate; the sandbox refuses cd/git into the primary worktree, so no `safe_merge.sh`), only on the founder's go. One push via `sh scripts/safe_push.sh` (`run_in_background`, ~7 min pre-push), verified with `git ls-remote`.
- [ ] **Step 7: Live verification after merge** — web build is the surface the founder can test immediately: (a) CI green; (b) with `*.supabase.co` blocked (devtools offline→throttle), cold-open the web app for the existing account → home within ~10 s (Unit A); (c) log weight offline → banner "Sync paused" → unblock → banner clears and `weight_logs` has the row (B/D). Android +47 users need a new APK for any of this — **APK build only on the founder's explicit say-so**.
- [ ] **Step 8: §5 close-out** — memory retrospective `project_resilient_client_phase1.md` + swap the MEMORY.md IN-FLIGHT line (shipped batches go to `MEMORY_ARCHIVED.md`); after merge + CI green retire THIS session's worktree autonomously (§4.13.8: `ExitWorktree({action:"keep"})`, then from the primary `dart run scripts/retire_worktree.dart next-aab-decision-d1227b` dry-run, then `--execute` with that slug; the slug is the worktree directory, not the branch name); `dart run scripts/check_context_artifact_budget.dart` (`--record` only for intended drift).

---

### Task 8: The OI board + the closure ledger (no-deferral terminal state, §4.2)

**Order matters** (R2d P1-2): the mint pushes a reservation ref, the board edits must be IN the single commit, and the diagnose doc / nested docs / sync.md / the closure ledger name the real OI numbers. So after the founder says "commit": mint all three → substitute the real numbers everywhere they were written as placeholders → regenerate → `safe_commit.sh`. Until then write `OI-<phase1b>` / `OI-<phase2>` / `OI-<nutdel>` as the placeholder tokens and `grep` for them before the commit.

- [ ] **Step 1: Mint (only when the founder says commit/push** — `mint_oi.sh` pushes a reservation ref `refs/heads/oi/N`, a documented §4.3 exemption but outward-facing; `gh` is installed and authenticated here, so it uses the API transport and no pre-push hook fires), from THIS worktree:
  - `sh scripts/mint_oi.sh "Phase 1b: pull-on-resume — a backgrounded device refreshes itself (7-day window, pull-before-reckon ordering, pending-delete-aware exercise-log restore, per-set fetch must fail the pull, own refresh signal) — split out of resilient-client Phase 1 by §4.12.1"`
  - `sh scripts/mint_oi.sh "Phase 2 multi-device delta sync: updated_at+deleted_at on every synced table, per-table cursor, conditional push, water as per-drink entries, cold-start restore → cursor delta (replaces since=2020-01-01 at sync_service.dart:1701)"`
  - `sh scripts/mint_oi.sh "Meal deletes never reach the cloud: NutritionWriteService.deleteLog is local-only, so _restoreNutritionLogs resurrects deleted meals at cold start"`
- [ ] **Step 2: Edit the stubs the mint appended** (`mint_oi.sh:251-257` `append_stub` already appends `## OI-N — <title>` with `Status: OPEN`, `Blocked on: none`, `Verified: never`, `Identified: …`). **Replace the `Blocked on` and `Verified` values IN PLACE — never add a second `## OI-N` heading or a second `Blocked on`/`Verified` line** (`build_oi_index.dart:121-133` and `check_oi_numbering_unique.dart` Check A fail on a duplicated heading; the parser keeps only the FIRST `Blocked on`/`Verified` line, so an appended second one is silently ignored and the index would show the stub's `none`). Content: Phase 1b — `Blocked on:` "Phase 1 merged; needs its own plan + two review rounds"; carry the round-2 design requirements (pull-before-reckon; skip rows whose delete is still queued in `PendingExlogDeletes`; a swallowed per-set fetch failure must fail the pull instead of writing a set-less exercise log; a refresh signal of its own instead of `restoreCompletedTick`; a failure counter so a failed op aborts the pull). The pending-delete and set-less-row defects live in the SHARED writer `_restoreExerciseLogs` (`sync_workout.dart:894` swallow, `:1024` local-wins write), so the cold-start restore has the same exposure — Phase 1b VERIFIES that and fixes it at the writer, not only in the pull; the draft file path. Phase 2 — `Blocked on:` "Phase 1b merged; needs founder go on the delta-sync design and per-action authorization for each live migration apply (`updated_at`/`deleted_at` columns)"; evidence: the water residual, the 2020 constant, `scheduled_workouts`/`streaks` have no `updated_at`, `weight_logs` only `created_at`. Nutrition-delete — `Blocked on:` "needs a cloud tombstone (`deleted_at`) on `nutrition_logs` + a reader filter — a migration, which needs the founder's per-action apply authorization"; evidence with file:line. `Verified:` = today's date + what was read. `build_oi_index.dart` is run by pre-commit (`pre-commit.sh:202-209`), so a manual run is optional.
- [ ] **Step 3: Closure ledger** — `docs/audit/resilient-client-phase1.closure.yaml`, created ONLY once every entry is terminal (it is validated on EVERY commit repo-wide, Gate 40, §4.10). Shape (R2d, `validate_audit_closure.dart:275-328`; copy `docs/audit/unitb-deload-reason.closure.yaml`): top-level `batch: resilient-client-phase1`, `plan_review_record: docs/plan-reviews/claude-resilient-client-phase1.md`, `bpass_review: docs/reviews/<id>-bpass.md`, `diagnose_docs: [docs/diagnoses/2026-10-01-supabase-api-outage-client-resilience-e5b2a9.md]`, `findings:` and a trailing `closed_count: N` equal to the terminal tally (`total:` optional, within 3). Entries: units A, B, D, E and OI-151 → `terminal_state: closed_in_commit`, **`commit: claude/resilient-client-phase1@branch`** (the in-branch form — a `closed_in_commit` WITHOUT `commit:` fails; the SHA does not exist yet), `verification:` = the test path. Phase 1b / Phase 2 / nutrition-delete OIs → `terminal_state: blocked_on_user`, `reason:` naming the actual user action required (Phase 1b: "founder go on the Phase 1b plan after its own two review rounds; OI-N filed"; Phase 2 / nutrition-delete: "needs founder go on the design and per-action authorization for each live migration apply; OI-N filed"). Never a `deferred:` key.
- [ ] **Step 4: Move OI-151** (Task 5 Step 5) — the board edit rides in the same commit as the code.

---

## Self-Review

**Spec coverage** (founder asks, 2026-10-01 thread → task):
- Splash hung 15 min / "how long before local Hive" → Task 1 (8 s with local evidence; no-evidence users keep waiting, late answer used).
- Weight never synced / no retry → Task 2 (+ stamp-on-clean so a relaunch re-sweeps; serialised sweeps).
- Failure is invisible → Task 4.
- "Minimal load on Supabase" → D1/D2/D12 + Task 5 (the measured 57% `client_errors` finding, closes OI-151) + the one-request probe, the 10 s manual cooldown and the cap.
- Android doesn't update when backgrounded → **NOT in this plan** (Unit C → Phase 1b, OI board). **Said plainly to the founder:** this batch fixes the splash hang and gets a failed push to the cloud on its own; a second device still only picks up changes at its next cold start until Phase 1b ships.
- Water / stale-device overwrite → explicitly NOT solved (Phase 2, OI board).
- Backups / standby DB → out of scope by founder decision.

**Placeholder scan:** every code step carries its code; every test carries assertions. The "read the neighbour" steps (registry, diagnose frontmatter, OI closing protocol) point at named existing files because their exact keys are validator-owned and must be copied, not invented. The Task 8 `OI-<…>` tokens are intentional placeholders with a "grep before commit" instruction.

**Type consistency:** `SyncRetryController.{noteFailure(error, {opType}), retryNow, reset, bind, paused, retryableFailureSeq}` identical in Tasks 2 and 4; `kSyncRetryManualCooldown` / `kSyncRetrySweepCeiling` identical between Task 2's tests and controller; `boundDestination` / `resolveBounded` / `kDestinationTimeoutReason` identical between Task 1's tests and implementation; `SyncPaused` / `retryPausedSync` identical in Task 4.

**Known residuals (stated, not hidden):** (1) a stale device holding a non-zero water total for the day still overwrites the cloud — Phase 2; (2) cross-device freshness on resume (workouts/weight/water) is Phase 1b, meals and schedule edits are Phase 2 (tombstones) — all on the OI board; (3) the retry cap ends the cycle after ~43 min — a still-unsent row then waits for the next failure, the next launch's (unstamped) sweep, or the next write; (4) `weeklyFullSync`'s stamp/serialise logic cannot be driven end-to-end in the stub harness (no auth user — `test/supabase/sync_service_test.dart:42`), so its wiring is presence-tested and mutation-proven but not behaviorally exercised — the B-pass must read it; (5) in-memory controller state is lost on app kill — correct, because a cold start runs the full restore and the unstamped sweep; (6) a launch following a failed sweep re-runs the whole sweep at most once per launch (`checkAndSync` is called only from `splash_screen.dart:203`).
