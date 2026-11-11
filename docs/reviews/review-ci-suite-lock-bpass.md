---
reviewed_at: 2026-11-11T20:10:00+05:30
staged_against: 0867aa61
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 3
verdict: accepted
verdict_note: three P3, all fixed on the branch after the review (commit after 0867aa61); no P0-P2
---

# Code Review — review-ci-suite-lock (0867aa61)

Context-blind adversarial B-pass (fresh Sonnet seat, self-initiated, §4.3) over the committed three-dot diff
`origin/main...0867aa61` (26 files), after `land_pr --ci-only` reported `ci-green` on that head. No P0, P1 or P2.

## Finding 1 — P3 — writer_reader_drift
- **file:line:** CLAUDE.md §0 pre-push bullet (:40); docs/onboarding/FRESH_CLONE.md:57
- **claim:** the hooks' full-suite paths can now exit 1 while another local suite holds the lock, but the always-loaded §0 hook summary and FRESH_CLONE.md did not say so.
- **verification:** `grep -n "one-suite lock\|_suite_lock" CLAUDE.md docs/onboarding/FRESH_CLONE.md`
- **suggested-fix:** one clause in each.
- **status:** accepted — fixed (both files name the refusal and the lock).

## Finding 2 — P3 — missing_input
- **file:line:** scripts/_suite_lock.sh (common-dir resolution)
- **claim:** `git rev-parse --path-format=absolute` needs git ≥ 2.31; on older git the helper failed open with a misleading "not inside a git repository" warning.
- **verification:** `grep -n "path-format" scripts/_suite_lock.sh` (0 hits after the fix)
- **suggested-fix:** resolve `--git-common-dir` with cd/pwd; reword the warning.
- **status:** accepted — fixed (two-step resolution, so an empty answer can never become `cd ""`; warning reworded). A new test proves the lock is the SAME across a linked worktree (`the lock is shared by every worktree of the clone…`). Mutating the cd/pwd step away is an equivalent mutant (a relative common dir is opened relative to the same cwd it was printed for), stated here rather than claimed covered.

## Finding 3 — P3 — asserted_fixture_value
- **file:line:** test/scripts/suite_lock_e2e_test.dart (`holdLockFor`, no platform guard)
- **claim:** a public function with a private parameter type (`library_private_types_in_public_api` info); the file needs `/proc` and `flock` but carried no platform guard.
- **verification:** `dart analyze test/scripts/suite_lock_e2e_test.dart` → No issues found
- **suggested-fix:** make it private; `@TestOn('linux')`.
- **status:** accepted — fixed (`_holdLockFor`, `@TestOn('linux')`). Also, while re-running: the lock holder is now ONE process (`exec 9>>lock; flock 9; exec sleep 30`) instead of `flock lock sleep`, which forks a child a kill could orphan; 5 consecutive runs left no process behind.

## Lenses that returned clean (reviewer's evidence, summarised)

- guard_without_its_mirror: the wrapper grammar (zero args under `set -u`, flag first, duplicates, four args, empty string, both orders); `_suite_lock.sh` under dash and bash in scratch repos (`command exec`, `--no-wait` closes fd 9, every fail-open path returns 0); the OLD installed hooks on the new tree (never source the helper: unchanged behaviour) and the NEW hooks on an old tree (no-op functions); `type x || x() { :; }` under `dash -e`; `f 9>&-` on a function call hides fd 9 from its child; no remaining real-lock path for a test inside a locked suite; `ci-green` only after `_waitCi` returns. One surviving mutant, judged equivalent: the `exec 9>&-` on the `--no-wait` refusal path (both callers `|| exit 1`).
- writer_reader_drift: no stale §4.12.8/§4.3 wording outside historical plans/reviews; no `docs/sot_registry.yaml` `line_range` cites an edited file.
- blast_radius_mismatch, secrets_in_tree, missing_input: clean as stated. `dart analyze` on all 12 changed .dart files: only the Finding 3 info; `sh -n`/`bash -n` clean on all five shell scripts. Working tree and processes left clean by the reviewer (sha256 restored).

## Founder triage notes

Triaged by the author under the founder's standing pipeline directive (carry a decided unit through its pipeline): all three findings accepted and fixed in this batch; none false.

## Tuning entry
- **2026-11-11** - blast-radius platform - 3 findings; 0 false_alarm; tuning: none (the installed-copy and analyze-scope sub-checks both ran and returned clean; one equivalent mutant named).
