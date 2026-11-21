---
bug_id: e5b2a9
date: 2026-10-01
batch: resilient-client-phase1
status: fixed
blast_radius: platform
symptom: |
  During the 2026-10-01 05:50-06:30 UTC Supabase API outage (Cloudflare 521/522/504
  and PGRST002; the database itself stayed ACTIVE_HEALTHY) the web app sat on
  "Getting you ready…" for ~15 minutes, a weight logged on web never reached the
  cloud, and nothing retried it until the next write or the next app launch.

  Three independent defects, one outage:

  (1) NO CEILING ON THE ROUTING READ. AuthSessionBootstrapper.resolveDestination
  (token refresh + SELECT + hard-refresh retry + SELECT) had no timeout, and
  RestoringScreen._kickoffRestore awaited it before its "already onboarded
  locally -> home" branch could run. Each hung request held a connection 10-36 s
  (the d7b1f8 shape), so a returning user with a full Hive saw the splash until
  they found the 30 s CONTINUE button. Founder follow-up the same day, and the
  reason the ceiling alone is not enough: a swipe-away is a full cold start, and a
  device that ALREADY holds everything needed to route still waited for the
  server's routing answer first ("if the data is on the phone, why wait?").

  (2) A FAILED PUSH HAD NO TRIGGER. Every domain push already goes through
  SyncSkipIndex.pushIfChanged, which records a row as sent only after a CONFIRMED
  push - so re-running the sweep sends exactly what is still unsent. What was
  missing was the trigger: the connectivity listener (sync_state_provider) cannot
  fire when only the backend is down (the device is online), and SyncQueue carries
  only three profile op types. Second defect in the same area: weeklyFullSync
  stamped last_full_sync unconditionally, so a launch AFTER a fully-failed sweep
  skipped the sweep for a day.

  (3) THE FAILURE WAS INVISIBLE. Nothing told the user their data had not synced.

  Measured side effect that retry sweeps would have multiplied: client_errors held
  7,047 rows on 2026-10-01; 5,479 (78%) were event rows and 4,043 (57%) were
  restore_op_done - one INSERT per SUCCESSFUL _safeRestoreOp (OI-151).
concept: sync_failure_retry_sweep
sot_registry_entry: restoring_destination_read_timeout, sync_failure_retry_sweep
writers:
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "boundDestination / resolveBounded / resolveDestinationBounded / resolveDestinationBoundedOnce - the 8 s ceiling and the local-evidence policy", line: 193 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "resolveBounded(evidenceFirst) / settleLateAnswer / applyLateAnswer / liveSessionOwnedBy / sessionOwnedBy / stampOnboardingCompletedAt - evidence-first routing: GoHome at once when the device holds local evidence; the read settles in the background (error sink, no ceiling) behind a live Supabase-uid + Hive-owner guard", line: 228 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "ExclusiveRun - the CONTINUE-retry stacking guard", line: 1247 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_reportSyncFailure - the single failure funnel; tells SyncRetryController about every failure and persists the durable sync_sweep_owed flag when one was accepted", line: 2745 }
  - { file: lib/core/services/sync_retry_controller.dart, method_or_widget: "SyncRetryController.noteFailure / _fire - outage-shaped failures of swept PUSH opTypes only (kNotSweptOpTypes excluded); probe-gated; 30s/2m/10m; capped at 6", line: 222 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "weeklyFullSync - serialised behind an in-flight sweep via SerialSlot; stamps last_full_sync AND clears sync_sweep_owed only on a clean sweep", line: 1323 }
  - { file: lib/core/services/serial_slot.dart, method_or_widget: "SerialSlot.enter / SerialTicket.turn / release / reset - the serialisation primitive, fakeAsync-tested", line: 24 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "checkAndSync - runs the launch sweep when shouldRunFullSweep says the daily interval elapsed, there is no stamp, OR sync_sweep_owed is set", line: 985 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_safeRestoreOp - restore_op_done only for ops >= 2 s", line: 2642 }
readers:
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_kickoffRestore - awaits the bounded destination (GoHome at once with local evidence); falls to the local-evidence branch on the ceiling", line: 111 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_onContinueAnyway - the bounded, guarded CONTINUE retry", line: 581 }
  - { file: lib/shared/providers/sync_state_provider.dart, method_or_widget: "SyncStateNotifier._stateFor - SyncPaused outranks the queue states", line: 159 }
  - { file: lib/shared/widgets/sync_banner.dart, method_or_widget: "_PausedBanner - renders SyncPaused; tap = retryPausedSync", line: 92 }
  - { file: lib/core/services/sync/sync_resilience.dart, method_or_widget: "probeBackendReachable - session guard + 8 s ceiling around the probe that decides whether a retry sweep is worth running", line: 11 }
  - { file: lib/core/services/backend_probe.dart, method_or_widget: "probeBackendWithClient - ONE request (SDK retry disabled); a server that answers 'no' is reachable", line: 20 }
hive_key_prefix: "n/a - ONE new key, syncBox 'sync_sweep_owed' (bool; user-scoped because the sync box is, like last_full_sync); kill-switches read configBox (disable_resolve_destination_timeout, disable_evidence_first_routing, disable_sync_retry_sweep, disable_restore_op_done_filter)"
hive_key_formula: "sync_sweep_owed is set when the retry controller ACCEPTS an outage-shaped push failure and deleted by a clean weeklyFullSync; the last_full_sync syncBox stamp is the existing key, now written only by a clean sweep"
sync_methods: [weeklyFullSync, checkAndSync, probeBackendReachable, _reportSyncFailure, _safeRestoreOp]
restore_methods: [restoreFromCloudForUser]
cloud_table: client_errors
cloud_columns: [op_type, error_message, created_at]
contract_test_path: test/contracts/restoring_destination_timeout_test.dart
ist_handling:
  - "Not applicable - no date key or counter reset is read or written. The retry schedule is relative durations; last_full_sync is an existing UTC instant compared against a 1-day interval, not a date key."
provider_invalidations: []
telemetry_op_types:
  success: [restore_op_done]
  failure: [weekly_full_sync, restore_sync_weight, upsert_weight_log]
cross_account_guard: |
  SyncRetryController is a process-wide singleton, so its pending timer, paused
  flag and an IN-FLIGHT run all belong to the previous owner after an account
  switch. SyncService._onUserChanged calls SyncRetryController.instance.reset(),
  which bumps a generation counter (a stale run's tail becomes a no-op and cannot
  sweep or clear the new owner's flag), clears the running flag (so the NEW
  owner's first failure schedules normally) and cancels the timer.
  _weeklyFullSyncSlot.reset() (the serialisation tail) is also called there, and
  the durable sync_sweep_owed flag lives in the user-scoped sync box, so a new
  owner never inherits the previous owner's "sweep owed".
  test/contracts/sync_retry_controller_test.dart pins the in-flight reset case;
  test/contracts/serial_slot_test.dart pins reset-while-waiting.
forbidden_patterns_checked:
  - { pattern: "an unbounded await on the post-auth routing read before the local-evidence branch", absent: true, after_fix: true }
  - { pattern: "a routing timeout reported as StartMissionBrief (a read that did not answer must never look like a new user - c2e9f4)", absent: true, after_fix: true }
  - { pattern: "evidence-first routing returning GoHome without evidence, or reading the evidence before the user-scoped Hive session is open (until then the raw box getter throws, which the callback turns into 'no evidence', so evidence-first silently never fires)", absent: true, after_fix: true }
  - { pattern: "a background late routing answer writing into Hive after the Supabase session or the open Hive owner changed (the stamp would land in the next user's profile)", absent: true, after_fix: true }
  - { pattern: "a second writer of the Plan A onboarding_completed_at self-heal stamp (the screen delegates to the bootstrapper)", absent: true, after_fix: true }
  - { pattern: "SyncError.isTransient (UnknownError / AuthError are transient) used as the retry predicate - an infinite loop", absent: true, after_fix: true }
  - { pattern: "weeklyFullSync stamping last_full_sync after a sweep in which an outage-shaped push failed", absent: true, after_fix: true }
  - { pattern: "an op type the sweep does NOT re-send (a READ, or a push only its own writer retries) arming the Sync paused state - a banner and a probe for nothing", absent: true, after_fix: true }
  - { pattern: "an error's details/hint text (the user's own row echoed by Postgres) classified as an outage", absent: true, after_fix: true }
  - { pattern: "a per-success logEvent in a path the retry sweep re-runs", absent: true, after_fix: true }
proposed_fix: |
  FOUR units, no migration, no Edge Function change (Unit C, pull-on-resume, was
  split out under CLAUDE.md 4.12.1 - see "Scope" in the body).

  A. Bound the routing read. AuthSessionBootstrapper.resolveBounded: answered
     within 8 s -> untouched; ceiling fired AND the device holds local evidence ->
     DestinationUnknown('read_ceiling') so the screen's existing unknown branch
     goes home; ceiling fired with NO local evidence (fresh device) -> keep
     awaiting the ORIGINAL read so a late answer still routes. The CONTINUE retry
     is bounded too and guarded by ExclusiveRun against stacking. All logic lives
     in the bootstrapper: restoring_screen.dart's head file was exactly on Gate
     43's 800-line cap at plan time (Gate 43 counts only the head file, so the
     cap does not force this - the logic lives there by choice, where it is
     testable without a widget). The screen edit is net -6 lines.
     A+ EVIDENCE-FIRST (founder decision 2026-10-01, same unit): when the device
     already holds local evidence of onboarding, resolveBounded returns GoHome()
     immediately instead of awaiting the cloud read. With evidence EVERY screen
     branch ends in _goHome (StartMissionBrief is overridden by the evidence,
     Unknown goes home on it, ResumeOnboarding self-heals and goes home, GoHome
     goes home), so the read cannot change where the user lands. What the read
     still owed is applied when it answers (applyLateAnswer): the Plan A
     onboarding_completed_at stamp for ResumeOnboarding (only with all 9
     migration-112 fields, OI-46) and the c2e9f4 override signal for
     StartMissionBrief - and only while the Supabase uid AND the open Hive owner
     still name the user (liveSessionOwnedBy -> sessionOwnedBy); the chain has an
     error sink and no ceiling (settleLateAnswer: a rejecting read, a throwing
     stamp or guard end in ONE evidence_first_late_answer_failed event). The
     stamp itself is self-protecting (it re-checks the session at entry and
     again before its profile push, keeps an existing real stamp and still pushes
     it). The read is observed with .ignore() the moment it is handed over, so
     an error completing while the evidence check runs is never uncaught. The
     evidence callback is the screen's own (it opens the Hive session before it
     reads, and honours disable_local_onboarded_evidence). No evidence (fresh
     device / reinstall) falls through to the policy above untouched, so "the read
     did not answer" is still never StartMissionBrief (c2e9f4). Kill-switch
     disable_evidence_first_routing restores the old path verbatim;
     disable_resolve_destination_timeout turns it off too. The screen's
     _stampOnboardingCompletedAt now delegates to
     AuthSessionBootstrapper.stampOnboardingCompletedAt, so there is ONE stamp
     writer.
  B. SyncRetryController: an OUTAGE-SHAPED failure (socket/DNS, TLS/handshake,
     Load failed, 5xx / Cloudflare 52x, 408/429, PGRST000-003,
     57014/53xxx/08xxx/40001/40P01, TimeoutException) on a PUSH opType the sweep
     actually re-sends (upsert_*, sync_*, restore_sync_*, weekly_full_sync, minus
     kNotSweptOpTypes: the sync_fitness_summary / sync_community_items READS and
     the pushes only their own writer retries) arms a reachability-probed re-run
     of weeklyFullSync on 30 s -> 2 m -> 10 m, capped at 6 failed runs. The
     classifier reads the status/code from the error text up to ", details:" only
     - Postgres echoes the user's own row into details/hint, so "my workout
     timed out yesterday" must not look like an outage. A banner tap is
     rate-limited to one run per 10 s (the same cooldown also gates the queue
     drain the tap fans out to) and a sweep that has not returned in 5 min is
     abandoned as a failed run. weeklyFullSync runs serialised behind an
     in-flight sweep (SerialSlot, not joined) and stamps last_full_sync only if
     no retryable failure moved the counter. The controller's own state is
     memory-only, so the funnel also writes a DURABLE sync_sweep_owed flag when a
     failure is accepted; a clean sweep clears it and checkAndSync runs the
     launch sweep when it is set (a web reload or the 6-run cap no longer leaves
     a row unsent until tomorrow). The probe (backend_probe.dart) is ONE request:
     supabase postgrest retries a GET that is answered 503/520 - or that throws -
     three more times (1/2/4 s), and 503 is the real PGRST002 shape, so it opts
     out with .retry(enabled: false).
  D. SyncPaused banner state ("Sync paused - your data is safe", one line, tap to
     retry), fed by SyncRetryController.paused, with a connectivity-restore kick
     while paused. A tap inside the cooldown does nothing; the queue drain is only
     forced when the queue actually holds work (a forced drain bypasses the
     queue's own backoff and bumps every op's retry count).
  E. restore_op_done only for ops >= 2 s (closes OI-151); kill-switch
     disable_restore_op_done_filter.
regression_test_planned: |
  test/contracts/restoring_destination_timeout_test.dart (Unit A, fakeAsync +
  ExclusiveRun + wiring), test/contracts/evidence_first_routing_test.dart (Unit A
  evidence-first: policy, late-answer handler, session guard, kill-switches, wiring), test/contracts/sync_retry_controller_test.dart (Unit B:
  predicate and classifier tables, op-type allowlist forcing function,
  controller, cap, reset-in-flight, cooldown, ceiling, owed flag, wiring),
  test/contracts/serial_slot_test.dart (the serialisation primitive, fakeAsync),
  test/sync/probe_backend_reachable_test.dart (the probe against a stub server:
  answered-no = reachable, 5xx/PGRST002 = not, ONE request),
  test/contracts/sync_paused_state_test.dart (Unit D),
  test/contracts/restore_op_done_filter_test.dart (Unit E). Two existing
  source-greps were repointed, not loosened: test/onboarding/
  resume_route_resolver_test.dart and test/contracts/
  local_onboarding_evidence_behavioral_test.dart (the screen now calls the
  bounded variants).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "Units A, B, D, E in lib/core/services/{auth_session_bootstrapper,sync_retry_controller,serial_slot,backend_probe,restore_telemetry_policy,sync_service}.dart, lib/core/services/sync/sync_resilience.dart, lib/shared/providers/sync_state_provider.dart, lib/shared/widgets/sync_banner.dart, lib/features/auth/screens/restoring_screen.dart (net -6 lines: 794 of the 800-line Gate 43 cap)." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "One new syncBox key, sync_sweep_owed (bool) - written by _reportSyncFailure when an outage-shaped push failure is accepted, deleted by a clean weeklyFullSync, read by checkAndSync. Kill-switches are read defensively from configBox; last_full_sync (syncBox) is the existing stamp and is now written only by a clean sweep." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "client_errors measured live 2026-10-01: 7,047 rows, 5,479 event rows (78%), 4,043 restore_op_done (57%). pg_stat_statements ranks INSERT INTO client_errors #2 by total time." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Client-only; no Edge Function changed or deployed." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involvement." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Unchanged. The reachability probe is the signed-in user's own users row under existing RLS." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage involvement." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: external_services, status: verified, evidence: "The Supabase API outage 2026-10-01 05:50-06:30 UTC: edge_logs 521/522/504 and PGRST002 on the REST and auth gateways while get_project reported ACTIVE_HEALTHY. Real client_errors shapes used as test fixtures: ClientException with SocketException Failed host lookup; PostgrestException code 521; PGRST002 (HTTP 503 with a JSON body, no status in the exception text); TimeoutException after 0:00:45; ClientException Load failed." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Traced one failure end-to-end in source: a domain push catch -> SyncService._reportSyncFailure (single funnel) -> SyncRetryController.noteFailure -> paused flag -> SyncStateNotifier._stateFor -> SyncBanner; and timer -> probeBackendReachable -> weeklyFullSync -> SyncSkipIndex re-sends only unsent rows." }
impact_analysis: |
  WHAT IT COSTS TODAY. A returning user on a backend outage waits out the splash
  (no ceiling), and a push that failed during the outage waits for an unrelated
  write or the next launch. The 57% share of client_errors written for SUCCESSFUL
  ops is pure overhead that every retry sweep would have multiplied (~20
  _safeRestoreOp per weeklyFullSync).

  LOAD. The fix is designed to put LESS load on Supabase, not more: a retry costs
  one probe per backoff step while the server is down (not a sweep); a sweep
  re-sends only fingerprint-changed rows plus about six unconditional requests
  (profile, progress, preferences, coach interactions, templates are not
  skip-indexed); the cap ends the cycle after six failed runs (~43 min); a banner
  tap is rate-limited; and Unit E removes ~57% of the telemetry INSERTs. The
  expected side effect is a ~57% step-down of client_errors_7d on the admin/digest
  dashboards - that is the filter working, not a regression.

  HONEST LIMITS (stated, not hidden). (1) This batch does NOT make a second device
  refresh itself: pull-on-resume was split out (Phase 1b, OI-279) after two review
  rounds found design-level defects in it, so a device still picks up another
  device's changes at its next cold start. (2) Water and meals/schedule edits made
  on another device remain Phase 2 (OI-280: tombstones, per-drink entries; meal deletes OI-281). (3) The retry
  cap ends the cycle after ~43 min; a still-unsent row then waits for the next
  failure, the next write, or the next launch (the durable sync_sweep_owed flag
  makes that launch's sweep run). (4) The weeklyFullSync stamp / owed-flag logic
  cannot be driven end-to-end in the stub harness (no auth user), so that wiring
  is presence-tested and mutation-proven, not behaviourally exercised; the
  serialisation primitive itself (SerialSlot) and the probe ARE behavioural.
  (5) A failure that never reaches _reportSyncFailure (for example the
  templates-resync catch at sync_workout.dart:2171) leaves a sweep looking
  clean - pre-existing, unchanged. (6) With disable_sync_retry_sweep on,
  weeklyFullSync takes no serialisation ticket (the old path, verbatim), so a
  launch sweep and a manual one can overlap again. (7) While paused, a banner tap
  or a connectivity return still issues one probe request, bounded to one per
  10 s by the manual cooldown - no unbounded loop. (8) The three disable_*
  kill-switches default to ACTIVE, matching the repo's permanent-operator-switch
  precedent (disable_bg_restore, disable_plan_integrity_reconciler,
  disable_sync_banner_grace); it is not CLAUDE.md 4.6's hide-until-rolled shape.
  (9) Evidence-first routing saves the routing-read wait only: on a healthy
  network that read answers in well under a second, so the gain is mostly in bad
  networks. It does NOT shorten the 3 s splash floor or the cold-start
  full-history restore (restoreFromCloudForUser, since='2020-01-01' - it re-runs
  on every swipe-away; a cold-start cooldown is only safe once resume-pull,
  Phase 1b, exists). A device whose ONLY evidence is the onboarding flag (no
  primary_goal in the local profile) still awaits that restore inside _goHome.
  (10) With evidence-first on, the per-launch restoring_destination_unknown /
  restoring_missionbrief_overridden_by_local_evidence events fire only from the
  background answer (the override signal) - the per-launch Unknown event no longer
  fires on a device with evidence.
  (11) For a device with NO evidence the 8 s ceiling window now starts after the
  (local, fast) evidence check instead of at call time - a few milliseconds
  later; the old path is otherwise verbatim. With the evidence-first kill-switch
  on, nothing changes at all.
  (12) _goHome calls ensureTermsConsentFallback at t~0 on the evidence path (it
  used to run only after the routing read had refreshed the token). A stale token
  answers HTTP 200 with ZERO rows (RLS-filtered, c2e9f4), which would read as "no
  consent in cloud" and stamp now() instead of created_at, so the fallback now
  calls ensureFreshToken() first (a refresh failure is recorded, never swallowed
  silently).
  Android users need a new APK for any of it.
related_bugs: [d7b1f8, c2e9f4, b7c2a9, d2e8f4, 4a3b08, 4f8e2d]
recurrence: |
  Same CLASS as c2e9f4 (a read that did not answer must not look like "new user")
  and d7b1f8 (auth reads piling up on a starved backend, 10-36 s each) - neither
  added a ceiling. b7c2a9 / d2e8f4 (SyncQueue auto-drain never wired) is the same
  class as defect (2): a retry mechanism with no trigger for the failure mode that
  actually occurs. Different mechanisms, so the full template is used.
self_review_findings: |
  Two plan-review rounds (4 context-blind reviewers each) shaped this fix; the
  dispositions are in docs/superpowers/plans/2026-10-01-resilient-client-phase1.md
  (Round-1 and Round-2 logs). The ones that changed the code: SyncError.isTransient
  would have looped forever on UnknownError (replaced by an outage-shaped,
  status-aware predicate on push opTypes only); weeklyFullSync stamped last_full_sync
  even when every op failed; the 8 s ceiling would have discarded a late answer
  for a no-evidence user; restoring_screen.dart sits exactly on Gate 43's 800-line
  cap (the edit is net -6 lines, logic moved into the bootstrapper); PostgrestException was
  not in scope in the sync library (compile error); the supabase SDK retries a
  503/520 GET three more times, so the probe opts out; a JOINED sweep let the retry
  report recovery about a sweep that started before the server came back (now
  serialised). Unit C failed two review rounds on design, not on detail - split.

  The self-triggered B-pass (10 findings, none P0/P1) changed the code further:
  the controller's state is memory-only, so a web reload or the 6-run cap left a
  failed row unsent until tomorrow (now a durable sync_sweep_owed flag honoured
  by checkAndSync); the serialisation was a source-grepped raw future that no
  test could exercise (now SerialSlot, fakeAsync-tested); the probe had no test
  although the registry cited one (backend_probe.dart + a stub-server test);
  sync_community_items / sync_custom_items / sync_freezes and similar op types
  armed the paused banner although the sweep does not re-send them
  (kNotSweptOpTypes); the classifier scanned Postgres' echo of the user's own row
  (now cut at ", details:"); a banner tap fanned an un-throttled drain into the
  queue (now cooldown-gated and only when work is queued). One finding is an
  OI (OI-282), not a code change: docs/blast_radius.yaml only classifies sync/** as
  platform, so sync_service.dart / sync_retry_controller.dart / sync_queue.dart
  compute account.

  The evidence-first extension had ONE self-triggered review round (3 context-blind
  reviewers, 22 findings, no P0/P1 and no new design-level issue, so no split under
  4.12.1). What it changed: the original read is now observed immediately
  (.ignore()) so an early rejection cannot go uncaught while the evidence check is
  still running; the background chain (which already caught) moved out of an inline
  closure into the static settleLateAnswer so its error sink is behaviourally
  testable (rejecting read, throwing stamp, throwing guard, throwing sink, no
  ceiling); the session guard is
  fed by injectable live readers (liveSessionOwnedBy) and the stamp re-checks it at
  entry and before its push; the stamp keeps an existing real stamp (the HEAD body
  overwrote it with now() unconditionally) and always pushes; ensureTermsConsentFallback refreshes
  the token first (see limit 12); the stamp's tests ran against explicit stubs, so a
  default-guard test was added; two source-greps that passed on ANY mention of
  onboarding_completed_at were tightened (resume_route_resolver_test.dart,
  onboarding_completed_at_writer_to_reader_test.dart); and the corrected wording for
  the owner-null mechanism (the raw box getter throws; the GuardedBox stub serves
  empty) replaced "serves an empty box".
---

# The client does not survive a Supabase API outage: splash hang, a failed push that is never retried, invisible failure

See frontmatter for the full analysis. One-line summary: three independent
defects turned a ~40-minute API-gateway outage into a 15-minute splash hang, a
lost weight entry and a silent failure.

## Scope

Phase 1 = Units A, B, D, E. Unit C (pull-on-resume) is NOT in this batch:
CLAUDE.md 4.12.1 - two review rounds in a row found design-level defects in it
(pull-before-reckon ordering against the streak-decay reckon, a local-wins
restore that resurrects an exercise log whose delete is still queued, a
swallowed per-set fetch, no refresh signal of its own). It is the Phase 1b OI (OI-279),
seeded by docs/superpowers/plans/2026-10-01-resilient-client-phase1b-resume-pull-DRAFT.md.

## Mutation log (rule 21 - each mutation compiled; read the failure, not just the colour)

Every mutation was applied by exact-string replacement that had to match once,
the named test files were run, and the source was restored from an in-memory
copy and byte-compared (`RESTORED_IDENTICAL: true` for every run). Each mutated
tree still COMPILED (the tally line shows passing tests alongside the failing
ones - a compile error would show neither). "Tests red" below is the `-N` of the
tally line; the harness's own failing-NAME list collapses every failure to one
entry (the `[E]` marker is at the END of each line), so it was not used.

**150 distinct mutations across the batch: 147 reddened at least one test; 3 are
documented EQUIVALENT mutants (SL-3, CL-7, M23); 0 are unaccounted for.** The runs:

| Run | Mutations | Result |
|---|---|---|
| Units A, B, D, E, first pass (`restoring_destination_timeout_test`, `sync_retry_controller_test`, `sync_paused_state_test`, `restore_op_done_filter_test`; detail below) - A 6, B 10, D 4, E 3 | 23 | 23 red. Three more of the original 26 (T2-7, T2-8c, T4-5) stopped matching the source after the B-pass fold changed its shape; they were RE-EXPRESSED (OP-1, Y-2, Y-4) rather than counted twice |
| B-pass fold: `serial_slot_test` / `probe_backend_reachable_test` / controller + classifier + owed flag + serialisation wiring + banner copy + provider kick | 42 | first pass 37 red, 5 survived: `SL-3` and `CL-7` are EQUIVALENT (a completed tail future is awaited in one microtask, so clearing it is an optimisation; the text fallback already matches `timeoutexception`); `PR-5` (probe 8 s ceiling), `CT-3` (`manualRetryAllowed`), `CT-4` (`disabled`) were REAL gaps - tests added, re-run, 3/3 red |
| B-pass fold, extras (browser outage strings, `_onPausedChanged`, kill-switch key, ceiling constants, probe null-user / catch paths) | 14 | first pass 10 red, 4 survived (`X-8` bare `SocketException`, `X-10` ceiling value, `X-13` / `X-14` probe fail-closed paths) - tests added, re-run, 4/4 red |
| Re-expressions of three older mutations against the post-fold source | 4 | 4 red |
| Evidence-first, ROUND 1 (the code before the review fold; `evidence_first_routing_test`, 25 tests then) | 21 | first pass 20 red, 1 survived (`EF-21`, the stamp's Hive write was untested) - real-Hive test added, re-run, red |
| Evidence-first, ROUND 2 (the FINAL code after the 22-finding review fold; table below) | 46 | first pass 42 red, 2 survived: `M23` is EQUIVALENT BY CONSTRUCTION (my `rethrow` sat inside the `try` whose `catch (_) {}` swallows it - re-expressed as `M23b` / `M23c`, both red); `M37` (an unreadable `configBox` must keep the feature ON) was a REAL gap - test added, re-run, red |

### Evidence-first, round 2 (final code; `evidence_first_routing_test` 51 tests + `restoring_destination_timeout_test` 19; the `S` rows also run `resume_route_resolver_test`, `local_onboarding_evidence_behavioral_test`, `onboarding_completed_at_writer_to_reader_test`)

| Mutation | Tests red | Tests green | Restored byte-identical |
|---|---|---|---|
| M01 flip the evidence check | 9 | 60 | true |
| M02 remove the early GoHome return | 6 | 63 | true |
| M03 evidence-first ignores the timeout kill-switch | 1 | 68 | true |
| M04 evidence-first never runs | 6 | 63 | true |
| M05 a throwing evidence check counts as evidence | 1 | 68 | true |
| M06 the original read is not handed on | 1 | 68 | true |
| M07 read.ignore() removed (early-rejecting read goes uncaught) | 1 | 68 | true |
| M08 wrapper ignores the evidence-first kill-switch | 1 | 68 | true |
| M09 evidence-first kill-switch key typo | 2 | 67 | true |
| M10 late answer skips the session guard | 2 | 67 | true |
| M11 sessionOwnedBy: && -> || | 3 | 66 | true |
| M12 sessionOwnedBy ignores the Hive owner | 2 | 67 | true |
| M13 StartMissionBrief branch also stamps | 1 | 68 | true |
| M14 ResumeOnboarding stamps without shouldStamp | 2 | 67 | true |
| M15 ResumeOnboarding never stamps | 6 | 63 | true |
| M16 settle path guard wiring => true | 1 | 68 | true |
| M17 _liveHiveOwner reads the Supabase uid instead | 1 | 68 | true |
| M17b _liveSupabaseUid reads the Hive owner instead | 2 | 67 | true |
| M18 stamp gate always true in the settle wiring | 1 | 68 | true |
| M19 override event renamed | 1 | 68 | true |
| M20 evidence-first returns GoHome even with no evidence | 2 | 67 | true |
| M21 stamp body no longer writes the box | 4 | 65 | true |
| M22 settleLateAnswer gets an 8 s ceiling | 2 | 67 | true |
| M23 settleLateAnswer rethrows after the sink | 0 | 69 | true |
| M24 applyLateAnswer does not await the stamp | 3 | 66 | true |
| M25 stamp overwrites an existing real stamp | 1 | 68 | true |
| M26 stamp entry guard removed | 4 | 65 | true |
| M27 stamp post-write guard removed | 2 | 67 | true |
| M28 stamp push deleted | 3 | 66 | true |
| M29 stamp value shifted +5:30 | 1 | 68 | true |
| M30 stamp DEFAULT guard => true | 1 | 68 | true |
| M31 blank stamp counts as real | 1 | 68 | true |
| M31b non-string stamp counts as real | 1 | 68 | true |
| M32 terms fallback no longer refreshes the token | 1 | 68 | true |
| M33 terms fallback swallows a refresh failure silently | 1 | 68 | true |
| M34 settle error sink reason renamed | 1 | 68 | true |
| M35 wrapper narrows evidence-first with an extra condition | 1 | 68 | true |
| M36 evidenceFirstDisabled inverted | 4 | 65 | true |
| M37 evidenceFirstDisabled fails closed (catch returns true) | 0 | 69 | true |
| S1 screen GoHome arm navigates directly | 1 | 105 | true |
| S2 screen evidence helper reads before the session open | 1 | 105 | true |
| S3 screen evidence helper kill-switch returns true | 1 | 105 | true |
| S5 screen DestinationUnknown arm no longer goes home on evidence | 1 | 105 | true |
| S6 screen stamp helper no longer delegates | 2 | 104 | true |
| M37 evidenceFirstDisabled fails closed (catch returns true) | 1 | 69 | true |
| M23b settleLateAnswer: the error sink is not itself guarded (inner try removed) | 1 | 69 | true |
| M23c settleLateAnswer rethrows AFTER the guarded sink | 4 | 66 | true |

TOTAL=47 KILLED=45 SURVIVED=2 BAD=0
SURVIVED: M23 settleLateAnswer rethrows after the sink
SURVIVED: M37 evidenceFirstDisabled fails closed (catch returns true)

Reading the table: `M37` appears twice (first pass 0 red; re-run after the
fail-open `configBox` test was added, 1 red), `M23b` / `M23c` ran only in that
re-run, and `M23` never reddened a test because it cannot (equivalent by
construction). `M07` is the uncaught-zone-error mutation (`read.ignore()`
removed); `S1`-`S6` mutate `restoring_screen.dart` (there is no `S4`: that
label was never used).

### Evidence-first, round 1 (superseded by round 2 for the final code, kept as the record)

| Mutation | Tests red | Tests green | Restored byte-identical |
|---|---|---|---|
| EF-1 flip the evidence check | 8 | 34 | true |
| EF-2 remove the early GoHome return | 5 | 37 | true |
| EF-3 evidence-first ignores the timeout kill-switch | 1 | 41 | true |
| EF-4 evidence-first never runs | 5 | 37 | true |
| EF-5 a throwing evidence check counts as evidence | 1 | 41 | true |
| EF-6 the original read is not handed on | 1 | 41 | true |
| EF-7 the wrapper ignores the evidence-first kill-switch | 1 | 41 | true |
| EF-8 evidence-first kill-switch key typo | 1 | 41 | true |
| EF-9 late answer skips the session guard | 2 | 40 | true |
| EF-10 sessionOwnedBy: && -> || | 1 | 41 | true |
| EF-11 sessionOwnedBy ignores the Hive owner | 1 | 41 | true |
| EF-12 StartMissionBrief branch also stamps | 1 | 41 | true |
| EF-13 ResumeOnboarding stamps without shouldStamp | 1 | 41 | true |
| EF-14 ResumeOnboarding never stamps | 1 | 41 | true |
| EF-15 settle path skips the session guard wiring | 1 | 41 | true |
| EF-16 screen keeps its own stamp writer (not delegated) | 1 | 41 | true |
| EF-17 _sessionStillMine passes the wrong Hive owner | 1 | 41 | true |
| EF-18 stamp gate always true | 1 | 41 | true |
| EF-19 override event renamed | 1 | 41 | true |
| EF-20 evidence-first returns GoHome even with no evidence | 2 | 40 | true |
| EF-21 stamp body no longer stamps | 0 | 42 | true |
| EF-21 stamp body no longer stamps | 2 | 42 | true |

TOTAL=22 KILLED=21 SURVIVED=1 BAD=0
SURVIVED: EF-21 stamp body no longer stamps

### First-pass detail (Units A, B, D, E - the tests as they were at that time)

**Unit A** - `test/contracts/restoring_destination_timeout_test.dart` (19 tests):

| Mutation | Red |
|---|---|
| `boundDestination`: `return read;` (no timeout) | 4 |
| `resolveBounded`: final `return bounded;` instead of `return read;` (late answer discarded) | 2 |
| `resolveBounded`: drop the `if (evidence) return bounded;` short-circuit | 1 |
| `ExclusiveRun`: drop the `_busy` guard | 1 |
| `ExclusiveRun`: no `_busy = false` in `finally` | 2 |
| `restoring_screen.dart`: bare `.resolveDestination(user.id)` in `_kickoffRestore` | 2 |

**Unit B** - `test/contracts/sync_retry_controller_test.dart` (25 tests):

| Mutation | Red |
|---|---|
| `_fire`: an unreachable probe falls through to the sweep | 3 |
| `noteFailure`: drop the outage-shape filter | 2 |
| `noteFailure`: drop the `String` (telemetry replay) filter | 1 |
| `reset()`: no generation bump (the in-flight-run test) | 1 |
| `_fire`: a manual run escalates the backoff | 1 |
| `_afterFailedRun`: cap disabled | 1 |
| `isPushFailureOpType`: accept the `sync_fitness_summary` READ | 1 |
| `weeklyFullSync`: stamp unconditionally (comparison edited) | 1 |
| `_reportSyncFailure`: `noteFailure` hook deleted | 1 |
| `weeklyFullSync`: failure baseline read BEFORE the wait | 1 |
| `retryNow`: no manual cooldown | 1 |
| `_fire`: no sweep ceiling | 1 |

**Unit D** - `test/contracts/sync_paused_state_test.dart` (7 tests): paused line
deleted from `_stateFor` (1), paused line moved BELOW the idle shortcut (1),
`removeListener` moved out of the first `onDispose` (1), connectivity kick
deleted (1), banner copy changed (1).

**Unit E** - `test/contracts/restore_op_done_filter_test.dart` (5 tests):
boundary `>=` -> `>` (1), kill-switch ignored (1), policy wrapper removed from
`_safeRestoreOp` (1).

**Not behaviourally proven (stated):** `weeklyFullSync`'s serialise / stamp /
owed-flag logic is presence-tested and mutation-proven but cannot be driven
end-to-end in the stub harness (no auth user); the serialisation primitive
(`SerialSlot`), the probe, the evidence-first policy, the late-answer handler,
the stamp writer and the kill-switch getter ARE behavioural. `resolveDestinationBounded`
itself (the wiring that passes the kill-switch and the settle callback) and the
screen's per-arm `_goHome` premise are anchored source-slice pins, not behavioural
tests - the screen needs a Supabase + router harness this repo does not have.

**Full gate loop (final, 2026-10-01):** `flutter analyze lib/` 0 errors / 0
warnings (60 info-level lines, none in a touched file). The gates run one by one
on the staged tree all pass (Gate 43, registry parity / citations / completeness
/ behavioral-test paths, Gate 25 INDEX freshness, nested-CLAUDE content, the
sync-skip atomicity gate G1, the diagnose-doc validator); the context-artifact
budget WARNs on `lib/core/services/CLAUDE.md` (+18.9%, soft band) and was
re-baselined deliberately. Full `TZ=Asia/Kolkata flutter test test/ --exclude-tags
golden`: **7,334 passed, 9 skipped, 114 failed** - all 114 in 11 files that spawn
`sh` / git (`test/scripts/*`, `git_lock_concurrency_test`) or do date arithmetic
(`logout_login_round_trip_test` T1, `session_date_and_home_start_behavioral_test`).
That run was launched from the PowerShell tool, whose PATH has no `sh`
(`ProcessException ... Command: sh ...` - a known trap, recorded in
`feedback_local_ci_env_divergence`). Re-run of exactly those 11 files from the Bash
tool: **143 of 143 passed**, the two date tests included. Their failure under
PowerShell was not root-caused here; none of the 11 files imports or exercises a
file this batch changed (checked by their imports and by `git diff --cached`).
So the evidence is TWO runs, not one clean run - the real full-suite proof is the
pre-push hook (blast radius >= account) and CI. The known load-sensitive
`hive_user_session_box_open_parallel_test` passed in this run. Reported, not hidden.
