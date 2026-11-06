---
plan: sync-resolver
revision: 4
date: 2026-10-26
base: 5794439a
blast_radius: platform
tier: L                  # adds a CLAUDE.md pointer (section 4.12.6: CLAUDE.md is L); the code is platform tooling
execution_mode: inline   # one worktree, one session
parent_plan: docs/plans/merge-conflict-treadmill.md (section 7, landing C, unit U5)
closes_oi: []            # OI-309 stays open for landing D (the merge train); this landing is its second-to-last step
landings: [C2]
---

# Landing C2: a record-aware resolver for the shared ledger files (U5, `scripts/sync_with_main.sh`)

C1 (PR #176) stopped the catastrophic review gate from re-grading main's content at a sync. C2 attacks what is left of
the cascade: the textual conflicts themselves. A branch that is behind `origin/main` is synced with `git merge
origin/main`; after A1 (tuning entry inside the review file) and A2 (indexes untracked) the files that still conflict
are append-only ledgers where both sides added DIFFERENT records at the same spot. Git sees overlapping insertions;
a human sees two independent records. This landing teaches a tool to see what the human sees, and to refuse when the
two sides really disagree.

## Revision history
- **rev 3 -> rev 4 (round 3, a delta round: two seats, both HARDEN on details, no P0 or P1 and no design defect; seat A 0 P1 + 7 P2 + 10 P3,
  seat B 0 P1 + 4 P2 + 8 P3; every item folded in):**
  - **Checks:** V-c cannot apply to a partial output (markers sit inside records), so it is clean-output only and a partial result is
    gated by V-a (interval form) and V-b (R3B-1); a record that one side deleted and the output KEPT passed all three checks, so V-a is
    now exact for a line that occurs at most once in each version (R3B-4); the false-positive corner of V-a is stated in full (R3B-5).
  - **Emission:** the last-record tail rule is conditional (it broke the byte-for-byte invariant on the one real board that ends in a
    blank line) and the invariant is scoped to appends (R3B-2); a lone CR is not a line break.
  - **Flow and state:** the tip is resolved to a SHA once and that SHA is merged, so a moving `refs/remotes/origin/main` cannot turn a
    committed merge into `refused` (A2); the "refused" row checks that nothing changed (A3); backups are ALWAYS taken before an overwrite
    (git's marker labels never equal the tool's own merge text, so the skip rule could not fire) in a lazily created run directory (A4);
    the direct-write fallback is removed: a failed rename is `left` (A14); the wrapper prints its own `result:` line, forwards
    TERM/INT/HUP and clamps without tripping `set -e` (A5, A6); `FileStat` for the millisecond mtime, `identity` written before the first
    temp write (A8); a `_finished` latch (A12); `protectedBranchReason` reused (A13).
  - **Tests:** the fetch-hang row uses the `b2f7e4` stub-`git` pattern (an `uploadpack` sleeper is a grandchild and survives the kill);
    rows added for every refusal, the fast-forward ordering, the read-only target directory, pruning, a failing `git add`, a
    `merge-file` failure, the child environment and a moving tip; the crash-state row is built from a second repository, not from
    `update-index --unresolve`; `tr` joins the E11 PATH; counts that did not match their enumerations are gone (R3B-8).
  - **Measurement wording:** rev 1 and rev 3 resolve the SAME 53 syncs; rev 2's refusal of the duplicate group cost `82844bfd`; the V-b
    rejection (`68843b8f`) sits in a sync that needs a human anyway (R3B-3); the board's 3 leftover syncs are old add/add collisions that
    pre-date `mint_oi.sh` and cannot recur, the changelog-shaped leftover is a prose bullet between the index and the changelog (R3B-7);
    157 -> 160 region merges, 95 of 111 -> 97 of 114 (R3B-8).
- **rev 2 -> rev 3 (round 2: two seats, both HARDEN, no P0; seat A 0 P1 + 6 P2 + 6 P3, seat B 1 P1 + 6 P2 + 7 P3; every item folded
  in). Round 2 found refinements of rev 2's NEW parts, none in the core decision table:**
  - **State machine (R2B-1, P1):** rev 2 decided "git refused to start" from an absent `MERGE_HEAD`, which is also what a merge git
    just COMMITTED looks like. Step 3 now has a full decision table over (`MERGE_HEAD`, HEAD moved, unmerged entries).
  - **Lifecycle of backups and records (R2B-2, -3, -4, -8, -11):** backups live outside the state directory and are never deleted by
    a fresh start; a file with NO marker line is never overwritten (hand-resolved, rerere without autoupdate); the no-op path still
    records and stages; the record identity uses milliseconds (Dart has no microsecond mtime); the temp file lives in the state
    directory, not beside the target; E8's kill is built from the post-crash disk state, not a race.
  - **Fetch (R2B-5):** `Process.run().timeout()` does not kill the child (diagnose `b2f7e4`); the fetch uses start / kill / drain and
    the explicit refspec, and has a hang-and-kill test.
  - **Fast-forward (R2B-6):** the pending-merge check comes first, a failed `--ff-only` is exit 2, old and new HEAD are printed, the
    branch prefixes `retire_worktree` protects are refused.
  - **Duplicate keys (F1):** rev 2 refused two CORRECT merges and misnamed the lost sync. A key that repeats is decided as a GROUP.
  - **Checks (F2, F3, F7, F10):** V-a's net-delta bounds have a documented false-positive corner (both sides delete the same record
    and each adds a record sharing a line, rejected safely) and a documented blind spot (twin lines of two added records); the
    partial-result form is an interval intersection; V-b states its normalisation and its blind spot (inside git's hunks); V-c is an
    emitter-fidelity check, not a splitter check; the "passes all three" evidence is for conflict-free merges only. The test contract
    no longer asserts what the checks cannot guarantee.
  - **Reorders (F6):** the "adopt theirs' reorder" mechanism had no use in 157 real region merges and had a measured ghost-anchor
    divergence; removed. A side that reordered shared keys makes the file unresolvable.
  - **Smaller fixes:** the first record starts at its first leader line (F4); the changelog keeps each bullet's own bytes and a
    trimmed-equal pair takes the side that differs from base, so a sync with an unchanged branch reproduces main byte for byte (F5);
    every row of a table region must match the row pattern (F8); `### N.M` also matches at end of line (F9); the trim rule names
    whitespace-only lines (F11); exit codes above 4 are mapped by the wrapper and there is one exit point (R2B-9); names and gate
    facts corrected (R2B-10); the child environment is the parent's plus one override (R2B-12).
- **rev 1 -> rev 2 (round 1: three seats, all HARDEN, no P0):** vacuous self-check replaced by three independent checks; emission
  keeps each record's own bytes; leaders for YAML comment blocks; write-once backups; the next step decided from git's state, never
  `git merge --abort`; `--commit` only for a merge this run started; exit codes 0-4; wrapper runs from its own directory; duplicate
  keys, fences, commas and region ends; builder runs alone; parent plan section 7/8 rewritten in this landing.
- **Alternative recorded (seat A, round 1):** resolving only the records that overlap git's own conflict hunks and splicing the result
  into git's output resolves 45 of 93 syncs against 53 for the whole-file record merge; not adopted (D9).

## 1. What goes wrong today

**Measured 2026-10-26** on `5794439a` (method in section 7; re-derived by four independent seats). The last 600 merges on
`origin/main` hold 448 merges that are not "Merge pull request" commits (branch syncs and branch-into-branch merges); replayed with
`git merge-tree --write-tree --name-only <m>^1 <m>^2`, **166 conflicted**.

| Question | Answer |
|---|---|
| Conflicted syncs cleared by A1 + A2 alone (every conflicted file is a tuning file or an index) | 73 of 166 |
| Remaining after A | 93 |
| Remaining syncs this design resolves COMPLETELY (no marker left, every conflicted file in the allow-list, all three checks of 4.4 pass) | **53 of 93** (prototype of THIS design; 55 once D4 handles the two syncs whose only leftover is `GATE_INDEX.md`; the as-built replay repeats it with the Dart tool) |
| Remaining syncs that still need a human | 40 (38 with D4) |

The first prototype (rev 1: no checks, duplicate keys paired by position) resolves the SAME 53 syncs (identical sets). Rev 2's refusal of
any changed duplicate group lost `82844bfd` (the migration ledger's duplicates 145 and 146); the group rule of this design gets it back.
One file merge is rejected by check V-b (`68843b8f`, the glossary's duplicate `**Photos hub**` group: a changed group is emitted at its
first occurrence's position, git kept the row where its second occurrence was), and that sync needs a human anyway (it also collides on
bug class 2.91).

What keeps the 40 conflicted, by SYNC (not by file hit): 14 touch a debugging file, and of those 9 are bug-class number
COLLISIONS in the index table, 10 in `bug-classes.md` (9 syncs hit both), 3 are the pre-split layout of `SKILL.md` the parser
rightly refuses, 1 a prose bullet between the index and the changelog; 1 more is a migration-number collision (`ef001508`, keys 145 and
146 added on both sides). So **11 of 40 syncs are live number collisions** (10 bug-class, 1 migration), which the tool must not hide.
The rest: `sot_registry.yaml` 5 (both sides moved the same `line_range` of code they both touched), `CLAUDE.md` 3, the board 3 (old
add/add number collisions from 2026-08, before `mint_oi.sh` existed on 2026-09-12; they cannot recur),
`context_artifact_sizes.json` 2, `skills-log.md` 2, `ship_dark_pending_review.yaml` 2, `live_schema_columns.json` 2, `GATE_INDEX.md` 2
(a builder output: D4 handles them), and one or two code or test files each.

Conflict shape in the ledgers (diff3 hunks of the 103 most recent conflicted syncs): the board has 37 hunks with an EMPTY base (both
inserted) against 5 with a base; `closed_issues.md` 11 against 0; `bug-classes.md` 16 against 0; the debugging index and changelog 20
against 2; naming 10 against 2; `applied_migrations.json` 7 against 0; the SoT registry 11 against 21 (19 of those 21 are
`line_range:` / `line:` numbers of code both sides edited, the other 2 a `line_range` of a different shape and a `method:` rename).

**Cross-check against what the humans did.** For the 73 file instances of the 53 resolved syncs, the rev-3 prototype's output was
compared with the file in the actual merge commit: 69 key sets agree, 4 differ (the human renumbered a colliding bug class in two
files of one sync, hand-added a migration record in one, and created a second glossary row in one; there is no hand-dropped record).
Byte-level: 31 files identical, 5 differ only in blank lines, 27 only in record order, 6 in content (text the human edited while
resolving). Order: of 66 syncs where both sides added records, humans put
main's first in 40 and the branch's first in 26; no gate reads the order (the boards, the registries and the ledgers are unsorted
today). Seat A compared 13 file merges of 6 syncs with `git merge-tree`'s result and the human's file: no semantic loss.

## 1.1 Bug history (section 4.1.5)
- OI-309 (the treadmill), parent plan section 0; C1 / `d1264d` (the review gate half); `c9f4e2` (2026-08-14: conflict
  markers committed to `main` in the board; its gate `scripts/check_no_conflict_markers.dart` is the reader that
  stops a half-resolved file from landing).
- 85fc430a is a recorded hand-resolution: "conflicting hunks of four shared files taken from main; restored in the next commit".
  That is the failure shape (a human under time pressure keeps one side of a hunk) the keyed merge removes.
- **Recurrence for the fetch only:** `b2f7e4` (2026-09-24): a `Process.run(...).timeout(...)` around `git fetch` does not kill the
  child, so a hung fetch outlives the caller. Its fix (`Process.start`, a timeout on `exitCode`, `kill(sigkill)`, drain both streams,
  the explicit refspec of `discipline_hook.dart`) is applied to this tool's fetch and has a hang-and-kill test (E7).
- No prior record merge exists; not a recurrence for the merge itself.

## 2. Writers and readers (section 4.1)

| Artifact | Writer(s) | Reader(s) |
|---|---|---|
| each allow-listed ledger | agents and `scripts/mint_oi.sh:255` (appends the `## OI-N` stub), by hand | `check_oi_numbering_unique.dart` (number-keyed, mid-merge arm), `check_bug_class_numbers_unique.dart` (id sets and titles of the two debugging files), `check_applied_migrations_ledger.dart` (Gate 39: per-file sha256, no order or chain), `check_no_conflict_markers.dart` (tracked files, working tree), the SoT gates (`line_range` is bounds-checked only), agents |
| the merge in progress | `git merge` (`--no-commit` or auto-commit), then THIS tool for the allow-listed paths only | `git commit` (hooks + the C1 gate), `safe_commit.sh` |
| `docs/audit/GATE_INDEX.md` | `scripts/build_gate_index.dart` (reads every `scripts/*.dart`, `build-apk.md`, the closure ledgers, `closed_issues.md`, `gate_test_ledger.yaml`; pre-commit regenerates it when an input is staged) | `check_gate_index_fresh.dart` (re-runs the builder and compares: it reads the index, not the ledgers) |

The tool is a NEW writer of the ledgers' merged text. Its output is read by every gate above at the merge commit, which is why it
never commits by default and why section 4.4 runs three independent checks before it stages. All allow-listed paths are
`feature` tier in `docs/blast_radius.yaml` (`docs/**`, `.claude/**`, `backups/**`), so a resolved ledger that equals neither side
cannot trip C1's catastrophic grading.

## 3. Decisions
- **D1: a record is merged by KEY, a region by its records, the text between regions by git.** A file is described by an
  allow-list entry (path, one or more regions). Each region is a run of records (a record starts at a line matching the
  region's start pattern, carries a key, owns the comment lines directly above it when the region has a `leader`, and ends where
  the next record starts or the region ends). Per key the three versions (base = stage 1, ours = stage 2, theirs = stage 3) are
  decided like a three-way merge: equal on both sides -> that; one side unchanged -> the other; both changed differently -> `git
  merge-file` on THAT record's three texts, and a conflicted result keeps its markers around that record only.
- **D2: collisions are conflicts, never renumbered.** Two sides that both ADDED the same key with different text are decided by
  `git merge-file` with an empty base, which conflicts (the whole record is in the markers). A bug-class number or a migration
  number is cited elsewhere; renumbering needs a citation sweep that belongs to a human.
- **D3: the allow-list is a DATA list in the lib, guarded by tests on the real files.** Included: the open and closed boards,
  `bug-classes.md`, the debugging index table and changelog, the naming glossary, the SoT registry, the gate test ledger,
  `applied_migrations.json`. NOT included (reasons in section 8): the tuning archive (frozen by A1), the two indexes (untracked by
  A2; a conflict there is a stale local build), `CLAUDE.md` and other prose, code, tests, `ship_dark_pending_review.yaml` (three
  lists), `live_schema_columns.json` and `context_artifact_sizes.json` (scalar fields that need a decision), the other generated
  indexes (`docs/adr/INDEX.md`, `docs/handbook/INDEX.md`, `docs/incidents/INDEX.md`; one leftover sync, a human's today).
- **D4: the gate-index builder runs last and alone.** `docs/audit/GATE_INDEX.md` is a pure function of tracked inputs. If it is
  unmerged and it is the ONLY path still unmerged after the record files, the tool snapshots it, runs
  `dart scripts/build_gate_index.dart` (plain `dart <file>`, not `dart run`) with the CLI's own Dart binary from the repo root, and
  stages it; a failing builder restores the snapshot (git's markers) and the path is reported. There is no second "freshness" run:
  `check_gate_index_fresh.dart` re-runs the same builder, and pre-commit regenerates the index at the commit when an input is staged.
- **D5: fail closed, and never lose work.** Anything the parser cannot place (an anchor missing from one version, a region with no
  record, an unkeyed record, a table row that does not match, an unclosed fence, a group of repeated keys that both sides changed, a
  side that reordered shared keys, a CRLF or NUL byte, a non-UTF-8 blob, a missing stage, a mode that differs, a symlink, `git
  merge-file` exiting above 127) leaves git's conflicted file untouched and says why. For each path, in this order: (1) the output
  equals the file -> write nothing, record `written/<path>` if it is missing or different, `git add` when no marker is left; (2) the
  file has NO marker line (hand-resolved, or resolved by rerere without autoupdate) -> `left: resolved but not staged, git add
  <path>`; (3) `written/<path>` exists and the file differs from it -> `left: edited since the tool wrote it`; (4) otherwise overwrite.
  Before an overwrite the previous bytes are ALWAYS copied to a backup (git's conflict labels never equal the tool's own merge text, so
  "already git's output" cannot be recognised and a hand-edited marker file looks the same as a pristine one); a failed copy means NO
  overwrite (`left`). The write is a temp file inside the state directory plus a rename; a failed rename (a read-only directory,
  another filesystem) is `left: could not write` and never a direct write, so a kill cannot truncate a ledger. A marker line is what
  `scripts/no_conflict_markers_lib.dart` calls one.
- **D6: the tool resolves and stages; it commits only with `--commit`, and only a merge it started.** CLAUDE.md section 4.3 (never
  commit unless asked) is kept by default. With `--commit` a clean merge is concluded by git itself (the cheap `pre-merge-commit`
  path), a conflicted one by `sh scripts/safe_commit.sh`. On a merge the CALLER started, or one the tool started in an earlier run,
  `--commit` is refused (exit 2) with "conclude it with `sh scripts/safe_commit.sh`": the index may hold other work. `--commit` runs
  the full pre-commit loop for a conflicted merge and takes minutes: a foreground Bash call will hit its timeout, so the docs say to
  run it in the background.
- **D7: three independent checks stand between the merge and the index** (section 4.4).
- **D8: execution mode inline, one worktree.** The coordinator and the implementer are the same session; review seats are
  context-blind subagents.
- **D9: why the whole-file record merge and not "splice into git's output".** Resolving only the records that overlap git's own
  conflict hunks and keeping every other byte as git wrote it would remove the emission rules of 4.3. Seat A measured it on the same
  93 syncs: 45 resolve, against 53 for the record merge, and its hunks do not align with record boundaries (the migration ledger's
  hunks start at `},` / `{`). The record merge keeps global record identity; its emission risk is bounded OUTSIDE git's conflict
  hunks by V-b and INSIDE them by the merge-matrix tests of section 5 (V-b is blind there: a mutant that put every theirs-only record
  at the front still passed all three checks on 97 of 114 real file merges with the rev-3 prototype: 15 rejected by V-b, 2 by V-c).
- **D10: no lock.** One worktree per session (section 4.13); `safe_commit.sh` takes `scripts/_git_lock.sh` itself and would refuse
  against a holder. The tool writes only allow-listed UNMERGED paths in its own worktree.

## 4. Design

### 4.1 Files and registrations
- `scripts/sync_resolver_lib.dart`: pure, imports only `dart:convert` (no `File`: `check_gate_existssync_file_vs_dir.dart` guards
  `scripts/check_*.dart`, `scripts/*_lib.dart` and `scripts/validate_*.dart`). Specs, parser, keyed merge, emitter, the three checks.
  The text merge of one piece comes in as a function so every case is unit-testable with a fake.
- `scripts/sync_with_main.dart`: the CLI. All git and file-system effects. Reads NO environment variable and contains no
  `Platform.environment` token (the scanner's arms 1-3 then have nothing to index); every child gets the parent's environment plus,
  for the fetch only, the override `GIT_TERMINAL_PROMPT=0` (a map literal passed as `environment:` with the parent included). Test-only
  switches are argv flags (`--no-fetch`, `--fetch-timeout-ms`) that the wrapper does not forward; the CLI rejects an unknown flag with
  exit 2. The header must not carry a canonical `// Gate: N` line (`build_gate_index.dart` hard-fails on one).
- `scripts/sync_with_main.sh`: the wrapper. Locates the `.dart` next to its OWN path (`$0`) and operates on the repository of the
  caller's working directory, so `sh <primary>/scripts/sync_with_main.sh` works in any worktree, including one cut before this
  landing. Resolves Dart through `_dart_bin.sh` found next to itself. Forwards ONLY `--commit`; any other argument is a usage error.
  Runs the CLI as a background child, forwards TERM, INT and HUP to it, waits for it and reads its status without `set -e` ending the
  wrapper (`rc=0; wait "$child" || rc=$?`, and a second `wait` after a trapped signal). The wrapper owns the last stdout line for every
  exit the CLI cannot make: no `dart` on the PATH (`resolve_dart_bin` prints a bare `dart`, so the wrapper checks) or a bad argument ->
  `result: refused`, exit 2; a child status above 4 (a compile error 254, an async leak 255, a signal 128+n) -> `result: error`, exit
  4. Never pipe it: `check_safe_wrapper_not_piped.dart` only knows `safe_commit.sh` and `safe_push.sh` (its regex), so this is
  documented, not gated. A founder allow-rule `Bash(sh scripts/sync_with_main.sh:*)` is a user-side setting and is mentioned in
  hooks.md only. Unbounded phases, stated for landing D: `git merge` and its hooks, the builder, and `--commit` (the full pre-commit
  loop); only the fetch has a deadline. A supervisor must signal the wrapper's process group.
- **Registrations and gates a change of this shape trips** (seat C, checked again in round 2): `docs/blast_radius.yaml` rows ABOVE
  `scripts/**` (line 515; platform) for the three files; `docs/naming_conventions.md` glossary rows (`sync_with_main`, record merge,
  region, leader: "NOT the data sync" of the Hive-to-cloud glossary); `docs/architecture/hooks.md` section; CLAUDE.md one row in
  section 7 and one sentence in section 4.13.2 tied to section 4.3 (+1.78% drift today, safe) with the deferral-phrase gate
  (`docs/deferral_euphemisms.yaml`) run on the new text; `.claude/skills/code-review/SKILL.md` is at +14.83% of its recorded size
  against a 15% soft band, so it is NOT edited; `spawn_sites_guard_test.dart` (new tests use `runSpawn` / `startSpawn` + `reportSpawn`,
  no raw `Process`, no `Platform.resolvedExecutable`, no `which dart`; the CLI is outside that scan and uses `resolvedExecutable` for
  its own children), `spawn_env_manifest_test.dart` (no new `Platform.environment` token, no unassigned `$VAR` read in the `.sh`; a
  control variable such as `GIT_CONFIG_GLOBAL` passed as `extraEnv` needs `allowControl`), `check_claude_md_citations.dart`,
  `check_merge_tree_write_tree_form.dart` (only the `--write-tree` form appears in prose); the parent plan's section 7 C2 bullet and
  section 8 numbers (the stale "about 4 of 52 need a human" and "27 of 50"); the plan-review record `docs/plan-reviews/sync-resolver.md`
  (`review_rounds: >=2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`, `bpass_review:` a path under
  `docs/reviews/`). No new `check_*.dart` is added, so rule 24 and the gate ledger do not apply; no SoT concept is added (the lib reads
  files, it defines no writer/reader contract).

### 4.2 The allow-list (`kResolvableFiles`)

| Path | Region(s): anchor -> record start -> key -> region end | Leader | After a record |
|---|---|---|---|
| `docs/audit/open_issues.md`, `docs/audit/closed_issues.md` | none -> `## OI-N ` -> `OI-N` -> end of file | none | blank line |
| `.claude/skills/debugging/bug-classes.md` | none -> `### N.M` followed by a space, a dot or the end of the line (also `### N.M.archived-DATE`) -> `N.M` (with the archived suffix) -> end of file | none | blank line |
| `.claude/skills/debugging/SKILL.md` | (1) `### Bug-class index` -> `\| N.M \|` -> `N.M` -> first line after the first row that does not start with `\|`; (2) `## Changelog` -> `- **` -> text of the bold lead -> end of file | none | none; none |
| `docs/naming_conventions.md` | `## 8. Reserved domain glossary` -> `\| **` -> the first cell -> first line after the first row that does not start with `\|` | none | none |
| `docs/sot_registry.yaml` | `concepts:` -> `  - concept: ` -> the concept name -> end of file | `^  #` | blank line |
| `docs/audit/gate_test_ledger.yaml` | none -> a top-level `name.dart:` -> the file name -> end of file | `^#` | blank line |
| `backups/applied_migrations.json` | none -> `  {` -> the `"migration"` value -> the closing `]` | none | comma |

The region's END is looked for after its first record start (the anchor is followed by prose lines that do not start with `|`). A
record is its lines up to the next record's leader or start line, so blank lines, `---` and H1 lines between records belong to the
previous record, and a comment block directly above a record (no blank line between) belongs to that record when the region has a
leader. **The first record starts at its first leader line; the region's prefix ends before it.** Trailing "blank" means empty or
whitespace-only lines. Every line of a TABLE region (the index table, the glossary) must match the row pattern, else the file is
unresolvable (a row that does not match would be absorbed into the previous record). Markdown regions ignore record starts inside
fenced blocks (same fence rules as `scripts/bug_class_ids_lib.dart` `_scanFences`, mirrored and pinned by a test); an unclosed fence
makes the file unresolvable. A region found in one version with the anchor present and no record is unresolvable ("no record").

KEYS AND GROUPS. A key that repeats inside a version (the migration ledger repeats `145` and `146`, the glossary `**gate**`, today) is
decided as a GROUP: the list of its occurrences' trimmed texts is compared across the three versions like a record. If the three lists
are identical the occurrences stay where they are; otherwise the 4.3 decision table applies to the LIST of trimmed texts (one side unchanged -> the
other side's list; both changed identically -> that list; both changed differently -> the file is unresolvable), and the chosen list
is emitted together at the position of the group's first occurrence (comma region: as separate elements). A rule that paired
occurrences by position would leave a stale duplicate behind when one side adds or consolidates a row. Cost, accepted: ANY change to a
duplicate group plus another change near it can fail V-b (git keeps the second occurrence where it was), and the file then goes to
the human; real syncs touching the glossary's `**gate**` rows or the ledger's 145/146 are rare, and no record is ever lost.

COMMA REGION. The trailing comma of an element is stripped at PARSE time and re-added at emission to every element but the last, so
`  },` against `  }` is never a difference.

### 4.3 The merge of one region
For each key in `ours-order + theirs-order + base-order`, with B/O/T the record texts compared after trimming trailing blank lines
(the number of blank lines between records never counts as a change):

| O vs T | Result |
|---|---|
| O == T (both absent -> the key is dropped) | theirs when ours' raw text equals base's raw text and theirs' differs; otherwise ours |
| O == B (ours unchanged; theirs added, changed or deleted it) | T |
| T == B | O |
| otherwise | `textMerge(B or "", O or "", T or "")`; conflicted -> markers kept for this record; clean -> the record is reported as "merged by line" |

ORDER. Let S be the keys present in all three versions (the records of a CHANGED group are excluded; the occurrences of an unchanged group stay in S). If S is not in the same order in ours, theirs and
base, a side reordered records: the file is unresolvable ("a side reordered records"; no real sync in the 160 region merges of the
replay did, so the cost is zero and nothing silently reverts main's sort). Otherwise the skeleton is ours' sequence and theirs-only
keys (new, or modified after ours deleted them) are inserted after the nearest preceding key of theirs that is PLACED in the skeleton
(a key the merge drops is not an anchor), else at the front: when both sides append at the end main's records come first, when both
prepend (the changelog) main's first. A key only the base and ours hold (theirs deleted it, ours unchanged) is dropped.

EMISSION. Every record is written with its OWN bytes, including its trailing blank lines and leader. A blank line is added after a
record only when it was the last record of its source version and is no longer last (a table region and the changelog add none; the
source of a `textMerge` result is ours). In a blank-separated region that ends at the end of the file, when the region's last record was
NOT the last record of its source version, its trailing blank lines are replaced by ours' final trailing blank lines (the real board
ends in a blank line, the other files do not). Lines are split on `\n` only (a lone CR, a form feed or U+2028 is not a break). Prefix,
the text between regions, and suffix: equal -> that; one side changed -> that; both -> `textMerge`. Invariants pinned by tests:
`resolve(x, x, y) == y` and `resolve(x, y, x) == y` byte for byte on every real file when y appends, prepends or inserts one record
(28 of 28 on the prototype); deleting the last record may change the trailing blank lines and is not claimed; `parse` then `emit` of an
unchanged file reproduces it. The two byte-for-byte statements hold for a file in canonical form; in the comma region (JSON) a blank line
between elements, whitespace after a comma and a trailing comma on the last element are normalised on emit (whitespace churn only, which V-a ignores).

### 4.4 The three checks (D7) - all must pass before `git add`
V-a and V-b are computed from the three input texts and the output alone, never from the parser's own decisions; V-c compares the output
with the decisions (an emitter-fidelity check). Lines are compared after trimming trailing whitespace (and, in a comma region, a
trailing comma); blank lines are skipped.
- **V-a, line counts.** On the output with conflict-marker blocks flattened, per line let b/o/t be the counts in base/ours/theirs:
  `upper = b + max(o-b,0) + max(t-b,0)` and `lower = b + min(o-b,0) + min(t-b,0) + max(max(o-b,0), max(t-b,0))` (clamped at 0); the
  output count must lie in [lower, upper]. For a CLEAN output, a line with b, o and t all at most 1 must have the EXACT count the
  three-way rule gives (o if o equals t; t if o equals b; o if t equals b; 1 or 2 when both sides added it): that is what catches a
  record one side deleted and the output kept ("resurrected deletion"), a dropped line that is unique to a changed record, and a
  duplicated record (the heading line of a record is unique). Limits, stated: (1) a line shared by two records that both sides ADDED
  (`- **Status**: OPEN`) can lose one copy undetected, because the interval [b+1, b+2] allows it (the twin-line blind spot; the
  merge-matrix tests cover it); (2) the interval uses NET deltas, so a correct merge can fall outside it when both sides delete the
  same record and each adds a record sharing a line, and when both sides add the SAME record and one side nets below it on a shared
  line (for example ours archives another record that shares it): it is rejected, safely, and the F oracle's generator excludes both
  shapes. For a PARTIAL result (markers kept) let x be the count outside conflict blocks and h_o, h_t the counts in the ours and theirs
  sections (the diff3 base section excluded): reject iff `x + min(h_o,h_t) > upper` or `x + h_o + h_t < lower`; the exact rule is not
  applied.
- **V-b, agreement with git.** `G = git merge-file -p --diff3` of the three whole files. The non-blank lines of G outside its conflict
  hunks, in order, must be a SUBSEQUENCE of the output's non-blank lines (greedy matching is exact for a subsequence). So nothing
  outside the places where git itself saw a conflict can be dropped, moved or reordered relative to git's merge, while the tool may place
  a record differently next to a hunk (a contiguous-run form of this check failed on 4 of 93 real syncs for exactly that reason). V-b is
  BLIND inside git's hunks and can reject a correct merge when git keeps a line outside a hunk that the record merge moves (two
  adjacent deletions in a comma region; a changed duplicate group): the file is then left for the human.
- **V-c, emitter fidelity, CLEAN outputs only.** The output is parsed again with the same spec: the keys and the trimmed record texts
  must equal the decisions, in order (the records of a changed group are adjacent; those of an unchanged group stay where they were).
  JSON: `jsonDecode` succeeds and every element is a map holding the key. YAML: in the registry every non-blank line of a record is
  indented at least two columns or a comment and the record's first non-leader line is `  - concept: <key>`; in the gate ledger every
  column-0 line that is not blank or a comment is `<name>.dart:`. A partial output has marker lines inside records, so V-c does not
  apply to it; V-a (interval form) and V-b gate the write. V-c is circular for a splitter bug that is consistent across the three
  versions; splitter correctness rests on L2 (the real files) and the fence-mirror test.
Measured on the first 93 syncs (prototype, `merge-base` as the base, CONFLICT-FREE merges only, with the interval V-a): 114 file merges
reached the checks, all passed V-a and V-c, 113 passed V-b (the one rejection is the glossary case above); the exact rule was checked
over all unique lines of the same 114 merges with 0 rejections. The checks were not run on conflicted records in the replay (the
partial-result forms are exercised by the fuzz and the e2e tests). A violation leaves the path unresolved, prints which check failed
and why, and the exit is 1.

### 4.5 The CLI flow (`sync_with_main.dart`)
Exit codes: **0** done (staged and ready, committed with `--commit`, fast-forwarded, or already up to date); **1** the merge is in
progress and paths remain for a human; **2** refused or failed before anything was changed; **3** `--commit` failed (the merge is
pending and staged); **4** internal error (any uncaught exception, including an async one, caught by `runZonedGuarded`; state unknown,
the merge may be pending). There is ONE exit point behind a `_finished` latch (a late error after the kill of the fetch, or an EPIPE,
cannot print a second result): every hint is printed first, then `result: <ready|pending|committed|fast-forwarded|up-to-date|refused|commit-failed|error>`
once as the last stdout line, then `exit(code)`. Per path one line `  <resolved|merged-by-line|partial|skipped|left>  <path>  <detail>`.
After exit 1 the message says: finish by hand, then `sh scripts/safe_commit.sh`.

1. Refuse (exit 2, nothing changed) when: not inside a work tree; HEAD is detached; the branch is protected by
   `protectedBranchReason` of `scripts/retire_worktree_lib.dart` (it lowercases: `main`, `develop`, `rescue/`, `oi/`, `dependabot/`);
   the repo is shallow; a rebase, am, cherry-pick, revert or bisect is in progress; `MERGE_HEAD` holds more than one line (octopus) or
   is not an ancestor of the tip (`merge-base --is-ancestor` exit 0 = yes, 1 = no, anything else = refuse); unmerged index entries exist
   with no `MERGE_HEAD`; tracked files are modified or staged while no merge is pending; `--commit` is given and a merge is already
   pending; the fetch fails or times out. FETCH: `git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main` started with
   `Process.start`, stdin closed, `GIT_TERMINAL_PROMPT=0`, stdout and stderr drained (the drain futures are not awaited after the
   kill), a timeout on `exitCode` (120 s, `--fetch-timeout-ms` in tests) and on timeout `kill(ProcessSignal.sigkill)` and exit 2 (the
   `b2f7e4` fix); skipped with `--no-fetch`. After the fetch resolve the tip ONCE: `TIP = git rev-parse --verify
   refs/remotes/origin/main^{commit}` (the ref is shared by every worktree and the SessionStart hook moves it); every later step uses the
   SHA.
2. If HEAD already contains TIP: `up-to-date`, exit 0. If no merge is pending and HEAD is an ancestor of TIP (a branch with no commit
   of its own): print the old HEAD, run `git merge --ff-only TIP`, print the new HEAD, `fast-forwarded`, exit 0 (no commit is created;
   the old HEAD is the undo); a failure of `--ff-only` (untracked files in the way) is exit 2, `refused`, with git's output. The
   pending-merge check of step 1 comes first, so a hand-started `--no-ff` merge never reaches this step.
3. If no merge is pending: delete `identity` and `written/` of the state directory (backups stay), record OLD = HEAD, then `git merge
   --no-ff -m "Merge remote-tracking branch 'origin/main' into <branch>" TIP` with `--no-commit` (without `--commit`) or `--no-edit` (with
   it, so a clean merge is concluded by git through `pre-merge-commit`, not `pre-commit`). Decide from STATE, never from the exit code:

   | `MERGE_HEAD` | HEAD | `git ls-files -u` | Meaning | Next |
   |---|---|---|---|---|
   | present | - | not empty | conflicts | step 4 |
   | present | - | empty | clean `--no-commit`, rerere resolved everything, or an auto-merge whose `pre-merge-commit` hook failed | step 6 (with `--commit`, `safe_commit.sh` re-runs the pre-commit gates, which in effect cover that hook's) |
   | absent | has two parents, `HEAD^1` is OLD and `HEAD^2` is TIP | - | git committed the merge | `committed`, exit 0 |
   | absent | otherwise | - | git stopped before any merge state | verify NOTHING changed (HEAD is OLD, `git status --porcelain=v1 -uno` is empty, `git diff --cached --quiet` passes): if so print git's output and exit 2; if not, `result: error`, exit 4, with `git reset --hard OLD` named as the undo (never run) |

   `git merge --abort` is never run by the tool. A merge already pending (the caller started it) resumes at 4.
4. For each unmerged path (`git ls-files -u -z`): read the three stages with `git cat-file blob` (a missing stage, including
   add/add, a mode that differs, a symlink, a gitlink, a path not in the allow-list -> `left`), decode strictly, `resolveFile`, run the
   checks, then apply D5 (1)-(4). Write `identity` BEFORE the first temp write. `textMerge` is `git merge-file -p --diff3 -L HEAD -L
   base -L origin/main` on three files inside the state directory; its exit 1..127 means conflicted, above 127 or a spawn error means
   "skip this path". A failing `git add` is reported "written, NOT staged". A rename or directory conflict leaves untracked `path~ref`
   side files; the report lists them.
5. D4 (the builder), re-read `git ls-files -u`, print the per-path lines, the backup directory if a backup was made, and the exact
   state path when a path was skipped as "edited since the tool wrote it" (remove it to let the tool redo the path), then exit 1 if
   any path remains.
6. Nothing is unmerged. Without `--commit`: print "all conflicts resolved and staged; review `git diff --cached`, then `sh
   scripts/safe_commit.sh "<message>"`", `result: ready`, exit 0. With `--commit`: run `sh scripts/safe_commit.sh "Merge
   remote-tracking branch 'origin/main' into <branch>"` with inherited stdio (never piped); exit 0 on success, 3 on any failure, with
   the merge still pending. On success delete the state.

STATE, in `git rev-parse --path-format=absolute --git-path sync_with_main/` (per worktree): `identity` (HEAD, the MERGE_HEAD sha and the
modification time of the `MERGE_HEAD` file in milliseconds, read with `FileStat.statSync(...).modified`; `lastModifiedSync` has second
resolution) and `written/<path>` (the bytes the tool wrote). A `written/` with no `identity`, or an identity that differs from the
current merge, is discarded. BACKUPS live in the sibling `sync_with_main_backup/<HEAD-short>-<n>/<path>[.N]` (`.N` numbers a second
backup of the same path inside one run directory), the run directory is created only when a backup is written, they are never deleted
by a fresh start, and only the newest 20 run directories that hold files are kept.

## 5. Tests (rule 21; every row names its mutant)

Fixtures project the post-A1/A2 layout: the tuning archive exists as a frozen file, the two indexes are untracked and ignored, a
review file carries its own tuning entry. Fixture text that needs a marker line builds it from `'<' * 7`, `'=' * 7`, `'>' * 7`
(the marker gate flags its own source otherwise). The conflict content in the e2e fixtures is built from the real record shapes
(an `## OI-N` stub as `mint_oi.sh` writes it, a `| N.M |` row, a JSON element with the real keys, a commented SoT concept). The e2e
fixtures reuse `test/helpers/merge_scope_repo.dart` (it isolates HOME, `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM`, `user.*` and
`gpgsign=false`).

**Lib** (`test/scripts/sync_resolver_lib_test.dart`, fake `textMerge` that records its calls and scripts its answers):
- L1 lossless round trip on a synthetic file of each region shape: `emit(parse(x)) == x`. [emitter drops a blank line, loses a comma]
- L2 the same round trip on the 8 REAL tracked files at HEAD (9 regions), no unkeyed record, every region found, every table row
  matches, duplicate keys only where the real files hold them, 25 leader blocks owned by their concept, and `resolve(x, x, y) == y`,
  `resolve(x, y, x) == y` for an appended, prepended and inserted record on every file, including the board whose last line is blank
  and a file whose last bullet has no blank line after it. [a spec stops matching a real file the day a heading is renamed; the leader
  moved to the previous record; an append that loses a blank line; the unconditional tail rule]
- The merge matrix of 4.3: one-sided add; both append (main first); both prepend; the same record on both sides; a same-key
  different-text collision (markers around that record only, neighbours resolved); one-sided edit; both edit different lines
  (`textMerge` called once with the three texts, reported "merged by line"); both edit the same line; delete vs unchanged; delete vs
  edit in each direction; both absent (dropped); trailing-blank-only difference is no change; trimmed-equal takes theirs only when
  ours' raw text equals base's; insertions at different anchors; theirs or ours reorders shared keys (unresolvable, naming the side);
  a deleted key is not an anchor; a group identical in all versions (carried through in place); a group one side consolidated or
  extended (that side's list, at the first position); a group both sides changed differently (unresolvable); prefix, gap and suffix
  equal / one side / both; anchor missing in ONE version -> unresolvable naming the version; a region with the anchor and no record;
  unkeyed record; a table row that does not match; CRLF; NUL; a lone CR (not a break); unclosed fence; a record-start line inside a
  fence is not a record; a COMMENTED FIRST concept; a commented concept inserted at the front; a commented concept deleted; both sides
  append a commented concept (clean, each comment stays with its concept); one side's comment and the other's none; the ledger spec's
  `^#` leader on a synthetic fixture; JSON commas after an append at the end, an insert in the middle, theirs editing or deleting the
  old last element while ours appends, a group in the JSON region, and a result that `jsonDecode`s; a table region that ends at the
  first non-table line after its first row; a two-region file; the archived heading and a bare `### N.M`. [each branch of the decision
  table inverted; order check dropped; the trim dropped; region end dropped; comma strip moved to emission; leader dropped; fence
  tracking dropped; group treated by position]
- The checks, each on the case it can catch: V-a fails on a dropped line unique to a changed record, a duplicated record, a dropped
  UNCHANGED record, a RESURRECTED deletion (a record one side deleted, kept), output = additions only; passes on a line both sides added
  once, on blank-line and comma-only differences; its documented blind spot (the dropped copy of a twin line) and both false-positive
  shapes are PINNED as expected outcomes so a later "fix" is a conscious change; the partial interval passes a correct conflicted
  result and fails a dropped line outside the hunk; V-b fails on a line moved out of its record, a hunk-external change, a reorder,
  and passes a record placed differently next to a hunk; V-c fails on a glued record, invalid JSON, a registry line at column 0, a
  changed key, and is not applied to a partial output. [each check deleted; max replaced by sum or min; the base section counted;
  subsequence replaced by contiguous; the exact rule dropped]
- The allow-list: contains none of the tuning archive, the two indexes and `code-review/SKILL.md`; every entry has a fixture; no two
  entries share a path. [a path added]
- F seeded fuzz (80 seeds x blank / none / comma regions): random base, two random op sequences (add anywhere, delete, edit a line,
  append, prepend; never the same record on both sides unless asserted; never both sides deleting the same record; never both adding
  the same record with an opposite-sign one-sided change of a shared line; no moves); oracle = an independent set model of 4.3.
  Asserts record set, texts, V-a and V-c on every clean result (no false positive), the partial interval on every conflicted result,
  and COUNTS V-b rejections instead of asserting none (a correct merge can be rejected; the pinned bound is the first run's rate rounded
  up to the next whole percent).

**CLI, real git, temp repos** (`test/scripts/sync_with_main_e2e_test.dart`, spawn helper, file-level `@Timeout` and `library;`; a
control variable such as `GIT_CONFIG_GLOBAL` needs `allowControl`):
- E1 both branches append an OI -> exit 0, no unmerged path, the file holds both, staged, no marker, not committed, `result: ready`.
- E2 both added bug class N.M with different text -> exit 1, markers only around that record, the other records of the file
  resolved, the path still unmerged, the merge pending, the message names the key.
- E3 one resolvable and one other conflicting file -> exit 1, the first staged, the second byte-identical to git's output.
- E4 a conflict in the tuning archive (tracked) and, on a PRE-A2 shaped branch, a tracked local index that main deleted (modify/delete,
  no stage 3) -> both untouched (bytes equal to git's), listed as `left`.
- E5 `GATE_INDEX.md` unmerged alone -> the stub builder runs (the test PATH holds git and sh but NOT dart, so a bare `dart` fails),
  the file is staged; a failing builder restores git's markers, exit 1; `GATE_INDEX.md` plus another unmerged path -> the builder does
  not run.
- E6 a clean merge -> exit 0, staged, `result: ready`; with `--commit` git concludes it (one merge commit, two parents, `HEAD^2` is the
  tip, `result: committed`); a clean `--commit` merge whose `pre-merge-commit` hook fails -> `MERGE_HEAD` stays, nothing unmerged, the
  fallback runs `safe_commit.sh` (this row tests the control flow only: `git commit` runs `pre-commit`, not `pre-merge-commit`); a
  conflicted merge with `--commit` -> the ledger resolved and `safe_commit.sh` concludes it; the commit's hook failure -> exit 3 and
  the merge still pending and staged; `--commit` on a merge the caller started, and on one the tool started in an earlier run -> exit
  2, nothing changed, the message names `safe_commit.sh`; the tip moves between the tool's fetch and the merge (a stub `git` moves
  `refs/remotes/origin/main` when it sees `merge`) -> the merge uses the recorded SHA, `committed`, `HEAD^2` is the OLD tip.
- E7 each refusal of step 1 (on main, develop, `rescue/x`, `oi/x`, `dependabot/x`, detached, not in a work tree, shallow, staged-only
  changes, modified tracked file, octopus MERGE_HEAD, MERGE_HEAD not an ancestor, unmerged entries with no merge, fetch failure, no
  `origin/main`, a rebase directory, cherry-pick, revert, bisect, am) -> exit 2 and HEAD, index and tree byte-identical to before; a
  fetch that hangs (the `b2f7e4` pattern: a stub `git` first on PATH that writes its pid to a file and `exec sleep 300` for `fetch`,
  real git otherwise; `--fetch-timeout-ms` small) -> `kill -0` on that pid fails afterwards, exit 2; the stub also logs
  `$GIT_TERMINAL_PROMPT` for `fetch` and the test asserts `0` (and that HOME and PATH reached the child); a merge that git refuses to
  start (untracked file in the way) -> exit 2 with git's text; a stub `git` that fails after the index was written -> `result: error`,
  exit 4, `git reset --hard OLD` named; up to date -> exit 0; a branch with no commit of its own -> fast-forwarded with the old and
  new HEAD printed, exit 0; a failing `--ff-only` -> exit 2; a hand-started `--no-ff` merge on a branch with no commit of its own is
  resumed, not fast-forwarded; a stub `git` that returns junk for `ls-files -u` after the merge started -> exit 4 with the merge
  pending and a single `result: error` last line (the stub fails inside the awaited flow, so this row does not pin `runZonedGuarded`;
  a source-grep test pins its presence and a second stub that throws from a timer pins the async path); nothing is printed after
  `result:` in any scenario.
- E8 resume and safety: a second run over the tool's own unchanged output writes nothing, adds no backup and keeps the old ones; after a
  human edit of a file the tool wrote, the file is left alone and the state path is printed; a file hand-edited before the first run
  but still holding markers is overwritten ONLY after a backup, and a second run does not destroy it; a file with NO marker line (a
  human resolved it, or rerere without autoupdate) is never overwritten; a failing backup (read-only backup parent) means no overwrite;
  the target's directory made read-only -> `left: could not write`, the file untouched, no temp file anywhere; the state is cleared
  after a fresh start but the backups survive a `git merge --abort` + hand re-merge, and the stale `written/` of the aborted merge is
  discarded by the identity check (the re-merge is done by hand, with a sleep past the millisecond mtime); the post-crash disk state is
  built from a second repository: run the CLI in repo A, copy its output file into repo B whose identical merge was started by hand
  (file == output, no record, still unmerged), run the CLI in B -> the record is written and the path is staged; a stub `git` whose
  `add` fails -> "written, NOT staged", exit 1; 21 runs that each make a backup keep 20 run directories and no empty one is created by a
  no-op rerun.
- E9 a symlink, a mode that differs, a delete/modify, an add/add (no stage 1), a non-UTF-8 blob, a NUL in an allow-listed path, and a
  stub `git merge-file` that exits 255 -> `left` with the reason, file untouched; the `path~ref` side files of a rename conflict are
  listed.
- E10 a linked worktree (state directory under the worktree's own git dir) and a run from a subdirectory (absolute path).
- E11 the wrapper: forwards only `--commit`; any other argument -> `result: refused`, exit 2; works from a subdirectory; runs from
  another tree's `scripts/` against a branch that does not contain it; with no `dart` on the PATH -> `result: refused`, exit 2; with a
  PATH holding only a symlink directory to the real dart AND to git, sh, dirname and tr it works with empty stderr (the layout check of
  `feedback_green_local_is_this_machines_layout.md`); a fixture CLI exiting 254, 255, 137 or 130 -> `result: error`, exit 4, the last
  stdout line; a TERM sent to the wrapper reaches a sleeping fixture CLI; the CLI rejects an unknown flag with exit 2.
- E12 a line that merely resembles a marker is not "partial"; the tool and `scripts/no_conflict_markers_lib.dart` agree on which
  outputs carry markers.
- E13 config variants: `rerere.enabled` + `rerere.autoupdate` (git resolves and stages, git exits 1, nothing is unmerged -> step 6, the
  tool exits 0 with `result: ready`, no abort), plain `rerere.enabled` (resolved but unstaged: the file is not overwritten, "git add" is
  advised), `merge.conflictStyle` diff3 and zdiff3, `merge.ff=only`, `commit.gpgsign=false` pinned.
- E14 CI runs these on git 2.55 and this VPS on 2.43: the tests use no version-specific option; the first CI run is the 2.55 check.

**History replay (measurement, not a repo test):** section 7. Its result goes in the as-built section and the OI-309 progress note.

**Mutation (rule 21; rule 24 not triggered):** one mutant per row above, plus the CLI's own guards (each refusal, state-not-exit-code,
the `--abort` that must not exist, the fast-forward guards and their order, the fetch kill and its child environment, the tip SHA, `git
add` only on a clean result, the builder preconditions and restore, `--commit` refusal on a resumed merge, the exit-code mapping, the
wrapper's `result:` lines, clamp and signal forwarding, the backup (always taken, never replaced, lazily created, pruned), the
no-marker rule, the no-op with record, the identity discard, the temp file location, the single exit point and its latch) run on the
FINAL tree after the last edit with `dart analyze` clean required for a mutant to count (a compile error is not red). The table goes
in the as-built section.

## 6. Process
Plan review x3 (context-blind sonnet seats, each claim checked against code and live state; round 3 was the delta round for the rev-2
changes and found no P0 or P1; rev 4 folds its details in), the whole gate loop on the final tree (whole-project `flutter analyze --no-fatal-infos`, the full suite with
`TZ=Asia/Kolkata --exclude-tags golden`, `sh scripts/pre-commit.sh`), B-pass with two seats, the review file named by the staged diff
hash, then commit, push, PR, `sh scripts/safe_pr_merge.sh`, retire the worktree, memory. No diagnose doc (this is a `feat`, not a fix);
OI-309 gets a progress paragraph and stays OPEN for D. Founder authorization: the standing go of 2026-10-26 ("standing go approved")
for landings C2 and D.

## 7. Measurement method
1. `git log --merges -600 origin/main`, drop subjects starting "Merge pull request" (448 left).
2. For each, `git merge-tree --write-tree --name-only <m>^1 <m>^2`; exit 1 = conflicted (166); the name list is the conflicted files.
3. Per file, the diff3 hunks of the conflicted blob (`-c merge.conflictStyle=diff3`), classified "empty base" or "base".
4. Prototype keyed merge (Python, session scratch, not committed; the Dart lib is the product) on `merge-base`, `m^1`, `m^2` for every
   conflicted allow-listed file; clean = no marker. Compared with the file at `m`. ("Resolved" means no marker and the checks pass,
   not that every gate passes.) None of the 93 syncs is a criss-cross merge, so `merge-base` equals stage 1.
5. A1 + A2 clear a sync when every conflicted file is one of `OPEN_INDEX.md`, `diagnoses/INDEX.md`, `tuning-history.md`,
   `code-review/SKILL.md`. (Modelled, not replayed on a post-A1/A2 tree: 29 of the 30 `code-review/SKILL.md` hunks are tuning-entry
   hunks. Conflicts per month, June to October: 1, 7, 25, 55, 78, so the sample leans to the last two months.)
The as-built section repeats the replay with the Dart tool (stage 1 as the base, the exact emission, the three checks, D4, the
refusals of D5 and a strict UTF-8 decode, which the prototype lacks).

## 8. Residuals
- Bug-class and migration number COLLISIONS stay a human renumber (D2): 11 of the 40 syncs that still need a human.
- `line_range` / `line:` conflicts in the SoT registry stay a human (or the registry gate) decision: 5 of the 40.
- A record both sides edited that `git merge-file` merges cleanly is staged as "merged by line"; the line merge can combine two
  statements that contradict each other (seat C found one, OI-129 in sync 03d8704b). The report names such records so the human reads
  them before the commit.
- A branch that is far behind with prose conflicts in `CLAUDE.md` or code is the human's, as before; the tool lists those paths and
  leaves them exactly as git wrote them.
- Not in the allow-list, each with its reason: `ship_dark_pending_review.yaml` (three top-level lists in one file, 2 of 166),
  `live_schema_columns.json` (scalar `regenerated_*` fields), `context_artifact_sizes.json` (a budget ratchet that records an
  intent), `skills-log.md` and other prose, the other generated indexes.
- V-a's twin-line blind spot and V-b's blindness inside git's hunks (section 4.4): an emitter or order bug that stays inside a hunk is
  caught only by the merge-matrix tests and by the human's `git diff --cached`. A banner comment separated from its records by ONE
  blank line (the ledger's `# ----` divider, the H1 prose blocks of the board) stays with the previous record, so a theirs-only record
  inserted after that record lands between the banner and the records it introduces: cosmetic.
- If a fetch moves `origin/main` while a resumed merge is pending, C1 compares with the NEW tip, so catastrophic paths main changed in
  between are graded (C1's documented behaviour, a window of minutes). `prepare-commit-msg` prepends a `Blast-radius:` line computed
  from the whole merge diff to a message given with `-m`; no gate reads it.
- A hand `git checkout --conflict=merge` of a path the tool wrote leaves it "changed since the tool wrote it": the tool skips it and
  prints the state path to remove (fail-safe, slightly annoying).
- Windows: the file rename and the git calls are portable; the wrapper needs `sh` (Git Bash), like every other wrapper; git's
  behaviour there is untested on this VPS.

## 9. As built (2026-11-02)

**Files.** `scripts/sync_resolver_lib.dart` (pure; the parser, the by-record merge, the three checks), `scripts/sync_with_main.dart` (the CLI; every git and file effect), `scripts/sync_with_main.sh` (the wrapper); helpers `test/helpers/sync_resolver_fixtures.dart`, `test/helpers/sync_cli_fixture.dart`; eight test files with 330 tests: `sync_resolver_lib_test` 89, `sync_resolver_real_files_test` 55, `sync_resolver_checks_test` 40, `sync_resolver_fuzz_test` 13 (240 seeded cases), `sync_with_main_e2e_test` 77, `sync_with_main_state_e2e_test` 17, `sync_with_main_wrapper_e2e_test` 26, `sync_with_main_source_pins_test` 13. The rows of section 5 are spread over more files than the plan named so that each file stays inside the per-file timeout of the full suite.

**Replay with the Dart library** (section 7 method, merge-base as stage 1, script not committed): of the 448 non-PR merges, 166 conflicted, A1 + A2 clear 73, 93 remain; the library resolves 53 completely and 2 more once D4 rebuilds `GATE_INDEX.md`, so 40 syncs (38 with D4) still need a human. One file merge was rejected by check V-b (68843b8f, the glossary's duplicate `**Photos hub**` group), as section 1 predicted. The CLI behaviours (refusals, state, backups) are covered by the e2e files, not replayed.

**Deviations from the plan** (the code is simpler or stricter than the text):
1. Statuses are `resolved`, `merged-by-line`, `partial`, `left`; the plan's `skipped` is unused (every non-write case is `left` with its reason).
2. No untracked side-file scan: a directory/file conflict puts the side file in the index as an unmerged path (`name~<sha>`), so it is an ordinary unmerged path off the allow-list and is `left`.
3. No `.N` backup suffix: one run backs a path up once; the run directory is `<HEAD8>-<n>` with the first free n.
4. Parse errors name the version (`base:`, `ours:`, `theirs:`); the bug-class record start accepts a heading that ends at the line end.
5. Per-path containment: an unexpected exception inside one path (an unreadable file) becomes `left <path> internal error: ...` and the other paths are still resolved (found by the mutation run; pinned by a chmod test, skipped as root).
6. Dead code removed after the first mutation run showed it could not be killed: the piece-count comparison in `resolveFile` and the region-count comparison in V-c (`parseFile` always returns the same sequence, one region per spec), V-c's "registry record starts with its concept line" (a record starts there by construction), a redundant `order.contains` and a newline strip in the fence scanner.
7. The `runZonedGuarded` path of the CLI has no timer-stub seam: it is pinned by a source grep and, behaviourally, by the wrapper turning any child status above 4 into `result: error`. The location of the atomic-write temp file is also a source pin (a crash is the only way to observe it).
8. The fuzz generator never edits the shared line of a record (V-a counts a net delta, so editing a line reads as deleting it: a documented false positive, pinned) and treats identical-add and collision seeds as scattered for the order checks. V-b rejections are bounded per class: plain appends at most 1 of 180, identical or collision seeds at most 26 of 60 (measured, rounded up).
9. The V-a marker scan and `conflictsInFile` use different predicates (seven `<` followed by a space or end of line, against any line starting with seven `<`), so a line of eight `<` passes V-a and is stopped by the CLI's own marker check: the file is left `partial` and unstaged (pinned).
10. The wrapper tests that start a process report it through `reportSpawn` (the spawn-sites guard G3 caught the first draft in the full suite).

**B-pass (2026-11-02, two Sonnet seats; 0 P0, 0 P1; fix-then-accept; every finding fixed in this batch).** The review file is `docs/reviews/<hash>-review.md`. Fixes: (S1-1) a conflicted JSON element whose hunk reaches its closing line now carries the separator comma on the last line of EACH side, never on the closing marker line (a hunk in the middle of an element keeps the comma after the closing brace; the fuzz caught the first draft that did not make this distinction), so deleting the marker lines leaves valid JSON (test decodes both choices); (S1-2, S1-3, S1-6) tests for V-c's empty-region and not-an-array branches and for a duplicated line outside a partial hunk; (S1-4) the byte-for-byte invariants are stated for canonical JSON; (S1-5) a gap git merges cleanly by line is reported as merged by line; (S1-7) the fixture's redundant braces; (S2-1) the wrapper re-reads the child's status with `wait; rc=$?` (a mirror test whose child exits 0 after a TERM); (S2-2) a signal sent to the wrapper alone does not reach the CLI's children: documented in the wrapper header and hooks.md (a supervisor signals the process group); (S2-3) tests that the ready path and `--commit` prune the backup directories; (S2-4) CLAUDE.md now says who concludes the merge; (S2-5) the plan-review record `docs/plan-reviews/sync-resolver.md` lands as the second commit of the same PR; (S2-6) the five final-run survivors are re-run red and appended to the final log; (S2-7) the gate-index run no longer prints a `left` line for the file it then regenerates; (S2-8) a file changed in the work tree after staging is named as NOT in the merge commit; (S2-9) the replay method is `git log --merges -600`, not first-parent; (S2-10) no `git` on the PATH is a clean refusal (exit 2); (S2-11) tests for a modify/delete with no stage 3 and for a path with a space, the dead `not handled by this run` branch removed; (S2-12) the root-only chmod tests report `markTestSkipped`. Accepted residuals, stated: an unreadable `identity` file discards the `written/` records (a backup of the file is taken first); the wrapper installs its trap one statement after it starts the child; the fetch timeout kills `git` only; git's English messages are asserted in one e2e test; the decision ids D1-D7 of this plan are its own (the treadmill plan's D4 names the landing as a whole).

**Mutation evidence.** One mutant per row of section 5 plus the ones the first run added: 205 mutants (library 99, CLI 93, wrapper 13: the 193 of the discovery and final runs plus the 12 B-pass mutants below) and 4 controls (a comment-only edit of each file, which must stay green and did). The discovery run found 24 library survivors; five were dead or equivalent code and were removed, three mutants were ill-formed and were replaced, the rest got tests. The final run on the final code left 5 CLI or wrapper survivors (MW12, MK34, MK54, MK62, MK86); each got a test and was re-run red (the re-run lines are appended to the final log). The B-pass fixes were mutated too (B1-B12: the wrapper status re-read, the two prune calls, the unstaged warning, the gate-index line, the missing-git refusal, the comma placement, the gap by-line report, the comma rule on a mid-element hunk, the V-a `lo > upper` clause, V-c's not-an-array and does-not-parse-again branches): all 12 red. Self-attested (rule 21).

**Gate loop.** Whole-project `flutter analyze --no-fatal-infos`: no warning or error. Full suite with `TZ=Asia/Kolkata --exclude-tags golden`: one failure (the spawn-sites guard, item 10), fixed. `sh scripts/pre-commit.sh`: passed. All three are re-run on the final tree before the commit.
