#!/usr/bin/env node
// Removals generator: Batch C2a (OI-460, plan docs/plans/2026-11-04-library-batch-c2a-removals.md) and Batch C2b (OI-462,
// plan docs/plans/2026-11-05-library-batch-c2b-twins.md). C2b adds the four twin rows to the depth rows (TWIN_FIXTURE) so a
// removal is judged with its twin present, and moves the six former twin_pending rows into REPLACEMENT.
//
//   node scripts/library_batch_c2_removals_gen.js                 # write scripts/data/library_batch_c2_removals.json
//   node scripts/library_batch_c2_removals_gen.js --check         # the committed file equals a fresh run (exit 1 if not)
//   node scripts/library_batch_c2_removals_gen.js --build-fixture <library.json> <sheet66.json>
//        # ONE-SHOT: freeze the BASE library's depth fields + the 66 sheet-drop ids into
//        # test/fixtures/library_c2_base_depth.json. Run it only against the pre-removal library (80a9bc2d).
//
// The generator reads ONLY the committed fixture, never the live library, `merged.json` or `git show`, so it and the
// tests behave the same in CI's depth-1 checkout and after the removals have shipped.
//
// DEPTH RULE (R8): removing a row must leave, in every cell the row occupies, at least min(depth_before, 3) rows.
// A cell is (injury set of 1 or 2 tags) x (slot pattern) x (equipment tier); the pool is discipline strength / prehab /
// mobility. It is evaluated under BOTH `movement_pattern` and `slot_pattern ?? movement_pattern`
// (lib/shared/repositories/plan_engine/core_list_selector.dart:166) and the UNION of the keeps is kept.
// Iteration order is ascending id; the loop runs to a fixed point (a keep can force another keep).
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.join(__dirname, '..');
const FIXTURE = path.join(ROOT, 'test', 'fixtures', 'library_c2_base_depth.json');
const TWIN_FIXTURE = path.join(ROOT, 'test', 'fixtures', 'library_c2b_twin_rows.json');
const OUT = path.join(ROOT, 'scripts', 'data', 'library_batch_c2_removals.json');
const SOURCE = path.join(ROOT, 'scripts', 'data', 'library_batch_c_source.json');

const ELIGIBLE = new Set(['strength', 'prehab', 'mobility']);
const SKIP_PATTERNS = new Set(['warmup', 'cooldown', 'flexibility', 'cardio']);

// ---- founder / reviewer decisions that the depth rule cannot compute -----------------------------------------
// forced keeps: names the plan engine EMITS (warm-up lists) or anchors (cool-down floor) with no like-for-like row.
const FORCED = {
  E208: 'Hip Circles is an emitted warm-up name (warmup_cooldown.dart) and has no like-for-like row.',
  E221: 'Deep Breathing is an emitted cool-down name and the cool-down floor anchor; no like-for-like row.',
  E254: 'Plan matrix (606 personas, scorecard_gate_test): 25 bodyweight build_muscle 4-6 day plans fill 5-6 distinct elbow_flexion Biceps rows; with E254 and E281 both gone the bodyweight pool is 4 and each gets a (none) pick (hard zero). E254 and E281 together are the floor: E254 alone leaves 25 target-fidelity fallbacks (2034 > baseline 2009). The injury-cell depth rule does not see the uninjured cell.',
  E281: 'Plan matrix (606 personas, scorecard_gate_test): see E254. With E254 kept and E281 removed the same 25 plans fall back to the universal pool (2034 fallback picks against a baseline of 2009).',
};
// removed_in: the batch that removed the row. The 50 ids below are FROZEN (Batch C2a, migration 167); every other `remove` id is
// Batch C2b. The seed generator scopes its rollback to `c2b` (plan Decision 3).
const C2A_REMOVED = new Set([
  'E075', 'E081', 'E082', 'E101', 'E115', 'E116', 'E125', 'E126', 'E128', 'E130', 'E137', 'E138', 'E144', 'E146', 'E150', 'E153', 'E154', 'E156', 'E157', 'E158', 'E160', 'E163', 'E164', 'E170', 'E178', 'E183', 'E184', 'E192', 'E194', 'E195', 'E196', 'E197', 'E199', 'E204', 'E210', 'E218', 'E223', 'E227', 'E228', 'E233', 'E237', 'E243', 'E256', 'E265', 'E279', 'E285', 'E287', 'E288', 'E293', 'E294',
]);
// replacement: the shipped row that serves the removed row's purpose TODAY. alias_to: the replacement that receives
// the removed NAME as an alias (founder alias policy 2026-11-04; only when the name differs from every row name).
const REPLACEMENT = {
  E144: { to: 'G3470', alias: true, why: 'Reverse Lunge: the hip/knee lunge twin (Forward Lunge); the name stays reachable as an alias.' },
  E075: { to: 'E008', alias: true, why: 'Dip (Parallel Bars) duplicates Chest Dip.' },
  E265: { to: 'E280', alias: false, why: 'Prone Lat Pull; E280 is the home Beginner vertical pull.' },
  E210: { to: 'G1428', alias: true, why: 'Wrist Rotations shares animation 1428 with G1428 Wrist Circles.' },
  E218: { to: 'G0794', alias: true, why: 'Side Bend Stretch; G0794 is the lower-back side stretch.' },
  E293: { to: 'E291', alias: false, why: 'Elevated Single Leg Hip Thrust; founder removed it 2026-11-04, E291 is the home hip thrust.' },
  // Batch C2b (OI-462): the four twins now ship, so the six rows that C2a kept as twin_pending leave. A name that equals the twin's
  // name needs no alias (the seed generator copies the twin's cues onto a same-name removed row).
  E084: { to: 'G1368', alias: false, isNew: true, why: 'Ankle Circles; G1368 is the same animation and the same name.' },
  E211: { to: 'G1368', alias: true, isNew: true, why: 'Ankle Rotations; G1368 Ankle Circles is the same animation, the name stays reachable as an alias.' },
  E111: { to: 'G1489', alias: false, isNew: true, why: 'Sissy Squat; G1489 is the same animation and name. The depth rule, judged with G1489 present, lets E111 go.' },
  E162: { to: 'G2567', alias: true, isNew: true, why: 'Piriformis Stretch; G2567 Seated Piriformis Stretch is the same animation, the name stays reachable as an alias.' },
  E169: { to: 'G2567', alias: false, isNew: true, why: 'Seated Piriformis Stretch; G2567 is the same animation and name.' },
  E179: { to: 'G0474', alias: false, isNew: true, why: 'Toes to Bar; G0474 is the same animation and name.' },
};

// The base fixture plus the four C2b twin rows, in ONE rows array: depth() uses the same array for the before and the
// after reading, so every removal is judged with its twin present.
function loadFixture() {
  const fx = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));
  const tw = JSON.parse(fs.readFileSync(TWIN_FIXTURE, 'utf8'));
  fx.rows = fx.rows.concat(tw.rows);
  return fx;
}

function injurySets(rows) {
  const inj = [...new Set(rows.flatMap((r) => r.injury_contraindications))].sort();
  const sets = [];
  inj.forEach((a, i) => {
    sets.push([a]);
    inj.slice(i + 1).forEach((b) => sets.push([a, b]));
  });
  return sets;
}

const patternsOf = (sem, r) => (sem === 'slot' ? (r.slot_pattern || r.movement_pattern) : r.movement_pattern);

function depth(rows, without, sem, S, p, t) {
  let n = 0;
  for (const r of rows) {
    if (without.has(r.id) || !ELIGIBLE.has(r.discipline)) continue;
    if (!S.every((i) => !r.injury_contraindications.includes(i))) continue;
    if (!patternsOf(sem, r).includes(p) || !r.equipment_tier.includes(t)) continue;
    n++;
  }
  return n;
}

// The cells of ONE row: [{key, S, p, t}] over the injury sets the row does not contraindicate.
function cellsOf(row, sets, sem) {
  const out = [];
  for (const S of sets) {
    if (S.some((i) => row.injury_contraindications.includes(i))) continue;
    for (const p of patternsOf(sem, row).filter((x) => !SKIP_PATTERNS.has(x))) {
      for (const t of row.equipment_tier) out.push({ key: `${sem}|${S.join('+')}/${p}/${t}`, S, p, t });
    }
  }
  return out;
}

function computeKeeps(fx, sem) {
  const rows = fx.rows;
  const byId = new Map(rows.map((r) => [r.id, r]));
  const sets = injurySets(rows);
  const drop = fx.drop.map((d) => d.id).sort();
  const keep = new Set(Object.keys(FORCED));
  const why = {};
  let changed = true;
  while (changed) {
    changed = false;
    const removed = new Set(drop.filter((i) => !keep.has(i)));
    for (const id of drop) {
      if (keep.has(id)) continue;
      const r = byId.get(id);
      if (!ELIGIBLE.has(r.discipline)) continue; // an ineligible row is in no pool, so it can never be needed
      const bad = [];
      for (const c of cellsOf(r, sets, sem)) {
        const before = depth(rows, new Set(), sem, c.S, c.p, c.t);
        const after = depth(rows, removed, sem, c.S, c.p, c.t);
        if (after < Math.min(before, 3)) bad.push(`${c.key}:${before}->${after}`);
      }
      if (bad.length) {
        keep.add(id);
        why[id] = bad.slice(0, 3);
        changed = true;
      }
    }
  }
  return { keep, why };
}

function build(fx) {
  const rows = fx.rows;
  const byId = new Map(rows.map((r) => [r.id, r]));
  const sets = injurySets(rows);
  const mp = computeKeeps(fx, 'mp');
  const slot = computeKeeps(fx, 'slot');
  const depthKeep = new Set([...mp.keep, ...slot.keep].filter((i) => !(i in FORCED)));
  const entries = fx.drop
    .map((d) => d.id)
    .sort()
    .map((id) => {
      const r = byId.get(id);
      const e = { id, name: r.name };
      if (id in FORCED) {
        e.decision = 'keep';
        e.keep_reason = 'forced';
        e.reason = FORCED[id];
      } else if (depthKeep.has(id)) {
        e.decision = 'keep';
        e.keep_reason = 'depth';
        e.reason = `Depth rule: ${(mp.why[id] || slot.why[id] || []).join('; ')}`;
      } else {
        e.decision = 'remove';
        e.removed_in = C2A_REMOVED.has(id) ? 'c2a' : 'c2b';
        const rep = REPLACEMENT[id];
        if (rep) {
          e.replacement = rep.to;
          // replacement_new: the replacement row ships for the FIRST time in the batch that removes this row (a twin). The seed
          // generator derives the rows its migration INSERTs, and its rollback deactivates, from this flag (B-pass C2b finding 3).
          if (rep.isNew) e.replacement_new = true;
          if (rep.alias) e.alias_to = rep.to;
          e.reason = rep.why;
        } else {
          e.reason = ELIGIBLE.has(r.discipline)
            ? 'Sheet drop; the depth rule holds without it in every cell.'
            : `Sheet drop; discipline ${r.discipline} is outside every pool.`;
        }
      }
      // depth_before: only the cells whose frozen depth is below 3 (above that the rule is just "after >= 3").
      const before = {};
      if (e.decision === 'remove' && ELIGIBLE.has(r.discipline)) {
        for (const sem of ['mp', 'slot']) {
          for (const c of cellsOf(r, sets, sem)) {
            const n = depth(rows, new Set(), sem, c.S, c.p, c.t);
            if (n < 3) before[c.key] = n;
          }
        }
      }
      e.depth_before = before;
      return e;
    });
  return {
    _meta: {
      plan: 'docs/plans/2026-11-04-library-batch-c2a-removals.md; docs/plans/2026-11-05-library-batch-c2b-twins.md',
      oi: 'OI-460; OI-462',
      generator: 'scripts/library_batch_c2_removals_gen.js',
      base_commit: fx._meta.base_commit,
      fixture: 'test/fixtures/library_c2_base_depth.json',
      twin_fixture: 'test/fixtures/library_c2b_twin_rows.json',
      twin_fixture_sha256: crypto.createHash('sha256').update(fs.readFileSync(TWIN_FIXTURE)).digest('hex'),
      sheet_sha256: fx._meta.sheet_sha256,
      iteration_order: 'ascending id',
      depth_rule: 'after >= min(before, 3) per cell (injury single or pair x slot pattern x equipment tier), pool strength/prehab/mobility, movement_pattern AND slot_pattern ?? movement_pattern, union of keeps',
      counts: {
        total: entries.length,
        remove: entries.filter((e) => e.decision === 'remove').length,
        keep: entries.filter((e) => e.decision === 'keep').length,
      },
    },
    entries,
  };
}

function buildFixture(libPath, sheetPath) {
  const lib = JSON.parse(fs.readFileSync(libPath, 'utf8'));
  const sheet = JSON.parse(fs.readFileSync(sheetPath, 'utf8'));
  const sheetIds = new Set(sheet.map((x) => x.id));
  const noFamily = lib.filter((r) => !r.variant_family).map((r) => r.id);
  if (noFamily.length !== 66 || noFamily.some((i) => !sheetIds.has(i)) || sheetIds.size !== 66) {
    throw new Error('the 66 rows without variant_family must equal the 66 sheet ids');
  }
  const src = JSON.parse(fs.readFileSync(SOURCE, 'utf8'));
  const rows = lib
    .filter((r) => ELIGIBLE.has(r.discipline) || sheetIds.has(r.id))
    .map((r) => {
      const o = {
        id: r.id,
        name: r.name,
        discipline: r.discipline,
        movement_pattern: r.movement_pattern,
      };
      if (r.slot_pattern) o.slot_pattern = r.slot_pattern;
      o.injury_contraindications = r.injury_contraindications;
      o.equipment_tier = r.equipment_tier;
      return o;
    });
  return {
    _meta: {
      base_commit: '80a9bc2d',
      note: 'Frozen BASE library depth fields (914 rows at 80a9bc2d): every strength/prehab/mobility row plus the 66 sheet-drop rows. Tests and the generator read this, never git history.',
      sheet_sha256: src._meta.merged_sha256,
      library_rows: lib.length,
    },
    drop: sheet.map((x) => ({ id: x.id, name: x.name, decided_by: x.by })),
    rows,
  };
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] === '--build-fixture') {
    const fx = buildFixture(args[1], args[2]);
    fs.mkdirSync(path.dirname(FIXTURE), { recursive: true });
    fs.writeFileSync(FIXTURE, JSON.stringify(fx) + '\n');
    console.log(`fixture: ${fx.rows.length} rows, ${fx.drop.length} sheet-drop ids`);
    return;
  }
  const text = JSON.stringify(build(loadFixture()), null, 1) + '\n';
  if (args[0] === '--check') {
    const cur = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
    if (cur !== text) {
      console.error('removals file is stale: run node scripts/library_batch_c2_removals_gen.js');
      process.exit(1);
    }
    console.log('removals file is current');
    return;
  }
  fs.writeFileSync(OUT, text);
  const j = JSON.parse(text);
  console.log(`removals: ${j._meta.counts.remove} remove, ${j._meta.counts.keep} keep`);
  console.log('keeps:', j.entries.filter((e) => e.decision === 'keep').map((e) => `${e.id}:${e.keep_reason}`).join(' '));
}

main();
