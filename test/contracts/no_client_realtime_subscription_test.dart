// Guard for batch realtime-weight-off (2026-11-04): the client opens NO
// Supabase Realtime subscription. The PRO `weight_logs` stream (the former
// lib/core/services/sync/sync_realtime.dart) was deleted because its only
// intended producer (Telegram) is dropped and every attach cost a
// `realtime.list_changes()` poller + a tenant init on the server.
//
// PRESENCE-ONLY protection (CLAUDE.md 4.4 rule 21): a source scan proves the
// patterns are absent from `lib/`, not that nothing subscribes by another
// route. A new Realtime feature must delete or edit this test on purpose,
// with a plan review (the server-side cost is the reason it was removed).
//
// The scan strips comments and string literals first, so prose such as
// "realtime" in a comment, a `.stream` getter or `ref.watch(` never trips it.
// `postgres_changes` is matched on the string-KEPT text (it is a string
// literal in the Supabase API).

library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Removes `//` line comments, `/* */` block comments (nesting is not
/// tracked: Dart nests them, a stray `*/` only ever ends the scan early on
/// the safe side) and the CONTENT of string literals (quotes kept): single,
/// double, triple-quoted and raw (`r'..'`, no escapes). Code inside a
/// `${...}` interpolation of a non-raw string is KEPT and scanned as code,
/// so `'${client.channel("x")}'` still trips the patterns. With
/// [keepStrings] the literal text is kept too (used for `postgres_changes`).
String stripCommentsAndStrings(String src, {bool keepStrings = false}) {
  final out = StringBuffer();
  var i = 0;
  final n = src.length;
  bool at(int k, String t) => src.startsWith(t, k);
  while (i < n) {
    final c = src[i];
    if (at(i, '//')) {
      while (i < n && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (at(i, '/*')) {
      i += 2;
      while (i < n && !at(i, '*/')) {
        i++;
      }
      i += 2;
      continue;
    }
    final raw =
        c == 'r' &&
        i + 1 < n &&
        (src[i + 1] == "'" || src[i + 1] == '"') &&
        (i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(src[i - 1]));
    if (raw || c == "'" || c == '"') {
      final qStart = raw ? i + 1 : i;
      final q = src[qStart];
      final triple = at(qStart, q * 3);
      final delim = triple ? q * 3 : q;
      if (raw) out.write('r');
      out.write(delim);
      i = qStart + delim.length;
      while (i < n && !at(i, delim)) {
        if (!raw && src[i] == '\\' && i + 1 < n) {
          if (keepStrings) out.write(src.substring(i, i + 2));
          i += 2;
          continue;
        }
        if (!raw && at(i, r'${')) {
          // Find the matching brace and scan the expression as code.
          var depth = 1;
          var j = i + 2;
          while (j < n && depth > 0) {
            if (src[j] == '{') depth++;
            if (src[j] == '}') depth--;
            j++;
          }
          out.write(' ');
          out.write(
            stripCommentsAndStrings(
              src.substring(i + 2, j - 1),
              keepStrings: keepStrings,
            ),
          );
          out.write(' ');
          i = j;
          continue;
        }
        if (!triple && src[i] == '\n') break; // unterminated: stop at EOL
        if (keepStrings) out.write(src[i]);
        i++;
      }
      out.write(delim);
      i += delim.length;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

final List<RegExp> _codePatterns = <RegExp>[
  RegExp(r'\.stream\s*[<(]'),
  RegExp(r'\.channel\s*\('),
  RegExp(r'onPostgresChanges'),
  RegExp(r'\bRealtimeChannel\b'),
  RegExp(r'\bRealtimeClient\b'),
  RegExp(r'\.realtime\b'),
  RegExp(r'\.onBroadcast\s*\('),
  RegExp(r'\.onPresence\s*\('),
  RegExp(r'subscribeToRealtimeSync'),
  RegExp(r'unsubscribeRealtime'),
];

final RegExp _stringKeptPattern = RegExp(r'postgres_changes');

/// True when [src] wires `onDowngrade` (assignment, `??=` or a named
/// argument). The declaration and `onDowngrade?.call()` do not match.
bool assignsOnDowngrade(String src) => RegExp(
  r'\bonDowngrade\s*(?:\?\?=|=(?!=)|:(?!:))',
).hasMatch(stripCommentsAndStrings(src));

/// Returns the pattern sources found in [src] (empty = clean).
List<String> findRealtimeUse(String src) {
  final code = stripCommentsAndStrings(src);
  final withStrings = stripCommentsAndStrings(src, keepStrings: true);
  return <String>[
    for (final p in _codePatterns)
      if (p.hasMatch(code)) p.pattern,
    if (_stringKeptPattern.hasMatch(withStrings)) _stringKeptPattern.pattern,
  ];
}

void main() {
  group('scanner fixtures (what trips, what does not)', () {
    test('the removed multi-line stream shape is caught', () {
      const src = '''
void f() {
  _realtimeSubscription = _supabase.client
      .from('weight_logs')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .listen((rows) {});
}
''';
      expect(findRealtimeUse(src), contains(r'\.stream\s*[<(]'));
    });

    test('each pattern is caught on its own', () {
      const hits = <String, String>{
        r'\.stream\s*[<(]': 'final s = t.stream(primaryKey: []);',
        r'\bRealtimeClient\b': 'RealtimeClient(url).connect();',
        r'\.channel\s*\(': "final c = client.channel('x');",
        'onPostgresChanges': 'c.onPostgresChanges(event: e);',
        r'\bRealtimeChannel\b': 'RealtimeChannel? _c;',
        r'\.realtime\b': 'client.realtime.connect();',
        r'\.onBroadcast\s*\(': "c.onBroadcast(event: 'e');",
        r'\.onPresence\s*\(': "c.onPresence(event: e);",
        'subscribeToRealtimeSync': 'x.subscribeToRealtimeSync();',
        'unsubscribeRealtime': 'x.unsubscribeRealtime();',
      };
      hits.forEach((pattern, code) {
        expect(findRealtimeUse(code), contains(pattern), reason: code);
      });
    });

    test('postgres_changes is caught as a string literal', () {
      const src =
          "final t = RealtimeListenTypes.postgresChanges;\n"
          "c.on('postgres_changes', f);";
      expect(findRealtimeUse(src), contains('postgres_changes'));
    });

    test('evasion shapes the first scanner missed are caught', () {
      const cases = <String, String>{
        'interpolation': "debugPrint('\${client.channel(\"x\")}');",
        'raw string ending in a backslash':
            "final a = r'\\'; final c = client.channel('x');",
        'triple quote holding an apostrophe':
            "final a = '''it's'''; final c = client.channel('x');",
        'generic stream call': 't.stream<Map>(primaryKey: []);',
        'direct client': 'RealtimeClient(url).connect();',
      };
      cases.forEach((name, code) {
        expect(findRealtimeUse(code), isNotEmpty, reason: name);
      });
    });

    test('a quote inside a triple-quoted string does not flip parity', () {
      const src = "final a = '''it's .channel( text''';\nfinal b = 1;";
      expect(findRealtimeUse(src), isEmpty);
    });

    test('onDowngrade wiring is detected, declaration and call are not', () {
      expect(assignsOnDowngrade('S.onDowngrade = () {};'), isTrue);
      expect(assignsOnDowngrade('S.onDowngrade ??= () {};'), isTrue);
      expect(assignsOnDowngrade('f(onDowngrade: () {});'), isTrue);
      expect(
        assignsOnDowngrade('static void Function()? onDowngrade;'),
        isFalse,
      );
      expect(assignsOnDowngrade('onDowngrade?.call();'), isFalse);
      expect(assignsOnDowngrade('if (onDowngrade == null) {}'), isFalse);
      expect(assignsOnDowngrade('// S.onDowngrade = () {};'), isFalse);
    });

    test('benign shapes do not trip it', () {
      const src = '''
// realtime .stream( in a line comment, subscribeToRealtimeSync mentioned
/* block comment: .channel('x') onPostgresChanges RealtimeChannel */
final msg = 'call .stream( or .channel( or unsubscribeRealtime in text';
final s = x.stream;
final w = ref.watch(provider);
final streamed = ctl.stream.listen((_) {});
''';
      expect(findRealtimeUse(src), isEmpty);
    });
  });

  group('lib/ opens no Realtime subscription', () {
    test('no file under lib/ matches a Realtime pattern', () {
      final offenders = <String>[];
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final hits = findRealtimeUse(f.readAsStringSync());
        if (hits.isNotEmpty) offenders.add('${f.path}: $hits');
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('no file under lib/ assigns SubscriptionService.onDowngrade', () {
      final offenders = <String>[];
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (assignsOnDowngrade(f.readAsStringSync())) offenders.add(f.path);
      }
      // The hook's declaration itself (`void Function()? onDowngrade;`) has
      // no `=`; a production assignee would reintroduce the teardown route.
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
