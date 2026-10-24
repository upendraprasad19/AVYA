// test/contracts/payment_log_safety_writer_to_reader_test.dart
//
// payment-hardening U0 (OI-360, diagnose d1a4f6). A payment-path log line carries a code, a type, a shape or a
// bounded value (supabase/functions/_shared/payment_log_safe.ts), never a whole object: a PostgREST error's
// `details` echoes the failing row (the Razorpay signature included), a Razorpay body or the notes can carry
// customer data, and a raw client string can forge a line. Writer: the helpers. Readers: every console call in
// the three payment functions and the payment alert module they call. Behaviour: each writer's "U0 log:" Deno
// tests (origin/main must SHOW the secret, the new handler must not) and _shared/payment_log_safe_test.ts.
//
// This file pins the SHAPE of every console call in source (any method: error, warn, log, info, debug, ...):
//   1. ONE argument, built only from string/template literals joined by `+` (or `(x ? literal : literal)`), so a
//      message assembled in a variable, a concatenated value or a second argument cannot carry an object;
//      the outer catch-alls the plan leaves unchanged are the only exceptions (their reachable throws carry
//      no row data);
//   2. every `${...}` in those literals is a value CLASSIFIED for that file in [_allowed], and no entry is stale;
//   3. a line held in a variable until the branch is known ([_messageVariables]) is checked where it is BUILT:
//      every assignment to it obeys 1 and 2, and every other mention of the name is one of those assignments
//      or a `${name}` in a console line (so a destructuring, a loop variable or a second use cannot fill it);
//   4. `console` appears only as `console.<method>(`, and neither the dynamic-global doors (globalThis, Reflect,
//      window, self, eval, Function: deliberately banned NAMES, so a local called `window` must be renamed) nor
//      the direct stream doors appear (`Deno` only as `Deno.<name>`, never `Deno.stderr`, `.stdout`, `.core`), so no alias,
//      bracket lookup or raw write reaches the logs unseen.
// Every name is matched in code with literal TEXT blanked, so a word inside a string is never code; regex
// literals are recognised (a quote or `//` inside one is not a string or a comment), and every file's raw count
// of `console.<method>(` must equal the calls the scan sees, so a desynchronised scan cannot hide a call.
// Comments are stripped by a quote-aware scanner, so a `//` inside a literal is text, not a comment.
//
// Run: flutter test test/contracts/payment_log_safety_writer_to_reader_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _functions = [
  'supabase/functions/verify-payment/index.ts',
  'supabase/functions/razorpay-webhook/index.ts',
  'supabase/functions/create-razorpay-order/index.ts',
];

/// Scanned too: the payment functions call it on the money path (it predates this batch and logs ids only).
const _alertModule = 'supabase/functions/_shared/payment_alert.ts';

const _scanned = [..._functions, _alertModule];

/// The outer catch-all calls kept with a second argument (plan section 3, "Unchanged, with reason").
const _allowedTwoArg = {
  'console.error(`[verify-payment] request_id=\${requestId}`, err)',
  'console.error(`[create-razorpay-order] request_id=\${requestId}`, e)',
  'console.error(`[razorpay-webhook] request_id=\${requestId}`, err)',
};

/// Per file, every `${...}` a console call may interpolate. Classes: a payment_log_safe.ts helper call (a code,
/// a type name, a shape, bounded and quoted text); an id checked before any log (verify-payment
/// isValidPaymentId, the webhook's pay_ and UUID checks, a JWT user id) or generated here; a number, boolean,
/// constant or value derived here (the plan comes from the amount, or after the monthly/yearly check); an HTTP
/// status. Per FILE because a name is not a class: create-razorpay-order's `plan` is raw client text until its
/// validation. A new interpolation is classified here, after checking it cannot carry a row, a body or raw
/// client text.
const Map<String, Set<String>> _allowed = {
  'supabase/functions/verify-payment/index.ts': {
    r'razorpayResponse.status', // HTTP status
    r'failId', // checked or generated id
    r'paymentId', // checked or generated id
    r'stackFailId', // checked or generated id
    r'userId', // checked or generated id
    r'boundedText(clientClaimedPlan)', // helper
    r'boundedText(promoCode)', // helper
    r'boundedText(razorpayResponse.statusText)', // helper
    r'codeToken(rec.code)', // helper
    r'errorName(e)', // helper
    r'pgErrorCode(e)', // helper
    r'pgErrorCode(incErr)', // helper
    r'pgErrorCode(insertError)', // helper
    r'pgErrorCode(preSelectError)', // helper
    r'pgErrorCode(rateErr)', // helper
    r'pgErrorCode(useErr)', // helper
    r'razorpayErrorSummary(captureResp.status, body)', // helper
    r'RATE_LIMIT_MAX', // number / boolean / constant / derived value
    r'RATE_LIMIT_QUOTA_KEY', // number / boolean / constant / derived value
    r'actualPaise', // number / boolean / constant / derived value
    r"isInactive ? 'inactive' : isExpired ? 'expired' : 'exhausted'", // number / boolean / constant / derived value
    r'plan', // number / boolean / constant / derived value
    r'rec.inserted', // number / boolean / constant / derived value
    r'stackingOn ? "on" : "off"', // number / boolean / constant / derived value
  },
  'supabase/functions/razorpay-webhook/index.ts': {
    r'paymentEntity.id', // checked or generated id
    r'razorpayPaymentId', // checked or generated id
    r'stackFailId', // checked or generated id
    r'userId', // checked or generated id
    r'boundedText(clientClaimedPlan)', // helper
    r'boundedText(promoCode)', // helper
    r'codeToken(rec.code)', // helper
    r'errorName(e)', // helper
    r'notesShape(notes)', // helper
    r'pgErrorCode(e)', // helper
    r'pgErrorCode(incErr)', // helper
    r'pgErrorCode(insertError)', // helper
    r'pgErrorCode(useErr)', // helper
    r'razorpayErrorSummary(captureResp.status, body)', // helper
    r'Math.round(ageSec)', // number / boolean / constant / derived value
    r'String(userId).length', // number / boolean / constant / derived value
    r'actualPaise', // number / boolean / constant / derived value
    r'expectedPaise', // number / boolean / constant / derived value
    r"isInactive ? 'inactive' : isExpired ? 'expired' : 'exhausted'", // number / boolean / constant / derived value
    r'plan', // number / boolean / constant / derived value
    r'rec.inserted', // number / boolean / constant / derived value
    r'stackingOn ? "on" : "off"', // number / boolean / constant / derived value
    r'typeof userId', // number / boolean / constant / derived value
  },
  'supabase/functions/create-razorpay-order/index.ts': {
    r'requestId', // checked or generated id
    r'boundedText(promoCode)', // helper
    r'guardError ? pgErrorCode(guardError) : "no_rows_array"', // helper
    r'razorpayErrorSummary(orderResp.status, body)', // helper
    r'isExhausted', // number / boolean / constant / derived value
    r'isExpired', // number / boolean / constant / derived value
  },
  'supabase/functions/_shared/payment_alert.ts': {
    r'a.paymentId', // checked or generated id
    r'c.paymentId', // checked or generated id
    r'c.userId', // checked or generated id
    r'c.fn', // number / boolean / constant / derived value
    r'(e as { name?: string })?.name ?? "error"', // the name of a library throw (as errorName)
  },
};

/// Per file, the variables that hold a log line until the branch is known (the webhook logs its capture refusal
/// only when the recovery does not apply). A console call may interpolate one because every assignment to it is
/// checked like a console argument (rule 3 in the header).
const Map<String, Set<String>> _messageVariables = {
  'supabase/functions/razorpay-webhook/index.ts': {'refusal'},
};

// ── a small TypeScript scanner: literals, nesting, comments ──

/// The dynamic-global names refused by rule 4.
const _dynamicGlobals = ['globalThis', 'Reflect', 'window', 'self', 'eval', 'Function'];

/// Rule 4's stream doors: `Deno` may be used only as `Deno.<name>`, and never with these names.
const _streamDoors = {'stderr', 'stdout', 'core'};

/// Every refused use of `Deno` in [blanked]: not `Deno.<name>`, or one of [_streamDoors].
List<String> _denoDoors(String blanked) => [
      for (final at in _mentions(blanked, 'Deno'))
        if (RegExp(r'Deno\.(\w+)').matchAsPrefix(blanked, at) case final m?)
          if (_streamDoors.contains(m.group(1))) m.group(0)!
          else ...const <String>[]
        else
          blanked.substring(at, (at + 24).clamp(0, blanked.length)).replaceAll(RegExp(r'\s+'), ' '),
    ];

/// Index just past the string or template literal that starts at [s][start].
int _literalEnd(String s, int start) {
  final q = s[start];
  var i = start + 1;
  while (i < s.length) {
    final c = s[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (c == q) return i + 1;
    if (q == '`' && c == r'$' && i + 1 < s.length && s[i + 1] == '{') {
      i = _closeIndex(s, i + 2) + 1;
      continue;
    }
    i++;
  }
  return s.length;
}

/// Index of the bracket that closes the expression starting at [start] (literals skipped).
int _closeIndex(String s, int start) {
  var depth = 0, i = start;
  while (i < s.length) {
    final c = s[i];
    if (c == '"' || c == "'" || c == '`') {
      i = _literalEnd(s, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return i;
      depth--;
    }
    i++;
  }
  return s.length;
}

/// [ts] without comments; literals (and `${...}` code inside templates) are kept intact.
String _code(String ts) {
  final out = StringBuffer();
  var i = 0;
  while (i < ts.length) {
    final c = ts[i];
    if (c == '"' || c == "'" || c == '`') {
      final e = _literalEnd(ts, i);
      out.write(ts.substring(i, e));
      i = e;
    } else if (ts.startsWith('//', i)) {
      final e = ts.indexOf('\n', i);
      i = e < 0 ? ts.length : e;
    } else if (ts.startsWith('/*', i)) {
      final e = ts.indexOf('*/', i + 2);
      i = e < 0 ? ts.length : e + 2;
    } else if (c == '/' && _regexStarts(out.toString())) {
      // A regex literal becomes `/r/`: a quote or a `//` inside it must not open a string or a comment.
      final e = _regexEnd(ts, i);
      if (e < 0) {
        out.write(c);
        i++;
      } else {
        out.write('/r/');
        i = e;
      }
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// Whether a `/` after the code in [before] starts a regex literal rather than a division: the last code
/// character is an operator, an opening bracket or a separator (or there is none), or the last word is a
/// keyword that takes an expression.
bool _regexStarts(String before) {
  final t = before.trimRight();
  if (t.isEmpty) return true;
  if ('(,=:[!&|?{};+-*%<>~^'.contains(t[t.length - 1])) return true;
  return RegExp(r'\b(return|typeof|case|in|of|delete|void|throw|new|yield|await)$').hasMatch(t);
}

/// Index just past the regex literal (flags included) that starts at [s][start], or -1 when no `/` closes it
/// on the same line (then it was not a regex).
int _regexEnd(String s, int start) {
  var i = start + 1;
  var inClass = false;
  while (i < s.length) {
    final c = s[i];
    if (c == '\n') return -1;
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (c == '[') {
      inClass = true;
    } else if (c == ']') {
      inClass = false;
    } else if (c == '/' && !inClass) {
      i++;
      while (i < s.length && RegExp(r'[a-z]').hasMatch(s[i])) {
        i++;
      }
      return i;
    }
    i++;
  }
  return -1;
}

/// [s] with the TEXT of every literal replaced by spaces (newlines kept); quotes and `${...}` code stay. Same
/// length as [s], so an offset found in the blanked view indexes the same character of [s].
String _blankLiterals(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '"' || c == "'" || c == '`') {
      final e = _literalEnd(s, i);
      out.write(_blankOne(s.substring(i, e)));
      i = e;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

String _blankOne(String lit) {
  final q = lit[0];
  final out = StringBuffer(q);
  var i = 1;
  while (i < lit.length) {
    final c = lit[i];
    if (c == r'\') {
      final n = i + 2 <= lit.length ? 2 : 1;
      out.write(' ' * n);
      i += n;
      continue;
    }
    if (q == '`' && c == r'$' && i + 1 < lit.length && lit[i + 1] == '{') {
      final e = _closeIndex(lit, i + 2);
      out
        ..write(r'${')
        ..write(_blankLiterals(lit.substring(i + 2, e)));
      if (e < lit.length) out.write('}');
      i = e + 1;
      continue;
    }
    out.write(c == q && i == lit.length - 1 ? c : (c == '\n' ? '\n' : ' '));
    i++;
  }
  return out.toString();
}

/// Offsets of [name] used as an identifier in [blanked] (not a property `.name`, not part of a longer name).
List<int> _mentions(String blanked, String name) => [
      for (final m in RegExp('(?<![\\w\$])${RegExp.escape(name)}(?![\\w\$])').allMatches(blanked))
        if (!_isProperty(blanked, m.start)) m.start,
    ];

/// Whether the name at [at] is a property (`o.name`, `o?.name`), as opposed to a spread `...name`.
bool _isProperty(String s, int at) {
  var j = at - 1;
  while (j >= 0 && (s[j] == ' ' || s[j] == '\t' || s[j] == '\n')) {
    j--;
  }
  return j >= 0 && s[j] == '.' && !(j >= 2 && s[j - 1] == '.' && s[j - 2] == '.');
}

/// Top-level pieces of [s] split on [sep] (literals and brackets respected), each trimmed; empty pieces dropped.
List<String> _split(String s, String sep) {
  final out = <String>[];
  var depth = 0, i = 0, from = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '"' || c == "'" || c == '`') {
      i = _literalEnd(s, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (depth == 0 && c == sep) {
      out.add(s.substring(from, i).trim());
      from = i + 1;
    }
    i++;
  }
  out.add(s.substring(from).trim());
  return out.where((p) => p.isNotEmpty).toList();
}

bool _isLiteral(String s) =>
    s.isNotEmpty && (s[0] == '"' || s[0] == "'" || s[0] == '`') && _literalEnd(s, 0) == s.length;

final _conditional = RegExp(r'^\(\s*[A-Za-z_]\w*\s*\?([\s\S]*):([\s\S]*)\)$');

/// The literals an argument is built from, or null when any operand is not a literal (or `(x ? lit : lit)`).
List<String>? _literalsOf(String arg) {
  final lits = <String>[];
  for (final op in _split(arg, '+')) {
    if (_isLiteral(op)) {
      lits.add(op);
      continue;
    }
    final m = _conditional.firstMatch(op);
    if (m != null && _closeIndex(op, 1) == op.length - 1) {
      final a = m.group(1)!.trim(), b = m.group(2)!.trim();
      if (_isLiteral(a) && _isLiteral(b)) {
        lits
          ..add(a)
          ..add(b);
        continue;
      }
    }
    return null;
  }
  return lits;
}

/// The `${...}` expressions of one template literal, whitespace-collapsed.
List<String> _interpolations(String lit) {
  final out = <String>[];
  if (lit[0] != '`') return out;
  var i = 1;
  while (i < lit.length - 1) {
    final c = lit[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (c == r'$' && lit[i + 1] == '{') {
      final e = _closeIndex(lit, i + 2);
      out.add(lit.substring(i + 2, e).replaceAll(RegExp(r'\s+'), ' ').trim());
      i = e + 1;
      continue;
    }
    i++;
  }
  return out;
}

/// The right-hand side of every assignment to [name] in [code] (`let name = ...;`, `name = ...;`, and the compound
/// `+=`, `??=`, `||=`, `&&=`), trimmed.
List<String> _assignments(String code, String name) {
  final out = <String>[];
  final blanked = _blankLiterals(code);
  for (final m
      in RegExp('(?<![\\w.\$])${RegExp.escape(name)}\\s*(?:\\+|\\?\\?|\\|\\||&&)?=(?![=>])').allMatches(blanked)) {
    var depth = 0, i = m.end;
    while (i < code.length) {
      final c = code[i];
      if (c == '"' || c == "'" || c == '`') {
        i = _literalEnd(code, i);
        continue;
      }
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') {
        if (depth == 0) break;
        depth--;
      }
      if (depth == 0 && (c == ';' || c == ',')) break;
      i++;
    }
    out.add(code.substring(m.end, i).trim());
  }
  return out;
}

typedef _Call = ({String text, List<String> args});

/// Every `console.<method>(...)` call in [code].
List<_Call> _consoleCalls(String code) {
  final out = <_Call>[];
  for (final m in RegExp(r'console\.\w+\(').allMatches(_blankLiterals(code))) {
    final close = _closeIndex(code, m.end);
    final args = _split(code.substring(m.end, close), ',');
    out.add((text: '${m.group(0)}${args.join(', ')})'.replaceAll(RegExp(r'\s+'), ' '), args: args));
  }
  return out;
}

void main() {
  group('payment_log_safety', () {
    test('every console call takes ONE argument built only from literals (no variable, value or object)', () {
      final offenders = <String>[];
      var seen = 0;
      for (final f in _scanned) {
        final code = _code(File(f).readAsStringSync());
        final calls = _consoleCalls(code);
        final raw = RegExp(r'console\.\w+\(').allMatches(code).length;
        if (calls.isEmpty) offenders.add('$f: the scan sees no console call at all');
        if (raw != calls.length) {
          offenders.add('$f: $raw console calls in the text but ${calls.length} seen; the scan is desynchronised '
              '(a call is inside what it reads as a literal)');
        }
        for (final c in calls) {
          seen++;
          if (_allowedTwoArg.contains(c.text)) continue;
          if (c.args.length != 1 || _literalsOf(c.args.single) == null) offenders.add('$f: ${c.text}');
        }
      }
      expect(seen, greaterThan(35), reason: 'the scan must see the real call sites');
      expect(offenders, isEmpty,
          reason: 'build the line from literals and payment_log_safe.ts helpers; a second argument, a variable '
              'or a concatenated value can carry a whole object or raw text');
    });

    test('every value interpolated into a console call is classified for its file, and no entry is stale', () {
      final offenders = <String>[];
      for (final f in _scanned) {
        final code = _code(File(f).readAsStringSync());
        final vars = _messageVariables[f] ?? const <String>{};
        final used = <String>{}, usedVars = <String>{};
        final varUses = <String, int>{};
        void classify(String e) {
          used.add(e);
          if (!(_allowed[f] ?? const <String>{}).contains(e)) offenders.add('$f: \${$e}');
        }

        for (final c in _consoleCalls(code)) {
          if (_allowedTwoArg.contains(c.text)) continue;
          for (final arg in c.args) {
            for (final lit in _literalsOf(arg) ?? const <String>[]) {
              for (final e in _interpolations(lit)) {
                if (vars.contains(e)) {
                  usedVars.add(e);
                  varUses[e] = (varUses[e] ?? 0) + 1;
                } else {
                  classify(e);
                }
              }
            }
          }
        }
        // Rule 3: a message variable is checked where it is built.
        for (final v in usedVars) {
          final rhs = _assignments(code, v);
          if (rhs.length < 2) offenders.add('$f: message variable $v has ${rhs.length} assignment(s); expected its line');
          final mentions = _mentions(_blankLiterals(code), v).length;
          if (mentions != rhs.length + varUses[v]!) {
            offenders.add('$f: $v is mentioned $mentions times but only ${rhs.length} assignment(s) and '
                '${varUses[v]} console use(s) are checked; any other mention can fill it unseen');
          }
          for (final r in rhs) {
            final lits = _literalsOf(r);
            if (lits == null) {
              offenders.add('$f: $v = $r (not built only from literals)');
              continue;
            }
            for (final lit in lits) {
              _interpolations(lit).forEach(classify);
            }
          }
        }
        // MIRROR: an entry nothing uses any more silently allows the next unchecked use of that name.
        for (final stale in (_allowed[f] ?? const <String>{}).difference(used)) {
          offenders.add('$f: stale allowlist entry $stale');
        }
        for (final stale in vars.difference(usedVars)) {
          offenders.add('$f: stale message variable $stale');
        }
        for (final v in vars) {
          if ((_allowed[f] ?? const <String>{}).contains(v)) offenders.add('$f: $v is a message variable, not a value');
        }
      }
      expect(offenders, isEmpty,
          reason: 'log only a code, a type, a shape, a checked id or bounded text (payment_log_safe.ts); '
              'classify a new safe value for its file in _allowed');
      expect(_allowed.keys.toSet(), _scanned.toSet(), reason: 'one allowlist per scanned file');
    });

    test('console is reached only as console.<method>( and no dynamic-global door appears', () {
      final offenders = <String>[];
      for (final f in _scanned) {
        final blanked = _blankLiterals(_code(File(f).readAsStringSync()));
        for (final at in _mentions(blanked, 'console')) {
          if (RegExp(r'console\.\w+\(').matchAsPrefix(blanked, at) == null) {
            final end = (at + 40).clamp(0, blanked.length);
            offenders.add('$f: ${blanked.substring(at, end).replaceAll(RegExp(r'\s+'), ' ')}');
          }
        }
        for (final g in _dynamicGlobals) {
          if (_mentions(blanked, g).isNotEmpty) offenders.add('$f: $g');
        }
        for (final d in _denoDoors(blanked)) {
          offenders.add('$f: $d');
        }
      }
      expect(offenders, isEmpty,
          reason: 'an alias, a bracket lookup or a global lookup reaches the console where the scan cannot see it');
    });

    test('the allowed catch-alls still exist exactly as listed (no silent widening of the list)', () {
      final all = [for (final f in _functions) ..._consoleCalls(_code(File(f).readAsStringSync())).map((c) => c.text)];
      for (final a in _allowedTwoArg) {
        expect(all.contains(a), isTrue, reason: 'allowed call not found: $a');
      }
    });

    test('the scanner: a `//` inside a literal is text, and the shapes a leak would take are refused', () {
      expect(_code('a("x // y"); // gone\nb()'), 'a("x // y"); \nb()');
      expect(_code('a(`u // v \${w}`)'), 'a(`u // v \${w}`)');
      expect(_literalsOf('`a \${b}` + "c"'), ['`a \${b}`', '"c"']);
      expect(_literalsOf('(p ? ` x \${q}` : "")'), ['` x \${q}`', '""']);
      expect(_literalsOf('msg'), isNull);
      expect(_literalsOf('"raw " + body'), isNull);
      expect(_literalsOf('`a` + JSON.stringify(body)'), isNull);
      expect(_interpolations('`a \${x ? `\${y}` : ""} b \${z}`'), ['x ? `\${y}` : ""', 'z']);
      final calls = _consoleCalls('console.info(`x \${a}`); console.debug(m); console.error(`y`, e,);');
      expect(calls.map((c) => c.args.length), [1, 1, 2]);
      // Every assignment to a message variable is found (declaration, plain and nested ones; never a
      // comparison, an arrow or another name that ends with it).
      expect(
          _assignments('let m = ""; if (x === m || y => m) { m = `a \${f(b, c)}`; } else m = "z" + `q`; xm = body;',
              'm'),
          ['""', '`a \${f(b, c)}`', '"z" + `q`']);
      expect(_assignments('o.m = body; \$m = body; m == x; m === y; "m = body";', 'm'), isEmpty);
      // Blanking keeps the length and every code character, and drops literal text only.
      const src = 'a("m = x", `t \${m} \${"m"}`) // m';
      expect(_blankLiterals(src).length, src.length);
      expect(_blankLiterals(src), 'a("     ", `  \${m} \${" "}`) // m');
      expect(_mentions(_blankLiterals('[m] = [x]; ({ m } = o); for (m of xs) {} o.m; mm; "m"'), 'm').length, 3);
      expect(_consoleCalls('x("console.error(body)")'), isEmpty);
      // A spread is a mention; a property is not.
      expect(_mentions(_blankLiterals('[...m] = y; o.m; o?.m; o . m'), 'm').length, 1);
      // Regex literals: a quote or `//` inside one opens no string and no comment; a division is not a regex.
      expect(_code('const q = /"/; console.error(`x`); const r = /"/;'),
          'const q = /r/; console.error(`x`); const r = /r/;');
      expect(_code('a = /\\/\\//g; console.warn(`y`)'), 'a = /r/; console.warn(`y`)');
      expect(_code('x = a / b / c; // note'), 'x = a / b / c; ');
      expect(_code('if (s.match(/[/"]/)) f()'), 'if (s.match(/r/)) f()');
      expect(_denoDoors('Deno.stderr.writeSync(b)'), ['Deno.stderr']);
      expect(_denoDoors('Deno["      "]').length, 1);
      expect(_denoDoors('(Deno as any)[x]').length, 1);
      expect(_denoDoors('const d = Deno; d.stdout'), hasLength(1));
      expect(_denoDoors('Deno.env.get("X"); Deno.test; o.Deno'), isEmpty);
      expect(_assignments('m += `\${body}`; m ??= x; m ||= y; m &&= z;', 'm'), ['`\${body}`', 'x', 'y', 'z']);
    });

    test('each payment function imports the helpers, and the module has no imports (pure)', () {
      for (final f in _functions) {
        expect(File(f).readAsStringSync(), contains('from "../_shared/payment_log_safe.ts"'), reason: f);
      }
      final helper = File('supabase/functions/_shared/payment_log_safe.ts').readAsStringSync();
      expect(RegExp(r'^import ', multiLine: true).hasMatch(helper), isFalse);
    });

    test('the insert-failure lines carry the reconcile fields and a code, under their own prefix', () {
      final vp = _code(File(_functions[0]).readAsStringSync());
      final wh = _code(File(_functions[1]).readAsStringSync());
      expect(vp, contains('[verify-payment] subscription insert failed (non-23505) request_id=\${failId} '));
      expect(vp, contains('code=\${pgErrorCode(insertError)}'));
      expect(wh, contains('[razorpay-webhook] subscription insert failed (non-23505) payment_id=\${razorpayPaymentId} '));
      expect(wh, contains('code=\${pgErrorCode(insertError)}'));
    });
  });
}
