---
reviewed_at: 2026-10-02T23:40:00+05:30
staged_against: deploy-token-path (HEAD 987ce09b) vs origin/main
blast_radius: platform
reviewer: fresh-context-blind-agents (two rounds, Sonnet; round 2 on the post-round-1 tree)
lens_set: [guard_without_its_mirror, writer_reader_drift, missing_input, asserted_fixture_value, blast_radius_mismatch, secrets_in_tree, function_exception_swallow, cross_platform_paths, git_env_leakage]
findings_count: 9
verdict: accepted
---

# Code Review (B-pass) — host-shell deploy token resolution (`deploy-token-path`)

Scope: `.claude/token_path.js` + its Dart twin `scripts/supabase_token_path_lib.dart`, wired into `deploy_via_api.js`, `apply_migration_via_api.js` and `check_onconflict_live_arbiter.dart`; the doc rewording about the two token files; OI-165 closed, OI-283 filed; `docs/blast_radius.yaml` (the four deploy tools to account tier). Self-attested: no token value was read by any reviewer.

## Round 1 (against `9ea30235`)
Fixed in `33048976` (all verified by the author): the primary worktree is found with `git worktree list --porcelain` (not `dirname(git-common-dir)`, which breaks `--separate-git-dir` / submodules); inherited `GIT_DIR` / `GIT_WORK_TREE` / `GIT_INDEX_FILE` / `GIT_COMMON_DIR` are scrubbed; the Dart twin exists so the live-SQL runner resolves the same file; a legacy hit or an unresolvable primary (from a linked worktree) prints a warning; the docs said "DEAD, never use it", which is only true on the VPS: reworded to "revoked on the VPS (401, 2026-10-02), Windows clone unverified"; stale line cites in `runbook_deploy_verify_jwt_test.dart` repointed.

## Round 2 (against `33048976`): 0 P1, 0 P2, 9 P3, all fixed in `987ce09b`
| # | Sev | Finding | Status |
|---|---|---|---|
| 1 | P3 | nothing asserted `primaryError`; deleting it kept all 13 tests green | fixed: an optional git executable on both resolvers; node + dart tests for the git-failed branch (linked-shaped path reports it, plain path does not) |
| 2 | P3 | JS used `fs.existsSync` (true for a directory), Dart used `File().existsSync` | fixed: JS `statSync().isFile()`; a twin-agreement test |
| 3 | P3 | `isLegacy` parsed the last two path segments: a repo directory named `supabase` flagged its good root token legacy | fixed: legacy is decided from the candidate slot; a test for that shape |
| 4 | P3 | CLAUDE.md and deploy skill §1.3 said "never use the revoked file" and "try the other file once" | fixed: a 401 on the root file means expired / wrong account; regenerate or `--token-file`; no fallback to the revoked file |
| 5 | P3 | `hooks.md` still said the live runners 403 (OI-165) | fixed: OI-283 (no CI runner) |
| 6 | P3 | `day_swap_sync_load_live_verify.sql` header told operators the runner 403s | fixed |
| 7 | P3 | a test fixture cited OI-165 as OPEN; `check_alerts.dart` called the old token "403, deploy-scoped" | fixed (fixture id renamed, comment states revoked / 401) |
| 8 | P3 | closed OI-165 carried `commit: <pending>` | fixed |
| 9 | P3 | blast tier: the diff was classified `feature` (`.claude/**`), though it changes which prod credential the deploy tools use | fixed: the four tools are `account` in `docs/blast_radius.yaml`; this branch now classifies `platform` through its other files and carries the record |

Mutations (rule 21), each confirmed applied by `grep -c` and each reddening at least one test: JS `isFile`→`existsSync` (1 red); JS `primaryError` dropped (1 red); Dart `primaryError` dropped (1 red); JS primary-legacy flag flipped (2 reds). Files restored and `cmp`-verified.

## Checked clean
Order and names agree between the twins; explicit `--token` / `--token-file` / env tokens keep their precedence; a failed git call never silently picks a wrong file; spaces and non-ASCII paths; detached / prunable worktrees; bare repos; no token value in the tree; Gate 33 and the context budget pass.

## Accepted residue (self-attested)
The Windows clone's `supabase/.supabase/` token was not verified (kept as a last-resort candidate, warned on use). Symlinked checkouts can yield duplicate candidate paths (harmless).
