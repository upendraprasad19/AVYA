---
reviewed_at: 2026-11-07T03:10:00+05:30
staged_against: 485923d4efcd (seats A-C); seat D reviewed the post-fix delta of the same branch
blast_radius: platform
reviewer: claude-sonnet-via-skill (four fresh context-blind seats, no shared context, none told another's findings)
lens_set: [guard_without_its_mirror (incl. installed-copy and analyze-scope sub-checks), writer_reader_drift (incl. moved-prose and inserted-lines sub-checks), function_exception_swallow (shell form), missing_input, asserted_fixture_value, blast_radius_mismatch, secrets_in_tree]
findings_count: 30
verdict: accepted
verdict_note: every finding is fixed in this batch or accepted with its reason below (no P0, no P1; 6 P2, 24 P3; 0 false alarms). Founder triage not required for platform tier (advisory); the author triaged.
---

# Code Review (B-pass) - OI-482 / OI-117, the `dart run` native-assets race at the five git hooks

Self-initiated before the merge (CLAUDE.md 4.3). Execution mode: four Sonnet seats, each in its own scratch dir, with an EXHAUSTIVE command list (read-only git, Read/Grep, `sh -n`,
`dart analyze` per file, the two new test files, and scratch-dir-only shell runs of copies); `dart run scripts/*`, hook scripts in place, network and database statements were forbidden.
Seat A: the shell function and the hook wiring (ran it under dash, bash and bash --posix, with and without `set -e`/`-u`). Seat B: the rewritten gate loop (a scratch rig of the real loop segment,
dash and bash) and the docs, board and ledgers. Seat C: the tests and the env plumbing (a scratch tree running the real test files, mutating scratch copies). Seat D: the delta between the reviewed
state and the fixed state (a second look at what the fixes changed), with busybox applets as a portability stand-in. The author's own evidence is not the reviewers': the reviewers re-ran
fixtures, byte-compared the frozen copies with `origin/main` (identical), and mutated scratch copies.

## Findings (all verified by the author against the files before acting on them)

| # | Seat | Sev | Lens | Finding | Status |
|---|---|---|---|---|---|
| 1 | A | P2 | guard_without_its_mirror | `use_dart_race_retry` is guarded at the hooks by `type use_dart_race_retry`, but it pointed DART_BIN at `_dart_run_retrying` without checking the function exists: a helper with the setter and without the function fails all 22 sites with 127 | fixed: `type _dart_run_retrying ... \|\| return 0` in the setter; test `a helper that has the setter but LOST the function...`; mutant U8 |
| 2 | A | P3 | missing_input | stderr is captured, so it is lost if the hook is interrupted | accepted, stated limit (header of `_dart_bin.sh`, `hooks.md`); the old gate loop sent it to `/dev/null` anyway |
| 3 | A | P3 | stdout/stderr ordering | a caller that merges the streams gets stdout first, stderr last (the gate loop does) | accepted, stated in the header, `hooks.md` and the `_gate_diag` comment |
| 4 | A | P3 | missing_input | a grandchild holding stderr delays the return by its lifetime | accepted, stated limit; no hook script starts a detached child (checked by seat B: `git grep` empty) |
| 5 | A | P3 | passthrough | with fd 0 closed a stdin-reading child hangs under bash | accepted, stated limit; git never closes a hook's stdin (it gives /dev/null or a pipe) |
| 6 | A | P3 | passthrough | NUL bytes in stderr are dropped | accepted, stated limit (Dart text output does not carry them) |
| 7 | A | P3 | writer_reader_drift | `pre-commit.sh` header said "13 times outside the gate loop": 13 counts the loop's own site, so 12 | fixed (also `_dart_bin.sh` header 18 -> 22) |
| 8 | B | P2 | writer_reader_drift (moved/changed prose) | five places still said "the pre-commit loop hides it" (`CLAUDE.md`, code-review `SKILL.md`, `hooks.md`, `check_skill_tuning_history.dart` header and a runtime message), which this batch made false | fixed in all five; CLAUDE.md edited on the author's own grep, not on the reviewer's request |
| 9 | B | P3 | writer_reader_drift | `bug-classes.md` class 2.147 still said "in the git hooks that is OI-482" as a structural fix and "output discarded" | fixed |
| 10 | B | P3 | writer_reader_drift | count changed to a wrong number (see 7) | fixed |
| 11 | B | P3 | writer_reader_drift | archived OI-482 said "three sites" for the silent retry; everything else says four | fixed |
| 12 | B | P3 | writer_reader_drift | closure ledger and diagnose cited pre-change line numbers | fixed (symbols in the ledger; line 400 in the diagnose, checked) |
| 13 | B | P3 | guard_without_its_mirror | a retried-then-failed gate shows its note twice (NOTE line plus the raw note in the block) | accepted, documented (both are true; harmless) |
| 14 | B | P3 | guard_without_its_mirror | an interrupted hook leaves two temp dirs (the old loop left one) | accepted, documented in `hooks.md` ("NOT on an interrupt") |
| 15 | B | P3 | guard_without_its_mirror | NOTE extraction: a NUL byte hid the note (`grep` without `-a`); the bare token in a gate's output counted as a note | fixed: `grep -a`, the pattern is the full phrase `[dart-run-retry] native-assets race`; tests with a NUL gate and a token-only gate; mutants L10b/c/d |
| 16 | B | P3 | guard_without_its_mirror | omitted-lines count off by one when the last line has no newline | fixed (`grep -a -c ''`); 62-line test |
| 17 | B | P3 | guard_without_its_mirror | the "KILLED ... (memory pressure?)" sentence also fires for 129/130/143 where that is not the likely cause | fixed: "from outside: memory pressure, a timeout or an interrupt?" |
| 18 | B | P3 | guard_without_its_mirror | no cap on total diagnostics: a broken shared library would print N x 51 lines | fixed: the first 8 failing gates print output, the rest keep their status line (tests, mutants L33-L36, L40) |
| 19 | B | P3 | guard_without_its_mirror | `_gate_diag` forks per gate even for passing gates (slow in Git Bash) | fixed: one `grep -l -a`, iteration over failure markers, parameter expansion instead of `basename` |
| 20 | B | P3 | process | the plan-review record is not in the staged tree | accepted: lands in its own commit after this file (hash-fixed-point rule of the skill) |
| 21 | C | P2 | asserted_fixture_value | `30 lines omitted` was asserted as a substring of the whole output; a wrong constant (`- 40`) still passed because another fixture printed 30 | fixed: per-block assertions (`blockOf`); two fixtures with different counts |
| 22 | C | P2 | asserted_fixture_value | the documented 60-line boundary was unpinned (mutants 60 -> 20 and 60 -> 69 survived) | fixed: 50/60/61-line gates and a 62-line gate; mutants L37-L39 |
| 23 | C | P2 | guard_without_its_mirror | the new tests assume POSIX (stubs on PATH, `/bin` links) but, unlike their siblings, did not skip on Windows | fixed: `posixGroup` with a visible skip reason (the Windows check is the founder's A/B, ledger row B1) |
| 24 | C | P3 | asserted_fixture_value | the unreadable-output assertions prove nothing as root | fixed: the stub records whether the chmod denied reading; otherwise the test `markTestSkipped`s with the reason |
| 25 | C | P3 | missing_input | an exported `DART_BIN_REAL` leaked into one unit test | fixed: the driver unsets it |
| 26 | C | P3 | test name | a test name over-claimed ("function-definitions-only") | fixed: renamed to what it pins |
| 27 | C | P3 | synchronous spawn | `@Timeout` cannot fire during `Process.runSync` | no action: the same pattern as the sibling hook e2e tests; no hang path found |
| 28 | D | P2 | guard_without_its_mirror | `grep -l` exits 2 when any listed file is unreadable even though it printed the others, so `\|\| DIAG_NOTED=""` discarded the notes of every gate | fixed: `\|\| :` inside the substitution; the unreadable test now has a passing gate with a note beside it; mutant L41 |
| 29 | D | P3 | guard_without_its_mirror | `grep -c ''` counts a line holding a NUL byte twice | fixed: `grep -a -c ''`; a 100-line NUL gate; mutant L42 |
| 30 | D | P3 | writer_reader_drift | wording: "a passing gate's NOTE is not shown" contradicted the loop's own NOTE lines; "printed nothing" (it printed the name); the cap and the setter's attribution missing from some docs | fixed (CLAUDE.md, SKILL.md, bug-classes, hooks.md, the tuning-gate message, the archive); the reviewer's separate note that the cap prints markers in name order is a design choice, now stated; its note that the wiring-text group could run on Windows is declined: the shared `setUpAll` needs `chmod`, and `dart_bin_resolver_test` already pins the same wiring text on every platform |

## Checked and clean (the seats' own lists, condensed)

Exit-status fidelity for 0/1/2/64/70/126/127/254-without-signature/255/signal deaths; argv fidelity (spaces, newlines, empty, `--`, `%s`); stdin as pipe and here-doc; 40 MB of stderr with no
deadlock; same-shell sequences, `$( )`, pipelines, `( ) &` (10 parallel subshells with independent counters); closed stdout/stderr under `set -e`/`-u` in dash, bash and bash --posix; kill switch
byte-identical to today's call; DART_BIN with spaces/relative; the installed-copy matrix (old hook on new helper, new hook on old helper); frozen fixtures byte-equal to `origin/main`; verdict
invariance of the gate loop for exit codes 1, 2, 127-130, 137, 192, 193, 254, 255, no-newline, 3 MB line, NUL, invalid UTF-8; attribution under 4 parallel jobs; temp dirs empty after pass and
fail; closure ledger (11 entries, valid states, Gate 40 rules), the two archived entries (40 lines added, 0 deleted), OI-483's citations, V1/V2, blast-radius tiers, secrets scan,
env-scan classification of the new variables. Not verifiable here (stated): Windows Git Bash, macOS/BSD userland, ksh/zsh, GNU grep older than 3.5.

## Founder triage notes
The author triaged every row (the Status column). Nothing is deferred: the "accepted" rows are stated limits or design choices with their reason, each recorded in `docs/architecture/hooks.md` or
the helper header.

## Tuning entry
- **2026-11-07** - blast-radius platform - 30 findings (6 P2, 24 P3); 0 false_alarm; tuning: lens 8 (asserted_fixture_value) gained a "constant coincidence" sub-check, because two of the three test P2s were a wrong constant that a SIBLING fixture happened to satisfy (a count asserted as a substring of a whole output) and a documented boundary nobody pinned.
