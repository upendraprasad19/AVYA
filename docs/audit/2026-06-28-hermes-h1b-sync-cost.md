---
hermes_pass_id: 2026-06-28-hermes-h1b-sync-cost
ran_at: 2026-06-28T00:00:00+05:30
batch_scope: 36495ba..HEAD (H1b — Part A edcb4f5 + Part B1 e46a1bc + review-fixes)
lens_set: [concurrency_cross_account, data_loss_restore, writer_reader_sot, telemetry_killswitch]
agents_dispatched: 4
findings_by_severity: { P0: 0, P1: 1, P2: 3, false_alarm: 13 }
verdict: accepted
---

# Hermes Pass — H1b sync-cost (Part A + Part B1)

4 context-blind Opus lenses over `git diff 36495ba..HEAD`, every claim verified against
file:line. **0 P0, 1 P1, 3 P2 — all resolved in-batch (no deferrals).**

## L-concurrency / cross-account — 1 P1 (the load-bearing finding) — RESOLVED
- **[P1] in-flight-await cross-account coach_memory leak.** `pushSnapshotNow` parked on its
  `await callFunction('daily-snapshot')` when an A→B account swap completes: the response
  carries A's coach_memory, but the mirror resolves `_hive.coachBox` to B's box and
  `GuardedBox._assertOwnership` PASSES (session==owner==B — blind to data-provenance). B-fix-1's
  `_onUserChanged` coalescer reset only drops an OWED trailing pass; it cannot cancel an
  already-in-flight one. The diagnose-doc's "B-fix-1 closes the leak" claim was incomplete.
- **resolution:** ACCEPTED → **B-fix-4**: `pushSnapshotNow` re-checks
  `_supabase.currentUser?.id == userId` (the entry-captured uid; `_ensureSessionOpen` returns
  exactly `currentUser.id`, so no false-skip) immediately before the mirror. `currentUser?.id`
  is a SYNC getter with no `await` before the `_hive.coachBox` resolution → atomic w.r.t. the
  event loop; the mirror is skipped on a mid-flight swap. Pinned by a source-grep in
  `pushsnapshot_debounce_behavioral_test`. The 4 other concurrency concerns (coalescer do-while
  no-loss, pausedForSimulation-guard-first, concurrent eager+coalesced mirror last-wins,
  flushPendingSyncs-through-trigger) were verified FALSE_ALARM.

## L-data-loss / restore — 0 P0/P1, 1 P2 — RESOLVED
- **[P2] schedPayloadFingerprint `|`/`=` aliasing** (hypothetical — the scheduled_workouts
  payload has no free-text fields). **resolution:** ACCEPTED → jsonEncode of a sorted-key map
  (delimiter-safe). The 4 load-bearing data-safety contracts verified intact: never-skip-completed
  (d9b2c5), store-on-200-only, first-run/prune heal, and snapshot-recomputed-from-Hive (so
  coalescing-away is loss-free). No primary user data routes solely through pushSnapshot.

## L-writer-reader / SoT — 0 P0/P1, 2 P2 — RESOLVED
- SoT line-ranges (pushSnapshot 800, restoreFromCloudForUser 1195), fingerprint-index
  sole-owner (`_syncScheduledWorkouts` spans 1442–1735; key written+read only there), and the
  public-API snapshot (`pushSnapshotNow` added; statics correctly excluded) all verified accurate.
- **[P2] public-API snapshot test stale comment** (claimed statics excluded by indent; really by
  the return-type-first regex). **resolution:** ACCEPTED → comment corrected + blind-spot noted.
- **[P2] `coach_memory_service:142`** is the comment-block start; actual call at `:146`.
  **resolution:** ACCEPTED → corrected to :146 in SoT + diagnose-doc.

## L-telemetry / kill-switch — 0 findings
- Both new kill-switches revert verbatim; defensive getters default fix-active; coalescing changed
  only the pass COUNT, not failure reporting (each task self-reports before the coalescer backstop);
  the skip `continue` suppresses no accounting telemetry (success was already silent pre-H1b). The
  one residual (a server-side-deleted PLANNED row never re-created locally → skip) is bounded +
  acceptable (regenerable from plan_json; Hive is SoT; no `updated_at` exists for server-change
  detection) and matches the offline-first contract — not a regression.

## Action items
- [x] B-fix-4 (in-flight cross-account guard) — fixed + tested.
- [x] jsonEncode fingerprint hardening — fixed.
- [x] public-API comment + :146 reference — fixed.
- [x] Hive round-trip test (from the B-pass) — added.

verdict: accepted
