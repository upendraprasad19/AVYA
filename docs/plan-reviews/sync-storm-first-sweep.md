---
branch: sync-storm-first-sweep
plan: docs/plans/2026-10-25-sync-storm-first-sweep.md
date: 2026-10-25
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/sync-storm-first-sweep-bpass.md
---

# Plan-review record: sync-storm-first-sweep (A1: migrator skip, incremental skip-index flush, postponed first sweep)

This is the record for the section 4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is `docs/plans/2026-10-25-sync-storm-first-sweep.md` (v4.1, with the as-built deltas in its section 12).

**Tier: platform, L** (sync engine; `lib/core/services/**`, the SoT registry and the nested CLAUDE.md files; measured with `blast_radius_from_diff.dart` on the real paths: platform, no catastrophic path, so no hermes). Execution mode: inline, one worktree, one writer (CLAUDE.md 4.12.7). Not `ship_dark_build`: the three kill switches are opt-out and live by default (a tester-only app, CLAUDE.md section 1), so the full x2 review applied; deleting the switches and their old paths is OI (h) on the board.

**Founder scope call (2026-10-25, AskUserQuestion, answer "Smallest piece first (Recommended)"), quoted verbatim in the plan header:** A1 = the migrator fix, saving progress every ~25 rows, and skipping the first full sweep on a fresh device. The one-pass-at-a-time guard, fingerprints for the other 15 domains, request batching, telemetry batching and the other findings are separate OIs. Commit, push and merge need the founder's explicit go.

## Rounds

Every round had context-blind Sonnet reviewers limited to an exhaustive read-only command list (no scripts, no network, no database), who checked each claim against the code and recorded live state. The plan's section 6 maps every finding of every round to its disposition.

| Round | Plan rev | Result |
|---|---|---|
| 1 | v1 | migrator root cause measured; a clean-restore collector signal rejected; shared `syncBox` -> uid-keyed marker with `ownerChangedSince`; v1's in-flight claim dropped; flush carries removals; closure ledger added |
| 2 | v2 | in-app sign-in path -> durable marker written by the restore core; in-memory latch removed; marker uid-keyed, consume-once, window-bounded; behavioural drivers through `@visibleForTesting` wrappers; missing OI for the removal of the switches |
| 3 | v3 -> v4 | three seats: W1/W2 NOT converged on test design and prose, W3 converged with mechanical edits, governance NOT converged on wording and ledger; no data-loss path found; v3's W2b removed (ledgered as OI (k)) because the rounds kept chasing its symptoms |
| 4 | v4 -> v4.1 | two seats, both converged, no P0/P1, ten P2 each, all mechanical and applied; two hardenings (the marker writer also requires `!ownerChangedSince(userId)`; the new catches use the default telemetry) |

Every reviewer claim was re-verified by the coordinator against the file before it was folded in. The plan was not sent to a fifth round: round 4 converged with no design change.

## Ground truth

Writers and readers named by file:line in plan section 3 and re-read by every round: `ExlogKeyMigrator.runIfNeeded` (the unconditional `updated_at_ms = now` rewrite), `_restoreExerciseLogs` (records the fingerprints), `_syncExerciseLogs` / `_buildExlogPushBundle` (`completed_at = max(resolved, updated_at_ms)` is in the fingerprint), `SyncSkipIndex.commit` (the only persistence), `checkAndSync` / `shouldRunFullSweep` (`last_full_sync` null = due). The mechanism was reproduced on the stub chain (restore, real migrator, real push): 0 upserts expected, 2 on `origin/main`. The 2026-10-25 gateway log is the incident evidence (2,228 requests, 633 upserts for 207 bundles, 51 HTTP 503); the diagnose-doc states what is NOT established (the backend stall, the extra table reads, the phone cold start).

## Mutation proof (rule 21, self-attested)

84 mutants on the final tree, each computed and anchor-asserted before any write, applied, run, restored by sha256 (`ALL RESTORED`): all red except five declared equivalents measured at 0 red with the equivalence argued (M1, W1f, M21, M51 and M54 as a pair). The full table, the survivors found along the way and their fixing tests are in the diagnose-doc.

## B-pass

`docs/reviews/sync-storm-first-sweep-bpass.md`: four fresh seats (W1, W2, W3, docs and governance), 36 findings (0 P0, 1 P1, 17 P2, 18 P3), all accepted and handled, none a false alarm; the P1 was a wrong "up to 24 h" disclosure in three docs; one finding changed the design (drops of stored fingerprints now count toward the flush).

## Verification

`flutter analyze --no-fatal-infos` over the whole project: 0 warnings, 0 errors. Full suite `TZ=Asia/Kolkata flutter test --exclude-tags golden`: 11,312 passed, 11 skipped, 0 failed. The 78 new tests in four files pass. The pre-commit gate loop runs on the staged state before the commit. Runtime verification on a device is owed by the founder (plan section 9) and is ledgered as a `blocked_on_user` entry.

## Open issues

The separate pieces (a) to (k) of the plan are OI-416 to OI-426 on the board (letter-to-number table in plan section 12) and are the `blocked_on_user` / `upstream_blocked` entries of `docs/audit/sync-storm-first-sweep.closure.yaml`.
