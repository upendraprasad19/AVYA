/// Source-slicing helpers for presence pins (L2b Landing B).
///
/// A pin over comment-stripped, FUNCTION-SLICED source: a comment that quotes
/// the protected statement, or the same statement in another function, must not
/// satisfy it. Brace counting is enough for the sources pinned here (no string
/// literal holds an unbalanced brace; `${...}` interpolations balance).
library;

/// [src] without comments, in ONE left-to-right pass.
///
/// A scanner and not two regex passes: `//` comment text may contain `/*` (a
/// glob such as `features/*/providers/`), which a block-comment pass run first
/// would take for a block start and use to delete real code up to the next
/// `*/`; and a string literal may contain `//` (a URL), which a line pass would
/// cut. Handles `//`, nested `/* */`, single, double, triple-quoted and raw
/// strings, and `${...}` interpolations (braces counted, nested quotes
/// skipped). Newlines inside a block comment are kept, so line counts survive.
String stripDartComments(String src) {
  final out = StringBuffer();
  final n = src.length;
  var i = 0;
  while (i < n) {
    final c = src[i];
    final next = i + 1 < n ? src[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < n && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      var depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (src.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (src.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          if (src[i] == '\n') out.write('\n');
          i++;
        }
      }
      continue;
    }
    if (c == "'" || c == '"') {
      final raw = i > 0 && src[i - 1] == 'r';
      i = _copyString(src, i, out, raw: raw);
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Copies the string literal that opens at [start] to [out]; returns the index
/// just past it.
int _copyString(String src, int start, StringBuffer out, {required bool raw}) {
  final n = src.length;
  final q = src[start];
  final triple = src.startsWith(q * 3, start);
  final close = triple ? q * 3 : q;
  out.write(close);
  var i = start + close.length;
  while (i < n) {
    if (src.startsWith(close, i)) {
      out.write(close);
      return i + close.length;
    }
    final c = src[i];
    if (!raw && c == '\\' && i + 1 < n) {
      out.write(src.substring(i, i + 2));
      i += 2;
      continue;
    }
    if (!raw && c == r'$' && i + 1 < n && src[i + 1] == '{') {
      // Interpolation: copy to the matching brace, skipping nested strings.
      var depth = 0;
      while (i < n) {
        final d = src[i];
        if (d == "'" || d == '"') {
          i = _copyString(src, i, out, raw: false);
          continue;
        }
        out.write(d);
        i++;
        if (d == '{') depth++;
        if (d == '}') {
          depth--;
          if (depth == 0) break;
        }
      }
      continue;
    }
    if (c == '\n' && !triple) {
      // An unterminated single-line literal: stop, so a stray quote cannot
      // swallow the rest of the file.
      return i;
    }
    out.write(c);
    i++;
  }
  return i;
}

/// The body (from its first `{` through the matching `}`) of the function whose
/// header contains [header] in [stripped] (already comment-stripped). The header
/// must include the opening `(` of the parameter list: the parameter list is
/// skipped by paren matching, so a named-parameter `({` is not mistaken for the
/// body. Throws if [header] is absent or occurs more than once, or if the
/// function has an expression body (`=>`) instead of a block.
String functionBody(String stripped, String header) {
  final first = stripped.indexOf(header);
  if (first < 0) throw StateError('header not found: $header');
  if (stripped.indexOf(header, first + 1) >= 0) {
    throw StateError('header occurs more than once: $header');
  }
  final paren = stripped.indexOf('(', first);
  if (paren < 0) throw StateError('no parameter list after: $header');
  var pd = 0;
  var afterParams = -1;
  for (var i = paren; i < stripped.length; i++) {
    final c = stripped[i];
    if (c == '(') pd++;
    if (c == ')') {
      pd--;
      if (pd == 0) {
        afterParams = i + 1;
        break;
      }
    }
  }
  if (afterParams < 0) throw StateError('unbalanced parameters: $header');
  final open = stripped.indexOf('{', afterParams);
  final arrow = stripped.indexOf('=>', afterParams);
  if (open < 0 || (arrow >= 0 && arrow < open)) {
    throw StateError('no block body after: $header');
  }
  var depth = 0;
  for (var i = open; i < stripped.length; i++) {
    final c = stripped[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return stripped.substring(open, i + 1);
    }
  }
  throw StateError('unbalanced body after: $header');
}

/// Number of non-overlapping occurrences of [needle] in [haystack].
int countOf(String haystack, String needle) =>
    needle.allMatches(haystack).length;

/// The braces-balanced block that starts at the first `{` after [header] (a
/// class, mixin or extension header, where there is no parameter list to skip).
/// Throws if [header] is absent or occurs more than once.
String blockBody(String stripped, String header) {
  final first = stripped.indexOf(header);
  if (first < 0) throw StateError('header not found: $header');
  if (stripped.indexOf(header, first + 1) >= 0) {
    throw StateError('header occurs more than once: $header');
  }
  final open = stripped.indexOf('{', first + header.length);
  if (open < 0) throw StateError('no block after: $header');
  var depth = 0;
  for (var i = open; i < stripped.length; i++) {
    final c = stripped[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return stripped.substring(open, i + 1);
    }
  }
  throw StateError('unbalanced block after: $header');
}
