---
bug_id: b7c2a9
date: 2026-09-16
batch: obs-batch-2026-09-16
status: fixed
blast_radius: account
symptom: >-
  Founder saw a "2 changes waiting to sync" banner with a Retry action on the
  Home screen (logged in as upendra), unprompted. Tapping Retry resolved it
  immediately. Founder asked what happened and why manual intervention was
  needed.
concept: sync_queue_auto_drain_triggers
recurrence: >-
  New. Grepped docs/diagnoses/INDEX.md and the memory feedback_*.md files for
  "stuck sync" / "pending sync" / "Retry" — no matching prior diagnose-doc.
  Not a recurrence of a previously-fixed bug; this is the first time the gap
  between `sync_queue.dart`'s documented design and its actual wiring has
  been diagnosed.
sot_registry_entry: not_applicable — this is a retry-queue delivery-trigger mechanism internal to lib/core/services/sync_queue.dart, not a Hive/Postgres writer/reader concept with an external contract.
writers:
  - { file: lib/shared/providers/sync_state_provider.dart, method: "SyncStateNotifier.build — Connectivity().onConnectivityChanged listener", line: 89 }
  - { file: lib/shared/providers/sync_state_provider.dart, method: "SyncStateNotifier.build — Timer.periodic(syncQueueAutoDrainInterval)", line: 104 }
readers:
  - { file: lib/core/services/sync_queue.dart, method: "SyncQueue.drain — iterates due ops and retries each via its registered executor", line: 239 }
hive_key_prefix: pending_sync_<id> (unchanged by this fix — see sync_queue.dart _persist/_loadAll)
hive_key_formula: "'pending_sync_${op.id}'"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/sync_queue_auto_drain_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "sync_queue.dart doc comment claiming a drain trigger with zero real SyncQueue.instance.drain() call sites implementing it", absent_after_fix: true }
proposed_fix: >-
  `sync_queue.dart`'s own doc comment claimed FOUR drain triggers: app
  launch, connectivity restore (via connectivity_plus), a 5-min periodic
  timer, and the manual Retry tap. Grepping every
  `SyncQueue.instance.drain()` call site in lib/ found exactly two: app
  launch (`splash_screen.dart:256`) and the manual tap
  (`sync_state_provider.dart`'s pre-existing `retryNow()`).
  `connectivity_plus` was not even a pubspec.yaml dependency, and no
  `Timer.periodic` anywhere called `drain()`. Added both missing triggers to
  `SyncStateNotifier.build` (the provider already manages a subscription
  lifecycle via `ref.onDispose`, so it's the natural home): a
  `connectivity_plus` listener that drains on any connectivity-restore event
  (gated through the extracted pure `shouldDrainOnConnectivityChange`), and
  a `Timer.periodic(syncQueueAutoDrainInterval)` (5 min, matching the
  documented interval) that drains unconditionally. Simplified one claim
  rather than chasing it: the periodic timer is NOT foreground-gated (the
  doc comment said "while app foregrounded") — `drain()` is a no-op when
  nothing is due, and most platforms suspend/throttle background timers
  anyway, so the simpler always-on timer is a strict improvement over the
  pre-fix "never" state without the added complexity of wiring
  `WidgetsBindingObserver` lifecycle tracking into a `Notifier`. Corrected
  `sync_queue.dart`'s header comment and `docs/architecture/sync.md`'s
  stale "pending_sync_queue is planned, not yet implemented" row to match
  reality.
regression_test_planned:
  - test/contracts/sync_queue_auto_drain_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter test test/contracts/sync_queue_auto_drain_test.dart -> 19/19 passed (grew from 11 after the B-pass added the disable_sync_auto_drain kill-switch [Finding 3] and SyncQueue.drain()'s in-flight guard [Finding 4], then 19 after plan-review round 2 added the coalesced-rerun test [round 2 Finding 1]). flutter analyze --no-fatal-infos over the whole worktree -> 0 warnings/errors, and zero issues attributed to sync_state_provider.dart or sync_queue.dart specifically (grepped the analyze log by filename). Mutation-proven (previously missing — B-pass Finding 7): reverted shouldDrainOnConnectivityChange to `=> false;` and reran the file -> exactly 3 of 19 assertions reddened (the three '-> drains' cases: wifi restored, mobile restored, mixed none+wifi); restored and reran -> 19/19 green again. Mutation-proven (round-2 remediation): reverted the coalesced-rerun ('_rerunRequested' + 'do {...} while') back to a bare 'if (_draining) return;' -> exactly 1 of 19 assertions reddened (the new coalescing test); restored and reran -> 19/19 green again." }
  - { tier: 2_hive, status: verified, evidence: "no Hive key SHAPE changed — pending_sync_<id> rows are read/written exactly as before by the pre-existing SyncQueue methods; this fix only adds callers of the already-correct drain()." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement — drain() calls the SAME registered executors (sync_service.dart) that app-launch and manual-retry already called" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no new write path — only new TRIGGERS for the existing drain() path" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function involvement" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: fixed_in_this_batch, evidence: "connectivity_plus added via `flutter pub add connectivity_plus` (resolved to ^7.3.1) — a real platform plugin needing a live device/emulator to fully exercise its channel; flutter test/analyze both pass against the resolved package, which is the tier this repo's own test suite can reach. OWED: manually toggle airplane mode on a real device with a queued offline write and confirm the banner clears without a manual Retry tap, before treating this as closed end-to-end." }
  - { tier: 12_client_server_contract, status: not_applicable, evidence: "no client-server contract change — drain() calls the same executors with the same payloads as before" }
impact_analysis: >-
  Account-tier (lib/core/services/** glob). Purely additive: two new
  triggers call the SAME pre-existing, already-tested `drain()` method that
  app-launch and manual-retry already call — no new write path, no new
  payload shape, no change to backoff/dead-letter logic. **Corrected
  2026-09-16 by B-pass Finding 4** (`docs/reviews/08821dc5a27b-review.md`):
  the safety claim in this paragraph originally attributed "no
  double-submission risk" to `_isDue`'s backoff check — wrong, `_isDue` is
  purely time-based and has no concurrency semantics, so it does nothing to
  stop two overlapping `drain()` calls from both reading and running the
  same due op. The real (pre-existing) safety net is that every registered
  executor is independently idempotent by construction. `drain()` now also
  carries its own in-flight guard (a `_draining` boolean) added during
  triage, since this fix is exactly what turns an occasional overlap (a
  user double-tapping Retry) into a routine one (a connectivity flap
  coinciding with the periodic timer). Also added: a `disable_sync_auto_drain`
  kill-switch (B-pass Finding 3) — this batch's overall blast radius is
  `platform` (via the new `connectivity_plus` pubspec dependency), and
  platform tier requires a rollback lever per `docs/blast_radius.yaml` +
  CLAUDE.md §4.6, which this fix originally shipped without. Real-world
  impact until fixed: an offline write (workout log, nutrition log, profile
  edit, etc.) that failed its first attempt sat queued with NO automatic
  retry path — only an app relaunch or the user noticing the banner and
  tapping Retry would ever clear it, which is a genuine data-durability gap
  for exactly the class of user this queue exists to protect (someone who
  loses connectivity mid-session and doesn't relaunch or check back).
---

# `sync_queue.dart` promised three auto-drain triggers; only one existed

## What was actually wrong

`lib/core/services/sync_queue.dart`'s own header doc comment claimed:

```
/// Drains run on:
///   * App launch (in `main.dart` after Hive opens, before `runApp`)
///   * Connectivity restore (via `connectivity_plus`)
///   * Periodic timer (every 5 min while app foregrounded)
///   * Explicit user "Retry now" tap in `SyncBanner`
```

Grepping every `SyncQueue.instance.drain()` call site in `lib/` found
exactly **two**: `splash_screen.dart:256` (app launch) and
`sync_state_provider.dart`'s pre-existing `retryNow()` (the manual tap).
`connectivity_plus` was not a `pubspec.yaml` dependency at all (confirmed
via a direct grep — zero matches), and no `Timer.periodic` anywhere in the
codebase called `drain()` (the app's other `Timer.periodic` call sites are
all unrelated — a recording ticker, video-render polling, workout timers,
OTP resend, a profile-prediction poll).

So an offline write that failed its first attempt was enqueued correctly,
but nothing automatic ever retried it except a fresh app launch. The
founder's observed banner + successful manual Retry is exactly this gap:
the write was sitting queued, waiting for a trigger that didn't exist,
until the tap ran `drain()` directly.

`docs/architecture/sync.md` independently confirmed the queue was
under-documented in the other direction too — its Hive-boxes table still
described `pending_sync_queue` as "**planned** ... not yet implemented"
long after `sync_queue.dart` shipped and was in active use (it already has
its own regression test file, `sync_queue_progress_marker_test.dart`, from
an earlier batch).

## The fix

Added the two missing triggers to `SyncStateNotifier.build`
(`lib/shared/providers/sync_state_provider.dart`) — the natural home, since
this provider already owns a subscription lifecycle via `ref.onDispose` and
is read early enough (via `SyncBanner`, mounted on Home/Profile) to live for
the app's session:

1. **Connectivity restore.** A `connectivity_plus` listener on
   `Connectivity().onConnectivityChanged`, gated through the extracted pure
   function `shouldDrainOnConnectivityChange` (true when the reported result
   list contains anything other than `none`) before calling `drain()`.
2. **Periodic timer.** `Timer.periodic(syncQueueAutoDrainInterval)` (a named
   5-minute constant, matching the doc comment's interval) calling `drain()`
   unconditionally.

Both are cancelled in the existing `ref.onDispose` alongside the
pre-existing pending-count subscription.

**One documented claim was simplified rather than chased:** the periodic
timer is not foreground-gated, even though the original comment said "while
app foregrounded." `drain()` is a no-op when nothing is due, and most
platforms suspend or throttle background timers anyway, so an occasional
tick while backgrounded is harmless — wiring full `WidgetsBindingObserver`
lifecycle tracking into a `Notifier` for that precision wasn't worth the
added complexity for this fix. `sync_queue.dart`'s header comment was
updated to describe this honestly rather than repeat the stronger claim.

Also corrected `docs/architecture/sync.md`'s stale "planned, not yet
implemented" row.

## Regression test

`test/contracts/sync_queue_auto_drain_test.dart`. `connectivity_plus`'s
stream needs a platform channel a plain `flutter test` can't exercise —
same justification this directory's `sync_queue_progress_marker_test.dart`
already uses for its own live-Supabase-dependent executor wiring — so this
file pins the DECISION logic behaviorally (`shouldDrainOnConnectivityChange`
is real production code under direct unit test, not a copy) and the WIRING
structurally via source-grep: the connectivity listener exists and gates
`drain()` through that exact function; the periodic timer exists at
`syncQueueAutoDrainInterval` and calls `drain()`; both are cancelled in
`ref.onDispose`; and `connectivity_plus` is a real declared `pubspec.yaml`
dependency, not merely an import that happens to resolve today.

Live device verification (airplane-mode toggle with a queued write) is owed
after this ships — see `touched_layers_checked` tier 11 above — since no
`flutter test` run can exercise the real platform channel end-to-end.

## Post-review remediation (B-pass, `docs/reviews/08821dc5a27b-review.md`)

Four findings against this fix specifically, all fixed in this same batch:

- **Finding 3 (P2):** added a `disable_sync_auto_drain` kill-switch (pure
  predicate `isSyncAutoDrainDisabled`, read defensively via `configBox`,
  same convention as `sync_service.dart`'s existing kill-switches) gating
  both new triggers — the platform-tier blast radius this batch carries
  (via the new `connectivity_plus` pubspec dependency) requires one per
  `docs/blast_radius.yaml` + CLAUDE.md §4.6, and this fix originally shipped
  without any rollback lever.
- **Finding 4 (P3):** added an in-flight guard (`_draining`) to
  `SyncQueue.drain()` and corrected the misleading comment/impact_analysis
  claim that attributed concurrency safety to `_isDue` (a time-based check
  with no concurrency semantics at all — the real, pre-existing safety net
  is that every registered executor is idempotent by construction).
  **Plan-review round 2** (`docs/plan-reviews/obs-batch-2026-09-16-round2.md`
  Finding 1) then found the `_draining` guard itself was too blunt: a bare
  `if (_draining) return;` also silently no-ops the pre-existing manual
  "Retry now" tap (`retryNow()` shares this same `drain()`) whenever it
  races an in-flight auto-drain, with zero indication to the user. Added a
  `_rerunRequested` coalesced-rerun flag (the same "in-flight + dirty
  do-while" shape `SyncCoalescer` already uses elsewhere in this codebase)
  so an overlapping call is never dropped — it guarantees a fresh pass
  starts right after the in-flight one finishes. Mutation-proven: reverting
  to the bare guard reddened exactly 1 of 19 assertions in
  `sync_queue_auto_drain_test.dart` (the new coalescing test); restored,
  19/19 green.
- **Finding 6 (P3):** the `writers`/`readers` file:line citations above were
  stale by 7-11 lines (drafted before later comments were added); corrected
  to the current staged line numbers.
- **Finding 7 (P3):** added the mutation-proof statement to tier 1 above —
  this was the only one of the batch's 5 diagnose-docs missing one.
