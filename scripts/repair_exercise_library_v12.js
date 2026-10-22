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

// Stage 2 — mergeDuplicates (Task 2). Seven rows duplicate a kept twin (same
// movement, same drawing). Each retired row leaves the file; the kept row gains
// name_aliases += [retired name] and merged_ids += [retired id] (the seed prune
// deletes merged_ids from every install). When the twins share movement_pattern
// the kept row also takes the retired row's selection fields, so the slot it
// filled keeps the same movement: union target_focus and primary_muscles
// (case-insensitive, kept spelling first), min priority_tier, OR is_foundational.
// injury_contraindications are NEVER merged (the founder's 13-B carve-out keeps
// 'v-up' and 'hip abduction machine' untagged). The stretches keep E216/E219/
// E220 because warmup_cooldown.dart emits those names.
const MERGES = [
  ['E241', 'E016'],
  ['E240', 'E097'],
  ['E225', 'E107'],
  ['E249', 'E176'],
  ['E165', 'E216'],
  ['E167', 'E219'],
  ['E168', 'E220'],
];

function unionCi(kept, extra) {
  const out = [...(kept || [])];
  const seen = new Set(out.map((s) => String(s).toLowerCase()));
  for (const s of extra || []) {
    if (!seen.has(String(s).toLowerCase())) {
      out.push(s);
      seen.add(String(s).toLowerCase());
    }
  }
  return out;
}

function samePattern(a, b) {
  const x = [...(a.movement_pattern || [])].sort().join('|');
  const y = [...(b.movement_pattern || [])].sort().join('|');
  return x === y;
}

function mergeDuplicates(rows) {
  const byId = new Map(rows.map((r) => [r.id, r]));
  const retired = new Set();
  for (const [retiredId, keptId] of MERGES) {
    const kept = byId.get(keptId);
    if (!kept) throw new Error(`kept row ${keptId} missing`);
    const old = byId.get(retiredId);
    if (!old) continue; // already merged on an earlier run
    if (samePattern(old, kept)) {
      kept.target_focus = unionCi(kept.target_focus, old.target_focus);
      kept.primary_muscles = unionCi(kept.primary_muscles, old.primary_muscles);
      kept.priority_tier = Math.min(kept.priority_tier, old.priority_tier);
      kept.is_foundational = Boolean(kept.is_foundational || old.is_foundational);
    }
    kept.name_aliases = unionCi(kept.name_aliases, [old.name]);
    kept.merged_ids = unionCi(kept.merged_ids, [old.id]);
    retired.add(retiredId);
  }
  return rows.filter((r) => !retired.has(r.id));
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
  const beforeMerge = rows.length;
  rows = mergeDuplicates(rows);
  writeLibrary(rows);
  const after = fs.readFileSync(FILE, 'utf8');
  console.log(
    `repairText: ${shifted} shifted rows; mergeDuplicates: ${beforeMerge - rows.length} retired; ` +
      `file ${before === after ? 'unchanged' : 'rewritten'} (${rows.length} rows)`,
  );
}

main();
