#!/usr/bin/env node
// Generates SQL to seed the exercise_library table from bundled JSON.
//
//   node scripts/seed_exercise_library.js <migration file name> [--split] [--out <dir>]
//
//   <migration file name>  REQUIRED, e.g. 163_reseed_exercise_library.sql. There is no default: a no-name run exits
//                          non-zero, because the old default was the LAST applied migration and a bare run would have
//                          rewritten it. A name whose number the applied ledger already records is refused (also for an explicit
//                          --out that resolves to supabase/migrations) unless --out
//                          redirects the file (a rehearsal / test).
//   --split                two INSERT statements (each with its own ON CONFLICT clause) instead of one, for a POST the
//                          apply tool refuses for size. Never hand-edit the generated file to split it.
//   --out <dir>            write there instead of supabase/migrations (used by test/contracts/exercise_library_cloud_seeded_test.dart).
//
// Output: <out dir or supabase/migrations>/<migration file name>.
//
// An APPLIED seed migration is IMMUTABLE, so a library change does NOT rewrite the
// last one -- it mints the next number. 074 seeded the original 259 rows; 125 re-seeds
// the 271 that OI-89 produced; 162 re-seeds the 285 of library v12 (Batch A) and
// deactivates the 7 retired duplicates; the Batch C1 seed re-seeds the 914 of library v15; the Batch C2a seed re-seeds the
// 864 of library v18 and deactivates the 50 rows it removed (scripts/data/library_batch_c2_removals.json); the Batch C2b seed
// re-seeds the 862 of library v19, inserts the four twin rows and deactivates the six rows C2b removed; the Batch C2c seed
// re-seeds the 862 of library v20 with ONE changed row (E230 retagged to bodyweight, scripts/data/library_e230_retag.json)
// and no row added or removed.
// Rewriting 074 in place would have made the applied ledger describe a file that no
// longer matches what ran.
// Idempotent: uses ON CONFLICT (id) DO UPDATE so re-runs are safe.
//
// Mirrors scripts/seed_food_database.js (the 030_seed_food_database.sql template).
// Closes diagnose 2026-05-27-exercise-library-cloud-empty-ada3fb (beat-my-coach was
// reading an empty cloud table since deploy because the bundled seed never landed).

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
// SEED_LIBRARY_JSON points a REHEARSAL at another library file (test/contracts/exercise_library_cloud_seeded_test.dart); the
// real run never sets it.
const JSON_PATH = process.env.SEED_LIBRARY_JSON ? path.resolve(process.env.SEED_LIBRARY_JSON) : path.join(ROOT, 'assets', 'data', 'exercise_library.json');
const LEDGER_PATH = path.join(ROOT, 'backups', 'applied_migrations.json');

// What the generated file says about itself. Edit this block for the next batch. The header text below is derived from it and
// from the removals file; the retag block (the record, its four cloud columns and `retagNote`) is the part to replace or delete
// when a batch has no retag.
const BATCH = {
  label: 'library v20, Batch C2c',
  diagnose: '2026-11-06-library-batch-c2c-e230-d8ac69',
  // Rows the Batch C1 importer wrote carry this `source` literal: the existing C1 rows plus the four Batch C2b twins.
  newRowSource: 'exercise-gif-set',
  // The removals file carries `removed_in` ('c2a' | 'c2b') per remove entry: ALL are deactivated (idempotent), but a batch's
  // rollback reactivates only the ones it removed itself (an earlier, already-applied migration keeps its own rollback text).
  // Batch C2c removes and adds no row, so its tag matches no entry and the reactivation / twin lines are left out.
  batchTag: 'c2c',
  removalsFile: path.join(ROOT, 'scripts', 'data', 'library_batch_c2_removals.json'),
  // Batch C2c (OI-474): the E230 retag record. Its `after` must equal the library row (a record that drifted from the library
  // would seed one thing and roll back to another); its `before` is what the inline rollback restores. The cloud table holds
  // only these four of the record's nine keys.
  retagFile: path.join(ROOT, 'scripts', 'data', 'library_e230_retag.json'),
  // What the Intent line says about the retag; edit with the record for the next retag batch.
  retagNote: 'Batch C2c, OI-474: retagged to bodyweight',
  cloudRetagColumns: ['equipment_needed', 'logging_type', 'coaching_cues', 'common_mistakes'],
  // The seed migration this one follows: its text is the other half of the rollback sentence.
  previousMigration: '171',
};

function fail(msg) {
  console.error(`seed_exercise_library: ${msg}`);
  console.error('usage: node scripts/seed_exercise_library.js <migration file name> [--split] [--out <dir>]');
  process.exit(2);
}

const argv = process.argv.slice(2);
let split = false;
let outDir = null;
const positional = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--split') {
    split = true;
  } else if (a === '--out') {
    if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) fail('--out needs a directory');
    outDir = path.resolve(argv[++i]);
  } else if (a.startsWith('--')) {
    fail(`unknown flag ${a}`);
  } else {
    positional.push(a);
  }
}
if (positional.length !== 1) fail('exactly one migration file name is required (there is no default)');
const FILE_NAME = positional[0];
if (path.basename(FILE_NAME) !== FILE_NAME || !/^\d+_\w*seed_exercise_library\.sql$/.test(FILE_NAME)) {
  fail(`"${FILE_NAME}" is not a seed migration name like 163_reseed_exercise_library.sql`);
}
const DEFAULT_OUT_DIR = path.join(ROOT, 'supabase', 'migrations');
// The refusal applies to the default directory in EVERY spelling: an explicit `--out supabase/migrations` is the same
// directory and would rewrite an applied, immutable migration just the same (B-pass 2026-10-26).
const normalizedDir = (p) => {
  const r = path.resolve(p);
  return process.platform === 'win32' || process.platform === 'darwin' ? r.toLowerCase() : r;
};
if (outDir === null || normalizedDir(outDir) === normalizedDir(DEFAULT_OUT_DIR)) {
  const number = String(parseInt(FILE_NAME.match(/^(\d+)_/)[1], 10));
  let applied = [];
  try {
    applied = JSON.parse(fs.readFileSync(LEDGER_PATH, 'utf-8'));
  } catch (_) {
    fail(`cannot read the applied ledger ${LEDGER_PATH}; refusing to write a migration blind`);
  }
  const clash = applied.some((e) => {
    const m = typeof e === 'string' ? e : e && e.migration;
    return m !== undefined && m !== null && String(parseInt(String(m), 10)) === number;
  });
  if (clash) fail(`migration ${number} is already in the applied ledger and is immutable; mint the next number`);
}
const OUTPUT_SQL = path.join(outDir || DEFAULT_OUT_DIR, FILE_NAME);

// UUID v5 namespace shared with custom_exercises + food_database seeds
const NAMESPACE = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';

function uuidv5(name, namespace) {
  const nsBytes = Buffer.from(namespace.replace(/-/g, ''), 'hex');
  const nameBytes = Buffer.from(name, 'utf-8');
  const hash = crypto.createHash('sha1').update(nsBytes).update(nameBytes).digest();
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  const hex = hash.toString('hex').slice(0, 32);
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20, 32)].join('-');
}

function sqlEscape(v) {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'number') return String(v);
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  return "'" + String(v).replace(/'/g, "''") + "'";
}

function sqlTextArray(arr) {
  if (!Array.isArray(arr) || arr.length === 0) return "ARRAY[]::text[]";
  const escaped = arr.map(s => "'" + String(s).replace(/'/g, "''") + "'").join(',');
  return `ARRAY[${escaped}]::text[]`;
}

// name_aliases is NULL, not an empty array, on a row with no alias: cloud rows
// seeded before v12 hold NULL there, and NULL is what "no alias" has always meant.
function sqlTextArrayOrNull(arr) {
  return Array.isArray(arr) && arr.length > 0 ? sqlTextArray(arr) : 'NULL';
}

function firstOrNull(arr) {
  // DB schema: movement_pattern + exercise_type are TEXT (not ARRAY).
  // JSON ships them as arrays — flatten to first element.
  if (!Array.isArray(arr) || arr.length === 0) return null;
  return arr[0];
}

function num(v) {
  return v == null ? 'NULL' : String(Number(v));
}

const data = JSON.parse(fs.readFileSync(JSON_PATH, 'utf-8'));
console.log(`Loaded ${data.length} exercises from ${JSON_PATH}`);

const valueTuples = data.map(item => {
  const uuid = uuidv5(`exercise_library|${item.id}`, NAMESPACE);
  // Single-line per row keeps the generated file under MCP / read limits.
  return `(${sqlEscape(uuid)}, ${sqlEscape(item.name)}, ${sqlEscape(item.category)}, ${sqlEscape(firstOrNull(item.movement_pattern))}, ${sqlEscape(firstOrNull(item.exercise_type))}, ${sqlTextArray(item.primary_muscles)}, ${sqlTextArray(item.secondary_muscles)}, ${sqlTextArray(item.equipment_needed)}, ${sqlEscape(item.logging_type ?? 'weight_reps')}, ${sqlEscape(item.difficulty_level)}, ${sqlTextArray(item.suitable_for)}, ${sqlTextArray(item.coaching_cues)}, ${sqlTextArray(item.common_mistakes)}, ${num(item.default_sets)}, ${sqlEscape(item.default_reps)}, ${num(item.default_rest_secs)}, ${sqlEscape(item.source ?? 'icanbefitter_seed')}, ${sqlEscape(item.is_active ?? true)}, ${sqlEscape(item.is_indian_context ?? false)}, ${sqlTextArrayOrNull(item.name_aliases)}, now())`;
});

// One INSERT ... ON CONFLICT statement for a slice of the tuples.
function insertStatement(tuples) {
  return `INSERT INTO exercise_library (
  id, name, category,
  movement_pattern, exercise_type,
  primary_muscles, secondary_muscles, equipment_needed,
  logging_type, difficulty_level, suitable_for,
  coaching_cues, common_mistakes,
  default_sets, default_reps, default_rest_secs,
  source, is_active, is_indian_context, name_aliases, created_at
) VALUES
${tuples.join(',\n')}
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  movement_pattern = EXCLUDED.movement_pattern,
  exercise_type = EXCLUDED.exercise_type,
  primary_muscles = EXCLUDED.primary_muscles,
  secondary_muscles = EXCLUDED.secondary_muscles,
  equipment_needed = EXCLUDED.equipment_needed,
  logging_type = EXCLUDED.logging_type,
  difficulty_level = EXCLUDED.difficulty_level,
  suitable_for = EXCLUDED.suitable_for,
  coaching_cues = EXCLUDED.coaching_cues,
  common_mistakes = EXCLUDED.common_mistakes,
  default_sets = EXCLUDED.default_sets,
  default_reps = EXCLUDED.default_reps,
  default_rest_secs = EXCLUDED.default_rest_secs,
  source = EXCLUDED.source,
  is_active = EXCLUDED.is_active,
  is_indian_context = EXCLUDED.is_indian_context,
  name_aliases = EXCLUDED.name_aliases;`;
}

const half = Math.ceil(valueTuples.length / 2);
const insertStatements = split
  ? `${insertStatement(valueTuples.slice(0, half))}\n\n${insertStatement(valueTuples.slice(half))}`
  : insertStatement(valueTuples);

// Library v12 (Batch A): a row retired into its twin leaves the bundled JSON, and
// the kept row lists it in merged_ids. Nothing deletes in cloud (promotions and
// logs may point at the row), so the retired row is deactivated instead, and it
// takes the kept row's cues because getFormCues matches by exact name with no
// is_active filter. One statement per pair, never starting with "(", so the
// VALUES-tuple count in exercise_library_cloud_seeded_test stays exact. These are
// idempotent: the 7 rows are already inactive in live cloud, so re-running changes nothing.
const idOf = (libraryId) => uuidv5(`exercise_library|${libraryId}`, NAMESPACE);
const retireStatements = data
  .filter((item) => Array.isArray(item.merged_ids))
  .flatMap((kept) => kept.merged_ids.map((retired) =>
    `UPDATE exercise_library r SET is_active = false, coaching_cues = k.coaching_cues, common_mistakes = k.common_mistakes FROM exercise_library k WHERE r.id = '${idOf(retired)}' AND k.id = '${idOf(kept.id)}';`))
  .join('\n');

// Batch C2a: the `decision: remove` ids. Cloud never deletes (promotions and logs may point at a row), so each is
// deactivated. A removed row that shares its name with a KEPT row also takes that row's cues (getFormCues matches by name
// with no is_active filter); a removed row whose name differs keeps its own cues, which are right for its own name.
// A missing removals file is a hard stop, never an empty list: a run that quietly emits no deactivations looks like success.
if (!fs.existsSync(BATCH.removalsFile)) fail(`removals file not found: ${path.relative(ROOT, BATCH.removalsFile)}`);
const removedEntries = JSON.parse(fs.readFileSync(BATCH.removalsFile, 'utf8')).entries.filter((e) => e.decision === 'remove').sort((a, b) => a.id.localeCompare(b.id));
const noTag = removedEntries.filter((e) => e.removed_in !== 'c2a' && e.removed_in !== 'c2b').map((e) => e.id);
if (noTag.length) fail(`removals without removed_in (c2a | c2b): ${noTag.join(' ')}`);
// This batch's own removals and the rows it adds: the twins are the replacements the removals file flags `replacement_new`
// (a replacement that ALREADY shipped, like C2a's E144 to G3470, is never a twin: its rollback must not deactivate a live row).
const ownRemoved = removedEntries.filter((e) => e.removed_in === BATCH.batchTag);
const ownTwinIds = [...new Set(ownRemoved.filter((e) => e.replacement_new === true).map((e) => e.replacement))].sort();
const missingTwin = ownTwinIds.filter((i) => !data.some((item) => item.id === i));
if (missingTwin.length) fail(`twin row(s) flagged replacement_new are not in the library: ${missingTwin.join(' ')}`);
// A removed id that is back in the library would be upserted active and then deactivated by the statements below (a row that
// ships dead). B-pass C2a finding 4: refuse, the Dart seed has the same mirror (`pruneRetired(...difference(shipped))`).
const dataIds = new Set(data.map((item) => item.id));
const reAdded = removedEntries.filter((e) => dataIds.has(e.id)).map((e) => e.id);
if (reAdded.length) fail(`removed id(s) are back in the library: ${reAdded.join(' ')} (edit ${path.relative(ROOT, BATCH.removalsFile)} first)`);
const keptByName = new Map(data.map((item) => [item.name.toLowerCase(), item]));
const removalStatements = removedEntries
  .map((e) => {
    const twin = keptByName.get(e.name.toLowerCase());
    return twin
      ? `UPDATE exercise_library r SET is_active = false, coaching_cues = k.coaching_cues, common_mistakes = k.common_mistakes FROM exercise_library k WHERE r.id = '${idOf(e.id)}' AND k.id = '${idOf(twin.id)}';`
      : `UPDATE exercise_library SET is_active = false WHERE id = '${idOf(e.id)}';`;
  })
  .join('\n');
// A batch that owns no removal and no twin has nothing to reactivate or deactivate: an `IN ()` list is a SQL syntax error,
// so those lines exist only when their list is non-empty (Batch C2c owns neither).
const reactivateLine = ownRemoved.length
  ? `UPDATE exercise_library SET is_active = true WHERE id IN (${ownRemoved.map((e) => `'${idOf(e.id)}'`).join(', ')});`
  : null;
// The twins are INSERTed active by this batch; the cloud never deletes, so the rollback deactivates them.
const deactivateTwinsLine = ownTwinIds.length
  ? `UPDATE exercise_library SET is_active = false WHERE id IN (${ownTwinIds.map((i) => `'${idOf(i)}'`).join(', ')});`
  : null;
// What the header says about rows: a batch that owns a removal or a twin has reactivation / deactivation lines in its rollback.
const ownsNoRow = ownRemoved.length === 0 && ownTwinIds.length === 0
  ? 'no row is added or removed (this batch owns neither)'
  : `${ownRemoved.length} removed and ${ownTwinIds.length} inserted row(s) belong to this batch`;
const rollbackRowSentence = ownRemoved.length === 0 && ownTwinIds.length === 0
  ? 'this batch removes and adds no row, so it has no reactivation or deactivation line'
  : 'the reactivation and twin deactivation lines of this batch follow in the commented block';
const removedBy = (tag) => removedEntries.filter((e) => e.removed_in === tag).length;
const newRows = data.filter((item) => item.source === BATCH.newRowSource).length;
const retiredPairs = data
  .filter((item) => Array.isArray(item.merged_ids))
  .reduce((n, kept) => n + kept.merged_ids.length, 0);

// Batch C2c (OI-474): the E230 retag. A missing record, a missing row or a record whose `after` differs from the library row
// is a hard stop (a run that quietly seeded one thing and rolled back to another would look like success). The rollback is the
// row's four cloud columns restored from `before`, through the same escapers the INSERT uses.
if (!fs.existsSync(BATCH.retagFile)) fail(`retag record not found: ${path.relative(ROOT, BATCH.retagFile)}`);
const retag = JSON.parse(fs.readFileSync(BATCH.retagFile, 'utf8'));
const retagRow = data.find((item) => item.id === retag.id);
if (!retagRow) fail(`retag record names ${retag.id}, which is not a library row`);
const retagDrift = Object.keys(retag.after).filter((k) => JSON.stringify(retagRow[k]) !== JSON.stringify(retag.after[k]));
if (retagDrift.length) fail(`${retag.id} differs from the retag record's after on: ${retagDrift.join(', ')} (run scripts/add_library_batch_c_v15.js, or update the record)`);
const missingCloud = BATCH.cloudRetagColumns.filter((k) => !(k in retag.before));
if (missingCloud.length) fail(`retag record has no before value for the cloud column(s): ${missingCloud.join(', ')}`);
const cloudValue = (k, v) => (Array.isArray(v) ? sqlTextArray(v) : sqlEscape(v));
const retagRollbackLine = `UPDATE exercise_library SET ${BATCH.cloudRetagColumns.map((k) => `${k} = ${cloudValue(k, retag.before[k])}`).join(', ')} WHERE id = '${idOf(retag.id)}';`;

const sql = `-- Intent: RE-SEED cloud exercise_library from bundled assets/data/exercise_library.json (${data.length} exercises, ${BATCH.label}): UPSERTS all ${data.length} rows with their bundled values; the ONE changed row is ${retag.id} ${retagRow.name} (${BATCH.retagNote}, so its ${BATCH.cloudRetagColumns.join(', ')} change and the row's other cloud columns do not); the ${newRows} rows with source '${BATCH.newRowSource}' and every other row are re-written with the values the previous seed (${BATCH.previousMigration}) gave them; ${ownsNoRow}; repeats the ${retiredPairs} idempotent Batch A retire UPDATEs and the ${removedEntries.length} idempotent deactivations of the rows Batch C2a (${removedBy('c2a')}) and C2b (${removedBy('c2b')}) removed (all already inactive in live cloud).
-- Destructive?: yes   -- UPSERT REWRITES ROWS (supabase/migrations/CLAUDE.md): ON CONFLICT (id) DO UPDATE re-writes every column of all ${data.length} rows (no new rows; one row, ${retag.id}, carries new values). Also repeats is_active = false on the ${removedEntries.length} removed rows (already inactive). No DELETE, DROP, TRUNCATE or constraint change.
-- Rollback strategy: inline   -- ${retagRollbackLine}  (restores the ${BATCH.cloudRetagColumns.length} cloud columns of ${retag.id} to the values the previous seed (${BATCH.previousMigration}) gave it; ${rollbackRowSentence}; commented block at the end of this file). NOT a DELETE: promotions and logs may point at a row once users see it.
-- Linked diagnose-doc: ${BATCH.diagnose}

-- Source: ${data.length} exercises from assets/data/exercise_library.json.
-- Deterministic UUIDs v5 from (namespace, "exercise_library|<json_id>") so re-runs are idempotent.
-- See scripts/seed_exercise_library.js for regeneration${split ? ' (generated with --split: two INSERT statements)' : ''}.
--
-- Schema mapping notes:
--   * movement_pattern + exercise_type are TEXT in DB but arrays in JSON — flatten to first element.
--   * name_aliases comes from the JSON since library v12 (NULL on a row without one).
--   * DB columns not in JSON (instructions, alternative_ids, regression_id,
--     progression_id, default_duration_secs) are intentionally NULL on first apply.
--   * JSON-only fields (tempo, met_value, cal_per_set_est, breathing_cue, warmup_protocol,
--     pro_tip, image_*, gif_url, equipment_tier, cns_demand, target_focus, priority_tier,
--     rep_range, is_foundational, is_bilateral, standard_swap, indian_alternative,
--     injury_contraindications, core_levels, discipline, gym_availability, requires_coaching,
--     high_impact, variant_family and the ladder keys) are not surfaced in cloud schema yet —
--     they live in the bundled Hive box. Add columns + a follow-up backfill migration when a
--     reader needs them.

${insertStatements}

-- Retired duplicates (library v12): deactivate, and copy the kept twin's cues.
${retireStatements}

-- Removed rows (Batch C2a and Batch C2b): deactivate. They left the bundled library; cloud keeps them.
${removalStatements}

-- Rollback (inline):
${[retagRollbackLine, reactivateLine, deactivateTwinsLine].filter(Boolean).map((l) => `--   ${l}`).join('\n')}
--   (every other row was re-written with its unchanged bundled values, so it needs no inverse. Re-applying the previous seed migration (${BATCH.previousMigration}) restores the old ${retag.id} values verbatim.)
`;

fs.mkdirSync(path.dirname(OUTPUT_SQL), { recursive: true });
fs.writeFileSync(OUTPUT_SQL, sql);
console.log(`Wrote ${(sql.length / 1024).toFixed(1)}KB to ${OUTPUT_SQL}${split ? ' (2 INSERT statements)' : ''}`);
