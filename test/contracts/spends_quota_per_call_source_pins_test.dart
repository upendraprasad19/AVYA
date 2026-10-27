// OI-414 — SOURCE PINS (presence only) for `spendsQuotaPerCall`.
//
// What runs for real lives elsewhere: the re-send loop in
// `edge_function_cold_start_retry_behavioral_test.dart` (mock invoker) and the
// forwarding through `callFunction` in
// `call_function_spends_quota_per_call_behavioral_test.dart` (real HTTP). What
// neither can see, and this file pins by reading the source:
//   - the declaration of the flag (default false) on BOTH functions;
//   - the stop is a separate early gate that precedes `if (isColdStart)`, and its
//     telemetry call is `unawaited` (an awaited event would hold the paywall
//     behind a log round trip that itself waits on the re-send schedule);
//   - the telemetry lane `callFunctionAnonymous` never carries the flag;
//   - EVERY call of `validate-promo` and `consume-day-swap` in `lib/` passes
//     `spendsQuotaPerCall: true`, and no other spelling of either name exists.
//
// A pin that matches nothing passes on a tree with no flag at all, so each call
// site pin also asserts it found at least one site.
//
// Run: flutter test test/contracts/spends_quota_per_call_source_pins_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _service = 'lib/core/services/supabase_service.dart';

String _code(String dart) => dart
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

/// The text from [head] to the first `) async {` after it (the parameter list).
String _signature(String src, String head) {
  final start = src.indexOf(head);
  expect(start, isNot(-1), reason: 'missing: $head');
  final end = src.indexOf(') async {', start);
  expect(end, greaterThan(start), reason: 'no body after: $head');
  return src.substring(start, end);
}

/// The paren-matched argument text of every `callFunction(` whose first
/// argument is the string [name], in comment-stripped Dart files under lib/.
List<String> _callSites(String name) {
  final head = RegExp('callFunction\\(\\s*[\'"]${RegExp.escape(name)}[\'"]');
  final sites = <String>[];
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final src = _code(f.readAsStringSync());
    for (final m in head.allMatches(src)) {
      var depth = 0;
      var i = src.indexOf('(', m.start);
      final from = i;
      for (; i < src.length; i++) {
        if (src[i] == '(') depth++;
        if (src[i] == ')') {
          depth--;
          if (depth == 0) break;
        }
      }
      sites.add('${f.path}: ${src.substring(from, i + 1)}');
    }
  }
  return sites;
}

/// How many times the quoted string [name] appears in comment-stripped lib/.
int _mentions(String name) {
  final lit = RegExp('[\'"]${RegExp.escape(name)}[\'"]');
  var n = 0;
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    n += lit.allMatches(_code(f.readAsStringSync())).length;
  }
  return n;
}

void main() {
  group('OI-414 spendsQuotaPerCall — wrapper source', () {
    final src = _code(File(_service).readAsStringSync());

    test('the flag is declared on callFunction AND retryColdStart, default false',
        () {
      final flag = RegExp(r'bool\s+spendsQuotaPerCall\s*=\s*false');
      expect(
          flag.hasMatch(_signature(src, 'Future<FunctionResponse> callFunction(')),
          isTrue,
          reason: 'callFunction must declare it (default false)');
      expect(
          flag.hasMatch(_signature(
              src, 'static Future<FunctionResponse> retryColdStart(')),
          isTrue,
          reason: 'retryColdStart must declare it (default false)');
    });

    test('callFunction forwards it to retryColdStart', () {
      final body = src.substring(
          src.indexOf('Future<FunctionResponse> callFunction('),
          src.indexOf('Future<FunctionResponse> _invokeRaw('));
      expect(
          RegExp(r'return retryColdStart\([\s\S]*?spendsQuotaPerCall:\s*spendsQuotaPerCall,[\s\S]*?\);')
              .hasMatch(body),
          isTrue,
          reason: 'forwarding is what makes the flag reach the loop');
    });

    test('the stop is a gate on the gateway statuses, before `if (isColdStart)`',
        () {
      expect(src, contains('static const Set<int> _gatewayStatuses = {502, 503, 504};'));
      final gate = src.indexOf(
          'if (spendsQuotaPerCall && _gatewayStatuses.contains(e.status)) {');
      expect(gate, greaterThan(0));
      expect(gate, lessThan(src.indexOf('if (isColdStart) {')),
          reason: 'the stop must come first or the re-send branch takes the status');
    });

    test('the stop event is fire-and-forget', () {
      expect(
          RegExp(r"""unawaited\(\s*ErrorTelemetry\.logEvent\(\s*['"]edge_function_no_retry_quota_call['"]""")
              .hasMatch(src),
          isTrue,
          reason: 'an awaited event holds the caller behind a log round trip');
    });

    test('the telemetry lane callFunctionAnonymous never carries the flag', () {
      final anon = src.substring(
          src.indexOf('Future<FunctionResponse> callFunctionAnonymous('),
          src.indexOf('static Future<FunctionResponse> retryColdStart('));
      expect(anon, isNot(contains('spendsQuotaPerCall')));
    });
  });

  group('OI-414 spendsQuotaPerCall — every metered call site passes it', () {
    for (final name in ['validate-promo', 'consume-day-swap']) {
      test('$name: every callFunction site is flagged, and no other spelling exists',
          () {
        final sites = _callSites(name);
        expect(sites, isNotEmpty,
            reason: 'found no call of $name: the pin would pass vacuously');
        for (final s in sites) {
          expect(RegExp(r'spendsQuotaPerCall:\s*true').hasMatch(s), isTrue,
              reason: 'unflagged call of $name -> $s');
        }
        expect(_mentions(name), sites.length,
            reason: 'a $name string outside a callFunction site (a constant, a '
                'second helper) escapes this pin');
      });
    }
  });
}
