// Contract (presence) — the prediction failure outcome is wired through
// `AiService.predict()` and all three `regeneratePrediction()` callers
// (B-pass c5d659f52986 Finding 1, diagnose 125b81). The mapping itself is
// behaviourally tested in test/services/prediction_refresh_outcome_test.dart;
// these pins cover what that test cannot reach — `predict()` needs a live
// Edge Function and the callers are widgets / a Notifier.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripped(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

/// The body of the first method whose signature matches [signature].
String _body(String src, Pattern signature) {
  final start = src.indexOf(signature);
  expect(start, isNonNegative, reason: 'signature $signature not found');
  final open = src.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}' && --depth == 0) return src.substring(open, i + 1);
  }
  fail('unbalanced braces after $signature');
}

void main() {
  test('predict() maps a FunctionException through predictionFailure', () {
    final body = _body(_stripped('lib/core/services/ai_service.dart'),
        'Future<AiChatResponse> predict(');
    expect(
        RegExp(r'on\s+FunctionException\s+catch\s*\(\s*e\s*\)\s*\{\s*throw\s+predictionFailure\(\s*e\s*\)\s*;')
            .hasMatch(body),
        isTrue,
        reason: 'invoke THROWS on non-2xx: without this catch the 429 loses '
            'its status in the generic catch below it');
  });

  test('Profile refresh shows the daily-limit message for dailyLimitReached', () {
    final body = _body(
        _stripped('lib/features/profile/screens/profile/screen.dart'),
        'Future<void> _refreshPrediction()');
    final branch = RegExp(
            r"outcome\s*==\s*PredictionRefreshOutcome\.dailyLimitReached\)\s*\{[\s\S]*?'Daily prediction limit reached\. Try again tomorrow\.'")
        .hasMatch(body);
    expect(branch, isTrue);
  });

  test('PRO goal-change regenerate marks the prediction stale unless it succeeded', () {
    final src =
        _stripped('lib/features/profile/screens/edit_profile_screen.dart');
    expect(
        RegExp(r'regeneratePrediction\(\s*automatic:\s*true\s*\)\s*\.then\(\(outcome\)\s*\{\s*if\s*\(\s*outcome\s*!=\s*PredictionRefreshOutcome\.success\s*\)\s*\{\s*PredictionService\.instance\.markStale\(\)\s*;')
            .hasMatch(src),
        isTrue);
  });

  test('the coach auto-refresh only invalidates on success', () {
    final body = _body(
        _stripped('lib/features/ai_coach/providers/ai_coach_provider.dart'),
        'Future<void> _autoRefresh()');
    expect(body, contains('outcome == PredictionRefreshOutcome.success'));
  });

  // Hermes 2026-09-26 (L1-F1 / L1-F3 / L29-F4). The gate and refreshEnabled
  // are behaviourally tested in test/services/prediction_attempt_gate_test.dart;
  // these pin that the real callers go through them.
  test('both automatic callers pass automatic: true', () {
    final coach = _body(
        _stripped('lib/features/ai_coach/providers/ai_coach_provider.dart'),
        'Future<void> _autoRefresh()');
    expect(RegExp(r'regeneratePrediction\(\s*automatic:\s*true\s*\)').hasMatch(coach),
        isTrue,
        reason: 'the 30-day auto-refresh fires on every provider rebuild — '
            'unbudgeted it can spend the whole 3/day');
    // The edit-profile call is pinned by the markStale test above.
  });

  test('regeneratePrediction runs through the gate with a persisted IST day', () {
    final src = _stripped('lib/core/services/prediction_service.dart');
    expect(
        RegExp(r'regeneratePrediction\([^)]*\)\s*=>\s*_gate\.run\(\s*_regenerate\s*,\s*automatic:\s*automatic\s*\)')
            .hasMatch(src),
        isTrue);
    expect(src, contains("MigratedKey.read<String>('prediction_auto_attempt_day')"));
    expect(src, contains("MigratedKey.write('prediction_auto_attempt_day', day)"));
    expect(RegExp(r'today:\s*istTodayStr\b').hasMatch(src), isTrue,
        reason: 'the server cap resets at IST midnight — the budget must too');
  });

  // B-pass finding, 2026-09-26. safeToWriteForTest is behaviorally tested in
  // test/services/prediction_attempt_gate_test.dart; these pin that
  // _regenerate actually calls it at the right point (after predict()
  // resolves, before any write) and that PredictionService really
  // registers with SingletonLifecycleRegistry so an account switch clears
  // the gate.
  test('_regenerate refuses to write when the account changed mid-flight', () {
    final body = _body(_stripped('lib/core/services/prediction_service.dart'),
        'Future<PredictionRefreshOutcome> _regenerate()');
    final ownerCapturedBeforePredict = RegExp(
            r'ownerAtStart\s*=\s*HiveUserSession\.currentOwnerFullId[\s\S]*?await\s+AiService\.instance\.predict\(')
        .hasMatch(body);
    expect(ownerCapturedBeforePredict, isTrue,
        reason: 'the owner must be captured BEFORE the network call, not '
            'after');
    final guardBeforeWrite = RegExp(
            r"await\s+AiService\.instance\.predict\([\s\S]*?if\s*\(\s*!safeToWriteForTest\(\s*ownerAtStart\s*,\s*HiveUserSession\.currentOwnerFullId\s*\)\s*\)[\s\S]*?return\s+PredictionRefreshOutcome\.failed[\s\S]*?MigratedKey\.write\(\s*'prediction_text'")
        .hasMatch(body);
    expect(guardBeforeWrite, isTrue,
        reason: 'the guard must run AFTER predict() resolves and BEFORE '
            'the first Hive write, or a mid-flight account switch can '
            "still leak the old account's prediction into the new one");
  });

  test('PredictionService registers with SingletonLifecycleRegistry to '
      'clear the gate on account change', () {
    final src = _stripped('lib/core/services/prediction_service.dart');
    expect(
        RegExp(r"SingletonLifecycleRegistry\.register\(\s*'PredictionService'\s*,\s*_onUserChanged\s*\)")
            .hasMatch(src),
        isTrue);
    expect(
        RegExp(r'void _onUserChanged\(\)\s*\{\s*_gate\.clearInFlightForAccountChange\(\)\s*;')
            .hasMatch(src),
        isTrue);
  });

  test('the prediction card enables UPDATE through refreshEnabled, stale included', () {
    final body = _body(
        _stripped('lib/features/ai_coach/providers/ai_coach_provider.dart'),
        'PredictionData build()');
    // Read the call's OWN argument list: `isStale: isStale` also appears in
    // the PredictionData(...) below it, which a lazy regex matched when the
    // call passed `isStale: false` (mutation Mh10, 0 red).
    const call = 'canRefresh = PredictionService.refreshEnabled(';
    final start = body.indexOf(call);
    expect(start, isNonNegative, reason: 'canRefresh must come from refreshEnabled');
    final args = body.substring(start + call.length, body.indexOf(')', start));
    expect(RegExp(r'\bisStale:\s*isStale\s*,').hasMatch(args), isTrue,
        reason: 'a stale PRO prediction with a disabled UPDATE button is the '
            'dead end L1-F1 found');
  });
}
