#!/usr/bin/env node
// Adds the core-list selection fields to assets/data/exercise_library.json for
// seed v13. Plan: docs/plans/2026-10-22-library-core-list-pool.md (Batch B1
// Task 2).
//
//   node scripts/add_library_core_fields_v13.js           # apply
//   node scripts/add_library_core_fields_v13.js --check   # round-trip only
//
// The values come from the committed table scripts/data/library_core_fields_v13.json
// (one entry per shipped id). New keys go after the last existing key; a key
// already present is rewritten in place, so the script is IDEMPOTENT. It
// REFUSES a table that misses a shipped id or names an id the library lacks.
// Existing keys are never touched: test/contracts/exercise_library_frozen_reference_test.dart
// fails if any of them changes.
//
// Before writing, it checks that re-serialising the UNCHANGED rows reproduces
// the shipped bytes; if not, the formatter is wrong and nothing is written.

const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, '..', 'assets', 'data', 'exercise_library.json');
const TABLE = path.join(__dirname, 'data', 'library_core_fields_v13.json');

// Same layout as repair_exercise_library_v12.js:writeLibrary — 2-space indent,
// key order kept, no trailing newline, and met_value / cal_per_set_est always
// with a decimal point so Dart's jsonDecode keeps typing them as double.
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
  const table = JSON.parse(fs.readFileSync(TABLE, 'utf8')).rows;
  const ids = new Set(rows.map((r) => r.id));
  const missing = [...ids].filter((id) => !(id in table));
  const extra = Object.keys(table).filter((id) => !ids.has(id));
  if (missing.length || extra.length) {
    throw new Error(`table/library id mismatch: missing ${missing}, extra ${extra}`);
  }
  const out = rows.map((r) => ({ ...r, ...table[r.id] }));
  fs.writeFileSync(FILE, format(out));
  const after = fs.readFileSync(FILE, 'utf8');
  console.log(`file ${before === after ? 'unchanged' : 'rewritten'} (${out.length} rows)`);
}

main();
