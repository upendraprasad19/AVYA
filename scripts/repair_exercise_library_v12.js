#!/usr/bin/env node
// One-shot repair of assets/data/exercise_library.json for seed v12.
// Plan: docs/plans/2026-10-22-library-data-repair.md (Batch A).
//
//   node scripts/repair_exercise_library_v12.js
//
// IDEMPOTENT: every stage keys off the defect it repairs, so running it on its
// own output changes nothing (a no-op run leaves the file byte-identical).
//
// Stage 1 — repairText (Task 1, OI-149). On 136 rows a spreadsheet column shift
// moved every field from met_value to source one place to the right, in file
// key order:
//   met_value > cal_per_set_est > breathing_cue > coaching_cues >
//   common_mistakes > warmup_protocol > pro_tip > is_indian_context >
//   indian_alternative > source > is_active
// The shifted rows are exactly the ones whose breathing_cue is a bare number
// (and whose met_value is null). Two values fell into boolean columns and are
// lost: the original pro_tip (now is_indian_context=false) and the original
// source (now is_active=true). Everything else is moved back verbatim. Then
// EVERY row's coaching_cues / common_mistakes become one cue per list item,
// because healthy rows stored them as a single "; "-joined string.

const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, '..', 'assets', 'data', 'exercise_library.json');
const NUMERIC = /^\d+(\.\d+)?$/;

function split(value) {
  const items = Array.isArray(value) ? value : [value];
  return items
    .flatMap((v) => String(v).split(';'))
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

function isShifted(row) {
  return typeof row.breathing_cue === 'string' && NUMERIC.test(row.breathing_cue.trim());
}

function repairText(rows) {
  return rows.map((original) => {
    const row = { ...original };
    if (isShifted(original)) {
      const o = original;
      row.met_value = o.cal_per_set_est;
      row.cal_per_set_est = Number(o.breathing_cue);
      row.breathing_cue = o.coaching_cues.join(', ');
      // Only E064 holds more than one element here: its cue text had commas, so
      // the shift split it; re-join before splitting on the real separator.
      row.coaching_cues = split(
        o.common_mistakes.length > 1 ? [o.common_mistakes.join(', ')] : o.common_mistakes,
      );
      row.common_mistakes = split(o.warmup_protocol);
      row.warmup_protocol = o.pro_tip;
      row.pro_tip = '';
      row.is_indian_context = o.indian_alternative === 'Yes';
      row.indian_alternative = o.source;
      row.source = '';
    }
    row.coaching_cues = split(row.coaching_cues);
    row.common_mistakes = split(row.common_mistakes);
    return row;
  });
}

// Writes the file in its existing layout: 2-space indent, key order kept, no
// trailing newline, and met_value / cal_per_set_est always with a decimal point
// so Dart's jsonDecode keeps typing them as double.
function writeLibrary(rows) {
  const text = JSON.stringify(rows, null, 2).replace(
    /"(met_value|cal_per_set_est)": (-?\d+)(?=[,\n])/g,
    (_, key, value) => `"${key}": ${value}.0`,
  );
  fs.writeFileSync(FILE, text);
}

function main() {
  const before = fs.readFileSync(FILE, 'utf8');
  let rows = JSON.parse(before);
  const shifted = rows.filter(isShifted).length;
  rows = repairText(rows);
  writeLibrary(rows);
  const after = fs.readFileSync(FILE, 'utf8');
  console.log(
    `repairText: ${shifted} shifted rows; file ${before === after ? 'unchanged' : 'rewritten'} (${rows.length} rows)`,
  );
}

main();
