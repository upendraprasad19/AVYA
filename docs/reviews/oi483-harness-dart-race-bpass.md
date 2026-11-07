---
reviewed_at: 2026-11-07T13:35:44+05:30
staged_against: 9a3c9a777818 (seats A-C), 40fb0f9e59b8 (seat D), e90b3e349fb7 (seat E); final staged state 97d92aa509a4, which differs from the seat E state only by doc wording
blast_radius: platform
reviewer: claude-sonnet-via-skill (five fresh context-blind seats, no shared context, none told another's findings)
lens_set: [guard_without_its_mirror (incl. installed-copy and analyze-scope sub-checks), writer_reader_drift (incl. moved-prose and inserted-lines sub-checks), function_exception_swallow (shell form), missing_input, asserted_fixture_value (incl. constant-coincidence)]
findings_count: 25
verdict: accepted
verdict_note: every finding is fixed in this batch or accepted with its reason below (no P0, no P1; 5 P2, 20 P3; 0 false alarms). Founder triage not required for platform tier (advisory); the author triaged.
---

# Code Review (B-pass) - OI-483, the `dart run` native-assets race at the harness hooks, the launchers and the Dart spawns

Self-initiated before the merge (CLAUDE.md 4.3). Run after a green full suite on the seat A-C state (13,571 passed, 14 skipped, 0 failed), the pre-commit gate loop and a whole-project analyze. Execution mode: Sonnet seats, each with its own scratch dir and an EXHAUSTIVE command list (read-only git, Read/Grep, `sh -n`, `dart analyze` per file, named test files, scratch-copy shell runs); `dart run scripts/*`, scripts in place, `rm`, network and database statements were forbidden. Seat A: the shell function and the nine harness commands. Seat B: the launchers, signals and the seven wrapped Dart spawns. Seat C: tests, env plumbing, docs and ledgers. Seat D: the delta after the first fixes. Seat E: the one final probe line. The primary tree was checked clean after the wave.

The review changed the code. The probe of the nine harness commands went through three forms in this pass, each measured on hostile helpers under dash, bash and bash --posix before adoption:

| Form | Hole | Found by |
|---|---|---|
| `if (. helper && setter) >/dev/null 2>&1; then` | a top-level `exit 0`, and a `set -e` plus a failing command at the top under bash, passed the probe and ended the hook shell before dart: a blocking exit 2 became an allow | seat A (the first was a stated residue) |
| `(. helper; setter && exit 7) ...; if [ $? = 7 ]; then` | a helper with `exit 7` did the same, and an errexit hook shell died on the probe with a SOUND helper | seat D |
| `p=$( (. helper; setter && echo ok) 2>/dev/null); if [ "$p" = ok ]; then` (shipped) | none in dash, bash or bash --posix; 14 helpers, every cell one dart call and exit 2. With errexit a sound helper is fine and a broken one ends the hook (stated, the harness shell does not set it) | seat E measured no regression |

The rejected forms are permanent mutants M22 to M25 in the META group of `test/scripts/claude_hooks_cwd_independent_test.dart`, each killed by its named check. New rows: `exit 0` and `exit 7`, at the end and on the first line of the helper, a `set -e` head, and a hook shell in errexit with a sound helper, lost race included.

## Findings (all verified by the author against the files before acting on them)

| # | Seat | Sev | Lens | Finding | Status |
|---|---|---|---|---|---|
| 1 | D | P2 | guard_without_its_mirror | the status sentinel: `exit 7` in the helper exits the hook with 0 dart calls | fixed: stdout sentinel, `exit 7` rows, M24 |
| 2 | C | P2 | writer_reader_drift | `hooks.md:282` still said "Still not routed through `_dart_bin.sh`" in the row that says the opposite | fixed |
| 3 | C | P2 | writer_reader_drift | `naming_conventions.md:395` said the retry is NOT applied to the harness hooks, launchers or plain form | fixed |
| 4 | C | P2 | writer_reader_drift | `common-pitfalls.md:183` listed the harness hooks and launchers as not covered (a file outside the diff) | fixed |
| 5 | C | P2 | missing_input | `docs/plan-reviews/oi483-harness-dart-race.md` is cited and absent | by protocol: lands in its own later commit, citing this file (SKILL section 3) |
| 6 | A | P3 | guard_without_its_mirror | a top-level `exit 0` passes the probe and ends the hook; a known residue before this pass | fixed, no longer a residue |
| 7 | A | P3 | guard_without_its_mirror | `set -e` plus a failing command in the helper diverges by shell | fixed, M23, M25 |
| 8 | A | P3 | missing_input | the wrapper holds stderr until the child exits, lost on a harness kill | accepted, stated in the file header (OI-482 row) |
| 9 | B | P3 | guard_without_its_mirror | `exec` replaced by a background child: a SIGKILL of `safe_pr_merge.sh` alone orphans dart | accepted, stated and pinned; `land_pr.dart` passes that wrapper no timeout, and the orphan still runs its CI-green check |
| 10 | B | P3 | writer_reader_drift | three comment citations moved by the inserted import | fixed (`:30`, `:99`, one range dropped) |
| 11 | B | P3 | missing_input | the 10 s budget of the batch-close telemetry now spans retries; an abandoned future could start one | accepted, the hook exits and takes it with it; the spawned CLI is read-only |
| 12 | B | P3 | function_exception_swallow | the launcher keys on 254 alone, so a compile error runs three times | accepted, stated; 2 s extra, no CLI `main` exits 254 (seat B grepped every exit path) |
| 13 | C | P3 | writer_reader_drift | closure title cited `safe_merge.sh:286,308`, now 288 and 310 | fixed, numbers dropped |
| 14 | C | P3 | writer_reader_drift | `naming_conventions.md:396`: note shape and "four sites" | fixed: `stderr=shown above`, six sites |
| 15 | C | P3 | writer_reader_drift | `hooks.md:282` "18/18 mutants red" was stale | fixed, the count removed |
| 16 | C | P3 | writer_reader_drift | the manifest row was out of order | fixed |
| 17 | C | P3 | asserted_fixture_value | the new TERM test leaves `p` running on a failure | fixed, `addTearDown` kills it |
| 18 | C | P3 | asserted_fixture_value | `>= 1` note against a 10 s budget can flake under extreme load | accepted: the bound is deliberately loose, the kill-switch twin pins 0, and the first attempt of a poisoned child fails in far less than the budget |
| 19 | D | P3 | guard_without_its_mirror | a hook shell in errexit dies on the status sentinel, sound helper included | fixed, the errexit row |
| 20 | D | P3 | writer_reader_drift | diagnose line 58 still named `exit 0` as the one residue | fixed |
| 21 | D | P3 | asserted_fixture_value | the plan's "every cell" claim did not cover `exit 7` | fixed, re-measured on 14 helpers |
| 22 | E | P3 | writer_reader_drift | "prints `ok`" was not strict: a helper printing a bare `ok` passes without a setter | fixed wording, stated limit; dart still runs |
| 23 | E | P3 | writer_reader_drift | errexit limit understated: under dash a missing helper exits 2 | fixed wording, stated limit |
| 24 | E | P3 | writer_reader_drift | the `hooks.md` cost figure predated this change | fixed: +0.4 ms dash, +0.7 ms bash (seat E, 100 runs) |
| 25 | E | P3 | missing_input | a CRLF helper turns the retry off silently | accepted, safe direction, stated; `.gitattributes` keeps it LF |

## Verification after the fixes

The full suite ran on the seat A-C state. After it, the code changed in the nine command strings, one test file's rows and mutants, a tearDown and comments, so the four affected test files were re-run (the hook file 24 of 24 on the final form), plus the gate loop and the whole-project analyze; CI runs the whole suite on the PR.

## Founder triage notes

Platform tier: advisory, triaged by the author. One founder check stays open: B1 in the closure ledger, the Windows clone.

## Tuning entry
- **2026-11-07** - blast-radius platform - 25 findings (5 P2, 20 P3); 0 false_alarm; tuning: lens 6 gained a sentinel sub-check, because two successive fixes of one probe each opened a hole the next fresh seat measured, and a delta seat per fix is what caught them.
