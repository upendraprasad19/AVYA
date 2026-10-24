---
bug_id: d5c8a3
date: 2026-07-30
batch: progress-map-consolidation
status: fixed
blast_radius: platform
blast_radius_note: >
  The diagnosed BUG itself (progress-map stale-snapshot) is account-tier —
  one user's own data. The diff's overall/gating tier is platform because
  the B-pass pass (see "B-pass review" below) found and fixed a real gap in
  docs/blast_radius.yaml itself, which is platform-tier by the registry's
  own rules (CLAUDE.md §7: "a change to the reviewer must not be exempt from
  review"). Recorded honestly rather than left at the bug's own lower tier.
symptom: >
  OI-45 named UserRepository's progress-map writers (updateProgress/saveProgress,
  user_repository.dart) as a HIGH lost-update race, originally citing 4 writers; a
  prior board-correction pass (Unit 1 of this batch) re-verified the writer set and
  found it was 3x undercounted — later re-verified precisely by round-2 review via a
  fresh `grep -rn '\.updateProgress(\|\.saveProgress('` across lib/: 15 write
  callsites (13 updateProgress + 2 saveProgress) across 11 files (10 external
  callers + user_repository.dart itself, where saveProgress's own body performs the
  actual Hive put) all read-modify-write the same top-level `progress` Hive key with
  no serialization. This unit
  investigated that claim with the same behavioral rigor as the sibling
  usage-counter-race batch (c9e3b1): does the claimed race actually reproduce, and
  what is the real fix. Findings, in the order discovered: (1) a Completer-based
  mutex mirroring ProfileWriteService._withLock was BUILT and tested — it provided
  NO correctness benefit for any concurrent updateProgress/saveProgress pairing
  tested via Future.wait (same structural-safety class as
  UsageCounterService.increment() — Hive's Box.put() lands its in-memory mutation
  synchronously, and Future.wait([a(), b()]) runs a() to its own first suspend
  point before b() is even invoked); (2) that same mutex ACTIVELY BROKE 2
  pre-existing tests in streak_decay_reckon_permanent_ledger_test.dart, because it
  serialized two previously-independently-landing UNAWAITED fire-and-forget calls
  (StreakProgressService.commitConsume and WorkoutRepository._persistCurrentStreakDays
  both fire un-awaited updateProgress calls within one
  reckonStreakDecayAndPersist() flow) into a genuine queue — the second call now had
  to suspend waiting for the first to release the lock, a real timing change neither
  caller nor the pre-existing tests expected; the mutex was removed as net-negative
  (no proven benefit, one concrete regression) rather than patched around. (3) The
  GENUINE, confirmed bug is a different, simpler mechanism: two callers
  (pro_phase_advance.dart's _advanceProPhaseIfExpired, simulation_service.dart's
  _maybeAdvancePhase) read `progress`, then awaited something REAL and slow (actual
  plan generation via autoGenerateNextPhaseIfNeeded — tens to hundreds of ms, not an
  artificial Future.wait pairing), then wrote the WHOLE map back from that pre-await
  snapshot via saveProgress. Any independent writer landing during that real await
  window was silently clobbered on the next whole-map save — reproduced directly (not
  just argued) by recreating the exact shape with UserRepository's own primitives.
  Fixed by converting both callers to updateProgress(delta), which re-reads
  getProgress() fresh at write time regardless of how long the caller's own
  preceding await took. (4) Two sibling OI-45 findings investigated in the same
  pass: BadgeService.checkAndUnlock/checkAll (finding 3) confirmed to have NO live
  race today (fully synchronous, no await between the badges-map read and write) —
  downgraded from HIGH, left unlocked (adding lock machinery for a non-existent race
  would be unjustified complexity), pinned with a synchronous-invariant tripwire test
  instead. HealthSyncService.syncToHive (finding 4) confirmed to have a genuine
  double-invocation TOCTOU — the method is called both on app launch and when the
  health-sync toggle is turned on, and its only real await gap sits BEFORE its
  read-check-write (inside fetchLatestWeight), not between them, so two concurrent
  calls can both pass the `existing == null` guard before either writes. Closed with
  a whole-method in-flight-Future dedup guard (a second caller awaits the first
  call's in-flight future instead of independently re-running the work).
concept: progress_map_writer_consolidation
sot_registry_entry: >
  No new docs/sot_registry.yaml entry. This fix does not rename or add any Hive
  field, cloud column, or writer/reader file:line contract — updateProgress and
  saveProgress keep writing the same `progress` Hive key with the same field names
  they always did (existing entries reference _syncUserProgress/_restoreUserProgress
  around sot_registry.yaml:1789/2024 and the streak_progress_* concept around
  :3253-3303, both unchanged). The fix corrects WHICH STATE two specific callers
  merge onto (fresh read vs. a stale pre-await snapshot), not what gets written or
  where. OI-45 findings 3 (BadgeService) and 4 (HealthSyncService) are internal
  concurrency-guard additions to already-registered concepts, same reasoning.
writers: >
  lib/shared/repositories/user_repository.dart saveProgress (line 112) and
  updateProgress (line 173) — UNCHANGED behavior (still no lock; still a fresh
  getProgress() read on every updateProgress call), doc comments corrected to
  reflect the empirical findings above. Two callers fixed: lib/shared/services/
  pro_phase_advance.dart:117 (_advanceProPhaseIfExpired, inside the
  `if (result.generated)` block starting line 103) — was
  saveProgress(Map.from(progressReadAtLine65)), now updateProgress({current_phase,
  current_week, plan_generated_at, phase_started_at}); lib/features/dev/
  simulation_service.dart:565 (_maybeAdvancePhase, debug-only /dev-panel harness,
  same conversion, was saveProgress(Map.from(progressReadAtLine535))). A third,
  PRE-EXISTING, untouched updateProgress call already lives at
  simulation_service.dart:469 (a different method) — not part of this fix, cited
  here only to avoid confusion with the one that was fixed at :565.
  lib/core/services/badge_service.dart checkAndUnlock (line 28) / checkAll (line
  94) — doc comment only, no behavior change (confirmed no live race; kept
  synchronous). lib/core/services/health_sync_service.dart — NEW _syncInFlight
  field (line 152) + syncToHive wrapper (line 154, plus a round-2-review fix: a
  silencing completer.future.catchError listener attached before the first
  await, closing a duplicate-Zone-error footgun) + renamed-and-now-private
  _syncToHiveLocked (line 189, was the old public syncToHive body verbatim —
  round-2 review P3: this citation previously said line 177, which is inside
  syncToHive's own closing brace region, not _syncToHiveLocked's definition).
readers: >
  lib/shared/repositories/user_repository.dart getProgress (line 71) — unchanged;
  read (directly or via a prior getProgress() call in the same function) by 15
  write callsites across 11 files, freshly re-counted by round-2 review via
  `grep -rn '\.updateProgress(\|\.saveProgress('` (StreakProgressService's 4
  updateProgress calls, WorkoutRepository._persistCurrentStreakDays,
  train_provider.dart, pro_phase_advance.dart, graduation_screen.dart,
  home_screen.dart, onboarding_provider.dart's saveProgress,
  simulation_service.dart's saveProgress + 2 updateProgress calls,
  phase_progress_reconciler.dart, restoring_screen.dart, plus
  user_repository.dart itself where saveProgress's own body performs the
  actual Hive put) — supersedes this doc's earlier "12+ callsites across 9
  files" figure, which undercounted by both measures. All unaffected by this
  fix except the 2 stale-snapshot callers named above.
  lib/core/services/badge_service.dart checkAll reads hive.userBox.get('progress')
  directly (line ~104, unchanged) for streak/phase badge conditions.
hive_key_prefix: "progress (single literal key, userBox — not a formula-prefixed key)"
hive_key_formula: "literal 'progress' — see docs/naming_conventions.md §3.3 streak_freezes_* row (the only progress sub-fields currently in the closed-set prefix registry; the top-level 'progress' key itself predates that registry and is not separately listed there)"
sync_methods: >
  lib/core/services/sync/sync_profile.dart syncProgressNow -> _syncUserProgress
  (unchanged by this fix — still a plain unversioned upsert to user_progress;
  cross-device optimistic locking is explicitly OUT OF SCOPE for this unit, see
  Unit 3b, not yet started). Fired unawaited from UserRepository.updateProgress
  (unchanged).
restore_methods: >
  lib/core/services/sync/sync_restore_completeness.dart / sync_profile.dart
  _restoreUserProgress — unchanged by this fix.
cloud_table: user_progress
cloud_columns: >
  current_phase, current_week, phase_started_at, plan_generated_at (the 4 fields
  the two fixed callers write) — unchanged column set, this fix does not touch
  the cloud schema.
contract_test_path: >
  test/contracts/user_repository_progress_stale_snapshot_test.dart (NEW — "OLD
  pattern documents the bug" / "NEW pattern proves the fix" pair, plus 3
  concurrent-dispatch invariant tests carried over from the removed-mutex design).
  test/contracts/badge_service_synchronous_invariant_test.dart (NEW — source-grep
  tripwire: checkAndUnlock/checkAll must never become async). test/contracts/
  health_sync_service_dedup_test.dart (NEW — source-grep contract for the
  _syncInFlight dedup guard's structure; kept at source-grep level, matching the
  sibling unit3_web_ux_gates_test.dart's own established restraint for this exact
  file — HealthSyncService reaches the unmocked `health` plugin platform channel,
  and _ensureConfigured's unawaited Health().configure() call risks an unhandled
  async rejection if actually invoked in this test suite).
ist_handling: >
  Not applicable — this fix touches Hive read/write ordering and a health-sync
  dedup guard, not date-key computation. DateTime.now()/nowWall() calls in the 2
  fixed callers (plan_generated_at, phase_started_at) are UNCHANGED verbatim from
  before this fix (still non-IST DateTime.now().toIso8601String() in
  pro_phase_advance.dart, still nowWall() in simulation_service.dart per each
  file's own existing convention) — not introduced or altered by this batch.
provider_invalidations: >
  Unchanged. updateProgress's existing unawaited(SyncService.instance.
  syncProgressNow()) fires exactly as before; the 2 fixed callers still fire
  their own unawaited(pushSnapshot()) afterward exactly as before. One net-new
  side effect (not a provider invalidation, a cloud-sync-timing improvement):
  pro_phase_advance.dart's saveProgress() call previously did NOT sync
  user_progress to cloud internally (saveProgress fires no sync; only
  updateProgress does) — the PRO phase-advance path left the cloud user_progress
  row stale until some unrelated updateProgress call happened to sync it. Now
  that this path calls updateProgress, that internal sync fires every time,
  closing a latent (separate, minor) staleness gap as a side effect of the
  delta-conversion. Same for simulation_service.dart (debug-only, so
  user-invisible either way).
telemetry_op_types: >
  No new telemetry op_types introduced. Existing sync_service_sync_progress_now /
  sync_user_progress reasons (error_telemetry.dart) unchanged.
cross_account_guard: >
  Unchanged — UserRepository.getProgress/saveProgress/updateProgress route through
  HiveService.userBox, which is wrapUserScopedBox-guarded per the existing
  auth_hive_owner_agreement SoT contract (not touched by this fix).
forbidden_patterns_checked: >
  Grepped this batch's own diff for raw Hive.box(...) access (none — all reads/
  writes go through HiveService.instance.userBox / _hive.userBox as before),
  setState-for-shared-state (none — no widget code touched), and hardcoded colors
  (none — no UI touched).
proposed_fix: >
  (1) lib/shared/services/pro_phase_advance.dart: convert the stale-snapshot
  saveProgress(Map.from(progress)..[4 fields]) to updateProgress({4 fields}). (2)
  lib/features/dev/simulation_service.dart: identical conversion in its debug-only
  twin. (3) lib/core/services/badge_service.dart: doc-comment only, documenting
  the synchronous-atomicity invariant checkAndUnlock/checkAll depend on. (4)
  lib/core/services/health_sync_service.dart: add a Future<void>? _syncInFlight
  guard; rename the old public syncToHive body to private _syncToHiveLocked; new
  public syncToHive() checks the guard first, and a second concurrent caller
  awaits the first call's in-flight future instead of independently re-running
  fetchLatestWeight + the unguarded read-check-write; round-1 review caught
  that the completer's `complete()` was unconditional in `finally` (a failed
  leader sync would still tell followers "success") — fixed to `complete()` on
  success / `completeError()` + rethrow on failure. A Completer-based mutex on
  UserRepository itself was ALSO tried, tested, and explicitly REMOVED — see
  symptom field and saveProgress's own doc comment for the full empirical
  account of why. NOT fixed here, spun out as Unit 3c (see "Round-1 review"
  body section): graduation_screen.dart's `_onPro()` has a narrower, related
  bug — a `nextPhase` value computed before a slow await, not re-derived after
  it — that needs its own conflict-resolution design, not a mechanical
  delta-conversion.
regression_test_planned: >
  test/contracts/user_repository_progress_stale_snapshot_test.dart — 5 tests: 3
  concurrent-dispatch invariants (2/5-concurrent updateProgress, saveProgress+
  updateProgress interleave) + the "OLD pattern documents the bug" /
  "NEW pattern proves the fix" pair which is the actual regression pin for the
  confirmed bug. test/contracts/badge_service_synchronous_invariant_test.dart — 3
  tests pinning the synchronous-signature invariant. test/contracts/
  health_sync_service_dedup_test.dart — 5 tests pinning the dedup guard's
  structure, including the round-1-review-driven completer-resolution fix. All
  13 new tests run green; full relevant-subset regression sweep (14 files, 67
  tests total including the 2 previously-broken
  streak_decay_reckon_permanent_ledger_test.dart cases) confirmed green after the
  mutex was removed, re-confirmed green again after the completer fix.
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on all 5 touched files (1 pre-existing unrelated info-lint on badge_service.dart's hive import, not introduced by this batch). All 5 files read in full and independently verified against the Unit-1-corrected OI-45 board text before any fix was proposed, per §4.1." }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "user_repository_progress_stale_snapshot_test.dart's OLD-pattern/NEW-pattern pair directly exercises real Hive reads/writes (temp-dir Hive.init, real Box.put/get) proving the bug reproduces and the fix closes it — not a mocked/simulated Hive." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "No schema change — this fix touches Hive-side read/write ordering only." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "No data migration or backfill involved." }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "No new migration in this unit (3a). Unit 3b, not yet started, will introduce one." }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "No cron job touched." }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "No RLS policy touched." }
  - { tier: 9_storage, status: not_applicable, evidence: "No Storage bucket touched." }
  - { tier: 10_secrets, status: not_applicable, evidence: "No secret or API key touched." }
  - { tier: 11_external_services, status: not_applicable, evidence: "No external service (Razorpay/OneSignal/Firebase/Health platform APIs) call shape changed — HealthSyncService's fix wraps CALL ORDERING only, not the calls themselves." }
  - { tier: 12_client_server_contract, status: verified, evidence: "Traced the full pro_phase_advance.dart -> updateProgress -> saveProgress -> Hive -> syncProgressNow -> _syncUserProgress -> Supabase user_progress upsert chain by reading every hop's source directly. The cloud upsert shape (which columns, when) is unchanged by this fix; only the LOCAL merge-base correctness changed." }
impact_analysis: >
  Before this fix: a PRO user's phase-advance (fired either silently on app
  launch, or via the user tapping the retry CTA on a stalled generation) could
  silently lose ANY OTHER progress-map write that happened to land during the
  real, tens-to-hundreds-of-ms plan-generation window — e.g. a concurrent streak
  decay/freeze-consume, a badge-relevant workout count, or a graduation-triggered
  advance racing the splash's own silent auto-advance. The whole-map
  saveProgress(staleSnapshot) call would reset any such field back to whatever it
  was BEFORE the interposed write, with no error, no telemetry, and no user-visible
  signal — a genuine, if narrow-window, silent data-loss bug. After this fix: the
  same 2 callsites merge via updateProgress(delta), which always reads current
  Hive state fresh at write time, closing the window regardless of how long plan
  generation takes. Separately, BadgeService's claimed HIGH race is confirmed NOT
  live (downgraded, tripwire-tested instead of lock-guarded — avoids adding
  complexity CLAUDE.md's own philosophy would flag as unjustified for a
  non-existent race). HealthSyncService's confirmed double-invocation TOCTOU
  (launch-time sync racing a Settings-toggle-triggered sync) is closed, including
  a round-1-review-found P2 (a failed sync could tell a deduped follower caller
  it succeeded) fixed in the same pass. OI-45 still stays OPEN — the
  cross-device optimistic-locking half (Unit 3b, not started) and a narrower,
  related stale-value bug round-1 review found in graduation_screen.dart (Unit
  3c, not started, needs its own conflict-resolution design) both remain; see
  the plan-review record and this doc's "Round-1 review" section for the
  explicit residual statements.
---

# Diagnosis: Progress-map stale-snapshot lost-update (OI-45 findings 2-4, Unit 3a)

## Investigation history — same discipline as the sibling usage-counter-race batch

OI-45's original text claimed a HIGH-severity lost-update race on `UserRepository`'s
`progress` map, naming 4 writers. Unit 1 of this 8-unit plan re-verified that claim
and found the writer set was **3x undercounted** — 12+ callsites across 9 files, not
4. This unit (originally scoped "Unit 3", split into 3a/3b mid-investigation — see
below) picked up that corrected scope and, per this repo's own
`feedback_source_grep_false_confidence.md` and `feedback_audit_verifier_cannot_trust_own_subagent.md`
discipline, independently re-verified every one of the board's citations by reading
the actual files myself before designing any fix — a subagent's initial investigation
report was cross-checked line-by-line, and one wrong file path
(`pro_phase_advance.dart`'s real location is `lib/shared/services/`, not
`lib/features/train/screens/`) and one off-by-one line citation
(`health_sync_service.dart`'s null-check is line 198, not 197 as originally claimed)
were caught and corrected before proceeding.

## The central discovery: migration 056's RPC has been dormant for 2.5 months

While tracing which progress sub-fields already have server-side protection
(the plan's own mandated first step), I found that `update_streak_progress`
(migration 056, column-fixed in 096) — built 2026-05-11 specifically to close the
CROSS-DEVICE half of a streak-freeze race — has **never been called by the client**,
confirmed two independent ways: (1) migration 096's own header comment states
"currently dormant — never called by literal RPC name per mig 090"; (2) grepping
all of `lib/` for `.rpc(` found exactly ONE hit in the entire client codebase
(`auth_provider.dart:181`, unrelated to progress). Both `syncFreezes()`
(`sync_restore_completeness.dart:14`) and `_syncUserProgress()`
(`sync_profile.dart:167`) — the ONLY two paths that push `progress`-map data to the
cloud today — are plain, unversioned `.upsert(...)` calls with zero optimistic-lock
protection. This is a significant, previously-undocumented finding: closing the
cross-device race properly means not just adding new RPC coverage for the fields
migration 056 doesn't reach, but ALSO finally wiring up the RPC that was built for
this exact purpose 2.5 months ago and never connected. Given the scale of that work
(a new migration, new client-side version tracking, retry-on-mismatch semantics —
none of which exist anywhere in this codebase's progress-sync path today) versus the
scope of this unit's confirmed, narrow, already-fixed bug, this was split out as
**Unit 3b**, not bundled into this diagnose-doc. See "Residuals" below.

## Why the client-side mutex was built, tested, and then removed

The natural first design — mirroring `ProfileWriteService._withLock` exactly, the
same pattern `UsageCounterService` used in the sibling usage-counter-race batch —
was implemented first. Before trusting it, I ran the SAME negative-control
discipline that batch established: temporarily disabled the lock, re-ran the full
test suite, and compared. Two findings:

1. **No correctness benefit.** Every concurrent `updateProgress`/`saveProgress`
   pairing I could construct via `Future.wait` landed correctly identically with
   or without the lock — the same structural-safety class as
   `UsageCounterService.increment()`'s own finding (Hive's `Box.put()` lands its
   in-memory mutation synchronously; `Future.wait([a(), b()])` runs `a()` fully to
   its own first suspend point before `b()` is even invoked).
2. **A real regression.** With the lock in place, 2 pre-existing tests in
   `streak_decay_reckon_permanent_ledger_test.dart` started failing — one with a
   `HiveError: Box not found` (a now-delayed unawaited write resolving after
   `tearDown` closed the boxes), one with a direct assertion failure
   (`Expected: <1> Actual: <7>` — the write hadn't landed by the time the test
   asserted). Root cause: `StreakProgressService.commitConsume` and
   `WorkoutRepository._persistCurrentStreakDays` both fire **un-awaited**
   `updateProgress` calls within a single `reckonStreakDecayAndPersist()` flow.
   Pre-lock, both landed independently (per finding 1's mechanism). Post-lock, the
   second call had to genuinely suspend waiting for the first to release the
   mutex — a real timing change that neither caller nor the existing tests
   anticipated, because nothing about their code changed, only how long their
   fire-and-forget call now took to settle.

Net: no proven benefit, one concrete regression. The mutex was removed rather than
patched around (e.g. by making the tests await longer) — that would have been
papering over a real behavioral change with no offsetting correctness gain. This
is a useful, generalizable lesson for this codebase: **a lock is not free even when
it "can't hurt"** — for any writer with unawaited, fire-and-forget callers (a
pattern used throughout this codebase's WriteService family for cloud-sync calls,
and here also for same-process Hive writes), adding serialization can silently
lengthen how long those calls take to settle, and any test relying on "fire and
forget settles fast enough" can break without the lock's own correctness case
being wrong.

## The fix

1. **`pro_phase_advance.dart:103-121`** (`_advanceProPhaseIfExpired`) — converted
   from `saveProgress(Map.from(progressReadBeforeTheAwait))` to
   `updateProgress({4 specific fields})`. Directly closes the confirmed bug: any
   writer landing during the real `autoGenerateNextPhaseIfNeeded` await is no
   longer clobbered, because `updateProgress` always re-reads `getProgress()`
   fresh at write time. Side effect: this path previously left `user_progress`
   stale in the cloud after every PRO phase advance (`saveProgress` fires no
   internal sync; only `updateProgress` does) — now fixed for free.
2. **`simulation_service.dart:560-573`** (`_maybeAdvancePhase`) — identical
   conversion in the debug-only `/dev`-panel sim harness (same bug shape,
   confirmed by reading the file directly, not assumed from the sibling fix).
3. **`badge_service.dart`** — doc comments only. `checkAndUnlock`/`checkAll`
   confirmed fully synchronous (no `await` between the badges-map read and
   write), so the claimed HIGH race does not exist today. Not locked (would be
   unjustified complexity for a non-live race) — pinned instead with a
   source-grep tripwire test asserting neither method ever becomes `async`.
4. **`health_sync_service.dart`** — new `Future<void>? _syncInFlight` guard.
   `syncToHive()` is called both on app launch and from the Settings health-sync
   toggle; its only real await gap sits BEFORE its weight read-check-write
   (inside `fetchLatestWeight`), not between the check and the write, so two
   overlapping calls can both pass the `existing == null` guard before either
   writes. The old `syncToHive` body is now private (`_syncToHiveLocked`); the
   new public `syncToHive()` makes a second concurrent caller await the FIRST
   call's in-flight future instead of independently re-running the fetch and the
   unguarded check-write.

## Round-1 review: 2 findings, one fixed here, one spun out (not silently dropped)

Independent, context-blind round-1 review (general-purpose agent, per §4.12)
re-verified every claim above against the actual code rather than trusting this
doc's prose — including independently reading the pinned Hive 2.2.3 package
source to re-derive the synchronous-`Box.put()` claim from first principles,
rather than trusting it as asserted. Two findings:

1. **P2, fixed in this batch:** `health_sync_service.dart`'s new `_syncInFlight`
   guard called `completer.complete()` unconditionally inside `finally`,
   regardless of whether `_syncToHiveLocked()` succeeded or threw. A deduped
   follower caller (one that got `return inFlight`) would silently observe
   SUCCESS even when the leader's sync actually failed —
   `profile_provider.dart:516`'s `BiometricNotifier.toggleSync` (the Settings
   toggle handler, itself with no surrounding try/catch) would believe an
   in-flight-but-failing sync succeeded and never surface or record the
   failure. Fixed: `complete()` now only follows a successful await;
   `completeError()` + `rethrow` live in a `catch`, so every follower sees the
   SAME outcome the leader did. Pinned by a new test in
   `health_sync_service_dedup_test.dart` asserting `complete()` is not the
   unconditional statement inside `finally`.
2. **P2, NOT fixed here — spun out as a new, explicitly tracked follow-up
   (Unit 3c), same reasoning as Unit 3b's split:** `graduation_screen.dart`'s
   `_onPro()` (lines 560-670) has the SAME general bug class this diagnose-doc
   is about — `currentPhase`/`nextPhase` are computed at lines 568/573, BEFORE
   the slow `await scheduleSvc.generateAndSchedule(...)` (lines 642-659, the
   same "real, slow plan-generation" shape as the fixed bug) — then the
   pre-await `nextPhase` value is written via `updateProgress({'current_phase':
   nextPhase, ...})` at line 665. Unlike the fixed bug, this already uses
   `updateProgress(delta)` (not a stale-snapshot whole-map `saveProgress`), so
   the blast radius is narrower — only `current_phase`/`current_week`/
   `phase_started_at`/`plan_generated_at` are at risk, not the WHOLE map, and
   only if an independent concurrent advance (e.g. the splash's silent
   `pro_phase_advance.dart` auto-advance) lands during this specific window.
   The file's own author was demonstrably aware of an adjacent race — lines
   591-604 already re-check `current_phase` and abort-to-`/train` if it
   changed — but that check only guards the CHOICE-SHEET wait window, not the
   `generateAndSchedule` await, which is the actually slow operation. NOT a
   mechanical copy of this unit's fix: `generateAndSchedule` has already run
   and produced real schedule rows for `nextPhase` by the time of the stale
   write, so the correct resolution (abort and discard the just-generated
   plan? re-target it? merge?) needs its own design, not a delta-conversion.
   Scoped out rather than rushed, matching this repo's own "when a fix needs
   genuinely new design, split it — don't force it into the current unit"
   precedent (§4.12) already applied once in this same diagnose-doc for Unit
   3b. Tracked here, in the board correction, and in the plan-review record —
   not silently dropped.

## Round-2 review: 4 findings, all fixed here — including a real bug in round-1's own fix

Independent, context-blind round-2 review (a different general-purpose agent,
no memory of round-1) ran on the round-1-hardened diff, per §4.12's explicit
requirement that round 2 re-review the diff INCLUDING round-1's own
corrections, not just the original. It re-verified the mutex-removal claim by
reading `user_repository.dart` directly (confirmed zero lock code remains),
independently re-derived the synchronous-`Box.put()` claim from the pinned
Hive 2.2.3 source (not trusted from this doc), re-ran all 13 tests live, and
grepped `lib/` fresh for every remaining `saveProgress`/`updateProgress`
caller to check for un-fixed instances of the same bug class (found none).
Four findings, all fixed in this pass:

1. **P1, fixed — a real bug in round-1's own completer fix, exactly the risk
   §4.12 names ("the corrections themselves can introduce new defects").**
   `health_sync_service.dart`'s `syncToHive()` creates a `Completer` and
   stores `completer.future` in `_syncInFlight`, but in the common case —
   no concurrent follower ever calls `syncToHive()` while one is in flight —
   nobody ever attaches a listener to that Future; the leader observes its
   own outcome through a SEPARATE Future (the `syncToHive()` async function's
   own, via `rethrow`). Dart treats `completer.completeError()` on a Future
   with no listener as an unhandled error and reports it a SECOND time to the
   current `Zone`. **Independently reproduced, not taken on the reviewing
   agent's word**: a minimal repro (`Completer` stashed in a field,
   `completeError` called, `rethrow`, no follower, inside
   `runZonedGuarded`) fired the zone's `onError` a duplicate time for every
   leader-only failure, and did NOT fire when a follower genuinely attached
   its own listener — confirming the bug hits exactly the common case, not
   the rare concurrent one. Traced the live wiring: `main.dart` wraps
   `runApp()` in `runZonedGuarded`, whose `onError` forwards to
   `FlutterError.onError` = `FirebaseCrashlytics.instance.recordFlutterFatalError`
   — so every ordinary `syncToHive()` failure was about to also report a
   spurious duplicate FATAL crash, on top of whatever the real caller already
   does (`checkAndSync`'s non-fatal telemetry, splash's silent swallow, or
   `toggleSync`'s uncaught propagation). Fixed by attaching a no-op
   `completer.future.catchError((_) {})` immediately after creating the
   completer, before the first `await` — verified empirically (a second
   repro) that this silences the phantom duplicate report WITHOUT preventing
   a real follower from independently observing the true outcome via its own
   listener on the same Future (Future listeners fan out, they don't
   consume). Pinned by a new test in `health_sync_service_dedup_test.dart`
   asserting the silencing listener is attached before the first `await`.
2. **P3, fixed — stale line citation.** This doc's `writers:` field cited
   `_syncToHiveLocked` at "line 177"; verified against the live file, line
   177 is inside `syncToHive`'s own closing-brace region — `_syncToHiveLocked`
   is actually defined at line 189. Corrected above.
3. **P3, fixed — a test that didn't scan what its name claimed.**
   `badge_service_synchronous_invariant_test.dart`'s "neither method contains
   an await keyword" test computed its scan region as
   `source.substring(checkAndUnlockStart, checkAllStart)` — i.e. everything
   FROM `checkAndUnlock`'s start UP TO (not including) `checkAll`'s start,
   which excluded `checkAll`'s own body entirely. Confirmed via direct read:
   not a live safety gap (the sibling "`checkAll` is not declared `async`"
   test already fully guarantees `checkAll` has no `await`, since Dart
   requires `async` for `await` to appear at all) but a genuine test-quality
   defect — the test's name and its actual coverage disagreed. Fixed by
   scanning from `checkAndUnlockStart` to the end of the source (`checkAll`
   is the last method in the class, so this covers both bodies with no risk
   of a false positive from an unrelated later method).
4. **P3, fixed — a stale, never-recounted "9 files" figure repeated in two
   places without being recomputed as the underlying list grew across
   passes.** Both this doc's `symptom:`/`readers:` fields and
   `open_issues.md`'s OI-45 writer census said "12+ callsites across 9
   files," but each field's OWN enumerated file list actually contained more
   than 9 (10 in this doc's `readers:` field, 11 in the board's writer
   census) — the count had been set early and copy-pasted forward rather
   than recounted. Resolved with a single fresh, precise count (not another
   guess): `grep -rn '\.updateProgress(\|\.saveProgress('` across `lib/`
   found **15 write callsites (13 updateProgress + 2 saveProgress) across 11
   files** (10 external callers + `user_repository.dart` itself, where
   `saveProgress`'s own body performs the actual Hive `put`). This doc and
   the board now both state that number. No functional impact either way —
   this was a documentation-accuracy nit, not a code defect.

**Explicitly checked and found clean by round-2** (stated so the checks don't
need re-doing next round): no other `saveProgress`/`updateProgress` caller in
`lib/` has the fixed bug's stale-whole-map-snapshot-across-a-slow-await shape;
`updateProgress`'s own implementation has no stale-read risk of its own
(no `await` between its read and write); `badge_service.dart`'s "no live
race" claim holds by direct read; all 13 tests pass live; `flutter analyze`
is clean except the one pre-existing, correctly-disclosed `badge_service.dart`
hive-import info-lint; `OPEN_INDEX.md` regenerates byte-identical (no stale
hand-edit); the Unit 3c `graduation_screen.dart` bug is real (independently
re-verified by direct read, including that the file's existing
`current_phase` re-check at lines 591-604 only guards the choice-sheet wait
window and does not run at all on the default path) and is genuinely tracked,
not silently dropped; blast radius of the actual behavior change is confined
to the 2 fixed call sites plus the new health-sync dedup guard, with no other
`updateProgress` caller (13 grepped call sites across 11 files) behaviorally
affected.

## B-pass review: 4 findings — 3 fixed, 1 spawned as a tracked follow-up

The mandatory self-triggered ≥account B-pass (§4.3, review file in
`docs/reviews/`, named after this diff's final staging hash per
`scripts/check_code_review_pass_exists.dart`'s own convention — not quoted
literally here, since editing this exact sentence to cite it would itself
change the hash it's citing, a self-reference this doc doesn't need to chase)
ran on the round-2-hardened diff — a third, independent pass, fresh Sonnet,
no memory of rounds 1-2. Dispatched against an earlier staging hash than the
diff's final one; findings 1-3's own fixes (below) added
`docs/blast_radius.yaml` + a new test file, which moved the hash again after
dispatch — expected and harmless, since the review's content (the findings
and their verification) doesn't depend on the hash, only the FILENAME does,
and the filename was set once the diff finished changing. Found and I
independently re-verified 4 findings:

1. **P2, fixed — a real, load-bearing gap in `docs/blast_radius.yaml` itself,**
   found via the diff's own `blast_radius_mismatch` lens, not a code defect in
   this batch's fix. The registry's catch-all comment has said
   "lib/shared/repositories ... is account" since it was written, but no rule
   ever implemented it — `lib/shared/repositories/**` fell through to the
   `lib/shared/** -> feature` catch-all (first-match-wins). Independently
   reproduced via the classifier's own stdin mode before fixing:
   `printf 'lib/shared/repositories/user_repository.dart\n' | dart run
   scripts/blast_radius_from_diff.dart -` returned `feature`. Same mechanism
   hit `graduation_screen.dart` (Unit 3c's target — a confirmed direct
   progress-map writer) via the `lib/features/train/** -> feature` catch-all.
   This meant Units 3b and 3c, both already queued as this batch's own
   follow-ups, would each silently clear ZERO review gate if they didn't also
   happen to touch a `lib/core/services/**` file. Fixed with two new, narrowly
   scoped rules (`lib/shared/repositories/**` and the single file
   `graduation_screen.dart`, not the whole `lib/features/train/**` tree —
   verified the rest of that tree still classifies `feature`, and
   `lib/shared/repositories/plan_engine/**` still classifies `platform`, so
   neither existing tier was disturbed) plus a new behavioral test,
   `test/contracts/blast_radius_progress_map_writer_paths_test.dart`, that
   spawns the real classifier subprocess against 4 real paths (2 fixed, 2
   controls) rather than grepping the yaml text.
2. **P2, fixed — a test that proved less than its name implied.**
   `test/contracts/user_repository_progress_stale_snapshot_test.dart`'s
   "do not corrupt each other" concurrent-dispatch test only ever asserted 2
   of the 3 fields genuinely in play. Independently reproduced (a temporary
   `print`, reverted immediately after, confirmed via `git diff` the file
   matched its prior staged state exactly before making the real fix):
   `total_workouts_done` comes back `null` — NOT a bug, but `saveProgress`'s
   real, intentional REPLACE-not-merge contract dropping a field the
   concurrently-dispatched `updateProgress` call had just set, because
   `saveProgress` (dispatched second in the list) fully overwrites the map
   with only its own 2 literal keys. Not exploitable in shipped code today
   (this batch's own fresh writer census, item 4 above, confirms the only 2
   real `saveProgress` callers — `simulation_service.dart`'s dev-only
   `resetJourney`, `onboarding_provider.dart`'s first-ever write to a
   brand-new account — never run concurrently with an `updateProgress` call
   on the same session) but a genuine, previously-undocumented sharp edge on
   a public repository method. Fixed by: renaming the test to say what it
   actually proves, adding the missing `isNull` assertion with a reason
   explaining it's the REAL contract (not a bug this test pins as fixed), and
   a new warning paragraph on `UserRepository.saveProgress`'s own doc comment
   telling future callers to use `updateProgress(delta)` instead whenever
   they don't hold the complete authoritative state.
3. **P3, fixed — stale test-filename citation.** `UserRepository.updateProgress`'s
   doc comment cited `user_repository_progress_lock_behavioral_test.dart` (a
   leftover from before the Completer-mutex design — hinted by "lock" in the
   name — was tried and removed) as proof of the fix; that file was never
   committed under that name. The real file is
   `user_repository_progress_stale_snapshot_test.dart`. Corrected; confirmed
   via `grep -rn "user_repository_progress_lock_behavioral_test"` across the
   whole repo now returns zero hits.
4. **P2, NOT fixed here — spawned as a tracked follow-up (live task #41),
   same "split rather than force it in" reasoning already applied twice above
   for Units 3b/3c:** the ONLY regression test for this diagnose-doc's central
   bug (`user_repository_progress_stale_snapshot_test.dart`) proves the bug
   PATTERN was real using `UserRepository`'s own primitives directly — its
   own header comment already discloses this — but never calls the actual
   production functions that had the confirmed bug
   (`advanceProPhaseIfExpired`/`_advanceProPhaseIfExpired` in
   `pro_phase_advance.dart`, `_maybeAdvancePhase` in `simulation_service.dart`).
   Independently confirmed via `grep -rln "pro_phase_advance\.dart\|
   simulation_service\.dart" test/`: every existing test referencing these
   functions (`phase_repeat_nudge_test.dart`, `pro_phase_expiry_surface_test.dart`,
   `splash_post_auth_session_gate_test.dart`) is `File(...).readAsStringSync()`
   source-grep style, none invoke the real functions — so if a future edit
   reverted either fixed callsite back to `saveProgress(Map.from(staleSnapshot))`,
   no test in the suite would fail. NOT a live gap in the fix's correctness
   (already proven by direct reproduction, see the writers/readers fields
   above) — a rule-21 coverage gap. Not fixed inline: `advanceProPhaseIfExpired`
   requires a real `WidgetRef` (obtainable via the widget-bridge pattern
   already established in
   `test/contracts/day_rollover_provider_invalidation_behavioral_test.dart`)
   PLUS driving `WorkoutScheduleService.autoGenerateNextPhaseIfNeeded` for
   real (it's local Dart, no network calls, per CLAUDE.md's plan-generator
   rule) — `WorkoutScheduleService` is a concrete ~15-method singleton facade,
   not abstract/interface-based, so there's no cheap fake to substitute; a
   proper test needs real exercise-library + profile + subscription Hive
   fixtures. Genuinely novel test infrastructure, not a quick extension of an
   existing pattern (confirmed via grep — no `workoutScheduleServiceProvider`
   override exists anywhere in the suite today) — disproportionate to build
   under this same B-pass remediation pass. Tracked as task #41, not silently
   dropped.

## Residuals, stated explicitly (not silently deferred)

- **Unit 3b (not started):** cross-device optimistic locking for the `progress`
  map. Requires: (a) finally wiring the dormant `update_streak_progress` RPC into
  `syncFreezes()`; (b) a NEW sibling RPC covering the ~10-11 fields
  `_syncUserProgress` pushes today with zero version protection; (c) local
  version-tracking (a new Hive field, `progress['streak_progress_version']`,
  reusing the existing `streak_progress_version` column as a whole-row optimistic
  counter rather than adding a second, since it's one row); (d) retry-on-mismatch
  semantics, bounded to a single re-fetch + drop (matching this codebase's
  established fire-and-forget-self-heals-on-next-write philosophy, not a new
  queue). OI-45 stays OPEN until this lands.
- **Unit 3c (not started, found by round-1 review):** `graduation_screen.dart`'s
  `_onPro()` writes a `nextPhase` value computed BEFORE the slow
  `generateAndSchedule` await, not re-derived after it — see "Round-1 review"
  above for the full account. Narrower blast radius than the fixed bug (delta
  write, not whole-map), needs real conflict-resolution design (not a
  mechanical fix), tracked explicitly rather than silently dropped.
- **Behavioral test for the real phase-advance callsites (not started, found
  by B-pass, live task #41):** see "B-pass review" finding 4 above.
  `advanceProPhaseIfExpired`/`_maybeAdvancePhase` — the actual production
  functions this diagnose-doc's central bug fix touches — have zero
  behavioral test coverage; only the bug PATTERN is proven, via
  `UserRepository`'s own primitives, not the real callsites. A regression to
  either fixed function today would pass the full suite. Needs the
  `day_rollover_provider_invalidation_behavioral_test.dart` WidgetRef-bridge
  pattern plus real exercise-library/profile/subscription Hive fixtures to
  drive `WorkoutScheduleService.autoGenerateNextPhaseIfNeeded` for real.
- Unit 3a does NOT change server-side protection for ANY progress field — same-
  device races (the confirmed bug) are closed; cross-device races (unconfirmed,
  no known live incident, migration 056 sat unwired for 2.5 months with no
  reported symptom) are not addressed here.
