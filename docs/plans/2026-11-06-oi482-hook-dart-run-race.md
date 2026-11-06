# OI-482 plan (v4): the five git hooks' `dart run` sites contain the native-assets race, and the parallel gate loop stops discarding its output

Tier: **platform** blast radius (four of the five installed hooks, `scripts/_dart_bin.sh`); the full pipeline of an L unit (own plan, two review rounds, plan-review
record, B-pass). Execution mode: INLINE (one worktree, `oi482-hook-dart-run-race`). Founder go: the OI-468 plan (D7) filed this as "starts next"; "Oi 468 now." plus the
standing "why are you waiting for me every time?".

History. v1 -> round 1 (two fresh Sonnet readers; 5 P1 each) -> v2 (the retry became a shell FUNCTION in `scripts/_dart_bin.sh`: round 1 showed an executable
wrapper file needs mode 100755 that no script here has, a blast-radius entry, a symlink/`dirname`/`exec` story and an untested Windows exec) -> round 2 (two fresh
Sonnet readers; lens A found 1 P1 and lens B 6 P1, none changes the design: a closed-stdout fail-open in the capture idiom, env-scan plumbing, the canary's spawn shape and
recipe, a fail-safe diagnostic block, mutants that survive, board consistency) -> v3 (every round-2 item folded) -> round 3 (one narrow Sonnet reader; no P0, 3 P1: the killed-gate range mislabelled Dart's own statuses 254/255, a fourth silent site, mutants the scenarios could not kill; plus P2s) -> **v4 (this), every round-3 item folded**; the design did not change in rounds 2 or 3.

## Done-when (OI-482, amended on the board in the same commit; deviations declared and why)

The five git hooks' 22 `"$DART_BIN" run` sites retry the native-assets race and no longer lose it silently; the pre-commit gate loop prints a failing gate's output (and a
distinct line for a gate that was KILLED, OI-117) instead of discarding it; a behavioural test proves the retry with the REAL SDK; the kill switch is stated; the installed hook
COPIES are re-installed from the primary on a tree equal to `origin/main` AFTER the merge (a post-merge local step: the batch commit does not claim it). Deviations from the OI text:
(1) **scope**: the harness hooks in `.claude/settings.json` and the dart launchers moved to **OI-483** (shape-fit, D6); (2) the OI said "re-runs once": this plan retries at most
**twice**, the test helper's budget (OI-468), because a writer descheduled inside its window can fail two attempts in a row; (3) the OI asked for a test "against a truncating
process": that is a timing test, so the proof is a deterministic real-SDK one (an EMPTY `native_assets.yaml` gives the real 254, D7.2) plus a heal-after-failure shim; (4) at the FOUR
sites that discard stderr (`prepare-commit-msg.sh:55`, `pre-commit.sh:456`, `pre-push.sh:226` with `2>/dev/null`, and `commit-msg.sh:108`, the quiet pre-check of `validate_diagnose_doc.dart`, with `>/dev/null 2>&1`, followed by a visible re-run at :110) the retry works and is SILENT: the note goes to the
discarded stderr. NOT established, stated as a residue row: that the loop's own historical failures (quirks item 5) were this race (D3's visible output is what will tell).

## Ground truth (measured or read; rounds 1 and 2 re-verified items 2-5)

1. **Mechanism** (diagnose `docs/diagnoses/2026-11-06-spawn-status-native-assets-race-b7e2d9.md`): `dart run` rewrites `<cwd package>/.dart_tool/native_assets.yaml` in place (empty
   ~0.3 ms) and every dart child reads `<script's package>/.dart_tool/native_assets.yaml` 245-390 ms after it starts; a reader inside a writer's window exits **254**, stderr
   `File not formatted as yaml: .`, BEFORE `main`. **Measured 2026-11-06 (scratch, SDK 3.11.1): an EMPTY `.dart_tool/native_assets.yaml` in a throwaway package with ZERO
   dependencies (`dart pub get --offline`; the test recipe uses a hand-written package_config.json instead, and the canary test is what proves THAT form) gives exit 254 and that stderr for `dart bin/x.dart` AND for `dart run <abs path>` from another cwd** (the diagnose's runs used a package
   with `objective_c`; the zero-dependency claim is new and is re-proven by the canary).
2. **Hook sites**: 22 `"$DART_BIN" run` lines: `pre-commit.sh` 13 (192, 220, 236, 246, 270, 280, 298, 315, 326, 392, 432, 441, 456), `commit-msg.sh` 3 (74, 108, 110),
   `pre-merge-commit.sh` 3 (182, 195, 227), `pre-push.sh` 2 (135, 226), `prepare-commit-msg.sh` 1 (55). No repo code exports `DART_BIN` or reads it from the environment; every
   use is `"$DART_BIN" run`; no `exec`/`env`/`xargs`/`timeout`/`nohup`/`command`/`sh -c`/`eval` on it; no hook uses fd 3. Each hook sources `scripts/_dart_bin.sh` behind
   `[ -r ] && sh -n` and assigns `DART_BIN="$(resolve_dart_bin)" 2>/dev/null || DART_BIN="dart"` inside the `then` branch; four are `#!/bin/sh` + `set -e`, `prepare-commit-msg.sh`
   is `#!/usr/bin/env bash` + `set -e`. Other sourcers of the helper (`land_pr.sh`, `sync_with_main.sh`, `safe_merge.sh` use `set -u`; `safe_pr_merge.sh` uses `set -e`) never call the new
   functions. A real SIGKILLed `dart run` returns 137 (measured 2026-11-06, both the launcher pid and the VM child).
3. **The loop discards everything**: `pre-commit.sh:392` `"$DART_BIN" run "$GATE" >/dev/null 2>&1`, 4 jobs, cwd the repo root; a failing gate prints only its name. A SIGKILLed gate
   prints the same line (OI-117, observed 2026-08-13).
4. **Installed hooks are COPIES** (read-only, dated 2026-10-25, sizes equal the sources) that source the WORKING TREE's helper.
5. **Pins**: the call-form pins (`gate_scripts_wired_lib.dart:invokesGate`, `blast_radius_stdin_usage_lib.dart`, `dart_bin_resolver_test.dart` checks 1-4 (incl. "no non-comment, non-`echo` line
   matches `dart\s+run\b`" at :293-306), `contract_sweep_wired_test.dart:34`, `gate_scripts_wired_runners_test.dart`) all match `"$DART_BIN" run ...`; with the 22 sites unchanged none
   moves. `pre_commit_gate_loop_parallel_test.dart` pins the glob, the `case` allowlist, `PRE_COMMIT_GATE_JOBS`, `wait || true`, `GATE_FAILDIR`, `GATE_FAIL=1`, "One or more gates failed":
   kept. Nothing pins `>/dev/null 2>&1` on the gate line or the text `re-run for details` (re-checked when D3 is written).
6. **Prototype and reviewer experiments** (dash 0.5.12, bash, bash --posix): `{ err=$("$REAL" "$@" 2>&1 1>&3 3>&-) || rc=$?; } 3>&1` passes child stdout straight to the original stdout,
   captures only stderr and the exact status (0, 1, 3, 254, 255, 130, 143), stdin survives (pipe, file, /dev/null, 300 KB), 200 KB+200 KB output does not deadlock, invalid UTF-8
   is preserved; a function NAME held in `DART_BIN` resolves in the foreground, in `( ... ) &`, in pipelines, in `$( )`, in `if !`, with `|| RC=$?`, under `set -e`. Found by round 2
   and fixed in the body below: with stdout CLOSED (`>&-`) the group does not run and a bare idiom returns 0 without running the child.
7. **No nested forwarder at the hook sites**: the scripts the hooks run that `exit` with a child's status are `check_onconflict_live_arbiter.dart:277` and
   `check_two_user_cross_account.dart:39`; both are on the loop's case-skip list.

## Design

**D1. `_dart_run_retrying`, a function in `scripts/_dart_bin.sh`; the 22 call sites do not change.** `DART_BIN` is set to the function's NAME, so `"$DART_BIN" run x` runs it. The
reference body (round 2 lens A, hardened and re-run under dash, bash and bash --posix, with and without `set -e`, incl. closed stdout, closed stderr and no `tr`/`sleep` on PATH):
```sh
_dart_race_backoff() { sleep 1; }
_dart_run_retrying() {
  _drr_real="${DART_BIN_REAL:-dart}"
  [ "$_drr_real" = _dart_run_retrying ] && _drr_real=dart        # never recurse
  if [ "${1:-}" != "run" ]; then "$_drr_real" "$@"; return $?; fi
  _drr_n=0
  while :; do
    _drr_ran=0; _drr_rc=0; _drr_err=                              # reset EVERY iteration
    { _drr_ran=1; _drr_err=$("$_drr_real" "$@" 2>&1 1>&3 3>&-) || _drr_rc=$?; } 3>&1 || :
    if [ "$_drr_ran" != 1 ]; then "$_drr_real" "$@"; return $?; fi   # stdout closed: the group never ran; run plainly
    if [ "$_drr_rc" = 254 ] && [ "$_drr_n" -lt 2 ]; then
      case "$_drr_err" in
        *"File not formatted as yaml"*)
          _drr_n=$((_drr_n + 1))
          _drr_note=$(printf '%.300s' "$_drr_err" | tr '\n' ' ') || _drr_note=
          printf '\n[dart-run-retry] native-assets race: retry %s of 2 | %s | exit=254 | stderr=%s\n' "$_drr_n" "$*" "$_drr_note" >&2 || :
          _dart_race_backoff || :
          continue ;;
      esac
    fi
    if [ -n "$_drr_err" ]; then printf '%s\n' "$_drr_err" >&2 || :; fi
    return "$_drr_rc"
  done
}
```
`${1:-}`/`${DART_BIN_REAL:-}` everywhere (callers source the helper under `set -u`); `_drr_` prefix, no `local`. The note starts with a NEWLINE because real `dart run` prints
`Running build hooks...` without one. The budget (2), the signature and `sleep 1` are the values of `test/helpers/spawn.dart`. New functions are APPENDED at the end of `_dart_bin.sh`
and header edits are line-neutral (`test/helpers/spawn.dart:71` and `spawn_env_manifest_test.dart:70` cite `_dart_bin.sh:85`), or those citations are repointed.
**Stated limits (round 2):** stderr is delivered when the child's stderr closes (not live; `contract_sweep.dart` already buffers via `Process.runSync`); a grandchild that outlives the
child and holds stderr open delays the return (no detached spawner exists in `scripts/`); the child's stderr is no longer a tty (colour, `\r` progress); lost if the hook is interrupted;
under bash with stdin CLOSED a stdin-reading child HANGS on the capture pipe it is given as fd 0 (git runs pre-commit, commit-msg, prepare-commit-msg and pre-merge-commit with /dev/null and pre-push with a pipe; Git Bash's `/bin/sh` is bash); with stdout CLOSED the child runs once, plainly, WITHOUT a retry, and the shell prints `Bad file descriptor` once per call; dash prefixes `Terminated` to a
captured SIGTERM message; bash warns on NUL bytes in stderr.

**D2. `use_dart_race_retry` turns it on.** `[ "${AVYA_DART_RUN_RETRY:-1}" = 0 ]` -> return 0; `DART_BIN` empty or already `_dart_run_retrying` -> return 0; else
`DART_BIN_REAL="$DART_BIN"; DART_BIN=_dart_run_retrying`. Each of the five hooks adds ONE line right after its `DART_BIN="$(resolve_dart_bin)" ...` line, inside the `then` branch:
`type use_dart_race_retry >/dev/null 2>&1 && use_dart_race_retry || true` (the `type` guard makes a NEW hook copy on an OLD tree a no-op). Only the exact value `0` disables
(`false`/`off`/empty leave it on); tested. `resolve_dart_bin` is unchanged.

**D3. The parallel gate loop keeps its output and reports a killed gate.** Each backgrounded gate becomes (the subshell inherits `set -e`):
```sh
( rc=0; "$DART_BIN" run "$GATE" >"$GATE_OUTDIR/$GATE_NAME" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then echo "$GATE_NAME" > "$GATE_FAILDIR/$GATE_NAME"; echo "$rc" > "$GATE_OUTDIR/$GATE_NAME.rc"; fi ) &
```
(`GATE_OUTDIR` is a second `mktemp -d`, never the marker dir: the aggregator globs `$GATE_FAILDIR/*`.) After `wait`, ONE function `_gate_diag`, always called as `_gate_diag || true` so it
can never change `GATE_FAIL` or the exit status, prints: for every gate whose output holds a retry note, `[pre-commit] NOTE: <gate> needed a native-assets retry: <note>` (the note is
extracted UNANCHORED, `grep -o '\[dart-run-retry\].*'`, ALL notes of the file, because it can follow the preamble on the same line); for every failed gate, a header, the whole output when
it has at most 60 lines, else its first 20 and last 30 lines, and, from the recorded status, `exit <rc>`; for `rc` from 129 to 192 (death by signal 1..64; 137 = SIGKILL, measured on a real `dart run`) the extra sentence `killed by signal <rc-128> (memory
pressure?): the gate could NOT BE RUN; re-run it alone before suspecting the repo`, and for `rc` 254 (the Dart front end could not load the gate, or the race outlived 2 retries) a sentence naming both causes (OI-117; 127, 128, 193 and 255 get neither: 255 is Dart's uncaught-exception status; a killed gate STILL blocks: a gate that could not run is not a pass; the OI's "only the second
should block" is not adopted and that is stated in the archive). The existing `GATE FAIL: <name> — re-run for details: dart run scripts/<name>` line and the `GATE_FAIL=1` accounting stay
exactly where they are and AFTER the diagnostics. Both temp dirs are removed on the pass and the fail path. Lines that mention "dart run" are printed with `echo` (the resolver test flags a
`printf` line). The literal `scripts/check_*.dart` glob, the `case ... esac`, `GATE_FAILDIR`, `wait || true`, `PRE_COMMIT_GATE_JOBS` are untouched. The output retention has no switch (a
diagnostic; the kill switch restores the CALL): stated. Display: a gate output without a trailing newline gets one before the next header; every printed line is cut at 2000 characters. Disk: the outputs of the ~99 loop gates (111 `check_*.dart` minus 12 case-skipped), previously discarded, sit in `$TMPDIR` until the loop ends.

**D4. Kill switch / rollback.** `AVYA_DART_RUN_RETRY=0`, per command, no reinstall: `use_dart_race_retry` leaves `DART_BIN` alone and the 22 sites run `"$REAL" run ...` exactly as today
(this is the platform tier's "feature flag", named). Permanent rollback = revert the commit. **Plumbing, complete (round 2):** `AVYA_DART_RUN_RETRY` is added by EXACT name to
`childEnvStrippedNames` (`scripts/regression_catalog_lib.dart`, no repo-owned prefix: other `AVYA_*` names are NOT auto-stripped and the naming doc says so) and to `_stripped` in
`test/contracts/spawn_env_manifest_test.dart`; the shell env-scan (`test/helpers/spawn_env_scan.dart:_scanShell`) reports `DART_BIN` and `DART_BIN_REAL` as env reads of the helper
(default-idiom and read-before-assign), so BOTH join `_localShell` in `spawn_env_manifest_test.dart` (classified exactly as the scan reports: the reverse direction fails on a stale
entry); the D2 recursion pin there (`capable.toSet()` equals exactly three files) is extended for any new test file whose source contains `sh|bash scripts/pre-push.sh`, and such a
scenario sets `CONTRACT_SWEEP_SKIP=1` with `allowControl` (pattern `pre_push_branch_push_skip_e2e_test.dart`); scenarios that set `AVYA_DART_RUN_RETRY` declare it in `allowControl`;
`DART_BIN_OVERRIDE` is stripped from test children by default (`spawn.dart:80`) and is set inside each driver script or passed via `extraEnv`. Run `spawn_env_manifest_test.dart` and
`spawn_sites_guard_test.dart` right after the FIRST edit (bug class 2.99). `docs/naming_conventions.md`: control-variable row, the glossary terms `_dart_run_retrying` /
`use_dart_race_retry` / the `[dart-run-retry]` token (NOT the test helper's `[spawn-retry]`).

**D5. Installed-copy matrix (tested; no fixture claimed that does not exist).** old hook copy + new tree: a frozen copy of the CURRENT `pre-merge-commit.sh`
(`test/scripts/fixtures/pre_oi482_hooks/pre-merge-commit.sh.txt`, from `origin/main`) runs against the new helper and behaves as today. new hook + old tree: a frozen copy of the CURRENT
`_dart_bin.sh` (no functions) is the tree's helper and the new hook behaves as today; a THIRD cell appends a `use_dart_race_retry` that returns 1 to that helper: the hook must survive it (this is what the `|| true` on the hook line is for; without a failing function the `|| true` is EQUIVALENT because errexit is already suppressed in an AND list). (`pre_a2_hooks/` is not used: pre-A2, 2 of 5 hooks, "do not update".)

**D6. Scope split, reason = shape-fit, not review churn (CLAUDE.md 4.12.1; OI-483 is the tracker).** The harness hooks (`.claude/settings.json`, 9 commands; exit 2 BLOCKS the tool call, so a
broken edit is worse than the race; bare `dart`) and the launchers (`land_pr.sh:65`, `sync_with_main.sh:56` BACKGROUND the child and forward TERM/INT/HUP to its PID; `safe_pr_merge.sh:44,46`
`exec`s it; `safe_merge.sh:286,308` resolves `_PRE_DART` and uses the plain form) and the Dart scripts that spawn dart in the plain form (`batch_close_hook.dart:159`, `land_pr.dart:521`,
`sync_with_main.dart:665`, readers) have shapes the function does not fit as is. OI-483 carries them (text corrected). Ledger: those are `upstream_blocked` rows (blocker: needs this
function on `main` and a design for the non-blocking/exec/background shapes; reopen_when: this batch merged) and OI-483 is their tracker. CI `test.yml`: 6 live `dart run` lines (154, 331, 373,
401, 408, 446), sequential (373 is a `for` loop), no `&`/`xargs -P`/`nohup`: `verified_clean`. The nested-forwarder caveat is `verified_clean` (ground truth 7).

**D7. Tests** (behavioural, then mutated per CLAUDE.md 4.4 rule 21). Two new files, each with a file-level `@Timeout` and `library;`: `test/scripts/dart_run_retry_test.dart` (function table +
real SDK + D5 + pins) and `test/scripts/hooks_dart_run_retry_e2e_test.dart` (the hooks). Every spawned `dart` child goes through an `sh -c` wrapper or the function, NEVER straight through
`runSpawn(dart, ...)` (OI-468's helper would retry the canary itself and print bogus `[spawn-retry]` lines); `dartBin()` supplies the absolute dart (the `flutter_tester` trap); cwd is a throwaway
dir, never the repo root. A logging `sleep` stub is first on PATH in the function table and in the hook runs (it also neutralises the 1 s sleep inside a REAL hook run).
1. **Function table, stub dart** (preamble WITHOUT a trailing newline; first failing call does NOT read stdin): {254+signature then ok; always-failing = 3 attempts, 254 back, child's stderr last;
   254 without the text; the text with exit 1; the text on STDOUT only (no retry); exit 3; `--version` and `pub get` with a 254+signature stub (one call); argv with spaces, `*` and an
   empty argument survive a retry; stdin re-read by the retry; stdout passthrough; success WITH stderr text is re-emitted; stub stderr multi-line and over 300 characters (flattened and cut note,
   leading newline); stdout CLOSED (`>&-`) still runs the child (marker file) and returns its status; closed stderr under `set -e` survives; call counts by marker file; the backoff log has
   exactly N-1 lines of `1`; `DART_BIN` already the function; `DART_BIN_REAL` equal to the function name does not recurse; `DART_BIN_REAL` UNSET under `set -u`; a same-shell SEQUENCE (a normal call, then a call with stdout closed, then two lost races each getting its own budget of 2); closed stdout and closed stderr UNDER `set -e` (the capture group and the final re-emit must not abort); a failing `sleep`; no `tr` on PATH}. Named: the single "per-iteration reset removed" mutant is killed through the `rc` reset only; the `err` reset was dead code and is deleted.
2. **Real SDK.** Recipe: a throwaway package = `pubspec.yaml` with an SDK lower bound (`dart run` fails without one), a hand-written `.dart_tool/package_config.json` (no pub), `bin/x.dart`.
   (a) CONTROL: absent yaml -> exit 0 (so a red cannot be a different failure); (b) CANARY: an EMPTY `.dart_tool/native_assets.yaml` -> the real exit 254 + the real signature through
   `dart bin/x.dart` and through `dart run <abs path>`; a pin that the signature in `_dart_bin.sh` equals `nativeAssetsRaceSignature` (`test/helpers/spawn.dart`), and a comment naming both
   constants to update on a Flutter bump (the canary going red on a bump is intended); (c) the function around a SHIM that runs the real dart and, on a 254, DELETES the yaml (a
   "filled" file of unknown content could itself fail attempt 2): attempt 1 real 254, retry, attempt 2 real success; (d) the same with a stdin payload read by a real Dart script.
   If the zero-dependency claim fails in CI, the fallback fixture needs `objective_c`, offline-safe only because the job's `flutter pub get` cached it (stated, not assumed).
3. `use_dart_race_retry`: {enabled, `0`, `false`, empty `DART_BIN`, already wrapped, twice}.
4. **The five hooks, run for real** (`sh scripts/x.sh`; `bash` for `prepare-commit-msg.sh`), `_dart_bin.sh` an explicit closure entry, `DART_BIN_OVERRIDE` set via `extraEnv`, the stub dart failing the
   FIRST call of every script with the signature: `pre-merge-commit` (extend `pre_merge_commit_e2e_test.dart`'s builder), `commit-msg` and `prepare-commit-msg` (no builder exists: two new ones;
   the `Blast-radius:` line survives a lost race), `pre-push` (copies only the hook today: add the helper; the tier pipeline, stdin through a retry; the D2 scenario above), `pre-commit` (the PATH-stub
   builder in `pre_commit_index_add_e2e_test.dart`, which deliberately omits `_dart_bin.sh`: the new case copies it) with stub gates. Each hook has a **switch-off twin** (`AVYA_DART_RUN_RETRY=0`:
   the same first-call failure now fails the hook, exactly as today's call) which is also the "where today's call fails" baseline. Loop assertions: a retried-but-passing gate prints its note; a
   retried-then-failed gate prints its note too; two failing gates with distinct text are attributed correctly; a failing output of >60 lines shows its first and last lines; an exit-137 stub prints
   the killed-gate sentence and still blocks; `GATE FAIL` comes after the output block; `TMPDIR` pointed at a fixture dir is EMPTY afterwards on the pass and the fail path; a `_gate_diag` that
   exits non-zero (mutant) or a missing file never changes the verdict.
5. D5's two cells. Pins: each hook has the guarded call exactly once, after its `DART_BIN=` assignment; no `export DART_BIN`; no `printf` line mentioning "dart run" in the loop; the loop's gate
   line no longer discards; the FOUR silent sites (D8 deviation 4) are listed in the test as silent-by-design, a closed inventory.
6. **Mutants** (harness baseline-first, anchors confirmed, a syntax or compile error is NOT a kill): signature dropped; 254 widened; `run` check dropped; cap 0/3/unbounded; `"$@"` unquoted; status
   lost; err not re-emitted; err re-emitted on failure only; per-iteration reset removed; ran-flag fallback removed; `|| :` removed from each printf/tr/backoff; note newline dropped; `type` guard
   removed; the hook line removed (x5); `|| true` removed from the hook line; kill switch inverted; idempotence guard removed; recursion guard removed; backoff before the first attempt or after the
   last failure; loop: output still discarded, tail instead of head, wrong attribution, notes only for passing gates, one note instead of all, `GATE FAIL` before the block, temp dir not removed,
   `_gate_diag` without `|| true`, rc not recorded. Named EQUIVALENT: dropping `3>&-` (the child inheriting fd 3 shows no difference); `|| true` on the hook line (see D5; killed by the third D5 cell); `sleep 1`'s duration is covered only by the logged-argument
   pin.

**D8. Process and closure.** Plan review: 3 rounds done (`review_rounds: 3`; this is v4); the full local gate loop; a B-pass (`/code-review`; installed-copy and moved-prose lenses named); plan-review record
`docs/plan-reviews/oi482-hook-dart-run-race.md` (`review_rounds: 3`, `bpass: accepted` with a bare `verdict: accepted` line in the cited review file); Gate 40 ledger `docs/audit/oi482-hook-dart-run-race.closure.yaml`: `closed_in_commit` for the
22 sites, the loop retention and killed-gate line (OI-117), the kill switch and the tests; `upstream_blocked` for the OI-483 rows; `verified_clean` for CI and the nested forwarder; and a
REAL residue row `upstream_blocked` for "the loop's historical failures were this race" (blocker: never captured with output; reopen_when: a gate fails in the loop with retained output lacking
the signature, or a `[dart-run-retry]` note is followed by a failure). A FULL diagnose doc (recurrence of class 2.147; `closes-diagnose:` trailer for the `fix(...)` subject), a bug-class
note, `docs/architecture/hooks.md`. Commit trailers `closes-oi: OI-482` and `closes-oi: OI-117` (as real trailers only; never quote the phrase in prose); the OI-482 Done-when on the board is amended in the same
commit; OI-483's "Blocked on" reads "OI-482 merged to main (reuses `_dart_run_retrying`)"; archive by APPENDING to `closed_issues.md` (check diff-stat deletions); rebuild the local indexes
before `--record` of the context budget. Stale prose repointed in the same commit: `scripts/check_context_artifact_budget.dart:21-26`, `scripts/check_gate_scripts_wired.dart:83`,
`scripts/check_code_review_pass_exists.dart:19-20`, `docs/architecture/hooks.md:314` and `:689`, `.claude/skills/code-review/SKILL.md:17`, `docs/architecture/hooks.md:138` ("the full 75-gate loop"), `docs/playbook/common-pitfalls.md:183`,
`.claude/skills/debugging/bug-classes.md:2059-2067`, `scripts/pre-commit.sh:49` header counts ("75 times inside" becomes "once per gate"), `scripts/batch_process_telemetry.dart:104` (cites a writer line number: cite the symbol), the `_dart_bin.sh` header and its
guard message at line 72 ("only defines resolve_dart_bin()"; the guard test pins only `must be SOURCED` and `resolve_dart_bin`). "A PASS prints nothing locally" stays true. The loop-failures residue has no board OI: its tracker is item 5 of `reference_vps_quirks.md`, which carries the reopen trigger. OI-117 is closed with its deviation visible ON OI-117 (its fix-shape line is amended in the same commit) and in the ledger `notes:`. The Done-when no longer contains the reinstall; the ledger has an `upstream_blocked` row for it (needs the merge; the installer refuses a tree behind origin/main). After the merge (not claimed by
the commit): `git fetch origin main && git merge --ff-only origin/main` in the primary, `sh scripts/setup-hooks.sh`, record it in the retrospective and in `reference_vps_quirks.md` item 5; then retire the
worktree. New tests and docs must not quote a piped call of the tier classifier without its trailing bare dash argument (gate `check_blast_radius_stdin_usage.dart` reads prose too; this plan's own first draft tripped it). Stated limits: Windows (Git Bash forks
are slow; the function adds one fork per call; measurable with the kill switch) and macOS are not measured here; the founder's clone gets a check item.
