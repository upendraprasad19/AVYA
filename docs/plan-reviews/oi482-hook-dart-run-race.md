---
branch: oi482-hook-dart-run-race
date: 2026-11-07
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi482-hook-dart-run-race-bpass.md
---

# Plan-review record: OI-482 / OI-117, the git hooks contain the `dart run` native-assets race and the pre-commit gate loop stops discarding its output (platform)

**Tier `platform`, L (git hooks, `scripts/_dart_bin.sh`, `CLAUDE.md` wording):** four of the five installed hooks and the helper every hook sources, the pre-commit gate loop,
two new test files, frozen old-hook fixtures, docs, the board, one bug class. No `lib/`, no Hive key, no cloud column, no Edge Function. Execution mode: INLINE (one worktree).
Founder go: the OI-468 plan (D7) filed this as "starts next" and the standing rule "why are you waiting for me every time?"; the founder may veto it. Plan
`docs/plans/2026-11-06-oi482-hook-dart-run-race.md` (v4), diagnose `docs/diagnoses/2026-11-06-hook-dart-run-native-assets-race-c4e2a8.md`, B-pass
`docs/reviews/oi482-hook-dart-run-race-bpass.md` (verdict accepted).

## What this branch is

Each hook adds ONE guarded line after its `DART_BIN=` assignment (`type use_dart_race_retry >/dev/null 2>&1 && use_dart_race_retry || true`); `use_dart_race_retry` sets `DART_BIN`
to the NAME of a shell function `_dart_run_retrying` (real binary in `DART_BIN_REAL`; kill switch `AVYA_DART_RUN_RETRY=0`), which re-runs a `run` whose child exits 254 with
`File not formatted as yaml` on stderr at most twice, one second apart, with a `[dart-run-retry]` note each. The 22 `"$DART_BIN" run` call sites do not change. The pre-commit loop keeps each
gate's output and exit status and prints notes, the first 8 failing gates' output, the status, and a distinct sentence for a signal death (129..192) and for 254. A killed gate still blocks.

## Rounds

Three plan-review rounds by fresh context-blind Sonnet readers (each re-measured against the SDK or the code; none was told another's findings), then a four-seat B-pass on the built change.

| Round | Plan | P0/P1 | Outcome |
|---|---|---|---|
| #1 | v1 | 0 P0, 5 P1 per reader (two readers) | the retry as an executable WRAPPER FILE failed on the facts: scripts here are mode 100644 (a wrapper needs 100755 or silently no-ops on a fresh checkout), a blast-radius entry, a dirname/symlink story, an untested Windows exec; the design became a shell FUNCTION in `_dart_bin.sh` (v2) |
| #2 | v2 | lens A 1 P1, lens B 6 P1 (none changes the design) | a closed-stdout fail-open in the capture idiom (the group never ran and the child was skipped: a ran-flag fallback), env-scan plumbing (`_localShell`, `_stripped`, the recursion-capable set), the canary's spawn shape and recipe, a fail-safe diagnostic block, mutants that survive, board consistency (v3) |
| #3 | v3 | 0 P0, 3 P1 | the killed-gate range mislabelled Dart's own statuses 254/255 (now 129..192 plus a 254 sentence), a fourth silent site (`commit-msg.sh`), mutants the scenarios could not kill (v4) |
| B-pass | built | 0 P0, 0 P1, 6 P2, 24 P3 (four seats, 30 findings) | every finding fixed or accepted with its reason in the review file; the P2s: the setter did not check the function exists; five stale "the loop hides it" claims; a count pinned by a substring a sibling fixture satisfied; the 60-line boundary unpinned; the new tests were not Windows-aware; `grep -l` exit 2 discarded every note when one output was unreadable |

## Ground truth

- Mechanism (writer/reader/victim model, the empty-yaml canary giving a deterministic real 254, a real 254 retried to a real success with a real stdin payload, a real SIGKILLed `dart run`
  returning 137): measured in diagnose `b7e2d9` and re-measured here; reviewers re-ran on a scratch package (SDK 3.11.1 = CI's Flutter 3.41.4).
- Proof: 90 mutants on the final code, 88 reddened, 2 named equivalents; the full local suite green on the final tree; whole-project `flutter analyze --no-fatal-infos` clean; the real
  `pre-commit.sh` run on the staged batch green (its first live run printed the cause of a failing gate: the new loop working).
- Stated residue, each with a ledger row: NOT established that the historical "different gate each run" pre-commit failures were this race (their output was discarded); Windows and macOS
  not measured; the retry is silent at four sites that discard stderr; OI-483 (harness hooks, launchers, plain-form Dart scripts) split on shape-fit grounds.
- After the merge (an operational step, not claimed by the commit): re-install the hook copies from the primary (`sh scripts/setup-hooks.sh`).
