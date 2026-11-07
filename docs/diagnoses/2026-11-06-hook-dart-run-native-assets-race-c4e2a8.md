---
bug_id: c4e2a8
date: 2026-11-06
batch: oi482-hook-dart-run-race
status: fixed
tier: m_fix
blast_radius: platform
symptom: >-
  The git hooks (pre-commit, commit-msg, prepare-commit-msg, pre-push, pre-merge-commit) run `"$DART_BIN" run <script>` at 22 sites, and the pre-commit
  gate loop runs it for every gate, four at a time, in the repo root, with `>/dev/null 2>&1`. When such a `dart run` starts while another `dart run`
  has `.dart_tool/native_assets.yaml` truncated, it exits 254 with `File not formatted as yaml: .` before `main` (mechanism: diagnose b7e2d9). In
  a hook that is a lost gate with no explanation: a DIFFERENT gate failed on each run (2026-09-29, 2026-11-05) and six gates at once at load about 10
  (2026-11-06), each green alone and green with PRE_COMMIT_GATE_JOBS=1, and the loop printed only a gate name; prepare-commit-msg silently dropped the
  `Blast-radius:` line (stderr to /dev/null); a lost race at a commit-msg gate rejected a commit. A gate SIGKILLed under memory pressure printed the same
  `GATE FAIL` line as a gate that found a violation (OI-117, observed 2026-08-13). NOT established: that the loop's historical failures were this race (their
  output was discarded and they were never reproduced); this change makes the next one visible.
concept: not_applicable — git-hook shell tooling (scripts/_dart_bin.sh, the five hooks); no Hive/cloud writer-reader contract and no entry of docs/sot_registry.yaml covers it.
sot_registry_entry: not_applicable — no writer/reader pair, Hive key or cloud table is involved.
related_bugs: [b7e2d9, a7f3d1, e6c4a9]
recurrence: |
  RECURRENCE of the OI-468 / OI-311 exit-254 family (class 2.147): b7e2d9 measured the mechanism and contained it in the TEST spawn helper only, and filed
  this OI for the hook sites. Also the bad-news-vs-no-news class (OI-117, class 2.90's sibling): an exit status reported without its cause. The known-good
  fix of b7e2d9 is applied here in shell: retry exactly the measured signature (a dart child, `run`, exit 254, the text on stderr), a bounded budget, a
  printed note.
writers:
  - { file: scripts/_dart_bin.sh, method_or_widget: "_dart_run_retrying: re-runs a `run` that exits 254 with the signature on stderr, at most twice, one note per retry; use_dart_race_retry: sets DART_BIN to the function's name unless AVYA_DART_RUN_RETRY=0", line: 147 }
  - { file: scripts/pre-commit.sh, method_or_widget: "the backgrounded gate subshell keeps each gate's output and exit status; _gate_diag prints retry notes, a failing gate's output (all of it up to 60 lines, else first 20 and last 30), its exit status, and a distinct sentence for a gate killed by a signal", line: 399 }
  - { file: scripts/pre-commit.sh, method_or_widget: "the guarded call after DART_BIN is assigned (and the same one line in commit-msg.sh, prepare-commit-msg.sh, pre-push.sh, pre-merge-commit.sh)", line: 64 }
readers:
  - { file: scripts/pre-commit.sh, method_or_widget: "22 `\"$DART_BIN\" run` sites across the five hooks: unchanged text, now resolved to the function (the gate loop's own is this one)", line: 400 }
  - { file: scripts/gate_scripts_wired_lib.dart, method_or_widget: "invokesGate: reads the `\"$DART_BIN\" run scripts/<gate>` form (Gate 33); unchanged because the call sites are unchanged", line: 153 }
  - { file: test/helpers/spawn_env_scan.dart, method_or_widget: "_scanShell: reports DART_BIN / DART_BIN_REAL as env reads of the helper; classified in spawn_env_manifest_test.dart _localShell", line: 263 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/scripts/dart_run_retry_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no user data.
forbidden_patterns_checked:
  - "an executable wrapper file standing in for dart (round 1 design) — rejected: scripts here are mode 100644 (a wrapper needs 100755 or the feature silently no-ops on a fresh checkout), it needs its own blast-radius entry, a dirname/symlink story and an untested Windows exec; a shell function has none of them"
  - "rewriting the 22 sites to `dart_run <script>` — rejected: Gate 33 (invokesGate), the stdin-usage gate, dart_bin_resolver_test checks 3 and 4 and contract_sweep_wired_test read the `\"$DART_BIN\" run` form"
  - "retrying any 254 — rejected: 254 is also a compile error; the retry needs the signature text AND `run`"
  - "the plain form `dart <script>` for the loop — rejected: it removes the loop's writers but not its victims, and any other session's `dart run` is still a writer"
  - "making a killed gate non-blocking (the OI-117 'only the second should block') — rejected: a gate that could not run is not a pass; the hook prints a distinct sentence and still blocks"
  - "a temp file for the captured stderr — rejected: a wrapper needs a trap that dash does not run on a signal death, and mktemp flavours differ; fd 3 swapping needs neither"
proposed_fix: |
  CAUSE: see b7e2d9 (the writer/reader/victim model, strace, 40 of 40 under a truncating process, 1 of 195 real gate scripts with no adversary). New today:
  an EMPTY `.dart_tool/native_assets.yaml` in a throwaway package with ZERO dependencies gives exit 254 and the signature for BOTH `dart bin/x.dart` and
  `dart run <abs path>` from another cwd, deterministically (the b7e2d9 runs used a package with `objective_c`), which is what the canary test pins.
  FIX. (1) `scripts/_dart_bin.sh`: `_dart_run_retrying` (a function; `DART_BIN` is set to its NAME so the 22 unchanged call sites run it; foreground,
  `( ... ) &`, pipelines and `$( )` all resolve it). `{ err=$("$REAL" "$@" 2>&1 1>&3 3>&-) || rc=$?; } 3>&1` passes the child's stdout and stdin straight
  through and captures only stderr and the exact status; on `254` plus the signature, at most 2 retries (the budget of test/helpers/spawn.dart), one note per
  retry starting with a newline (real `dart run` prints its preamble without one), a `sleep 1` between; otherwise the captured stderr is re-emitted and the
  status returned. Round 2 found and the body fixes: with stdout closed the group never runs and a bare idiom returned 0 WITHOUT running the child (a
  ran-flag falls back to a plain call); the per-iteration reset; `|| :` on every external and printf so nothing aborts a `set -e` hook. (2)
  `use_dart_race_retry`: kill switch `AVYA_DART_RUN_RETRY=0` (exactly `0`), idempotent, empty-safe. (3) Each hook adds ONE guarded line after its
  `DART_BIN=` assignment; the `type` guard makes a NEW hook copy on an OLD tree a no-op. (4) The pre-commit gate loop keeps each gate's output in a second
  temp dir and records its exit status; `_gate_diag || true` prints retry notes (every note of every gate, found by ONE `grep -l -a`, so a passing gate costs no
  fork), a failing gate's output (the first 8 failing gates only), its status and, for a status 129..192, the sentence that the gate was KILLED and could not be run
  (OI-117) — it still blocks — and for 254 its own sentence. The four sites that discard stderr (the tier extraction of pre-commit, prepare-commit-msg and pre-push, and
  commit-msg's quiet diagnose pre-check) retry silently by design (declared). `use_dart_race_retry` also checks that `_dart_run_retrying` exists (B-pass seat A, P2).
  STATED LIMITS: stderr is delivered when the child's stderr closes (not live, not a tty, lost on interrupt; a grandchild holding it delays the return; a caller
  that merges the streams gets stdout first and stderr last; NUL bytes are dropped);
  with stdin CLOSED bash hands a stdin-reading child the capture pipe (git never closes a hook's stdin); Windows and macOS are not measured (the function adds
  one fork per call; the kill switch gives the A/B); the harness hooks in .claude/settings.json and the dart launchers are OI-483.
regression_test_planned: |
  - test/scripts/dart_run_retry_test.dart: the function against a stub dart (call counts by marker file, argv byte for byte, stdin re-read, closed stdout and
    stderr, set -e / -u, a failing sleep, no tr on PATH, note shape and 300-char cut, the exact backoff log), `use_dart_race_retry` (enabled, `0`, `false`, `off`,
    empty, twice, recursion), the REAL SDK (control, canary, a real 254 retried to a real success with a real stdin payload, the kill-switch twin), and the
    wiring pins (one guarded line per hook right after the assignment, no `export DART_BIN`, the loop no longer discards).
  - test/scripts/hooks_dart_run_retry_e2e_test.dart: the five real hooks against a stub that loses the race once per script, each with a switch-off twin; the
    gate loop's diagnostics (attribution, head and tail of an 80-line output, exit status, killed vs 127/128/129, order, every note, empty temp dirs on both
    paths, an unreadable output that must not change the verdict); the D5 installed-copy matrix.
  - test/contracts/spawn_env_manifest_test.dart / scripts/regression_catalog_lib.dart: AVYA_DART_RUN_RETRY is stripped from test children by exact name;
    DART_BIN and DART_BIN_REAL are classified as the helper's own locals; the new e2e file joins the recursion-capable set.
  MUTATION PROOF (rule 21): the "Mutation proof" section below (90 mutants run on the FINAL code, 88 reddened, 2 named equivalent).
impact_analysis: |
  Platform tier (four of the five installed hooks and the helper they all source). No lib/ code, no Hive key, no cloud column, no Edge Function. A commit that
  used to fail on a lost race now passes after at most two more attempts with a note on stderr; a failing gate now explains itself. The kill switch
  restores today's call at all 22 sites. The installed hook COPIES are re-installed from the primary after the merge (a post-merge local step: the commit does
  not claim it); until then the old copies run the real dart exactly as today. Value semantics (4.1.5.3): swept `test/` and `scripts/` for pins on the
  gate-loop text (`>/dev/null 2>&1` on the gate line, `re-run for details`): none; stale prose was repointed.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "scripts/_dart_bin.sh and the five hook scripts; no lib/ change" }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "no client or server code is involved; the failing component is the Dart SDK's `dart run` start-up" }
  - { tier: 11, name: "External services", status: verified, evidence: "Dart SDK 3.11.1 (the Dart in CI's Flutter 3.41.4): an empty native_assets.yaml reproduces the exit 254 and the text through both forms; checked today in a scratch package and again by the canary test" }
---

# The `dart run` native-assets race at the git hooks, and a gate loop that said nothing (OI-482, OI-117)

## What was seen
Gates failed in the pre-commit loop with no explanation, a different gate each time, green alone; a lost race at the tier extraction silently dropped the
`Blast-radius:` line. The loop discarded every gate's output. A SIGKILLed gate looked like a violation.

## Cause (writers and readers by file:line)
See `proposed_fix`: the function and the hook lines are the writers; the 22 call sites and the gate loop are the readers. The mechanism is b7e2d9's.

## What was proven and what was not
- PROVEN (here): an empty yaml gives the real 254 + signature through both forms with a zero-dependency package; the function retries a REAL 254 to a REAL
  success with a real stdin payload (the shim heals the file after the first real failure); the kill switch brings the failure back; each of the five
  hooks passes where today's call fails (the switch-off twins) with the stub dart; the loop prints what a failing gate said.
- NOT proven: that the loop's historical failures were this race; that two retries are enough under load 10 (1 in 195 is the measured natural rate, so two in
  a row would be about 1 in 38000 if independent, but a descheduled writer is not independent: the 1 s backoff is the answer to that, unmeasured); Windows and
  macOS behaviour of the capture idiom (dash and bash on Linux only).

## Repeatable commands
- Canary: a package with `pubspec.yaml` (sdk bound), a hand-written `.dart_tool/package_config.json`, `bin/x.dart`, then `: > .dart_tool/native_assets.yaml`
  and `dart bin/x.dart` (rc 254, `File not formatted as yaml: .`). Remove the file and it runs.
- The function: `. scripts/_dart_bin.sh; DART_BIN=<stub>; use_dart_race_retry; "$DART_BIN" run scripts/x.dart`.
- The loop: run `sh scripts/pre-commit.sh` in a repo whose `scripts/check_*.dart` are stubs (test/scripts/hooks_dart_run_retry_e2e_test.dart builds one).

## Mutation proof (rule 21, self-attested)
Run on the final code (after the B-pass fixes) by a driver that applies one mutation at a time to the real file, confirms it APPLIED (the anchor text is counted before
the replace and the run aborts on a missing anchor; a no-op mutation asserts), runs `test/scripts/dart_run_retry_test.dart` and
`test/scripts/hooks_dart_run_retry_e2e_test.dart` (the baseline must be green first), treats a compile error as NOT a kill (none occurred), and restores the file byte for
byte (asserted after every mutant; no `.mutbak` left). Result: **88 of 90 reddened, 274 failing tests in total (a mutant reddens one to nineteen); the other two are named
equivalents, below; 0 compile errors.**

| Group | Mutants | Reddened | What they were (each is a way a real regression re-enters, not a delete-only set) |
|---|---|---|---|
| F: `_dart_run_retrying` | 29 | 28 | signature check dropped; 254 widened to any non-zero; the `run`-only check dropped (and `${1:-}` to `$1`); retry budget 0 / 3 / unbounded; `"$@"` unquoted in the capture; status lost; stderr never re-emitted / re-emitted only on failure; the per-iteration status reset and the per-iteration ran-flag reset removed (the second is the one a SAME-SHELL sequence test kills); the ran-flag fallback for a closed stdout removed; `|| :` removed from the capture group, the note printf, the backoff call, the note's `tr` and the final re-emit printf (each aborts a `set -e` hook if it fails; the capture-group and re-emit ones are killed by the closed-stdout and closed-stderr tests under `set -e`); the note's leading newline, its 300-character cut and its newline flattening; a backoff before the first attempt and after the last failure; `sleep 1` to `sleep 2` (killed by the logged-argument pin); the recursion guard; `DART_BIN_REAL` defaulting removed (killed by the `set -u` test with `DART_BIN_REAL` unset); the non-`run` path swallowing a status; `3>&-` dropped (the named equivalent F29) |
| U: `use_dart_race_retry` | 8 | 8 | kill switch inverted / ignored / accepting `false` and `off`; empty `DART_BIN` guard; idempotence guard; the real binary not remembered; `DART_BIN` not switched; the `type _dart_run_retrying` check dropped (a helper with the setter but without the function) |
| K: the five hook lines | 8 | 8 | the guarded line removed from each of the five hooks; `|| true` dropped (killed by the third installed-copy cell: an old helper plus `use_dart_race_retry() { return 1; }`); the `type` guard dropped in two hooks |
| L: the gate loop | 45 | 44 | output discarded again / stdout only; head 20 to 19, tail 30 to 29, head instead of tail, the 60-line limit to 20 / 61 / `-lt`, to 100, the omitted-lines count off by one; iterating over every output instead of the failure markers; notes only for failing gates, only for passing gates, one note only, notes anchored (killed by a gate that prints the token mid-line), the full phrase dropped from the note pattern (killed by a gate that prints the bare token), `-a` dropped from `grep -o` (killed by a gate whose output holds a NUL byte); diagnostics after the `GATE FAIL` lines; the temp output dir not removed; `_gate_diag` without `|| true`; status not recorded; the killed threshold `>= 128`, `> 129`, upper bound 192 to 255 and to 191; the 254 sentence dropped and widened to 255; the whole-output, head and tail `cut` removed and its cap 2000 to 2001; the unreadable-count fallback removed (killed by the unreadable-output gate); the line count by `wc -l` (killed by the 62-line gate with an unterminated last line) and by `grep -c` without `-a` (killed by a 100-line gate with a NUL byte, which GNU grep counts twice); the notes substitution without its inner `|| :` (killed by an unreadable output next to a retried passing gate: grep exits 2 and the whole list was discarded); the 8-gate cap at 7, 9, removed, its counter not incremented, and a capped gate losing its status line; a killed gate no longer blocking; the output dir sharing the marker dir; the signal number printed wrong; the `GATE FAIL` line dropped; `-a` dropped from `grep -l` (the named equivalent L10b) |

**Survivors found on the way and what was done (not hidden):** the first full run survived 5; three were killed by new tests (closed stdout and closed stderr under
`set -e`; `DART_BIN_REAL` unset under `set -u`; a note that follows other text on its line) and two were dead code, so the CODE changed, not the tests: the `_drr_err=` reset
at the top of the retry loop (the next line assigns it) and the numeric guard on the exit status in `_gate_diag` (the file is written only by an `echo` of a shell status).
The B-pass (four fresh readers, the fourth on the post-fix delta) then found, among others, that the e2e test pinned the omitted-lines count with a substring that a wrong constant also
satisfied (`30 lines omitted` appears in two blocks: the assertion is now per block), that the 60-line boundary and the 8-gate cap were unpinned, and that a NUL byte in a gate
output hid its note; each now has a gate in the e2e stub and a mutant above that it kills.

**Named equivalents (each run once, GREEN):** (F29) dropping `3>&-` from the capture (the child merely inherits a duplicate of fd 3: nothing observes it); (L10b) dropping `-a`
from `grep -l`, which only lists file names: GNU grep 3.11 lists a binary file with plain `-l` (checked with `/usr/bin/grep`), so the flag is defensive for other greps and
cannot be observed here, while `-a` on `grep -o` is needed (L10c reddens). Not mutated and stated: the duration of `sleep 1` is pinned only through the logged argument of the
stub (a real sleep is never run in the suite); the unreadable-output assertions need a non-root user (the test says so and skips itself otherwise).
