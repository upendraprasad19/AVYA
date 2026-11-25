// Roman numerals for phase labels (OI-348 Landing 3a, P1 "all phases").
//
// Phases do not stop at XII: the generator keeps producing phases past 12
// (`plan_engine/plan_generator.dart` `_getPhaseMeta`), so every label must
// render XIII, XIV, ... The 1-12 lookup maps this replaces fell back to an
// arabic "13", so a PRO user in Phase XI saw "PHASE 13" for the phase two
// ahead in the week selector.
//
// ONE converter, both directions. Every phase label goes through
// `phaseRoman` (`hold_week_labels.dart`), which delegates here; the preview
// route parses with [fromRoman]. Test: test/core/roman_numeral_test.dart,
// single-source pin test/contracts/phase_roman_single_source_test.dart.

const List<(int, String)> _romanTable = [
  (1000, 'M'),
  (900, 'CM'),
  (500, 'D'),
  (400, 'CD'),
  (100, 'C'),
  (90, 'XC'),
  (50, 'L'),
  (40, 'XL'),
  (10, 'X'),
  (9, 'IX'),
  (5, 'V'),
  (4, 'IV'),
  (1, 'I'),
];

/// Standard subtractive Roman numeral for [n] in 1..3999; any other value is
/// returned as its decimal digits (never throws).
String toRoman(int n) {
  if (n < 1 || n > 3999) return '$n';
  final out = StringBuffer();
  var rest = n;
  for (final (value, glyph) in _romanTable) {
    while (rest >= value) {
      out.write(glyph);
      rest -= value;
    }
  }
  return out.toString();
}

/// Parses a CANONICAL upper-case Roman numeral (the exact form [toRoman]
/// produces) and returns its value, or null for anything else: lower case,
/// spaces, non-canonical forms such as `IIII` or `IC`, or an empty string.
int? fromRoman(String s) {
  if (s.isEmpty) return null;
  const values = {
    'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000,
  };
  var total = 0;
  for (var i = 0; i < s.length; i++) {
    final v = values[s[i]];
    if (v == null) return null;
    final next = i + 1 < s.length ? values[s[i + 1]] : null;
    if (next != null && next > v) {
      total -= v;
    } else {
      total += v;
    }
  }
  // Canonical only: a string that does not round-trip is not a numeral this
  // app ever wrote.
  return (total >= 1 && total <= 3999 && toRoman(total) == s) ? total : null;
}
