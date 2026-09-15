---
bug_id: d8e5b3
date: 2026-05-12
batch: APK Test #15.1
status: in_progress
symptom: Photo upload to AI coach → "Sorry, I couldn't analyse that photo. Please try again." Zero client_errors rows for ai-media-proxy in last 12h — generic fallback fires silently without telemetry.
concept: ai_media_proxy_error_handling
sot_registry_entry: ai_coach_chat_history
writers:
  - { file: supabase/functions/ai-media-proxy/index.ts, method_or_widget: handler, line: 1 }
readers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: chatWithMediaProvider.send catch block, line: 427 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [content]
contract_test_path: test/contracts/ai_media_proxy_telemetry_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [ai_media_proxy_unknown_error]
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: |
  In the generic fallback else-branch (ai_coach_provider.dart:442-444
  pre-fix), after setting the user-facing errorMsg, log the original
  exception string to client_errors via ErrorTelemetry.logEvent with
  op_type 'ai_media_proxy_unknown_error'. Clip to 500 chars before
  write (some exceptions carry full stack traces). Next user report
  surfaces with actionable telemetry attached.
regression_test_planned:
  - test/contracts/ai_media_proxy_telemetry_test.dart
---

# Bug D — ai-media-proxy generic fallback telemetry blackout

## Symptom

Founder uploaded a photo to AI coach. Got back: "Sorry, I couldn't analyse that photo. Please try again."

Telemetry sweep on `client_errors` for the founder's user_id, op_type ILIKE `%media%` OR `%ai%` — **zero rows in last 12h**. The audit-batch H-42 telemetry retrofit cohort 4 (commit `cd9372c`) added try/catch + telemetry across AI/ML code paths but missed this specific else-branch.

## Root cause

`ai_coach_provider.dart` catch block (lines 427-444 pre-fix) checks for a series of specific error patterns and maps each to a user-facing message:
- SocketException → "No internet connection"
- Image too large → "5 MB max"
- "Only Supabase Storage URLs" → "Upload failed"
- Message too long → "max 5000 chars"
- PRO subscription required → upgrade prompt
- 502/503/504 → "vision model temporarily unavailable"

If NONE match, falls through to the generic: `'Sorry, I couldn't analyse...'`. No `logEvent` call in that branch — the actual exception is dropped. Founder reports the user-facing message; we have no signal for what the underlying ai-media-proxy reject reason was.

## Fix

Single edit in the else-branch:

```dart
} else {
  errorMsg = 'Sorry, I couldn\'t analyse that photo. Please try again.';
  final clipped = errStr2.length > 500 ? errStr2.substring(0, 500) : errStr2;
  unawaited(ErrorTelemetry.logEvent('ai_media_proxy_unknown_error',
      message: clipped));
}
```

Imported `ErrorTelemetry` from `core/services/error_telemetry.dart`. Next user report leaves an `ai_media_proxy_unknown_error` row in `client_errors` with the actual exception text, so the next diagnosis cycle is data-driven instead of speculative.

## Verification

- 3 source-grep tests pass: import present, op_type literal present, clip-to-500 logic present.
- Server-side: next failed photo upload will produce `client_errors` row that ops can correlate with the Edge Function logs at the same timestamp.

## Related

- Audit-batch H-42 telemetry retrofit (commits `43d8c65` → `c0b9999`) — added telemetry to many failure paths but missed this else-branch.
- `feedback_no_deferrals.md` — Bug D ships in same batch.

## Skills evolution

This is the second time in 4 weeks we've shipped a generic catch-all error message without telemetry (Test #12.4 had the same class — `_showOrderCreationFailure`). Adding a new build-apk gate (skills-evolution batch in this same APK Test #15.1) — `scripts/check_generic_error_messages_have_telemetry.dart` — that source-greps for "Sorry," / "Something went wrong" / generic copy strings in `lib/` and asserts each is preceded within 10 lines by an `ErrorTelemetry.logEvent` or `_reportSyncFailure` call.
