#!/usr/bin/env node
// Imports the Batch C1 rows into assets/data/exercise_library.json for seed v15.
// Plan: docs/plans/2026-10-25-library-batch-c-new-rows.md (Task 4, R3 and R4).
//
//   node scripts/add_library_batch_c_v15.js                  # write the library
//   node scripts/add_library_batch_c_v15.js --check          # byte equality of a fresh import with the shipped file
//   ... [--library <path>] [--source <path>] [--table <path>]  # test seams; the defaults are the committed files
//   ... [--media <path>|none]    # the media provenance table (Batch M1, R4); default scripts/data/library_media_v16.json
//   ... [--removals <path>|none] # the Batch C2a removals file; default scripts/data/library_batch_c2_removals.json (absent = no-op)
//
// Inputs: scripts/data/library_batch_c_source.json (every converted row, a held row carries `hold`),
// scripts/data/library_injury_additions_v15.json (the founder-approved tag table and the frozen variant_family).
//
// Rules:
//  - It DROPS every row whose id is ANY source id (held or not), then appends the NON-held source rows in source order,
//    so a row held after a first import leaves the file on the next run and a release adds it. Kept rows are untouched,
//    with TWO exceptions: E274's target_focus Upper Back -> Mid Back, and E230's nine retag keys (Batch C2c, below).
//  - RETAG STAGE (Batch C2c, OI-474): scripts/data/library_e230_retag.json holds E230's `before` and `after` for nine keys.
//    A row whose nine values all equal `before` takes `{...row, ...after}` (key positions kept); all equal `after` is a
//    no-op; anything else stops the run naming the key. A later hand edit of those nine E230 keys therefore throws until
//    the record's `after` is updated. An absent record is a printed no-op (tests copy this script into temp dirs, as for
//    --removals); a record whose id is not a kept row stops the run.
//  - CORE-LEVELS STAGE (Library Batch S1a, plan docs/plans/2026-11-08-library-batch-s1-core-data.md):
//    scripts/data/library_s1_core_levels.json holds `before` and `after` of `core_levels` for KEPT rows only (G and N rows
//    change in the source). It runs as its own pass over the kept rows AFTER the retag and E274 steps and before the media
//    stage: a row at `before` takes `after`, a row at `after` is a no-op, anything else stops the run naming the id; an id
//    that is not a kept row, or a duplicate id, stops the run. An absent record is a printed no-op (tests copy this script
//    into temp dirs).
//  - MERGE STAGE (Library Batch S1b-3, OI-147): scripts/data/library_s1b3_merges.json, rows retired INTO a kept row (drop,
//    then merged_ids + name_aliases on `into`), run after the standard_swap repoint and before the media stage.
//  - SUITABLE_FOR STAGE (Library Batch S1b-2): scripts/data/library_s1b2_suitable_for.json, the core-levels contract for
//    `suitable_for` of kept rows, run right after the core-levels stage.
//  - INJURY-TAG STAGE (Unit 1B-F, Ruling 12, d19): scripts/data/library_injury_additions_v25.json, the same contract for
//    `injury_contraindications` of kept rows (the five lower-body jump E-rows gain `hip`), run right after the
//    suitable_for stage. New rows take their tags from the injury table, never from this record.
//  - A row is built from an ALLOW-LIST: the 40 required keys, then variant_family (from the table), then skill_track,
//    skill_step, progression_to, regression_to where non-null, then slot_pattern and same_movement_as where present (LINK). Everything else in the source (confidence, note, changes,
//    hold, _coreAdded, demo_*, a future meta key) is dropped.
//  - Derived keys (R4): is_active, source "exercise-gif-set", is_indian_context false, standard_swap "", warmup_protocol "",
//    cal_per_set_est = round(met_value * 1.8), equipment_tier = every tier whose items hold every equipment token.
//  - injury_contraindications = sorted(raw source tags UNION the table row); a token is never removed, a non-canonical
//    token is refused. A shipped row with no table row stops the run.
//  - Before writing it proves that re-serialising the UNCHANGED library reproduces its bytes (the v13 formatter,
//    scripts/add_library_core_fields_v13.js:50-72); if not, the formatter is wrong and nothing is written.
//  - It is idempotent: a second run on unchanged inputs is byte-identical.
//  - MEDIA STAGE (Batch M1, plan R4), the last stage: every row the media table maps gets `media_slug`, `media_version`,
//    `media_source` appended after every other key, in that order; every other row has the three keys removed. The default
//    table is scripts/data/library_media_v16.json next to this script and a missing one is FATAL; `--media none` is the
//    only skip and is refused unless `--library` is also given (the stage-less run would otherwise rewrite the real
//    library in place and strip the keys from every mapped row). A table row whose id is not in the new library (a newly
//    held row) stops the run, as does a `rows` slug with no `files` entry or no `versions` (no partial triple).

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
// --media <path> | none. `none` is tested BEFORE any path.resolve (it is not a path).
function rawFlag(name) {
  const i = args.indexOf(name);
  if (i < 0) return undefined;
  if (i + 1 >= args.length || args[i + 1].startsWith('--')) throw new Error(`${name} needs a value`);
  return args[i + 1];
}
const MEDIA_ARG = rawFlag('--media');
const MEDIA_NONE = MEDIA_ARG === 'none';
if (MEDIA_NONE && !args.includes('--library')) {
  throw new Error('--media none needs an explicit --library <copy>: without it the run would rewrite the real library and strip the media keys from every mapped row');
}
const MEDIA = MEDIA_NONE ? null : MEDIA_ARG === undefined ? path.join(__dirname, 'data', 'library_media_v16.json') : path.resolve(MEDIA_ARG);
// Batch C2a (OI-460): scripts/data/library_batch_c2_removals.json. Every `decision: remove` id leaves the library; a
// removed name that differs from every kept row name (`alias_to`) is appended to that row's name_aliases. A missing
// file is a printed no-op, an id already absent is an idempotent no-op, an id that is a SOURCE id stops the run, and a
// replacement / alias target that is not a row of the new library stops the run.
const REMOVALS_ARG = rawFlag('--removals');
const REMOVALS_NONE = REMOVALS_ARG === 'none';
const REMOVALS = REMOVALS_NONE ? null : path.resolve(REMOVALS_ARG === undefined ? path.join(__dirname, 'data', 'library_batch_c2_removals.json') : REMOVALS_ARG);
const MEDIA_KEYS = ['media_slug', 'media_version', 'media_source'];
const MEDIA_SOURCE = 'wardroom';

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
// Library Batch S1b-2: source keys copied through when present (after LADDER, before the media keys). slot_pattern puts
// a loaded version in its original's ON pool (E048 / E050 carry one); same_movement_as names the original a loaded version
// must never share a day with (SameMovement, lib/shared/repositories/plan_engine/same_movement.dart).
const LINK = ['slot_pattern', 'same_movement_as'];
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
  for (const k of LINK) if (src[k] !== undefined && src[k] !== null) out[k] = src[k];
  return out;
}

// Batch M1 (R4): the media stage. Delete-then-set, because assigning an existing key keeps its position and the
// three keys must come last and in order. Returns new row objects; the input is not mutated.
function readMediaTable() {
  if (!fs.existsSync(MEDIA)) {
    throw new Error(`media table ${MEDIA} not found (pass --media <path>, or --media none together with --library to skip the media stage)`);
  }
  const t = JSON.parse(fs.readFileSync(MEDIA, 'utf8'));
  if (!t || typeof t.rows !== 'object' || typeof t.files !== 'object') throw new Error(`media table ${MEDIA} has no rows / files`);
  // An empty `rows` map is not "nothing to attach": applyMedia deletes the three keys from every old row first, so an
  // empty or truncated table would silently strip the media from the whole library. Skipping the stage must be explicit.
  if (t.rows === null || Object.keys(t.rows).length === 0) {
    throw new Error(`media table ${MEDIA} maps no rows (an empty table would strip the media keys from every row; pass --media none with --library to skip the media stage on purpose)`);
  }
  return t;
}

function applyMedia(allRows, media) {
  const ids = new Set(allRows.map((r) => r.id));
  const resolved = {};
  for (const [id, slug] of Object.entries(media.rows)) {
    if (!ids.has(id)) {
      throw new Error(`media table maps ${id}, which is not a row of the new library (a newly held row? remove it from the table first: docs/operations/EXERCISE_MEDIA.md, "Hold a mapped row")`);
    }
    const file = media.files[slug];
    if (!file) throw new Error(`media table: ${id} maps to ${slug}, which has no files entry`);
    if (!Array.isArray(file.versions) || file.versions.length === 0) throw new Error(`media table: file ${slug} has no versions`);
    const version = file.versions[file.versions.length - 1].media_version;
    if (!Number.isInteger(version) || version < 1) throw new Error(`media table: file ${slug} has an invalid media_version ${version}`);
    resolved[id] = { media_slug: slug, media_version: version, media_source: MEDIA_SOURCE };
  }
  return allRows.map((r) => {
    const out = { ...r };
    for (const k of MEDIA_KEYS) delete out[k];
    const m = resolved[r.id];
    if (m) for (const k of MEDIA_KEYS) out[k] = m[k];
    return out;
  });
}

// Batch C2c (OI-474): the E230 retag record. Absent = printed no-op. The record must name the same keys in `before`
// and `after` (a typo key would be appended last and --check would still pass bytewise).
const RETAG = path.join(__dirname, 'data', 'library_e230_retag.json');

function readRetag() {
  if (!fs.existsSync(RETAG)) {
    console.log(`retag stage skipped: ${RETAG} not found`);
    return null;
  }
  const rec = JSON.parse(fs.readFileSync(RETAG, 'utf8'));
  if (!rec || typeof rec.id !== 'string' || !rec.before || !rec.after) {
    throw new Error(`retag record ${RETAG} needs id, before and after`);
  }
  const bk = Object.keys(rec.before);
  const ak = Object.keys(rec.after);
  if (bk.length === 0 || bk.join(',') !== ak.join(',')) {
    throw new Error(`retag record ${RETAG}: before and after must name the same keys in the same order (${bk} vs ${ak})`);
  }
  return rec;
}

function retagRow(row, rec) {
  const keys = Object.keys(rec.before);
  const missing = keys.filter((k) => !(k in row));
  if (missing.length) throw new Error(`${rec.id}: the row has no ${missing.join(', ')} (the retag record names it)`);
  const same = (which) => keys.filter((k) => JSON.stringify(row[k]) === JSON.stringify(rec[which][k]));
  if (same('after').length === keys.length) return row;
  if (same('before').length === keys.length) return { ...row, ...rec.after };
  const atBefore = same('before');
  const atAfter = same('after');
  const foreign = keys.filter((k) => !atBefore.includes(k) && !atAfter.includes(k));
  // A half-applied row has no foreign key: every key matches ONE state, so name both sides instead of all nine keys.
  const where = foreign.length
    ? `key(s) with a foreign value: ${foreign.join(', ')}`
    : `key(s) at before: ${atBefore.join(', ') || '(none)'}; key(s) at after: ${atAfter.join(', ') || '(none)'}`;
  throw new Error(`${rec.id}: the row matches neither the retag record's before nor its after; ${where} (update after, or restore the row)`);
}

// Library Batch S1a: the core-levels record for kept rows. Absent = printed no-op.
const CORE_LEVELS = path.join(__dirname, 'data', 'library_s1_core_levels.json');

function readCoreLevels() {
  if (!fs.existsSync(CORE_LEVELS)) {
    console.log(`core-levels stage skipped: ${CORE_LEVELS} not found`);
    return null;
  }
  const rec = JSON.parse(fs.readFileSync(CORE_LEVELS, 'utf8'));
  if (!rec || !Array.isArray(rec.rows)) throw new Error(`core-levels record ${CORE_LEVELS} has no rows array`);
  const byId = new Map();
  for (const e of rec.rows) {
    if (!e || typeof e.id !== 'string' || !Array.isArray(e.before) || !Array.isArray(e.after)) {
      throw new Error(`core-levels record ${CORE_LEVELS}: every row needs id, before and after arrays`);
    }
    if (byId.has(e.id)) throw new Error(`core-levels record ${CORE_LEVELS} repeats ${e.id}`);
    byId.set(e.id, e);
  }
  return byId;
}

function coreLevelsRow(row, e) {
  const cur = JSON.stringify(row.core_levels);
  if (cur === JSON.stringify(e.after)) return row;
  if (cur === JSON.stringify(e.before)) return { ...row, core_levels: e.after };
  throw new Error(`${e.id}: core_levels ${cur} matches neither the core-levels record's before nor its after (update after, or restore the row)`);
}

function readRemovals() {
  if (REMOVALS === null || !fs.existsSync(REMOVALS)) {
    console.log(`removals stage skipped: ${REMOVALS === null ? '--removals none' : `${REMOVALS} not found`}`);
    return [];
  }
  const entries = JSON.parse(fs.readFileSync(REMOVALS, 'utf8')).entries;
  if (!Array.isArray(entries)) throw new Error(`removals file ${REMOVALS} has no entries array`);
  return entries.filter((e) => e.decision === 'remove');
}

// Appends each alias_to name to its target row's name_aliases (existing array kept in order, no duplicate).
function applyAliases(allRows, removals) {
  const byId = new Map(allRows.map((r) => [r.id, r]));
  const names = new Set(allRows.map((r) => r.name.toLowerCase()));
  return allRows.map((r) => {
    const add = removals.filter((e) => e.alias_to === r.id).map((e) => e.name);
    if (!add.length) return r;
    for (const n of add) {
      if (names.has(n.toLowerCase())) throw new Error(`alias "${n}" equals a row name of the new library`);
    }
    const cur = Array.isArray(r.name_aliases) ? r.name_aliases : [];
    const merged = [...cur, ...add.filter((n) => !cur.includes(n))];
    return { ...r, name_aliases: merged };
  });
}

// A `standard_swap` that names a removed row would point at nothing (B-pass C2a finding 2): it takes the replacement row's
// name, or "" when the removal has no replacement or the replacement is the row itself. Batch C2b (OI-462): the field also
// holds ids on 21 rows (E043 names "E111"), so an id-form value is matched by id and takes the replacement's ID, a
// name-form value keeps taking the NAME. Nothing in lib/ or the Edge Functions reads the field.
function repointStandardSwap(allRows, removals) {
  const byId = new Map(allRows.map((r) => [r.id, r]));
  const goneByName = new Map(removals.map((e) => [e.name.toLowerCase(), e]));
  const goneById = new Map(removals.map((e) => [e.id, e]));
  return allRows.map((r) => {
    if (typeof r.standard_swap !== 'string') return r;
    const byName = goneByName.get(r.standard_swap.toLowerCase());
    const e = byName || goneById.get(r.standard_swap);
    if (!e) return r;
    const to = e.replacement ? byId.get(e.replacement) : undefined;
    const ok = to && to.id !== r.id;
    return { ...r, standard_swap: ok ? (byName ? to.name : to.id) : '' };
  });
}

// Library Batch S1b-3 (OI-147, plan D9): the MERGE STAGE. scripts/data/library_s1b3_merges.json lists rows retired INTO a
// kept row ({id, name, into, merged_in}). The record is authoritative: `into` may be a SOURCE row (G1373 is), which
// buildRow rebuilds from the allow-list on every run, so nothing is ever read back from `into` to decide what to do.
// Order: drop the row (only when present; its name must equal `name`), append `id` to into.merged_ids and `name` to
// into.name_aliases (no duplicates, existing order kept; new keys are appended, and applyMedia then moves the media keys
// back to the end), then check every alias against the POST-drop row names. A second run is byte-identical. Absent =
// printed no-op, like the other stages; the cloud seed generator treats a missing file as a hard stop instead.
const MERGES = path.join(__dirname, 'data', 'library_s1b3_merges.json');

function readMerges() {
  if (!fs.existsSync(MERGES)) {
    console.log(`merge stage skipped: ${MERGES} not found`);
    return [];
  }
  const rec = JSON.parse(fs.readFileSync(MERGES, 'utf8'));
  if (!rec || !Array.isArray(rec.rows)) throw new Error(`merges record ${MERGES} has no rows array`);
  const seen = new Set();
  for (const m of rec.rows) {
    for (const k of ['id', 'name', 'into', 'merged_in']) {
      if (typeof m[k] !== 'string' || m[k].length === 0) throw new Error(`merges record ${MERGES}: a row lacks ${k} (${m.id || '?'})`);
    }
    if (seen.has(m.id)) throw new Error(`merges record ${MERGES} repeats ${m.id}`);
    seen.add(m.id);
  }
  // A chain (A into B, then B into C) would drop B after it took A's alias and merged_ids, losing both silently.
  for (const m of rec.rows) {
    if (seen.has(m.into)) throw new Error(`merges record ${MERGES}: ${m.id}'s merge target ${m.into} is itself merged away by this record`);
  }
  return rec.rows;
}

function applyMerges(allRows, merges, sourceIds) {
  let out = allRows;
  for (const m of merges) {
    if (sourceIds.has(m.id)) throw new Error(`${m.id}: the merges record names a source row (only a kept base row can be merged away)`);
    const present = out.find((r) => r.id === m.id);
    if (present && present.name !== m.name) {
      throw new Error(`${m.id}: the merges record names it "${m.name}", the library row is "${present.name}"`);
    }
    out = out.filter((r) => r.id !== m.id);
    const at = out.findIndex((r) => r.id === m.into);
    if (at < 0) throw new Error(`${m.id}: merge target ${m.into} is not a row of the new library`);
    const into = { ...out[at] };
    const ids = Array.isArray(into.merged_ids) ? into.merged_ids : [];
    const aliases = Array.isArray(into.name_aliases) ? into.name_aliases : [];
    into.name_aliases = aliases.includes(m.name) ? aliases : [...aliases, m.name];
    into.merged_ids = ids.includes(m.id) ? ids : [...ids, m.id];
    out = [...out.slice(0, at), into, ...out.slice(at + 1)];
  }
  const names = new Set(out.map((r) => r.name.toLowerCase()));
  for (const m of merges) {
    if (names.has(m.name.toLowerCase())) throw new Error(`${m.id}: alias "${m.name}" equals a row name of the new library`);
  }
  return out;
}

// Library Batch S1b-2: the suitable_for record for kept rows (E010, E045; founder 2026-11-09, board d12). Same contract as
// the core-levels record: a row at `before` takes `after`, a row at `after` is a no-op, anything else stops the run;
// an id that is not a kept row, or a duplicate id, stops the run. Absent = printed no-op (tests copy this script).
const SUITABLE_FOR = path.join(__dirname, 'data', 'library_s1b2_suitable_for.json');

function readSuitableFor() {
  if (!fs.existsSync(SUITABLE_FOR)) {
    console.log(`suitable_for stage skipped: ${SUITABLE_FOR} not found`);
    return null;
  }
  const rec = JSON.parse(fs.readFileSync(SUITABLE_FOR, 'utf8'));
  if (!rec || !Array.isArray(rec.rows)) throw new Error(`suitable_for record ${SUITABLE_FOR} has no rows array`);
  const byId = new Map();
  for (const e of rec.rows) {
    if (!e || typeof e.id !== 'string' || !Array.isArray(e.before) || !Array.isArray(e.after)) {
      throw new Error(`suitable_for record ${SUITABLE_FOR}: every row needs id, before and after arrays`);
    }
    if (byId.has(e.id)) throw new Error(`suitable_for record ${SUITABLE_FOR} repeats ${e.id}`);
    byId.set(e.id, e);
  }
  return byId;
}

function suitableForRow(row, e) {
  const cur = JSON.stringify(row.suitable_for);
  if (cur === JSON.stringify(e.after)) return row;
  if (cur === JSON.stringify(e.before)) return { ...row, suitable_for: e.after };
  throw new Error(`${e.id}: suitable_for ${cur} matches neither the suitable_for record's before nor its after (update after, or restore the row)`);
}

// Unit 1B-F (Ruling 12, founder d19 2026-11-10): the injury-tag record for kept rows. Same contract as the
// suitable_for record: a row at `before` takes `after`, a row at `after` is a no-op, anything else stops the run; an id
// that is not a kept row, or a duplicate id, stops the run. Absent = printed no-op (tests copy this script).
const INJURY_TAGS = path.join(__dirname, 'data', 'library_injury_additions_v25.json');

function readInjuryTags() {
  if (!fs.existsSync(INJURY_TAGS)) {
    console.log(`injury-tag stage skipped: ${INJURY_TAGS} not found`);
    return null;
  }
  const rec = JSON.parse(fs.readFileSync(INJURY_TAGS, 'utf8'));
  if (!rec || !Array.isArray(rec.rows)) throw new Error(`injury-tag record ${INJURY_TAGS} has no rows array`);
  const byId = new Map();
  for (const e of rec.rows) {
    if (!e || typeof e.id !== 'string' || !Array.isArray(e.before) || !Array.isArray(e.after)) {
      throw new Error(`injury-tag record ${INJURY_TAGS}: every row needs id, before and after arrays`);
    }
    if (byId.has(e.id)) throw new Error(`injury-tag record ${INJURY_TAGS} repeats ${e.id}`);
    byId.set(e.id, e);
  }
  return byId;
}

function injuryTagsRow(row, e) {
  const cur = JSON.stringify(row.injury_contraindications);
  if (cur === JSON.stringify(e.after)) return row;
  if (cur === JSON.stringify(e.before)) return { ...row, injury_contraindications: e.after };
  throw new Error(`${e.id}: injury_contraindications ${cur} matches neither the injury-tag record's before nor its after (update after, or restore the row)`);
}

function main() {
  const media = MEDIA_NONE ? null : readMediaTable();
  const before = fs.readFileSync(LIBRARY, 'utf8');
  const base = JSON.parse(before);
  if (format(base) !== before) {
    throw new Error('round-trip of the unchanged library does not reproduce its bytes');
  }
  console.log(`round-trip OK (${base.length} rows)`);

  const e001 = base.find((r) => r.id === 'E001');
  const e001Keys = Object.keys(e001).filter((k) => !['demo_slug', 'demo_pair', 'variant_family', ...MEDIA_KEYS].includes(k));
  if (e001Keys.join(',') !== REQUIRED.join(',')) {
    throw new Error('the 40 required keys no longer match E001 minus demo_slug / demo_pair / variant_family');
  }

  const source = JSON.parse(fs.readFileSync(SOURCE, 'utf8'));
  const rows = source.rows;
  const table = JSON.parse(fs.readFileSync(TABLE, 'utf8')).rows;
  const sourceIds = new Set(rows.map((r) => r.id));
  if (sourceIds.size !== rows.length) throw new Error('the source file repeats an id');
  /*HELD-SKIP*/ const shipped = rows.filter((r) => !r.hold);

  const removals = readRemovals();
  const removeIds = new Set(removals.map((e) => e.id));
  const inSource = [...removeIds].filter((i) => sourceIds.has(i));
  if (inSource.length) throw new Error(`removals name source ids: ${inSource.join(' ')}`);
  const retag = readRetag();
  const kept = base.filter((r) => !sourceIds.has(r.id) && !removeIds.has(r.id)).map((r) => {
    if (retag && r.id === retag.id) return retagRow(r, retag);
    if (r.id !== 'E274') return r;
    // E274 Prone T Raise: target_focus Upper Back -> Mid Back (slot_focus already carries Mid Back).
    return { ...r, target_focus: r.target_focus.map((f) => (f === 'Upper Back' ? 'Mid Back' : f)) };
  });
  if (!kept.some((r) => r.id === 'E274')) throw new Error('E274 is not in the library');
  if (retag && !kept.some((r) => r.id === retag.id)) throw new Error(`${retag.id} is not a kept row of the library (the retag record names it)`);
  const coreLevels = readCoreLevels();
  if (coreLevels) {
    const keptIds = new Set(kept.map((r) => r.id));
    const foreign = [...coreLevels.keys()].filter((i) => !keptIds.has(i));
    if (foreign.length) throw new Error(`core-levels record names ids that are not kept rows: ${foreign.join(' ')}`);
    for (let i = 0; i < kept.length; i++) {
      const e = coreLevels.get(kept[i].id);
      if (e) kept[i] = coreLevelsRow(kept[i], e);
    }
  }
  const suitableFor = readSuitableFor();
  if (suitableFor) {
    const keptIds = new Set(kept.map((r) => r.id));
    const foreign = [...suitableFor.keys()].filter((i) => !keptIds.has(i));
    if (foreign.length) throw new Error(`suitable_for record names ids that are not kept rows: ${foreign.join(' ')}`);
    for (let i = 0; i < kept.length; i++) {
      const e = suitableFor.get(kept[i].id);
      if (e) kept[i] = suitableForRow(kept[i], e);
    }
  }
  const injuryTags = readInjuryTags();
  if (injuryTags) {
    const keptIds = new Set(kept.map((r) => r.id));
    const foreign = [...injuryTags.keys()].filter((i) => !keptIds.has(i));
    if (foreign.length) throw new Error(`injury-tag record names ids that are not kept rows: ${foreign.join(' ')}`);
    for (let i = 0; i < kept.length; i++) {
      const e = injuryTags.get(kept[i].id);
      if (e) kept[i] = injuryTagsRow(kept[i], e);
    }
  }

  const added = shipped.map((r) => {
    const tableRow = table[r.id];
    if (!tableRow) throw new Error(`${r.id}: no row in the injury tag table (the injury gate cannot be skipped)`);
    return buildRow(r, tableRow);
  });
  const finalRows = [...kept, ...added];
  const finalIds = new Set(finalRows.map((r) => r.id));
  for (const e of removals) {
    for (const t of [e.replacement, e.alias_to]) {
      if (t && !finalIds.has(t)) throw new Error(`${e.id}: replacement / alias target ${t} is not a row of the new library`);
    }
  }
  const aliased = applyAliases(finalRows, removals);
  const swapped = repointStandardSwap(aliased, removals);
  const merges = readMerges();
  const merged = applyMerges(swapped, merges, sourceIds);
  const withMedia = media ? applyMedia(merged, media) : merged;
  const next = format(withMedia);

  const heldCount = rows.length - shipped.length;
  const mergedAway = swapped.length - merged.length;
  const keptAfter = kept.length - mergedAway;
  const summary = `${keptAfter} kept + ${added.length} new = ${keptAfter + added.length} rows (${heldCount} held source rows skipped, ${mergedAway} merged away), media keys on ${withMedia.filter((r) => 'media_slug' in r).length} rows`;
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
