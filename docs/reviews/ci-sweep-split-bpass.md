---
reviewed_at: 2026-11-24T19:10:00+05:30
staged_against: cff3fb44
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [guard_without_its_mirror, missing_input, writer_reader_drift, blast_radius_mismatch, secrets_in_tree]
findings_count: 12
verdict: accepted
---

# Code Review: ci-sweep-split (PR #338) at cff3fb44

Scope: `git diff origin/main...HEAD` (38 files): the core / sweep matrix split, the pull-request sweep scope
(`scripts/ci_sweep_scope{,_lib}.dart`, the workflow scope step, `land_pr`'s `sweeps:` line), the titration gate split
into three per-goal files, and the docs. CI's full suite was green on the reviewed SHA (run 45399115784, sweeps ran).
One fresh Sonnet reviewer, read-only, no conversation context. Every finding was reproduced by the coordinator
before its fix; every fix is covered by a test that was mutated (21 mutants, 21 red).

## Finding 1 - P1 - guard_without_its_mirror
- **file:line:** .github/workflows/test.yml (the scope step's `git diff --no-renames --name-only`), scripts/ci_sweep_scope_lib.dart `decideSweeps`
- **claim:** git prints a path holding a non-ASCII byte, a quote or a backslash QUOTED and octal-escaped; the quoted string is in no closure and does not end in `.dart`, so a change to such a closure file answered `run=false`.
- **verification:** `printf '"lib/caf\\303\\251.dart"\n' | dart scripts/ci_sweep_scope.dart` printed `run=false`. No tracked file has such a name today.
- **fix:** `isPlainPath`: a changed path that is not printable ASCII without `"` and `\` is a reason to run. Tests in test/scripts/ci_sweep_scope_test.dart (5 refused shapes, 3 plain shapes that still skip); 6 mutants red.
- **status:** fixed

## Finding 2 - P2 - writer_reader_drift
- **file:line:** scripts/ci_sweep_scope_lib.dart `_directive`, `stripDartComments`
- **claim:** the directive regex was anchored to the start of a line: `import 'a.dart'; import 'b.dart';` gave one edge, `library x; import 'a.dart';` and `@pragma('x') import 'a.dart';` gave none, and a nested block comment hid the directive after it. A missed edge is an input the decision cannot see.
- **verification:** reproduced by calling `directiveUris`; the real tree had no such line (an independent closure gave the same 292 files).
- **fix:** the keyword is matched wherever it starts a word; block comments nest. The real closure is still 292 files with no unresolved edge. 3 mutants red.
- **status:** fixed

## Finding 3 - P2 - guard_without_its_mirror
- **file:line:** test/contracts/titration_gate_split_test.dart `filesProblem`
- **claim:** it searched a gate file for the call, so a commented-out call or one behind `if (false)` passed while that goal ran nothing.
- **fix:** the whole file is pinned line for line (comment and blank lines aside). 5 mutants red, two of them on a real gate file.
- **status:** fixed

## Finding 4 - P2 - blast_radius_mismatch (doc and code)
- **file:line:** scripts/ci_sweep_scope_lib.dart header; the workflow's replay figures
- **claim:** "235 of the 669 lib/ files" is 237 of 671; the 80-merge replay is 27 / 53 on today's main, not 28 / 52.
- **fix:** the header is corrected; the workflow comment keeps the dated measurement and adds the later one.
- **status:** fixed

## Finding 5 - P3 - missing_input
- **file:line:** scripts/data/ci_sweep_durations.json
- **claim:** 40 rows for 42 sweep files; the leg loads quoted in the workflow comment did not match the committed table.
- **fix:** both rows added (1 s each, from run 45399115784); the comment says 646-653 s, recomputed.
- **status:** fixed

## Finding 6 - P3 - guard_without_its_mirror
- **file:line:** .github/workflows/test.yml scope step
- **claim:** a pull request that changes the scope script is judged by its own copy of it; the always-run entry only helps while that copy still behaves.
- **fix:** the shell counts changed paths under `scripts/ci_sweep_scope*`, `scripts/ci_test_partition*` and `.github/` and asks the script only on a count of exactly `0`; a failing `grep` gives no count, which runs the sweeps. Tests under sh and bash; 7 mutants red.
- **status:** fixed

## Delta round on the fixes (fresh Sonnet, `git diff cff3fb44 d94be03b`): 0 P0, 0 P1, 2 P2, 4 P3

## Finding 7 - P2 - guard_without_its_mirror
- **file:line:** scripts/ci_sweep_scope_lib.dart `_directive`
- **claim:** the unanchored regex of finding 2 invents an edge from `final part = 'a.dart';`; an edge to a missing file is `unresolved`, which makes every pull request run the sweeps.
- **fix:** a string literal must follow the keyword at once. Dart source quoted inside a string can still read as an edge; that is caught, loudly and in the core set, by the existing "the walk is COMPLETE" test on the real tree, so it cannot switch the feature off unseen. 1 mutant red.
- **status:** fixed

## Finding 8 - P2 - guard_without_its_mirror
- **file:line:** scripts/ci_sweep_scope_lib.dart `stripDartComments`
- **claim:** a `/*` inside a triple-quoted string opened a comment and hid the directive after it.
- **fix:** triple-quoted strings are tracked to their closing triple. 3 mutants red (one after a test was added for a line-end rule that had none).
- **status:** fixed

## Finding 9 - P3 - guard_without_its_mirror
- **file:line:** test/contracts/titration_gate_split_test.dart `filesProblem`
- **claim:** a lone `\r` ends a line in Dart but not in `split('\n')`, so `// c\r@Skip('x')` read as one comment line.
- **fix:** lines are split on `\r\n`, `\r` and `\n`. 1 mutant red; splitting CRLF as two ends is an equivalent mutant (blank lines are dropped).
- **status:** fixed

## Finding 10 - P3 - writer_reader_drift
- **claim:** `import 'a' 'b.dart';` imports `ab.dart`; the edge read was `b.dart`.
- **fix:** adjacent leading literals are joined and the joined URI is an edge too. 1 mutant red.
- **status:** fixed

## Finding 11 - P3 - stale comment
- **claim:** `stripDartComments`' doc comment still said triple-quoted strings do not occur where it reads.
- **fix:** rewritten with the function.
- **status:** fixed

## Finding 12 - P3 - ledger
- **claim:** the ledger's `BPASS-FIXES` row cited no hash. Gate 40 accepted it (run before the commit).
- **fix:** it cites `d94be03b` now.
- **status:** fixed

## Attacks that found nothing

Closure completeness against an independent any-`.dart`-literal walk; files read by path; always-run paths; deleted
and renamed files; the scope step under `sh -e` and `bash -e -o pipefail` with failing `git` and `dart`; every test
file in exactly one of the 9 legs; the `Unit Tests` gate with a failed, cancelled or skipped leg; the `sweeps:` line;
the titration move (no check lost; per-goal pins sum to the old totals); secrets.

## Founder triage notes

All twelve findings (six, then six in the delta round) fixed in the batch, none declined. Coordinator triage, 2026-11-24.

## Tuning entry
- **2026-11-24** - blast-radius platform - 12 findings over two rounds; 0 false_alarm; tuning: none to the lens set. The delta round's two P2 were both in the FIX for finding 2 (a hand-written reader of Dart source): a fix that loosens a parser gets its own round. For the next brief on a script that reads `git diff --name-only`: name git's path QUOTING (core.quotePath) as an attack, and ask whether the change is judged by its own copy of the judge.
