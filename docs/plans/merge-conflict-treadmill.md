---
plan: merge-conflict-treadmill
revision: 7
date: 2026-10-22
base: 47cb142c
blast_radius: platform
tier: L
execution_mode: inline   # one worktree per landing
closes_oi: [OI-309, OI-167]
landings: [A0, A1, A2, B, C, D]   # each: own branch, plan-review record (≥2 rounds, last converged), B-pass, PR
---

# Stop the merge-conflict cascade between parallel PRs

## Revision history
- **A0 build notes (2026-10-24, after rev 7):** two B-pass rounds on the built A0 changed the installer beyond the plan text: the behind-main line became a REFUSAL before any hook is replaced (`--allow-stale`; behind / diverged / unreadable told apart), a tree off `main` with changed hook sources is refused (`--allow-unmerged`), unknown arguments exit 2, `chmod +x` failure is a recorded failure unless the copy is already executable. §4 below is updated in place; the review is the `docs/reviews/<staged-diff hash>-review.md` that lands with the A0 commit.
- **rev 6 → rev 7:** round 6 on A2 (two reviewers, both VERDICT converged, no P0/P1). Mechanical text corrections folded into §6 in place:
  - **Fixtures (R6C-1):** one `test/helpers/` closure helper copies a builder's transitive relative imports; no fixture lists builder files by hand.
  - **pre-merge-commit (R6C-2, R6C-4, R6D-4):** the untracked branch is keyed on `git check-ignore -q`, takes NO backup, never sets the skip flag, never restores.
  - **pre-commit (R6D-2, R6D-3):** the MERGE_HEAD lenient build runs only when the builder exists and the bug index is untracked. A failed WRITE of a regenerable output is exit 3 and a warning, not a block.
  - **Full-suite test (R6C-5):** a pure `ensureLocalIndexes(root)` helper, OI index only, unit-tested.
  - **Nudge (R6D-1):** the not-installed warning keys on an A2-only literal.
  - **Dropped (the reviewer's "removable without losing the elimination value"):** the pre-push build line, the pre-merge-commit bug-index build and the `new-worktree.sh` build. This removes R6C-3, R6C-7 and R6C-8.
  - **Other:** SoT `line_range: 1-9999`; stamp about +87 B; CLAUDE.md :38 is hooks text, the read recipe is :115/:345/:349; the isolation-worktree fallback lives in the CLAUDE.md recipe; the merge note names the dirty-tracked-index checkout.
- **rev 5 → rev 6:** round 5 (four reviewers).
  - **A1:** both reviewers CONVERGED. Spec pins folded (tier normalization, scanner state machine, flipped tests).
  - **A0:** exposure CONVERGED; ground truth HARDEN on one P1 (R5A-1): two planned mutations could not redden any test and the post-install `cmp` had no covering test. The test and mutation table is rewritten and re-derived case by case (§4). Optional hardening adopted.
  - **A2:** exposure CONVERGED; ground truth HARDEN on one P1 (R5C-1): the stamp digest needs a shared lib, so builders DO gain an import and every fixture copy list must change. Verified: `pre_merge_commit_e2e_test.dart:143-149` copies five files, and `build_oi_index.dart` imports only `dart:io`. The rev-5 "no new import" claim was wrong.
  - **Other A2 changes:**
    - the nudge uses `Directory.current`, makes no spawn, and emits once;
    - the nudge fires at SessionStart and on bug-shaped prompts only;
    - the nudge command is `--lenient`;
    - `pre-merge-commit` keeps its build and builds the bug index;
    - `new-worktree.sh` builds instead of seeding;
    - the full-suite test builds for itself.
  - **Process:** A0 got one narrow delta check (mechanical, round 6). It returned HARDEN with one P1 (the README had no test) and five P2 wording fixes in the test table; all are folded into §4 as an in-place text edit (cases 16–17 added; the EXIT-trap mutant re-attributed to cases 13/16; `|| true` on standalone chmods; exec-bit, fresh-dir and content assertions). Per its reviewer, no further full review round: the implementation's own mutation runs (rule 21) verify every row mechanically.
- **rev 4 → rev 5:** automatic rebuild removed from Claude Code hooks (D7); A0 test redesign; A1 structural parsing.
- **rev 3 → rev 4:** A0 shrank to `git add -u`; landing A split into A1 and A2.
- **rev 2 → rev 3:** hook shims dropped. **rev 1 → rev 2:** landings.

## 0. Evidence (measured 2026-10-22; replays on cbfa8884, re-anchored on 47cb142c)
- **Sync-merge replays** (`git merge-tree --write-tree --name-only <m>^1 <m>^2`, last 60 PRs): 52 main-sync merges, 47 conflicted, 46 of those ONLY in shared docs/ledger/generated files. Reviewer methods agree (52/54, 49/51, 53/60).
- **Per file (of 52):**
  - tuning-history 35
  - `OPEN_INDEX.md` 20
  - `diagnoses/INDEX.md` 13
  - `open_issues.md` 12
  - `naming_conventions.md` 7
  - `sot_registry.yaml` 4
  - debugging `SKILL.md` 4
  - `bug-classes.md` 3
  - `ship_dark` 2
  - `closed_issues.md` 2
  - `applied_migrations.json` 2
  - tests 1
- **Which landing clears which sync** (50 conflicted incl. branch-to-branch; "tuning" = `tuning-history.md` or `code-review/SKILL.md`):

  | Conflict set | Syncs | Cleared by |
  |---|---|---|
  | Tuning only | 14 | A1 alone |
  | Index only | 7 | A2 alone |
  | Tuning + index only | 6 | A1 + A2 |
  | Other files too | 23 | needs C |

  A1 + A2 together clear 27 of 50. Another sample (44 syncs) gave a smaller tuning-only share because the tuning section moved out of `SKILL.md` on 2026-09-29; the conclusion that A1 + A2 clear about half holds in both.
- **Conflict shape:** outside tuning and the indexes, 36 of 39 hunk-groups have an empty diff3 base.
- **Live:** PR #147 needed 3 more syncs on 2026-10-22.
- **Forced merge-only reviews:** 7 entries + 3 rebuilds.
- **Dangling claim:** `test.yml:370-372` cites `check_oi_index_fresh`, which does not exist.
- **Installed hooks:** plain `cp` copies (`setup-hooks.sh:62-72`), mode 0775, shared by 21 worktrees, all equal to 47cb142c; every worktree HEAD tracks both indexes.
  - The in-place `cp` can cut a running hook short (latent fail-open).
  - `git add` of an ignored untracked path exits 1.
  - `git add -u -- <path>` (executed on git 2.43.0 ONLY; CI's git 2.55.0 exits 128 for an ignored, untracked, existing file, see the CI finding at the end of section 4): a no-op with exit 0 on an ignored untracked file, stages a tracked modified file, exit 128 only for a nonexistent path.
  - A plain `cp` onto a read-only file fails; `mv -f` over it succeeds (executed).
  - `mv -f tmp dir` moves tmp INTO the directory and exits 0 (hence the dir guard and the post-swap compare).
- **Diagnose docs:** 660, all parse, all carry `date:` and `symptom:`. `bug_id` == the 6-character filename suffix for 648 and == the full stem for 12 (10 `2026-05-16-*` with no suffix, plus `-logpr-bypass` and `-workout-schedule-service-bypass`). No README.md or TEMPLATE.md exists there.
- **Reviews:**
  - Frontmatter `blast_radius:` carries trailing text in 10 of 314 (e.g. `account (L tier: auth)`, `platform   # …`).
  - 45 of 179 archive headers are unbolded (`blast-radius platform (…)`).
  - On 170 reviews with both fields, the date matches 170/170 and the first-word tier matches all but one genuine divergence.
  - The largest review is 84 KB, the archive 417 KB.
- **Bug classes:** 122 entries, max 2.113, 9 duplicates; next free 2.114.
- **Platform:** no merge queue for User-owned repos. CI ~5 min per run. 8 unmerged remote branches (excluding `oi/`, `mig/`, dependabot); 1 touches an index.

## 1. Bug history (§4.1.5)
- OI-309; OI-167 (b7e3d1, the §4.9 2026-09-29 row, `check_oi_numbering_unique.dart`, `mint_migration.sh`).
- Hook copies: memory 2026-10-11, OI-104 (closed). A recurrence → A0 full-template diagnose doc.
- Forced merge-only reviews (C). Dangling `check_oi_index_fresh` (A2).
- A renamed review skips its tuning entry (`check_skill_tuning_history.dart:37`): found in review, fixed in A1.

## 2. Writers and readers (§4.1)

| Artifact | Writer(s) | Reader(s) |
|---|---|---|
| `OPEN_INDEX.md` | `build_oi_index.dart:299` (non-atomic; `exit(1)` :229, :243, :263, :290, :296) via `pre-commit.sh:203-210` (`git add` :209), `pre-merge-commit.sh:103-187` (validate, backup/restore :166/:187, NOTE :176-186), CI `test.yml:356-373` | agents (CLAUDE.md :38, :349); `check_context_artifact_budget.dart:48`; `context_artifact_tracked_list_test.dart:64-68`; `check_no_deferral_euphemism.dart:358`; `closed_issues.md:9`; `GO_LIVE_CHECKLIST.md:215`; `hooks.md:175` |
| `diagnoses/INDEX.md` | `build_bug_index.dart:158` (non-atomic; `exit(1)` :21, :65; skip-unparseable :31-34; `e['date'] as String` :74) via `pre-commit.sh:186-193` (`git add` :192) | `check_regression_catalog.dart:15-20` (missing → exit 2; run on merge commits at `pre-commit.sh:401-407`); Gate 25 `check_diagnose_index_fresh.dart:45-59`; agents (CLAUDE.md :115, :345; `discipline_hook.dart:57`, `.opencode/plugins/discipline.ts:45`); `check_no_deferral_euphemism.dart:348`; `update-docs/SKILL.md:42` |
| installed hooks | `setup-hooks.sh:62-78` | git; Gate 32 `check_hooks_installed.dart` (parser :64-73, count :136, per-hook loop :187, text :252, :269, comments :44-46, :230-232) |
| tuning entries | agents → `tuning-history.md` per `code-review/SKILL.md` template (:25-60), step 5 (:231), §5 (:247) | `check_skill_tuning_history.dart:35-48, :72-76, :97-107, :112, :137-141` → `skill_tuning_lib.dart:71, :107-108, :122-125, :145-175, :183-221`; `batch_close_lib.dart:221`; hash pathspecs `check_code_review_pass_exists.dart:160-162` |

## 3. Decisions
- **D1:** the two indexes become local build products (A2).
- **D2:** a tuning entry is a section inside its review file; the archive is frozen (A1).
- **D3:** bug-class uniqueness gate + legacy fix (B).
- **D4:** record-aware resolver (C).
- **D5:** merge train only after a comparison (D).
- **D6:** no hook shims; A0 makes copies transition-safe and installs atomic.
- **D7:** no automatic index rebuild in Claude Code hooks. Staleness is detected by a stat-only nudge that spawns nothing. Builds are automatic only in git hooks and CI.

## 4. Landing A0 — copies survive untracking; atomic, read-only install (branch `merge-conflict-treadmill`)
- **`pre-commit.sh:196-197, :216-217`:** `git add <index>` → a tracked-only guard (`git ls-files --error-unmatch -- <index>`) and then `git add -u -- <index>`. The first form, `git add -u -- <index>` alone, failed in CI on git 2.55.0 (see the CI finding at the end of section 4). `pre-merge-commit.sh` is unchanged in A0.
- **`setup-hooks.sh` `install_hook`** (signature `install_hook() {` kept, the five literal call lines at :74-78 kept, no quoted call shape in any comment/echo/heredoc, no `$` in the README body, no `${X:-}` idiom: the env scanner `spawn_env_scan.dart:290-300` reads those as env inputs). For each hook:
  1. `[ -d "$dst" ]` → record "destination is a directory" and return.
  2. `rm -f "$tmp"`, then `cp "$src" "$tmp"`.
  3. `cmp -s "$src" "$tmp"` BEFORE the swap (R5B-2).
  4. `if ! chmod +x "$tmp" && [ ! -x "$tmp" ]` → record a PERSISTENT failure (git silently skips a hook that is not executable; a filesystem where chmod fails but the copy is already executable is accepted); `chmod a-w "$tmp" || echo warning` (losing the read-only bit only loses the protection).
  5. `mv -f "$tmp" "$dst"`. On failure and ONLY then, `chmod u+w "$dst" 2>/dev/null`, retry once, and on a second failure restore `chmod a-w "$dst"`. Linux needs no `u+w` (rename needs directory write permission); the retry is the Windows fallback, and is unverified there.
  6. `cmp -s "$src" "$dst"` AFTER the swap (the "lying `mv`" case) before printing "installed".
  - Every step is `if ! …; then record "<hook>: <step>"; rm -f "$tmp"; return 0; fi` (the five call lines at :74-78 are plain, so `set -e` IS active inside the function: both standalone `chmod u+w`/`chmod a-w "$dst"` lines, every README-block command and the summary commands end in `|| true`, otherwise a failed chmod aborts the installer before record-and-continue).
  - `trap 'rm -f "$HOOKS_DIR"/*.tmp."$$"' EXIT` and `trap 'exit 1' HUP INT TERM` (set after `HOOKS_DIR` is assigned; own pid only; dash does not run the EXIT trap on signal death). The per-step `rm` and the trap overlap on every non-signal path, so "drop the EXIT trap" is killed by case 16 (the README tmp has no explicit `rm`) and case 13 (signals), not by case 8. Leftover read-only `*.tmp.*` files are inert (Gate 32 reads only the five named hooks), and the README says they are safe to delete.
  - After the core.sshCommand config (:91-93): if any hook was recorded, list each with its cause. For persistent causes (missing source, directory at the destination, read-only filesystem) print "fix the tree; retrying will not help". For transient ones print "retry when no commit is running". Exit 1.
  - **Shipped behaviour (A0 B-pass F1 + delta F1/F2/F7/F8):** the installer REFUSES, BEFORE any hook is replaced, when `git merge-base --is-ancestor origin/main HEAD` exits 1 (exit 128 = no `origin/main` ref installs silently; a tree AHEAD installs). The cause is told apart so the advice is right: behind (`--ff-only` fixes it), diverged (merge or push), unreadable (git's own error is shown). `--allow-stale` overrides. A second guard refuses a tree that is not on `main` when its hook sources differ from `origin/main` (`git diff --name-only origin/main -- <the six sources>`; on `main` it is a WARNING; `--allow-unmerged` overrides). Unknown arguments exit 2 before anything runs; `--help` exits 0. This uses local refs and no fetch (R5B-5). The original plan said "loud line, install still succeeds"; the first B-pass showed a current installer run from a stale checkout would downgrade the shared hooks for every session, so it became a refusal.
  - It writes `$HOOKS_DIR/AVYA-HOOKS-README.txt` via tmp + `mv`. A failed README write is a warning, not a failed hook. Content: read-only copies; install only from the primary after `git fetch origin main && git merge --ff-only origin/main`; "Permission denied" from an installer means that tree's installer is old, so update the tree and never chmod/rm; `*.tmp.*` is safe to delete.
  - Header lines :4-5, :31-35 and the echo at :95 are updated.
- **Guidance** (channels that reach stale trees):
  - the README sidecar;
  - one line in the harness `MEMORY.md` index;
  - Gate 32's fix text (:252, :269) keeps the substring `STALE` (asserted at `check_hooks_installed_e2e_test.dart:138`) and carries the same recipe; comments :44-46 and :230-232 aligned;
  - CLAUDE.md §0 :37 and §4.13.2 (hook install is a primary operation);
  - `hooks.md:73-74`; `FRESH_CLONE.md:31-36`;
  - rollback recipe (`chmod u+w <hooks>/*`, then install) named as the one sanctioned exception to "never chmod".
- **`docs/blast_radius.yaml`:** `- { glob: "scripts/setup-hooks.sh", tier: platform }` beside `pre-push.sh` (:246), before the catch-all (:483). Prose :243-244 rewritten. `'scripts/setup-hooks.sh'` added to `enforcementPaths` (`blast_radius_content_rule_wired_all_scripts_test.dart:92-105`).
- **Diagnose doc** `docs/diagnoses/2026-10-22-hook-install-in-place-and-ignored-index-add-<id>.md` (full template, recurrence, `touched_layers_checked`), committed with `fix(hooks): …` + `closes-diagnose:`.
- **Tests.**
  - **`test/scripts/pre_commit_index_add_e2e_test.dart`** (file-level `@Timeout` + `library;`, `runSpawn(why:)`):
    - Fixture:
      - `pre-commit.sh`, `build_oi_index.dart`, `build_bug_index.dart`, `bug_index_lib.dart`;
      - NO `_dart_bin.sh`, so the guard at `pre-commit.sh:59` falls to the PATH `dart` at :82;
      - a PATH-stub `dart` that execs the real dart (via `dartBin()`, POSIX form) only for the two builders and exits 0 otherwise;
      - a board with ≥1 OPEN OI carrying `Blocked on` and `Verified`;
      - a seed commit holding stale tracked indexes.
    - The hook is run directly, so the exit code is the verdict.
    - Cases, with the board index and the diagnoses index each tested separately:
      - (1a) board staged, index tracked → `OPEN_INDEX.md` staged;
      - (1b) diagnose doc staged, index tracked → `INDEX.md` staged;
      - (2a, 2b) the same with the index `.gitignore`d and untracked → exit 0, file built, not staged;
      - (3) a duplicate `## OI-N` → exit 1 with the index tracked and with it ignored.
  - **`test/scripts/setup_hooks_atomic_install_e2e_test.dart`** (POSIX-only; skip when uid 0; tearDown `chmod u+w` first; `startSpawn`/`reportSpawn`; file-level `@Timeout` + `library;`). Each case names the mutant it kills:
    - (4) re-install over read-only hooks succeeds; the hooks stay non-writable AND executable (`mode & 0111 != 0`, fixture sources written 0644 so `chmod +x` is load-bearing); `cmp` equal. [drop `a-w` → red; drop `chmod +x` → red]
    - (5) an old-style plain `cp` over an installed hook fails and the bytes are unchanged. [drop `a-w`]
    - (6) running `sh` explicitly: a hook larger than 16 KiB writes a "started" marker in its first 8 KiB block, then waits for a handshake file, and is replaced with DIFFERENT shorter content → the installer exits 0, `cmp` shows the NEW content in place, AND the end marker is still written (otherwise a mutant that keeps `a-w` leaves the old inode untouched and stays green for the wrong reason). [in-place `cp` → red]
    - (7) a missing middle source (`scripts/commit-msg.sh` deleted) → the other four install, exit 1, the hook named, the "fix the tree" wording. [stop on first failure]
    - (8) a PATH-stub `mv` that fails → exit 1, no `*.tmp.*` anywhere under the hooks dir (recursive scan), the old hook intact AND non-writable; a second run on a FRESH hooks dir (no old hooks) names all five hooks, exits 1 and does not abort early; the transient "retry when no commit is running" wording is printed. [drop mode restore; drop `|| true` on a `chmod`]
    - (9) `dst` is a directory → recorded failure, exit 1, the directory stays EMPTY, no tmp anywhere, the directory-specific message. [drop the dir guard]
    - (10) the real `setup-hooks.sh`: run `check_hooks_installed.dart` against an install from it and assert `PASS: all 5 hook(s)` (UNDETERMINED would exit 0 without that line); no `WARN`/`staleness` text in the Gate 32 output; the installed hooks are executable; also a regex over the file asserts no quoted call shape outside the five calls. [`install_hook () {`; a quoted shape]
    - (11) a PATH-stub `mv` that exits 0 and moves nothing, on a FRESH hooks dir (with `dst` already equal to `src` a lying `mv` is indistinguishable) → exit 1, the hook named, no "installed" line for it. [drop the post-swap `cmp`]
    - (12) a foreign `pre-commit.tmp.foreign` (non-numeric, so it can never be a live pid) pre-created, then a failing-`mv` install → the foreign tmp survives and the own-pid tmp is gone. [widen the trap glob]
    - (13) a stub `mv` that runs `kill -TERM $PPID; exit 0`, only when `sh` is dash → no tmp left. Where `sh` is not dash the case is skipped and the residual is recorded in the diagnose doc. [drop the signal traps]
    - (14) a stub `cp` that writes different bytes to its LAST argument (so `cp -f`/`--` do not shift `$2`), with a stale live hook present → the pre-swap `cmp` fails and the live hook keeps its old bytes. [drop the pre-swap `cmp`]
    - (15) the tree is behind / diverged / unreadable relative to `origin/main` → REFUSED (exit 1, hooks untouched, no README), with cause-specific advice; `--allow-stale` installs with a warning; a STALE linked worktree is refused while the primary's `main` is current (HEAD, not `main`, is compared); up to date, ahead and a missing `origin/main` ref (exit 128) install with EMPTY stderr; a feature branch whose hook sources differ from `origin/main` is refused (`--allow-unmerged` installs with a warning, on `main` it only warns, an uncommitted edit is seen too); an unknown argument exits 2 and `--help` exits 0 without installing; a run from a subdirectory of the primary prints no linked-worktree note. [drop the refusal; HEAD → main; drop `2>&1`; drop `-C`; drop the diff guard]
    - (16) a PATH-stub `mv` that fails only when its last argument ends in `AVYA-HOOKS-README.txt` → the five hooks install, exit 0, a warning is printed, and no README tmp is left (the README tmp has no explicit `rm`, so only the EXIT trap removes it). [README failure counted as a hook failure → exit 1; drop the EXIT trap]
    - (17) after a normal install the README exists, contains the recipe markers (`ff-only`, `Permission denied`, `*.tmp.*`) and no `$`. [drop the README write]
- **Mutations** (each applied with `grep -c` proof, run, reverted, as above):
  - plus, for the tracked-only guard that replaced the bare `git add -u -- <index>` after the CI finding: the guard always true / inverted / testing the other site's path / HEAD-keyed / ignore-keyed / without `--error-unmatch` / with its stderr visible, each applied separately at :196 and :216; the add dropped, swallowed (`|| true`) or spelled bare `git add -u`; the diagnose builder's `exit 1` dropped; the stub dropped from the hook's PATH; spellings of `add` the stub does not model (26 mutants, all red);
  - plus the README-write failure counted as a hook failure → case 16 red.
  - plus: `chmod +x` dropped → cases 4/10 red; the EXIT trap dropped → cases 13 and 16 red (not case 8: the per-step `rm` masks it; on a non-dash `sh` only case 16 kills it, which the diagnose doc records).
  - The Windows-only retry is unverifiable on Linux; it is recorded as such.
- **Roll-out:** after the merge, the primary runs `git fetch origin main && git merge --ff-only origin/main && sh scripts/setup-hooks.sh`; the founder runs it once on Windows.
- **CI finding (2026-10-24, PR #159):** the design above said `git add -u -- <index>` is "a no-op for an untracked one". That held on this VPS's git 2.43.0 and is false on the CI runner's git 2.55.0, where it exits 128 ("pathspec ... did not match any file(s) known to git") and cases 2a/2b went red. The landed form is a tracked-only guard: `git ls-files --error-unmatch -- <index>` decides, then `git add -u -- <index>`. The e2e test now runs the hook with a PATH-stub `git` that reproduces the 2.55.0 answer, refuses every spelling of `add` it does not model and logs its calls, so the guard cannot be deleted, and the stub cannot be bypassed, without a red case on any git (case 0 proves the stub; 4a-4d use one tracked and one ignored index to tell the two sites apart; 5a-5c cover the untracking commit and an untracked, non-ignored index; 6a/6b a failing add stays fatal; 7a/7b a tracked index that rebuilds identical). A delta B-pass (one fresh seat, 0 P0/P1, 3 P2, 3 P3, all closed) strengthened the tests; the guard itself was correct in every index state it built. Mutation proof: 26 mutants, all red. Details and the recurrence class are in the diagnose doc `c5e1a8`.

## 5. Landing A1 — tuning entry inside the review file (branch `tuning-entry-in-review`; independent of A0)
- **Scope** (R4A-12): every `.md` added under `docs/reviews/` (except INDEX.md, README.md) that carries a line-anchored `reviewed_at:` — `-bpass`, `-review`, `-groundtruth`, `-merge-review`, and the like.
- **Convention.** The FIRST qualifying `## Tuning entry` section in file order is judged:
  - **Scanner.** A single-pass line state machine, not strip-then-strip:
    - Fences follow CommonMark: backtick or tilde, closing length ≥ opening length. An unclosed fence runs to EOF.
    - `<!--` … `-->` spans lines.
    - A fence opener inside a comment, or a comment opener inside a fence, is inert.
    - CRLF is normalized as `reviewedOnFrom` does (`trimRight`).
    - A rejected section's message names the construct and its line ("unclosed fence opened at line N").
  - **Heading** `^## Tuning entry[ \t]*$` exactly, at column 0, outside fences and comments.
  - **Header.** The first non-blank line after the heading is a dated bullet (the shared `isDatedHeaderLine`), and its date equals `reviewed_at`.
  - **Tier rule** (R5B-6, R5A-10):
    - Header tier = the first `[a-z]+` after `blast-radius\s+\**`, case-insensitive.
    - Frontmatter tier = the first word of the `blast_radius:` value after stripping an optional quote. Frontmatter is parsed only inside the leading `---` block.
    - Compared only when BOTH are one of feature, account, platform or catastrophic (a template placeholder or free text skips the check).
    - A mismatch message prints both values and says which to edit.
  - The entry need not name the review basename.
  - `docs/reviews/` is already excluded from the staged-diff hash, so `check_code_review_pass_exists.dart:160-162` and `SKILL.md:182` keep all three exclusions (pinned at `review_gate_staged_content_not_working_tree_test.dart:287`). Only the rationale prose at :121-139 and `SKILL.md:188-203` gains a sentence.
- **Lib** (`skill_tuning_lib.dart`):
  - public per-line `isDatedHeaderLine`, `inReviewEntry(String review, String isoDate, String? tier)`, `countDatedHeaders`;
  - `evaluateTuning` evaluates the in-review route FIRST, independent of the archive. A null archive then only means "no legacy entries": a review failing both routes is `missingEntry`, never `undetermined` (R4A-7).
  - A dateless review stays fail-open, as today.
  - `ReviewClaim` gains a named optional field.
- **Gate** (`check_skill_tuning_history.dart`):
  - Added reviews come from `git diff --cached --name-status --diff-filter=A` with `--no-renames` ONLY when there is no `MERGE_HEAD` (R5B-9): a renamed review then shows as D + A and needs a section; inside a merge, renames from main keep default detection so a bulk move on main cannot block every sync.
  - **Freeze**, computed after the `added == null` check (:72-76) and before the reviews filter and early exit (:97-101), exit codes combined at the end:
    - Mid-merge = the path from `git rev-parse --git-path MERGE_HEAD` exists (matches the `check_oi_numbering_unique.dart:337-383` precedent, which treats a present-but-unresolvable MERGE_HEAD as mid-merge). Mid-merge → exempt.
    - Otherwise, when the HEAD blob and the staged blob both exist and `countDatedHeaders(staged) > countDatedHeaders(HEAD)` → fail. HEAD blob absent → not applicable (R4A-6).
    - Message: the added header lines; the restore command `git restore --source=HEAD --staged --worktree -- .claude/skills/code-review/tuning-history.md`; for each added review the exact `## Tuning entry` text built from its `reviewed_at` and normalized tier; a note that a dated SUB-bullet counts as an entry; `--warn-only` honored.
    - The pre-commit loop hides gate output (`pre-commit.sh:371`), so SKILL.md, `hooks.md` and the template all say: "re-run `dart run scripts/check_skill_tuning_history.dart` on the staged state to read the message".
    - Squash, cherry-pick and revert are not exempt.
  - Local-only and transitional (pre-A1 branches merged on GitHub can still grow the archive). Stated in the gate header and `hooks.md`.
  - Header comment (:3-9, :16-18) and fail text (:137-141) rewritten (the fail-open statement at :16-18 and `skill_tuning_lib.dart:51-52` becomes: an unreadable archive no longer silences the in-review route).
- **Archive:** a freeze note in the intro (lines 3-7) that contains no literal dated bullet (`YYYY-MM-DD` is safe).
- **Docs:**
  - `code-review/SKILL.md`: template (:25-60) gains the stub; step 5 (:231); §5 (:247); §7, read recipe `grep -h -A3 '^## Tuning entry' docs/reviews/*.md | grep '^- \*\*'` plus the archive.
  - `docs/reviews/README.md`.
  - `hooks.md:205, :625-628`.
  - `batch_close_lib.dart:221`.
  - `gate_test_ledger.yaml:800-830`, evidence for the new mutants; mutation (2) "COLLAPSE THE FAIL-OPEN" (:818) rewritten.
  - CLAUDE.md §5.1 (:298), §7 rows :351 AND :355, §4.9 :262.
  - `common-pitfalls.md:335, :339`.
  - `check_no_deferral_euphemism.dart` comment: reviews are scanned once at add time (staged `*.md`, :190) and never re-swept (R4A-9).
- **Tests.**
  - **Existing tests that flip** (R5A-11, R5B-8):
    - `skill_tuning_lib_test.dart:165-173` ("FAILS OPEN when the skill file cannot be read") → a review without a section and with a null archive is `missingEntry`;
    - `skill_tuning_history_e2e_test.dart:190` ("FAILS OPEN when the skill file is absent entirely") → exit 1.
    - Kept unchanged: `skill_tuning_lib_test.dart:175` and e2e `:199` (dateless fail-open), and `:184`.
  - **New** (a fixture helper commits the archive first; one staged-only-archive fixture is kept on purpose as the killer of "HEAD-absent counted as 0", named in the table):
    - section satisfies;
    - section satisfies with the archive absent;
    - wrong date;
    - tier mismatch; tier with a suffix (`account (L tier: auth)`) passes; unbolded header passes;
    - heading inside a fence (3-backtick, 4-backtick, tilde); heading inside a comment; a fence containing `<!--`; a comment containing a fence;
    - an unclosed fence names its line;
    - a heading with trailing words (`## Tuning entry …`) does not count;
    - a valid dated bullet with no heading fails;
    - the dated bullet not first after the heading fails;
    - CRLF review passes;
    - legacy review with an archive entry passes in a merge;
    - non-merge archive growth fails;
    - archive shrink passes;
    - in-place header edit passes;
    - archive growth with no review added fails;
    - `--warn-only` warns;
    - a linked-worktree fixture using a real `git merge --no-commit --no-ff` state exempts;
    - MERGE_HEAD present as a directory or an empty file is treated as mid-merge (portable; no `chmod 000`);
    - a renamed review without a section fails, with a section passes;
    - a rename inside a merge is not forced through `--no-renames`.
- **Mutations:**
  - date equality dropped;
  - heading requirement dropped (the dated-bullet-no-heading case);
  - fence stripping dropped; comment stripping dropped; single-pass replaced by two-pass (the fence-with-comment cases);
  - tier check dropped; whole-value tier comparison (the suffix case);
  - freeze on merges; freeze after the early exit;
  - `>` → `!=` (the shrink case);
  - HEAD-absent counted as 0 (the staged-only-archive fixture);
  - archive-first evaluation (the absent-archive case);
  - `--no-renames` always on / never on;
  - `.git/MERGE_HEAD` hardcoded (the linked-worktree fixture).
- **Known limit, stated:** a later edit that deletes a review's section is unchecked (the gate judges additions). The sibling `batch_close_hook.dart:210` keeps its rename-blind `--diff-filter=A` for an informational row.

## 6. Landing A2 — indexes become local build products (branch `local-indexes`; after A0 is merged AND installed, including the founder's confirmation for the Windows clone)
- **Untrack:**
  - `.gitignore` gets both exact paths, with a comment pointing to A0 / `setup-hooks.sh`. `git rm --cached` both.
  - `retire_worktree_lib.dart:238` gets both (`.dart_tool/` is already at :248; `gitignore_classification_test.dart`).
- **Shared lib `scripts/local_indexes_lib.dart`** (R5C-1): the single home for:
  - the stamp digest;
  - `isStale(root)` (one predicate, shared with the builders' input scan);
  - the atomic write.
  - A `File(...).existsSync()` there needs a `// file-only:` comment (`gate_existssync_file_vs_dir`).
- **Builders import it** (`local_indexes_lib.dart` → `migration_ledger_hash_lib.dart`; `build_bug_index.dart` → `bug_index_lib.dart`). The structural cure (R6C-1): ONE helper in `test/helpers/` computes the transitive closure of relative imports from a named entry script and copies it into a fixture. Every fixture calls it instead of listing files; it is unit-tested on a synthetic import chain, and a grep test asserts no fixture names a builder in a literal copy list.
  - `pre_merge_commit_e2e_test.dart:143-149` (today a 5-file literal list; the OI builder's closure replaces it);
  - A0's `pre_commit_index_add_e2e_test.dart` fixture (both builders' closures);
  - fixtures that copy `pre-push.sh`, `new-worktree.sh` or the discipline hook alone do not run the builders and are unaffected.
- **Builders:**
  - Each becomes `int runOiIndex(String root, {bool strict = true})` / `int runBugIndex(String root, {bool strict = true})` returning an exit code; every `exit(1)` becomes a return; `main(a) => exit(run…(…))`. Names imported by `oi_index_test.dart` stay public.
  - **Strict** (pure `validateDiagnoseDocs` in `bug_index_lib.dart`): parse failure (replaces the `continue` at :31-34); missing `date:`/`symptom:` (before the sort at :73, which also fixes the TypeError on :74); id rule `bug_id ∈ {6-character suffix, full stem}` (660/660 pass today); README.md and TEMPLATE.md skipped like Gate 25.
  - **Lenient** (R5D-2, R5C-6, R5C-7g): the diagnose index skips bad docs, reports them, still writes. The OI index renders an unknown-status or missing-field row flagged and lists the offenders (the OI-68 scar: nothing vanishes silently). A DUPLICATE `## OI-N` still fails closed with no write, because a duplicate corrupts every pointer below it (the OI-collision invariant).
  - A bare run is strict. pre-commit and CI call bare.
- **Stamp inside each output.** Line 1 is `<!-- local-build: <sha256 of the sorted "name size mtime" text> -->`.
  - It is built with `sha256Hex` (`migration_ledger_hash_lib.dart:43`) over the STAT text, never `String.hashCode`, which is not stable across processes.
  - Inputs:
    - `OPEN_INDEX.md` ← `open_issues.md`, `build_oi_index.dart`, `local_indexes_lib.dart`;
    - `diagnoses/INDEX.md` ← every `docs/diagnoses/*.md` using the SAME predicate as the builder (`.md`, excluding `INDEX.md`; editor `*.md~` files do not count), plus `build_bug_index.dart`, `bug_index_lib.dart`, `local_indexes_lib.dart`.
  - The stats are captured BEFORE the inputs are read (R5D-8).
  - Readers tolerate the comment line (verified: the catalog row regex is `^\|\s*date\s*\|`; `oi_index_test.dart` tests the render and parse functions only).
  - Budget effect about +87 B on a 43,020 B baseline.
- **Atomic write:** a temp file under `<root>/.dart_tool/local_indexes/<name>.<pid>.tmp` (dir created), then rename. A rename that fails is retried once after 200 ms; if it still fails the old output stays and the exit is **3** (R6D-3: validation passed, write failed). Hooks print a warning and CONTINUE on exit 3 (the output is ignored and regenerable, and the nudge already reports a stale index); validation failures stay exit 1 and block. Stale `*.tmp` older than 1 h are swept on start. Windows behavior is unverified.
- **`scripts/build_local_indexes.dart`:**
  - Root = git toplevel, else the script's parent dir (`git archive` tree).
  - Strict by default; `--lenient`.
  - Runs BOTH builders regardless and returns the worst code.
  - **Self-check:** after a successful write, `isStale(root)` must be false, or the exit is non-zero.
- **Who builds (git hooks and CI only):**
  - **pre-commit:**
    - A staged diagnose doc or board runs the matching per-index builder as today (strict). A0's tracked-only guard makes it a no-op for an untracked file.
    - When `MERGE_HEAD` exists, the lenient bug-index build runs before the catalog walk at :401-407 (R5D-4, R5C-4), **only when `[ -f scripts/build_local_indexes.dart ]` and the bug index is untracked (`! git ls-files --error-unmatch`)** (R6D-2). Otherwise the existing path runs byte-for-byte: the old builder ignores `--lenient` and would rewrite a tracked `INDEX.md`, leaving a dirty tracked file after every merge commit. Test: a MERGE_HEAD fixture with a tracked index and old scripts asserts no file is modified.
  - **pre-merge-commit** (R5D-1, R5C-7a, R6C-2, R6C-4, R6D-4): keyed on **`git check-ignore -q -- docs/audit/OPEN_INDEX.md`** (not on `ls-files`: the three existing tests build a fixture where the file is neither tracked nor ignored and must stay unchanged). When ignored: keep the OI build and its duplicate-id gate, take NO backup (no `mktemp`, nothing to leak), never set `_SKIP_RENDER_CHECK`, never call `_restore_index` at either site (:167 failure branch, :187 final; a restore with `_INDEX_EXISTED=0` would `rm -f` the fresh build), and suppress the NOTE (:176-186). The flag is assigned beside `_INDEX_EXISTED=0` (:103-105), before the function body, with no `${X:-}` idiom (the env scanner reads line order). When not ignored the existing path runs byte-for-byte. **New coverage:** an ignored fixture, a tracked fixture, and an ignored fixture with a failing `mktemp` stub that must still run the duplicate check. No bug-index build in this hook (dropped: a freshness build only; the nudge covers staleness).
  - **pre-push: no build line** (dropped, rev 7). The full-suite test builds for itself and CI builds strictly.
  - **CI:** a plain strict step (no `${{ }}`, no `if:`) before :306 (Audit Gates) and before the shard run (:139). The OI-render step stays; its comment (:370-372) is corrected.
  - **`new-worktree.sh`: no build** (dropped, rev 7). The SessionStart nudge says "missing" on a new worktree's first session.
  - **The full-suite test builds for itself** (R5C-5, R6C-5): `local_indexes_lib.dart` defines the OI-index path constant and a pure `ensureLocalIndexes(root)` helper that builds the OI index (lenient) when it is missing. `context_artifact_tracked_list_test.dart`'s `setUpAll` calls it (OI index only: nothing in `test/` reads `docs/diagnoses/INDEX.md`). The helper is unit-tested in a temp directory with the index missing; the mutation (drop the build) reddens that test. This covers `PRE_COMMIT_FULL=1` (`pre-commit.sh:173-175`, before the regen), `/build-apk` Gate 5 (`build-apk.md:191-194`) and a bare `flutter test`. The failure message still names `dart run scripts/build_local_indexes.dart`. No change to `kTrackedArtifacts`, `_pinned` or `context_artifact_sizes.json` (a top-level key fails the two-way test; `--record` drops per-entry fields): the "measured as built locally" note goes in `hooks.md` and the budget gate's header comment.
  - **No Claude Code hook builds (D7).**
- **The nudge** (`discipline_hook.dart`):
  - **Branches:** SessionStart (:112) and the existing bug-trigger branch (:135). Not every prompt (R5D-3).
  - **Structure** (R5C-2): a `parts` list and ONE `_emit` call per event, as SessionStart does at :123-129. A bug-shaped prompt plus a stale index yields one JSON document.
  - **Own `try/catch`,** silent like its siblings.
  - **No spawn:** `Directory.current` is the checkout root, because the settings commands `cd` to it (fce6065c). It acts only if `scripts/build_local_indexes.dart` exists there. It uses one `FileStat.statSync` per input and reads only the first 256 bytes of each output.
  - **Stale or missing → one context line:** `Local indexes stale/missing — run: dart run scripts/build_local_indexes.dart --lenient (then read docs/audit/OPEN_INDEX.md / docs/diagnoses/INDEX.md)`.
  - **Hooks-not-reinstalled warning** (R6D-1): SessionStart only, one `git rev-parse --git-path hooks` spawn (SessionStart already runs about 15 git spawns), once, when the indexes are untracked here and the installed `pre-commit` or `pre-merge-commit` lacks the A2-only literal `build_local_indexes.dart`. (A0's tracked-only guard is always present at A2 time, so it cannot be the marker; A2 changes three hook files, and the A2 hooks contain A0's line, so one marker covers both.) Test: A0-only hooks produce the warning, A2 hooks do not. The PR body names the first-failure symptom (pre-A0 hooks on Windows: `git add` on an ignored index exits 1) and the fix command.
  - **No env reads, no kill switch.**
  - The 100 ms wall-clock assertion is DROPPED (flake source). A structural test uses a stat-counter seam and asserts that document bodies are never read; mutant: read contents.
- **Reader-side guard** (R5D-1): the OI index header and the CLAUDE.md read recipe say "the first line returned by `Read(open_issues.md, offset: <line>)` must be `## OI-N —`; otherwise rebuild".
- **New gate `check_local_indexes_untracked.dart`:** `git ls-files` of both paths must be empty; runs on the PR merge ref in CI. `mutation_proven: true` ledger entry whose test file names the gate and contains an `exitCode, 1`-style red-path assertion; it must clear `gate_existssync_file_vs_dir` and `gate_source_literal_brittleness`.
- **Delete Gate 25.** Update:
  - `gate_test_ledger.yaml:286`; `check_gate_test_ledger.dart:58`;
  - `LENS_REGISTRY.md:121` (L44); `bug-classes.md:100, :106`; `debugging/SKILL.md:129` (row 2.15); `update-docs/SKILL.md:42, :75`;
  - `check_closes_oi_performed.dart:141-143` (still says "regenerate the index");
  - the comments at `check_gate_index_fresh.dart:4` and `check_adr_index_fresh.dart:3`;
  - `GATE_INDEX.md:43` (regen).
  - Historical mentions stay.
- **Agent guidance:**
  - CLAUDE.md :38 (the pre-commit bullet: index regens become local builds; hooks text), and the read recipe at :115, :345, :349: read via Read or plain `grep` on the explicit path, never `git grep` or an ignore-respecting directory walk; if absent or stale, run the builder with `--lenient`; no-Dart fallbacks `grep -n '^## OI-' docs/audit/open_issues.md` and `grep -ril <term> docs/diagnoses/`. Isolation worktrees (`agent-*`) get neither the nudge nor the files (ignored files are not copied; SessionStart does not fire for subagents), so the fallback lives in the recipe subagents load (R6D-5).
  - `docs/agent_brief_preamble.md` repeats the fallbacks and "the index may be absent or stale; the source docs are authoritative" (R5D-7). A coordinator builds before dispatching only for subagents that share its cwd.
  - `_hotSet` (`discipline_hook.dart:57`) and `.opencode/plugins/discipline.ts:45` gain "(build it first if absent)".
- **Other docs:** `hooks.md:46, :117, :175, :490, :703`; `FRESH_CLONE.md`; `docs/operations/GO_LIVE_CHECKLIST.md:215` and `closed_issues.md:9` → `open_issues.md`; `tech-debt-audit` SKILL; `naming_conventions.md` ("local build product", "local-build stamp"); `.opencode/plugins/discipline.ts:25, :45` carries a hand-copied `_hotSet` (edit both by hand, nothing pins it).
- **SoT registry:** `local_generated_indexes` is registered in the SAME commit as the A2 diagnose doc (`check_sot_registry_citations` fails a doc whose concept does not resolve; its `sot_registry_entry:` is `local_generated_indexes`). Writers: the two builders with `line_range: 1-9999` (the `coach_write_claim_wording` precedent; a narrow range around `runOiIndex` goes stale on the next edit, and the parity gate needs the method symbol in non-comment code inside the range). Readers: §2, but NOT the generated outputs as `file:` entries (Gate 7 requires the file to exist). `behavioral_test_path: test/scripts/local_indexes_e2e_test.dart`. The description avoids the literal text `key_prefix:`.
- **`docs/blast_radius.yaml`:** platform rows for `build_oi_index.dart`, `build_bug_index.dart`, `bug_index_lib.dart`, `local_indexes_lib.dart`, `build_local_indexes.dart`, `check_local_indexes_untracked.dart`.
- **Tests.** All spawn tests use `runSpawn`/`startSpawn`, a hermetic env, file-level `@Timeout` + `library;`.
  - **`test/scripts/local_indexes_e2e_test.dart`:**
    - a staged board leaves the index untracked;
    - a duplicate OI blocks (strict AND lenient);
    - strict fails on unparseable / dateless / symptomless / id-mismatch docs;
    - the 12 legacy id shapes pass;
    - lenient writes and reports, and clears the nudge for a dateless WIP doc;
    - the orchestrator self-check fails on a stale-after-build;
    - a deleted doc AND an added doc change the stamp;
    - a `git archive` tree builds;
    - cwd ≠ root;
    - a unreadable output (a directory at the path) is replaced or reported;
    - the output inode changes across a rebuild (POSIX-only; skipped on Windows);
    - an unwritable target → exit 3 with a warning while a duplicate OI still exits 1 (hook case);
    - `ensureLocalIndexes` builds a missing OI index in a temp directory.
  - **`test/scripts/bug_index_strict_test.dart`** (pure `validateDiagnoseDocs`).
  - **`test/scripts/check_local_indexes_untracked_test.dart`.**
  - **`test/scripts/discipline_hook_local_indexes_e2e_test.dart`:**
    - fresh → nothing; stale → one line; missing → one line;
    - a fixture without the builder → nothing;
    - an unreadable output → the other SessionStart parts still emitted;
    - the bug-trigger branch emits one JSON document when both the hot-set and the nudge apply;
    - UserPromptSubmit on a non-bug prompt → nothing;
    - the hooks-not-reinstalled warning (A0-only hooks warn; A2 hooks do not);
    - the stat-counter structural test;
    - one stale-fixture case through the real settings command (`claude_hooks_cwd_independent_test.dart:446-448` runs every settings command from `supabase/functions`).
  - **Fixture closure helper:** unit test on a synthetic chain, plus the no-literal-copy-list grep test.
  - **Presence tests:** the CI steps precede the gate loop and the shard tests.
  - **Updates:** `pre_merge_commit_e2e_test.dart` (closure helper; ignored, tracked and failing-`mktemp` fixtures); `pre_commit_index_add_e2e_test.dart` (A0's; closure helper; MERGE_HEAD fixture with a tracked index and old scripts); `context_artifact_tracked_list_test.dart` (`setUpAll`).
- **Mutations:**
  - the stamp ignores deletions; ignores additions; omits mtime; omits the builder inputs; unsorted list;
  - the id rule = suffix-only (the 12 legacy docs red);
  - a builder calls `exit()` (orchestrator test red);
  - a non-atomic write (inode seam red);
  - the gate accepts tracked;
  - the CI step dropped;
  - the nudge's own catch dropped; the existence guard dropped; two `_emit` calls;
  - the self-check dropped;
  - the nudge reads contents;
  - pre-merge-commit still restores when ignored; the NOTE not suppressed; the backup taken (leak); the skip flag set;
  - the pre-commit MERGE_HEAD build runs without the tracked/builder guard (mixed-fleet fixture red);
  - a write failure exits 1 instead of 3;
  - `ensureLocalIndexes` drops the build;
  - the warning keyed on A0's line instead of the A2 literal.
- **Process:**
  - The diagnose doc (dangling `check_oi_index_fresh` + latent stale-index risk) goes in the first commit.
  - The PR edits `test.yml`, so the merge is `safe_pr_merge.sh <N> --allow-workflow-change` on the founder's go.
  - **The founder confirms in chat that the Windows hooks are reinstalled BEFORE the A2 merge** (it cannot be verified from the VPS).
  - **Roll-out recipe** (in the PR body and the A0 README): in the primary, `git checkout -- docs/diagnoses/INDEX.md docs/audit/OPEN_INDEX.md` if dirty; fast-forward; `dart run scripts/build_local_indexes.dart --lenient`; re-run `setup-hooks.sh` (pre-push changed).
  - **Merge note:** a branch that edited either index hits one modify/delete conflict → `git rm --cached` both paths, then run the builder. A pre-A2 worktree with a dirty tracked index (pre-A2 builders write it in place) refuses the sync merge ("local changes would be overwritten"): `git checkout -- docs/diagnoses/INDEX.md docs/audit/OPEN_INDEX.md` first (R6D-6). Today 1 of 8 unmerged remote branches is affected; unpushed in-flight work is the same conflict count as today, now with a one-line recipe.
- **Build notes (A2 as built, 2026-10-24; deviations from the text above, each found while building):**
  - `ensureLocalIndexes(root)` lives in `build_local_indexes.dart`, not in `local_indexes_lib.dart`: the builders import the lib, so a lib that called `runOiIndex` would be an import cycle. `context_artifact_tracked_list_test.dart` imports it from there.
  - The strict `bug_id` rule compares the value UNQUOTED (one pair of surrounding quotes is stripped, mismatched quotes still fail): the real doc `2026-10-23-dow-skip-rate-132315.md` writes `bug_id: "132315"`. Found by the first strict build on the real corpus; `bug_index_strict_test.dart` runs the rule over every doc in the repo.
  - The gate lists a path once however many index stages it has (a conflicted merge prints an unmerged path once per stage) and does no sort: `git ls-files` already emits index order.
  - `check_diagnose_index_fresh.dart` (Gate 25) was deleted together with its ledger and grandfather entries; `GATE_INDEX.md` was regenerated.
  - The A0 `pre_commit_index_add_e2e_test.dart` cases 7a/7b (a tracked index rebuilt by the OLD builders) run against FROZEN copies of the pre-A2 builders in `test/scripts/fixtures/pre_a2_index_builders/` (with a README), because the closure helper would otherwise copy the new builders into them.
  - `ci_local_indexes_steps_test.dart` also EXECUTES the workflow's own `run:` string against a board with an unknown status and a dateless diagnose doc, so `--lenient`, `|| true` or another script fails by behaviour as well as by text.
  - The roll-out recipe's "(pre-push changed)" is stale since rev 7 dropped the pre-push build line: A2 changes `pre-commit.sh` and `pre-merge-commit.sh` (and no other hook), so those two are what a machine must reinstall, and what `discipline_hook.dart`'s hooks-not-reinstalled warning checks.
  - The SoT concept lists six `behavioral_test_path_*` siblings (strict validation, both hooks, the nudge, the CI steps, the gate) besides the e2e file.
  - **B-pass fixes (two fresh seats, 2026-10-24), each a deviation from the text above:**
    - `check_regression_catalog.dart` makes sure of its OWN input (`ensureBugIndexFresh` in `build_local_indexes.dart`: build lenient when the diagnose index is missing or stale). The plan had only the hook build it before the walk; hooks are copies, and the FROZEN A0 hook against an A2 tree blocked a merge commit in a fresh worktree with a "regression catalog" message about a missing file. The hook's own lenient build stays (its exit-code policy and tracked-index guard); the walk is the net under every older copy. The impact analysis "does not block" was false for that cell and is corrected; `test/scripts/fixtures/pre_a2_hooks/` holds the A0 hooks frozen for cases 9h-9k and the `pre_merge_commit_e2e_test.dart` group.
    - The strict `date:` rule is a BARE `YYYY-MM-DD` (no quotes, no free text). Gate 25 is gone, so the rule is the only guard, and the regression walk keeps only index rows whose first cell has that shape: a quoted or free-text date sorted wrongly and silently dropped that bug's test from the walk.
    - A `## OI-N` header the section regexp cannot read (hyphen or en dash for the em dash, U+2028 in the title, no title) fails strict and is listed under "Needs attention" in lenient; it used to vanish from the index with exit 0 (the OI-68 scar, one step earlier). An unreadable board (not valid UTF-8) and an unreadable `docs/diagnoses` are exit 1 in both modes, and `runLocalIndexes` guards each builder so one that throws counts as 1 and does not stop the other (the header promise "both builders always run").
    - `diagnoseDocNames` lost its unused `list:` seam (nothing counted the directory reads); the STRUCTURE test now slices it and `indexInputPaths` as well, since they run on every SessionStart.
    - `build_gate_index.dart` counted the numbered gates from the claims, including the one a closure ledger still mints for the deleted Gate 25, so `GATE_INDEX.md` said 48 numbered where its table shows 47.
    - CLAUDE.md §4.12.8's gate loop says `flutter analyze --no-fatal-infos` (the whole project, as pre-push runs it) instead of `flutter analyze lib/`: a seat found a `warning -` in a new `test/` file that the `lib/` loop could not see and pre-push would have refused.
    - The 48 `(relocated 2026-05-18 — see docs/diagnoses/INDEX.md)` pointers in the nested CLAUDE.md files and the `*-detail.md` docs now say `a local build: CLAUDE.md §4.1.5`.

## 7. Landings B–D
Each gets its own revision and two review rounds, the last converged, before code.
- **B (OI-167):** a uniqueness gate + lib; the legacy 9 renumbered from 2.114 after reading every citation (excluding reviews, plan-reviews and closure ledgers). Before C.
- **C:**
  - U3: remerge ∪ both-sides overlap; full ref name; fallbacks.
  - U5: the record-aware resolver; builders last; fixtures projected through A1/A2; the archive off the allow-list; YAML structural checks.
  - Diagnose doc for forced merge-only reviews.
- **D:** a written comparison first; if bespoke: its own temp worktree, pinned shas, a `GITHUB_REF` seam replay with an output check, a lock, a background run. OI-309 closed per option.

## 8. Expected effect and residuals
- **After A1:** 14 of 50 conflicted syncs clear. **After A1 + A2:** 27 of 50.
- **After C:** the rest are one command away; about 4 of 52 need a human; forced main-sync reviews stop.
- **After D:** one background command.
- **Residuals:**
  - Hooks stay copies. Gate 32's WARN stays hidden by the pre-commit loop (pre-existing); the A0 README, the memory line and the A2 SessionStart check cover the known failure.
  - A post-A0 installer run with `--allow-stale` / `--allow-unmerged` from a stale or unmerged tree still changes the shared hooks; A0 refuses by default but cannot prevent a deliberate override, and an OLD tree's installer (plain `cp`) is stopped only by the read-only bit.
  - Parallel bug-class collisions need one human renumber.
  - The A1 freeze is local-only while pre-A1 branches exist.
  - A deleted review section is unchecked.
  - An agent that ignores the nudge reads a stale index; the reader-side `## OI-N —` check catches a wrong pointer.

## 9. Round-5 finding map

| Finding | Disposition |
|---|---|
| R5A-1, R5A-2, R5A-3, R5B-1 | A0 tests (9), (11), (12), (13) and the mutation table re-derived case by case |
| R5A-4 | tests (1a/1b/2a/2b); mutants at :192 and :209 separately |
| R5A-5 | `@Timeout` + `library;` on both A0 test files |
| R5A-6 | test (10) runs Gate 32 and asserts `PASS: all 5 hook(s)` |
| R5A-7 | no `$` in the README body; no `${X:-}`; README via tmp + `mv` |
| R5A-8, R5B-2 | pre-swap `cmp`; restore `a-w` on failure; `u+w` only as a retry fallback |
| R5A-9 | cites fixed (:243-244, :59/:82); test (3) wording |
| R5B-3 | cause-specific retry wording; README failure is a warning |
| R5B-4 | traps KEPT (tests 12, 13) because test (8) needs them for stray tmp |
| R5B-5 | behind-main check on a local ref, no fetch (test 15); became a refusal after the first B-pass |
| R5A-10, R5B-6 | tier normalization rule |
| R5A-11, R5B-8 | flipped tests listed; gate/ledger comments |
| R5A-12 | CLAUDE.md :355 |
| R5A-13 | the staged-only-archive fixture named as the killer |
| R5A-14 | MERGE_HEAD as directory/empty file; matches precedent |
| R5A-15, R5B-7 | scanner state machine; `-A3`; no literal bullet in the freeze note |
| R5B-9 | `--no-renames` only without MERGE_HEAD |
| R5B-10 | "re-run the gate to read the message" |
| R5C-1 | shared lib; fixture copy lists; derivation test |
| R5C-2 | `Directory.current`; one `_emit` |
| R5C-3, R5D-3 | no wall-clock test; nudge at SessionStart and bug-trigger only |
| R5C-4, R5D-4 | MERGE_HEAD lenient bug build before the catalog walk; roll-out step |
| R5C-5 | the full-suite test builds for itself |
| R5C-6, R5D-2 | the nudge uses `--lenient`; worst-code orchestrator; self-check |
| R5C-7a, R5D-1 | pre-merge-commit keeps the build, skips the restore, suppresses the NOTE |
| R5C-7b..j | mutation list; inode seam POSIX-only; digest rules; docs list; branch count; OI lenient; registry; pre-push presence test; rename retry |
| R5D-5 | no seeding |
| R5D-6 | roll-out recipe; Windows confirmation before the A2 merge |
| R5D-7 | preamble fallbacks |
| R5D-8, R5D-9, R5D-10 | stats before reads; build in `run_full_suite()`; the warning kept SessionStart-only |

## 10. Next
- **A0:** one narrow, mechanical-only delta check of §4 (one reviewer), then implement.
- **A1:** both round-5 verdicts are CONVERGED; implement after A0 (or in parallel, on its own branch).
- **A2:** both reviewers' P1s are fixed in text. It gets one more converged round before code, because rev 6 changed its import structure and the merge-hook behavior.
