---
branch: claude/resilient-client-phase1
plan: docs/superpowers/plans/2026-10-01-resilient-client-phase1.md
date: 2026-10-01
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/resilient-client-phase1-bpass.md
---

# Plan review — the client survives a Supabase API outage (Phase 1, diagnose e5b2a9)

**Blast radius:** platform. Driven by `lib/core/services/sync/sync_resilience.dart` (the only file in
the batch under the `sync/**` platform glob); every other touched `lib/` file computes `account` or
`feature` (B-pass F8 — the glob gap is its own OI). The batch was handled at platform tier throughout.

**Origin:** the 2026-10-01 05:50-06:30 UTC Supabase API-gateway outage (Cloudflare 521/522/504,
PGRST002; the database stayed healthy). The web app sat on "Getting you ready…" for ~15 minutes, a
weight logged on web never reached the cloud and nothing retried it. Locked scope: a resilient
client only (no standby database; backups wait for Supabase Pro).

## Scope

Four units, no migration, no Edge Function change: **A** bound the post-auth routing read (8 s);
**B** a reachability-probed, capped retry of the failed-push sweep; **D** the "Sync paused" banner
state; **E** stop logging every successful `_safeRestoreOp` (closes OI-151). **Unit C
(pull-on-resume) was split out** under CLAUDE.md §4.12.1 and is the Phase 1b OI.

**Unit A extension — evidence-first routing (founder decision 2026-10-01, folded in AFTER the
two plan rounds and the first B-pass):** a device that already holds local evidence of onboarding
goes home without awaiting the cloud routing read (`resolveBounded(evidenceFirst)` returns `GoHome()`;
the read settles in the background behind a Supabase-uid + Hive-owner guard). Kill-switch
`disable_evidence_first_routing`. It is a **narrowing** of Unit A — same files, same invariant (a
read that did not answer is never `StartMissionBrief`), no new surface — so it did not restart the ×2
plan review; it got its own self-triggered review round (below). The founder's brief also set the
split rule: had that round kept surfacing NEW design-level issues, the extension would have been split
back out (§4.12.1). It did not (see "Implementation review").

## Rounds

| Round | Outcome |
|---|---|
| 1 — four context-blind reviewers on the first draft (every finding verified against code before acting) | **14 findings folded** (plan Round-1 log): `SyncError.isTransient` would loop forever on `UnknownError`; `weeklyFullSync` stamped `last_full_sync` after a fully-failed sweep; the 8 s ceiling would discard a late answer for a no-evidence user; `restoring_screen.dart` sits exactly on Gate 43's 800-line cap (the edit ended net -6 lines, logic moved into the bootstrapper); stale registry ranges; public-API snapshot ordering; a vacuous wiring test. |
| 2 — four context-blind reviewers on the POST-round-1 plan, incl. a scratch-copy simulation of the plan's own tasks | **10 findings folded** (plan Round-2 log): `PostgrestException` not in scope in the sync library (a P0 compile error); the supabase SDK retries a GET answered 503/520 three more times so the "one request" probe opts out with `.retry(enabled: false)`; two existing source-greps stranded by Task 1 (repointed, not loosened); a JOINED sweep let the retry report recovery about a sweep that started before the server came back (now serialised); a hung sweep and a hammered banner needed a ceiling and a cooldown. Round 2 also found **design-level** defects in Unit C twice in a row, so Unit C was split out rather than patched a third time (§4.12.1: "if reviews keep surfacing new material issues the unit is too large"). Revision 3 removes Unit C and folds every other round-2 finding; it adds no new behaviour. |

Execution mode (§4.12.7): inline in one worktree, decided at batch start (Tasks 2 and 4 edit the
same shared files).

## Implementation review

The implemented diff was reviewed by a self-triggered B-pass (`/code-review`, context-blind Sonnet,
before the merge): `docs/reviews/resilient-client-phase1-bpass.md` — 10 findings, no P0/P1, every one
verified by mutation or by running the code in a scratch copy. Nine were fixed in this batch with
tests (durable `sync_sweep_owed` flag, `SerialSlot`, `backend_probe.dart`, `kNotSweptOpTypes` + a
forcing-function test, classifier hardening, banner/drain throttling); one is a tier-policy OI.
Every new test was mutated before it was believed; the log is in the diagnose doc.

**Evidence-first review round (one round, three context-blind Sonnet reviewers, run in parallel):**
routing equivalence / kill-switch matrix; background settle safety (concurrency, error sinks,
cross-account writes); tests, docs and gates. **22 findings: 0 P0, 0 P1, 10 P2, 12 P3, no design-level
defect** — the equivalence table (old flow vs new flow, every answer x evidence x kill-switch cell) came
back identical to the old flow wherever evidence is true, so the extension did not need to be split.
All 22 were folded in the same batch (code hardening, behavioural tests, tightened source-greps,
docs/registry, gates); the dispositions are in the "Evidence-first extension" section of
`docs/reviews/resilient-client-phase1-bpass.md`. The staged diff hash recorded there is the final one.

## Convergence

**Converged.** Two plan-review rounds with their findings verified and folded, the one unit that
would not converge split out, and an accepted B-pass on the implemented diff. Residual
self-attested items (stated in the diagnose doc, not hidden): the `weeklyFullSync` stamp / owed-flag
wiring cannot be driven end-to-end in the stub harness (no auth user), so it is presence-tested and
mutation-proven rather than behaviourally exercised; failures that never reach `_reportSyncFailure`
leave a sweep looking clean (pre-existing).
