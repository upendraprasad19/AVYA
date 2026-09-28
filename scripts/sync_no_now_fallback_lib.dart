/// Pure core of scripts/check_sync_no_now_fallback.dart — gate G2 of the
/// day-swapper + sync-load batch (spec §5.12, §7).
///
/// A sync payload must never send "now" as the fallback for a timestamp that
/// describes the past (`created_at`, `completed_at`, `read_at`, ...). A row
/// that is pushed on every pass would otherwise re-stamp its history with the
/// current time — the recurrence of 5a36ad ("completed_at overwritten to NOW
/// on every sync"). The fallback order is: the recorded value, then a value
/// derived from a `*_ms` sibling or the Hive key, then OMIT the field (the
/// database keeps what it has; on insert the column default applies).
library;

/// The files gates G1 and G2 scan: the whole sync layer.
bool isSyncLayerPath(String relPath) {
  final p = relPath.replaceAll(r'\', '/');
  if (p == 'lib/core/services/sync_service.dart') return true;
  return p.startsWith('lib/core/services/sync/') && p.endsWith('.dart');
}

/// Strips `//` and `/* */` comments. String-aware (a `//` inside '...' or
/// "..." is kept) and newline-preserving (a block comment keeps its line
/// breaks), so every line number reported afterwards is exact.
///
/// Limitation, shared with stripDartComments in
/// scripts/schedule_row_builder_gate_lib.dart: quotes are tracked one
/// character at a time, so a lone quote inside a triple-quoted string, or a
/// raw string ending in a backslash, can desynchronise the scan. The sync
/// layer contains neither (checked when this gate was written).
String stripDartCommentsPreservingLines(String source) {
  final out = StringBuffer();
  var i = 0;
  String? quote;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (quote != null) {
      if (c == r'\' && next.isNotEmpty) {
        out
          ..write(c)
          ..write(next);
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      out.write(c);
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      out.write(c);
      i++;
      continue;
    }
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i < source.length &&
          !(source[i] == '*' && i + 1 < source.length && source[i + 1] == '/')) {
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      i += 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// One past-timestamp field that falls back to "now".
class NowFallbackFinding {
  const NowFallbackFinding(this.path, this.line, this.field);

  final String path;
  final int line;

  /// The payload key being assigned, e.g. `created_at`; `?` when no
  /// `'key':` precedes the fallback within 240 characters.
  final String field;

  /// `'<file basename>|<field>'` — stable across line-number drift.
  String get key => '${path.split('/').last}|$field';

  @override
  String toString() => '$path:$line  `$field` falls back to "now"';
}

/// `?? DateTime.now()`, `?? DateTime.timestamp()`, `?? nowWall()` and
/// `?? istNow()` — and the compound-assignment spelling of the same fallback,
/// `x ??= DateTime.now()` (B-pass R4-F1: the `=` defeated the first version).
/// `\s` spans newlines, so a `??` at a line end still matches.
///
/// Residue, stated so nobody mistakes this grep for proof: a fallback routed
/// through a local (`final now = DateTime.now(); a ?? now`) or a helper is
/// invisible to it. The behavioural guards for the class assert VALUES, not
/// source text: test/sync/schedule_completion_time_test.dart (the resolver's
/// output) and the per-domain push tests under test/sync/ that read the row
/// the stub received (e.g. weight_skip_test.dart's derived `created_at`).
final RegExp nowFallbackPattern = RegExp(
    r'\?\?=?\s*(?:DateTime\s*\.\s*(?:now|timestamp)|nowWall|istNow)\s*\(');

final RegExp _fieldKey = RegExp(r'''['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s*:''');

/// Every now-fallback in [source] (comment-stripped first).
List<NowFallbackFinding> findNowFallbacks(String relPath, String source) {
  final path = relPath.replaceAll(r'\', '/');
  final stripped = stripDartCommentsPreservingLines(source);
  final findings = <NowFallbackFinding>[];
  for (final m in nowFallbackPattern.allMatches(stripped)) {
    final line = '\n'.allMatches(stripped.substring(0, m.start)).length + 1;
    final windowStart = m.start > 240 ? m.start - 240 : 0;
    final keys = _fieldKey.allMatches(stripped.substring(windowStart, m.start)).toList();
    findings.add(NowFallbackFinding(path, line, keys.isEmpty ? '?' : keys.last.group(1)!));
  }
  return findings;
}
