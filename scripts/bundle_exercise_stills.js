#!/usr/bin/env node
// scripts/bundle_exercise_stills.js
//
// Batch M2a (plan Task 2). Copies the 192 x 192 still of every animation named by scripts/data/library_media_v16.json into the
// app bundle as assets/exercise_stills/<media_slug>.webp, checking every file's sha256 against the table BEFORE it is copied.
//
//   node scripts/bundle_exercise_stills.js --src "<.../wardroom customized gifs>"   # copy (needs the founder's folder)
//   node scripts/bundle_exercise_stills.js --check                                  # verify --dir against --table; needs no --src
//   flags: --src --dir --table --check
//
// The still's source path is the ledger's `outputs.thumbnail` of the entry whose id equals files[slug].ledger_id (the same field
// scripts/build_library_media_v16.js reads); the file name is NOT derived by string replacement. The founder's folder lives only in
// the PRIMARY checkout, never at a relative path from a worktree, so --src is required and is never guessed.
// Exit: 0 ok, 1 refused or failed (the message names the slug), 2 usage.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const REPO = path.resolve(__dirname, '..');
const DEFAULT_TABLE = path.join(__dirname, 'data', 'library_media_v16.json');
const DEFAULT_DIR = path.join(REPO, 'assets', 'exercise_stills');
const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

class Stop extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}

const usage = () => new Stop('usage: bundle_exercise_stills.js [--check] [--src <wardroom folder>] [--dir <stills dir>] [--table <path>]\n' +
  '  copy mode needs --src (the founder\'s ".../wardroom customized gifs" folder); --check needs none', 2);

function parseArgs(argv) {
  const o = { check: false, src: null, dir: DEFAULT_DIR, table: DEFAULT_TABLE };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--check') o.check = true;
    else if (a === '--src' || a === '--dir' || a === '--table') {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) throw new Stop(`${a} needs a value`, 2);
      o[a.slice(2)] = path.resolve(v);
    } else throw new Stop(`unknown flag ${JSON.stringify(a)}`, 2);
  }
  if (!o.check && !o.src) throw new Stop('copy mode needs --src <the founder\'s wardroom folder>; use --check to verify the bundle without it', 2);
  return o;
}

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

function readJson(file, what) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (e) {
    throw new Stop(`cannot read ${what} ${file}: ${e.message}`);
  }
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Stop(`${what} ${file} is not JSON: ${e.message}`);
  }
}

function readTable(file) {
  const t = readJson(file, 'table');
  if (!t || typeof t.files !== 'object' || t.files === null) throw new Stop(`table ${file} has no files object`);
  const slugs = Object.keys(t.files);
  for (const s of slugs) {
    const rec = t.files[s];
    if (!SLUG_RE.test(s)) throw new Stop(`${s}: not a valid media slug`);
    if (!Number.isInteger(rec.thumb_bytes) || rec.thumb_bytes <= 0) throw new Stop(`${s}: table has no thumb_bytes`);
    if (!/^[0-9a-f]{64}$/.test(rec.thumb_sha256 || '')) throw new Stop(`${s}: table has no thumb_sha256`);
  }
  return { slugs: slugs.sort(), files: t.files };
}

// Verifies the folder against the table. Returns the list of problems (empty = ok); every problem names its slug or file.
function checkDir(dir, table) {
  const problems = [];
  if (!fs.existsSync(dir)) return [`stills folder ${dir} does not exist`];
  for (const slug of table.slugs) {
    const rec = table.files[slug];
    const file = path.join(dir, `${slug}.webp`);
    if (!fs.existsSync(file)) {
      problems.push(`${slug}: still missing (${slug}.webp)`);
      continue;
    }
    const buf = fs.readFileSync(file);
    if (buf.length !== rec.thumb_bytes) problems.push(`${slug}: ${buf.length} bytes, table says ${rec.thumb_bytes}`);
    else if (sha256(buf) !== rec.thumb_sha256) problems.push(`${slug}: sha256 differs from thumb_sha256`);
  }
  const expected = new Set(table.slugs.map((s) => `${s}.webp`));
  for (const name of fs.readdirSync(dir)) {
    if (!expected.has(name)) problems.push(`${name}: not named by the table (a stray file would ship in the bundle)`);
  }
  return problems;
}

function thumbnailPath(entry, slug) {
  const rel = entry && entry.outputs && entry.outputs.thumbnail;
  if (typeof rel !== 'string' || !/^thumbnails-192\/[^/\\]+\.webp$/.test(rel) || rel.includes('..')) {
    throw new Stop(`${slug}: ledger thumbnail path ${JSON.stringify(rel)} must be thumbnails-192/<file>.webp`);
  }
  return rel.split('/');
}

function copyAll(o, table) {
  const ledgerFile = path.join(o.src, 'generation-ledger.json');
  const ledger = readJson(ledgerFile, 'ledger');
  if (!Array.isArray(ledger.entries)) throw new Stop(`ledger ${ledgerFile} has no entries array`);
  const byId = new Map();
  for (const e of ledger.entries) if (e && typeof e.id === 'string') byId.set(e.id, e);

  // Verify everything BEFORE writing anything, so a bad source leaves the bundle untouched.
  const plan = [];
  for (const slug of table.slugs) {
    const rec = table.files[slug];
    const entry = byId.get(rec.ledger_id);
    if (!entry) throw new Stop(`${slug}: ledger has no entry with id ${JSON.stringify(rec.ledger_id)}`);
    const from = path.join(o.src, ...thumbnailPath(entry, slug));
    if (!fs.existsSync(from)) throw new Stop(`${slug}: thumbnail missing on disk: ${from}`);
    const buf = fs.readFileSync(from);
    if (buf.length !== rec.thumb_bytes) throw new Stop(`${slug}: source is ${buf.length} bytes, table says ${rec.thumb_bytes}`);
    if (sha256(buf) !== rec.thumb_sha256) throw new Stop(`${slug}: source sha256 differs from thumb_sha256`);
    plan.push({ slug, buf });
  }
  fs.mkdirSync(o.dir, { recursive: true });
  for (const { slug, buf } of plan) fs.writeFileSync(path.join(o.dir, `${slug}.webp`), buf);
  return plan.length;
}

function main() {
  const o = parseArgs(process.argv.slice(2));
  const table = readTable(o.table);
  if (!o.check) {
    const n = copyAll(o, table);
    console.log(`copied ${n} stills into ${o.dir}`);
  }
  const problems = checkDir(o.dir, table);
  if (problems.length) {
    throw new Stop(`${problems.length} problem(s):\n  ${problems.slice(0, 20).join('\n  ')}${problems.length > 20 ? `\n  ... and ${problems.length - 20} more` : ''}`);
  }
  const total = table.slugs.reduce((n, s) => n + table.files[s].thumb_bytes, 0);
  console.log(`ok: ${table.slugs.length} stills, ${total} bytes, every sha256 matches the table`);
}

try {
  main();
} catch (e) {
  if (e instanceof Stop) {
    console.error(e.message);
    if (e.code === 2) console.error(usage().message);
    process.exit(e.code);
  }
  throw e;
}
