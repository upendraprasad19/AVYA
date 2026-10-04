// test/scripts/gemini_retry_coverage_lib_test.dart
//
// Unit tests for scripts/gemini_retry_coverage_lib.dart
// (check_gemini_retry_and_telemetry_coverage.dart's detection logic).
// A5/OI-226, f7a2c9, 2026-09-21.
//
// Mutation-proof evidence lives in docs/audit/gate_test_ledger.yaml under
// check_gemini_retry_and_telemetry_coverage.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/gemini_retry_coverage_lib.dart';

void main() {
  group('extractBalancedBraces', () {
    test('extracts a simple balanced block', () {
      const src = 'geminiChat({a: 1, b: 2});';
      final block = extractBalancedBraces(src, src.indexOf('{'));
      expect(block, '{a: 1, b: 2}');
    });

    test('handles nested braces', () {
      const src = 'foo({a: {nested: true}, b: 2});';
      final block = extractBalancedBraces(src, src.indexOf('{'));
      expect(block, '{a: {nested: true}, b: 2}');
    });

    test('returns null on unbalanced input', () {
      const src = 'foo({a: 1';
      final block = extractBalancedBraces(src, src.indexOf('{'));
      expect(block, isNull);
    });

    test('returns null when index does not point at a brace', () {
      const src = 'foo(a: 1)';
      final block = extractBalancedBraces(src, 0);
      expect(block, isNull);
    });
  });

  group('lineOf', () {
    test('counts newlines before the index, 1-indexed', () {
      const src = 'line1\nline2\nline3';
      expect(lineOf(src, 0), 1);
      expect(lineOf(src, 6), 2);
      expect(lineOf(src, 12), 3);
    });
  });

  group('findGeminiChatMissingRetries (part a)', () {
    test('GOOD — geminiChat( call with retries: passes clean', () {
      final files = {
        'fn/index.ts': '''
          const { content } = await geminiChat({
            model: MODEL_FLASH,
            retries: 2,
          });
        ''',
      };
      final violations = findGeminiChatMissingRetries(files);
      expect(violations, isEmpty);
    });

    test('BAD — geminiChat( call missing retries: is a violation', () {
      final files = {
        'fn/index.ts': '''
          const { content } = await geminiChat({
            model: MODEL_FLASH,
          });
        ''',
      };
      final violations = findGeminiChatMissingRetries(files);
      expect(violations, isNotEmpty);
      expect(violations.single, contains('fn/index.ts'));
      expect(violations.single, contains('missing a retries:'));
    });

    test('geminiChatWithTools( is excluded (different function, no '
        'retries parameter)', () {
      final files = {
        'fn/index.ts': '''
          const resp = await geminiChatWithTools({
            model: MODEL_FLASH,
            messages,
          });
        ''',
      };
      final violations = findGeminiChatMissingRetries(files);
      expect(violations, isEmpty,
          reason: 'geminiChatWithTools has its own TOOLS_MAX_PASSES '
              'resilience and no retries parameter at all — must never be '
              'flagged by this gate.');
    });

    test('multiple call sites in one file are each checked independently',
        () {
      final files = {
        'fn/index.ts': '''
          async function a() {
            await geminiChat({ model: X, retries: 2 });
          }
          async function b() {
            await geminiChat({ model: Y });
          }
        ''',
      };
      final violations = findGeminiChatMissingRetries(files);
      expect(violations, hasLength(1),
          reason: 'exactly the second (missing retries:) call site should '
              'be flagged — the width-of-input-set discipline: a whole-file '
              'count must not mask which specific site is missing it.');
    });

    test('multiple files are each scanned', () {
      final files = {
        'fn/a.ts': 'geminiChat({ retries: 2 });',
        'fn/b.ts': 'geminiChat({ model: X });',
      };
      final violations = findGeminiChatMissingRetries(files);
      expect(violations, hasLength(1));
      expect(violations.single, contains('fn/b.ts'));
    });

    test('BAD — a COMMENT mentioning retries: does not satisfy the check '
        'when the real argument is absent (green-check-input-set-width; '
        'the self-triggered B-pass review on this gate\'s own launch batch '
        'found the first version comment-blind)', () {
      final files = {
        'fn/index.ts': '''
          const { content } = await geminiChat({
            model: MODEL_FLASH,
            // retries: 2 — removed intentionally, see OI-999
          });
        ''',
      };
      final violations = findGeminiChatMissingRetries(files);
      expect(violations, isNotEmpty,
          reason: 'a comment saying "retries: 2" is not a retries: argument '
              '— stripComments() must blind the check to it.');
      expect(violations.single, contains('missing a retries:'));
    });
  });

  group('findAiEntryPointsMissingTelemetry (part b)', () {
    // Several registry entries share ONE file (nutrition_provider.dart has
    // 3), so a fixture map keyed one-entry-per-file-key would silently drop
    // all but the last entry sharing a key — this groups by file and
    // concatenates each entry's own body into one combined fixture,
    // avoiding exactly that map-literal collision.
    Map<String, String> buildFixtures(
        String Function(AiEntryPoint) bodyFor) {
      final byFile = <String, StringBuffer>{};
      for (final ep in aiNetworkEntryPoints) {
        byFile.putIfAbsent(ep.file, () => StringBuffer()).writeln(bodyFor(ep));
      }
      return {for (final e in byFile.entries) e.key: e.value.toString()};
    }

    test('GOOD — a registered entry point whose catch has telemetry passes',
        () {
      final files = buildFixtures((ep) => '${ep.methodAnchor}) async {\n'
          '  try {\n'
          '    doSomething();\n'
          '  } catch (e) {\n'
          '    ErrorTelemetry.logEvent("x");\n'
          '  }\n'
          '}\n');
      final violations = findAiEntryPointsMissingTelemetry(files);
      expect(violations, isEmpty);
    });

    test('BAD — a registered entry point whose catch has NO telemetry is a '
        'violation', () {
      final files = buildFixtures((ep) => '${ep.methodAnchor}) async {\n'
          '  try {\n'
          '    doSomething();\n'
          '  } catch (e) {\n'
          '    state = state.copyWith(error: "failed");\n'
          '  }\n'
          '}\n');
      final violations = findAiEntryPointsMissingTelemetry(files);
      expect(violations, hasLength(aiNetworkEntryPoints.length),
          reason: 'every registered entry point in this fixture set is '
              'missing telemetry, so every one must be individually '
              'flagged — not collapsed into one aggregate finding.');
    });

    test('an EARLIER, deliberately-silent inner catch does not mask a '
        'LATER, real outer catch with telemetry (the send()/analyse() '
        'shape found while building this gate)', () {
      final files = buildFixtures((ep) => '${ep.methodAnchor}) async {\n'
          '  try {\n'
          '    await optionalRefresh();\n'
          '  } catch (_) {\n'
          '    // deliberately silent, non-fatal\n'
          '  }\n'
          '  try {\n'
          '    doTheRealWork();\n'
          '  } catch (e) {\n'
          '    ErrorTelemetry.logEvent("real_failure");\n'
          '  }\n'
          '}\n');
      final violations = findAiEntryPointsMissingTelemetry(files);
      expect(violations, isEmpty,
          reason: 'picking "the first catch after the anchor" would land '
              'on the silent inner one and false-positive here — this is '
              'the exact bug this gate\'s own design hit against the real '
              'send()/analyse() methods before shipping.');
    });

    test('a registered file that does not exist in the input map is a '
        'violation (registry/reality drift)', () {
      final violations = findAiEntryPointsMissingTelemetry(const {});
      expect(violations, hasLength(aiNetworkEntryPoints.length));
      for (final v in violations) {
        expect(v, contains('file not found'));
      }
    });

    test('a registered method anchor that no longer matches the file is a '
        'violation (renamed without updating the registry)', () {
      final files = {
        for (final path in aiNetworkEntryPoints.map((e) => e.file).toSet())
          path: 'this file has been completely rewritten',
      };
      final violations = findAiEntryPointsMissingTelemetry(files);
      expect(violations, hasLength(aiNetworkEntryPoints.length));
      for (final v in violations) {
        expect(v, contains('anchor'));
      }
    });

    test('a registered method with no catch at all within the search '
        'window is a violation', () {
      final files = buildFixtures((ep) => '${ep.methodAnchor}) async {\n'
          '  doSomethingWithNoErrorHandling();\n'
          '}\n');
      final violations = findAiEntryPointsMissingTelemetry(files);
      expect(violations, hasLength(aiNetworkEntryPoints.length));
      for (final v in violations) {
        expect(v, contains('no catch block'));
      }
    });

    test('BAD — a COMMENT mentioning ErrorTelemetry does not satisfy the '
        'check when no real call is present (green-check-input-set-width; '
        'the self-triggered B-pass review on this gate\'s own launch batch '
        'found the first version comment-blind)', () {
      final files = buildFixtures((ep) => '${ep.methodAnchor}) async {\n'
          '  try {\n'
          '    doSomething();\n'
          '  } catch (e) {\n'
          '    // ErrorTelemetry.recordNonFatal(reason: \'x\') was here, '
          'removed\n'
          '    state = state.copyWith(error: "failed");\n'
          '  }\n'
          '}\n');
      final violations = findAiEntryPointsMissingTelemetry(files);
      expect(violations, hasLength(aiNetworkEntryPoints.length),
          reason: 'a comment naming ErrorTelemetry is not a call to it — '
              'stripComments() must blind the check to it.');
      for (final v in violations) {
        expect(v, contains('none contain an ErrorTelemetry call'));
      }
    });
  });

  group('the registry itself, against the REAL repo files', () {
    // Not a fixture test — reads the actual registered files to prove the
    // registry's anchors and telemetry are real today, not just internally
    // consistent with the pure-logic tests above.
    test('every registered AI entry point is currently clean', () {
      final files = <String, String>{};
      for (final ep in aiNetworkEntryPoints) {
        final f = File(ep.file);
        if (f.existsSync()) files[ep.file] = f.readAsStringSync();
      }
      final violations = findAiEntryPointsMissingTelemetry(files);
      expect(violations, isEmpty,
          reason: 'if this fails, either a real telemetry regression '
              'landed, or a registered file/anchor drifted — both are '
              'real, actionable gate failures, not a test-fixture problem.');
    });
  });
}
