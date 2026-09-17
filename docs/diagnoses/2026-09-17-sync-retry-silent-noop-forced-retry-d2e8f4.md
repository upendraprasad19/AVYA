---
bug_id: d2e8f4
date: 2026-09-17
batch: sync-banner-force-retry
status: fixed
blast_radius: account
symptom: >-
  Founder observed the SyncBanner ("1 change waiting to sync") on the webapp
  as test2@gmail.com at 23:17 IST 2026-09-17 and asked whether yesterday's
  auto-drain fix (b7c2a9) had broken. Live verification showed the banner
  appeared from a login-time user_progress version conflict that enqueued a
  sync_user_progress op, and the 5-min auto-drain cleared it at 23:22:38 IST
  (cloud row updated_at) — the fix working as designed. The observation
  surfaced two adjacent UX defects on the same surface instead: (1) the
  manual Retry tap can be a SILENT NO-OP — retryNow() issues a plain
  drain() whose _isDue backoff filter skips any op inside its backoff
  window, so the user taps and nothing happens, with zero feedback; and
  (2) the banner flashes for self-healing conflicts that resolve without
  user action within one drain tick. Batch: force-retry (this doc) + banner
  grace policy (feat commit, same batch).
concept: sync_queue_auto_drain_triggers
recurrence: >-
  New defect class, but same concept as b7c2a9 (the previous diagnose-doc
  for this surface, one day earlier). Grepped docs/diagnoses/INDEX.md for
  "Retry" / "backoff" / "silent" — b7c2a9 is the only prior instance; its
  round-2 review explicitly noted the bare in-flight guard would make Retry
  "a silent no-op whenever it races an in-flight auto-drain" and fixed the
  COALESCING side; the BACKOFF side (this doc) was reachable only after
  auto-drain made queued ops routine — a same-day follow-up, not a missed
  fix in b7c2a9.
sot_registry_entry: not_applicable — retry-queue delivery-trigger + banner display policy internal to lib/core/services/sync_queue.dart and lib/shared/providers/sync_state_provider.dart; no Hive/Postgres writer/reader concept with an external contract (same scope as b7c2a9's record).
writers:
  - { file: lib/core/services/sync_queue.dart, method: "SyncQueue.drain — force param (signature :282) now bypasses the _isDue backoff filter for the manual pass (:299); mid-pass force merged at the TOP of the loop (:295) and all rerun state reset in finally (:317-319)", line: 282 }
  - { file: lib/shared/providers/sync_state_provider.dart, method: "SyncStateNotifier.retryNow — now issues drain(force: true) (:227) behind the disable_sync_force_retry kill-switch", line: 222 }
  - { file: lib/core/services/sync_queue.dart, method: "SyncQueue.enqueueFresh — added the missing _notifyPending() after the immediate attempt (:263; pre-existing count-stream gap, round 2 Finding 4)", line: 263 }
readers:
  - { file: lib/shared/providers/sync_state_provider.dart, method_or_widget: "SyncStateNotifier._stateFor (:144) — the ONE funnel for seed/stream-event/timer state; applies the grace policy via syncBannerDisplayCount (:80) to the count the SyncBanner renders", line: 144 }
  - { file: lib/shared/widgets/sync_banner.dart, method_or_widget: "SyncBanner.build — consumes the provider state (count semantics change from raw queue depth to displayable depth); widget itself untouched", line: 24 }
hive_key_prefix: pending_sync_<id> (unchanged — no key shape, formula, or box change)
hive_key_formula: "'pending_sync_${op.id}'"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/sync_queue_force_retry_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "retryNow body issuing a plain drain() without the _forceRetryDisabled gate", absent_after_fix: true }
  - { pattern: "auto-drain call sites (splash_screen.dart, connectivity listener, periodic timer) passing force: true", absent_after_fix: true }
proposed_fix: >-
  Two changes. (1) `drain({bool force = false})`: the manual Retry tap now
  bypasses the `_isDue` backoff filter, so an op sitting inside its window
  is retried NOW instead of the tap silently doing nothing. Safety: every
  registered executor is idempotent by construction and the progress
  executor re-reads fresh Hive state at drain time
  (sync_service.dart:716-749), so an early forced attempt cannot push
  stale data; a failed forced attempt resumes normal backoff (retryCount
  still increments, budget still 7). A force request arriving WHILE a pass
  is in flight forces the coalesced RERUN pass — merged at the TOP of the
  loop (capture-then-apply), because a bottom-merge is one pass late and
  can be dropped entirely (plan-review round 2 Finding 1, P0). All rerun
  state resets in `finally` so an exception mid-pass cannot leak a forced
  pass into the next drain call (round 2 Finding 3, P1). Auto triggers
  (splash app-launch, connectivity restore, 5-min timer) stay unforced —
  force is per-call, never ambient. Also (2): banner display grace
  (feat commit, same batch) — the provider now renders only ops older than
  syncBannerGraceWindow (6 min = one drain tick + slack), via ONE state
  funnel (_stateFor) shared by seed/stream/timer, so a self-healing
  login-time conflict never flashes the banner while aged debt still
  surfaces; a 1-min display-aging timer catches ops crossing the threshold
  with no queue event (the stream notifies on mutations, not age
  crossings). Kill-switches disable_sync_force_retry /
  disable_sync_banner_grace (§4.6; sync surface), each restoring exactly
  the pre-batch behavior. Plus the round-2-surfaced pre-existing
  enqueueFresh notify gap (Finding 4) and the phantom
  sync_queue_retry_budget_consistency_test.dart comment promise, now
  backed by a real end-to-end budget test (7 attempts then dead-letter).
regression_test_planned:
  - test/contracts/sync_queue_force_retry_test.dart
  - test/contracts/sync_queue_auto_drain_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter analyze (4 touched files: No issues found) + both test files 43/43 green (9 new + 34 in the extended file). MUTATION m1 (force gate neutered): removed '!passForce && ' from sync_queue.dart:299 (confirmed applied: grep '!passForce' -> 0 matches), reran sync_queue_force_retry_test.dart -> 5 of 6 reddened (every scenario except the enqueueFresh-notify one — the skip-path, the dead-letter path, the sticky-rerun path, and the never-leak regression all exercise the filter); restored (grep -> 1 match) -> 6/6 green. MUTATION m2 (grace -> Duration.zero, confirmed applied: grep 'minutes: 6' -> 0): reran sync_queue_auto_drain_test.dart -> 2 reddened — the 6-min constant pin (trivial) and the MIXED-AGES count test (fixed ages 2m/7m/30s/26m: all 4 counted, expected 2). NOTE: the 'just under the grace window' test is parameterized OFF the constant, so it self-adjusts and is NOT an m2 discriminator — the fixed-age mixed test is. Restored -> 34/34 green. MUTATION m3 (capture/reset swapped — reset before capture, confirmed applied by reading lines 293-295): reran force-retry file -> exactly 1 reddened (the sticky-rerun scenario: attempts==1, expected 2 — the unforced rerun skipped the 5s-backoff op); restored -> 6/6 green. MUTATION m4 (enqueueFresh notify removed via edit, confirmed applied: grep 'Notify AFTER' -> 0): reran -> exactly 1 reddened (stream-ends-at-0); restored -> green. LESSON RECORDED: the m3 mutation's first regex application SILENTLY FAILED to match (CRLF) and the m4 RESTORE initially landed inside the drain loop instead of enqueueFresh — both caught by re-reading the file/grep before believing results, exactly the confirm-applied trap rule 21 warns about." }
  - { tier: 2_hive, status: verified, evidence: "no Hive key shape or box changed — pending_sync_<id> rows written/read exactly as before; the new public pendingOps() accessor wraps the existing _loadAll(). The behavioral tests drive the REAL syncBox (Hive.init tempDir + openBox + markInitializedForTests, per bodyweight_capability_leak_test.dart precedent)." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement — drain() calls the same registered executors with the same payloads" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no new write path — only a new bypass of the backoff filter on the existing path" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function involvement" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no new platform channel; connectivity_plus was already a dependency from b7c2a9" }
  - { tier: 12_client_server_contract, status: not_applicable, evidence: "no client-server contract change — same executors, same payloads; the retryCount/backoff budget is unchanged (pinned end-to-end by the budget test: dead-letter on the 7th total attempt)" }
impact_analysis: >-
  Account-tier (lib/core/services/** glob per docs/blast_radius.yaml:338;
  no pubspec change, so no platform bump — both rounds verified). Additive
  trigger semantics on the EXISTING drain path; no new payload shape, no
  backoff/dead-letter change (budget pinned). Deliberate behavioral note:
  a forced drain against a cross-account marker op (executor refuses with
  non-transient ValidationError, sync_service.dart:730-749) dead-letters
  on the FIRST tap — correct (it can never succeed) and now pinned by the
  dead-letter scenario. A THROWING executor remains out of contract
  (_runOne has no try/catch; a throw aborts the remaining ops in that
  pass and leaves the op queued) — pre-existing, out of scope, noted for a
  future batch. Banner copy can now UNDERCOUNT transiently (aged op
  succeeds while a young op is still queued) — the intended tradeoff,
  documented in docs/architecture/sync.md's display-policy note rather
  than "fixed". Both kill-switches ON = exactly today's pre-batch
  behavior (raw count + plain retry), verified by round 1 Finding 10.
---

# The manual Retry tap could silently no-op on a backoff-windowed op (and the banner flashed for self-healing conflicts)

## What was actually wrong

Two defects on the surface yesterday's `b7c2a9` made busy:

1. **Silent no-op Retry.** `retryNow()` (`sync_state_provider.dart:126-128`
   pre-fix) issued a plain `drain()`. `drain()`'s op loop filters through
   `_isDue` (`sync_queue.dart:127-132`) — a time-based backoff check. An op
   that has failed recently sits in its window (1s → 5s → 30s → 5m → 30m →
   2h → 24h), so the user taps "Retry" and the filter skips the op with
   zero feedback: the banner stays, the tap does nothing. The coalescing
   fix in b7c2a9's round 2 covered only the in-flight race, not the
   backoff skip.

2. **Banner flash for self-healing conflicts.** Live observation
   (2026-09-17 23:17 IST, test2 on web): a login-time `user_progress`
   version conflict enqueued a marker op; the 5-min auto-drain resolved it
   at 23:22:38 (cloud row `updated_at`); the banner flashed "1 change
   waiting to sync" for ~5 minutes for something the queue fixed without
   the user. Honest, but alarming for a no-action event.

**Also found by plan-review round 2 (pre-existing):** `enqueueFresh`'s
success path removes the op with no `_notifyPending()` — every other
mutator notifies (`enqueue:224`, `_deadLetter:339`, drain end-of-pass,
`clearAll`) — so a pushSnapshot-style fresh op that succeeded immediately
left the pending-count stream at 1 until an unrelated event. And
`sync_queue.dart`'s header comment promised
`test/contracts/sync_queue_retry_budget_consistency_test.dart` "(lands in
B2 continuation)" — a file that has never existed (glob + audit finding
corroboration); the batch adds the real end-to-end budget test instead of
leaving the phantom citation.

## The fix

`lib/core/services/sync_queue.dart`: `drain({bool force = false})` —
`!passForce && !_isDue(...)` keeps auto passes time-gated while the manual
pass (and a mid-pass force request, via the sticky `_rerunForce` merged at
the TOP of the coalesced rerun) bypasses the filter. All rerun state
resets in `finally`. `enqueueFresh` notifies after its immediate attempt.

`lib/shared/providers/sync_state_provider.dart`: `retryNow()` →
`drain(force: true)` behind `disable_sync_force_retry`; banner state flows
through ONE funnel `_stateFor` (seed/stream/1-min aging timer) applying
`syncBannerGraceWindow` (6 min) behind `disable_sync_banner_grace`.

## Regression tests

- `test/contracts/sync_queue_force_retry_test.dart` (behavioral, real
  Hive syncBox + fake executor): plain-drain skips a backoff-windowed op
  (m1 target) / forced retry clears it / non-transient failure
  dead-letters immediately / sticky force across an in-flight pass (m3
  target) / plain drain never force-retries / enqueueFresh stream ends at
  0 (m4 target) / budget: dead-letter exactly on the 7th total attempt.
- `test/contracts/sync_queue_auto_drain_test.dart` (extended): grace
  count policy table (m2 target), both new kill-switch predicate tables,
  constants, and structural pins (repointed drain anchor + 800-char
  window, display timer after the drain timer, funnel through `_stateFor`,
  retryNow force + fallback, auto/splash drains stay unforced, defensive
  kill-switch getters).

Mutation proofs (each confirmed applied by grep before the green run):
m1 `!passForce && ` removed → scenario-1 skip + scenario-4 never-leak
redden; m2 grace → `Duration.zero` → "just under the window" reddens;
m3 capture/reset swapped → sticky-rerun reddens; m4 enqueueFresh notify
removed → stream-ends-at-0 reddens.

## Post-review remediation (plan-review rounds 1 + 2)

Round 1 (10 findings): repoint the drain source-grep anchor (the old
literal breaks on the new signature — both tests failed at the anchor),
window 500→800; capture-before-reset ordering specified; display timer
joins `ref.onDispose`; ONE state funnel for all producers; scenario 2
returns `Result.err` not throws (`_runOne` has no try/catch); scenario 1
pinned to the enqueue path with a legible <900ms premise guard; lighter
Hive setup precedent; dead-letter-on-force documented; undercount
documented; phantom test promise corrected.

Round 2 (2×P0, 1×P1, 1×P2 pre-existing): sticky-force merged at the TOP
of the loop (a bottom-merge was one pass late and droppable); sticky
scenario re-specced off `enqueueFresh` (which awaits `_runOne` internally
— deadlocked the old shape) to a backdated `enqueue` seed; `finally`
resets both rerun flags; `enqueueFresh` notify gap fixed + pinned; window
re-derived to 800.

## OWED live verification

After the Vercel deploy: on web as test2 — (1) a queued op inside a
backoff window shows the banner after grace and the Retry tap actually
re-attempts it; (2) a self-healing login conflict produces no banner.
Related observe-first artifact: the 2026-09-17 sighting needed no fix —
`b7c2a9`'s auto-drain cleared it at 23:22:38 IST exactly as designed.
