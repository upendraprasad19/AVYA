---
bug_id: e4c1b7
date: 2026-11-07
batch: oi483-harness-dart-race
status: fixed
tier: l_fix
blast_radius: platform
symptom: >-
  The native-assets race (diagnose b7e2d9) was contained in the test helper (OI-468) and at the git hooks (OI-482), but every other dart start still lost it
  silently. A lost race means exit 254 with `File not formatted as yaml: .` BEFORE `main`. At the 9 harness hooks in .claude/settings.json 254 is NON-BLOCKING:
  a lost race at `git_safety_hook.dart` lets a raw `git commit` or `git push` through, and the other hooks simply do not run. At the launchers `land_pr.sh`,
  `sync_with_main.sh` and `safe_pr_merge.sh` a lost race ends the run with `result: error` before the CLI started. At `safe_merge.sh` it gives a false "could not
  classify" and silently loses the version-bump exemption. Among the Dart spawns, `land_pr.dart`'s replay gate reports a false `record-failed`, three gates
  (`check_adr_index_fresh`, `check_gate_index_fresh`, `check_incident_index_fresh`) could block a commit on it, and `check_two_user_cross_account` (live-DB, run at /build-apk) a build. NOT established: that
  any historical failure of these sites was this race; the race is measured at each site by forcing it, not by a recorded incident at that site.
concept: not_applicable — harness hook and launcher tooling (.claude/settings.json, scripts/_dart_bin.sh, the launchers, the Dart spawns); no Hive/cloud writer-reader contract and no entry of docs/sot_registry.yaml covers it.
sot_registry_entry: not_applicable — no writer/reader pair, Hive key or cloud table is involved.
related_bugs: [b7e2d9, c4e2a8, a7f3d1, 8f3e35]
recurrence: |
  RECURRENCE of class 2.147 (the OI-468 / OI-482 exit-254 family): b7e2d9 contained it in the test spawn helper, c4e2a8 at the git hooks, and c4e2a8 named these
  sites as this OI. The known-good fix is applied again: retry exactly the measured signature, a bounded budget of 2, a 1 s backoff, a printed note. Two things
  differ from those instances and are the reason for a plan: a launcher's stderr must stay live, so `run_dart_cli` keys on the bare status 254; and a helper
  sourced by a harness hook can turn a tool call into a BLOCK (exit 2), so the harness tail probes the helper in a subshell first (class of 8f3e35: a guard that
  "did not fire" may never have started).
writers:
  - { file: .claude/settings.json, method_or_widget: "the 9 hooks stay WRITERS of .dart_tool/native_assets.yaml on every prompt and tool call (`dart run` rewrites it in place, b7e2d9): the plain form cannot resolve packages in a fresh worktree, it would exit 255, non-blocking, so fail-open", line: 12 }
  - { file: scripts/_dart_bin.sh, method_or_widget: "_dart_run_retrying: `run` or a first argument ending in `.dart` is retried on 254 + signature; everything else passes straight through", line: 153 }
  - { file: scripts/_dart_bin.sh, method_or_widget: "run_dart_cli: a supervised background child, TERM/INT/HUP forwarded as TERM, the real status waited for, a retry on bare 254 unless a signal arrived", line: 231 }
  - { file: scripts/dart_race_retry_lib.dart, method_or_widget: "retryDartRace / retryDartProcess: the same budget, backoff, note and kill switch for a Dart caller, keyed on status AND signature; dart:io only", line: 43 }
readers:
  - { file: .claude/settings.json, method_or_widget: "the 9 hook commands: probe subshell, then the setter, then `\"$DART_BIN\" run ...`; a helper that cannot be sourced leaves today's bare `dart run`", line: 12 }
  - { file: scripts/land_pr.sh, method_or_widget: "run_dart_cli around land_pr.dart; the clamp and the result line unchanged", line: 60 }
  - { file: scripts/sync_with_main.sh, method_or_widget: "run_dart_cli around sync_with_main.dart; the clamp and the result line unchanged", line: 57 }
  - { file: scripts/safe_pr_merge.sh, method_or_widget: "run_dart_cli when the helper has it and the switch is on; the two literal exec lines stay as the fallback and the kill-switch path", line: 49 }
  - { file: scripts/safe_merge.sh, method_or_widget: "`_PRE_DART` takes the function, so the `run` call and the plain-form call are both retried", line: 276 }
  - { file: scripts/land_pr.dart, method_or_widget: "_recordGate: the replay gate, whose clone has no .dart_tool of its own, so dart walks UP and reads the PRIMARY's yaml", line: 523 }
  - { file: scripts/batch_close_hook.dart, method_or_widget: "the telemetry spawn, under its existing 10 s timeout", line: 159 }
  - { file: scripts/sync_with_main.dart, method_or_widget: "_gateIndex", line: 666 }
  - { file: scripts/check_adr_index_fresh.dart, method_or_widget: "the builder spawn", line: 28 }
  - { file: scripts/check_gate_index_fresh.dart, method_or_widget: "the builder spawn", line: 36 }
  - { file: scripts/check_incident_index_fresh.dart, method_or_widget: "the builder spawn", line: 19 }
  - { file: scripts/check_two_user_cross_account.dart, method_or_widget: "the arbiter spawn; keyed on the signature, so it can only fire before `main`", line: 31 }
  - { file: scripts/git_safety_hook.dart, method_or_widget: "the advisory plan-review precheck: deliberately NOT wrapped, see forbidden_patterns_checked", line: 217 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/scripts/dart_race_retry_lib_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no user data.
forbidden_patterns_checked:
  - "`sh -n scripts/_dart_bin.sh && . scripts/_dart_bin.sh` as the harness guard (the design notes' plan) — rejected: measured, `sh -n` passes a helper containing `exit 3`, `. /nonexistent` or `readonly DART_BIN`, and each of those kills or breaks the hook's shell; only a subshell that really sources it and runs the setter contains all of them. A helper that ends the shell with `exit 0` is contained too, since the B-pass (see the mutation section)"
  - "converting the harness commands to the plain form `dart scripts/x.dart` to stop them being writers — rejected: `dart run` resolves packages in a fresh worktree, the plain form does not, and the resulting 255 is non-blocking, so the raw-git guard would fail OPEN"
  - "setting DART_BIN to the function at the launchers — rejected: `child=$!` of a backgrounded function is its subshell, so a forwarded TERM orphans the real dart"
  - "reading stderr at the launchers to require the signature — rejected: a tee or FIFO adds processes around a pid-sensitive block for a cosmetic gain, and the CLIs never exit 254 themselves (they clamp): the bare status is safe there, and a retried 254 repeats no side effect because `main` never ran"
  - "the design notes' 'land_pr's scratch clone has no .dart_tool, so no race' — FALSE, measured: dart walks UP from the script, so the replay gate reads the primary's yaml. The site is wrapped"
  - "importing the retry into git_safety_hook.dart — rejected: a compile error in the guard's closure is a silent 254, which is `allow`; its one spawn is an advisory precheck whose lost race costs one spurious NOTE. The exemption and the closure are both tests"
  - "a single-line grep for dart spawns — rejected after it missed five sites (the calls span lines), three of which could block a commit: the inventory is now a multi-line test that also fails on any new unwrapped spawn"
  - "a timeout on land_pr's call of the merge wrapper — rejected: a timeout is the only path to a SIGKILL, and SIGKILL of the wrapper orphans the supervised dart now that it is not an exec. Pinned by a source test"
proposed_fix: |
  CAUSE: b7e2d9's mechanism. New today, measured on SDK 3.11.1 under dash and bash: dart walks UP directories to find the package, so a script with no .dart_tool reads
  the nearest parent's yaml; `dart run` does not heal an empty yaml, so a permanently empty file is a stable fixture; `--verbosity=error` and `runInShell` keep the
  signature; a FIFO in place of the yaml holds a real dart inside its read until the writer closes, then gives a real 254 (the seam of the land_pr interrupt test).
  FIX. (1) The 9 harness commands: `DART_BIN=dart; p=$( (. scripts/_dart_bin.sh; use_dart_race_retry && echo ok) 2>/dev/null); if [ "$p" = ok ]; then . scripts/_dart_bin.sh; use_dart_race_retry; fi;
  "$DART_BIN" run ...`. The probe runs the setter inside a subshell, so every source-time death is contained and today's call is the fallback. (2) `_dart_run_retrying`
  learns the plain form (`run|*.dart`). (3) `safe_merge.sh` passes `_PRE_DART` through the setter. (4) `run_dart_cli`: a background child in a loop, a trap on TERM, INT and
  HUP that forwards TERM, a `kill -0` loop plus a re-wait that recover the REAL status after a signal interrupts `wait`, a retry on 254 unless a signal arrived, the same
  note and budget. `land_pr.sh` and `sync_with_main.sh` use it in place of their own block; `safe_pr_merge.sh` uses it behind the switch and keeps its literal `exec`
  lines. (5) `scripts/dart_race_retry_lib.dart` wraps seven Dart spawns; `land_pr.dart` passes `stop:` so an interrupt ends the retry. Kill switch: AVYA_DART_RUN_RETRY=0.
  STATED LIMITS: the harness hooks remain WRITERS while a suite runs in the same checkout; a harness hook now costs 3.3 ms more per run; the launcher note says
  "stderr=shown above" because stderr is live; `safe_pr_merge.sh` reports a SIGKILL of the wrapper differently and leaves its dart orphaned (no exec any more, and the only
  sender in this repo was a timeout, which is pinned absent); Windows is not measured (founder check B1 in the closure ledger).
regression_test_planned: |
  - test/scripts/claude_hooks_cwd_independent_test.dart: EVERY command string executed under dash and bash with a stub dart and with the real SDK: a lost race, a blocked exit 2
    with its message, the kill switch, and hostile helpers (absent, syntax-broken, a directory, older than OI-482, `exit 3`, `. /nonexistent`, `readonly DART_BIN`).
  - test/scripts/launchers_dart_race_retry_e2e_test.dart: the three real wrappers and the real helper under both shells: retry, budget, 255 not retried, kill switch, TERM in the
    first attempt, in a retry and in the backoff, INT and HUP, the real status after a signal, a real SDK 254; and run_dart_cli directly, unclamped.
  - test/scripts/dart_race_retry_lib_test.dart: the predicate, note, budget and `stop`; the sweep pin; the guard's compile closure; the merge-without-timeout pin.
  - test/scripts/fresh_gates_race_retry_e2e_test.dart, safe_merge_test.dart, batch_close_hook_e2e_test.dart, sync_with_main_e2e_test.dart, land_pr_replay_test.dart: each wrapped
    site through a real lost race, with a switched-off twin where the failure is visible.
  MUTATION PROOF (rule 21): the "Mutation proof" section below.
impact_analysis: |
  Platform tier (.claude/settings.json runs in every session; the helper is sourced by every hook and launcher). No lib/ code, no Hive key, no cloud column, no Edge Function. A
  dart start that used to fail on a lost race now passes after at most two more attempts with a note on stderr; the kill switch restores today's call at each site. Behaviour
  changes stated in the plan: `sync_with_main.sh` now returns a CLI's real status after a signal under bash and survives a signal before the child starts (a side effect of
  sharing one function), `safe_pr_merge.sh`'s child gets stdin from /dev/null. The installed git hooks are not touched by this batch; `setup-hooks.sh` is re-run after the merge
  as the handoff asks. Value semantics (4.1.5.3): swept `test/` and `docs/` for pins on the launcher blocks and the harness tail; source pins and the two wrapper e2e tests were
  repointed, none loosened.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: ".claude/settings.json, scripts/_dart_bin.sh, the launchers and seven Dart spawns; no lib/ change" }
  - { tier: 11, name: "External services", status: verified, evidence: "Dart SDK 3.11.1 (the Dart of CI's Flutter 3.41.4): the race measured through `dart run`, `dart run --verbosity=error`, the plain form, a walked-up parent yaml and a FIFO, each giving exit 254 and the signature" }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "no client or server code is involved; the failing component is the Dart SDK's start-up" }
---

# The native-assets race at the harness hooks, the launchers and the Dart spawns (OI-483)

## What was seen
A lost race at `git_safety_hook.dart` is exit 254, which the harness reads as "allow": the guard that blocks a raw `git commit` silently did not run. The same race ended `land_pr.sh`
with a false `result: error`, gave `safe_merge.sh` a false "could not classify", and reported `record-failed` at a replay whose clone was believed to be safe from it.

## Cause (writers and readers by file:line)
See the front matter. The writers are every `dart run` in the package; the readers are every dart child that walks up to that package. A harness hook is both.

## What was proven and what was not
- PROVEN: the real `git_safety_hook.dart` with the real SDK through the new command string blocks a raw commit with exit 2 and its message; a real 254 at each launcher reaches the real
  `main` exactly once on the retry; dart walks up (a script under `P/.git/x/` with no `.dart_tool` exits 254 on P's empty yaml and 0 when it is removed); each wrapped site passes where
  its switched-off twin fails; every hostile helper in the table leaves today's call.
- NOT proven: that any past failure at these sites was this race; that two retries are enough under load (the same limit as c4e2a8); Windows behaviour (founder check B1).

## Repeatable commands
- Walk-up: an empty `P/.dart_tool/native_assets.yaml`, a script at `P/.git/x/scripts/x.dart`, `dart P/.git/x/scripts/x.dart`: rc 254.
- Holding a real dart inside the read: `mkfifo .dart_tool/native_assets.yaml`, start the script, `exec 3> .dart_tool/native_assets.yaml`, wait, `exec 3>&-`: rc 254 at the close.
- A harness command: take the string from `.claude/settings.json` and run it with `sh -c` in a repo with a stub `dart` on PATH (test/scripts/claude_hooks_cwd_independent_test.dart does).

## Mutation proof (rule 21, self-attested)
Run on the final code by a driver that applies one mutation at a time to the real file, counts its anchor first (a missing or repeated anchor is logged, never run; none occurred), runs the tests named for
that mutant, and restores the file byte for byte (asserted at the end of every run: `RESTORED ok=True`). The baseline of the 11 test files was green first (352 tests). A compile error counts as nothing; every
red below is failing assertions in tests that ran. Result: **54 of 54 reddened after five tests were added for the survivors of the first run; 0 equivalents named.**

| Group | Mutants | What they were |
|---|---|---|
| D2 `_dart_run_retrying`'s first argument | 3 | `.dart` arm removed, `run` arm removed, widened to everything |
| D3 `safe_merge.sh` | 2 | the line removed; `_PRE_DART` not reassigned |
| D4 `run_dart_cli` and the launchers | 26 | each clause of the retry condition removed; 254 to 255; cap 1 and 3; the two `got` checks; the handler's kill; the `kill -0` loop; the re-wait (also against the source pins alone); `-ne 127` to `-eq 127`; the note; the child not cleared; the trap, and HUP and INT out of it; the backoff; a plain child in `land_pr.sh` and `sync_with_main.sh`; `set +e`, the switch clause, the `type` clause and the flag at `safe_pr_merge.sh` |
| D5 `dart_race_retry_lib.dart` | 12 | `&&` to `||`; status dropped; signature dropped; the switch ignored and any value; cap 3; `stop` ignored before the retry and after the backoff; the note dropped; the backoff dropped; the 300 cut; the note on stdout |
| Sites | 8 | six spawns unwrapped; `land_pr`'s `stop` dropped; `git_safety_hook.dart` given the import |
| Pins and settings | 3 | the merge wrapper given a timeout; the harness tail bypassing the function; the probe dropped on one hook |

**Added at the B-pass (seat A).** The probe first read `if (. helper && setter)`: a helper with a top-level `exit 0` passed it and then ended the hook shell before dart, and a `set -e` plus a failing command at the top of the helper did the same under bash, either of which turns a blocking exit 2 into an allow. A status sentinel (`exit 7`) fixed those and made `exit 7` the new hole, plus an errexit hook shell ending every hook (seat D); a stdout sentinel inside the `if` brought the `set -e` hole back. Measured on 14 helpers x dash, bash and bash --posix, the shipped form had every cell run dart once and keep exit 2: it prints `ok`, runs in a plain assignment, and sources with `;`. Permanent mutants in the META group of `claude_hooks_cwd_independent_test.dart` prove each row fires: M22 (the old form, C14 under both shells), M23 (`&&` after the `.`, C14 under bash; dash survives that helper either way), M24 (the status sentinel, C14 under both shells) and M25 (`|| :` on the assignment, C14 under bash).

**Survivors of the first run, and what was done (not hidden).** Five mutants of 54 stayed green, all in signal handling, because the launcher rows saw the status through the wrappers' clamps or sent a single signal:
- the `got` clause of the retry condition: killed by a new row where a child answers TERM with 254 (no note, no backoff);
- the `kill -0` loop: the re-wait covers one signal, so a second TERM is what needs the loop; a new row sends two;
- the re-wait: `kill -0` covers a live child, so a child already REAPED is what needs it; a new row holds the handler open with a shimmed `kill` until the shell has reaped the child;
- `-ne 127` to `-eq 127`: a new row kills the child from outside and asserts the unclamped 143 of `run_dart_cli` itself;
- `land_pr`'s `stop:`: the first version of the row sent TERM during the last git call, and `sg` caught it before the gate ran, which its own check ("the gate must really have lost the race") reported. The row now
  uses a FIFO as the yaml, so a real dart is held inside its read while the signal lands, then exits a real 254.

**Six kills of the first run were not clean and were re-proven.** They hit the driver's 540 s limit, because every row waited out its own 30 to 45 s deadline for a marker the mutant never produces. A timeout is not a
red, so each was re-run narrowed to the row that names the behaviour, and each then failed by assertion: 254 to 255, the backoff removed, the handler's kill removed, the trap removed, the plain child in `land_pr.sh`, the plain
child in `sync_with_main.sh`.

**Not mutated and stated:** the duration of the 1 s backoff is pinned through the argument logged by the stub sleep.
