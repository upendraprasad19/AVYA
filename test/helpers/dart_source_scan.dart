// Shared Dart-source scanner for source-guard tests (moved here from
// test/contracts/ist_now_double_shift_behavioral_test.dart, OI-494, so the
// OI-493 food_name reader guard uses the same scanner).

/// [src] with every comment removed. String literals (single, double, triple,
/// raw, and `${...}` interpolations, nested) are kept as written, so a `//`
/// inside a string is not read as a comment. Fails closed: a string's text is
/// kept, so a token written inside a string still counts.
String stripDartComments(String src) {
  final out = StringBuffer();
  // One frame per nesting level: 'code', or the quote that opened a string.
  // A code frame opened by `${` tracks its brace depth so its closing `}`
  // returns to the enclosing string.
  final quotes = <String>['code'];
  final raws = <bool>[false];
  final depths = <int>[0];
  final ident = RegExp(r'[\w$]');
  var i = 0;
  while (i < src.length) {
    final q = quotes.last;
    if (q == 'code') {
      if (src.startsWith('//', i)) {
        while (i < src.length && src[i] != '\n') {
          i++;
        }
        continue;
      }
      if (src.startsWith('/*', i)) {
        var depth = 1;
        i += 2;
        while (i < src.length && depth > 0) {
          if (src.startsWith('/*', i)) {
            depth++;
            i += 2;
          } else if (src.startsWith('*/', i)) {
            depth--;
            i += 2;
          } else {
            i++;
          }
        }
        out.write(' ');
        continue;
      }
      var raw = false;
      var j = i;
      if ((src[i] == 'r' || src[i] == 'R') &&
          i + 1 < src.length &&
          (src[i + 1] == "'" || src[i + 1] == '"') &&
          (i == 0 || !ident.hasMatch(src[i - 1]))) {
        raw = true;
        j = i + 1;
      }
      if (src[j] == "'" || src[j] == '"') {
        final quote = src.startsWith(src[j] * 3, j) ? src[j] * 3 : src[j];
        out.write(src.substring(i, j + quote.length));
        i = j + quote.length;
        quotes.add(quote);
        raws.add(raw);
        depths.add(0);
        continue;
      }
      if (src[i] == '{') {
        depths[depths.length - 1]++;
      } else if (src[i] == '}') {
        if (depths.last == 0 && quotes.length > 1) {
          // closes a `${` interpolation: back to the enclosing string
          quotes.removeLast();
          raws.removeLast();
          depths.removeLast();
        } else {
          depths[depths.length - 1]--;
        }
      }
      out.write(src[i]);
      i++;
      continue;
    }
    // inside a string literal
    if (!raws.last && src[i] == r'\' && i + 1 < src.length) {
      out.write(src.substring(i, i + 2));
      i += 2;
      continue;
    }
    if (src.startsWith(q, i)) {
      out.write(q);
      i += q.length;
      quotes.removeLast();
      raws.removeLast();
      depths.removeLast();
      continue;
    }
    if (!raws.last && src.startsWith(r'${', i)) {
      out.write(r'${');
      i += 2;
      quotes.add('code');
      raws.add(false);
      depths.add(0);
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}
