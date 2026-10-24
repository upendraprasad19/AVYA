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
//   2. every `${...}` in those literals is a value CLASSIFIED for that file in [_allowed], and no entry is stale.
// Comments are stripped by a quote-aware scanner, so a `//` inside a literal is text, not a comment.
//
// Run: flutter test test/contracts/payment_log_safety_writer_to_reader_test.dart

import 'dart:io';
import 'package:test/test.dart';

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

// ── a small TypeScript scanner: literals, nesting, comments ──

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
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
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

typedef _Call = ({String text, List<String> args});

/// Every `console.<method>(...)` call in [code].
List<_Call> _consoleCalls(String code) {
  final out = <_Call>[];
  for (final m in RegExp(r'console\.\w+\(').allMatches(code)) {
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
        for (final c in _consoleCalls(_code(File(f).readAsStringSync()))) {
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
        final used = <String>{};
        for (final c in _consoleCalls(_code(File(f).readAsStringSync()))) {
          if (_allowedTwoArg.contains(c.text)) continue;
          for (final arg in c.args) {
            for (final lit in _literalsOf(arg) ?? const <String>[]) {
              for (final e in _interpolations(lit)) {
                used.add(e);
                if (!(_allowed[f] ?? const <String>{}).contains(e)) offenders.add('$f: \${$e}');
              }
            }
          }
        }
        // MIRROR: an entry nothing uses any more silently allows the next unchecked use of that name.
        for (final stale in (_allowed[f] ?? const <String>{}).difference(used)) {
          offenders.add('$f: stale allowlist entry $stale');
        }
      }
      expect(offenders, isEmpty,
          reason: 'log only a code, a type, a shape, a checked id or bounded text (payment_log_safe.ts); '
              'classify a new safe value for its file in _allowed');
      expect(_allowed.keys.toSet(), _scanned.toSet(), reason: 'one allowlist per scanned file');
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
