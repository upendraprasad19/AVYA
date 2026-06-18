// test/contracts/ai_proxy_placeholder_resolution_behavioral_test.dart
//
// Behavioral contract: ai_proxy_placeholder_resolution
// Writer: supabase/functions/ai-proxy/index.ts (Deno Edge Function)
//         Inserts a placeholder row into ai_coach_interactions BEFORE the
//         Gemini API call (rate-limit trigger SoT). The placeholder dedup
//         logic prevents duplicate chat bubbles on weak-network retries.
// Reader: lib/core/services/sync/sync_coach.dart + ai_coach_provider.dart
//         (dedup checks placeholder before issuing a new request)
//
// STATUS: BLOCKED — presence_only in sot_registry.yaml
//
// This contract is implemented entirely inside the Deno Edge Function
// (ai-proxy/index.ts). The Flutter client is a consumer, not the writer.
// There is no stubbable seam in the Flutter test environment that lets
// us trigger the real placeholder-insert path and observe its effect
// on the client-side dedup logic without a live Supabase project.
//
// What can be tested:
//   - The client-side dedup WINDOW (60s) is a constant — source-grep only.
//   - The coachBox row written by _restoreCoachInteractions is the reader
//     path (already covered by coach_interactions_behavioral_test.dart).
//
// To convert this to a full behavioral test:
//   - Extract an injectable `AiProxyClient` interface so tests can supply
//     a fake that emits a placeholder row to an in-memory Supabase stub.
//   - Or use integration_test/ with a live dev project.
//
// Until then, the behavioral_test_required flag in sot_registry.yaml stays
// set to true and Gate 42 emits a WARN for this entry.

// ignore_for_file: unused_import
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ai_proxy_placeholder_resolution — BLOCKED (Deno EF, no Flutter seam)',
      () {
    // This test is intentionally a no-op placeholder.
    // The contract lives in supabase/functions/ai-proxy/index.ts.
    // See file header for upgrade path.
    //
    // Do NOT add assertions here that give false confidence about the
    // server-side placeholder behaviour. Source-grep tests for the dedup
    // window constant are in:
    //   test/contracts/coach_interactions_writer_to_reader_test.dart
    //   (coachWriterDedupWindow == 60s constant presence check)
  }, skip: 'BLOCKED: server-side EF contract — no Flutter unit-test seam available');
}
