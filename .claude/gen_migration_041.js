#!/usr/bin/env node
// Generates migration 041_food_database_seed_v2.sql from V2 food_database.json.
// Output: supabase/migrations/041_food_database_seed_v2.sql
//
// Differences from scripts/seed_food_database.js (which produced migration 030):
//   - Adds ALTER TABLE for is_veg + is_vegan columns at the top.
//   - Includes is_veg + is_vegan in the upsert.
//   - 1431 rows instead of 93.
//   - Idempotent: uses ON CONFLICT (id) DO UPDATE so re-runs are safe and
//     legacy rows from migration 030 get the new is_veg/is_vegan flags
//     written automatically (same v5 UUID = same id).
//
// Also emits chunked variants under supabase/migrations/041_chunks/ to stay
// inside MCP apply_migration payload limits.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const JSON_PATH = path.join(ROOT, 'assets', 'data', 'food_database.json');
const OUTPUT_SQL = path.join(
  ROOT,
  'supabase',
  'migrations',
  '041_food_database_seed_v2.sql',
);
const CHUNK_DIR = path.join(
  ROOT,
  'supabase',
  'migrations',
  '041_chunks',
);

// UUID v5 namespace (shared with custom exercises + templates per CLAUDE.md §7).
// MUST match scripts/seed_food_database.js so existing 93 rows resolve to the
// same UUIDs and get UPDATE'd in place rather than INSERT'd as duplicates.
const NAMESPACE = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';

function uuidv5(name, namespace) {
  const nsBytes = Buffer.from(namespace.replace(/-/g, ''), 'hex');
  const nameBytes = Buffer.from(name, 'utf-8');
  const hash = crypto.createHash('sha1').update(nsBytes).update(nameBytes).digest();
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  const hex = hash.toString('hex').slice(0, 32);
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join('-');
}

function sqlEscape(v) {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'number') return String(v);
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  return "'" + String(v).replace(/'/g, "''") + "'";
}

function num(v, def = 0) {
  return v == null ? def : Number(v);
}

const data = JSON.parse(fs.readFileSync(JSON_PATH, 'utf-8'));
console.log(`Loaded ${data.length} foods from ${JSON_PATH}`);

const ALTER_SQL = `-- Migration 041: V2 food database seed (1431 items).
-- APK Test #3 batch (2026-04-26).
--
-- Expands food_database from 93 → 1431 items. Sources:
--   - 93 icanbefitter_seed (preserved by deterministic v5 UUID)
--   - 699 manual_indian_staples_v2
--   - 228 manual_western_v2
--   - 225 openfoodfacts_india_v2
--   - 186 manual_fitness_v2
--
-- Adds is_veg + is_vegan columns. is_vegan=true implies is_veg=true.
-- Idempotent: ON CONFLICT (id) DO UPDATE so legacy rows get refreshed in place.

ALTER TABLE food_database
  ADD COLUMN IF NOT EXISTS is_veg BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS is_vegan BOOLEAN DEFAULT FALSE;
`;

function rowToValuesSqlPretty(item) {
  const uuid = uuidv5(`food_database|${item.id}`, NAMESPACE);
  return `(
    ${sqlEscape(uuid)},
    ${sqlEscape(item.name)},
    ${sqlEscape(item.category)},
    ${num(item.calories_per_100g)},
    ${num(item.protein_per_100g)},
    ${num(item.carbs_per_100g)},
    ${num(item.fat_per_100g)},
    ${num(item.fiber_per_100g)},
    ${sqlEscape(item.standard_serving_desc)},
    ${num(item.standard_serving_g)},
    ${num(item.calories_std)},
    ${num(item.protein_std)},
    ${num(item.carbs_std)},
    ${num(item.fat_std)},
    '{}'::text[],
    ${sqlEscape(item.is_indian ?? true)},
    ${sqlEscape(item.is_veg ?? true)},
    ${sqlEscape(item.is_vegan ?? false)},
    ${sqlEscape(item.source ?? 'bundled')},
    now()
  )`;
}

// Compact one-line format used for chunked SQL files (smaller payloads).
function rowToValuesSqlCompact(item) {
  const uuid = uuidv5(`food_database|${item.id}`, NAMESPACE);
  return `(${sqlEscape(uuid)},${sqlEscape(item.name)},${sqlEscape(item.category)},${num(item.calories_per_100g)},${num(item.protein_per_100g)},${num(item.carbs_per_100g)},${num(item.fat_per_100g)},${num(item.fiber_per_100g)},${sqlEscape(item.standard_serving_desc)},${num(item.standard_serving_g)},${num(item.calories_std)},${num(item.protein_std)},${num(item.carbs_std)},${num(item.fat_std)},'{}'::text[],${sqlEscape(item.is_indian ?? true)},${sqlEscape(item.is_veg ?? true)},${sqlEscape(item.is_vegan ?? false)},${sqlEscape(item.source ?? 'bundled')},now())`;
}

const rowToValuesSql = rowToValuesSqlPretty;

const INSERT_HEADER = `INSERT INTO food_database (
  id, name, category,
  calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, fiber_per_100g,
  standard_serving_desc, standard_serving_g,
  calories_std, protein_std, carbs_std, fat_std,
  common_additions, is_indian, is_veg, is_vegan, source, created_at
) VALUES`;

const ON_CONFLICT = `ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  calories_per_100g = EXCLUDED.calories_per_100g,
  protein_per_100g = EXCLUDED.protein_per_100g,
  carbs_per_100g = EXCLUDED.carbs_per_100g,
  fat_per_100g = EXCLUDED.fat_per_100g,
  fiber_per_100g = EXCLUDED.fiber_per_100g,
  standard_serving_desc = EXCLUDED.standard_serving_desc,
  standard_serving_g = EXCLUDED.standard_serving_g,
  calories_std = EXCLUDED.calories_std,
  protein_std = EXCLUDED.protein_std,
  carbs_std = EXCLUDED.carbs_std,
  fat_std = EXCLUDED.fat_std,
  is_indian = EXCLUDED.is_indian,
  is_veg = EXCLUDED.is_veg,
  is_vegan = EXCLUDED.is_vegan,
  source = EXCLUDED.source;`;

// ---- Single-file output (full migration, used as the canonical artifact). ----
const allRows = data.map(rowToValuesSql).join(',\n');
const fullSql = `${ALTER_SQL}
${INSERT_HEADER}
${allRows}
${ON_CONFLICT}
`;

fs.mkdirSync(path.dirname(OUTPUT_SQL), { recursive: true });
fs.writeFileSync(OUTPUT_SQL, fullSql);
console.log(`Wrote ${(fullSql.length / 1024).toFixed(1)}KB to ${OUTPUT_SQL}`);

// ---- Chunked output (for MCP apply_migration payload caps). --------------
// Chunk 0: ALTER TABLE only.
// Chunks 1..N: INSERT/UPSERT chunks of CHUNK_SIZE rows each.
const CHUNK_SIZE = 150;
fs.mkdirSync(CHUNK_DIR, { recursive: true });

fs.writeFileSync(path.join(CHUNK_DIR, '041_00_alter.sql'), ALTER_SQL);

let chunkIdx = 1;
for (let i = 0; i < data.length; i += CHUNK_SIZE) {
  const slice = data.slice(i, i + CHUNK_SIZE);
  const sliceRows = slice.map(rowToValuesSqlCompact).join(',\n');
  const sliceSql = `-- Migration 041 chunk ${chunkIdx} (rows ${i + 1}-${i + slice.length} of ${data.length}).
${INSERT_HEADER}
${sliceRows}
${ON_CONFLICT}
`;
  const file = path.join(
    CHUNK_DIR,
    `041_${String(chunkIdx).padStart(2, '0')}_rows_${i + 1}_${i + slice.length}.sql`,
  );
  fs.writeFileSync(file, sliceSql);
  console.log(`Wrote chunk ${chunkIdx} (${slice.length} rows, ${(sliceSql.length / 1024).toFixed(1)}KB)`);
  chunkIdx += 1;
}
console.log('Done.');
