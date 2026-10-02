// .claude/token_path.js
//
// ONE place that answers "which Supabase Management-API token file do the host-shell
// deploy tools read?" (deploy_via_api.js, apply_migration_via_api.js).
//
// Why this exists (2026-10-02): two token files sit on the VPS and only ONE works.
//   WORKING : <primary repo>/.supabase/supabase access token.txt            (2026-09-23)
//   DEAD    : <primary repo>/supabase/.supabase/supabase access token.txt   (2026-08-08)
//             -> HTTP 401 from api.supabase.com. Never use it.
// The tools used to read ONLY the dead path, and a linked worktree has neither file (both
// are gitignored), so every deploy session burned time on a 401 before finding the
// right file. Order below: the repo-root `.supabase/` of THIS tree, then of the PRIMARY
// worktree (resolved through the git common dir), and only then the dead legacy path.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const TOKEN_NAME = 'supabase access token.txt';

function primaryRoot(repoRoot) {
  try {
    const common = execFileSync(
      'git',
      ['rev-parse', '--path-format=absolute', '--git-common-dir'],
      { cwd: repoRoot, stdio: ['ignore', 'pipe', 'ignore'] },
    ).toString().trim();
    return common ? path.dirname(common) : null;
  } catch (_) {
    return null;
  }
}

/** Ordered candidate token files (existing or not). The last is the DEAD legacy path. */
function candidateTokenFiles(repoRoot) {
  const root = path.resolve(repoRoot);
  const primary = primaryRoot(root);
  const list = [path.join(root, '.supabase', TOKEN_NAME)];
  if (primary && path.resolve(primary) !== root) {
    list.push(path.join(primary, '.supabase', TOKEN_NAME));
  }
  list.push(path.join(root, 'supabase', '.supabase', TOKEN_NAME)); // DEAD (401) - last resort
  if (primary && path.resolve(primary) !== root) {
    list.push(path.join(primary, 'supabase', '.supabase', TOKEN_NAME));
  }
  return list;
}

/** First candidate that exists, or null. `legacy` is true for the dead supabase/.supabase path. */
function resolveTokenFile(repoRoot) {
  for (const p of candidateTokenFiles(repoRoot)) {
    if (fs.existsSync(p)) {
      const legacy = p.split(path.sep).slice(-3, -1).join('/') === 'supabase/.supabase';
      return { path: p, legacy };
    }
  }
  return null;
}

module.exports = { candidateTokenFiles, resolveTokenFile, TOKEN_NAME };
