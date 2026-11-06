#!/usr/bin/env node
// Regression test for emit_payload.js's payloadName() naming scheme.
// diagnose a2b2f1 — the old scheme named EVERY non-entry file
// `../<path-relative-to-functions-dir>` unconditionally, which broke any
// function with a same-directory sibling of index.ts (e.g. `./message.ts`
// in protein-gap-alert): it deployed as `../<fn-name>/message.ts` (a
// sibling of `source/`) instead of `message.ts` (inside `source/`, where
// index.ts's own `./message.ts` import actually looks), and Deno's bundler
// rejected it with "Module not found .../source/message.ts".
//
// Black-box test: builds a small fixture function directory with both
// shapes (a same-dir sibling AND a `_shared/` file one level up), runs the
// REAL CLI against it, and asserts both resulting payload names.
//
// Run: node .claude/emit_payload_payloadname_test.js
// Exits 0 on pass, 1 on fail (prints which assertion failed).

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'emit_payload_test_'));
let failures = 0;

function assertEqual(actual, expected, label) {
  if (actual !== expected) {
    failures++;
    console.error(`FAIL: ${label}\n  expected: ${expected}\n  actual:   ${actual}`);
  } else {
    console.log(`PASS: ${label}`);
  }
}

try {
  const functionsDir = path.join(tmpRoot, 'functions');
  const fnDir = path.join(functionsDir, 'fixture-fn');
  const sharedDir = path.join(functionsDir, '_shared');
  fs.mkdirSync(fnDir, { recursive: true });
  fs.mkdirSync(sharedDir, { recursive: true });

  // A same-directory sibling of index.ts (the shape that broke).
  fs.writeFileSync(
    path.join(fnDir, 'message.ts'),
    'export const greeting = "hi";\n',
  );
  // A `_shared/` file one level up (the shape that already worked).
  fs.writeFileSync(
    path.join(sharedDir, 'util.ts'),
    'export const helper = () => 1;\n',
  );
  fs.writeFileSync(
    path.join(fnDir, 'index.ts'),
    [
      'import { greeting } from "./message.ts";',
      'import { helper } from "../_shared/util.ts";',
      'console.log(greeting, helper());',
      '',
    ].join('\n'),
  );

  const scriptPath = path.join(__dirname, 'emit_payload.js');
  execFileSync(
    process.execPath,
    [scriptPath, 'fixture-fn', '--auto', '--functions-dir', functionsDir],
    { cwd: __dirname, stdio: 'pipe' },
  );

  const payloadPath = path.join(__dirname, '_payload_fixture-fn.json');
  const files = JSON.parse(fs.readFileSync(payloadPath, 'utf-8'));
  const names = files.map((f) => f.name).sort();

  assertEqual(names.includes('index.ts'), true, 'entry file named index.ts');
  assertEqual(
    names.includes('message.ts'),
    true,
    'same-directory sibling named bare "message.ts" (not "../fixture-fn/message.ts")',
  );
  assertEqual(
    names.includes('../_shared/util.ts'),
    true,
    '_shared file still climbs out with "../_shared/util.ts"',
  );

  fs.unlinkSync(payloadPath);
} finally {
  fs.rmSync(tmpRoot, { recursive: true, force: true });
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
}
console.log('\nAll assertions passed.');
