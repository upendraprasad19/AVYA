#!/usr/bin/env node
// Applies the v14 injury re-check to assets/data/exercise_library.json (seed v14).
// Plan: docs/plans/2026-10-23-library-injury-recheck.md.
//
//   node scripts/add_library_injury_tags_v14.js           # apply
//   node scripts/add_library_injury_tags_v14.js --check   # round-trip only
//
// The tokens come from the committed table scripts/data/library_injury_additions_v14.json
// (founder-approved 2026-10-23). They are UNIONED into injury_contraindications:
// sorted, canonical tokens only, and no existing tag is ever removed. The script
// REFUSES an unknown id or a non-canonical token, and it is IDEMPOTENT. No other
// key of any row is touched (test/contracts/exercise_library_frozen_reference_test.dart
// fails if one is).
//
// Before writing, it checks that re-serialising the UNCHANGED rows reproduces the
// shipped bytes; if not, the formatter is wrong and nothing is written.

const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, '..', 'assets', 'data', 'exercise_library.json');
const TABLE = path.join(__dirname, 'data', 'library_injury_additions_v14.json');
// InjuryVocab.canonicalTokens (lib/core/utils/injury_vocab.dart).
const INJURY_TOKENS = new Set([
  'ankle', 'elbow', 'hamstring', 'hip', 'knee', 'lower_back', 'neck', 'shoulder', 'wrist',
]);

// Same layout as add_library_core_fields_v13.js:format — 2-space indent, key order
// kept, no trailing newline, and met_value / cal_per_set_est always with a decimal
// point so Dart's jsonDecode keeps typing them as double.
function format(rows) {
  return JSON.stringify(rows, null, 2).replace(
    /"(met_value|cal_per_set_est)": (-?\d+)(?=[,\n])/g,
    (_, key, value) => `"${key}": ${value}.0`,
  );
}

function main() {
  const before = fs.readFileSync(FILE, 'utf8');
  const rows = JSON.parse(before);
  if (format(rows) !== before) {
    throw new Error('round-trip of the unchanged library does not reproduce its bytes');
  }
  if (process.argv.includes('--check')) {
    console.log(`round-trip OK (${rows.length} rows)`);
    return;
  }
  const additions = JSON.parse(fs.readFileSync(TABLE, 'utf8')).additions;
  const byId = new Map(rows.map((r) => [r.id, r]));
  let changedRows = 0;
  let addedTokens = 0;
  for (const [id, tokens] of Object.entries(additions)) {
    const row = byId.get(id);
    if (!row) throw new Error(`table names an unknown id: ${id}`);
    const bad = tokens.filter((t) => !INJURY_TOKENS.has(t));
    if (bad.length) throw new Error(`${id}: non-canonical injury token(s) ${bad}`);
    const old = row.injury_contraindications || [];
    const next = [...new Set([...old, ...tokens])].sort();
    if (!old.every((t) => next.includes(t))) throw new Error(`${id}: would remove a tag`);
    const gained = next.length - old.length;
    if (gained > 0) {
      changedRows++;
      addedTokens += gained;
    }
    row.injury_contraindications = next;
  }
  fs.writeFileSync(FILE, format(rows));
  const after = fs.readFileSync(FILE, 'utf8');
  console.log(
    `file ${before === after ? 'unchanged' : 'rewritten'} (${rows.length} rows): ` +
      `${changedRows} rows gained ${addedTokens} tokens`,
  );
}

main();
