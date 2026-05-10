import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// T3.2 — APK Test #13 (2026-05-12)
///
/// Source-grep contract test for Bug b7e3f1: DayRolloverObserver.runRolloverNow
/// was overwriting the long-lived app-root WidgetRef (set by init() in app.dart)
/// with the short-lived splash WidgetRef. After splash disposed, resume-time
/// _doRollover() calls silently no-op'd on ref.invalidate() and the today-card
/// showed stale yesterday data.
///
/// Fix (closes-diagnose: b7e3f1):
///   runRolloverNow uses `_ref ??= ref` (not `_ref = ref`) so the durable
///   app-root ref survives across the splash → home navigation.
///
/// This test asserts the structural invariants that keep the fix in place:
///   1. runRolloverNow does NOT use `_ref = ref` (the raw overwrite is gone).
///   2. runRolloverNow uses `_ref ??= ref` (null-coalescing assignment only).
///   3. _doRolloverWithRef contains ref.invalidate(todayWorkoutProvider)
///      (canonical today-card provider is in the invalidation set).
///   4. app.dart calls DayRolloverObserver.instance.init(ref)
///      (long-lived ref is established before any screen mounts).
///   5. splash_screen.dart calls DayRolloverObserver.instance.runRolloverNow(ref)
///      (cold-start path still fires for the immediate first-launch invalidation).
///   6. The invalidation set in _doRolloverWithRef includes all required
///      today-bearing providers from the sot_registry.yaml entry.
void main() {
  late String rolloverSrc;
  late String appSrc;
  late String splashSrc;

  setUpAll(() {
    final rolloverFile =
        File('lib/core/services/day_rollover_service.dart');
    final appFile = File('lib/app.dart');
    final splashFile =
        File('lib/features/auth/screens/splash_screen.dart');

    expect(rolloverFile.existsSync(), isTrue,
        reason:
            'lib/core/services/day_rollover_service.dart not found — run from project root');
    expect(appFile.existsSync(), isTrue,
        reason: 'lib/app.dart not found — run from project root');
    expect(splashFile.existsSync(), isTrue,
        reason:
            'lib/features/auth/screens/splash_screen.dart not found — run from project root');

    rolloverSrc = rolloverFile.readAsStringSync();
    appSrc = appFile.readAsStringSync();
    splashSrc = splashFile.readAsStringSync();
  });

  // ── Test 1: raw overwrite `_ref = ref` must NOT exist in runRolloverNow ──

  test(
      'runRolloverNow does NOT clobber _ref with raw assignment (_ref = ref)',
      () {
    // Locate the body of runRolloverNow
    final methodBody = _extractMethodBody(rolloverSrc, 'runRolloverNow');
    expect(methodBody, isNotNull,
        reason: 'runRolloverNow method not found in day_rollover_service.dart');

    // The fix changed `_ref = ref` to `_ref ??= ref`. A raw `_ref = ref`
    // anywhere inside runRolloverNow would re-introduce the bug.
    // We match the raw assignment carefully — `_ref ??= ref` must NOT match.
    final rawAssign = RegExp(r'_ref\s*=\s*ref\s*;');
    expect(rawAssign.hasMatch(methodBody!), isFalse,
        reason:
            'runRolloverNow must not clobber _ref with `_ref = ref`. '
            'Use `_ref ??= ref` so the durable app-root ref from init() '
            'is never replaced by the short-lived splash ref (Bug b7e3f1).');
  });

  // ── Test 2: null-coalescing assignment IS present in runRolloverNow ──

  test('runRolloverNow uses null-coalescing assignment `_ref ??= ref`', () {
    final methodBody = _extractMethodBody(rolloverSrc, 'runRolloverNow');
    expect(methodBody, isNotNull,
        reason: 'runRolloverNow method not found');

    final nullCoalesce = RegExp(r'_ref\s*\?\?=\s*ref\s*;');
    expect(nullCoalesce.hasMatch(methodBody!), isTrue,
        reason:
            'runRolloverNow must use `_ref ??= ref` to preserve the long-lived '
            'app-root ref already set by init() (Bug b7e3f1 fix).');
  });

  // ── Test 3: todayWorkoutProvider is in the invalidation set ──

  test(
      '_doRolloverWithRef invalidates todayWorkoutProvider (canonical today-card provider)',
      () {
    final methodBody =
        _extractMethodBody(rolloverSrc, '_doRolloverWithRef');
    expect(methodBody, isNotNull,
        reason: '_doRolloverWithRef method not found in day_rollover_service.dart');

    expect(methodBody!.contains('ref.invalidate(todayWorkoutProvider)'),
        isTrue,
        reason:
            '_doRolloverWithRef must invalidate todayWorkoutProvider so the '
            'home today-card rebuilds after a date rollover.');
  });

  // ── Test 4: invalidation set completeness ──

  test(
      '_doRolloverWithRef invalidates all required today-bearing providers',
      () {
    final methodBody =
        _extractMethodBody(rolloverSrc, '_doRolloverWithRef');
    expect(methodBody, isNotNull);

    // Minimum set from sot_registry.yaml day_rollover_provider_invalidation entry:
    const required = [
      'todayWorkoutProvider',
      'dailyNutritionProvider',
      'streakProvider',
      'aiInsightProvider',
      'allExercisePRsProvider',
      'calendarWeekProvider',
    ];

    for (final provider in required) {
      expect(
          methodBody!.contains('ref.invalidate($provider)'), isTrue,
          reason:
              '_doRolloverWithRef must invalidate $provider. '
              'Missing this provider means the home screen can render '
              'stale data after a date rollover.');
    }
  });

  // ── Test 5: app.dart calls init() to establish the long-lived ref ──

  test(
      'app.dart calls DayRolloverObserver.instance.init(ref) in initState',
      () {
    expect(
        appSrc.contains('DayRolloverObserver.instance.init(ref)'), isTrue,
        reason:
            'app.dart must call DayRolloverObserver.instance.init(ref) from '
            'initState so the root app WidgetRef is stored before any screen '
            'mounts. Without this, resume-time rollovers have no ref to invalidate on.');
  });

  // ── Test 6: splash_screen.dart still calls runRolloverNow for cold starts ──

  test(
      'splash_screen.dart calls DayRolloverObserver.instance.runRolloverNow for cold-start',
      () {
    expect(
        splashSrc.contains(
            'DayRolloverObserver.instance.runRolloverNow(ref)'),
        isTrue,
        reason:
            'splash_screen.dart must call runRolloverNow(ref) on cold launch so '
            'first-paint providers are fresh even when the date rolled over while '
            'the app was fully killed overnight.');
  });

  // ── Test 7: _doRolloverWithRef is called from runRolloverNow (not _doRollover) ──

  test(
      'runRolloverNow delegates to _doRolloverWithRef (not _doRollover) for cold start',
      () {
    final methodBody = _extractMethodBody(rolloverSrc, 'runRolloverNow');
    expect(methodBody, isNotNull);

    // Cold-start path must use _doRolloverWithRef so it uses the PASSED ref
    // (which is valid for the duration of the call), not _ref (which might
    // be the app-root ref that behaves differently in the splash widget tree).
    expect(methodBody!.contains('_doRolloverWithRef(ref,'), isTrue,
        reason:
            'runRolloverNow must call _doRolloverWithRef(ref, today) '
            'passing the explicit ref, NOT _doRollover(today) which reads '
            'from _ref. This ensures cold-start invalidations use a live ref.');

    // Conversely, runRolloverNow must NOT call _doRollover (which reads _ref).
    expect(
        RegExp(r'\b_doRollover\s*\(').hasMatch(methodBody), isFalse,
        reason:
            'runRolloverNow must not call _doRollover() — that method reads '
            '_ref which may differ from the passed ref.');
  });

  // ── Test 8: _doRollover (resume path) calls _doRolloverWithRef with _ref ──

  test(
      '_doRollover (resume path) delegates to _doRolloverWithRef with stored _ref',
      () {
    final methodBody = _extractMethodBody(rolloverSrc, '_doRollover');
    expect(methodBody, isNotNull);

    // Resume path reads _ref (the durable app-root ref stored by init()).
    // After the fix, _doRollover is a thin wrapper that extracts _ref and
    // delegates to _doRolloverWithRef.
    expect(methodBody!.contains('_doRolloverWithRef(ref, today)'), isTrue,
        reason:
            '_doRollover must delegate to _doRolloverWithRef(ref, today) '
            'where ref = _ref. This keeps invalidation logic in one place.');
  });
}

// ── Helper: extract the body of the first METHOD DEFINITION matching [name] ──

/// Locates the METHOD DEFINITION of [methodName] in [src] (not a call site).
/// A method definition is identified by a return type token immediately before
/// the method name on the same line (e.g., `Future<void> _doRolloverWithRef(`).
///
/// Extracts everything between the opening `{` and the matching closing `}`.
/// Returns null if the definition is not found.
String? _extractMethodBody(String src, String methodName) {
  // Match a method definition: return-type keyword + optional whitespace/generic
  // then the method name, then `(`. This rules out call sites where the name
  // is preceded by `await`, `.`, or similar.
  //
  // Pattern: any non-`(` token followed by whitespace then methodName then `(`
  // Anchored to line boundaries helps avoid matching call expressions.
  final definitionPattern = RegExp(
    r'(?:^|[\n\r])\s+(?:Future<[^>]+>|void|String\?|String|bool|int|Map[^)]*|List[^)]*)\s+'
    + RegExp.escape(methodName)
    + r'\s*\(',
    multiLine: true,
  );

  final sigMatch = definitionPattern.firstMatch(src);
  if (sigMatch == null) return null;

  // Find the opening `{` after the signature (skip parameter list).
  // Walk past the `(` to find the matching `)` then look for `{`.
  final parenOpen = src.indexOf('(', sigMatch.start + sigMatch.group(0)!.indexOf(methodName));
  if (parenOpen == -1) return null;

  // Skip past the closing `)` of the parameter list.
  int parenDepth = 1;
  int j = parenOpen + 1;
  while (j < src.length && parenDepth > 0) {
    if (src[j] == '(') parenDepth++;
    if (src[j] == ')') parenDepth--;
    j++;
  }

  // Find the opening `{` of the body.
  final openBrace = src.indexOf('{', j);
  if (openBrace == -1) return null;

  // Walk forward matching braces to find the closing `}`.
  int depth = 1;
  int i = openBrace + 1;
  while (i < src.length && depth > 0) {
    final ch = src[i];
    if (ch == '{') depth++;
    if (ch == '}') depth--;
    i++;
  }

  return src.substring(openBrace, i);
}
