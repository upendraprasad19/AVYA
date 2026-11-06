---
bug_id: b7e2d9
date: 2026-11-06
batch: oi468-spawn-status
status: fixed
tier: m_fix
blast_radius: feature
symptom: >-
  Eight CI failures of unit tests that spawn a child process, in three groups. GROUP A (five sightings, OI-311 and OI-468 sighting 1):
  a spawned `dart` exited 254, in four of them with `stderr=File not formatted as yaml: .` and `stdout=Running build hooks...Running
  build hooks...` (2026-10-13, 10-17, 10-19, 11-06: `dart run scripts/blast_radius_from_diff.dart` from the repo root) and in one with no
  text printed (2026-10-04, the sot gate test: `dart run <repo script>` with a temp git repo as the working directory). GROUP U (one,
  July 2026 `a7f3d1`): a plain `dart <script>` of a script copied into a throwaway repo exited 254; no mechanism found. GROUP B (two,
  OI-468 sightings 2 and 3): a spawned quiet `git` returned an exit status no process can return: `git push -q -u origin main` 1668163832
  (0x636e28f8, run 40178030547) and `git worktree add -q <dir> -b wt` 1752491432 (0x6874e5a8, run 41889308206), stdout and stderr empty.
  Every one passed on re-run and none reproduced locally. The same race also fits the parallel pre-commit gate loop on the VPS
  (memory `reference_vps_quirks.md` item 5: a different gate each time, six at once on 2026-11-06, each green alone), which is filed
  as its own OI (hook sites are platform tier).
concept: not_applicable — test-support spawn handling (the shared helper test/helpers/spawn.dart); no Hive/cloud writer-reader contract and no entry of docs/sot_registry.yaml covers it (c3f8e1 and e6c4a9 recorded the same).
sot_registry_entry: not_applicable — no writer/reader pair, Hive key or cloud table is involved.
related_bugs: [a7f3d1, e6c4a9, c3f8e1]
recurrence: |
  RECURRENCE of OI-311 (five sightings of the 254 family since 2026-10-04) and of the "spawn test hides its child's output" class
  (2.90, PR #79 / batch spawn-tests-env-and-stderr, e6c4a9). Those batches made the failing spawn PRINT its output; this one explains
  the 254 family and contains it. a7f3d1 is cited as the same symptom whose mechanism does NOT match (its script reads nothing of the
  repo's `native_assets.yaml`); it stays unexplained.
writers:
  - { file: test/helpers/spawn.dart, method_or_widget: "retryingSpawn / retryingSpawnAsync: the loop that decides, per attempt, whether a finished child's answer is the harness's failure, reports every attempt and returns the last result", line: 245 }
  - { file: test/helpers/spawn.dart, method_or_widget: "spawnRetryDecision: the pure decision (race: dart exe + exit 254 + signature on stderr, budget 2; impossible status: outside -255..255 off Windows, budget 1)", line: 188 }
  - { file: test/helpers/spawn.dart, method_or_widget: "runSpawn / runSpawnAsync / runSpawnWithInput: the three entry points wired through the loops (stdin re-fed on every attempt)", line: 360 }
readers:
  - { file: test/contracts/blast_radius_sync_engine_platform_test.dart, method_or_widget: "the real CLI test: spawns `dart run scripts/blast_radius_from_diff.dart` (bare 'dart', runInShell, cwd = repo root) and asserts the printed tier: victim and writer of the race", line: 689 }
  - { file: test/contracts/sot_registry_citations_test.dart, method_or_widget: "runGateOn: `dart run <repo script>` with a temp git repo as cwd: a reader-only victim; its report-count pins read through finalAttempts", line: 240 }
  - { file: test/scripts/token_path_resolver_test.dart, method_or_widget: "_git / _repoWithLinkedWorktree: the group-B sighting 3 spawn (`git worktree add -q`)", line: 85 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/spawn_retry_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no user data.
forbidden_patterns_checked:
  - "a retry of ANY bare 254 — rejected: 254 is also a compile error (`dart run` exits 254 when the front end cannot load the script); the retry needs the signature text AND a dart executable"
  - "a retry of a `sh -c` wrapper that forwards a nested dart's 254 — rejected: the measurement that the child never reached `main` holds for the dart process itself; a wrapper may have done work first"
  - "rewriting `dart run <script>` to `dart <script>` at the sites — rejected: it removes writers, not victims (the plain form is still a reader), changes the command under test away from what the hooks run, and every helper dart victim is healed by the retry already"
  - "relocating the file with --packages — rejected: measured, `dart --packages=<elsewhere> run` still writes into the cwd package's `.dart_tool`"
  - "a retry that hides its evidence — rejected: every attempt is reported whole through the existing report channel and ONE `[spawn-retry]` line with the failed attempt's exit, time, stdout and stderr is printed with plain print before each retry, so it survives a passing test (OI-311's caution 'do not add a retry first' is superseded because the cause is measured)"
proposed_fix: |
  CAUSE, group A (measured 2026-11-06, SDK 3.11.1 = the Dart in CI's Flutter 3.41.4).
  (1) The text lives in the Dart front end: `File not formatted as yaml: ` is a string of its `NativeAssetsValidator` (grep -a -c gives 1 for
  dart-sdk/bin/dartvm and snapshots/kernel-service.dart.snapshot, frontend_server_aot, gen_kernel_aot, kernel_worker_aot; 0 for the
  `dart` launcher and dartdev_aot). Earlier searches read text files only.
  (2) WRITER: `dart run` only (never the plain form `dart <script>`), when the package found upward from its working directory has a
  build hook (`objective_c` is in the tree): it opens `<cwd>/.dart_tool/native_assets.yaml` with O_RDWR|O_CREAT|O_TRUNC and writes 171
  bytes (truncate to write 0.23 to 0.3 ms, the file EMPTY in between), then execs the VM. READER: any `dart` or `dart run` (plain form
  included): a front-end thread opens `<SCRIPT's package>/.dart_tool/native_assets.yaml` O_RDONLY 245 to 390 ms later and validates it,
  whatever the cwd. VICTIM: a reader that opens the file while any writer on the same file is between truncate and write: exit 254,
  stderr `File not formatted as yaml: .`, and (only when the cwd package ran the hook step) stdout `Running build hooks...Running build
  hooks...`. The writer's and the reader's file coincide only when the cwd IS the package root.
  (3) In the repo: the blast-radius CLI tests are victims AND writers (script and cwd both the repo root, `runInShell`, no
  workingDirectory); the sot test is a reader-only victim (cwd a temp repo, script in the repo: predicts the 10-04 empty stdout; its
  text was never printed, so that sighting is attributed, not confirmed). The fifth sighting's log shows
  blast_radius_progress_map_writer_paths_test.dart (the same spawn) running in the same second.
  (4) The child dies BEFORE `main`: a script whose first statement writes a marker file, run 12 times under a truncating process, gave
  9 exits of 254 and no marker after any of them (a reviewer's repeat: 11 of 12, none). So for the dart process itself a retry cannot
  repeat a side effect of the script.
  FIX. test/helpers/spawn.dart: `runSpawn`, `runSpawnAsync`, `runSpawnWithInput` run a child again in exactly two cases. (a) The child is
  the Dart executable (`isDartExecutable`: basename, lower-cased, minus one `.exe`/`.bat`/`.cmd`, equals `dart`), the exit code is exactly
  254 and the decoded stderr contains `File not formatted as yaml`: at most 2 retries. (b) The exit code is above 255 or below -255 and
  the platform is not Windows: at most 1 retry, any child. The decision (`spawnRetryDecision`, budgets per reason and independent, worst
  case 4 attempts), the note (`spawnRetryNote`) and the loops (`retryingSpawn`, `retryingSpawnAsync<T>`, seams `isWindows`, `clock`,
  `note`) are separate; every attempt is reported (attempt n>1 under `<label> [attempt n]`), the note is printed BEFORE each retry
  runs, the last result is returned. test/contracts/sot_registry_citations_test.dart reads its reports through `finalAttempts`
  (positional: an `[attempt N]` report replaces the report before it and loses the suffix), because that test spawns the group-A victim
  and a healed run would otherwise carry two reports with one prefix.
  GROUP B is NOT explained. A valid status is 0..255 (the SDK doc: -255..-1 for a signal); the harness' wait path returned a number the
  child did not produce; both values are multiples of 8, a hypothesis (a stale pointer-sized slot), not a cause. The retry cures an
  idempotent child (`git push`); for a non-idempotent child that really ran (`git worktree add`, `git commit`) it produces a second red
  with the child's own message ("already exists") or duplicates the effect: diagnosable, not necessarily green. A correct result is never
  changed. OI-468 Done-when branch 2 is claimed for the three result-returning helpers; `startSpawn` callers, wrapper children and nested
  spawns are not covered (ledger rows).
regression_test_planned: |
  - test/contracts/spawn_retry_test.dart (a file of its own: spawn_sites_guard_test allows exactly one raw Process.* and one unmatched
    startSpawn in spawn_helper_test.dart): `isDartExecutable` table; `spawnRetryDecision` table (each conjunct alone, near-miss texts,
    raw-bytes stderr, bounds 255/256/-255/-256 for any exe, Windows, per-reason budgets written as explicit rows); `spawnRetryNote` table
    (exact shape, hex of the unsigned 32-bit value, slots, escaping, the 300-character cut AFTER escaping at 299/300/301, raw bytes with a
    byte length); both loops against the SAME scripted children (race then ok, always-race = 3 attempts, lost then ok, lost-lost, the mixed
    sequence race/lost/race/lost = 4 attempts with suffixes 2 3 4, the event order once-report-note, per-attempt clock, mirrors, Windows,
    a thrown ProcessException, the default note via a zone); real children through each entry point (a Dart child that fails with the
    signature on its first run, marker file; stdin re-fed for a String and a List<int>; an always-failing child, self-limiting; a plain 254
    and the text with exit 1 run once; a `sh -c` wrapper is not retried; workingDirectory / runInShell / extraEnv / remove forwarded by the
    two async entry points); wiring pins (no isWindows/clock in the entry points, report before decision, last result returned).
  - test/contracts/spawn_helper_test.dart: the two body pins repointed to the new shape (each entry point hands ONE raw spawn straight to its loop).
  - test/contracts/sot_registry_citations_test.dart: `finalAttempts` at the seven report-count sites plus its own unit test.
  MUTATION PROOF (rule 21; scratchpad harness `mut468.py`: baseline asserted green first, every anchor confirmed present, each run under
  an OS timeout counted as a kill, a compile error NOT a kill, the mutated file compared byte for byte after each restore): 103 mutants, 103 red, 0 survived, 0 compile errors, 0 anchor misses, about 13 s each, re-run on the FINAL code after the diff review's fixes (the first run of 97 was also all red), each run against test/contracts/spawn_retry_test.dart plus test/contracts/spawn_helper_test.dart (the sot mutants S1 to S5c against the sot test, including three raw-read shapes for the widened report-count pin and an end-of-label suffix anchor; T1 sets the per-call timeout to 1 ms and reddens the real-child tests). Families: the decision (signature check dropped, exit-only, text-only, 254 widened to nonzero, stdout read instead of stderr in each loop, `contains` to `==`, the constant weakened to `yaml` and to `File not formatted`, the bounds 255/256, -255/-256, the lower clause dropped, `||` to `&&`, `> 254`, the Windows guard removed and leaked into the race, both budgets at 0, one too many, unbounded, shared and `<=`, both cap constants, the lost status limited to dart children); `isDartExecutable` (`contains`, `endsWith`, slash-only split, case-sensitive, each of `.exe` `.bat` `.cmd` not stripped, scope removed); each of the two loops separately (a counter not incremented, counters reset on a reason change, attempt suffix dropped or off by one, attempt 1 not reported, the note deleted, a note on a passing attempt, the default note a no-op, a cumulative clock, `isWindows` defaulting to true or forced true, the note slots swapped, the FIRST result returned instead of the last, a swallowed ProcessException); the note formatter (excerpt 299 and 301, cut before escaping, CR and LF unescaped, slots swapped, byte length counted as characters, the hex of a negative number, labels swapped, k and cap swapped, the label unescaped, the length of the cut text, the time shifted); the entry points, each of the three (unwired from the dart scope, the note not threaded, `isWindows` passed), `runSpawnWithInput` stdin fed only once or only the String re-fed, the accessors swapped or the exit accessor wrong; raw-bytes stderr cast; the report moved after the decision (killed by the source pin); the default note through `printOnFailure`; the sot `finalAttempts` keeping every attempt or keeping the suffix (killed by its unit test). Plus one manual mutant: a report-count site of the sot test reading the raw list again (the presence pin reddens). Not mutated, stated: the real race itself (it cannot be produced on demand through the helper), and the Windows branches (this VPS is Linux).
impact_analysis: |
  Test-support only (blast radius feature): no lib/ code, no Hive key, no cloud column, no Edge Function. A test that spawns a dart child
  and used to fail on the race now passes after at most two more attempts, with a `[spawn-retry]` line in the CI log; a test that spawns
  a child returning an impossible status now runs it once more. Value semantics (4.1.5.3): swept test/ for assertions on stdout containing
  `Running build hooks` and for tests that count spawns or deliberately produce a 254 with the signature text: none (tests that produce a
  bare 254 go through `sh` or a stub and are not retried). The report-count pins of the sot test are the only reader of the number of
  reports; spawn_helper_test's `reports.single` pins use children that exit 3, 7, 0, 4, 5 and are never retried.
  RESIDUE, each with a ledger row (docs/audit/oi468-spawn-status.closure.yaml): R1 `startSpawn` callers (the caller drives the streams),
  `sh -c` wrapper children and nested spawns are not retried (an exposed example: discipline_hook_main_sync_e2e_test.dart:241, a
  `startSpawn` of `dart run` on a repo script); R2 two limits of the COVERED path, stated in the helper header (a Dart script that itself spawns
  a nested `dart run` and forwards its status and stderr cannot be told from the race and would be run again; a stdin payload above the pipe
  buffer written to a child that already died on the race throws out of the stdin write, unretried, as before); no test spawns either today;
  group U unexplained; group B cause unestablished; the note is the only record of a retry and
  lives in a CI log kept about 90 days. The hook sites (`scripts/pre-commit.sh` 13 `dart run`, the parallel gate loop at :392 with its output
  discarded, `commit-msg.sh`, `prepare-commit-msg.sh`, `pre-push.sh`, `pre-merge-commit.sh`, the harness hooks) have the same race and are a
  separate platform-tier OI (tracker).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "test/helpers/spawn.dart (retry machinery), three test files; no lib/ change" }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "no client or server code is involved; the failing component is the Dart SDK's `dart run` start-up reading `.dart_tool/native_assets.yaml`" }
  - { tier: 11, name: "External services", status: verified, evidence: "the Dart SDK 3.11.1 front end (strings in dartvm and four snapshots), strace of `dart run` on this VPS, 3.41.4 is CI's Flutter pin (.github/workflows/test.yml); GitHub Actions job logs show `print` output of a passing test under `--reporter expanded` (saved shard log, test.yml:182)" }
---

# The `dart run` native-assets race and an impossible exit status in spawned test children (OI-468, OI-311)

## What was seen
Unit tests that spawn a child process failed in CI with an exit status that was not the child's answer, passed on re-run, and never
reproduced locally: eight times in 33 days, in three groups (see `symptom`).

## Cause (writers and readers by file:line)
Group A is a read-while-rewritten race on `.dart_tool/native_assets.yaml`, the file `dart run` rewrites in place (truncate, then write)
and every dart child reads while it starts. See `proposed_fix` for the strace facts. The helper side is `test/helpers/spawn.dart`
(`retryingSpawn` :245, `retryingSpawnAsync` :300, `spawnRetryDecision` :188); the victims are the spawn tests (the readers above).

## What was proven and what was not
- PROVEN: the message's origin; the writer/reader/victim model (strace, three cwd/script layouts in both directions, the subdirectory case);
  exit 254 with exactly the sightings' text from an empty file (40 of 40 under a truncating process, 8 of 8 reader-only); natural
  reproduction without any truncating process (1 of 265 and 1 of 554 `dart run` under load on a minimal package, 1 of 195 real gate scripts);
  the child never reaches `main` (marker, 9 of 9 and 11 of 11); `--packages` does not move the file; the plain form never writes.
- NOT proven: WHY it is rare (the writer descheduled inside the 0.3 ms window under load is an inference); the 10-04 sot sighting's text
  and its writer; the July `a7f3d1`; the cause of group B (the VM's wait path; source not available here).

## Repeatable commands (scratch package with `objective_c` as its only dependency; SDK 3.11.1)
- Message origin: `grep -a -c 'File not formatted as yaml' <dart-sdk>/bin/dartvm <dart-sdk>/bin/snapshots/*.snapshot`.
- Writer/reader: `strace -f -e trace=openat,write dart run bin/x.dart`, read the `native_assets.yaml` lines.
- Truncating process: re-open the file `O_TRUNC`, sleep 0.3 ms, write the content back, in a loop; run `dart run bin/x.dart` meanwhile.
- Before `main`: `bin/y.dart` whose first statement appends to `side_effect_marker`; delete the marker between runs under the truncating process.
- cwd/script: cwd with no pubspec + script in the package (reader-only); cwd = a subdirectory of the package (writer writes `<subdir>/.dart_tool/`).
- Natural: six loops of `dart run bin/x.dart` pinned to two cores with three busy loops on the same core, 100 s.

## Process
Plan `docs/plans/2026-11-06-oi468-spawn-status.md` (v5; four review rounds, seven fresh Sonnet passes), record
`docs/plan-reviews/oi468-spawn-status.md`. A bug-classes entry was added to `.claude/skills/debugging/bug-classes.md` (CLAUDE.md §5.1).
