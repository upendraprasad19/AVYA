#!/usr/bin/env node
// scripts/build_library_media_v16.js
//
// Batch M1 (plan R1, R3, R5, R13). Builds the provenance table scripts/data/library_media_v16.json:
// which library row shows which Wardroom animation, and the hash and size of every file that
// the upload tool will move into the private `exercise-media` bucket.
//
//   id -> slug   `rows`   (G/N ids from the media map + the shipped library, E ids from --old-rows)
//   slug -> file `files`  (hashes read from the files on disk and checked against the ledger)
//
// Usage:
//   node scripts/build_library_media_v16.js --write | --check  [--prune-only]
//        [--table P] [--map P] [--ledger P] [--wardroom-dir P] [--library P] [--old-rows P] [--out P]
//
//   --write        build and write --out (default: --table in place)
//   --check        build and compare, byte for byte, with --table (exit 1 when they differ)
//   --prune-only   no Wardroom folder needed: drop `rows` entries whose row left the library and
//                  flip files nothing maps to `unmapped` (the hold recipe of R13)
//
// The Wardroom folder is the founder's, untracked, and lives only in the primary checkout, so the
// default for --wardroom-dir is found with primaryRoot() from .claude/token_path.js.
// Exit: 0 ok, 1 refused (message on stderr starts "FAIL:"), 2 usage.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const REPO = path.resolve(__dirname, '..');
const ORIGIN =
  'AI recreation of the GIF set in `assets/exercise animations/forgetrainer_animations/gifs`; ' +
  'licensing risk accepted by the founder (D9, 2026-10-21)';
const BUCKET = 'exercise-media';
const WEBP_BYTES_MAX = 1500000;
const WARDROOM_REL = ['assets', 'exercise animations', 'forgetrainer_animations', 'gifs', 'wardroom customized gifs'];
const GIF_RE = /^\d{4}$/;
const OLD_ID_RE = /^E\d+$/;

class Fail extends Error {}
const fail = (m) => {
  throw new Fail(m);
};

function usage(msg) {
  process.stderr.write(
    `${msg}\nusage: node scripts/build_library_media_v16.js (--write | --check) [--prune-only] ` +
      '[--table P] [--map P] [--ledger P] [--wardroom-dir P] [--library P] [--old-rows P] [--out P]\n'
  );
  process.exit(2);
}

function parseArgs(argv) {
  const valueFlags = new Set(['--table', '--map', '--ledger', '--wardroom-dir', '--library', '--old-rows', '--out']);
  const boolFlags = new Set(['--write', '--check', '--prune-only']);
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (valueFlags.has(a)) {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) usage(`${a} needs a value`);
      o[a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = v;
    } else if (boolFlags.has(a)) {
      o[a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = true;
    } else usage(`unknown flag ${a}`);
  }
  if (!!o.write === !!o.check) usage('exactly one of --write and --check is required');
  o.table = path.resolve(o.table || path.join(__dirname, 'data', 'library_media_v16.json'));
  o.map = path.resolve(o.map || path.join(__dirname, 'data', 'library_batch_c_media_map.json'));
  o.library = path.resolve(o.library || path.join(REPO, 'assets', 'data', 'exercise_library.json'));
  if (o.ledger) o.ledger = path.resolve(o.ledger);
  if (o.wardroomDir) o.wardroomDir = path.resolve(o.wardroomDir);
  if (o.oldRows) o.oldRows = path.resolve(o.oldRows);
  if (o.out) o.out = path.resolve(o.out);
  return o;
}

// kebab(s): lower-case, each run of characters outside [a-z0-9] becomes one '-', trim '-'.
// Permanent: object names are immutable, so this function never changes.
const kebab = (s) =>
  String(s)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

function readJson(p, what) {
  let text;
  try {
    text = fs.readFileSync(p, 'utf8');
  } catch (e) {
    fail(`cannot read ${what} ${p}: ${e.message}`);
  }
  try {
    return JSON.parse(text);
  } catch (e) {
    return fail(`${what} ${p} is not JSON: ${e.message}`);
  }
}

function canon(v) {
  if (Array.isArray(v)) return v.map(canon);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v).sort()) o[k] = canon(v[k]);
    return o;
  }
  return v;
}
const render = (t) => `${JSON.stringify(canon(t), null, 2)}\n`;

function emptyTable() {
  return {
    _meta: {
      origin: ORIGIN,
      ledger_completed_at: null,
      bucket: BUCKET,
      webp_bytes_max: WEBP_BYTES_MAX,
      old_rows: null,
      taken_down: [],
    },
    files: {},
    rows: {},
  };
}

function readTable(p, mustExist) {
  if (!fs.existsSync(p)) {
    if (mustExist) fail(`table ${p} does not exist`);
    return emptyTable();
  }
  const t = readJson(p, 'table');
  if (!t || !t._meta || !t.files || !t.rows) fail(`table ${p} lacks _meta, files or rows`);
  return t;
}

function readLibraryIds(p) {
  const lib = readJson(p, 'library');
  if (!Array.isArray(lib)) fail(`library ${p} is not a JSON array`);
  const ids = new Set();
  const order = [];
  for (const r of lib) {
    if (r && typeof r.id === 'string' && !ids.has(r.id)) {
      ids.add(r.id);
      order.push(r.id);
    }
  }
  return { ids, order };
}

function defaultWardroom() {
  const { primaryRoot } = require(path.join(REPO, '.claude', 'token_path.js'));
  const { root, error } = primaryRoot(REPO);
  if (!root) fail(`cannot locate the primary checkout (${error}); pass --wardroom-dir`);
  return path.join(root, ...WARDROOM_REL);
}

function relOk(rel, dir, ext) {
  return typeof rel === 'string' && rel.startsWith(`${dir}/`) && rel.endsWith(ext) && !rel.includes('..') && !rel.includes('\\');
}

function summarize(t) {
  const counts = { active: 0, unmapped: 0, taken_down: 0 };
  for (const f of Object.values(t.files)) counts[f.status] = (counts[f.status] || 0) + 1;
  return `rows ${Object.keys(t.rows).length}, files ${Object.keys(t.files).length} ` +
    `(active ${counts.active}, unmapped ${counts.unmapped}, taken_down ${counts.taken_down})`;
}

function setStatuses(files, rows, takenDown) {
  const used = new Set(Object.values(rows));
  for (const [slug, rec] of Object.entries(files)) {
    rec.status = takenDown.has(slug) ? 'taken_down' : used.has(slug) ? 'active' : 'unmapped';
  }
}

function oldRowCount(rows) {
  return Object.keys(rows).filter((id) => OLD_ID_RE.test(id)).length;
}

// ---- --prune-only: no Wardroom folder, no ledger ------------------------------------------------
function buildPrune(a) {
  const t = readTable(a.table, true);
  const { ids } = readLibraryIds(a.library);
  const takenDown = new Set(t._meta.taken_down || []);
  const rows = {};
  for (const [id, slug] of Object.entries(t.rows)) if (ids.has(id) && !takenDown.has(slug)) rows[id] = slug;
  const files = {};
  for (const [slug, rec] of Object.entries(t.files)) files[slug] = { ...rec };
  setStatuses(files, rows, takenDown);
  const meta = { ...t._meta };
  if (meta.old_rows) meta.old_rows = { ...meta.old_rows, entries: oldRowCount(rows) };
  return { _meta: meta, files, rows };
}

// ---- full build ---------------------------------------------------------------------------------
function buildFull(a) {
  const existing = readTable(a.table, false);
  const { ids: libIds, order: libOrder } = readLibraryIds(a.library);
  const map = readJson(a.map, 'media map');
  const ward = a.wardroomDir || defaultWardroom();
  if (!fs.existsSync(ward) || !fs.statSync(ward).isDirectory()) fail(`Wardroom folder ${ward} does not exist; pass --wardroom-dir`);
  const ledgerPath = a.ledger || path.join(ward, 'generation-ledger.json');
  const ledger = readJson(ledgerPath, 'ledger');
  if (!Array.isArray(ledger.entries)) fail(`ledger ${ledgerPath} has no entries array`);
  if (typeof ledger.completedAt !== 'string') fail(`ledger ${ledgerPath} has no completedAt`);

  const byNum = new Map();
  for (const e of ledger.entries) {
    const m = /^(\d{4})_/.exec(e.id || '');
    if (!m) continue; // non-numeric ids (table-row-clean) are never mappable
    if (byNum.has(m[1])) fail(`ledger has two entries for gif ${m[1]}`);
    byNum.set(m[1], e);
  }

  // Any map entry naming something other than a 4-digit gif number is refused, mapped or not.
  for (const [id, v] of Object.entries(map)) {
    const g = v && v._gif;
    if (g !== undefined && g !== '' && !GIF_RE.test(String(g))) {
      fail(`media map entry ${id}: "${g}" is not a 4-digit gif number`);
    }
  }

  const takenDown = new Set(existing._meta.taken_down || []);
  for (const s of takenDown) if (!existing.files[s]) fail(`_meta.taken_down names ${s}, which has no files entry`);

  const gifSlug = new Map(); // gif -> slug
  const built = {}; // slug -> freshly verified record

  const slugFor = (gif, ctx) => {
    if (gifSlug.has(gif)) return gifSlug.get(gif);
    const entry = byNum.get(gif);
    if (!entry) fail(`${ctx}: gif ${gif} has no entry in the ledger`);
    const fromName = kebab(entry.name);
    const fromId = kebab(String(entry.id).slice(5));
    if (!fromName || !fromId) fail(`${ctx}: ledger entry ${entry.id} kebabs to an empty name`);
    if (fromName !== fromId) {
      fail(`${ctx}: ledger entry ${entry.id}: the name-derived slug "${fromName}" and the id-derived slug "${fromId}" differ`);
    }
    const slug = `${gif}-${fromName}`;
    gifSlug.set(gif, slug);
    return slug;
  };

  // Verifies the files of one slug against the ledger and the table, once.
  const verify = (gif, slug) => {
    if (built[slug] || takenDown.has(slug)) return;
    const entry = byNum.get(gif);
    const out = entry.outputs || {};
    if (!relOk(out.animation, 'webp-720', '.webp')) fail(`${slug}: ledger animation path ${JSON.stringify(out.animation)} must start with webp-720/ and end .webp`);
    if (!relOk(out.thumbnail, 'thumbnails-192', '.webp')) fail(`${slug}: ledger thumbnail path ${JSON.stringify(out.thumbnail)} must start with thumbnails-192/ and end .webp`);
    const animPath = path.join(ward, ...out.animation.split('/'));
    const thumbPath = path.join(ward, ...out.thumbnail.split('/'));
    if (!fs.existsSync(animPath)) fail(`${slug}: animation file missing on disk: ${animPath}`);
    if (!fs.existsSync(thumbPath)) fail(`${slug}: thumbnail file missing on disk: ${thumbPath}`);
    const anim = fs.readFileSync(animPath);
    const thumb = fs.readFileSync(thumbPath);
    const av = entry.animationValidation || {};
    const tv = entry.thumbnailValidation || {};
    const animSha = sha256(anim);
    const thumbSha = sha256(thumb);
    if (animSha !== av.SHA256) fail(`${slug}: the animation on disk (sha256 ${animSha}) differs from the ledger's validation sha`);
    if (thumbSha !== tv.SHA256) fail(`${slug}: the thumbnail on disk (sha256 ${thumbSha}) differs from the ledger's validation sha`);
    if (av.bytes !== anim.length) fail(`${slug}: the animation is ${anim.length} bytes, the ledger says ${av.bytes}`);
    if (!Number.isInteger(av.frames)) fail(`${slug}: the ledger has no integer frame count`);
    if (anim.length > WEBP_BYTES_MAX) fail(`${slug}: ${anim.length} bytes is over webp_bytes_max ${WEBP_BYTES_MAX}`);
    const prior = existing.files[slug];
    if (prior && (prior.webp_sha256 !== animSha || prior.thumb_sha256 !== thumbSha)) {
      fail(`${slug}: the file on disk differs from the sha256 recorded in the table (objects are immutable; a changed file needs a new slug or a new version, which is M1c)`);
    }
    built[slug] = {
      frames: av.frames,
      gif,
      ledger_id: entry.id,
      source_gif_sha256: entry.sourceSHA256,
      thumb_bytes: thumb.length,
      thumb_sha256: thumbSha,
      versions: [{ file: out.animation, media_version: 1, webp_bytes: anim.length, webp_sha256: animSha }],
      webp_bytes: anim.length,
      webp_sha256: animSha,
    };
  };

  // G / N rows: the map, the ledger, the disk and the shipped library. A held row is not in the library.
  const rows = {};
  for (const id of libOrder) {
    const v = map[id];
    const gif = v && v._gif !== undefined && v._gif !== '' ? String(v._gif) : null;
    if (!gif) continue;
    const slug = slugFor(gif, `${id}`);
    if (takenDown.has(slug)) continue; // a taken-down slug is never mapped
    verify(gif, slug);
    rows[id] = slug;
  }

  // E rows: from the founder's export, else carried verbatim from the existing table.
  let oldMeta = existing._meta.old_rows || null;
  if (a.oldRows) {
    const raw = fs.readFileSync(a.oldRows);
    const exp = readJson(a.oldRows, 'old-rows export');
    if (!exp || !Array.isArray(exp.entries)) fail(`old-rows export ${a.oldRows} has no entries array`);
    let written = 0;
    let omitted = 0;
    for (const en of exp.entries) {
      const id = en && en.id;
      if (typeof id !== 'string' || !OLD_ID_RE.test(id)) fail(`old-rows entry ${JSON.stringify(id)}: the id must look like E050`);
      if (!libIds.has(id)) fail(`old-rows entry ${id}: the library holds no such row`);
      if (en.equipment_checked !== true) fail(`old-rows entry ${id}: equipment_checked must be true (a name says nothing about equipment)`);
      if (!GIF_RE.test(String(en.gif))) fail(`old-rows entry ${id}: "${en.gif}" is not a 4-digit gif number`);
      const slug = slugFor(String(en.gif), `old-rows entry ${id}`);
      if (takenDown.has(slug)) {
        omitted++;
        continue;
      }
      verify(String(en.gif), slug);
      rows[id] = slug;
      written++;
    }
    oldMeta = { entries: written, omitted, sha256: sha256(raw) };
  } else {
    let dropped = 0;
    for (const [id, slug] of Object.entries(existing.rows)) {
      if (!OLD_ID_RE.test(id)) continue;
      if (takenDown.has(slug)) {
        dropped++;
        continue;
      }
      rows[id] = slug;
    }
    if (oldMeta) oldMeta = { ...oldMeta, entries: oldRowCount(rows), omitted: (oldMeta.omitted || 0) + dropped };
  }

  // Files: never drop an existing entry (provenance); fresh verified records replace carried ones.
  const files = {};
  for (const [slug, rec] of Object.entries(existing.files)) files[slug] = { ...rec };
  for (const [slug, rec] of Object.entries(built)) files[slug] = rec;
  setStatuses(files, rows, takenDown);

  return {
    _meta: {
      bucket: BUCKET,
      ledger_completed_at: ledger.completedAt,
      old_rows: oldMeta,
      origin: ORIGIN,
      taken_down: [...takenDown].sort(),
      webp_bytes_max: WEBP_BYTES_MAX,
    },
    files,
    rows,
  };
}

function main() {
  const a = parseArgs(process.argv.slice(2));
  const table = a.pruneOnly ? buildPrune(a) : buildFull(a);
  const text = render(table);
  if (a.check) {
    const have = fs.existsSync(a.table) ? fs.readFileSync(a.table, 'utf8') : null;
    if (have !== text) fail(`${a.table} is not byte-identical to a fresh build (${summarize(table)}); run with --write`);
    process.stdout.write(`check OK: ${summarize(table)}\n`);
    return;
  }
  const out = a.out || a.table;
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, text);
  process.stdout.write(`wrote ${out}: ${summarize(table)}\n`);
}

try {
  main();
} catch (e) {
  if (e instanceof Fail) {
    process.stderr.write(`FAIL: ${e.message}\n`);
    process.exit(1);
  }
  throw e;
}
