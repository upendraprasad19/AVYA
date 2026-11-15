---
reviewed_at: 2026-10-22T12:20:00+05:30
staged_against: hook-cwd-fail-open working tree on base c54e63ba (uncommitted; 18 files staged)
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh context-blind read-only seats)
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
---

# Code Review (B-pass) — OI-384 hook-cwd fail-open (`hook-cwd-fail-open`)

Two fresh Sonnet seats, both read-only (no dart, flutter, scripts, shell experiments, network, DB or state-changing
git; exhaustive command list in the brief). Seat A: lenses 1, 3, 4, 7 and docs accuracy. Seat B: lenses 6 and 8,
shell semantics, test discrimination. Lenses 2 and 5 (functions.invoke, unawaited) are out of scope: no Flutter
client code in the diff. Run after the full gate loop (full suite 10149 passed / 9 skipped; pre-commit gate loop OK).

Both seats found the same P1 independently. Distinct findings: 1 P1, 8 P3. All fixed; 0 false alarms.

## Finding 1 — P1 — asserted_fixture_value (both seats)
- **file:line:** `test/scripts/claude_hooks_cwd_independent_test.dart` C11 payload (`'cwd': '$root/supabase/functions'`)
- **claim:** the real git-safety hook waives a raw `git commit` while MERGE_HEAD / CHERRY_PICK_HEAD / REVERT_HEAD exists
  in the PAYLOAD cwd (`scripts/git_safety_hook.dart`, `mergeInProgress`). C11 pointed that cwd at the live repo, so it
  goes red during every merge commit, which is exactly when `scripts/pre-commit.sh` runs the 30-day regression-catalog
  walk that includes this file. The header comment claimed the hook "runs no git". Same trap as b7e4c2.
- **verification:** `grep -n "'cwd': fx.x" test/scripts/claude_hooks_cwd_independent_test.dart`
- **status:** fixed. Payload cwd = the non-repo fixture `fx.x`; the shell still starts in `supabase/functions`.
  Comment and plan line 219 corrected. Proof (`c11_merge_proof.sh`, scratchpad): MERGE_HEAD written into this
  worktree's git dir; fixed C11 1/1 green, the old payload cwd 1 red; MERGE_HEAD removed and file byte-restored.

## Finding 2 — P3 — asserted_fixture_value (seat B)
- **file:line:** `test/contracts/git_safety_hook_integration_test.dart` `expectPrecheckRanAtRoot`
- **claim:** `contains('ROOT=$resolvedRoot')` also accepts `ROOT=<repo>/sub`, so a precheck with an absolute script
  path but `workingDirectory: cwd` stayed green.
- **status:** fixed: end-of-line anchored regex. Mutant N3 (absolute script path + cwd) now red (1).

## Finding 3 — P3 — guard_without_its_mirror (both seats)
- **file:line:** `test/scripts/claude_hooks_cwd_independent_test.dart` `safetyViolations`
- **claim:** the split on `;`/`&&`/`||` missed a newline, carriage return or lone `&`, after which a real program ran.
- **status:** fixed: those are refused outright; three META cases added. Mutants N1 (no newline check) and N2 (no
  lone-`&` check) each red (1).

## Finding 4 — P3 — process (both seats)
- **claim:** C11's two real-`dart` spawns had no per-call `.timeout()` (CLAUDE.md 4.9 spawn row).
- **status:** fixed: 120 s each.

## Finding 5 — P3 — writer_reader_drift, comments (seat B)
- **claim:** `_gitToplevel` inserted above `main()` shifted `git_safety_hook.dart:85-95` and `:126-127`, cited by five
  live comments/reasons (`batch_close_hook.dart:127`, `regression_catalog_lib.dart:138`, two tests, one e2e test).
- **status:** fixed by moving `_gitToplevel` below `main()`; all five citations resolve again, and `exit(2)` is back at
  `:67` as the plan cites.

## Finding 6 — P3 — docs (seat B)
- **claim:** bug class 2.113 listed d7b3e9 as an instance; it is the origin of the exact-match rule.
- **status:** fixed (instances: f2a9c7, b4d7e9, a9c4f2, the `.gate_failures.log` entry).

## Finding 7 — P3 — blast_radius_mismatch (seat A)
- **claim:** `scripts/retire_worktree.dart` / `_lib.dart` fell through to `scripts/**` (feature), though the list they
  hold is what keeps precious ignored files from deletion.
- **status:** fixed: both pinned `platform` in `docs/blast_radius.yaml`; `blast_radius_from_diff.dart` confirms.

## Finding 8 — P3 — docs accuracy (seat A)
- **claim:** OI-384 marked CLOSED while two live checks remain; OI-348's "How to use" omitted section W.
- **status:** fixed: the closure names where each check is tracked (post-merge probe by the merging session; Windows
  check OI-348 W1; OI-361 precedent); the intro now names W.

## Finding 9 — P3 — docs (seat A)
- **claim:** the diagnose-doc's multi-sentence `concept:` becomes a truncated INDEX heading.
- **status:** fixed: slug plus one sentence; the external-reader note moved to its own field. Validator OK.

## Checked and clean (from the seats' reports)
Shell precedence, exit-code propagation, stdin, quoting, dash `cd` exit, linked worktree / nested repo / no-repo
fallbacks; `precheckRoot` null / empty / newline / no-script cases and its call site; the exact retirement entry, its
near-misses and `gitignore_classification_test`; spawn guards; template equality with all nine commands; secrets;
deferral-euphemism scan; bug-class number unique; context budget in band. Not re-run by the seats (read-only):
the author's 18/18 mutation run and the live harness probe (plan 3.5, after the merge).

## Founder triage notes
All findings fixed in this batch; verdict accepted by the author on the founder's standing B-pass instruction.
