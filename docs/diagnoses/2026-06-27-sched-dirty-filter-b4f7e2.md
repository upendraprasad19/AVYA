---
bug_id: b4f7e2
date: 2026-06-27
batch: sync-cost-debounce
status: fixed
blast_radius: platform
symptom: >
  Live telemetry (project dedsavbjuwgarrhphgnl, user e34b04a9) showed a RETURNING
  login made ~190 cloud ops, of which ~96 were `upsert_scheduled_workout` — one
  full UNCONDITIONAL re-upload of the entire plan the cloud already held.
  `_syncScheduledWorkouts` swept every `schedule_`-prefixed Hive row and upserted
  it on every sync pass with zero change-detection. Cloud cost scales with the
  NUMBER of calls (not users), so this per-login tax (plus H1a's fan-out storm)
  was the bulk of the free-tier load. H1a coalesced the sync-pass COUNT; it did
  NOT cut the per-pass row count — that is this fix.
concept: scheduled_workouts_idempotent_upsert_skip
sot_registry_entry: sync_scheduled_payload_hash_index (NEW — writer == reader == _syncScheduledWorkouts; the sync-owned fingerprint index that gates the idempotent re-upsert)
writers: >
  lib/core/services/sync/sync_workout.dart (_syncScheduledWorkouts — the SOLE
  writer of the fingerprint index: loads it at method head, stores
  index[date]=fingerprint ON CONFIRMED 200 ONLY at the 3 upsert success points
  (plain :1547 / 23503-recovery :1581 / null-fallback :1607), prunes to live
  schedule rows + persists after the loop);
  lib/core/services/sync_service.dart (3 pure statics — schedPayloadFingerprint /
  schedShouldSkipUpsert / schedPrunedHashIndex — + the _schedHashIndexKey const +
  the disable_sched_hash_skip kill-switch getter);
  lib/features/dev/simulation_service.dart (resetJourney adds the index key to the
  workoutBox prefix-clear list — A-fix-3).
readers: >
  lib/core/services/sync/sync_workout.dart (_syncScheduledWorkouts — the SOLE
  reader: the skip decision reads index[date] for the current row). No other code
  reads or writes the index ⇒ writer/reader drift is structurally impossible. The
  per-user workoutBox file IS the namespace, so the index auto-clears on
  user-swap / sign-out / DPDP (no extra wiring).
hive_key_prefix: sync_sched_payload_hash_index
hive_key_formula: reserved single key in user-scoped workoutBox → Map{scheduled_date: UUID-v5(canonical payload string)}
sync_methods: ["SyncService._syncScheduledWorkouts", "SyncService.schedPayloadFingerprint", "SyncService.schedShouldSkipUpsert", "SyncService.schedPrunedHashIndex"]
restore_methods: []
cloud_table: scheduled_workouts
cloud_columns: ["user_id", "template_id", "scheduled_date", "week_number", "day_of_week", "status", "completed_at"]
contract_test_path: test/contracts/sync_scheduled_payload_hash_index_writer_to_reader_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: ["scheduled_workout_fk_recovered", "scheduled_workout_template_orphaned"]
  failure: ["upsert_scheduled_workout"]
cross_account_guard: true
forbidden_patterns_checked:
  - "An unconditional full-sweep re-upsert — _syncScheduledWorkouts upserted EVERY schedule_ row on EVERY pass (zero change-detection), re-uploading the whole plan the cloud already held (~96 upserts per returning login). FIXED — a sync-owned fingerprint index (sync_sched_payload_hash_index) lets an unchanged PLANNED row skip its idempotent re-upsert. The fingerprint is stored ON CONFIRMED 200 ONLY (store-on-200), so a failed push re-pushes next pass."
  - "Skipping a completed row whose cloud copy is silently stale — the d9b2c5 contract has restore KEEP a local completed row when cloudStatus=='planned', relying on the unconditional sweep to re-push + heal cloud. A naive dirty-filter that skipped a 'completed' row whose fingerprint matched would freeze cloud at 'planned' → cross-device completion loss, made PERMANENT by the resync migrator's one-shot flag. FIXED — A-fix-1: a row with status=='completed' is NEVER skipped (schedShouldSkipUpsert returns false for completed)."
  - "String.hashCode as the fingerprint (H-15: unstable across VMs/sessions → the index would mis-match every restart → never skip, OR worse, collide). FIXED — A-fix-4: the fingerprint is UUID v5 (sha1-based, deterministic) via the existing SyncService._deterministicId helper, the same stable-hash idiom as the nutrition items hash."
proposed_fix: >
  H1b Part A — a per-row dirty-filter on the idempotent scheduled_workouts upsert.
  A sync-owned fingerprint index (reserved key sync_sched_payload_hash_index in the
  user-scoped workoutBox; sole writer+reader is _syncScheduledWorkouts, so drift is
  impossible) maps scheduled_date → UUID-v5 fingerprint of the EXACT payload pushed.
  In the loop: compute the fingerprint of the resolved payload; if the row is NOT
  completed and its fingerprint matches the last CONFIRMED push, skip the upsert
  (the bulk of the ~96 — planned-week regeneration — skips). A-fix-1 (load-bearing):
  a completed row is NEVER skipped (cloud can be silently stale per d9b2c5/B.1 and a
  mis-skip is made permanent by the resync migrator). Store the fingerprint ON
  CONFIRMED 200 ONLY at the 3 success points (a throw leaves no entry → re-push).
  A-fix-2: prune the index to live schedule rows after the loop (covers deletes
  without per-call-site wiring). A-fix-3: resetJourney clears the index key. A-fix-4:
  UUID v5 (cross-VM stable), not String.hashCode. The skip decision + fingerprint +
  prune are extracted to pure statics for behavioral coverage. Kill-switch
  disable_sched_hash_skip restores the verbatim pre-H1b unconditional sweep (§4.6).
regression_test_planned: >
  test/contracts/sync_scheduled_payload_hash_index_writer_to_reader_test.dart — 12 behavioral assertions
  on the pure statics: schedPayloadFingerprint is stable + sensitive to EVERY pushed
  field (incl. null-vs-present template_id); schedShouldSkipUpsert NEVER skips a
  completed row even on a fingerprint match (A-fix-1 P0), skips unchanged planned,
  re-pushes changed, re-pushes on a null stored fingerprint (store-on-200), never
  skips when the kill-switch is set; schedPrunedHashIndex drops deleted dates
  (A-fix-2). Plus source guards: resetJourney clears the key (A-fix-3); exactly 3
  fingerprint writes (store-on-200 placement). Removing the `status=='completed'`
  guard turns the A-fix-1 test RED. All 12 green; the 17 affected existing sync
  tests (fk-resilience, fan-out, template-order, public-API-snapshot, resync
  migrator) stay green.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "_syncScheduledWorkouts dirty-filter + 3 pure statics in sync_service.dart + resetJourney clear in simulation_service.dart. flutter analyze clean on all touched files (pre-existing infos only). 12/12 behavioral + 17/17 affected existing tests green." }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "the fingerprint index lives under reserved key sync_sched_payload_hash_index in the user-scoped workoutBox. Sole writer+reader is _syncScheduledWorkouts. The per-user box file is the namespace ⇒ auto-clears on swap/sign-out/DPDP; resetJourney also wipes it (A-fix-3). The existing !key.startsWith('schedule_') guard auto-skips the reserved key during the row sweep, so it is never mistaken for a schedule row." }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "read-only query confirmed scheduled_workouts has NO updated_at column (only created_at + completed_at), so a server-side mutation timestamp is unavailable — the fingerprint MUST be client-side. The final cloud state is unchanged: an unchanged row already holds the exact payload; a changed/completed/failed row still upserts. onConflict (user_id,scheduled_date) is unchanged." }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "the dirty-filter only suppresses a REDUNDANT upsert (cloud already holds the byte-identical row); completed rows + changed rows + failed-push rows always re-push, so cloud never diverges. The d9b2c5 stale-cloud heal survives (A-fix-1 + store-on-200 + the empty-index-on-first-run heals existing divergence on pass 1). Live before/after upsert_scheduled_workout count on :8082 is founder-gated." }
impact_analysis: >
  Platform blast radius (scheduled_workouts sync fires on every workout/plan write
  and on every login full-sweep). The fix cuts the returning-login ~96
  upsert_scheduled_workout calls to ~0 for an unchanged user, while preserving every
  data-safety contract: completed rows always re-push (d9b2c5), failed pushes
  re-push (store-on-200), deletes drop their entry (prune), and the whole path is
  kill-switched to the verbatim pre-H1b sweep. Worst-case miss is a one-pass delay
  (the next sync re-pushes), never data loss — Hive is the source of truth. The
  data-lossy alternatives (delta-sync since→last_synced; a dirty-filter that also
  skipped completed rows) were REJECTED by the ×2 + Opus-4.8 foolproof review: they
  re-tread the pinned restore-window anti-pattern (feedback_mistake_restore_window)
  and break d9b2c5. Sibling unit: c4f8d2 (H1a — the fan-out coalescer, the signup
  storm). Part B1 (pushSnapshot debounce) ships next in the same branch. related:
  d9b2c5 (cross-device completion contract this fix preserves);
  docs/reviews/e2e-fullcharter-2026-06-21-evidence.md.
---

# Sync cost: scheduled_workouts unconditional re-upsert → returning-login 96-tax (b4f7e2)

## What happened
Live telemetry for a **returning login** (`e34b04a9`) showed **~96
`upsert_scheduled_workout`** ops — one full re-upload of the entire plan the cloud
already held. `_syncScheduledWorkouts` swept every `schedule_`-prefixed Hive row and
upserted it on **every** sync pass with **zero change-detection**. Combined with
H1a's fan-out storm this per-login tax was the bulk of the free-tier load.

## Root cause (the class)
**An unconditional idempotent re-upsert.** The upsert is correct (onConflict merge)
but wasteful — re-pushing a byte-identical row the cloud already holds. Cloud cost
scales with the *number of calls*, so a returning login ≈ 190 ops.

## Fix (H1b Part A — the converged scope after a ×2 + Opus-4.8 foolproof review)
A **sync-owned fingerprint index** (reserved key `sync_sched_payload_hash_index` in
the user-scoped `workoutBox`; **sole writer+reader is `_syncScheduledWorkouts`** so
drift is structurally impossible) maps `scheduled_date → UUID-v5 fingerprint` of the
exact payload pushed. An unchanged **planned** row whose fingerprint matches the last
**confirmed** push skips its re-upsert.

- **A-fix-1 (P0 — load-bearing):** a `completed` row is **NEVER** skipped. Cloud can
  be silently stale (the **d9b2c5** contract has restore keep a local completed row
  when cloud is still `planned`, relying on the sweep to re-push + heal), and a
  mis-skip is made **permanent** by the resync migrator's one-shot flag.
- **store-on-200-only:** the fingerprint is stored only after a confirmed 200 at the
  3 upsert success points — a throw leaves no entry → re-push next pass.
- **A-fix-2:** prune the index to live schedule rows after the loop (covers deletes).
- **A-fix-3:** `resetJourney` clears the index key (a survivor would mis-skip the sim
  re-drive).
- **A-fix-4:** the fingerprint is **UUID v5** (sha1-based, cross-VM stable) via the
  existing `_deterministicId` helper — **not** `String.hashCode` (H-15).
- The skip decision, fingerprint, and prune are extracted to pure statics
  (`schedShouldSkipUpsert` / `schedPayloadFingerprint` / `schedPrunedHashIndex`) for
  behavioral coverage. Kill-switch `disable_sched_hash_skip`.

## Why this preserves d9b2c5 (the data-safety proof)
- A `completed` row always re-pushes (A-fix-1) → cloud is re-healed from `planned`.
- A failed push records no fingerprint (store-on-200) → re-pushes next pass.
- First run starts with an empty index → every row re-pushes once, healing any
  existing divergence before the index warms.

## Verification
- `test/contracts/sync_scheduled_payload_hash_index_writer_to_reader_test.dart` — 12 behavioral
  assertions (A-fix-1 never-skip-completed; skip/re-push; store-on-200; fingerprint
  sensitivity; prune) + 2 source guards. Removing the completed guard turns A-fix-1
  RED.
- The 17 affected existing sync tests stay green; `flutter analyze` clean.
- Read-only DB check: `scheduled_workouts` has no `updated_at` → the fingerprint is
  necessarily client-side.
- Live before/after `upsert_scheduled_workout` count on :8082 — founder-gated.

## See also
- `lib/core/services/sync/sync_workout.dart` (`_syncScheduledWorkouts`),
  `lib/core/services/sync_service.dart` (the 3 statics + kill-switch).
- `c4f8d2` (H1a — the fan-out coalescer; same incident).
- `d9b2c5` (the cross-device completion contract this fix preserves).
