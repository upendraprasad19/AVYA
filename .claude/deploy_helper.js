#!/usr/bin/env node
// Helper: Given a function name and shared deps list, read files from disk
// and emit a JSON object ready to paste into MCP deploy_edge_function's `files` array.
//
// Usage:
//   node deploy_helper.js <function_name> [shared_dep1] [shared_dep2] ...
//
// Example:
//   node deploy_helper.js ai-proxy embeddings openrouter

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const FUNCTIONS_DIR = path.join(ROOT, 'supabase', 'functions');

const [, , fnName, ...sharedDeps] = process.argv;
if (!fnName) {
  console.error('Usage: node deploy_helper.js <function_name> [shared_dep1] ...');
  process.exit(1);
}

const entry = path.join(FUNCTIONS_DIR, fnName, 'index.ts');
if (!fs.existsSync(entry)) {
  console.error('Entry file not found:', entry);
  process.exit(1);
}

const files = [
  { name: 'index.ts', content: fs.readFileSync(entry, 'utf-8') },
];

// Try two naming conventions — caller picks which works.
for (const dep of sharedDeps) {
  const p = path.join(FUNCTIONS_DIR, '_shared', `${dep}.ts`);
  if (!fs.existsSync(p)) {
    console.error('Shared dep not found:', p);
    process.exit(1);
  }
  files.push({ name: `../_shared/${dep}.ts`, content: fs.readFileSync(p, 'utf-8') });
}

// Write JSON array to a tmp file so we can Read it back cleanly.
const outPath = path.join(__dirname, `_deploy_payload_${fnName}.json`);
fs.writeFileSync(outPath, JSON.stringify(files, null, 2));
console.log('Wrote:', outPath);
console.log('Entry size:', files[0].content.length, 'chars');
for (let i = 1; i < files.length; i++) {
  console.log(`Shared ${files[i].name}:`, files[i].content.length, 'chars');
}
