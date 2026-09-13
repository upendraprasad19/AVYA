import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/copy/coach_replies.dart';

const _serverPath = 'supabase/functions/_shared/coach_replies.ts';
const _clientPath = 'lib/features/ai_coach/copy/coach_replies.dart';

/// One TS string literal — single-, double- or backtick-quoted, escape-aware.
/// OI-153 review round 2: the previous extractor used a `[^'"]*` class, which
/// stops at the apostrophe in "You've" and returned NULL for
/// `imagePaywallExhausted` — the very key the mirror loop was being extended
/// to cover. Quote-aware means: the closing quote is the SAME character as the
/// opening one, and the other quote character is ordinary text inside it.
final _literal = RegExp(
  r'''(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)''',
);

String _unquote(String lit) {
  final body = lit.substring(1, lit.length - 1);
  // No literal in either mirror file uses an escape sequence today; if one
  // ever does, the comparison below reddens rather than silently mis-decoding.
  expect(body.contains(r'\'), isFalse,
      reason: 'escape sequences in coach copy are not supported by this '
          'mirror test — rewrite the literal without one: $lit');
  return body;
}

/// Reads a `<lit> + <lit> + …` expression starting at [from], stopping at the
/// first `;` or `,` that sits OUTSIDE a literal. Returns the joined text and the
/// index just past the terminator. Written as a scanner rather than a regex
/// because the cap copies contain a literal `;` ("midnight IST; send it…"),
/// which a non-greedy `.*?;` would cut in half.
(String, int) _readConcat(String src, int from) {
  final buf = StringBuffer();
  var i = from;
  while (true) {
    while (i < src.length && ' \t\r\n'.contains(src[i])) {
      i++;
    }
    expect(i, lessThan(src.length), reason: 'unterminated copy expression');
    final m = _literal.matchAsPrefix(src, i);
    expect(m, isNotNull,
        reason: 'expected a string literal at offset $i, got '
            '"${src.substring(i, (i + 30).clamp(0, src.length))}"');
    buf.write(_unquote(m!.group(0)!));
    i = m.end;
    while (i < src.length && ' \t\r\n'.contains(src[i])) {
      i++;
    }
    if (src[i] == '+') {
      i++;
      continue;
    }
    expect(src[i] == ';' || src[i] == ',', isTrue,
        reason: 'unexpected "${src[i]}" after a copy literal at offset $i');
    return (buf.toString(), i + 1);
  }
}

String _stripComments(String raw) => raw
    .replaceAll('\r\n', '\n')
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = RegExp(r'(?<!:)//').firstMatch(l)?.start ?? -1;
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

/// Every key of the server's `COACH_REPLIES` object, in declaration order,
/// with its rendered text(s): one string for a constant, one per `return` for
/// a method. Templates (`${cap}`, `${remaining}`) are left as-is; the caller
/// substitutes the argument it will pass to the Dart twin.
Map<String, List<String>> _serverEntries(String ts) {
  final start = ts.indexOf('export const COACH_REPLIES = {');
  expect(start, greaterThanOrEqualTo(0));
  final body = ts.substring(start);
  final out = <String, List<String>>{};
  final entryStart = RegExp(r'^  (\w+)(:|\()', multiLine: true);
  for (final m in entryStart.allMatches(body)) {
    final key = m.group(1)!;
    if (m.group(2) == ':') {
      final (text, _) = _readConcat(body, m.end);
      out[key] = [text];
    } else {
      // Method: collect every `return <concat>;` until the closing `},` at
      // two-space indentation.
      final close = body.indexOf('\n  },', m.end);
      expect(close, greaterThan(m.end), reason: 'unterminated method $key');
      final fn = body.substring(m.end, close);
      final returns = <String>[];
      for (final r in RegExp(r'\breturn\s').allMatches(fn)) {
        final (text, _) = _readConcat(fn, r.end);
        returns.add(text);
      }
      expect(returns, isNotEmpty, reason: 'method $key has no return');
      out[key] = returns;
    }
  }
  return out;
}

/// F17 · Test #9 — reply copy contract.
void main() {
  group('CoachReplies', () {
    test('welcomeBridge is on-brand (Bridge + Recruit + action words)', () {
      final w = CoachReplies.welcomeBridge;
      expect(w.contains('Bridge'), isTrue);
      expect(w.contains('Recruit'), isTrue);
      expect(w.contains('Workouts'), isTrue);
      expect(w.contains('nutrition'), isTrue);
      expect(w.contains('recovery'), isTrue);
    });

    test('freeImageCounter(4) shows "4 of 5 free analyses left"', () {
      expect(CoachReplies.freeImageCounter(4),
          contains('4 of 5 free analyses left'));
    });

    test('freeImageCounter(1) shows "Last free analysis used"', () {
      expect(CoachReplies.freeImageCounter(1),
          contains('Last free analysis used'));
    });

    test('freeImageCounter(0) shows "used your 5 free analyses"', () {
      expect(CoachReplies.freeImageCounter(0),
          contains('used your 5 free analyses'));
    });

    test('imagePaywallExhausted mentions Upgrade to PRO', () {
      expect(CoachReplies.imagePaywallExhausted,
          contains('Upgrade to PRO'));
    });

    test('videoPaywall mentions PRO + form check / technique', () {
      expect(CoachReplies.videoPaywall, contains('PRO'));
      expect(CoachReplies.videoPaywall, contains('form check'));
    });

    // OI-162 slice 3b — the fail-CLOSED refusal copy. B-pass finding 3: this
    // string shipped with ZERO assertions, and it is the exact text a real
    // production refusal shows when the quota ledger is unreadable.
    test('imageQuotaUnavailable never claims the user spent their quota', () {
      final c = CoachReplies.imageQuotaUnavailable;
      // The WHOLE POINT of this copy existing separately: reusing
      // imagePaywallExhausted would tell a user who may have spent NOTHING
      // that they had used all 5. Pin the absence, not just the presence.
      expect(c.contains('used your 5'), isFalse,
          reason: 'this refusal fires on a DB error, not on exhaustion — '
              'claiming a spent quota here is a lie');
      expect(c.contains('Upgrade'), isFalse,
          reason: 'this is not a paywall; upselling on an infrastructure '
              'failure is both wrong and unactionable');
      expect(c, contains('Recruit'), reason: 'on-brand (Wardroom voice)');
      expect(c.toLowerCase(), contains('again'),
          reason: 'the user must be told it is retryable');
      // MIRROR: the real paywall must still say the opposite, or this test
      // would keep passing after someone merged the two strings back together.
      expect(CoachReplies.imagePaywallExhausted, contains('used your 5'));
      expect(CoachReplies.imagePaywallExhausted, contains('Upgrade'));
    });

    // OI-153 — the PRO daily-cap copy: rank-free (PRO users hold ranks), no
    // upgrade CTA (they already pay), states WHEN it resets, and carries the
    // cap as an ARGUMENT so the number can never drift from the constant.
    test('the PRO cap copies state the reset and sell nothing', () {
      for (final c in [
        CoachReplies.proImageDailyCapReached(50),
        CoachReplies.proVideoDailyCapReached(10),
      ]) {
        expect(c, contains('midnight IST'));
        expect(c.contains('Upgrade'), isFalse);
        expect(c.contains('Recruit'), isFalse);
      }
      expect(CoachReplies.proImageDailyCapReached(50), contains('50 image reads'));
      expect(CoachReplies.proVideoDailyCapReached(10), contains('10 video reads'));
      expect(CoachReplies.proImageDailyCapReached(7), contains('7 image reads'),
          reason: 'the number must be the argument, not a typed literal');
      for (final c in [
        CoachReplies.imageLedgerUnavailable,
        CoachReplies.videoLedgerUnavailable,
      ]) {
        expect(c, contains('not a limit'));
        expect(c.contains('Upgrade'), isFalse);
        expect(c.contains('Recruit'), isFalse);
      }
    });

    test('no coach copy promises "unlimited" on either side (OI-153)', () {
      // PRO media reads have a visible daily ceiling. A single surviving
      // "unlimited" — the free counter's CTA said it twice while only the
      // paywall string was reworded — is false the day the cap fires.
      for (final path in const [_serverPath, _clientPath]) {
        final src = _stripComments(File(path).readAsStringSync());
        expect(src.toLowerCase().contains('unlimited'), isFalse,
            reason: '$path still promises "unlimited"');
      }
    });

    test('EVERY server copy key has a byte-identical client twin', () {
      // The two files each declare themselves a MIRROR of the other, and until
      // OI-162 slice 3b nothing enforced it; that batch pinned ONE key, and a
      // membership check over one member cannot see another member drift.
      // The key list is DERIVED from the server object (a hand-written list
      // omitted `videoPaywall` in review round 4), and the Dart side must
      // register a twin for every one of them — an unregistered key fails.
      final ts = _stripComments(File(_serverPath).readAsStringSync());
      final server = _serverEntries(ts);
      expect(server.keys, isNotEmpty);

      // Rendered Dart twins, keyed by the server key. Methods list one output
      // per server `return`, in the same order, with the template argument
      // the server text is rendered with.
      final dartTwins = <String, List<String>>{
        'videoPaywall': [CoachReplies.videoPaywall],
        'imagePaywallExhausted': [CoachReplies.imagePaywallExhausted],
        'imageQuotaUnavailable': [CoachReplies.imageQuotaUnavailable],
        'imageLedgerUnavailable': [CoachReplies.imageLedgerUnavailable],
        'videoLedgerUnavailable': [CoachReplies.videoLedgerUnavailable],
        'proImageDailyCapReached': [CoachReplies.proImageDailyCapReached(50)],
        'proVideoDailyCapReached': [CoachReplies.proVideoDailyCapReached(10)],
        'freeImageCounter': [
          CoachReplies.freeImageCounter(3),
          CoachReplies.freeImageCounter(1),
          CoachReplies.freeImageCounter(0),
        ],
      };
      const templateArgs = <String, Map<String, String>>{
        'proImageDailyCapReached': {r'${cap}': '50'},
        'proVideoDailyCapReached': {r'${cap}': '10'},
        'freeImageCounter': {r'${remaining}': '3'},
      };

      expect(dartTwins.keys.toSet(), server.keys.toSet(),
          reason: 'the server object and the Dart twin registry disagree on '
              'WHICH keys are mirrored. Server: ${server.keys.toList()}. '
              'Dart: ${dartTwins.keys.toList()}. Add the twin (and the Dart '
              'constant) or remove the server key — never leave one side.');

      for (final key in server.keys) {
        var rendered = server[key]!;
        final subs = templateArgs[key];
        if (subs != null) {
          rendered = rendered
              .map((t) => subs.entries.fold(t, (s, e) => s.replaceAll(e.key, e.value)))
              .toList();
        }
        expect(rendered.any((t) => t.contains(r'${')), isFalse,
            reason: '$key still carries an unsubstituted template: $rendered');
        expect(rendered, dartTwins[key],
            reason: 'client and server copies of `$key` have DRIFTED. Both '
                'files call themselves a mirror of the other; update both '
                'or neither.');
      }
    });
  });
}
