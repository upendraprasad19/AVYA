---
reviewed_at: 2026-08-12T23:15:00+05:30
staged_against: ci-reconciler (branch), based on main 888a3fcd
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — ci-reconciler

Self-triggered per §4.3 (platform tier, ≥account, touches code). Reviewer ran the real
`reconcile_ci.dart` end-to-end with `gh` genuinely removed from `PATH`, and executed the pure
functions directly rather than reasoning about them — three of four findings are things the
batch's own 37 tests did not cover.

## Finding 1 — P1 — function_exception_swallow — FIXED

- **file:line:** `scripts/gh_run_lib.dart:113-119`, `scripts/reconcile_ci.dart:159-163`
- **claim:** A broken local `gh` (uninstalled, unauthenticated, expired token, network down) was
  indistinguishable from "CI genuinely never ran" — both collapsed to the same
  `GhRunQueryResult.notFound`. Past the 48h bound the tool then emitted a confidently WRONG
  diagnostic: *"Check whether Actions is enabled and the workflow file is valid on this branch"*,
  when the actual fault was local.
- **failure scenario:** a `gh` token expires (routine). Every session thereafter, every pending
  entry on `main`/`develop` older than 48h produces a wrong "CI never ran" warning — the exact
  cry-wolf failure the rest of the design avoids (unset conclusion ≠ failure; non-CI branches stay
  silent).
- **verification:** reviewer ran the real script twice against the same stale entry — once with
  `gh` present, once with its directory stripped from `PATH` (`which gh` → not found). Output was
  **byte-for-byte identical**.
- **WHY THIS ONE MATTERS BEYOND ITSELF:** it is the *same conflation class* as the
  `safe_push.sh` defect fixed one day earlier (diagnose `d4f9b2`) — an empty `ls-remote` meaning
  both "ref absent" and "probe unreachable". Reproduced inside the tool built to complement that
  fix, by the same session. Knowing the pattern by name did not prevent re-committing it; only
  running the thing with the dependency removed did.
- **fix:** `GhRunQueryResult` gains an explicit `lookupFailed` flag, and `GhRunLister` now returns
  `List?` where **null means "could not ask"** and `[]` means "asked, no matches". `classify()`
  returns `stillPending` (keep, never warn) on a failed lookup at any age. The orchestrator emits
  ONE global `gh_unavailable` notice — the fault is the local CLI, not any individual push.
- **proof of fix:** the same PATH-stripping experiment now yields materially different output —
  `ci_never_ran` with `gh` present vs `gh_unavailable` ("This says NOTHING about whether those runs
  passed. Check `gh auth status`") with it absent. Entries are retained, so they reconcile once
  `gh` works. Tests: `gh_run_lib_test.dart` "could not ask is DISTINGUISHABLE from no such run",
  `ci_reconcile_state_lib_test.dart` "a FAILED LOOKUP never warns" + its mirror "a genuine notFound
  at the same age DOES warn" (without the mirror, the first would pass on code that never warns).
- **status:** accepted — fixed in-batch.

## Finding 2 — P2 — guard_without_its_mirror — REJECTED (false_alarm)

- **claim:** `mergeConcurrentArrivals` keys on `branch@sha` alone, so a concurrent re-arm of a key
  this run just resolved-and-dropped is discarded with no trace.
- **verification:** reviewer demonstrated `merged == []` for that input. The mechanism is real and
  the demonstration is correct.
- **why rejected:** the discarded record refers to the **same (branch, sha)** — therefore the same
  commit, therefore the same CI run, whose verdict this run just established and (if bad) already
  reported. An entry is only ever dropped after reaching a terminal verdict: `resolvedSuccess`,
  `resolvedFailure` (warned), or a stale outcome. Re-arming an identical SHA cannot produce a
  different CI answer, so re-adding it would schedule a duplicate lookup that re-reports an
  already-reported result. Dropping it is the correct behaviour, not data loss.
- **what would change this:** if entries ever carried per-arm state that mattered (a retry count, a
  push timestamp used for anything), the identity argument would break and the key would need
  widening. It does not today — `PendingEntry` is exactly `{branch, sha, armedAt}` and `armedAt` is
  only used for the staleness clock, which `dedupeKeepingEarliest` deliberately anchors to the
  earliest arm.
- **status:** false_alarm (reasoned, not dismissed).

## Finding 3 — P2 — guard_without_its_mirror — FIXED (partially; residual named)

- **file:line:** `scripts/reconcile_ci.dart` `_writeState`, between the re-read and the
  delete/rename.
- **claim:** "Re-read as late as possible" narrows but does not close the window, and the exposure
  is **symmetric across both branches** — the `deleteSync` path is not uniquely unsafe, because
  `renameSync` equally replaces the destination with a snapshot decided before a concurrent append.
- **verification:** reviewer replicated `_writeState` verbatim against real temp files, injecting a
  concurrent append precisely between the re-read and the act, on both branches. A concurrently
  armed `develop@zzz999` was lost either way.
- **fix:** added a compare-and-swap — re-read the bytes immediately before acting and bail if they
  moved (`_bytesChangedSince`, which also treats a read error as "changed" so it backs off rather
  than overwriting what it cannot see). Bailing is always safe: the file keeps its entries and the
  next session reconciles them.
- **residual, stated plainly:** this shrinks the window to the width of the write call; it does not
  eliminate it. A true fix needs a lock, and the approved plan already recorded why the obvious
  candidate is wrong here: `_git_lock.sh` is source-only (no CLI entry point, releases on the
  sourcing shell's EXIT trap) so a Dart process cannot hold it, and it is the *git* lock — a
  pre-push suite can hold it for many minutes, and blocking session start would violate this hook's
  one non-negotiable contract. Cost of the residual: one advisory line may not fire. The tool
  gates nothing.
- **status:** accepted — fixed in-batch to the extent achievable without a new concurrency
  primitive; residual documented rather than papered over.

## Finding 4 — P2 — blast_radius_mismatch — FIXED

- **claim:** `docs/blast_radius.yaml` platform tier `requires: [regression_test,
  behavioral_test_path, code_review_b_pass, feature_flag]`. This diff had **no feature flag** — the
  SessionStart hook was registered unconditionally and live from the next session after merge, with
  no way off short of editing `.claude/settings.json`. Also therefore ineligible for §4.12.4
  ship-dark tiering, which requires default-OFF.
- **verification:** `git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
  → `Blast-radius: platform`; grep for `kDebugMode|FEATURE_FLAG|kill.switch|RECONCILE_CI` across
  the four new scripts → 0 hits.
- **fix:** added a kill switch — `touch .claude/.reconcile_ci.disabled` and the hook does nothing
  at all (checked BEFORE any file read or `gh` call). Marker is gitignored, so disabling it in one
  clone does not disable it for everyone, and it never shows up as an untracked file. Deliberately
  default-ON: the tool is warn-only, so the risk it needs a switch for is noise, not damage.
  Pinned by two assertions in `reconcile_ci_wiring_test.dart` — one that the switch exists and is
  gitignored, one that it is checked *before* the state file is read (a switch consulted after the
  work is done is not a switch).
- **status:** accepted — fixed in-batch. Registry requirement now met rather than deviated from.

## Clean lenses (verified by execution, not assumption)

- **Lens 1 writer_reader_drift** — clean. Shell writes `date -u +%Y-%m-%dT%H:%M:%SZ`; Dart parses
  with `isUtc == true`, round-trips through `toIso8601String()` to the identical instant, and
  compares against `DateTime.now().toUtc()` with zero drift. Reviewer also proved the
  counterfactual: parsing the same digits *without* the `Z` produces exactly 5:30:00 of error on
  this IST machine — so the `-u`/`Z` discipline is load-bearing, not incidental.
- **Lens 4 secrets_in_tree** — clean. 0 credential literals in the staged diff.
  `git check-ignore -v` confirmed both state paths matched. (The kill-switch marker was NOT
  ignored when first added — caught and fixed during triage, not by the reviewer.)
- **Lens 5 unawaited_no_error_sink** — clean. The only `async`-shaped hit is the word
  "asynchronously" in a comment; the script is genuinely fully synchronous.
- **Lens 6 sub-checks** — clean: `resolvedFailure` is branch-agnostic, so a red run on a PR branch
  is still caught despite the stale path being scoped to `main`/`develop`; and the
  detached-HEAD guard in `arm_ci_reconcile.sh` was verified in a throwaway repo across all three
  cases, including the observation that `git push origin HEAD` from a detached HEAD fails outright,
  so the LANDED path (and thus the arm) is unreachable there anyway.

## Triage summary

4 findings: 1 P1 + 2 P2 fixed in-batch, 1 P2 rejected with reasoning. False-alarm rate 1/4 (25%),
below the 30% tuning threshold — no lens changes. Test count 37 → 49.

**Lens 6 (`guard_without_its_mirror`) earned its place for the third consecutive batch**, and lens 2
produced the headline finding only because the reviewer *ran the code with the dependency removed*
instead of reading it. Both fixes that mattered came from execution, not inspection.
