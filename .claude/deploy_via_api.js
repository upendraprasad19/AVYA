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
 *
 * Example:
 *   node deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy \
 *     ./_payload_ai-proxy.json false
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

for (let i = 0; i < rawArgs.length; i++) {
  const a = rawArgs[i];
  if (a === '--token') {
    cliToken = rawArgs[++i];
  } else if (a === '--token-file') {
    cliTokenFile = rawArgs[++i];
  } else if (a === '--dry-run') {
    dryRun = true;
  } else if (a.startsWith('--token=')) {
    cliToken = a.slice('--token='.length);
  } else if (a.startsWith('--token-file=')) {
    cliTokenFile = a.slice('--token-file='.length);
  } else {
    positional.push(a);
  }
}

const [projectRef, fnName, payloadPath, verifyJwtArg] = positional;
if (!projectRef || !fnName || !payloadPath) {
  console.error('Usage: deploy_via_api.js <project_ref> <function_name> <payload_json_path> [verify_jwt] [flags]');
  console.error('  Flags: --token <value> | --token-file <path> | --dry-run');
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

// --- Payload load --------------------------------------------------------
const payload = JSON.parse(fs.readFileSync(payloadPath, 'utf-8'));
console.log(`[deploy] Loaded ${payload.length} files from ${payloadPath}`);
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

(async () => {
  if (dryRun) {
    console.log(`[deploy] DRY RUN — would POST ${url}`);
    console.log(`[deploy] DRY RUN — verify_jwt=${verifyJwt}`);
    console.log(`[deploy] DRY RUN — Authorization header: Bearer ${tokenPreview}`);
    console.log('[deploy] DRY RUN — skipping actual request. All inputs valid.');
    process.exit(0);
  }
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
