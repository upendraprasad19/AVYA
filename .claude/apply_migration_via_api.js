#!/usr/bin/env node
// apply_migration_via_api.js
//
// Applies a single .sql migration to Supabase by POSTing to the
// Management API. Mirrors the auth + token resolution used by
// .claude/deploy_via_api.js. Use this when the SQL payload is too
// large to pass through the MCP apply_migration tool's `query`
// parameter (~25K-token cap per tool call).
//
// Usage:
//   node .claude/apply_migration_via_api.js <project_ref> <migration_file>
//
// Notes:
//   - This calls POST /v1/projects/{ref}/database/query (RPC-style),
//     which executes the SQL but does NOT add a row to cloud's
//     `supabase_migrations.schema_migrations` table. That's consistent
//     with the chunked-apply pattern documented in
//     supabase/migrations/README_RECONCILIATION_2026-05-11.md §C.
//     The local `backups/applied_migrations.json` is the audit source
//     for what was applied — the caller MUST update it in the same commit.

const fs = require('fs');
const path = require('path');
const https = require('https');

const TOKEN_PATH = path.join(__dirname, '..', 'supabase', '.supabase', 'supabase access token.txt');

function resolveToken() {
  if (process.env.SUPABASE_ACCESS_TOKEN_FITNESS) {
    return process.env.SUPABASE_ACCESS_TOKEN_FITNESS.trim();
  }
  if (fs.existsSync(TOKEN_PATH)) {
    return fs.readFileSync(TOKEN_PATH, 'utf-8').trim();
  }
  if (process.env.SUPABASE_ACCESS_TOKEN) {
    console.warn('[warn] using SUPABASE_ACCESS_TOKEN — verify it is the fitness-app account.');
    return process.env.SUPABASE_ACCESS_TOKEN.trim();
  }
  throw new Error('No access token. Set SUPABASE_ACCESS_TOKEN_FITNESS or populate ' + TOKEN_PATH);
}

function postJson(host, p, token, body) {
  const payload = JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const req = https.request({
      method: 'POST',
      host,
      path: p,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
    }, (res) => {
      let chunks = '';
      res.on('data', d => { chunks += d; });
      res.on('end', () => {
        resolve({ status: res.statusCode, body: chunks });
      });
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

async function main() {
  const [projectRef, sqlFile] = process.argv.slice(2);
  if (!projectRef || !sqlFile) {
    console.error('Usage: node .claude/apply_migration_via_api.js <project_ref> <migration_file>');
    process.exit(1);
  }
  if (!fs.existsSync(sqlFile)) {
    console.error(`File not found: ${sqlFile}`);
    process.exit(1);
  }
  const sql = fs.readFileSync(sqlFile, 'utf-8');
  console.log(`Applying ${(sql.length / 1024).toFixed(1)}KB SQL to project ${projectRef}…`);

  const token = resolveToken();
  const result = await postJson(
    'api.supabase.com',
    `/v1/projects/${projectRef}/database/query`,
    token,
    { query: sql }
  );

  console.log(`HTTP ${result.status}`);
  console.log(result.body.slice(0, 2000));
  if (result.status >= 200 && result.status < 300) {
    console.log('OK.');
    process.exit(0);
  }
  process.exit(1);
}

main().catch(e => { console.error(e.message || e); process.exit(1); });
