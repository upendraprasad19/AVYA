---
branch: train-signout-notif-bugs
date: 2026-08-09
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/914854ec1b48-review.md
---

# Plan-review record — train-signout-notif-bugs

Seven issues the founder found live-testing the web app as
`upendraprasad19@gmail.com` on 2026-08-05 / 2026-08-07. Six fixed; issue 5 is
`upstream_blocked` on OI-60.

Blast-radius measured, not assumed: `blast_radius_from_diff.dart` over the
staged set returns **platform**, which is why `bpass: accepted` is required here
rather than optional.

## Round 1 — the approved plan did not survive contact with the code

The headline outcome of this review is that **four of the approved plan's
premises were WRONG**, and all four were corrected before a line was written.
Recording them individually, because the wrong fix is the more useful artifact
for a future reader than the right one.

**1. Issue 1 named the wrong function.** The plan blamed
`generateAndScheduleFromDate` for failing to write `plan_start`. That function
is Edit-Profile-only (`edit_profile_screen.dart:1881`). The phase-advance path
is `generateAndSchedule`, which already writes plan_start, and its
`isFirstGeneration` gate is deliberate per `docs/sot_registry.yaml`. Had the
plan been implemented as written it would have changed a function the bug never
touches, and `profile['phase_started_at']` — the rank tenure anchor — would have
been altered as collateral.

**2. Issue 3's proposed fix would have blinded a live alarm.** The plan proposed
flipping the `signOut()` teardown order so `auth.signOut()` runs first. Verified
against `wrapUserScopedBox`: it throws when the caller is unauthenticated with a
non-null owner, so ending the session first makes all 7 user-scoped clears
throw. Each is caught independently, so teardown still completes — but every
sign-out would then fire 7 `recordNonFatal` events and permanently return
`ClearResult.hasFailures`. Two live recovery paths key off exactly that signal
(`_ensureLocalUser`, and `main.dart`'s interrupted-logout completion). The
"fix" would have traded an intermittent race for a permanently-deaf alarm on
the cross-account partial-clear path. Order kept; the ambiguity closed instead.

**3. Issue 4's proposed fix would have aborted healthy restores.** The plan
proposed making RestoringScreen's "Continue" cancel the restore.
`cancelInflightRestore()` is already correctly wired
(`restoring_screen.dart:116`, `:182`); making Continue abort would kill working
restores seconds from completion. The real defect was the total absence of a
ceiling — confirmed by `grep -c '\.timeout('` returning **0** across
`sync_service.dart`, `supabase_service.dart` AND
`auth_session_bootstrapper.dart`. Scope corrected to timeouts only;
cancellation untouched.

**4. Issue 5 cannot be done at all in this batch.** The plan (and a mid-session
question of mine) implied `enable_hold_weeks` could be flipped here. It is
gated by OI-60's 7 unstarted FOB items. The flag stays OFF. Recorded as
`upstream_blocked` in the closure ledger — terminal, not deferred: the blocker
is another work item with its own board entry, not a scheduling choice.

## Round 2 — run on the hardened plan, per §4.12.1

Round 2 reviewed the post-round-1 plan, since corrections can introduce their
own defects. Findings:

**2a. The issue-1 correction created a new hazard of its own.** Adding a
recovery path to `pastPhaseBlocks()` would have widened the set the
`PhaseProgressReconciler` consumes. That reconciler advances `current_phase`
MONOTONICALLY and its own comment calls an over-advance "unrecoverable" — so
the round-1 fix, applied naively, could have promoted users on evidence the
strict filter deliberately rejected, with no way back. Resolved by splitting
into two named methods rather than one relaxed method, and pinning the
separation with an `isFalse` source-grep assertion against
`phase_progress_reconciler.dart`. A `bool strict` parameter was considered and
rejected: it would put the reconciler one boolean away from the unrecoverable
path, invisibly at the call site, and would make the assertion inexpressible.

**2b. Removing the PR title branch was not sufficient on its own.**
`recent_pr_exercise` was also being handed to Gemini in `userState`. Since the
model writes the body independently of the title, dropping only the title would
have left it free to narrate the same unbounded, months-old PR into the copy —
the exact contradiction that reached the founder's phone. Both removed.

**2c. A dead fallback would have silently restored the bug.** After gating on
`.gte("current_streak_days", 1)`, the `?? streakWeeks * 7` fallback is
unreachable (SQL excludes NULL from `>=`). Left in place it would re-derive the
exact two-source contradiction the moment anyone loosened the gate. Removed;
the guarantee now lives in the query alone.

**2d. Pagination bookkeeping must NOT follow the PRO filter.** `.range()` walks
the RAW page, so advancing `offset` by the filtered count would skip users on
every page containing a non-PRO. Bookkeeping pinned to `users.length` and
asserted both positively and negatively.

Round 2 surfaced no defect requiring a redesign of a unit, so per §4.12.1 the
batch was NOT split further — the "keep finding new material issues" signal did
not fire.

## Ground-truth verification

Every claim below was checked against code or live state, never against
subagent prose (`feedback_audit_verifier_cannot_trust_own_subagent.md`):

- `generateAndScheduleFromDate` call sites read directly; Edit-Profile-only.
- `wrapUserScopedBox` throw condition read directly, plus both consumers of
  `ClearResult.hasFailures`.
- `grep -c '\.timeout('` = 0 across all three restore-path files.
- `cancelInflightRestore()` wiring read at both call sites.
- `fetchProUserIds` predicate read in `_shared/subscription.ts` — the assertion
  lives against the helper, not a copy of it.
- The founder's live row (`current_streak_weeks=4`, `current_streak_days=0`,
  last workout 2026-05-22) and the PRO-expiry date (2026-07-05, still receiving
  the Sunday Brief 2026-08-07) recorded in the diagnose-docs as the reproducing
  cases.
- Blast-radius computed with `blast_radius_from_diff.dart` over the real staged
  set, not estimated.

## Two corrections found by re-checking, not by the reviews

Both are recorded because they are process findings, not code findings.

**Bug-ID collision.** `a4f1c8` was verified free — against committed history and
the main worktree. It was NOT free: `post38-auth-fixes` holds
`2026-08-06-notifications-inbox-nonuuid-id-a4f1c8.md`, uncommitted, so it was
invisible to both. It would have collided the moment that branch merged.
Renamed to `e3b9d7`, re-verified across **every** worktree's `docs/diagnoses/`
**with a positive control** — the method correctly reports `a4f1c8 = 1`, so the
zeros are meaningful rather than a blind grep. Same class as
`feedback_green_check_input_set_width.md`: a check is only as wide as the input
set it consumed. (`b6d3f9`, the originally-planned ID for the auth doc, had
already collided with `2026-06-28-logurine-sync-routing-b6d3f9.md` and was
changed to `b7e4c1` during planning.)

**Repo-wide git corruption, unrelated to this batch.** Mid-session,
`core.worktree` was written into the SHARED `.git/config`, pointing every
worktree — including main — at `post38-auth-fixes`. `git status` in this
worktree reported 146 files belonging to another branch while omitting all of
mine, despite index/disk hashes differing. Confirmed five ways (config read,
`--show-toplevel` across 6 dirs, index-vs-disk hash, `ls-files -v` ruling out
skip bits, and `extensions.worktreeConfig = true` making a shared
`core.worktree` invalid by git's own docs). No commit was attempted while it
was live. Fixed outside this batch, with its own gate
(`check_worktree_config_integrity.dart`, diagnose `a4f7c2`).

## Deliberately not in scope

- **Whatever leaves `plan_start` un-advanced on some accounts.** This batch
  makes the DISPLAY resilient to that state; it does not diagnose the cause.
  The strict filter remains the reconciler's contract and remains correct.
- **The divergence between the two streak caches.** The crons no longer straddle
  them; the writers are not reconciled here.
- **`refreshListenable` on router auth state**, which is what makes the sign-out
  window timing-dependent. Closing the ambiguity is the correct minimal fix;
  re-architecting router refresh is a materially larger change with its own risk
  surface and no additional benefit to this symptom.
- **The live Edge Function deploy.** Source only. Deploying `streak-guardian`
  and `weekly-recap-ready` needs its own explicit authorization per §4.3 —
  plan approval is not deploy approval. Until then production runs the old code,
  and this record says so rather than letting a green merge imply otherwise.

## Verdict

**Converged.** All four wrong premises corrected and re-verified; round 2's
findings folded in; six issues closed with mutation-proven behavioral tests
(each fails with its fix removed); issue 5 terminal as `upstream_blocked`.
Closure ledger: `docs/audit/train-signout-notif-bugs.closure.yaml`, 7/7 terminal.
