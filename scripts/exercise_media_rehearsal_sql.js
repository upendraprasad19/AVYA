#!/usr/bin/env node
'use strict';
// Composes the SQL text the Batch M1 rehearsal (plan Task 8.4) sends, so it is never assembled by hand.
//
//   node scripts/exercise_media_rehearsal_sql.js --file1   # FILE 1 with the migration body inserted TWICE at its marker
//   node scripts/exercise_media_rehearsal_sql.js --file2   # FILE 2 (it carries the migration body itself, pinned equal)
//
// The text goes to STDOUT, comments stripped (a comment is legal SQL, but the call is one MCP request and short is safer);
// nothing is written to disk. Nothing here contacts a database. The migration is whichever of the draft and the final
// supabase/migrations/NNN_exercise_media_bucket.sql exists (exactly one must).
//
// Why twice: the bucket does not exist before the apply, so the rehearsal runs the migration's DO body inside the
// always-aborting probe block. The second copy proves the DO UPDATE and the policy re-creation are idempotent.
// Exit 0 with the text on stdout, exit 2 on any shape problem (marker count, dollar-quote balance, missing file).

const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const FILE1 = 'test/sql/exercise_media_bucket_live_verify.sql';
const FILE2 = 'test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql';
const DRAFT = 'docs/plans/library-batch-m/exercise_media_bucket.sql.draft';
const MIGRATIONS = 'supabase/migrations';
const FINAL_RE = /^\d{3}[a-z]?_exercise_media_bucket\.sql$/;
const MARKER = '-- PRELUDE-INSERT-POINT';

class Problem extends Error {}

function migrationPath(root) {
  const found = [];
  const dir = path.join(root, MIGRATIONS);
  if (fs.existsSync(dir)) {
    for (const f of fs.readdirSync(dir)) if (FINAL_RE.test(f)) found.push(path.join(MIGRATIONS, f));
  }
  if (fs.existsSync(path.join(root, DRAFT))) found.push(DRAFT);
  if (found.length !== 1) throw new Problem(`exactly one of the draft and the final migration must exist, found ${JSON.stringify(found)}`);
  return found[0];
}

/** The text between the BEGIN and the END of the migration's DO block (comments included). */
function migrationBody(text) {
  const m = /DO \$mig\$\s*BEGIN([\s\S]*)\nEND\s*\$mig\$;/.exec(text);
  if (!m) throw new Problem('the migration has no DO $mig$ block');
  return m[1];
}

/**
 * Removes `--` line comments and block comments outside single-quoted literals (an E'' literal also escapes a quote with a
 * backslash) and outside double-quoted identifiers, and drops the blank lines that leave. Dollar-quoted bodies are treated as plain text:
 * the DO bodies of these files are PL/pgSQL, where `--` is a comment, which is what this strips.
 */
function stripComments(sql) {
  let out = '';
  let i = 0;
  const n = sql.length;
  while (i < n) {
    const c = sql[i];
    if (c === "'") {
      const escapes = i > 0 && (sql[i - 1] === 'E' || sql[i - 1] === 'e') && (i < 2 || !/[A-Za-z0-9_]/.test(sql[i - 2]));
      let j = i + 1;
      for (;;) {
        if (j >= n) throw new Problem('an unterminated string literal');
        if (escapes && sql[j] === '\\') {
          j += 2;
          continue;
        }
        // a doubled quote ends this literal and opens the next one at once, which reads the same as an escaped quote here
        if (sql[j] === "'") break;
        j += 1;
      }
      out += sql.slice(i, j + 1);
      i = j + 1;
    } else if (c === '"') {
      // a double-quoted identifier: a `--` or a `/*` inside it is part of the name (a doubled quote reads the same as above)
      let j = i + 1;
      for (;;) {
        if (j >= n) throw new Problem('an unterminated quoted identifier');
        if (sql[j] === '"') break;
        j += 1;
      }
      out += sql.slice(i, j + 1);
      i = j + 1;
    } else if (c === '-' && sql[i + 1] === '-') {
      while (i < n && sql[i] !== '\n') i += 1;
    } else if (c === '/' && sql[i + 1] === '*') {
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (sql.startsWith('/*', i)) {
          depth += 1;
          i += 2;
        } else if (sql.startsWith('*/', i)) {
          depth -= 1;
          i += 2;
        } else {
          i += 1;
        }
      }
      out += ' ';
    } else {
      out += c;
      i += 1;
    }
  }
  return out
    .split('\n')
    .map((l) => l.replace(/\s+$/, ''))
    .filter((l) => l.trim().length > 0)
    .join('\n') + '\n';
}

function count(text, needle) {
  return text.split(needle).length - 1;
}

/** Every dollar tag must come in pairs: a stripped comment that held a tag would have changed the nesting. */
function assertBalanced(text, tags) {
  for (const tag of tags) {
    const n = count(text, tag);
    if (n !== 2) throw new Problem(`the dollar quote ${tag} appears ${n} times, expected 2`);
  }
}

function compose(which, root = REPO) {
  const read = (rel) => {
    const p = path.join(root, rel);
    if (!fs.existsSync(p)) throw new Problem(`${rel} does not exist`);
    return fs.readFileSync(p, 'utf8');
  };
  if (which === 'file1') {
    const f1 = read(FILE1);
    if (count(f1, MARKER) !== 1) throw new Problem(`${FILE1} must carry the marker ${MARKER} exactly once`);
    const body = stripComments(migrationBody(read(migrationPath(root)))).trimEnd();
    // the marker line is a comment, so it is replaced before the whole text is stripped
    const at = f1.indexOf(MARKER);
    const lineStart = f1.lastIndexOf('\n', at) + 1;
    const lineEnd = f1.indexOf('\n', at);
    const composed = f1.slice(0, lineStart) + `${body}\n${body}\n` + f1.slice(lineEnd + 1);
    const out = stripComments(composed);
    assertBalanced(out, ['$v$']);
    if (count(out, "PERFORM set_config('lock_timeout', '5s', true);") !== 2) throw new Problem('the migration body must appear twice in the composed text');
    return out;
  }
  if (which === 'file2') {
    const out = stripComments(read(FILE2));
    assertBalanced(out, ['$r$']);
    return out;
  }
  throw new Problem('pass --file1 or --file2');
}

if (require.main === module) {
  const args = process.argv.slice(2);
  try {
    if (args.length !== 1 || (args[0] !== '--file1' && args[0] !== '--file2')) throw new Problem('usage: exercise_media_rehearsal_sql.js --file1 | --file2');
    process.stdout.write(compose(args[0].slice(2)));
  } catch (e) {
    if (!(e instanceof Problem)) throw e;
    process.stderr.write(`exercise_media_rehearsal_sql: ${e.message}\n`);
    process.exitCode = 2;
  }
}

module.exports = { compose, stripComments, migrationBody, migrationPath, Problem };
