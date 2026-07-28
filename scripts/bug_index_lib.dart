// scripts/bug_index_lib.dart
//
// Pure helpers for scripts/build_bug_index.dart, split out so they are
// unit-testable (test/contracts/bug_index_frontmatter_test.dart). Same reason
// plan_review_record_lib.dart exists: a decision that gates discipline should
// be exercisable without spawning the whole generator.
//
// THE BUG THESE EXIST TO PREVENT. `docs/diagnoses/INDEX.md` carried no symptom
// text for 237 of its 344 entries. The generator did
// `symptom?.toString().split('\n').first`, which on a YAML block scalar
// (`symptom: >`) returns the bare INDICATOR — the folded body sits on the
// following lines and was never read. CLAUDE.md §4.1.5 makes grepping that
// index the mandatory first step before any root-cause hypothesis, so 70% of
// bug history was unsearchable by symptom while the file looked populated.

/// A bare YAML block-scalar indicator: `|`, `|-`, `|+`, `>`, `>-`, `>+`.
final blockScalarRe = RegExp(r'^[|>][-+]?$');

/// One-line, greppable summary of a possibly multi-paragraph field.
///
/// `.split('\n').first` is wrong twice over: on an unfolded block scalar it
/// yields the indicator, and on a correctly folded one it yields only the FIRST
/// PARAGRAPH — which for `2026-05-15-sync-null-key-guard-9f4ab2.md` is
/// "Hypothetical (defence-in-depth) — no production occurrence yet." and drops
/// the entire data-loss description. Flatten instead, then cap.
String summarize(Object? value, {String fallback = '', int maxLen = 200}) {
  final flat = (value?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return fallback;
  if (flat.length <= maxLen) return flat;
  final cut = flat.lastIndexOf(' ', maxLen);
  return '${flat.substring(0, cut > 0 ? cut : maxLen).trimRight()}…';
}

/// Folded (`>`) semantics: consecutive lines join with a space, a blank line
/// becomes a paragraph break.
String foldScalar(List<String> lines) {
  final buf = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].isEmpty) {
      buf.write('\n');
      continue;
    }
    if (i > 0 && lines[i - 1].isNotEmpty) buf.write(' ');
    buf.write(lines[i]);
  }
  return buf.toString();
}

/// Minimal YAML frontmatter reader — top-level scalar keys plus block scalars.
/// Complex shapes (`writers:` lists) are intentionally not parsed; the
/// diagnose-doc validator covers those.
Map<String, dynamic>? parseFrontmatter(String content) {
  // Normalize line endings so CRLF (Windows) files parse the same as LF.
  final normalized = content.replaceAll('\r\n', '\n');
  final match = RegExp(r'^---\n(.*?)\n---', dotAll: true).firstMatch(normalized);
  if (match == null) return null;
  final out = <String, dynamic>{};
  final lines = match.group(1)!.split('\n');
  final keyRe = RegExp(r'^([a-z_]+):\s*(.*)$');

  for (var i = 0; i < lines.length; i++) {
    final m = keyRe.firstMatch(lines[i]);
    if (m == null) continue;
    final key = m.group(1)!;
    final value = m.group(2)!.trim();
    if (value.isEmpty) continue;

    if (!blockScalarRe.hasMatch(value)) {
      out[key] = value;
      continue;
    }

    // Block scalar — the real text is on the following indented lines.
    //
    // A BLANK LINE IS CONTENT, NOT A TERMINATOR. 36 diagnose docs have a
    // paragraph break inside `symptom:`; stopping at the first blank line
    // truncates them to their opening sentence while STILL passing a
    // placeholder check, because the value is no longer literally `>`. Only a
    // line that is non-blank AND back at key indentation ends the scalar.
    final collected = <String>[];
    var j = i + 1;
    while (j < lines.length) {
      final l = lines[j];
      if (l.trim().isEmpty) {
        collected.add('');
        j++;
        continue;
      }
      if (!l.startsWith(' ') && !l.startsWith('\t')) break;
      collected.add(l.trim());
      j++;
    }
    while (collected.isNotEmpty && collected.last.isEmpty) {
      collected.removeLast();
    }
    // Literal (`|`) keeps line breaks; folded (`>`) joins.
    out[key] =
        value.startsWith('|') ? collected.join('\n') : foldScalar(collected);
    i = j - 1;
  }
  return out;
}
