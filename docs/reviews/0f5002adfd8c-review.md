---
reviewed_at: 2026-09-29T21:00:00+05:30
staged_against: 0f5002adfd8c
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, modelled_on_is_a_checkable_claim, self_attesting_artifact]
findings_count: 5
verdict: accepted
---

# Code Review — 0f5002adfd8c

Branch `branch-lifecycle-cleanup` (OI-138: `retire_worktree.dart` deletes the retired
worktree's own merged local branch with `git branch -d`). One context-blind Sonnet
reviewer, isolated worktree, the staged patch applied with `git apply --index`, own
scratch repos, no shared ref touched. It was dispatched against staged hash
`223280051c51`; the fixes below moved the hash and the file was renamed to match
(`docs/reviews/` is hash-excluded, so the rename itself is free).

Author-side gates before dispatch: `flutter analyze lib/` 0 warnings / 0 errors,
full `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden` 7071 passed, 0 failed.

## Finding 1 — P2 — self_attesting_artifact / guard_without_its_mirror
- **file:line:** `docs/diagnoses/2026-09-29-retire-worktree-deletes-branch-4c3fc4.md` (M7 "zero red, cannot be reproduced end to end"); `scripts/retire_worktree.dart:132-137`; the OI-138 closure text.
- **claim:** The ancestry re-check was described as untestable (a race), so its zero-red mutation was waved through as defense in depth. It is deterministically testable, and it is the only guard against deleting an UNMERGED branch that has an in-sync upstream, because `git branch -d` accepts "merged into its upstream".
- **verification (reviewer):** scratch repo with a bare origin, worktrees `a1`/`b1` both merged and tracking `origin/<b>`, plus a `reference-transaction` hook that on deletion of `refs/heads/a1` commits on `b1` and advances `refs/remotes/origin/b1`. Real script: `KEPT-BRANCH b1 [not an ancestor of main at delete time]`. With `if (anc.exitCode != 0) {` mutated to `if (false) {`: `BRANCH-DELETED b1`.
- **author re-verification:** reproduced independently in a new e2e test. Mutation M9 (the same edit; `grep -c "if (false) {"` = 1, so it applied) reddens exactly 1 test, the new one, failing on `BRANCH-DELETED b1` (an assertion, not a compile error). File restored, `cmp` identical.
- **status:** accepted — fixed. New test "the ancestry re-check is what keeps an UNMERGED branch"; the "untestable race" wording removed from the diagnose-doc, the code comment, the OI-138 closure text, and corrected in the spec (§10).

## Finding 2 — P2 — modelled_on_is_a_checkable_claim / self_attesting_artifact
- **file:line:** diagnose `impact_analysis` ("still refuses --execute without a slug").
- **claim:** The tool never refused a bare `--execute`; a pre-existing e2e test runs it bare and expects exit 0. So the new branch deletion is reachable unscoped, and the only defence is CLAUDE.md prose.
- **verification (reviewer):** `grep -n "only == null\|only != null" scripts/retire_worktree.dart` gives filters only (`:235,:244,:361,:400,:409`); author re-check: `retire(['--execute'])` at `test/scripts/retire_worktree_e2e_test.dart:254`.
- **status:** accepted — fixed by correcting the claim, not by changing the tool. Making the tool refuse a bare `--execute` would change existing behaviour and the existing test, which is not what the founder approved for this batch. The diagnose-doc now says a bare `--execute` deletes every retirable worktree's branch behind the same guards; CLAUDE.md §4.13.6 already said so; the spec §10 records the correction. Whether the tool should refuse an unscoped `--execute` is a product decision for the founder, stated in the batch report.

## Finding 3 — P3 — guard_without_its_mirror
- **file:line:** `scripts/retire_worktree.dart:343-346` ("Structural, not a tested condition — no test forces `git worktree remove` to fail").
- **claim:** A test can force removal to fail, and git's own refusal of a checked-out branch absorbs the data-level effect, so the "only after removal succeeds" guard is invisible except in the output.
- **verification (reviewer):** `chmod 000` on an ignored `build/sub`, then moving the call ahead of removal gives `KEPT-BRANCH f1 [cannot delete branch 'f1' used by worktree ...]` before `FAILED f1`.
- **author re-verification:** new e2e test (skipped on Windows and uid 0). Mutation M10 (branch deletion moved before, and independent of, removal; the call count confirmed 1, moved) reddens 6 tests including the new one, which fails on an unexpected `KEPT-BRANCH f1`. Restored, `cmp` identical.
- **status:** accepted — fixed. New test "a FAILED worktree removal never touches the branch"; comment corrected.

## Finding 4 — P3 — writer_reader_drift
- **file:line:** `CLAUDE.md:860` (§4.13.8 go-condition) and `:893`; `scripts/retire_worktree_lib.dart:148`.
- **claim:** After a GitHub-PR merge with delete-on-merge and a pruned tracking ref, the dry-run prints the reworded `merged + clean (no upstream configured, or it was deleted on the remote ...)` rather than `[merged + clean + pushed]`, but §4.13.8 names only the latter as the go-signal. A literal-reading agent has a go-condition the tool never prints in the exact case this batch exists for.
- **verification (reviewer):** `git grep -n "merged + clean + pushed" -- CLAUDE.md` matches `:860` and `:893` as expected signals; tests pin only `contains('no upstream configured')`.
- **status:** accepted — fixed. §4.13.8 now accepts either form; the `:893` pitfall row states both.

## Finding 5 — P4 — blast_radius_mismatch / self_attesting_artifact
- **file:line:** `docs/blast_radius.yaml` (no `retire_worktree` entry; falls to `scripts/** feature`); platform `requires:` includes `feature_flag`; no plan-review record in the diff.
- **claim:** A new destructive path is tiered `feature` by path and `platform` only because `CLAUDE.md` is in the diff, so `feature_flag` has nothing behind it. The plan-review record must exist with `bpass: accepted` before the merge or the CI keystone gate fails.
- **verification (reviewer):** `grep -n "retire_worktree" docs/blast_radius.yaml` prints nothing.
- **status:** accepted — resolved by process. The plan-review record `docs/plan-reviews/branch-lifecycle-cleanup.md` lands in its own later commit (the `docs/plan-reviews/` hash fixed-point) and states the no-flag position explicitly: the change cannot delete an unmerged branch (`-d` plus the ancestor re-check plus name guards), never a remote, never `-D`, and is reversible by the reflog. The path-tier gap is OI-139, already open.

## Lenses that returned clean (reviewer's account, with the commands it named)
- **1 writer_reader_drift** (beyond F4): `git grep -n -E "KEPT-BRANCH|BRANCH-DELETED|no upstream configured|would be deleted|would be kept|\[merged \+ clean"` found only the changed script, its tests, CLAUDE.md, the spec, the diagnose doc and two historical review docs. No parser of these strings in `.claude/`, `scripts/*.sh`, or any hook.
- **2 function_exception_swallow:** `_git` returns null only on `ProcessException`; every new call site prints `KEPT-BRANCH ... [git unavailable]`, fail-closed.
- **4 secrets_in_tree, 5 unawaited_no_error_sink:** clean (all `Process.runSync`; only pre-existing `secrets/` fixtures matched).
- **6 other guards:** real-git runs with `feat/é`, `Feature/Up`, and a branch `T` plus tag `T`: all retired, tag survived. Detached worktree is `KEEP [branch not merged]`. Lowercasing mutation (`final lower = branch`, applied) reddens 3.
- **7 missing_input:** git 2.43.0 accepts `branch --merged main --format=%(refname)` and `branch -d -- <b>`.
- **8 asserted_fixture_value:** 16 + 46 = 62 tests at dispatch, matching the pass count; line citations `:141/:216/:346` and lib `:374` resolved. It counted 7 `test(` entries in the OI-138 group against the doc's "8": the doc was wrong. Author check: the group had 7 at dispatch (now 9), and the diagnose-doc/OI text is corrected. The reviewer did not re-run M1-M4, M6, M8; those were the author's runs (M6 and M8 not independently re-derived by the reviewer).
- **9 modelled_on_is_a_checkable_claim:** §4.13.8's added sentence is scoped to `--execute <slug>` and says "not additional authority"; it does not widen the founder's authorization in text.
- **10 self_attesting_artifact:** diagnose, spec, `contract_test_path`, OI-138's `4c3fc4` and OI-273's spec reference all resolve in the staged tree.

## Founder triage notes
All five findings accepted and closed in this batch; none deferred. Open decision for the founder, not made here: whether `retire_worktree.dart` should refuse an unscoped `--execute` (Finding 2).
