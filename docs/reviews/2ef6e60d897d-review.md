---
reviewed_at: 2026-08-30T09:00:00+05:30
staged_against: 2ef6e60d897d
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 3
verdict: accepted
---

# Code Review — 2ef6e60d897d (process-hardening)

Dispatched context-blind against `354ad5b024ff`; this file is named for the
POST-remediation hash. **3 findings, 0 false alarms, all three real and all
fixed.** Every one was independently re-verified against the repo before being
accepted — the reviewer's evidence was not taken on trust.

> The batch under review exists to close defect classes found in the previous
> batch. Two of its three findings are the SAME classes recurring inside the
> fix for them, which is the most useful thing this review produced.

## Finding 1 — P0 — guard_without_its_mirror / asserted_fixture_value

- **file:line:** `scripts/safe_merge.sh:153-168` (pre-fix), fixture at `test/scripts/safe_merge_test.dart`
- **claim:** The new precheck read `docs/plan-reviews/<branch>.md` from the WORKING TREE. `safe_merge.sh` runs on `main`, before the merge — and the plan-review record is authored and committed on the FEATURE BRANCH. So the check matched nothing on every real invocation: a silent no-op, shipped as a guard against silent no-ops. Its three tests passed only because the fixture committed the record onto `main`, a shape the real workflow never produces.
- **verification:** Re-confirmed independently against real history rather than trusting the reviewer:
  ```
  git merge-base --is-ancestor 11a148fd a7a254b8^1   # -> NOT on main side
  git cat-file -e a7a254b8^1:docs/plan-reviews/profile-phase-fixes.md
  # -> fatal: exists on disk, but not in 'a7a254b8^1'  => absent from main pre-merge
  ```
- **suggested-fix:** Read from the branch's tree via `git show "$BRANCH:<path>"`, matching `check_plan_review_record_exists.dart:216`; fix the fixture to commit on the branch.
- **status:** accepted — fixed. Precheck now reads `git show "${BRANCH}:${_REC}"`. `writeReviewPair` → `writeReviewPairOnBranch`, which commits on the branch, returns to main, and **asserts main does not have the file** — without that precondition the test cannot distinguish a branch read from a working-tree read. **Re-mutation-proven:** reverting `git show` to a working-tree `cat` now reddens the warning test. Under the OLD fixture that same mutation passed, which is exactly what made the bug invisible.

## Finding 2 — P1 — guard_without_its_mirror

- **file:line:** `scripts/_dart_bin.sh`, `scripts/_git_lock.sh` (the `case "$0"` guards)
- **claim:** The guard pattern was forward-slash-only. A backslash invocation — `sh 'scripts\_dart_bin.sh'`, the dominant path spelling in this Windows environment — bypassed it entirely, exiting 0 and reproducing the original silent no-op.
- **verification:** Reproduced directly against the staged file: backslash form → `exit=0` (silent); forward-slash control → `exit=64`. Does not threaten the five hooks (they source via `$REPO_ROOT`, which Git Bash returns forward-slashed) — but it reopens the exact failure mode the batch exists to close, through a spelling the author did not consider.
- **suggested-fix:** Normalize `$0` with `tr '\\' '/'`, mirroring `_norm()` in `safe_merge.sh`.
- **status:** accepted — fixed on both files. Verified: backslash form now exits 64 on each; sourcing still resolves the SDK exe and still defines the lock functions; `sh -n` still parses.

## Finding 3 — P2 — writer_reader_drift

- **file:line:** `scripts/safe_merge.sh:153` (`_REC="docs/plan-reviews/${BRANCH}.md"`)
- **claim:** The CI gate locates the record via `plan_review_record_lib.dart`'s `recordSlug()` — strip a leading `origin/`, map every `/` → `-`. The precheck interpolated the raw branch name, so the two readers disagree for any slash-containing branch, and `claude/*` is a live convention here.
- **verification:** Read `recordSlug` directly (`plan_review_record_lib.dart:140-145`) — confirmed. `docs/plan-reviews/claude-oi-pending-hold-weeks-1od97o.md` exists; `docs/plan-reviews/claude/` does not.
- **suggested-fix:** Shell-port the slug mapping.
- **status:** accepted — fixed. `_REC_SLUG="$(printf '%s' "$BRANCH" | sed 's#^origin/##' | tr '/' '-')"`. Verified against three shapes, including the real `claude/*` branch, resolving to the file that actually exists.

## Lenses that found nothing

Reported clean by the reviewer with commands shown, and spot-re-checked here:
`function_exception_swallow` (no `.functions.invoke(` in the diff),
`secrets_in_tree` (one "token" hit, prose about mutation tokens, not a credential),
`unawaited_no_error_sink` (no `unawaited(` added),
`blast_radius_mismatch` (each path classified individually — `_dart_bin.sh`, `_git_lock.sh`, `safe_merge.sh`, `CLAUDE.md` all pinned `platform`; classifier re-run → `platform`),
`missing_input` (every cited file/symbol read and confirmed present),
`writer_reader_drift` in the Hive/Postgres sense (no box or schema touched).

The reviewer also independently mutation-tested both execution guards against the real staged files and confirmed exactly one test reddens per guard, restoring both byte-for-byte afterward.

## Subsequent rounds (recorded here for one-file traceability)

**Round 1 — 6 findings, 3 actionable, all fixed.** Precheck silent on the two
likeliest operator errors (no `bpass_review:` field; a field naming an
uncommitted file) — both hard-rejected by CI. Two mutation gaps: the guard's
bare-filename pattern arm, and the verdict grep's line-anchoring. Plus rule
21's clause not flagging itself as self-attested.

**Found while fixing round 1:** `check_skill_tuning_history` rejected this
batch's own honest `(b)` tuning entry — its matcher required the date
immediately closed by `**`, matching none of the **5** suffixed headers already
in SKILL.md. Fixed in `skill_tuning_lib.dart`, both regexes.

**Round 2 — `converged`, no P0s, 7 findings, all folded in.** Two
documentation-accuracy misses in CLAUDE.md (a test count of 4 where there are
5; "reddens exactly one" where it reddens two — both stale within this batch),
rule 21's clause scoped to source-greps while its own examples are behavioral,
three declared defenses with no test (backslash normalization ×2,
`refs/heads/`), a nested-paren regex edge case with a false-PASS direction, and
a benign shell-vs-Dart parser divergence recorded in place.

## Founder triage notes

**The lesson worth carrying:** two of three findings are this batch committing the very classes it was written to close. Finding 1 is a no-op guard against no-op guards; Finding 2 is a guard that only catches the spelling its author happened to type. Neither was visible from reading — both needed someone to run the thing against reality.

Finding 1 is also a clean instance of rule 21's new mutate-it-and-run-it clause justifying itself within hours of being written: the mutation was available the whole time, and the fixture is what hid it. That is the sharper form of the rule — **mutate the code, but check the FIXTURE reproduces a state the real workflow actually produces**, or the mutation proves nothing.

⚠ Process note carried forward from the reviewer, verbatim in substance: while reproducing hook `$0` behavior, a `cd` silently failed and a `git commit` landed on this worktree (`95285150`). It was caught immediately, reset `--soft`, never pushed. Independently verified afterward: HEAD is `a7a254b8`, the staged hash was unchanged at `354ad5b024ff`, and the stray commit is dangling and absent from history.
