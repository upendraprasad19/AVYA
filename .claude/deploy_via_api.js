#!/usr/bin/env node
/**
 * Direct Supabase Management API edge function deployer.
 *
 * Bypasses MCP entirely — reads payload JSON from disk, builds a
 * multipart form, POSTs to the management API. This exists because
 * MCP deploy_edge_function requires the assistant to embed all file
 * content as a tool-call argument, and the assistant's per-turn
 * output token budget can't fit a 132KB payload.
 *
 * Usage:
 *   FORWARD DEPLOY (normal):
 *     node deploy_via_api.js <project_ref> <function_name> <payload_json_path> [verify_jwt] [flags]
 *
 *   ROLLBACK (I3 — tech-debt audit 2026-05-20):
 *     node deploy_via_api.js --rollback <function_name> <git-sha-or-keyword> [flags]
 *       <git-sha-or-keyword> ∈ { 7-char-sha, full-sha, "previous" (= HEAD~1) }
 *
 *   LEGACY ROLLBACK (snapshot-based, audit 2026-05-11):
 *     node deploy_via_api.js --rollback <project_ref> <function_name> [flags]
 *       (snapshot-from-cloud-pre-deploy; preserved unchanged)
 *
 *   HELP:
 *     node deploy_via_api.js --help
 *
 * Examples:
 *   node deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy \
 *     ./_payload_ai-proxy.json false
 *
 *   # Roll back ai-proxy to the source at commit abc1234.
 *   node deploy_via_api.js --rollback ai-proxy abc1234
 *
 *   # Roll back to the immediate previous commit (HEAD~1).
 *   node deploy_via_api.js --rollback ai-proxy previous
 *
 *   # Roll back to the most recent pre-deploy snapshot (legacy path).
 *   node deploy_via_api.js --rollback dedsavbjuwgarrhphgnl ai-proxy
 *
 * Token lookup priority (first match wins):
 *   1. CLI flag:       --token <value>  OR  --token-file <path>
 *   2. Env var:        SUPABASE_ACCESS_TOKEN_FITNESS  (preferred — specific to fitness-app account)
 *   3. Default file:   <repo>/supabase/.supabase/supabase access token.txt
 *   4. Fallback env:   SUPABASE_ACCESS_TOKEN          (warns — might be the wrong account)
 *
 * Flags:
 *   --token <value>        Use this token directly.
 *   --token-file <path>    Read token from this file (trimmed).
 *   --dry-run              Skip the actual POST (and smoke step). Validates payload + auth only.
 *   --yes / -y             Skip the interactive confirmation prompt (CI / unattended).
 *   --rollback             Rollback mode (see usage above).
 *   --no-snapshot          Skip the legacy pre-deploy cloud-snapshot capture.
 *   --no-smoke             Skip the post-deploy smoke step (I3 — discouraged).
 *   --project <ref>        Project ref for rollback mode (default: dedsavbjuwgarrhphgnl).
 *   --help / -h            Print this help and exit 0.
 *
 * I3 (Tech-debt audit 2026-05-20) additions:
 *   1. Git-SHA rollback path — `node deploy_via_api.js --rollback <fn> <sha>`
 *      reads `supabase/functions/<fn>/index.ts` at the given SHA without
 *      checking out, re-emits the payload via emit_payload.js semantics,
 *      diffs against current HEAD, and prompts confirmation before posting.
 *   2. Post-deploy smoke step — every successful forward deploy posts a
 *      synthetic `{ smoke: true }` payload to the deployed function and
 *      asserts a tolerated response (2xx for most, 401 for auth-required
 *      functions like verify-payment). Smoke failures log a WARN with the
 *      rollback command pre-baked; do NOT auto-rollback (operator call).
 *   3. Payload archive — every deploy writes `backups/edge_function_payloads/<fn>/v<N>_<sha>.json`.
 *      Pruned to the 3 most recent on every deploy. Regenerable from git
 *      so no PII concerns; serves as a fast-path for "redeploy v(N-1)".
 *
 * Pre-deploy cloud snapshot (legacy — audit-2026-05-11):
 *   Before every non-rollback, non-dry-run deploy, the deployer fetches
 *   the function's current cloud source via the Management API
 *   (GET /v1/projects/{ref}/functions/{slug}/body) and writes it to
 *   `.claude/_snapshots/<fn>_<ISO-ts>.json`. The legacy `--rollback`
 *   shape (2 positional args = project + fn) deploys this snapshot.
 *
 * Default confirmation:
 *   When stdin is a TTY and `--yes` / `--dry-run` were not passed, the
 *   deployer prints a summary and waits for "yes". Pressing any other
 *   key aborts.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync, spawnSync } = require('child_process');

// --- Argument parsing ----------------------------------------------------
const rawArgs = process.argv.slice(2);
const positional = [];
let cliToken = null;
let cliTokenFile = null;
let dryRun = false;
let assumeYes = false;
let rollback = false;
let skipSnapshot = false;
let skipSmoke = false;
let showHelp = false;
let rollbackProject = null;

for (let i = 0; i < rawArgs.length; i++) {
  const a = rawArgs[i];
  if (a === '--help' || a === '-h') {
    showHelp = true;
  } else if (a === '--token') {
    cliToken = rawArgs[++i];
  } else if (a === '--token-file') {
    cliTokenFile = rawArgs[++i];
  } else if (a === '--project') {
    rollbackProject = rawArgs[++i];
  } else if (a === '--dry-run') {
    dryRun = true;
  } else if (a === '--yes' || a === '-y') {
    assumeYes = true;
  } else if (a === '--rollback') {
    rollback = true;
  } else if (a === '--no-snapshot') {
    skipSnapshot = true;
  } else if (a === '--no-smoke') {
    skipSmoke = true;
  } else if (a.startsWith('--token=')) {
    cliToken = a.slice('--token='.length);
  } else if (a.startsWith('--token-file=')) {
    cliTokenFile = a.slice('--token-file='.length);
  } else if (a.startsWith('--project=')) {
    rollbackProject = a.slice('--project='.length);
  } else {
    positional.push(a);
  }
}

const DEFAULT_PROJECT_REF = 'dedsavbjuwgarrhphgnl';

// --- Help ----------------------------------------------------------------
function printHelp() {
  console.log(`deploy_via_api.js — Supabase Edge Function deployer

USAGE
  Forward deploy:
    node deploy_via_api.js <project_ref> <function_name> <payload_json_path> [verify_jwt] [flags]

  Rollback (git-SHA — I3, audit 2026-05-20):
    node deploy_via_api.js --rollback <function_name> <git-sha-or-keyword> [flags]
      <git-sha-or-keyword>: 7-char SHA, full SHA, or literal "previous" (= HEAD~1).

  Rollback (legacy cloud-snapshot, audit 2026-05-11):
    node deploy_via_api.js --rollback <project_ref> <function_name> [flags]

  Help:
    node deploy_via_api.js --help

FLAGS
  --token <value>        Use this Supabase Management API token directly.
  --token-file <path>    Read token from this file (trimmed).
  --project <ref>        Project ref for rollback mode (default: ${DEFAULT_PROJECT_REF}).
  --dry-run              Build payload + diff but don't POST anything.
  --yes / -y             Skip interactive confirmation (CI / unattended).
  --rollback             Enter rollback mode (see USAGE above).
  --no-snapshot          Skip pre-deploy cloud-snapshot capture.
  --no-smoke             Skip post-deploy smoke check (discouraged).
  --help / -h            Print this help.

I3 SAFETY FEATURES (audit 2026-05-20)
  - Every forward deploy archives its payload under
    backups/edge_function_payloads/<fn>/v<N>_<sha>.json
    (pruned to 3 most recent per function).
  - Every forward deploy runs a post-deploy smoke check:
      POST <fn-url>  body={"smoke":true}
    Tolerated codes: 2xx, plus 401 for verify-payment / admin-* /
    delete-account. Non-tolerated responses log a WARN with the
    rollback command pre-baked (operator decides — no auto-rollback).
  - Rollback by git SHA: reconstructs the function source at any past
    commit via \`git show <SHA>:supabase/functions/<fn>/index.ts\`
    (no checkout, no working-tree mutation), re-emits the payload
    byte-identical to emit_payload.js semantics, diffs against HEAD,
    confirms with operator, deploys.

EXAMPLES
  # Forward deploy ai-proxy in production:
  node .claude/deploy_via_api.js ${DEFAULT_PROJECT_REF} ai-proxy \\
    .claude/_payload_ai-proxy.json false

  # Roll back ai-proxy to commit fed9e2c (no checkout needed):
  node .claude/deploy_via_api.js --rollback ai-proxy fed9e2c

  # Roll back to immediate previous commit on disk for that function:
  node .claude/deploy_via_api.js --rollback ai-proxy previous

  # Dry-run rollback (produces payload + prints diff, no POST):
  node .claude/deploy_via_api.js --rollback ai-proxy abc1234 --dry-run

RUNBOOK
  Full operator runbook: docs/runbooks/edge-function-rollback.md
`);
}

if (showHelp) {
  printHelp();
  process.exit(0);
}

// --- Mode dispatch / positional resolution -------------------------------
// Forward mode:        <project_ref> <fn_name> <payload_path> [verify_jwt]
// Rollback (I3 git):   --rollback <fn_name> <sha-or-keyword>     (2 positional)
// Rollback (legacy):   --rollback <project_ref> <fn_name>        (2 positional)
//   Disambiguator: arg looks like a git revspec (40/7-char hex or "previous")
//                  → git-SHA mode. Otherwise → legacy snapshot mode.

let mode; // 'forward' | 'rollback-git' | 'rollback-snapshot'
let projectRef;
let fnName;
let payloadPath;
let verifyJwtArg;
let gitRevspec;

function looksLikeGitRevspec(s) {
  if (!s) return false;
  if (s === 'previous') return true;
  return /^[0-9a-fA-F]{7,40}$/.test(s);
}

if (rollback) {
  if (positional.length < 2) {
    console.error('Usage (rollback): deploy_via_api.js --rollback <function_name> <git-sha-or-previous>');
    console.error('              or: deploy_via_api.js --rollback <project_ref> <function_name>  (legacy snapshot)');
    console.error('Run with --help for full details.');
    process.exit(1);
  }
  if (looksLikeGitRevspec(positional[1])) {
    // git-SHA rollback (I3)
    mode = 'rollback-git';
    fnName = positional[0];
    gitRevspec = positional[1];
    projectRef = rollbackProject || DEFAULT_PROJECT_REF;
  } else {
    // legacy snapshot rollback
    mode = 'rollback-snapshot';
    projectRef = positional[0];
    fnName = positional[1];
  }
} else {
  mode = 'forward';
  [projectRef, fnName, payloadPath, verifyJwtArg] = positional;
  if (!projectRef || !fnName || !payloadPath) {
    console.error('Usage: deploy_via_api.js <project_ref> <function_name> <payload_json_path> [verify_jwt] [flags]');
    console.error('  Flags: --token <value> | --token-file <path> | --dry-run | --yes/-y | --rollback | --no-snapshot | --no-smoke');
    console.error('Run with --help for full details.');
    process.exit(1);
  }
}

// --- Token resolution ----------------------------------------------------
const DEFAULT_TOKEN_FILE = path.resolve(
  __dirname, '..', 'supabase', '.supabase', 'supabase access token.txt',
);
const LEGACY_TOKEN_FILE = path.join(os.homedir(), '.supabase', 'fitness-app-token');

function readTokenFile(p) {
  try {
    return fs.readFileSync(p, 'utf-8').trim();
  } catch (e) {
    throw new Error(`Failed to read token file ${p}: ${e.message}`);
  }
}

function resolveToken() {
  if (cliToken) {
    return { token: cliToken.trim(), source: '--token CLI flag' };
  }
  if (cliTokenFile) {
    return { token: readTokenFile(cliTokenFile), source: `--token-file ${cliTokenFile}` };
  }
  if (process.env.SUPABASE_ACCESS_TOKEN_FITNESS) {
    return {
      token: process.env.SUPABASE_ACCESS_TOKEN_FITNESS.trim(),
      source: 'SUPABASE_ACCESS_TOKEN_FITNESS env var',
    };
  }
  if (fs.existsSync(DEFAULT_TOKEN_FILE)) {
    return {
      token: readTokenFile(DEFAULT_TOKEN_FILE),
      source: `default file ${DEFAULT_TOKEN_FILE}`,
    };
  }
  if (fs.existsSync(LEGACY_TOKEN_FILE)) {
    return {
      token: readTokenFile(LEGACY_TOKEN_FILE),
      source: `legacy default file ${LEGACY_TOKEN_FILE}`,
    };
  }
  if (process.env.SUPABASE_ACCESS_TOKEN) {
    return {
      token: process.env.SUPABASE_ACCESS_TOKEN.trim(),
      source: 'SUPABASE_ACCESS_TOKEN env var (FALLBACK)',
      warn: true,
    };
  }
  return null;
}

// Token is required for live API calls. In dry-run we skip the check so
// `--help` and `--dry-run` work on machines without the token file.
let accessToken = null;
let tokenPreview = '';
if (!dryRun) {
  const resolved = resolveToken();
  if (!resolved || !resolved.token) {
    console.error('[deploy] ERROR: No Supabase Management API token found.');
    console.error('');
    console.error('  Provide one via any of these (priority order):');
    console.error('    1. --token <sbp_xxx>             (CLI flag)');
    console.error('       --token-file <path>           (CLI flag, reads from file)');
    console.error('    2. SUPABASE_ACCESS_TOKEN_FITNESS env var   (preferred)');
    console.error(`    3. File at ${DEFAULT_TOKEN_FILE}   (one line, just the token)`);
    console.error('    4. SUPABASE_ACCESS_TOKEN env var           (fallback — may be wrong account)');
    process.exit(1);
  }
  accessToken = resolved.token;
  tokenPreview = accessToken.slice(0, 10) + '...';
  console.log(`[deploy] Using token from: ${resolved.source}`);
  console.log(`[deploy] Token preview: ${tokenPreview}  (confirm this is the fitness-app account token)`);
  if (resolved.warn) {
    console.warn('[deploy] WARNING: SUPABASE_ACCESS_TOKEN may belong to the wrong account.');
  }
} else {
  // Best-effort token preview for dry-run UX.
  const resolved = resolveToken();
  if (resolved && resolved.token) {
    tokenPreview = resolved.token.slice(0, 10) + '...';
    console.log(`[deploy] DRY RUN — token would come from: ${resolved.source}`);
  } else {
    tokenPreview = '<no-token-found>';
    console.log('[deploy] DRY RUN — no token resolved (would fail in live mode).');
  }
}

const verifyJwt = verifyJwtArg !== 'false';

// --- I3: git-SHA rollback helpers ----------------------------------------
const REPO_ROOT = path.resolve(__dirname, '..');

function resolveGitSha(revspec) {
  // "previous" → HEAD~1 for THIS function file (last commit that touched
  // the function's index.ts). Fall back to plain HEAD~1 if no per-file
  // history exists.
  let target = revspec;
  if (revspec === 'previous') {
    const fnIndexRel = `supabase/functions/${fnName}/index.ts`;
    try {
      const out = execSync(
        `git log -n 2 --format=%H -- "${fnIndexRel}"`,
        { cwd: REPO_ROOT, encoding: 'utf-8' },
      ).trim().split('\n').filter(Boolean);
      if (out.length >= 2) {
        target = out[1]; // second-most-recent commit touching this file
      } else if (out.length === 1) {
        // First and only commit for this file — fall back to HEAD~1 repo-wide.
        target = 'HEAD~1';
      } else {
        target = 'HEAD~1';
      }
    } catch (e) {
      target = 'HEAD~1';
    }
  }
  try {
    const full = execSync(`git rev-parse ${target}`, { cwd: REPO_ROOT, encoding: 'utf-8' }).trim();
    return full;
  } catch (e) {
    console.error(`[deploy] ROLLBACK ERROR: could not resolve revspec "${revspec}" → ${target}`);
    console.error(`[deploy]                  git rev-parse said: ${e.message}`);
    process.exit(1);
  }
}

function gitShowAtSha(sha, relPath) {
  // Returns the file's contents at the given SHA, or null if missing.
  const r = spawnSync('git', ['show', `${sha}:${relPath}`], {
    cwd: REPO_ROOT,
    encoding: 'utf-8',
    maxBuffer: 16 * 1024 * 1024,
  });
  if (r.status !== 0) return null;
  return r.stdout;
}

function gitCommitSubject(sha) {
  try {
    return execSync(`git log -n 1 --format=%s ${sha}`, { cwd: REPO_ROOT, encoding: 'utf-8' }).trim();
  } catch (e) {
    return '(no subject)';
  }
}

// Parse relative TS imports out of a source string. Mirrors emit_payload.js.
function findRelativeImports(source) {
  const out = [];
  const re = /(?:from|import)\s+["']([^"']+)["']/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    const spec = m[1];
    if (!spec.startsWith('.')) continue;
    if (spec.endsWith('.d.ts')) continue;
    out.push(spec);
  }
  return out;
}

/**
 * Walk imports starting at <fn>/index.ts at the given SHA. Returns
 * { name, content } objects in payload shape. BYTE-IDENTICAL to what
 * emit_payload.js would have produced at that SHA.
 *
 * Path-naming scheme (must match emit_payload.js):
 *   - The entry is always 'index.ts'.
 *   - Every other file is `../<path-relative-to-functions-dir>`.
 */
function emitPayloadAtSha(sha, fnName) {
  const functionsDirRel = 'supabase/functions';
  const entryRel = `${functionsDirRel}/${fnName}/index.ts`;
  const entrySource = gitShowAtSha(sha, entryRel);
  if (entrySource === null) {
    console.error(`[deploy] ROLLBACK ERROR: ${entryRel} does not exist at SHA ${sha.slice(0, 7)}.`);
    process.exit(1);
  }

  const visited = new Map(); // relPath → content
  const order = []; // ordered list of relPath
  const entryAbs = `${functionsDirRel}/${fnName}/index.ts`;
  visited.set(entryAbs, entrySource);
  order.push(entryAbs);

  function walk(relPath, source) {
    if (!relPath.endsWith('.ts')) return;
    const dir = path.posix.dirname(relPath);
    for (const spec of findRelativeImports(source)) {
      if (!spec.endsWith('.ts')) continue;
      // Resolve POSIX-style (git paths use forward slashes regardless of OS).
      const resolved = path.posix.normalize(path.posix.join(dir, spec));
      // Must live under supabase/functions/
      if (!resolved.startsWith(`${functionsDirRel}/`)) continue;
      if (visited.has(resolved)) continue;
      const depSource = gitShowAtSha(sha, resolved);
      if (depSource === null) {
        console.warn(`[deploy] ROLLBACK WARN: dep ${resolved} missing at SHA ${sha.slice(0, 7)} — skipping.`);
        continue;
      }
      visited.set(resolved, depSource);
      order.push(resolved);
      walk(resolved, depSource);
    }
  }

  walk(entryAbs, entrySource);

  // Convert to payload shape: entry → 'index.ts'; others → '../<rel-from-functions-dir>'.
  const files = order.map((rel) => {
    const content = visited.get(rel);
    if (rel === entryAbs) {
      return { name: 'index.ts', content };
    }
    const relFromFunctionsDir = path.posix.relative(functionsDirRel, rel);
    return { name: `../${relFromFunctionsDir}`, content };
  });
  return files;
}

function diffSummaryVsHead(sha) {
  // Returns short summary of changes between SHA and HEAD restricted to
  // supabase/functions/<fnName>/.
  const scope = `supabase/functions/${fnName}/`;
  try {
    const out = execSync(
      `git diff --stat ${sha} HEAD -- ${scope}`,
      { cwd: REPO_ROOT, encoding: 'utf-8' },
    );
    return out.trim() || '(no diff vs HEAD for this function)';
  } catch (e) {
    return `(diff failed: ${e.message})`;
  }
}

// --- Legacy snapshot helpers (audit-2026-05-11) --------------------------
const SNAPSHOT_DIR = path.resolve(__dirname, '_snapshots');

function listSnapshotsFor(fn) {
  if (!fs.existsSync(SNAPSHOT_DIR)) return [];
  return fs
    .readdirSync(SNAPSHOT_DIR)
    .filter((n) => n.startsWith(`${fn}_`) && n.endsWith('.json'))
    .map((n) => ({
      name: n,
      path: path.join(SNAPSHOT_DIR, n),
      mtime: fs.statSync(path.join(SNAPSHOT_DIR, n)).mtimeMs,
    }))
    .sort((a, b) => b.mtime - a.mtime);
}

async function captureSnapshot() {
  if (skipSnapshot) {
    console.log('[deploy] Skipping snapshot (--no-snapshot).');
    return null;
  }
  const url = `https://api.supabase.com/v1/projects/${projectRef}/functions/${fnName}/body`;
  let res;
  try {
    res = await fetch(url, {
      method: 'GET',
      headers: { Authorization: `Bearer ${accessToken}` },
    });
  } catch (e) {
    console.warn(`[deploy] Snapshot fetch failed (non-fatal): ${e.message}`);
    return null;
  }
  if (res.status === 404) {
    console.log('[deploy] No existing function — skipping pre-deploy snapshot (first deploy).');
    return null;
  }
  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    console.warn(`[deploy] Snapshot HTTP ${res.status} (non-fatal): ${errText.slice(0, 200)}`);
    return null;
  }
  const contentType = res.headers.get('content-type') ?? '';
  const buf = Buffer.from(await res.arrayBuffer());
  const files = parseMultipartFiles(buf, contentType);
  if (!files || files.length === 0) {
    console.warn('[deploy] Snapshot parse produced 0 files — skipping write.');
    return null;
  }
  if (!fs.existsSync(SNAPSHOT_DIR)) {
    fs.mkdirSync(SNAPSHOT_DIR, { recursive: true });
  }
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const outPath = path.join(SNAPSHOT_DIR, `${fnName}_${ts}.json`);
  fs.writeFileSync(outPath, JSON.stringify(files, null, 2), 'utf-8');
  console.log(`[deploy] Snapshot captured: ${outPath}  (${files.length} files)`);
  return outPath;
}

function parseMultipartFiles(buf, contentType) {
  const m = /boundary=(.+)$/i.exec(contentType);
  if (!m) return null;
  const boundary = `--${m[1]}`;
  const parts = buf.toString('binary').split(boundary);
  const files = [];
  for (const part of parts) {
    if (!part || part === '--' || part === '--\r\n') continue;
    const headerEnd = part.indexOf('\r\n\r\n');
    if (headerEnd < 0) continue;
    const header = part.slice(0, headerEnd);
    const fname = /filename="([^"]+)"/.exec(header);
    if (!fname) continue;
    let body = part.slice(headerEnd + 4);
    if (body.endsWith('\r\n')) body = body.slice(0, -2);
    files.push({
      name: fname[1],
      content: Buffer.from(body, 'binary').toString('utf-8'),
    });
  }
  return files;
}

// --- I3: payload archive -------------------------------------------------
const ARCHIVE_DIR = path.resolve(REPO_ROOT, 'backups', 'edge_function_payloads');

function archivePayload(fnName, files, headSha) {
  try {
    const dir = path.join(ARCHIVE_DIR, fnName);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    // Filename: v<N>_<sha>.json — N is monotonic per-function counter
    // derived from how many archives currently exist + 1.
    const existing = fs.readdirSync(dir).filter((n) => n.endsWith('.json'));
    const nextN = existing.length + 1;
    const shortSha = (headSha || 'unknown').slice(0, 7);
    const archivePath = path.join(dir, `v${nextN}_${shortSha}.json`);
    fs.writeFileSync(archivePath, JSON.stringify(files, null, 2), 'utf-8');
    console.log(`[deploy] Archived payload to ${path.relative(REPO_ROOT, archivePath)}`);

    // Prune to most recent 3 by mtime.
    const allArchives = fs.readdirSync(dir)
      .filter((n) => n.endsWith('.json'))
      .map((n) => ({ name: n, path: path.join(dir, n), mtime: fs.statSync(path.join(dir, n)).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime);
    if (allArchives.length > 3) {
      for (const stale of allArchives.slice(3)) {
        fs.unlinkSync(stale.path);
        console.log(`[deploy] Pruned old archive ${path.relative(REPO_ROOT, stale.path)}`);
      }
    }
    return archivePath;
  } catch (e) {
    console.warn(`[deploy] Archive failed (non-fatal): ${e.message}`);
    return null;
  }
}

function currentHeadSha() {
  try {
    return execSync('git rev-parse HEAD', { cwd: REPO_ROOT, encoding: 'utf-8' }).trim();
  } catch (e) {
    return null;
  }
}

// --- I3: post-deploy smoke step ------------------------------------------
// Allow-list per function: codes that mean "deployed and running" even if
// they reject the synthetic {smoke:true} payload (e.g. missing JWT → 401
// is a valid healthy signal for auth-required functions).
const SMOKE_TOLERATED_CODES = {
  // 2xx is always tolerated for every function; the list below adds
  // function-specific non-2xx tolerations.
  'verify-payment': [401, 400],
  'admin-verify-payment': [401, 400],
  'admin-wipe-storage': [401, 400],
  'delete-account': [401, 400],
  'get-community-review-items': [401], // verify_jwt — unauth smoke gets a gateway 401 (expected, not a failure)
  'admin-dashboard-data': [401],       // verify_jwt — unauth smoke gets a gateway 401 (module does its own ADMIN_USER_IDS gate)
  'compute-admin-metrics-daily': [401], // cron-only auth (isAuthorizedCronCall)
  'create-razorpay-order': [401, 400],
  'razorpay-webhook': [400, 401], // missing signature header → 400 is healthy
  'ai-proxy': [400, 401],          // missing user_id → 400 is healthy
  'ai-proxy-pro': [400, 401],
  'ai-media-proxy': [400, 401],
  'log-client-error': [400],
  'morning-alert': [401],          // cron-only auth
  'evaluate-rank-promotions': [401],
  'compute-coach-signals': [401],
  'i-see-you-callout': [401],
  'expiry-reminder': [401],
  'proactive-coach-promotion': [401], // F44 — now cron/service-auth gated (was the fictional 'proactive-triggers', F47)
  'clean-orphan-media': [401],
  'pr-detection': [401],
  'daily-snapshot': [401],
  // Cron-only auth, same as their siblings above. These three were MISSING when
  // the six notif-prefs guards were deployed on 2026-07-27: an unauthenticated
  // smoke correctly gets 401 from `isAuthorizedCronCall`, but with no toleration
  // entry the deploy script reported that healthy 401 as a smoke FAILURE. The
  // deploy had in fact succeeded, so the misreport pushed toward re-deploying a
  // function that was already fine — the opposite of what a smoke step is for.
  'plateau-alert': [401],
  'protein-gap-alert': [401],
  're-engagement': [401],
  'beat-my-coach': [400, 401],
  'future-prediction': [400, 401],
  'assess-body-composition': [400, 401],
  'weekly-report': [400, 401],
  'one-line-coach': [400, 401],
  'streak-restore': [400, 401],
};

async function runSmokeStep(fnName, projectRef) {
  if (skipSmoke) {
    console.log('[deploy] Skipping post-deploy smoke (--no-smoke). NOT RECOMMENDED.');
    return { ok: true, skipped: true };
  }
  const url = `https://${projectRef}.supabase.co/functions/v1/${fnName}`;
  console.log(`[deploy] Smoke check → POST ${url}  body={"smoke":true}`);
  let res;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // Intentionally NO Authorization header — many functions enforce
        // their own auth; a missing-auth 401 is a valid "deployed" signal.
      },
      body: JSON.stringify({ smoke: true }),
    });
  } catch (e) {
    console.warn(`[deploy] Smoke fetch threw: ${e.message}`);
    console.warn('[deploy] WARN: post-deploy smoke could not reach the function.');
    console.warn(`[deploy] WARN: to roll back, run:`);
    console.warn(`[deploy] WARN:   node .claude/deploy_via_api.js --rollback ${fnName} previous`);
    return { ok: false, reason: `fetch failed: ${e.message}` };
  }
  const tolerated = SMOKE_TOLERATED_CODES[fnName] ?? [];
  const ok = (res.status >= 200 && res.status < 300) || tolerated.includes(res.status);
  if (ok) {
    console.log(`[deploy] Smoke OK — HTTP ${res.status} (function reachable; deployment confirmed).`);
    return { ok: true, status: res.status };
  }
  const bodyText = await res.text().catch(() => '');
  console.warn(`[deploy] Smoke FAIL — HTTP ${res.status} (not in tolerated set ${JSON.stringify(tolerated)}).`);
  console.warn(`[deploy] Smoke body (truncated): ${bodyText.slice(0, 200)}`);
  console.warn('[deploy] WARN: deployment succeeded BUT smoke flagged it. NOT auto-rolling back.');
  console.warn(`[deploy] WARN: to roll back, run:`);
  console.warn(`[deploy] WARN:   node .claude/deploy_via_api.js --rollback ${fnName} previous`);
  return { ok: false, status: res.status };
}

// --- Payload load (mode-dependent) ---------------------------------------
let payload;
let payloadSourceLabel;
let resolvedSha = null;

if (mode === 'forward') {
  payload = JSON.parse(fs.readFileSync(payloadPath, 'utf-8'));
  payloadSourceLabel = payloadPath;
} else if (mode === 'rollback-git') {
  resolvedSha = resolveGitSha(gitRevspec);
  const shortSha = resolvedSha.slice(0, 7);
  const subject = gitCommitSubject(resolvedSha);
  console.log(`[deploy] ROLLBACK (git): ${fnName} → ${shortSha}  "${subject}"`);
  payload = emitPayloadAtSha(resolvedSha, fnName);
  // Write the reconstructed payload next to other emit_payload.js outputs.
  const rollbackPayloadPath = path.resolve(__dirname, `_payload_${fnName}_rollback_${shortSha}.json`);
  fs.writeFileSync(rollbackPayloadPath, JSON.stringify(payload), 'utf-8');
  console.log(`[deploy] ROLLBACK (git): wrote ${path.relative(REPO_ROOT, rollbackPayloadPath)}  (${payload.length} files)`);
  console.log(`[deploy] ROLLBACK (git): diff vs HEAD for supabase/functions/${fnName}/:`);
  const diff = diffSummaryVsHead(resolvedSha);
  for (const line of diff.split('\n')) {
    console.log(`[deploy]   ${line}`);
  }
  payloadSourceLabel = rollbackPayloadPath;
} else if (mode === 'rollback-snapshot') {
  const snapshots = listSnapshotsFor(fnName);
  if (snapshots.length === 0) {
    console.error(`[deploy] ROLLBACK ERROR: no snapshots found for ${fnName} under ${SNAPSHOT_DIR}.`);
    process.exit(1);
  }
  const snapPath = snapshots[0].path;
  console.log(`[deploy] ROLLBACK (snapshot): using ${snapPath}`);
  console.log(`[deploy] ROLLBACK (snapshot): ${snapshots.length} snapshot(s) available; using most recent.`);
  payload = JSON.parse(fs.readFileSync(snapPath, 'utf-8'));
  payloadSourceLabel = snapPath;
}

console.log(`[deploy] Loaded ${payload.length} files from ${payloadSourceLabel}`);
const totalBytes = payload.reduce((a, f) => a + Buffer.byteLength(f.content, 'utf-8'), 0);
console.log(`[deploy] Total content size: ${totalBytes} bytes`);

// --- Multipart body ------------------------------------------------------
const boundary = '----icbf-deploy-' + Date.now().toString(16);
const CRLF = '\r\n';
const parts = [];

const metadata = {
  name: fnName,
  entrypoint_path: 'index.ts',
  verify_jwt: verifyJwt,
};

parts.push(Buffer.from(
  `--${boundary}${CRLF}` +
  `Content-Disposition: form-data; name="metadata"${CRLF}` +
  `Content-Type: application/json${CRLF}${CRLF}` +
  JSON.stringify(metadata) + CRLF
));

for (const f of payload) {
  const filename = f.name;
  parts.push(Buffer.from(
    `--${boundary}${CRLF}` +
    `Content-Disposition: form-data; name="file"; filename="${filename}"${CRLF}` +
    `Content-Type: application/typescript${CRLF}${CRLF}`
  ));
  parts.push(Buffer.from(f.content, 'utf-8'));
  parts.push(Buffer.from(CRLF));
}

parts.push(Buffer.from(`--${boundary}--${CRLF}`));

const body = Buffer.concat(parts);
console.log(`[deploy] Multipart body size: ${body.length} bytes`);

const url = `https://api.supabase.com/v1/projects/${projectRef}/functions/deploy?slug=${fnName}`;

async function confirmOrAbort() {
  if (assumeYes || dryRun) return;
  console.log('');
  console.log('  ╔════════════════════════════════════════╗');
  console.log('  ║   Edge Function deploy confirmation    ║');
  console.log('  ╠════════════════════════════════════════╣');
  console.log(`  ║   project   ${projectRef}`);
  console.log(`  ║   function  ${fnName}`);
  console.log(`  ║   verify_jwt ${verifyJwt}`);
  console.log(`  ║   files     ${payload.length}  (${totalBytes} bytes)`);
  console.log(`  ║   source    ${payloadSourceLabel}`);
  if (mode === 'rollback-git') {
    console.log(`  ║   MODE      ROLLBACK (git SHA ${resolvedSha.slice(0, 7)})`);
  } else if (mode === 'rollback-snapshot') {
    console.log('  ║   MODE      ROLLBACK (cloud snapshot)');
  }
  console.log('  ║   token     ' + tokenPreview);
  console.log('  ╚════════════════════════════════════════╝');
  process.stdout.write('Type "yes" to deploy: ');
  const answer = await new Promise((resolve) => {
    let chunks = '';
    const onData = (d) => {
      chunks += d.toString();
      if (chunks.includes('\n')) {
        process.stdin.off('data', onData);
        resolve(chunks.split('\n')[0].trim().toLowerCase());
      }
    };
    process.stdin.on('data', onData);
    process.stdin.once('end', () => {
      resolve(chunks.trim().toLowerCase());
    });
  });
  if (answer !== 'y' && answer !== 'yes') {
    console.log(`[deploy] ABORTED — input was "${answer}" (expected "y" or "yes").`);
    console.log('[deploy] Pass --yes / -y for unattended runs.');
    process.exit(2);
  }
  console.log('[deploy] Confirmed. Proceeding.');
}

(async () => {
  if (dryRun) {
    console.log(`[deploy] DRY RUN — would POST ${url}`);
    console.log(`[deploy] DRY RUN — verify_jwt=${verifyJwt}`);
    console.log(`[deploy] DRY RUN — Authorization header: Bearer ${tokenPreview}`);
    if (mode === 'rollback-git') {
      console.log(`[deploy] DRY RUN — rollback payload reconstructed from SHA ${resolvedSha.slice(0, 7)} (no POST).`);
    }
    console.log('[deploy] DRY RUN — skipping actual request. All inputs valid.');
    process.exit(0);
  }

  // Snapshot the current cloud state before forward deploys (legacy safety
  // net — preserved). Rollback paths already know what they're deploying.
  if (mode === 'forward') {
    await captureSnapshot();
  }

  await confirmOrAbort();

  // Archive the payload BEFORE posting so we keep a copy even if the
  // network call fails partway through.
  const headSha = currentHeadSha();
  archivePayload(fnName, payload, mode === 'rollback-git' ? resolvedSha : headSha);

  console.log(`[deploy] POST ${url}`);
  const t0 = Date.now();
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
    },
    body,
  });
  const dt = Date.now() - t0;
  const text = await res.text();
  console.log(`[deploy] HTTP ${res.status} in ${dt}ms`);
  console.log(`[deploy] Response body: ${text}`);

  if (!res.ok) {
    process.exit(1);
  }

  // I3: post-deploy smoke step. Runs on forward deploys AND rollbacks
  // (rollbacks need verification too — you just deployed *something*).
  await runSmokeStep(fnName, projectRef);

  process.exit(0);
})().catch((e) => {
  console.error('[deploy] ERROR:', e);
  process.exit(1);
});
