// APK +43 obs 2 — the client must be able to tell a genuine Gemini quota
// exhaustion apology apart from real model output, so it can exclude that
// turn from the next request's replayed coach history (see
// coach_chat_history_replay_writer_to_reader_test.dart for the Hive-side
// writer/reader pin, and tool-loop_hard_failure_flag_test.ts for the
// server-side origin of the flag).
//
// This file pins the PARSE step: `had_hard_failure` (server JSON) →
// AiChatResponse.hadHardFailure (client model). Pure/static — no Hive,
// network, or Riverpod required.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

void main() {
  test('had_hard_failure: true parses to AiChatResponse.hadHardFailure', () {
    final response = AiService.buildResponseForTest({
      'reply': 'I had trouble reaching the model. Try again in a moment.',
      'model_used': 'Gemini 2.5 Flash Lite',
      'tokens_used': 42,
      'had_hard_failure': true,
    });
    expect(response.hadHardFailure, isTrue);
  });

  test('had_hard_failure: false parses to false', () {
    final response = AiService.buildResponseForTest({
      'reply': 'Push day — bench, incline dumbbell, dips.',
      'model_used': 'Gemini 2.5 Flash',
      'tokens_used': 120,
      'had_hard_failure': false,
    });
    expect(response.hadHardFailure, isFalse);
  });

  test('missing had_hard_failure (e.g. ai-media-proxy responses) defaults to false', () {
    final response = AiService.buildResponseForTest({
      'reply': 'That looks like grilled chicken and rice.',
      'model_used': 'Gemini 2.5 Flash Lite',
      'tokens_used': 88,
    });
    expect(response.hadHardFailure, isFalse);
  });
}
