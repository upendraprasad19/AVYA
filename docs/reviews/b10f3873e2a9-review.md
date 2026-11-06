---
reviewed_at: 2026-11-02T18:40:00+05:30
staged_against: b10f3873e2a9
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [guard_without_its_mirror, writer_reader_drift, missing_input, empty_state, contract_test_coverage, asserted_fixture_value, intra_document_drift, cross_document_consistency, secrets_in_tree]
findings_count: 13
verdict: accepted
verdict_note: two Sonnet seats (S1 library and its tests, S2 CLI, wrapper, their tests and the docs); 0 P0, 0 P1, 9 P2 and 10 P3 raised, the seats' near-duplicates merged here into 13 entries; every one fixed in this batch or stated as an accepted residual in plan section 9; the fixes are in the diff this file is named for and were re-gated (full suite, whole-project analyze, pre-commit)
---

# Code Review — b10f3873e2a9

Landing C2 of the merge-conflict treadmill fix (`scripts/sync_resolver_lib.dart`, `scripts/sync_with_main.dart`,
`scripts/sync_with_main.sh`, 8 test files, plan `docs/plans/sync-resolver.md`). Both seats returned `fix-then-accept`.
The seats ran on the pre-fix tree; triage by the author. Detail of each fix: plan section 9, "B-pass" paragraph.

## Finding 1 — P2 — guard_without_its_mirror (S1-1, JSON separator comma)
- **claim:** a conflicted JSON element whose hunk reaches its closing line put the separator comma on the closing marker line, so deleting markers left invalid JSON.
- **status:** accepted — fixed: the comma goes on the last line of each side; a hunk in the middle of an element keeps it after the closing brace (the fuzz caught the first draft; mutant B12 covers the mid-element rule). Tests decode both choices.

## Finding 2 — P2 — contract_test_coverage (S1-2, S1-3, S1-6, verification branches)
- **claim:** V-c's empty-region and not-an-array branches and V-a's duplicate outside a partial hunk had no test.
- **status:** accepted — fixed: tests added; mutants B10, B11 and the V-a `lo > upper` clause (B-pass mutants) red.

## Finding 3 — P3 — intra_document_drift (S1-4, canonical JSON)
- **claim:** the byte-for-byte invariants were stated without saying they hold for canonical JSON.
- **status:** accepted — fixed: plan section 4.3 states it.

## Finding 4 — P3 — empty_state (S1-5, S1-7, gap merged by line; fixture)
- **claim:** a gap git merged cleanly by line was not reported as `merged-by-line`; a fixture had redundant braces.
- **status:** accepted — fixed (`byLine.add('<gap>')`, fixture `$before`; mutant B7 red).

## Finding 5 — P2 — guard_without_its_mirror (S2-1, wrapper exit status)
- **claim:** `wait "$child" || ...` hides the child's real status after a TERM.
- **status:** accepted — fixed: `wait "$child"; rc=$?` in both places; a mirror test (TERM, child exits 0: one `result:` line, exit 0); mutant B1 red.

## Finding 6 — P2 — missing_input (S2-2, signals; S2-10, no git)
- **claim:** a signal to the wrapper alone does not reach the CLI's children; `git` missing from the PATH was an uncaught error.
- **status:** accepted — fixed: documented in the wrapper header and hooks.md (a supervisor signals the process group); `ProcessException` becomes a clean refusal, exit 2 (mutant B5 red).

## Finding 7 — P2 — contract_test_coverage (S2-3, S2-11, S2-12, test gaps)
- **claim:** no test that the ready path and `--commit` prune backups; none for a modify/delete with no stage 3 or a path with a space; root-only chmod tests passed silently as root.
- **status:** accepted — fixed: tests added (mutants B2, B3 red); the chmod tests call `markTestSkipped`.

## Finding 8 — P2 — intra_document_drift (S2-4, CLAUDE.md wording)
- **claim:** CLAUDE.md did not say who concludes the merge.
- **status:** accepted — fixed: "commits only with `--commit`, and only in the run that started the merge: a clean merge is concluded by git itself, a conflicted one through `scripts/safe_commit.sh`".

## Finding 9 — P2 — cross_document_consistency (S2-5, plan-review record)
- **claim:** the plan-review record for this branch was not part of the change.
- **status:** accepted — fixed: `docs/plan-reviews/sync-resolver.md` lands as the second commit of the same PR (citing this file).

## Finding 10 — P3 — contract_test_coverage (S2-6, mutation evidence)
- **claim:** five final-run survivors (MW12, MK34, MK54, MK62, MK86) were only claimed fixed.
- **status:** accepted — fixed: each re-run red; the lines are appended to the final log (205 mutants and 4 controls).

## Finding 11 — P3 — writer_reader_drift (S2-7, S2-8, report lines)
- **claim:** the gate-index run printed a `left` line for the file it then regenerates; a file edited after staging was not named as outside the merge commit.
- **status:** accepted — fixed (`lines.removeWhere`; step 6 names the file); mutants B4, B6 red.

## Finding 12 — P3 — cross_document_consistency (S2-9, replay method)
- **claim:** docs said "first-parent" for the replay; the method is `git log --merges -600`.
- **status:** accepted — fixed in hooks.md and the treadmill plan.

## Finding 13 — P3 — residuals (both seats)
- **claim:** an unreadable `identity` discards `written/` records; the wrapper trap is installed one statement after the child starts; the fetch timeout kills git only; git's English text is asserted in one e2e test; the plan's decision ids D1-D7 differ from the treadmill plan's D4.
- **status:** accepted_residual — stated in plan section 9 (a backup of the file is taken before any discard; the others cannot lose work). No secrets in the diff (secrets_in_tree clean).

## Tuning entry
- **2026-11-02** - blast-radius platform - 13 findings (9 P2, 10 P3 raised, merged); 0 false_alarm; tuning: none (a fuzz found the comma rule that unit tests missed, and every B-pass fix was given its own mutant; the lens set held).
