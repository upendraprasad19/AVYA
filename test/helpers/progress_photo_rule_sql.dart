// test/helpers/progress_photo_rule_sql.dart
//
// Pure SQL readers for the progress-photo PRO INSERT rule
// (docs/plans/progress-photos-pro-server-rule.md, unit B1).
//
// The rule is ONE migration (a single DO block) and its pins live in
// test/contracts/progress_photos_pro_insert_rule_test.dart. Every function here takes
// source text or a `Map<path, content>` so the test can feed SYNTHETIC migration sets
// (one mutant per hole) as well as the real tree; only [loadRuleSqlSources] touches disk.
//
// Why whole-expression equality, not clauses (round 2, finding 1, P1): a pin that checks
// that the policy's WITH CHECK "contains" each conjunct passes when an AND is changed to
// an OR, and `(bucket AND own-folder) OR EXISTS(active subscription)` lets any PRO user
// INSERT into ANY bucket under any user's folder. So the pins compare the WHOLE
// normalised expression with an independently written literal.
//
// Why a TRIPWIRE and not an effective-state resolver (round 2, findings 4 and 11): a
// resolver that models what the later migrations do must anticipate every statement kind
// (a default-ALL policy, DROP FUNCTION ... CASCADE, RENAME, REVOKE ALL, a USING (false)
// narrowing, a RESTRICTIVE policy). The tripwire does not: ANY later migration that
// touches the protected set at all fails the test until it is acknowledged in an
// allow-list, and acknowledging forces a human to re-verify the rule. An acknowledgement is
// BOUND to the file's content ([TripwireAllow.contentHash]): editing an acknowledged file
// makes the violation come back, so the entry cannot outlive the verification it records.

import 'dart:io';

// ── lexical helpers shared by every reader below ───────────────────────────────────────────
//
// THIS FILE IS A LEXICAL READER, NOT A PARSER. It models what Postgres's lexer does with comments,
// single-quoted and E'...' literals, double-quoted identifiers and dollar quoting, and it reads statements
// with regular expressions. It cannot see dynamic SQL built by concatenation (`EXECUTE 'DROP ' || ...`) or
// anything else Postgres accepts that is not modelled here. The tripwire is therefore a best-effort guard
// against an ACCIDENTAL weakening of the rule; the arbiter is the live check
// (test/sql/progress_photos_pro_insert_rule_live_verify.sql, and the recurring catalog check tracked as OI-316).

bool _identChar(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

/// True when the `'` at [i] opens an `E'...'` string (backslash escapes are active in it).
bool _opensEString(String s, int i) => i > 0 && (s[i - 1] == 'E' || s[i - 1] == 'e') && (i == 1 || !_identChar(s[i - 2]));

/// Index just past the single-quoted literal whose opening `'` is at [i]: `''` is an escaped quote and,
/// in an `E'...'` string, a backslash escapes the next character. An unterminated literal ends at the end.
int _endOfLiteral(String s, int i) {
  final esc = _opensEString(s, i);
  var j = i + 1;
  while (j < s.length) {
    final c = s[j];
    if (esc && c == r'\') {
      j += 2;
      continue;
    }
    if (c == "'") {
      if (j + 1 < s.length && s[j + 1] == "'") {
        j += 2;
        continue;
      }
      return j + 1;
    }
    j++;
  }
  return s.length;
}

/// Index just past the double-quoted identifier whose opening `"` is at [i] (`""` is an escaped quote).
int _endOfQuotedIdent(String s, int i) {
  var j = i + 1;
  while (j < s.length) {
    if (s[j] == '"') {
      if (j + 1 < s.length && s[j + 1] == '"') {
        j += 2;
        continue;
      }
      return j + 1;
    }
    j++;
  }
  return s.length;
}

/// Removes `--` line comments and (nested) `/* ... */` block comments (a block comment becomes ONE
/// space: to Postgres it is whitespace, so `ALTER/**/POLICY` is `ALTER POLICY`), leaving string literals
/// (`'...'` with `''` as the escape, `E'...'` with backslash escapes) and double-quoted identifiers intact
/// and keeping newlines. A comment marker inside a literal or a quoted identifier is not a comment.
///
/// Dollar quoting is modelled the way Postgres reads it, in two levels: the SQL lexer finds the
/// closing `$tag$` of a dollar-quoted body by the first later occurrence of the same tag, with NO
/// comment recognition inside the body (so a `-- $tag$` line inside a DO body CLOSES it); the body
/// text is then read by PL/pgSQL, where comments ARE comments, so it is stripped recursively. A
/// stripper that skipped `--` lines first would hide a statement that Postgres executes.
String stripSqlAllComments(String sql) {
  final out = StringBuffer();
  var i = 0;
  final n = sql.length;
  final tagStart = RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$');
  bool identChar(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);
  while (i < n) {
    final c = sql[i];
    if (c == "'") {
      final e = _endOfLiteral(sql, i);
      out.write(sql.substring(i, e));
      i = e;
      continue;
    }
    if (c == '"') {
      final e = _endOfQuotedIdent(sql, i);
      out.write(sql.substring(i, e));
      i = e;
      continue;
    }
    if (c == '-' && i + 1 < n && sql[i + 1] == '-') {
      while (i < n && sql[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < n && sql[i + 1] == '*') {
      var depth = 1;
      out.write(' ');
      i += 2;
      while (i < n && depth > 0) {
        if (sql.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (sql.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          if (sql[i] == '\n') out.write('\n');
          i++;
        }
      }
      continue;
    }
    if (c == r'$' && (i == 0 || !identChar(sql[i - 1]))) {
      final m = tagStart.matchAsPrefix(sql, i);
      if (m != null) {
        final tag = m.group(0)!;
        final close = sql.indexOf(tag, m.end);
        if (close >= 0) {
          out.write(tag);
          out.write(stripSqlAllComments(sql.substring(m.end, close)));
          out.write(tag);
          i = close + tag.length;
          continue;
        }
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// [stripSqlAllComments] with every simple double-quoted identifier (`"storage"."objects"`,
/// `"progress_photos_insert_own"`) unquoted and the blanks around a dot removed, outside string
/// literals, so a name written in the quoted style `supabase db diff` emits, or with a blank before or
/// after the dot, is read as the same name. A quoted name that is not a plain lower-case identifier
/// (spaces, capitals) keeps its quotes.
String executableText(String sql) {
  final segs = _literalSegments(stripSqlAllComments(sql));
  final b = StringBuffer();
  for (final (isLit, text) in segs) {
    b.write(isLit
        ? text
        // a plain quoted name loses its quotes (not when it is half of a `""` escape); blanks around a dot go
        // (`storage . objects`, `public .progress_photos`: Postgres reads them as one qualified name)
        : text
            .replaceAllMapped(RegExp(r'(?<!")"([a-z_][a-z0-9_]*)"(?!")'), (m) => m.group(1)!)
            .replaceAll(RegExp(r'[ \t\r\n\f\v]*\.[ \t\r\n\f\v]*'), '.'));
  }
  return b.toString();
}

/// [executableText] with every `;` INSIDE a single-quoted literal replaced by U+0001, so a `[^;]*` that
/// reads "the rest of this statement" does not stop in the middle of a string (`WITH CHECK (x = ';')`).
String statementText(String sql) {
  final b = StringBuffer();
  for (final (isLit, text) in _literalSegments(executableText(sql))) {
    b.write(isLit ? text.replaceAll(';', '\u0001') : text);
  }
  return b.toString();
}

/// Code points above U+007F in the executable text of [sql] (comments stripped, string literals
/// included). Postgres does not treat U+00A0 as whitespace and reads any high byte as part of an
/// identifier, so a non-breaking space inside `end_date > now()` creates a function that refuses
/// every INSERT while a whitespace-collapsing reader sees the frozen text.
List<String> nonAsciiInExecutableText(String sql) {
  final out = <String>[];
  for (final r in stripSqlAllComments(sql).runes) {
    if (r > 0x7F) out.add('U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}');
  }
  return out;
}

/// Splits [sql] into alternating segments: `(false, text)` outside a string literal and
/// `(true, 'text')` for a whole `'...'` literal (quotes included).
List<(bool, String)> _literalSegments(String sql) {
  final out = <(bool, String)>[];
  var i = 0;
  var start = 0;
  final n = sql.length;
  while (i < n) {
    if (sql[i] == '"') {
      i = _endOfQuotedIdent(sql, i); // an apostrophe inside "it's" does not open a literal
      continue;
    }
    if (sql[i] != "'") {
      i++;
      continue;
    }
    if (i > start) out.add((false, sql.substring(start, i)));
    final litStart = i;
    i = _endOfLiteral(sql, i);
    out.add((true, sql.substring(litStart, i)));
    start = i;
  }
  if (start < n) out.add((false, sql.substring(start)));
  return out;
}

/// Comments stripped, whitespace collapsed to single spaces and no space around `(`, `)`,
/// `,` or `;`, so assertions do not depend on SQL layout. String literals are left untouched.
String normalizeSql(String sql) {
  final segs = _literalSegments(stripSqlAllComments(sql));
  final b = StringBuffer();
  for (final (isLit, text) in segs) {
    if (isLit) {
      b.write(text);
    } else {
      // replaceAllMapped, not replaceAll: Dart's replaceAll does not interpret `$1`.
      // ASCII whitespace only: Dart's `\s` also matches U+00A0, which Postgres does not read as whitespace.
      b.write(text.replaceAll(RegExp(r'[ \t\r\n\f\v]+'), ' ').replaceAllMapped(RegExp(r'[ \t\r\n\f\v]*([(),;])[ \t\r\n\f\v]*'), (m) => m.group(1)!));
    }
  }
  return b.toString().trim();
}

/// The text between the `(` at [openIdx] and its matching `)` (string literals respected),
/// or null when unbalanced.
String? balancedAfter(String s, int openIdx) {
  if (openIdx >= s.length || s[openIdx] != '(') return null;
  var depth = 0;
  var i = openIdx;
  while (i < s.length) {
    final c = s[i];
    if (c == "'") {
      i = _endOfLiteral(s, i);
      continue;
    }
    if (c == '"') {
      i = _endOfQuotedIdent(s, i);
      continue;
    }
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return s.substring(openIdx + 1, i);
    }
    i++;
  }
  return null;
}

/// Every `WITH CHECK ( ... )` expression of the statements that create or alter policy
/// [policy] ON storage.objects, normalised, in source order.
List<String> storagePolicyWithChecks(String sql, String policy) {
  final src = stripSqlAllComments(sql);
  final head = RegExp(
      '(?:ALTER|CREATE)\\s+POLICY\\s+"?${RegExp.escape(policy)}"?\\s+ON\\s+storage\\.objects\\b[^;]*?\\bWITH\\s+CHECK\\s*\\(',
      caseSensitive: false);
  final out = <String>[];
  for (final m in head.allMatches(src)) {
    final inner = balancedAfter(src, m.end - 1);
    if (inner != null) out.add(normalizeSql(inner));
  }
  return out;
}

/// The whole `CREATE [OR REPLACE] FUNCTION [public.]<name> ... AS $tag$ ... $tag$;` statement,
/// normalised, or null when [sql] does not define it.
String? functionStatement(String sql, String name) {
  final src = stripSqlAllComments(sql);
  final start = RegExp(
          'CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:public\\.)?${RegExp.escape(name)}\\b',
          caseSensitive: false)
      .firstMatch(src);
  if (start == null) return null;
  final open = RegExp(r'\bAS\s+(\$[A-Za-z_]*\$)').firstMatch(src.substring(start.start));
  if (open == null) return null;
  final tag = open.group(1)!;
  final bodyStart = start.start + open.end;
  final close = src.indexOf(tag, bodyStart);
  if (close < 0) return null;
  final semi = src.indexOf(';', close + tag.length);
  if (semi < 0) return null;
  return normalizeSql(src.substring(start.start, semi + 1));
}

/// The whole `CREATE TRIGGER <name> ...;` statement, normalised, or null.
String? triggerStatement(String sql, String name) {
  final src = stripSqlAllComments(sql);
  final m = RegExp('CREATE\\s+TRIGGER\\s+${RegExp.escape(name)}\\b[^;]*;', caseSensitive: false).firstMatch(src);
  return m == null ? null : normalizeSql(m.group(0)!);
}

/// Replaces the body of every `AS $tag$ ... $tag$` (a function body) with `AS BODY_MASKED`, so
/// a statement inside a function body is not read as a statement of the enclosing file.
String maskDollarBodies(String src) {
  final re = RegExp(r'\bAS\s+(\$[A-Za-z_]*\$)', caseSensitive: false);
  final out = StringBuffer();
  var pos = 0;
  while (true) {
    final it = re.allMatches(src, pos).iterator;
    if (!it.moveNext()) break;
    final m = it.current;
    final tag = m.group(1)!;
    final close = src.indexOf(tag, m.end);
    if (close < 0) break;
    out.write(src.substring(pos, m.start));
    out.write('AS BODY_MASKED');
    pos = close + tag.length;
  }
  out.write(src.substring(pos));
  return out.toString();
}

/// The statements of [src] (comments already stripped, function bodies masked), split at a
/// top-level `;` and ALSO after a top-level `BEGIN`, `THEN` or `ELSE` word and after a `DO $tag$`
/// opener, so the statements INSIDE a DO block are separate fragments. Parentheses and string
/// literals are respected. Fragments are normalised and non-empty.
List<String> splitStatements(String src) {
  final text = src.replaceAllMapped(RegExp(r'\bDO\s+\$[A-Za-z_]*\$', caseSensitive: false), (m) => '${m.group(0)};');
  final out = <String>[];
  final cur = StringBuffer();
  var depth = 0;
  var i = 0;
  final wordStart = RegExp(r'[A-Za-z_]');
  final wordChar = RegExp(r'[A-Za-z0-9_$.]');
  void flush() {
    final f = normalizeSql(cur.toString());
    if (f.isNotEmpty) out.add(f);
    cur.clear();
  }

  while (i < text.length) {
    final c = text[i];
    if (c == "'") {
      final e = _endOfLiteral(text, i);
      cur.write(text.substring(i, e));
      i = e;
      continue;
    }
    if (c == '"') {
      final e = _endOfQuotedIdent(text, i);
      cur.write(text.substring(i, e));
      i = e;
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (depth == 0 && c == ';') {
      flush();
      i++;
      continue;
    }
    if (wordStart.hasMatch(c) && (i == 0 || !wordChar.hasMatch(text[i - 1]))) {
      final m = RegExp(r'[A-Za-z_][A-Za-z0-9_$]*').matchAsPrefix(text, i)!;
      final w = m.group(0)!;
      cur.write(w);
      i = m.end;
      final up = w.toUpperCase();
      if (depth == 0 && (up == 'BEGIN' || up == 'THEN' || up == 'ELSE')) flush();
      continue;
    }
    cur.write(c);
    i++;
  }
  flush();
  return out;
}

final RegExp _controlFragment = RegExp(
    r'^(DO\s+\$[A-Za-z_]*\$|BEGIN|ELSE|END(\s+IF)?(\s+\$[A-Za-z_]*\$)?|\$[A-Za-z_]*\$|IF\b.*\bTHEN)$',
    caseSensitive: false);

/// The statement HEADS of [sql], in source order, with function bodies masked: the control
/// fragments of a DO block (`DO $tag$`, `BEGIN`, `IF ... THEN`, `ELSE`, `END IF`, `END $tag$`)
/// are skipped, every other statement contributes a short head: policies and triggers
/// `<VERB> <name> ON <table>` (a drop keeps `IF EXISTS`), functions
/// `CREATE [OR REPLACE] FUNCTION <name>`, anything else its first two words (`PERFORM set_config`).
/// Any statement a mutant adds, of any kind, adds a head.
List<String> ddlInventory(String sql) {
  final frags = splitStatements(maskDollarBodies(stripSqlAllComments(sql)));
  final heads = <String>[];
  for (final f in frags) {
    if (_controlFragment.hasMatch(f)) continue;
    final pol = RegExp(r'^(ALTER POLICY|CREATE POLICY|DROP POLICY(?: IF EXISTS)?)\s+"?(\w+)"?\s+ON\s+([\w.]+)', caseSensitive: false).firstMatch(f);
    if (pol != null) {
      heads.add('${pol.group(1)!.toUpperCase()} ${pol.group(2)} ON ${pol.group(3)}');
      continue;
    }
    final trg = RegExp(r'^(CREATE TRIGGER|DROP TRIGGER(?: IF EXISTS)?)\s+"?(\w+)"?\s+(?:[^;]*?\s)?ON\s+([\w.]+)', caseSensitive: false).firstMatch(f);
    if (trg != null) {
      heads.add('${trg.group(1)!.toUpperCase()} ${trg.group(2)} ON ${trg.group(3)}');
      continue;
    }
    final fn = RegExp(r'^(CREATE(?: OR REPLACE)? FUNCTION)\s+([\w.]+)', caseSensitive: false).firstMatch(f);
    if (fn != null) {
      heads.add('${fn.group(1)!.toUpperCase()} ${fn.group(2)}');
      continue;
    }
    final words = RegExp(r'[A-Za-z_][A-Za-z0-9_.]*').allMatches(f).take(2).map((m) => m.group(0)!).toList();
    heads.add(words.isEmpty ? f : '${words.first.toUpperCase()}${words.length > 1 ? ' ${words[1]}' : ''}');
  }
  return heads;
}

// ── file sets ──────────────────────────────────────────────────────────────────────────

/// Every `.sql` under [migrationsDir] and [draftsDir], keyed by repo-relative path
/// (forward slashes). The draft directory exists so the migration can be reviewed before it is
/// applied (Gate 14 fails on an unledgered file in supabase/migrations/).
Map<String, String> loadRuleSqlSources({
  String migrationsDir = 'supabase/migrations',
  String draftsDir = 'docs/drafts',
}) {
  final out = <String, String>{};
  for (final dir in [migrationsDir, draftsDir]) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final e in d.listSync()) {
      if (e is File && e.path.endsWith('.sql')) {
        out[e.path.replaceAll(r'\', '/')] = e.readAsStringSync();
      }
    }
  }
  return out;
}

String baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

/// `NNN` of `NNN[x]_*.sql`, or null for an unnumbered file.
int? migrationNumberOf(String baseName) {
  final m = RegExp(r'^(\d{3})[a-z]?_.*\.sql$').firstMatch(baseName);
  return m == null ? null : int.parse(m.group(1)!);
}

/// The unnumbered files that exist today and are not part of the applied sequence
/// (three timestamp-scheme files and the never-applied combined dump).
const Set<String> unnumberedSqlBaseline = <String>{
  '20260328000001_video_renders.sql',
  '20260330_create_promo_codes.sql',
  '20260331000001_add_pgvector_memory.sql',
  'all_migrations_combined.sql',
};

/// Numbered files in (number, name) order, with an explicit tie-break (two files share a
/// number and Dart's sort is not stable).
List<String> numberedInOrder(Iterable<String> paths) {
  final list = paths.where((p) => migrationNumberOf(baseName(p)) != null).toList();
  list.sort((a, b) {
    final c = migrationNumberOf(baseName(a))!.compareTo(migrationNumberOf(baseName(b))!);
    return c != 0 ? c : baseName(a).compareTo(baseName(b));
  });
  return list;
}

// ── the tripwire (D3b) ──────────────────────────────────────────────────────────────────

/// The protected-set patterns (D3b categories 1-5), matched on the comment-stripped text of a
/// file NEWER than the rule's migration. Deliberately wide: a false positive costs one
/// allow-list line and a re-verification; a false negative loses the rule.
final List<({int category, String label, RegExp re})> _protected = <({int category, String label, RegExp re})>[
  (category: 1, label: 'the rule\'s trigger or function', re: RegExp(r'trg_progress_photo_pro|enforce_progress_photo_pro', caseSensitive: false)),
  (
    category: 2,
    label: 'a progress-photos policy',
    re: RegExp(r'(?:CREATE|ALTER|DROP)\s+POLICY\s+(?:IF\s+EXISTS\s+)?"?progress_photos_(?:insert|select|delete|update)_own"?', caseSensitive: false)
  ),
  (
    category: 2,
    label: 'any policy statement on storage.objects',
    re: RegExp(r'(?:CREATE|ALTER|DROP)\s+POLICY\b[^;]*?\bON\s+(?:storage\.)?objects\b', caseSensitive: false)
  ),
  (category: 3, label: 'ALTER TABLE storage.objects', re: RegExp(r'ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?(?:storage\.)?objects\b', caseSensitive: false)),
  (
    category: 3,
    label: 'DROP/ALTER TABLE progress_photos (rename, trigger, RLS, column, owner, drop)',
    re: RegExp(
        r'(?:DROP\s+TABLE\b[^;]*?\bprogress_photos\b|ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?(?:public\.)?progress_photos\b[^;]*?'
        r'\b(?:RENAME|DISABLE\s+TRIGGER|ENABLE\s+(?:ALWAYS\s+|REPLICA\s+)?TRIGGER|DISABLE\s+ROW|ENABLE\s+ROW|FORCE\s+ROW|NO\s+FORCE|DROP\s+COLUMN|ALTER\s+COLUMN|OWNER|SET\s+SCHEMA)\b)',
        caseSensitive: false)
  ),
  (category: 3, label: 'ALTER TRIGGER', re: RegExp(r'ALTER\s+TRIGGER\b', caseSensitive: false)),
  (
    category: 3,
    label: 'GRANT/REVOKE on public.progress_photos or storage.objects (a privilege change on a table the rule guards)',
    re: RegExp(
        r'(?:GRANT|REVOKE)\b[^;]*?\bON\b[^;]*?(?:\bprogress_photos\b|\b(?:storage\.)?objects\b|\bALL\s+TABLES\s+IN\s+SCHEMA\s+(?:public|storage)\b)',
        caseSensitive: false)
  ),
  (
    category: 3,
    label: 'a trigger or rule on a guarded table (a BEFORE INSERT trigger can rewrite NEW.user_id)',
    re: RegExp(
        r'CREATE\s+(?:OR\s+REPLACE\s+)?(?:CONSTRAINT\s+)?TRIGGER\b[^;]*?\bON\s+(?:(?:public\.)?progress_photos|(?:storage\.)?objects|(?:public\.)?subscriptions)\b|'
        r'CREATE\s+(?:OR\s+REPLACE\s+)?RULE\b[^;]*?\bTO\s+(?:(?:public\.)?progress_photos|(?:storage\.)?objects|(?:public\.)?subscriptions)\b',
        caseSensitive: false)
  ),
  (
    category: 3,
    label: 'session_replication_role (replica skips every ordinary trigger: SET, SET LOCAL, set_config, ALTER ROLE/DATABASE ... SET)',
    re: RegExp(r'\bsession_replication_role\b', caseSensitive: false)
  ),
  (category: 3, label: 'DROP OWNED (removes every object and privilege a role owns)', re: RegExp(r'DROP\s+OWNED\b', caseSensitive: false)),
  (
    category: 3,
    label: 'a role created or altered with BYPASSRLS',
    re: RegExp(r'(?:ALTER|CREATE)\s+(?:ROLE|USER)\b[^;]*?\bBYPASSRLS\b', caseSensitive: false)
  ),
  (
    category: 4,
    label: 'a policy statement on public.subscriptions',
    re: RegExp(r'(?:CREATE|ALTER|DROP)\s+POLICY\b[^;]*?\bON\s+(?:public\.)?subscriptions\b', caseSensitive: false)
  ),
  (
    category: 4,
    label: 'GRANT/REVOKE on public.subscriptions',
    re: RegExp(r'(?:GRANT|REVOKE)\b[^;]*?\bON\b[^;]*?(?:\bsubscriptions\b|\bALL\s+TABLES\s+IN\s+SCHEMA\s+public\b)', caseSensitive: false)
  ),
  (
    category: 4,
    label: 'DROP TABLE or a structural ALTER TABLE on public.subscriptions',
    re: RegExp(
        r'(?:DROP\s+TABLE\b[^;]*?\bsubscriptions\b|ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?(?:public\.)?subscriptions\b[^;]*?'
        r'\b(?:RENAME|DROP\s+COLUMN|ALTER\s+COLUMN|ROW\s+LEVEL\s+SECURITY|SET\s+SCHEMA|OWNER)\b)',
        caseSensitive: false)
  ),
  (
    category: 5,
    label: 'DROP ... CASCADE (a cascade can silently delete the trigger or the policy)',
    re: RegExp(r'DROP\s+(?:FUNCTION|TABLE|COLUMN|TRIGGER|POLICY|SCHEMA)\b[^;]*?\bCASCADE\b', caseSensitive: false)
  ),
];

/// One acknowledged later migration: why a human judged it safe for the rule, and the content hash
/// of the file at that moment. The acknowledgement stops applying when the file changes.
class TripwireAllow {
  const TripwireAllow({required this.reason, required this.contentHash});
  final String reason;
  final String contentHash;
}

/// FNV-1a 64-bit of [text]'s UTF-16 code units, as 16 hex digits. Not cryptographic: it only has
/// to change when the acknowledged file is edited.
String ruleSqlHash(String text) {
  var h = 0xcbf29ce484222325;
  for (final u in text.codeUnits) {
    h = (h ^ u) * 0x100000001b3;
  }
  String half(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '${half(h >>> 32)}${half(h)}';
}

/// Problems with the allow-list itself: an entry that names no file newer than the rule, a reason
/// too short to record what was re-verified, or a hash that no longer matches the file. Empty =
/// every entry is a current, reasoned acknowledgement.
List<String> allowListIssues(Map<String, String> files, Map<String, TripwireAllow> allow, {required String b1Path}) {
  final b1Number = migrationNumberOf(baseName(b1Path));
  final byName = <String, String>{for (final e in files.entries) baseName(e.key): e.value};
  final out = <String>[];
  for (final e in allow.entries) {
    final content = byName[e.key];
    final number = migrationNumberOf(e.key);
    if (content == null) {
      out.add('${e.key}: acknowledged but no such file exists (a stale entry)');
      continue;
    }
    if (number == null || b1Number == null || number < b1Number) {
      out.add('${e.key}: acknowledged but it is not a file newer than the rule');
    }
    if (e.value.reason.trim().length < 40) out.add('${e.key}: the reason does not say what was re-verified (under 40 characters)');
    if (e.value.contentHash != ruleSqlHash(content)) {
      out.add('${e.key}: the file changed since it was acknowledged (hash ${ruleSqlHash(content)}, recorded ${e.value.contentHash})');
    }
  }
  return out;
}

/// Violations of the tripwire over [files] (`path -> content`). [b1Path] is the rule's own
/// migration (its path in [files]). [allow] maps a BASE NAME to its acknowledgement (empty at B1:
/// nothing newer exists); an acknowledgement applies only while the file's hash matches. Returns
/// human-readable lines; empty = clean.
List<String> tripwireViolations(
  Map<String, String> files, {
  required String b1Path,
  Map<String, TripwireAllow> allow = const <String, TripwireAllow>{},
}) {
  final b1Name = baseName(b1Path);
  final b1Number = migrationNumberOf(b1Name);
  if (b1Number == null) {
    return <String>['the rule\'s migration $b1Name has no NNN_ prefix'];
  }
  final out = <String>[];
  for (final e in files.entries) {
    final name = baseName(e.key);
    if (name == b1Name) continue;
    final number = migrationNumberOf(name);
    if (number == null) {
      if (!unnumberedSqlBaseline.contains(name)) {
        out.add('$name: an unnumbered .sql file that is not in the baseline list (it would dodge "newer than the rule")');
      }
      continue;
    }
    if (number < b1Number) continue;
    final ack = allow[name];
    if (ack != null && ack.contentHash == ruleSqlHash(e.value)) continue;
    final src = statementText(e.value);
    for (final p in _protected) {
      final m = p.re.firstMatch(src);
      if (m != null) {
        final t = m.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
        final stale = ack != null ? ' (its acknowledgement is stale: the file changed)' : '';
        out.add('$name: [category ${p.category}] ${p.label}: "${t.length > 90 ? t.substring(0, 90) : t}"$stale');
      }
    }
  }
  return out;
}

// ── no second door (E5) ──────────────────────────────────────────────────────────────────

/// Policies ON storage.objects whose command is INSERT, ALL or UNSPECIFIED (Postgres defaults
/// an unspecified command to ALL) must name a `bucket_id = '<literal>'` (an unscoped one would
/// OR past the rule), and no policy other than the rule's own `progress_photos_insert_own` in
/// [b1Path] may name 'progress-photos' with such a command. Applies to EVERY numbered file
/// (the unnumbered baseline, the combined dump, is never applied).
List<String> secondDoorViolations(Map<String, String> files, {required String b1Path}) {
  final out = <String>[];
  // A policy name is a plain word or a double-quoted name that may hold spaces (the dashboard names
  // its policies "Allow authenticated uploads to avatars").
  final stmt = RegExp(r'CREATE\s+POLICY\s+(?:"((?:[^"]|"")+)"|(\w+))\s+ON\s+(?:storage\.)?objects\b([^;]*)(?:;|$)', caseSensitive: false);
  for (final e in files.entries) {
    final name = baseName(e.key);
    if (migrationNumberOf(name) == null) continue;
    final src = statementText(e.value);
    for (final m in stmt.allMatches(src)) {
      final policy = m.group(1) ?? m.group(2)!;
      final rest = m.group(3)!;
      final cmd = RegExp(r'\bFOR\s+(SELECT|INSERT|UPDATE|DELETE|ALL)\b', caseSensitive: false).firstMatch(rest)?.group(1)?.toUpperCase() ?? 'ALL';
      if (cmd != 'INSERT' && cmd != 'ALL') continue;
      if (!RegExp(r"bucket_id\s*=\s*'[^']+'").hasMatch(rest)) {
        out.add('$name: policy $policy ON storage.objects (command $cmd) names no bucket_id literal');
      }
      final isRule = e.key == b1Path && policy == 'progress_photos_insert_own';
      if (rest.contains("'progress-photos'") && !isRule) {
        out.add('$name: policy $policy is a second door into the progress-photos bucket (command $cmd)');
      }
    }
  }
  return out;
}

// ── public.subscriptions: the effective policy set (D12 / E6) ─────────────────────────────

/// The policies on public.subscriptions that survive [files] applied in (number, name) order:
/// `name -> command` (an unspecified command is ALL). A policy whose `TO` list names none of
/// public, authenticated or anon (a service_role-only policy) is not a client write path and is
/// skipped. Unnumbered files are skipped.
Map<String, String> subscriptionsEffectivePolicies(Map<String, String> files) {
  final policies = <String, String>{};
  final stmt = RegExp(
      r'(CREATE\s+POLICY\s+(?:"((?:[^"]|"")+)"|(\w+))\s+ON\s+(?:public\.)?subscriptions\b([^;]*)(?:;|$))|'
      r'(DROP\s+POLICY\s+(?:IF\s+EXISTS\s+)?(?:"((?:[^"]|"")+)"|(\w+))\s+ON\s+(?:public\.)?subscriptions\b)',
      caseSensitive: false);
  for (final path in numberedInOrder(files.keys)) {
    final src = statementText(files[path]!);
    for (final m in stmt.allMatches(src)) {
      if (m.group(1) != null) {
        final rest = m.group(4)!;
        final cmd = RegExp(r'\bFOR\s+(SELECT|INSERT|UPDATE|DELETE|ALL)\b', caseSensitive: false).firstMatch(rest)?.group(1)?.toUpperCase() ?? 'ALL';
        final roles = RegExp(r'\bTO\s+([\w\s,"]+?)(?=\bUSING\b|\bWITH\b|$)', caseSensitive: false).firstMatch(rest)?.group(1);
        if (roles != null) {
          final names = roles.split(',').map((r) => r.replaceAll('"', '').trim().toLowerCase()).toSet();
          if (!names.any((r) => r == 'public' || r == 'authenticated' || r == 'anon')) continue;
        }
        policies[m.group(2) ?? m.group(3)!] = cmd;
      } else {
        policies.remove(m.group(6) ?? m.group(7)!);
      }
    }
  }
  return policies;
}
