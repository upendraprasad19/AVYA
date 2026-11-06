// Behavioural — a prediction failure keeps its HTTP status all the way to the
// refresh outcome (B-pass c5d659f52986 Finding 1, diagnose 125b81).
//
// `functions.invoke` THROWS on every non-2xx, so `AiService.predict()`'s
// status check never saw the new 429 (the 3/day cap): the generic catch
// dropped the status, `regeneratePrediction()` returned a bare `false`, and
// the Profile tab told a capped user to "try again later". These tests drive
// the two pure pieces the fix introduced — `AiService.predictionFailure` and
// `PredictionService.outcomeForError` — with the exception types
// functions_client 2.7.1 actually throws. The wiring into `predict()` and the
// callers is pinned in test/contracts/prediction_refresh_outcome_wiring_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/prediction_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AiService.predictionFailure', () {
    test('a 429 keeps its status and the server\'s own error text', () {
      final e = AiService.predictionFailure(const FunctionsHttpException(
        status: 429,
        details: {
          'error': 'Daily prediction limit reached (3/day)',
          'code': 'RATE_LIMITED',
        },
      ));
      expect(e.statusCode, 429);
      expect(e.message, 'Daily prediction limit reached (3/day)');
      expect(e.code, 'RATE_LIMITED');
    });

    test('the code is read from a JSON string body too, and absent means null', () {
      expect(
          AiService.predictionFailure(const FunctionsHttpException(
            status: 429,
            details: '{"error":"x","code":"RATE_LIMITED"}',
          )).code,
          'RATE_LIMITED');
      expect(
          AiService.predictionFailure(const FunctionsHttpException(
            status: 429,
            details: '<html>Too Many Requests</html>',
          )).code,
          isNull);
    });

    test('a 500 keeps its status and text', () {
      final e = AiService.predictionFailure(const FunctionsHttpException(
        status: 500,
        details: {'error': 'AI temporarily unavailable'},
      ));
      expect(e.statusCode, 500);
      expect(e.message, 'AI temporarily unavailable');
    });

    test('a request that never reached the server is status 0, with a fallback message', () {
      final e = AiService.predictionFailure(
          const FunctionsFetchException(details: 'SocketException'));
      expect(e.statusCode, 0);
      expect(e.message, 'Prediction failed with status 0');
    });
  });

  group('PredictionService.outcomeForError', () {
    test('429 + RATE_LIMITED → dailyLimitReached', () {
      expect(
        PredictionService.outcomeForError(const AiServiceException('x',
            statusCode: 429, code: 'RATE_LIMITED')),
        PredictionRefreshOutcome.dailyLimitReached,
      );
    });

    // Hermes 2026-09-26, L37-F3: a 429 that is not the prediction cap's own
    // refusal (a gateway or platform limit) is a fault — "try again tomorrow"
    // would be wrong and telemetry would never see it.
    test('a 429 without RATE_LIMITED → failed', () {
      for (final e in const [
        AiServiceException('x', statusCode: 429),
        AiServiceException('x', statusCode: 429, code: 'SOMETHING_ELSE'),
      ]) {
        expect(PredictionService.outcomeForError(e),
            PredictionRefreshOutcome.failed,
            reason: '$e code=${e.code}');
      }
    });

    test('every other failure → failed (500, 0, no status, a non-AI error)', () {
      for (final e in <Object>[
        const AiServiceException('x', statusCode: 500),
        const AiServiceException('x', statusCode: 0),
        const AiServiceException('x'),
        Exception('boom'),
      ]) {
        expect(PredictionService.outcomeForError(e),
            PredictionRefreshOutcome.failed,
            reason: '$e');
      }
    });

    test('end to end: the handler\'s 429 body reaches the caller as dailyLimitReached', () {
      final thrown = AiService.predictionFailure(const FunctionsHttpException(
        status: 429,
        details: {
          'error': 'Daily prediction limit reached (3/day)',
          'code': 'RATE_LIMITED',
        },
      ));
      expect(PredictionService.outcomeForError(thrown),
          PredictionRefreshOutcome.dailyLimitReached);
    });

    test('end to end: a gateway 429 with no code reaches the caller as failed', () {
      final thrown = AiService.predictionFailure(const FunctionsHttpException(
        status: 429,
        details: 'Too Many Requests',
      ));
      expect(PredictionService.outcomeForError(thrown),
          PredictionRefreshOutcome.failed);
    });
  });
}
