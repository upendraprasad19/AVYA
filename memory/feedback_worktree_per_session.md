---
name: One worktree per session — never edit/commit in the shared main folder
description: Multiple Claude sessions in the shared main folder share ONE git index; concurrent `git add` mixes their files across sessions (2 incidents 2026-07-07). EVERY session works in its own worktree (`sh scripts/new-worktree.sh <slug>`); main is integration-only. Enforced by scripts/check_commit_from_worktree.dart (pre-commit) + a SessionStart warning. CLAUDE.md §4.13, diagnose f0c2d5.
metadata:
  node_type: memory
  type: feedback
---

**What happened:** On 2026-07-07, two incidents mixed work across concurrent Claude
sessions. Both sessions were running in the SHARED main folder
(`C:/Upendra/Claude Code/Fitness App`). That folder has ONE git index
(`.git/index`): a `git add` from either session stages into the SAME index, so a
`git commit` from one session can silently sweep in the OTHER session's staged
files. During the OPT-A batch I ran `git checkout -b` + staged/committed directly
in the main folder while a concurrent session had its coach-completion work staged
there — I only avoided shipping their files by (a) pathspec-committing and
(b) finally moving to an isolated worktree.

**What's actually true:** git WORKTREES each have their OWN index. Working in a
dedicated worktree makes the cross-session mixing structurally impossible. The
`.claude/worktrees/<branch>` convention + the `using-git-worktrees` skill already
existed and most batches used them — the gap was that it was never ENFORCED, so a
session could work directly in the shared main folder and collide.

**How to avoid next time (now enforced):**
- **Before ANY edit/commit, create your own worktree:** `sh scripts/new-worktree.sh
  <slug>` (branches off the latest `main`, copies `.env`), then
  `cd .claude/worktrees/<slug>` and do ALL work there. Its git index is isolated.
- **The shared main folder is INTEGRATION-ONLY:** reads, `git merge <branch>` +
  `git push`, and `/build-apk`. Never `git add`/commit feature work there.
- **A pre-commit gate blocks it:** `scripts/check_commit_from_worktree.dart` fails a
  non-integration commit made in the primary worktree (primary = `git rev-parse
  --git-dir` == `--git-common-dir`, both resolved absolute so it holds from a
  subdirectory too). Exempt: integration ops into main (merge/cherry-pick/revert),
  linked worktrees, CI (`GITHUB_ACTIONS`), nothing-staged, and `ALLOW_MAIN_COMMIT=1`
  (rare, deliberate solo). Never `--no-verify` around it.
- **A SessionStart warning** (`scripts/discipline_hook.dart`) fires when a session
  starts in the shared main folder.
- **Even a solo session should use a worktree** — it is always safe, and "is another
  session active in this folder?" is not reliably knowable. When two sessions must
  share the machine, give each its own worktree; the main folder is the serialized
  integration point (one merge/push at a time). See CLAUDE.md §4.13, diagnose f0c2d5.
