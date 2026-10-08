// scripts/generate_food_tag_review.dart
//
// Diet-plan meal-quality batch (2026-09-17): heuristic pre-classifier +
// founder HTML review page for the two new food_database.json fields:
//   meal_fit           — List<String> from {breakfast, lunch, dinner, snack}
//   is_ultra_processed — bool
//
// Usage:
//   dart run scripts/generate_food_tag_review.dart
//
// Outputs (NOT committed):
//   C:\Users\upend\Downloads\food_database_tagged_draft.json  — heuristic draft
//   C:\Users\upend\Downloads\food_tag_review.html             — editable review page
//
// The founder reviews/edits the HTML page and exports the final JSON. The
// export is validated by scripts/validate_food_tag_export.dart BEFORE the
// asset is replaced. Heuristic guesses are a STARTING POINT only — the
// pinned spot-check tests (test/nutrition/food_database_tagged_test.dart)
// are the floor, the founder's review is the authority.

import 'dart:convert';
import 'dart:io';

const _outputDir = r'C:\Users\upend\Downloads';

// Word-scoped where a loose substring would misfire (e.g. 'lay' matches
// 'Layered' — live proof in the DB: "Mayora Malkist ... Layered ...").
// Apostrophes normalized before matching.
const _upfKeywords = <String>[
  'pringles', 'maggi', "lay's", 'lays', 'kurkure', 'doritos', 'balaji',
  'wafers', 'ferrero', 'oreo', 'snickers', 'kitkat', 'dairy milk',
  'special k', 'kellogg', 'chocos', 'cornflakes', 'muesli', 'granola',
  'knorr', 'haldiram', 'mayora', 'malkist', 'cracker biscuit', 'biscuit',
  'bournvita', 'horlicks', 'complan', 'boost', 'pepsi', 'coca cola',
  'coke', 'sprite', 'fanta', 'mountain dew', 'red bull', 'stinger',
  'mcdonald', 'kfc', 'domino', 'pizza hut', 'burger king', 'subway',
  'chips', 'nachos', 'instant noodles', 'instant pasta', 'candy',
  'jelly', 'gum', 'soft drink', 'sausage', 'salami', 'bacon',
  // added post founder-review (real-DB debug run caught these leaking
  // into plans — see diagnose d3c7a9 residual notes)
  'milkybar', 'nestle', 'smith & jones', 'yoga bar', 'pintos', 'jaouda',
  'protein bar', 'dark chocolate',
];

const _breakfastStapleKeywords = <String>[
  'idli', 'dosa', 'poha', 'upma', 'oats', 'porridge', 'paratha',
  'pancake', 'cereal', 'bread', 'sandwich', 'toast', 'omelette',
  'uttapam', 'dhokla', 'thepla', 'puri',
];

const _dairyBreakfastNames = <String>[
  'milk', 'curd', 'yogurt', 'chaas', 'buttermilk', 'lassi', 'paneer',
  'cheese', 'whey', 'shake',
];

String _normalize(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r"['’]"), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _wordMatch(String normalized, String keyword) {
  final kw = _normalize(keyword);
  if (kw.contains(' ')) return normalized.contains(kw);
  return RegExp('\\b${RegExp.escape(kw)}').hasMatch(normalized);
}

bool _heuristicIsUpf(Map<String, dynamic> row) {
  final category = (row['category'] as String? ?? '').toLowerCase();
  final name = _normalize(row['name'] as String? ?? '');
  if (category == 'packaged' || category == 'sweets') return true;
  return _upfKeywords.any((kw) => _wordMatch(name, kw));
}

List<String> _heuristicMealFit(Map<String, dynamic> row) {
  final category = (row['category'] as String? ?? '').toLowerCase();
  final name = _normalize(row['name'] as String? ?? '');
  bool hasKw(List<String> kws) => kws.any((kw) => _wordMatch(name, kw));

  switch (category) {
    case 'vegetables':
      return ['lunch', 'dinner'];
    case 'fruits':
      return ['breakfast', 'snack'];
    case 'pulses':
      return ['lunch', 'dinner'];
    case 'nuts_seeds':
      return ['snack'];
    case 'sweets':
      return ['snack'];
    case 'restaurant':
    case 'street_food':
      return ['lunch', 'dinner'];
    case 'supplements':
      return ['snack'];
    case 'beverages':
      if (hasKw(['protein shake', 'whey'])) return ['breakfast', 'snack'];
      if (hasKw(['chai', 'coffee', 'tea'])) return ['breakfast', 'snack'];
      return ['snack'];
    case 'dairy':
      if (hasKw(['ghee', 'butter'])) return ['breakfast', 'lunch', 'dinner'];
      if (hasKw(['cheese'])) return ['snack'];
      if (hasKw(_dairyBreakfastNames)) return ['breakfast', 'snack'];
      return ['breakfast', 'snack'];
    case 'protein':
      if (hasKw(['egg'])) return ['breakfast'];
      return ['lunch', 'dinner'];
    case 'staples':
    case 'packaged':
    default:
      final slots = <String>['lunch', 'dinner'];
      if (hasKw(_breakfastStapleKeywords)) slots.add('breakfast');
      return slots;
  }
}

void main() {
  final asset = File('assets/data/food_database.json');
  if (!asset.existsSync()) {
    stderr.writeln('FATAL: assets/data/food_database.json not found — run from repo root.');
    exit(1);
  }
  final rows = (jsonDecode(asset.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  if (rows.isEmpty) {
    stderr.writeln('FATAL: food_database.json is empty.');
    exit(1);
  }

  var upfCount = 0;
  for (final row in rows) {
    final upf = _heuristicIsUpf(row);
    row['is_ultra_processed'] = upf;
    if (upf) upfCount++;
    row['meal_fit'] = _heuristicMealFit(row);
  }

  Directory(_outputDir).createSync(recursive: true);

  final draftPath = '$_outputDir\\food_database_tagged_draft.json';
  File(draftPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(rows));
  stdout.writeln('Draft tagged JSON : $draftPath ($upfCount/${rows.length} rows flagged UPF)');

  final html = _buildHtml(rows, upfCount);
  final htmlPath = '$_outputDir\\food_tag_review.html';
  File(htmlPath).writeAsStringSync(html);
  stdout.writeln('Review page       : $htmlPath');
  stdout.writeln('');
  stdout.writeln('NEXT: open the HTML in a browser, glance over the tags, fix what');
  stdout.writeln('the heuristics got wrong, then Export JSON and tell the agent the');
  stdout.writeln('export path. The agent runs scripts/validate_food_tag_export.dart');
  stdout.writeln('before the asset is replaced.');
}

String _buildHtml(List<Map<String, dynamic>> rows, int upfCount) {
  final payload = jsonEncode(rows.map((r) {
    final servingG = (r['standard_serving_g'] as num?)?.toDouble() ?? 100.0;
    final kcal100 = (r['calories_per_100g'] as num?)?.toDouble() ?? 0.0;
    return {
      'id': r['id'],
      'name': r['name'],
      'category': r['category'],
      'serving': '${r['standard_serving_desc']} (${(servingG).round()}g)',
      'kcalSrv': (kcal100 * servingG / 100).round(),
      'upf': r['is_ultra_processed'] as bool,
      'meal_fit': r['meal_fit'] as List,
    };
  }).toList());

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>ICANBEFITTER — Food DB Tag Review (meal_fit + UPF)</title>
<style>
  :root { color-scheme: dark; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; background:#02070F; color:#E8ECF4; margin:0; padding:16px; }
  h1 { font-size:18px; color:#D4B270; margin:0 0 4px; }
  .sub { color:#8B97A8; font-size:13px; margin-bottom:12px; }
  .toolbar { position:sticky; top:0; background:#02070F; padding:8px 0; z-index:5; display:flex; gap:8px; flex-wrap:wrap; align-items:center; border-bottom:1px solid #1A2A40; }
  input[type=text], select { background:#0E1E30; color:#E8ECF4; border:1px solid #24354D; border-radius:6px; padding:6px 10px; font-size:13px; }
  .counts { font-size:12px; color:#8B97A8; margin-left:auto; }
  table { width:100%; border-collapse:collapse; font-size:12.5px; }
  th { text-align:left; color:#D4B270; border-bottom:1px solid #24354D; padding:6px 8px; position:sticky; top:52px; background:#06101F; z-index:4; }
  td { border-bottom:1px solid #101D30; padding:5px 8px; vertical-align:top; }
  tr:hover td { background:#06101F; }
  .upf-yes { color:#FF7B72; font-weight:700; cursor:pointer; user-select:none; }
  .upf-no { color:#7EE787; font-weight:700; cursor:pointer; user-select:none; }
  .mf { display:inline-block; background:#0E1E30; border:1px solid #24354D; border-radius:10px; padding:1px 8px; margin:1px 2px; cursor:pointer; user-select:none; font-size:11px; color:#8B97A8; }
  .mf.on { background:#D4B270; color:#02070F; border-color:#D4B270; font-weight:700; }
  .btn { background:#D4B270; color:#02070F; border:0; border-radius:8px; padding:8px 18px; font-weight:800; font-size:13px; cursor:pointer; }
  .btn:hover { filter:brightness(1.1); }
  .hint { color:#8B97A8; font-size:12px; }
  kbd { background:#0E1E30; border:1px solid #24354D; border-radius:4px; padding:0 5px; font-size:11px; }
</style>
</head>
<body>
<h1>Food DB Tag Review — meal_fit + is_ultra_processed</h1>
<div class="sub">Heuristic pre-fill of ${rows.length} rows · <b style="color:#FF7B72">$upfCount flagged UPF</b> · Glance over, fix what's wrong, click Export JSON.
Click a <span class="upf-yes">UPF</span> cell to toggle · click slot chips to toggle meal_fit. Edits are tracked live; Export always downloads the FULL row set.</div>
<div class="toolbar">
  <input type="text" id="q" placeholder="Search name…" oninput="render()">
  <select id="cat" onchange="render()"><option value="">All categories</option></select>
  <select id="view" onchange="render()">
    <option value="all">All rows</option>
    <option value="upf">UPF-flagged only</option>
    <option value="nonupf">Non-UPF only</option>
  </select>
  <span class="counts" id="counts"></span>
  <button class="btn" onclick="exportJson()">Export JSON</button>
</div>
<div class="hint" style="margin:8px 0">Export → save as <b>food_database_tagged_final.json</b> → give the path to the agent (default: Downloads folder).</div>
<table>
<thead><tr><th style="width:32%">Name</th><th>Category</th><th>Serving</th><th>kcal/srv</th><th>UPF (click)</th><th>meal_fit (click chips)</th></tr></thead>
<tbody id="tb"></tbody>
</table>
<script>
const ROWS = ${payload};
const SLOTS = ['breakfast','lunch','dinner','snack'];
const edited = new Set();
const norm = s => s.toLowerCase().replace(/['\u2019]/g,'');

const catSel = document.getElementById('cat');
[...new Set(ROWS.map(r=>r.category))].sort().forEach(c=>{ const o=document.createElement('option'); o.value=c; o.textContent=c; catSel.appendChild(o); });

function render(){
  const q = norm(document.getElementById('q').value);
  const cat = document.getElementById('cat').value;
  const view = document.getElementById('view').value;
  const tb = document.getElementById('tb');
  tb.innerHTML = '';
  let shown = 0, upfShown = 0;
  for (const r of ROWS){
    if (q && !norm(r.name).includes(q)) continue;
    if (cat && r.category !== cat) continue;
    if (view==='upf' && !r.upf) continue;
    if (view==='nonupf' && r.upf) continue;
    shown++; if (r.upf) upfShown++;
    const tr = document.createElement('tr');
    // IDs are quote-free by construction (seed Fnnnn / uuid) — plain
    // interpolation; JSON.stringify would emit double quotes INSIDE the
    // double-quoted onclick attribute and silently kill every handler.
    const chips = SLOTS.map(s => `<span class="mf \${r.meal_fit.includes(s)?'on':''}" onclick="toggleFit('\${r.id}', '\${s}')">\${s}</span>`).join('');
    tr.innerHTML = `<td>\${r.name}</td><td>\${r.category}</td><td>\${r.serving}</td><td>\${r.kcalSrv}</td>
      <td class="\${r.upf?'upf-yes':'upf-no'}" onclick="toggleUpf('\${r.id}')">\${r.upf?'UPF':'clean'}</td>
      <td>\${chips}</td>`;
    tb.appendChild(tr);
  }
  document.getElementById('counts').textContent = `\${shown} shown · \${upfShown} UPF · \${edited.size} edited`;
}
function toggleUpf(id){ const r=ROWS.find(x=>x.id===id); r.upf=!r.upf; edited.add(id); render(); }
function toggleFit(id,s){ const r=ROWS.find(x=>x.id===id); const i=r.meal_fit.indexOf(s); if(i>=0) r.meal_fit.splice(i,1); else { r.meal_fit.push(s); r.meal_fit.sort(); } edited.add(id); render(); }
function exportJson(){
  // Rebuild FULL rows: original asset fields + edited tags, original order.
  const out = SRC.map(row => {
    const e = ROWS.find(x=>x.id===row.id);
    if (!e) throw new Error('id mismatch: '+row.id);
    row.is_ultra_processed = e.upf;
    row.meal_fit = e.meal_fit.slice();
    return row;
  });
  const blob = new Blob([JSON.stringify(out, null, 2)], {type:'application/json'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'food_database_tagged_final.json';
  a.click();
  document.getElementById('counts').textContent = `\${edited.size} edited — EXPORTED`;
}
// Embed the original asset so export preserves every original field byte-exactly.
const SRC = ${jsonEncode(rows)};
render();
</script>
</body>
</html>''';
}
