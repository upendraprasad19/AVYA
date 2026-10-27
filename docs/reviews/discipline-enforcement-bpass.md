---
reviewed_at: 2026-08-25T14:15:00+05:30
staged_against: fbbea768
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 4
verdict: accepted
---

# Code Review — discipline-enforcement

Four findings, **2 P0**, all reproduced live by the reviewer and independently
re-verified by the author before fixing. All four fixed in this batch.

Two ×2 review rounds preceded this pass. Neither found any of these.

## Finding 1 — P0 — guard_without_its_mirror / writer_reader_drift
- **file:line:** `scripts/batch_close_hook.dart` `_range()`
- **claim:** `_range()` fell straight to `origin/main..HEAD`, never checking whether local
  `main` is ahead of `origin/main` — which CLAUDE.md §4.13 point 1 documents as **the common
  state** for this repo. Reproduced live: `origin/main..HEAD` = **9**, `main..HEAD` = **2**.
  Every DERIVED row was then computed over three unrelated batches:
  `reviewsAdded` picked up `docs/reviews/2e9503eb-review.md` and marked the skill-tuning row
  `[x]` satisfied; `hasBugfixCommit` matched two `fix(...)` subjects from other batches; and
  `oldestUnpushedAt` anchored the retrospective check to an unrelated commit's date.
  **Three rows reported green on somebody else's evidence.**
  `new-worktree.sh:65-91` had already solved this exact range-selection problem with
  `merge-base --is-ancestor`. This hook reinvented range detection and did not carry the fix
  across — the third guard-without-its-mirror instance in this batch.
- **verification:** `git rev-list --count main..HEAD` vs `git rev-list --count origin/main..HEAD`,
  then run the hook and read the row states.
- **status:** accepted — fixed. Extracted `chooseRange()` into the pure lib: prefer the
  TIGHTEST range that still describes the batch (`main..HEAD` on a branch;
  `origin/main..HEAD` once main has nothing beyond it). Mutation: reverting to
  always-`origin/main..HEAD` reddens 1.

## Finding 2 — P0 — guard_without_its_mirror
- **file:line:** `scripts/skill_tuning_lib.dart` `hasTuningEntryFor`
- **claim:** The matcher proved only that *a* bullet with that date exists — not that an entry
  for **this** review exists. Two reviews on one calendar date collapse into one satisfied
  check. **Live at the time of review:** `SKILL.md:129` already carried a `2026-08-25` bullet
  for the `oi60-client-blockers` review, so this very B-pass's review file — written the same
  day — would have been reported PASS with no entry of its own. The gate built to stop the
  skill's self-evolution loop decaying would have silently passed **its own first real use**.
- **verification:** `grep -nE '^\s*[-*]\s+\*\*2026-08-25\*\*' .claude/skills/code-review/SKILL.md`
  returns exactly the unrelated entry.
- **status:** accepted — fixed. New `hasTuningEntryForReview()` scans the dated bullet's BLOCK
  (to the next dated header or EOF) and requires it to NAME the review. Mutation: reverting to
  date-only reddens 2.

## Finding 3 — P1 — blast_radius_mismatch
- **file:line:** `docs/blast_radius.yaml` — no entries for the four new script files
- **claim:** The whole diff classifies `platform` only because `CLAUDE.md` and
  `.claude/settings.json` are in it. The four new scripts ALONE classify **`feature`**. A later
  commit touching only them — fixing one of the two P0s above, say — would skip both the local
  full suite at pre-push and the ≥account keystone plan-review gate. Every sibling that guards
  a commit is already pinned.
- **verification:** pipe just the four paths through `blast_radius_from_diff.dart -`.
- **status:** accepted — fixed. All four pinned `platform` above the `scripts/**` catch-all,
  with the rationale recorded inline: the machinery that enforces discipline must not be the
  one piece changeable without it.

## Finding 4 — P1 — writer_reader_drift (doc vs behaviour)
- **file:line:** `scripts/batch_close_hook.dart` `_range()` comment vs `main()`
- **claim:** The comment claimed a null range is "UNKNOWN, not zero … would silence the hook
  exactly where a fresh clone needs it most." `main()` did precisely that: `range == null ? 0`,
  and `evaluateBatchClose` treats 0 as fully silent. Reproduced with a fresh repo: silent,
  exit 0, right after a commit landed.
- **status:** accepted — resolved as a DOC fix, deliberately, not a behaviour change. With no
  `main` and no `origin/main` there is no mainline to measure a batch against, and a hook that
  blocked every turn in a fresh clone would be worse than one that says nothing. The comment
  now states the real behaviour and a test pins it, so silence-on-unknown is deliberate rather
  than accidental.

## Lenses that returned clean

- **function_exception_swallow** — no `.functions.invoke(` in the diff; pure Dart + docs.
- **secrets_in_tree** — no credential-shaped literals.
- **unawaited_no_error_sink** — no `unawaited(` added.
- **.gitignore correctness** — `git check-ignore -v` resolves both the state file and the kill
  switch to the two lines this diff adds.
- **Per-worktree state isolation** — state path derives from the worktree's own
  `--show-toplevel`, so two sessions in different worktrees do not interfere.
- **`renderBlockReason` JSON safety** — built via `jsonEncode`, and the row count is fixed at
  ~6 regardless of commit count, so no unbounded growth.

## Founder triage notes

Not required — all four fixed in-batch rather than triaged; the verdict moved `pending` →
`accepted` only after each fix landed with a mutation proof.

⚠ **Process incident during this review, recorded rather than absorbed.** The reviewer's own
`cd` into a not-yet-created scratch directory failed silently, leaving the shell in this
worktree, and a subsequent `ALLOW_RAW_GIT=1 git commit` landed a stray commit here, deleting an
untracked file. The reviewer caught it, reset to `fbbea768`, and recovered the file byte-for-byte
from the stray commit's tree. Author independently verified afterwards: HEAD correct, stray
commit not an ancestor, file intact at 136 lines. Two real lessons: chain `cd <dir> && …` so a
failed `cd` aborts (the repo's own "cwd can silently revert" class), and a review subagent
should not hold a raw-git escape hatch at all.
