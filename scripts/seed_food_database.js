#!/usr/bin/env node
// Generates SQL to seed the food_database table from bundled JSON.
// Output: supabase/migrations/030_seed_food_database.sql
// Idempotent: uses ON CONFLICT (id) DO UPDATE so re-runs are safe.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const JSON_PATH = path.join(ROOT, 'assets', 'data', 'food_database.json');
const OUTPUT_SQL = path.join(ROOT, 'supabase', 'migrations', '030_seed_food_database.sql');

// UUID v5 namespace (shared with custom exercises + templates per docs/architecture/database.md)
const NAMESPACE = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';

function uuidv5(name, namespace) {
  // Hand-rolled v5 implementation — Node's crypto doesn't have a built-in
  const nsBytes = Buffer.from(namespace.replace(/-/g, ''), 'hex');
  const nameBytes = Buffer.from(name, 'utf-8');
  const hash = crypto.createHash('sha1').update(nsBytes).update(nameBytes).digest();
  // Set version (5) and variant (RFC 4122)
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

function num(v, def = 0) {
  return v == null ? def : Number(v);
}

const data = JSON.parse(fs.readFileSync(JSON_PATH, 'utf-8'));
console.log(`Loaded ${data.length} foods from ${JSON_PATH}`);

const valuesRows = data.map(item => {
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
    ${sqlEscape(item.source ?? 'bundled')},
    now()
  )`;
}).join(',\n');

const sql = `-- Seed food_database from bundled JSON (assets/data/food_database.json).
-- Source: ${data.length} Indian-first foods. Deterministic UUIDs v5 from
-- (namespace, "food_database|<json_id>") so re-runs are idempotent.
-- See scripts/seed_food_database.js for regeneration.

INSERT INTO food_database (
  id, name, category,
  calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, fiber_per_100g,
  standard_serving_desc, standard_serving_g,
  calories_std, protein_std, carbs_std, fat_std,
  common_additions, is_indian, source, created_at
) VALUES
${valuesRows}
ON CONFLICT (id) DO UPDATE SET
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
  source = EXCLUDED.source;
`;

fs.mkdirSync(path.dirname(OUTPUT_SQL), { recursive: true });
fs.writeFileSync(OUTPUT_SQL, sql);
console.log(`Wrote ${(sql.length / 1024).toFixed(1)}KB to ${OUTPUT_SQL}`);
