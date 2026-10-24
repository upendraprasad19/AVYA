#!/usr/bin/env node
// Regression test for deploy_via_api.js's emitPayloadAtSha() naming scheme
// (the --rollback git-SHA path).
//
// diagnose a2b2f1 — this function is a deliberate inline duplicate of
// emit_payload.js's payloadName() scheme (so both surfaces reconstruct a
// byte-identical payload for the same SHA), and it carried the IDENTICAL
// bug: every non-entry file was unconditionally named
// `../<path-relative-to-functions-dir>`, which breaks any function with a
// same-directory sibling of index.ts. A rollback of protein-gap-alert (or
// morning-alert/plateau-alert/pr-detection/re-engagement/streak-guardian/
// workout-window-closing/future-prediction/proactive-coach-promotion) would
// have deployed a payload Deno's bundler rejects with "Module not found
// .../source/message.ts" — the same failure shape emit_payload.js produced
// forward, just reached via the rollback path instead.
//
// This is a BLACK-BOX subprocess test, not a synthetic fixture, because
// emitPayloadAtSha() reads via `git show <sha>:<path>` against this
// script's own REPO_ROOT (`path.resolve(__dirname, '..')`, hardcoded, not
// configurable) — a temp git repo fixture would test nothing about the real
// function. Per CLAUDE.md's own "confirm the FIXTURE reproduces a state the
// real workflow actually produces" lesson, this uses REAL committed content
// at the current HEAD: protein-gap-alert/index.ts today imports BOTH a
// same-directory sibling (`./message.ts`) and several `_shared/` files one
// level up (`../_shared/...`), so one real commit exercises both naming
// branches.
//
// Run: node .claude/deploy_via_api_rollback_payloadname_test.js
// Exits 0 on pass, 1 on fail (prints which assertion failed).

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const REPO_ROOT = path.resolve(__dirname, '..');
let failures = 0;

function assertEqual(actual, expected, label) {
  if (actual !== expected) {
    failures++;
    console.error(`FAIL: ${label}\n  expected: ${expected}\n  actual:   ${actual}`);
  } else {
    console.log(`PASS: ${label}`);
  }
}

function assertTrue(cond, label) {
  if (!cond) {
    failures++;
    console.error(`FAIL: ${label}`);
  } else {
    console.log(`PASS: ${label}`);
  }
}

const headSha = execFileSync('git', ['rev-parse', 'HEAD'], {
  cwd: REPO_ROOT,
  encoding: 'utf-8',
}).trim();
const shortSha = headSha.slice(0, 7);
const fnName = 'protein-gap-alert';
const payloadPath = path.join(__dirname, `_payload_${fnName}_rollback_${shortSha}.json`);

try {
  // Sanity-check the fixture assumption itself before trusting the tool's
  // output against it — the real, LIVE bug class this file's own
  // CLAUDE.md common-pitfalls table warns about is asserting against a
  // fictional or stale fixture.
  const realIndexSource = execFileSync(
    'git',
    ['show', `${headSha}:supabase/functions/${fnName}/index.ts`],
    { cwd: REPO_ROOT, encoding: 'utf-8' },
  );
  assertTrue(
    realIndexSource.includes('from "./message.ts"'),
    `fixture assumption: ${fnName}/index.ts at HEAD imports a same-directory sibling`,
  );
  assertTrue(
    realIndexSource.includes('from "../_shared/'),
    `fixture assumption: ${fnName}/index.ts at HEAD also imports at least one _shared/ file`,
  );

  const scriptPath = path.join(__dirname, 'deploy_via_api.js');
  execFileSync(
    process.execPath,
    [scriptPath, '--rollback', fnName, headSha, '--dry-run', '--yes'],
    { cwd: __dirname, stdio: 'pipe' },
  );

  assertTrue(fs.existsSync(payloadPath), `rollback payload written to ${payloadPath}`);
  const files = JSON.parse(fs.readFileSync(payloadPath, 'utf-8'));
  const names = files.map((f) => f.name).sort();

  assertTrue(names.includes('index.ts'), 'entry file named index.ts');
  assertTrue(
    names.includes('message.ts'),
    'same-directory sibling named bare "message.ts" (not "../protein-gap-alert/message.ts")',
  );
  assertTrue(
    names.some((n) => n.startsWith('../_shared/')),
    '_shared file still climbs out with "../_shared/..."',
  );
  assertTrue(
    !names.some((n) => n === `../${fnName}/message.ts`),
    'the OLD buggy name ("../<fn>/message.ts") must not appear',
  );
} finally {
  if (fs.existsSync(payloadPath)) fs.unlinkSync(payloadPath);
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
}
console.log('\nAll assertions passed.');
