#!/usr/bin/env node
// Imports the Batch C1 rows into assets/data/exercise_library.json for seed v15.
// Plan: docs/plans/2026-10-25-library-batch-c-new-rows.md (Task 4, R3 and R4).
//
//   node scripts/add_library_batch_c_v15.js                  # write the library
//   node scripts/add_library_batch_c_v15.js --check          # byte equality of a fresh import with the shipped file
//   ... [--library <path>] [--source <path>] [--table <path>]  # test seams; the defaults are the committed files
//
// Inputs: scripts/data/library_batch_c_source.json (every converted row, a held row carries `hold`),
// scripts/data/library_injury_additions_v15.json (the founder-approved tag table and the frozen variant_family).
//
// Rules:
//  - It DROPS every row whose id is ANY source id (held or not), then appends the NON-held source rows in source order,
//    so a row held after a first import leaves the file on the next run and a release adds it. Kept rows are untouched,
//    with ONE exception: E274's target_focus Upper Back -> Mid Back.
//  - A row is built from an ALLOW-LIST: the 40 required keys, then variant_family (from the table), then skill_track,
//    skill_step, progression_to, regression_to where non-null. Everything else in the source (confidence, note, changes,
//    hold, _coreAdded, demo_*, a future meta key) is dropped.
//  - Derived keys (R4): is_active, source "exercise-gif-set", is_indian_context false, standard_swap "", warmup_protocol "",
//    cal_per_set_est = round(met_value * 1.8), equipment_tier = every tier whose items hold every equipment token.
//  - injury_contraindications = sorted(raw source tags UNION the table row); a token is never removed, a non-canonical
//    token is refused. A shipped row with no table row stops the run.
//  - Before writing it proves that re-serialising the UNCHANGED library reproduces its bytes (the v13 formatter,
//    scripts/add_library_core_fields_v13.js:50-72); if not, the formatter is wrong and nothing is written.
//  - It is idempotent: a second run on unchanged inputs is byte-identical.

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const args = process.argv.slice(2);
function flag(name, fallback) {
  const i = args.indexOf(name);
  if (i < 0) return fallback;
  if (i + 1 >= args.length || args[i + 1].startsWith('--')) throw new Error(`${name} needs a value`);
  return path.resolve(args[i + 1]);
}
const CHECK = args.includes('--check');
const LIBRARY = flag('--library', path.join(ROOT, 'assets', 'data', 'exercise_library.json'));
const SOURCE = flag('--source', path.join(__dirname, 'data', 'library_batch_c_source.json'));
const TABLE = flag('--table', path.join(__dirname, 'data', 'library_injury_additions_v15.json'));

// E001's 43 keys minus demo_slug, demo_pair and variant_family: carried by every library row, in this order.
const REQUIRED = [
  'id', 'name', 'category', 'movement_pattern', 'exercise_type', 'primary_muscles', 'secondary_muscles',
  'equipment_needed', 'logging_type', 'difficulty_level', 'suitable_for', 'default_sets', 'default_reps',
  'default_rest_secs', 'tempo', 'met_value', 'cal_per_set_est', 'breathing_cue', 'coaching_cues', 'common_mistakes',
  'warmup_protocol', 'pro_tip', 'is_indian_context', 'indian_alternative', 'source', 'is_active', 'is_foundational',
  'injury_contraindications', 'is_bilateral', 'cns_demand', 'target_focus', 'equipment_tier', 'standard_swap',
  'priority_tier', 'rep_range', 'core_levels', 'discipline', 'gym_availability', 'requires_coaching', 'high_impact',
];
const LADDER = ['skill_track', 'skill_step', 'progression_to', 'regression_to'];
const DERIVED_SOURCE = 'exercise-gif-set';
// InjuryVocab.canonicalTokens (lib/core/utils/injury_vocab.dart).
const INJURY_TOKENS = new Set([
  'ankle', 'elbow', 'hamstring', 'hip', 'knee', 'lower_back', 'neck', 'shoulder', 'wrist',
]);
// EquipmentVocab.tierItems (lib/core/utils/equipment_vocab.dart). Pinned by test/contracts/equipment_tier_consistency_test.dart,
// which asserts derive(equipment_needed) == equipment_tier on every shipped row.
const HOUSEHOLD = ['wall', 'doorway', 'elevated surface', 'foot anchor', 'towel'];
const TIER_ITEMS = {
  bodyweight: ['none', 'bodyweight', ...HOUSEHOLD],
  home_dumbbells: ['none', 'bodyweight', 'dumbbells', 'resistance band', ...HOUSEHOLD],
  basic_gym: [
    'none', 'bodyweight', 'dumbbells', 'barbell', 'bench', 'pull-up bar', 'cables', 'resistance band', 'cardio machine',
    'ab wheel', 'jump rope', 'parallel bars', 'plyo box', 'medicine ball', 'battle ropes', ...HOUSEHOLD,
  ],
  full_gym: [
    'none', 'bodyweight', 'dumbbells', 'barbell', 'bench', 'pull-up bar', 'cables', 'machines', 'smith machine',
    'resistance band', 'kettlebell', 'ez-bar', 'cardio machine', 'ab wheel', 'jump rope', 'parallel bars', 'plyo box',
    'medicine ball', 'battle ropes', 'suspension trainer', ...HOUSEHOLD,
  ],
};
const TIERS = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];

// Same layout as add_library_core_fields_v13.js:format: 2-space indent, key order kept, no trailing newline, and
// met_value / cal_per_set_est always with a decimal point so Dart's jsonDecode keeps typing them as double.
function format(rows) {
  return JSON.stringify(rows, null, 2).replace(
    /"(met_value|cal_per_set_est)": (-?\d+)(?=[,\n])/g,
    (_, key, value) => `"${key}": ${value}.0`,
  );
}

function tiersFor(tokens, id) {
  const tiers = TIERS.filter((t) => tokens.every((x) => TIER_ITEMS[t].includes(x)));
  if (!tiers.length) throw new Error(`${id}: no equipment tier holds ${JSON.stringify(tokens)} (a non-canonical token?)`);
  return tiers;
}

function mustHave(row, key) {
  if (row[key] === undefined || row[key] === null) throw new Error(`${row.id}: source row has no ${key}`);
  return row[key];
}

function buildRow(src, tableRow) {
  const metValue = mustHave(src, 'met_value');
  const rawTags = mustHave(src, 'injury_contraindications');
  const tags = [...new Set([...rawTags, ...tableRow.tokens])].sort();
  const bad = tags.filter((t) => !INJURY_TOKENS.has(t));
  if (bad.length) throw new Error(`${src.id}: non-canonical injury token(s) ${bad}`);
  const equipment = mustHave(src, 'equipment_needed');
  const derived = {
    cal_per_set_est: Math.round(metValue * 1.8),
    warmup_protocol: '',
    is_indian_context: false,
    source: DERIVED_SOURCE,
    is_active: true,
    standard_swap: '',
    equipment_tier: tiersFor(equipment, src.id),
    injury_contraindications: tags,
  };
  const out = {};
  for (const k of REQUIRED) out[k] = k in derived ? derived[k] : mustHave(src, k);
  if (!tableRow.variant_family) throw new Error(`${src.id}: the tag table row has no variant_family`);
  out.variant_family = tableRow.variant_family;
  for (const k of LADDER) if (src[k] !== undefined && src[k] !== null) out[k] = src[k];
  return out;
}

function main() {
  const before = fs.readFileSync(LIBRARY, 'utf8');
  const base = JSON.parse(before);
  if (format(base) !== before) {
    throw new Error('round-trip of the unchanged library does not reproduce its bytes');
  }
  console.log(`round-trip OK (${base.length} rows)`);

  const e001 = base.find((r) => r.id === 'E001');
  const e001Keys = Object.keys(e001).filter((k) => !['demo_slug', 'demo_pair', 'variant_family'].includes(k));
  if (e001Keys.join(',') !== REQUIRED.join(',')) {
    throw new Error('the 40 required keys no longer match E001 minus demo_slug / demo_pair / variant_family');
  }

  const source = JSON.parse(fs.readFileSync(SOURCE, 'utf8'));
  const rows = source.rows;
  const table = JSON.parse(fs.readFileSync(TABLE, 'utf8')).rows;
  const sourceIds = new Set(rows.map((r) => r.id));
  if (sourceIds.size !== rows.length) throw new Error('the source file repeats an id');
  /*HELD-SKIP*/ const shipped = rows.filter((r) => !r.hold);

  const kept = base.filter((r) => !sourceIds.has(r.id)).map((r) => {
    if (r.id !== 'E274') return r;
    // E274 Prone T Raise: target_focus Upper Back -> Mid Back (slot_focus already carries Mid Back).
    return { ...r, target_focus: r.target_focus.map((f) => (f === 'Upper Back' ? 'Mid Back' : f)) };
  });
  if (!kept.some((r) => r.id === 'E274')) throw new Error('E274 is not in the library');

  const added = shipped.map((r) => {
    const tableRow = table[r.id];
    if (!tableRow) throw new Error(`${r.id}: no row in the injury tag table (the injury gate cannot be skipped)`);
    return buildRow(r, tableRow);
  });
  const next = format([...kept, ...added]);

  const heldCount = rows.length - shipped.length;
  const summary = `${kept.length} kept + ${added.length} new = ${kept.length + added.length} rows (${heldCount} held source rows skipped)`;
  if (CHECK) {
    if (next === before) {
      console.log(`check OK: the shipped file is byte-identical to a fresh import (${summary})`);
      return;
    }
    const a = before.split('\n');
    const b = next.split('\n');
    let i = 0;
    while (i < a.length && i < b.length && a[i] === b[i]) i++;
    console.error(`check FAILED: the shipped file differs from a fresh import at line ${i + 1}`);
    console.error(`  shipped: ${a[i]}`);
    console.error(`  fresh:   ${b[i]}`);
    process.exitCode = 1;
    return;
  }
  fs.writeFileSync(LIBRARY, next);
  console.log(`${next === before ? 'file unchanged' : 'file rewritten'}: ${summary}`);
}

main();
