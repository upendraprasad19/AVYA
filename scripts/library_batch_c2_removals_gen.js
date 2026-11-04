#!/usr/bin/env node
// Batch C2a removals generator (OI-460). Plan: docs/plans/2026-11-04-library-batch-c2a-removals.md (Task 1).
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

const ROOT = path.join(__dirname, '..');
const FIXTURE = path.join(ROOT, 'test', 'fixtures', 'library_c2_base_depth.json');
const OUT = path.join(ROOT, 'scripts', 'data', 'library_batch_c2_removals.json');
const SOURCE = path.join(ROOT, 'scripts', 'data', 'library_batch_c_source.json');

const ELIGIBLE = new Set(['strength', 'prehab', 'mobility']);
const SKIP_PATTERNS = new Set(['warmup', 'cooldown', 'flexibility', 'cardio']);

// ---- founder / reviewer decisions that the depth rule cannot compute -----------------------------------------
// forced keeps: names the plan engine EMITS (warm-up lists) or anchors (cool-down floor) with no like-for-like row.
const FORCED = {
  E208: 'Hip Circles is an emitted warm-up name (warmup_cooldown.dart) and has no like-for-like row.',
  E221: 'Deep Breathing is an emitted cool-down name and the cool-down floor anchor; no like-for-like row.',
};
// twin_pending: the depth rule would let the row go, but its replacement twin is added by Batch C2b (OI-462).
const TWIN_PENDING = {
  E084: 'G1368', E211: 'G1368', E111: 'G1489', E162: 'G2567', E169: 'G2567', E179: 'G0474',
};
// replacement: the shipped row that serves the removed row's purpose TODAY. alias_to: the replacement that receives
// the removed NAME as an alias (founder alias policy 2026-11-04; only when the name differs from every row name).
const REPLACEMENT = {
  E144: { to: 'G3470', alias: true, why: 'Reverse Lunge: the hip/knee lunge twin (Forward Lunge); the name stays reachable as an alias.' },
  E075: { to: 'E008', alias: true, why: 'Dip (Parallel Bars) duplicates Chest Dip.' },
  E254: { to: 'E282', alias: false, why: 'Doorframe Curl; E282 is the home biceps curl.' },
  E265: { to: 'E280', alias: false, why: 'Prone Lat Pull; E280 is the home Beginner vertical pull.' },
  E210: { to: 'G1428', alias: true, why: 'Wrist Rotations shares animation 1428 with G1428 Wrist Circles.' },
  E218: { to: 'G0794', alias: true, why: 'Side Bend Stretch; G0794 is the lower-back side stretch.' },
  E293: { to: 'E291', alias: false, why: 'Elevated Single Leg Hip Thrust; founder removed it 2026-11-04, E291 is the home hip thrust.' },
};

function loadFixture() {
  return JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));
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
        if (id in TWIN_PENDING) e.twin = TWIN_PENDING[id];
      } else if (id in TWIN_PENDING) {
        e.decision = 'keep';
        e.keep_reason = 'twin_pending';
        e.twin = TWIN_PENDING[id];
        e.reason = `Replacement ${TWIN_PENDING[id]} is added by Batch C2b (OI-462); the row leaves then.`;
      } else {
        e.decision = 'remove';
        const rep = REPLACEMENT[id];
        if (rep) {
          e.replacement = rep.to;
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
      plan: 'docs/plans/2026-11-04-library-batch-c2a-removals.md',
      oi: 'OI-460',
      generator: 'scripts/library_batch_c2_removals_gen.js',
      base_commit: fx._meta.base_commit,
      fixture: 'test/fixtures/library_c2_base_depth.json',
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
