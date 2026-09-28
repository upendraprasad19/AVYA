/// Pure logic for check_sync_hash_skip_atomicity.dart. Originally the OI-204
/// gate-before-refactor atomicity invariant (CLAUDE.md §4.11) for the
/// exlog/nlog hash-skip mechanism; that count-based check (`checkDomainAtomicity`
/// et al.) was retired in Task 32 of the day-swapper + sync-load batch once
/// both domains moved onto SyncSkipIndex. This file now holds only the G1
/// structural rule below. See
/// docs/superpowers/specs/2026-09-19-oi204-delta-sync-design.md §5.1/§5.2/§6.
library;

import 'sync_no_now_fallback_lib.dart'
    show isSyncLayerPath, stripDartCommentsPreservingLines;

// ─────────────────────────────────────────────────────────────────────────
// G1 structural rule (day-swapper + sync-load batch, spec §7): "sent" can
// only be recorded by SyncSkipIndex.pushIfChanged, which owns the try/catch,
// so a swallowing catch that forgets to flip a flag — the gap the retired
// count-based check could not see (docs/architecture/sync.md, OI-204 B-pass)
// — cannot exist by construction.
// ─────────────────────────────────────────────────────────────────────────

/// Methods whose Supabase writes need not sit inside `pushIfChanged(`:
/// single-row pushes, and the coach loop, which skips by the cloud id it
/// stamps into each Hive row (spec §5.9).
const Set<String> kSyncWriteAllowlist = {
  '_executeUserProfileUpsert',
  '_syncUserProfile',
  '_syncUserPreferences',
  'syncCoachMemoryNow',
  '_syncCoachInteractions',
  'syncFreezes',
  'syncNotificationsInboxEntry',
  'syncSavedDietPlan',
};

/// One Supabase write call in the sync layer.
class SyncWriteCall {
  const SyncWriteCall({
    required this.path,
    required this.line,
    required this.offset,
    required this.verb,
    required this.table,
  });

  final String path;
  final int line;

  /// Offset into the comment-stripped source.
  final int offset;

  /// `upsert`, `insert`, `update` or `delete`.
  final String verb;

  /// The `.from('<table>')` literal, or null for a non-literal table.
  final String? table;
}

class StructuralViolation {
  const StructuralViolation(this.path, this.line, this.kind, this.detail);

  final String path;
  final int line;

  /// `unwrapped_write`, `swallowing_catch`, `catch_error_in_push`,
  /// `index_literal_outside_helper` or `aliased_query_builder`.
  final String kind;
  final String detail;

  @override
  String toString() => '$path:$line [$kind] $detail';
}

final RegExp _writeVerb = RegExp(r'\.(upsert|insert|update|delete)\s*\(');
final RegExp _supabaseFrom =
    RegExp(r'''(?:\.from\(\s*['"]|client\s*\.\s*from\s*\()''');
final RegExp _fromLiteral =
    RegExp(r'''\.from\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s*\)''');
final RegExp _pushIfChangedCall = RegExp(r'\bpushIfChanged\s*\(');
final RegExp _catchClause = RegExp(r'\bcatch\s*\(');
final RegExp _onClause = RegExp(r'\bon\s+[A-Z]\w*(?:<[^>{]*>)?\s*\{');
final RegExp _catchError = RegExp(r'\.catchError\s*\(');
final RegExp _indexLiteral =
    RegExp(r'''['"][^'"\n]*payload_hash_index[^'"\n]*['"]''');

// Fix round 1 (day-swapper + sync-load, spec §7 G1): a `.from(` builder
// stored in a variable evades findSyncWriteCalls entirely, because the
// eventual `.upsert(`/etc. call site is a DIFFERENT statement with no
// `.from(` of its own — the write is real and unwrapped, but structurally
// invisible to the statement-scoped scan above it. Ruling: forbid aliasing
// outright rather than trying to trace it — lexical form is the contract.
final RegExp _assignOp = RegExp(r'(?<![=!<>])=(?!=)(?!>)');
// `.stream(` is terminal too: `_realtimeSubscription = client.from('t')
// .stream(...).listen(...)` (sync_realtime.dart) opens a realtime channel and
// is never later called with a write verb — it is a subscription handle, not
// a query builder stashed for a future `.upsert(`/etc. Confirmed live: this
// is the ONLY assignment of a `.from(` chain anywhere in the current sync
// layer (2026-09-27), and excluding it is what keeps this gate at zero
// false positives on the real tree.
final RegExp _terminalRead = RegExp(r'\.(select|rpc|stream)\s*\(');

const String _skipIndexPath = 'lib/core/services/sync/sync_skip_index.dart';

int _lineOf(String s, int offset) =>
    '\n'.allMatches(s.substring(0, offset)).length + 1;

final RegExp _exitStatement = RegExp(r'^(?:rethrow|return\s+false)\s*;$');

/// Whether a `{ ... }` catch block ENDS in an unconditional `rethrow;` or
/// `return false;` — its LAST top-level statement, not a token anywhere in
/// its text. B-pass R4-F2: the first version accepted `rethrow` anywhere, so
/// `catch (e) { if (false) { rethrow; } }` — a catch that always swallows —
/// passed. A conditional exit may still precede the final one
/// (`if (!x) rethrow; return false;` is the live 23503 shape).
///
/// Residue, stated plainly: this is still a text scan. A final `rethrow;`
/// inside an unreachable region after an earlier `return` is not modelled,
/// and a block whose branches ALL exit (`if (a) { rethrow; } else { return
/// false; }`) is rejected — write it with a trailing exit instead.
bool endsInUnconditionalExit(String block) {
  final inner = block.substring(1, block.length - 1);
  var depth = 0;
  String? quote;
  var segStart = 0;
  String? lastStatement;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
        continue;
      }
      if (c == quote) quote = null;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      continue;
    }
    if (c == '(' || c == '{' || c == '[') {
      depth++;
      continue;
    }
    if (c == ')' || c == '}' || c == ']') {
      depth--;
      if (depth == 0 && c == '}') {
        lastStatement = inner.substring(segStart, i + 1);
        segStart = i + 1;
      }
      continue;
    }
    if (c == ';' && depth == 0) {
      lastStatement = inner.substring(segStart, i + 1);
      segStart = i + 1;
    }
  }
  if (inner.substring(segStart).trim().isNotEmpty) return false;
  return _exitStatement.hasMatch((lastStatement ?? '').trim());
}

/// Offset of the bracket that closes the one at [openIndex] (same bracket
/// type), skipping string literals. Returns the last offset when unbalanced.
int _matchingClose(String s, int openIndex) {
  final open = s[openIndex];
  final close = open == '(' ? ')' : (open == '{' ? '}' : ']');
  var depth = 0;
  String? quote;
  for (var i = openIndex; i < s.length; i++) {
    final c = s[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
        continue;
      }
      if (c == quote) quote = null;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      continue;
    }
    if (c == open) {
      depth++;
    } else if (c == close) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return s.length - 1;
}

/// Every Supabase write in [stripped] (already comment-stripped). A write's
/// statement runs from the previous `;`, `{` or `}` to the verb; it counts
/// only when that statement contains a Supabase `.from(` (a quoted literal or
/// `client.from(`), which excludes Hive `box.delete(k)` and `List.insert`.
List<SyncWriteCall> findSyncWriteCalls(String path, String stripped) {
  final calls = <SyncWriteCall>[];
  for (final m in _writeVerb.allMatches(stripped)) {
    var start = m.start;
    while (start > 0 && !';{}'.contains(stripped[start - 1])) {
      start--;
    }
    final statement = stripped.substring(start, m.start);
    if (!_supabaseFrom.hasMatch(statement)) continue;
    final literals = _fromLiteral.allMatches(statement).toList();
    calls.add(SyncWriteCall(
      path: path,
      line: _lineOf(stripped, m.start),
      offset: m.start,
      verb: m.group(1)!,
      table: literals.isEmpty ? null : literals.last.group(1),
    ));
  }
  return calls;
}

/// The argument-list spans `(open, close)` of every `pushIfChanged(` call.
List<(int, int)> _pushSpans(String s) => [
      for (final m in _pushIfChangedCall.allMatches(s))
        (m.end - 1, _matchingClose(s, m.end - 1)),
    ];

/// The declaration-to-body-end spans of every method named in [names].
List<(int, int)> _methodSpans(String s, Set<String> names) {
  final spans = <(int, int)>[];
  for (final name in names) {
    final decl = RegExp(
        r'(?:Future(?:<[^;{()]*>)?|void)\s+' + RegExp.escape(name) + r'\s*\(');
    for (final m in decl.allMatches(s)) {
      final paramsEnd = _matchingClose(s, m.end - 1);
      final brace = s.indexOf('{', paramsEnd);
      final arrow = s.indexOf('=>', paramsEnd);
      if (arrow >= 0 && (brace < 0 || arrow < brace)) {
        final end = s.indexOf(';', arrow);
        spans.add((m.start, end < 0 ? s.length - 1 : end));
      } else if (brace >= 0) {
        spans.add((m.start, _matchingClose(s, brace)));
      }
    }
  }
  return spans;
}

/// Tables written by the sync layer. [sourcesByPath] holds RAW sources keyed
/// by repo-relative path; comments are stripped here.
Set<String> enumerateSyncWriteTables(Map<String, String> sourcesByPath) => {
      for (final e in sourcesByPath.entries)
        if (isSyncLayerPath(e.key))
          for (final c in findSyncWriteCalls(
              e.key, stripDartCommentsPreservingLines(e.value)))
            if (c.table != null) c.table!,
    };

/// Every statement in the sync layer that DECLARES OR ASSIGNS a Supabase
/// query builder to a variable instead of executing it inline —
/// `final row = _supabase.client.from('t');` — rather than writing the chain
/// inline where `findSyncWriteCalls` can see the write. A statement counts
/// only when it has an assignment `=` before the `.from(`, contains no write
/// verb of its own (that shape is an executed write already governed by the
/// `unwrapped_write` rule above) and no terminal read (`.select(`/`.rpc(`,
/// which executes the builder rather than storing it).
List<StructuralViolation> _findAliasedQueryBuilders(String path, String s) {
  final out = <StructuralViolation>[];
  final seenStarts = <int>{};
  for (final m in _supabaseFrom.allMatches(s)) {
    var start = m.start;
    while (start > 0 && !';{}'.contains(s[start - 1])) {
      start--;
    }
    if (!seenStarts.add(start)) continue;
    final semi = s.indexOf(';', m.start);
    final end = semi < 0 ? s.length : semi;
    final statement = s.substring(start, end);
    final beforeFrom = s.substring(start, m.start);
    if (!_assignOp.hasMatch(beforeFrom)) continue;
    if (_writeVerb.hasMatch(statement)) continue;
    if (_terminalRead.hasMatch(statement)) continue;
    out.add(StructuralViolation(path, _lineOf(s, m.start), 'aliased_query_builder',
        'store no Supabase query builder in a variable — write the chain '
        'inline so G1 can see the write (spec §7)'));
  }
  return out;
}

/// The G1 structural check over RAW sources keyed by repo-relative path.
List<StructuralViolation> checkSyncStructure(
  Map<String, String> sourcesByPath, {
  Set<String> allowlist = kSyncWriteAllowlist,
}) {
  final out = <StructuralViolation>[];
  for (final entry in sourcesByPath.entries) {
    final path = entry.key.replaceAll(r'\', '/');
    if (!isSyncLayerPath(path)) continue;
    final s = stripDartCommentsPreservingLines(entry.value);
    final pushSpans = _pushSpans(s);
    final allowed = _methodSpans(s, allowlist);
    bool inside(List<(int, int)> spans, int o) =>
        spans.any((sp) => o > sp.$1 && o < sp.$2);

    for (final call in findSyncWriteCalls(path, s)) {
      if (inside(pushSpans, call.offset) || inside(allowed, call.offset)) {
        continue;
      }
      out.add(StructuralViolation(path, call.line, 'unwrapped_write',
          '.${call.verb}( on ${call.table ?? '<non-literal table>'} is outside '
          'pushIfChanged( and outside the allowlist (spec §7 G1)'));
    }

    out.addAll(_findAliasedQueryBuilders(path, s));

    for (final sp in pushSpans) {
      final body = s.substring(sp.$1, sp.$2 + 1);
      for (final m in _catchClause.allMatches(body)) {
        final parenEnd = _matchingClose(s, sp.$1 + m.end - 1);
        final brace = s.indexOf('{', parenEnd);
        if (brace < 0 || brace > sp.$2) continue;
        final block = s.substring(brace, _matchingClose(s, brace) + 1);
        if (!endsInUnconditionalExit(block)) {
          out.add(StructuralViolation(path, _lineOf(s, sp.$1 + m.start),
              'swallowing_catch',
              'a catch inside pushIfChanged( must END in `rethrow;` or `return false;`'));
        }
      }
      for (final m in _onClause.allMatches(body)) {
        final brace = sp.$1 + m.end - 1;
        final block = s.substring(brace, _matchingClose(s, brace) + 1);
        if (!endsInUnconditionalExit(block)) {
          out.add(StructuralViolation(path, _lineOf(s, sp.$1 + m.start),
              'swallowing_catch',
              'an `on T {` block inside pushIfChanged( must END in `rethrow;` or `return false;`'));
        }
      }
      for (final m in _catchError.allMatches(body)) {
        out.add(StructuralViolation(path, _lineOf(s, sp.$1 + m.start),
            'catch_error_in_push',
            '.catchError( inside pushIfChanged( hides a failed push'));
      }
    }

    if (path != _skipIndexPath) {
      for (final m in _indexLiteral.allMatches(s)) {
        out.add(StructuralViolation(path, _lineOf(s, m.start),
            'index_literal_outside_helper',
            '${m.group(0)} — index keys live only in SyncSkipDomain '
            '($_skipIndexPath)'));
      }
    }
  }
  return out;
}
