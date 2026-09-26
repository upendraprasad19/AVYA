// scripts/check_unbounded_cron_reads.dart
//
// Gate — every fan-out read in a cron-dispatched Edge Function must be bounded.
//
// WHY (OI-79, 2026-08-01)
// ----------------------
// PostgREST caps every response at `db-max-rows` (1000 on this project) and
// supabase-js gives the caller NO way to notice. Measured live against
// `food_database` (1431 rows): a bare `?select=id` — exactly what `.select()`
// sends — returns **HTTP 200 OK**, `Content-Range: 0-999/*`, 1000 rows, and
// `error === null`. Not a 206 (that needs `Prefer: count=exact`, which no cron
// function sends), and the total is `*`, so the response does not even carry
// what you would need to detect the loss. A truncated read is byte-for-byte
// indistinguishable from a small one.
//
// The consequence is not merely "some users are skipped". The audit that
// produced this gate found reads whose truncation INVERTS a decision:
// `protein-gap-alert` reads nutrition_logs to compute how much protein each PRO
// user ate; nutrition_logs holds ~4 rows per user per day, so the read clipped
// at ~250 users and the users it dropped had their protein summed low —
// producing a "you're short on protein" push to someone who hit their target.
// Same shape in `workout-window-closing` / `streak-guardian` (the "already
// trained today" exclusion set) and `plateau-alert` (the PRO inclusion set).
//
// WHAT IT CHECKS
// --------------
// For every cron-dispatched Edge Function (roster derived from
// docs/operations/CRON_REGISTRY.md, so it cannot drift from the real cron
// fleet) plus the shared helpers they read through, every `.from("<t>")` and
// `.rpc("<fn>")` query chain must be bounded by one of:
//   - routed through `_shared/paged_fetch.ts` (fetchAllPages / fetchAllByIds)
//   - `.single()` / `.maybeSingle()`            → at most one row
//   - `{ count: "exact", head: true }`          → no rows, just a count
//   - `.limit(<n>)` with n <= POSTGREST_MAX_ROWS → explicitly, honestly bounded
//   - `.range(` inside a hand-rolled pagination loop
// Anything else is an unbounded fan-out read and fails.
//
// It also rejects `.limit(<n>)` with n > 1000 outright: that is not a bound at
// all, it is a lie. `rolling-context` asked for `.limit(10000)` and could only
// ever receive 1000, and `active_users_for_signals()` carries an internal
// `limit 5000` that PostgREST made unreachable — both shipped believing they
// had a 5-10k ceiling when the real one was 1000.
//
// SCOPE / LIMITS (honest — same discipline as check_schema_column_refs.dart)
// -------------------------------------------------------------------------
//   - Only CRON-dispatched functions + `_shared/`. Client-invoked functions
//     (ai-proxy, verify-payment, …) read one user's own rows and are out of
//     scope by design.
//   - Chain extraction is textual: from `.from(`/`.rpc(` forward to the
//     statement's terminating `;`. A query built across several statements
//     (`let q = supabase.from(...); q = q.eq(...)`) is NOT tracked — it would
//     read as unbounded and fail loudly rather than pass silently, which is the
//     correct direction for a gate.
//   - `supabase.storage.from(<bucket>)` is skipped (not a PostgREST table read).
//   - The table name must be a STRING LITERAL. `.from(tbl)` where `tbl` is a
//     variable is INVISIBLE to this gate — it will not be reported at all.
//     Disclosed because the failure direction here is the dangerous one (a
//     silent pass, not a loud fail), unlike the multi-statement case above.
//     Found by round-1 review 2026-08-01; no such call site exists in the cron
//     fleet today, which is why this is documented rather than implemented.
//   - It cannot verify that a `.limit(n)` is *semantically* right, only that it
//     is a real ceiling PostgREST can honour.
//
// Exit 0 = clean. Exit 1 = at least one unbounded read. `--warn-only` reports
// without failing (§4.11 baseline window).

import 'dart:io';

const int postgrestMaxRows = 1000;

/// Markers that make a query chain bounded.
///
/// `_pagedHelper` deliberately does NOT require a following `(` — the real call
/// sites carry a generic parameter (`fetchAllPages<Record<string, unknown>>(`)
/// whose nested angle brackets no simple regex matches. The bare name inside a
/// 6-line window is signal enough.
final _pagedHelper = RegExp(r'fetchAll(Pages|ByIds)\b');
final _single = RegExp(r'\.(maybeSingle|single)\s*\(');
final _headCount = RegExp(r'head\s*:\s*true');
final _range = RegExp(r'\.range\s*\(');
/// `.order("col"…)` in a hand-rolled chain, or a `paged_fetch` `orderBy:`
/// option. A `.range()` loop needs one of these or its pages are unstable.
final _orderBy = RegExp(r'\.order\s*\(|\borderBy\s*:');
final _limit = RegExp(r'\.limit\s*\(\s*(\d+)\s*\)');

/// A write, not a read — PostgREST's row cap does not apply.
final _write = RegExp(r'\.(insert|update|upsert|delete)\s*\(');

/// Server-side pagination pushed INTO an RPC (`p_offset` + `p_limit`
/// parameters). `morning-alert`'s delivery sweep uses this and it is strictly
/// better than a client `.range()` loop — ordering and paging both happen in
/// SQL. Requires BOTH parameters: an offset with no limit is not a bound.
final _rpcPaged = RegExp(r'p_offset\s*:');
final _rpcPagedLimit = RegExp(r'p_limit\s*:');

/// Explicit, reviewed waiver. Put `// oi79-ok: <reason>` on or just above the
/// read. Used for genuinely per-entity reads (`.eq("user_id", uid)` inside a
/// per-user loop) that cannot exceed the cap in practice but carry no syntactic
/// bound. Requiring the marker means each one was a decision, not an oversight.
final _waiver = RegExp(r'//\s*oi79-ok:');

/// A `.from("table")` or `.rpc("fn")` occurrence.
final _queryStart = RegExp(r'\.(from|rpc)\s*\(\s*[' "'" r'"`]([A-Za-z0-9_\-]+)');

class Violation {
  Violation(this.file, this.line, this.kind, this.name, this.reason);
  final String file;
  final int line;
  final String kind;
  final String name;
  final String reason;
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final root = Directory.current.path;

  final registry = File('$root/docs/operations/CRON_REGISTRY.md');
  if (!registry.existsSync()) {
    stderr.writeln('check_unbounded_cron_reads: CRON_REGISTRY.md not found');
    exit(1);
  }

  final cronFns = _cronFunctionSlugs(registry.readAsStringSync());
  if (cronFns.isEmpty) {
    stderr.writeln(
      'check_unbounded_cron_reads: parsed ZERO cron functions from '
      'CRON_REGISTRY.md — the table format changed. Failing closed rather than '
      'reporting a vacuous pass.',
    );
    exit(1);
  }

  final targets = <File>[];
  final seen = <String>{};
  void addTarget(File f) {
    // NORMALISE before de-duping. The registry branch builds paths with `/`
    // while Directory.listSync() returns platform paths (`\` on Windows), so
    // keying on the raw string let the SAME file enter twice — inflating the
    // scanned-file count, double-counting waivers, and (worse) reporting any
    // real violation twice. Caught by printing the waived SITES: three of them
    // appeared as exact duplicates, which a bare tally of "8" concealed.
    final key = f.absolute.path.replaceAll('\\', '/').toLowerCase();
    if (seen.add(key)) targets.add(f);
  }

  for (final slug in cronFns) {
    final f = File('$root/supabase/functions/$slug/index.ts');
    if (f.existsSync()) addTarget(f);
  }
  // UNION with every CRON-SHAPED function — one importing `_shared/cron_auth.ts`
  // — even if CRON_REGISTRY.md does not list it. The registry alone was NOT
  // enough: `weekly-recalc` imports both cron_auth and cron_telemetry yet has
  // zero entries in the registry, so it was never scanned, and it holds one of
  // the three hand-rolled `.range()` loops this batch fixed. Found by round-2
  // review 2026-08-01, after the round-1 fix comment had already named
  // weekly-recalc as a case the new `.range()` rule covered — it did not.
  // Deriving from the registry alone means a function missing from a
  // hand-maintained doc is silently exempt from the gate; the import is the
  // structural fact, so it is the better roster key.
  final fnRoot = Directory('$root/supabase/functions');
  if (fnRoot.existsSync()) {
    for (final dir in fnRoot.listSync().whereType<Directory>()) {
      final idx = File('${dir.path}/index.ts');
      if (!idx.existsSync()) continue;
      if (idx.readAsStringSync().contains('_shared/cron_auth.ts')) {
        addTarget(idx);
      }
    }
  }
  // Shared helpers run inside those same cron ticks, and a batch read hidden in
  // one of them is exactly as exposed (notification_prefs.ts was: it clipped at
  // ~175 users and silently disabled every notification toggle past that).
  final sharedDir = Directory('$root/supabase/functions/_shared');
  if (sharedDir.existsSync()) {
    for (final e in sharedDir.listSync()) {
      if (e is File &&
          e.path.endsWith('.ts') &&
          !e.path.contains('_test') &&
          !e.path.endsWith('.test.ts')) {
        addTarget(e);
      }
    }
  }

  final violations = <Violation>[];
  for (final file in targets) {
    violations.addAll(_scan(file, root));
  }

  if (violations.isEmpty) {
    stdout.writeln(
      'check_unbounded_cron_reads: OK — ${targets.length} files scanned '
      '(${cronFns.length} in CRON_REGISTRY.md + cron-shaped functions + shared '
      'helpers), no unbounded reads'
      '${waived > 0 ? ", $waived explicitly waived (// oi79-ok:)" : ""}.',
    );
    // Print every waived SITE, not just a tally. A count cannot be audited:
    // 5 markers in the tree suppress 8 reads, because one marker covers every
    // read within the lookback beneath it. Listing them is what made that
    // visible, and keeps a waiver from quietly widening later.
    for (final s in waivedSites) {
      stdout.writeln('  waived: $s');
    }
    exit(0);
  }

  final label = warnOnly ? 'WARN' : 'FAIL';
  stderr.writeln(
    'check_unbounded_cron_reads: $label — ${violations.length} unbounded '
    'read(s) in cron-dispatched Edge Functions.\n'
    'PostgREST silently truncates these at $postgrestMaxRows rows with HTTP 200 '
    'and error===null (OI-79).\n',
  );
  for (final v in violations) {
    stderr.writeln('  ${v.file}:${v.line}  .${v.kind}("${v.name}") — ${v.reason}');
  }
  stderr.writeln(
    '\nFix: route the read through supabase/functions/_shared/paged_fetch.ts\n'
    '  const rows = await fetchAllPages<T>(\n'
    '    () => supabase.from("t").select("...").eq(...),\n'
    '    { orderBy: "id", label: "<fn> <what>" },\n'
    '  );\n'
    'Use fetchAllByIds when the query has an .in(<ids>) — it bounds the URL AND\n'
    'the row count; chunking the id list alone does NOT bound the response.\n'
    'orderBy must end in a unique, immutable column (a primary key).',
  );
  exit(warnOnly ? 0 : 1);
}

/// Extracts the Function-column slugs from the registry's active-jobs table.
Set<String> _cronFunctionSlugs(String md) {
  final out = <String>{};
  // Rows look like: | 031 | `job` (10) | ... | `re-engagement` | ... |
  // The function slug is the first backticked token in the "Function" column
  // that maps to a real directory; intra-DB rows carry "(intra-DB)" instead.
  for (final line in md.split('\n')) {
    if (!line.trimLeft().startsWith('|')) continue;
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (cells.length < 7) continue;
    final fnCell = cells[5];
    if (fnCell.contains('intra-DB') || fnCell.isEmpty) continue;
    final m = RegExp(r'`([a-z0-9\-]+)`').firstMatch(fnCell);
    if (m != null) out.add(m.group(1)!);
  }
  return out;
}

/// Reads suppressed by an explicit `// oi79-ok:` waiver, each PRINTED on a
/// clean run so the waivers stay auditable instead of accumulating silently.
///
/// The count alone was not enough: 5 markers in the tree suppress 8 reads,
/// because one marker inside the 15-line lookback covers every read beneath
/// it — a waiver written for one query silently blessing its neighbours. That
/// is the same inherit-bounded-ness shape as F24/F26, just via prose, and a
/// bare tally hid it. Printing the sites is what surfaced it.
final waivedSites = <String>[];
int get waived => waivedSites.length;

/// Blanks out `//` and `/* */` comment bodies, preserving newlines and length
/// so reported line numbers stay correct.
///
/// Without this the gate reports prose. `re-engagement/index.ts` carries a
/// comment explaining what the OLD code did — including the literal text
/// `.from("users")` — and the gate flagged it as a live unbounded read.
/// Recurrence of `feedback_source_grep_strip_comments_first.md`: strip comments
/// BEFORE any source-pattern scan, every time.
String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    // A string literal is copied VERBATIM, never scanned for comment markers.
    // Without this, the `//` in any URL blanks the rest of its physical line —
    // and these files are full of `https://…`. Verified as a live bypass: a
    // statement placed after a URL on the same line vanished from the scan and
    // the gate exited 0. A `/*` inside a literal was worse still: it blanked
    // everything to the next `*/`, potentially voiding many reads at once.
    final q = src[i];
    if (q == '"' || q == "'" || q == '`') {
      out.write(q);
      i++;
      while (i < src.length) {
        out.write(src[i]);
        if (src[i] == r'\' && i + 1 < src.length) {
          i++;
          out.write(src[i]);
          i++;
          continue;
        }
        if (src[i] == q) {
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        out.write(' ');
        i++;
      }
    } else if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '*') {
      while (i < src.length && !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < src.length) {
        out.write('  ');
        i += 2;
      }
    } else {
      out.write(src[i]);
      i++;
    }
  }
  return out.toString();
}

List<Violation> _scan(File file, String root) {
  final raw = file.readAsStringSync();
  // Waivers live IN comments, so match them against the raw text; everything
  // else scans the comment-stripped copy.
  final src = _stripComments(raw);
  final rel = file.path.replaceFirst('$root${Platform.pathSeparator}', '').replaceAll('\\', '/');
  final out = <Violation>[];
  final helperRanges = _helperCallRanges(src);

  for (final m in _queryStart.allMatches(src)) {
    final kind = m.group(1)!;
    final name = m.group(2)!;

    // storage.from('bucket') is not a PostgREST table read.
    final before = src.substring((m.start - 40).clamp(0, m.start), m.start);
    if (before.contains('storage')) continue;

    final chain = _chainFrom(src, m.start);
    // Waivers are comments, so they only exist in the raw text. A waiver must
    // justify itself and those justifications run several lines, so this window
    // is deliberately generous — a line-distance window is the right tool for a
    // comment, and the wrong one for the paged-helper check below.
    final rawCtx = _contextBefore(raw, m.start, lines: 15);

    if (_write.hasMatch(chain)) continue;
    if (_insideAny(helperRanges, m.start) || _pagedHelper.hasMatch(chain)) {
      continue;
    }
    if (_single.hasMatch(chain)) continue;
    if (_headCount.hasMatch(chain)) continue;
    // A hand-rolled `.range()` loop bounds the ROW COUNT but not the row
    // ORDER. Postgres gives no cross-page ordering guarantee without ORDER BY,
    // so pages can skip or duplicate rows — this batch's own Class 4, which the
    // gate could not previously see because any `.range(` counted as bounded.
    // `paged_fetch` makes `orderBy` mandatory so the pairing is unconstructible
    // there; outside it (weekly-recalc, i-see-you-callout) it must be checked.
    if (_range.hasMatch(chain)) {
      if (_orderBy.hasMatch(chain)) continue;
      // Honour the documented `// oi79-ok:` escape hatch HERE. This branch
      // `continue`s before the shared waiver check further down, so without
      // this the hatch was inoperative for this one class alone — a reviewed
      // per-user `.range()` loop would have been unblockable except by
      // --no-verify, which §4.3 forbids. (Round-2 review 2026-08-01.)
      if (_waiver.hasMatch(rawCtx)) {
        waivedSites.add('$rel:${_lineOf(src, m.start)}  .from("$name") [.range() without .order()]');
        continue;
      }
      out.add(Violation(
        rel,
        _lineOf(src, m.start),
        kind,
        name,
        '.range() without .order() — Postgres gives no cross-page row-order '
        'guarantee, so pages can skip or duplicate rows (one user alerted '
        'twice, another never). Add a stable .order() ending in a unique '
        'column, or route through paged_fetch (orderBy is mandatory there)',
      ));
      continue;
    }
    if (_rpcPaged.hasMatch(chain) && _rpcPagedLimit.hasMatch(chain)) continue;
    if (_waiver.hasMatch(rawCtx)) {
      waivedSites.add('$rel:${_lineOf(src, m.start)}  $kind("$name")');
      continue;
    }

    final lim = _limit.firstMatch(chain);
    if (lim != null) {
      final n = int.parse(lim.group(1)!);
      if (n <= postgrestMaxRows) continue;
      out.add(Violation(
        rel,
        _lineOf(src, m.start),
        kind,
        name,
        'unreachable .limit($n) — PostgREST caps responses at $postgrestMaxRows, '
        'so this ceiling can never be observed and the extra rows are dropped '
        'with no error',
      ));
      continue;
    }

    out.add(Violation(
      rel,
      _lineOf(src, m.start),
      kind,
      name,
      'unbounded read — no paged_fetch, .single(), head-count, .range() or '
      '.limit()',
    ));
  }
  return out;
}

/// The query chain starting at [start]: forward to the terminating `;` at
/// paren-depth 0 (or EOF). Deliberately conservative — a chain split across
/// statements is not tracked and will read as unbounded.
/// Longest plausible single statement. The longest real chain in the cron
/// fleet measures 683 chars, so 4000 is ~6x headroom.
const _maxChainChars = 4000;

String _chainFrom(String src, int start) {
  var depth = 0;
  var i = start;
  // FAIL CLOSED on a runaway. The string-skipping below is not a real JS
  // tokenizer — it does not know about regex literals, so `/'/g` (an odd
  // number of quote chars inside a regex) opens string mode that never closes,
  // `;` never terminates, and the chain swallows the rest of the FILE,
  // inheriting a distant `.limit()` / `.range()` / `fetchAllPages(` and
  // whitewashing a genuinely unbounded read. That is F28's bug re-entered
  // through a different token — the THIRD token class to defeat this scanner
  // (comments, strings, now regexes), which is the signal to stop patching
  // token-by-token and bound the blast radius instead.
  //
  // Returning '' makes every bounded-ness pattern fail to match, so the read is
  // REPORTED rather than silently blessed. A structurally paged read is still
  // recognised, because `_insideAny` works on offsets and never consults the
  // chain. Loud false positive, never a silent false negative.
  final limit = start + _maxChainChars;
  while (i < src.length) {
    if (i > limit) return '';
    final c = src[i];
    // Skip string literals. Counting parens inside them is how a chain used to
    // run away: `.eq("note", "(")` left depth permanently > 0, the `;` never
    // terminated the chain, and it swallowed the rest of the FILE — so a later
    // `.range(`, `.limit(`, `.insert(` or `fetchAllPages(` matched and
    // whitewashed a genuinely unbounded read. Verified as a live bypass.
    if (c == '"' || c == "'" || c == '`') {
      final quote = c;
      i++;
      while (i < src.length && src[i] != quote) {
        if (src[i] == r'\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (c == ';' && depth <= 0) return src.substring(start, i);
    i++;
  }
  return src.substring(start);
}

/// [lines] lines of context before the match — used ONLY to find a multi-line
/// `// oi79-ok:` waiver, where line distance is the right unit because a waiver
/// is prose attached to a site.
///
/// It is deliberately NOT used to decide whether a read is paged. See
/// [_helperCallRanges] for why that question is structural, not positional.
String _contextBefore(String src, int start, {int lines = 15}) {
  var seen = 0;
  var i = start;
  while (i > 0 && seen < lines) {
    i--;
    if (src[i] == '\n') seen++;
  }
  return src.substring(i, start);
}

/// Byte ranges spanning the ARGUMENT LIST of every `fetchAllPages(` /
/// `fetchAllByIds(` call in [src] (which must already be comment-stripped, or
/// a doc example would register as a call).
///
/// This replaces a line-distance heuristic that was wrong in BOTH directions
/// and could not be tuned out of it — measured, not theorised:
///
///   * Too narrow (6 lines): a multi-line GENERIC ARGUMENT pushes the helper
///     name far above the `.from(` it wraps. `rolling-context/index.ts` spans
///     8 lines between `fetchAllPages<{` and `.from("ai_coach_interactions")`,
///     so a correctly-paged read was reported as unbounded. This is F18's tooth
///     biting twice: fixing the PATTERN (`fetchAllPages\s*\(` -> `\b`) left the
///     DISTANCE wrong.
///   * Too wide (15 lines): an UNPAGED read a few lines BELOW a paged one
///     inherits its bounded-ness. Injecting `.from("users").select("id")` 11
///     lines under expiry-reminder's `fetchAllPages` made the gate report OK —
///     a false negative, which in a safety gate is strictly worse than the
///     false positive it was meant to cure.
///
/// Distance was never the question. The question is whether the `.from(` sits
/// lexically INSIDE the helper's argument list, which is what this computes.
List<List<int>> _helperCallRanges(String src) {
  final ranges = <List<int>>[];
  for (final m in _pagedHelper.allMatches(src)) {
    // Step over a generic argument (`<{ id: string }>`, `<Record<K,V>>`) to
    // reach the real `(`. Anything else non-blank means this is a mention, not
    // a call (e.g. an `import { fetchAllPages }`), so bail on it.
    var i = m.end;
    var angle = 0;
    var isCall = false;
    while (i < src.length) {
      final c = src[i];
      if (c == '<') {
        angle++;
      } else if (c == '>') {
        angle--;
      } else if (angle <= 0) {
        if (c == '(') {
          isCall = true;
          break;
        }
        if (c != ' ' && c != '\n' && c != '\r' && c != '\t') break;
      }
      i++;
    }
    if (!isCall) continue;
    final close = _matchingParen(src, i);
    if (close <= i) continue;
    // ONLY the first argument (the `makeQuery` lambda) is paged. Spanning the
    // whole argument list would bless a `.from()` appearing in a LATER
    // argument — and `fetchAllByIds`'s second argument is an id list that
    // callers routinely compute inline, e.g.
    //   fetchAllByIds(chunk => …, (await sb.from("users").select("id")).data…)
    // where the id-source read is itself unbounded. Verified as a live bypass
    // of the whole-arg-list version: injecting exactly that into
    // streak-guardian made the gate exit 0.
    final firstArgEnd = _firstArgEnd(src, i, close);
    ranges.add([i, firstArgEnd]);
  }
  return ranges;
}

/// Offset of the top-level `,` ending the first argument of the call whose
/// `(` is at [open] and whose `)` is at [close]; [close] when there is only one
/// argument. Strings are skipped so a comma inside a literal cannot end it.
int _firstArgEnd(String src, int open, int close) {
  var depth = 0;
  var i = open;
  while (i < close) {
    final c = src[i];
    if (c == '"' || c == "'" || c == '`') {
      final quote = c;
      i++;
      while (i < close && src[i] != quote) {
        if (src[i] == r'\') i++;
        i++;
      }
    } else if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (c == ',' && depth == 1) {
      return i;
    }
    i++;
  }
  return close;
}

/// Index of the `)` closing the `(` at [open], skipping string literals so a
/// paren inside a `label:` string cannot unbalance the scan. Returns -1 if
/// unbalanced.
int _matchingParen(String src, int open) {
  var depth = 0;
  var i = open;
  while (i < src.length) {
    final c = src[i];
    if (c == '"' || c == "'" || c == '`') {
      final quote = c;
      i++;
      while (i < src.length && src[i] != quote) {
        if (src[i] == r'\') i++;
        i++;
      }
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

bool _insideAny(List<List<int>> ranges, int offset) =>
    ranges.any((r) => offset > r[0] && offset < r[1]);

int _lineOf(String src, int offset) =>
    '\n'.allMatches(src.substring(0, offset)).length + 1;
