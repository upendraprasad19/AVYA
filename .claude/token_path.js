// .claude/token_path.js
//
// ONE place that answers "which Supabase Management-API token file do the host-shell
// deploy tools read?" (deploy_via_api.js, apply_migration_via_api.js). The Dart twin is
// scripts/supabase_token_path_lib.dart (same order, same git lookup, pinned together by
// test/scripts/token_path_resolver_test.dart).
//
// Why this exists (2026-10-02): two token files sit on the VPS and only ONE works.
//   WORKS : <primary repo>/.supabase/supabase access token.txt            (2026-09-23)
//   REVOKED: <primary repo>/supabase/.supabase/supabase access token.txt  (2026-08-08)
//            -> HTTP 401 from api.supabase.com on the VPS. A path cannot be dead, only the
//            token in it: on the founder's Windows clone that path may hold a GOOD token
//            (unverified), which is why it stays a last-resort candidate here.
// The tools used to read ONLY the revoked path, and a linked worktree has neither file (both
// are gitignored), so every deploy session burned time on a 401 before finding the right file.
// Order: the repo-root `.supabase/` of THIS tree, then of the PRIMARY (main) worktree, then
// the legacy `supabase/.supabase/` paths (a warning is printed when one of those is used).
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const TOKEN_NAME = 'supabase access token.txt';

// A hook (or a parent `git` process) can export GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE;
// inherited, they make `git worktree list` answer about THAT repo, or fail from another cwd.
function scrubbedGitEnv() {
  const env = { ...process.env };
  for (const k of Object.keys(env)) {
    if (k === 'GIT_DIR' || k === 'GIT_WORK_TREE' || k === 'GIT_INDEX_FILE' || k === 'GIT_COMMON_DIR') {
      delete env[k];
    }
  }
  return env;
}

/**
 * The MAIN worktree root (first entry of `git worktree list --porcelain`). Correct for
 * linked worktrees, `--separate-git-dir` repos and submodule checkouts, unlike
 * dirname(git-common-dir). Returns `{ root, error }`; `error` explains a null root.
 */
function primaryRoot(repoRoot) {
  try {
    const out = execFileSync('git', ['worktree', 'list', '--porcelain'], {
      cwd: repoRoot,
      env: scrubbedGitEnv(),
      stdio: ['ignore', 'pipe', 'pipe'],
    }).toString();
    const first = out.split(/\r?\n/).find((l) => l.startsWith('worktree '));
    if (!first) return { root: null, error: 'git worktree list printed no worktree line' };
    return { root: first.slice('worktree '.length).trim(), error: null };
  } catch (e) {
    const msg = (e && e.stderr && e.stderr.toString().trim()) || (e && e.message) || String(e);
    return { root: null, error: msg.split('\n')[0].slice(0, 200) };
  }
}

/** Ordered candidate token files (existing or not). The last ones are the LEGACY paths. */
function candidateTokenFiles(repoRoot) {
  const root = path.resolve(repoRoot);
  const { root: primary } = primaryRoot(root);
  const hasOther = primary && path.resolve(primary) !== root;
  const list = [path.join(root, '.supabase', TOKEN_NAME)];
  if (hasOther) list.push(path.join(path.resolve(primary), '.supabase', TOKEN_NAME));
  list.push(path.join(root, 'supabase', '.supabase', TOKEN_NAME)); // legacy (401 on the VPS)
  if (hasOther) list.push(path.join(path.resolve(primary), 'supabase', '.supabase', TOKEN_NAME));
  return list;
}

function isLegacy(p) {
  return p.split(path.sep).slice(-3, -1).join('/') === 'supabase/.supabase';
}

/**
 * First candidate that exists, or null. `legacy` is true for a `supabase/.supabase` path.
 * `primaryError` is set when the primary worktree could not be located AND the tree looks like
 * a linked worktree (`.claude/worktrees/` in its path): the caller should say so, because the
 * silent fall-through is exactly how a deploy ends up on the legacy file.
 */
function resolveTokenFile(repoRoot) {
  const root = path.resolve(repoRoot);
  const { error } = primaryRoot(root);
  const looksLinked = root.split(path.sep).join('/').includes('/.claude/worktrees/');
  for (const p of candidateTokenFiles(root)) {
    if (fs.existsSync(p)) {
      return { path: p, legacy: isLegacy(p), primaryError: looksLinked ? error : null };
    }
  }
  return null;
}

module.exports = { candidateTokenFiles, resolveTokenFile, primaryRoot, TOKEN_NAME };
