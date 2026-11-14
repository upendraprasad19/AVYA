#!/usr/bin/env node
// Batch C1 (library v15) scope script: converts the sheet rows once, decides WHICH rows need a
// picture or an identity read, and verifies that the records of those reads exist.
//
//   node scripts/library_batch_c_scope.js --init <path to merged.json>   one-time conversion
//   node scripts/library_batch_c_scope.js --write                        seed stubs / holds / derived counts
//   node scripts/library_batch_c_scope.js --check                        verify contract C1..C6
//
// Plan: docs/plans/2026-10-25-library-batch-c-new-rows.md (R1, R11, Task 1). The criterion is
// evaluated on the FROZEN inputs in _meta.criterion_inputs (name, equipment_needed, core_levels,
// confidence as first written by --init) plus the row's note / changes and the media map folder, so
// the triage edits of Tasks 1.2 to 4.3 can never turn it red. _meta.inputs_sha256 enforces that.
//
// Contract checked by --check (every failing point is printed, with its id):
//   C1 containment: every recomputed picture-set id has a picture_checked entry and every recomputed
//      identity-set id an identity_checked entry; EXTRA entries are legal.
//   C2 a frozen-low row of the population has a picture_checked record XOR hold.class low_confidence;
//      a low_confidence hold exists only on a frozen-low row.
//   C3 hold.class picture iff ANY entry of the row says action hold.
//   C4 every entry has a non-empty seen and an action in {unchanged, edited, hold, none}; none only
//      for a row with no animation.
//   C5 every hold has class in {token, name_collision, low_confidence, picture}, a reason, an owner.
//   C6 the derived _meta counts equal a recomputation, and _meta.inputs_sha256 matches.

'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'scripts', 'data', 'library_batch_c_source.json');
const MEDIA = path.join(ROOT, 'scripts', 'data', 'library_batch_c_media_map.json');
const LIB = path.join(ROOT, 'assets', 'data', 'exercise_library.json');

const META_DROP = ['_src', '_status', '_gif', '_folder', '_decision', '_decision_by', '_coreAdded', '_comment'];
// The vocabulary's own aliases (lib/core/utils/equipment_vocab.dart: 'landmine', 'landmine attachment',
// 'weight plate'); Task 4.2 checks the mapping against Dart for every shipped, un-edited row.
const ALIASES = { 'weight plate': 'dumbbells', 'landmine': 'barbell', 'landmine attachment': 'barbell' };
// Raw tokens that map to nothing in EquipmentVocab: Batch D owns them.
const UNMAPPED_TOKENS = ['dip belt', 'gymnastic rings', 'grip trainer', 'balance board', 'yoga strap', 'wrist roller'];
const HOLD_CLASSES = ['token', 'name_collision', 'low_confidence', 'picture'];
const HOLD_OWNERS = ['Batch D', 'C2', 'founder GIF review', 'founder'];
const ACTIONS = ['unchanged', 'edited', 'hold', 'none'];
// OFF-experiment (993-row base, 998 personas, 2026-10-25): the top-20 new ids by pick count. Every id with
// at least 100 picks is in this list (the 21st and later have fewer than 64).
const OFF_PICKS = {
  G0845: 5966, G0380: 3938, G0285: 3166, G1373: 1398, G0007: 1312, G0200: 1064, G0974: 1026, G1013: 946,
  G0293: 706, G1297: 428, G0710: 232, G0088: 224, G0409: 208, G0311: 196, G0299: 174, G0339: 94,
  G0988: 78, G0661: 66, G0983: 66, G0340: 64,
};

const CRITERION = {
  bw: ['none', 'bodyweight', 'wall', 'towel', 'doorway', 'elevated surface', 'chair', 'floor', 'table', 'stairs', 'foot anchor'],
  doubt: { source: 'check|assum|draft|unclear|ambig|probably|likely|guess|could be|verify|trusted', flags: 'i' },
  kit: {
    source: 'draft (said|equipment|was)|equipment draft|needs a|requires a|normally .* on (rings|bars)|cable|machine|station|pole|rail|\\bbar\\b|bench|towel|band|step|chair|door|plate|dumbbell|weight',
    flags: 'i',
  },
  strong: { source: 'guess|could be|could also|unclear|ambig|not sure|probably|or maybe|might be|uncertain', flags: 'i' },
  identityNote: { source: 'renam|founder|trusted', flags: 'i' },
  fold: [['pushup', 'push up'], ['situp', 'sit up'], ['pullup', 'pull up'], ['chinup', 'chin up']],
  equipmentStoplist: ['machine', 'band', 'cable', 'dumbbell', 'barbell', 'smith', 'ez', 'bar', 'kettlebell', 'weighted',
    'assisted', 'bodyweight', 'plate', 'loaded', 'banded', 'suspended', 'lever'],
  top20: ['G0845', 'G0380', 'G0285', 'G1373', 'G0007', 'G0200', 'G0974', 'G1013', 'G0293', 'G1297',
    'G0710', 'G0088', 'G0409', 'G0311', 'G0299', 'G0339', 'G0988', 'G0661', 'G0983', 'G0340'],
};

// ---------- helpers ----------
function canon(v) {
  if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
  if (v && typeof v === 'object') {
    return '{' + Object.keys(v).sort().map((k) => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}';
  }
  return JSON.stringify(v);
}
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const writeJson = (p, o) => fs.writeFileSync(p, JSON.stringify(o, null, 2) + '\n');
const rx = (o) => new RegExp(o.source, o.flags);

function inPopulation(row) {
  return !row.hold || row.hold.class === 'low_confidence' || row.hold.class === 'picture';
}

function folded(c, s) {
  let t = String(s || '').toLowerCase().replace(/\(.*?\)/g, ' ');
  for (const [a, b] of c.fold) t = t.split(a).join(b);
  return t.replace(/[^a-z ]/g, ' ').replace(/\s+/g, ' ').trim();
}
function toks(c, s) {
  const stop = new Set(c.equipmentStoplist);
  return new Set(folded(c, s).split(' ').filter((x) => x && !stop.has(x)).map((x) => x.replace(/s$/, '')));
}
function folderDisagrees(c, name, folder) {
  if (!folder) return false;
  const a = toks(c, name);
  const b = toks(c, folder);
  return [...a].some((x) => !b.has(x)) || [...b].some((x) => !a.has(x));
}

// The criterion: returns { picture:Set, identity:Set, parts } over the population, from FROZEN inputs.
function computeSets(src, media) {
  const c = src._meta.criterion;
  const inp = src._meta.criterion_inputs;
  const bw = new Set(c.bw);
  const doubt = rx(c.doubt);
  const kit = rx(c.kit);
  const strong = rx(c.strong);
  const idNote = rx(c.identityNote);
  const bwOnly = (eq) => eq.every((e) => bw.has(e));
  const parts = { A: new Set(), B: new Set(), C: new Set(), D: new Set(), E: new Set(), F: new Set(), G: new Set(), H: new Set() };
  const pop = src.rows.filter(inPopulation);
  for (const r of pop) {
    const f = inp[r.id];
    const low = f.confidence === 'low';
    const core = f.core_levels.length > 0;
    const note = r.note || '';
    if (low && (bwOnly(f.equipment_needed) || core || c.top20.includes(r.id))) parts.A.add(r.id);
    if (folderDisagrees(c, f.name, (media[r.id] || {})._folder)) parts.B.add(r.id);
    if (!low && bwOnly(f.equipment_needed) && kit.test(note)) parts.C.add(r.id);
    if (c.top20.includes(r.id) && doubt.test(note)) parts.D.add(r.id);
    if (core && f.confidence !== 'high') parts.E.add(r.id);
    if (r.changes && Object.keys(r.changes).some((k) => !k.startsWith('core_levels_'))) parts.F.add(r.id);
    if (idNote.test(note)) parts.G.add(r.id);
  }
  const identity = new Set([...parts.F, ...parts.G]);
  const pictureAE = new Set([...parts.A, ...parts.B, ...parts.C, ...parts.D, ...parts.E]);
  for (const r of pop) {
    const f = inp[r.id];
    if (f.confidence !== 'low' && !pictureAE.has(r.id) && !identity.has(r.id) && strong.test(r.note || '')) parts.H.add(r.id);
  }
  const picture = new Set([...pictureAE, ...parts.H]);
  return { picture, identity, parts, population: pop };
}

function derived(src) {
  const held = { token: 0, name_collision: 0, low_confidence: 0, picture: 0 };
  for (const r of src.rows) if (r.hold && held[r.hold.class] !== undefined) held[r.hold.class]++;
  const shipped = src.rows.filter((r) => !r.hold);
  const core = { beginner: 0, intermediate: 0, advanced: 0, rows: 0 };
  for (const r of shipped) {
    const l = r.core_levels || [];
    if (l.length) core.rows++;
    for (const x of l) if (core[x] !== undefined) core[x]++;
  }
  return { rows: src.rows.length, held, shipped: shipped.length, core };
}

function inputsHash(src, media) {
  const rows = {};
  for (const r of src.rows) rows[r.id] = { note: r.note === undefined ? null : r.note, changes: r.changes === undefined ? null : r.changes };
  return sha(canon({ criterion: src._meta.criterion, criterion_inputs: src._meta.criterion_inputs, rows, media }));
}

// ---------- --init ----------
function init(mergedPath) {
  if (fs.existsSync(SRC)) throw new Error('refusing to overwrite ' + SRC);
  const raw = fs.readFileSync(mergedPath);
  const merged = JSON.parse(raw.toString('utf8'));
  const lib = readJson(LIB);
  const libIds = new Set(lib.map((r) => r.id));
  const discard = new Set(merged.filter((r) => r._decision === 'discard').map((r) => r.key));
  const libByName = new Map(lib.map((r) => [r.name.toLowerCase(), r.id]));
  const keep = merged.filter((r) => r._decision === 'keep' && !libIds.has(r.key));
  const rows = [];
  const media = {};
  const criterionInputs = {};
  const aliasApplied = {};
  const collisions = [];
  for (const m of keep) {
    const row = {};
    for (const [k, v] of Object.entries(m)) {
      if (META_DROP.includes(k)) continue;
      row[k === 'key' ? 'id' : k] = v;
    }
    const id = m.key;
    const mm = {};
    if (m._gif) mm._gif = m._gif;
    if (m._folder) mm._folder = m._folder;
    media[id] = mm;
    const orig = row.equipment_needed || [];
    const mapped = [];
    for (const t of orig) {
      const u = ALIASES[String(t).toLowerCase()] || t;
      if (!mapped.includes(u)) mapped.push(u);
    }
    if (JSON.stringify(mapped) !== JSON.stringify(orig)) {
      aliasApplied[id] = orig;
      row.equipment_needed = mapped;
    }
    const unmapped = (row.equipment_needed || []).filter((t) => UNMAPPED_TOKENS.includes(String(t).toLowerCase()));
    if (unmapped.length) {
      row.hold = { class: 'token', reason: 'raw equipment token ' + unmapped.join(', ') + ' maps to nothing in EquipmentVocab; Batch D owns the tokens', owner: 'Batch D' };
    } else {
      const libId = libByName.get(String(row.name).toLowerCase());
      if (libId) {
        if (!discard.has(libId)) {
          collisions.push(id + ' collides with KEPT library row ' + libId);
        } else {
          row.hold = { class: 'name_collision', reason: 'same name as ' + libId + ', which the sheet marks drop; added by C2 together with the removal', owner: 'C2' };
        }
      }
    }
    criterionInputs[id] = {
      name: row.name,
      equipment_needed: row.equipment_needed,
      core_levels: row.core_levels || [],
      confidence: row.confidence,
    };
    rows.push(row);
  }
  if (collisions.length) throw new Error('name collisions with kept library rows: ' + collisions.join('; '));
  const src = {
    _meta: {
      merged_sha256: sha(raw),
      criterion: CRITERION,
      criterion_inputs: criterionInputs,
      inputs_sha256: '',
      alias_applied: aliasApplied,
      off_experiment_picks: OFF_PICKS,
      picture_checked: {},
      identity_checked: {},
      identical_cues_ok: {},
      family_exception: {},
      derived: null,
    },
    rows,
  };
  src._meta.inputs_sha256 = inputsHash(src, media);
  src._meta.derived = derived(src);
  fs.mkdirSync(path.dirname(SRC), { recursive: true });
  writeJson(MEDIA, media);
  writeJson(SRC, src);
  console.log('init: wrote', rows.length, 'rows; holds', JSON.stringify(src._meta.derived.held), 'alias_applied', Object.keys(aliasApplied).length);
}

// ---------- --write ----------
function write() {
  const src = readJson(SRC);
  const media = readJson(MEDIA);
  const { picture, identity, population } = computeSets(src, media);
  const m = src._meta;
  let stubs = 0;
  for (const id of picture) if (!m.picture_checked[id]) { m.picture_checked[id] = { seen: '', action: '' }; stubs++; }
  for (const id of identity) if (!m.identity_checked[id]) { m.identity_checked[id] = { seen: '', action: '' }; stubs++; }
  let holds = 0;
  for (const r of population) {
    if (m.criterion_inputs[r.id].confidence === 'low' && !m.picture_checked[r.id] && !r.hold) {
      r.hold = { class: 'low_confidence', reason: 'low-confidence draft with no picture read; the drafted identity is unchecked', owner: 'founder GIF review' };
      holds++;
    }
  }
  m.derived = derived(src);
  writeJson(SRC, src);
  const lowIdOnly = population.filter((r) => m.criterion_inputs[r.id].confidence === 'low' && identity.has(r.id) && !picture.has(r.id)).map((r) => r.id);
  console.log('write: population', population.length, 'picture', picture.size, 'identity', identity.size,
    'stubs added', stubs, 'low_confidence holds added', holds, 'derived', JSON.stringify(m.derived));
  if (lowIdOnly.length) console.log('NOTE low rows in the identity set only (they need a picture_checked record or stay held):', lowIdOnly.join(','));
}

// ---------- --check ----------
function check() {
  const src = readJson(SRC);
  const media = readJson(MEDIA);
  const m = src._meta;
  const fails = {};
  const fail = (pt, msg) => { (fails[pt] = fails[pt] || []).push(msg); };
  const ids = new Set(src.rows.map((r) => r.id));
  if (ids.size !== src.rows.length) fail('C5', 'duplicate ids in rows');
  const { picture, identity, population } = computeSets(src, media);
  const byId = new Map(src.rows.map((r) => [r.id, r]));

  // C1
  for (const id of picture) if (!(m.picture_checked || {})[id]) fail('C1', 'picture set id without picture_checked entry: ' + id);
  for (const id of identity) if (!(m.identity_checked || {})[id]) fail('C1', 'identity set id without identity_checked entry: ' + id);
  // C4
  for (const [file, rec] of [['picture_checked', m.picture_checked || {}], ['identity_checked', m.identity_checked || {}]]) {
    for (const [id, e] of Object.entries(rec)) {
      if (!ids.has(id)) { fail('C4', file + ' entry for unknown id ' + id); continue; }
      if (typeof e.seen !== 'string' || e.seen.trim() === '') fail('C4', file + '[' + id + '].seen is empty');
      if (!ACTIONS.includes(e.action)) fail('C4', file + '[' + id + '].action is not one of ' + ACTIONS.join('/') + ': ' + JSON.stringify(e.action));
      if (e.action === 'none' && (media[id] || {})._gif) fail('C4', file + '[' + id + '] action none on a row that has an animation');
    }
  }
  // C5
  for (const r of src.rows) {
    if (!r.hold) continue;
    if (!HOLD_CLASSES.includes(r.hold.class)) fail('C5', r.id + ' hold.class ' + JSON.stringify(r.hold.class));
    if (typeof r.hold.reason !== 'string' || r.hold.reason.trim() === '') fail('C5', r.id + ' hold without reason');
    if (!HOLD_OWNERS.includes(r.hold.owner)) fail('C5', r.id + ' hold.owner ' + JSON.stringify(r.hold.owner));
  }
  // C2
  for (const r of population) {
    const low = m.criterion_inputs[r.id].confidence === 'low';
    const hasPic = !!(m.picture_checked || {})[r.id];
    const lowHold = !!r.hold && r.hold.class === 'low_confidence';
    if (low && hasPic === lowHold) fail('C2', r.id + ' frozen-low: picture_checked record ' + hasPic + ' and low_confidence hold ' + lowHold + ' must differ');
    if (!low && lowHold) fail('C2', r.id + ' low_confidence hold on a row that is not frozen-low');
  }
  // C3
  const holdAction = new Set();
  for (const rec of [m.picture_checked || {}, m.identity_checked || {}]) {
    for (const [id, e] of Object.entries(rec)) if (e.action === 'hold') holdAction.add(id);
  }
  for (const id of holdAction) {
    const r = byId.get(id);
    if (r && !(r.hold && r.hold.class === 'picture')) fail('C3', id + ' has an entry with action hold but hold.class is not picture');
  }
  for (const r of src.rows) {
    if (r.hold && r.hold.class === 'picture' && !holdAction.has(r.id)) fail('C3', r.id + ' hold.class picture but no entry says action hold');
  }
  // C6
  const d = derived(src);
  if (canon(d) !== canon(m.derived)) fail('C6', 'derived counts are stale: recomputed ' + canon(d) + ' recorded ' + canon(m.derived) + ' (run --write)');
  const h = inputsHash(src, media);
  if (h !== m.inputs_sha256) fail('C6', 'inputs_sha256 mismatch: recomputed ' + h + ' (a deliberate change to a hashed input is re-pinned by pasting this value)');

  console.log('check: population', population.length, '| picture set', picture.size, '| identity set', identity.size,
    '| held', JSON.stringify(d.held), '| shipped', d.shipped, '| core', JSON.stringify(d.core));
  const pts = Object.keys(fails).sort();
  if (!pts.length) { console.log('check: OK (C1 to C6)'); return 0; }
  for (const p of pts) {
    console.log('FAIL ' + p + ' (' + fails[p].length + ')');
    for (const x of fails[p].slice(0, 20)) console.log('  - ' + x);
    if (fails[p].length > 20) console.log('  ... ' + (fails[p].length - 20) + ' more');
  }
  return 1;
}

function main() {
  const [mode, arg] = process.argv.slice(2);
  if (mode === '--init') { if (!arg) throw new Error('--init needs the path to merged.json'); init(arg); return 0; }
  if (mode === '--write') { write(); return 0; }
  if (mode === '--check') return check();
  console.error('usage: library_batch_c_scope.js --init <merged.json> | --write | --check');
  return 2;
}

process.exit(main());
