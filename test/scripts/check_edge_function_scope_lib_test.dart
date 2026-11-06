// test/scripts/check_edge_function_scope_lib_test.dart
//
// Unit tests for the pure predicate behind scripts/check_edge_function_scope.dart
// (Fitness App's Rule-3 equivalent, CLAUDE.md §4.4 rule 9). Mutation-proven
// (rule 24).

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/check_edge_function_scope.dart';

void main() {
  group('aiProviderEndpoint', () {
    test('matches the Gemini API domain', () {
      expect(
        aiProviderEndpoint.hasMatch("Uri.parse('https://generativelanguage.googleapis.com/v1')"),
        isTrue,
      );
    });

    test('matches the OpenAI API domain', () {
      expect(aiProviderEndpoint.hasMatch("'https://api.openai.com/v1/chat'"), isTrue);
    });

    test('matches the Cerebras API domain', () {
      expect(aiProviderEndpoint.hasMatch("'https://api.cerebras.ai/v1'"), isTrue);
    });

    test('does not match an unrelated domain', () {
      expect(aiProviderEndpoint.hasMatch("'https://dedsavbjuwgarrhphgnl.supabase.co'"), isFalse);
    });
  });

  group('aiSecretKeyName', () {
    test('matches GEMINI_API_KEY', () {
      expect(aiSecretKeyName.hasMatch('final k = GEMINI_API_KEY;'), isTrue);
    });

    test('matches numbered CEREBRAS_API_KEY_1/2/3', () {
      expect(aiSecretKeyName.hasMatch('CEREBRAS_API_KEY_1'), isTrue);
      expect(aiSecretKeyName.hasMatch('CEREBRAS_API_KEY_2'), isTrue);
    });

    test('matches RAZORPAY_KEY_SECRET but NOT the client-legitimate RAZORPAY_KEY_ID', () {
      expect(aiSecretKeyName.hasMatch('RAZORPAY_KEY_SECRET'), isTrue);
      expect(aiSecretKeyName.hasMatch('RAZORPAY_KEY_ID'), isFalse);
    });

    test('does not match an unrelated identifier containing a substring', () {
      expect(aiSecretKeyName.hasMatch('final myGeminiApiKeyLabel = "x";'), isFalse);
    });
  });

  group('findViolations', () {
    test('flags a direct AI endpoint call', () {
      final files = {
        'lib/features/ai_coach/services/rogue.dart':
            "final uri = Uri.parse('https://generativelanguage.googleapis.com/v1');",
      };
      final violations = findViolations(files);
      expect(violations, hasLength(1));
      expect(violations.first.kind, 'endpoint');
    });

    test('flags a secret-key-name reference', () {
      final files = {
        'lib/features/ai_coach/services/rogue.dart': 'final k = GEMINI_API_KEY;',
      };
      final violations = findViolations(files);
      expect(violations, hasLength(1));
      expect(violations.first.kind, 'secret-key-name');
    });

    test('flags BOTH kinds on the same line as two separate violations', () {
      final files = {
        'lib/x.dart':
            "http.post(Uri.parse('https://api.openai.com'), headers: {'key': OPENAI_API_KEY});",
      };
      final violations = findViolations(files);
      expect(violations, hasLength(2));
      expect(violations.map((v) => v.kind).toSet(), {'endpoint', 'secret-key-name'});
    });

    test('has NO allowlist -- even lib/core/services/ is flagged (unlike Rule 2)', () {
      final files = {
        'lib/core/services/supabase_service.dart': 'final k = GEMINI_API_KEY;',
      };
      expect(findViolations(files), hasLength(1));
    });

    test('does not flag the legitimate functions.invoke( pattern', () {
      final files = {
        'lib/core/services/sync_service.dart':
            "await supabase.functions.invoke('ai-proxy', body: payload);",
      };
      expect(findViolations(files), isEmpty);
    });

    test('does not flag a commented-out example', () {
      final files = {
        'lib/x.dart': '// old: used to call generativelanguage.googleapis.com directly',
      };
      expect(findViolations(files), isEmpty);
    });

    test('reports the correct 1-indexed line number', () {
      final files = {
        'lib/x.dart': 'line one\nline two\nfinal k = GEMINI_API_KEY;\nline four',
      };
      expect(findViolations(files).single.line, 3);
    });
  });
}
