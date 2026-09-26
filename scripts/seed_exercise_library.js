#!/usr/bin/env node
// Generates SQL to seed the exercise_library table from bundled JSON.
//
// Output: supabase/migrations/<argv[2] or the CURRENT_SEED below>.
//
// An APPLIED seed migration is IMMUTABLE, so a library change does NOT rewrite the
// last one -- it mints the next number and CURRENT_SEED moves to it. 074 seeded the
// original 259 rows; 125 re-seeds the 271 that OI-89 produced. Rewriting 074 in
// place would have made the applied ledger describe a file that no longer matches
// what ran.
// Idempotent: uses ON CONFLICT (id) DO UPDATE so re-runs are safe.
//
// Mirrors scripts/seed_food_database.js (the 030_seed_food_database.sql template).
// Closes diagnose 2026-05-27-exercise-library-cloud-empty-ada3fb (beat-my-coach was
// reading an empty cloud table since deploy because the bundled seed never landed).

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const JSON_PATH = path.join(ROOT, 'assets', 'data', 'exercise_library.json');
const CURRENT_SEED = '125_reseed_exercise_library.sql';
const OUTPUT_SQL = path.join(
  ROOT, 'supabase', 'migrations', process.argv[2] || CURRENT_SEED);

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

const valuesRows = data.map(item => {
  const uuid = uuidv5(`exercise_library|${item.id}`, NAMESPACE);
  // Single-line per row keeps the generated file under MCP / read limits.
  return `(${sqlEscape(uuid)}, ${sqlEscape(item.name)}, ${sqlEscape(item.category)}, ${sqlEscape(firstOrNull(item.movement_pattern))}, ${sqlEscape(firstOrNull(item.exercise_type))}, ${sqlTextArray(item.primary_muscles)}, ${sqlTextArray(item.secondary_muscles)}, ${sqlTextArray(item.equipment_needed)}, ${sqlEscape(item.logging_type ?? 'weight_reps')}, ${sqlEscape(item.difficulty_level)}, ${sqlTextArray(item.suitable_for)}, ${sqlTextArray(item.coaching_cues)}, ${sqlTextArray(item.common_mistakes)}, ${num(item.default_sets)}, ${sqlEscape(item.default_reps)}, ${num(item.default_rest_secs)}, ${sqlEscape(item.source ?? 'icanbefitter_seed')}, ${sqlEscape(item.is_active ?? true)}, ${sqlEscape(item.is_indian_context ?? false)}, now())`;
}).join(',\n');

const sql = `-- Intent: Seed cloud exercise_library from bundled assets/data/exercise_library.json (${data.length} exercises). Mirrors 030_seed_food_database — base seed for the canonical library that user_custom_exercises promotions accrete onto via promote-community-item Edge Function.
-- Destructive?: no   -- INSERT...ON CONFLICT DO UPDATE; no row deletion, no constraint change
-- Rollback strategy: inline   -- TRUNCATE TABLE exercise_library; only safe if no promotions have landed (always true at first apply)
-- Linked diagnose-doc: 2026-05-27-exercise-library-cloud-empty-ada3fb

-- Source: ${data.length} exercises from assets/data/exercise_library.json.
-- Deterministic UUIDs v5 from (namespace, "exercise_library|<json_id>") so re-runs are idempotent.
-- See scripts/seed_exercise_library.js for regeneration.
--
-- Schema mapping notes:
--   * movement_pattern + exercise_type are TEXT in DB but arrays in JSON — flatten to first element.
--   * DB columns not in JSON (name_aliases, instructions, alternative_ids, regression_id,
--     progression_id, default_duration_secs) are intentionally NULL on first apply.
--   * JSON-only fields (tempo, met_value, cal_per_set_est, breathing_cue, warmup_protocol,
--     pro_tip, image_*, gif_url, equipment_tier, cns_demand, target_focus, priority_tier,
--     rep_range, is_foundational, is_bilateral, standard_swap, indian_alternative,
--     injury_contraindications) are not surfaced in cloud schema yet — they live in the
--     bundled Hive box. Add columns + a follow-up backfill migration when a reader needs them.

INSERT INTO exercise_library (
  id, name, category,
  movement_pattern, exercise_type,
  primary_muscles, secondary_muscles, equipment_needed,
  logging_type, difficulty_level, suitable_for,
  coaching_cues, common_mistakes,
  default_sets, default_reps, default_rest_secs,
  source, is_active, is_indian_context, created_at
) VALUES
${valuesRows}
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
  is_indian_context = EXCLUDED.is_indian_context;

-- Rollback (commented):
-- TRUNCATE TABLE exercise_library;
`;

fs.mkdirSync(path.dirname(OUTPUT_SQL), { recursive: true });
fs.writeFileSync(OUTPUT_SQL, sql);
console.log(`Wrote ${(sql.length / 1024).toFixed(1)}KB to ${OUTPUT_SQL}`);
