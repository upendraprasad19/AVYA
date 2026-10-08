---
branch: sync-banner-force-retry
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/efcfe7745ebe-review.md
---

# Plan-review record — sync-banner-force-retry

Two changes to the sync retry-queue surface, born from the 2026-09-17
founder observation (test2 on web: "1 change waiting to sync" appeared at
23:17:40 IST from a login-time `user_progress` version conflict and
self-cleared at 23:22:38 IST via the 5-min auto-drain wired by
diagnose `b7c2a9` — the fix working as designed, but with two UX gaps).
Both landed in ONE commit (`e6dfd9a3`, `fix(sync):`) — they share the same
two lib files and test files, so hunk-splitting them into the originally
planned fix/feat pair was rejected as pure risk:

- **(b) `fix(sync)`** — manual Retry silently no-ops on an op inside a
  backoff window (`drain()`'s `_isDue` filter skips it with no feedback);
  plus a **pre-existing** bug surfaced by round 2: `enqueueFresh`'s success
  path removes the op without ever notifying the pending-count stream, so
  the banner could stick at "1 change waiting" until an unrelated event.
  Plus a comment-only correction: `sync_queue.dart`'s header promised
  `test/contracts/sync_queue_retry_budget_consistency_test.dart` "(lands in
  B2 continuation)" — that file has never existed; the batch adds the real
  consistency test instead of editing the promise.
- **(a) `feat(sync)`** — SyncBanner display grace: a pending op younger
  than 6 minutes (one 5-min auto-drain tick + slack) never turns the banner
  on, so self-healing conflicts stay silent; aged debt still surfaces.
  Kill-switches `disable_sync_banner_grace` / `disable_sync_force_retry`
  (§4.6; sync surface), each restoring exactly today's behavior.

Blast-radius: **account** (`lib/core/services/**` catch-all,
`docs/blast_radius.yaml:338` — verified by both rounds; no pubspec change,
so no platform bump). No new Hive key, no cloud column, no Edge Function —
`sot_registry` not applicable (same scope as b7c2a9's own record).

## Plan-review round 1 (context-blind, preamble-prefixed)

Verdicts: (a) CONCERNS, (b) CONCERNS. 10 findings, all incorporated:

1. **[P1]** The existing source-grep tests' anchor
   `queueSrc.indexOf('Future<void> drain()')` returns −1 once the signature
   gains `{bool force = false}` — both tests (:165, :178) fail at the
   anchor before any window is evaluated. Measured the planned body at
   ~545–580 chars > the 500 window.
   → Repoint BOTH anchors to `'Future<void> drain('` (verified unique),
   widen window to **800** (round 2 re-derived: finally-reset pushes
   `_draining = false;` to ~736). Repoint, never loosen — the four
   `contains(...)` assertions survive verbatim.
2. **[P1]** Force-sticky rerun had zero coverage and ambiguous ordering.
   → Capture-before-reset ordering specified + behavioral sticky-rerun
   scenario demanded.
3. **[P2]** The new 1-min display timer must join `ref.onDispose` and be
   pinned structurally.
4. **[P2]** Seed/recompute must funnel through ONE state mapping
   (`raw==0 || displayable==0 → SyncIdle`, else `SyncQueued(displayable)`),
   with a test for the raw>0/displayable==0 seed case.
5. **[P2]** Scenario 2 must RETURN a non-transient `Result.err`, not throw
   — `_runOne` has no try/catch; a throwing executor leaves the op queued
   and aborts the pass (pre-existing, out-of-scope, noted in the
   diagnose-doc).
6. **[P2]** Scenario 1's premise pinned to the `enqueue(transientError)`
   path (retryCount=1, backoff idx 0 → 1s), not a post-failure bump (5s).
7. **[P3]** Test setup lighter than planned: `Hive.init(tempDir)` +
   `Hive.openBox('syncBox')` + `HiveService.instance.markInitializedForTests()`
   (precedent: `bodyweight_capability_leak_test.dart` and ~20 others) —
   no path_provider mock; syncBox is a SHARED box
   (`hive_service.dart:53-59`), no user scoping.
8. **[P3]** Force-drain on a cross-account marker op (executor refuses
   with non-transient `ValidationError`, `sync_service.dart:730-749`)
   dead-letters on first tap — correct (it can never succeed); stated in
   the diagnose-doc, pinned by scenario 2.
9. **[P3]** Banner copy can undercount (aged succeeds, young pending →
   banner hides ≤1 tick); documented in `docs/architecture/sync.md`, not
   "fixed".
10. **[P3]** `sync_queue.dart:110-115` promised a test file that never
    existed (verified: glob + `docs/audit/2026-09-02/findings-by-lens.md:206`)
    → comment corrected + real consistency test added in this batch.

## Plan-review round 2 (on the post-round-1 hardened plan)

Verdicts: (a) PASS, (b) CONCERNS→amended, tests CONCERNS→re-specced.
The round-1 amendments themselves had introduced defects — exactly the
§4.12.1 failure mode:

1. **[P0]** B1's sticky-force was merged one pass LATE: the bottom
   `passForce = rerunWasForce` consumed a mid-pass force request only into
   pass N+2, and if no further rerun was requested the force was NEVER
   applied — the exact "Retry silently no-ops" defect, recreated by the
   amendment. → Merged at the TOP (`if (rerunWasForce) passForce = true;`
   before the ops loop; bottom assignment deleted). Trace-verified: force
   during pass N ⇒ pass N+1 forced.
2. **[P0]** The sticky-rerun scenario was unspecifiable via
   `enqueueFresh`: it AWAITS `_runOne` internally (test deadlocks), and a
   plain drain pass re-fires the still-persisted op concurrently with
   enqueueFresh's own call (attemptCount lands 2-or-3 for the wrong
   reason; err-persist after ok-remove can resurrect the op). → Re-specced:
   seed via `enqueue` with `NetworkError(at: now−5s)` (immediately due,
   retryCount=1), `final d = drain();` blocks in the executor completer,
   `drain(force: true);` sets both flags, complete with transient error
   (→ retryCount=2, backoff 5s — not due on the rerun pass), `await d;`
   reruns FORCED → success → removed. Assert attemptCount==2, queue empty.
3. **[P1]** `_rerunRequested`/`_rerunForce` survive an exception and
   poison the NEXT drain call with a forced pass (exception-path only;
   normal-path consumption proven complete). → `finally` resets all three.
4. **[P2, pre-existing]** `enqueueFresh`'s success path never notifies the
   pending-count stream (`_remove` at `:307` has no `_notifyPending`;
   every other mutation path does) — banner could stick at 1 until an
   unrelated event, up to hours on mobile. → Added `_notifyPending();`
   after `await _runOne(op);` in `enqueueFresh`, pinned by a new
   stream-event scenario (mutation: remove it → reddens).
5. **[P2]** Window arithmetic re-derived: B1's body ≈631 chars to the
   while-close, ≈672 to `_draining = false;`, ≈736 with Finding 3's
   finally-reset → window **800** (not 700).
6. **[P3]** Scenario 1's ~1s not-due margin → legible pre-assertion
   (`expect(DateTime.now().difference(errAt).inMilliseconds, lessThan(900))`).
7. **[P3]** Executors cannot be unregistered (plain map assign) — every
   scenario registers its own fake over `'test_op'` (overwrite-safe); grep
   confirmed no other test touches the singleton at runtime.
8. **[P4]** Cosmetic double-scans noted, deliberately left (caching would
   reintroduce staleness).
9. Verified-correct: `_stateFor` has no Hive race (`_loadAll` is fully
   synchronous, same-isolate); every mutator except Finding 4's path
   notifies, and the timer backstops; the display-timer block must come
   AFTER the `_drainTimer` block so the `_drainTimer =` first-occurrence
   grep still lands on the drain timer; existing provider windows
   (:114-134, :148-160) survive unmodified.
10. Blast radius confirmed account via `docs/blast_radius.yaml:338`; zero
    `check_*.dart` gates grep this surface (no gate updates needed).

## Ground-truth verification

Both rounds re-read every cited file live (`sync_queue.dart`,
`sync_state_provider.dart`, `sync_banner.dart`, `sync_service.dart`,
`hive_service.dart`, `sync_error.dart`, the existing test file,
`splash_screen.dart:256`) and re-derived the interleavings by trace rather
than accepting the plan's prose; the cloud-side observation facts
(telemetry `sync_user_progress_retry_dropped` at 17:47:40 UTC, cloud row
`updated_at` 17:52:38 UTC) were verified live via SQL earlier in the
session. Mutations will be confirmed-applied by grep before any green run
is believed (§4.4 rule 21), with counts recorded in the diagnose-doc.

## Verdict

**Converged.** Two independent context-blind rounds; round 2 found real
defects in round 1's amendments (2×P0, 1×P1) and its own amendments are
now trace-verified against the live code with no further material issues.
Per §4.12.1's split signal: the findings all live in ONE mechanism
(force/coalesce correctness) now fully specified; the batch remains two
small changes in two files.

## B-pass (code-review, self-triggered per §4.3)

`docs/reviews/efcfe7745ebe-review.md` — 6 findings (0 P0, 0 P1, 1 P2,
5 P3), 0 false alarms, all accepted and fixed in the same session; verdict
**accepted**. None required a change to the two lib files' logic: 3
diagnose-doc corrections (the prose mutation paragraph contradicted the
frontmatter — m1 is 5-of-6 and m2's discriminator is the mixed-ages test,
not the self-adjusting "just under" one; a finally-block citation was
:317-319 instead of :305-307; the test-count split read 9+34 against the
real 6+37), 1 wording nuance with no code change (force is per-CALL at
trigger sites, but a plain caller coalesced into an in-flight forced pass
rides that pass — drain()'s doc comment and the diagnose doc now say so),
1 NEW behavioral test + its m5 mutation proof (exception mid-pass leaves no
poisoned forced flag — previously pinned structurally only), and 1
test-robustness guard (the gate-parked scenario now always releases the
parked pass on premise failure instead of poisoning `_draining` for the
rest of the file). Post-remediation: 44/44 tests green (7 + 37), analyze
clean on touched files.
