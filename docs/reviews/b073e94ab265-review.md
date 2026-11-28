---
reviewed_at: 2026-11-03T00:30:00+05:30
staged_against: b073e94ab265
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [guard_without_its_mirror, writer_reader_drift, missing_input, empty_state, contract_test_coverage, asserted_fixture_value, intra_document_drift, cross_document_consistency, secrets_in_tree]
findings_count: 12
verdict: accepted
verdict_note: two Sonnet seats (S1 library and CLI, S2 wrapper and docs); 0 P0, 0 P1, 5 P2 and the P3s raised, merged here into 12 entries; every one fixed in this batch or stated as an accepted residual in plan section 8; the fixes are in the diff this file is named for and were re-gated (mutation table re-run, full suite, whole-project analyze, pre-commit)
---

# Code Review — b073e94ab265

Landing D of the merge-conflict treadmill fix (`scripts/land_pr.sh`, `scripts/land_pr.dart`, `scripts/land_pr_lib.dart`, the classifier in
`scripts/safe_pr_merge_lib.dart`, 5 test files and a fixture, plan `docs/plans/merge-train.md`). Both seats returned `fix-then-accept`.
The seats ran on the pre-fix tree; triage by the author. Detail of each fix: plan section 8, "B-pass changes".

## Finding 1 — P2 — writer_reader_drift (S1-P2-1, main read more than once per round)
- **claim:** origin/main was read separately for the ancestry check, the record gate and the push guard, so a fetch by another session between the reads could make them disagree.
- **status:** accepted — fixed: read ONCE per round (`mainSha`); the ancestry check, `_recordGate(head, mainSha)`, `PUSH_BEFORE` and the commit-tree parent use it; the scratch clone checks `refs/replay/main == mainSha` else `needs-human`. Test: replay "origin/main moving between the ancestry check and the replay"; source pins; mutants N-series red.

## Finding 2 — P2 — missing_input (S1-P2-2, interrupt window)
- **claim:** a TERM during the `gh` read of the PR head, or before the push, was not checked before the next step started.
- **status:** accepted — fixed: `_checkInterrupt()` after the PR head read and before the push. Tests: TERM during a gh read (no replay, no merge), TERM during the loop's ls-remote via a fake git on the PATH (no push); mutants red.

## Finding 3 — P2 — missing_input (S1-P2-3, non-UTF-8 child output)
- **claim:** a malformed byte in a child line stopped the output pump.
- **status:** accepted — fixed: `Utf8Decoder(allowMalformed: true)`; e2e test with a stray 0xFF byte; mutant N06 red.

## Finding 4 — P2 — guard_without_its_mirror (S1-P2-4, our own streams)
- **claim:** a closed stdout or stderr turned a landing into an uncaught error while the merge ran.
- **status:** accepted — fixed: safe writers `_out`/`_err`, `stdout.done`/`stderr.done` errors swallowed, a bounded final flush (the closed-stdout test found that flush never completes on a closed descriptor), a running-children counter that an uncaught error waits for. Tests: closed stdout still merges. Mutants N08, N10, N11 red (N11 by source pin only). One survivor, N09 (the `try/catch` inside `_out` turned into `rethrow`): a closed stdout reports its error through `stdout.done`, not as a synchronous throw, so no test reaches it; kept as defence for a detached stdout, stated honestly as not behaviourally proven.

## Finding 5 — P2 — intra_document_drift (S1-P2-5, no lock)
- **claim:** two runs for the same PR or in the same worktree can interleave.
- **status:** accepted_residual — a lock was rejected on purpose (`scripts/_git_lock.sh` is unsound, OI-92); documented as residual R1 in the wrapper header, plan section 8 and hooks.md.

## Finding 6 — P3 — empty_state (S1 P3s, messages)
- **claim:** a multi-line gh or git error could put a line starting with `result:` into the output.
- **status:** accepted — fixed: every message passes `_oneLine` (joined by ` | `); e2e test; mutant N07 red. Direct CLI use with the test seams is documented as test-only in the header.

## Finding 7 — P2 — guard_without_its_mirror (S2-1, bash early reap)
- **claim:** under bash the child can be reaped inside the SIGCHLD handler, after which `wait` answers with the signal's 128+n and the wrapper reported a wrong status.
- **status:** accepted — fixed: a second `wait` when the status is above 128 (127 ignored). A test under bash is in the suite, but this machine's bash does not reach the early-reap path (mutant W07 survived the behavioural suite); the branch is pinned by shape and order (source pin) and W07 is red by that pin only. Stated as not behaviourally proven.

## Finding 8 — P2 — missing_input (S2-2, early signal, wrapper messages)
- **claim:** a signal between the start of the CLI and the trap was lost; `--allow-workflow-change <pr>` got a misleading message.
- **status:** accepted — fixed: the trap is set before the CLI starts, a `got` flag remembers an early signal and the wrapper delivers it after the start (W05 is red by source pin only: the window is microseconds wide); a reversed-argument message ("the PR number comes first", W06 red). Wrapper tests: INT and HUP forwarded, bash variant, SIGKILL becomes `result: error` exit 4, a scripts path with a space.

## Finding 9 — P2 — contract_test_coverage (S2-3, vacuous pins)
- **claim:** several pins matched anything (plan table rows, hooks.md code-and-word pairs, trap order).
- **status:** accepted — fixed: pins tightened to table rows and sections, plus new pins for `mainSha` ancestry, `_recordGate(head, mainSha)`, `stdout.done.catchError`, the child-wait loop and the bash reap branch.

## Finding 10 — P3 — cross_document_consistency (S2 docs)
- **claim:** the plan had a stale section number and the needs-human wording of hooks.md was thin.
- **status:** accepted — fixed: the plan is renumbered ("## 8. As built" with a "B-pass changes" paragraph), hooks.md lists commit-failed, someone-pushed and main-moved-during-replay; `backups/context_artifact_sizes.json` re-recorded (all 13 entries, intended).

## Finding 11 — P3 — contract_test_coverage (found while re-running the mutants)
- **claim:** (author, not a seat) the SIGHUP wrapper test failed whenever the suite was started under `nohup`, because an ignored SIGHUP cannot be trapped by `sh`; and the closed-stdout e2e test had a `startSpawn` without a `reportSpawn` (the full suite's spawn-sites guard caught it).
- **status:** accepted — fixed: the test starts the wrapper through `perl -e '$SIG{HUP} = $SIG{INT} = "DEFAULT"; exec @ARGV'` so it does not depend on how the suite was started; `reportSpawn` added; the guard test and the e2e file pass (95/95).

## Finding 12 — P3 — residuals
- **claim:** one unrelated test (`test/ai_coach/workout_log_confirm_card_saved_signal_test.dart`) failed once under load in an earlier full run and passes alone; the final full run did not show it again.
- **status:** accepted_residual — not touched by this diff; CI is the gate. No secrets in the diff (secrets_in_tree clean).

## Tuning entry
- **2026-11-03** - blast-radius platform - 12 findings (5 P2 plus P3s, merged); 0 false_alarm; tuning: none (the seats found a real hang class — a flush on a closed stdout — and a bash timing path; two mutation survivors are pin-only and named; the full suite, not the targeted runs, caught the spawn-guard breach; the lens set held).
