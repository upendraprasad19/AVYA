# Hooks, gates and infrastructure — full detail

> Moved VERBATIM out of root `CLAUDE.md` (context-lean batch, 2026-09-29): the §0 "Git hooks (FIVE)" + CI block, and the long cells of the §7 pointer table. Root keeps a short summary and bare `topic | path` rows that point here. Counts quoted in this file are point-in-time prose; re-derive them (`ls scripts/check_*.dart | wc -l` etc.) rather than trusting them.

## Git hooks (FIVE) — tiered by blast radius (formerly root CLAUDE.md §0)

Installed once per clone via `sh scripts/setup-hooks.sh` (Git Bash on Windows). Not
version-controlled into `.git/hooks/`. Bypass a single run with `--no-verify` (sparingly — CI
runs the same gates). See §4 process invariants for the no-deferred-failures policy.

> **All five hooks resolve Dart through `scripts/_dart_bin.sh`, never a bare `dart`.**
> `flutter/bin/dart` is a WRAPPER that takes the SDK update lock and shells out to
> `git rev-parse` on the Flutter checkout on EVERY invocation — and the lock SERIALIZES
> concurrent callers, so its cost scales with the gate loop's job count instead of dividing by
> it. Measured 2026-08-17 on the real hook, same worktree, same gates, both exit 0:
> **182149 ms → 98447 ms** (a second, load-contended pair: 399370 → 163744). Bare
> `dart --version`, which does nothing at all, costs **3.4–10.5 s** via the wrapper and
> **0.10–0.22 s** via the SDK exe. Two hypotheses were tested and REFUTED — do not re-run them:
> Windows Defender (the exe is scanned identically and costs 280 ms) and the hook's `GIT_DIR`
> leak reaching `dart.bat`'s git call (no measurable effect). Corollary: **raising
> `PRE_COMMIT_GATE_JOBS` is not the lever** — it bought ~20% while the wrapper was in the path
> (that was lock contention, not parallelism headroom) and nothing measurable now that it is not.
> Pinned by `test/scripts/dart_bin_resolver_test.dart`, whose mirror test fails if any hook
> reverts to a bare `dart run` or drops the `.` source line.

- **`scripts/pre-commit.sh` (gates only, ~98 s measured):** **96** `check_*.dart` files exist
  (`ls scripts/check_*.dart | wc -l`, re-run 2026-09-19 after retiring `check_migrations_live.dart`
  — see below); the loop runs **84** (12 are case-skipped), and 2 more
  (`check_no_deferral_euphemism`, `check_skipped_discipline_budget`) are invoked explicitly after
  it, so real pre-commit coverage is **86 of 96** — `check_regression_catalog` makes 87 on a
  merge only. **Which gates the skip lists may name is no longer prose:** since OI-155
  (2026-09-19) Gate 33's allowlist is a typed map of runners (`file(path)` / `loop(preCommit|ci)`
  / `manual(OI-NNN)`), each checked on every commit — a `file` runner must INVOKE the gate on a
  live line, a `loop` runner must not case-skip it, a `manual` runner must name an OPEN or
  IN_PROGRESS OI on the merged boards (CLOSED / absent / unreadable board ⇒ FAIL), and an
  allowlist key with no script on disk is itself a violation. Three gates are `manual:` today and
  run NOWHERE by construction — `onconflict_live_arbiter` + `two_user_cross_account` (OI-283: no CI runner), and `test_runtime_budget` (OI-101). (A fourth, `migrations_live`, was `manual(OI-223)`
  for the same reason — cannot pass, 125/139 migrations applied raw and never registered live —
  and was RETIRED in the same batch: OI-223 closed, the script deleted, Gate 14
  `check_migrations_applied.dart` already owning "applied live".) Closing any of those OIs turns Gate 33 red until the gate
  gets a real runner — that is the point.
  ⚠ These counts are PROSE and no gate validates them (`check_claude_md_citations.dart` checks
  `§N` heading citations, not numeric claims), so they go stale on any commit that adds a gate —
  as this row did (it said 90 / 76 / 78 from 2026-08-25 until 2026-09-19). Re-run the `ls`
  above rather than trusting the number.
  Bounded-parallel, `PRE_COMMIT_GATE_JOBS` default 4. Plus Gate 40 + conditional index regens +
  merge-commit regression-catalog walk. Blocks the commit on any failure. Prints a non-blocking
  `/code-review` (B-pass) reminder when the staged blast-radius is ≥`account` — the review itself
  is MANDATORY before the merge per §4.3; the echo is only the reminder, not the gate.
  It does **NOT** run `flutter analyze` or `flutter test` (cost split 2026-08-11 — see ADR-0018).
  The two flutter steps dominated commit cost and were the most duplicated work in the pipeline:
  `test/contracts/` is a strict subdirectory of `test/`, so pre-push (≥account) and CI each re-run
  those same files. ⚠ **The exact seconds are contested. OI-102 is CLOSED** (2026-08-11 — ADR-0018
  removed its trigger); the unanswered measurement half was carried forward as **OI-106** (`Verified:
  never`), which owns the still-unexplained "CI runs 690 files in 417s while local ran 478 in
  1114.6s — ~3.9× slower per file locally at ~4× the parallelism". Corrected 2026-08-17: this row,
  `scripts/pre-commit.sh` and ADR-0018 all still called OI-102 OPEN, while the board — the
  authoritative source — had marked it CLOSED the same day those three were written. An
  in-session run measured 845s total (analyze 212s cold / ~18s warm, contracts 521s), while
  OI-102's board-verified JSON-reporter run the same day measured the contracts subset alone at
  1114.6s over 477 files. Treat 845s as a floor, not a settled figure; the decision holds under
  either. `PRE_COMMIT_FULL=1` runs analyze + the FULL suite here; `PRE_COMMIT_LEGACY=1` restores
  the old analyze + contracts-subset behaviour. If both are set, `PRE_COMMIT_FULL` wins.
- **`scripts/pre-push.sh` (analyze always + blast-radius-tiered suite):**
  `flutter analyze --no-fatal-infos` runs **unconditionally**, above every early exit — placement
  is load-bearing, because on a `feature`-tier branch push it is the only compile check that runs
  anywhere (see the CI row).
  ⚠ **`--no-fatal-infos` suppresses INFOS, not WARNINGS.** A single `warning -` line makes analyze
  exit non-zero, the hook aborts, and git prints only `error: failed to push some refs` — no hint,
  no `remote:` line, nothing naming the file or the rule. **That error shape on a clean
  fast-forward means the LOCAL hook failed; read its output, not git's.** Measured 2026-08-26: one
  `avoid_dynamic_calls` warning among 268 infos cost a full push cycle, and it sat in the one file
  that had never been named in a `dart analyze` invocation. Analyze the files you WROTE.
  **Then the targeted contract sweep runs, for EVERY tier** (OI-220, 2026-09-19):
  `"$DART_BIN" run scripts/contract_sweep.dart --warn-only || true` selects the contract tests
  the push range can have broken — a changed path that is a `file:` of a SoT-registry concept
  → its `behavioral_test_path(_*)`; every changed non-doc file's basename → `git grep -l -F`
  over `test/`; changed `test/**_test.dart` themselves — over the three-dot
  `origin/main...HEAD` range, and spawns `flutter test <files> --exclude-tags golden`. Any
  unreadable input (registry, `git diff`, a `git grep` error, `origin/main` unresolvable) or
  internal exception falls back to the WHOLE `test/contracts/` subset — uncertainty must never
  look like a clean sweep. `--warn-only || true` is the §4.11 baseline; the hard-fail flip
  (after one clean batch, tracked on OI-220) removes BOTH tokens. Guards:
  `CONTRACT_SWEEP_SKIP=1` (kill switch) and `CONTRACT_SWEEP_NESTED=1` (set on its own spawn —
  on Windows the Dart spawn reaches the REAL flutter past a PATH stub, so without it the
  analyze e2e would recurse). It is deliberately NOT a `check_*` gate (the two loops enumerate
  `check_*` and the rule-24 ledger rejects non-`check_*` keys), so its wiring is pinned by
  `test/contracts/contract_sweep_wired_test.dart` and its proof is rule 21 (§7 row). Measured:
  1.9 s / 17 tests on a 15-file range; 18.5 s / 505 on a 366-file range.
  Then the full `flutter test` runs only when the pushed range's
  blast-radius is ≥`account` (auth/ai_coach/sync/ai-proxy/payment/migrations/CLAUDE.md/…).
  `feature`-tier pushes (docs / most of `scripts/` / `.claude/` / `backups/` / profile-only)
  **skip** the local full suite — note `scripts/` is NOT uniformly feature-tier: the hook scripts
  and the review/blast-radius machinery are individually pinned `platform` in
  `docs/blast_radius.yaml`.
  Fail-safe: any uncertainty runs the suite. Force it with `PRE_PUSH_FULL=1`. (Tier via
  `scripts/blast_radius_from_diff.dart`; lean-workflow batch 2026-06-01, analyze added 2026-08-11.
  Pinned by `test/contracts/hook_gate_placement_test.dart` +
  `test/scripts/pre_push_analyze_always_e2e_test.dart`.)
- **`scripts/pre-merge-commit.sh` (OI board integrity at the merge, ~2 s):** git invokes THIS
  hook — NOT `pre-commit` — for an automatically-created merge commit. Until 2026-08-17 it was
  not installed, so a **CLEAN auto-merge ran no hook at all**. That is the exact shape of the
  OI-number collision class: two sessions' board additions sit in different regions of the file,
  git combines them silently, and one number ends up naming two issues. Two places in the repo
  asserted the opposite — OI-112 (now in `closed_issues.md`; the line anchor this row used to
  carry rotted, which is its own lesson) and diagnose `b7e3d1:56-58`, both
  claiming "corruption cannot LAND — the merge commit regenerates the index and the gate fires" —
  and both were false for want of this hook. It runs the two board gates only
  (`build_oi_index.dart` for within-file duplicates, `check_oi_numbering_unique.dart` for
  cross-branch/cross-board), NOT the full 75-gate loop: a merge needs board integrity, not a
  re-scan of a tree already gated at every commit on both sides.
- **CI (`.github/workflows/test.yml`) is the full-suite source-of-truth for `main`** — analyze +
  full `flutter test` + all gates + a debug-APK compile + **the `deno-edge-functions` job**
  (`test.yml:120`), which runs `deno test` AND a `deno check` type-check over the WHOLE
  `supabase/functions/` tree.
  ⚠ **That job was missing from this list until 2026-08-26, and the omission has teeth: until
  2026-09-12 there was no Deno on the dev machine, so NOTHING type-checked an Edge Function
  locally** — not `flutter analyze`, not the pre-commit gates (which are Dart source-greps), not
  pre-push. An EF type error was invisible until CI. It cost a red `main` that day: a removed
  `user_daily_snapshots` query orphaned two reads 60 lines below the edit, and `deno check`
  reported `TS2304 Cannot find name 'snapshot'` only after the push had landed. **Deno 2.9.6 is
  installed locally since 2026-09-12 (winget; `%LOCALAPPDATA%/Microsoft/WinGet/Links/deno.exe`)
  — run `deno check --node-modules-dir=none supabase/functions/<fn>/index.ts` on every EF you
  touch BEFORE the commit. ⚠ `--node-modules-dir=none` is load-bearing: the default `auto`
  mode replaced the TRACKED `node_modules/pg` with a symlink into `node_modules/.deno/` on its
  first run (22 files "deleted" in `git status`). Recovery: `rm -f node_modules/pg && rm -rf
  node_modules/.deno && git checkout -- node_modules/`. See `supabase/functions/CLAUDE.md`.**
  Nothing in the hooks runs it yet — it is a habit, not a gate; the pre-commit gates remain
  Dart source-greps. Also note CI's analyze step is named
  *"Flutter analyze (zero warnings allowed)"* (`test.yml:61`) — stricter than a casual reading of
  the pre-push row suggests. ⚠ It triggers on `push: [main, develop]`
  **and `pull_request` targeting them** — **not on every push**. Counted live 2026-08-11:
  `git ls-remote --heads origin` = 29 refs (28 non-main); 8 have an open PR and so DO get CI on
  every push; the other ~20, including most `claude/*` working branches, get none. Corrected
  2026-08-11 — this row previously claimed "on every push, regardless of the local tier", and
  `pre-push.sh` justified its `feature`-tier skip with "CI runs it ~2 min after push (the
  backstop)" on the strength of it. (A first correction attempt overshot in the other direction,
  claiming "42 branches, none run CI"; 42 counts remote-*tracking* refs from `git branch -r`,
  including `origin/main` and refs deleted upstream, and it missed the PR trigger entirely.)
  The PR-less majority is exactly why pre-push analyze is unconditional rather than tiered.


## §7 pointer-table rows — full text (formerly root CLAUDE.md §7)

### Live schema column snapshot (Gate: `check_schema_column_refs.dart` validates every `.from().select/eq/gte/o...

| Topic | Path / detail |
|---|---|
| Live schema column snapshot (Gate: `check_schema_column_refs.dart` validates every `.from().select/eq/gte/order` + insert/update-key column ref in BOTH `lib/` (client) AND `supabase/functions/` (Edge Functions) — server-seam extension WI-1 2026-06-08, after the lib/-only gate stayed blind to 5 weeks of live cloud-contract bugs incl. the delete-account DPDP P0 b4e2a9) | `backups/live_schema_columns.json` — **regenerate in the SAME commit as any migration that adds/drops/renames a column** (regen SQL in the gate script header). Sibling gate `check_container_color_decoration.dart` blocks `Container(color:+decoration:)`. |

### Open-issues backlog — READ THE INDEX FIRST

| Topic | Path / detail |
|---|---|
| **Open-issues backlog — READ THE INDEX FIRST** | `docs/audit/OPEN_INDEX.md` — auto-generated, one line per open OI (`Blocked on` / `Verified` / line anchor), **~3,800 tokens (13,619 B, measured 2026-08-30)**. ⚠ This row said **"~950 tokens" for a month while the real figure reached 5,266** — TRUE when written (`e4bc9040`, 2026-07-29: 3,759 B ≈ 1,044 tok) and never re-derived, on the very row that tells every session to read this file first. **Do not trust this number either — measure it**: `wc -c docs/audit/OPEN_INDEX.md`, ÷3.6 for tokens. It is now gated (`check_context_artifact_budget.dart`, soft 15% warn / hard 50% block) precisely because prose cannot hold a number. The 2026-08-30 batch also capped `Blocked on`/`Verified` at 40 chars in the RENDER (`build_oi_index.dart`, reusing `_shorten`) — they were emitted RAW at up to 212 and 312 chars against a title capped at 74, which is where the bloat came from. Full detail: `docs/audit/open_issues.md` at the cited line (`Read(offset:, limit: 60)`); closed history archived in `docs/audit/closed_issues.md` — **which is where 27 CLOSED entries went on 2026-08-30, 46% of a board named "open"** (357,664 → 194,850 B — the FINAL figure across both archive commits; 200,300 B was the intermediate state after the first 26, and pairing the final count with the intermediate size is exactly the error round 1 caught here). Generator `scripts/build_oi_index.dart` regenerates on any commit touching the board (`pre-commit.sh`) and **fails closed** on a missing `Blocked on`/`Verified`. `closes-oi: OI-NN` is enforced at commit-msg by `scripts/check_closes_oi_cited.dart` when a status moves OPEN→CLOSED. Tests: `test/contracts/oi_index_test.dart`, `test/contracts/closes_oi_cited_test.dart`. **Why generated:** the board went 70 days unread because nothing referenced it, and its own "fixed by `check_open_issues_reconciled.dart`" note described a script that was never written. |

### Discipline harness hooks (prompt-time §4 reminders + euphemism gate + MEMORY.md size nudge + worktree warni...

| Topic | Path / detail |
|---|---|
| Discipline harness hooks (prompt-time §4 reminders + euphemism gate + MEMORY.md size nudge + worktree warning + multi-machine main-sync warning) | `scripts/discipline_hook.dart` (UserPromptSubmit / PreToolUse:Skill / SessionStart → `.claude/settings.json`; the SessionStart matcher fires on ALL sources — startup/resume/compact: compact re-injects the hot-set, the shared-main worktree triggers the §4.13 warning, an over-cap MEMORY.md index nudges `/consolidate-memory` — user-level skill `~/.claude/skills/consolidate-memory/` — and `_mainSyncWarning()` compares local `main` to `origin/main`) + `scripts/check_no_deferral_euphemism.dart` (pre-commit gate, §4.2). ⚠ The MEMORY.md nudge's path derivation was FIXED 2026-09-23 (diagnose `c8d5b2`): it mangled `Directory.current.path` (the WORKTREE path in every §4.13 session) instead of the PRIMARY root, so the nudge silently never fired from any worktree — the exact bug class `batch_close_lib.dart`'s own `primaryRootFrom` doc comment already named, just never applied here. Now reuses that same function via the extracted, testable `resolveMemoryIndexPath`. Test: `test/scripts/discipline_hook_memory_path_test.dart` (5, mutation-proven). **Multi-machine main-sync warning ADDED 2026-09-24**, after a VPS clone's local `main` silently drifted 300 commits behind `origin/main` with no warning until someone happened to run `git status` — the incident that also surfaced several stale/duplicate files hand-copied between the laptop and VPS (that second half — untracked-file staleness — was explicitly left for a future step; see the design note below). `_mainSyncWarning()` prints `⚠️ MAIN BEHIND` / `MAIN AHEAD` / `MAIN DIVERGED` with the exact `git pull`/`git push`/reconcile command. **Deliberately DIFFERS from the OI board line's local-read-only precedent below**: it performs its own short, bounded (~4s) `git fetch origin main` before comparing, because staleness at the moment of session start matters more here than the fixed per-hook cost this line exists once per session (not per SessionStart source group) to answer — a slow/offline network degrades to the last-known local comparison with a staleness caveat (`(offline/fetch failed — last known sync was Xh ago)`) rather than blocking the session. Pure formatter `formatMainSyncWarning` + I/O wrapper `_mainSyncWarning`. Tests: `test/scripts/discipline_hook_main_sync_format_test.dart` (5, pure) + `test/scripts/discipline_hook_main_sync_e2e_test.dart` (8, real subprocess/git — in-sync, behind, ahead, diverged, offline-fallback, no-remote-silent, kill-switch, and the hang-is-actually-killed case from the B-pass fix below). Audit retrospectives: `memory/project_discipline_harness_hooks_2026_06_27.md`, `memory/project_memory_consolidation_2026_07_04.md`. |

### Memory write-guard (PreToolUse:Write\|Edit, WARN-ONLY, discipline v3 Phase 3, 2026-09-23 — adopted from ICA...

| Topic | Path / detail |
|---|---|
| **Memory write-guard** (PreToolUse:Write\|Edit, WARN-ONLY, discipline v3 Phase 3, 2026-09-23 — adopted from ICANBEFITTER's `claude-memory-write-guard.mjs`) — validates a memory-file write BEFORE it lands: topic-file frontmatter shape (`---`/`name:`/`description:`/`type:`) or, for MEMORY.md itself, the founder's own byte caps (600B/line pointer cap, 24,400B hard cap; the UTF-8 byte count, not `String.length`). `MEMORY_ARCHIVED.md` (append-only, no frontmatter, no byte-cap contract) gets its own no-op branch — fixed 2026-09-23 (round-1 review, P1) after it fell through to the frontmatter validator and warned on EVERY edit, the most routinely written memory file in the `/consolidate-memory` workflow. | `scripts/memory_write_guard_hook.dart` + pure `scripts/memory_write_guard_lib.dart`; wired at `PreToolUse` (matcher `Write\|Edit`) in `.claude/settings.json`. Deliberately WARN-ONLY, never blocking — a hygiene gate must not wedge a legitimate save (same fail-open philosophy as every other hook here). For `Edit`, simulates the real on-disk replacement (reads the current file, applies `old_string`→`new_string`) rather than validating the fragment alone. ⚠ **Cost, measured, not assumed**: the FIRST PreToolUse hook here matched on `Write\|Edit` rather than `Skill`/`Bash` — fires on every file edit, not a rare event. ~1.5-1.7s/call via the wrapper `.claude/settings.json` actually invokes; ~540-800ms via the SDK exe `_dart_bin.sh` resolves (not currently wired — same "separate, unmade decision" as its three siblings, but with a stronger frequency argument for making it; open follow-up). Tests: `test/scripts/memory_write_guard_lib_test.dart` (**31**) + `memory_write_guard_hook_e2e_test.dart` (**7**, real processes), mutation-proven on three legs (type-field check 2 red, line-byte-cap check 3 red, MEMORY_ARCHIVED.md no-op branch 1 red). |

### AST-style debt gates (report mode, never block) — Fitness App's equivalent of ICANBEFITTER's Rule 2 / Rule ...

| Topic | Path / detail |
|---|---|
| **AST-style debt gates (report mode, never block)** — Fitness App's equivalent of ICANBEFITTER's Rule 2 / Rule 3 (discipline v3 Phase 3, 2026-09-23): `check_hive_first_pattern.dart` flags a direct Supabase `.from(`/`.client.from(` call outside `lib/core/services/`, `lib/shared/repositories/`, `lib/features/*/repositories/` (CLAUDE.md §4.4 rule 4); `check_edge_function_scope.dart` flags any AI-provider endpoint domain or Edge-Function-only secret name anywhere in `lib/`, with NO allowed location (rule 9). Both are source-grep heuristics, not real AST — deliberately never fail a commit, for the same reason ICANBEFITTER's own Rule 2/3 don't ("if the guard is a source grep, assume it is defeatable" — code-review skill lens 6). | `scripts/check_hive_first_pattern.dart` + `scripts/check_edge_function_scope.dart`, auto-wired into the `scripts/check_*.dart` gate loop. Both verified against the REAL `lib/` tree before being written (zero violations, zero false positives measured, not assumed — see each file's header). ⚠ No baseline-raising mechanism exists yet for either (ICANBEFITTER's `check-baseline-notes.mjs` equivalent is Phase 2 scope, still separately incomplete) — these gates only print a count, nothing yet alarms if it grows. ⚠ `check_hive_first_pattern.dart`'s alias set was WIDENED 2026-09-23 (round-1 review, P2-5): a live grep found a real third alias (`supa.from(`, `rank_service.dart`) the original 2-alias pattern missed entirely — a coverage gap in the detector, not a live violation, since the call site was already inside an allowed dir. Tests: `test/scripts/check_hive_first_pattern_lib_test.dart` (**21**, mutation-proven on 3 legs) + `check_edge_function_scope_lib_test.dart` (**15**, mutation-proven on 1 leg). |

### End-of-batch enforcement — the `Stop` hook (§5). Before 2026-08-25 the three wired hook events all fired BE...

| Topic | Path / detail |
|---|---|
| **End-of-batch enforcement — the `Stop` hook** (§5). Before 2026-08-25 the three wired hook events all fired BEFORE work, so nothing watched the END of a batch, which is exactly where §5's rows live and exactly where four of them went unwalked in one batch. | `scripts/batch_close_hook.dart` + pure `scripts/batch_close_lib.dart`; wired at `Stop` in `.claude/settings.json`. Fires ONCE per HEAD (state file `.claude/.batch_close_state`, gitignored), only when commits have landed unpushed. Three states per row — `[x]` satisfied, `[ ]` not, **`[?]` COULD NOT DETERMINE, which is not the same as fine**. Safety, in order: `stop_hook_active` short-circuit (blocking on Stop re-triggers Stop — an infinite loop), once-per-HEAD, kill switch `.claude/.batch_close.disabled`, and every error path exits 0. ⚠ Derives the harness memory dir from **`--git-common-dir`, never `--show-toplevel`** — every session works in a linked worktree per §4.13, so the worktree path never matches the harness's mangled directory name. Found by live-testing, not by a unit test. ⚠ Cost, stated because this file is intensely sensitive to exactly this lever elsewhere: `Stop` fires at turn-END, so Dart-wrapper startup (~2.2 s here) is now paid TWICE per turn rather than once. The 3 s stdin timeout is NOT added per turn — only when stdin stays open, which the harness's normal write-then-close does not do. Like its three siblings this hook does not route through `scripts/_dart_bin.sh`; wiring the hooks in `.claude/settings.json` to that resolver is a separate, unmade decision. Tests: `test/scripts/batch_close_lib_test.dart` (**22**) + `batch_close_hook_e2e_test.dart` (**7**, real repos), mutation-proven on six legs — the three safety guards plus `primaryRootFrom`, the `-+` collapse, and the `readLineSync` hang. |

### Skill self-evolution gate (§5.1) — a code-review pass that produces a review file must also record what it ...

| Topic | Path / detail |
|---|---|
| **Skill self-evolution gate** (§5.1) — a code-review pass that produces a review file must also record what it learned, or the skill stops evolving | `scripts/check_skill_tuning_history.dart` + pure `scripts/skill_tuning_lib.dart`. Matches the dated-bullet SHAPE, never `contains(date)` — a date also appears inside older entries' prose, so a substring test would let an OLD entry satisfy a NEW review and the gate would go permanently inert. Reads the STAGED blob (OI-72's lesson). Fails OPEN on an unreadable skill file or unparseable `reviewed_at:`. A review is identified by WHERE IT LIVES — any `docs/reviews/**.md` except `INDEX.md`/`README.md` — not by suffix: the first version matched only `-review.md` while **81 of 164** files use `-bpass.md`, so it was blind to the majority convention. ⚠ Its "code-review only" scope is currently protected BY ACCIDENT, not by a provenance check: the one hermes output living in `docs/reviews/` happens to use `staged_against:` rather than `reviewed_at:`, so it fails open. If `/hermes-pass` ever adopts `reviewed_at:`, this gate silently widens to cover it — and its `hermes-pass/SKILL.md` contract says it writes to `docs/audit/` anyway, which that file already contradicts. Tests: `test/scripts/skill_tuning_lib_test.dart` (**13**) + `skill_tuning_history_e2e_test.dart` (**10**), mutation-proven on three legs (matcher→`contains` 4 red, fail-open→satisfied 3, filter→`-review.md` 2). |

### Worktree-per-session enforcement (one worktree per session; shared main folder = integration-only; prevents...

| Topic | Path / detail |
|---|---|
| Worktree-per-session enforcement (one worktree per session; shared main folder = integration-only; prevents cross-session git-index file-mixing) | **§4.13.** Pre-commit gate `scripts/check_commit_from_worktree.dart` (+ pure `scripts/worktree_guard_lib.dart`, test `test/contracts/check_commit_from_worktree_test.dart`) blocks non-merge commits in the primary worktree; helper `scripts/new-worktree.sh <slug>`; `scripts/discipline_hook.dart` SessionStart warning. Diagnose `f0c2d5`; `memory/feedback_worktree_per_session.md`. |

### Worktree lifecycle — retirement (the half §4.13 originally lacked; the count reached 106 dirs / 17 GB befor...

| Topic | Path / detail |
|---|---|
| Worktree **lifecycle** — retirement (the half §4.13 originally lacked; the count reached 106 dirs / 17 GB before this existed, reclaimed to 1.4 GB) | **§4.13 point 6.** `dart run scripts/retire_worktree.dart` (dry-run DEFAULT, `--execute` opt-in) + pure `scripts/retire_worktree_lib.dart`. Four-leg predicate: merged AND no tracked changes AND no non-regenerable ignored files AND nothing unpushed — "merged" alone would have destroyed 21 uncommitted files across 5 worktrees on 2026-08-09. Orphans (on disk, not in `git worktree list`) are a stricter separate category: only genuinely empty dirs (0 entries, counting directories) auto-remove. Operator-invoked, NOT a blocking gate. **OI-138 (2026-09-29):** after removal it also deletes the worktree's local branch with `git branch -d` (protected names/prefixes, ancestry re-check, `KEPT-BRANCH` on refusal) — §4.13 point 6. Tests `test/scripts/retire_worktree_lib_test.dart` + `retire_worktree_e2e_test.dart` (mutation-proven). |

### Gate registry — which script owns gate number N, and can that gate's test actually FAIL? (Before this, neit...

| Topic | Path / detail |
|---|---|
| **Gate registry** — which script owns gate number N, and can that gate's test actually FAIL? (Before this, neither question was mechanically answerable: "Gate 44" named TWO unrelated scripts, five surveys in one session returned five different collision counts, and only 6 test files in the whole repo asserted a red path.) | `docs/audit/GATE_INDEX.md` — **generated**, do not hand-edit; regenerated by `scripts/pre-commit.sh` when a baked input changes. Generator `scripts/build_gate_index.dart` + pure `scripts/gate_index_lib.dart`; freshness gate `scripts/check_gate_index_fresh.dart`. **The registry keys on the FILENAME**; a number is an optional alias (49 of 87 have one). Canonical declaration is `// Gate: N` alone on its line in the first 10 lines — the ONLY form the generator reads. Four claim sources: script headers, `_extraGateScripts` (for numbered non-`check_*` gates like `validate_audit_closure.dart` = Gate 40), `build-apk.md` sections, and the closure ledgers (BOTH `*_closures.yaml` and `*.closure.yaml`, BOTH mint orders) — a ledger mint is EVIDENCE, superseded once the script declares its own number, because ledgers are historical records that are never rewritten. Rule 24 ledger: `docs/audit/gate_test_ledger.yaml` + `scripts/check_gate_test_ledger.dart`. Tests: `test/scripts/gate_index_{lib,e2e,fresh_e2e}_test.dart`, `gate_test_ledger_lib_test.dart`. |

### OI number uniqueness across branches — numbers are ALLOCATED by `scripts/mint_oi.sh` (2026-09-12), never ey...

| Topic | Path / detail |
|---|---|
| **OI number uniqueness across branches** — numbers are ALLOCATED by `scripts/mint_oi.sh` (2026-09-12), never eyeballed. Before it: no allocator, the ceiling split across two files, six manual renumbers by 2026-09-12 (the last, 177/178→186/187, landed while the allocator was being specified). The detector alone was structurally late — two of its three placements run after the number is committed, and the early one was vacuous in the zero-commit worktree state (OI-176). | `scripts/mint_oi.sh` reserves `refs/heads/oi/N` as a server-side compare-and-swap: `gh api` on the laptop (NOT a `git push`, so pre-push never runs), `git push --force-with-lease=<ref>:` in the cloud (no `gh`, no hooks, and its credential writes `refs/heads/**` only — `refs/oi/*` is a 403). **That push is a documented exemption from §4.3's `safe_push.sh` rule:** it creates a ref that must not exist, so the exit code IS the landing verification, there is no range to gate, and `git_safety_hook.dart` cannot see it (it runs inside a script). Sync is `git fetch` into the SHARED `.git/`, so every laptop worktree sees a reservation instantly. Offline ⇒ the mint REFUSES (exit 2, nothing written) — the one deliberately fail-closed step; gates stay fail-open. Gate `scripts/check_oi_numbering_unique.dart`: Check B′ compares the UNCOMMITTED board against origin/main whatever shape HEAD has (closes OI-176, diagnose `f3a9c1`); Check C fails a commit whose new number has no `oi/N` — meaningful at pre-commit, pre-merge-commit (the backstop for hookless cloud branches) and CI-on-a-PR; VACUOUS by design at CI-on-main (published numbers are exempt because prune may already have removed their reservation); offline ⇒ SKIPPED naming which check. SessionStart prints `next free number is at least N` from LOCAL refs (no fetch — ~3 s over SSH, on every source incl. compact). Orphan reservations: adopt by hand or `--release N` — which refuses any number filed on ANY local branch and prints the ledger line (branch + time) before deleting, because from worktree B a sibling A's in-flight number looks unfiled. The cloud never prunes (no `gh`); the next laptop mint prunes for it. `vercel.json` skips `oi/*` builds (`ignoreCommand`). GitHub Issues as the allocator was REJECTED: issues+PRs share one sequence, max #23 < OI-185. Residue: a hookless environment pushing straight to `main` is checked for collisions but not reservations. Tests: `test/scripts/mint_oi_e2e_test.dart`, `oi_numbering_gate_e2e_test.dart`, `discipline_hook_oi_line_e2e_test.dart` — counts deliberately omitted; run them. Spec: `docs/superpowers/specs/2026-09-12-oi-allocator-design.md`. **Sibling (2026-09-29, OI-263):** `scripts/mint_migration.sh` allocates MIGRATION numbers the same way (`refs/heads/mig/N`, a parity-tested copy of this CAS core; its ref-create push is the same documented exemption) — see `supabase/migrations/CLAUDE.md`. |

### Dart binary resolution in the hooks — `flutter/bin/dart` is a wrapper that takes the SDK update lock + runs...

| Topic | Path / detail |
|---|---|
| **Dart binary resolution in the hooks** — `flutter/bin/dart` is a wrapper that takes the SDK update lock + runs git on the Flutter checkout EVERY call, and the lock serializes the parallel gate loop | `scripts/_dart_bin.sh` (sourced by all five hooks; `DART_BIN_OVERRIDE` escapes it). Real-hook A/B: **182149 ms → 98447 ms**. Refuted hypotheses recorded in its header so nobody re-runs them: Defender, and the `GIT_DIR` leak. Mirror test `test/scripts/dart_bin_resolver_test.dart` fails if a hook reverts to bare `dart run` or drops the source line. |

### Sourced-only shell helpers refuse to be EXECUTED — running one is a silent no-op that exits 0, so a caller ...

| Topic | Path / detail |
|---|---|
| **Sourced-only shell helpers refuse to be EXECUTED** — running one is a silent no-op that exits 0, so a caller reads success for work that never happened | **`scripts/_dart_bin.sh` and `scripts/_git_lock.sh`** each open with a `case "$0"` guard that exits **64 (EX_USAGE)** with the correct invocation. Both files define functions and nothing else, so `sh scripts/_dart_bin.sh run <script>` did nothing and exited 0 — on 2026-08-30 that shape was used repeatedly and gates/diagnose-doc validations were reported as passing on the strength of it. `$0` is the file's own path ONLY when executed; when sourced it belongs to the caller, so the guard cannot fire on the five hooks or the three `safe_*` wrappers, and `sh -n` (the parse-check every hook runs before sourcing) never executes it. Tests: `test/scripts/dart_bin_resolver_test.dart` `execution guard` group (**5**, verified by running the group — not counted by eye) — mutation-proven: deleting the guard block reddens **both** execute-must-fail tests (the full-path form and the bare-filename form, which exercise the pattern's two separate arms) while the three does-not-fire tests stay green. ⚠ This row said "(4) … reddens exactly the execute-must-fail test" for part of its own batch and was wrong on both counts within hours — a 5th test was added during review remediation and the prose was not re-derived. Exactly the stale-PROSE-count class §0 warns about; **re-run the group rather than trusting this number.** **Any future sourced-only helper owes itself the same guard.** |

### Pre-merge `bpass_review` verdict precheck — a `verdict: pending` review is unfixable after the merge, becau...

| Topic | Path / detail |
|---|---|
| **Pre-merge `bpass_review` verdict precheck** — a `verdict: pending` review is unfixable after the merge, because CI reads that file AT the merge commit | `scripts/safe_merge.sh` warns (never blocks) when the merging branch's plan-review record claims `bpass: accepted` while its `bpass_review:` file lacks a line-anchored `verdict: accepted`. **ADVISORY by construction**, matching `git_safety_hook.dart`'s own round-2 reasoning for the push-side twin: this must never wedge the only path that lands work on main, and every failure mode (missing record, unreadable field, absent file) falls through silently. The push-shaped precheck in that hook fires only AFTER the merge — by then the repair is a full `git reset --hard` unwind, which is what it cost on 2026-08-30. ⚠ **Two things its first version got wrong, both caught by the B-pass, both worth knowing before touching it:** it read the WORKING TREE, but this script runs on `main` before the merge and the record is authored on the FEATURE BRANCH — so it matched nothing on every real invocation (a no-op shipped as a guard against no-ops). It now reads `git show "$BRANCH:<path>"`, the same read-from-a-rev pattern `check_plan_review_record_exists.dart:216` uses. And it interpolated the raw branch name, while the real filename comes from `plan_review_record_lib.dart`'s `recordSlug()` (strip `origin/`, map `/`→`-`) — so it was inert for every `claude/*` branch. Tests: `test/scripts/safe_merge_test.dart` (**15**, re-run 2026-09-19; the row said 3 while the file held 12) — mutation-proven, and the fixture commits the record ON THE BRANCH deliberately: the first fixture wrote it onto `main`, which made all three tests pass against the broken working-tree read. A fixture that manufactures a state the workflow never produces asserts nothing about the workflow. **Second precheck, same script, same advisory contract (OI-181, 2026-09-19, diagnose `b7e2d4`, `safe_merge.sh:235-`):** the ABSENT-record case. The verdict precheck above fires only when a record EXISTS with a wrong pointer; a branch with NO record at all was silent, and the keystone gate (`check_plan_review_record_exists.dart:617-620`) then failed the merge commit in CI three times (2026-08-30, `dcb94a93` 2026-09-10, `0768a0ce` 2026-09-19). It now classifies the three-dot `refs/heads/main...refs/heads/$BRANCH` range with the real classifier (bare `-` stdin form; `refs/heads/` because a same-named TAG resolves first) and WARNS when the tier is ≥ account and `git show $BRANCH:docs/plan-reviews/<slug>.md` is empty; a non-empty path list that classifies to NOTHING prints one `NOTE:` (bad news vs no news); every other failure path is silent and the merge proceeds. The gate's version-bump exemption is deliberately NOT mirrored — `0768a0ce` was a version bump and the gate failed it (OI-222). Mutation-proven: block deleted 1 red · case arm widened 2 · three-dot → two-dot 1. |

### Pre-push contract sweep — the targeted SoT contract tests a push range can have broken, run for EVERY tier ...

| Topic | Path / detail |
|---|---|
| **Pre-push contract sweep** — the targeted SoT contract tests a push range can have broken, run for EVERY tier above the full-suite block, so a contract regression surfaces in seconds instead of after a full run (or, on a feature-tier push, never locally) | `scripts/contract_sweep.dart` (runner) + pure `scripts/contract_sweep_lib.dart` (OI-220, 2026-09-19; the pre-push bullet under "Git hooks (FIVE)" in this file has the arms, fallback and guards). **Not a `check_*` gate and carries NO rule-24 ledger entry, by design:** `pre-commit.sh:325` and `test.yml:234` (`for GATE in scripts/check_*.dart` — grep for the loop, the line shifts) enumerate every `check_*.dart` (a `check_contract_sweep.dart` would spawn `flutter test` at every commit and in CI's gate loop), and `gate_test_ledger_lib.dart:274` ("has a ledger entry but no scripts/<gate> on disk") rejects a ledger key with no `check_*` script on disk. Its wiring is pinned by `test/contracts/contract_sweep_wired_test.dart` (live line below the unconditional analyze, above `run_full_suite()`, via `"$DART_BIN"`) plus a behavioural assertion in `test/scripts/pre_push_analyze_always_e2e_test.dart` that the REAL hook reaches the sweep line; its proof is rule 21: 6 mutations, 9 reds (null-grep → `continue` 1; registry match → `false` 2; golden skip dropped 2; `warnOnly ? 0 : code` → `0` 1; `noMatchIsEmpty` → false 2; NESTED guard deleted 1) + un-wiring the pre-push line 2 — counts re-derived by the coordinator on the integrated branch for the first leg. Tests: `test/scripts/contract_sweep_lib_test.dart` (10), `contract_sweep_e2e_test.dart` (7, bare `origin.git` + `.bat` stub flutter on Windows), `contract_sweep_wired_test.dart` (1). ⚠ Its `unmapped` line is the baseline's recall signal, print-only: a changed non-doc file that no test names — including PROSE `.md` under `docs/audit/` and `docs/architecture/`, which are keys because the boards and `sync.md` have test readers (10 / 29). The flip criterion lives on OI-220. |

### Worktree config integrity — `core.worktree` must never be set (it silently redirects EVERY worktree at one ...

| Topic | Path / detail |
|---|---|
| Worktree **config integrity** — `core.worktree` must never be set (it silently redirects EVERY worktree at one branch's files, defeating §4.13 from underneath while its gate passes cleanly) | **§4.13 point 7.** Pre-commit gate `scripts/check_worktree_config_integrity.dart` + pure `scripts/worktree_config_integrity_lib.dart`; tests `test/scripts/worktree_config_integrity_lib_test.dart` + `worktree_config_integrity_e2e_test.dart`. Checks ALL git scopes (a global `~/.gitconfig` entry corrupts identically); **fails OPEN** when git cannot answer, so an environment quirk cannot wedge every commit. Diagnose `a4f7c2`. |


## Pre-shortening root text (verbatim, formerly root CLAUDE.md)

> The sections below were tightened in root during the context-lean batch. This is their text exactly as it stood on 2026-09-28 (headings demoted two levels). Sections already preserved in full elsewhere (§4.3/4.4/4.10/4.12/4.13 in `process-invariants-detail.md`, §4.9 rows in `common-pitfalls.md`) are not repeated.


### Original text: Header, DISCIPLINE-FIRST, §0 environment/run/build/gradle/tests/lint

### CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Scope:** root CLAUDE.md is the thin invariants index. Per-feature rules live in nested `lib/.../CLAUDE.md` (auto-loaded by Claude Code when you work in that subtree). Cross-cutting concerns live in `docs/architecture/<topic>.md` (Read explicitly when relevant). Bug history is searchable at `docs/diagnoses/INDEX.md` (auto-generated by `scripts/build_bug_index.dart`). See §7 for the full pointer table.

---

#### ⚠️ DISCIPLINE-FIRST (before ANY investigation, fix, or skill)

**Before investigating a bug, proposing a fix, OR invoking any skill:** load and apply the governing invariants first.

1. **Debugging a bug?** Load the six-step debugging methodology (`docs/playbook/common-pitfalls.md` + `.claude/skills/debugging/SKILL.md`) AND the §4.1 observation→propose workflow. Never jump to a root-cause hypothesis without naming writers + readers by file:line first.
2. **Proposing a fix?** Apply §4 process invariants (no-deferrals §4.2, build/commit gates §4.3, coding rules §4.4, discipline gates §4.5) before writing a single line.
3. **Invoking a skill?** Read the SKILL.md for that skill, apply the relevant §4 invariants, AND (for copy/UI work) load the Wardroom brand soul (`lib/shared/widgets/wardroom/CLAUDE.md`). Never fire a skill blind.
4. **This rule EXTENDS §4.12** (discipline-before-skill — founder directive 2026-06-13) to cover investigation itself. §4.12 covers skill invocations; this section covers the earlier step of investigation and root-cause analysis.
5. **No exceptions.** The observation workflow, the six-step methodology, and §4 invariants are not optional context — they are required pre-conditions for ANY code-touching action.
6. **Harness-injected (2026-06-28).** The highest-recurrence invariants here are now surfaced automatically at the trigger moment by `scripts/discipline_hook.dart`: the hot-set on a bug/fix/observation prompt (UserPromptSubmit), the discipline-before-skill note before any skill (PreToolUse), and a re-injection after compaction (SessionStart). A pre-commit gate (`scripts/check_no_deferral_euphemism.dart`) flags deferral euphemisms in staged docs. **The hook is a reminder, NOT a substitute** — still load the governing rules. See the §7 pointer row.

---

#### 0. DEVELOPMENT COMMANDS

##### Environment Setup
Copy `.env.example` → `.env` and fill in Supabase URL, anon key, and Razorpay key ID.
Environment variables are injected **at build time** via `--dart-define-from-file=.env` (NOT flutter_dotenv — the package was removed). Every `flutter run` / `flutter build` command **MUST** include this flag or the app will crash with "No host specified in URI".

```
SUPABASE_URL=https://dedsavbjuwgarrhphgnl.supabase.co
SUPABASE_ANON_KEY=<anon key>
RAZORPAY_KEY_ID=rzp_test_<key>   # use rzp_test_ for dev flavor
```

##### Run / Build (two flavors: `dev` and `prod`)
> ⚠️ **CRITICAL**: Every command below includes `--dart-define-from-file=.env`. Without it, SUPABASE_URL compiles to an empty string and auth will crash.

```bash
# Run dev flavor on connected device
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart

# Run prod flavor
flutter run --dart-define-from-file=.env --flavor prod -t lib/main.dart

# Release APK (prod)
flutter build apk --dart-define-from-file=.env --flavor prod --release -t lib/main.dart

# Release App Bundle (Play Store)
flutter build appbundle --dart-define-from-file=.env --flavor prod --release -t lib/main.dart

# Web (no flavor needed)
flutter run --dart-define-from-file=.env -d chrome
flutter build web --dart-define-from-file=.env
```

##### Gradle Configuration
`android/gradle.properties` controls JVM memory. Current safe defaults for 16GB system:
- `-Xmx4G` heap (NOT 8G — causes silent OOM crash)
- `-XX:MaxMetaspaceSize=2G`
- `-XX:ReservedCodeCacheSize=256m`
- `org.gradle.parallel=true` + `org.gradle.caching=true`

If build hangs silently with no output, check `android/hs_err_*.log` for JVM crash dumps. Use `/build-apk` skill for the full automated pipeline.

##### Tests
```bash
# All unit tests (no device required)
flutter test

# Single test file
flutter test test/bmr_calculator_test.dart

# All integration tests (requires connected Android device + .env)
flutter test --dart-define-from-file=.env integration_test/app_test.dart --flavor dev

# Single integration flow
flutter test --dart-define-from-file=.env integration_test/flows/workout_log_flow_test.dart --flavor dev
```

Unit tests live in `test/`. Integration tests (require Hive + real device) live in `integration_test/flows/`.

##### Lint & Analysis
```bash
flutter analyze
```


### Original text: §0 Riverpod + Edge Function deploy, §1, §2, §2a, §3, §4 intro, §4.1, §4.1.5, §4.2

##### Riverpod Code Generation
The project has `riverpod_generator` installed but providers are currently written manually using `flutter_riverpod` directly (no `.g.dart` files). If you add `@riverpod` annotations, run:
```bash
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch   # watch mode during development
```

##### Edge Functions — host-shell deploy (preferred for any function with nested `_shared/tools/...` or payloads >100KB)

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js <fn> --auto --functions-dir <worktree>/supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl <fn> .claude/_payload_<fn>.json <verify_jwt>
```

- **Token:** auto-resolved by `.claude/token_path.js` to `<primary repo>/.supabase/supabase access token.txt` (gitignored; WORKS, HTTP 200, 2026-10-02). `supabase/.supabase/supabase access token.txt` (generated 2026-04-20 / file dated 2026-08-08) holds a REVOKED token on the VPS: HTTP 401, do not use it there.
- **Byte-identical to git** (no MCP path-mangling, no hand-trim risk). First used Phase C.5 → ai-proxy v43; now standard for all redeploys.
- **Path scheme:** all shared imports MUST use `from "../_shared/..."` (parent dir), NOT `from "./_shared/..."`. The OLD MCP `deploy_edge_function` tool silently mangled the wrong path; the new flow doesn't.

`mcp__ba7b5e8e__deploy_edge_function` (the legacy MCP path) still works for small single-file functions but is unsafe for the AI coach tools bundle. Do not use `supabase` CLI — it is logged into the wrong account (personal, not fitness app account). See §2a for account details.

---

#### 1. PROJECT IDENTITY

**App:** ICANBEFITTER — personalised fitness & nutrition platform for young professionals (22-35) in India.
**Model:** Freemium. ₹349/month or ₹2,999/year for PRO.
**Architecture:** Offline-first. Hive = primary. Supabase = backup + AI + community growth.

---

#### 2. TECH STACK

| Layer | Technology |
|---|---|
| Frontend | Flutter (Android + Web → iOS later) |
| State Management | Riverpod (with code generation) |
| Local Storage | Hive (offline-first, primary for all reads/writes) |
| Auth | Supabase Auth (Email + Google OAuth + Phone OTP) |
| Database | Supabase Postgres (47 tables — backup + AI + community) |
| Storage | Supabase Storage (exercise images, progress photos PRO) |
| AI Coach (all tiers) | Single Edge Function `ai-proxy` → Gemini 3.1 Flash Lite. Free: 7 msg/day FOREVER (no trial — OQ-1). PRO: 20 msg/day (not unlimited). Server-side gate. |
| Food AI | Gemini 3.1 Flash Lite (text analysis, scan meal, cart auditor) |
| Weekly AI Report | Gemini 3.1 Flash Lite, thinking on (PRO-only) |
| Plan Generator | Dart (local, queries Hive exercise_library, zero API cost) |
| Payments | Razorpay (WebView checkout → webhook → Supabase → poll → Hive) |
| Telegram Bot | Separate project (OpenClaw VPS, @ICanbeFitterBot) — NOT in this repo |
| Health | Google Fit / Health Connect / Samsung Health |

---

#### 2a. SUPABASE PROJECT — CONFIRMED IDENTITY

> ⚠️ CRITICAL: There are TWO Supabase projects on this account. ALWAYS use the one below. NEVER guess.

| Field | Value |
|---|---|
| **Project ID** | `dedsavbjuwgarrhphgnl` |
| **Project name** | myfitnessjourney1988@gmail.com's Project |
| **Region** | ap-southeast-1 |
| **DB host** | `db.dedsavbjuwgarrhphgnl.supabase.co` |
| **Confirmed by** | Querying actual tables — `users`, `exercise_library`, `food_database`, `workout_logs`, `ai_coach_interactions`, `subscriptions` etc. all present |

**The OTHER project** (`krcrkntuwutvnmdnkfqf`, named "icanbefitter" is for icanbefitter.com website) is a **different app entirely** (blog/content platform — `posts`, `members`, `media` tables). Never touch it.

**Rule: Before ANY Supabase operation, confirm project_id = `dedsavbjuwgarrhphgnl`.**

##### Supabase Access — TWO SEPARATE ACCOUNTS

The user has **two Supabase accounts** with different logins. These are NOT the same account.

| Account | Org ID | Org Name | Projects | Access via |
|---|---|---|---|---|
| **myfitnessjourney1988@gmail.com** | `hwwukmntixflgbxkwavm` | (default) | `dedsavbjuwgarrhphgnl` ✅ FITNESS APP, `krcrkntuwutvnmdnkfqf` (blog) | **MCP only** (auto-authenticated) |
| **Upendra's personal account** | `dsvxqvpitnpumftnsnwe` | ICANBEFITTER Supabase | `tjjmtscmwzvlzpbvgtbv` (Upendra-Prasad's Project), `zvwepplqqflhgubwalee` (ICANBEFITTER AI V1) | **CLI only** (`supabase login`) |

⚠️ The Supabase CLI (`supabase` command) is logged into the **personal account**, NOT the fitness app account. CLI commands like `supabase secrets set` will NOT work against the fitness app project unless re-authenticated.

**For Edge Function secrets / admin operations:** Use MCP tools (auto-authenticated to the correct account) or the Supabase Dashboard logged in as `myfitnessjourney1988@gmail.com`.

##### Credentials (Edge Function Secrets)

| Secret Key | Value | Status |
|---|---|---|
| `ONESIGNAL_APP_ID` | `fd37a411-121e-4022-9929-2af68c2371f5` | ✅ Set |
| `ONESIGNAL_REST_API_KEY` | *(set in dashboard, not committed to code)* | ✅ Set |
| `GEMINI_API_KEY` | *(set in dashboard, not committed to code)* | ✅ Set |
| `CEREBRAS_API_KEY_1` | *(already set)* | ✅ |
| `CEREBRAS_API_KEY_2` | *(already set)* | ✅ |
| `CEREBRAS_API_KEY_3` | *(already set)* | ✅ |
| `RAZORPAY_KEY_SECRET` | *(already set)* | ✅ |

##### Firebase / OneSignal

| Field | Value |
|---|---|
| Firebase project | AVYA |
| Firebase Sender ID | `194342788570` |
| OneSignal App ID | `fd37a411-121e-4022-9929-2af68c2371f5` |
| `google-services.json` | ✅ In `android/app/google-services.json` |
| Google Services Gradle plugin | ✅ Configured in `settings.gradle.kts` + `app/build.gradle.kts` |

---

#### 3. SCREENS (5 Tabs)

| Tab | Screen | Key Features |
|-----|--------|-------------|
| 🏠 Home | Dashboard | Streak, weekly calendar, quick actions, today's workout, nutrition snapshot, weight sparkline, PR snapshot |
| 🏋️ Train | Workouts | Phase plan, week selector, active workout mode, exercise swap, template builder, copy week |
| 🥗 Nutrition | Food Logging | BMR/TDEE, 2-tab Log Food (AI + Scan), food search (~1.4K DB), AI analysis (PRO), saved meals, water tracking, diet plan generator + PDF export |
| 💬 AI Coach | Chat | In-app chat, Telegram toggle, quick prompt chips, reasoning tab (PRO), photo/video upload (PRO) |
| 👤 Profile | Settings | Bio stats, goal card, edit profile, health sync, reports, subscription, logout |

---

#### 4. PROCESS INVARIANTS (NON-NEGOTIABLE)

> These rules apply EVERY interaction. Subagent dispatches inherit them.
> Pre-commit hook gates them. Violations are P0.

##### 4.1 Observation / bugfix workflow

- APK observations: WAIT for all → brainstorm → propose → user reviews → plan → execute. Never reflexively fix.
- Every fix must NAME writer(s) + reader(s) by file:line BEFORE proposing the fix.
- Writer/reader drift is the default suspect class.
- Every fix lands with a regression test in `test/contracts/` + a diagnose-doc.
- Refs: `feedback_observation_workflow.md`, `feedback_source_of_truth_audit.md`, `feedback_writer_reader_field_drift_recurring.md`.

##### 4.1.5 Bug-history lookup (BEFORE proposing root cause)

After observations captured + before brainstorming:
1. Grep `docs/diagnoses/INDEX.md` for matching symptom / concept / file paths.
2. Read every matching diagnose-doc — what was the root cause, what fixed it.
3. Check `feedback_*.md` files for the recurrence class.
4. If recurrence: cite prior instances in the new diagnose-doc's `related_bugs:` + `recurrence:` fields; apply the known-good fix pattern.
5. If not recurrence: note explicitly so future audits can verify.
6. **Value-semantics grep (pre-work):** a batch that changes a stored value's MEANING sweeps `test/` AND `supabase/functions/` for that value BEFORE coding — not just `lib/` (codified 2026-09-18 in the code-review tuning history; `feedback_green_check_input_set_width` #47).

##### 4.2 No-deferrals

- Multi-bug batches: fix ALL in same batch. No "lower priority" tagging.
- No "context tight" / "responsible handoff" as a stopping excuse — context management is the agent's job (use TodoWrite, dispatch focused subagents, compact when needed). <!-- deu-quote: enumerates the banned phrases -->

- **The ban is on the SEMANTIC, not the literal string.** Re-wrapping a deferral as `dedicated batch` / `test-maintenance batch` / `cleanup batch` / `next-batch baseline` / `documented baseline for next batch` is the SAME violation as `defer` / `follow-up batch`. When the menu you write would force founder to ratify a deferral to pick any option, the menu is malformed — re-design it. Codified 2026-05-24 as 7th instance per `feedback_mistake_dedicated_batch_is_defer.md` after founder caught the recovery batch's first plan attempting to ship APK +31 with 50 test failures rolled to a "dedicated test-maintenance batch". <!-- deu-quote: §4.2 enumerating the banned re-wraps it forbids -->
- **Structural closed==N invariant (P1.E, 2026-06-18):** every multi-item batch (≥4 findings/units) or audit MUST produce a `docs/audit/<batch>.closure.yaml` with per-entry `terminal_state:` ∈ {`closed_in_commit`, `upstream_blocked`, `blocked_on_user`, `verified_clean`} and no `deferred:` key. Gate 40 (`scripts/validate_audit_closure.dart`) recomputes the closed tally and FAILS if any item is non-terminal (closed < N). This makes deferrals structurally impossible — a non-terminal item blocks the gate. Small 2–3 item bugfix batches keep the existing per-fix diagnose-doc + TodoWrite discipline instead.
- Refs: `feedback_no_deferrals.md`, `feedback_no_deferrals_recurrence.md`, `feedback_no_stop_until_done.md`, `feedback_mistake_dedicated_batch_is_defer.md`.


### Original text: §4.5-§4.8

##### 4.5 Discipline gates per fix

- Diagnose-doc REQUIRED with `touched_layers_checked` YAML field (per §6).
- Migration apply paired with `backups/applied_migrations.json` update in same commit.
- IST throughout for date keys + cloud `date` columns + counter resets. Helpers: `lib/core/utils/ist_date.dart`, `supabase/functions/_shared/ist_date.ts`.
- SoT registry update for new writer/reader contracts: `docs/sot_registry.yaml`.
- Pre-commit hook MUST pass — no `--no-verify`.
- Cron-dispatched Edge Functions MUST use `_shared/cron_telemetry.ts` (adoption gate test exists).

##### 4.6 Feature-flag protocol for risky changes

When touching payment / sync / auth / AI prompt / plan generator:
1. Default new code path behind `kDebugMode` gate OR Hive flag OR RemoteConfig.
2. Old path preserved verbatim, reachable when gate closed.
3. Roll the gate after manual verification.
4. Delete the old path in the SAME batch that rolls the gate — that batch is
   already touching and re-testing this exact code, so the deletion is cheapest
   and safest there. If the founder schedules the roll for later, the old path
   is tracked on the OI board (or in `docs/ship_dark_pending_review.yaml`, which
   §4.12.4 already uses for exactly this shape), never left as an intention.
   Corrected 2026-08-17: this step read *"Once verified, delete old path in
   follow-up batch"* — a §4.2 violation sitting inside the process rules, found <!-- deu-quote: records what the step said before it was fixed -->
   when `check_no_deferral_euphemism.dart` was widened from staged-diff-only to
   a full sweep of CLAUDE.md and the skills. A diff-scoped gate can never see a
   violation older than itself.

##### 4.7 Naming conventions

Before introducing any new file / symbol / Hive key / cloud column / Edge Function name:
1. Read `docs/naming_conventions.md`.
2. Check the reserved-domain glossary.
3. If introducing a new domain term, append to the glossary.

##### 4.8 Subagent brief preamble + audit lens registry

- Every subagent investigation dispatch MUST prepend `docs/agent_brief_preamble.md` to the task-specific brief.
- When invoking review / audit work, specify which lenses from `docs/audit/LENS_REGISTRY.md` (54 canonical lenses, L1–L54) are in scope. Prevents "we just look at code" audit blind spot.


### Original text: §4.11

##### 4.11 Gates before refactor (NEW — extends §4.6 feature-flag protocol)

When a planned refactor touches a known bug class (writer/reader drift, restore completeness, telemetry, secret exposure, etc.):

1. The regression-detection gate script (`scripts/check_*.dart`) lives + is wired into pre-commit + CI **before** the first refactor commit lands.
2. Gate runs `--warn-only` for 24h to baseline current violations, then flips to hard-fail.
3. Each refactor commit can detect its own partial-state drift via the gate. No commit lands without the gate green.

See `feedback_gates_before_refactor.md`. This rule turns multi-day refactors into atomic-safe rolling commits.


### Original text: §5, §5.1, §6

#### 5. PER-BATCH MAINTENANCE PROTOCOL

> At the end of any batch that lands a commit, walk this checklist.
> "No update needed" is a valid answer — the agent MUST consider each row.
> Invoke `/update-docs` to walk it mechanically.
>
> **ENFORCED since 2026-08-25 by a `Stop` hook** (`scripts/batch_close_hook.dart`),
> because "the agent MUST consider each row" is an intention and intentions decay —
> this file says so itself at §4.13 point 6: *everything with a gate holds, everything
> on intention decays.* An audit that day found **four** rows unwalked in one
> three-part batch (skill tuning, feedback memory, the CLAUDE.md rows, and an
> unstated full-suite scope); none surfaced until founder asked directly.
> The three previously-wired hook events all fire BEFORE work, so nothing was
> watching the END of a batch — which is where §5 lives.
> It fires ONCE per HEAD (not per turn), only when commits have landed and are
> unpushed, and hands the checklist back with each row marked `[x]` / `[ ]` / `[?]`.
> **`[?]` means the hook could not determine it, NOT that it is fine** — several rows
> are unknowable to any script and exist to be ANSWERED, not assumed. What is enforced
> is that the rows are answered, not that they were done; the content stays
> self-attested, same trust model as rule 21's `presence_only:` and rule 24's ledger.
> Kill switch `.claude/.batch_close.disabled`; every error path exits 0. ⚠ Its state file `.claude/.batch_close_state` is ALSO listed in `retire_worktree_lib.dart`'s `regenerableIgnoredPaths` — it must be, or the hook silently makes every worktree it fires in permanently unretirable (diagnose `b4d7e9`, 2026-08-27; the same shape OI-128 fixed for test outputs). Any future tool that WRITES a gitignored file into a worktree owes that list an entry.

```
[ ] Diagnose-doc written + validated (every bug fix; rule §4.5)
[ ] Contract test added + green (every bug fix; rule §4.5)
[ ] SoT registry updated if writer/reader file:line changed
[ ] backups/applied_migrations.json updated if migration applied
[ ] Root CLAUDE.md: new non-negotiable invariant emerged? (rare)
[ ] Nested CLAUDE.md updated if feature contract changed
[ ] docs/architecture/<topic>.md updated if cross-cutting concept changed
[ ] feedback_*.md added/updated if user corrected a claim OR recurring class
[ ] project_*.md retrospective written (every shipped batch)
[ ] Agent memory index (the HARNESS `~/.claude/projects/<mangled>/memory/MEMORY.md` — NOT repo
    `memory/MEMORY.md`, a pointer stub since its mirror sat 3 months stale): a shipped batch's
    DEFAULT destination is a `MEMORY_ARCHIVED.md` line, NOT an index line. It earns an index
    line only for something not already on the OI board — and if it is, file the OI instead.
    The old row said only "MEMORY.md index updated": it mandated the WRITE and defined no
    removal, the same unclosed loop §4.13 point 6 closed for worktrees, and each of the last
    three consolidation passes then had to archive 4 shipped lines. Test any surviving
    `IN-FLIGHT` label with `git merge-base --is-ancestor <branch> main` — on 2026-08-11 one
    was still labelled in-flight the day after it merged. **No detector: one was built,
    ×2-reviewed and WITHDRAWN (OI-68/OI-69, 3 generations of parser scars) — don't re-propose.**
[ ] Worktree retired if merged + clean (incl. ignored) + nothing unpushed (§4.13 point 6):
      dart run scripts/retire_worktree.dart          # dry-run first, ALWAYS
    This row IS the trigger — point 6 is deliberately ungated, so nothing else fires it.
[ ] Context-artifact budget re-baselined if a tracked doc drifted (§7 row):
      dart run scripts/check_context_artifact_budget.dart        # then --record if intended
    THIS ROW IS THE TRIGGER, for the same reason the worktree row above is one.
    The gate's SOFT band is invisible locally — pre-commit.sh:368 runs every gate
    as `>/dev/null 2>&1`, so a PASS-with-WARN prints nothing; CI shows it, but only
    on main/develop pushes and PRs, which most branches never get. Without this row
    the first thing anyone sees is the HARD band blocking every commit in the repo.
    ⚠ `--record` REFUSES over a hard breach unless you also pass `--force-record`
    — deliberately, so a breach cannot be blessed by pasting the command the
    failure message prints.
[ ] Skill self-evolution: does any .claude/skills/<topic>/SKILL.md need a new bug-class entry, red flag, or trigger phrase?
[ ] Runtime verified on device — app launched, went through core flow, observed expected state (NON-NEGOTIABLE).
[ ] After the merge: `dart run scripts/retire_worktree.dart --execute <slug>` in the primary (§4.13.6).
```

##### 5.1 Skill self-evolution

**GATED since 2026-08-25 for the code-review skill** by
`scripts/check_skill_tuning_history.dart`: a commit that ADDS
`docs/reviews/<x>-review.md` must also append a same-dated entry to
`.claude/skills/code-review/tuning-history.md` (moved out of SKILL.md 2026-09-29), or the commit is blocked.
Born from the omission that motivated it — a B-pass produced a 4-finding review
that day and nothing was appended, so the skill's own self-evolution loop was the
thing decaying. **Scope, so this is not read as wider than it is:** code-review
only. `/hermes-pass` writes to the same directory but keeps its own tuning
section, and wiring that needs its own decision. Everything below — a new
bug-class in ANY skill — remains unenforceable by script and is prompted by the
§5 Stop hook instead.

After a batch that surfaced a new bug-class, red flag, or anti-pattern:
1. Check whether an existing skill's "Bug classes" or "Red flags" table covers it. If not, add an entry.
2. New entry cites: bug ID + one-line trigger + regression test path.
3. Skill edits commit in the SAME commit as the discovering fix.
4. New skills added under `.claude/skills/<topic>/SKILL.md` when 3+ batches share a pattern.

---

#### 6. MULTI-TIER COVERAGE PROTOCOL

> Every bug fix verifies state across every system tier it touches.
> Validator: `scripts/validate_diagnose_doc.dart` requires `touched_layers_checked` YAML field.

##### The 12 tiers

| # | Tier | How to verify |
|---|---|---|
| 1 | Client code | Read code, run tests, `flutter analyze` |
| 2 | Hive (local state) | Contract test in `test/contracts/`, manual Hive inspection |
| 3 | Postgres schema | `information_schema.columns`, `pg_constraint`, `pg_indexes` |
| 4 | Postgres data | Audit query on affected table |
| 5 | Migrations applied | MCP `list_migrations` vs `backups/applied_migrations.json` |
| 6 | Edge Function code vs deploy | API `GET /functions/<slug>` returns version |
| 7 | Cron jobs | `cron.job_run_details` last 24h for non-2xx |
| 8 | RLS policies | `pg_policies` for affected table |
| 9 | Storage buckets + objects | `storage.buckets` + `storage.objects` queries |
| 10 | Secrets / API keys | Smoke test Edge Function; check Vault `service_role_key` |
| 11 | External services | Razorpay / OneSignal / Firebase dashboard check |
| 12 | Client → server contract | Trace one full user flow end-to-end |

##### touched_layers_checked YAML field

Every diagnose-doc lists tiers with status `verified` / `fixed_in_this_batch` / `not_applicable` / `deferred` + evidence. Validator requires field non-empty + at least one `verified` or `fixed_in_this_batch`.

Subagent investigation dispatches prepend the 12-tier checklist via `docs/agent_brief_preamble.md` (§4.8).

---


### Original text: §7 short rows (before the table was reduced to bare topic | path)

| Topic | Path / detail |
|---|---|
| Active workout, swap, edit log, train screen | `lib/features/train/CLAUDE.md` |
| Food logging, water, scan meal, AI breakdown | `lib/features/nutrition/CLAUDE.md` |
| Home cards, weight log, streak, freeze | `lib/features/home/CLAUDE.md` |
| AI coach chat + tool dispatcher | `lib/features/ai_coach/CLAUDE.md` |
| Onboarding (stepped flow) | `lib/features/onboarding/CLAUDE.md` |
| Auth, session, cross-account guard | `lib/features/auth/CLAUDE.md` |
| Profile & settings | `lib/features/profile/CLAUDE.md` |
| WriteServices, sync fan-out, Hive contracts | `lib/core/services/CLAUDE.md` |
| Plan generator V4 | `lib/shared/repositories/plan_engine/CLAUDE.md` |
| Wardroom design system | `lib/shared/widgets/wardroom/CLAUDE.md` |
| Edge Function deploy + AI architecture | `supabase/functions/CLAUDE.md` |
| Migration apply protocol | `supabase/migrations/CLAUDE.md` |
| AI architecture (model matrix, tools, triggers, semantic retrieval) | `docs/architecture/ai.md` |
| Sync schedule, SoT rules, Hive field-name contracts, restore-completeness | `docs/architecture/sync.md` |
| Database schema (47 tables) | `docs/architecture/database.md` |
| Subscription gate pattern | `docs/architecture/subscription.md` |
| Payment flow + DPDP delete-account | `docs/architecture/payment.md` |
| Business rules (free/PRO matrix, calorie calc) | `docs/architecture/business-rules.md` |
| Functionality flow (intended-behaviour TEST CHARTER — every feature, numbered assertions) | `docs/architecture/functionality-flow.md` |
| Directory structure (annotated tree) | `docs/reference/directory-structure.md` |
| Exercise library reference | `docs/reference/exercise-library.md` |
| Food database reference | `docs/reference/food-database.md` |
| Common pitfalls (cross-domain) | `docs/playbook/common-pitfalls.md` |
| Bug history index | `docs/diagnoses/INDEX.md` (auto-generated; regenerated on commit) |
| SoT registry (machine-readable) | `docs/sot_registry.yaml` |
| Naming conventions | `docs/naming_conventions.md` |
| Audit lens registry (54 lenses; L54 = context-artifact cost, added 2026-08-30) | `docs/audit/LENS_REGISTRY.md` |
| Audit closure ledger (per-quarter) | `docs/audit/<YYYY_MM_DD>_audit_closures.yaml` (Gate 40 validator + `feedback_closure_yaml_per_finding_discipline.md`) |
| Blast-radius registry (4 tiers: feature/account/platform/catastrophic) | `docs/blast_radius.yaml` + `scripts/blast_radius_from_diff.dart` + `scripts/check_blast_radius_coverage.dart` |
| ADR registry (architectural decisions, MADR-lite) | `docs/adr/` (auto-generated `INDEX.md`; `/adr` scaffolds) |
| Handbook (durable working rules, portable) | `docs/handbook/` (auto-generated `INDEX.md`; bug-classes / process / conventions / audit / testing) |
| Incident playbook (post-mortems) | `docs/incidents/` + `alerts/_thresholds.yaml` + `/incident` skill (Phase 1 placeholder thresholds — Phase 2 tuning 2026-06-03) |
| Code review skills (B-pass per-commit, E-pass end-of-batch) | `.claude/skills/code-review/SKILL.md` + `.claude/skills/hermes-pass/SKILL.md` + `docs/reviews/` |
| E2E sim-testing (live-web cross-surface verification: Claude-in-Chrome real pixels, temp-PRO + cleanup, AI-coach tool driving, shared-Gemini-quota pacing, off-live canonical-routing fallback) | `.claude/skills/e2e-sim-testing/SKILL.md` |
| Device-CI runner + 4 critical Patrol flows | `docs/operations/DEVICE_TESTING.md` + `scripts/run-device-tests.sh` |
| Cron registry | `docs/operations/CRON_REGISTRY.md` (Gate 31) |
| Secret inventory | `docs/operations/SECRET_INVENTORY.md` |
| Fresh clone onboarding | `docs/onboarding/FRESH_CLONE.md` |
| Subagent brief preamble | `docs/agent_brief_preamble.md` |
| End-of-batch maintenance skill | `/update-docs` (`.claude/skills/update-docs/SKILL.md`) |

