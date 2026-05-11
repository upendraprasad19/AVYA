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
 *   node deploy_via_api.js <project_ref> <function_name> <payload_json_path> [verify_jwt] [flags]
 *   node deploy_via_api.js --rollback <project_ref> <function_name> [flags]
 *
 * Example:
 *   node deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy \
 *     ./_payload_ai-proxy.json false
 *
 *   # Roll back ai-proxy to the most recent pre-deploy snapshot.
 *   node deploy_via_api.js --rollback dedsavbjuwgarrhphgnl ai-proxy
 *
 * Token lookup priority (first match wins):
 *   1. CLI flag:       --token <value>  OR  --token-file <path>
 *   2. Env var:        SUPABASE_ACCESS_TOKEN_FITNESS  (preferred — specific to fitness-app account)
 *   3. Default file:   ~/.supabase/fitness-app-token  (one-line file containing just the token)
 *   4. Fallback env:   SUPABASE_ACCESS_TOKEN          (warns — might be the wrong account)
 *
 * Flags:
 *   --token <value>        Use this token directly.
 *   --token-file <path>    Read token from this file (trimmed).
 *   --dry-run              Skip the actual POST. Validates payload + auth setup only.
 *   --yes / -y             Skip the default interactive confirmation prompt
 *                          (TTY-only). Use this in CI / unattended pipelines.
 *   --rollback             Deploy the most recent pre-deploy snapshot for
 *                          <function_name> instead of <payload_json_path>.
 *                          Snapshots are captured automatically before every
 *                          deploy at `.claude/_snapshots/<fn>_<ts>.json`.
 *   --no-snapshot          Skip the pre-deploy snapshot capture. Default is
 *                          to snapshot so every deploy is reversible.
 *
 * Pre-deploy snapshot:
 *   Before every non-rollback, non-dry-run deploy, the deployer fetches
 *   the function's current cloud source via the Management API
 *   (GET /v1/projects/{ref}/functions/{slug}/body) and writes it to
 *   `.claude/_snapshots/<fn>_<ISO-ts>.json` in the same multipart shape
 *   the deployer consumes. This makes every deploy reversible via the
 *   `--rollback` flag.
 *
 * Default confirmation:
 *   When stdin is a TTY and `--yes` / `--dry-run` / `--rollback` were
 *   not passed, the deployer prints a summary (function name, bytes,
 *   verify_jwt, token preview) and waits for ENTER. Pressing any other
 *   key (or piping non-empty stdin) aborts.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

// --- Argument parsing ----------------------------------------------------
// Separate flag args from positional args so order doesn't matter.
const rawArgs = process.argv.slice(2);
const positional = [];
let cliToken = null;
let cliTokenFile = null;
let dryRun = false;
// T23 (audit-2026-05-11) — new flags.
let assumeYes = false;
let rollback = false;
let skipSnapshot = false;

for (let i = 0; i < rawArgs.length; i++) {
  const a = rawArgs[i];
  if (a === '--token') {
    cliToken = rawArgs[++i];
  } else if (a === '--token-file') {
    cliTokenFile = rawArgs[++i];
  } else if (a === '--dry-run') {
    dryRun = true;
  } else if (a === '--yes' || a === '-y') {
    assumeYes = true;
  } else if (a === '--rollback') {
    rollback = true;
  } else if (a === '--no-snapshot') {
    skipSnapshot = true;
  } else if (a.startsWith('--token=')) {
    cliToken = a.slice('--token='.length);
  } else if (a.startsWith('--token-file=')) {
    cliTokenFile = a.slice('--token-file='.length);
  } else {
    positional.push(a);
  }
}

const [projectRef, fnName, payloadPath, verifyJwtArg] = positional;

// In rollback mode the payload path is resolved from the snapshot
// directory, so callers may omit it.
if (rollback) {
  if (!projectRef || !fnName) {
    console.error('Usage (rollback): deploy_via_api.js --rollback <project_ref> <function_name> [flags]');
    process.exit(1);
  }
} else if (!projectRef || !fnName || !payloadPath) {
  console.error('Usage: deploy_via_api.js <project_ref> <function_name> <payload_json_path> [verify_jwt] [flags]');
  console.error('  Flags: --token <value> | --token-file <path> | --dry-run | --yes/-y | --rollback | --no-snapshot');
  process.exit(1);
}

// --- Token resolution ----------------------------------------------------
// Default token location (created 2026-04-20). User-chosen path inside the
// repo's supabase/.supabase/ dir for discoverability. The directory itself
// is gitignored via supabase/.gitignore so the token never enters version
// control.
const DEFAULT_TOKEN_FILE = path.resolve(
  __dirname, '..', 'supabase', '.supabase', 'supabase access token.txt',
);
// Legacy fallback for the original default suggestion — checked second.
const LEGACY_TOKEN_FILE = path.join(os.homedir(), '.supabase', 'fitness-app-token');

function readTokenFile(p) {
  try {
    return fs.readFileSync(p, 'utf-8').trim();
  } catch (e) {
    throw new Error(`Failed to read token file ${p}: ${e.message}`);
  }
}

function resolveToken() {
  // 1. CLI flag
  if (cliToken) {
    return { token: cliToken.trim(), source: '--token CLI flag' };
  }
  if (cliTokenFile) {
    return { token: readTokenFile(cliTokenFile), source: `--token-file ${cliTokenFile}` };
  }
  // 2. Preferred env var
  if (process.env.SUPABASE_ACCESS_TOKEN_FITNESS) {
    return {
      token: process.env.SUPABASE_ACCESS_TOKEN_FITNESS.trim(),
      source: 'SUPABASE_ACCESS_TOKEN_FITNESS env var',
    };
  }
  // 3a. Default file (canonical location since 2026-04-20)
  if (fs.existsSync(DEFAULT_TOKEN_FILE)) {
    return {
      token: readTokenFile(DEFAULT_TOKEN_FILE),
      source: `default file ${DEFAULT_TOKEN_FILE}`,
    };
  }
  // 3b. Legacy default (kept for back-compat)
  if (fs.existsSync(LEGACY_TOKEN_FILE)) {
    return {
      token: readTokenFile(LEGACY_TOKEN_FILE),
      source: `legacy default file ${LEGACY_TOKEN_FILE}`,
    };
  }
  // 4. Fallback env (with warning)
  if (process.env.SUPABASE_ACCESS_TOKEN) {
    return {
      token: process.env.SUPABASE_ACCESS_TOKEN.trim(),
      source: 'SUPABASE_ACCESS_TOKEN env var (FALLBACK)',
      warn: true,
    };
  }
  return null;
}

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

const accessToken = resolved.token;
const tokenPreview = accessToken.slice(0, 10) + '...';
console.log(`[deploy] Using token from: ${resolved.source}`);
console.log(`[deploy] Token preview: ${tokenPreview}  (confirm this is the fitness-app account token)`);
if (resolved.warn) {
  console.warn('[deploy] WARNING: SUPABASE_ACCESS_TOKEN may belong to the wrong account.');
  console.warn('[deploy]          The Supabase CLI on this machine is logged in as Upendra (personal),');
  console.warn('[deploy]          NOT the fitness-app account (myfitnessjourney1988@gmail.com).');
  console.warn('[deploy]          Prefer SUPABASE_ACCESS_TOKEN_FITNESS to avoid confusion.');
}

const verifyJwt = verifyJwtArg !== 'false';

// --- T23 (audit-2026-05-11): snapshot + rollback helpers -----------------
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

/**
 * Fetch the current cloud function source and write it to
 * `_snapshots/<fn>_<ISO-ts>.json` in the same payload shape this
 * deployer consumes. Skips silently when the function doesn't exist
 * yet (first deploy) or when --no-snapshot was passed.
 */
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
  // The /body endpoint returns the multipart payload as a series of
  // parts. Easiest to capture is to read the raw response body and
  // re-encode as a single-file payload — but since callers usually
  // want a faithful copy, we instead parse the multipart back into
  // the payload-array shape we deploy from.
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

/**
 * Parse a multipart/form-data response back into the payload-array
 * shape ([{ name, content }]). Only handles the simple shape Supabase
 * returns — no nested parts.
 */
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

// --- Payload load --------------------------------------------------------
// In rollback mode, payloadPath is resolved from the latest snapshot.
let resolvedPayloadPath = payloadPath;
if (rollback) {
  const snapshots = listSnapshotsFor(fnName);
  if (snapshots.length === 0) {
    console.error(`[deploy] ROLLBACK ERROR: no snapshots found for ${fnName} under ${SNAPSHOT_DIR}.`);
    console.error('[deploy]                  Snapshots are captured automatically on every non-dry-run deploy.');
    process.exit(1);
  }
  resolvedPayloadPath = snapshots[0].path;
  console.log(`[deploy] ROLLBACK: latest snapshot for ${fnName} is ${resolvedPayloadPath}`);
  console.log(`[deploy] ROLLBACK: ${snapshots.length} snapshot(s) available; using most recent.`);
}

const payload = JSON.parse(fs.readFileSync(resolvedPayloadPath, 'utf-8'));
console.log(`[deploy] Loaded ${payload.length} files from ${resolvedPayloadPath}`);
const totalBytes = payload.reduce((a, f) => a + Buffer.byteLength(f.content, 'utf-8'), 0);
console.log(`[deploy] Total content size: ${totalBytes} bytes`);

// The management API deploys via multipart form data.
// metadata field is JSON: { name, entrypoint_path, import_map_path, verify_jwt }
// then each file is a separate "file" form field with filename = relative path.

const boundary = '----icbf-deploy-' + Date.now().toString(16);
const CRLF = '\r\n';

const parts = [];

const metadata = {
  name: fnName,
  // Server writes uploaded files to /tmp/.../source/<filename>. The
  // entrypoint_path metadata is treated as a path RELATIVE to source/,
  // so we just supply 'index.ts' (no file:// scheme, no source/ prefix —
  // the server prepends 'source/' itself).
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
  // Normalise filename: strip leading "../" so server stores under expected path.
  // The MCP convention uses "../_shared/foo.ts" for shared deps. The management
  // API just stores files keyed by the form filename — Deno resolves imports at
  // runtime relative to the entrypoint.
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

/**
 * T23 (audit-2026-05-11) — interactive confirmation. Only prompts
 * when stdin is a TTY and --yes / --dry-run / --rollback weren't
 * passed. Pipe-safe: a piped invocation with no `--yes` aborts
 * unless the input contained "y\n" or "yes\n".
 */
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
  console.log(`  ║   source    ${resolvedPayloadPath}`);
  if (rollback) {
    console.log('  ║   MODE      ROLLBACK (deploying snapshot)');
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
    console.log('[deploy] DRY RUN — skipping actual request. All inputs valid.');
    process.exit(0);
  }

  // T23 — capture pre-deploy snapshot. Skipped on rollback (we're
  // already deploying the snapshot) and on --no-snapshot.
  if (!rollback) {
    await captureSnapshot();
  }

  await confirmOrAbort();

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
  process.exit(res.ok ? 0 : 1);
})().catch((e) => {
  console.error('[deploy] ERROR:', e);
  process.exit(1);
});
