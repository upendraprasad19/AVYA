#!/usr/bin/env node
// Emit the full JSON files array for an MCP `deploy_edge_function` call.
//
// Two modes:
//
//   AUTO-DISCOVER (preferred — recursively follows relative imports from
//   the entry index.ts and bundles every transitively referenced file
//   under <functions-dir>):
//
//     node emit_payload.js <fn-name> --auto \
//       [--functions-dir <path>]
//
//   MANUAL LIST (explicit space-separated paths, each RELATIVE to
//   <functions-dir>; entry index.ts is always added first):
//
//     node emit_payload.js <fn-name> --files \
//       _shared/gemini.ts _shared/tools/index.ts ... \
//       [--functions-dir <path>]
//
// Output: writes `_payload_<fn-name>.json` next to this script. Each
// file's content is BYTE-IDENTICAL to its on-disk source — no comment
// stripping, no whitespace compression. The whole point is to make the
// MCP deploy reproducible from git.
//
// Path-naming scheme (matches what ai-proxy v42 was deployed with):
//   - The entry file is always named `index.ts`.
//   - Every other file is named `../<path-relative-to-functions-dir>`.
//     E.g. `_shared/tools/workout/swapExercise.ts` →
//          `../_shared/tools/workout/swapExercise.ts`.

const fs = require('fs');
const path = require('path');

const DEFAULT_FUNCTIONS_DIR = path.resolve(
  __dirname,
  '..',
  'supabase',
  'functions',
);

function usage(msg) {
  if (msg) console.error('Error:', msg);
  console.error('');
  console.error('Usage:');
  console.error('  node emit_payload.js <fn-name> --auto [--functions-dir <path>]');
  console.error('  node emit_payload.js <fn-name> --files <path> [<path> ...] [--functions-dir <path>]');
  process.exit(1);
}

// ---- Argument parsing ------------------------------------------------------

const argv = process.argv.slice(2);
if (argv.length === 0) usage('missing <fn-name>');

const fnName = argv[0];
let mode = null; // 'auto' | 'files'
let manualFiles = [];
let functionsDir = DEFAULT_FUNCTIONS_DIR;

for (let i = 1; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--auto') {
    mode = 'auto';
  } else if (a === '--files') {
    mode = 'files';
    // Consume everything until the next flag (or end of argv).
    while (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
      manualFiles.push(argv[++i]);
    }
  } else if (a === '--functions-dir') {
    functionsDir = path.resolve(argv[++i]);
  } else {
    usage(`unknown argument: ${a}`);
  }
}

if (!mode) usage('one of --auto or --files is required');
if (!fs.existsSync(functionsDir) || !fs.statSync(functionsDir).isDirectory()) {
  usage(`functions dir not found: ${functionsDir}`);
}

const entryPath = path.join(functionsDir, fnName, 'index.ts');
if (!fs.existsSync(entryPath)) {
  usage(`entry file not found: ${entryPath}`);
}

// ---- Helpers ---------------------------------------------------------------

// Compute the payload "name" for a file — `index.ts` for the entry, and
// `../<path-from-functions-dir>` for everything else. We always emit
// forward slashes regardless of host OS (Deno/MCP expects POSIX-style).
function payloadName(absPath) {
  if (absPath === entryPath) return 'index.ts';
  const rel = path.relative(functionsDir, absPath).split(path.sep).join('/');
  return `../${rel}`;
}

// Parse all relative imports out of a TS source string. Captures the
// import specifier (the `"..."` payload). Skips:
//   - URL-style imports (https://, http://)
//   - bare specifiers (no leading `.`)
//   - `.d.ts` declaration files (Deno doesn't bundle them)
function findRelativeImports(source) {
  const out = [];
  // Matches `import ... from "..."`, `export ... from "..."`, and
  // bare `import "..."` side-effect imports.
  const re = /(?:from|import)\s+["']([^"']+)["']/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    const spec = m[1];
    if (!spec.startsWith('.')) continue; // bare or URL specifier
    if (spec.endsWith('.d.ts')) continue;
    out.push(spec);
  }
  return out;
}

function readFileSafe(p) {
  if (!fs.existsSync(p)) {
    console.error(`MISSING: ${p}`);
    process.exit(1);
  }
  return fs.readFileSync(p, 'utf-8');
}

// Recursively walk imports starting from `entryPath`. Returns an ordered
// array of absolute paths (entry first, then deps in discovery order).
function discover(entryPath) {
  const visited = new Set();
  const order = [];

  function walk(absPath) {
    if (visited.has(absPath)) return;
    visited.add(absPath);
    order.push(absPath);

    if (!absPath.endsWith('.ts')) return; // only parse TS files
    const src = readFileSafe(absPath);
    const dir = path.dirname(absPath);

    for (const spec of findRelativeImports(src)) {
      // Specifier MUST end in .ts (Deno requires explicit extensions for
      // local files). Skip silently if missing — the runtime would error
      // anyway, and we don't want to invent paths.
      if (!spec.endsWith('.ts')) {
        console.error(`SKIP (no .ts ext): ${spec} (in ${absPath})`);
        continue;
      }
      const resolved = path.resolve(dir, spec);
      // Sanity: resolved path must live under functionsDir. If it
      // escapes (e.g. ../../../etc/passwd), bail loudly.
      const relCheck = path.relative(functionsDir, resolved);
      if (relCheck.startsWith('..') || path.isAbsolute(relCheck)) {
        console.error(
          `SKIP (escapes functionsDir): ${spec} → ${resolved}`,
        );
        continue;
      }
      walk(resolved);
    }
  }

  walk(entryPath);
  return order;
}

// ---- Build the file list ---------------------------------------------------

let absPaths;

if (mode === 'auto') {
  absPaths = discover(entryPath);
} else {
  // Manual mode: entry first, then the explicit list.
  absPaths = [entryPath];
  for (const rel of manualFiles) {
    const abs = path.resolve(functionsDir, rel);
    if (!fs.existsSync(abs)) {
      console.error(`MISSING: ${abs}`);
      process.exit(1);
    }
    absPaths.push(abs);
  }
}

const files = absPaths.map((abs) => ({
  name: payloadName(abs),
  content: fs.readFileSync(abs, 'utf-8'), // BYTE-IDENTICAL — no transforms
}));

// ---- Write & report --------------------------------------------------------

const outPath = path.join(__dirname, `_payload_${fnName}.json`);
fs.writeFileSync(outPath, JSON.stringify(files));
const outSize = fs.statSync(outPath).size;

console.log('WROTE:', outPath);
console.log('FILE COUNT:', files.length);
console.log('PAYLOAD JSON SIZE:', outSize, 'bytes');

// Per-file sizes (sorted desc by content length).
const sized = files
  .map((f) => ({ name: f.name, bytes: Buffer.byteLength(f.content, 'utf-8') }))
  .sort((a, b) => b.bytes - a.bytes);

const totalContentBytes = sized.reduce((s, f) => s + f.bytes, 0);
console.log('TOTAL CONTENT SIZE:', totalContentBytes, 'bytes');
console.log('');
console.log('Files (largest first):');
for (const f of sized) {
  console.log(`  ${String(f.bytes).padStart(7)}  ${f.name}`);
}

// MCP size warnings — empirical thresholds.
if (outSize > 500 * 1024) {
  console.warn('');
  console.warn(`!! WARNING: payload ${outSize} bytes (>500KB) — MCP deploy will likely fail.`);
} else if (outSize > 200 * 1024) {
  console.warn('');
  console.warn(`!! NOTICE: payload ${outSize} bytes (>200KB) — approaching MCP practical limit.`);
}
