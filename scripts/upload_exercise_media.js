#!/usr/bin/env node
// scripts/upload_exercise_media.js
//
// Batch M1 (plan R7, R14). Moves the Wardroom animations named by scripts/data/library_media_v16.json into the
// PRIVATE Storage bucket `exercise-media` of the fitness project, and proves the bucket is private.
//
//   node scripts/upload_exercise_media.js                                     # dry run: the plan + a check of every local file
//   node scripts/upload_exercise_media.js --execute --report <path>           # upload the active files' current objects
//   node scripts/upload_exercise_media.js --canary --execute --report <path>  # three tiny files + the privacy proof
//   node scripts/upload_exercise_media.js --canary --repost --execute --report <path>
//   node scripts/upload_exercise_media.js --probe-key                         # which key names the endpoint returned (never the key)
//   node scripts/upload_exercise_media.js --probe-control avatars/<name>      # positive control for the public-route probe
//   node scripts/upload_exercise_media.js --verify                            # every active object: length + sha256; then the probes
//   node scripts/upload_exercise_media.js --sign <names> [--expires 300]      # short-lived signed URLs (stdout only)
//   node scripts/upload_exercise_media.js --delete-object <names> --execute --confirm-bucket exercise-media --report <path>
//   node scripts/upload_exercise_media.js --delete-bucket --execute --confirm-bucket exercise-media --report <path>
//   flags: --table --wardroom-dir --only --cache-control --token-file --base-url --management-url
//
// Pins: the project ref and the bucket are constants (there is no --bucket flag); an unknown flag is refused. The key is the
// service-role key, from SUPABASE_SERVICE_ROLE_KEY or, failing that, the Management API with the access-token FILE (the
// SUPABASE_ACCESS_TOKEN* variables are never read). The key is never printed, logged or written to the report.
// Exit: 0 ok, 1 refused or failed (the message says why), 2 usage.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const REPO = path.resolve(__dirname, '..');
const PROJECT_REF = 'dedsavbjuwgarrhphgnl';
const BUCKET = 'exercise-media';
const DEFAULT_TABLE = path.join(__dirname, 'data', 'library_media_v16.json');
const MANAGEMENT_DEFAULT = 'https://api.supabase.com';
const OBJECT_RE = /^\d{4}-[a-z0-9]+(-[a-z0-9]+)*_v\d+\.webp$/;
const CANARY_RE = /^canary-[1-3]_v0\.webp$/;
// The default is the `private` form: an object's cache-control is fixed at upload (x-upsert false), a signed URL is a bearer link, and a
// shared cache that stores a signed response for a year would outlive the link's expiry. A form containing `public` is refused.
// The canary uploads all three so the observed headers say which survive. (The bare form is the shared-cacheable one; it is the last.)
const CACHE_FORMS = ['private, max-age=31536000, immutable', 'max-age=31536000, immutable', 'max-age=31536000'];
const DEFAULT_CACHE = CACHE_FORMS[0];
const REQUEST_TIMEOUT_MS = 60000;
const MAX_CONSECUTIVE_FAILURES = 5;
const WARDROOM_REL = ['assets', 'exercise animations', 'forgetrainer_animations', 'gifs', 'wardroom customized gifs'];

class Stop extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}
const stop = (m) => {
  throw new Stop(m, 1);
};
const usage = (m) => {
  throw new Stop(m, 2);
};

// ---- output (every line passes the redactor; the key and the access token are registered once known) ---------------------
const SECRETS = [];
const redact = (s) => SECRETS.reduce((acc, v) => (v && v.length >= 8 ? acc.split(v).join('[redacted]') : acc), String(s));
const say = (s = '') => process.stdout.write(`${redact(s)}\n`);
const warn = (s = '') => process.stderr.write(`${redact(s)}\n`);

async function finish(code) {
  await new Promise((r) => process.stdout.write('', r));
  await new Promise((r) => process.stderr.write('', r));
  process.exit(code);
}

// ---- arguments ----------------------------------------------------------------------------------------------------------
const VALUE_FLAGS = new Set([
  '--table', '--wardroom-dir', '--only', '--sign', '--expires', '--cache-control', '--report', '--token-file', '--base-url',
  '--management-url', '--confirm-bucket', '--probe-control', '--delete-object',
]);
const BOOL_FLAGS = new Set(['--execute', '--canary', '--repost', '--probe-key', '--verify', '--delete-bucket']);

function parseArgs(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const key = a.replace(/^--/, '').replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (VALUE_FLAGS.has(a)) {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) usage(`${a} needs a value`);
      o[key] = v;
    } else if (BOOL_FLAGS.has(a)) {
      o[key] = true;
    } else {
      usage(`unknown flag ${a}`);
    }
  }
  return o;
}

// hostname must be EXACTLY 127.0.0.1 or localhost after parsing (never a prefix match: `http://127.0.0.1@evil.com/` is evil.com).
function seamUrl(value, flag) {
  let u;
  try {
    u = new URL(value);
  } catch (_) {
    return usage(`${flag} is not a URL`);
  }
  if ((u.protocol !== 'http:' && u.protocol !== 'https:') || u.username || u.password) usage(`${flag} must be a plain http(s) URL`);
  if (u.hostname !== '127.0.0.1' && u.hostname !== 'localhost') usage(`${flag} is accepted only for 127.0.0.1 or localhost (got host ${u.hostname})`);
  return u.origin;
}

function resolveEndpoints(o) {
  const hasBase = o.baseUrl !== undefined;
  const hasMgmt = o.managementUrl !== undefined;
  if (hasBase !== hasMgmt) usage('--base-url and --management-url must be given together');
  if (hasBase) return { base: seamUrl(o.baseUrl, '--base-url'), management: seamUrl(o.managementUrl, '--management-url'), seam: true };
  return { base: `https://${PROJECT_REF}.supabase.co`, management: MANAGEMENT_DEFAULT, seam: false };
}

// ---- table + local files ------------------------------------------------------------------------------------------------
const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

function readTable(p) {
  let t;
  try {
    t = JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (e) {
    stop(`cannot read the media table ${p}: ${e.message}`);
  }
  if (!t || typeof t.files !== 'object' || typeof t.rows !== 'object') stop(`media table ${p} has no files / rows`);
  return t;
}

function objectOf(slug, file) {
  const v = file.versions && file.versions[file.versions.length - 1];
  if (!v || !Number.isInteger(v.media_version)) stop(`file ${slug} has no usable version`);
  const name = `${slug}_v${v.media_version}.webp`;
  if (!OBJECT_RE.test(name)) stop(`object name ${name} is not a valid exercise-media object name`);
  return { slug, name, file: v.file, sha: v.webp_sha256, bytes: v.webp_bytes };
}

/** The `active` files' current objects, optionally restricted by --only. unmapped and taken_down files are out of scope. */
function activeObjects(table, only) {
  const all = Object.entries(table.files).filter(([, f]) => f.status === 'active').map(([slug, f]) => objectOf(slug, f));
  if (only === undefined) return all;
  const wanted = only.split(',').filter(Boolean);
  if (wanted.length === 0) usage('--only needs at least one slug');
  const bySlug = new Map(all.map((x) => [x.slug, x]));
  return wanted.map((s) => bySlug.get(s) || usage(`--only ${s}: not an active file of the table`));
}

function defaultWardroom() {
  const { primaryRoot } = require(path.join(REPO, '.claude', 'token_path.js'));
  const { root, error } = primaryRoot(REPO);
  if (!root) stop(`cannot locate the primary checkout (${error}); pass --wardroom-dir`);
  return path.join(root, ...WARDROOM_REL);
}

function localFile(wardroom, obj) {
  const rel = obj.file;
  if (typeof rel !== 'string' || !rel.startsWith('webp-720/') || rel.includes('..') || rel.includes('\\')) {
    stop(`${obj.slug}: the table's file path ${JSON.stringify(rel)} is not under webp-720/`);
  }
  return path.join(wardroom, ...rel.split('/'));
}

/** Reads and checks one local file against the table. Returns {ok, status, bytes}. */
function checkLocal(wardroom, obj) {
  const p = localFile(wardroom, obj);
  if (!fs.existsSync(p) || !fs.statSync(p).isFile()) return { ok: false, status: 'missing' };
  const bytes = fs.readFileSync(p);
  if (sha256(bytes) !== obj.sha || bytes.length !== obj.bytes) return { ok: false, status: 'sha mismatch' };
  return { ok: true, status: 'ok', bytes };
}

// ---- report path --------------------------------------------------------------------------------------------------------
const FOLD = process.platform === 'win32' || process.platform === 'darwin';
const fold = (p) => (FOLD ? p.toLowerCase() : p);

/**
 * realpath of the nearest existing ancestor, plus the not-yet-existing remainder. The native form is used on purpose: on
 * Windows it expands 8.3 short names (C:\PROGRA~1) and turns a \\?\C:\ device spelling into C:\, so those spellings of a path
 * inside the repository compare as inside; the JS form leaves the first alone and throws EISDIR on the second.
 */
function realpathLoose(p) {
  let cur = path.resolve(p);
  const rest = [];
  while (!fs.existsSync(cur)) {
    const parent = path.dirname(cur);
    if (parent === cur) break;
    rest.unshift(path.basename(cur));
    cur = parent;
  }
  const real = fs.existsSync(cur) ? fs.realpathSync.native(cur) : cur;
  return path.join(real, ...rest);
}

function isInside(root, p) {
  const rel = path.relative(fold(realpathLoose(root)), fold(realpathLoose(p)));
  return rel === '' || (rel !== '..' && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel));
}

function checkReportPath(report) {
  if (!report) usage('--report <path> is required with --execute');
  const { primaryRoot } = require(path.join(REPO, '.claude', 'token_path.js'));
  const { root: primary, error } = primaryRoot(REPO);
  if (!primary) stop(`cannot locate the primary checkout to keep the report out of it (${error})`);
  for (const root of [REPO, primary]) {
    if (isInside(root, report)) stop(`the report path must be outside the repository and the primary checkout (it is inside ${root})`);
  }
  const resolved = path.resolve(report);
  // Prove the report can be written BEFORE anything destructive runs (a delete mode records its result last). A file created
  // only for the probe is removed again, and so is every directory the probe had to create, so a run that stops early leaves
  // nothing behind. A symbolic link is refused: opening a dangling one would create its target, and removing "our" file would
  // remove the link instead.
  let existing = null;
  try {
    existing = fs.lstatSync(resolved);
  } catch (e) {
    if (e.code !== 'ENOENT') usage(`the report path cannot be inspected (${e.code || e.message}); nothing was sent`);
  }
  if (existing && existing.isSymbolicLink()) usage('the report path is a symbolic link; give the path of a real file; nothing was sent');
  const leaf = path.dirname(resolved);
  // The directories the probe has to create, deepest first, listed BEFORE the mkdir: the return value of a recursive
  // mkdirSync cannot be used to find them again (on Windows it is the \\?\ spelling, which never equals a path walked up
  // from the leaf, so a stop-at-the-first-created-directory test is dead code there and removes empty parents that were
  // already there).
  const toCreate = [];
  for (let d = leaf; !fs.existsSync(d); ) {
    toCreate.push(d);
    const parent = path.dirname(d);
    if (parent === d) break;
    d = parent;
  }
  try {
    fs.mkdirSync(leaf, { recursive: true });
    fs.closeSync(fs.openSync(resolved, 'a'));
    if (!existing) fs.unlinkSync(resolved);
  } catch (e) {
    usage(`the report path cannot be written (${e.code || e.message}); nothing was sent`);
  } finally {
    // On both paths, and only the directories listed above; the first one that cannot be removed (not empty) ends it.
    for (const d of toCreate) {
      try {
        fs.rmdirSync(d);
      } catch (_) {
        break;
      }
    }
  }
  return resolved;
}

/** The reason a run stopped, for a partial report: the error text, redacted when it is written. */
const stoppedBy = (e) => String((e && e.message) || e).slice(0, 200);

// ---- HTTP ---------------------------------------------------------------------------------------------------------------
const state = { deleteAllowed: false };

async function request(method, url, { headers = {}, body } = {}) {
  if (method === 'DELETE' && !state.deleteAllowed) throw new Error('internal: a DELETE outside the two delete modes');
  return fetch(url, { method, headers, body, redirect: 'manual', signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
}

const authHeaders = (key) => ({ authorization: `Bearer ${key}`, apikey: key });
const objectUrl = (base, name) => `${base}/storage/v1/object/${BUCKET}/${name}`;
const authenticatedUrl = (base, name) => `${base}/storage/v1/object/authenticated/${BUCKET}/${name}`;
const publicUrl = (base, bucket, name) => `${base}/storage/v1/object/public/${bucket}/${name}`;

const netReason = (e) => {
  const c = e && e.cause && (e.cause.code || e.cause.message);
  return `network error${c ? ` (${String(c).slice(0, 80)})` : ''}`;
};

// ---- key ----------------------------------------------------------------------------------------------------------------
function decodeJwtRef(key) {
  const parts = key.split('.');
  if (parts.length !== 3) return { jwt: false };
  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return { jwt: true, ref: payload.ref };
  } catch (_) {
    return { jwt: false };
  }
}

function checkKeyRef(key) {
  const d = decodeJwtRef(key);
  if (d.jwt && d.ref !== PROJECT_REF) stop('the service-role key is a JWT for another project; refusing');
  return d.jwt ? 'ref ok' : 'ref not checkable (not a JWT)';
}

function tokenFile(o) {
  if (o.tokenFile !== undefined) {
    const p = path.resolve(o.tokenFile);
    if (!fs.existsSync(p) || !fs.statSync(p).isFile()) return null;
    return p;
  }
  const { resolveTokenFile } = require(path.join(REPO, '.claude', 'token_path.js'));
  const r = resolveTokenFile(REPO);
  return r ? r.path : null;
}

/** {key, source, refNote, names} - the key is registered with the redactor before anything can print. */
async function resolveKey(o, endpoints) {
  const envKey = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
  if (envKey) {
    SECRETS.push(envKey);
    return { key: envKey, source: 'environment', refNote: checkKeyRef(envKey), names: null };
  }
  const tf = tokenFile(o);
  if (!tf) {
    stop('no service-role key: set SUPABASE_SERVICE_ROLE_KEY, or provide a Management API access-token file (--token-file)');
  }
  const access = fs.readFileSync(tf, 'utf8').trim();
  if (!access) stop('the access-token file is empty');
  SECRETS.push(access);
  let res;
  try {
    res = await request('GET', `${endpoints.management}/v1/projects/${PROJECT_REF}/api-keys?reveal=true`, {
      headers: { authorization: `Bearer ${access}` },
    });
  } catch (e) {
    return stop(`the Management API key request failed: ${netReason(e)}`);
  }
  if (res.status !== 200) {
    return stop(`the Management API key request answered ${res.status}; set SUPABASE_SERVICE_ROLE_KEY in the shell instead`);
  }
  let list;
  try {
    list = await res.json();
  } catch (_) {
    return stop('the Management API key answer was not JSON; set SUPABASE_SERVICE_ROLE_KEY in the shell instead');
  }
  if (!Array.isArray(list)) return stop('the Management API key answer was not a list');
  const names = list.map((k) => ({ name: String(k && k.name), length: k && typeof k.api_key === 'string' ? k.api_key.length : 0 }));
  const entry = list.find((k) => k && k.name === 'service_role' && typeof k.api_key === 'string' && k.api_key.length > 0);
  if (!entry) {
    return stop(`the Management API returned no revealed service_role key (names: ${names.map((n) => `${n.name}:${n.length}`).join(', ')}); set SUPABASE_SERVICE_ROLE_KEY in the shell instead`);
  }
  SECRETS.push(entry.api_key);
  return { key: entry.api_key, source: 'management api', refNote: checkKeyRef(entry.api_key), names, status: res.status };
}

// ---- object operations --------------------------------------------------------------------------------------------------
/** HEAD with the key. absent = any status other than 200. */
async function headObject(base, key, name) {
  const res = await request('HEAD', authenticatedUrl(base, name), { headers: authHeaders(key) });
  return { status: res.status, length: Number(res.headers.get('content-length')) };
}

async function getObjectSha(base, key, name) {
  const res = await request('GET', authenticatedUrl(base, name), { headers: authHeaders(key) });
  if (res.status !== 200) return { status: res.status, sha: null, length: 0 };
  const buf = Buffer.from(await res.arrayBuffer());
  return { status: 200, sha: sha256(buf), length: buf.length };
}

/** Is the object a duplicate answer? status 409, or 400 whose JSON body carries statusCode "409" / Duplicate. */
function isDuplicate(status, bodyText) {
  if (status === 409) return true;
  if (status !== 400) return false;
  try {
    const j = JSON.parse(bodyText);
    return String(j.statusCode) === '409' || /duplicate/i.test(String(j.error || j.message || ''));
  } catch (_) {
    return /duplicate/i.test(bodyText);
  }
}

const isQuota = (status, bodyText) => status === 413 || /quota|limit exceeded|exceeded the maximum/i.test(bodyText);

async function postObject(base, key, name, bytes, cacheControl) {
  const res = await request('POST', objectUrl(base, name), {
    headers: { ...authHeaders(key), 'content-type': 'image/webp', 'cache-control': cacheControl, 'x-upsert': 'false' },
    body: bytes,
  });
  const text = await res.text();
  return { status: res.status, text };
}

/** Equal-or-different decision for an existing object: GET the bytes. */
async function compareExisting(base, key, obj) {
  const g = await getObjectSha(base, key, obj.name);
  if (g.status !== 200) return { equal: false, status: g.status, unreadable: true };
  return { equal: g.sha === obj.sha, status: 200 };
}

/** One file of the upload. Returns {outcome: 'uploaded'|'alreadyEqual'} or throws Stop for a stop condition. */
async function uploadOne(ctx, obj, bytes) {
  const { base, key, cache } = ctx;
  const head = await headObject(base, key, obj.name);
  if (head.status === 200) {
    const c = await compareExisting(base, key, obj);
    if (c.equal) return { outcome: 'alreadyEqual' };
    return stop(`${obj.slug}: the object ${obj.name} exists with different bytes (objects are immutable); stopping`);
  }
  const post = await postObject(base, key, obj.name, bytes, cache);
  if (post.status === 200) return { outcome: 'uploaded' };
  if (isQuota(post.status, post.text)) return stop(`${obj.slug}: the upload was refused for size or quota (status ${post.status}); stopping`);
  if (isDuplicate(post.status, post.text)) {
    const c = await compareExisting(base, key, obj);
    if (c.equal) return { outcome: 'alreadyEqual' };
    return stop(`${obj.slug}: the object ${obj.name} appeared with different bytes (objects are immutable); stopping`);
  }
  throw new Error(`POST answered ${post.status}`);
}

// ---- the privacy probes (no credential) ---------------------------------------------------------------------------------
async function noCredentialProbes(base, name) {
  const out = {};
  for (const [label, url] of [['publicRoute', publicUrl(base, BUCKET, name)], ['noAuthorization', authenticatedUrl(base, name)]]) {
    try {
      const res = await request('GET', url, {});
      out[label] = res.status;
      await res.arrayBuffer().catch(() => {});
    } catch (e) {
      out[label] = netReason(e);
    }
  }
  return out;
}

// A probe that did not run (a network error), or that answered anything but a plain refusal (429, 5xx, 3xx, 206), proves nothing: it must
// stop the run, not count as "private".
const REFUSAL_STATUSES = new Set([400, 401, 403, 404]);

function assertPrivate(probes, name) {
  const open = Object.entries(probes).filter(([, s]) => s === 200).map(([l]) => l);
  if (open.length) stop(`${name} is readable without a login (${open.join(', ')} answered 200): the bucket is not private; stopping`);
  const unclear = Object.entries(probes).filter(([, s]) => !REFUSAL_STATUSES.has(s)).map(([l, st]) => `${l}: ${st}`);
  if (unclear.length) stop(`${name}: the privacy probe did not get a clear refusal (${unclear.join('; ')}); privacy is NOT shown; stopping`);
}

// ---- signing ------------------------------------------------------------------------------------------------------------
async function signObject(ctx, name, expires) {
  const res = await request('POST', `${ctx.base}/storage/v1/object/sign/${BUCKET}/${name}`, {
    headers: { ...authHeaders(ctx.key), 'content-type': 'application/json' },
    body: JSON.stringify({ expiresIn: expires }),
  });
  if (res.status !== 200) return { status: res.status, url: null };
  let j;
  try {
    j = await res.json();
  } catch (_) {
    return { status: res.status, url: null, bad: 'the sign answer was not JSON' };
  }
  const signed = j && (j.signedURL || j.signedUrl);
  if (typeof signed !== 'string') return { status: res.status, url: null, bad: 'the sign answer has no signedURL' };
  const baseUrl = new URL(ctx.base);
  // The answer is a path relative to /storage/v1 (what supabase-js appends to its storage URL); an absolute URL is kept and host-checked.
  const joined = /^[a-z][a-z0-9+.-]*:/i.test(signed) ? new URL(signed) : new URL(`${ctx.base}/storage/v1${signed.startsWith('/') ? '' : '/'}${signed}`);
  if (joined.host !== baseUrl.host || joined.protocol !== baseUrl.protocol) {
    return stop(`the signed URL for ${name} points at another host (${joined.host}); refusing`);
  }
  return { status: res.status, url: joined.toString() };
}

// ---- modes --------------------------------------------------------------------------------------------------------------
function writeReport(p, data) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, `${redact(JSON.stringify(data, null, 2))}\n`);
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function modeDryRun(o, table, wardroom) {
  const objs = activeObjects(table, o.only);
  const total = objs.reduce((n, x) => n + x.bytes, 0);
  say(`plan: ${objs.length} objects, ${total} bytes -> ${BUCKET} (private) on project ${PROJECT_REF}`);
  const counts = { ok: 0, missing: 0, 'sha mismatch': 0 };
  const bad = [];
  for (const obj of objs) {
    const r = checkLocal(wardroom, obj);
    counts[r.status] += 1;
    if (!r.ok) bad.push(`${obj.slug}: ${r.status}`);
  }
  say(`local files: ok ${counts.ok}, missing ${counts.missing}, sha mismatch ${counts['sha mismatch']}`);
  for (const b of bad.slice(0, 20)) say(`  ${b}`);
  if (bad.length) stop(`${bad.length} local file(s) do not match the table; nothing was sent`);
  say('dry run only: nothing was sent');
}

async function modeExecute(o, table, wardroom, ctx, reportPath) {
  const objs = activeObjects(table, o.only);
  const uploaded = [];
  const alreadyEqual = [];
  const failed = [];
  let consecutive = 0;
  let stopped = null;
  for (const obj of objs) {
    const local = checkLocal(wardroom, obj);
    if (!local.ok) {
      failed.push({ name: obj.name, reason: `local file ${local.status}` });
      stopped = `${obj.slug}: the local file is ${local.status}`;
      break;
    }
    try {
      const r = await uploadOne(ctx, obj, local.bytes);
      (r.outcome === 'uploaded' ? uploaded : alreadyEqual).push(obj.name);
      consecutive = 0;
    } catch (e) {
      if (e instanceof Stop) {
        failed.push({ name: obj.name, reason: e.message });
        stopped = e.message;
        break;
      }
      failed.push({ name: obj.name, reason: e.message && e.message.startsWith('POST') ? e.message : netReason(e) });
      consecutive += 1;
      if (consecutive >= MAX_CONSECUTIVE_FAILURES) {
        stopped = `${MAX_CONSECUTIVE_FAILURES} failures in a row; stopping`;
        break;
      }
    }
  }
  writeReport(reportPath, { mode: 'execute', bucket: BUCKET, planned: objs.length, uploaded, alreadyEqual, failed, stopped });
  say(`uploaded ${uploaded.length}, alreadyEqual ${alreadyEqual.length}, failed ${failed.length} of ${objs.length}`);
  if (stopped) stop(stopped);
  if (failed.length) stop(`${failed.length} object(s) failed; run again to continue`);
}

function smallestThumbnails(wardroom) {
  const dir = path.join(wardroom, 'thumbnails-192');
  if (!fs.existsSync(dir)) stop(`${dir} does not exist`);
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.webp')).map((f) => ({ f, size: fs.statSync(path.join(dir, f)).size }));
  files.sort((a, b) => a.size - b.size || a.f.localeCompare(b.f));
  if (files.length < 3) stop('fewer than three thumbnails to use as canaries');
  return files.slice(0, 3).map((x) => path.join(dir, x.f));
}

async function modeCanary(o, wardroom, ctx, reportPath) {
  const files = smallestThumbnails(wardroom);
  const entries = [];
  let stopped = null;
  for (let i = 0; i < 3; i++) {
    const name = `canary-${i + 1}_v0.webp`;
    const bytes = fs.readFileSync(files[i]);
    const sha = sha256(bytes);
    const cache = CACHE_FORMS[i];
    const e = { name, cacheControl: cache, bytes: bytes.length };
    entries.push(e);
    const obj = { slug: name, name, sha };
    const head = await headObject(ctx.base, ctx.key, name);
    e.headBeforePost = head.status;
    if (head.status === 200) {
      const c = await compareExisting(ctx.base, ctx.key, obj);
      if (!c.equal) return stop(`${name} exists with different bytes; delete it first (--delete-object)`);
      e.postStatus = 'skipped (already equal)';
    } else {
      const post = await postObject(ctx.base, ctx.key, name, bytes, cache);
      e.postStatus = post.status;
      if (post.status !== 200 && !isDuplicate(post.status, post.text)) {
        stopped = `${name}: the canary POST answered ${post.status}`;
        break;
      }
    }
    const g = await getObjectSha(ctx.base, ctx.key, name);
    e.authenticatedGet = { status: g.status, sha: g.sha === sha ? 'equal' : 'different' };
    const s = await signObject(ctx, name, 300);
    e.signStatus = s.status;
    if (s.url) {
      const res = await request('GET', s.url, {});
      const buf = res.status === 200 ? Buffer.from(await res.arrayBuffer()) : null;
      e.signedGet = { status: res.status, sha: buf ? (sha256(buf) === sha ? 'equal' : 'different') : 'n/a', cacheControl: res.headers.get('cache-control') };
    } else {
      e.signedGet = null;
    }
    e.probes = await noCredentialProbes(ctx.base, name);
    try {
      assertPrivate(e.probes, name);
    } catch (err) {
      stopped = err.message;
      break;
    }
  }
  writeReport(reportPath, { mode: 'canary', bucket: BUCKET, canaries: entries, stopped });
  for (const e of entries) {
    say(`${e.name}: head ${e.headBeforePost}, post ${e.postStatus}, get ${e.authenticatedGet && e.authenticatedGet.sha}, sign ${e.signStatus}, signed get ${e.signedGet ? `${e.signedGet.status} ${e.signedGet.sha} cache-control=${e.signedGet.cacheControl}` : 'n/a'}, probes ${JSON.stringify(e.probes)}`);
  }
  if (stopped) stop(stopped);
}

async function modeRepost(o, wardroom, ctx, reportPath) {
  const bytes = fs.readFileSync(smallestThumbnails(wardroom)[0]);
  const post = await postObject(ctx.base, ctx.key, 'canary-1_v0.webp', bytes, DEFAULT_CACHE);
  say(`repost canary-1_v0.webp: status ${post.status}, body ${post.text.slice(0, 300)}`);
  writeReport(reportPath, { mode: 'canary-repost', status: post.status, body: post.text.slice(0, 300) });
}

async function modeVerify(o, table, ctx) {
  const objs = activeObjects(table, o.only);
  if (objs.length === 0) stop('verify: the table has no active object to check (an empty check proves nothing)');
  const problems = [];
  let okCount = 0;
  for (const obj of objs) {
    try {
      const head = await headObject(ctx.base, ctx.key, obj.name);
      if (head.status !== 200) {
        problems.push(`${obj.slug}: missing (HEAD ${head.status})`);
        continue;
      }
      if (head.length !== obj.bytes) {
        problems.push(`${obj.slug}: wrong length ${head.length}, expected ${obj.bytes}`);
        continue;
      }
      const g = await getObjectSha(ctx.base, ctx.key, obj.name);
      if (g.status !== 200) problems.push(`${obj.slug}: GET ${g.status}`);
      else if (g.sha !== obj.sha) problems.push(`${obj.slug}: wrong sha256`);
      else okCount += 1;
    } catch (e) {
      problems.push(`${obj.slug}: ${netReason(e)}`);
    }
  }
  say(`verify: ${okCount} of ${objs.length} objects match the table`);
  for (const p of problems.slice(0, 20)) say(`  ${p}`);
  if (objs.length > 0) {
    const probes = await noCredentialProbes(ctx.base, objs[0].name);
    say(`no-credential probes on ${objs[0].name}: ${JSON.stringify(probes)}`);
    assertPrivate(probes, objs[0].name);
  }
  if (problems.length) stop(`${problems.length} object(s) do not match the table`);
}

function parseNames(value, flag) {
  const names = value.split(',').filter(Boolean);
  if (names.length === 0) usage(`${flag} needs at least one name`);
  for (const n of names) {
    if (!OBJECT_RE.test(n) && !CANARY_RE.test(n)) usage(`${flag}: "${n}" is not a valid object name`);
  }
  return names;
}

function slugOfObject(name) {
  return name.replace(/_v\d+\.webp$/, '');
}

async function modeSign(o, table, ctx) {
  const names = parseNames(o.sign, '--sign');
  const expires = o.expires === undefined ? 300 : Number(o.expires);
  const current = new Set(activeObjects(table).map((x) => x.name));
  for (const n of names) {
    if (!CANARY_RE.test(n) && !current.has(n)) usage(`--sign ${n}: not the current object of an active file`);
  }
  for (const n of names) {
    const s = await signObject(ctx, n, expires);
    if (!s.url) stop(`signing ${n} answered ${s.status}${s.bad ? ` (${s.bad})` : ''}`);
    say(`${n} ${s.url}`);
  }
}

async function modeDeleteObject(o, table, ctx, reportPath, endpoints) {
  const names = parseNames(o.deleteObject, '--delete-object');
  for (const n of names) {
    if (CANARY_RE.test(n)) continue;
    const f = table.files[slugOfObject(n)];
    if (f && f.status === 'active') usage(`--delete-object ${n}: the object of an active file is not deleted by this tool`);
  }
  state.deleteAllowed = true;
  const results = [];
  let bad = false;
  let failure = null;
  let inFlight = null; // the object whose DELETE was sent (or whose HEAD is running) when a request is cut off
  try {
    for (const n of names) {
      inFlight = n;
      const del = await request('DELETE', objectUrl(ctx.base, n), { headers: authHeaders(ctx.key) });
      await del.arrayBuffer().catch(() => {});
      let head = await headObject(ctx.base, ctx.key, n);
      let note = '';
      if (head.status === 200) {
        const wait = endpoints.seam && process.env.EXERCISE_MEDIA_RETRY_WAIT_MS ? Number(process.env.EXERCISE_MEDIA_RETRY_WAIT_MS) : 90000;
        say(`${n}: HEAD still 200 after the delete (CDN lag?); waiting ${wait} ms and checking again`);
        await sleep(wait);
        head = await headObject(ctx.base, ctx.key, n);
        note = ' (second check)';
        if (head.status === 200) bad = true;
      }
      results.push({ name: n, deleteStatus: del.status, headAfter: head.status, secondCheck: note !== '' });
      inFlight = null;
      say(`${n}: DELETE ${del.status}, HEAD with key ${head.status}${note}`);
    }
  } catch (e) {
    failure = e;
  }
  // The report is written even when a request threw halfway: an object already deleted must be on record.
  // A cut DELETE may or may not have been executed by the server: inFlight names the object, as emptyStatus: null does for the bucket.
  writeReport(reportPath, { mode: 'delete-object', bucket: BUCKET, results, ...(failure ? { stoppedBy: stoppedBy(failure), inFlight } : {}) });
  if (failure) throw failure;
  if (bad) stop('an object still answers 200 after the delete and a second check');
}

async function modeDeleteBucket(o, ctx, reportPath) {
  state.deleteAllowed = true;
  let empty;
  try {
    empty = await request('POST', `${ctx.base}/storage/v1/bucket/${BUCKET}/empty`, { headers: authHeaders(ctx.key) });
  } catch (e) {
    // The empty call may or may not have reached the server: the report says so instead of saying nothing.
    writeReport(reportPath, { mode: 'delete-bucket', emptyStatus: null, deleteStatus: null, stoppedBy: stoppedBy(e) });
    throw e;
  }
  await empty.arrayBuffer().catch(() => {});
  say(`empty ${BUCKET}: ${empty.status}`);
  if (empty.status !== 200) {
    writeReport(reportPath, { mode: 'delete-bucket', emptyStatus: empty.status, deleteStatus: null });
    return stop(`emptying the bucket answered ${empty.status}; the bucket was not deleted`);
  }
  let del;
  try {
    del = await request('DELETE', `${ctx.base}/storage/v1/bucket/${BUCKET}`, { headers: authHeaders(ctx.key) });
  } catch (e) {
    writeReport(reportPath, { mode: 'delete-bucket', emptyStatus: empty.status, deleteStatus: null, stoppedBy: stoppedBy(e) });
    throw e;
  }
  await del.arrayBuffer().catch(() => {});
  say(`delete ${BUCKET}: ${del.status}`);
  writeReport(reportPath, { mode: 'delete-bucket', emptyStatus: empty.status, deleteStatus: del.status });
  if (del.status !== 200) stop(`deleting the bucket answered ${del.status}`);
}

async function modeProbeKey(o, endpoints) {
  const k = await resolveKey(o, endpoints);
  say(`key source: ${k.source}`);
  if (k.source === 'environment') {
    say('the Management API was NOT contacted: SUPABASE_SERVICE_ROLE_KEY is set in this shell; unset it to probe the endpoint');
  } else {
    say(`management api http status: ${k.status}`);
  }
  if (k.names) say(`key names returned: ${k.names.map((n) => `${n.name} (length ${n.length})`).join(', ')}`);
  say(`service-role key length: ${k.key.length}`);
  say(k.refNote);
}

async function modeProbeControl(o, endpoints) {
  const m = /^([^/]+)\/(.+)$/.exec(o.probeControl);
  if (!m) usage('--probe-control needs <bucket>/<name>');
  const [, bucket, name] = m;
  if (bucket !== 'avatars' && bucket !== 'banners') usage('--probe-control: the bucket must be avatars or banners');
  if (!/^[A-Za-z0-9._/-]{1,200}$/.test(name) || name.includes('..')) usage('--probe-control: the object name is not allowed');
  let res;
  try {
    res = await request('GET', publicUrl(endpoints.base, bucket, name), {});
  } catch (e) {
    return stop(`the control request failed: ${netReason(e)}`);
  }
  await res.arrayBuffer().catch(() => {});
  say(`control status ${res.status}`);
  if (res.status !== 200) stop('the public-route control did not answer 200');
}

// ---- main ---------------------------------------------------------------------------------------------------------------
async function main() {
  const o = parseArgs(process.argv.slice(2));
  const endpoints = resolveEndpoints(o);

  const cache = o.cacheControl === undefined ? DEFAULT_CACHE : o.cacheControl;
  if (/public/i.test(cache) || !/^[A-Za-z0-9=, -]{1,100}$/.test(cache)) usage('--cache-control: a form containing "public" (or any odd character) is refused');
  if (o.expires !== undefined && !(o.sign !== undefined && Number.isInteger(Number(o.expires)) && Number(o.expires) >= 1 && Number(o.expires) <= 900)) {
    usage('--expires needs --sign and a whole number of seconds from 1 to 900');
  }

  const modes = [o.sign !== undefined, !!o.probeKey, o.probeControl !== undefined, !!o.verify, o.deleteObject !== undefined, !!o.deleteBucket, !!o.canary].filter(Boolean).length;
  if (modes > 1) usage('choose one mode');
  if (o.repost && !o.canary) usage('--repost goes with --canary');
  const isDelete = o.deleteObject !== undefined || o.deleteBucket;
  if (isDelete && (!o.execute || o.confirmBucket !== BUCKET)) usage(`the delete modes need --execute --confirm-bucket ${BUCKET}`);
  if (o.confirmBucket !== undefined && o.confirmBucket !== BUCKET) usage(`--confirm-bucket must be ${BUCKET}`);

  // modes that need no key and no table
  if (o.probeControl !== undefined) return modeProbeControl(o, endpoints);
  if (o.probeKey) return modeProbeKey(o, endpoints);

  const tablePath = o.table ? path.resolve(o.table) : DEFAULT_TABLE;
  const table = readTable(tablePath);
  if (o.deleteBucket) {
    const reportPath = checkReportPath(o.report);
    const k = await resolveKey(o, endpoints);
    return modeDeleteBucket(o, { base: endpoints.base, key: k.key }, reportPath);
  }
  if (o.deleteObject !== undefined) {
    parseNames(o.deleteObject, '--delete-object');
    const reportPath = checkReportPath(o.report);
    const k = await resolveKey(o, endpoints);
    return modeDeleteObject(o, table, { base: endpoints.base, key: k.key }, reportPath, endpoints);
  }
  if (o.sign !== undefined) {
    const k = await resolveKey(o, endpoints);
    return modeSign(o, table, { base: endpoints.base, key: k.key });
  }
  if (o.verify) {
    const k = await resolveKey(o, endpoints);
    return modeVerify(o, table, { base: endpoints.base, key: k.key });
  }

  const wardroom = o.wardroomDir ? path.resolve(o.wardroomDir) : defaultWardroom();
  if (!fs.existsSync(wardroom)) stop(`the Wardroom folder ${wardroom} does not exist; pass --wardroom-dir`);

  if (o.canary) {
    if (!o.execute) {
      const files = smallestThumbnails(wardroom);
      say(`canary plan (nothing sent): ${files.map((f, i) => `canary-${i + 1}_v0.webp <- ${path.basename(f)}`).join('; ')}`);
      return undefined;
    }
    const reportPath = checkReportPath(o.report);
    const k = await resolveKey(o, endpoints);
    const ctx = { base: endpoints.base, key: k.key, cache };
    return o.repost ? modeRepost(o, wardroom, ctx, reportPath) : modeCanary(o, wardroom, ctx, reportPath);
  }
  if (o.execute) {
    const reportPath = checkReportPath(o.report);
    const k = await resolveKey(o, endpoints);
    return modeExecute(o, table, wardroom, { base: endpoints.base, key: k.key, cache }, reportPath);
  }
  return modeDryRun(o, table, wardroom);
}

main().then(
  () => finish(0),
  (e) => {
    if (e instanceof Stop) {
      warn(`${e.code === 2 ? 'usage: ' : 'STOP: '}${e.message}`);
      return finish(e.code);
    }
    warn(`FAILED: ${e && e.message ? e.message : e}`);
    return finish(1);
  },
);
