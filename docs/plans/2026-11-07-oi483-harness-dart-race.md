# OI-483 plan (v4): the harness hooks, the four dart launchers and the Dart spawns contain the native-assets race

Tier: **platform** blast radius (`dart run scripts/blast_radius_from_diff.dart` on the touched paths prints `Blast-radius: platform`); the full pipeline of an L unit
(own plan, two or more review rounds, plan-review record, B-pass). Execution mode: INLINE (one worktree, `oi483-harness-dart-race`). No subagent implements; subagents only review.
Founder go: "B" on 2026-11-07 (all sites stay in OI-483, no split; the alternative of filing the launchers and the Dart spawns as a new OI was declined).

History. v1 -> round 1 (two fresh Sonnet readers: mechanism lens no P0, 1 P1; tests-and-pins lens 4 P1) -> v2 -> round 2 (two fresh Sonnet readers: mechanism lens no P0, 1 P1; tests lens 2 P1, no design change) -> v3 -> round 3 (one narrow Sonnet reader on the v3 delta; no P0, 1 P1 and 4 P2, all mechanical test-spec items, the design ran clean: `mechanical_only`) -> **v4 (this)**; the design did not change in rounds 2 or 3 beyond the `git_safety_hook` exemption. Round 2 folded: `git_safety_hook.dart:217` left untouched (a new import would add a file whose compile error removes the guard, for an advisory note; D5); the dash `exec` claim corrected (D1); the pid cleared on every path (D4); D7.1's SAFETY rule specified; D7.7 reuses `land_pr_replay_test.dart`. Round 1 folded: the site list grew from 3 to 8 Dart spawns (the v1 sweep regex was single-line; D5), `sh -n` replaced by a probe subshell (D1), the stale pid cleared (D4), the import closures and the fixtures of D7.7. Rejected, with evidence: "the citation `_dart_bin.sh:85` is stale" (line 85 IS the `DART_BIN_OVERRIDE` read it cites; `resolve_dart_bin` at 82 was never the target); "leave `safe_pr_merge.sh` alone" (the founder chose all sites, the reviewer found no double-merge path, the kill switch keeps the literal `exec`; the SIGKILL residue is stated and pinned, D4).

## Done-when (the OI-483 text; deviations declared)

Every site runs through the retry (or has a stated reason it cannot, with a test of that reason); the harness commands are covered by a test that executes each command string; the
kill switch `AVYA_DART_RUN_RETRY=0` restores today's call at each site; the launchers keep their signal behaviour (a test sends TERM to the launcher and shows the child dies).

**One site takes the "stated reason" exit: `git_safety_hook.dart:217` (D5).** The design notes planned one for `land_pr.dart:521` ("no .dart_tool in the scratch clone"): that claim is FALSE, ground truth 2.
Deviations: (1) at the launchers the retry cannot read the signature (stderr stays live), so it keys on the bare status 254 (D4, with the proof that 254 means `main` never ran);
(2) `sync_with_main.sh` gains the trap-before-start and the bash re-wait that `land_pr.sh` already had (a side effect of sharing one function, D4; not a separate fix); (3) **five spawns the OI did not list join it** (ground truth 3): same class, same one-line wrap, and three of them are the likeliest victims of all; (4) the OI asked for `sh -n`: a probe subshell replaces it, because it is strictly stronger (ground truth 10).

## Ground truth (measured 2026-11-07 on this worktree at c18a606f, SDK 3.11.1, dash and bash; scripts in the session scratchpad)

1. **The race, per form.** An EMPTY `.dart_tool/native_assets.yaml` gives exit 254 and `File not formatted as yaml: .` for `dart bin/x.dart`, for `dart run <abs path>` from another
   cwd, and for `dart run --verbosity=error` from both cwds, i.e. the harness form carries the same signature. The control (no yaml) exits 0 and prints `MAIN RAN`; the failing forms print no `MAIN RAN`.
2. **Dart walks UP to find the package.** A script in `P/.git/land_pr_replay_x/scripts/x.dart`, with NO `.dart_tool` of its own, exits 254 when `P/.dart_tool/native_assets.yaml` is empty (also with a
   `pubspec.yaml` beside it, also by absolute path); it exits 0 when the parent's yaml is removed. `land_pr.dart:472` builds the replay clone at `<git common dir>/<replayDirName>`, so its gate reads the
   PRIMARY's `.dart_tool/native_assets.yaml`, which every `dart run` from the primary rewrites. **`land_pr.dart:521` is a victim**, and the OI's "readers" label stands for all three Dart spawns.
3. **Sweep of every site** (a MULTI-LINE scan of `scripts/*.dart` for `Process.run|runSync|start(` whose executable is `'dart'` or `Platform.resolvedExecutable`, plus `_run(Platform.resolvedExecutable`; a case-insensitive scan of every tracked shell file): the OI's list PLUS FIVE. Harness
   `.claude/settings.json` lines 12, 20, 28, 38, 49, 58, 67, 77, 87; launchers `land_pr.sh:65`, `sync_with_main.sh:56`, `safe_pr_merge.sh:44,46`, `safe_merge.sh:286,308`; Dart from the OI `batch_close_hook.dart:158`, `land_pr.dart:520`,
   `sync_with_main.dart:665`; Dart NOT in the OI `git_safety_hook.dart:217` (`runSync`, the advisory plan-review precheck, inside the PreToolUse hook), `check_adr_index_fresh.dart:26`, `check_gate_index_fresh.dart:34`, `check_incident_index_fresh.dart:17` (each `Process.run('dart', ['run', ...], runInShell: true)`, each in the parallel pre-commit loop, each turning ANY non-zero into `FAIL: builder errored` and exit 1, so a lost race there blocks a commit and the OI-482 hook retry cannot see it: that retry keys on 254 and the gate exits 1), and `check_two_user_cross_account.dart:27` (case-skipped in pre-commit and CI, manual; forwards the child's status). `land_pr.dart:462` runs the `--record-gate` TEST SEAM, not dart; `cqrs_query_naming_lib.dart:10` is a comment. `sh`-spawned children (`land_pr.dart:324,354,574`, `sync_with_main.dart:343`) are wrappers already in scope or `safe_commit.sh`/`safe_push.sh`, which run no dart. CI `test.yml` is sequential (`verified_clean` in the OI-482 ledger).
4. **Harness command prototype, run for real** (11 scenarios x dash and bash, throwaway repo, stub dart): ok; a lost race (2 calls, exit 0, one note); three lost races (3 calls, exit 254); exit 2 + stderr message
   (1 call, exit 2, message kept); kill switch (1 call, 254); helper SYNTAX-BROKEN (today's call, exit 0, and exit 2 still blocks); helper ABSENT; helper is a DIRECTORY; helper OLDER than OI-482 (no function, today's
   call); setter returning 1. The real `git_safety_hook.dart` with the real SDK through this command string blocks a raw commit: exit 2 with its message. Added cost: 3.3 ms per run (100 runs of the prefix: 0.327 s).
5. **Launcher prototype, run for real** (11 scenarios x 3 launchers x dash and bash = 66 runs): status passthrough; race healed; race twice then a real status; race always (3 calls); kill switch (1 call); TERM during the
   backoff (no further attempt, 254 reported); TERM during attempt 1 and attempt 2 (child dead, no orphan); INT and HUP (forwarded as TERM, no orphan); TERM with a child that exits 3 (the REAL status comes back, also
   under bash, also on `sync_with_main.sh`).
6. **No CLI's `main` can exit 254.** `land_pr.dart:97` `exit(r.code)` where `LandResult.code` is 0..7; `sync_with_main.dart:119` `exit(code)` with 0..4; `safe_pr_merge.dart:180` `exit(_run(args))` where `_run` returns 0, 1, 2. So a
   254 from the plain form means the front end failed BEFORE `main` (the race or a compile error): re-running repeats no side effect. An uncaught exception is 255, not 254.
7. **The three launcher CLIs read no stdin** (`grep -n stdin`: only `p.stdin.close()` on their own children), so a background job's `/dev/null` stdin is safe at `safe_pr_merge.dart`, the one site that is not already backgrounded.
8. **After the wrapper, `land_pr.dart:574-577` asks GitHub** (`_prMerged()`, then `mergeOutcome(status, merged)`), so a changed exit status from `safe_pr_merge.sh` under a signal (143 instead of death-by-signal) does not change a verdict.
9. **Pins**: `claude_hooks_cwd_independent_test.dart` (621 lines) pins the exact template (C2) and a SAFETY rule that refuses to execute anything else; `land_pr_source_pins_test.dart:27,33-41` and
   `sync_with_main_source_pins_test.dart:94-96,106` pin wrapper text; `land_pr_wrapper_e2e_test.dart:109` and `sync_with_main_wrapper_e2e_test.dart:103` write a fake `_dart_bin.sh` with only `resolve_dart_bin`;
   `safe_pr_merge_e2e_test.dart:220` deliberately copies no helper. `dart_run_retry_test.dart:209` pins the pass-through of `--version`, `pub get` and an empty argument, none of which D2 touches.

10. **The probe subshell, measured** (9 hostile helpers x dash and bash, plus absent and pre-OI-482): `if (. scripts/_dart_bin.sh && <setter>) >/dev/null 2>&1; then . ...`. A helper that passes `sh -n` but fails at RUN time is the gap in v1: with `sh -n` alone, an appended `exit 3` made the git-safety hook exit 3 with 0 dart calls (non-blocking), and `. /nonexistent` killed dash with 2 (the reviewer's measurement). Through the probe, `exit 3`, `. /nonexistent`, `set -o nosuchopt`, a syntax error, a top-level `return 1`, a trailing `false`, an absent helper and an old helper all reach today's call with the real exit 2 and the payload on stdin. A `readonly DART_BIN` in the helper escaped a probe that only ran `type`, which is why the setter itself runs inside the probe. **Superseded at the B-pass:** that form had one case left, a top-level `exit 0` reading as success (rc 0, 0 dart calls), and a `set -e` plus a failing command at the top of the helper ended a bash hook shell. A status sentinel then made `exit 7` the hole and ended every hook in an errexit shell (seat D). The shipped probe in D1 prints `ok`, runs in a plain assignment and sources with `;`: measured on 14 helpers x dash, bash and bash --posix, every cell ran dart once and kept exit 2. With a hook shell in errexit a sound helper is fine and a broken one ends the hook.
11. **The `flutter` spawns are not readers at start** (`check_regression_catalog.dart:73`, `check_test_runtime_budget.dart:60`, `contract_sweep.dart:51`, `capture_baseline.dart`, `compare_baseline.dart`): `flutter --version --machine` in a package with an empty yaml exits 0 (measured); the tool runs from its own snapshot in the SDK. Spawned test processes are OI-468's helper. Ledger: `verified_clean`.
12. **`dart run` does not heal an empty yaml** (round 2, measured): the file stays 0 bytes and every run exits 254, so a PERMANENT poison is a stable fixture. The harness shell: not known whether Claude Code uses dash or bash, so both run. Windows Git Bash (`wait`, `kill -0`, `$()` fds under MSYS): not verifiable here.
13. **Citation**: `test/helpers/spawn.dart:71` and `spawn_env_manifest_test.dart:72` cite `_dart_bin.sh:85`, the `DART_BIN_OVERRIDE` read. Correct today. D2's edits are below line 118, so it stays.

## Design

**D1. Harness command (nine strings in `.claude/settings.json`).** After the existing `cd "$r" || exit 1;` the tail `dart run [--verbosity=error] scripts/X.dart` becomes:
```sh
DART_BIN=dart; p=$( (. scripts/_dart_bin.sh; use_dart_race_retry && echo ok) 2>/dev/null); if [ "$p" = ok ]; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; "$DART_BIN" run [--verbosity=error] scripts/X.dart
```
- **Bare `dart` stays** (the same binary as today; `resolve_dart_bin` is not called: a change of binary is not this unit's business and is not needed for the retry).
- **`dart run` stays**, not the plain form: `dart run` resolves packages implicitly in a fresh worktree (no `.dart_tool` yet); the plain form would fail there with 255, non-blocking, i.e. fail-OPEN for the git-safety hook.
- **The probe subshell is mandatory** (ground truth 10). Anything that kills the shell while sourcing kills only the subshell, whatever the status; the real shell then falls through to today's call. Exit 2 BLOCKS a tool call and any other status lets it through, so both directions matter. It replaces `sh -n` AND the `type` guard and it covers a missing file (no `[ -r ]`), an old helper (the setter is `not found`, status 127, swallowed by the probe's redirect) and a setter that fails. The second `.` is what puts the function in the hook's own shell.
- Sourcing executes one `case` over `$0`, which is the hook shell's name, so the helper's "must be SOURCED" guard (exit 64) cannot fire.
- Residues, stated: (a) the TOCTOU between the probe and the second `.`: a checkout rewriting the helper in that window can still end the hook; (a1) a broken helper in a hook shell running with errexit ends the hook (the harness shell does not set it); (a2) the harness always supplies stdin as a pipe; with stdin CLOSED a stdin-reading child hangs under bash (the helper's documented limit, measured by the reviewer, not a shape the harness produces); (b) three straight lost races at `git_safety_hook` still exit 254 = non-blocking.
  This is NOT turned into exit 2, because a compile error in that hook is also 254 and would block every Bash call of the session; (c) process tree, measured in round 2: dash does NOT exec the last command of this string today; bash does, so under bash a harness KILL of the hook shell used to hit `dart` directly and with the retry active it does not (dart finishes by itself; every hook is short and bounded). The kill switch keeps today's tree in both shells; (d) the hooks remain WRITERS of the yaml (the plain form is unsafe, above); (e) stderr is delivered when the child ends: an exit 2 message arrives at the end, which is when the
  harness reads it anyway.
- A session reads its hooks at start, so the new commands apply to a session started after the merge; a session running an old string against a new tree is simply today's call.

**D2. `_dart_run_retrying` also retries the plain form.** The first-argument test becomes `case "${1:-}" in run|*.dart) ;; *) "$_drr_real" "$@"; return $? ;; esac`. Nothing else in the function changes. The five hooks only ever pass `run`, so they are unaffected
(`--version`, `pub get` and an empty argument still pass through once). Header comment updated; `resolve_dart_bin` stays at line 85 or the citations in `test/helpers/spawn.dart:71` and `spawn_env_manifest_test.dart:70` are repointed.

**D3. `safe_merge.sh`.** One line in the existing `then` branch, right after `_PRE_DART="$(resolve_dart_bin ...)"`:
```sh
DART_BIN="$_PRE_DART"; type use_dart_race_retry >/dev/null 2>&1 && use_dart_race_retry || true; _PRE_DART="$DART_BIN"
```
Lines 286 and 308 do not change. 286 is the `run` form in a pipeline inside `$( )` with stdin from `printf`, the shape `pre-push.sh`'s tier pipeline already proves; 308 is the plain form (D2). Both discard stderr, so the retry is silent there: stated, like the four OI-482 sites.
`safe_merge.sh` is `set -u` and has no other `DART_BIN`.

**D4. `run_dart_cli`, one supervised function in `scripts/_dart_bin.sh`, used by all three launchers.** `land_pr.sh` and `sync_with_main.sh` carry near-copies of a delicate signal block and have already drifted (`sync_with_main.sh` lacks the trap-before-start and
the bash re-wait), and `safe_pr_merge.sh` would be a third copy, so the block moves to one function:
```sh
_dart_cli_child=
_dart_cli_got=0
_dart_cli_on_signal() {
  _dart_cli_got=1
  if [ -n "$_dart_cli_child" ]; then kill -TERM "$_dart_cli_child" 2>/dev/null; fi
}

run_dart_cli() {
  _dc_n=0
  _dart_cli_child=''
  _dart_cli_got=0
  trap _dart_cli_on_signal TERM INT HUP
  while :; do
    "$@" &
    _dart_cli_child=$!
    if [ "$_dart_cli_got" = 1 ]; then kill -TERM "$_dart_cli_child" 2>/dev/null; fi
    wait "$_dart_cli_child"
    _dc_rc=$?
    while kill -0 "$_dart_cli_child" 2>/dev/null; do
      wait "$_dart_cli_child"
      _dc_rc=$?
    done
    if [ "$_dc_rc" -gt 128 ]; then
      wait "$_dart_cli_child" 2>/dev/null
      _dc_rc2=$?
      if [ "$_dc_rc2" -ne 127 ]; then _dc_rc=$_dc_rc2; fi
    fi
    _dart_cli_child=''
    if [ "$_dc_rc" != 254 ] || [ "$_dart_cli_got" = 1 ] || [ "$_dc_n" -ge 2 ] || [ "${AVYA_DART_RUN_RETRY:-1}" = 0 ]; then
      return "$_dc_rc"
    fi
    _dc_n=$((_dc_n + 1))
    printf '\n[dart-run-retry] native-assets race: retry %s of 2 | %s | exit=254 | stderr=shown above\n' "$_dc_n" "$*" >&2 || :
    _dart_race_backoff || :
    if [ "$_dart_cli_got" = 1 ]; then return 254; fi
  done
}
```
- **Why not `use_dart_race_retry` here:** `$!` would name the function's subshell, a TERM would orphan dart, and `exec` of a function fails. The child stays a direct background job, so `$!` IS dart.
- **The harness and the Dart sites key on status AND signature; only these three launchers use the bare status.**
- **Why the bare 254:** stderr stays live (these are long-running CLIs people watch), so the shell never sees the signature. Ground truth 6 proves no `main` here exits 254, so the only other 254 is a compile error: three attempts, 2 s lost, the error printed three times,
  still `result: error`. Accepted; a tee or FIFO to read stderr would add processes around a PID-sensitive block for a cosmetic gain.
- **No elapsed-time guard** (the design notes proposed `elapsed <= ~10 s`): with ground truth 6 it could never decide anything, so it would be a dead clause with an unkillable mutant.
- `land_pr.sh` and `sync_with_main.sh`: the block is replaced by `run_dart_cli "$DART_BIN" "$here/<cli>.dart" "$@"` + `rc=$?`; the clamp, the refusals and the `result:` lines stay. The helper is mandatory in both (`[ -f "$here/_dart_bin.sh" ] || refuse`) and comes from the same
  directory, so there is no old-helper case: a function missing from it gives 127, clamped to `result: error`, fail-closed.
- **The child pid is cleared once reaped**, on the return path as well as the retry path (rounds 1 and 2): a TERM in the 1 s backoff, or between the return and the wrapper's `exit`, must not `kill` a pid that may have been reused. The trap stays installed after the return, as it does today in `land_pr.sh`; the wrappers exit right after: stated.
- `safe_pr_merge.sh`, whose helper is OPTIONAL and which keeps its literal `exec` lines as the fallback AND as the kill-switch path, so today's call is reachable verbatim:
```sh
if [ "${AVYA_DART_RUN_RETRY:-1}" != 0 ] && type run_dart_cli >/dev/null 2>&1; then
  set +e
  if [ -n "$ALLOW" ]; then
    run_dart_cli "$DART_BIN" scripts/safe_pr_merge.dart "$1" "$ALLOW"
    exit $?
  fi
  run_dart_cli "$DART_BIN" scripts/safe_pr_merge.dart "$1"
  exit $?
fi
```
  `set +e` because the function's `wait` must reach its own status handling.
- Behaviour changes, stated: `sync_with_main.sh` now returns a CLI's real status after a signal under bash and survives a signal in the pre-start window; `safe_pr_merge.sh` forwards INT and HUP as TERM (today the exec'd dart gets them directly) and a signal death is reported as
  143 rather than as a signal: `land_pr.dart` asks GitHub afterwards (ground truth 8). Its stdin is now `/dev/null` (ground truth 7). **SIGKILL residue (round 1):** `exec` meant a SIGKILL of the wrapper was a SIGKILL of dart; now the background dart survives a SIGKILL of the wrapper alone and may start or finish the merge. Today's SIGKILL already leaves a running `gh pr merge` alive, nothing here sends SIGKILL (`land_pr.dart:574` passes no `timeoutMs`, the only path to `p.kill(sigkill)`, pinned by a new source test), and it needs a deliberate `kill -9` of that one pid. A 254 on the last attempt reports as today: non-zero, no merge.
- Existing rows `[8, 9, 254, 255, 137, 130]` of the wrapper e2e tests keep passing; the 254 row now takes 2 s longer (fixture CLI, real retries). Stated; the tests are not changed for it.

**D5. The Dart spawns: `scripts/dart_race_retry_lib.dart`, seven sites wrapped, one exempt.**
```dart
const String kNativeAssetsRaceSignature = 'File not formatted as yaml';
const int kNativeAssetsRaceStatus = 254;
const int kNativeAssetsRaceMaxRetries = 2;

bool isNativeAssetsRace(int status, String stderrText);
bool dartRaceRetryOff(Map<String, String> environment);     // exactly '0'

Future<T> retryDartRace<T>(
  Future<T> Function() attempt, {
  required int Function(T) statusOf,
  required String Function(T) stderrOf,
  required String label,                                    // goes into the note
  void Function(String note)? onNote,                       // default: stderr.writeln
  Future<void> Function(Duration)? backoff,                 // default: Future.delayed; test seam
  bool Function()? stop,                                    // land_pr: an interrupt ends the retry
  Map<String, String>? environment,                         // default: Platform.environment; test seam
});

// The common `Process.run` shape: retryDartRace<ProcessResult> reading exitCode and stderr. Six of the seven sites use it.
Future<ProcessResult> retryDartProcess(
  Future<ProcessResult> Function() attempt, {
  required String label,
  void Function(String note)? onNote,
  Future<void> Function(Duration)? backoff,
  Map<String, String>? environment,
});
```
Same budget, same 1 s backoff and the same `[dart-run-retry]` note as the shell function; the signature IS available here (`Process.run` captures it; round 2 measured that it survives `runInShell`), so the Dart sites key on status AND signature. `ProcessResult.stderr` is `String` at every site (default or explicit utf8). The lib is registered `platform` in `docs/blast_radius.yaml` (a new file under `scripts/` defaults to feature; it is imported by `land_pr.dart` and `sync_with_main.dart`, both on the merge path). Sites:
- `batch_close_hook.dart:_telemetry`: under the EXISTING outer `.timeout(10 s)`, so the 10 s budget and the silent-on-any-failure contract do not change. `Future.timeout` does not cancel the loop, so an attempt can still start after the deadline and die with the hook's `exit`: harmless, stated, and the same "abandons the child" the code comment already names. The note goes to stderr; stdout carries the harness JSON and must not get it.
- `sync_with_main.dart:_gateIndex`: around `Process.run`; the `on ProcessException` arm is unchanged.
- `land_pr.dart:_recordGate`: around `_run(Platform.resolvedExecutable, [gate.path], ...)` with `stop: () => _interruptSignal != null`. The `_checkInterrupt()` after it stays. `land_pr.dart:462` (the seam) is not wrapped.
- `check_adr_index_fresh.dart`, `check_gate_index_fresh.dart`, `check_incident_index_fresh.dart`: around `Process.run('dart', ['run', ...], runInShell: true)`. Each builder's failure branch is unchanged. These are the three sites where a lost race can block a commit today.
- `check_two_user_cross_account.dart`: around its `Process.run`. Keyed on the signature, so the retry only fires before `main`; the live arbiter it starts cannot run twice. Never executed by a test (it reaches production): covered by the sweep pin only, stated.
- **`git_safety_hook.dart:217` is NOT changed: the stated reason, with its test.** It is the advisory plan-review precheck; a lost race gives one spurious `NOTE` in `additionalContext` and enforcement is unaffected. An import of the lib would add a file to the guard's compile closure, and a compile error there is 254 = non-blocking = the guard is gone (measured in round 2: a broken or missing import gives 254). Trading a guard's safety for an advisory note is the wrong way round. Tests: the sweep pin's allowlist names exactly this site with this reason; a pin that the hook's imports are exactly `dart:*` and `git_safety_lib.dart`.

**The sweep pin (the reason v1 missed five sites):** a test in `dart_race_retry_lib_test.dart` scans `scripts/*.dart`, comments stripped, multi-line, for every `Process.run|runSync|start(` or `_run(` whose first argument is the literal `'dart'` or `Platform.resolvedExecutable`, and requires each to match the wrapped shape `retryDartRace<...>(() [async] => [await] <spawn>` (a shape match, not paren balancing; `<...>` optional, whitespace and newlines allowed after `(` and `=>` because `dart format` breaks them; a block-bodied closure is not recognised, so every site uses `=>`). Allowlist: exactly `git_safety_hook.dart`. `dart_race_retry_lib.dart` spawns nothing. It catches LITERALS only: a spawn through an executable held in a variable (`land_pr.dart:177`, `check_oi_numbering_unique.dart:66`, `safe_pr_merge.dart:43` have such parameters, none is dart today) is out of its reach: stated. A fixture string with a new unwrapped multi-line spawn proves the scan fires.

**D6. Kill switch, plumbing.** `AVYA_DART_RUN_RETRY=0`, exactly `0`: harness (the setter is a no-op, `DART_BIN` stays `dart`), `safe_merge.sh` (same), `land_pr.sh` and `sync_with_main.sh` (one attempt, same signal handling), `safe_pr_merge.sh` (the literal `exec` line), Dart (no retry). The name is already
in `childEnvStrippedNames` and `_stripped`. `environment ?? Platform.environment` in the new lib is an alias read: one new `_aliasAllowList` row in `test/contracts/spawn_env_manifest_test.dart` (`count: 1, kind: 'reads'`; so the expression appears exactly once outside comments in the lib). Run that test and `spawn_sites_guard_test.dart` right after the first edit. Every new e2e file declares a file-level `@Timeout` and `library;`, spawns through `runSpawn`/`startSpawn`/`dartBin()`, and sets `DART_BIN_OVERRIDE` through `extraEnv` with `allowControl` (the helper strips it by default). Docs: `docs/naming_conventions.md` (`run_dart_cli`, `retryDartRace`,
`kNativeAssetsRaceSignature`, the changed kill-switch row), `docs/architecture/hooks.md:282` (the hook template; a new OI-483 row), the `_dart_bin.sh` header ("Sourced by the git hooks" becomes hooks, harness commands and launchers).

**D7. Tests.** New: `test/scripts/launchers_dart_race_retry_e2e_test.dart`, `test/scripts/dart_race_retry_lib_test.dart`. Extended: `claude_hooks_cwd_independent_test.dart`, `dart_run_retry_test.dart`, `safe_merge_test.dart`, `batch_close_hook_e2e_test.dart`, `gate_index_fresh_e2e_test.dart`, the two source-pin files, the two wrapper e2e files. **Import closures:** `batch_close_hook_e2e_test.dart:70-74` hand-copies its scripts into fixtures and must also copy `dart_race_retry_lib.dart` (or move to `copyScriptClosure`, `test/helpers/script_closure_fixture.dart`). `gate_index_fresh_e2e_test.dart` needs no change: the gate runs from the repo path and only the builder is copied. Every other test that copies one of the seven files is found by `git grep` at the first edit. `discipline_hook_local_indexes_e2e_test.dart:377` runs the real SessionStart command in a helper-less fixture: it exercises the today's-call path and must stay green unchanged; `reconcile_ci_wiring_test.dart:30` greps `scripts/reconcile_ci.dart`, which survives.
1. **`claude_hooks_cwd_independent_test.dart`.** `hookTemplate` learns the new tail; `scriptOf`'s pattern becomes `(?:dart|"\$DART_BIN") run (?:--verbosity=error )?scripts/...`. **The SAFETY rule (round 2 replayed it: `2>&1` trips the lone-`&` check, `>/dev/null` the redirection check, and a first-token allowlist containing `then` would pass `then . /anything`):** the new fragment is accepted ONLY as one exact string. `_retryHead = 'DART_BIN=dart; p=$( (. scripts/_dart_bin.sh; use_dart_race_retry && echo ok) 2>/dev/null); if [ "$p" = ok ]; then . scripts/_dart_bin.sh; use_dart_race_retry; fi; '` is removed by `replaceAll`, and `"$DART_BIN" run` is normalised to `dart run`, (and the `exec` mutant's `exec "$DART_BIN" run` likewise, through its `alsoAllow` literal) before the existing rule runs unchanged, so every other segment still goes through it and `then . /anything` fails. Each META mutant of the fragment is a fixed literal: `safetyViolations(mutant, alsoAllow: <that mutant's own head>)` admits exactly it, so it still reaches its behaviour check and the "every mutant passes SAFETY" test stays honest. The strict one-argument form is what `setUpAll` applies to `.claude/settings.json`. C3..C9 run in two fixtures: with the REAL helper seeded and with none (today's path; `seedScripts` gains a variant). New named checks, every command, both shells: C12 lost race retried (stub dart fails the first call with 254 + signature WITHOUT reading stdin; a logging `sleep` stub on PATH); C13 helper absent; C14 the hostile-helper table of ground truth 10, every row reaching today's call with the real exit 2 and the payload (syntax error, `exit 3`, `. /nonexistent`, `set -o nosuchopt`, top-level `return 1`, `readonly DART_BIN`), the top-level `exit 0` row pinned as the KNOWN residue;
   C15 exit 2 with a stderr message through the function, stdout untouched; C16 kill switch (one call, 254 back); C17 helper older than OI-482 (frozen from `git show`, stored as a fixture; no `not found` on stderr); C18 a setter that returns 1. One REAL-SDK test: the git-safety template in a throwaway package whose `dart` on PATH is a SHIM that runs the real dart and deletes the yaml on a 254, so
   attempt 1 is a real 254 and attempt 2 reads stdin and blocks with exit 2 (recipe from `dart_run_retry_test.dart` 2c, with a stub `git_safety_hook.dart` that reads stdin and exits 2; the shim is spawned through `sh -c`, not `runSpawn(dart, ...)`, so OI-468's helper does not retry it).
2. **META mutants of the template** (each killed by its NAMED check): the probe dropped so the `.` is unguarded (C14), `sh -n` instead of the probe (C14, the `exit 3` row), the setter outside the probe (C14, the `readonly` row), `2>&1` dropped from the probe (C17), no `DART_BIN=dart` (C3), `dart run` instead of `"$DART_BIN" run` (C12), setter call dropped (C12), the source line dropped (C12), `|| true` appended (C5, the existing M3), `exec "$DART_BIN"` (C12: `exec` of a function fails).
3. **`dart_run_retry_test.dart`.** The plain form: `x.dart`, an absolute `.../x.dart` and `--flag` (not retried); argv preserved; the note names the script; the real-SDK canary gains the `run --verbosity=error` row, and the shim test gains a plain-form row. The existing `--version` / `pub get` / empty pass-through stays.
4. **`launchers_dart_race_retry_e2e_test.dart`.** Table over the three launchers x `sh` and `bash`, stub child via `DART_BIN_OVERRIDE` plus the real `_dart_bin.sh`: status passthrough 0..7 (`safe_pr_merge`: 0..2); race healed (2 calls, 1 note); race twice then a real status (3 calls); race always (3 calls; `result: error` exit 4 for the two clamped wrappers, 254 for `safe_pr_merge`);
   255 is NOT retried; kill switch (1 call; for `safe_pr_merge` a source-and-behaviour check that it reached the `exec` line: the PID the stub records equals the wrapper's PID); TERM during attempt 1 and attempt 2 (child dead, `kill -0` false, no further attempt); TERM during the backoff: dash and bash defer a trap until a foreground `sleep` returns, so the `sleep` stub on PATH does a short REAL sleep, the test signals when the note appears on stderr, and the assertions are the status and a `kill`-logging driver (a shell function shadowing `kill`), never a timing or a call count alone; INT and HUP through the `perl` wrapper of the existing test; TERM with a child that exits 3 (the real status: this row is the named killer of the `kill -0` loop and the `> 128` re-wait mutants; record which it reddens). One real-SDK row per launcher: a fixture CLI beside the wrapper with an empty yaml and the shim, real 254 then real success. `land_pr.dart:574` carries no `timeoutMs` (source pin, the SIGKILL residue of D4).
5. **`safe_merge_test.dart`.** Its fixture (`:46-50`) copies only `safe_merge.sh` and `_git_lock.sh`, so the new scenario copies `_dart_bin.sh` too, or D3 would be inert and the test green for nothing. A branch at blast-radius >= account with a stub dart failing the first call of each of the two sites: 286 still classifies (the WARNING names the tier) and 308 still honours a bare bump (the NOTE, not the WARNING); the kill-switch twin shows today's outcome: "could not classify", and the WARNING on a bump.
6. **`dart_race_retry_lib_test.dart`.** Pure table with a fake attempt and a recording backoff: race then ok; budget exhausted returns the last result; non-race status; signature with exit 1; 254 without the signature; kill switch `0`, `false`, empty; `stop` true before a retry; note text and backoff count (N-1 rule). Pin that `kNativeAssetsRaceSignature` equals the literal in `_dart_bin.sh` and `nativeAssetsRaceSignature` in `test/helpers/spawn.dart`; pin the lib's imports (`dart:io`, `dart:async` only); the sweep pin of D5 with its positive fixture and its one-entry allowlist; the imports pin on `git_safety_hook.dart`.
7. **The Dart sites, real SDK, deterministic.** A PERMANENT empty yaml, asserting exactly 2 notes on stderr and the site's existing failure text, with a kill-switch twin of 0 notes. Each shape keeps the CLI out of the poisoned package (Dart walks UP, so a CLI inside the fixture dies itself, red for the wrong reason). `sync_with_main`: `sync_cli_fixture` already runs the CLI from `srcRoot` (`left ... the builder failed (exit 254)`). `batch_close_hook`: the fixture copies hook and telemetry into ONE directory (`:109-112`), so the new row runs the REAL hook by absolute path in the plain form, cwd = a fixture whose `scripts/batch_process_telemetry.dart` is poisoned (no telemetry line, exit unchanged). `land_pr`: `test/scripts/land_pr_replay_test.dart` already drives the REAL replay (`replayFixture()`, `realReplay`, a control reaching `merged`, `:54,:85`): a new row poisons `${fx.dir}/.dart_tool/native_assets.yaml` AFTER the fixture's last commit and push (`ScopeRepo` does not exclude `.dart_tool`, so an earlier poison would be committed by `add -A`), untracked, so the dirty check (`status --untracked-files=no`, `land_pr.dart:277`) is not tripped; `result: record-failed`, 2 notes, and it is the regression test of ground truth 2. The fresh gates: `check_gate_index_fresh.dart`, `check_adr_index_fresh.dart` and `check_incident_index_fresh.dart` each run from the repo path with a poisoned fixture cwd (`dart run` resolves its package from the script, so the gate survives and only its inner `dart run` dies; `dart run` does not heal the file, ground truth 12): 2 notes then the substring `FAIL: builder errored` on stderr, exit 1, kill-switch twin 0 notes. Each fixture needs what the gate reads first (`docs/adr/INDEX.md`, `docs/incidents/INDEX.md`, `docs/audit/GATE_INDEX.md`) and a `scripts/build_*_index.dart` in the fixture cwd, and PATH must hold the SDK because these gates spawn a bare `dart` through a shell. REQUIRED for all three: two of them can block a commit exactly as the third can. `check_two_user_cross_account.dart`: sweep pin only (never executed in a test, it reaches production): stated, presence only. `batch_close_hook`: the assertion is at LEAST 1 note with 0 on the twin, because 3 dart starts plus 2 s of backoff under a 10 s budget on a loaded machine cannot promise 2. A healing variant is NOT used: it would race the 1 s backoff on a loaded machine.
8. **Repoints** (never loosen): `land_pr_source_pins_test.dart` and `sync_with_main_source_pins_test.dart` read the signal block from `_dart_bin.sh` and pin that each wrapper calls `run_dart_cli`; `sync_with_main` "does not use set -e" stays; `land_pr_wrapper_e2e_test.dart:109` and `sync_with_main_wrapper_e2e_test.dart:103` APPEND their `resolve_dart_bin` to the copied real helper. A new pin: `safe_pr_merge.sh` keeps both `exec` lines after the `run_dart_cli` block.
9. **Mutants** (harness baseline-first, anchors confirmed, a syntax or compile error is NOT a kill): harness as in 2; D2 `*.dart` arm removed, `run` arm removed, widened to `*`; D3 line removed, `_PRE_DART="$DART_BIN"` removed; D4 each clause of the retry condition removed (x4, per-clause), `254` to `255`, cap 1/3, `_dart_cli_got` check after the backoff removed, `kill` in the handler removed, the pre-start `got` check removed, the `kill -0` loop removed, the `> 128` re-wait removed, `-ne 127` to `-eq 127`, note removed, each launcher's call replaced by the plain child; safe_pr_merge `set +e` removed, the switch clause removed, the `type` clause removed; D5 each predicate clause, `stop` ignored, cap, note dropped, each of the three call sites unwrapped; `.timeout` moved inside the retry. `_dart_cli_child=''` removed (the `kill`-logging driver). Named equivalents only after a run shows it. The bash re-wait is pinned by shape, as today (land_pr pin: "cannot be provoked here"), UNLESS the `sync_with_main` TERM-real-status row reddens when it is removed, which the prototype suggests: run it and record which. The mutant "`.timeout` moved inside the retry" is run; if no fixture can kill it, it is listed as survived with that reason, not called equivalent. D5's site mutants: each of the seven sites unwrapped (the sweep pin AND its e2e row where one exists), `git_safety_hook.dart` given the import (the imports pin).

**D8. Process and closure.** Two or more plan-review rounds; `flutter analyze --no-fatal-infos`, the full suite (`TZ=Asia/Kolkata`, `--exclude-tags golden`) and the pre-commit gate loop before the B-pass; `/code-review`; plan-review record `docs/plan-reviews/oi483-harness-dart-race.md` (`bpass: accepted`, a bare `verdict: accepted` line in the cited file); Gate 40 ledger
`docs/audit/oi483-harness-dart-race.closure.yaml` (header with `diagnose_docs:` and `plan_review_record:` like the OI-482 ledger; 9 harness commands + 6 launcher lines + 7 Dart spawns as `closed_in_commit`; `git_safety_hook.dart:217` as `verified_clean` with the stated reason; the `flutter` spawns of ground truth 11 as `verified_clean`; the residues of D1 as `verified_clean` or `upstream_blocked` with a reason; a `blocked_on_user` row for the Windows clone, whose Git Bash `sh` is bash, not measured here). A FULL diagnose doc (recurrence of bug class 2.147, instances b7e2d9 and c4e2a8; `closes-diagnose:` trailer), an addition to bug class 2.147, not a new class, with the `debugging/SKILL.md:234` row updated ("a package lookup walks UP: a directory with no `.dart_tool` is not out of the race"; "a sweep regex that cannot cross a line missed five spawns"), `closes-oi: OI-483` as a real trailer only (never quoted in prose in any commit body).
OI-483 moves to `closed_issues.md` by APPENDING (check diff-stat deletions); its stale "Blocked on" line is corrected in the archived text. The OI-482 ledger's R1 row stays as written (a closed batch's record); the new ledger cites it. Run `check_context_artifact_budget.dart` after the doc edits (`debugging/SKILL.md` and `hooks.md` are near their baselines; build the local indexes before any `--record`). No SoT registry entry: this is process tooling, no Hive or cloud contract (`c3f8e1`, `e6c4a9`, `b7e2d9` recorded the same). Replay the whole `check_*.dart` loop on a simulated merge before the push. After the merge: `land_pr.sh`, `git fetch origin main && git merge --ff-only origin/main` in the primary, `sh scripts/setup-hooks.sh` (no hook source changes here, so the installed copies should already match: run it anyway and report), retire the worktree, correct the design-notes memory (the `land_pr.dart:521` claim was wrong).
