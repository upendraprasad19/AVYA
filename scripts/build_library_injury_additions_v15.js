#!/usr/bin/env node
// Batch C1 (docs/plans/2026-10-25-library-batch-c-new-rows.md, R5 and Task 2.1): builds the injury additions
// table scripts/data/library_injury_additions_v15.json for the NON-held rows of the source file.
//
// A new row's final tags are sorted(raw source tags UNION its table row). The table row is built from five
// classes, each recorded with a reason:
//   floor     intersection of the tags of the same-variant_family ORIGINAL library rows (E-ids, never new rows)
//   majority  tokens on more than half (not all) of those originals - included by default, the founder may drop
//   family    push-up names -> shoulder; elbow_flexion / elbow_extension rows -> elbow; Russian twist / V-up /
//             crunch / sit-up names -> lower_back; hip abduction / adduction names -> hip
//   twin      the tags of a library row that shares the new row's picture (a two-entry constant: the library
//             rows' picture ids exist only in the scratch merged.json)
//   judgement the founder table: a row with no tag from any class above stays PENDING until it is decided
//
// ADD-ONLY and merge-preserving: a re-run appends rows for ids that lack one and never changes the tokens,
// class, reason or variant_family of an existing row, nor safe_pool_additions. A table row whose id is held or
// gone is REPORTED, not removed; `--drop <id>` removes the row of ANY id (a changed family or pattern means
// --drop, a re-run and a fresh founder decision) and never appends in the same run.
//
//   node scripts/build_library_injury_additions_v15.js [--table <path>] [--out <path>] [--drop <id>]
//
// --table  the input table (default: the committed one).  --out  where to write (default: the --table path).
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'scripts', 'data', 'library_batch_c_source.json');
const LIB = path.join(ROOT, 'assets', 'data', 'exercise_library.json');
const DEFAULT_TABLE = path.join(ROOT, 'scripts', 'data', 'library_injury_additions_v15.json');

const CLASSES = ['floor', 'majority', 'family', 'twin', 'judgement'];
const PENDING = 'PENDING founder review';
// Library row whose picture a new row shares: its tags are the new row's twin tags.
const TWIN = { G0814: { from: 'E075' }, G1428: { from: 'E210' } };

const sortedUnique = (a) => [...new Set(a || [])].sort();
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));

function familyTokens(row) {
  const out = [];
  if (/push[- ]?up/i.test(row.name)) out.push(['shoulder', 'push-up name']);
  if ((row.movement_pattern || []).some((p) => p === 'elbow_flexion' || p === 'elbow_extension')) out.push(['elbow', 'elbow_flexion / elbow_extension pattern']);
  if (/russian twist|v[- ]?up|crunch|sit[- ]?up/i.test(row.name)) out.push(['lower_back', 'twist / V-up / crunch / sit-up name']);
  if (/\bhip (abduction|adduction)\b/i.test(row.name)) out.push(['hip', 'hip abduction / adduction name']);
  return out;
}

function buildRow(row, lib) {
  const sibs = lib.filter((l) => l.variant_family && l.variant_family === row.variant_family);
  const cnt = {};
  for (const l of sibs) for (const t of sortedUnique(l.injury_contraindications)) cnt[t] = (cnt[t] || 0) + 1;
  const floor = sibs.length ? Object.keys(cnt).filter((t) => cnt[t] === sibs.length) : [];
  const majority = sibs.length ? Object.keys(cnt).filter((t) => cnt[t] > sibs.length / 2 && cnt[t] < sibs.length) : [];
  const fam = familyTokens(row);
  let twin = [];
  let twinReason = '';
  if (TWIN[row.id]) {
    const from = lib.find((l) => l.id === TWIN[row.id].from);
    twin = sortedUnique(from.injury_contraindications);
    twinReason = `twin of ${from.id} ${from.name}`;
  }
  const tokens = sortedUnique([...floor, ...majority, ...fam.map((f) => f[0]), ...twin]);
  const raw = sortedUnique(row.injury_contraindications);
  const parts = [];
  if (floor.length) parts.push(`floor ${floor.join('+')} (all ${sibs.length} same-family originals)`);
  if (majority.length) parts.push(`majority ${majority.join('+')} (more than half of ${sibs.length} same-family originals)`);
  for (const [t, why] of fam) parts.push(`family ${t} (${why})`);
  if (twin.length) parts.push(`twin ${twin.join('+')} (${twinReason})`);
  let cls;
  if (twin.length) cls = 'twin';
  else if (fam.length) cls = 'family';
  else if (floor.length) cls = 'floor';
  else if (majority.length) cls = 'majority';
  else cls = 'judgement';
  let reason = parts.join('; ');
  if (!sortedUnique([...raw, ...tokens]).length) reason = PENDING;
  else if (!parts.length) reason = `no same-family original or name rule; the source tags (${raw.join('+')}) stand`;
  return { tokens, class: cls, reason, variant_family: row.variant_family };
}

function parseArgs(argv) {
  const a = { table: DEFAULT_TABLE, out: null, drop: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--table') a.table = path.resolve(argv[++i]);
    else if (argv[i] === '--out') a.out = path.resolve(argv[++i]);
    else if (argv[i] === '--drop') a.drop = argv[++i];
    else throw new Error('unknown argument ' + argv[i]);
  }
  if (!a.out) a.out = a.table;
  return a;
}

function write(file, table) {
  const rows = {};
  for (const id of Object.keys(table.rows).sort()) rows[id] = table.rows[id];
  fs.writeFileSync(file, JSON.stringify({ ...table, rows }, null, 2) + '\n');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const src = readJson(SRC);
  const lib = readJson(LIB);
  const table = fs.existsSync(args.table)
    ? readJson(args.table)
    : {
      _meta: {
        version: 15,
        about: 'Injury tokens ADDED to the raw tags of each new row (final tags = sorted(raw union row tokens)). Built by scripts/build_library_injury_additions_v15.js; decided by the founder.',
        classes: CLASSES,
      },
      safe_pool_additions: [],
      rows: {},
    };
  if (!table.rows || !Array.isArray(table.safe_pool_additions)) throw new Error('table shape: needs rows and safe_pool_additions');

  if (args.drop) {
    if (!table.rows[args.drop]) { console.log('drop: no table row for ' + args.drop); process.exitCode = 1; return; }
    delete table.rows[args.drop];
    write(args.out, table);
    console.log('drop: removed ' + args.drop + '; rows now ' + Object.keys(table.rows).length);
    return;
  }

  const rows = src.rows;
  const shipped = rows.filter((r) => !r.hold);
  const heldIds = new Set(rows.filter((r) => r.hold).map((r) => r.id));
  const allIds = new Set(rows.map((r) => r.id));
  let added = 0;
  for (const r of shipped) {
    if (table.rows[r.id]) continue;
    table.rows[r.id] = buildRow(r, lib);
    added++;
  }
  const held = Object.keys(table.rows).filter((id) => heldIds.has(id));
  const gone = Object.keys(table.rows).filter((id) => !allIds.has(id));
  write(args.out, table);
  const byClass = {};
  let pending = 0;
  for (const row of Object.values(table.rows)) {
    byClass[row.class] = (byClass[row.class] || 0) + 1;
    if (row.reason === PENDING) pending++;
  }
  console.log('build: appended ' + added + ' row(s); table rows ' + Object.keys(table.rows).length + ' ' + JSON.stringify(byClass) + '; PENDING ' + pending);
  if (held.length) console.log('build: table rows for HELD ids (not removed, red in the coverage test): ' + held.join(' '));
  if (gone.length) console.log('build: table rows for ids gone from the source (not removed, red in the coverage test): ' + gone.join(' '));
}

main();
