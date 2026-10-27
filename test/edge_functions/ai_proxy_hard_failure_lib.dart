/// True when the Edge Function's own JSON says `data`'s reply is NOT real
/// model output -- the hardcoded hard-failure apology
/// (`supabase/functions/_shared/tool-loop.ts`'s
/// `HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED`, surfaced as `had_hard_failure`
/// at `supabase/functions/ai-proxy/index.ts:1179`) rather than a genuine
/// Gemini answer. A live chat that hits this never reached the model, so a
/// content assertion ("does the reply mention the user's goal") is
/// unanswerable and must be skipped -- exactly as the 429/capped branch in
/// `ai_proxy_test.dart`'s `chatBodyOrAssertCapped` is skipped.
///
/// Only the literal bool `true` counts: a missing key, `false`, or any other
/// value (including a stray JSON string `"true"`) means the reply is (or is
/// claimed to be) real model output, so the caller's content assertion still
/// applies.
bool isHardFailureReply(Map<String, dynamic> data) =>
    data['had_hard_failure'] == true;
