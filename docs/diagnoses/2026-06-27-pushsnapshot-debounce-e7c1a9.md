---
bug_id: e7c1a9
date: 2026-06-27
batch: sync-cost-debounce
status: fixed
blast_radius: platform
symptom: >
  Every Hive write across health / nutrition / workout / schedule fires
  unawaited(SyncService.instance.pushSnapshot()) (~50 call-sites) — each a
  separate `daily-snapshot` Edge Function invoke. During the signup storm and
  ordinary heavy-write sessions this was the SNAPSHOT half of the per-login
  cloud tax (the workout/nutrition fan-out half was coalesced in H1a c4f8d2;
  the schedule re-upsert half in H1b Part A b4f7e2). H1a coalesced the LOG
  fan-out but left pushSnapshot un-debounced.
concept: snapshot_fanout_coalescing
sot_registry_entry: sync_fanout_workout_domain (pushSnapshot reader-row annotated — now coalesced via _snapshotCoalescer and delegates to pushSnapshotNow)
writers: >
  lib/core/services/sync_service.dart — pushSnapshot() is now the COALESCED
  fire-and-forget entry (in-flight + dirty do-while via the dedicated
  _snapshotCoalescer); the verbatim pre-H1b body (H3 callFunction routing +
  coach_memory mirror) moved to pushSnapshotNow(). _onUserChanged reassigns
  _snapshotCoalescer beside the other two (B-fix-1, GATING). flushPendingSyncs
  flushes it (B-fix-3). Kill-switch _snapshotDebounceDisabled / disable_snapshot_debounce.
readers: >
  The ~50 WriteService / repository / provider call-sites that fire
  unawaited(SyncService.instance.pushSnapshot()) after a Hive mutation
  (unchanged — they keep the coalesced path). The 3 DURABLE callers now call
  pushSnapshotNow() directly (B-fix-2): onboarding_provider.dart
  completeOnboarding (first AI-context, inside the signup storm);
  sync_service.dart checkAndSync (the next-login backstop, awaited); and
  lib/features/ai_coach/services/coach_memory_service.dart:142 (the only PROMPT
  sync of freshly-extracted coachBox['coaching_notes'] — syncCoachMemoryNow is
  only a delayed full-sweep backstop). The caller inventory was verified against
  the actual files: coach_memory_service.dart lives under
  lib/features/ai_coach/services/ (NOT lib/core/services/ — an initial wrong-path
  check + a head-limited grep briefly mis-flagged it absent; the SoT entry + a
  direct Read confirmed the :142 pushSnapshot call).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: ["SyncService.pushSnapshot", "SyncService.pushSnapshotNow"]
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: []
contract_test_path: test/contracts/pushsnapshot_debounce_behavioral_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["push_snapshot", "mirror_coach_memory_from_snapshot"]
cross_account_guard: true
forbidden_patterns_checked:
  - "Un-debounced fire-and-forget pushSnapshot — every Hive write fired a separate daily-snapshot EF invoke (~50 callers), the snapshot half of the per-login cost storm. FIXED — coalesced via a dedicated _snapshotCoalescer (reusing SyncCoalescer): a burst collapses to 1–2 EF calls. The verbatim body (H3 callFunction + coach_memory mirror) is preserved in pushSnapshotNow."
  - "Cross-account coach_memory leak — an owed trailing snapshot pass carried into the NEW owner's session would mirror the PREVIOUS user's coach_memory into the new owner's coachBox (auth_hive_owner_agreement class, strictly worse than the cost problem). FIXED — B-fix-1 (GATING): _onUserChanged reassigns _snapshotCoalescer beside _workoutCoalescer / _nutritionCoalescer, so the fresh coalescer carries NO owed work from the prior session. Pinned by the source-grep that asserts all THREE resets in _onUserChanged."
  - "A durable snapshot deferred to a coalescer pass that could be lost — onboarding's first AI-context + the checkAndSync next-login backstop need a GUARANTEED snapshot. FIXED — B-fix-2: both call pushSnapshotNow() directly (eager, bypass the coalescer)."
proposed_fix: >
  H1b Part B1 — split pushSnapshot() into a coalesced fire-and-forget entry +
  the non-coalesced pushSnapshotNow() body (mirrors the H1a syncWorkoutData →
  syncWorkoutDataNow split). pushSnapshot() guards pausedForSimulation FIRST,
  then the kill-switch, then `_snapshotCoalescer.trigger(pushSnapshotNow)`.
  pushSnapshotNow() is the verbatim pre-H1b body (H3 callFunction routing +
  coach_memory mirror + token refresh — all intact). B-fix-1 (GATING):
  _onUserChanged resets _snapshotCoalescer so an owed pass can't leak the prior
  user's coach_memory into the new owner's coachBox. B-fix-2: the 3 durable
  callers (onboarding first-context, checkAndSync backstop, coach_memory_service
  freshly-extracted coaching_notes) call pushSnapshotNow directly. B-fix-3: flushPendingSyncs flushes the snapshot coalescer on
  app-pause (best-effort; the eager carve-out is the real durability guarantee —
  web `paused` is unreliable). Kill-switch disable_snapshot_debounce reverts to
  the verbatim direct push (§4.6). DROPPED — Part B2 (induction_service /
  edit_profile_screen / splash_screen stay coalesced; their durability already
  rides syncCoachMemoryNow / syncProfileNow + the next-login checkAndSync
  backstop; repointing = churn + miscategorization risk, zero durability gain).
regression_test_planned: >
  test/contracts/pushsnapshot_debounce_behavioral_test.dart — a behavioral
  swap-safety assertion (reassigning the coalescer yields a clean slate: the
  fresh instance inherits none of the prior owner's in-flight / _dirty work) +
  source-pinned wiring contracts: B-fix-1 GATING (_onUserChanged resets ALL
  THREE coalescers — fails RED if the _snapshotCoalescer reset is removed),
  pushSnapshot routes through _snapshotCoalescer behind disable_snapshot_debounce,
  pushSnapshotNow holds the verbatim body, B-fix-3 flush, B-fix-2 eager callers
  (onboarding + checkAndSync call pushSnapshotNow). The MECHANISM (do-while
  coalescing, burst→≤2, no-loss) stays pinned by sync_coalescer_behavioral_test.
  Updated string-pinned: sync_service_public_api_snapshot_test (+pushSnapshotNow),
  guarded_box_auto_open_test (the _ensureSessionOpen bootstrap entry moved from
  pushSnapshot → pushSnapshotNow). All affected pushSnapshot-referencing tests green.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "pushSnapshot split + _snapshotCoalescer field/reset/getter + flush + 2 eager carve-outs. flutter analyze clean (No issues found) on sync_service.dart + onboarding_provider.dart. 6/6 behavioral + all affected pushSnapshot tests green." }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "B-fix-1 GATING — _snapshotCoalescer reset in _onUserChanged means an owed trailing snapshot can't mirror the prior user's coach_memory into the new owner's coachBox. The coachBox mirror itself (pushSnapshotNow) is unchanged + still defensively try/caught. Pinned by the 3-coalescer-reset source-grep." }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: verified, evidence: "daily-snapshot EF is unchanged/undeployed by this batch; pushSnapshotNow invokes it via the same callFunction routing as H3 (token refresh preserved). Coalescing only changes the NUMBER of invokes (~50 → 1-2 per burst), not the call shape." }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "the snapshot still lands — coalesced into 1-2 EF calls per burst (the trailing pass uses compileDailySnapshot()'s latest state) plus the eager onboarding/checkAndSync pushes. Worst-case miss is a delay (next login's checkAndSync re-pushes), never loss — Hive is SoT. Live before/after push_snapshot count on :8082 is founder-gated." }
impact_analysis: >
  Platform blast radius (pushSnapshot fires on every health/nutrition/workout
  write + onboarding + login). This is the third and final cost lever of the
  sync-cost-debounce branch: H1a (c4f8d2) coalesced the LOG fan-out, Part A
  (b4f7e2) the schedule re-upsert, and Part B1 the snapshot storm. Together they
  cut a fresh signup from ~90 cloud calls and a returning login from ~190 to a
  handful — a ~20× reduction at ZERO infra spend, keeping the free tier viable
  to thousands of users. The single biggest residual risk (the cross-account
  coach_memory leak via an owed snapshot pass) is closed by B-fix-1, mirroring
  the H1a coalescer-reset pattern. The eager-caller inventory (3: onboarding,
  checkAndSync, coach_memory_service:142) was confirmed against the actual files —
  after an initial wrong-dir + head-limited-grep false-negative on
  coach_memory_service that the SoT entry + a direct Read corrected. Reinforces
  the CLAUDE.md rule: verify a path with the FULL path + an UN-truncated grep
  before concluding "absent."
  Sibling units: c4f8d2 (H1a fan-out coalescer), b4f7e2 (Part A schedule
  dirty-filter). related: d3a1c7 (BUG-C token-freshness, preserved via
  callFunction); docs/reviews/e2e-fullcharter-2026-06-21-evidence.md.
---

# Sync cost: un-debounced pushSnapshot → snapshot storm + cross-account guard (e7c1a9)

## What happened
~50 call-sites fire `unawaited(SyncService.instance.pushSnapshot())` after every
Hive write — each a separate `daily-snapshot` EF invoke. This was the SNAPSHOT
half of the per-login cost storm (H1a coalesced the log fan-out; Part A the
schedule re-upsert; this fix the snapshot).

## Root cause (the class)
**Un-debounced fire-and-forget snapshot push.** Same class as the H1a fan-out
storm, on a different entry point. Cloud cost scales with the *number of calls*.

## Fix (H1b Part B1 — the converged scope after a foolproof review)
- **Split** `pushSnapshot()` → coalesced wrapper (`_snapshotCoalescer.trigger(
  pushSnapshotNow)`) + the verbatim `pushSnapshotNow()` body (H3 callFunction +
  coach_memory mirror intact). Kill-switch `disable_snapshot_debounce`.
- **B-fix-1 (GATING):** `_onUserChanged` resets `_snapshotCoalescer` beside the
  other two — an owed trailing pass can't mirror the previous user's
  coach_memory into the new owner's `coachBox` (cross-account leak).
- **B-fix-2:** the 2 durable callers (onboarding first-context, checkAndSync
  next-login backstop) call `pushSnapshotNow()` directly (eager).
- **B-fix-3:** `flushPendingSyncs` flushes the snapshot coalescer on app-pause
  (best-effort; the eager carve-out is the real guarantee).
- **DROPPED Part B2** — induction/edit_profile/splash stay coalesced (durability
  already rides syncCoachMemoryNow/syncProfileNow + the checkAndSync backstop).

## Caller-inventory (verified against code — 3 eager carve-outs)
The eager (non-coalesced) callers are **onboarding** (`onboarding_provider.dart`
completeOnboarding), **checkAndSync** (`sync_service.dart`, awaited backstop),
and **coach_memory_service** (`lib/features/ai_coach/services/coach_memory_service.dart:142`
— the only prompt sync of freshly-extracted `coachBox['coaching_notes']`).

A process note worth keeping: I initially mis-flagged the coach_memory_service
caller as "absent" because I checked the wrong directory
(`lib/core/services/coach_memory_service.dart`, which doesn't exist) and a
`head_limit`-truncated grep cut the real hit. The SoT registry entry (which lists
`lib/features/ai_coach/services/coach_memory_service.dart` as a coaching_notes
writer) plus a direct Read confirmed the `:142 pushSnapshot()` call before the
implementation was finalized. Lesson (reinforces the CLAUDE.md rule): verify a
path with the FULL path and an UN-truncated grep before concluding "absent" —
a wrong-dir guess + a capped grep can fabricate a false negative.

## Verification
- `test/contracts/pushsnapshot_debounce_behavioral_test.dart` — swap-safety
  behavioral + GATING source-grep (all 3 coalescers reset; remove the
  `_snapshotCoalescer` reset → RED) + eager-caller + routing + flush contracts.
- Updated `sync_service_public_api_snapshot_test` (+pushSnapshotNow) +
  `guarded_box_auto_open_test` (bootstrap entry → pushSnapshotNow). All
  pushSnapshot-referencing tests green; `flutter analyze` clean.
- Live before/after `push_snapshot` count on :8082 — founder-gated.

## See also
- `lib/core/services/sync_service.dart` (`pushSnapshot` / `pushSnapshotNow` /
  `_onUserChanged` / `flushPendingSyncs`).
- `c4f8d2` (H1a fan-out coalescer), `b4f7e2` (Part A schedule dirty-filter) —
  the other two cost levers of this branch.
