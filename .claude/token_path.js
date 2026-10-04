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
function primaryRoot(repoRoot, gitBin = 'git') {
  try {
    const out = execFileSync(gitBin, ['worktree', 'list', '--porcelain'], {
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

/**
 * Ordered candidates (existing or not) as `{ path, legacy }`; the legacy `supabase/.supabase`
 * entries come last. `legacy` is decided HERE, from which slot the path was built for, never by
 * parsing the path back (a repo whose own directory is named `supabase` would fool that).
 * `opts.git` overrides the git executable (tests use it to prove the git-failed branch).
 */
function candidateEntries(repoRoot, opts = {}) {
  const root = path.resolve(repoRoot);
  const { root: primary } = primaryRoot(root, opts.git || 'git');
  const hasOther = primary && path.resolve(primary) !== root;
  const list = [{ path: path.join(root, '.supabase', TOKEN_NAME), legacy: false }];
  if (hasOther) list.push({ path: path.join(path.resolve(primary), '.supabase', TOKEN_NAME), legacy: false });
  list.push({ path: path.join(root, 'supabase', '.supabase', TOKEN_NAME), legacy: true }); // 401 on the VPS
  if (hasOther) {
    list.push({ path: path.join(path.resolve(primary), 'supabase', '.supabase', TOKEN_NAME), legacy: true });
  }
  return list;
}

/** Ordered candidate token file paths (existing or not). The last ones are the LEGACY paths. */
function candidateTokenFiles(repoRoot, opts = {}) {
  return candidateEntries(repoRoot, opts).map((e) => e.path);
}

// A directory (or anything not a regular file) named like the token file is NOT a token: the
// Dart twin uses File().existsSync(), so both must agree.
function isRegularFile(p) {
  try {
    return fs.statSync(p).isFile();
  } catch (_) {
    return false;
  }
}

/**
 * First candidate that is a regular file, or null. `legacy` is true for a `supabase/.supabase`
 * path. `primaryError` is set when the primary worktree could not be located AND the tree looks
 * like a linked worktree (`.claude/worktrees/` in its path): the caller should say so, because
 * the silent fall-through is exactly how a deploy ends up on the legacy file.
 */
function resolveTokenFile(repoRoot, opts = {}) {
  const root = path.resolve(repoRoot);
  const { error } = primaryRoot(root, opts.git || 'git');
  const looksLinked = root.split(path.sep).join('/').includes('/.claude/worktrees/');
  for (const e of candidateEntries(root, opts)) {
    if (isRegularFile(e.path)) {
      return { path: e.path, legacy: e.legacy, primaryError: looksLinked ? error : null };
    }
  }
  return null;
}

module.exports = { candidateTokenFiles, resolveTokenFile, primaryRoot, TOKEN_NAME };
