# OI-384: Claude Code hooks fail open when the session shell sits in a subdirectory (v4.1)

Branch `hook-cwd-fail-open`, from `main` `c54e63ba` (includes PR #139). Execution mode (CLAUDE.md 4.12.7): **inline, one
worktree, one coordinator.** Tier: **platform** (`.claude/settings.json`, `scripts/git_safety_hook.dart`);
`scripts/retire_worktree_lib.dart` is `feature`. So: x2 plan review, B-pass, plan-review record at the merge. No hermes
(below catastrophic). Diagnose id `8f3e35`, FULL template (the retirement half is a recurrence class).

Founder decisions: 2026-10-21 "ok" to fix the retirement block with a tool fix (option 1), then "ok" to the widened
scope: the hooks themselves, the retirement list, a test that runs every hook command from a subdirectory, and a
diagnose-doc with a transcript audit. Commit, push and merge are each a separate go.

## 1. Facts (verified 2026-10-21)

F1. Nine hook entries in `.claude/settings.json` (`:12, :20, :28, :38, :49, :58, :67, :77, :87`), SEVEN distinct
    commands: `check_alerts` (SessionStart, no flags), `discipline_hook` (SessionStart, UserPromptSubmit, PreToolUse
    Skill), `reconcile_ci` (SessionStart), `git_safety_hook` (PreToolUse Bash), `memory_write_guard_hook`
    (PreToolUse Write|Edit), `batch_close_hook` (Stop), `session_release` (SessionEnd). All relative:
    `dart run [--verbosity=error] scripts/<name>.dart`. No `settings.local.json`.

F2. The harness runs a hook in the session's CURRENT directory, which follows the Bash tool's persistent `cd`.
    - Claude Code hooks docs (code.claude.com/docs/en/hooks, read 2026-10-21): "Handlers run in the current directory
      with Claude Code's environment"; the command string goes to "`sh -c` on macOS and Linux, Git Bash on Windows, or
      PowerShell when Git Bash isn't installed"; `CLAUDE_PROJECT_DIR` is exported as the "project root where the
      session started" and "does not change if Claude enters a worktree"; the JSON payload arrives on stdin and its
      `cwd` field is the "Current working directory when the hook is invoked".
    - Measured 2026-10-21 17:09 UTC: one Bash call ran `cd <primary>/supabase/functions`; the NEXT call's PreToolUse
      hook rewrote `<primary>/supabase/functions/.dart_tool/native_assets.yaml` (mtime 17:09:49.743; the call printed
      17:09:50.163). By hand from that directory, `echo '{}' | dart run --verbosity=error scripts/git_safety_hook.dart`
      prints ``Could not find file `scripts/git_safety_hook.dart` `` and exits **255**, and rewrites the same file;
      with an absolute script path it exits 0 and STILL writes `<cwd>/.dart_tool/native_assets.yaml` (dartdev writes
      it into the current directory).
    - The B2a worktree's copy was written 2026-10-21 07:49:38.857, 78 ms after a Bash call whose predecessor had
      `cd`-ed into `supabase/functions`. The primary's copy dates from 2026-10-03.

F3. Exit codes (same docs): PreToolUse / UserPromptSubmit / Stop: 0 = proceed, **2 = block**, any other non-zero =
    "non-blocking error, the action goes ahead". So from a subdirectory every hook is skipped: `git_safety_hook`
    (its block is `exit(2)`, `scripts/git_safety_hook.dart:67`), `memory_write_guard_hook` (warn-only),
    `discipline_hook`, `batch_close_hook`, `session_release`, `check_alerts`, `reconcile_ci`. Git's own hooks are
    unaffected. **`/bin/sh` here is dash, and dash's failed `cd` exits 2** (measured: `sh -c 'cd /nonexistent && …'`
    exits 2, bash exits 1): a naive `cd X && dart …` prefix would turn a missing root into a BLOCK of every call.

F4. Retirement: `retire_worktree.dart:288` runs `git status --porcelain --ignored=matching` and counts every `!!`
    path that `isRegenerableIgnored` (`retire_worktree_lib.dart`, exact match against `regenerableIgnoredPaths`,
    `:237`) rejects. git collapses the stray directory to one entry, `supabase/functions/.dart_tool/`; only the root
    `.dart_tool/` is listed. Exact matching is deliberate (three review rounds each found a P0 from looser matching,
    comment above the list) and `retire_worktree_lib_test.dart:277` pins `vendor/.dart_tool/` as NOT regenerable.
    `gitignore_classification_test.dart` requires each literal `.gitignore` line to sit in exactly one list and the
    lists to be disjoint; it does not require a list entry to be a `.gitignore` literal.

F5. Transcript audit (heuristic; `scratchpad/hook_cwd_audit.py`, its output copied into the diagnose-doc): 19 session
    transcripts, about 253 Bash calls issued while the persistent shell sat in a project subdirectory. The only two
    matching a risky git pattern (commit, push, reset --hard, clean -f, rebase, merge, the bypass flag, `gh pr merge`)
    are Python heredocs whose TEXT mentions `git commit`; neither ran git. No raw git landing through the unguarded
    window was found. A pattern match over `cd` tokens, not a proof.

F6. Bug history: no INDEX entry for hooks and the working directory. The retirement symptom is the FIFTH of its class
    ("a tool writes into the worktree, retirement refuses"): f2a9c7 (test output, OI-128), b4d7e9
    (`.batch_close_state`), a9c4f2 (`.ci_reconcile_pending.jsonl`), the `.gate_failures.log` entry (recorded in the
    lib as the fourth, no own id). Each was fixed by an exact list entry.

F7. Readers of the hook command strings: `test/scripts/reconcile_ci_wiring_test.dart:47`
    (`contains('scripts/reconcile_ci.dart')`, still satisfied by the new form); `.claude/skills/audit-claude-config/
    SKILL.md` step 2.4 resolves each hook's script path. No doc quotes a full command string. `.opencode/plugins/
    discipline.ts:87-154` invokes its own scripts with an explicit root cwd and is unaffected.

F8. A second instance of the same defect INSIDE `git_safety_hook.dart`: its advisory plan-review precheck builds
    `File('$cwd/$scriptPath')` and runs it with `workingDirectory: cwd`, where `cwd` is the payload's `cwd` (`:110`,
    `:206`, `:211`). From a subdirectory the precheck is silently skipped.

F9. A NESTED repository defeats `--show-toplevel` alone: `vendor/` is a gitignored clone (`.gitignore:203`); from inside
    it the toplevel is the clone, which has no `scripts/`.

F10. Process-relative paths: only `reconcile_ci.dart` (`:70`, `:79`, `:194-196`, its `.claude/...` state file) and
    `check_alerts.dart` (`:37`, `.claude/.alerts.env` and `.env`). `batch_close_hook.dart` derives its root from
    `git rev-parse --show-toplevel` (`:187`) and uses `$root/...` (`:196`, `:236`); `discipline_hook` and the
    plan-review gate also use `git rev-parse`; `git_safety_hook` reads `cwd` from stdin. Running every hook from the
    checkout root changes nothing any of them does at the root.

## 2. Design

### 2.1 Every hook command runs from the checkout that holds its script

Each of the nine commands becomes (shown for `git_safety_hook`; `check_alerts` keeps no flags):

```sh
r=$(git rev-parse --show-toplevel 2>/dev/null); [ -n "$r" ] && [ -f "$r/scripts/git_safety_hook.dart" ] || r="${CLAUDE_PROJECT_DIR:-.}"; cd "$r" || exit 1; dart run --verbosity=error scripts/git_safety_hook.dart
```

- From any subdirectory of a checkout, the checkout's root wins; a linked worktree resolves to the WORKTREE root, so
  a worktree session still runs its own copy, exactly as it does today from the root.
- A nested repository without the script (F9), no git, or a directory outside any repository: the harness's
  `CLAUDE_PROJECT_DIR` (the session's start root), else `.` (today's behaviour).
- `cd … || exit 1`: a missing root is a NON-blocking error (1), never dash's 2 (F3).
- The last command is `dart`, so its exit code is the hook's: the git-safety hook's 2 still blocks.
- `$(…)` and `[ … ]` do not read stdin, so the payload reaches `dart`.
- `[ -n "$r" ]`: an empty toplevel (no git) never tests `/scripts/<name>.dart` at the filesystem root.
- `native_assets.yaml` now lands in the root `.dart_tool/` (regenerable).
- Shells: POSIX `sh` (dash on Linux, macOS sh) and Git Bash on Windows. Without Git Bash, Claude Code falls back to
  PowerShell and this form does not parse there (non-blocking error, hooks skipped). The repo's git hooks already
  require Git Bash on Windows (hooks.md:7, FRESH_CLONE.md), so the dependency is not new; stated in hooks.md.
- Cost: the prefix measured 2.3 ms per call (20 runs from `supabase/functions`), against a ~0.5-2 s dart start.
- Exposure (stated in hooks.md, unchanged in kind): after the session `cd`s into ANY checkout that holds
  `scripts/<hook>.dart`, the hooks run THAT checkout's script. This was already true at such a checkout's root; it now
  also holds from its subdirectories. `CLAUDE_PROJECT_DIR`-first would avoid it but would make a worktree session run
  the primary's copy; §4.13's flow (start in the primary, `cd` into a worktree) relies on the worktree's own copy.
- NOT in scope (stated): routing through `scripts/_dart_bin.sh` (hooks.md: a separate decision); making a CRASHING
  hook fail closed (a compile error would then block every Bash call, including the fix; hooks.md's fail-open rule).

### 2.2 `git_safety_hook.dart` precheck resolves the checkout root (F8)

Add a pure `precheckRoot(String cwd, {required String scriptPath, required String? Function(String cwd) toplevel,
required bool Function(String path) fileExists})` to `scripts/git_safety_lib.dart` (pure and git-free by its own
header, so both the git call and the file check are injected; `scriptPath` is the hook's own `:205` constant, passed
in so the two cannot drift): the toplevel of `cwd` when it holds `scriptPath`, else `cwd`. The hook's `toplevel`
closure runs `Process.runSync('git', ['rev-parse', '--show-toplevel'], workingDirectory: cwd)`, returns its
`stdout.trim()` on exit 0, and returns null on a non-zero exit or a `ProcessException` (a deleted cwd); the hook uses
the result for BOTH the existence check (`:206`) and `workingDirectory` (`:211`).
Still advisory and fail-open. Side effect: the precheck's own `dart run` then writes `native_assets.yaml` into the
root `.dart_tool/`, not the subdirectory.

### 2.3 Retirement list: one exact entry

Add `supabase/functions/.dart_tool/` to `regenerableIgnoredPaths` (dartdev's per-directory cache, written by any
`dart run` issued from `supabase/functions`, which the author's own sessions `cd` into for the Deno tests; CI runs
deno from the root, `test.yml:235`; ignored by `.gitignore:29` `.dart_tool/`, measured with `git check-ignore -v`). Content: the 171-byte `native_assets.yaml` and an empty `native_assets/`; no
`pubspec.yaml` lives there. Exact match kept; `vendor/.dart_tool/` stays precious. A point fix by design: another
subdirectory (`scripts/`, `lib/`, `test/`) entered by hand for a `dart run` would still keep a worktree, which is the
list's stated trade ("inertness is recoverable"). Also replace the stale "six entries" count in the comment at `:230` (the list holds 21 today) with wording that
does not go stale. The concrete need: strays ALREADY on disk (the B2a worktree's, the primary's since 2026-10-03), and
a session's own `cd supabase/functions && dart run …`, which 2.1 does not cover.

### 2.4 Docs

- `docs/architecture/hooks.md`: a row "Claude Code hooks run from the checkout root" (F2, F3, the command form, the
  shell dependency including the PowerShell-without-Git-Bash regression, the exposure note, the cost, the test).
- `docs/playbook/common-pitfalls.md` and a condensed root CLAUDE.md §4.9 row: a guard registered by a path relative
  to the current directory fails open, silently, when the directory moves. Re-record the context-artifact budget.
- `.claude/skills/debugging/bug-classes.md` + index row: that class, with this diagnose id and the test path.
- `.claude/skills/audit-claude-config/SKILL.md` step 2.4: resolve the script from the `scripts/<name>.dart` token of a
  compound command; QUOTED interpolation (`"$r"`, `"${CLAUDE_PROJECT_DIR:-.}"`) is the expected form, only unquoted
  interpolation is the P0 (`:67`); flag any hook command that is relative to the current directory.
- `docs/audit/open_issues.md`: OI-384 filed and closed by this batch (archived to `closed_issues.md`).
- Diagnose-doc: F2-F10 evidence, the `.opencode` check, the audit script and its output, the cost measurement.

## 3. Tests (each protection names the mutant that must redden it)

### 3.1 Structure: behaviour checks are functions of a command string

New `test/scripts/claude_hooks_cwd_independent_test.dart`: file-level `@Timeout`, `library;`, `skip: Platform.isWindows` on
the SPAWNING groups only (precedent `discipline_hook_main_sync_e2e_test.dart:280`; C1/C2 spawn nothing and run everywhere); spawns only through `runSpawn` / `runSpawnWithInput`
(`test/helpers/spawn.dart`; raw `Process.run` is banned by `spawn_sites_guard_test.dart`; the stub is made executable
with `runSpawn('chmod', ['+x', …])`); every scenario passes `remove: {'CLAUDE_PROJECT_DIR'}` unless it sets it;
`GIT_CEILING_DIRECTORIES` (a `resolveSymbolicLinksSync()` path) through `allowControl`; no `Platform.environment[...]`
read except `PATH` (classified `_kept`); directories compared after `resolveSymbolicLinksSync()`; no `command -v` /
`which` (guard G4a, `spawn_sites_scan.dart:23-24`).

The ONE thing `setUpAll` checks is SAFETY, not shape, as a rule `safetyViolations(command)`:
- the only command substitution allowed is `$(git rev-parse <--flag> 2>/dev/null)` (any single `--flag`, so M5b's
  `--git-common-dir` passes); any other `$(` or a backtick is a violation;
- the command is split on `;`, `&&`, `||`; each segment's first word must be one of: an `r=` assignment whose value is
  that substitution, `"${CLAUDE_PROJECT_DIR:-.}"` / `"${CLAUDE_PROJECT_DIR}"` / `"${r%<suffix>}"`, `[`, `cd`, `exit`,
  `true`, `dart`;
- redirections allowed: `2>/dev/null`, `</dev/null` only;
- at least one segment is `dart run … scripts/<name>.dart`.
That rejects a future hook that runs a real program (e.g. `sh scripts/x.sh`, `[ -f "$(sh x)" ]`). A META loop asserts
`safetyViolations` is EMPTY for every mutant string M1-M12 (so the permissiveness is tested, not prose) and NON-empty
for `sh scripts/x.sh` and the `$(sh x)` case. A mutant therefore reaches the behaviour assertions instead of stopping
the file (round 3 P1).

Each behaviour check is a function `List<String> checkX(String command, {required String script, …})` that returns
violations. The REAL tests apply every check to every command in `.claude/settings.json`. META tests apply the same
checks to synthetic mutants of the template (the `spawn_sites_guard_test` pattern) and assert each mutant yields a
violation from its NAMED check, so the kill is part of the suite, not only a hand run. The hand mutation run (rule 21)
then edits `.claude/settings.json` itself and records which tests redden.

Fixtures: a stub `dart` first on PATH (a shell script; every path baked into its text is SINGLE-quoted) writes its
`pwd -P`, its last argument, FOUND/MISSING for that argument relative to its cwd, and its whole stdin into files in
its own temp dir, then exits with a code baked into it. A FRESH stub and record directory is created for EVERY spawn
(each shell, each exit code), so a record can never be left over from an earlier spawn. Every scenario that expects the stub to run asserts its record
file EXISTS. Shells: `sh` and `/bin/bash`; on Linux both are REQUIRED (`/bin/bash` must exist, not silently skipped),
and the dash-only kill (M4b) asserts its precondition on the SAME `sh` the test spawns (resolved from PATH by the
helper, then `resolveSymbolicLinksSync()` ends in `dash`) or skips that one expectation with the reason. Three checkouts, all `git init` under a temp path containing a SPACE (the founder's Windows path is
`C:\Upendra\Claude Code\Fitness App`, `discipline_hook.dart` ~:147), each holding an empty `scripts/<name>.dart` for
every hook script: `A` (the "repo"), `D` (a DECOY used as `CLAUDE_PROJECT_DIR`, so the rev-parse arm and the fallback
arm give DIFFERENT answers), and `W`, a linked worktree of `A` (A's `scripts/*.dart` are COMMITTED in the seed commit,
`-c user.name=t -c user.email=t@t -c commit.gpgsign=false`, so `W` checks them out; C8 also asserts W's script files
exist before running, so it cannot silently fall to `D`). Plus `X`, a non-repo directory with a space, under `GIT_CEILING_DIRECTORIES`.

### 3.2 Checks and their mutants

- C1 wiring (real only): the parsed hooks equal EXACTLY the nine (event, matcher, script) triples of F1. M11 (swap the
  scripts of PreToolUse Bash and Write|Edit; or delete one entry): red.
- C2 shape (real only, an ordinary test): every command matches the 2.1 template exactly, the same script name in its
  two places, `--verbosity=error` on all but `check_alerts`. Every mutant below also reddens C2; the attribution that
  matters is the behaviour check named with it.
- C3 subdirectory: from `A/sub dir`, payload on stdin, under both shells: stub ran, FOUND, last argument is
  `scripts/<name>.dart`, cwd `A`, stdin equals the payload. Also from `A` itself (the common case). Real tests also run
  it from the REAL repo root's `supabase/functions` with the repo's own scripts (if `git rev-parse` fails there, the
  test fails with that message rather than a bare MISSING). M1 (the relative form): red. M9
  (`</dev/null` before `dart`): red on stdin. M12 (unquoted `$r` in `[ -f ]` and `cd`): red (the space).
- C4 fallback: from `X` with `CLAUDE_PROJECT_DIR=D`: FOUND, cwd `D`. M2 (drop the `CLAUDE_PROJECT_DIR` arm): red.
- C4b no fallback: from `X`, `CLAUDE_PROJECT_DIR` removed: the stub runs in `X` and reports MISSING; exit is the
  stub's. M2b (drop `:-.`): EQUIVALENT under dash and bash (measured: `cd ""` stays put, exit 0); stated, not claimed.
- C5 exit code: stub exits 2, 0, 1: the command's exit equals the stub's, under both shells. M3 (`|| true`): red.
- C6 missing root: from `X` with `CLAUDE_PROJECT_DIR=<X>/missing dir`, `stdin: ''` (the child exits before reading;
  `runSpawnWithInput` does not guard a broken pipe), both shells: exit exactly 1, stub NOT run. M4 (`cd "$r"; dart …`):
  red under both. M4b (`cd "$r" && dart …`): red under dash only (exit 2); bash exits 1 there too.
- C7 checkout beats fallback: from `A/sub dir` with `CLAUDE_PROJECT_DIR=D`: cwd `A`, not `D`. M5 (the rev-parse arm
  replaced by `CLAUDE_PROJECT_DIR` alone): red.
- C8 linked worktree: from `W/sub dir` with `CLAUDE_PROJECT_DIR=D`: cwd `W` (not `A`, not `D`). M5b (`git rev-parse
  --git-common-dir`-based root, i.e. the primary): red.
- C9 nested repo: a nested `git init` directory without `scripts/` inside `A`; from inside it with
  `CLAUDE_PROJECT_DIR=D`: FOUND, cwd `D`. M8 (drop the `[ -f … ]` check): red.
- C10 empty toplevel: dropping `[ -n "$r" ]` is EQUIVALENT in behaviour on any normal filesystem (with `$r` empty the
  test becomes `[ -f /scripts/<name>.dart ]`, false, so the fallback runs anyway); stated like M2b, not claimed. The
  same guard in `precheckRoot` IS testable by injection (3.3).
- C11 real guard end to end: the REAL `git_safety_hook` command from `.claude/settings.json`, run under `sh` with the
  REAL `dart` (no stub) from the real repo's `supabase/functions`, payload = a PreToolUse Bash call whose command is a
  raw git commit: exit 2 and `[git-safety] BLOCKED` on stderr. (The hook DOES run git against the payload `cwd`: it waives a raw commit while MERGE_HEAD / CHERRY_PICK_HEAD / REVERT_HEAD exists there. So the payload `cwd` is the non-repo fixture `X`, never the live repo; the shell still starts in `supabase/functions`. B-pass P1, 2026-10-21; same trap as b7e4c2.)
  Under the OLD relative form the same run exits 255 (T-control for the end-to-end path).
- T-control: the OLD relative form run through C3 from a subdirectory reports MISSING (the check can see the bug).

### 3.3 git-safety precheck (2.2)

`test/contracts/git_safety_lib_test.dart`: `precheckRoot(cwd, scriptPath: …, toplevel: …, fileExists: …)` from a
subdirectory returns the toplevel; toplevel lacking the script returns `cwd`; git failure (null) returns `cwd`; an EMPTY
toplevel with `fileExists: (_) => true` returns `cwd` (the helper rejects an empty string). M10 (return `cwd`
unconditionally): red. M10d (drop the empty-string rejection): red.

`test/contracts/git_safety_hook_integration_test.dart`, a new case through the REAL hook (its `runHook` precedent,
`:111-119`), `skip: Platform.isWindows` (git prints `C:/…`, temp may be 8.3-short): a temp `git init` repo (path
with a space) holding a stub `scripts/check_plan_review_record_exists.dart` that prints `ROOT=<Directory.current.path>`
and exits 1, and a subdirectory `sub/`; payload `cwd` = `<repo>/sub`, command `sh scripts/safe_push.sh`
(push-shaped: `git_safety_lib.dart:386-397`). Assert exit 0 and that `hookSpecificOutput.additionalContext`
(`git_safety_hook.dart:76-81`) carries `ROOT=<repo>` (resolved); stdout is asserted non-empty before `jsonDecode`, so
M10a reads as a clean failure. A second case with payload `cwd` = `<repo>` itself (the root) carries the same ROOT. M10a (existence check back to `File('$cwd/…')`):
red (no context). M10b (`workingDirectory: cwd`): red (dart's "Could not find file", not ROOT). M10c (no `.trim()` on
git's stdout): red (the file check fails on the trailing newline). Today no test covers the precheck at all.

### 3.4 Retirement list

`test/scripts/retire_worktree_lib_test.dart`: `supabase/functions/.dart_tool/` is regenerable; near-misses stay
precious: `supabase/.dart_tool/`, `supabase/functions/x/.dart_tool/`, `supabase/functions/.dart_tool/native_assets.yaml`,
`supabase/functions/.dart_tool` (no slash), and the existing `vendor/.dart_tool/`. M6 (remove the entry): red; M7
(`endsWith('/.dart_tool/')`): red on `vendor/` and `x/`. `gitignore_classification_test.dart` and
`reconcile_ci_wiring_test.dart` must stay green.

### 3.5 Live check after the merge (no network, no DB)

Once the primary's `main` is fast-forwarded. This session loaded the PRIMARY's `.claude/settings.json` at start, and
whether the harness re-reads it mid-session is not established, so the check may need a new session started in the
primary. A hook runs BEFORE a Bash call, in the directory the PREVIOUS call left, so every step is its own call:
1. Call A: `cd <worktree>/supabase/functions`, then (same call, after that call's own hook ran in the old directory)
   record the BASELINE mtimes of `<worktree>/.dart_tool/native_assets.yaml` and
   `<worktree>/supabase/functions/.dart_tool/native_assets.yaml` (if present). Call B: read them again. PASS = the
   worktree ROOT's file moved (measured 2026-10-21: a `dart run` at a checkout root moves that root's file) and the
   subdirectory's did not.
2. Call C (same directory): `git commit --dry-run -m probe`. PASS = `[git-safety] BLOCKED` (the guard denies any raw
   `git commit`, `git_safety_lib.dart:337`, no dry-run exemption; harmless if it did not run: `--dry-run` writes
   nothing and runs no hooks).
3. The `CLAUDE_PROJECT_DIR` arm is NOT exercisable live: the harness resets the shell when a `cd` leaves the project,
   and there is no nested repository inside the project (`vendor/` is absent on this VPS). It is covered by C4 and C9;
   stated, not claimed.
4. Windows (Git Bash) is unverified here; a founder check is added to the OI-348 post-build list: in a session on the
   Windows clone, `cd supabase/functions`, then a raw `git commit --dry-run -m probe` must print `[git-safety] BLOCKED`.

## 4. Order

1. Plan review: rounds 1-4 done; round 4 converged (no P0/P1); v4.1 folds round 4's P2/P3 items (mechanical).
2. Build 2.1-2.4 and the tests; mutants M1-M12 and M10a-d confirmed applied (`grep -c`) and run; full gate loop
   (`flutter analyze lib/`, full `flutter test` with TZ=Asia/Kolkata, pre-commit loop).
3. B-pass; record; commit (founder go); push, PR, gate replay, merge (founder go).
4. Post-merge: the live check in 3; then retire the B2a worktree (`--execute oi341-piece-b2-door`) and this one.

## 5. Review round 1 dispositions (v1 -> v2)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | dash `cd` failure exits 2 (blocking); T6 too weak | Measured (F3); `cd "$r" \|\| exit 1`; T6 asserts exactly 1 + stub not run; M4/M4b |
| 2 | P1 | Harness shell unestablished, Windows | Docs quoted (F2): sh -c / Git Bash / PowerShell fallback; dependency stated (2.1); T2 runs under sh and bash; Windows skip stated |
| 3 | P2 | Linked worktree not pinned | T8 |
| 4 | P2 | `:-.` arm unpinned; ambient CLAUDE_PROJECT_DIR | T4b + measured M2b; `remove` in every scenario |
| 5 | P2 | stdin passthrough untested | stub records stdin; T2 + M9 |
| 6 | P2 | nested repo defeats `--show-toplevel` | script-existence check in 2.1 (F9); T9 + M8 |
| 7 | P2 | test would trip spawn gates / env scan / symlinks / Windows | `runSpawnWithInput`, `allowControl`, no env reads, `resolveSymbolicLinksSync`, `skip: Platform.isWindows` |
| 8 | P2 | wiring not pinned per event; unknown commands executed | T1 exact triples + T1b exact shape; M11 |
| 9 | P3 | distinct-command count | F1: seven |
| 10 | P3 | prior instance ids | F6 corrected; fifth instance |
| 11 | P3 | git_safety precheck uses stdin cwd | FIXED in this batch, not only stated (2.2, F8, M10) |
| 12 | P3 | rationale wording, stale count, skill 2.4, budget, `.opencode`, audit output, cost | 2.3 wording + `:230` count; 2.4 docs list; cost measured (2.1) |

## 6. Review round 2 dispositions (v2 -> v3)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | precheck call sites unprovable; helper-only test; lib is git-free | Real-hook integration case + M10a/M10b; helper takes injected `toplevel` and `fileExists` (2.2, section 3) |
| 2 | P2 | quoting pinned only textually; founder's path has spaces | temp paths with a space (section 3) |
| 3 | P2 | T6 stdin broken-pipe race | `stdin: ''` in T6 |
| 4 | P2 | live check weaker than claimed; CLAUDE_PROJECT_DIR arm and real harness shell untested | two `git commit --dry-run` guard probes after the merge (section 3) |
| 5 | P3 | M4b dash-only | stated; T6 runs under both shells; dash arm is the kill |
| 6 | P3 | FOUND does not identify the script | stub records the last argument; T2 asserts it |
| 7 | P3 | "only the stub runs" depends on ordering and PATH | shape check in `setUpAll`; stub-ran assertion; no `command -v`/`which` |
| 8 | P3 | F10 partly wrong | F10 corrected |
| 9 | P3 | untrusted-checkout exposure | stated in 2.1 and hooks.md; rev-parse-first kept for §4.13 |
| 10 | P3 | root start dir; 2.3 reasoning; count 21; PowerShell | T2 adds `<root>`; 2.3 reworded with `git check-ignore`; count wording; hooks.md |

## 7. Review round 3 dispositions (v3 -> v4)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | `setUpAll` shape pin stops the file, so no behavioural assertion is ever shown to kill a mutant | `setUpAll` checks only SAFETY (a vocabulary every mutant passes); shape is an ordinary test; behaviour checks are functions of a command string with in-suite META mutants (3.1) |
| 2 | P2 | `<root>` ambiguous; T7 cannot tell M5; unquoted mutant unnumbered | Three checkouts A, D (decoy fallback), W; C7/C8 use `CLAUDE_PROJECT_DIR=D`; M12 numbered (3.1, 3.2) |
| 3 | P2 | closure needs trim + ProcessException; scriptPath duplicated | 2.2 spells both; `scriptPath` passed in; M10c |
| 4 | P3 | Windows path compare in the integration case | `skip: Platform.isWindows` (3.3) |
| 5 | P3 | probe 1 cannot isolate the rev-parse arm; one call per probe | mtime discriminator on the worktree root; one call per step (3.5) |
| 6 | P3 | chmod, bash required on Linux, dash precondition, resolved ceiling, single quotes | all in 3.1 |
| 7 | P3 | audit skill would flag quoted interpolation as P0 | 2.4 wording |
| 8 | P3 | empty `$r` tests `/scripts/…` | `[ -n "$r" ]` in the template; C10 META |

## 8. Review round 4 dispositions (v4 -> v4.1, round 4 verdict: converged)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | safety vocabulary not implementable; permissiveness only prose | written as a rule (3.1) + META loop asserting it accepts M1-M12 and rejects two real-program cases |
| 2 | P2 | C10 cannot be behavioural | declared equivalent like M2b; the helper's empty-string guard tested by injection (M10d) |
| 3 | P2 | stub record lifetime | fresh stub + record dir per spawn (3.1) |
| 4 | P2 | live check: baseline, root-mtime assumption, step 3 vacuous, Windows | baseline in the `cd` call; root mtime MEASURED; step 3 stated not exercisable (no nested repo, harness resets out-of-project `cd`); Windows to OI-348 (3.5) |
| 5 | P2 | unit too large, split 2.3 / 2.2 / 2.1 | founder decision (asked 2026-10-21); the review loop has converged, so the split is a delivery choice, not a convergence fix |
| 6 | P3 | "three places"; section 4 text; C1/C2 Windows skip; same-`sh` dash check; W scripts; real-repo message; non-empty stdout + root case; git-fails-at-root fallback; real guard e2e | fixed in 3.1-3.3 and section 4; C1/C2 spawn nothing and are not Windows-skipped; git-fails-at-root fallback stated (the root form would then run `CLAUDE_PROJECT_DIR`'s copy, normally the same checkout); C11 added |
