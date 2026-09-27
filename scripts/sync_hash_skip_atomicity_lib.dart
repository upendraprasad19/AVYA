/// Pure logic for check_sync_hash_skip_atomicity.dart (OI-204 gate-before-refactor,
/// CLAUDE.md §4.11). Verifies the atomicity invariant the OI-204 fingerprint-skip
/// design requires: a sync fingerprint may only be recorded as "confirmed pushed"
/// when every constituent network write for that key/slot succeeded. See
/// docs/superpowers/specs/2026-09-19-oi204-delta-sync-design.md §5.1/§5.2/§6.
library;

import 'sync_no_now_fallback_lib.dart'
    show isSyncLayerPath, stripDartCommentsPreservingLines;

class HashSkipDomainSpec {
  final String flagName;
  final String indexAssignPrefix;
  final String fingerprintVarName;
  final int expectedSwallowCatches;

  const HashSkipDomainSpec({
    required this.flagName,
    required this.indexAssignPrefix,
    required this.fingerprintVarName,
    required this.expectedSwallowCatches,
  });
}

const exlogSpec = HashSkipDomainSpec(
  flagName: 'exlogBundleSynced',
  indexAssignPrefix: 'exlogHashIndex[',
  fingerprintVarName: 'fp',
  expectedSwallowCatches: 1,
);

const nlogSpec = HashSkipDomainSpec(
  flagName: 'nlogSlotSynced',
  indexAssignPrefix: 'nlogHashIndex[',
  fingerprintVarName: 'nlogFp',
  expectedSwallowCatches: 2,
);

/// Strips `//` line comments so a comment mentioning the flag/store cannot
/// satisfy the checks below. Not string-literal-aware — matches this repo's
/// existing comment-stripping gates (good enough for Dart source; a `//`
/// inside a string literal in these two files would be unusual and is an
/// accepted limitation, same as the other comment-stripping gates in this repo).
String stripLineComments(String source) {
  final out = StringBuffer();
  for (final line in source.split('\n')) {
    final idx = line.indexOf('//');
    out.writeln(idx == -1 ? line : line.substring(0, idx));
  }
  return out.toString();
}

class AtomicityViolation {
  final String message;
  AtomicityViolation(this.message);
}

/// Returns null when the domain's mechanism doesn't exist YET in [source]
/// (vacuously fine — nothing to check before the flag is introduced) or is
/// fully correct. Returns a violation describing exactly what's wrong otherwise.
AtomicityViolation? checkDomainAtomicity(String source, HashSkipDomainSpec spec) {
  final stripped = stripLineComments(source);
  final declRe = RegExp('bool\\s+${spec.flagName}\\s*=\\s*true\\s*;');
  // OI-204 C1 (plan-review round 1): the store must be an ASSIGNMENT of the
  // confirmed fingerprint specifically — `<indexAssignPrefix>...] = <fpVar>;`
  // — not merely a line containing the index-variable substring. The real
  // code has TWO other lines that contain that bare substring and are NOT
  // stores: the preamble's index-hydration loop (`exlogHashIndex[k] = v;`,
  // an assignment too, but of the hydration value `v`, never the fingerprint
  // var) and the skip-check's read (`storedFingerprint: exlogHashIndex[key],`
  // — no `=` follows the `]` at all). Requiring the specific fingerprint
  // variable name as the assigned value excludes both by construction.
  final storeRe = RegExp(
      '${RegExp.escape(spec.indexAssignPrefix)}[^\\]]*\\]\\s*=\\s*${spec.fingerprintVarName}\\s*;');

  final hasDecl = declRe.hasMatch(stripped);
  final hasStore = storeRe.hasMatch(stripped);

  if (!hasDecl && !hasStore) return null;

  if (hasStore && !hasDecl) {
    return AtomicityViolation(
        '${spec.indexAssignPrefix} is written but ${spec.flagName} is never declared '
        'true — the store is unconditional, violating the atomicity requirement.');
  }
  if (hasDecl && !hasStore) {
    return AtomicityViolation(
        '${spec.flagName} is declared but ${spec.indexAssignPrefix} is never '
        'assigned from ${spec.fingerprintVarName} — the flag is dead.');
  }

  final lines = stripped.split('\n');
  // OI-204 B-pass Finding 1 (2026-09-19): `storeRe`'s `\s*` matches `\n`
  // (Dart's `\s` spans newlines regardless of any regex flag), so `hasStore`
  // above tolerates a store statement wrapped across two lines (e.g. by
  // `dart format` on a line past 80 columns) -- but re-running `storeRe`
  // against each SPLIT line in isolation, as this used to do, can never
  // match either half. That silently emptied `storeLineIdxs`, skipped the
  // guard-scan loop entirely, and let an UNGUARDED multi-line store pass as
  // if it were vacuously fine. Fixed by finding matches against the SAME
  // whole `stripped` text `hasStore` uses, then mapping each match's START
  // offset to a line index -- so both checks agree on what counts as "a
  // store", regardless of how many lines it spans.
  int lineIndexForOffset(int offset) {
    var pos = 0;
    for (var i = 0; i < lines.length; i++) {
      final lineEnd = pos + lines[i].length;
      if (offset <= lineEnd) return i;
      pos = lineEnd + 1; // +1 for the '\n' this split() consumed.
    }
    return lines.length - 1;
  }

  final storeLineIdxs = <int>[
    for (final m in storeRe.allMatches(stripped)) lineIndexForOffset(m.start),
  ];
  // The flag may appear anywhere inside an `if (...)` condition, not only as
  // the sole condition — the real code guards with `if (flagName && fp !=
  // null)` (spec §5.4's fingerprint-failure safety net adds the second
  // clause), so the check must accept a compound condition. It must NOT
  // accept a NEGATED flag (`if (!flagName)`) as a guard — that shape stores
  // exactly when sync failed, which is backwards — so any line matching the
  // positive form is discarded if it also contains the negated form.
  final guardRe = RegExp('if\\s*\\([^)]*\\b${spec.flagName}\\b[^)]*\\)');
  final negatedRe = RegExp('!\\s*${spec.flagName}\\b');
  for (final lineIdx in storeLineIdxs) {
    var guarded = false;
    for (var back = lineIdx; back >= 0 && lineIdx - back < 6; back--) {
      if (guardRe.hasMatch(lines[back]) && !negatedRe.hasMatch(lines[back])) {
        guarded = true;
        break;
      }
    }
    if (!guarded) {
      return AtomicityViolation(
          'Line ${lineIdx + 1}: ${spec.indexAssignPrefix} store is not visibly '
          'guarded by a positive `if (... ${spec.flagName} ...)` within 6 lines '
          'above it (a negated `if (!${spec.flagName})` does not count as a guard).');
    }
  }

  final setFalseCount =
      RegExp('${spec.flagName}\\s*=\\s*false\\s*;').allMatches(stripped).length;
  if (setFalseCount != spec.expectedSwallowCatches) {
    return AtomicityViolation(
        '${spec.flagName} is set false in $setFalseCount place(s); expected '
        'exactly ${spec.expectedSwallowCatches} (one per swallowing catch block '
        'for this domain). A mismatch means either a new swallowing catch forgot '
        'to guard the flag, or the expected count in '
        'sync_hash_skip_atomicity_lib.dart is stale.');
  }

  return null;
}

// ─────────────────────────────────────────────────────────────────────────
// G1 structural rule (day-swapper + sync-load batch, spec §7). Replaces the
// count-based check above once every domain pushes through SyncSkipIndex:
// "sent" can only be recorded by SyncSkipIndex.pushIfChanged, which owns the
// try/catch, so a swallowing catch that forgets to flip a flag — the gap the
// count-based check cannot see (docs/architecture/sync.md, OI-204 B-pass) —
// cannot exist by construction.
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

  /// `unwrapped_write`, `swallowing_catch`, `catch_error_in_push` or
  /// `index_literal_outside_helper`.
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
final RegExp _rethrowOrFalse = RegExp(r'\brethrow\b|\breturn\s+false\s*;');
final RegExp _indexLiteral =
    RegExp(r'''['"][^'"\n]*payload_hash_index[^'"\n]*['"]''');

const String _skipIndexPath = 'lib/core/services/sync/sync_skip_index.dart';

int _lineOf(String s, int offset) =>
    '\n'.allMatches(s.substring(0, offset)).length + 1;

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

    for (final sp in pushSpans) {
      final body = s.substring(sp.$1, sp.$2 + 1);
      for (final m in _catchClause.allMatches(body)) {
        final parenEnd = _matchingClose(s, sp.$1 + m.end - 1);
        final brace = s.indexOf('{', parenEnd);
        if (brace < 0 || brace > sp.$2) continue;
        final block = s.substring(brace, _matchingClose(s, brace) + 1);
        if (!_rethrowOrFalse.hasMatch(block)) {
          out.add(StructuralViolation(path, _lineOf(s, sp.$1 + m.start),
              'swallowing_catch',
              'a catch inside pushIfChanged( must `rethrow` or `return false;`'));
        }
      }
      for (final m in _onClause.allMatches(body)) {
        final brace = sp.$1 + m.end - 1;
        final block = s.substring(brace, _matchingClose(s, brace) + 1);
        if (!_rethrowOrFalse.hasMatch(block)) {
          out.add(StructuralViolation(path, _lineOf(s, sp.$1 + m.start),
              'swallowing_catch',
              'an `on T {` block inside pushIfChanged( must `rethrow` or `return false;`'));
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
